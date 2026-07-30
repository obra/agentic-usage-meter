import SwiftUI
import UsageMeterCore

public struct UsageWindowRow: View {
    private let row: UsageTimelineRowPresentation

    public init(row: UsageTimelineRowPresentation) {
        self.row = row
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(row.account.provider.timelineColor)
                    .frame(width: 7, height: 7)
                Text(row.account.provider.displayName)
                    .foregroundStyle(.secondary)
                Text(row.account.displayName)
                    .fontWeight(.medium)
                Spacer()
            }
            .font(.caption)

            GeometryReader { geometry in
                let presentation = row.windowPresentation
                let width = geometry.size.width
                let outerX = width * presentation.outerXFraction
                let outerWidth =
                    width * presentation.outerWidthFraction

                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.secondary.opacity(0.12))

                        Rectangle()
                            .fill(
                                row.account.provider.timelineColor
                                    .gradient,
                            )
                            .frame(
                                width:
                                outerWidth
                                    * presentation.fillFraction,
                            )

                        HStack(spacing: 6) {
                            timelinePill(
                                presentation.remainingText,
                            )
                            Spacer(minLength: 4)
                            timelinePill(
                                presentation.expiryText,
                            )
                        }
                        .padding(.horizontal, 5)
                    }
                    .frame(width: outerWidth, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                row.account.provider.timelineColor
                                    .opacity(0.9),
                                lineWidth: 1,
                            )
                    }
                    .offset(x: outerX)

                    Rectangle()
                        .fill(.primary.opacity(0.55))
                        .frame(width: 1, height: 38)
                        .offset(
                            x:
                            width
                                * presentation.nowXFraction,
                        )
                }
            }
            .frame(height: 38)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.windowPresentation.accessibilityValue)
    }

    private func timelinePill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.62), in: Capsule())
    }
}

private extension Provider {
    var timelineColor: Color {
        switch self {
        case .claude:
            Color(red: 0.83, green: 0.43, blue: 0.28)
        case .codex:
            Color(red: 0.24, green: 0.66, blue: 0.54)
        case .kimi:
            Color(red: 0.48, green: 0.45, blue: 0.90)
        }
    }

    var displayName: String {
        switch self {
        case .claude:
            "Claude"
        case .codex:
            "Codex"
        case .kimi:
            "Kimi"
        }
    }
}
