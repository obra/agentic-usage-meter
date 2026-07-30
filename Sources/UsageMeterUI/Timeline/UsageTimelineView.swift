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
        let timeline = UsageTimelinePresentation(
            accounts: accounts,
            now: now,
            timeZone: timeZone,
        )

        VStack(alignment: .leading, spacing: 14) {
            ForEach(timeline.sections, id: \.kind) {
                timelineSection($0)
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
                UsageWindowRow(row: $0)
            }
        }
    }
}

private extension UsageTimelineSectionPresentation {
    var title: String {
        switch kind {
        case .short:
            "5-hour windows"
        case .weekly:
            "Weekly windows"
        }
    }
}
