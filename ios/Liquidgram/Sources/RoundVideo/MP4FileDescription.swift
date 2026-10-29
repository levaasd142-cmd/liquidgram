import Foundation

/// Reads what an MP4 file holds from its boxes (ISO/IEC 14496-12 and -15): the order of the top-level boxes, the movie
/// duration, and per track the codec, the size or the sound format, the number of samples, and for H.264 the profile,
/// the level and whether the picture parameter set uses CABAC
enum MP4FileDescription {
  /// Box types whose payload is a list of boxes
  private static let containerTypes: Set<String> = ["moov", "trak", "mdia", "minf", "stbl"]
  /// The fields of a visual sample entry before its child boxes
  private static let visualSampleEntryLength = 78
  /// The fields of an audio sample entry before its child boxes
  private static let audioSampleEntryLength = 28
  private static let decoderConfigTag: UInt8 = 0x04
  private static let decoderSpecificInfoTag: UInt8 = 0x05

  static func read(_ url: URL) -> [String: Any] {
    guard let data = try? Data(contentsOf: url) else {
      return ["error": "unreadable"]
    }
    let bytes = [UInt8](data)
    var description: [String: Any] = ["size": bytes.count]
    let topLevel = findBoxes(in: bytes, range: 0..<bytes.count)
    description["topLevelBoxes"] = topLevel.map(\.type)
    if let moovIndex = topLevel.firstIndex(where: { $0.type == "moov" }),
       let mdatIndex = topLevel.firstIndex(where: { $0.type == "mdat" }) {
      description["fastStart"] = moovIndex < mdatIndex
    }
    guard let moov = topLevel.first(where: { $0.type == "moov" }) else {
      return description
    }
    let movie = findBoxes(in: bytes, range: moov.payload)
    if let mvhd = movie.first(where: { $0.type == "mvhd" }), let duration = readDuration(bytes, mvhd.payload) {
      description["durationMs"] = duration
    }
    var tracks: [[String: Any]] = []
    for trak in movie where trak.type == "trak" {
      tracks.append(describeTrack(bytes, trak))
    }
    description["tracks"] = tracks
    return description
  }

  private static func describeTrack(_ bytes: [UInt8], _ trak: Box) -> [String: Any] {
    var track: [String: Any] = [:]
    guard let mdia = findChild(bytes, trak, "mdia") else {
      return track
    }
    if let mdhd = findChild(bytes, mdia, "mdhd"), let duration = readDuration(bytes, mdhd.payload) {
      track["durationMs"] = duration
    }
    if let hdlr = findChild(bytes, mdia, "hdlr"), hdlr.payload.count >= 12 {
      track["handler"] = readType(bytes, hdlr.payload.lowerBound + 8)
    }
    guard let stbl = findChild(bytes, mdia, "minf").flatMap({ findChild(bytes, $0, "stbl") }) else {
      return track
    }
    if let stsz = findChild(bytes, stbl, "stsz"), stsz.payload.count >= 12 {
      track["samples"] = readUInt32(bytes, stsz.payload.lowerBound + 8)
    }
    // `stsd`: version and flags, the entry count, then the sample entries as boxes
    guard let stsd = findChild(bytes, stbl, "stsd"), stsd.payload.count > 8,
          let entry = findBoxes(in: bytes, range: (stsd.payload.lowerBound + 8)..<stsd.payload.upperBound).first else {
      return track
    }
    track["codec"] = entry.type
    switch entry.type {
    case "avc1":
      describeVideoEntry(bytes, entry, into: &track)
    case "mp4a":
      describeAudioEntry(bytes, entry, into: &track)
    default:
      break
    }
    return track
  }

  private static func describeVideoEntry(_ bytes: [UInt8], _ entry: Box, into track: inout [String: Any]) {
    let start = entry.payload.lowerBound
    guard entry.payload.count >= visualSampleEntryLength else {
      return
    }
    track["width"] = readUInt16(bytes, start + 24)
    track["height"] = readUInt16(bytes, start + 26)
    let children = findBoxes(in: bytes, range: (start + visualSampleEntryLength)..<entry.payload.upperBound)
    guard let avcC = children.first(where: { $0.type == "avcC" }), avcC.payload.count >= 7 else {
      return
    }
    // `AVCDecoderConfigurationRecord`: version, profile, compatibility, level, NAL length size, then the SPS and PPS
    let record = avcC.payload.lowerBound
    track["profile"] = Int(bytes[record + 1])
    track["level"] = Int(bytes[record + 3])
    var offset = record + 5
    let spsCount = Int(bytes[offset] & 0x1F)
    offset += 1
    for _ in 0..<spsCount {
      guard offset + 2 <= avcC.payload.upperBound else {
        return
      }
      offset += 2 + readUInt16(bytes, offset)
    }
    guard offset + 3 <= avcC.payload.upperBound, bytes[offset] > 0 else {
      return
    }
    let ppsLength = readUInt16(bytes, offset + 1)
    let ppsStart = offset + 3
    guard ppsStart + ppsLength <= avcC.payload.upperBound, ppsLength > 1 else {
      return
    }
    track["cabac"] = readEntropyCodingModeFlag(Array(bytes[(ppsStart + 1)..<(ppsStart + ppsLength)]))
  }

  private static func describeAudioEntry(_ bytes: [UInt8], _ entry: Box, into track: inout [String: Any]) {
    let start = entry.payload.lowerBound
    guard entry.payload.count >= audioSampleEntryLength else {
      return
    }
    track["channels"] = readUInt16(bytes, start + 16)
    // A 16.16 fixed-point number
    track["sampleRate"] = readUInt16(bytes, start + 24)
    let children = findBoxes(in: bytes, range: (start + audioSampleEntryLength)..<entry.payload.upperBound)
    guard let esds = children.first(where: { $0.type == "esds" }) else {
      return
    }
    let descriptors = Array(bytes[esds.payload])
    if let config = findDescriptor(descriptors, tag: decoderConfigTag), config.count >= 13 {
      track["objectTypeIndication"] = Int(config[0])
      track["averageBitRate"] = Int(config[9]) << 24 | Int(config[10]) << 16 | Int(config[11]) << 8 | Int(config[12])
    }
    if let audioSpecificConfig = findDescriptor(descriptors, tag: decoderSpecificInfoTag),
       audioSpecificConfig.count >= 2 {
      // `AudioSpecificConfig`: 5 bits of object type (2 is AAC LC), 4 of the sampling frequency index (3 is 48 kHz),
      // 4 of the channel configuration (1 is mono)
      track["audioObjectType"] = Int(audioSpecificConfig[0] >> 3)
      track["samplingFrequencyIndex"] = Int((audioSpecificConfig[0] & 0x07) << 1 | audioSpecificConfig[1] >> 7)
      track["channelConfiguration"] = Int((audioSpecificConfig[1] >> 3) & 0x0F)
    }
  }

  /// The payload of the first descriptor with `tag` inside an `esds` box. The `ES_Descriptor` is skipped into, since
  /// the other descriptors are nested in it.
  private static func findDescriptor(_ bytes: [UInt8], tag: UInt8) -> [UInt8]? {
    // Version and flags of the full box
    var offset = 4
    while offset < bytes.count {
      let descriptorTag = bytes[offset]
      offset += 1
      var length = 0
      for _ in 0..<4 {
        guard offset < bytes.count else {
          return nil
        }
        let byte = bytes[offset]
        offset += 1
        length = length << 7 | Int(byte & 0x7F)
        if byte & 0x80 == 0 {
          break
        }
      }
      if descriptorTag == tag {
        return offset + length <= bytes.count ? Array(bytes[offset..<(offset + length)]) : nil
      }
      switch descriptorTag {
      case 0x03:
        // `ES_Descriptor`: the ID and the flags, then the nested descriptors
        let flags = offset + 2 < bytes.count ? bytes[offset + 2] : 0
        offset += 3
        if flags & 0x80 != 0 {
          offset += 2
        }
        if flags & 0x40 != 0, offset < bytes.count {
          offset += 1 + Int(bytes[offset])
        }
        if flags & 0x20 != 0 {
          offset += 2
        }
      case decoderConfigTag:
        // The decoder configuration's own fields, then its nested descriptors
        offset += 13
      default:
        offset += length
      }
    }
    return nil
  }

  /// `pic_parameter_set_id` and `seq_parameter_set_id` are Exp-Golomb codes, then comes `entropy_coding_mode_flag`
  private static func readEntropyCodingModeFlag(_ rbsp: [UInt8]) -> Bool? {
    var reader = BitReader(bytes: rbsp)
    guard reader.readExpGolomb() != nil, reader.readExpGolomb() != nil, let flag = reader.readBit() else {
      return nil
    }
    return flag == 1
  }

  private static func findBoxes(in bytes: [UInt8], range: Range<Int>) -> [Box] {
    var boxes: [Box] = []
    var offset = range.lowerBound
    while offset + 8 <= range.upperBound {
      var size = readUInt32(bytes, offset)
      var headerLength = 8
      if size == 1, offset + 16 <= range.upperBound {
        size = readUInt32(bytes, offset + 8) << 32 | readUInt32(bytes, offset + 12)
        headerLength = 16
      } else if size == 0 {
        size = range.upperBound - offset
      }
      guard size >= headerLength, offset + size <= range.upperBound else {
        break
      }
      boxes.append(Box(type: readType(bytes, offset + 4), payload: (offset + headerLength)..<(offset + size)))
      offset += size
    }
    return boxes
  }

  private static func findChild(_ bytes: [UInt8], _ box: Box, _ type: String) -> Box? {
    guard containerTypes.contains(box.type) else {
      return nil
    }
    return findBoxes(in: bytes, range: box.payload).first { $0.type == type }
  }

  /// The duration of an `mvhd` or `mdhd` box in milliseconds
  private static func readDuration(_ bytes: [UInt8], _ payload: Range<Int>) -> Int? {
    guard !payload.isEmpty else {
      return nil
    }
    let version = bytes[payload.lowerBound]
    let start = payload.lowerBound + 4
    let timescale: Int
    let duration: Int
    if version == 1 {
      guard payload.count >= 32 else {
        return nil
      }
      timescale = readUInt32(bytes, start + 16)
      duration = readUInt32(bytes, start + 20) << 32 | readUInt32(bytes, start + 24)
    } else {
      guard payload.count >= 20 else {
        return nil
      }
      timescale = readUInt32(bytes, start + 8)
      duration = readUInt32(bytes, start + 12)
    }
    return timescale > 0 ? duration * 1000 / timescale : nil
  }

  private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> Int {
    Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
  }

  private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> Int {
    readUInt16(bytes, offset) << 16 | readUInt16(bytes, offset + 2)
  }

  private static func readType(_ bytes: [UInt8], _ offset: Int) -> String {
    String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
  }

  private struct Box {
    let type: String
    let payload: Range<Int>
  }

  private struct BitReader {
    let bytes: [UInt8]
    var position = 0

    mutating func readBit() -> Int? {
      guard position < bytes.count * 8 else {
        return nil
      }
      let bit = Int(bytes[position / 8] >> (7 - position % 8)) & 1
      position += 1
      return bit
    }

    mutating func readExpGolomb() -> Int? {
      var leadingZeros = 0
      while true {
        guard let bit = readBit() else {
          return nil
        }
        if bit == 1 {
          break
        }
        leadingZeros += 1
      }
      var value = 0
      for _ in 0..<leadingZeros {
        guard let bit = readBit() else {
          return nil
        }
        value = value << 1 | bit
      }
      return (1 << leadingZeros) - 1 + value
    }
  }
}
