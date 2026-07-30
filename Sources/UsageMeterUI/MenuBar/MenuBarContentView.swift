import AppKit
import SwiftUI

public struct MenuBarContentView: View {
    private let model: AppModel
    @Environment(\.openSettings) private var openSettings

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Usage")
                    .font(.title3.weight(.semibold))
                if model.isSampleData {
                    sampleDataBadge
                }
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

            ViewThatFits(in: .vertical) {
                timeline
                    .fixedSize(
                        horizontal: false,
                        vertical: true,
                    )
                ScrollView {
                    timeline
                }
            }

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

                Button {
                    SettingsWindowPresenter().present {
                        openSettings()
                    }
                } label: {
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private func refreshAllAccounts() {
        Task {
            for account in model.accounts {
                await model.refreshAccount(id: account.id)
            }
        }
    }

    private var timeline: some View {
        UsageTimelineView(accounts: model.accounts)
            .padding()
    }

    private var sampleDataBadge: some View {
        Text("SAMPLE DATA")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.orange.opacity(0.14), in: Capsule())
            .accessibilityLabel("Sample data")
    }
}
