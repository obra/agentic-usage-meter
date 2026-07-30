import AppKit
import SwiftUI
import UsageMeterCore
import UsageMeterUI

@main
struct AgenticUsageMeterApp: App {
    @State private var model: AppModel
    @State private var widgetController: FloatingWidgetController

    init() {
        let model = AppEnvironment.makeModel()
        _model = State(initialValue: model)
        _widgetController = State(
            initialValue: FloatingWidgetController(model: model),
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            MenuBarLabel(
                model: model,
                widgetController: widgetController,
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
            await model.start()
            widgetController.synchronize()
            await model.runAutomaticRefresh()
        }
        .onChange(of: model.isFloatingWidgetVisible) {
            widgetController.synchronize()
        }
        .onChange(of: model.accounts) {
            widgetController.synchronize()
        }
    }
}

private enum AppEnvironment {
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

        return AppModel(
            stateStore: stateStore,
            credentialStore: KeychainCredentialStore(),
            clients: [
                CodexUsageClient(),
                KimiUsageClient(),
            ],
            credentialRefreshers: [
                .kimi: refreshKimiCredential,
            ],
            claudeClient: ClaudeWebAccountUsageClient(),
            claudeProfileRemover: {
                try await ClaudeWebAccountUsageClient.removeProfile(
                    $0,
                )
            },
            isSampleData: sampleData,
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

    private static func sampleState(
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
        guard provider == .claude else {
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
