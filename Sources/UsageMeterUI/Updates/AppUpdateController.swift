import Foundation
import Sparkle

struct AppUpdateConfiguration: Equatable {
    let feedURL: URL
    let publicKey: Data

    static func from(
        infoDictionary: [String: Any]?,
    ) -> AppUpdateConfiguration? {
        guard
            let dictionary = infoDictionary,
            let feed = dictionary["SUFeedURL"] as? String,
            let feedURL = URL(string: feed),
            feedURL.scheme == "https",
            let encodedKey = dictionary["SUPublicEDKey"] as? String,
            let publicKey = Data(base64Encoded: encodedKey),
            publicKey.count == 32
        else {
            return nil
        }
        return AppUpdateConfiguration(
            feedURL: feedURL,
            publicKey: publicKey,
        )
    }
}

@MainActor
public final class AppUpdateController {
    public static let disabled = AppUpdateController(
        startUpdater: nil,
        checkForUpdates: nil,
    )

    private let startUpdater: (() -> Void)?
    private let check: (() -> Void)?
    private var didStart = false

    public var canCheckForUpdates: Bool {
        check != nil
    }

    public convenience init(bundle: Bundle = .main) {
        guard AppUpdateConfiguration.from(
            infoDictionary: bundle.infoDictionary,
        ) != nil else {
            self.init(startUpdater: nil, checkForUpdates: nil)
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil,
        )
        self.init(
            startUpdater: { controller.startUpdater() },
            checkForUpdates: {
                controller.checkForUpdates(nil)
            },
        )
    }

    init(
        startUpdater: (() -> Void)?,
        checkForUpdates: (() -> Void)?,
    ) {
        self.startUpdater = startUpdater
        check = checkForUpdates
    }

    public func start() {
        guard !didStart, let startUpdater else { return }
        didStart = true
        startUpdater()
    }

    public func checkForUpdates() {
        check?()
    }
}
