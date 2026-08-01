import Foundation
import UsageMeterCore

struct UsagePoolShelfItemPresentation:
  Equatable,
  Identifiable,
  Sendable
{
  let id: String
  let account: SubscriptionAccount
  let accountText: String
  let detailText: String
  let remainingFraction: Double
  let accessibilityValue: String

  init(_ row: UsageTimelineRowPresentation) {
    id = row.id
    account = row.account
    accountText = row.account.displayName.trimmingCharacters(
      in: .whitespacesAndNewlines,
    )
    let percentage =
      row.windowPresentation.remainingPercentageText
    detailText = row.window.label.map {
      "\(percentage) · \($0)"
    } ?? percentage
    remainingFraction = row.window.remainingFraction
    accessibilityValue =
      row.windowPresentation.accessibilityValue
  }
}

struct UsageBalanceShelfItemPresentation:
  Equatable,
  Identifiable,
  Sendable
{
  let id: String
  let account: SubscriptionAccount
  let accountText: String
  let detailText: String
  let accessibilityValue: String

  init(_ row: UsageBalanceRowPresentation) {
    id = row.id
    account = row.account
    accountText = row.accountText
    detailText = row.valueText
    accessibilityValue = row.helpText
  }
}
