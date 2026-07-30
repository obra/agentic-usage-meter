import Foundation
import Testing
@testable import UsageMeterProbe

@Suite
struct UsageMeterProbeCommandTests {
    private let accountID = UUID(
        uuidString: "11111111-2222-3333-4444-555555555555"
    )!

    @Test
    func parsesProviderAndCodexAccountCommands() throws {
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
                    accountID.uuidString
                ]
            ) == .codexLogin(accountID)
        )
        #expect(
            try UsageMeterProbeCommand.parse(
                arguments: [
                    "probe",
                    "codex-fetch",
                    accountID.uuidString
                ]
            ) == .codexFetch(accountID)
        )
        #expect(
            try UsageMeterProbeCommand.parse(
                arguments: [
                    "probe",
                    "codex-refresh",
                    accountID.uuidString
                ]
            ) == .codexRefresh(accountID)
        )
        #expect(
            try UsageMeterProbeCommand.parse(
                arguments: [
                    "probe",
                    "codex-delete",
                    accountID.uuidString
                ]
            ) == .codexDelete(accountID)
        )
        #expect(
            try UsageMeterProbeCommand.parse(
                arguments: ["probe", "kimi"]
            ) == .kimi
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
}
