import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private let dockSurfaceController = DockAttachedWindowSurfaceController(
        configuration: DockAttachedSurfaceConfiguration(
            miniTitle: "Window Arranger Mini",
            transitionTitle: "Window Arranger Transition",
            miniSize: CGSize(width: 430, height: 68)
        )
    )
    private let windowPickerController = WindowPickerController.appDefault()
    private let compactLayoutService = WindowManagementService()
    private let appUpdateService = AppUpdateService()
    private let issueReportService = IssueReportService()
    private weak var mainWindow: NSWindow?
    private var fallbackMainWindow: NSWindow?
    private var privacyPolicyWindow: NSWindow?
    private var issueReportWindow: NSWindow?
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
        checkForUpdatesAtLaunchIfNeeded()
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

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func showExpandedWindowFromMenu(_ sender: Any?) {
        showExpandedWindow()
    }

    @objc func showMiniModeFromMenu(_ sender: Any?) {
        showCompactStatus(message: "Ready to arrange windows.", kind: .neutral)
    }

    @objc func showPrivacyPolicyFromMenu(_ sender: Any?) {
        showPrivacyPolicyWindow()
    }

    @objc func checkForUpdatesFromMenu(_ sender: Any?) {
        requestUpdateCheck()
    }

    @objc func reportIssueFromMenu(_ sender: Any?) {
        showIssueReportWindow()
    }

    @objc func quitFromMenu(_ sender: Any?) {
        NSApp.terminate(nil)
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
            self.dockSurfaceController.constrainExpandedWindow(window)
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func showExpandedWindow() {
        DispatchQueue.main.async {
            self.dockSurfaceController.cancelActiveTransition()
            self.dockSurfaceController.hideMini()

            guard let window = self.configureMainWindowIfNeeded(centerIfNeeded: false) else {
                return
            }

            window.alphaValue = 1
            self.dockSurfaceController.constrainExpandedWindow(window)
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func fitMainWindowToContentSize(
        _ contentSize: CGSize,
        animated: Bool = true,
        prepareContent: (@MainActor @Sendable () -> Void)? = nil,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        DispatchQueue.main.async {
            guard let window = self.configureMainWindowIfNeeded(centerIfNeeded: false) else {
                prepareContent?()
                completion?()
                return
            }

            let frameSize = self.dockSurfaceController.frameSize(for: contentSize, in: window)
            guard let frame = self.dockSurfaceController.bottomAnchoredFrame(for: window, size: frameSize) else {
                prepareContent?()
                completion?()
                return
            }

            self.dockSurfaceController.rememberExpandedFrame(frame, for: window)

            guard animated, window.isVisible else {
                prepareContent?()
                window.setFrame(frame, display: true)
                window.alphaValue = 1
                completion?()
                return
            }

            self.dockSurfaceController.transition(
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
                    NSApp.activate()
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                },
                completion: completion
            )
        }
    }

    func beginWindowPick(
        configuration: WindowPickerConfiguration = .default,
        onPicked: @escaping (WindowItem) -> Void,
        onCancelled: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            self.configureMainWindowIfNeeded(centerIfNeeded: false)?.orderOut(nil)
            self.windowPickerController.pickWindow(configuration: configuration) { result in
                switch result {
                case .selected(let window):
                    onPicked(WindowItem(pickerItem: window))
                case .cancelled:
                    onCancelled()
                }
            }
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
        case "check-updates", "updates":
            requestUpdateCheck()
        case "report-issue", "issue", "support":
            showIssueReportWindow()
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

        let miniFrame = dockSurfaceController.currentMiniFrame ?? dockSurfaceController.miniFrame(on: window.screen)
        let expandedFrame = dockSurfaceController.constrainedExpandedFrame(
            dockSurfaceController.lastExpandedFrame ?? window.frame,
            for: window
        )
        let miniWindow = dockSurfaceController.currentMiniWindow

        dockSurfaceController.transition(
            from: miniWindow,
            sourceFrame: miniFrame,
            to: expandedFrame,
            prepareDestination: {
                self.dockSurfaceController.hideMini()
                window.setFrame(expandedFrame, display: true)
                window.alphaValue = 0
                window.displayIfNeeded()
            },
            revealDestination: {
                window.alphaValue = 1
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        )
    }

    private func showLaunchMiniMode() {
        DispatchQueue.main.async {
            guard !self.hasHandledAutomationURL else {
                return
            }

            self.showCompactPanel(
                message: "Ready to arrange windows.",
                kind: .neutral,
                on: NSScreen.main
            )
        }
    }

    private func requestUpdateCheck() {
        showExpandedWindow()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .windowArrangerCheckForUpdatesRequested, object: nil)
        }
    }

    private func checkForUpdatesAtLaunchIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard !self.hasHandledAutomationURL, self.appUpdateService.shouldRunAutomaticCheck() else {
                return
            }

            self.appUpdateService.checkForUpdate { [weak self] result in
                Task { @MainActor in
                    guard let self else {
                        return
                    }

                    guard case .success(let checkResult) = result else {
                        if self.isMissingReleaseResult(result) {
                            self.appUpdateService.markAutomaticCheckCompleted()
                        }
                        return
                    }

                    self.appUpdateService.markAutomaticCheckCompleted()

                    guard case .updateAvailable(let update) = checkResult else {
                        return
                    }

                    self.showCompactStatus(message: "Update \(update.version) is available.", kind: .warning)
                }
            }
        }
    }

    private func isMissingReleaseResult(_ result: Result<AppUpdateCheckResult, Error>) -> Bool {
        guard
            case .failure(let error) = result,
            let updateError = error as? AppUpdateServiceError,
            case .noRelease = updateError
        else {
            return false
        }

        return true
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

        let targetFrame = dockSurfaceController.miniFrame(on: window.screen)
        let sourceFrame = window.frame

        if sourceFrame.width > targetFrame.width || sourceFrame.height > targetFrame.height {
            dockSurfaceController.rememberExpandedFrame(sourceFrame, for: window)
        }

        let showMiniMode: @MainActor @Sendable () -> Void = {
            window.orderOut(nil)
            self.showCompactPanel(
                message: message,
                kind: kind,
                on: window.screen
            )
        }

        guard animated, window.isVisible else {
            showMiniMode()
            return true
        }

        dockSurfaceController.transition(
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

    private func showCompactPanel(message: String, kind: ResizeStatusKind, on screen: NSScreen?) {
        let layoutState = compactLayoutState()
        dockSurfaceController.showMini(on: screen) {
            CompactArrangerPanelView(
                message: compactMessage(from: message),
                kind: kind,
                layoutTitle: layoutState.title,
                layoutOptions: layoutState.options,
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
    }

    private func compactMessage(from message: String) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedMessage.isEmpty else {
            return "Ready to arrange windows."
        }

        return trimmedMessage.components(separatedBy: .newlines).first ?? trimmedMessage
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
        showCompactPanel(
            message: "Opening and arranging \(layout.name)...",
            kind: .neutral,
            on: dockSurfaceController.currentMiniWindow?.screen
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
            ?? fallbackMainWindow
            ?? makeFallbackMainWindow()

        let isNewMainWindow = mainWindow !== window
        mainWindow = window
        configureMainWindow(window)
        dockSurfaceController.trackExpandedWindow(window)

        if centerIfNeeded || isNewMainWindow {
            dockSurfaceController.positionExpandedWindowAboveDock(window)
        } else {
            dockSurfaceController.constrainExpandedWindow(window)
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

    private func showPrivacyPolicyWindow() {
        let window = privacyPolicyWindow ?? makePrivacyPolicyWindow()
        privacyPolicyWindow = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func showIssueReportWindow() {
        let window = issueReportWindow ?? makeIssueReportWindow()
        issueReportWindow = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makePrivacyPolicyWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Privacy Policy"
        window.contentView = NSHostingView(rootView: PrivacyPolicyView())
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func makeIssueReportWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Report an Issue"
        window.contentView = NSHostingView(
            rootView: IssueReportView(
                diagnostics: issueReportService.diagnostics,
                reportBugAction: { [weak self] in
                    self?.copyDiagnosticsAndOpenReport(kind: .bug)
                },
                requestFeatureAction: { [weak self] in
                    self?.copyDiagnosticsAndOpenReport(kind: .feature)
                },
                askQuestionAction: { [weak self] in
                    self?.copyDiagnosticsAndOpenReport(kind: .question)
                },
                openIssuesAction: { [weak self] in
                    self?.issueReportService.openIssuesList()
                },
                copyDiagnosticsAction: { [weak self] in
                    self?.issueReportService.copyDiagnosticsToPasteboard()
                }
            )
        )
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func copyDiagnosticsAndOpenReport(kind: IssueReportKind) {
        issueReportService.copyDiagnosticsToPasteboard()
        issueReportService.openReport(kind: kind)
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
