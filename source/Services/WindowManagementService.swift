import AppKit
import ApplicationServices
import Foundation

struct WindowManagementService {
    private static var installedAppCache: [AppItem]?

    private struct LayoutWindowCandidate {
        let key: String
        let appName: String
        let title: String
        let element: AXUIElement

        var displayName: String {
            if title.isEmpty {
                return appName
            }

            return "\(appName) - \(title)"
        }
    }

    private struct WindowListSnapshot {
        let processIdentifier: pid_t
        let windowNumber: CGWindowID
        let title: String
        let frame: CGRect
        let order: Int
    }

    private struct WindowItemCandidate {
        let window: WindowItem
        let order: Int?
    }

    func hasAccessibilityAccess() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func loadRunningApps() -> [AppItem] {
        let runningApps = loadRunningAppItems()
        let installedApps = loadInstalledApps()
        var mergedAppsByID: [String: AppItem] = [:]

        for app in installedApps {
            mergedAppsByID[app.id] = app
        }

        for app in runningApps {
            mergedAppsByID[app.id] = app
        }

        return mergedAppsByID.values
            .sorted(by: appPickerSort)
    }

    private func loadRunningAppItems() -> [AppItem] {
        var seenIDs = Set<String>()
        let runningApplications = NSWorkspace.shared.runningApplications
        let visibleAppIDs = visibleRunningAppIDs(from: runningApplications)
        let focusedAppID = focusedApplicationID(
            from: runningApplications,
            visibleAppIDs: visibleAppIDs
        )

        return runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppItem? in
                guard
                    let item = appItem(
                        for: app,
                        hasVisibleWindows: visibleAppIDs.contains(appIdentity(for: app)),
                        isFocused: appIdentity(for: app) == focusedAppID
                    )
                else {
                    return nil
                }

                let inserted = seenIDs.insert(item.id).inserted
                guard inserted else {
                    return nil
                }

                return item
            }
    }

    private func appItem(
        for app: NSRunningApplication,
        hasVisibleWindows: Bool,
        isFocused: Bool
    ) -> AppItem? {
        guard app.activationPolicy == .regular, let name = app.localizedName, name != "Window Arranger" else {
            return nil
        }

        return AppItem(
            id: appIdentity(for: app),
            name: name,
            bundleIdentifier: app.bundleIdentifier,
            bundleURL: app.bundleURL,
            isRunning: true,
            hasVisibleWindows: hasVisibleWindows,
            isFocused: isFocused
        )
    }

    private func appPickerSort(_ lhs: AppItem, _ rhs: AppItem) -> Bool {
        let lhsRank = appPickerRank(lhs)
        let rhsRank = appPickerRank(rhs)

        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)

        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
    }

    private func appPickerRank(_ app: AppItem) -> Int {
        if app.isFocused {
            return 0
        }

        if app.isRunning, app.hasVisibleWindows {
            return 1
        }

        if app.isRunning {
            return 2
        }

        return 3
    }

    private func appIdentity(for app: NSRunningApplication) -> String {
        app.bundleIdentifier ?? app.bundleURL?.path ?? app.localizedName ?? "\(app.processIdentifier)"
    }

    private func visibleRunningAppIDs(from runningApplications: [NSRunningApplication]) -> Set<String> {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let regularAppsByPID = regularApplicationsByPID(runningApplications)
        var visibleIDs = Set<String>()

        for info in windowInfo {
            guard
                let processIdentifier = info[kCGWindowOwnerPID as String] as? pid_t,
                let app = regularAppsByPID[processIdentifier],
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let bounds = info[kCGWindowBounds as String] as? [String: Any]
            else {
                continue
            }

            let width = cgFloatValue(bounds["Width"])
            let height = cgFloatValue(bounds["Height"])

            guard width >= 80, height >= 80 else {
                continue
            }

            visibleIDs.insert(appIdentity(for: app))
        }

        return visibleIDs
    }

    private func focusedApplicationID(
        from runningApplications: [NSRunningApplication],
        visibleAppIDs: Set<String>
    ) -> String? {
        if
            let frontmostApplication = NSWorkspace.shared.frontmostApplication,
            isExternalRegularApplication(frontmostApplication)
        {
            return appIdentity(for: frontmostApplication)
        }

        return topVisibleExternalApplicationID(
            from: runningApplications,
            visibleAppIDs: visibleAppIDs
        )
    }

    private func topVisibleExternalApplicationID(
        from runningApplications: [NSRunningApplication],
        visibleAppIDs: Set<String>
    ) -> String? {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let regularAppsByPID = regularApplicationsByPID(runningApplications)

        for info in windowInfo {
            guard
                let processIdentifier = info[kCGWindowOwnerPID as String] as? pid_t,
                let app = regularAppsByPID[processIdentifier],
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let bounds = info[kCGWindowBounds as String] as? [String: Any]
            else {
                continue
            }

            let appID = appIdentity(for: app)

            guard visibleAppIDs.contains(appID) else {
                continue
            }

            let width = cgFloatValue(bounds["Width"])
            let height = cgFloatValue(bounds["Height"])

            guard width >= 80, height >= 80 else {
                continue
            }

            return appID
        }

        return nil
    }

    private func regularApplicationsByPID(_ applications: [NSRunningApplication]) -> [pid_t: NSRunningApplication] {
        var appsByPID: [pid_t: NSRunningApplication] = [:]

        for app in applications where isExternalRegularApplication(app) {
            appsByPID[app.processIdentifier] = app
        }

        return appsByPID
    }

    private func isExternalRegularApplication(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular
            && app.localizedName != "Window Arranger"
            && app.processIdentifier > 0
    }

    private func loadInstalledApps() -> [AppItem] {
        if let installedAppCache = Self.installedAppCache {
            return installedAppCache
        }

        let fileManager = FileManager.default
        let homeApplicationsURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let searchRoots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            homeApplicationsURL
        ]
        var appsByID: [String: AppItem] = [:]

        for rootURL in searchRoots where fileManager.fileExists(atPath: rootURL.path) {
            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isApplicationKey, .localizedNameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let appURL as URL in enumerator where appURL.pathExtension == "app" {
                enumerator.skipDescendants()

                guard let appItem = installedAppItem(at: appURL) else {
                    continue
                }

                appsByID[appItem.id] = appItem
            }
        }

        let apps = appsByID.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        Self.installedAppCache = apps
        return apps
    }

    private func installedAppItem(at appURL: URL) -> AppItem? {
        guard let bundle = Bundle(url: appURL) else {
            return nil
        }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, trimmedName != "Window Arranger" else {
            return nil
        }

        return AppItem(
            id: bundle.bundleIdentifier ?? appURL.path,
            name: trimmedName,
            bundleIdentifier: bundle.bundleIdentifier,
            bundleURL: appURL,
            isRunning: false
        )
    }

    func collectAvailableWindows() -> [WindowItem] {
        let accessibilityWindows = collectAccessibilityWindowCandidates()
            .map(\.window)
            .sorted(by: windowPickerSort)

        guard !accessibilityWindows.isEmpty else {
            return collectVisibleWindowItems()
        }

        return accessibilityWindows
    }

    func windowUnderMouse() -> WindowItem? {
        let mouseLocation = NSEvent.mouseLocation
        let windowListPoint = windowListPoint(from: mouseLocation)
        let visibleCandidates = collectVisibleWindowCandidates()
        let topVisibleCandidate = visibleCandidates
            .filter { $0.window.frame.contains(windowListPoint) }
            .sorted(by: windowStackSort)
            .first

        guard let topVisibleCandidate else {
            return nil
        }

        let accessibilityCandidates = collectAccessibilityWindowCandidates()
        let matchingAccessibilityCandidate = accessibilityCandidates.first { candidate in
            candidate.window.windowNumber != 0
                && candidate.window.windowNumber == topVisibleCandidate.window.windowNumber
        }

        return matchingAccessibilityCandidate?.window ?? topVisibleCandidate.window
    }

    func appKitFrame(for window: WindowItem) -> CGRect? {
        appKitFrame(fromWindowListFrame: window.frame)
    }

    private func collectVisibleWindowItems() -> [WindowItem] {
        collectVisibleWindowCandidates().map(\.window)
    }

    private func collectVisibleWindowCandidates() -> [WindowItemCandidate] {
        guard AXIsProcessTrusted() else {
            return []
        }

        var runningAppsByPID: [pid_t: NSRunningApplication] = [:]

        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier > 0 else {
                continue
            }

            if runningAppsByPID[app.processIdentifier] == nil || app.activationPolicy == .regular {
                runningAppsByPID[app.processIdentifier] = app
            }
        }

        var windowCountsByPID: [pid_t: Int] = [:]

        return visibleWindowSnapshots().compactMap { snapshot -> WindowItemCandidate? in
            guard
                let app = runningAppsByPID[snapshot.processIdentifier],
                app.activationPolicy == .regular,
                let appName = app.localizedName,
                appName != "Window Arranger"
            else {
                return nil
            }

            let windowIndex = windowCountsByPID[snapshot.processIdentifier, default: 0]
            windowCountsByPID[snapshot.processIdentifier] = windowIndex + 1

            return WindowItemCandidate(
                window: WindowItem(
                    id: "\(snapshot.windowNumber)",
                    appName: appName,
                    bundleIdentifier: app.bundleIdentifier,
                    processIdentifier: snapshot.processIdentifier,
                    windowNumber: snapshot.windowNumber,
                    windowIndex: windowIndex,
                    title: snapshot.title,
                    frame: snapshot.frame
                ),
                order: snapshot.order
            )
        }
    }

    private func collectAccessibilityWindowCandidates() -> [WindowItemCandidate] {
        guard AXIsProcessTrusted() else {
            return []
        }

        let windowSnapshots = visibleWindowSnapshots()
        let runningApps = NSWorkspace.shared.runningApplications
            .filter(isExternalRegularApplication)
            .sorted { lhs, rhs in
                (lhs.localizedName ?? "").localizedCaseInsensitiveCompare(rhs.localizedName ?? "") == .orderedAscending
            }

        var usedWindowNumbers = Set<CGWindowID>()
        var seenIDs = Set<String>()
        var windows: [WindowItemCandidate] = []

        for app in runningApps {
            guard let appName = app.localizedName else {
                continue
            }

            let windowElements = accessibilityWindowElements(for: app.processIdentifier)

            for (index, element) in windowElements.enumerated() {
                let title = axStringValue(element, attribute: kAXTitleAttribute as CFString)
                let axFrame = axFrameValue(element)
                let snapshot = bestWindowSnapshot(
                    for: app.processIdentifier,
                    title: title,
                    frame: axFrame,
                    snapshots: windowSnapshots,
                    usedWindowNumbers: usedWindowNumbers
                )
                let frame = axFrame ?? snapshot?.frame ?? .zero

                guard frame.width >= 80, frame.height >= 80 else {
                    continue
                }

                let windowNumber = snapshot?.windowNumber ?? 0
                let windowID = snapshot.map { "\($0.windowNumber)" }
                    ?? accessibilityWindowID(
                        processIdentifier: app.processIdentifier,
                        index: index,
                        title: title,
                        frame: frame
                    )

                guard seenIDs.insert(windowID).inserted else {
                    continue
                }

                if let snapshot {
                    usedWindowNumbers.insert(snapshot.windowNumber)
                }

                windows.append(
                    WindowItemCandidate(
                        window: WindowItem(
                            id: windowID,
                            appName: appName,
                            bundleIdentifier: app.bundleIdentifier,
                            processIdentifier: app.processIdentifier,
                            windowNumber: windowNumber,
                            windowIndex: index,
                            title: title,
                            frame: frame
                        ),
                        order: snapshot?.order
                    )
                )
            }
        }

        return windows
    }

    private func visibleWindowSnapshots() -> [WindowListSnapshot] {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowInfo.enumerated().compactMap { order, info -> WindowListSnapshot? in
            guard
                let processIdentifier = info[kCGWindowOwnerPID as String] as? pid_t,
                let windowNumber = info[kCGWindowNumber as String] as? CGWindowID,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer >= 0,
                let bounds = info[kCGWindowBounds as String] as? [String: Any]
            else {
                return nil
            }

            let frame = CGRect(
                x: cgFloatValue(bounds["X"]),
                y: cgFloatValue(bounds["Y"]),
                width: cgFloatValue(bounds["Width"]),
                height: cgFloatValue(bounds["Height"])
            )

            guard frame.width >= 80, frame.height >= 80 else {
                return nil
            }

            return WindowListSnapshot(
                processIdentifier: processIdentifier,
                windowNumber: windowNumber,
                title: info[kCGWindowName as String] as? String ?? "",
                frame: frame,
                order: order
            )
        }
    }

    private func bestWindowSnapshot(
        for processIdentifier: pid_t,
        title: String,
        frame: CGRect?,
        snapshots: [WindowListSnapshot],
        usedWindowNumbers: Set<CGWindowID>
    ) -> WindowListSnapshot? {
        let candidates = snapshots.filter { snapshot in
            snapshot.processIdentifier == processIdentifier
                && !usedWindowNumbers.contains(snapshot.windowNumber)
        }

        guard !candidates.isEmpty else {
            return nil
        }

        let titleMatches = title.isEmpty ? [] : candidates.filter { $0.title == title }
        let preferredCandidates = titleMatches.isEmpty ? candidates : titleMatches

        guard let frame else {
            return preferredCandidates.min { $0.order < $1.order }
        }

        let bestMatch = preferredCandidates.min {
            windowFrameDistance($0.frame, to: frame) < windowFrameDistance($1.frame, to: frame)
        }

        guard let bestMatch else {
            return nil
        }

        let distance = windowFrameDistance(bestMatch.frame, to: frame)

        if distance < 160 || (!title.isEmpty && bestMatch.title == title) {
            return bestMatch
        }

        return nil
    }

    private func accessibilityWindowID(
        processIdentifier: pid_t,
        index: Int,
        title: String,
        frame: CGRect
    ) -> String {
        let titleComponent = title.isEmpty ? "untitled" : title
        let roundedFrame = [
            Int(frame.minX.rounded()),
            Int(frame.minY.rounded()),
            Int(frame.width.rounded()),
            Int(frame.height.rounded())
        ]
            .map(String.init)
            .joined(separator: "-")

        return "ax-\(processIdentifier)-\(index)-\(titleComponent)-\(roundedFrame)"
    }

    private func windowPickerSort(_ lhs: WindowItem, _ rhs: WindowItem) -> Bool {
        if lhs.processIdentifier == rhs.processIdentifier {
            return lhs.windowIndex < rhs.windowIndex
        }

        let appNameComparison = lhs.appName.localizedCaseInsensitiveCompare(rhs.appName)

        if appNameComparison != .orderedSame {
            return appNameComparison == .orderedAscending
        }

        return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
    }

    private func windowStackSort(_ lhs: WindowItemCandidate, _ rhs: WindowItemCandidate) -> Bool {
        if let lhsOrder = lhs.order, let rhsOrder = rhs.order, lhsOrder != rhsOrder {
            return lhsOrder < rhsOrder
        }

        if lhs.order != nil, rhs.order == nil {
            return true
        }

        if lhs.order == nil, rhs.order != nil {
            return false
        }

        return windowPickerSort(lhs.window, rhs.window)
    }

    func currentVisibleWindowManagementFrame() -> CGRect? {
        guard let screen = NSScreen.main else {
            return nil
        }

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let topY = screenFrame.maxY - visibleFrame.maxY

        return CGRect(
            x: visibleFrame.minX,
            y: topY,
            width: visibleFrame.width,
            height: visibleFrame.height
        ).roundedForWindowManagement()
    }

    func frames(for layout: SavedLayout) -> [CGRect] {
        guard let visibleFrame = currentVisibleWindowManagementFrame() else {
            return []
        }

        let slots = layout.slots.sorted { $0.position < $1.position }

        if layout.layoutKind.usesStoredFrames {
            return slots.compactMap { slot in
                slot.normalizedFrame?.frame(in: visibleFrame)
            }
        }

        return frames(for: layout.layoutKind)
    }

    func frames(for layoutKind: LayoutKind) -> [CGRect] {
        guard let visibleFrame = currentVisibleWindowManagementFrame() else {
            return []
        }

        switch layoutKind {
        case .twoColumns:
            return columnFrames(count: 2, in: visibleFrame)
        case .threeColumns:
            return columnFrames(count: 3, in: visibleFrame)
        case .fourGrid:
            return gridFrames(columns: 2, rows: 2, in: visibleFrame)
        case .focusStack:
            let mainWidth = floor(visibleFrame.width * 0.62)
            let sideWidth = visibleFrame.width - mainWidth
            let sideHeight = floor(visibleFrame.height / 2)

            return [
                CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: mainWidth, height: visibleFrame.height),
                CGRect(x: visibleFrame.minX + mainWidth, y: visibleFrame.minY, width: sideWidth, height: sideHeight),
                CGRect(x: visibleFrame.minX + mainWidth, y: visibleFrame.minY + sideHeight, width: sideWidth, height: visibleFrame.height - sideHeight)
            ].map { $0.roundedForWindowManagement() }
        case .customPositions:
            return []
        }
    }

    func openAndArrange(layout: SavedLayout, frames: [CGRect]) -> String {
        let slots = layout.slots.sorted { $0.position < $1.position }

        guard AXIsProcessTrusted() else {
            return "Error: Accessibility access is required before layouts can move windows."
        }

        guard slots.count == frames.count else {
            return "Failed: Saved layout \"\(layout.name)\" does not match the current split setup."
        }

        var messages: [String] = []

        for slot in slots {
            if let launchMessage = openApplicationIfNeeded(for: slot) {
                messages.append(launchMessage)
            }
        }

        Thread.sleep(forTimeInterval: 0.7)

        let matchedWindows = waitForLayoutWindowElements(slots: slots)
        var successCount = 0

        for slot in slots {
            guard let window = matchedWindows[slot.id] else {
                messages.append("Failed to find a window for \(slot.appName).")
                continue
            }

            guard let frame = frames[safe: slot.position] else {
                messages.append("Failed to find a saved position for \(slot.appName).")
                continue
            }

            let moveResult = applyFrame(frame, to: window.element)

            guard moveResult == .success else {
                messages.append("Failed to move \(window.displayName): \(moveResult.readableDescription).")
                continue
            }

            _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            successCount += 1
            Thread.sleep(forTimeInterval: 0.12)
        }

        if successCount == slots.count, messages.isEmpty {
            return "Opened and arranged \"\(layout.name)\"."
        }

        if successCount > 0 {
            return "\(successCount) layout window(s) arranged.\n\n" + messages.joined(separator: "\n")
        }

        return "Failed: Could not arrange \"\(layout.name)\".\n\n" + messages.joined(separator: "\n")
    }

    func performLayoutArrangement(windows: [WindowItem], frames: [CGRect], successMessage: String) -> String {
        var messages: [String] = []
        var successCount = 0

        for index in windows.indices {
            let window = windows[index]
            let frame = frames[index]

            guard let windowElement = resolveWindowElement(for: window) else {
                messages.append("Failed to find \(window.displayName).")
                continue
            }

            if let app = NSRunningApplication(processIdentifier: window.processIdentifier) {
                activate(app)
            }

            let moveResult = applyFrame(frame, to: windowElement)

            guard moveResult == .success else {
                messages.append("Failed to move \(window.displayName): \(moveResult.readableDescription).")
                continue
            }

            Thread.sleep(forTimeInterval: 0.12)

            if let actualSize = axSizeValue(windowElement, attribute: kAXSizeAttribute as CFString) {
                let requestedWidth = frame.width
                let requestedHeight = frame.height
                let widthDifference = abs(actualSize.width - requestedWidth)
                let heightDifference = abs(actualSize.height - requestedHeight)

                if widthDifference > 8 || heightDifference > 8 {
                    messages.append("\(window.displayName) resized to \(Int(actualSize.width))x\(Int(actualSize.height)) because of app constraints.")
                }
            }

            successCount += 1
        }

        if successCount == windows.count, messages.isEmpty {
            return successMessage
        }

        if successCount > 0 {
            return "\(successCount) window(s) split.\n\n" + messages.joined(separator: "\n")
        }

        return "Failed: Could not split the selected windows.\n\n" + messages.joined(separator: "\n")
    }

    func executeResize(app: AppItem, dimensions: (width: Int, height: Int), resizeAllWindows: Bool) -> String {
        guard AXIsProcessTrusted() else {
            return "Error: Accessibility access is required before resizing windows."
        }

        guard let runningApp = runningApplication(for: app) ?? launchApplication(for: app) else {
            return "Error: Could not open \(app.name)."
        }

        activate(runningApp)

        let targetWindows = waitForResizableWindowElements(
            for: runningApp.processIdentifier,
            resizeAllWindows: resizeAllWindows
        )

        guard !targetWindows.isEmpty else {
            return "Error: \(app.name) is running but has no visible windows."
        }

        let result = resizeWindowElements(targetWindows, dimensions: dimensions)

        activate(runningApp)

        if result.messages.isEmpty {
            return "Resized \(result.successCount) window(s) of \(app.name) to \(dimensions.width)x\(dimensions.height)."
        }

        if result.successCount > 0 {
            return "\(result.successCount) window(s) resized.\n\n" + result.messages.joined(separator: "\n")
        }

        return result.messages.joined(separator: "\n")
    }

    func executeResize(window: WindowItem, dimensions: (width: Int, height: Int), resizeAllWindows: Bool) -> String {
        guard AXIsProcessTrusted() else {
            return "Error: Accessibility access is required before resizing windows."
        }

        if resizeAllWindows {
            return executeResize(
                app: AppItem(
                    id: window.bundleIdentifier ?? window.appName,
                    name: window.appName,
                    bundleIdentifier: window.bundleIdentifier
                ),
                dimensions: dimensions,
                resizeAllWindows: true
            )
        }

        guard let windowElement = resolveWindowElement(for: window) else {
            return "Failed: Could not access \(window.displayName)."
        }

        if let app = NSRunningApplication(processIdentifier: window.processIdentifier) {
            activate(app)
            Thread.sleep(forTimeInterval: 0.15)
        }

        let result = resizeWindowElements([windowElement], dimensions: dimensions)

        if let app = NSRunningApplication(processIdentifier: window.processIdentifier) {
            activate(app)
        }

        if result.messages.isEmpty {
            return "Resized \(window.displayName) to \(dimensions.width)x\(dimensions.height)."
        }

        if result.successCount > 0 {
            return "Resized \(window.displayName).\n\n" + result.messages.joined(separator: "\n")
        }

        return result.messages.joined(separator: "\n")
    }

    private func resizeWindowElements(
        _ windowElements: [AXUIElement],
        dimensions: (width: Int, height: Int)
    ) -> (successCount: Int, messages: [String]) {
        var messages: [String] = []
        var successCount = 0

        for windowElement in windowElements {
            let originalSize = axSizeValue(windowElement, attribute: kAXSizeAttribute as CFString)
            let targetFrame = resizeFrame(for: windowElement, dimensions: dimensions)
            let resizeResult = applyFrame(targetFrame, to: windowElement)

            guard resizeResult == .success else {
                messages.append("A window could not be resized: \(resizeResult.readableDescription).")
                continue
            }

            Thread.sleep(forTimeInterval: 0.2)

            guard let actualSize = axSizeValue(windowElement, attribute: kAXSizeAttribute as CFString) else {
                successCount += 1
                continue
            }

            let requestedWidth = CGFloat(dimensions.width)
            let requestedHeight = CGFloat(dimensions.height)
            let widthDifference = abs(actualSize.width - requestedWidth)
            let heightDifference = abs(actualSize.height - requestedHeight)

            if widthDifference <= 8, heightDifference <= 8 {
                successCount += 1
            } else if originalSize == actualSize {
                messages.append("A window was blocked from resizing and stayed at \(Int(actualSize.width))x\(Int(actualSize.height)).")
            } else {
                messages.append("A window resized to \(Int(actualSize.width))x\(Int(actualSize.height)) because of app constraints.")
            }
        }

        return (successCount, messages)
    }

    private func openApplicationIfNeeded(for slot: SavedLayoutSlot) -> String? {
        if let bundleIdentifier = slot.bundleIdentifier, !bundleIdentifier.isEmpty {
            let runningApps = matchingLayoutApplications(for: slot)

            if runningApps.isEmpty {
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                    return "Could not find \(slot.appName) on this Mac."
                }

                if let openError = openApplication(at: appURL).errorMessage {
                    return "Could not open \(slot.appName): \(openError)"
                }
            }

            activateApplication(for: slot)
            return nil
        }

        let isRunning = NSWorkspace.shared.runningApplications.contains { app in
            app.localizedName == slot.appName
        }

        if !isRunning {
            return "Could not open \(slot.appName) because this saved layout does not include its bundle identifier. Re-save the layout to make it store-ready."
        }

        activateApplication(for: slot)
        return nil
    }

    private func openApplication(at appURL: URL) -> (application: NSRunningApplication?, errorMessage: String?) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        let semaphore = DispatchSemaphore(value: 0)
        var launchedApplication: NSRunningApplication?
        var launchError: Error?

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { application, error in
            launchedApplication = application
            launchError = error
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 8) == .timedOut {
            return (nil, "Launch timed out.")
        }

        return (launchedApplication, launchError?.localizedDescription)
    }

    private func activateApplication(for slot: SavedLayoutSlot) {
        if let app = matchingLayoutApplications(for: slot).first {
            activate(app)
        }
    }

    @discardableResult
    private func activate(_ app: NSRunningApplication) -> Bool {
        _ = app.unhide()
        return app.activate(options: [.activateAllWindows])
    }

    private func waitForLayoutWindowElements(slots: [SavedLayoutSlot], timeout: TimeInterval = 18) -> [UUID: LayoutWindowCandidate] {
        let deadline = Date().addingTimeInterval(timeout)
        var latestMatches: [UUID: LayoutWindowCandidate] = [:]
        var reopenedApplicationIDs = Set<String>()

        repeat {
            latestMatches = matchLayoutWindowElements(slots: slots)

            if latestMatches.count == slots.count {
                return latestMatches
            }

            refreshMissingLayoutApplications(
                slots: slots,
                matches: latestMatches,
                reopenedApplicationIDs: &reopenedApplicationIDs
            )
            Thread.sleep(forTimeInterval: 0.45)
        } while Date() < deadline

        return latestMatches
    }

    private func refreshMissingLayoutApplications(
        slots: [SavedLayoutSlot],
        matches: [UUID: LayoutWindowCandidate],
        reopenedApplicationIDs: inout Set<String>
    ) {
        let missingSlots = slots.filter { matches[$0.id] == nil }

        for slot in missingSlots {
            let matchingApps = matchingLayoutApplications(for: slot)

            for app in matchingApps {
                activate(app)

                guard accessibilityWindowElements(for: app.processIdentifier).isEmpty else {
                    continue
                }

                let appID = appIdentity(for: app)

                guard reopenedApplicationIDs.insert(appID).inserted else {
                    continue
                }

                let appURL = app.bundleURL ?? slot.bundleIdentifier.flatMap {
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
                }

                guard let appURL else {
                    continue
                }

                _ = openApplication(at: appURL)
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
    }

    private func matchLayoutWindowElements(slots: [SavedLayoutSlot]) -> [UUID: LayoutWindowCandidate] {
        var matches: [UUID: LayoutWindowCandidate] = [:]
        var usedWindowKeys = Set<String>()

        for slot in slots.sorted(by: { $0.position < $1.position }) {
            let candidates = layoutWindowCandidates(for: slot).filter { candidate in
                guard !usedWindowKeys.contains(candidate.key) else {
                    return false
                }

                return true
            }

            let match = bestLayoutWindowMatch(for: slot, candidates: candidates)

            if let match {
                matches[slot.id] = match
                usedWindowKeys.insert(match.key)
            }
        }

        return matches
    }

    private func layoutWindowCandidates(for slot: SavedLayoutSlot) -> [LayoutWindowCandidate] {
        let matchingApps = matchingLayoutApplications(for: slot)

        return matchingApps.flatMap { app -> [LayoutWindowCandidate] in
            activate(app)

            return accessibilityWindowElements(for: app.processIdentifier)
                .enumerated()
                .map { index, element in
                    LayoutWindowCandidate(
                        key: "\(app.processIdentifier)-\(index)",
                        appName: app.localizedName ?? slot.appName,
                        title: axStringValue(element, attribute: kAXTitleAttribute as CFString),
                        element: element
                    )
                }
        }
    }

    private func matchingLayoutApplications(for slot: SavedLayoutSlot) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular else {
                return false
            }

            if let bundleIdentifier = slot.bundleIdentifier, !bundleIdentifier.isEmpty {
                return app.bundleIdentifier == bundleIdentifier
            }

            return app.localizedName == slot.appName
        }
    }

    private func bestLayoutWindowMatch(
        for slot: SavedLayoutSlot,
        candidates: [LayoutWindowCandidate]
    ) -> LayoutWindowCandidate? {
        guard !slot.windowTitle.isEmpty else {
            return candidates.first
        }

        let exactMatch = candidates.first { candidate in
            candidate.title == slot.windowTitle
        }

        if let exactMatch {
            return exactMatch
        }

        let caseInsensitiveMatch = candidates.first { candidate in
            !candidate.title.isEmpty
                && (
                    candidate.title.localizedCaseInsensitiveContains(slot.windowTitle)
                        || slot.windowTitle.localizedCaseInsensitiveContains(candidate.title)
                )
        }

        return caseInsensitiveMatch ?? candidates.first
    }

    private func runningApplication(for app: AppItem) -> NSRunningApplication? {
        if let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.isEmpty {
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
        }

        if let bundleURL = app.bundleURL {
            return NSWorkspace.shared.runningApplications.first { runningApp in
                runningApp.bundleURL == bundleURL
            }
        }

        return NSWorkspace.shared.runningApplications.first { runningApp in
            runningApp.localizedName == app.name
        }
    }

    private func launchApplication(for app: AppItem) -> NSRunningApplication? {
        let appURL: URL?

        if let bundleURL = app.bundleURL {
            appURL = bundleURL
        } else if let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.isEmpty {
            appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        } else {
            appURL = nil
        }

        guard let appURL else {
            return nil
        }

        let result = openApplication(at: appURL)

        if let application = result.application {
            return application
        }

        Thread.sleep(forTimeInterval: 0.4)
        return runningApplication(for: app)
    }

    private func waitForResizableWindowElements(
        for processIdentifier: pid_t,
        resizeAllWindows: Bool,
        timeout: TimeInterval = 8
    ) -> [AXUIElement] {
        let deadline = Date().addingTimeInterval(timeout)
        var windows: [AXUIElement] = []

        repeat {
            windows = resizableWindowElements(
                for: processIdentifier,
                resizeAllWindows: resizeAllWindows
            )

            if !windows.isEmpty {
                return windows
            }

            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline

        return windows
    }

    private func resizableWindowElements(for processIdentifier: pid_t, resizeAllWindows: Bool) -> [AXUIElement] {
        let selectableWindows = accessibilityWindowElements(for: processIdentifier)

        if resizeAllWindows {
            return selectableWindows
        }

        return selectableWindows.first.map { [$0] } ?? []
    }

    private func resizeFrame(for windowElement: AXUIElement, dimensions: (width: Int, height: Int)) -> CGRect {
        let requestedSize = CGSize(width: dimensions.width, height: dimensions.height)
        let currentFrame = axFrameValue(windowElement)
        let visibleFrame = currentVisibleWindowManagementFrame()

        var origin = currentFrame?.origin ?? visibleFrame?.origin ?? .zero

        if let visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - requestedSize.width)
            origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - requestedSize.height)
            origin.x = max(origin.x, visibleFrame.minX)
            origin.y = max(origin.y, visibleFrame.minY)
        }

        return CGRect(origin: origin, size: requestedSize).roundedForWindowManagement()
    }

    private func accessibilityWindowElements(for processIdentifier: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var windowElements: [AXUIElement] = []

        appendWindowElements(
            from: appElement,
            attribute: kAXWindowsAttribute as CFString,
            to: &windowElements
        )

        appendWindowElement(
            from: appElement,
            attribute: kAXFocusedWindowAttribute as CFString,
            to: &windowElements
        )

        appendWindowElement(
            from: appElement,
            attribute: kAXMainWindowAttribute as CFString,
            to: &windowElements
        )

        return uniqueWindowElements(windowElements).filter { isSelectableWindow($0) }
    }

    private func appendWindowElements(
        from appElement: AXUIElement,
        attribute: CFString,
        to windowElements: inout [AXUIElement]
    ) {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, attribute, &valueRef)

        guard result == .success, let elements = valueRef as? [AXUIElement] else {
            return
        }

        windowElements.append(contentsOf: elements)
    }

    private func appendWindowElement(
        from appElement: AXUIElement,
        attribute: CFString,
        to windowElements: inout [AXUIElement]
    ) {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, attribute, &valueRef)

        guard
            result == .success,
            let value = valueRef,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return
        }

        windowElements.append(value as! AXUIElement)
    }

    private func uniqueWindowElements(_ elements: [AXUIElement]) -> [AXUIElement] {
        var uniqueElements: [AXUIElement] = []

        for element in elements {
            if uniqueElements.contains(where: { CFEqual($0, element) }) {
                continue
            }

            uniqueElements.append(element)
        }

        return uniqueElements
    }

    private func resolveWindowElement(for item: WindowItem) -> AXUIElement? {
        let windowElements = accessibilityWindowElements(for: item.processIdentifier)
        let indexedWindows = Array(windowElements.enumerated())

        let candidates = indexedWindows.map { index, element in
            (
                index: index,
                element: element,
                title: axStringValue(element, attribute: kAXTitleAttribute as CFString),
                frame: axFrameValue(element)
            )
        }

        if !item.title.isEmpty {
            let titleMatches = candidates.filter { $0.title == item.title }

            if let match = titleMatches.min(by: {
                windowFrameDistance($0.frame, to: item.frame) < windowFrameDistance($1.frame, to: item.frame)
            }) {
                return match.element
            }
        }

        if let frameMatch = candidates.min(by: {
            windowFrameDistance($0.frame, to: item.frame) < windowFrameDistance($1.frame, to: item.frame)
        }), windowFrameDistance(frameMatch.frame, to: item.frame) < 120 {
            return frameMatch.element
        }

        if item.windowIndex < windowElements.count, isSelectableWindow(windowElements[item.windowIndex]) {
            return windowElements[item.windowIndex]
        }

        return indexedWindows.first?.element
    }

    private func windowFrameDistance(_ currentFrame: CGRect?, to originalFrame: CGRect) -> CGFloat {
        guard let currentFrame else {
            return .greatestFiniteMagnitude
        }

        return abs(currentFrame.minX - originalFrame.minX)
            + abs(currentFrame.minY - originalFrame.minY)
            + abs(currentFrame.width - originalFrame.width)
            + abs(currentFrame.height - originalFrame.height)
    }

    private func applyFrame(_ frame: CGRect, to windowElement: AXUIElement) -> AXError {
        if axBoolValue(windowElement, attribute: kAXMinimizedAttribute as CFString) == true {
            _ = AXUIElementSetAttributeValue(windowElement, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            Thread.sleep(forTimeInterval: 0.2)
        }

        _ = AXUIElementSetAttributeValue(windowElement, "AXFullScreen" as CFString, kCFBooleanFalse)

        var position = CGPoint(x: frame.minX, y: frame.minY)
        var size = CGSize(width: frame.width, height: frame.height)

        guard
            let positionValue = AXValueCreate(.cgPoint, &position),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else {
            return .failure
        }

        let sizeResult = AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue)
        let positionResult = AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, positionValue)
        let finalSizeResult = AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue)

        if sizeResult == .success || positionResult == .success || finalSizeResult == .success {
            return .success
        }

        return positionResult
    }

    private func isSelectableWindow(_ windowElement: AXUIElement) -> Bool {
        let role = axStringValue(windowElement, attribute: kAXRoleAttribute as CFString)

        guard role == kAXWindowRole as String else {
            return false
        }

        let subrole = axStringValue(windowElement, attribute: kAXSubroleAttribute as CFString)
        return subrole.isEmpty
            || subrole == kAXStandardWindowSubrole as String
            || subrole == "AXDialog"
    }

    private func axStringValue(_ element: AXUIElement, attribute: CFString) -> String {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)

        guard result == .success else {
            return ""
        }

        return valueRef as? String ?? ""
    }

    private func axBoolValue(_ element: AXUIElement, attribute: CFString) -> Bool? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)

        guard result == .success else {
            return nil
        }

        return valueRef as? Bool
    }

    private func axFrameValue(_ element: AXUIElement) -> CGRect? {
        guard
            let position = axPointValue(element, attribute: kAXPositionAttribute as CFString),
            let size = axSizeValue(element, attribute: kAXSizeAttribute as CFString)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func axPointValue(_ element: AXUIElement, attribute: CFString) -> CGPoint? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)

        guard result == .success, let value = valueRef else {
            return nil
        }

        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        var point = CGPoint.zero
        let didRead = AXValueGetValue(axValue, .cgPoint, &point)
        return didRead ? point : nil
    }

    private func axSizeValue(_ element: AXUIElement, attribute: CFString) -> CGSize? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)

        guard result == .success, let value = valueRef else {
            return nil
        }

        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        var size = CGSize.zero
        let didRead = AXValueGetValue(axValue, .cgSize, &size)
        return didRead ? size : nil
    }

    private func columnFrames(count: Int, in visibleFrame: CGRect) -> [CGRect] {
        guard count > 0 else {
            return []
        }

        let baseWidth = floor(visibleFrame.width / CGFloat(count))
        var frames: [CGRect] = []
        var x = visibleFrame.minX

        for index in 0..<count {
            let width = index == count - 1
                ? visibleFrame.maxX - x
                : baseWidth

            frames.append(
                CGRect(
                    x: x,
                    y: visibleFrame.minY,
                    width: width,
                    height: visibleFrame.height
                ).roundedForWindowManagement()
            )
            x += width
        }

        return frames
    }

    private func gridFrames(columns: Int, rows: Int, in visibleFrame: CGRect) -> [CGRect] {
        guard columns > 0, rows > 0 else {
            return []
        }

        let baseWidth = floor(visibleFrame.width / CGFloat(columns))
        let baseHeight = floor(visibleFrame.height / CGFloat(rows))
        var frames: [CGRect] = []

        for row in 0..<rows {
            var x = visibleFrame.minX
            let height = row == rows - 1
                ? visibleFrame.maxY - (visibleFrame.minY + CGFloat(row) * baseHeight)
                : baseHeight

            for column in 0..<columns {
                let width = column == columns - 1
                    ? visibleFrame.maxX - x
                    : baseWidth

                frames.append(
                    CGRect(
                        x: x,
                        y: visibleFrame.minY + CGFloat(row) * baseHeight,
                        width: width,
                        height: height
                    ).roundedForWindowManagement()
                )
                x += width
            }
        }

        return frames
    }

    private func windowListPoint(from appKitPoint: CGPoint) -> CGPoint {
        guard
            let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitPoint) }),
            let displayBounds = displayBounds(for: screen)
        else {
            return appKitPoint
        }

        return CGPoint(
            x: displayBounds.minX + (appKitPoint.x - screen.frame.minX),
            y: displayBounds.minY + (screen.frame.maxY - appKitPoint.y)
        )
    }

    private func appKitFrame(fromWindowListFrame frame: CGRect) -> CGRect? {
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)

        guard let match = NSScreen.screens.compactMap({ screen -> (screen: NSScreen, displayBounds: CGRect)? in
            guard let displayBounds = displayBounds(for: screen), displayBounds.contains(midpoint) else {
                return nil
            }

            return (screen, displayBounds)
        }).first else {
            return nil
        }

        return CGRect(
            x: match.screen.frame.minX + (frame.minX - match.displayBounds.minX),
            y: match.screen.frame.maxY - (frame.minY - match.displayBounds.minY) - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    private func displayBounds(for screen: NSScreen) -> CGRect? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }

        return CGDisplayBounds(displayID)
    }

    private func cgFloatValue(_ value: Any?) -> CGFloat {
        switch value {
        case let number as NSNumber:
            return CGFloat(truncating: number)
        case let value as CGFloat:
            return value
        case let value as Double:
            return CGFloat(value)
        case let value as Int:
            return CGFloat(value)
        default:
            return 0
        }
    }

}
