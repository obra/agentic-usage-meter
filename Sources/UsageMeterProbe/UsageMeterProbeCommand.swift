import Foundation

enum UsageMeterProbeCommand: Equatable {
    case claude
    case codexLogin(UUID)
    case codexFetch(UUID)
    case codexRefresh(UUID)
    case codexDelete(UUID)
    case kimi

    static func parse(arguments: [String]) throws -> Self {
        if arguments.count == 2 {
            switch arguments[1] {
            case "claude":
                return .claude
            case "kimi":
                return .kimi
            default:
                throw UsageMeterProbeCommandError.invalidArguments
            }
        }

        guard
            arguments.count == 3,
            let accountID = UUID(uuidString: arguments[2])
        else {
            throw UsageMeterProbeCommandError.invalidArguments
        }

        switch arguments[1] {
        case "codex-login":
            return .codexLogin(accountID)
        case "codex-fetch":
            return .codexFetch(accountID)
        case "codex-refresh":
            return .codexRefresh(accountID)
        case "codex-delete":
            return .codexDelete(accountID)
        default:
            throw UsageMeterProbeCommandError.invalidArguments
        }
    }
}

enum UsageMeterProbeCommandError: Error, Equatable {
    case invalidArguments
}
