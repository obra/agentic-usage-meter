import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct ProviderCatalogTests {
    @Test
    func existingProviderValuesKeepTheirStoredStrings() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let cases: [(Provider, String)] = [
            (.claude, "\"claude\""),
            (.codex, "\"codex\""),
            (.kimi, "\"kimi\""),
        ]

        for (provider, encoded) in cases {
            #expect(
                String(
                    decoding: try encoder.encode(provider),
                    as: UTF8.self,
                ) == encoded,
            )
            #expect(
                try decoder.decode(
                    Provider.self,
                    from: Data(encoded.utf8),
                ) == provider,
            )
        }
    }

    @Test
    func liveCatalogHasUniqueProvidersInProductOrder() {
        let providers = ProviderCatalog.live.all.map(\.provider)

        #expect(
            providers == [
                .claude,
                .codex,
                .kimi,
                .minimax,
                .githubCopilot,
                .antigravity,
                .factory,
                .openCodeGo,
                .openCodeZen,
                .superGrok,
            ],
        )
        #expect(Set(providers).count == providers.count)
    }

    @Test
    func catalogShowsAllImplementedProviders() {
        let connectable = [
            Provider.claude,
            Provider.codex,
            Provider.kimi,
            Provider.minimax,
            Provider.githubCopilot,
            Provider.factory,
            Provider.openCodeGo,
            Provider.openCodeZen,
            Provider.superGrok,
        ]

        #expect(
            ProviderCatalog.live
                .connectableDefinitions()
                .map(\.provider)
                == connectable,
        )
    }

    @Test
    func openCodeUsesIsolatedDashboardSessions() throws {
        for provider in [
            Provider.openCodeGo,
            Provider.openCodeZen,
        ] {
            let definition = try #require(
                ProviderCatalog.live.definition(
                    for: provider,
                ),
            )

            #expect(definition.releaseState == .experimental)
            #expect(
                definition.connectionStrategy
                    == .isolatedWebSession,
            )
        }
    }

    @Test
    func superGrokUsesTheAccountScopedUsageDashboard()
        throws
    {
        let definition = try #require(
            ProviderCatalog.live.definition(
                for: .superGrok
            )
        )

        #expect(
            definition.releaseState
                == .experimental
        )
        #expect(
            definition.dashboardStrategy
                == .embedded(
                    URL(
                        string:
                            "https://grok.com/?_s=usage"
                    )!
                )
        )
    }

    @Test
    func factoryUsesPerAccountAPIKeysAndNativeUsageDetail()
        throws
    {
        let definition = try #require(
            ProviderCatalog.live.definition(
                for: .factory
            )
        )

        #expect(definition.releaseState == .experimental)
        #expect(definition.connectionStrategy == .apiKey)
        #expect(
            definition.dashboardStrategy
                == .nativeDetail(
                    externalURL: URL(
                        string:
                            "https://app.factory.ai/settings/usage"
                    )!
                )
        )
    }

    @Test
    func githubUsesItsCompactProviderLabel() throws {
        let definition = try #require(
            ProviderCatalog.live.definition(
                for: .githubCopilot
            )
        )

        #expect(definition.displayName == "GitHub")
    }

    @Test
    func antigravityExplainsItsMultiAccountCredentialBlocker()
        throws
    {
        let definition = try #require(
            ProviderCatalog.live.definition(
                for: .antigravity
            )
        )

        #expect(definition.releaseState == .unavailable)
        #expect(
            definition.connectionDetail
                == "Shared macOS Keychain prevents isolated accounts"
        )
    }

    @Test
    func unknownCatalogProviderSortsAfterKnownProviders() {
        let catalog = ProviderCatalog(
            definitions: [
                ProviderCatalog.live.all[0],
                ProviderCatalog.live.all[1],
            ],
        )

        #expect(
            catalog.sortIndex(for: .kimi)
                > catalog.sortIndex(for: .codex),
        )
    }
}
