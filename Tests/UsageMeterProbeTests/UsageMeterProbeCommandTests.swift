import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterProbe

@Suite
struct UsageMeterProbeCommandTests {
  private let accountID = UUID(
    uuidString: "11111111-2222-3333-4444-555555555555"
  )!

  @Test
  func parsesProviderAndAccountCommands() throws {
    #expect(
      try UsageMeterProbeCommand.parse(
        arguments: ["probe", "claude"]
      ) == .claude
    )
    #expect(
      try UsageMeterProbeCommand.parse(
        arguments: [
          "probe",
          "codex-login",
          accountID.uuidString,
        ]
      ) == .codexLogin(accountID)
    )
    #expect(
      try UsageMeterProbeCommand.parse(
        arguments: [
          "probe",
          "codex-fetch",
          accountID.uuidString,
        ]
      ) == .codexFetch(accountID)
    )
    #expect(
      try UsageMeterProbeCommand.parse(
        arguments: [
          "probe",
          "codex-refresh",
          accountID.uuidString,
        ]
      ) == .codexRefresh(accountID)
    )
    #expect(
      try UsageMeterProbeCommand.parse(
        arguments: [
          "probe",
          "codex-delete",
          accountID.uuidString,
        ]
      ) == .codexDelete(accountID)
    )
    #expect(
      try UsageMeterProbeCommand.parse(
        arguments: [
          "probe",
          "kimi-login",
          accountID.uuidString,
        ]
      ) == .kimiLogin(accountID)
    )
    #expect(
      try UsageMeterProbeCommand.parse(
        arguments: [
          "probe",
          "kimi-fetch",
          accountID.uuidString,
        ]
      ) == .kimiFetch(accountID)
    )
    #expect(
      try UsageMeterProbeCommand.parse(
        arguments: [
          "probe",
          "kimi-refresh",
          accountID.uuidString,
        ]
      ) == .kimiRefresh(accountID)
    )
    #expect(
      try UsageMeterProbeCommand.parse(
        arguments: [
          "probe",
          "kimi-delete",
          accountID.uuidString,
        ]
      ) == .kimiDelete(accountID)
    )
    #expect(
      try UsageMeterProbeCommand.parse(
        arguments: [
          "probe",
          "minimax",
          "login",
          "--account-id",
          accountID.uuidString,
        ]
      ) == .minimaxLogin(accountID)
    )
    #expect(
      try UsageMeterProbeCommand.parse(
        arguments: [
          "probe",
          "minimax",
          "usage",
          "--account-id",
          accountID.uuidString,
        ]
      ) == .minimaxFetch(accountID)
    )
    #expect(
      try UsageMeterProbeCommand.parse(
        arguments: [
          "probe",
          "minimax",
          "delete",
          "--account-id",
          accountID.uuidString,
        ]
      ) == .minimaxDelete(accountID)
    )
  }

  @Test
  func rejectsUnknownCommandsAndMalformedAccountIDs() {
    #expect(throws: UsageMeterProbeCommandError.invalidArguments) {
      _ = try UsageMeterProbeCommand.parse(
        arguments: ["probe", "codex-login", "not-a-uuid"]
      )
    }
    #expect(throws: UsageMeterProbeCommandError.invalidArguments) {
      _ = try UsageMeterProbeCommand.parse(
        arguments: ["probe", "unknown"]
      )
    }
  }

  @Test
  func minimaxOutputContainsOnlySanitizedUsage() throws {
    let snapshot = UsageSnapshot(
      accountID: accountID,
      fetchedAt: Date(
        timeIntervalSince1970: 2_000_000_000
      ),
      windows: [
        UsageWindow(
          id: "minimax-short",
          kind: .short,
          duration: 18_000,
          resetAt: Date(
            timeIntervalSince1970: 2_000_003_600
          ),
          consumedFraction: 0.4
        )!
      ]
    )
    let output = ProbeOutput(
      provider: .minimax,
      identity: nil,
      snapshot: snapshot
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let text = String(
      decoding: try encoder.encode(output),
      as: UTF8.self
    )

    #expect(text.contains(accountID.uuidString.lowercased()))
    #expect(text.contains("\"kind\":\"short\""))
    #expect(text.contains("\"remainingFraction\":0.6"))
    #expect(!text.contains("secret-api-key"))
    #expect(!text.localizedCaseInsensitiveContains("authorization"))
    #expect(!text.contains("person@example.com"))
    #expect(!text.localizedCaseInsensitiveContains("raw"))
  }

  @Test
  func sanitizedOutputPreservesMissingProviderReset() throws {
    let snapshot = UsageSnapshot(
      accountID: accountID,
      fetchedAt: Date(timeIntervalSince1970: 2_000_000_000),
      windows: [
        try #require(
          UsageWindow(
            id: "inactive",
            kind: .short,
            duration: 18_000,
            resetAt: nil,
            consumedFraction: 0
          )
        )
      ]
    )

    let output = ProbeOutput(
      provider: .factory,
      identity: nil,
      snapshot: snapshot
    )

    #expect(output.windows.first?.resetAt == nil)
  }

  @Test
  func sanitizedOutputPreservesScopedWindowLabel() throws {
    let window = try #require(
      UsageWindow(
        id: "claude-weekly-scoped-6e616d653a4661626c65",
        kind: .weekly,
        duration: 604_800,
        resetAt: Date(timeIntervalSince1970: 2_000_000_000),
        consumedFraction: 0.42,
        label: "Fable",
      ),
    )
    let output = ProbeOutput(
      provider: .claude,
      identity: nil,
      snapshot: UsageSnapshot(
        accountID: accountID,
        fetchedAt: Date(timeIntervalSince1970: 1_999_999_000),
        windows: [window],
      ),
    )

    #expect(output.windows == [ProbeWindow(window: window)])
  }
}
