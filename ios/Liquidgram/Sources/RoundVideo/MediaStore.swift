import Foundation
import os

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "MediaStore")

/// Files that the app hands to the page, such as recorded round videos. The page gets a path under `pathPrefix` with a
/// random 128-bit token, and `AppSchemeHandler` serves the file at that path, with range requests, until the page
/// releases it, it expires after `lifetime` or the app launches again. So no file data crosses the bridge as base64.
///
/// The files live in `tmp/RoundVideos/`. Every method is thread-safe: the bridge registers and releases files on the
/// main queue, and the scheme handler looks them up on its read queue.
final class MediaStore {
  /// A registered file as the scheme handler serves it. Registered files never change.
  struct File {
    let url: URL
    let contentType: String
    let length: Int
  }

  static let shared = MediaStore()
  static let pathPrefix = "/__liquidgram/media/"
  static let defaultDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("RoundVideos", isDirectory: true)
  static let defaultLifetime: Duration = .seconds(600)

  private static let tokenByteCount = 16

  private let directory: URL
  private let lifetime: Duration
  private let lock = NSLock()
  /// Registered files by their path
  private var entries: [String: Entry] = [:]

  init(directory: URL = MediaStore.defaultDirectory, lifetime: Duration = MediaStore.defaultLifetime) {
    self.directory = directory
    self.lifetime = lifetime
  }

  /// The number of registered files
  var count: Int {
    removeExpired()
    lock.lock()
    defer {
      lock.unlock()
    }
    return entries.count
  }

  /// A new file in the store's folder for a recording to be written to. The page can reach it only after `register`.
  func makeFileURL(pathExtension: String) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
      .appendingPathComponent(UUID().uuidString, isDirectory: false)
      .appendingPathExtension(pathExtension)
  }

  /// Makes a finished file available to the page and returns its path, or `nil` when the file cannot be read. The
  /// path ends with the file's extension.
  func register(_ fileURL: URL, contentType: String) -> String? {
    guard let length = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
      logger.error("Could not register a file that cannot be read")
      return nil
    }
    let path = Self.pathPrefix + Self.makeToken() + "." + fileURL.pathExtension
    let entry = Entry(
      file: File(url: fileURL, contentType: contentType, length: length),
      expiry: ContinuousClock.now.advanced(by: lifetime)
    )
    lock.lock()
    entries[path] = entry
    lock.unlock()
    scheduleExpiry()
    return path
  }

  /// The registered file at a path the page requested, or `nil` when the path is unknown, released or expired
  func findFile(path: String) -> File? {
    removeExpired()
    lock.lock()
    defer {
      lock.unlock()
    }
    return entries[path]?.file
  }

  /// Deletes the file at a path that the page got and no longer needs
  func release(path: String) {
    lock.lock()
    let entry = entries.removeValue(forKey: path)
    lock.unlock()
    if let entry {
      Self.delete(entry.file.url)
    }
  }

  /// Deletes every registered file, for example when the page that knew their paths is gone
  func releaseAll() {
    lock.lock()
    let removedEntries = Array(entries.values)
    entries.removeAll()
    lock.unlock()
    for entry in removedEntries {
      Self.delete(entry.file.url)
    }
  }

  /// Deletes the folder with every file in it, including files of an earlier launch, which no page can know
  func removeAllFiles() {
    releaseAll()
    try? FileManager.default.removeItem(at: directory)
  }

  private static func makeToken() -> String {
    var generator = SystemRandomNumberGenerator()
    return (0..<tokenByteCount)
      .map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
      .joined()
  }

  private static func delete(_ url: URL) {
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      logger.debug("Could not delete a media file: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Deletes the files once they expire, even when nothing asks for them. The wall clock keeps counting while the
  /// device sleeps; every lookup checks the expiry too.
  private func scheduleExpiry() {
    let components = lifetime.components
    let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
    DispatchQueue.global(qos: .utility).asyncAfter(wallDeadline: .now() + seconds) { [weak self] in
      self?.removeExpired()
    }
  }

  private func removeExpired() {
    let now = ContinuousClock.now
    lock.lock()
    let expiredPaths = entries.filter { $0.value.expiry <= now }.map(\.key)
    let expiredEntries = expiredPaths.compactMap { entries.removeValue(forKey: $0) }
    lock.unlock()
    for entry in expiredEntries {
      logger.info("A media file expired before the page released it")
      Self.delete(entry.file.url)
    }
  }
}

private struct Entry {
  let file: MediaStore.File
  let expiry: ContinuousClock.Instant
}
