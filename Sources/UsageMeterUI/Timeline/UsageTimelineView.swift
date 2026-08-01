import SwiftUI
import UsageMeterCore

public struct UsageTimelineView: View {
  private let accounts: [AccountViewState]
  private let now: Date
  private let timeZone: TimeZone
  private let collapsedSections: Set<UsageSectionID>
  private let onToggleSection: ((UsageSectionID) -> Void)?
  private let onOpenAccount: ((AccountViewState) -> Void)?

  public init(
    accounts: [AccountViewState],
    now: Date = Date(),
    timeZone: TimeZone = .autoupdatingCurrent,
    collapsedSections: Set<UsageSectionID> = [],
    onToggleSection: ((UsageSectionID) -> Void)? = nil,
    onOpenAccount: ((AccountViewState) -> Void)? = nil,
  ) {
    self.accounts = accounts
    self.now = now
    self.timeZone = timeZone
    self.collapsedSections = collapsedSections
    self.onToggleSection = onToggleSection
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
    let sectionID = section.kind.sectionID
    let isCollapsed =
      onToggleSection != nil
      && collapsedSections.contains(sectionID)
    let toggleAction = onToggleSection.map { toggle in
      { toggle(sectionID) }
    }

    return VStack(
      alignment: .leading,
      spacing: UsageTimelineMetrics.sectionContentSpacing,
    ) {
      UsageSectionDisclosureHeader(
        title: section.title,
        identityColumnsWidth: identityColumnsWidth,
        showsTimelineColumns: true,
        isExpanded: !isCollapsed,
        onToggle: toggleAction,
      )

      if isCollapsed {
        CollapsedUsagePoolShelf(
          rows: section.rows,
          onOpenAccount: openAccount,
        )
      } else {
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
  }

  private func balanceSection(
    _ rows: [UsageBalanceRowPresentation],
  ) -> some View {
    let isCollapsed =
      onToggleSection != nil
      && collapsedSections.contains(.extraCredits)
    let toggleAction = onToggleSection.map { toggle in
      { toggle(.extraCredits) }
    }

    return VStack(
      alignment: .leading,
      spacing: UsageTimelineMetrics.sectionContentSpacing,
    ) {
      UsageSectionDisclosureHeader(
        title: "Extra Credits",
        identityColumnsWidth: identityColumnsWidth,
        showsTimelineColumns: false,
        isExpanded: !isCollapsed,
        onToggle: toggleAction,
      )

      if isCollapsed {
        CollapsedUsageBalanceShelf(
          rows: rows,
          onOpenAccount: openAccount,
        )
      } else {
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

extension UsageWindowKind {
  fileprivate var sectionID: UsageSectionID {
    switch self {
    case .short:
      .short
    case .daily:
      .daily
    case .weekly:
      .weekly
    case .monthly:
      .monthly
    case .custom:
      .custom
    }
  }
}
