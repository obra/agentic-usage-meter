import Combine
import Foundation
import UsageMeterClaudeWeb
import UsageMeterCore
import WebKit

enum ClaudeWebProbeCommand: Equatable {
    case login(UUID)
    case delete(UUID)

    static func parse(arguments: [String]) throws -> Self {
        guard
            arguments.count == 3,
            let profileID = UUID(uuidString: arguments[2])
        else {
            throw ClaudeWebProbeCommandError.invalidArguments
        }

        switch arguments[1] {
        case "login":
            return .login(profileID)
        case "delete":
            return .delete(profileID)
        default:
            throw ClaudeWebProbeCommandError.invalidArguments
        }
    }
}

enum ClaudeWebProbeCommandError: Error, Equatable {
    case invalidArguments
}

struct ClaudeWebProbeWindow: Codable, Equatable {
    let kind: UsageWindowKind
    let duration: TimeInterval
    let consumedFraction: Double
    let resetAt: Date
}

struct ClaudeWebProbeOutput: Codable, Equatable {
    let profileID: UUID
    let organizationCount: Int
    let windows: [ClaudeWebProbeWindow]

    init(
        profileID: UUID,
        organizationCount: Int,
        snapshot: UsageSnapshot
    ) {
        self.profileID = profileID
        self.organizationCount = organizationCount
        windows = snapshot.windows.map {
            ClaudeWebProbeWindow(
                kind: $0.kind,
                duration: $0.duration,
                consumedFraction: $0.consumedFraction,
                resetAt: $0.resetAt
            )
        }
    }
}

enum ClaudeWebProbeOrganizationSelection {
    static func candidate(
        from organizations: [ClaudeOrganization]
    ) -> ClaudeOrganization? {
        organizations.first
    }
}

@MainActor
final class ClaudeWebProbeModel: ObservableObject {
    enum Phase: Equatable {
        case signingIn
        case loadingOrganizations
        case loadingUsage
        case complete
        case failed(String)
    }

    let profileID: UUID
    @Published private(set) var phase = Phase.signingIn
    @Published private(set) var hasRenderedLoginPage = false
    @Published private(set) var webView: WKWebView?
    @Published private(set) var organizations: [ClaudeOrganization] = []

    private let usageClient: ClaudeWebUsageClient
    private let onQualified: @MainActor (ClaudeWebProbeOutput) -> Void
    private var loginSession: ClaudeLoginSession?
    private var didQualify = false

    init(
        profileID: UUID,
        usageClient: ClaudeWebUsageClient = ClaudeWebUsageClient(),
        onQualified: @escaping @MainActor (ClaudeWebProbeOutput) -> Void
    ) {
        self.profileID = profileID
        self.usageClient = usageClient
        self.onQualified = onQualified
    }

    func start() {
        guard loginSession == nil else {
            return
        }

        let session = ClaudeLoginSession(
            profileID: profileID,
            onPageReady: { [weak self] in
                self?.loginPageDidFinish()
            }
        ) { [weak self] _, _ in
            self?.loadOrganizations()
        }
        loginSession = session
        webView = session.start()
    }

    func loginPageDidFinish() {
        hasRenderedLoginPage = true
    }

    private func qualify(organization: ClaudeOrganization) {
        phase = .loadingUsage

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let snapshot = try await usageClient.fetchUsage(
                    accountID: profileID,
                    profileID: profileID,
                    organizationID: organization.id,
                    now: Date()
                )
                let output = ClaudeWebProbeOutput(
                    profileID: profileID,
                    organizationCount: organizations.count,
                    snapshot: snapshot
                )
                didQualify = true
                loginSession?.close()
                loginSession = nil
                webView = nil
                phase = .complete
                onQualified(output)
            } catch {
                phase = .failed(Self.safeDescription(of: error))
            }
        }
    }

    func cancel() async {
        defer {
            loginSession = nil
            webView = nil
        }

        guard let loginSession else {
            return
        }
        if didQualify {
            loginSession.close()
            return
        }
        try? await loginSession.cancel()
    }

    private func loadOrganizations() {
        phase = .loadingOrganizations

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                organizations = try await usageClient.organizations(
                    profileID: profileID
                )
                guard
                    let candidate =
                        ClaudeWebProbeOrganizationSelection.candidate(
                            from: organizations
                        )
                else {
                    phase = .failed("No Claude organizations were found")
                    return
                }
                qualify(organization: candidate)
            } catch {
                phase = .failed(Self.safeDescription(of: error))
            }
        }
    }

    private static func safeDescription(of error: any Error) -> String {
        guard let error = error as? ProviderClientError else {
            return "Transport failure"
        }

        switch error {
        case .credentialMismatch:
            return "Credential mismatch"
        case .unsupportedResponse:
            return "Unsupported response shape"
        case .reauthenticationRequired:
            return "Authentication is required"
        case .retryAfter:
            return "Claude is rate limiting requests"
        case .temporaryFailure:
            return "Temporary provider failure"
        }
    }
}
