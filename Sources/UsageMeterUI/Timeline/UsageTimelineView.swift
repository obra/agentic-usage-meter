import SwiftUI
import UsageMeterCore

public struct UsageTimelineView: View {
  private let accounts: [AccountViewState]
  private let now: Date
  private let timeZone: TimeZone
  private let onOpenAccount: ((AccountViewState) -> Void)?

  public init(
    accounts: [AccountViewState],
    now: Date = Date(),
    timeZone: TimeZone = .autoupdatingCurrent,
    onOpenAccount: ((AccountViewState) -> Void)? = nil,
  ) {
    self.accounts = accounts
    self.now = now
    self.timeZone = timeZone
    self.onOpenAccount = onOpenAccount
  }

  public var body: some View {
    let timeline = UsageTimelinePresentation(
      accounts: accounts,
      now: now,
      timeZone: timeZone,
    )

    VStack(
      alignment: .leading,
      spacing: UsageTimelineMetrics.sectionSpacing,
    ) {
      ForEach(timeline.sections, id: \.kind) {
        timelineSection($0)
      }

      if !timeline.balanceRows.isEmpty {
        if !timeline.sections.isEmpty {
          Divider()
        }
        balanceSection(timeline.balanceRows)
      }
    }
  }

  private func timelineSection(
    _ section: UsageTimelineSectionPresentation,
  ) -> some View {
    VStack(
      alignment: .leading,
      spacing: UsageTimelineMetrics.sectionContentSpacing,
    ) {
      HStack(spacing: UsageTimelineMetrics.columnSpacing) {
        Text(section.title)
          .font(.headline)
          .frame(
            width: identityColumnsWidth,
            alignment: .leading,
          )

        Text("Now")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)

        Color.clear
          .frame(width: UsageTimelineMetrics.resetColumnWidth)
      }

      ForEach(section.rows) {
        let row = $0
        UsageWindowRow(
          row: row,
          onOpenDashboard: {
            openAccount(id: row.account.id)
          }
        )
      }
    }
  }

  private func balanceSection(
    _ rows: [UsageBalanceRowPresentation],
  ) -> some View {
    VStack(
      alignment: .leading,
      spacing: UsageTimelineMetrics.sectionContentSpacing,
    ) {
      Text("Extra Credits")
        .font(.headline)

      ForEach(rows) { row in
        HStack(spacing: UsageTimelineMetrics.columnSpacing) {
          Circle()
            .fill(row.account.provider.timelineColor)
            .frame(width: 7, height: 7)
            .frame(
              width: UsageTimelineMetrics.percentageColumnWidth,
              alignment: .trailing,
            )

          Text(row.providerText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(
              width: UsageTimelineMetrics.providerColumnWidth,
              alignment: .leading,
            )

          Text(row.accountText)
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(
              width: UsageTimelineMetrics.accountColumnWidth,
              alignment: .leading,
            )

          Text(row.labelText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

          Text(row.valueText)
            .font(.caption.monospacedDigit())
            .fontWeight(.semibold)
            .lineLimit(1)
            .frame(width: 88, alignment: .trailing)
        }
        .frame(height: UsageTimelineMetrics.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.helpText)
        .contentShape(Rectangle())
        .onTapGesture {
          openAccount(id: row.account.id)
        }
        .help(row.helpText)
      }
    }
  }

  private var identityColumnsWidth: CGFloat {
    UsageTimelineMetrics.percentageColumnWidth
      + UsageTimelineMetrics.providerColumnWidth
      + UsageTimelineMetrics.accountColumnWidth
      + (2 * UsageTimelineMetrics.columnSpacing)
  }

  private func openAccount(id: UUID) {
    guard
      let onOpenAccount,
      let account = accounts.first(where: {
        $0.id == id
      })
    else {
      return
    }
    onOpenAccount(account)
  }
}

extension UsageTimelineSectionPresentation {
  fileprivate var title: String {
    switch kind {
    case .short:
      "5-hour windows"
    case .daily:
      "Daily windows"
    case .weekly:
      "Weekly windows"
    case .monthly:
      "Monthly windows"
    case .custom:
      "Other windows"
    }
  }
}
