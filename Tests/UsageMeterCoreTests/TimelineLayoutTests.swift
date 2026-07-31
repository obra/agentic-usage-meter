import Foundation
import Testing

@testable import UsageMeterCore

@Test
func fourteenDayLayoutCentersNowAndUsesSevenDayBars() throws {
  let now = Date(timeIntervalSince1970: 2_000_000_000)
  let layout = try #require(TimelineLayout(duration: 604_800, now: now))
  let reset = now.addingTimeInterval(172_800)
  let window = try #require(
    UsageWindow(
      id: "weekly",
      kind: .weekly,
      duration: 604_800,
      resetAt: reset,
      consumedFraction: 0.25
    )
  )

  #expect(layout.start == now.addingTimeInterval(-604_800))
  #expect(layout.end == now.addingTimeInterval(604_800))
  #expect(abs(layout.widthFraction(for: window) - 0.5) < 0.000_001)
  #expect(abs(layout.xFraction(for: window) - (2.0 / 14.0)) < 0.000_001)
}

@Test
func layoutClampsWindowsAtItsVisibleEdges() throws {
  let now = Date(timeIntervalSince1970: 2_000_000_000)
  let layout = try #require(TimelineLayout(duration: 18_000, now: now))
  let window = try #require(
    UsageWindow(
      id: "outside",
      kind: .short,
      duration: 18_000,
      resetAt: now.addingTimeInterval(36_000),
      consumedFraction: 0
    )
  )

  #expect(layout.xFraction(for: window) == 1)
  #expect(layout.widthFraction(for: window) == 0.5)
}

@Test
func resetlessWindowBeginsAtNowOnTheSharedAxis() throws {
  let now = Date(timeIntervalSince1970: 2_000_000_000)
  let layout = try #require(
    TimelineLayout(duration: 18_000, now: now),
  )
  let window = try #require(
    UsageWindow(
      id: "inactive",
      kind: .short,
      duration: 18_000,
      resetAt: nil,
      consumedFraction: 0,
    ),
  )

  #expect(layout.xFraction(for: window) == 0.5)
  #expect(layout.widthFraction(for: window) == 0.5)
}
