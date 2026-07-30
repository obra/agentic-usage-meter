import SwiftUI
import UsageMeterCore

public struct UsageTimelineView: View {
    private let accounts: [AccountViewState]
    private let now: Date
    private let timeZone: TimeZone

    public init(
        accounts: [AccountViewState],
        now: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent,
    ) {
        self.accounts = accounts
        self.now = now
        self.timeZone = timeZone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            timelineSection(
                title: "5-hour windows",
                kind: .short,
            )
            timelineSection(
                title: "Weekly windows",
                kind: .weekly,
            )
        }
    }

    private func timelineSection(
        title: String,
        kind: UsageWindowKind,
    ) -> some View {
        let section = UsageTimelineSectionPresentation(
            kind: kind,
            accounts: accounts,
            now: now,
            timeZone: timeZone,
        )

        return VStack(alignment: .leading, spacing: 7) {
            ZStack {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                }
                HStack(spacing: UsageWindowRow.labelSpacing) {
                    Color.clear
                        .frame(width: UsageWindowRow.labelColumnWidth)
                    Text("Now")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            if section.rows.isEmpty {
                Text("No current data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 34)
            } else {
                ForEach(section.rows) {
                    UsageWindowRow(row: $0)
                }
            }
        }
    }
}
