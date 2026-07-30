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

            ScrollView {
                UsageTimelineView(accounts: model.accounts)
                    .padding(14)
            }
        }
        .background(.regularMaterial)
    }
}
