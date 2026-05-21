import AppKit
import Foundation
import Observation

@Observable
final class WindowArrangerStore {
    var runningApps: [AppItem] = []
    var availableWindows: [WindowItem] = []
    var hasAccessibilityAccess: Bool
    var workflowMode: WindowWorkflowMode = .arrange {
        didSet {
            UserDefaults.standard.set(workflowMode.rawValue, forKey: workflowModeDefaultsKey)
        }
    }
    var selectedAppName = ""
    var selectedSplitWindowIDs = Array(repeating: "", count: 3)
    var selectedPreset: ResizePreset = .hd
    var customWidth = "1280"
    var customHeight = "720"
    var resizeAllWindows = false
    var isExecuting = false
    var isPickingWindow = false
    var executionResult = ""
    var resultKind: ResizeStatusKind = .neutral
    var savedLayouts: [SavedLayout] = []
    var selectedLayoutID = ""
    var layoutName = "Work Layout"
    var selectedLayoutKind: LayoutKind = .threeColumns
    var customLayoutWindowCount = 3

    let customLayoutWindowRange = 1...8

    private let workflowModeDefaultsKey = "selectedWorkflowMode.v1"
    private let savedLayoutsDefaultsKey = "savedWindowLayouts.v1"
    private let service = WindowManagementService()

    init() {
        hasAccessibilityAccess = service.hasAccessibilityAccess()

        if
            let rawMode = UserDefaults.standard.string(forKey: workflowModeDefaultsKey),
            let savedMode = WindowWorkflowMode(rawValue: rawMode)
        {
            workflowMode = savedMode
        }
    }

    var targetDimensions: (width: Int, height: Int)? {
        if let presetDimensions = selectedPreset.dimensions {
            return presetDimensions
        }

        let widthText = customWidth.trimmingCharacters(in: .whitespacesAndNewlines)
        let heightText = customHeight.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let width = Int(widthText),
            let height = Int(heightText),
            (100...10000).contains(width),
            (100...10000).contains(height)
        else {
            return nil
        }

        return (width, height)
    }

    var dimensionsLabel: String {
        guard let dimensions = targetDimensions else {
            return "Invalid size"
        }

        return "\(dimensions.width) x \(dimensions.height)"
    }

    var canResize: Bool {
        !selectedAppName.isEmpty
            && targetDimensions != nil
            && hasAccessibilityAccess
            && !isExecuting
            && !isPickingWindow
    }

    var selectedSplitWindows: [WindowItem] {
        normalizedSelectionIDs(selectedSplitWindowIDs).compactMap { selectedID in
            availableWindows.first { $0.id == selectedID }
        }
    }

    var layoutPreviewPanes: [LayoutPreviewPane] {
        let selectedIDs = normalizedSelectionIDs(selectedSplitWindowIDs)
        let fallbackFrames = selectedLayoutKind.previewFrames(slotCount: layoutSlotCount)
        let visibleFrame = selectedLayoutKind.usesStoredFrames ? service.currentVisibleWindowManagementFrame() : nil

        return (0..<layoutSlotCount).map { index in
            let selectedID = selectedIDs[safe: index] ?? ""
            let window = availableWindows.first { $0.id == selectedID }
            let fallbackFrame = fallbackFrames[safe: index] ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            let frame = previewFrame(for: window, visibleFrame: visibleFrame) ?? fallbackFrame

            return LayoutPreviewPane(
                position: index,
                slotTitle: splitSlotTitle(for: index),
                selectedWindowID: selectedID.isEmpty ? nil : selectedID,
                appName: window?.appName,
                windowTitle: window?.title,
                frame: frame
            )
        }
    }

    var layoutSlotCount: Int {
        selectedLayoutKind.fixedWindowCount ?? customLayoutWindowCount
    }

    var hasCompleteLayoutSelection: Bool {
        let selectedIDs = normalizedSelectionIDs(selectedSplitWindowIDs).filter { !$0.isEmpty }
        return selectedIDs.count == layoutSlotCount
            && Set(selectedIDs).count == layoutSlotCount
            && selectedSplitWindows.count == layoutSlotCount
    }

    var canSplitSelectedWindows: Bool {
        selectedLayoutKind != .customPositions
            && hasCompleteLayoutSelection
            && hasAccessibilityAccess
            && !isExecuting
            && !isPickingWindow
    }

    var selectedSavedLayout: SavedLayout? {
        savedLayouts.first { $0.id.uuidString == selectedLayoutID }
    }

    var trimmedLayoutName: String {
        layoutName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSaveLayout: Bool {
        !trimmedLayoutName.isEmpty
            && hasCompleteLayoutSelection
            && hasAccessibilityAccess
            && !isExecuting
            && !isPickingWindow
    }

    var canApplyLayout: Bool {
        selectedSavedLayout != nil
            && hasAccessibilityAccess
            && !isExecuting
            && !isPickingWindow
    }

    var splitPickerStatusText: String {
        if !hasAccessibilityAccess {
            return "Grant Accessibility access to list windows."
        }

        if isPickingWindow {
            return "Hover over a window, then click to choose it."
        }

        if availableWindows.count < layoutSlotCount {
            return "Open at least \(layoutSlotCount) window(s) to build this layout."
        }

        if !canSplitSelectedWindows {
            if selectedLayoutKind == .customPositions, hasCompleteLayoutSelection {
                return "Save this layout to remember the selected windows' current positions."
            }

            return "Choose \(layoutSlotCount) different window(s)."
        }

        return "Arrange selected windows using \(selectedLayoutKind.title)."
    }

    func start() {
        loadSavedLayouts()
        loadRunningApps()
        refreshAccessibilityAccess()
    }

    func compactToDock() {
        let message = executionResult.isEmpty ? "Ready to arrange windows." : executionResult
        let kind: ResizeStatusKind = executionResult.isEmpty ? .neutral : resultKind
        compactToDock(message: message, kind: kind)
    }

    func loadSavedLayouts() {
        guard
            let data = UserDefaults.standard.data(forKey: savedLayoutsDefaultsKey),
            let decodedLayouts = try? JSONDecoder().decode([SavedLayout].self, from: data)
        else {
            if selectedLayoutID.isEmpty {
                layoutName = "Work Layout"
            }
            return
        }

        savedLayouts = decodedLayouts

        if selectedLayoutID.isEmpty {
            selectedLayoutID = decodedLayouts.first?.id.uuidString ?? ""
        }

        syncSelectedLayoutMetadata()
    }

    func syncSelectedLayoutMetadata() {
        if let selectedSavedLayout {
            layoutName = selectedSavedLayout.name
            selectedLayoutKind = selectedSavedLayout.layoutKind
            if selectedSavedLayout.layoutKind == .customPositions {
                customLayoutWindowCount = min(
                    max(selectedSavedLayout.slots.count, customLayoutWindowRange.lowerBound),
                    customLayoutWindowRange.upperBound
                )
            }
        } else if savedLayouts.isEmpty {
            layoutName = "Work Layout"
        }
    }

    func saveCurrentLayout() {
        let windows = selectedSplitWindows

        guard canSaveLayout, windows.count == layoutSlotCount else {
            resultKind = .error
            executionResult = "Choose \(layoutSlotCount) different window(s) before saving a layout."
            return
        }

        let visibleFrame = service.currentVisibleWindowManagementFrame()

        if selectedLayoutKind.usesStoredFrames, visibleFrame == nil {
            resultKind = .error
            executionResult = "Could not read the current screen size for a custom layout."
            return
        }

        let slots = windows.enumerated().map { index, window -> SavedLayoutSlot in
            let storedFrame = selectedLayoutKind.usesStoredFrames
                ? visibleFrame.map { NormalizedWindowFrame(frame: window.frame, in: $0) }
                : nil

            return SavedLayoutSlot(
                id: UUID(),
                position: index,
                appName: window.appName,
                bundleIdentifier: window.bundleIdentifier,
                windowTitle: window.title,
                normalizedFrame: storedFrame
            )
        }

        let existingIndex = savedLayouts.firstIndex {
            $0.id.uuidString == selectedLayoutID
                || $0.name.localizedCaseInsensitiveCompare(trimmedLayoutName) == .orderedSame
        }

        let layoutID = existingIndex.map { savedLayouts[$0].id } ?? UUID()
        let layout = SavedLayout(
            id: layoutID,
            name: trimmedLayoutName,
            layoutKind: selectedLayoutKind,
            slots: slots,
            updatedAt: Date()
        )

        if let existingIndex {
            savedLayouts[existingIndex] = layout
        } else {
            savedLayouts.append(layout)
        }

        selectedLayoutID = layout.id.uuidString
        layoutName = layout.name
        persistSavedLayouts()
        resultKind = .success
        executionResult = "Saved \(layout.layoutKind.title.lowercased()) layout \"\(layout.name)\" with \(layout.slots.count) window(s)."
    }

    func deleteSelectedLayout() {
        guard let selectedSavedLayout else {
            return
        }

        savedLayouts.removeAll { $0.id == selectedSavedLayout.id }
        selectedLayoutID = savedLayouts.first?.id.uuidString ?? ""
        layoutName = savedLayouts.first?.name ?? "Work Layout"
        persistSavedLayouts()
        resultKind = .success
        executionResult = "Deleted layout \"\(selectedSavedLayout.name)\"."
    }

    func applySelectedLayout() {
        guard let selectedSavedLayout else {
            resultKind = .error
            executionResult = "Choose a saved layout first."
            return
        }

        let frames = service.frames(for: selectedSavedLayout)

        guard frames.count == selectedSavedLayout.slots.count else {
            resultKind = .error
            executionResult = "Could not read the saved layout frames."
            return
        }

        isExecuting = true
        resultKind = .neutral
        executionResult = "Opening and arranging \(selectedSavedLayout.name)..."

        DispatchQueue.global(qos: .userInitiated).async { [service] in
            let resultMessage = service.openAndArrange(layout: selectedSavedLayout, frames: frames)

            DispatchQueue.main.async {
                self.finishWindowAction(with: resultMessage)
                self.loadRunningApps(preserveSelection: true)
            }
        }
    }

    func loadRunningApps(preserveSelection: Bool = true) {
        let currentSelection = selectedAppName
        let apps = service.loadRunningApps()

        runningApps = apps

        if preserveSelection, apps.contains(where: { $0.name == currentSelection }) {
            selectedAppName = currentSelection
        } else {
            selectedAppName = apps.first?.name ?? ""
        }

        loadAvailableWindows(preserveSelection: preserveSelection)
    }

    func pickWindowAndResize() {
        guard !isExecuting, !isPickingWindow else {
            return
        }

        guard hasAccessibilityAccess else {
            resultKind = .error
            executionResult = "Grant Accessibility access before picking a window."
            return
        }

        guard targetDimensions != nil else {
            resultKind = .error
            executionResult = "Enter valid dimensions before picking a window."
            return
        }

        loadRunningApps(preserveSelection: true)
        isPickingWindow = true
        resultKind = .neutral
        executionResult = "Hover over a window, then click to resize it."

        AppDelegate.shared?.beginWindowPick(
            onPicked: { [weak self] window in
                self?.executePickedWindowResize(window)
            },
            onCancelled: { [weak self] in
                self?.finishWindowPickCancellation()
            }
        )
    }

    func pickWindowForLayoutSlot(at index: Int) {
        guard !isExecuting, !isPickingWindow else {
            return
        }

        guard (0..<layoutSlotCount).contains(index) else {
            return
        }

        guard hasAccessibilityAccess else {
            resultKind = .error
            executionResult = "Grant Accessibility access before choosing a window."
            return
        }

        loadAvailableWindows(preserveSelection: true)
        isPickingWindow = true
        resultKind = .neutral
        executionResult = "Hover over a window, then click to choose it for \(splitSlotTitle(for: index))."

        AppDelegate.shared?.beginWindowPick(
            onPicked: { [weak self] window in
                self?.executePickedLayoutWindow(window, at: index)
            },
            onCancelled: { [weak self] in
                self?.finishWindowPickCancellation()
            }
        )
    }

    func normalizeLayoutSelectionAndRefresh() {
        selectedSplitWindowIDs = normalizedSelectionIDs(selectedSplitWindowIDs)
        loadAvailableWindows(preserveSelection: true)
    }

    func splitSlotTitle(for index: Int) -> String {
        selectedLayoutKind.slotTitle(for: index)
    }

    func setSplitWindowSelection(_ selectedID: String, at index: Int) {
        selectedSplitWindowIDs = normalizedSelectionIDs(selectedSplitWindowIDs)

        if selectedSplitWindowIDs.indices.contains(index) {
            if !selectedID.isEmpty {
                for selectionIndex in selectedSplitWindowIDs.indices where selectionIndex != index && selectedSplitWindowIDs[selectionIndex] == selectedID {
                    selectedSplitWindowIDs[selectionIndex] = ""
                }
            }

            selectedSplitWindowIDs[index] = selectedID
        }
    }

    func normalizedSelectionIDs(_ ids: [String]) -> [String] {
        var normalized = Array(ids.prefix(layoutSlotCount))

        while normalized.count < layoutSlotCount {
            normalized.append("")
        }

        return normalized
    }

    private func previewFrame(for window: WindowItem?, visibleFrame: CGRect?) -> CGRect? {
        guard
            selectedLayoutKind.usesStoredFrames,
            let window,
            let visibleFrame
        else {
            return nil
        }

        let previewFrame = NormalizedWindowFrame(frame: window.frame, in: visibleFrame).previewFrame
        return previewFrame.width >= 0.06 && previewFrame.height >= 0.06 ? previewFrame : nil
    }

    func loadAvailableWindows(preserveSelection: Bool = true) {
        let currentSelection = normalizedSelectionIDs(selectedSplitWindowIDs)
        let windows = service.collectAvailableWindows()
        let validIDs = Set(windows.map(\.id))
        var usedIDs = Set<String>()

        availableWindows = windows

        var nextSelection = currentSelection.map { selectedID -> String in
            guard !selectedID.isEmpty, validIDs.contains(selectedID), !usedIDs.contains(selectedID) else {
                return ""
            }

            usedIDs.insert(selectedID)
            return selectedID
        }

        if !preserveSelection {
            nextSelection = Array(repeating: "", count: layoutSlotCount)
            usedIDs.removeAll()
        }

        for index in nextSelection.indices where nextSelection[index].isEmpty {
            guard let nextWindow = windows.first(where: { !usedIDs.contains($0.id) }) else {
                continue
            }

            nextSelection[index] = nextWindow.id
            usedIDs.insert(nextWindow.id)
        }

        selectedSplitWindowIDs = nextSelection
    }

    func requestAccessibilityAccess() {
        service.requestAccessibilityAccess()
        refreshAccessibilityAccess()

        for delay in [0.5, 1.5, 3.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.refreshAccessibilityAccess()
            }
        }
    }

    func refreshAccessibilityAccess() {
        let isTrusted = service.hasAccessibilityAccess()

        guard isTrusted != hasAccessibilityAccess else {
            return
        }

        hasAccessibilityAccess = isTrusted

        if isTrusted {
            loadRunningApps(preserveSelection: true)
            executionResult = ""
            resultKind = .neutral
        }
    }

    func openAccessibilitySettings() {
        service.openAccessibilitySettings()
    }

    func executeThreeWaySplit() {
        let windows = selectedSplitWindows

        guard canSplitSelectedWindows, windows.count == layoutSlotCount else {
            resultKind = .error
            executionResult = "Choose \(layoutSlotCount) different window(s) before arranging."
            return
        }

        let layoutKind = selectedLayoutKind
        let frames = service.frames(for: layoutKind)

        guard frames.count == windows.count else {
            resultKind = .error
            executionResult = "Could not read the current screen size."
            return
        }

        isExecuting = true
        resultKind = .neutral
        executionResult = "Arranging selected windows..."

        DispatchQueue.global(qos: .userInitiated).async { [service] in
            let resultMessage = service.performLayoutArrangement(
                windows: windows,
                frames: frames,
                successMessage: "Arranged \(windows.count) window(s) using \(layoutKind.title)."
            )

            DispatchQueue.main.async {
                self.finishWindowAction(with: resultMessage)
                self.loadAvailableWindows(preserveSelection: true)
            }
        }
    }

    func executeResize() {
        guard let dimensions = targetDimensions else {
            resultKind = .error
            executionResult = "Enter valid dimensions before resizing."
            return
        }

        let appName = selectedAppName
        let shouldResizeAllWindows = resizeAllWindows

        isExecuting = true
        resultKind = .neutral
        executionResult = "Preparing \(selectedAppName)..."

        DispatchQueue.global(qos: .userInitiated).async { [service] in
            let resultMessage = service.executeResize(
                appName: appName,
                dimensions: dimensions,
                resizeAllWindows: shouldResizeAllWindows
            )

            DispatchQueue.main.async {
                self.finishWindowAction(with: resultMessage)
            }
        }
    }

    private func finishWindowPickCancellation() {
        isPickingWindow = false
        resultKind = .neutral
        executionResult = "Window pick cancelled."
        AppDelegate.shared?.bringMainWindowForward()
    }

    private func executePickedWindowResize(_ window: WindowItem) {
        guard let dimensions = targetDimensions else {
            isPickingWindow = false
            resultKind = .error
            executionResult = "Enter valid dimensions before resizing."
            AppDelegate.shared?.bringMainWindowForward()
            return
        }

        isPickingWindow = false
        loadRunningApps(preserveSelection: true)

        if !runningApps.contains(where: { $0.name == window.appName }) {
            runningApps.append(
                AppItem(
                    id: window.bundleIdentifier ?? window.appName,
                    name: window.appName,
                    bundleIdentifier: window.bundleIdentifier
                )
            )
            runningApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        selectedAppName = window.appName

        let shouldResizeAllWindows = resizeAllWindows
        isExecuting = true
        resultKind = .neutral
        executionResult = "Resizing \(window.displayName)..."

        DispatchQueue.global(qos: .userInitiated).async { [service] in
            let resultMessage = service.executeResize(
                window: window,
                dimensions: dimensions,
                resizeAllWindows: shouldResizeAllWindows
            )

            DispatchQueue.main.async {
                self.finishWindowAction(with: resultMessage)
            }
        }
    }

    private func executePickedLayoutWindow(_ window: WindowItem, at index: Int) {
        isPickingWindow = false
        loadAvailableWindows(preserveSelection: true)

        if !availableWindows.contains(where: { $0.id == window.id }) {
            availableWindows.append(window)
        }

        setSplitWindowSelection(window.id, at: index)
        resultKind = .neutral
        executionResult = "Selected \(window.displayName) for \(splitSlotTitle(for: index))."
        AppDelegate.shared?.bringMainWindowForward()
    }

    private func persistSavedLayouts() {
        guard let data = try? JSONEncoder().encode(savedLayouts) else {
            return
        }

        UserDefaults.standard.set(data, forKey: savedLayoutsDefaultsKey)
    }

    private func finishWindowAction(with resultMessage: String) {
        let kind = statusKind(for: resultMessage)
        resultKind = kind
        executionResult = resultMessage
        isExecuting = false

        if kind == .error {
            AppDelegate.shared?.bringMainWindowForward()
        } else {
            compactToDock(message: resultMessage, kind: kind)
        }
    }

    private func compactToDock(message: String, kind: ResizeStatusKind) {
        AppDelegate.shared?.showCompactStatus(message: message, kind: kind)
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
