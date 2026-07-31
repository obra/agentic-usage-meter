import Foundation
import UsageMeterCore

public struct UsageWindowPresentation: Equatable, Sendable {
  public let provider: Provider
  public let providerText: String
  public let accountText: String
  public let outerXFraction: Double
  public let outerWidthFraction: Double
  public let fillFraction: Double
  public let nowXFraction: Double
  public let remainingPercentageText: String
  public let relativeResetText: String
  public let exactResetText: String?
  public let helpText: String
  public let accessibilityValue: String

  public init(
    account: SubscriptionAccount,
    window: UsageWindow,
    now: Date,
    timeZone: TimeZone = .autoupdatingCurrent,
    axisDuration: TimeInterval? = nil,
  ) {
    provider = account.provider
    let identity = usageIdentity(for: account)
    providerText = identity.providerText
    accountText = identity.accountText

    let layout = TimelineLayout(
      duration: axisDuration
        ?? window.kind.defaultAxisDuration(
          customDuration: window.duration,
        ),
      now: now,
    )!
    outerXFraction = layout.xFraction(for: window)
    outerWidthFraction = layout.widthFraction(for: window)
    fillFraction = window.consumedFraction
    nowXFraction = 0.5

    let remainingPercent = Int(
      (window.remainingFraction * 100).rounded(),
    )
    remainingPercentageText = "\(remainingPercent)%"
    if let resetAt = window.resetAt {
      relativeResetText = Self.relativeResetText(
        from: now,
        to: resetAt,
      )

      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = timeZone
      formatter.dateFormat = "EEE h:mm a"
      let formattedReset = formatter.string(from: resetAt)
      exactResetText = formattedReset
      helpText = "Resets \(formattedReset)"
    } else {
      relativeResetText = Self.relativeResetText(
        from: now,
        to: now.addingTimeInterval(window.duration),
      )
      exactResetText = nil
      helpText = "No provider reset reported"
    }

    let windowName =
      switch window.kind {
      case .short:
        "five-hour"
      case .daily:
        "daily"
      case .weekly:
        "weekly"
      case .monthly:
        "monthly"
      case .custom:
        window.label ?? "custom"
      }
    let resetAccessibilityText =
      if let exactResetText {
        "resets \(exactResetText)"
      } else {
        "allowance unused, no provider reset reported, "
          + "displayed empty window starts now"
      }
    accessibilityValue =
      "\(providerText), \(account.displayName), "
      + "\(windowName) window, \(remainingPercent) percent remaining, "
      + resetAccessibilityText
  }

  private static func relativeResetText(
    from now: Date,
    to resetAt: Date,
  ) -> String {
    let interval = resetAt.timeIntervalSince(now)
    guard interval > 0 else {
      return "Now"
    }

    let totalMinutes = Int(interval) / 60
    if totalMinutes < 60 {
      return "\(totalMinutes)m"
    }

    let totalHours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if totalHours < 24 {
      return "\(totalHours)h \(minutes)m"
    }

    let days = totalHours / 24
    let hours = totalHours % 24
    return "\(days)d \(hours)h"
  }
}

public struct UsageTimelineRowPresentation:
  Equatable,
  Identifiable,
  Sendable
{
  public let account: SubscriptionAccount
  public let window: UsageWindow
  public let windowPresentation: UsageWindowPresentation

  public var id: String {
    "\(account.id.uuidString):\(window.id)"
  }
}

public struct UsageTimelineSectionPresentation:
  Equatable,
  Sendable
{
  public let kind: UsageWindowKind
  public let rows: [UsageTimelineRowPresentation]

  public init(
    kind: UsageWindowKind,
    accounts: [AccountViewState],
    now: Date,
    timeZone: TimeZone = .autoupdatingCurrent,
  ) {
    self.kind = kind
    let matchingWindows =
      accounts
      .sorted(by: accountStateComesBefore)
      .flatMap { state in
        (state.snapshot?.windows ?? [])
          .filter { $0.kind == kind }
          .map { window in
            (account: state.account, window: window)
          }
      }
    let axisDuration = kind.defaultAxisDuration(
      customDuration:
        matchingWindows.map { $0.window.duration }.max() ?? 1,
    )
    rows = matchingWindows.map { item in
      UsageTimelineRowPresentation(
        account: item.account,
        window: item.window,
        windowPresentation: UsageWindowPresentation(
          account: item.account,
          window: item.window,
          now: now,
          timeZone: timeZone,
          axisDuration: axisDuration,
        ),
      )
    }
  }
}

public struct UsageBalanceRowPresentation:
  Equatable,
  Identifiable,
  Sendable
{
  public let account: SubscriptionAccount
  public let balance: UsageBalance
  public let providerText: String
  public let accountText: String
  public let labelText: String
  public let valueText: String
  public let cycleEndText: String?

  public var helpText: String {
    var components = [providerText, accountText, labelText, valueText]
    if let cycleEndText {
      components.append("Cycle ends \(cycleEndText)")
    }
    return components.joined(separator: ", ")
  }

  public var id: String {
    "\(account.id.uuidString):balance:\(balance.id)"
  }

  public init(
    account: SubscriptionAccount,
    balance: UsageBalance,
    timeZone: TimeZone = .autoupdatingCurrent,
  ) {
    self.account = account
    self.balance = balance

    let identity = usageIdentity(for: account)
    providerText = identity.providerText
    accountText = identity.accountText
    labelText = balance.label

    switch balance.value {
    case .available(let amount, let unit):
      valueText = Self.format(amount: amount, unit: unit)
    case .unlimited:
      valueText = "Unlimited"
    case .disabled:
      valueText = "Off"
    }

    if let cycleEndsAt = balance.cycleEndsAt {
      let dateFormatter = DateFormatter()
      dateFormatter.locale = Locale(identifier: "en_US_POSIX")
      dateFormatter.timeZone = timeZone
      dateFormatter.dateFormat = "EEE h:mm a"
      cycleEndText = dateFormatter.string(from: cycleEndsAt)
    } else {
      cycleEndText = nil
    }
  }

  private static func format(
    amount: Decimal,
    unit: String,
  ) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US")
    let number = NSDecimalNumber(decimal: amount)

    if unit.count == 3,
      unit.allSatisfy({ $0.isASCII && $0.isLetter })
    {
      formatter.numberStyle = .currency
      formatter.currencyCode = unit.uppercased()
      return formatter.string(from: number)
        ?? "\(number) \(unit)"
    }

    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 8
    let amountText = formatter.string(from: number) ?? "\(number)"
    return "\(amountText) \(unit)"
  }
}

public struct UsageTimelinePresentation: Equatable, Sendable {
  public let sections: [UsageTimelineSectionPresentation]
  public let balanceRows: [UsageBalanceRowPresentation]

  public init(
    accounts: [AccountViewState],
    now: Date,
    timeZone: TimeZone = .autoupdatingCurrent,
  ) {
    sections = UsageWindowKind.presentationOrder.compactMap { kind in
      let section = UsageTimelineSectionPresentation(
        kind: kind,
        accounts: accounts,
        now: now,
        timeZone: timeZone,
      )
      return section.rows.isEmpty ? nil : section
    }
    balanceRows =
      accounts
      .sorted(by: accountStateComesBefore)
      .flatMap { state in
        (state.snapshot?.balances ?? []).map { balance in
          UsageBalanceRowPresentation(
            account: state.account,
            balance: balance,
            timeZone: timeZone,
          )
        }
      }
  }
}

extension UsageWindowKind {
  fileprivate static let presentationOrder: [UsageWindowKind] = [
    .short,
    .daily,
    .weekly,
    .monthly,
    .custom,
  ]

  fileprivate func defaultAxisDuration(
    customDuration: TimeInterval,
  ) -> TimeInterval {
    switch self {
    case .short:
      18000
    case .daily:
      86400
    case .weekly:
      604_800
    case .monthly:
      2_678_400
    case .custom:
      customDuration
    }
  }
}

private func usageIdentity(
  for account: SubscriptionAccount,
) -> (providerText: String, accountText: String) {
  let providerText =
    ProviderCatalog.live.definition(
      for: account.provider,
    )?.displayName
    ?? account.provider.rawValue
  let trimmedAccountName = account.displayName.trimmingCharacters(
    in: .whitespacesAndNewlines,
  )
  return (providerText, trimmedAccountName)
}

private func accountStateComesBefore(
  _ lhs: AccountViewState,
  _ rhs: AccountViewState,
) -> Bool {
  let lhsProvider = ProviderCatalog.live.sortIndex(
    for: lhs.account.provider,
  )
  let rhsProvider = ProviderCatalog.live.sortIndex(
    for: rhs.account.provider,
  )
  if lhsProvider != rhsProvider {
    return lhsProvider < rhsProvider
  }
  if lhs.account.displayOrder != rhs.account.displayOrder {
    return lhs.account.displayOrder < rhs.account.displayOrder
  }
  return lhs.id.uuidString < rhs.id.uuidString
}
