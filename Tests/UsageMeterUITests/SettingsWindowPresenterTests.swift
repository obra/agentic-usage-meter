import AppKit
import Testing

@testable import UsageMeterUI

@Suite
@MainActor
struct SettingsWindowPresenterTests {
    @Test
    func openingSettingsActivatesApplicationAfterSceneCreation() {
        enum Event: Equatable {
            case opened
            case activated
        }

        var events: [Event] = []
        let presenter = SettingsWindowPresenter(
            activateApplication: {
                events.append(.activated)
            },
        )

        presenter.present {
            events.append(.opened)
        }

        #expect(events == [.opened, .activated])
    }

    @Test
    func settingsWindowIsRegularOnlyWhileItIsVisible() {
        var policies: [NSApplication.ActivationPolicy] = []
        let activation = SettingsWindowActivation(
            setActivationPolicy: {
                policies.append($0)
            },
        )

        activation.settingsDidAppear()
        activation.settingsDidDisappear()

        #expect(policies == [.regular, .accessory])
    }

    @Test
    func appStaysRegularUntilEveryManagedWindowCloses() {
        var policies: [NSApplication.ActivationPolicy] = []
        let activation = SettingsWindowActivation(
            setActivationPolicy: {
                policies.append($0)
            },
        )

        activation.regularWindowDidAppear()
        activation.regularWindowDidAppear()
        activation.regularWindowDidDisappear()
        activation.regularWindowDidDisappear()

        #expect(policies == [.regular, .accessory])
    }
}
