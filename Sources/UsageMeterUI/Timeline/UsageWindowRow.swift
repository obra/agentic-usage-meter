import SwiftUI
import UsageMeterCore

public struct UsageWindowRow: View {
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

    HStack(spacing: UsageTimelineMetrics.columnSpacing) {
      Text(presentation.remainingPercentageText)
        .font(.caption.monospacedDigit())
        .fontWeight(.semibold)
        .frame(
          width: UsageTimelineMetrics.percentageColumnWidth,
          alignment: .trailing,
        )

      HStack(spacing: 4) {
        Circle()
          .fill(row.account.provider.timelineColor)
          .frame(width: 7, height: 7)
        Text(presentation.providerText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .font(.caption)
      .lineLimit(1)
      .frame(
        width: UsageTimelineMetrics.providerColumnWidth,
        alignment: .leading,
      )

      Text(presentation.accountText)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(
          width: UsageTimelineMetrics.accountColumnWidth,
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
          .frame(
            width: outerWidth,
            height: UsageTimelineMetrics.barHeight,
          )
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
            .frame(
              width: 1,
              height: UsageTimelineMetrics.nowLineHeight,
            )
            .offset(
              x:
                width
                * presentation.nowXFraction,
            )
        }
      }
      .frame(
        minWidth: UsageTimelineMetrics.minimumTimelineWidth,
        maxWidth: .infinity,
      )
      .frame(height: UsageTimelineMetrics.rowHeight)

      Text(presentation.relativeResetText)
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(
          width: UsageTimelineMetrics.resetColumnWidth,
          alignment: .trailing,
        )
    }
    .frame(height: UsageTimelineMetrics.rowHeight)
    .help(presentation.helpText)
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
