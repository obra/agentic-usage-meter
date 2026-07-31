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
    func catalogShowsExperimentalProvidersOnlyInDevelopment() {
        let qualified = [
            Provider.claude,
            Provider.codex,
            Provider.kimi,
        ]

        #expect(
            ProviderCatalog.live
                .visibleDefinitions(isDevelopmentBuild: false)
                .map(\.provider) == qualified,
        )
        #expect(
            ProviderCatalog.live
                .visibleDefinitions(isDevelopmentBuild: true)
                .map(\.provider)
                == qualified
                    + [
                        .minimax,
                        .githubCopilot,
                        .openCodeGo,
                        .openCodeZen,
                        .superGrok,
                    ],
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
