import AppKit

protocol WindowPickerInteractionHandling: AnyObject {
    func updateHoveredWindow()
    func pickHoveredWindow()
    func cancel()
}

final class WindowPickerSession: WindowPickerInteractionHandling {
    private let completion: (WindowPickerResult) -> Void
    private let configuration: WindowPickerConfiguration
    private let previewCaptureService: WindowPickingPreviewCapturing
    private let windowProvider: WindowPickingWindowProviding
    private var capturePanels: [WindowPickerCapturePanel] = []
    private var focusPanels: [WindowPickerFocusPanel] = []
    private var highlightPanel: WindowPickerHighlightPanel?
    private var hoveredWindow: WindowPickerItem?
    private var eventMonitors: [Any] = []
    private var didComplete = false

    init(
        configuration: WindowPickerConfiguration,
        windowProvider: WindowPickingWindowProviding,
        previewCaptureService: WindowPickingPreviewCapturing,
        completion: @escaping (WindowPickerResult) -> Void
    ) {
        self.completion = completion
        self.configuration = configuration
        self.windowProvider = windowProvider
        self.previewCaptureService = previewCaptureService
    }

    func start() {
        capturePanels = NSScreen.screens.map { screen in
            let panel = WindowPickerCapturePanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            let captureView = WindowPickerCaptureView()
            captureView.interactionHandler = self
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
            panel.contentView = WindowPickerFocusView(configuration: configuration)
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

        if configuration.behavior.activatesAppDuringPick {
            NSApp.activate(ignoringOtherApps: true)
        }

        capturePanels.first?.makeKey()
        updateHoveredWindow()
    }

    func updateHoveredWindow() {
        let nextWindow = windowProvider.windowUnderMouse()

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

        finish(with: .selected(hoveredWindow))
    }

    func cancel() {
        cancel(notify: true)
    }

    func cancel(notify: Bool) {
        guard !didComplete else {
            return
        }

        cleanup()

        if notify {
            finishCompletion(with: .cancelled)
        }
    }

    private func finish(with result: WindowPickerResult) {
        guard !didComplete else {
            return
        }

        cleanup()
        finishCompletion(with: result)
    }

    private func finishCompletion(with result: WindowPickerResult) {
        guard !didComplete else {
            return
        }

        didComplete = true
        completion(result)
    }

    private func updateHighlight(for window: WindowPickerItem?) {
        guard
            let window,
            let frame = windowProvider.appKitFrame(for: window)
        else {
            updateFocusOverlay(nil)
            highlightPanel?.orderOut(nil)
            return
        }

        let foregroundFrames = configuration.behavior.previewsOccludingWindows
            ? windowProvider.foregroundAppKitFrames(overlapping: window)
            : []
        updateFocusOverlay(WindowPickerFocusOverlay(focusedFrame: frame))

        let panel = highlightPanel ?? makeHighlightPanel()
        highlightPanel = panel
        (panel.contentView as? WindowPickerHighlightView)?.configure(
            for: window,
            previewImage: nil,
            foregroundFrames: foregroundFrames
        )
        panel.setFrame(
            frame.insetBy(
                dx: -configuration.style.highlightInset,
                dy: -configuration.style.highlightInset
            ),
            display: true
        )
        panel.orderFrontRegardless()

        guard configuration.behavior.previewsOccludingWindows else {
            return
        }

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
        panel.contentView = WindowPickerHighlightView(configuration: configuration)
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
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
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
