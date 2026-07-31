import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable {
  case claude
  case codex
  case kimi
  case minimax
  case githubCopilot = "github-copilot"
  case antigravity
  case factory
  case openCodeGo = "opencode-go"
  case openCodeZen = "opencode-zen"
  case superGrok = "supergrok"
}

public struct SubscriptionAccount: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public var provider: Provider
  public var displayName: String
  public var authenticatedIdentity: String?
  public var displayOrder: Int
  public var claudeProfileID: UUID?
  public var claudeOrganizationID: UUID?

  public init(
    id: UUID = UUID(),
    provider: Provider,
    displayName: String,
    authenticatedIdentity: String? = nil,
    displayOrder: Int,
    claudeProfileID: UUID? = nil,
    claudeOrganizationID: UUID? = nil,
  ) {
    self.id = id
    self.provider = provider
    self.displayName = displayName
    self.authenticatedIdentity = authenticatedIdentity
    self.displayOrder = displayOrder
    self.claudeProfileID = claudeProfileID
    self.claudeOrganizationID = claudeOrganizationID
  }
}

public enum UsageWindowKind: String, Codable, Sendable {
  case short
  case daily
  case weekly
  case monthly
  case custom
}

public struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let kind: UsageWindowKind
  public let duration: TimeInterval
  public let resetAt: Date?
  public let consumedFraction: Double
  public let label: String?
  public let reportedStartAt: Date?

  public init?(
    id: String,
    kind: UsageWindowKind,
    duration: TimeInterval,
    resetAt: Date?,
    consumedFraction: Double,
    label: String? = nil,
    reportedStartAt: Date? = nil
  ) {
    guard
      !id.isEmpty,
      duration.isFinite,
      duration > 0,
      consumedFraction.isFinite,
      (0...1).contains(consumedFraction),
      resetAt != nil
        || (consumedFraction == 0 && reportedStartAt == nil)
    else {
      return nil
    }

    self.id = id
    self.kind = kind
    self.duration = duration
    self.resetAt = resetAt
    self.consumedFraction = consumedFraction
    self.label = label
    self.reportedStartAt = reportedStartAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(String.self, forKey: .id)
    let kind = try container.decode(UsageWindowKind.self, forKey: .kind)
    let duration = try container.decode(TimeInterval.self, forKey: .duration)
    let resetAt = try container.decodeIfPresent(
      Date.self,
      forKey: .resetAt,
    )
    let consumedFraction = try container.decode(Double.self, forKey: .consumedFraction)
    let label = try container.decodeIfPresent(String.self, forKey: .label)
    let reportedStartAt = try container.decodeIfPresent(
      Date.self,
      forKey: .reportedStartAt,
    )

    guard
      let window = UsageWindow(
        id: id,
        kind: kind,
        duration: duration,
        resetAt: resetAt,
        consumedFraction: consumedFraction,
        label: label,
        reportedStartAt: reportedStartAt,
      )
    else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "Usage window contains invalid values.",
        ),
      )
    }

    self = window
  }

  public var startAt: Date? {
    reportedStartAt ?? resetAt?.addingTimeInterval(-duration)
  }

  public var remainingFraction: Double {
    1 - consumedFraction
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case kind
    case duration
    case resetAt
    case consumedFraction
    case label
    case reportedStartAt
  }
}

public enum UsageBalanceValue: Codable, Equatable, Sendable {
  case available(amount: Decimal, unit: String)
  case unlimited
  case disabled
}

public struct UsageBalance: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let label: String
  public let value: UsageBalanceValue
  public let cycleEndsAt: Date?

  public var remainingAmount: Double? {
    guard case .available(let amount, _) = value else {
      return nil
    }
    return NSDecimalNumber(decimal: amount).doubleValue
  }

  public var unit: String? {
    guard case .available(_, let unit) = value else {
      return nil
    }
    return unit
  }

  public init?(
    id: String,
    label: String,
    remainingAmount: Double,
    unit: String,
    cycleEndsAt: Date? = nil
  ) {
    guard
      remainingAmount.isFinite,
      let amount = Decimal(
        string: String(remainingAmount),
        locale: Locale(identifier: "en_US_POSIX"),
      )
    else {
      return nil
    }
    self.init(
      id: id,
      label: label,
      value: .available(amount: amount, unit: unit),
      cycleEndsAt: cycleEndsAt,
    )
  }

  public init?(
    id: String,
    label: String,
    value: UsageBalanceValue,
    cycleEndsAt: Date? = nil
  ) {
    let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
    let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !id.isEmpty,
      !label.isEmpty,
      let value = Self.normalized(value)
    else {
      return nil
    }

    self.id = id
    self.label = label
    self.value = value
    self.cycleEndsAt = cycleEndsAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let storedState = try container.decodeIfPresent(
      StoredState.self,
      forKey: .state,
    )
    let value: UsageBalanceValue
    switch storedState {
    case nil, .available:
      value = .available(
        amount: try container.decode(
          Decimal.self,
          forKey: .remainingAmount,
        ),
        unit: try container.decode(
          String.self,
          forKey: .unit,
        ),
      )
    case .unlimited:
      value = .unlimited
    case .disabled:
      value = .disabled
    }

    guard
      let balance = try UsageBalance(
        id: container.decode(String.self, forKey: .id),
        label: container.decode(String.self, forKey: .label),
        value: value,
        cycleEndsAt: container.decodeIfPresent(
          Date.self,
          forKey: .cycleEndsAt,
        ),
      )
    else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "Usage balance contains invalid values.",
        ),
      )
    }

    self = balance
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(label, forKey: .label)
    try container.encodeIfPresent(cycleEndsAt, forKey: .cycleEndsAt)

    switch value {
    case .available(let amount, let unit):
      try container.encode(StoredState.available, forKey: .state)
      try container.encode(amount, forKey: .remainingAmount)
      try container.encode(unit, forKey: .unit)
    case .unlimited:
      try container.encode(StoredState.unlimited, forKey: .state)
    case .disabled:
      try container.encode(StoredState.disabled, forKey: .state)
    }
  }

  private static func normalized(
    _ value: UsageBalanceValue,
  ) -> UsageBalanceValue? {
    switch value {
    case .available(let amount, let unit):
      let unit = unit.trimmingCharacters(
        in: .whitespacesAndNewlines,
      )
      guard
        !amount.isNaN,
        NSDecimalNumber(decimal: amount).doubleValue.isFinite,
        !unit.isEmpty
      else {
        return nil
      }
      return .available(amount: amount, unit: unit)
    case .unlimited:
      return .unlimited
    case .disabled:
      return .disabled
    }
  }

  private enum StoredState: String, Codable {
    case available
    case unlimited
    case disabled
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case label
    case state
    case remainingAmount
    case unit
    case cycleEndsAt
  }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
  public let accountID: UUID
  public let fetchedAt: Date
  public let windows: [UsageWindow]
  public let balances: [UsageBalance]

  public init(
    accountID: UUID,
    fetchedAt: Date,
    windows: [UsageWindow],
    balances: [UsageBalance] = []
  ) {
    self.accountID = accountID
    self.fetchedAt = fetchedAt
    self.windows = windows
    self.balances = balances
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    accountID = try container.decode(UUID.self, forKey: .accountID)
    fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
    windows = try container.decode([UsageWindow].self, forKey: .windows)
    balances =
      try container.decodeIfPresent(
        [UsageBalance].self,
        forKey: .balances,
      ) ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case accountID
    case fetchedAt
    case windows
    case balances
  }
}
