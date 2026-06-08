import AppKit
import SwiftUI

@MainActor
final class DockAttachedWindowSurfaceController {
    private let configuration: DockAttachedSurfaceConfiguration
    private let miniPanelController: DockAttachedMiniPanelController
    private let transitionCoordinator: DockAttachedWindowTransitionCoordinator
    private let expandedBoundaryController: DockAttachedExpandedWindowBoundaryController
    private(set) var lastExpandedFrame: NSRect?

    init(configuration: DockAttachedSurfaceConfiguration) {
        self.configuration = configuration
        miniPanelController = DockAttachedMiniPanelController(configuration: configuration)
        transitionCoordinator = DockAttachedWindowTransitionCoordinator(configuration: configuration)
        expandedBoundaryController = DockAttachedExpandedWindowBoundaryController(configuration: configuration)
    }

    var currentMiniFrame: NSRect? {
        miniPanelController.currentFrame
    }

    var currentMiniWindow: NSWindow? {
        miniPanelController.currentWindow
    }

    func ownsMiniWindow(_ window: NSWindow) -> Bool {
        miniPanelController.owns(window)
    }

    func showMini<Content: View>(
        on preferredScreen: NSScreen?,
        @ViewBuilder content: () -> Content
    ) {
        miniPanelController.show(on: preferredScreen, content: content)
    }

    func hideMini() {
        miniPanelController.hide()
    }

    func miniFrame(on preferredScreen: NSScreen?) -> NSRect {
        miniPanelController.frame(on: preferredScreen)
    }

    func cancelActiveTransition() {
        transitionCoordinator.cancelActiveTransition()
    }

    func transition(
        from sourceWindow: NSWindow?,
        sourceFrame: NSRect,
        to targetFrame: NSRect,
        prepareDestination: (@MainActor @Sendable () -> Void)? = nil,
        revealDestination: @escaping @MainActor @Sendable () -> Void,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        transitionCoordinator.transition(
            from: sourceWindow,
            sourceFrame: sourceFrame,
            to: targetFrame,
            prepareDestination: prepareDestination,
            revealDestination: revealDestination,
            completion: completion
        )
    }

    func setFrame(
        of window: NSWindow,
        to targetFrame: NSRect,
        animated: Bool,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        transitionCoordinator.setFrame(
            of: window,
            to: targetFrame,
            animated: animated,
            completion: completion
        )
    }

    func trackExpandedWindow(_ window: NSWindow) {
        expandedBoundaryController.track(window)
    }

    func constrainExpandedWindow(_ window: NSWindow) {
        let constrainedFrame = constrainedExpandedFrame(window.frame, for: window)

        guard constrainedFrame != window.frame else {
            return
        }

        window.setFrame(constrainedFrame, display: true)
    }

    func rememberExpandedFrame(_ frame: NSRect, for window: NSWindow) {
        lastExpandedFrame = constrainedExpandedFrame(frame, for: window)
    }

    func constrainedExpandedFrame(_ frame: NSRect, for window: NSWindow) -> NSRect {
        guard let screen = NSScreen.bestScreen(for: frame, fallback: window.screen) else {
            return frame
        }

        var constrainedFrame = frame
        let minimumY = screen.visibleFrame.minY + configuration.dockMargin

        if constrainedFrame.minY < minimumY {
            constrainedFrame.origin.y = minimumY
        }

        return constrainedFrame
    }

    func positionExpandedWindowAboveDock(_ window: NSWindow) {
        guard let frame = bottomAnchoredFrame(for: window, size: window.frame.size) else {
            return
        }

        window.setFrame(frame, display: true)
        lastExpandedFrame = frame
    }

    func bottomAnchoredFrame(for window: NSWindow, size: CGSize) -> NSRect? {
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return nil
        }

        let visibleFrame = screen.visibleFrame
        var frame = NSRect(origin: window.frame.origin, size: size)

        let centeredX = visibleFrame.midX - (frame.width / 2)
        let minimumX = visibleFrame.minX + configuration.dockMargin
        let maximumX = visibleFrame.maxX - frame.width - configuration.dockMargin
        frame.origin.x = clamped(centeredX, lower: minimumX, upper: maximumX)

        let dockAdjustedY = visibleFrame.minY + configuration.dockMargin
        let highestAllowedY = visibleFrame.maxY - frame.height - configuration.dockMargin
        frame.origin.y = min(dockAdjustedY, highestAllowedY)
        frame.origin.y = max(frame.origin.y, visibleFrame.minY + configuration.dockMargin)

        return frame
    }

    func frameSize(for contentSize: CGSize, in window: NSWindow) -> CGSize {
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

@MainActor
private final class DockAttachedExpandedWindowBoundaryController {
    private let configuration: DockAttachedSurfaceConfiguration
    private weak var trackedWindow: NSWindow?
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    private var isConstrainingFrame = false

    init(configuration: DockAttachedSurfaceConfiguration) {
        self.configuration = configuration
    }

    func track(_ window: NSWindow) {
        guard trackedWindow !== window else {
            return
        }

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }

        trackedWindow = window
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else {
                return
            }

            MainActor.assumeIsolated {
                self?.constrain(window)
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func constrain(_ window: NSWindow) {
        guard !isConstrainingFrame else {
            return
        }

        guard let screen = NSScreen.bestScreen(for: window.frame, fallback: window.screen) else {
            return
        }

        let minimumY = screen.visibleFrame.minY + configuration.dockMargin

        guard window.frame.minY < minimumY else {
            return
        }

        var frame = window.frame
        frame.origin.y = minimumY

        isConstrainingFrame = true
        window.setFrame(frame, display: true)
        isConstrainingFrame = false
    }
}
