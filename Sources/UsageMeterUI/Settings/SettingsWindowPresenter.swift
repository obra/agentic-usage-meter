import AppKit

@MainActor
struct SettingsWindowPresenter {
    private let activateApplication: @MainActor () -> Void

    init(
        activateApplication: @escaping @MainActor () -> Void = {
            NSApplication.shared.activate()
        },
    ) {
        self.activateApplication = activateApplication
    }

    func present(
        openSettings: @MainActor () -> Void,
    ) {
        openSettings()
        activateApplication()
    }
}
