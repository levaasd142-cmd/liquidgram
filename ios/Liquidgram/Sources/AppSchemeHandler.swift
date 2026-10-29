import Foundation
import os
import WebKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "AppSchemeHandler")

/// Serves the bundled web build at `liquidgram-web://app/`. All user data lives in storage owned by this origin, so
/// the scheme and the host never change. Only the web views this handler is registered with can load the scheme, and
/// no socket is involved, so no other app on the device can answer these requests, unlike a loopback port, which any
/// app can bind while Liquidgram is suspended. Since iOS 16 WebKit gives a scheme with a handler a regular origin and
/// treats it as a secure context, so Web Crypto, media capture and storage work as on HTTPS.
///
/// Two limits come with the scheme. WebKit sends no `Referer` from pages that are not http(s), so embeds that require
/// one, such as YouTube's player, show an error instead of the video. Shared workers run outside the page, where the
/// scheme has no handler: they get an opaque origin that is not a secure context and cannot load anything, which the
/// web app's shared state worker never needs.
///
/// WebKit starts and stops tasks on the main queue. Files are read on a background queue, one chunk of a task at a
/// time, and every call to a task happens on the main queue after checking that WebKit has not stopped it: a call to a
/// stopped task raises an exception.
final class AppSchemeHandler: NSObject {
  static let scheme = "liquidgram-web"
  static let host = "app"
  static let appURL = URL(string: "\(scheme)://\(host)/")!
  static let bundledWebRoot = Bundle.main.bundleURL.appendingPathComponent("WebApp", isDirectory: true)

  /// Larger files, such as media that WebKit reads with range requests, are read and handed over in chunks
  private static let chunkLength = 256 * 1024

  private let responder: SchemeFileResponder
  private let readQueue = DispatchQueue(label: "org.liquidgram.messenger.app-scheme", qos: .userInitiated)
  /// Tasks that WebKit started and has not stopped, used on the main queue only
  private var runningTasks: [ObjectIdentifier: RunningTask] = [:]

  init(webRoot: URL = AppSchemeHandler.bundledWebRoot) {
    responder = SchemeFileResponder(webRoot: webRoot.standardizedFileURL)
    super.init()
  }

  /// Whether a URL or a security origin with these parts belongs to the app's own pages. The scheme has no default
  /// port: app URLs have none, and their `WKSecurityOrigin` reports 0.
  static func isAppOrigin(scheme: String?, host: String?, port: Int?) -> Bool {
    scheme?.lowercased() == Self.scheme && host?.lowercased() == Self.host && (port == nil || port == 0)
  }

  static func isAppURL(_ url: URL) -> Bool {
    isAppOrigin(scheme: url.scheme, host: url.host, port: url.port)
  }

  /// Hands an answer to WebKit unless it stopped the task while the answer was prepared
  private func deliver(_ answer: SchemeAnswer, to task: RunningTask) {
    guard !task.isStopped else {
      return
    }

    switch answer {
    case .failure(let error):
      complete(task, error: error)
    case .response(let response, let body):
      task.task.didReceive(response)
      switch body {
      case .none:
        complete(task)
      case .data(let data):
        task.task.didReceive(data)
        complete(task)
      case .file(let fileBody):
        readNextChunk(of: fileBody, for: task)
      }
    }
  }

  /// Reads the next chunk only after the previous one reached WebKit, so a task holds at most one chunk in memory
  private func readNextChunk(of body: FileBody, for task: RunningTask) {
    readQueue.async {
      let result = Result { try body.readChunk(maxLength: Self.chunkLength) }
      let isLastChunk = body.isComplete
      DispatchQueue.main.async {
        guard !task.isStopped else {
          return
        }

        switch result {
        case .success(let data):
          task.task.didReceive(data)
          if isLastChunk {
            self.complete(task)
          } else {
            self.readNextChunk(of: body, for: task)
          }
        case .failure(let error):
          logger.error("Could not read a file of the web build: \(error.localizedDescription, privacy: .public)")
          self.complete(task, error: error)
        }
      }
    }
  }

  private func complete(_ task: RunningTask, error: Error? = nil) {
    runningTasks.removeValue(forKey: ObjectIdentifier(task.task))
    if let error {
      task.task.didFailWithError(error)
    } else {
      task.task.didFinish()
    }
  }
}

extension AppSchemeHandler: WKURLSchemeHandler {
  func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    let task = RunningTask(task: urlSchemeTask)
    runningTasks[ObjectIdentifier(urlSchemeTask)] = task
    let request = urlSchemeTask.request
    readQueue.async { [responder] in
      let answer = responder.makeAnswer(for: request)
      DispatchQueue.main.async {
        self.deliver(answer, to: task)
      }
    }
  }

  func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    guard let task = runningTasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask)) else {
      return
    }
    task.isStopped = true
  }
}

/// A task that WebKit started. `isStopped` is used on the main queue only.
private final class RunningTask {
  let task: WKURLSchemeTask
  var isStopped = false

  init(task: WKURLSchemeTask) {
    self.task = task
  }
}

/// A response with its body, or an error for a request that has no URL to answer
private enum SchemeAnswer {
  case response(HTTPURLResponse, SchemeBody)
  case failure(Error)
}

private enum SchemeBody {
  case none
  case data(Data)
  case file(FileBody)
}

/// A byte range of a file, read in chunks on the read queue only. Every read opens the file and closes it again, so
/// tasks that wait for the main queue hold no file descriptors.
private final class FileBody {
  private let url: URL
  private var offset: Int
  private var remainingLength: Int

  init(url: URL, range: Range<Int>) {
    self.url = url
    offset = range.lowerBound
    remainingLength = range.count
  }

  var isComplete: Bool {
    remainingLength == 0
  }

  func readChunk(maxLength: Int) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer {
      try? handle.close()
    }
    try handle.seek(toOffset: UInt64(offset))

    let length = min(maxLength, remainingLength)
    var data = Data()
    while data.count < length {
      guard let part = try handle.read(upToCount: length - data.count), !part.isEmpty else {
        break
      }
      data.append(part)
    }
    // Files of the app bundle never change, so a short read means a damaged file
    guard data.count == length else {
      throw CocoaError(.fileReadCorruptFile)
    }
    offset += length
    remainingLength -= length
    return data
  }
}

/// Answers requests with files of the web build, with the content types, cache headers and range support of
/// `LocalServer`
private struct SchemeFileResponder {
  private static let indexFileName = "index.html"
  private static let defaultContentType = "application/octet-stream"
  private static let immutableCacheControl = "public, max-age=31536000, immutable"
  private static let revalidateCacheControl = "no-cache"
  private static let hashedAssetPrefix = "assets/"
  private static let assetHashLength = 8
  private static let httpVersion = "HTTP/1.1"
  private static let allowedMethods: Set<String> = ["GET", "HEAD"]

  // An explicit table, so the types never depend on what the system maps extensions to
  private static let contentTypes: [String: String] = [
    "avif": "image/avif",
    "bin": "application/octet-stream",
    "css": "text/css; charset=utf-8",
    "gif": "image/gif",
    "htm": "text/html; charset=utf-8",
    "html": "text/html; charset=utf-8",
    "ico": "image/x-icon",
    "jpeg": "image/jpeg",
    "jpg": "image/jpeg",
    "js": "text/javascript; charset=utf-8",
    "json": "application/json",
    "m4a": "audio/mp4",
    "mjs": "text/javascript; charset=utf-8",
    "mp3": "audio/mpeg",
    "mp4": "video/mp4",
    "oga": "audio/ogg",
    "ogg": "audio/ogg",
    "opus": "audio/ogg",
    "otf": "font/otf",
    "pdf": "application/pdf",
    "png": "image/png",
    "svg": "image/svg+xml",
    "tgs": "application/x-tgsticker",
    "ttf": "font/ttf",
    "txt": "text/plain; charset=utf-8",
    "wasm": "application/wasm",
    "wav": "audio/wav",
    "webm": "video/webm",
    "webmanifest": "application/manifest+json",
    "webp": "image/webp",
    "woff": "font/woff",
    "woff2": "font/woff2",
    "xml": "application/xml",
  ]

  let webRoot: URL

  func makeAnswer(for request: URLRequest) -> SchemeAnswer {
    guard let url = request.url else {
      return .failure(URLError(.badURL))
    }
    let method = request.httpMethod?.uppercased() ?? "GET"
    // A response to `HEAD` carries the headers of the `GET` response, including its length, without the body
    let omitsBody = method == "HEAD"

    // Another host or a port makes another origin, which the app never loads
    guard AppSchemeHandler.isAppURL(url) else {
      return makeError(.misdirectedRequest, url: url, omitsBody: omitsBody)
    }
    guard Self.allowedMethods.contains(method) else {
      return makeError(.methodNotAllowed, url: url, omitsBody: omitsBody, extraHeaders: ["Allow": "GET, HEAD"])
    }
    if let mediaAnswer = makeMediaAnswer(
      url: url,
      rangeHeader: request.value(forHTTPHeaderField: "Range"),
      omitsBody: omitsBody
    ) {
      return mediaAnswer
    }
    guard let fileName = Self.resolveFileName(url) else {
      return makeError(.badRequest, url: url, omitsBody: omitsBody)
    }
    return makeFileAnswer(
      url: url,
      fileName: fileName,
      rangeHeader: request.value(forHTTPHeaderField: "Range"),
      omitsBody: omitsBody
    )
  }

  private func makeFileAnswer(url: URL, fileName: String, rangeHeader: String?, omitsBody: Bool) -> SchemeAnswer {
    let fileURL = webRoot.appendingPathComponent(fileName, isDirectory: false)
    // `resolveFileName` already keeps requests inside the build; this guards against mistakes in it
    guard fileURL.standardizedFileURL.path.hasPrefix(webRoot.path + "/"),
          let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
          values.isRegularFile == true,
          let fileLength = values.fileSize else {
      return makeError(.notFound, url: url, omitsBody: omitsBody)
    }

    let contentType = Self.contentTypes[fileURL.pathExtension.lowercased()] ?? Self.defaultContentType
    var headers = [
      "Content-Type": contentType,
      "Cache-Control": Self.isHashedAsset(fileName) ? Self.immutableCacheControl : Self.revalidateCacheControl,
      "Accept-Ranges": "bytes",
      "X-Content-Type-Options": "nosniff",
    ]
    let status: SchemeStatus
    let range: Range<Int>
    // WebKit plays audio and video only from sources that answer range requests
    switch SchemeByteRange(header: rangeHeader, length: fileLength) {
    case .entire:
      status = .ok
      range = 0..<fileLength
    case .partial(let partialRange):
      status = .partialContent
      range = partialRange
      headers["Content-Range"] = "bytes \(partialRange.lowerBound)-\(partialRange.upperBound - 1)/\(fileLength)"
    case .unsatisfiable:
      return makeError(
        .rangeNotSatisfiable,
        url: url,
        omitsBody: omitsBody,
        extraHeaders: ["Content-Range": "bytes */\(fileLength)"]
      )
    }
    headers["Content-Length"] = String(range.count)

    guard let response = HTTPURLResponse(
      url: url,
      statusCode: status.rawValue,
      httpVersion: Self.httpVersion,
      headerFields: headers
    ) else {
      return .failure(URLError(.cannotParseResponse))
    }
    let body: SchemeBody = omitsBody || range.isEmpty ? .none : .file(FileBody(url: fileURL, range: range))
    return .response(response, body)
  }

  /// Files that the app hands to the page, such as recorded round videos, live outside the web build under
  /// `MediaStore.pathPrefix`. They are never cached, support single ranges like the build's files, and a path that is
  /// not registered, or no longer, is 404 rather than a file of the build. `nil` for every other path.
  private func makeMediaAnswer(url: URL, rangeHeader: String?, omitsBody: Bool) -> SchemeAnswer? {
    guard url.path.hasPrefix(MediaStore.pathPrefix) else {
      return nil
    }
    guard let file = MediaStore.shared.findFile(path: url.path) else {
      return makeError(.notFound, url: url, omitsBody: omitsBody)
    }
    var headers = [
      "Content-Type": file.contentType,
      "Cache-Control": "no-store",
      "Accept-Ranges": "bytes",
      "X-Content-Type-Options": "nosniff",
    ]
    let status: SchemeStatus
    let range: Range<Int>
    switch SchemeByteRange(header: rangeHeader, length: file.length) {
    case .entire:
      status = .ok
      range = 0..<file.length
    case .partial(let partialRange):
      status = .partialContent
      range = partialRange
      headers["Content-Range"] = "bytes \(partialRange.lowerBound)-\(partialRange.upperBound - 1)/\(file.length)"
    case .unsatisfiable:
      return makeError(
        .rangeNotSatisfiable,
        url: url,
        omitsBody: omitsBody,
        extraHeaders: ["Content-Range": "bytes */\(file.length)"]
      )
    }
    headers["Content-Length"] = String(range.count)
    guard let response = HTTPURLResponse(
      url: url,
      statusCode: status.rawValue,
      httpVersion: Self.httpVersion,
      headerFields: headers
    ) else {
      return .failure(URLError(.cannotParseResponse))
    }
    let body: SchemeBody = omitsBody || range.isEmpty ? .none : .file(FileBody(url: file.url, range: range))
    return .response(response, body)
  }

  private func makeError(
    _ status: SchemeStatus,
    url: URL,
    omitsBody: Bool,
    extraHeaders: [String: String] = [:]
  ) -> SchemeAnswer {
    let body = Data(status.reasonPhrase.utf8)
    var headers = [
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Length": String(body.count),
      "X-Content-Type-Options": "nosniff",
    ]
    headers.merge(extraHeaders) { _, extraValue in
      extraValue
    }
    guard let response = HTTPURLResponse(
      url: url,
      statusCode: status.rawValue,
      httpVersion: Self.httpVersion,
      headerFields: headers
    ) else {
      return .failure(URLError(.cannotParseResponse))
    }
    return .response(response, omitsBody ? .none : .data(body))
  }

  /// Maps a URL to a file of the web build. Dot segments, empty segments, backslashes and NUL characters are refused
  /// instead of being normalized, so no request reaches outside the build.
  private static func resolveFileName(_ url: URL) -> String? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let decodedPath = components.percentEncodedPath.removingPercentEncoding else {
      return nil
    }

    var fileName = decodedPath.hasPrefix("/") ? String(decodedPath.dropFirst()) : decodedPath
    if fileName.isEmpty || fileName.hasSuffix("/") {
      fileName += indexFileName
    }
    let segments = fileName.split(separator: "/", omittingEmptySubsequences: false)
    let hasInvalidSegment = segments.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    guard !hasInvalidSegment, !fileName.contains("\\"), !fileName.contains("\0") else {
      return nil
    }
    return fileName
  }

  /// Vite names content-hashed files in `assets/` as `<name>-<8 hash characters>.<extension>`. Other files,
  /// including `index.html` and the workers in the root folder, are revalidated on every load.
  private static func isHashedAsset(_ fileName: String) -> Bool {
    guard fileName.hasPrefix(hashedAssetPrefix) else {
      return false
    }
    let assetName = fileName.dropFirst(hashedAssetPrefix.count)
    guard !assetName.contains("/"), let dotIndex = assetName.lastIndex(of: ".") else {
      return false
    }

    let stem = assetName[..<dotIndex]
    let fileExtension = assetName[assetName.index(after: dotIndex)...]
    // At least one character of the name, the dash and the hash
    guard !fileExtension.isEmpty, stem.count > assetHashLength + 1 else {
      return false
    }
    let hash = stem.suffix(assetHashLength)
    let isHashCharacter: (Character) -> Bool = { character in
      character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "-")
    }
    return stem.dropLast(assetHashLength).last == "-" && hash.allSatisfy(isHashCharacter)
  }
}

/// A single `bytes=` range of a `Range` header. Other forms, such as several ranges, are ignored, as RFC 9110 allows,
/// and the response then carries the whole file.
private enum SchemeByteRange {
  case entire
  case partial(Range<Int>)
  case unsatisfiable

  private static let unitPrefix = "bytes="

  init(header: String?, length: Int) {
    guard let header, header.hasPrefix(Self.unitPrefix), length > 0 else {
      self = .entire
      return
    }
    let spec = header.dropFirst(Self.unitPrefix.count).trimmingCharacters(in: .whitespaces)
    guard !spec.contains(","), let dashIndex = spec.firstIndex(of: "-") else {
      self = .entire
      return
    }
    let firstText = spec[..<dashIndex]
    let lastText = spec[spec.index(after: dashIndex)...]

    // A suffix range such as `bytes=-500` asks for the last bytes
    if firstText.isEmpty {
      guard let suffixLength = Int(lastText), suffixLength >= 0 else {
        self = .entire
        return
      }
      self = suffixLength > 0 ? .partial(max(0, length - suffixLength)..<length) : .unsatisfiable
      return
    }

    guard let first = Int(firstText), first >= 0 else {
      self = .entire
      return
    }
    guard first < length else {
      self = .unsatisfiable
      return
    }
    guard !lastText.isEmpty else {
      self = .partial(first..<length)
      return
    }
    guard let last = Int(lastText), last >= first else {
      self = .entire
      return
    }
    self = .partial(first..<(min(last, length - 1) + 1))
  }
}

private enum SchemeStatus: Int {
  case ok = 200
  case partialContent = 206
  case badRequest = 400
  case notFound = 404
  case methodNotAllowed = 405
  case rangeNotSatisfiable = 416
  case misdirectedRequest = 421

  var reasonPhrase: String {
    switch self {
    case .ok:
      return "OK"
    case .partialContent:
      return "Partial Content"
    case .badRequest:
      return "Bad Request"
    case .notFound:
      return "Not Found"
    case .methodNotAllowed:
      return "Method Not Allowed"
    case .rangeNotSatisfiable:
      return "Range Not Satisfiable"
    case .misdirectedRequest:
      return "Misdirected Request"
    }
  }
}
