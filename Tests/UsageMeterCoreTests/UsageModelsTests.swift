import Foundation
import Testing

@testable import UsageMeterCore

@Test
func usageWindowDerivesStartAndRemainingCapacity() throws {
  let reset = Date(timeIntervalSince1970: 2_000_000_000)
  let window = try #require(
    UsageWindow(
      id: "five-hour",
      kind: .short,
      duration: 18000,
      resetAt: reset,
      consumedFraction: 0.81
    )
  )

  #expect(window.startAt == reset.addingTimeInterval(-18000))
  #expect(abs(window.remainingFraction - 0.19) < 0.000_001)
}

@Test
func usageWindowRejectsInvalidProviderValues() {
  let reset = Date(timeIntervalSince1970: 2_000_000_000)

  #expect(
    UsageWindow(
      id: "zero-duration",
      kind: .short,
      duration: 0,
      resetAt: reset,
      consumedFraction: 0.5
    ) == nil
  )
  #expect(
    UsageWindow(
      id: "over-consumed",
      kind: .weekly,
      duration: 604_800,
      resetAt: reset,
      consumedFraction: 1.1
    ) == nil
  )
  #expect(
    UsageWindow(
      id: "not-finite",
      kind: .weekly,
      duration: 604_800,
      resetAt: reset,
      consumedFraction: .infinity
    ) == nil
  )
}

@Test
func zeroUseWindowAcceptsMissingProviderReset() throws {
  let window = try #require(
    UsageWindow(
      id: "inactive",
      kind: .short,
      duration: 18_000,
      resetAt: nil,
      consumedFraction: 0,
    ),
  )

  #expect(window.resetAt == nil)
  #expect(window.startAt == nil)

  let encoded = try JSONEncoder().encode(window)
  let decoded = try JSONDecoder().decode(
    UsageWindow.self,
    from: encoded,
  )
  #expect(decoded == window)
}

@Test
func nonzeroWindowRejectsMissingProviderReset() {
  #expect(
    UsageWindow(
      id: "invalid",
      kind: .weekly,
      duration: 604_800,
      resetAt: nil,
      consumedFraction: 0.01,
    ) == nil,
  )
}

@Test
func usageWindowDecodingRejectsInvalidPersistedValues() {
  let invalidWindow = Data(
    #"{"id":"invalid","kind":"short","duration":0,"resetAt":0,"consumedFraction":0.5}"#.utf8
  )

  #expect(throws: DecodingError.self) {
    _ = try JSONDecoder().decode(UsageWindow.self, from: invalidWindow)
  }
}

@Test
func snapshotKeepsIndependentAccountIdentity() throws {
  let accountID = UUID()
  let window = try #require(
    UsageWindow(
      id: "weekly",
      kind: .weekly,
      duration: 604_800,
      resetAt: Date(timeIntervalSince1970: 2_000_000_000),
      consumedFraction: 0.25
    )
  )

  let snapshot = UsageSnapshot(
    accountID: accountID,
    fetchedAt: Date(timeIntervalSince1970: 1_999_999_000),
    windows: [window]
  )

  #expect(snapshot.accountID == accountID)
  #expect(snapshot.windows == [window])
}

@Test
func legacySnapshotWithoutBalancesStillDecodes() throws {
  let accountID = UUID()
  let encoded = Data(
    """
    {
      "accountID": "\(accountID.uuidString)",
      "fetchedAt": 0,
      "windows": []
    }
    """.utf8,
  )

  let snapshot = try JSONDecoder().decode(
    UsageSnapshot.self,
    from: encoded,
  )

  #expect(snapshot.accountID == accountID)
  #expect(snapshot.balances.isEmpty)
}

@Test
func usageWindowUsesProviderReportedStartWhenAvailable() throws {
  let resetAt = Date(timeIntervalSince1970: 2_000_000_000)
  let reportedStartAt = resetAt.addingTimeInterval(-3600)
  let window = try #require(
    UsageWindow(
      id: "custom",
      kind: .custom,
      duration: 7200,
      resetAt: resetAt,
      consumedFraction: 0.5,
      label: "Burst",
      reportedStartAt: reportedStartAt,
    ),
  )

  #expect(window.startAt == reportedStartAt)
  #expect(window.label == "Burst")
}

@Test
func usageBalanceRejectsMissingLabelsAndInvalidAmounts() {
  #expect(
    UsageBalance(
      id: "credits",
      label: "   ",
      remainingAmount: 100,
      unit: "credits",
    ) == nil,
  )
  #expect(
    UsageBalance(
      id: "credits",
      label: "AI credits",
      remainingAmount: .infinity,
      unit: "credits",
    ) == nil,
  )
}

@Test
func legacyNumericBalanceDecodesAsAvailable() throws {
  let data = Data(
    #"{"id":"credits","label":"Usage credits","remainingAmount":38.42,"unit":"USD"}"#.utf8,
  )

  let balance = try JSONDecoder().decode(
    UsageBalance.self,
    from: data,
  )

  #expect(
    balance.value
      == .available(
        amount: Decimal(string: "38.42")!,
        unit: "USD",
      ),
  )
}

@Test(arguments: [
  UsageBalanceValue.unlimited,
  UsageBalanceValue.disabled,
])
func nonnumericCreditStatesRoundTrip(
  _ value: UsageBalanceValue,
) throws {
  let balance = try #require(
    UsageBalance(
      id: "credits",
      label: "Usage credits",
      value: value,
    ),
  )

  let encoded = try JSONEncoder().encode(balance)
  #expect(
    try JSONDecoder().decode(
      UsageBalance.self,
      from: encoded,
    ) == balance,
  )
}
