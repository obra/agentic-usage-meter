import Darwin
import Foundation
import UsageMeterCore

@main
enum UsageMeterProbe {
  private static let credentialStore = KeychainCredentialStore(
    service: "com.jesse.agentic-usage-meter.probe.credentials"
  )

  static func main() async {
    do {
      let command = try UsageMeterProbeCommand.parse(
        arguments: CommandLine.arguments
      )
      switch command {
      case .claude:
        try await runClaude()
      case let .codexLogin(accountID):
        try await runCodexLogin(accountID: accountID)
      case let .codexFetch(accountID):
        try await runCodexFetch(accountID: accountID)
      case let .codexRefresh(accountID):
        try await runCodexRefresh(accountID: accountID)
      case let .codexDelete(accountID):
        try await credentialStore.delete(for: accountID)
      case let .kimiLogin(accountID):
        try await runKimiLogin(accountID: accountID)
      case let .kimiFetch(accountID):
        try await runKimiFetch(accountID: accountID)
      case let .kimiRefresh(accountID):
        try await runKimiRefresh(accountID: accountID)
      case let .kimiDelete(accountID):
        try await credentialStore.delete(for: accountID)
      case let .minimaxLogin(accountID):
        try await runMiniMaxLogin(accountID: accountID)
      case let .minimaxFetch(accountID):
        try await runMiniMaxFetch(accountID: accountID)
      case let .minimaxDelete(accountID):
        try await credentialStore.delete(for: accountID)
      }
    } catch UsageMeterProbeCommandError.invalidArguments {
      writeError(
        """
        usage:
          UsageMeterProbe claude
          UsageMeterProbe codex-login <account-uuid>
          UsageMeterProbe codex-fetch <account-uuid>
          UsageMeterProbe codex-refresh <account-uuid>
          UsageMeterProbe codex-delete <account-uuid>
          UsageMeterProbe kimi-login <account-uuid>
          UsageMeterProbe kimi-fetch <account-uuid>
          UsageMeterProbe kimi-refresh <account-uuid>
          UsageMeterProbe kimi-delete <account-uuid>
          UsageMeterProbe minimax login --account-id <account-uuid>
          UsageMeterProbe minimax usage --account-id <account-uuid>
          UsageMeterProbe minimax delete --account-id <account-uuid>
        """
      )
      Darwin.exit(EX_USAGE)
    } catch {
      writeError(
        "qualification failed: \(safeDescription(of: error))"
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
    try write(output)
  }

  private static func runCodexLogin(accountID: UUID) async throws {
    let result = try await CodexOAuthFlow().authenticate()
    guard
      let providerAccountID = result.credential.accountID,
      !providerAccountID.isEmpty
    else {
      throw CodexOAuthFlowError.invalidTokenResponse
    }

    let identity = displayIdentity(result.identity)
    writePrompt(
      "Authenticated Codex account: \(identity). Save and fetch usage? [y/N] "
    )
    guard readLine()?.lowercased() == "y" else {
      writeError("Codex account was not saved.")
      return
    }

    try await credentialStore.save(
      .codex(result.credential),
      for: accountID
    )
    try await fetchCodexUsage(
      accountID: accountID,
      credential: result.credential,
      identity: identity
    )
  }

  private static func runCodexFetch(accountID: UUID) async throws {
    let result = try await storedCodexResult(accountID: accountID)
    try await fetchCodexUsage(
      accountID: accountID,
      credential: result.credential,
      identity: displayIdentity(result.identity)
    )
  }

  private static func runCodexRefresh(accountID: UUID) async throws {
    let current = try await storedCodexResult(accountID: accountID)
    let refreshed = try await CodexOAuthFlow().refresh(current)
    try await credentialStore.save(
      .codex(refreshed.credential),
      for: accountID
    )
    try await fetchCodexUsage(
      accountID: accountID,
      credential: refreshed.credential,
      identity: displayIdentity(refreshed.identity)
    )
  }

  private static func storedCodexResult(
    accountID: UUID
  ) async throws -> CodexOAuthResult {
    guard
      let stored = try await credentialStore.load(for: accountID),
      case let .codex(credential) = stored,
      let idToken = credential.idToken
    else {
      throw CodexOAuthFlowError.reauthenticationRequired
    }

    return CodexOAuthResult(
      credential: credential,
      identity: try CodexOAuthIdentity.decode(from: idToken)
    )
  }

  private static func fetchCodexUsage(
    accountID: UUID,
    credential: OAuthCredential,
    identity: String
  ) async throws {
    let snapshot = try await CodexUsageClient().fetchUsage(
      accountID: accountID,
      credential: .codex(credential),
      now: Date()
    )
    try write(
      ProbeOutput(
        provider: .codex,
        identity: identity,
        snapshot: snapshot
      )
    )
  }

  private static func runKimiLogin(accountID: UUID) async throws {
    let credential = try await KimiOAuthFlow(
      device: kimiDevice(for: accountID)
    ).authenticate()
    writePrompt(
      "Kimi authorization completed. Save and fetch usage? [y/N] "
    )
    guard readLine()?.lowercased() == "y" else {
      writeError("Kimi account was not saved.")
      return
    }

    try await credentialStore.save(
      .kimi(credential),
      for: accountID
    )
    try await fetchKimiUsage(
      accountID: accountID,
      credential: credential
    )
  }

  private static func runKimiFetch(accountID: UUID) async throws {
    let credential = try await storedKimiCredential(
      accountID: accountID
    )
    try await fetchKimiUsage(
      accountID: accountID,
      credential: credential
    )
  }

  private static func runKimiRefresh(accountID: UUID) async throws {
    let current = try await storedKimiCredential(
      accountID: accountID
    )
    let refreshed = try await KimiOAuthFlow(
      device: kimiDevice(for: accountID)
    ).refresh(current)
    try await credentialStore.save(
      .kimi(refreshed),
      for: accountID
    )
    try await fetchKimiUsage(
      accountID: accountID,
      credential: refreshed
    )
  }

  private static func storedKimiCredential(
    accountID: UUID
  ) async throws -> OAuthCredential {
    guard
      let stored = try await credentialStore.load(for: accountID),
      case let .kimi(credential) = stored
    else {
      throw KimiOAuthFlowError.reauthenticationRequired
    }
    return credential
  }

  private static func fetchKimiUsage(
    accountID: UUID,
    credential: OAuthCredential
  ) async throws {
    let snapshot = try await KimiUsageClient().fetchUsage(
      accountID: accountID,
      credential: .kimi(credential),
      now: Date()
    )
    try write(
      ProbeOutput(
        provider: .kimi,
        identity: nil,
        snapshot: snapshot
      )
    )
  }

  private static func runMiniMaxLogin(
    accountID: UUID
  ) async throws {
    let apiKey = try readSecret(
      prompt: "MiniMax API key: "
    )
    guard
      let credential = MiniMaxCredential(apiKey: apiKey)
    else {
      throw ProviderClientError.credentialMismatch
    }
    try await credentialStore.save(
      credential,
      for: accountID
    )
    try await fetchMiniMaxUsage(
      accountID: accountID
    )
  }

  private static func runMiniMaxFetch(
    accountID: UUID
  ) async throws {
    try await fetchMiniMaxUsage(
      accountID: accountID
    )
  }

  private static func fetchMiniMaxUsage(
    accountID: UUID
  ) async throws {
    let account = SubscriptionAccount(
      id: accountID,
      provider: .minimax,
      displayName: "MiniMax qualification",
      displayOrder: 0
    )
    let snapshot = try await MiniMaxUsageAdapter(
      credentialStore: credentialStore
    ).fetchUsage(
      for: account,
      now: Date()
    )
    try write(
      ProbeOutput(
        provider: .minimax,
        identity: nil,
        snapshot: snapshot
      )
    )
  }

  private static func readSecret(
    prompt: String
  ) throws -> String {
    var buffer = [CChar](
      repeating: 0,
      count: 4_096
    )
    defer {
      _ = buffer.withUnsafeMutableBytes {
        $0.initializeMemory(
          as: UInt8.self,
          repeating: 0
        )
      }
    }

    let result = prompt.withCString { promptPointer in
      buffer.withUnsafeMutableBufferPointer {
        bufferPointer in
        readpassphrase(
          promptPointer,
          bufferPointer.baseAddress,
          bufferPointer.count,
          RPP_ECHO_OFF
        )
      }
    }
    guard result != nil else {
      throw ProviderClientError.credentialMismatch
    }
    let terminator =
      buffer.firstIndex(of: 0) ?? buffer.endIndex
    return String(
      decoding: buffer[..<terminator].map {
        UInt8(bitPattern: $0)
      },
      as: UTF8.self
    )
  }

  private static func kimiDevice(
    for accountID: UUID
  ) -> KimiDeviceInfo {
    KimiDeviceInfo(
      name: Host.current().localizedName ?? "Mac",
      model: "macOS",
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      id: accountID.uuidString.lowercased(),
      clientVersion: "0.1.0"
    )
  }

  private static func displayIdentity(
    _ identity: CodexOAuthIdentity
  ) -> String {
    switch (identity.email, identity.plan) {
    case let (email?, plan?):
      "\(email) (\(plan))"
    case let (email?, nil):
      email
    case let (nil, plan?):
      "\(plan) account"
    case (nil, nil):
      "unknown account"
    }
  }

  private static func write(_ output: ProbeOutput) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(output)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func safeDescription(of error: any Error) -> String {
    if let error = error as? CodexOAuthFlowError {
      return error.description
    }
    if let error = error as? KimiOAuthFlowError {
      return error.description
    }

    guard let providerError = error as? ProviderClientError else {
      return "credential or transport failure"
    }

    switch providerError {
    case .credentialMismatch:
      return "credential mismatch"
    case .subscriptionRequired:
      return "subscription is not active"
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

  private static func writePrompt(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
  }
}
