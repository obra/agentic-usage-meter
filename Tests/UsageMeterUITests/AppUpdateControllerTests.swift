import Testing
@testable import UsageMeterUI

@Suite
@MainActor
struct AppUpdateControllerTests {
    @Test
    func malformedBundleConfigurationDisablesUpdates() {
        #expect(
            AppUpdateConfiguration.from(
                infoDictionary: [
                    "SUFeedURL": "http://example.com/appcast.xml",
                    "SUPublicEDKey": "not-a-key",
                ],
            ) == nil,
        )
    }

    @Test
    func configuredControllerStartsOnceAndChecksOnDemand() {
        var starts = 0
        var checks = 0
        let controller = AppUpdateController(
            startUpdater: { starts += 1 },
            checkForUpdates: { checks += 1 },
        )

        #expect(controller.canCheckForUpdates)
        controller.start()
        controller.start()
        controller.checkForUpdates()

        #expect(starts == 1)
        #expect(checks == 1)
    }

    @Test
    func disabledControllerDoesNothing() {
        let controller = AppUpdateController.disabled

        #expect(!controller.canCheckForUpdates)
        controller.start()
        controller.checkForUpdates()
    }
}
