import AppKit

final class WindowPickerController {
    private let service = WindowManagementService()
    private var capturePanels: [WindowPickerCapturePanel] = []
    private var highlightPanel: WindowPickerHighlightPanel?
    private var hoveredWindow: WindowItem?
    private var onPicked: ((WindowItem) -> Void)?
    private var onCancelled: (() -> Void)?
    private var eventMonitors: [Any] = []

    func start(
        onPicked: @escaping (WindowItem) -> Void,
        onCancelled: @escaping () -> Void
    ) {
        cancel(notify: false)

        self.onPicked = onPicked
        self.onCancelled = onCancelled

        capturePanels = NSScreen.screens.map { screen in
            let panel = WindowPickerCapturePanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            let captureView = WindowPickerCaptureView()
            captureView.controller = self
            panel.contentView = captureView
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.level = .screenSaver
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .ignoresCycle,
                .stationary
            ]
            panel.acceptsMouseMovedEvents = true
            panel.makeKeyAndOrderFront(nil)
            return panel
        }

        installEventMonitors()
        NSApp.activate(ignoringOtherApps: true)
        capturePanels.first?.makeKey()
        updateHoveredWindow()
    }

    func updateHoveredWindow() {
        let nextWindow = service.windowUnderMouse()

        guard nextWindow?.id != hoveredWindow?.id else {
            return
        }

        hoveredWindow = nextWindow
        updateHighlight(for: nextWindow)
    }

    func pickHoveredWindow() {
        updateHoveredWindow()

        guard let hoveredWindow else {
            NSSound.beep()
            return
        }

        let picked = onPicked
        cleanup()
        picked?(hoveredWindow)
    }

    func cancel() {
        cancel(notify: true)
    }

    private func cancel(notify: Bool) {
        let cancelled = onCancelled
        cleanup()

        if notify {
            cancelled?()
        }
    }

    private func updateHighlight(for window: WindowItem?) {
        guard
            let window,
            let frame = service.appKitFrame(for: window)
        else {
            highlightPanel?.orderOut(nil)
            return
        }

        let panel = highlightPanel ?? makeHighlightPanel()
        highlightPanel = panel
        panel.setFrame(frame.insetBy(dx: -4, dy: -4), display: true)
        panel.orderFrontRegardless()
    }

    private func makeHighlightPanel() -> WindowPickerHighlightPanel {
        let panel = WindowPickerHighlightPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = WindowPickerHighlightView()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]
        return panel
    }

    private func cleanup() {
        hoveredWindow = nil
        onPicked = nil
        onCancelled = nil

        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()

        for panel in capturePanels {
            panel.orderOut(nil)
            panel.close()
        }
        capturePanels.removeAll()

        highlightPanel?.orderOut(nil)
        highlightPanel?.close()
        highlightPanel = nil
    }

    private func installEventMonitors() {
        appendEventMonitor(
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                self?.updateHoveredWindow()
                return event
            }
        )

        appendEventMonitor(
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                self?.pickHoveredWindow()
                return nil
            }
        )

        appendEventMonitor(
            NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .keyDown]) { [weak self] event in
                if event.type == .keyDown, event.keyCode != 53 {
                    return event
                }

                self?.cancel()
                return nil
            }
        )

        appendEventMonitor(
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                self?.updateHoveredWindow()
            }
        )

        appendEventMonitor(
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
                self?.pickHoveredWindow()
            }
        )

        appendEventMonitor(
            NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] _ in
                self?.cancel()
            }
        )
    }

    private func appendEventMonitor(_ monitor: Any?) {
        if let monitor {
            eventMonitors.append(monitor)
        }
    }
}

final class WindowPickerCapturePanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

final class WindowPickerHighlightPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

final class WindowPickerCaptureView: NSView {
    weak var controller: WindowPickerController?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .inVisibleRect, .mouseMoved],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseMoved(with event: NSEvent) {
        controller?.updateHoveredWindow()
    }

    override func mouseDragged(with event: NSEvent) {
        controller?.updateHoveredWindow()
    }

    override func mouseDown(with event: NSEvent) {
        controller?.pickHoveredWindow()
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.cancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            controller?.cancel()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class WindowPickerHighlightView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 3
        layer?.cornerRadius = 8
    }

    required init?(coder: NSCoder) {
        nil
    }
}
