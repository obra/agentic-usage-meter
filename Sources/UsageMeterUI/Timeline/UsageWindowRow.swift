import SwiftUI
import UsageMeterCore

public struct UsageWindowRow: View {
    static let percentageColumnWidth: CGFloat = 42
    static let identityColumnWidth: CGFloat = 156
    static let resetColumnWidth: CGFloat = 64
    static let columnSpacing: CGFloat = 8
    static let rowHeight: CGFloat = 29

    private let row: UsageTimelineRowPresentation
    private let onOpenDashboard: (() -> Void)?

    public init(
        row: UsageTimelineRowPresentation,
        onOpenDashboard: (() -> Void)? = nil
    ) {
        self.row = row
        self.onOpenDashboard = onOpenDashboard
    }

    public var body: some View {
        let presentation = row.windowPresentation

        HStack(spacing: Self.columnSpacing) {
            Text(presentation.remainingPercentageText)
                .font(.caption.monospacedDigit())
                .fontWeight(.semibold)
                .frame(
                    width: Self.percentageColumnWidth,
                    alignment: .trailing,
                )

            HStack(spacing: 4) {
                Circle()
                    .fill(row.account.provider.timelineColor)
                    .frame(width: 7, height: 7)
                Text(presentation.providerText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                if let accountText = presentation.accountText {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(accountText)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.caption)
            .lineLimit(1)
            .frame(
                width: Self.identityColumnWidth,
                alignment: .leading,
            )

            GeometryReader { geometry in
                let width = geometry.size.width
                let outerX = width * presentation.outerXFraction
                let outerWidth =
                    width * presentation.outerWidthFraction

                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
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
                    }
                    .frame(width: outerWidth, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(
                                row.account.provider.timelineColor
                                    .opacity(0.8),
                                lineWidth: 1,
                            )
                    }
                    .offset(x: outerX)

                    Rectangle()
                        .fill(.primary.opacity(0.55))
                        .frame(width: 1, height: 22)
                        .offset(
                            x:
                            width
                                * presentation.nowXFraction,
                        )
                }
            }
            .frame(height: Self.rowHeight)

            Text(presentation.relativeResetText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(
                    width: Self.resetColumnWidth,
                    alignment: .trailing,
                )
        }
        .frame(height: Self.rowHeight)
        .help("Resets \(presentation.exactResetText)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityValue)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenDashboard?()
        }
    }
}

extension Provider {
    var timelineColor: Color {
        let color =
            ProviderCatalog.live.definition(
                for: self,
            )?.color
            ?? ProviderColor(
                red: 0.5,
                green: 0.5,
                blue: 0.5,
            )
        return Color(
            red: color.red,
            green: color.green,
            blue: color.blue,
        )
    }
}
