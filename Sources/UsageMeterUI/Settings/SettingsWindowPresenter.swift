import AppKit

@MainActor
final class SettingsWindowActivation {
    static let shared = SettingsWindowActivation()

    private let setActivationPolicy:
        @MainActor (NSApplication.ActivationPolicy) -> Void
    private var visibleWindowCount = 0

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
        regularWindowDidAppear()
    }

    func settingsDidDisappear() {
        regularWindowDidDisappear()
    }

    func regularWindowDidAppear() {
        visibleWindowCount += 1
        if visibleWindowCount == 1 {
            setActivationPolicy(.regular)
        }
    }

    func regularWindowDidDisappear() {
        guard visibleWindowCount > 0 else {
            return
        }
        visibleWindowCount -= 1
        if visibleWindowCount == 0 {
            setActivationPolicy(.accessory)
        }
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
