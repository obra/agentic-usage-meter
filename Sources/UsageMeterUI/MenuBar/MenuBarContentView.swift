import AppKit
import SwiftUI

public struct MenuBarContentView: View {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Usage")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    refreshAllAccounts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh eligible accounts")
                .disabled(model.accounts.contains {
                    $0.isRefreshing
                })
            }
            .padding()

            Divider()

            ScrollView {
                UsageTimelineView(accounts: model.accounts)
                    .padding()
            }
            .frame(minHeight: 280, maxHeight: 520)

            Divider()

            HStack {
                Button {
                    Task {
                        try? await model.setFloatingWidgetVisible(
                            !model.isFloatingWidgetVisible,
                        )
                    }
                } label: {
                    Label(
                        model.isFloatingWidgetVisible
                            ? "Hide Widget"
                            : "Show Widget",
                        systemImage: "rectangle.on.rectangle",
                    )
                }

                Spacer()

                SettingsLink {
                    Label("Settings", systemImage: "gear")
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.borderless)
            .padding()
        }
        .frame(width: 520)
    }

    private func refreshAllAccounts() {
        Task {
            for account in model.accounts {
                await model.refreshAccount(id: account.id)
            }
        }
    }
}
