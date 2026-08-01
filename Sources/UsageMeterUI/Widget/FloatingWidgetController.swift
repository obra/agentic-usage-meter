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
    private var isApplyingPlacement = false

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
        guard !isApplyingPlacement else {
            return
        }
        schedulePlacementSave()
    }

    public func windowDidEndLiveResize(
        _: Notification,
    ) {
        guard !isApplyingPlacement else {
            return
        }
        schedulePlacementSave()
    }

    private func makePanel() -> NSPanel {
        let hostingView = NSHostingView(
            rootView: FloatingWidgetView(model: model),
        )
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.frame.size.width =
            UsageTimelineMetrics.naturalWidth
        hostingView.layoutSubtreeIfNeeded()
        let fittingHeight = hostingView.fittingSize.height
        let screenHeight =
            NSScreen.main?.visibleFrame.height
                ?? max(fittingHeight, 360)
        let initialHeight = min(
            max(fittingHeight, 240),
            screenHeight,
        )
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: UsageTimelineMetrics.naturalWidth,
                height: initialHeight,
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
        panel.minSize = NSSize(width: 360, height: 240)
        panel.delegate = self
        panel.contentView = hostingView
        self.panel = panel
        observeCollapsedSections()
        return panel
    }

    private func observeCollapsedSections() {
        withObservationTracking {
            _ = model.collapsedUsageSections
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.observeCollapsedSections()
                guard let panel = self.panel else {
                    return
                }
                self.sizeToFitContent(panel)
            }
        }
    }

    private func applySavedPlacement(to panel: NSPanel) {
        guard let placement = model.floatingWidgetPlacement else {
            applyNaturalPlacement(to: panel)
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
            applyNaturalPlacement(to: panel)
            return
        }
        isApplyingPlacement = true
        defer {
            isApplyingPlacement = false
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

    private func applyNaturalPlacement(to panel: NSPanel) {
        isApplyingPlacement = true
        defer {
            isApplyingPlacement = false
        }
        sizeToFitContent(panel)
        panel.center()
    }

    private func sizeToFitContent(_ panel: NSPanel) {
        guard let hostingView = panel.contentView else {
            return
        }
        let contentWidth = panel.contentLayoutRect.width
        hostingView.frame.size.width = contentWidth
        hostingView.layoutSubtreeIfNeeded()
        let fittingHeight = hostingView.fittingSize.height
        let screenHeight =
            panel.screen?.visibleFrame.height
                ?? NSScreen.main?.visibleFrame.height
                ?? max(fittingHeight, 360)
        let height = min(
            max(fittingHeight, 240),
            screenHeight,
        )
        let topLeft = NSPoint(
            x: panel.frame.minX,
            y: panel.frame.maxY,
        )
        panel.setContentSize(
            NSSize(
                width: contentWidth,
                height: height
            ),
        )
        panel.setFrameTopLeftPoint(topLeft)
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
