import Foundation

public struct RefreshPolicy: Equatable, Sendable {
    public let automaticInterval: TimeInterval
    public let minimumProviderInterval: TimeInterval

    public init(
        automaticInterval: TimeInterval,
        minimumProviderInterval: TimeInterval,
    ) {
        precondition(automaticInterval.isFinite && automaticInterval > 0)
        precondition(
            minimumProviderInterval.isFinite
                && minimumProviderInterval > 0,
        )
        self.automaticInterval = automaticInterval
        self.minimumProviderInterval = minimumProviderInterval
    }

    public static let development = RefreshPolicy(
        automaticInterval: 60,
        minimumProviderInterval: 60,
    )

    public static let release = RefreshPolicy(
        automaticInterval: 600,
        minimumProviderInterval: 600,
    )
}
