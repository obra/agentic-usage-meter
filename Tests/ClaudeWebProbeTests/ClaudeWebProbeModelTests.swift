import Foundation
import Testing
import UsageMeterClaudeWeb
import UsageMeterCore
import WebKit

@testable import ClaudeWebProbe

@Suite
struct ClaudeWebProbeModelTests {
  @Test
  func parsesLoginAndDeleteCommandsWithProfileIDs() throws {
    let profileID = UUID()

    #expect(
      try ClaudeWebProbeCommand.parse(
        arguments: ["ClaudeWebProbe", "login", profileID.uuidString]
      ) == .login(profileID)
    )
    #expect(
      try ClaudeWebProbeCommand.parse(
        arguments: ["ClaudeWebProbe", "delete", profileID.uuidString]
      ) == .delete(profileID)
    )
  }

  @Test
  func rejectsInvalidCommandsWithoutInterpretingThem() {
    #expect(throws: ClaudeWebProbeCommandError.invalidArguments) {
      _ = try ClaudeWebProbeCommand.parse(
        arguments: ["ClaudeWebProbe", "login", "not-a-uuid"]
      )
    }
    #expect(throws: ClaudeWebProbeCommandError.invalidArguments) {
      _ = try ClaudeWebProbeCommand.parse(
        arguments: ["ClaudeWebProbe", "unknown", UUID().uuidString]
      )
    }
  }

  @Test
  func outputContainsOnlyLocalProfileAndNormalizedUsage() throws {
    let profileID = UUID()
    let resetAt = Date(timeIntervalSince1970: 2_000_000_000)
    let snapshot = UsageSnapshot(
      accountID: UUID(),
      fetchedAt: resetAt.addingTimeInterval(-60),
      windows: [
        try #require(
          UsageWindow(
            id: "provider-specific-id",
            kind: .short,
            duration: 18_000,
            resetAt: resetAt,
            consumedFraction: 0.42
          )
        )
      ]
    )

    let output = ClaudeWebProbeOutput(
      profileID: profileID,
      organizationCount: 2,
      snapshot: snapshot
    )

    #expect(output.profileID == profileID)
    #expect(output.organizationCount == 2)
    #expect(
      output.windows == [
        ClaudeWebProbeWindow(
          kind: .short,
          duration: 18_000,
          consumedFraction: 0.42,
          resetAt: resetAt,
          label: nil
        )
      ]
    )
  }

  @Test
  func outputPreservesMissingProviderReset() throws {
    let profileID = UUID()
    let snapshot = UsageSnapshot(
      accountID: UUID(),
      fetchedAt: Date(timeIntervalSince1970: 2_000_000_000),
      windows: [
        try #require(
          UsageWindow(
            id: "inactive",
            kind: .short,
            duration: 18_000,
            resetAt: nil,
            consumedFraction: 0,
          ),
        )
      ],
    )

    let output = ClaudeWebProbeOutput(
      profileID: profileID,
      organizationCount: 1,
      snapshot: snapshot,
    )

    #expect(output.windows.first?.resetAt == nil)
  }

  @Test
  func outputPreservesScopedWindowLabel() throws {
    let resetAt = Date(timeIntervalSince1970: 2_000_000_000)
    let window = try #require(
      UsageWindow(
        id: "claude-weekly-scoped-6e616d653a4661626c65",
        kind: .weekly,
        duration: 604_800,
        resetAt: resetAt,
        consumedFraction: 0.42,
        label: "Fable",
      ),
    )
    let output = ClaudeWebProbeOutput(
      profileID: UUID(),
      organizationCount: 1,
      snapshot: UsageSnapshot(
        accountID: UUID(),
        fetchedAt: resetAt.addingTimeInterval(-60),
        windows: [window],
      ),
    )

    #expect(output.windows.first?.label == "Fable")
  }

  @Test
  func trackerCompatibleSelectionDoesNotAskBetweenDuplicateNames() {
    let first = ClaudeOrganization(
      id: UUID(),
      name: "Duplicate",
      capabilities: ["chat", "claude_max"]
    )
    let second = ClaudeOrganization(
      id: UUID(),
      name: "Duplicate",
      capabilities: ["chat"]
    )

    #expect(
      ClaudeWebProbeOrganizationSelection.candidate(
        from: [first, second]
      ) == first
    )
  }

  @MainActor
  @Test
  func loginPresentationWaitsForTheFirstRenderedPage() {
    let model = ClaudeWebProbeModel(profileID: UUID()) { _ in }

    #expect(!model.hasRenderedLoginPage)
    model.loginPageDidFinish()
    #expect(model.hasRenderedLoginPage)
  }

  @MainActor
  @Test
  func deleteCommandRemovesAStoreFromAColdProcess() async throws {
    let profileID = UUID()
    var store: WKWebsiteDataStore? = WKWebsiteDataStore(
      forIdentifier: profileID
    )
    #expect(store?.identifier == profileID)
    store = nil

    let probeURL = URL(
      filePath: FileManager.default.currentDirectoryPath,
      directoryHint: .isDirectory
    )
    .appending(
      path: ".build/debug/ClaudeWebProbe",
      directoryHint: .notDirectory
    )
    let process = Process()
    process.executableURL = probeURL
    process.arguments = ["delete", profileID.uuidString]
    try process.run()
    process.waitUntilExit()

    #expect(process.terminationReason == .exit)
    #expect(process.terminationStatus == 0)
  }
}
