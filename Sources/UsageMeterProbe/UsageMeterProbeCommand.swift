import Foundation

enum UsageMeterProbeCommand: Equatable {
  case claude
  case codexLogin(UUID)
  case codexFetch(UUID)
  case codexRefresh(UUID)
  case codexDelete(UUID)
  case kimiLogin(UUID)
  case kimiFetch(UUID)
  case kimiRefresh(UUID)
  case kimiDelete(UUID)
  case minimaxLogin(UUID)
  case minimaxFetch(UUID)
  case minimaxDelete(UUID)

  static func parse(arguments: [String]) throws -> Self {
    if arguments.count == 2 {
      switch arguments[1] {
      case "claude":
        return .claude
      default:
        throw UsageMeterProbeCommandError.invalidArguments
      }
    }

    if
      arguments.count == 5,
      arguments[1] == "minimax",
      arguments[3] == "--account-id",
      let accountID = UUID(uuidString: arguments[4])
    {
      return switch arguments[2] {
      case "login":
        .minimaxLogin(accountID)
      case "usage":
        .minimaxFetch(accountID)
      case "delete":
        .minimaxDelete(accountID)
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
    case "kimi-login":
      return .kimiLogin(accountID)
    case "kimi-fetch":
      return .kimiFetch(accountID)
    case "kimi-refresh":
      return .kimiRefresh(accountID)
    case "kimi-delete":
      return .kimiDelete(accountID)
    default:
      throw UsageMeterProbeCommandError.invalidArguments
    }
  }
}

enum UsageMeterProbeCommandError: Error, Equatable {
  case invalidArguments
}
