import AppKit
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private let compactPanelController = CompactPanelController()
    private let transitionDuration: TimeInterval = 0.24
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

            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func restoreMainWindow() {
        guard let window = configureMainWindowIfNeeded(centerIfNeeded: false) else {
            return
        }

        let miniFrame = compactPanelController.currentFrame ?? compactPanelController.frame(on: window.screen)
        let expandedFrame = lastExpandedMainWindowFrame ?? window.frame

        window.setFrame(miniFrame, display: true)
        compactPanelController.hide()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        animate(window: window, to: expandedFrame)
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

        animate(window: window, to: targetFrame) {
            showMiniMode()
        }
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
        window.collectionBehavior = window.collectionBehavior.union([
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ])
    }

    private func positionMainWindowAboveDock(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 12
        var frame = window.frame

        let centeredX = visibleFrame.midX - (frame.width / 2)
        let minimumX = visibleFrame.minX + margin
        let maximumX = visibleFrame.maxX - frame.width - margin
        frame.origin.x = clamped(centeredX, lower: minimumX, upper: maximumX)

        let dockAdjustedY = visibleFrame.minY + margin
        let highestAllowedY = visibleFrame.maxY - frame.height - margin
        frame.origin.y = min(dockAdjustedY, highestAllowedY)
        frame.origin.y = max(frame.origin.y, visibleFrame.minY + margin)

        window.setFrame(frame, display: true)
        lastExpandedMainWindowFrame = frame
    }

    private func animate(window: NSWindow, to frame: NSRect, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        } completionHandler: {
            window.setFrame(frame, display: true)
            completion?()
        }
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else {
            return lower
        }

        return min(max(value, lower), upper)
    }
}
