import Darwin
import Foundation
import UsageMeterCore

@main
enum UsageMeterProbe {
    static func main() async {
        guard
            CommandLine.arguments.count == 2,
            let provider = Provider(rawValue: CommandLine.arguments[1])
        else {
            writeError("usage: UsageMeterProbe <claude|codex|kimi>")
            Darwin.exit(EX_USAGE)
        }

        do {
            switch provider {
            case .claude:
                try await runClaude()
            case .codex, .kimi:
                writeError(
                    "\(provider.rawValue) qualification is not implemented in this build."
                )
                Darwin.exit(EX_UNAVAILABLE)
            }
        } catch {
            writeError(
                "\(provider.rawValue) qualification failed: \(safeDescription(of: error))"
            )
            Darwin.exit(EX_UNAVAILABLE)
        }
    }

    private static func runClaude() async throws {
        guard
            let token = ProcessInfo.processInfo.environment[
                "CLAUDE_CODE_OAUTH_TOKEN"
            ],
            !token.isEmpty
        else {
            writeError(
                "set CLAUDE_CODE_OAUTH_TOKEN to a token created by `claude setup-token`"
            )
            Darwin.exit(EX_CONFIG)
        }

        let snapshot = try await ClaudeUsageClient().fetchUsage(
            accountID: UUID(),
            credential: .claude(token: token),
            now: Date()
        )
        let output = ProbeOutput(
            provider: .claude,
            identity: nil,
            snapshot: snapshot
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func safeDescription(of error: any Error) -> String {
        guard let error = error as? ProviderClientError else {
            return "transport failure"
        }

        switch error {
        case .credentialMismatch:
            return "credential mismatch"
        case .unsupportedResponse:
            return "unsupported response shape"
        case .reauthenticationRequired:
            return "reauthentication required"
        case let .retryAfter(date):
            guard let date else {
                return "rate limited"
            }
            return "rate limited until \(date.formatted(.iso8601))"
        case .temporaryFailure:
            return "temporary provider failure"
        }
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
