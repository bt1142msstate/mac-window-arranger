import AppKit

final class WindowPickerController {
    private let service = WindowManagementService()
    private let previewCaptureService = WindowPreviewCaptureService()
    private var capturePanels: [WindowPickerCapturePanel] = []
    private var focusPanels: [WindowPickerFocusPanel] = []
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
        previewCaptureService.requestScreenCaptureAccessIfNeeded()

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

        focusPanels = NSScreen.screens.map { screen in
            let panel = WindowPickerFocusPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = WindowPickerFocusView()
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
            panel.orderFrontRegardless()
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
            updateFocusOverlay(nil)
            highlightPanel?.orderOut(nil)
            return
        }

        let foregroundFrames = service.foregroundAppKitFrames(overlapping: window)
        updateFocusOverlay(WindowPickerFocusOverlay(focusedFrame: frame))
        let panel = highlightPanel ?? makeHighlightPanel()
        highlightPanel = panel
        (panel.contentView as? WindowPickerHighlightView)?.configure(
            for: window,
            previewImage: nil,
            foregroundFrames: foregroundFrames
        )
        panel.setFrame(frame.insetBy(dx: -4, dy: -4), display: true)
        panel.orderFrontRegardless()

        let hoveredWindowID = window.id
        previewCaptureService.capturePreview(for: window, displaySize: frame.size) { [weak self, weak panel] image in
            guard self?.hoveredWindow?.id == hoveredWindowID else {
                return
            }

            (panel?.contentView as? WindowPickerHighlightView)?.updatePreviewImage(image)
        }
    }

    private func updateFocusOverlay(_ overlay: WindowPickerFocusOverlay?) {
        for panel in focusPanels {
            (panel.contentView as? WindowPickerFocusView)?.overlay = overlay
        }
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

        for panel in focusPanels {
            panel.orderOut(nil)
            panel.close()
        }
        focusPanels.removeAll()

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
