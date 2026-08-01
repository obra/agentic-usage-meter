import Testing
import UsageMeterCore

@testable import UsageMeterUI

@Test
func providerMarkResourcesLoad() {
    let bundledProviders: [Provider] = [
        .claude,
        .kimi,
        .minimax,
        .githubCopilot,
        .antigravity,
        .factory,
        .openCodeGo,
        .openCodeZen,
        .superGrok,
    ]

    for provider in bundledProviders {
        #expect(
            ProviderMarkImageLoader.image(for: provider)
                != nil,
        )
    }
    #expect(
        ProviderMarkImageLoader.image(for: .codex) == nil,
    )
}
