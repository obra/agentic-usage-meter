import AppKit
import SwiftUI
import UsageMeterCore
import UsageMeterUI

@main
struct AgenticUsageMeterApp: App {
    @State private var model: AppModel
    @State private var widgetController: FloatingWidgetController
    @State private var updateController: AppUpdateController

    init() {
        let model = AppEnvironment.makeModel()
        _model = State(initialValue: model)
        _widgetController = State(
            initialValue: FloatingWidgetController(model: model),
        )
        _updateController = State(
            initialValue: AppUpdateController(),
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                model: model,
                updateController: updateController,
            )
        } label: {
            MenuBarLabel(
                model: model,
                widgetController: widgetController,
                updateController: updateController,
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

private struct MenuBarLabel: View {
    let model: AppModel
    let widgetController: FloatingWidgetController
    let updateController: AppUpdateController

    var body: some View {
        Group {
            if let text = model.menuBarSummary.text {
                Label(
                    text,
                    systemImage: model.menuBarSummary.systemImage,
                )
            } else {
                Image(systemName: model.menuBarSummary.systemImage)
            }
        }
        .task {
            NSApplication.shared.setActivationPolicy(.accessory)
            updateController.start()
            await model.start()
            widgetController.synchronize()
            await model.runAutomaticRefresh()
        }
        .task {
            for await _ in NSWorkspace.shared.notificationCenter
                .notifications(
                    named: NSWorkspace.didWakeNotification
                )
            {
                await model.refreshAfterWake()
            }
        }
        .onChange(of: model.isFloatingWidgetVisible) {
            widgetController.synchronize()
        }
        .onChange(of: model.accounts) {
            widgetController.synchronize()
        }
    }
}

enum AppEnvironment {
    @MainActor
    static func makeModel() -> AppModel {
        let sampleData = CommandLine.arguments.contains(
            "--sample-data",
        )
        let stateStore: any AppStatePersisting =
            sampleData
                ? SampleAppStateStore(
                    state: sampleState(
                        showWidget: CommandLine.arguments.contains(
                            "--show-widget",
                        ),
                    ),
                )
                : AppStateStore(fileURL: stateFileURL())
        let credentialStore = KeychainCredentialStore()
        #if DEBUG
            let refreshPolicy = RefreshPolicy.development
        #else
            let refreshPolicy = RefreshPolicy.release
        #endif
        let adapters: [any ProviderAccountAdapter] = [
            ClaudeWebAccountUsageClient(),
            CredentialUsageAdapter(
                provider: .codex,
                credentialStore: credentialStore,
                client: CodexUsageClient()
            ),
            CredentialUsageAdapter(
                provider: .kimi,
                credentialStore: credentialStore,
                client: KimiUsageClient(),
                refreshCredential: refreshKimiCredential
            ),
            MiniMaxUsageAdapter(
                credentialStore: credentialStore
            ),
            FactoryUsageAdapter(
                credentialStore: credentialStore
            ),
            GitHubCopilotUsageAdapter(
                credentialStore: credentialStore
            ),
            SuperGrokUsageAdapter(
                credentialStore: credentialStore
            ),
            OpenCodeWebAccountUsageClient(
                base: OpenCodeGoUsageAdapter(
                    credentialStore:
                        credentialStore
                ),
                credentialStore: credentialStore
            ),
            OpenCodeWebAccountUsageClient(
                base: OpenCodeZenUsageAdapter(
                    credentialStore:
                        credentialStore
                ),
                credentialStore: credentialStore
            ),
        ]

        return AppModel(
            stateStore: stateStore,
            credentialStore: credentialStore,
            adapters: adapters,
            refreshPolicy: refreshPolicy,
            isSampleData: sampleData
        )
    }

    private static func refreshKimiCredential(
        accountID: UUID,
        credential: ProviderCredential,
    ) async throws -> ProviderCredential {
        guard case let .kimi(oauth) = credential else {
            throw ProviderClientError.credentialMismatch
        }
        do {
            return .kimi(
                try await KimiOAuthFlow(
                    device: .currentMac(accountID: accountID),
                ).refresh(oauth),
            )
        } catch let error as KimiOAuthFlowError {
            switch error {
            case .reauthenticationRequired:
                throw ProviderClientError.reauthenticationRequired
            case .invalidResponse:
                throw ProviderClientError.unsupportedResponse
            case .browserOpenFailed, .authorizationFailed,
                .temporaryFailure:
                throw ProviderClientError.temporaryFailure
            }
        }
    }

    private static func stateFileURL() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        )[0]
            .appending(
                path: "AgenticUsageMeter/state.json",
            )
    }

    static func sampleState(
        showWidget: Bool,
    ) -> PersistedAppState {
        let now = Date()
        let accounts = [
            SubscriptionAccount(
                provider: .claude,
                displayName: "Work",
                displayOrder: 0,
            ),
            SubscriptionAccount(
                provider: .claude,
                displayName: "Personal",
                displayOrder: 1,
            ),
            SubscriptionAccount(
                provider: .codex,
                displayName: "Work",
                displayOrder: 0,
            ),
            SubscriptionAccount(
                provider: .codex,
                displayName: "Personal",
                displayOrder: 1,
            ),
            SubscriptionAccount(
                provider: .kimi,
                displayName: "Kimi",
                displayOrder: 0,
            ),
            SubscriptionAccount(
                provider: .factory,
                displayName: "Factory",
                displayOrder: 0,
            ),
        ]
        let snapshots = Dictionary(
            uniqueKeysWithValues: accounts.enumerated().map {
                index,
                    account in
                (
                    account.id,
                    UsageSnapshot(
                        accountID: account.id,
                        fetchedAt: now,
                        windows: sampleWindows(
                            provider: account.provider,
                            index: index,
                            now: now,
                        ),
                        balances: sampleBalances(
                            provider: account.provider,
                            displayOrder: account.displayOrder,
                        ),
                    ),
                )
            },
        )
        let refreshStates = Dictionary(
            uniqueKeysWithValues: accounts.map {
                (
                    $0.id,
                    AccountRefreshState(
                        lastRequestStartedAt: now,
                    ),
                )
            },
        )
        return PersistedAppState(
            accounts: accounts,
            snapshots: snapshots,
            refreshStates: refreshStates,
            isFloatingWidgetVisible: showWidget,
        )
    }

    private static func sampleWindows(
        provider: Provider,
        index: Int,
        now: Date,
    ) -> [UsageWindow] {
        if provider == .factory {
            return [
                (id: "standard", label: "Standard"),
                (id: "core", label: "Droid Core"),
            ].flatMap { pool in
                [
                    UsageWindow(
                        id: "\(pool.id)-short",
                        kind: .short,
                        duration: 18_000,
                        resetAt: nil,
                        consumedFraction: 0,
                        label: pool.label,
                    )!,
                    UsageWindow(
                        id: "\(pool.id)-weekly",
                        kind: .weekly,
                        duration: 604_800,
                        resetAt: nil,
                        consumedFraction: 0,
                        label: pool.label,
                    )!,
                    UsageWindow(
                        id: "\(pool.id)-monthly",
                        kind: .monthly,
                        duration: 2_592_000,
                        resetAt: nil,
                        consumedFraction: 0,
                        label: pool.label,
                    )!,
                ]
            }
        }

        let weeklyConsumed =
            provider == .kimi
                ? 0.26
                : min(
                    0.31 + Double(index) * 0.11,
                    0.90,
                )
        let weekly = UsageWindow(
            id: "weekly",
            kind: .weekly,
            duration: 604_800,
            resetAt: now.addingTimeInterval(
                Double(180_000 + index * 72000),
            ),
            consumedFraction: weeklyConsumed,
        )!
        guard provider == .claude || provider == .kimi else {
            return [weekly]
        }
        return [
            UsageWindow(
                id: "short",
                kind: .short,
                duration: 18000,
                resetAt: now.addingTimeInterval(
                    Double(3000 + index * 1500),
                ),
                consumedFraction: min(
                    0.22 + Double(index) * 0.13,
                    0.92,
                ),
            )!,
            weekly,
        ]
    }

    private static func sampleBalances(
        provider: Provider,
        displayOrder: Int,
    ) -> [UsageBalance] {
        let value: UsageBalanceValue
        let label: String
        switch (provider, displayOrder) {
        case (.claude, 0):
            label = "Extra usage"
            value = .available(
                amount: Decimal(string: "38.42")!,
                unit: "USD",
            )
        case (.claude, _):
            label = "Extra usage"
            value = .disabled
        case (.codex, 0):
            label = "Credits"
            value = .available(
                amount: Decimal(string: "1240.5")!,
                unit: "credits",
            )
        case (.codex, _):
            label = "Credits"
            value = .unlimited
        case (.kimi, _):
            label = "Extra usage"
            value = .disabled
        case (.factory, _):
            label = "Credits"
            value = .available(amount: 0, unit: "USD")
        default:
            return []
        }

        return [
            UsageBalance(
                id: "extra-credits",
                label: label,
                value: value,
            )!
        ]
    }
}

private actor SampleAppStateStore: AppStatePersisting {
    private var state: PersistedAppState

    init(state: PersistedAppState) {
        self.state = state
    }

    func load() -> PersistedAppState {
        state
    }

    func save(_ state: PersistedAppState) {
        self.state = state
    }
}
