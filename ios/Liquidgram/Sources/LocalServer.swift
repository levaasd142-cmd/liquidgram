import Foundation
import Network
import os

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "LocalServer")

/// Serves the bundled web build on `http://127.0.0.1:47821/`. All user data lives in storage owned by this
/// origin, so the address never changes. The listener is bound to the loopback address, so only processes on
/// the device can connect, and every request runs on one serial queue.
final class LocalServer {
  static let host = "127.0.0.1"
  static let port: NWEndpoint.Port = 47821
  static let appURL = URL(string: "http://\(host):\(port.rawValue)/")!
  static let bundledWebRoot = Bundle.main.bundleURL.appendingPathComponent("WebApp", isDirectory: true)

  private static let initialRestartDelay: TimeInterval = 0.5
  private static let maxRestartDelay: TimeInterval = 8
  private static let requestTimeout: TimeInterval = 30
  private static let receiveLength = 64 * 1024
  private static let maxRequestHeadLength = 32 * 1024
  private static let requestHeadTerminator = Data("\r\n\r\n".utf8)

  private let queue = DispatchQueue(label: "org.liquidgram.messenger.local-server")
  private let responder: FileResponder
  private var listener: NWListener?
  private var lastError: String?
  private var readyCallbacks: [() -> Void] = []
  private var restartDelay = LocalServer.initialRestartDelay
  private var isRestartScheduled = false

  init(webRoot: URL = LocalServer.bundledWebRoot) {
    let portText = String(Self.port.rawValue)
    responder = FileResponder(
      webRoot: webRoot.standardizedFileURL,
      allowedHosts: ["\(Self.host):\(portText)", "localhost:\(portText)"]
    )
  }

  /// Whether a URL or a security origin with these parts belongs to the app's own pages
  static func isAppOrigin(scheme: String?, host: String?, port: Int?) -> Bool {
    scheme?.lowercased() == "http" && host == Self.host && port == Int(Self.port.rawValue)
  }

  static func isAppURL(_ url: URL) -> Bool {
    isAppOrigin(scheme: url.scheme, host: url.host, port: url.port)
  }

  /// Starts listening unless a listener is starting or running, so it is safe to call at any time. iOS may
  /// reclaim the listening socket while the app is suspended (TN2277); calling this when the app becomes
  /// active again replaces a listener that failed or was cancelled with a new one on the same port.
  func start() {
    queue.async {
      self.startIfNeeded()
    }
  }

  /// Calls `callback` on the main queue once the server accepts connections, starting it if needed
  func whenReady(_ callback: @escaping () -> Void) {
    queue.async {
      if self.listener?.state == .ready {
        DispatchQueue.main.async {
          callback()
        }
        return
      }
      self.readyCallbacks.append(callback)
      self.startIfNeeded()
    }
  }

  /// Calls `completion` on the main queue with the last error while the server is not ready, else `nil`
  func fetchFailure(_ completion: @escaping (String?) -> Void) {
    queue.async {
      let failure = self.listener?.state == .ready ? nil : self.lastError
      DispatchQueue.main.async {
        completion(failure)
      }
    }
  }

  private func startIfNeeded() {
    if let listener {
      switch listener.state {
      case .failed, .cancelled:
        // The state handler has not run yet, so the listener is replaced here
        self.listener = nil
        listener.cancel()
      default:
        return
      }
    }
    startListener()
  }

  private func startListener() {
    let parameters = NWParameters.tcp
    // Binding to 127.0.0.1 keeps the server off every other interface
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: Self.port)
    // A new listener can take the port while sockets of closed connections are still in TIME_WAIT
    parameters.allowLocalEndpointReuse = true

    let listener: NWListener
    do {
      listener = try NWListener(using: parameters)
    } catch {
      recordFailure(String(describing: error))
      return
    }

    listener.stateUpdateHandler = { [weak self, weak listener] state in
      guard let self, let listener else {
        return
      }
      self.handle(state, of: listener)
    }
    listener.newConnectionHandler = { [weak self] connection in
      guard let self else {
        connection.cancel()
        return
      }
      self.serve(connection)
    }
    self.listener = listener
    listener.start(queue: queue)
  }

  private func handle(_ state: NWListener.State, of listener: NWListener) {
    // A replaced listener may still report its own cancellation
    guard listener === self.listener else {
      return
    }

    switch state {
    case .ready:
      logger.info("Serving the web app at \(Self.appURL.absoluteString, privacy: .public)")
      lastError = nil
      restartDelay = Self.initialRestartDelay
      let callbacks = readyCallbacks
      readyCallbacks.removeAll()
      for callback in callbacks {
        DispatchQueue.main.async {
          callback()
        }
      }
    case .waiting(let error), .failed(let error):
      // An address in use is reported as `waiting`; both states need a new listener
      self.listener = nil
      listener.cancel()
      recordFailure(String(describing: error))
    case .cancelled:
      self.listener = nil
    case .setup:
      break
    @unknown default:
      break
    }
  }

  private func recordFailure(_ description: String) {
    logger.error("The local server stopped: \(description, privacy: .public)")
    lastError = description
    scheduleRestart()
  }

  private func scheduleRestart() {
    guard !isRestartScheduled else {
      return
    }
    isRestartScheduled = true
    let delay = restartDelay
    restartDelay = min(restartDelay * 2, Self.maxRestartDelay)
    queue.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self else {
        return
      }
      self.isRestartScheduled = false
      self.startIfNeeded()
    }
  }

  private func serve(_ connection: NWConnection) {
    let request = PendingRequest()
    connection.stateUpdateHandler = { [weak connection] state in
      if case .failed = state {
        connection?.cancel()
      }
    }
    connection.start(queue: queue)
    receiveRequestHead(on: connection, into: request)

    // A client that never completes its request must not hold the connection open
    queue.asyncAfter(deadline: .now() + Self.requestTimeout) { [weak connection] in
      if !request.isComplete {
        connection?.cancel()
      }
    }
  }

  private func receiveRequestHead(on connection: NWConnection, into request: PendingRequest) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: Self.receiveLength) {
      [weak self] content, _, isComplete, error in
      guard let self else {
        connection.cancel()
        return
      }
      if let content {
        request.buffer.append(content)
      }

      if let headEnd = request.buffer.range(of: Self.requestHeadTerminator) {
        let head = request.buffer.subdata(in: request.buffer.startIndex..<headEnd.lowerBound)
        request.complete()
        self.send(self.responder.makeResponse(forRequestHead: head), on: connection)
      } else if request.buffer.count > Self.maxRequestHeadLength {
        request.complete()
        self.send(.error(.requestHeaderFieldsTooLarge), on: connection)
      } else if error != nil || isComplete {
        connection.cancel()
      } else {
        self.receiveRequestHead(on: connection, into: request)
      }
    }
  }

  /// Sends the response as the final message, which closes the write side as `Connection: close` announces
  private func send(_ response: HTTPResponse, on connection: NWConnection) {
    connection.send(
      content: response.serialize(),
      contentContext: .finalMessage,
      isComplete: true,
      completion: .contentProcessed { error in
        if let error {
          logger.debug("Could not send a response: \(String(describing: error), privacy: .public)")
        }
        connection.cancel()
      }
    )
  }
}

/// The part of a request read so far. Reads and the timeout run on the server queue.
private final class PendingRequest {
  var buffer = Data()
  private(set) var isComplete = false

  /// Marks the head as read and frees the buffer, since the timeout keeps this object for a while
  func complete() {
    isComplete = true
    buffer = Data()
  }
}

/// Answers requests with files of the web build
private struct FileResponder {
  private static let indexFileName = "index.html"
  private static let defaultContentType = "application/octet-stream"
  private static let immutableCacheControl = "public, max-age=31536000, immutable"
  private static let revalidateCacheControl = "no-cache"
  private static let hashedAssetPrefix = "assets/"
  private static let assetHashLength = 8

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
  let allowedHosts: Set<String>

  func makeResponse(forRequestHead head: Data) -> HTTPResponse {
    guard let request = HTTPRequestHead(head) else {
      return .error(.badRequest)
    }
    // Any other host name means DNS rebinding or a request that was not meant for this server
    guard let host = request.headers["host"], allowedHosts.contains(host.lowercased()) else {
      return .error(.misdirectedRequest)
    }
    guard request.method == "GET" || request.method == "HEAD" else {
      var response = HTTPResponse.error(.methodNotAllowed)
      response.headers.append((name: "Allow", value: "GET, HEAD"))
      return response
    }
    guard let fileName = Self.resolveFileName(request.target) else {
      return .error(.badRequest)
    }

    var response = makeFileResponse(fileName: fileName, rangeHeader: request.headers["range"])
    response.omitsBody = request.method == "HEAD"
    return response
  }

  private func makeFileResponse(fileName: String, rangeHeader: String?) -> HTTPResponse {
    let fileURL = webRoot.appendingPathComponent(fileName, isDirectory: false)
    // `resolveFileName` already keeps requests inside the build; this guards against mistakes in it
    guard fileURL.standardizedFileURL.path.hasPrefix(webRoot.path + "/"),
          let content = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
      return .error(.notFound)
    }

    let contentType = Self.contentTypes[fileURL.pathExtension.lowercased()] ?? Self.defaultContentType
    let cacheControl = Self.isHashedAsset(fileName) ? Self.immutableCacheControl : Self.revalidateCacheControl
    var response = HTTPResponse(
      status: .ok,
      headers: [
        (name: "Content-Type", value: contentType),
        (name: "Cache-Control", value: cacheControl),
        (name: "Accept-Ranges", value: "bytes"),
      ],
      body: content
    )

    // WebKit plays audio and video only from servers that answer range requests
    switch ByteRange(header: rangeHeader, length: content.count) {
    case .entire:
      break
    case .partial(let range):
      response.status = .partialContent
      response.body = content.subdata(in: range)
      response.headers.append(
        (name: "Content-Range", value: "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(content.count)")
      )
    case .unsatisfiable:
      var errorResponse = HTTPResponse.error(.rangeNotSatisfiable)
      errorResponse.headers.append((name: "Content-Range", value: "bytes */\(content.count)"))
      return errorResponse
    }
    return response
  }

  /// Maps a request target to a file of the web build. Dot segments, empty segments, backslashes and NUL
  /// characters are refused instead of being normalized, so no request reaches outside the build.
  private static func resolveFileName(_ target: String) -> String? {
    let path = String(target.prefix(while: { $0 != "?" && $0 != "#" }))
    guard path.hasPrefix("/"), let decodedPath = path.removingPercentEncoding else {
      return nil
    }

    var fileName = String(decodedPath.dropFirst())
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

/// The request line and headers of an HTTP/1.x request
private struct HTTPRequestHead {
  let method: String
  let target: String
  /// Header values by lowercased name
  let headers: [String: String]

  init?(_ data: Data) {
    let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n")
    let requestLine = lines[0].split(separator: " ", omittingEmptySubsequences: false)
    guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else {
      return nil
    }

    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let colonIndex = line.firstIndex(of: ":") else {
        continue
      }
      let name = line[..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
      headers[name] = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
    }

    method = String(requestLine[0])
    target = String(requestLine[1])
    self.headers = headers
  }
}

/// A single `bytes=` range of a `Range` header. Other forms, such as several ranges, are ignored, as RFC 9110
/// allows, and the response then carries the whole file.
private enum ByteRange {
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

private enum HTTPStatus: Int {
  case ok = 200
  case partialContent = 206
  case badRequest = 400
  case notFound = 404
  case methodNotAllowed = 405
  case rangeNotSatisfiable = 416
  case misdirectedRequest = 421
  case requestHeaderFieldsTooLarge = 431

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
    case .requestHeaderFieldsTooLarge:
      return "Request Header Fields Too Large"
    }
  }
}

private struct HTTPResponse {
  var status: HTTPStatus
  var headers: [(name: String, value: String)]
  var body: Data
  /// A response to `HEAD` carries the headers of the `GET` response, including its length, without the body
  var omitsBody = false

  static func error(_ status: HTTPStatus) -> HTTPResponse {
    HTTPResponse(
      status: status,
      headers: [
        (name: "Content-Type", value: "text/plain; charset=utf-8"),
        (name: "Cache-Control", value: "no-store"),
      ],
      body: Data(status.reasonPhrase.utf8)
    )
  }

  func serialize() -> Data {
    var head = "HTTP/1.1 \(status.rawValue) \(status.reasonPhrase)\r\n"
    let allHeaders = headers + [
      (name: "Content-Length", value: String(body.count)),
      (name: "X-Content-Type-Options", value: "nosniff"),
      (name: "Connection", value: "close"),
    ]
    for header in allHeaders {
      head += "\(header.name): \(header.value)\r\n"
    }
    head += "\r\n"

    var data = Data(head.utf8)
    if !omitsBody {
      data.append(body)
    }
    return data
  }
}
