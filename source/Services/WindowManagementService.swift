import AppKit
import ApplicationServices
import Foundation

struct WindowManagementService {
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
        var seenNames = Set<String>()

        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppItem? in
                guard let item = appItem(for: app) else {
                    return nil
                }

                let inserted = seenNames.insert(item.name).inserted
                guard inserted else {
                    return nil
                }

                return item
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func appItem(for app: NSRunningApplication) -> AppItem? {
        guard app.activationPolicy == .regular, let name = app.localizedName, name != "Window Arranger" else {
            return nil
        }

        return AppItem(
            id: app.bundleIdentifier ?? name,
            name: name,
            bundleIdentifier: app.bundleIdentifier
        )
    }

    func collectAvailableWindows() -> [WindowItem] {
        collectVisibleWindowItems()
    }

    func windowUnderMouse() -> WindowItem? {
        let mouseLocation = NSEvent.mouseLocation
        let windowListPoint = windowListPoint(from: mouseLocation)

        return collectVisibleWindowItems().first { window in
            window.frame.contains(windowListPoint)
        }
    }

    func appKitFrame(for window: WindowItem) -> CGRect? {
        appKitFrame(fromWindowListFrame: window.frame)
    }

    private func collectVisibleWindowItems() -> [WindowItem] {
        guard AXIsProcessTrusted() else {
            return []
        }

        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
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

        return windowInfo.compactMap { info -> WindowItem? in
            guard
                let processIdentifier = info[kCGWindowOwnerPID as String] as? pid_t,
                let app = runningAppsByPID[processIdentifier],
                app.activationPolicy == .regular,
                let appName = app.localizedName,
                appName != "Window Arranger",
                let windowNumber = info[kCGWindowNumber as String] as? CGWindowID,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
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

            let title = info[kCGWindowName as String] as? String ?? ""
            let windowIndex = windowCountsByPID[processIdentifier, default: 0]
            windowCountsByPID[processIdentifier] = windowIndex + 1

            return WindowItem(
                id: "\(windowNumber)",
                appName: appName,
                bundleIdentifier: app.bundleIdentifier,
                processIdentifier: processIdentifier,
                windowNumber: windowNumber,
                windowIndex: windowIndex,
                title: title,
                frame: frame
            )
        }
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

    func executeResize(appName: String, dimensions: (width: Int, height: Int), resizeAllWindows: Bool) -> String {
        guard AXIsProcessTrusted() else {
            return "Error: Accessibility access is required before resizing windows."
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
            return "Error: \(appName) is not running."
        }

        activate(app)
        Thread.sleep(forTimeInterval: 0.2)

        let targetWindows = resizableWindowElements(
            for: app.processIdentifier,
            resizeAllWindows: resizeAllWindows
        )

        guard !targetWindows.isEmpty else {
            return "Error: Application is running but has no visible windows."
        }

        let result = resizeWindowElements(targetWindows, dimensions: dimensions)

        activate(app)

        if result.messages.isEmpty {
            return "Resized \(result.successCount) window(s) of \(appName) to \(dimensions.width)x\(dimensions.height)."
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
                appName: window.appName,
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
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)

            if runningApps.isEmpty {
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                    return "Could not find \(slot.appName) on this Mac."
                }

                if let openError = openApplication(at: appURL) {
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

    private func openApplication(at appURL: URL) -> String? {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        let semaphore = DispatchSemaphore(value: 0)
        var launchError: Error?

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            launchError = error
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 8) == .timedOut {
            return "Launch timed out."
        }

        return launchError?.localizedDescription
    }
    private func activateApplication(for slot: SavedLayoutSlot) {
        if let bundleIdentifier = slot.bundleIdentifier, !bundleIdentifier.isEmpty {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                activate(app)
            }
        } else {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == slot.appName }) {
                activate(app)
            }
        }
    }

    @discardableResult
    private func activate(_ app: NSRunningApplication) -> Bool {
        _ = app.unhide()
        return app.activate(options: [.activateAllWindows])
    }

    private func waitForLayoutWindowElements(slots: [SavedLayoutSlot], timeout: TimeInterval = 12) -> [UUID: LayoutWindowCandidate] {
        let deadline = Date().addingTimeInterval(timeout)
        var latestMatches: [UUID: LayoutWindowCandidate] = [:]

        repeat {
            latestMatches = matchLayoutWindowElements(slots: slots)

            if latestMatches.count == slots.count {
                return latestMatches
            }

            Thread.sleep(forTimeInterval: 0.35)
        } while Date() < deadline

        return latestMatches
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
        let matchingApps = NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular else {
                return false
            }

            if let bundleIdentifier = slot.bundleIdentifier, !bundleIdentifier.isEmpty {
                return app.bundleIdentifier == bundleIdentifier
            }

            return app.localizedName == slot.appName
        }

        return matchingApps.flatMap { app -> [LayoutWindowCandidate] in
            accessibilityWindowElements(for: app.processIdentifier)
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
