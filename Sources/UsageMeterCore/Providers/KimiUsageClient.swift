import Foundation

public struct KimiUsageClient: UsageProviderClient {
  public let provider = Provider.kimi

  private let transport: any HTTPTransport
  private let decoder: KimiUsageDecoder

  public init(
    transport: any HTTPTransport = URLSessionHTTPTransport(),
    decoder: KimiUsageDecoder = KimiUsageDecoder()
  ) {
    self.transport = transport
    self.decoder = decoder
  }

  public func fetchUsage(
    accountID: UUID,
    credential: ProviderCredential,
    now: Date
  ) async throws -> UsageSnapshot {
    guard
      case let .kimi(oauth) = credential,
      !oauth.accessToken.isEmpty
    else {
      throw ProviderClientError.credentialMismatch
    }

    var request = URLRequest(
      url: URL(
        string: "https://api.kimi.com/coding/v1/usages"
      )!
    )
    request.httpMethod = "GET"
    request.setValue(
      "Bearer \(oauth.accessToken)",
      forHTTPHeaderField: "Authorization"
    )

    let response = try await transport.send(request)
    switch response.statusCode {
    case 200...299:
      return try decoder.decode(
        response.data,
        accountID: accountID,
        fetchedAt: now
      )
    case 401, 403:
      throw ProviderClientError.reauthenticationRequired
    case 429:
      throw ProviderClientError.retryAfter(
        response.retryDate(relativeTo: now)
      )
    default:
      throw ProviderClientError.temporaryFailure
    }
  }
}

public struct KimiUsageDecoder: Sendable {
  public init() {}

  public func decode(
    _ data: Data,
    accountID: UUID,
    fetchedAt: Date
  ) throws -> UsageSnapshot {
    let response: KimiUsageResponse
    do {
      response = try JSONDecoder().decode(
        KimiUsageResponse.self,
        from: data
      )
    } catch {
      throw ProviderClientError.unsupportedResponse
    }

    var windowsByKind: [UsageWindowKind: UsageWindow] = [:]
    for limit in response.limits ?? [] {
      guard let seconds = limit.window.durationInSeconds else {
        continue
      }
      guard let kind = windowKind(for: seconds) else {
        continue
      }
      guard
        let window = makeWindow(
          detail: limit.detail,
          kind: kind,
          duration: seconds,
          fetchedAt: fetchedAt
        )
      else {
        throw ProviderClientError.unsupportedResponse
      }
      windowsByKind[kind] = window
    }

    if windowsByKind[.weekly] == nil, let summary = response.usage {
      guard
        let weekly = makeWindow(
          detail: summary,
          kind: .weekly,
          duration: 604_800,
          fetchedAt: fetchedAt
        )
      else {
        throw ProviderClientError.unsupportedResponse
      }
      windowsByKind[.weekly] = weekly
    }

    let windows = [
      windowsByKind[.short],
      windowsByKind[.weekly],
    ].compactMap(\.self)
    guard !windows.isEmpty else {
      throw ProviderClientError.unsupportedResponse
    }
    return UsageSnapshot(
      accountID: accountID,
      fetchedAt: fetchedAt,
      windows: windows
    )
  }

  private func makeWindow(
    detail: KimiUsageResponse.Detail,
    kind: UsageWindowKind,
    duration: TimeInterval,
    fetchedAt: Date
  ) -> UsageWindow? {
    guard
      let limit = detail.limit,
      limit.isFinite,
      limit > 0
    else {
      return nil
    }
    let used = detail.used ?? detail.remaining.map { limit - $0 }
    guard
      let used,
      used.isFinite,
      (0...limit).contains(used),
      let resetAt = detail.resetAt(relativeTo: fetchedAt)
    else {
      return nil
    }

    return UsageWindow(
      id: "kimi-\(kind.rawValue)",
      kind: kind,
      duration: duration,
      resetAt: resetAt,
      consumedFraction: used / limit
    )
  }

  private func windowKind(
    for duration: TimeInterval
  ) -> UsageWindowKind? {
    switch duration {
    case 18_000:
      .short
    case 604_800:
      .weekly
    default:
      nil
    }
  }
}

private struct KimiUsageResponse: Decodable {
  let usage: Detail?
  let limits: [Limit]?

  struct Limit: Decodable {
    let window: Window
    let detail: Detail

    private enum CodingKeys: String, CodingKey {
      case window
      case detail
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(
        keyedBy: CodingKeys.self
      )
      window =
        try container.decodeIfPresent(
          Window.self,
          forKey: .window
        )
        ?? Window(from: decoder)
      detail =
        try container.decodeIfPresent(
          Detail.self,
          forKey: .detail
        )
        ?? Detail(from: decoder)
    }
  }

  struct Window: Decodable {
    let duration: TimeInterval?
    let timeUnit: String?

    private enum CodingKeys: String, CodingKey {
      case duration
      case timeUnit
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(
        keyedBy: CodingKeys.self
      )
      duration = container.flexibleDouble(forKey: .duration)
      timeUnit = try container.decodeIfPresent(
        String.self,
        forKey: .timeUnit
      )
    }

    var durationInSeconds: TimeInterval? {
      guard
        let duration,
        duration.isFinite,
        duration > 0,
        let timeUnit
      else {
        return nil
      }
      return switch timeUnit.uppercased() {
      case "MINUTE", "MINUTES":
        duration * 60
      case "HOUR", "HOURS":
        duration * 3_600
      case "DAY", "DAYS":
        duration * 86_400
      case "SECOND", "SECONDS":
        duration
      default:
        nil
      }
    }
  }

  struct Detail: Decodable {
    let limit: Double?
    let used: Double?
    let remaining: Double?
    let resetAtValue: String?
    let resetIn: TimeInterval?

    enum CodingKeys: String, CodingKey {
      case limit
      case used
      case remaining
      case resetAt
      case resetAtSnake = "reset_at"
      case resetTime = "resetTime"
      case resetTimeSnake = "reset_time"
      case resetIn
      case resetInSnake = "reset_in"
      case ttl
      case window
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(
        keyedBy: CodingKeys.self
      )
      limit = container.flexibleDouble(forKey: .limit)
      used = container.flexibleDouble(forKey: .used)
      remaining = container.flexibleDouble(forKey: .remaining)
      resetAtValue =
        try container.decodeIfPresent(
          String.self,
          forKey: .resetAt
        )
        ?? container.decodeIfPresent(
          String.self,
          forKey: .resetAtSnake
        )
        ?? container.decodeIfPresent(
          String.self,
          forKey: .resetTime
        )
        ?? container.decodeIfPresent(
          String.self,
          forKey: .resetTimeSnake
        )
      resetIn =
        container.flexibleDouble(forKey: .resetIn)
        ?? container.flexibleDouble(forKey: .resetInSnake)
        ?? container.flexibleDouble(forKey: .ttl)
        ?? container.flexibleDouble(forKey: .window)
    }

    func resetAt(relativeTo fetchedAt: Date) -> Date? {
      if let resetAtValue {
        if let fractionStart = resetAtValue.firstIndex(of: "."),
          let zoneStart = resetAtValue[fractionStart...]
            .firstIndex(where: {
              $0 == "Z" || $0 == "+" || $0 == "-"
            }),
          let fraction = Double(
            "0."
              + resetAtValue[
                resetAtValue.index(after: fractionStart)..<zoneStart
              ].prefix(6)
          )
        {
          let wholeSeconds =
            resetAtValue[..<fractionStart]
            + resetAtValue[zoneStart...]
          if let date = ISO8601DateFormatter().date(
            from: String(wholeSeconds)
          ) {
            return date.addingTimeInterval(fraction)
          }
        }
        return ISO8601DateFormatter().date(from: resetAtValue)
      }
      guard
        let resetIn,
        resetIn.isFinite,
        resetIn >= 0
      else {
        return nil
      }
      return fetchedAt.addingTimeInterval(resetIn)
    }
  }
}

extension KeyedDecodingContainer {
  fileprivate func flexibleDouble(forKey key: Key) -> Double? {
    if let value = try? decodeIfPresent(Double.self, forKey: key) {
      return value
    }
    guard
      let value = try? decodeIfPresent(String.self, forKey: key)
    else {
      return nil
    }
    return Double(value)
  }
}
