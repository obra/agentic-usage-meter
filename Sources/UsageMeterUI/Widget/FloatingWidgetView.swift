import SwiftUI

public struct FloatingWidgetView: View {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agentic Usage")
                    .font(.headline)
                if model.isSampleData {
                    sampleDataBadge
                }
                Spacer()
                Button {
                    Task {
                        try? await model.setFloatingWidgetVisible(
                            false,
                        )
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Hide Widget")
            }
            .controlSize(.small)
            .padding(
                .horizontal,
                UsageTimelineMetrics.outerHorizontalPadding
            )
            .padding(
                .vertical,
                UsageTimelineMetrics.outerVerticalPadding
            )

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
        }
        .frame(
            minWidth: 360,
            idealWidth: UsageTimelineMetrics.naturalWidth,
            maxWidth: .infinity
        )
        .background(.regularMaterial)
    }

    private var timeline: some View {
        UsageTimelineView(
            accounts: model.accounts,
            collapsedSections:
                model.collapsedUsageSections,
            onToggleSection: { section in
                Task {
                    try? await model.toggleUsageSection(
                        section,
                    )
                }
            },
            onOpenAccount: {
                AccountDashboardPresenter.shared.open($0)
            }
        )
            .padding(
                .horizontal,
                UsageTimelineMetrics.outerHorizontalPadding
            )
            .padding(
                .vertical,
                UsageTimelineMetrics.outerVerticalPadding
            )
    }

    private var sampleDataBadge: some View {
        Text("SAMPLE DATA")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.14), in: Capsule())
            .accessibilityLabel("Sample data")
    }
}
