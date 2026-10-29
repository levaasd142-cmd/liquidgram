import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif
import WebKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "MediaStream")

/// Bytes of a media file that the stream asks the page for
struct MediaPartRequest {
  /// The URL the media element loads, such as `liquidgram-web://app/progressive/document5032971201876312345?fileSize=…`,
  /// which the page's API understands
  let url: String
  /// The first and the last byte, both included
  let start: Int
  let end: Int
}

/// Bytes of a media file and what the page knows about the whole file
struct MediaPart {
  let data: Data
  /// The size of the whole file, when the page knows it
  let totalLength: Int?
  let mimeType: String?
}

/// Asks the page of a web view for bytes of a media file and calls back on the main queue
typealias MediaPartLoader = (MediaPartRequest, WKWebView, @escaping (Result<MediaPart, Error>) -> Void) -> Void

enum MediaStreamError: Error {
  /// The page has no `loadMediaPart` yet, or its download failed
  case pageFailed(String)
  /// The page answered with fewer bytes than the file has at that offset
  case incompletePart
  /// Neither the page nor the URL tells the size of the file
  case unknownLength
}

/// Streams the videos and the music of the web app. In browsers the web app's service worker answers the range
/// requests that media elements send for `./progressive/<media hash>`; the iOS app has no service worker, so this
/// stream answers them under `liquidgram-web://app/progressive/`. The bytes come from the page, which downloads them
/// from Telegram with its API worker: the stream calls `window.__liquidgramNative.loadMediaPart(url, start, end)`.
///
/// A file is read in parts of 512 KB at fixed offsets, so requests that start anywhere share them. Like the service
/// worker's, a response carries at most 512 KB from the requested start, and the media element asks for the rest
/// with further requests; meanwhile the next two parts load ahead. Recent parts stay in memory up to 16 MB, so the
/// 0-1 probe, repeated small ranges and seeks back need no new download. At most four parts load at once, and a part
/// that only stopped requests waited for is dropped before it starts.
///
/// Responses carry only audio and video content types, `nosniff` and a sandbox policy: a frame of another origin
/// could open a stream URL as a page of the app's origin, and the file is whatever someone sent in a chat. WebKit
/// starts and stops tasks on the main queue, and all state here is used there.
final class ProgressiveMediaStream {
  static let pathPrefix = "/progressive/"
  static let partLength = 512 * 1024

  private static let readAheadPartCount = 2
  private static let maxConcurrentLoads = 4
  private static let maxQueuedReadAheads = 8
  private static let cacheBudget = 16 * 1024 * 1024
  /// The page retries a failed download for a few seconds; a slow network can take longer for a part
  private static let defaultLoadTimeout: TimeInterval = 60
  private static let appOrigin = "\(AppSchemeHandler.scheme)://\(AppSchemeHandler.host)"
  private static let rangeUnitPrefix = "bytes="
  private static let defaultContentType = "application/octet-stream"
  private static let maxContentTypeLength = 100
  private static let httpVersion = "HTTP/1.1"

  private let loadPart: MediaPartLoader
  private let loadTimeout: TimeInterval
  private var streams: [ObjectIdentifier: StreamTask] = [:]
  private var loads: [PartKey: PartLoad] = [:]
  /// Loads waiting for a free slot, oldest first
  private var queuedKeys: [PartKey] = []
  private var activeLoadCount = 0
  private var cache = PartCache(budget: ProgressiveMediaStream.cacheBudget)
  private var memoryWarningObserver: NSObjectProtocol?

  init(
    loadPart: @escaping MediaPartLoader = PageMediaPartLoader.load,
    loadTimeout: TimeInterval = ProgressiveMediaStream.defaultLoadTimeout
  ) {
    self.loadPart = loadPart
    self.loadTimeout = loadTimeout
    #if canImport(UIKit)
    memoryWarningObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.cache.removeAll()
    }
    #endif
  }

  deinit {
    if let memoryWarningObserver {
      NotificationCenter.default.removeObserver(memoryWarningObserver)
    }
  }

  /// Whether a request of the app's origin is for a stream
  static func canAnswer(_ url: URL?) -> Bool {
    guard let url, AppSchemeHandler.isAppURL(url) else {
      return false
    }
    return url.path.hasPrefix(pathPrefix)
  }

  func start(_ schemeTask: WKURLSchemeTask, in webView: WKWebView) {
    let request = schemeTask.request
    guard let url = request.url else {
      schemeTask.didFailWithError(URLError(.badURL))
      return
    }
    let stream = StreamTask(task: schemeTask, webView: webView, url: url, request: request)
    stream.firstPartIndex = Self.findFirstOffset(rangeHeader: stream.rangeHeader, declaredLength: stream.declaredLength)
      / Self.partLength
    streams[ObjectIdentifier(schemeTask)] = stream

    let method = request.httpMethod?.uppercased() ?? "GET"
    guard method == "GET" || method == "HEAD" else {
      respondWithError(stream, .methodNotAllowed, extraHeaders: ["Allow": "GET, HEAD"])
      return
    }
    // The page's media elements send no `Origin`; a fetch from a frame of another origin does
    if let origin = request.value(forHTTPHeaderField: "Origin"), origin.lowercased() != Self.appOrigin {
      respondWithError(stream, .forbidden)
      return
    }
    guard url.path.count > Self.pathPrefix.count else {
      respondWithError(stream, .notFound)
      return
    }
    advance(stream)
  }

  /// Returns whether the task was a stream's
  @discardableResult
  func stop(_ schemeTask: WKURLSchemeTask) -> Bool {
    guard let stream = streams.removeValue(forKey: ObjectIdentifier(schemeTask)) else {
      return false
    }
    stream.isStopped = true
    if let index = stream.awaitedPart {
      release(stream, from: PartKey(resource: stream.resource, index: index))
    }
    return true
  }

  // MARK: - Responses

  /// Hands WebKit the bytes of the task that are at hand, then waits for the part it needs next
  private func advance(_ stream: StreamTask, loaded: (index: Int, part: MediaPart)? = nil) {
    while !stream.isStopped {
      guard let responseRange = stream.responseRange else {
        // The first part tells the size and the type of the file, which the response head needs
        let index = stream.firstPartIndex
        guard let part = findPart(index, of: stream, loaded: loaded) else {
          waitForPart(index, stream)
          return
        }
        respond(to: stream, firstPart: part)
        continue
      }

      guard !stream.omitsBody, stream.offset < responseRange.upperBound else {
        finish(stream)
        return
      }
      let index = stream.offset / Self.partLength
      guard let part = findPart(index, of: stream, loaded: loaded) else {
        waitForPart(index, stream)
        return
      }
      let partStart = index * Self.partLength
      let sliceEnd = min(responseRange.upperBound, partStart + part.data.count)
      guard sliceEnd > stream.offset else {
        fail(stream, MediaStreamError.incompletePart)
        return
      }
      let dataStart = part.data.startIndex
      stream.task.didReceive(part.data.subdata(in: (dataStart + stream.offset - partStart)..<(dataStart + sliceEnd - partStart)))
      stream.offset = sliceEnd
      readAhead(after: index, for: stream)
    }
  }

  /// Sends the response head, or an error when the range lies beyond the file
  private func respond(to stream: StreamTask, firstPart: MediaPart) {
    guard let totalLength = firstPart.totalLength ?? stream.declaredLength, totalLength > 0 else {
      fail(stream, MediaStreamError.unknownLength)
      return
    }

    let status: SchemeStatus
    let range: Range<Int>
    var headers: [String: String] = [:]
    switch SchemeByteRange(header: stream.rangeHeader, length: totalLength) {
    case .entire:
      status = .ok
      range = 0..<totalLength
      stream.readAheadEnd = totalLength
    case .partial(let requestedRange):
      status = .partialContent
      range = requestedRange.lowerBound..<min(requestedRange.upperBound, requestedRange.lowerBound + Self.partLength)
      headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(totalLength)"
      stream.readAheadEnd = requestedRange.upperBound
    case .unsatisfiable:
      respondWithError(stream, .rangeNotSatisfiable, extraHeaders: ["Content-Range": "bytes */\(totalLength)"])
      return
    }

    headers["Content-Type"] = Self.makeContentType(firstPart.mimeType, stream.declaredMimeType)
    headers["Content-Length"] = String(range.count)
    headers["Accept-Ranges"] = "bytes"
    headers["Cache-Control"] = "no-store"
    headers["X-Content-Type-Options"] = "nosniff"
    // A frame that opens a stream as a page gets a document without scripts and without the app's origin
    headers["Content-Security-Policy"] = "sandbox"
    guard let response = HTTPURLResponse(
      url: stream.url,
      statusCode: status.rawValue,
      httpVersion: Self.httpVersion,
      headerFields: headers
    ) else {
      fail(stream, URLError(.cannotParseResponse))
      return
    }
    stream.responseRange = range
    stream.offset = range.lowerBound
    stream.task.didReceive(response)
  }

  private func respondWithError(_ stream: StreamTask, _ status: SchemeStatus, extraHeaders: [String: String] = [:]) {
    let body = Data(status.reasonPhrase.utf8)
    var headers = [
      "Content-Type": "text/plain; charset=utf-8",
      "Content-Length": String(body.count),
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    ]
    headers.merge(extraHeaders) { _, extraValue in
      extraValue
    }
    guard let response = HTTPURLResponse(
      url: stream.url,
      statusCode: status.rawValue,
      httpVersion: Self.httpVersion,
      headerFields: headers
    ) else {
      fail(stream, URLError(.cannotParseResponse))
      return
    }
    stream.task.didReceive(response)
    if !stream.omitsBody {
      stream.task.didReceive(body)
    }
    finish(stream)
  }

  private func finish(_ stream: StreamTask) {
    guard !stream.isStopped else {
      return
    }
    stream.isStopped = true
    streams.removeValue(forKey: ObjectIdentifier(stream.task))
    stream.task.didFinish()
  }

  private func fail(_ stream: StreamTask, _ error: Error) {
    guard !stream.isStopped else {
      return
    }
    stream.isStopped = true
    streams.removeValue(forKey: ObjectIdentifier(stream.task))
    stream.task.didFailWithError(error)
  }

  /// The first requested byte as far as the request tells it before the size of the file is known: the start of
  /// `bytes=<first>-…`, or of a suffix range in a file of the declared size. Other forms start at 0, which also
  /// gives the size for a suffix range of an undeclared size.
  private static func findFirstOffset(rangeHeader: String?, declaredLength: Int?) -> Int {
    guard let rangeHeader, rangeHeader.hasPrefix(rangeUnitPrefix), !rangeHeader.contains(",") else {
      return 0
    }
    let spec = rangeHeader.dropFirst(rangeUnitPrefix.count).trimmingCharacters(in: .whitespaces)
    let bounds = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    guard bounds.count == 2 else {
      return 0
    }
    var offset = 0
    if let first = Int(bounds[0]), first >= 0 {
      offset = first
    } else if bounds[0].isEmpty, let suffixLength = Int(bounds[1]), let declaredLength {
      offset = max(0, declaredLength - suffixLength)
    }
    // A start beyond the declared size gets 416, which the first part's size confirms
    if let declaredLength, offset >= declaredLength {
      return 0
    }
    return offset
  }

  /// Audio and video types only, without parameters; anything else is served as plain bytes
  private static func makeContentType(_ candidates: String?...) -> String {
    for candidate in candidates {
      guard let type = candidate?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased(),
            type.count <= maxContentTypeLength,
            type.hasPrefix("video/") || type.hasPrefix("audio/") else {
        continue
      }
      let isToken = type.allSatisfy { character in
        character.isASCII && (character.isLetter || character.isNumber || "/.+-".contains(character))
      }
      if isToken {
        return type
      }
    }
    return defaultContentType
  }

  // MARK: - Parts

  private func findPart(_ index: Int, of stream: StreamTask, loaded: (index: Int, part: MediaPart)?) -> MediaPart? {
    if let loaded, loaded.index == index {
      return loaded.part
    }
    return cache.part(for: PartKey(resource: stream.resource, index: index))
  }

  private func waitForPart(_ index: Int, _ stream: StreamTask) {
    stream.awaitedPart = index
    let key = PartKey(resource: stream.resource, index: index)
    let load = loads[key] ?? addLoad(key, webView: stream.webView)
    load.waitingStreams.append(stream)
    readAhead(after: index, for: stream)
    startQueuedLoads()
  }

  /// Loads the next parts of a stream that reads on, so its next requests find them
  private func readAhead(after index: Int, for stream: StreamTask) {
    guard let readAheadEnd = stream.readAheadEnd, readAheadEnd > 0 else {
      return
    }
    let lastIndex = min(index + Self.readAheadPartCount, (readAheadEnd - 1) / Self.partLength)
    guard lastIndex > index else {
      return
    }
    for nextIndex in (index + 1)...lastIndex {
      let key = PartKey(resource: stream.resource, index: nextIndex)
      guard loads[key] == nil, !cache.contains(key) else {
        continue
      }
      addLoad(key, webView: stream.webView).isReadAhead = true
    }
    dropOldReadAheads()
    startQueuedLoads()
  }

  @discardableResult
  private func addLoad(_ key: PartKey, webView: WKWebView?) -> PartLoad {
    let load = PartLoad(key: key, webView: webView)
    loads[key] = load
    queuedKeys.append(key)
    return load
  }

  /// A part nobody waits for any more is not loaded, unless it was read ahead
  private func release(_ stream: StreamTask, from key: PartKey) {
    guard let load = loads[key] else {
      return
    }
    load.waitingStreams.removeAll { $0 === stream }
    if !load.isStarted, load.waitingStreams.isEmpty, !load.isReadAhead {
      loads.removeValue(forKey: key)
      queuedKeys.removeAll { $0 == key }
    }
  }

  /// Keeps the newest read-aheads that have not started, so a stream that jumped around does not hold up others
  private func dropOldReadAheads() {
    let readAheadKeys = queuedKeys.filter { key in
      guard let load = loads[key] else {
        return false
      }
      return !load.isStarted && load.waitingStreams.isEmpty
    }
    guard readAheadKeys.count > Self.maxQueuedReadAheads else {
      return
    }
    let droppedKeys = Set(readAheadKeys.prefix(readAheadKeys.count - Self.maxQueuedReadAheads))
    for key in droppedKeys {
      loads.removeValue(forKey: key)
    }
    queuedKeys.removeAll { droppedKeys.contains($0) }
  }

  /// Starts queued loads while slots are free: parts that requests wait for first, then read-aheads
  private func startQueuedLoads() {
    while activeLoadCount < Self.maxConcurrentLoads {
      let waitedIndex = queuedKeys.firstIndex { loads[$0]?.waitingStreams.isEmpty == false }
      guard let queueIndex = waitedIndex ?? (queuedKeys.isEmpty ? nil : 0) else {
        return
      }
      let key = queuedKeys.remove(at: queueIndex)
      guard let load = loads[key] else {
        continue
      }
      startLoad(load)
    }
  }

  private func startLoad(_ load: PartLoad) {
    guard let webView = load.webView else {
      loads.removeValue(forKey: load.key)
      complete(load, with: .failure(URLError(.cancelled)))
      return
    }
    load.isStarted = true
    activeLoadCount += 1

    let start = load.key.index * Self.partLength
    let request = MediaPartRequest(url: load.key.resource, start: start, end: start + Self.partLength - 1)
    let timeout = DispatchWorkItem { [weak self, weak load] in
      guard let self, let load else {
        return
      }
      self.finishLoad(load, with: .failure(URLError(.timedOut)))
    }
    load.timeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + loadTimeout, execute: timeout)
    loadPart(request, webView) { [weak self, weak load] result in
      guard let self, let load else {
        return
      }
      self.finishLoad(load, with: result)
    }
  }

  /// Takes the first of the page's answer and the timeout
  private func finishLoad(_ load: PartLoad, with result: Result<MediaPart, Error>) {
    guard !load.isFinished else {
      return
    }
    load.isFinished = true
    load.timeout?.cancel()
    activeLoadCount -= 1
    loads.removeValue(forKey: load.key)

    let checkedResult = result.flatMap { Self.check($0, index: load.key.index) }
    switch checkedResult {
    case .success(let part):
      cache.insert(part, for: load.key)
    case .failure(let error):
      logger.error("A part of a media file did not load: \(String(describing: error), privacy: .public)")
    }
    complete(load, with: checkedResult)
    startQueuedLoads()
  }

  private func complete(_ load: PartLoad, with result: Result<MediaPart, Error>) {
    let waitingStreams = load.waitingStreams
    load.waitingStreams.removeAll()
    for stream in waitingStreams where !stream.isStopped {
      stream.awaitedPart = nil
      switch result {
      case .success(let part):
        advance(stream, loaded: (index: load.key.index, part: part))
      case .failure(let error):
        fail(stream, error)
      }
    }
  }

  /// A part has all bytes of the file at its offset: a whole part, or the rest of the file at its end
  private static func check(_ part: MediaPart, index: Int) -> Result<MediaPart, Error> {
    let start = index * partLength
    let data = part.data.count > partLength ? part.data.prefix(partLength) : part.data
    guard !data.isEmpty else {
      return .failure(MediaStreamError.incompletePart)
    }
    if let totalLength = part.totalLength {
      guard start < totalLength, data.count == min(partLength, totalLength - start) else {
        return .failure(MediaStreamError.incompletePart)
      }
      return .success(MediaPart(data: data, totalLength: totalLength, mimeType: part.mimeType))
    }
    // Without the size, a short part ends the file
    let totalLength = data.count < partLength ? start + data.count : nil
    return .success(MediaPart(data: data, totalLength: totalLength, mimeType: part.mimeType))
  }
}

/// Calls the page's `window.__liquidgramNative.loadMediaPart(url, start, end)`, which `util/nativeMediaStream.ts`
/// sets. It resolves with `{ data, mimeType, fullSize }`, the bytes in base64, or with nothing when the download failed.
enum PageMediaPartLoader {
  private static let script = """
    const loadMediaPart = window.__liquidgramNative?.loadMediaPart;
    if (typeof loadMediaPart !== 'function') return { error: 'notReady' };
    return (await loadMediaPart(url, start, end)) || { error: 'failed' };
    """

  static func load(
    _ request: MediaPartRequest,
    from webView: WKWebView,
    completion: @escaping (Result<MediaPart, Error>) -> Void
  ) {
    let arguments: [String: Any] = ["url": request.url, "start": request.start, "end": request.end]
    webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
      completion(result.flatMap(makePart))
    }
  }

  private static func makePart(_ value: Any) -> Result<MediaPart, Error> {
    let object = value as? [String: Any]
    guard let base64 = object?["data"] as? String, let data = Data(base64Encoded: base64) else {
      return .failure(MediaStreamError.pageFailed(object?["error"] as? String ?? "invalid answer"))
    }
    return .success(MediaPart(
      data: data,
      totalLength: (object?["fullSize"] as? NSNumber)?.intValue,
      mimeType: object?["mimeType"] as? String
    ))
  }
}

/// A part of a file, named by the stream URL without its fragment
private struct PartKey: Hashable {
  let resource: String
  let index: Int
}

/// A request of a media element
private final class StreamTask {
  let task: WKURLSchemeTask
  weak var webView: WKWebView?
  let url: URL
  /// The URL without its fragment, which names the file for the page and in the cache
  let resource: String
  let rangeHeader: String?
  let omitsBody: Bool
  /// The size and the type that the page put into the URL, as for Safari
  let declaredLength: Int?
  let declaredMimeType: String?
  /// The part that holds the first requested byte, as far as the request tells it before the size is known
  var firstPartIndex = 0
  var isStopped = false
  /// The bytes the response carries, known once the first part arrived
  var responseRange: Range<Int>?
  /// The next byte to hand to WebKit
  var offset = 0
  var awaitedPart: Int?
  /// The end of what the request asked for, up to which the next parts load ahead
  var readAheadEnd: Int?

  init(task: WKURLSchemeTask, webView: WKWebView, url: URL, request: URLRequest) {
    self.task = task
    self.webView = webView
    self.url = url
    resource = url.absoluteString.components(separatedBy: "#")[0]
    rangeHeader = request.value(forHTTPHeaderField: "Range")
    omitsBody = request.httpMethod?.uppercased() == "HEAD"

    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let fileSize = queryItems.first { $0.name == "fileSize" }?.value.flatMap { Int($0) }
    declaredLength = fileSize.flatMap { $0 > 0 ? $0 : nil }
    declaredMimeType = queryItems.first { $0.name == "mimeType" }?.value
  }
}

/// A part that is loading or waits for a slot
private final class PartLoad {
  let key: PartKey
  weak var webView: WKWebView?
  var waitingStreams: [StreamTask] = []
  /// Loaded ahead of the requests, so it stays queued when no request waits for it
  var isReadAhead = false
  var isStarted = false
  var isFinished = false
  var timeout: DispatchWorkItem?

  init(key: PartKey, webView: WKWebView?) {
    self.key = key
    self.webView = webView
  }
}

/// Recently used parts up to a total size; the least recently used go first
private struct PartCache {
  private let budget: Int
  private var parts: [PartKey: (part: MediaPart, lastUse: Int)] = [:]
  private var totalBytes = 0
  private var useCounter = 0

  init(budget: Int) {
    self.budget = budget
  }

  func contains(_ key: PartKey) -> Bool {
    parts[key] != nil
  }

  mutating func part(for key: PartKey) -> MediaPart? {
    guard let entry = parts[key] else {
      return nil
    }
    useCounter += 1
    parts[key] = (part: entry.part, lastUse: useCounter)
    return entry.part
  }

  mutating func insert(_ part: MediaPart, for key: PartKey) {
    if let old = parts[key] {
      totalBytes -= old.part.data.count
    }
    useCounter += 1
    parts[key] = (part: part, lastUse: useCounter)
    totalBytes += part.data.count
    while totalBytes > budget, let oldest = parts.min(by: { $0.value.lastUse < $1.value.lastUse }) {
      parts.removeValue(forKey: oldest.key)
      totalBytes -= oldest.value.part.data.count
    }
  }

  mutating func removeAll() {
    parts.removeAll()
    totalBytes = 0
  }
}
