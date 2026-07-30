import AppKit
import SwiftUI
import UsageMeterCore

@MainActor
public final class FloatingWidgetController:
    NSObject,
    NSWindowDelegate
{
    private let model: AppModel
    private var panel: NSPanel?
    private var placementTask: Task<Void, Never>?

    public init(model: AppModel) {
        self.model = model
    }

    public func synchronize() {
        if model.isFloatingWidgetVisible {
            let panel = panel ?? makePanel()
            applySavedPlacement(to: panel)
            panel.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        Task {
            try? await model.setFloatingWidgetVisible(false)
        }
        return false
    }

    public func windowDidMove(_: Notification) {
        schedulePlacementSave()
    }

    public func windowDidEndLiveResize(
        _: Notification,
    ) {
        schedulePlacementSave()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 520,
                height: 360,
            ),
            styleMask: [
                .nonactivatingPanel,
                .titled,
                .closable,
                .resizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false,
        )
        panel.title = "Agentic Usage"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
        ]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.contentViewController = NSHostingController(
            rootView: FloatingWidgetView(model: model),
        )
        self.panel = panel
        return panel
    }

    private func applySavedPlacement(to panel: NSPanel) {
        guard let placement = model.floatingWidgetPlacement else {
            panel.center()
            return
        }
        guard
            placement.x.isFinite,
            placement.y.isFinite,
            placement.width.isFinite,
            placement.height.isFinite,
            placement.width >= 360,
            placement.height >= 240
        else {
            panel.center()
            return
        }
        panel.setFrame(
            NSRect(
                x: placement.x,
                y: placement.y,
                width: placement.width,
                height: placement.height,
            ),
            display: false,
        )
    }

    private func schedulePlacementSave() {
        placementTask?.cancel()
        placementTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard
                !Task.isCancelled,
                let frame = panel?.frame
            else {
                return
            }
            try? await model.setFloatingWidgetPlacement(
                FloatingWidgetPlacement(
                    x: frame.origin.x,
                    y: frame.origin.y,
                    width: frame.width,
                    height: frame.height,
                ),
            )
        }
    }
}
