import Foundation
import Testing
@testable import UsageMeterCore

@Test
func credentialStoreKeepsAccountsIndependentAndSupportsDeletion() async throws {
    let store: any CredentialStore = InMemoryCredentialStore()
    let claudeAccountID = UUID()
    let codexAccountID = UUID()
    let claudeCredential = ProviderCredential.claude(token: "claude-secret")
    let codexCredential = ProviderCredential.codex(
        OAuthCredential(
            accessToken: "codex-access",
            refreshToken: "codex-refresh",
            idToken: "codex-id",
            accountID: "workspace-account",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
    )

    try await store.save(claudeCredential, for: claudeAccountID)
    try await store.save(codexCredential, for: codexAccountID)

    #expect(try await store.load(for: claudeAccountID) == claudeCredential)
    #expect(try await store.load(for: codexAccountID) == codexCredential)

    try await store.delete(for: claudeAccountID)

    #expect(try await store.load(for: claudeAccountID) == nil)
    #expect(try await store.load(for: codexAccountID) == codexCredential)
}

@Test
func credentialStoreReplacesAnAccountsCredential() async throws {
    let store: any CredentialStore = InMemoryCredentialStore()
    let accountID = UUID()
    let original = ProviderCredential.kimi(
        OAuthCredential(
            accessToken: "original-access",
            refreshToken: "original-refresh",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
    )
    let replacement = ProviderCredential.kimi(
        OAuthCredential(
            accessToken: "replacement-access",
            refreshToken: "replacement-refresh",
            expiresAt: Date(timeIntervalSince1970: 2_000_003_600)
        )
    )

    try await store.save(original, for: accountID)
    try await store.save(replacement, for: accountID)

    #expect(try await store.load(for: accountID) == replacement)
}

private actor InMemoryCredentialStore: CredentialStore {
    private var credentials: [UUID: ProviderCredential] = [:]

    func save(_ credential: ProviderCredential, for accountID: UUID) {
        credentials[accountID] = credential
    }

    func load(for accountID: UUID) -> ProviderCredential? {
        credentials[accountID]
    }

    func delete(for accountID: UUID) {
        credentials.removeValue(forKey: accountID)
    }
}
