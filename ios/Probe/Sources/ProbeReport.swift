import Foundation

/// One result of the probe, reported by a page or by the native side. Names that start with `info-` describe the
/// environment; the others are capabilities the web app needs.
struct ProbeCheck: Encodable {
  let name: String
  let ok: Bool
  let detail: String
}

/// Something a page or WebKit reported while a scenario ran, such as a console error or a frame navigation
struct ProbeEvent: Encodable {
  let time: Double
  let kind: String
  let text: String
}

/// One page loaded over one origin. Used on the main queue only.
final class ScenarioRecord: Encodable {
  let name: String
  let origin: String
  let url: String
  let startedAt: Double
  var finishedAt: Double?
  var status = "running"
  var checks: [ProbeCheck] = []
  var events: [ProbeEvent] = []
  var snapshot: String?
  var hasMessageOrigin = false

  init(name: String, origin: String, url: String, startedAt: Double) {
    self.name = name
    self.origin = origin
    self.url = url
    self.startedAt = startedAt
  }
}

/// A request that WebKit sent to the scheme handler and how the handler answered it. Used on the main queue only.
final class SchemeRequestRecord: Encodable {
  let scenario: String
  let url: String
  let method: String
  let range: String?
  let startedAt: Double
  var status: Int?
  var contentType: String?
  var contentLength: String?
  var contentRange: String?
  var receivedBytes = 0
  var outcome = "pending"
  var finishedAt: Double?

  init(scenario: String, url: String, method: String, range: String?, startedAt: Double) {
    self.scenario = scenario
    self.url = url
    self.method = method
    self.range = range
    self.startedAt = startedAt
  }
}

/// A website data record of the default data store, as Settings-like UIs would list it
struct DataRecordInfo: Encodable {
  let displayName: String
  let dataTypes: [String]
}

struct ProbeReport: Encodable {
  let phase: String
  let runId: String
  let systemName: String
  let systemVersion: String
  let model: String
  let userAgent: String
  /// Must be false: WebKit refuses a handler for a scheme it handles itself
  let isSchemeHandledByWebKit: Bool
  let startedAt: String
  let finishedAt: String
  let scenarios: [ScenarioRecord]
  let schemeRequests: [SchemeRequestRecord]
  let dataRecords: [DataRecordInfo]
}
