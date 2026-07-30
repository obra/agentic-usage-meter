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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

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
        .frame(width: 520)
        .background(.regularMaterial)
    }

    private var timeline: some View {
        UsageTimelineView(accounts: model.accounts)
            .padding(14)
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
