import Foundation

public struct TimelineLayout: Equatable, Sendable {
  public let start: Date
  public let end: Date

  public init?(duration: TimeInterval, now: Date) {
    guard duration.isFinite, duration > 0 else {
      return nil
    }

    start = now.addingTimeInterval(-duration)
    end = now.addingTimeInterval(duration)
  }

  public func xFraction(for window: UsageWindow) -> Double {
    let windowStart =
      window.startAt
      ?? start.addingTimeInterval(span / 2)
    return clamped(windowStart.timeIntervalSince(start) / span)
  }

  public func widthFraction(for window: UsageWindow) -> Double {
    clamped(window.duration / span)
  }

  private var span: TimeInterval {
    end.timeIntervalSince(start)
  }

  private func clamped(_ value: Double) -> Double {
    min(max(value, 0), 1)
  }
}
