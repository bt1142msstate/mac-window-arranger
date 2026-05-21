import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private let compactPanelController = CompactPanelController()
    private let windowPickerController = WindowPickerController()
    private let transitionCoordinator = WindowTransitionCoordinator()
    private weak var mainWindow: NSWindow?
    private var lastExpandedMainWindowFrame: NSRect?

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showLaunchMiniMode()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func showCompactStatus(message: String, kind: ResizeStatusKind) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.showCompactStatusIfPossible(message: message, kind: kind)
        }
    }

    func bringMainWindowForward() {
        DispatchQueue.main.async {
            guard let window = self.configureMainWindowIfNeeded(centerIfNeeded: false) else {
                return
            }

            window.alphaValue = 1
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func fitMainWindowToContentSize(
        _ contentSize: CGSize,
        animated: Bool = true,
        prepareContent: (() -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        DispatchQueue.main.async {
            guard let window = self.configureMainWindowIfNeeded(centerIfNeeded: false) else {
                prepareContent?()
                completion?()
                return
            }

            let frameSize = self.frameSize(for: contentSize, in: window)
            guard let frame = self.bottomAnchoredFrameAboveDock(for: window, size: frameSize) else {
                prepareContent?()
                completion?()
                return
            }

            self.lastExpandedMainWindowFrame = frame

            guard animated, window.isVisible else {
                prepareContent?()
                window.setFrame(frame, display: true)
                window.alphaValue = 1
                completion?()
                return
            }

            self.transitionCoordinator.transition(
                from: window,
                sourceFrame: window.frame,
                to: frame,
                prepareDestination: {
                    prepareContent?()
                    window.setFrame(frame, display: true)
                    window.alphaValue = 0
                    window.displayIfNeeded()
                },
                revealDestination: {
                    window.alphaValue = 1
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                },
                completion: completion
            )
        }
    }

    func beginWindowResizePick(
        onPicked: @escaping (WindowItem) -> Void,
        onCancelled: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            self.configureMainWindowIfNeeded(centerIfNeeded: false)?.orderOut(nil)
            self.windowPickerController.start(
                onPicked: onPicked,
                onCancelled: onCancelled
            )
        }
    }

    private func restoreMainWindow() {
        guard let window = configureMainWindowIfNeeded(centerIfNeeded: false) else {
            return
        }

        let miniFrame = compactPanelController.currentFrame ?? compactPanelController.frame(on: window.screen)
        let expandedFrame = lastExpandedMainWindowFrame ?? window.frame
        let miniWindow = compactPanelController.currentWindow

        transitionCoordinator.transition(
            from: miniWindow,
            sourceFrame: miniFrame,
            to: expandedFrame,
            prepareDestination: {
                self.compactPanelController.hide()
                window.setFrame(expandedFrame, display: true)
                window.alphaValue = 0
                window.displayIfNeeded()
            },
            revealDestination: {
                window.alphaValue = 1
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        )
    }

    private func showLaunchMiniMode(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let didShow = self.showCompactStatusIfPossible(
                message: "Ready to arrange windows.",
                kind: .neutral,
                centerMainWindowIfNeeded: true,
                animated: false
            )

            guard !didShow, attempt < 20 else {
                return
            }

            self.showLaunchMiniMode(attempt: attempt + 1)
        }
    }

    @discardableResult
    private func showCompactStatusIfPossible(
        message: String,
        kind: ResizeStatusKind,
        centerMainWindowIfNeeded: Bool = false,
        animated: Bool = true
    ) -> Bool {
        guard let window = configureMainWindowIfNeeded(centerIfNeeded: centerMainWindowIfNeeded) else {
            return false
        }

        let targetFrame = compactPanelController.frame(on: window.screen)
        let sourceFrame = window.frame

        if sourceFrame.width > targetFrame.width || sourceFrame.height > targetFrame.height {
            lastExpandedMainWindowFrame = sourceFrame
        }

        let showMiniMode = {
            window.orderOut(nil)
            self.compactPanelController.show(
                message: message,
                kind: kind,
                on: window.screen,
                expandAction: { [weak self] in
                    self?.restoreMainWindow()
                },
                quitAction: {
                    NSApp.terminate(nil)
                }
            )
        }

        guard animated, window.isVisible else {
            showMiniMode()
            return true
        }

        transitionCoordinator.transition(
            from: window,
            sourceFrame: sourceFrame,
            to: targetFrame,
            prepareDestination: {
                window.alphaValue = 0
            },
            revealDestination: showMiniMode
        )
        return true
    }

    @discardableResult
    private func configureMainWindowIfNeeded(centerIfNeeded: Bool) -> NSWindow? {
        let window = mainWindow ?? NSApp.windows.first { window in
            !compactPanelController.owns(window) && !(window is NSPanel)
        }

        guard let window else {
            return nil
        }

        let isNewMainWindow = mainWindow !== window
        mainWindow = window
        configureMainWindow(window)

        if centerIfNeeded || isNewMainWindow {
            positionMainWindowAboveDock(window)
        }

        return window
    }

    private func configureMainWindow(_ window: NSWindow) {
        window.title = "Window Arranger"
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.level = .floating
        window.animationBehavior = .none
        window.collectionBehavior = window.collectionBehavior.union([
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ])
    }

    private func positionMainWindowAboveDock(_ window: NSWindow) {
        guard let frame = bottomAnchoredFrameAboveDock(for: window, size: window.frame.size) else {
            return
        }

        window.setFrame(frame, display: true)
        lastExpandedMainWindowFrame = frame
    }

    private func bottomAnchoredFrameAboveDock(for window: NSWindow, size: CGSize) -> NSRect? {
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return nil
        }

        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 12
        var frame = NSRect(origin: window.frame.origin, size: size)

        let centeredX = visibleFrame.midX - (frame.width / 2)
        let minimumX = visibleFrame.minX + margin
        let maximumX = visibleFrame.maxX - frame.width - margin
        frame.origin.x = clamped(centeredX, lower: minimumX, upper: maximumX)

        let dockAdjustedY = visibleFrame.minY + margin
        let highestAllowedY = visibleFrame.maxY - frame.height - margin
        frame.origin.y = min(dockAdjustedY, highestAllowedY)
        frame.origin.y = max(frame.origin.y, visibleFrame.minY + margin)

        return frame
    }

    private func frameSize(for contentSize: CGSize, in window: NSWindow) -> CGSize {
        let currentContentSize = window.contentLayoutRect.size
        let chromeWidth = max(window.frame.width - currentContentSize.width, 0)
        let chromeHeight = max(window.frame.height - currentContentSize.height, 0)

        return CGSize(
            width: contentSize.width + chromeWidth,
            height: contentSize.height + chromeHeight
        )
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else {
            return lower
        }

        return min(max(value, lower), upper)
    }
}
