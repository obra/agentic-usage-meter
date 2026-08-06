import AppKit
import SwiftUI
import UsageMeterCore

@MainActor
public final class AccountDashboardPresenter {
    public static let shared = AccountDashboardPresenter()

    private let windowActivation: SettingsWindowActivation
    private let openExternalURL: (URL) -> Void
    private var windowControllers:
        [UUID: AccountDashboardWindowController] = [:]

    init(
        windowActivation: SettingsWindowActivation = .shared,
        openExternalURL: @escaping (URL) -> Void = {
            NSWorkspace.shared.open($0)
        }
    ) {
        self.windowActivation = windowActivation
        self.openExternalURL = openExternalURL
    }

    public func open(_ state: AccountViewState) {
        guard
            let definition = ProviderCatalog.live.definition(
                for: state.account.provider
            )
        else {
            return
        }

        let route = AccountDashboardRoute(
            account: state.account,
            strategy: definition.dashboardStrategy
        )
        if case let .external(url) = route.strategy {
            openExternalURL(url)
            return
        }

        if let existing = windowControllers[state.id] {
            existing.update(route: route, state: state)
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
            return
        }

        let controller = AccountDashboardWindowController(
            route: route,
            state: state,
            activation: windowActivation,
            onClose: { [weak self] in
                self?.windowControllers[state.id] = nil
            }
        )
        windowControllers[state.id] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    public func hasOpenDashboard(accountID: UUID) -> Bool {
        windowControllers[accountID] != nil
    }

    // A dashboard window keeps the account's web profile open, which
    // blocks deleting the profile's website data store on removal.
    public func close(accountID: UUID) {
        guard let controller = windowControllers[accountID] else {
            return
        }
        windowControllers[accountID] = nil
        controller.close()
    }
}

@MainActor
private final class AccountDashboardWindowController:
    NSWindowController,
    NSWindowDelegate
{
    private let activation: SettingsWindowActivation
    private let onClose: () -> Void

    init(
        route: AccountDashboardRoute,
        state: AccountViewState,
        activation: SettingsWindowActivation,
        onClose: @escaping () -> Void
    ) {
        self.activation = activation
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 760,
                height: 520
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
            ],
            backing: .buffered,
            defer: false
        )
        window.title = "\(state.account.displayName) Usage"
        window.center()
        window.contentViewController = NSHostingController(
            rootView: AccountDashboardView(
                route: route,
                state: state
            )
        )

        super.init(window: window)
        window.delegate = self
        activation.regularWindowDidAppear()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func update(
        route: AccountDashboardRoute,
        state: AccountViewState
    ) {
        window?.title = "\(state.account.displayName) Usage"
        window?.contentViewController = NSHostingController(
            rootView: AccountDashboardView(
                route: route,
                state: state
            )
        )
    }

    func windowWillClose(_: Notification) {
        activation.regularWindowDidDisappear()
        onClose()
    }
}
