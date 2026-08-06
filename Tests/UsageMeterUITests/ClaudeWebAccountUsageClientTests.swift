import Foundation
import Testing
import UsageMeterClaudeWeb
import UsageMeterCore
@testable import UsageMeterUI

@MainActor
@Suite
struct ClaudeWebAccountUsageClientTests {
    @Test
    func removalReleasesTheProfileBeforeRemovingItsStore() async throws {
        let profileID = UUID()
        let recorder = RemovalOrderRecorder()
        let cookieSource = RemovalRecordingCookieSource(
            recorder: recorder,
        )
        let adapter = ClaudeWebAccountUsageClient(
            client: ClaudeWebUsageClient(
                transport: FailingHTTPTransport(),
                cookieSource: cookieSource,
            ),
            removeProfile: { removedProfileID in
                recorder.events.append(
                    "remove:\(removedProfileID)",
                )
            },
        )
        let account = SubscriptionAccount(
            provider: .claude,
            displayName: "Personal",
            displayOrder: 0,
            claudeProfileID: profileID,
            claudeOrganizationID: UUID(),
        )

        try await adapter.removeAuthentication(for: account)

        #expect(
            recorder.events == [
                "prepare:\(profileID)",
                "remove:\(profileID)",
                "finish:\(profileID)",
            ],
        )
    }

    @Test
    func removalFailureStillReleasesTheRemovalLease() async throws {
        let profileID = UUID()
        let recorder = RemovalOrderRecorder()
        let cookieSource = RemovalRecordingCookieSource(
            recorder: recorder,
        )
        let adapter = ClaudeWebAccountUsageClient(
            client: ClaudeWebUsageClient(
                transport: FailingHTTPTransport(),
                cookieSource: cookieSource,
            ),
            removeProfile: { _ in
                throw ProviderClientError.temporaryFailure
            },
        )
        let account = SubscriptionAccount(
            provider: .claude,
            displayName: "Personal",
            displayOrder: 0,
            claudeProfileID: profileID,
            claudeOrganizationID: UUID(),
        )

        await #expect(throws: ProviderClientError.temporaryFailure) {
            try await adapter.removeAuthentication(for: account)
        }
        #expect(
            recorder.events == [
                "prepare:\(profileID)",
                "finish:\(profileID)",
            ],
        )
    }
}

@MainActor
private final class RemovalOrderRecorder {
    var events: [String] = []
}

@MainActor
private final class RemovalRecordingCookieSource:
    ClaudeWebCookieSource
{
    private let recorder: RemovalOrderRecorder

    init(recorder: RemovalOrderRecorder) {
        self.recorder = recorder
    }

    func cookies(
        for _: URL,
        profileID _: UUID,
    ) async -> [HTTPCookie] {
        []
    }

    func prepareForRemoval(profileID: UUID) {
        recorder.events.append("prepare:\(profileID)")
    }

    func finishRemoval(profileID: UUID) {
        recorder.events.append("finish:\(profileID)")
    }
}

private struct FailingHTTPTransport: HTTPTransport {
    func send(_: URLRequest) async throws -> HTTPResponse {
        throw HTTPTransportError.nonHTTPResponse
    }
}
