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
}
