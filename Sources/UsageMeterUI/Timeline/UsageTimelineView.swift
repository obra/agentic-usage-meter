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

        VStack(alignment: .leading, spacing: 14) {
            ForEach(timeline.sections, id: \.kind) {
                timelineSection($0)
            }
            if !timeline.balanceRows.isEmpty {
                balanceSection(timeline.balanceRows)
            }
        }
    }

    private func timelineSection(
        _ section: UsageTimelineSectionPresentation,
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                HStack {
                    Text(section.title)
                        .font(.headline)
                    Spacer()
                }
                HStack(spacing: UsageWindowRow.columnSpacing) {
                    Color.clear
                        .frame(
                            width:
                            UsageWindowRow
                                .percentageColumnWidth,
                        )
                    Color.clear
                        .frame(
                            width:
                            UsageWindowRow
                                .identityColumnWidth,
                        )
                    Text("Now")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Color.clear
                        .frame(
                            width:
                            UsageWindowRow
                                .resetColumnWidth,
                        )
                }
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
        VStack(alignment: .leading, spacing: 7) {
            Text("Balances")
                .font(.headline)

            ForEach(rows) { row in
                HStack(spacing: UsageWindowRow.columnSpacing) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(row.account.provider.timelineColor)
                            .frame(width: 7, height: 7)
                        Text(row.providerText)
                            .foregroundStyle(.secondary)
                        if let accountText = row.accountText {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(accountText)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                    }
                    .frame(
                        width:
                        UsageWindowRow.percentageColumnWidth
                            + UsageWindowRow.identityColumnWidth
                            + UsageWindowRow.columnSpacing,
                        alignment: .leading,
                    )

                    Text(row.balance.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(row.amountText)
                        .font(.caption.monospacedDigit())
                        .fontWeight(.semibold)

                    if let cycleEndText = row.cycleEndText {
                        Text(cycleEndText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: UsageWindowRow.rowHeight)
                .accessibilityElement(children: .combine)
                .contentShape(Rectangle())
                .onTapGesture {
                    openAccount(id: row.account.id)
                }
            }
        }
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

private extension UsageTimelineSectionPresentation {
    var title: String {
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
