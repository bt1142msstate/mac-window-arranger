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
            updateFocusOverlay(for: nil)
            highlightPanel?.orderOut(nil)
            return
        }

        updateFocusOverlay(for: frame)
        let panel = highlightPanel ?? makeHighlightPanel()
        highlightPanel = panel
        (panel.contentView as? WindowPickerHighlightView)?.configure(for: window)
        panel.setFrame(frame.insetBy(dx: -4, dy: -4), display: true)
        panel.orderFrontRegardless()
    }

    private func updateFocusOverlay(for focusedFrame: CGRect?) {
        for panel in capturePanels {
            (panel.contentView as? WindowPickerCaptureView)?.focusedScreenFrame = focusedFrame
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
    var focusedScreenFrame: CGRect? {
        didSet {
            needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        guard
            let focusedScreenFrame,
            let windowFrame = window?.frame
        else {
            return
        }

        let localFrame = CGRect(
            x: focusedScreenFrame.minX - windowFrame.minX,
            y: focusedScreenFrame.minY - windowFrame.minY,
            width: focusedScreenFrame.width,
            height: focusedScreenFrame.height
        )
            .insetBy(dx: -4, dy: -4)
            .intersection(bounds)

        guard !localFrame.isNull, localFrame.width > 0, localFrame.height > 0 else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(roundedRect: localFrame, xRadius: 10, yRadius: 10).fill()
        NSGraphicsContext.restoreGraphicsState()
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
    private let badgeView = NSVisualEffectView()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 3
        layer?.cornerRadius = 8

        badgeView.material = .hudWindow
        badgeView.blendingMode = .withinWindow
        badgeView.state = .active
        badgeView.wantsLayer = true
        badgeView.layer?.cornerRadius = 14
        badgeView.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        badgeView.layer?.borderWidth = 1
        addSubview(badgeView)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        badgeView.addSubview(iconView)

        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .white
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        badgeView.addSubview(titleField)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(for window: WindowItem) {
        iconView.image = appIcon(
            bundleIdentifier: window.bundleIdentifier,
            appName: window.appName
        )
        titleField.stringValue = window.appName
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let badgeHeight: CGFloat = 28
        let horizontalPadding: CGFloat = 10
        let iconSize: CGFloat = 18
        let spacing: CGFloat = 7
        let preferredTextWidth = ceil(titleField.intrinsicContentSize.width)
        let maximumBadgeWidth = max(min(bounds.width - 24, 260), 78)
        let badgeWidth = min(
            max(horizontalPadding * 2 + iconSize + spacing + preferredTextWidth, 92),
            maximumBadgeWidth
        )
        let badgeX = (bounds.width - badgeWidth) / 2
        let badgeY = max(bounds.height - badgeHeight - 10, 8)

        badgeView.frame = CGRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)
        iconView.frame = CGRect(
            x: horizontalPadding,
            y: (badgeHeight - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        titleField.frame = CGRect(
            x: horizontalPadding + iconSize + spacing,
            y: 4,
            width: max(badgeWidth - horizontalPadding * 2 - iconSize - spacing, 10),
            height: badgeHeight - 8
        )
    }

    private func appIcon(bundleIdentifier: String?, appName: String?) -> NSImage {
        if
            let bundleIdentifier,
            !bundleIdentifier.isEmpty,
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        if
            let appName,
            let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }),
            let bundleURL = runningApp.bundleURL
        {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
