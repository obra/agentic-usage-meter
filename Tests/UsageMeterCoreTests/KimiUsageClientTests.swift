import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct KimiUsageClientTests {
  @Test
  func requestAndResponseMapCurrentKimiWindows() async throws {
    let responseData = try usageFixture(named: "kimi-usage")
    let transport = KimiUsageRecordingTransport(
      response: HTTPResponse(
        data: responseData,
        statusCode: 200,
        headers: [:]
      )
    )
    let client = KimiUsageClient(transport: transport)
    let accountID = UUID()
    let fetchedAt = Date(timeIntervalSince1970: 2_000_000_000)

    let snapshot = try await client.fetchUsage(
      accountID: accountID,
      credential: .kimi(
        OAuthCredential(accessToken: "access-token")
      ),
      now: fetchedAt
    )

    #expect(snapshot.accountID == accountID)
    #expect(snapshot.fetchedAt == fetchedAt)
    #expect(snapshot.windows.count == 2)
    #expect(snapshot.windows[0].kind == .short)
    #expect(snapshot.windows[0].duration == 18_000)
    #expect(snapshot.windows[0].consumedFraction == 0.4)
    #expect(
      snapshot.windows[0].resetAt
        == fetchedAt.addingTimeInterval(3_600)
    )
    #expect(snapshot.windows[1].kind == .weekly)
    #expect(snapshot.windows[1].duration == 604_800)
    #expect(snapshot.windows[1].consumedFraction == 0.25)
    #expect(
      snapshot.windows[1].resetAt
        == Date(timeIntervalSince1970: 2_000_000_000)
    )

    let request = try #require(await transport.lastRequest)
    #expect(request.httpMethod == "GET")
    #expect(
      request.url?.absoluteString
        == "https://api.kimi.com/coding/v1/usages"
    )
    #expect(
      request.value(forHTTPHeaderField: "Authorization")
        == "Bearer access-token"
    )
  }

  @Test
  func acceptsItemLevelLimitAndCurrentFieldAliases() async throws {
    let response = Data(
      """
      {
        "limits": [
          {
            "limit": "200",
            "used": "50",
            "reset_at": "2033-05-18T03:33:20.123456789Z",
            "duration": 5,
            "timeUnit": "HOUR"
          }
        ]
      }
      """.utf8
    )
    let client = KimiUsageClient(
      transport: KimiUsageRecordingTransport(
        response: HTTPResponse(
          data: response,
          statusCode: 200,
          headers: [:]
        )
      )
    )

    let snapshot = try await client.fetchUsage(
      accountID: UUID(),
      credential: .kimi(
        OAuthCredential(accessToken: "access-token")
      ),
      now: Date(timeIntervalSince1970: 2_000_000_000)
    )

    let window = try #require(snapshot.windows.first)
    #expect(window.kind == .short)
    #expect(window.duration == 18_000)
    #expect(window.consumedFraction == 0.25)
    #expect(
      try #require(window.resetAt).timeIntervalSince1970
        == 2_000_000_000.123456
    )
  }

  @Test
  func malformedSupportedWindowIsRejected() async {
    let response = Data(
      """
      {
        "usage": {
          "limit": 100,
          "used": 25,
          "resetAt": "2033-05-18T03:33:20Z"
        },
        "limits": [
          {
            "window": {
              "duration": 300,
              "timeUnit": "MINUTE"
            },
            "detail": {
              "limit": 100,
              "used": 125,
              "resetIn": 3600
            }
          }
        ]
      }
      """.utf8
    )
    let client = KimiUsageClient(
      transport: KimiUsageRecordingTransport(
        response: HTTPResponse(
          data: response,
          statusCode: 200,
          headers: [:]
        )
      )
    )

    await #expect(throws: ProviderClientError.unsupportedResponse) {
      _ = try await client.fetchUsage(
        accountID: UUID(),
        credential: .kimi(
          OAuthCredential(accessToken: "access-token")
        ),
        now: Date(timeIntervalSince1970: 2_000_000_000)
      )
    }
  }

  @Test
  func malformedWeeklySummaryIsRejectedWhenShortWindowIsValid() async {
    let response = Data(
      """
      {
        "usage": {
          "limit": 0,
          "used": 0,
          "resetAt": "2033-05-18T03:33:20Z"
        },
        "limits": [
          {
            "window": {
              "duration": 300,
              "timeUnit": "MINUTE"
            },
            "detail": {
              "limit": 100,
              "used": 25,
              "resetIn": 3600
            }
          }
        ]
      }
      """.utf8
    )
    let client = KimiUsageClient(
      transport: KimiUsageRecordingTransport(
        response: HTTPResponse(
          data: response,
          statusCode: 200,
          headers: [:]
        )
      )
    )

    await #expect(throws: ProviderClientError.unsupportedResponse) {
      _ = try await client.fetchUsage(
        accountID: UUID(),
        credential: .kimi(
          OAuthCredential(accessToken: "access-token")
        ),
        now: Date(timeIntervalSince1970: 2_000_000_000)
      )
    }
  }

  @Test
  func credentialMustBeKimiAndIncludeAccessToken() async {
    let transport = KimiUsageRecordingTransport(
      response: HTTPResponse(
        data: Data(),
        statusCode: 200,
        headers: [:]
      )
    )
    let client = KimiUsageClient(transport: transport)
    let invalidCredentials: [ProviderCredential] = [
      .codex(OAuthCredential(accessToken: "wrong-provider")),
      .kimi(OAuthCredential(accessToken: "")),
    ]

    for credential in invalidCredentials {
      await #expect(throws: ProviderClientError.credentialMismatch) {
        _ = try await client.fetchUsage(
          accountID: UUID(),
          credential: credential,
          now: Date()
        )
      }
    }

    #expect(await transport.lastRequest == nil)
  }

  @Test
  func statusCodesMapToProviderFailures() async {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let cases: [(Int, [String: String], ProviderClientError)] = [
      (401, [:], .reauthenticationRequired),
      (403, [:], .reauthenticationRequired),
      (
        429,
        ["Retry-After": "600"],
        .retryAfter(now.addingTimeInterval(600))
      ),
      (500, [:], .temporaryFailure),
    ]

    for (statusCode, headers, expectedError) in cases {
      let client = KimiUsageClient(
        transport: KimiUsageRecordingTransport(
          response: HTTPResponse(
            data: Data(),
            statusCode: statusCode,
            headers: headers
          )
        )
      )

      await #expect(throws: expectedError) {
        _ = try await client.fetchUsage(
          accountID: UUID(),
          credential: .kimi(
            OAuthCredential(accessToken: "access-token")
          ),
          now: now
        )
      }
    }
  }
}

private actor KimiUsageRecordingTransport: HTTPTransport {
  private let response: HTTPResponse
  private(set) var lastRequest: URLRequest?

  init(response: HTTPResponse) {
    self.response = response
  }

  func send(_ request: URLRequest) -> HTTPResponse {
    lastRequest = request
    return response
  }
}
