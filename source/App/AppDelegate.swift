import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private let compactPanelController = CompactPanelController()
    private let windowPickerController = WindowPickerController()
    private let transitionCoordinator = WindowTransitionCoordinator()
    private let mainWindowBoundaryController = MainWindowBoundaryController()
    private let compactLayoutService = WindowManagementService()
    private weak var mainWindow: NSWindow?
    private var fallbackMainWindow: NSWindow?
    private var lastExpandedMainWindowFrame: NSRect?
    private var isApplyingCompactLayout = false
    private var hasHandledAutomationURL = false

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !activateExistingInstanceIfNeeded() else {
            NSApp.terminate(nil)
            return
        }

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showLaunchMiniMode()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func activateExistingInstanceIfNeeded() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let existingInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { application in
                application.processIdentifier != currentProcessIdentifier && !application.isTerminated
            }

        guard let existingInstance else {
            return false
        }

        existingInstance.activate(options: [.activateAllWindows])
        return true
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
            self.constrainMainWindowAboveDock(window)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func showExpandedWindow() {
        DispatchQueue.main.async {
            self.transitionCoordinator.cancelActiveTransition()
            self.compactPanelController.hide()

            guard let window = self.configureMainWindowIfNeeded(centerIfNeeded: false) else {
                return
            }

            window.alphaValue = 1
            self.constrainMainWindowAboveDock(window)
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

    func beginWindowPick(
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

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString)
        else {
            showCompactStatus(message: "Invalid automation URL.", kind: .error)
            return
        }

        hasHandledAutomationURL = true
        handleAutomationURL(url)
    }

    private func handleAutomationURL(_ url: URL) {
        guard url.scheme == "window-arranger" else {
            showCompactStatus(message: "Unsupported automation URL.", kind: .error)
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let action = automationAction(from: url)

        switch action {
        case "show", "open":
            showExpandedWindow()
        case "mini", "compact":
            showCompactStatus(message: "Ready to arrange windows.", kind: .neutral)
        case "apply-layout", "layout", "open-layout":
            applyAutomationLayout(components: components, url: url)
        case "resize":
            performAutomationResize(components: components)
        case "accessibility", "settings":
            compactLayoutService.openAccessibilitySettings()
        default:
            showCompactStatus(message: "Unknown automation action: \(action).", kind: .error)
        }
    }

    private func automationAction(from url: URL) -> String {
        let host = url.host(percentEncoded: false) ?? ""
        let firstPathComponent = url.pathComponents.first { $0 != "/" } ?? ""
        let rawAction = host.isEmpty ? firstPathComponent : host
        return rawAction.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    private func applyAutomationLayout(components: URLComponents?, url: URL) {
        let layoutID = queryValue("id", in: components)
        let layoutName = queryValue("name", in: components)
            ?? queryValue("layout", in: components)
            ?? layoutNameFromPath(url)

        if let layoutID, !layoutID.isEmpty {
            applyCompactLayout(id: layoutID)
            return
        }

        guard let layoutName, !layoutName.isEmpty else {
            showCompactStatus(message: "Add a layout name or id to the automation URL.", kind: .error)
            return
        }

        applyCompactLayout(named: layoutName)
    }

    private func layoutNameFromPath(_ url: URL) -> String? {
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let host = url.host(percentEncoded: false) ?? ""
        let nameComponents = host.isEmpty ? pathComponents.dropFirst() : pathComponents[...]

        guard !nameComponents.isEmpty else {
            return nil
        }

        return nameComponents.joined(separator: "/").removingPercentEncoding
    }

    private func performAutomationResize(components: URLComponents?) {
        guard
            let widthText = queryValue("width", in: components),
            let heightText = queryValue("height", in: components),
            let width = Int(widthText),
            let height = Int(heightText),
            (100...10000).contains(width),
            (100...10000).contains(height)
        else {
            showCompactStatus(message: "Resize automation needs width and height.", kind: .error)
            return
        }

        let requestedName = queryValue("app", in: components) ?? queryValue("name", in: components)
        let requestedBundleID = queryValue("bundle", in: components) ?? queryValue("bundleIdentifier", in: components)
        let resizeAllWindows = boolQueryValue("all", in: components)
            || boolQueryValue("resizeAllWindows", in: components)
        let availableApps = compactLayoutService.loadRunningApps()

        guard let app = availableApps.first(where: { candidate in
            if let requestedBundleID, !requestedBundleID.isEmpty {
                return candidate.bundleIdentifier == requestedBundleID
            }

            if let requestedName, !requestedName.isEmpty {
                return candidate.name.localizedCaseInsensitiveCompare(requestedName) == .orderedSame
            }

            return false
        }) else {
            showCompactStatus(message: "Could not find the requested app.", kind: .error)
            return
        }

        showCompactStatus(message: "Resizing \(app.name)...", kind: .neutral)

        DispatchQueue.global(qos: .userInitiated).async { [compactLayoutService] in
            let resultMessage = compactLayoutService.executeResize(
                app: app,
                dimensions: (width: width, height: height),
                resizeAllWindows: resizeAllWindows
            )

            DispatchQueue.main.async {
                self.showCompactStatus(message: resultMessage, kind: self.statusKind(for: resultMessage))
            }
        }
    }

    private func queryValue(_ name: String, in components: URLComponents?) -> String? {
        components?.queryItems?.first { $0.name == name }?.value?.removingPercentEncoding
    }

    private func boolQueryValue(_ name: String, in components: URLComponents?) -> Bool {
        guard let value = queryValue(name, in: components)?.lowercased() else {
            return false
        }

        return ["1", "true", "yes", "on"].contains(value)
    }

    private func restoreMainWindow() {
        guard let window = configureMainWindowIfNeeded(centerIfNeeded: false) else {
            return
        }

        let miniFrame = compactPanelController.currentFrame ?? compactPanelController.frame(on: window.screen)
        let expandedFrame = constrainedMainWindowFrame(lastExpandedMainWindowFrame ?? window.frame, for: window)
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
            guard !self.hasHandledAutomationURL else {
                return
            }

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
            lastExpandedMainWindowFrame = constrainedMainWindowFrame(sourceFrame, for: window)
        }

        let showMiniMode = {
            window.orderOut(nil)
            let layoutState = self.compactLayoutState()
            self.compactPanelController.show(
                message: message,
                kind: kind,
                layoutTitle: layoutState.title,
                layoutOptions: layoutState.options,
                on: window.screen,
                selectLayoutAction: { [weak self] layoutID in
                    self?.applyCompactLayout(id: layoutID)
                },
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

    private func compactLayoutState() -> (title: String?, options: [CompactLayoutOption]) {
        let layouts = LayoutPersistence.loadSavedLayouts()
        let selectedLayoutID = LayoutPersistence.selectedLayoutID
        let selectedLayout = layouts.first { $0.id.uuidString == selectedLayoutID }
        let title = selectedLayout?.name ?? (layouts.isEmpty ? nil : "Unsaved Layout")

        let options = layouts.map { layout in
            CompactLayoutOption(
                id: layout.id.uuidString,
                name: layout.name,
                detail: "\(layout.layoutKind.title) - \(layout.slots.count) windows",
                isSelected: layout.id.uuidString == selectedLayoutID
            )
        }

        return (title, options)
    }

    private func applyCompactLayout(id layoutID: String) {
        guard !isApplyingCompactLayout else {
            return
        }

        let layouts = LayoutPersistence.loadSavedLayouts()

        guard let layout = layouts.first(where: { $0.id.uuidString == layoutID }) else {
            LayoutPersistence.selectedLayoutID = ""
            showCompactStatus(message: "Saved layout could not be found.", kind: .error)
            return
        }

        applyCompactLayout(layout)
    }

    private func applyCompactLayout(named layoutName: String) {
        guard !isApplyingCompactLayout else {
            return
        }

        let layouts = LayoutPersistence.loadSavedLayouts()

        guard let layout = layouts.first(where: {
            $0.name.localizedCaseInsensitiveCompare(layoutName) == .orderedSame
        }) else {
            LayoutPersistence.selectedLayoutID = ""
            showCompactStatus(message: "Saved layout \"\(layoutName)\" could not be found.", kind: .error)
            return
        }

        applyCompactLayout(layout)
    }

    private func applyCompactLayout(_ layout: SavedLayout) {
        let frames = compactLayoutService.frames(for: layout)

        guard frames.count == layout.slots.count else {
            showCompactStatus(message: "Could not read the saved layout frames.", kind: .error)
            return
        }

        isApplyingCompactLayout = true
        LayoutPersistence.selectedLayoutID = layout.id.uuidString
        let layoutState = compactLayoutState()
        compactPanelController.show(
            message: "Opening and arranging \(layout.name)...",
            kind: .neutral,
            layoutTitle: layoutState.title,
            layoutOptions: layoutState.options,
            on: compactPanelController.currentWindow?.screen,
            selectLayoutAction: { [weak self] layoutID in
                self?.applyCompactLayout(id: layoutID)
            },
            expandAction: { [weak self] in
                self?.restoreMainWindow()
            },
            quitAction: {
                NSApp.terminate(nil)
            }
        )

        DispatchQueue.global(qos: .userInitiated).async { [compactLayoutService] in
            let resultMessage = compactLayoutService.openAndArrange(layout: layout, frames: frames)

            DispatchQueue.main.async {
                self.isApplyingCompactLayout = false
                self.showCompactStatus(message: resultMessage, kind: self.statusKind(for: resultMessage))
            }
        }
    }

    @discardableResult
    private func configureMainWindowIfNeeded(centerIfNeeded: Bool) -> NSWindow? {
        let window = mainWindow
            ?? NSApp.windows.first { window in
                !compactPanelController.owns(window) && !(window is NSPanel)
            }
            ?? fallbackMainWindow
            ?? makeFallbackMainWindow()

        let isNewMainWindow = mainWindow !== window
        mainWindow = window
        configureMainWindow(window)
        mainWindowBoundaryController.track(window)

        if centerIfNeeded || isNewMainWindow {
            positionMainWindowAboveDock(window)
        } else {
            constrainMainWindowAboveDock(window)
        }

        return window
    }

    private func makeFallbackMainWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WindowWorkflowMode.arrange.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = NSHostingView(rootView: ContentView())
        window.isReleasedWhenClosed = false
        fallbackMainWindow = window
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

    private func constrainMainWindowAboveDock(_ window: NSWindow) {
        let constrainedFrame = constrainedMainWindowFrame(window.frame, for: window)

        guard constrainedFrame != window.frame else {
            return
        }

        window.setFrame(constrainedFrame, display: true)
    }

    private func constrainedMainWindowFrame(_ frame: NSRect, for window: NSWindow) -> NSRect {
        guard let screen = NSScreen.bestScreen(for: frame, fallback: window.screen) else {
            return frame
        }

        let margin: CGFloat = 12
        var constrainedFrame = frame
        let minimumY = screen.visibleFrame.minY + margin

        if constrainedFrame.minY < minimumY {
            constrainedFrame.origin.y = minimumY
        }

        return constrainedFrame
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

    private func statusKind(for message: String) -> ResizeStatusKind {
        let lowercased = message.lowercased()

        if lowercased.contains("failed") || lowercased.contains("error") || lowercased.contains("script error") {
            return .error
        }

        if lowercased.contains("blocked") || lowercased.contains("constraints") {
            return .warning
        }

        return .success
    }
}

private final class MainWindowBoundaryController {
    private weak var trackedWindow: NSWindow?
    private var observer: NSObjectProtocol?
    private var isConstrainingFrame = false

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

            self?.constrain(window)
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

        let margin: CGFloat = 12
        let minimumY = screen.visibleFrame.minY + margin

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

private extension NSScreen {
    static func bestScreen(for frame: NSRect, fallback: NSScreen?) -> NSScreen? {
        let candidates = screens.map { screen in
            (screen: screen, area: screen.frame.intersection(frame).positiveArea)
        }
        let bestMatch = candidates.max { first, second in
            first.area < second.area
        }

        if let bestMatch, bestMatch.area > 0 {
            return bestMatch.screen
        }

        return fallback ?? main ?? screens.first
    }
}

private extension NSRect {
    var positiveArea: CGFloat {
        guard width > 0, height > 0 else {
            return 0
        }

        return width * height
    }
}
