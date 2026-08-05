import Foundation

public struct ProviderColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum ProviderReleaseState: Equatable, Sendable {
    case qualified
    case experimental
    case unavailable
}

public enum ProviderConnectionStrategy: Equatable, Sendable {
    case isolatedWebSession
    case browserOAuth
    case deviceOAuth
    case apiKey
    case isolatedCLIProfile(executable: String)
}

public enum ProviderDashboardStrategy: Equatable, Sendable {
    case embedded(URL)
    case nativeDetail(externalURL: URL?)
    case external(URL)
}

public struct ProviderDefinition: Equatable, Identifiable, Sendable {
    public let provider: Provider
    public let displayName: String
    public let connectionDetail: String
    public let systemImage: String
    public let color: ProviderColor
    public let releaseState: ProviderReleaseState
    public let connectionStrategy: ProviderConnectionStrategy
    public let dashboardStrategy: ProviderDashboardStrategy

    public init(
        provider: Provider,
        displayName: String,
        connectionDetail: String,
        systemImage: String,
        color: ProviderColor,
        releaseState: ProviderReleaseState,
        connectionStrategy: ProviderConnectionStrategy,
        dashboardStrategy: ProviderDashboardStrategy,
    ) {
        self.provider = provider
        self.displayName = displayName
        self.connectionDetail = connectionDetail
        self.systemImage = systemImage
        self.color = color
        self.releaseState = releaseState
        self.connectionStrategy = connectionStrategy
        self.dashboardStrategy = dashboardStrategy
    }

    public var id: Provider {
        provider
    }
}

public struct ProviderCatalog: Sendable {
    public static let live = ProviderCatalog(
        definitions: [
            ProviderDefinition(
                provider: .claude,
                displayName: "Claude",
                connectionDetail: "Isolated browser session",
                systemImage: "globe",
                color: ProviderColor(
                    red: 0.86,
                    green: 0.36,
                    blue: 0.18,
                ),
                releaseState: .qualified,
                connectionStrategy: .isolatedWebSession,
                dashboardStrategy: .embedded(
                    URL(
                        string: "https://claude.ai/settings/usage",
                    )!,
                ),
            ),
            ProviderDefinition(
                provider: .codex,
                displayName: "Codex",
                connectionDetail:
                "ChatGPT OAuth in your browser",
                systemImage: "terminal",
                color: ProviderColor(
                    red: 0.15,
                    green: 0.68,
                    blue: 0.55,
                ),
                releaseState: .qualified,
                connectionStrategy: .browserOAuth,
                dashboardStrategy: .nativeDetail(
                    externalURL: URL(
                        string:
                        "https://chatgpt.com/codex/settings/usage",
                    )!,
                ),
            ),
            ProviderDefinition(
                provider: .kimi,
                displayName: "Kimi",
                connectionDetail: "Device authorization",
                systemImage: "moon.stars",
                color: ProviderColor(
                    red: 0.33,
                    green: 0.45,
                    blue: 0.92,
                ),
                releaseState: .qualified,
                connectionStrategy: .deviceOAuth,
                dashboardStrategy: .nativeDetail(
                    externalURL: URL(
                        string: "https://www.kimi.com/code/console",
                    )!,
                ),
            ),
            ProviderDefinition(
                provider: .minimax,
                displayName: "MiniMax",
                connectionDetail: "Token Plan API key",
                systemImage: "waveform.path.ecg",
                color: ProviderColor(
                    red: 0.91,
                    green: 0.28,
                    blue: 0.38,
                ),
                releaseState: .experimental,
                connectionStrategy: .apiKey,
                dashboardStrategy: .nativeDetail(
                    externalURL: URL(
                        string: "https://www.minimax.io/platform",
                    )!,
                ),
            ),
            ProviderDefinition(
                provider: .githubCopilot,
                displayName: "GitHub",
                connectionDetail: "GitHub device OAuth",
                systemImage:
                "chevron.left.forwardslash.chevron.right",
                color: ProviderColor(
                    red: 0.50,
                    green: 0.36,
                    blue: 0.88,
                ),
                releaseState: .experimental,
                connectionStrategy: .deviceOAuth,
                dashboardStrategy: .nativeDetail(
                    externalURL: URL(
                        string:
                        "https://github.com/settings/billing/summary",
                    )!,
                ),
            ),
            ProviderDefinition(
                provider: .antigravity,
                displayName: "Antigravity",
                connectionDetail:
                "Shared macOS Keychain prevents isolated accounts",
                systemImage: "sparkles",
                color: ProviderColor(
                    red: 0.25,
                    green: 0.55,
                    blue: 0.95,
                ),
                releaseState: .unavailable,
                connectionStrategy: .isolatedCLIProfile(
                    executable: "agy",
                ),
                dashboardStrategy: .nativeDetail(
                    externalURL: URL(
                        string: "https://antigravity.google/",
                    )!,
                ),
            ),
            ProviderDefinition(
                provider: .factory,
                displayName: "Factory",
                connectionDetail:
                "Per-account Factory API key",
                systemImage: "building.2",
                color: ProviderColor(
                    red: 0.89,
                    green: 0.55,
                    blue: 0.18,
                ),
                releaseState: .experimental,
                connectionStrategy: .apiKey,
                dashboardStrategy: .nativeDetail(
                    externalURL: URL(
                        string:
                        "https://app.factory.ai/settings/usage",
                    )!,
                ),
            ),
            ProviderDefinition(
                provider: .openCodeGo,
                displayName: "OpenCode Go",
                connectionDetail:
                "Isolated OpenCode session",
                systemImage: "arrow.right.circle",
                color: ProviderColor(
                    red: 0.18,
                    green: 0.70,
                    blue: 0.72,
                ),
                releaseState: .experimental,
                connectionStrategy: .isolatedWebSession,
                dashboardStrategy: .embedded(
                    URL(string: "https://opencode.ai/go")!,
                ),
            ),
            ProviderDefinition(
                provider: .openCodeZen,
                displayName: "OpenCode Zen",
                connectionDetail:
                "Isolated OpenCode session",
                systemImage: "circle.hexagongrid",
                color: ProviderColor(
                    red: 0.51,
                    green: 0.61,
                    blue: 0.29,
                ),
                releaseState: .experimental,
                connectionStrategy: .isolatedWebSession,
                dashboardStrategy: .embedded(
                    URL(string: "https://opencode.ai/zen")!,
                ),
            ),
            ProviderDefinition(
                provider: .superGrok,
                displayName: "SuperGrok",
                connectionDetail: "Grok device OAuth",
                systemImage: "xmark.circle",
                color: ProviderColor(
                    red: 0.36,
                    green: 0.36,
                    blue: 0.38,
                ),
                releaseState: .experimental,
                connectionStrategy: .deviceOAuth,
                dashboardStrategy: .embedded(
                    URL(
                        string:
                            "https://grok.com/?_s=usage",
                    )!,
                ),
            ),
            ProviderDefinition(
                provider: .zai,
                displayName: "Z.ai",
                connectionDetail: "Coding Plan API key",
                systemImage: "z.circle",
                color: ProviderColor(
                    red: 0.20,
                    green: 0.42,
                    blue: 0.95,
                ),
                releaseState: .experimental,
                connectionStrategy: .apiKey,
                dashboardStrategy: .nativeDetail(
                    externalURL: URL(
                        string:
                            "https://z.ai/manage-apikey/coding-plan/personal/usage",
                    )!,
                ),
            ),
            ProviderDefinition(
                provider: .mimo,
                displayName: "MiMo",
                connectionDetail: "Isolated browser session",
                systemImage: "m.circle",
                color: ProviderColor(
                    red: 1.00,
                    green: 0.44,
                    blue: 0.20,
                ),
                releaseState: .experimental,
                connectionStrategy: .isolatedWebSession,
                dashboardStrategy: .embedded(
                    URL(
                        string:
                            "https://platform.xiaomimimo.com/console/balance",
                    )!,
                ),
            ),
        ],
    )

    public let all: [ProviderDefinition]

    public init(definitions: [ProviderDefinition]) {
        precondition(
            Set(definitions.map(\.provider)).count
                == definitions.count,
        )
        all = definitions
    }

    public func definition(
        for provider: Provider,
    ) -> ProviderDefinition? {
        all.first { $0.provider == provider }
    }

    public func connectableDefinitions() -> [ProviderDefinition] {
        all.filter {
            $0.releaseState != .unavailable
        }
    }

    public func sortIndex(for provider: Provider) -> Int {
        all.firstIndex { $0.provider == provider }
            ?? Int.max
    }
}
