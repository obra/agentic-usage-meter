import AppKit

@MainActor
struct SettingsWindowActivation {
    private let setActivationPolicy:
        @MainActor (NSApplication.ActivationPolicy) -> Void

    init(
        setActivationPolicy:
            @escaping @MainActor (
                NSApplication.ActivationPolicy
            ) -> Void = {
                NSApplication.shared.setActivationPolicy($0)
            },
    ) {
        self.setActivationPolicy = setActivationPolicy
    }

    func settingsDidAppear() {
        setActivationPolicy(.regular)
    }

    func settingsDidDisappear() {
        setActivationPolicy(.accessory)
    }
}

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
