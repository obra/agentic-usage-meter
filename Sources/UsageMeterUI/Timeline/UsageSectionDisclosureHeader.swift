import SwiftUI

struct UsageSectionDisclosureHeader: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let title: String
  let identityColumnsWidth: CGFloat
  let showsTimelineColumns: Bool
  let isExpanded: Bool
  let onToggle: (() -> Void)?

  var body: some View {
    if let onToggle {
      Button(action: onToggle) {
        content
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        "\(isExpanded ? "Collapse" : "Expand") \(title)",
      )
    } else {
      content
    }
  }

  private var content: some View {
    HStack(spacing: UsageTimelineMetrics.columnSpacing) {
      HStack(spacing: 4) {
        if onToggle != nil {
          Image(systemName: "chevron.down")
            .font(.caption2.weight(.semibold))
            .rotationEffect(.degrees(isExpanded ? 0 : -90))
            .animation(
              reduceMotion
                ? nil
                : .easeInOut(duration: 0.15),
              value: isExpanded,
            )
        }
        Text(title)
          .font(.headline)
      }
      .frame(
        width: showsTimelineColumns
          ? identityColumnsWidth
          : nil,
        alignment: .leading,
      )

      if showsTimelineColumns {
        Text(isExpanded ? "Now" : "")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)

        Color.clear
          .frame(width: UsageTimelineMetrics.resetColumnWidth)
      } else {
        Spacer()
      }
    }
    .frame(maxWidth: .infinity)
  }
}
