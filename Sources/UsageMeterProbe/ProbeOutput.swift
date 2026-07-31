import Foundation
import UsageMeterCore

struct ProbeOutput: Codable, Equatable {
  let provider: Provider
  let accountID: UUID
  let identity: String?
  let windows: [ProbeWindow]

  init(
    provider: Provider,
    identity: String?,
    snapshot: UsageSnapshot
  ) {
    self.provider = provider
    accountID = snapshot.accountID
    self.identity = identity
    windows = snapshot.windows.map(ProbeWindow.init)
  }
}

struct ProbeWindow: Codable, Equatable {
  let kind: UsageWindowKind
  let durationSeconds: Int
  let consumedPercent: Int
  let remainingFraction: Double
  let resetAt: Date?

  init(window: UsageWindow) {
    kind = window.kind
    durationSeconds = Int(window.duration.rounded())
    consumedPercent = Int((window.consumedFraction * 100).rounded())
    remainingFraction = window.remainingFraction
    resetAt = window.resetAt
  }
}
