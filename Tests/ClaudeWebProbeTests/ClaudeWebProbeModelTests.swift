import Foundation
import Testing
@testable import ClaudeWebProbe
import UsageMeterClaudeWeb
import UsageMeterCore
import WebKit

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
                    resetAt: resetAt
                )
            ]
        )
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
