import Foundation
import WebKit

/// Passes every task to `AppSchemeHandler` through a proxy that records the request and the answer, so the report
/// shows which range requests WebKit sent for media and how they were answered. Used on the main queue only, like
/// the handler it wraps.
final class RecordingSchemeHandler: NSObject {
  var scenarioName = ""
  private(set) var records: [SchemeRequestRecord] = []
  private let base: AppSchemeHandler
  private let startDate: Date
  private var proxies: [ObjectIdentifier: RecordingTask] = [:]

  init(base: AppSchemeHandler, startDate: Date) {
    self.base = base
    self.startDate = startDate
    super.init()
  }

  fileprivate var elapsed: Double {
    Date().timeIntervalSince(startDate)
  }

  fileprivate func forget(_ proxy: RecordingTask) {
    proxies.removeValue(forKey: proxy.baseIdentifier)
  }
}

extension RecordingSchemeHandler: WKURLSchemeHandler {
  func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    let request = urlSchemeTask.request
    let record = SchemeRequestRecord(
      scenario: scenarioName,
      url: request.url?.absoluteString ?? "",
      method: request.httpMethod ?? "GET",
      range: request.value(forHTTPHeaderField: "Range"),
      startedAt: elapsed
    )
    records.append(record)
    let proxy = RecordingTask(base: urlSchemeTask, record: record, owner: self)
    proxies[proxy.baseIdentifier] = proxy
    base.webView(webView, start: proxy)
  }

  func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    guard let proxy = proxies.removeValue(forKey: ObjectIdentifier(urlSchemeTask)) else {
      return
    }
    proxy.record.outcome = "stopped by WebKit"
    proxy.record.finishedAt = elapsed
    base.webView(webView, stop: proxy)
  }
}

/// Forwards the calls of `AppSchemeHandler` to WebKit's task and records them
final class RecordingTask: NSObject, WKURLSchemeTask {
  let record: SchemeRequestRecord
  let baseIdentifier: ObjectIdentifier
  private let base: WKURLSchemeTask
  private weak var owner: RecordingSchemeHandler?

  init(base: WKURLSchemeTask, record: SchemeRequestRecord, owner: RecordingSchemeHandler) {
    self.base = base
    self.record = record
    self.owner = owner
    baseIdentifier = ObjectIdentifier(base)
    super.init()
  }

  var request: URLRequest {
    base.request
  }

  func didReceive(_ response: URLResponse) {
    if let response = response as? HTTPURLResponse {
      record.status = response.statusCode
      record.contentType = response.value(forHTTPHeaderField: "Content-Type")
      record.contentLength = response.value(forHTTPHeaderField: "Content-Length")
      record.contentRange = response.value(forHTTPHeaderField: "Content-Range")
    }
    base.didReceive(response)
  }

  func didReceive(_ data: Data) {
    record.receivedBytes += data.count
    base.didReceive(data)
  }

  func didFinish() {
    record.outcome = "finished"
    end()
    base.didFinish()
  }

  func didFailWithError(_ error: Error) {
    record.outcome = "failed: \(error.localizedDescription)"
    end()
    base.didFailWithError(error)
  }

  private func end() {
    record.finishedAt = owner?.elapsed
    owner?.forget(self)
  }
}
