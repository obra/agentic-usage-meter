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
        }
        .onChange(of: model.isFloatingWidgetVisible) {
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
                ? SampleAppStateStore(state: sampleState())
                : AppStateStore(fileURL: stateFileURL())

        return AppModel(
            stateStore: stateStore,
            credentialStore: KeychainCredentialStore(),
            clients: [
                CodexUsageClient(),
                KimiUsageClient(),
            ],
            claudeClient: ClaudeWebAccountUsageClient(),
            claudeProfileRemover: {
                try await ClaudeWebAccountUsageClient.removeProfile(
                    $0,
                )
            },
        )
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

    private static func sampleState() -> PersistedAppState {
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
        )
    }

    private static func sampleWindows(
        index: Int,
        now: Date,
    ) -> [UsageWindow] {
        [
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
            UsageWindow(
                id: "weekly",
                kind: .weekly,
                duration: 604_800,
                resetAt: now.addingTimeInterval(
                    Double(180_000 + index * 72000),
                ),
                consumedFraction: min(
                    0.31 + Double(index) * 0.11,
                    0.90,
                ),
            )!,
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
