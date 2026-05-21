import SwiftUI
import AppKit
import ApplicationServices

@main
struct WindowResizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            NSApp.windows.forEach { window in
                window.title = "Window Resizer"
                window.titlebarAppearsTransparent = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.center()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct AppItem: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleIdentifier: String?
}

struct WindowItem: Identifiable, Hashable {
    let id: String
    let appName: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let windowNumber: CGWindowID
    let windowIndex: Int
    let title: String
    let frame: CGRect

    var displayName: String {
        if title.isEmpty {
            return "\(appName) - Window \(windowIndex + 1)"
        }

        return "\(appName) - \(title)"
    }
}

enum LayoutKind: String, CaseIterable, Identifiable, Codable {
    case twoColumns
    case threeColumns
    case fourGrid
    case focusStack
    case customPositions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twoColumns: "Two Columns"
        case .threeColumns: "Three Columns"
        case .fourGrid: "Four Grid"
        case .focusStack: "Focus + Stack"
        case .customPositions: "Custom Positions"
        }
    }

    var detail: String {
        switch self {
        case .twoColumns:
            return "Two apps side by side."
        case .threeColumns:
            return "Three equal windows across the screen."
        case .fourGrid:
            return "Four windows in equal quadrants."
        case .focusStack:
            return "One large focus window with two stacked side windows."
        case .customPositions:
            return "Save the selected windows exactly where they are now."
        }
    }

    var symbolName: String {
        switch self {
        case .twoColumns: "rectangle.split.2x1"
        case .threeColumns: "rectangle.split.3x1"
        case .fourGrid: "rectangle.grid.2x2"
        case .focusStack: "rectangle.leadinghalf.inset.filled"
        case .customPositions: "slider.horizontal.3"
        }
    }

    var fixedWindowCount: Int? {
        switch self {
        case .twoColumns: 2
        case .threeColumns: 3
        case .fourGrid: 4
        case .focusStack: 3
        case .customPositions: nil
        }
    }

    var usesStoredFrames: Bool {
        self == .customPositions
    }

    func slotTitle(for index: Int) -> String {
        switch self {
        case .twoColumns:
            return index == 0 ? "Left" : "Right"
        case .threeColumns:
            switch index {
            case 0: return "Left"
            case 1: return "Center"
            default: return "Right"
            }
        case .fourGrid:
            switch index {
            case 0: return "Top Left"
            case 1: return "Top Right"
            case 2: return "Bottom Left"
            default: return "Bottom Right"
            }
        case .focusStack:
            switch index {
            case 0: return "Main"
            case 1: return "Side Top"
            default: return "Side Bottom"
            }
        case .customPositions:
            return "Window \(index + 1)"
        }
    }
}

struct NormalizedWindowFrame: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(frame: CGRect, in visibleFrame: CGRect) {
        let safeWidth = max(visibleFrame.width, 1)
        let safeHeight = max(visibleFrame.height, 1)

        self.x = Double((frame.minX - visibleFrame.minX) / safeWidth)
        self.y = Double((frame.minY - visibleFrame.minY) / safeHeight)
        self.width = Double(frame.width / safeWidth)
        self.height = Double(frame.height / safeHeight)
    }

    func frame(in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.minX + (CGFloat(x) * visibleFrame.width),
            y: visibleFrame.minY + (CGFloat(y) * visibleFrame.height),
            width: CGFloat(width) * visibleFrame.width,
            height: CGFloat(height) * visibleFrame.height
        ).roundedForWindowManagement()
    }
}

struct SavedLayout: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var layoutKind: LayoutKind
    var slots: [SavedLayoutSlot]
    var updatedAt: Date

    init(id: UUID, name: String, layoutKind: LayoutKind, slots: [SavedLayoutSlot], updatedAt: Date) {
        self.id = id
        self.name = name
        self.layoutKind = layoutKind
        self.slots = slots
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case layoutKind
        case slots
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        layoutKind = try container.decodeIfPresent(LayoutKind.self, forKey: .layoutKind) ?? .threeColumns
        slots = try container.decode([SavedLayoutSlot].self, forKey: .slots)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct SavedLayoutSlot: Identifiable, Codable, Hashable {
    var id: UUID
    var position: Int
    var appName: String
    var bundleIdentifier: String?
    var windowTitle: String
    var normalizedFrame: NormalizedWindowFrame?

    init(id: UUID, position: Int, appName: String, bundleIdentifier: String?, windowTitle: String, normalizedFrame: NormalizedWindowFrame?) {
        self.id = id
        self.position = position
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.normalizedFrame = normalizedFrame
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case position
        case appName
        case bundleIdentifier
        case windowTitle
        case normalizedFrame
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        position = try container.decode(Int.self, forKey: .position)
        appName = try container.decode(String.self, forKey: .appName)
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        windowTitle = try container.decode(String.self, forKey: .windowTitle)
        normalizedFrame = try container.decodeIfPresent(NormalizedWindowFrame.self, forKey: .normalizedFrame)
    }
}

enum ResizePreset: String, CaseIterable, Identifiable {
    case fullHD
    case hd
    case mobile
    case tablet
    case square
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullHD: "1080p"
        case .hd: "720p"
        case .mobile: "Mobile"
        case .tablet: "Tablet"
        case .square: "Square"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .fullHD: "Presentation and screen capture friendly."
        case .hd: "Fast default for smaller browser and app windows."
        case .mobile: "Tall phone viewport for responsive checks."
        case .tablet: "Tablet viewport for layout checks."
        case .square: "Square canvas for social and design previews."
        case .custom: "Use exact dimensions."
        }
    }

    var symbolName: String {
        switch self {
        case .fullHD, .hd: "rectangle"
        case .mobile: "iphone"
        case .tablet: "ipad"
        case .square: "square"
        case .custom: "slider.horizontal.3"
        }
    }

    var dimensions: (width: Int, height: Int)? {
        switch self {
        case .fullHD: (1920, 1080)
        case .hd: (1280, 720)
        case .mobile: (375, 812)
        case .tablet: (768, 1024)
        case .square: (1080, 1080)
        case .custom: nil
        }
    }
}

enum ResizeStatusKind {
    case neutral
    case success
    case warning
    case error

    var symbolName: String {
        switch self {
        case .neutral: "clock"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .neutral: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

struct ContentView: View {
    @State private var runningApps: [AppItem] = []
    @State private var availableWindows: [WindowItem] = []
    @State private var hasAccessibilityAccess = AXIsProcessTrusted()
    @State private var selectedAppName = ""
    @State private var selectedSplitWindowIDs = Array(repeating: "", count: 3)
    @State private var selectedPreset: ResizePreset = .hd
    @State private var customWidth = "1280"
    @State private var customHeight = "720"
    @State private var resizeAllWindows = false
    @State private var isExecuting = false
    @State private var executionResult = ""
    @State private var resultKind: ResizeStatusKind = .neutral
    @State private var savedLayouts: [SavedLayout] = []
    @State private var selectedLayoutID = ""
    @State private var layoutName = "Work Layout"
    @State private var selectedLayoutKind: LayoutKind = .threeColumns
    @State private var customLayoutWindowCount = 3

    private let savedLayoutsDefaultsKey = "savedWindowLayouts.v1"
    private let customLayoutWindowRange = 1...8
    private let appRefreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var targetDimensions: (width: Int, height: Int)? {
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

    private var dimensionsLabel: String {
        guard let dimensions = targetDimensions else {
            return "Invalid size"
        }

        return "\(dimensions.width) x \(dimensions.height)"
    }

    private var canResize: Bool {
        !selectedAppName.isEmpty && targetDimensions != nil && hasAccessibilityAccess && !isExecuting
    }

    private var selectedSplitWindows: [WindowItem] {
        normalizedSelectionIDs(selectedSplitWindowIDs).compactMap { selectedID in
            availableWindows.first { $0.id == selectedID }
        }
    }

    private var layoutSlotCount: Int {
        selectedLayoutKind.fixedWindowCount ?? customLayoutWindowCount
    }

    private var hasCompleteLayoutSelection: Bool {
        let selectedIDs = normalizedSelectionIDs(selectedSplitWindowIDs).filter { !$0.isEmpty }
        return selectedIDs.count == layoutSlotCount
            && Set(selectedIDs).count == layoutSlotCount
            && selectedSplitWindows.count == layoutSlotCount
    }

    private var canSplitThreeWindows: Bool {
        selectedLayoutKind != .customPositions
            && hasCompleteLayoutSelection
            && hasAccessibilityAccess
            && !isExecuting
    }

    private var selectedSavedLayout: SavedLayout? {
        savedLayouts.first { $0.id.uuidString == selectedLayoutID }
    }

    private var trimmedLayoutName: String {
        layoutName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveLayout: Bool {
        !trimmedLayoutName.isEmpty
            && hasCompleteLayoutSelection
            && hasAccessibilityAccess
            && !isExecuting
    }

    private var canApplyLayout: Bool {
        selectedSavedLayout != nil
            && hasAccessibilityAccess
            && !isExecuting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeaderView()

                if !hasAccessibilityAccess {
                    PermissionBanner(
                        promptAction: requestAccessibilityAccess,
                        settingsAction: openAccessibilitySettings
                    )
                }

                Panel(title: "Saved Layouts", symbolName: "rectangle.stack") {
                    VStack(alignment: .leading, spacing: 11) {
                        Picker("Saved Layout", selection: $selectedLayoutID) {
                            if savedLayouts.isEmpty {
                                Text("No saved layouts").tag("")
                            } else {
                                ForEach(savedLayouts) { layout in
                                    Text(layout.name).tag(layout.id.uuidString)
                                }
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .disabled(isExecuting || savedLayouts.isEmpty)

                        HStack(spacing: 10) {
                            TextField("Layout name", text: $layoutName)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isExecuting)

                            Button(action: saveCurrentLayout) {
                                Label("Save Layout", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!canSaveLayout)
                        }

                        HStack(spacing: 10) {
                            Button(action: applySelectedLayout) {
                                Label("Open & Arrange", systemImage: "play.rectangle")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canApplyLayout)

                            Button(role: .destructive, action: deleteSelectedLayout) {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedSavedLayout == nil || isExecuting)

                            Spacer()

                            Text("\(savedLayouts.count) saved")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                        }

                        if let layout = selectedSavedLayout {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("\(layout.layoutKind.title) - \(layout.slots.count) window(s)", systemImage: layout.layoutKind.symbolName)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.secondary)

                                ForEach(layout.slots.sorted { $0.position < $1.position }) { slot in
                                    HStack(spacing: 8) {
                                        Text(layout.layoutKind.slotTitle(for: slot.position))
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.secondary)
                                            .frame(width: 78, alignment: .leading)

                                        Text(slot.appName)
                                            .font(.caption)
                                            .lineLimit(1)

                                        if !slot.windowTitle.isEmpty {
                                            Text(slot.windowTitle)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        } else {
                            Text("Choose a layout type, select the windows, name it, then save it. Opening a saved layout launches those apps and restores the saved arrangement.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Panel(title: "Target", symbolName: "app.dashed") {
                    Picker("Application", selection: $selectedAppName) {
                        if runningApps.isEmpty {
                            Text("No running apps found").tag("")
                        }

                        ForEach(runningApps) { app in
                            Text(app.name).tag(app.name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    if let selectedApp = runningApps.first(where: { $0.name == selectedAppName }) {
                        Label(selectedApp.bundleIdentifier ?? "Running application", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Panel(title: "Layout Builder", symbolName: selectedLayoutKind.symbolName) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Layout Type", selection: $selectedLayoutKind) {
                            ForEach(LayoutKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(isExecuting)

                        HStack(spacing: 10) {
                            Label(selectedLayoutKind.detail, systemImage: selectedLayoutKind.symbolName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)

                            Spacer()

                            Text("\(layoutSlotCount) window(s)")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                        }

                        if selectedLayoutKind == .customPositions {
                            Stepper("Window count: \(customLayoutWindowCount)", value: $customLayoutWindowCount, in: customLayoutWindowRange)
                                .font(.caption)
                                .disabled(isExecuting)
                        }

                        ForEach(0..<layoutSlotCount, id: \.self) { index in
                            HStack(spacing: 10) {
                                Text(splitSlotTitle(for: index))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 78, alignment: .leading)

                                Picker(splitSlotTitle(for: index), selection: splitSelectionBinding(for: index)) {
                                    Text("Choose window").tag("")

                                    ForEach(availableWindows) { window in
                                        Text(window.displayName).tag(window.id)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .disabled(isExecuting || availableWindows.isEmpty)
                            }
                        }

                        HStack(spacing: 10) {
                            Label(splitPickerStatusText, systemImage: "rectangle.split.3x1")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)

                            Spacer()

                            Button(action: executeThreeWaySplit) {
                                Label("Arrange Selected", systemImage: selectedLayoutKind.symbolName)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!canSplitThreeWindows)
                        }
                    }
                }

                Panel(title: "Size", symbolName: "aspectratio") {
                    Picker("Preset", selection: $selectedPreset) {
                        ForEach(ResizePreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(isExecuting)

                    HStack(spacing: 10) {
                        Label(selectedPreset.detail, systemImage: selectedPreset.symbolName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        Spacer()

                        Text(dimensionsLabel)
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .foregroundColor(targetDimensions == nil ? .red : .primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    if selectedPreset == .custom {
                        HStack(spacing: 10) {
                            DimensionField(title: "Width", text: $customWidth)
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)
                            DimensionField(title: "Height", text: $customHeight)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))

                        if targetDimensions == nil {
                            Text("Enter whole-pixel dimensions between 100 and 10000.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                Panel(title: "Options", symbolName: "rectangle.3.group") {
                    Toggle(isOn: $resizeAllWindows) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Resize every standard window")
                            Text("Leave this off to target only the frontmost window.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(isExecuting)
                }

                VStack(spacing: 12) {
                    Button(action: executeResize) {
                        HStack(spacing: 8) {
                            if isExecuting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: resizeAllWindows ? "rectangle.3.group.bubble.left" : "macwindow")
                            }

                            Text(isExecuting ? "Resizing..." : "Resize \(resizeAllWindows ? "Windows" : "Window")")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canResize)
                    .keyboardShortcut(.return, modifiers: .command)

                    HStack {
                        Text(selectedAppName.isEmpty ? "Choose a running app." : "\(selectedAppName) -> \(dimensionsLabel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Spacer()

                        Text(resizeAllWindows ? "All windows" : "Front window")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                    }

                    if !executionResult.isEmpty {
                        StatusBanner(text: executionResult, kind: resultKind)
                    }
                }
            }
            .padding(22)
        }
        .frame(width: 560, height: 760)
        .background(WindowBackground())
        .tint(.blue)
        .onAppear {
            loadSavedLayouts()
            loadRunningApps()
            refreshAccessibilityAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityAccess()
            loadRunningApps(preserveSelection: true)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            loadRunningApps(preserveSelection: true)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            loadRunningApps(preserveSelection: true)
        }
        .onReceive(appRefreshTimer) { _ in
            refreshAccessibilityAccess()
            loadRunningApps(preserveSelection: true)
        }
        .onChange(of: selectedLayoutID) { _, newValue in
            if let layout = savedLayouts.first(where: { $0.id.uuidString == newValue }) {
                layoutName = layout.name
                selectedLayoutKind = layout.layoutKind
                if layout.layoutKind == .customPositions {
                    customLayoutWindowCount = min(max(layout.slots.count, customLayoutWindowRange.lowerBound), customLayoutWindowRange.upperBound)
                }
            }
        }
        .onChange(of: selectedLayoutKind) { _, _ in
            selectedSplitWindowIDs = normalizedSelectionIDs(selectedSplitWindowIDs)
            loadAvailableWindows(preserveSelection: true)
        }
        .onChange(of: customLayoutWindowCount) { _, _ in
            selectedSplitWindowIDs = normalizedSelectionIDs(selectedSplitWindowIDs)
            loadAvailableWindows(preserveSelection: true)
        }
        .animation(.snappy(duration: 0.18), value: selectedPreset)
        .animation(.snappy(duration: 0.18), value: executionResult.isEmpty)
        .animation(.snappy(duration: 0.18), value: availableWindows.count)
    }

    private func loadSavedLayouts() {
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

        if let selectedSavedLayout {
            layoutName = selectedSavedLayout.name
            selectedLayoutKind = selectedSavedLayout.layoutKind
            if selectedSavedLayout.layoutKind == .customPositions {
                customLayoutWindowCount = min(max(selectedSavedLayout.slots.count, customLayoutWindowRange.lowerBound), customLayoutWindowRange.upperBound)
            }
        } else if decodedLayouts.isEmpty {
            layoutName = "Work Layout"
        }
    }

    private func persistSavedLayouts() {
        guard let data = try? JSONEncoder().encode(savedLayouts) else {
            return
        }

        UserDefaults.standard.set(data, forKey: savedLayoutsDefaultsKey)
    }

    private func saveCurrentLayout() {
        let windows = selectedSplitWindows

        guard canSaveLayout, windows.count == layoutSlotCount else {
            resultKind = .error
            executionResult = "Choose \(layoutSlotCount) different window(s) before saving a layout."
            return
        }

        let visibleFrame = currentVisibleWindowManagementFrame()

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

    private func deleteSelectedLayout() {
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

    private func applySelectedLayout() {
        guard let selectedSavedLayout else {
            resultKind = .error
            executionResult = "Choose a saved layout first."
            return
        }

        let frames = frames(for: selectedSavedLayout)

        guard frames.count == selectedSavedLayout.slots.count else {
            resultKind = .error
            executionResult = "Could not read the saved layout frames."
            return
        }

        isExecuting = true
        resultKind = .neutral
        executionResult = "Opening and arranging \(selectedSavedLayout.name)..."

        DispatchQueue.global(qos: .userInitiated).async {
            let resultMessage = openAndArrange(layout: selectedSavedLayout, frames: frames)

            DispatchQueue.main.async {
                resultKind = statusKind(for: resultMessage)
                executionResult = resultMessage
                isExecuting = false
                loadRunningApps(preserveSelection: true)
            }
        }
    }

    private func loadRunningApps(preserveSelection: Bool = true) {
        let currentSelection = selectedAppName
        var seenNames = Set<String>()

        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppItem? in
                guard let name = app.localizedName, name != "Window Resizer" else {
                    return nil
                }

                let inserted = seenNames.insert(name).inserted
                guard inserted else {
                    return nil
                }

                return AppItem(
                    id: app.bundleIdentifier ?? name,
                    name: name,
                    bundleIdentifier: app.bundleIdentifier
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        runningApps = apps

        if preserveSelection, apps.contains(where: { $0.name == currentSelection }) {
            selectedAppName = currentSelection
        } else {
            selectedAppName = apps.first?.name ?? ""
        }

        loadAvailableWindows(preserveSelection: preserveSelection)
    }

    private var splitPickerStatusText: String {
        if !hasAccessibilityAccess {
            return "Grant Accessibility access to list windows."
        }

        if availableWindows.count < layoutSlotCount {
            return "Open at least \(layoutSlotCount) window(s) to build this layout."
        }

        if !canSplitThreeWindows {
            if selectedLayoutKind == .customPositions, hasCompleteLayoutSelection {
                return "Save this layout to remember the selected windows' current positions."
            }

            return "Choose \(layoutSlotCount) different window(s)."
        }

        return "Arrange selected windows using \(selectedLayoutKind.title)."
    }

    private func splitSlotTitle(for index: Int) -> String {
        selectedLayoutKind.slotTitle(for: index)
    }

    private func splitSelectionBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard selectedSplitWindowIDs.indices.contains(index) else {
                    return ""
                }

                return selectedSplitWindowIDs[index]
            },
            set: { newValue in
                selectedSplitWindowIDs = normalizedSelectionIDs(selectedSplitWindowIDs)

                if selectedSplitWindowIDs.indices.contains(index) {
                    selectedSplitWindowIDs[index] = newValue
                }
            }
        )
    }

    private func normalizedSelectionIDs(_ ids: [String]) -> [String] {
        var normalized = Array(ids.prefix(layoutSlotCount))

        while normalized.count < layoutSlotCount {
            normalized.append("")
        }

        return normalized
    }

    private func loadAvailableWindows(preserveSelection: Bool = true) {
        let currentSelection = normalizedSelectionIDs(selectedSplitWindowIDs)
        let windows = collectAvailableWindows()
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

    private func collectAvailableWindows() -> [WindowItem] {
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
                appName != "Window Resizer",
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

    private func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        refreshAccessibilityAccess()

        for delay in [0.5, 1.5, 3.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                refreshAccessibilityAccess()
            }
        }
    }

    private func refreshAccessibilityAccess() {
        let isTrusted = AXIsProcessTrusted()

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

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func openAndArrange(layout: SavedLayout, frames: [CGRect]) -> String {
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

        let matchedWindows = waitForLayoutWindows(slots: slots)
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

            guard let windowElement = resolveWindowElement(for: window) else {
                messages.append("Failed to access \(window.displayName). It may have closed.")
                continue
            }

            let moveResult = applyFrame(frame, to: windowElement)

            guard moveResult == .success else {
                messages.append("Failed to move \(window.displayName): \(moveResult.readableDescription).")
                continue
            }

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

            sendReopenCommand(for: slot)
            return nil
        }

        let isRunning = NSWorkspace.shared.runningApplications.contains { app in
            app.localizedName == slot.appName
        }

        if !isRunning {
            if let openError = openApplication(named: slot.appName) {
                return "Could not open \(slot.appName): \(openError)"
            }
        }

        sendReopenCommand(for: slot)
        return nil
    }

    private func openApplication(at appURL: URL) -> String? {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false

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

    private func openApplication(named appName: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return error.localizedDescription
        }

        guard process.terminationStatus == 0 else {
            return "open -a exited with status \(process.terminationStatus)."
        }

        return nil
    }

    private func sendReopenCommand(for slot: SavedLayoutSlot) {
        let target: String

        if let bundleIdentifier = slot.bundleIdentifier, !bundleIdentifier.isEmpty {
            target = "application id \"\(appleScriptEscaped(bundleIdentifier))\""
        } else {
            target = "application \"\(appleScriptEscaped(slot.appName))\""
        }

        let script = """
        try
            tell \(target)
                reopen
                activate
            end tell
        end try
        """

        var errorDict: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&errorDict)
    }

    private func waitForLayoutWindows(slots: [SavedLayoutSlot], timeout: TimeInterval = 12) -> [UUID: WindowItem] {
        let deadline = Date().addingTimeInterval(timeout)
        var latestMatches: [UUID: WindowItem] = [:]

        repeat {
            latestMatches = matchLayoutWindows(slots: slots, windows: collectAvailableWindows())

            if latestMatches.count == slots.count {
                return latestMatches
            }

            Thread.sleep(forTimeInterval: 0.35)
        } while Date() < deadline

        return latestMatches
    }

    private func matchLayoutWindows(slots: [SavedLayoutSlot], windows: [WindowItem]) -> [UUID: WindowItem] {
        var matches: [UUID: WindowItem] = [:]
        var usedWindowIDs = Set<String>()

        for slot in slots.sorted(by: { $0.position < $1.position }) {
            let candidates = windows.filter { window in
                guard !usedWindowIDs.contains(window.id) else {
                    return false
                }

                if let bundleIdentifier = slot.bundleIdentifier, !bundleIdentifier.isEmpty {
                    return window.bundleIdentifier == bundleIdentifier
                }

                return window.appName == slot.appName
            }

            let match = candidates.first { candidate in
                !slot.windowTitle.isEmpty && candidate.title == slot.windowTitle
            } ?? candidates.first

            if let match {
                matches[slot.id] = match
                usedWindowIDs.insert(match.id)
            }
        }

        return matches
    }

    private func executeThreeWaySplit() {
        let windows = selectedSplitWindows

        guard canSplitThreeWindows, windows.count == layoutSlotCount else {
            resultKind = .error
            executionResult = "Choose \(layoutSlotCount) different window(s) before arranging."
            return
        }

        let frames = frames(for: selectedLayoutKind)

        guard frames.count == windows.count else {
            resultKind = .error
            executionResult = "Could not read the current screen size."
            return
        }

        isExecuting = true
        resultKind = .neutral
        executionResult = "Arranging selected windows..."

        DispatchQueue.global(qos: .userInitiated).async {
            let resultMessage = performLayoutArrangement(
                windows: windows,
                frames: frames,
                successMessage: "Arranged \(windows.count) window(s) using \(selectedLayoutKind.title)."
            )

            DispatchQueue.main.async {
                resultKind = statusKind(for: resultMessage)
                executionResult = resultMessage
                isExecuting = false
                loadAvailableWindows(preserveSelection: true)
            }
        }
    }

    private func currentVisibleWindowManagementFrame() -> CGRect? {
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

    private func frames(for layout: SavedLayout) -> [CGRect] {
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

    private func frames(for layoutKind: LayoutKind) -> [CGRect] {
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

    private func performLayoutArrangement(windows: [WindowItem], frames: [CGRect], successMessage: String) -> String {
        var messages: [String] = []
        var successCount = 0

        for index in windows.indices {
            let window = windows[index]
            let frame = frames[index]

            guard let windowElement = resolveWindowElement(for: window) else {
                messages.append("Failed to find \(window.displayName).")
                continue
            }

            NSRunningApplication(processIdentifier: window.processIdentifier)?
                .activate(options: [])

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

    private func resolveWindowElement(for item: WindowItem) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(item.processIdentifier)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success, let windowElements = windowsRef as? [AXUIElement] else {
            return nil
        }

        let indexedWindows = windowElements.enumerated().filter { _, element in
            isSelectableWindow(element)
        }

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

    private func executeResize() {
        guard let dimensions = targetDimensions else {
            resultKind = .error
            executionResult = "Enter valid dimensions before resizing."
            return
        }

        isExecuting = true
        resultKind = .neutral
        executionResult = "Preparing \(selectedAppName)..."

        let chosenApp = appleScriptEscaped(selectedAppName)
        let resizeScopeStr = resizeAllWindows ? "All Windows" : "Main Window"

        let script = """
        set chosenApp to "\(chosenApp)"
        set theWidth to \(dimensions.width)
        set theHeight to \(dimensions.height)
        set resizeScope to "\(resizeScopeStr)"

        set screenWidth to 0
        set screenHeight to 0
        try
            tell application "Finder"
                set desktopBounds to bounds of window of desktop
                set screenWidth to item 3 of desktopBounds
                set screenHeight to item 4 of desktopBounds
            end tell
        end try

        try
            tell application chosenApp
                activate
                reopen
            end tell
        end try
        delay 0.5

        set resultsText to ""
        set successCount to 0

        tell application "System Events"
            try
                tell process chosenApp
                    if (count of windows) is 0 then
                        return "Error: Application is running but has no visible windows."
                    end if

                    set minimizedWindows to (windows whose value of attribute "AXMinimized" is true)
                    repeat with mw in minimizedWindows
                        try
                            set value of attribute "AXMinimized" of mw to false
                        end try
                    end repeat

                    if (count of minimizedWindows) > 0 then delay 0.5

                    set targetWindows to {}

                    if resizeScope is "Main Window" then
                        try
                            set end of targetWindows to (first window whose role description is "standard window" or subrole is "AXStandardWindow")
                        on error
                            set end of targetWindows to window 1
                        end try
                    else
                        set targetWindows to (every window whose role description is "standard window" or subrole is "AXStandardWindow")
                        if (count of targetWindows) is 0 then
                            set targetWindows to every window
                        end if
                    end if

                    repeat with targetWindow in targetWindows
                        try
                            if value of attribute "AXFullScreen" of targetWindow is true then
                                set value of attribute "AXFullScreen" of targetWindow to false
                                delay 1.0
                            end if
                        end try

                        set originalSize to size of targetWindow

                        try
                            set currentPos to position of targetWindow
                            set currX to item 1 of currentPos
                            set currY to item 2 of currentPos

                            set newX to currX
                            set newY to currY

                            if screenWidth > 0 and screenHeight > 0 then
                                if (newX + theWidth) > screenWidth then
                                    set newX to screenWidth - theWidth
                                end if
                                if (newY + theHeight) > screenHeight then
                                    set newY to screenHeight - theHeight
                                end if

                                if newX < 0 then set newX to 0
                                if newY < 30 then set newY to 30

                                if newX is not currX or newY is not currY then
                                    set position of targetWindow to {newX, newY}
                                end if
                            end if

                            set size of targetWindow to {theWidth, theHeight}
                        end try

                        delay 0.3
                        set actualSize to size of targetWindow

                        if (item 1 of actualSize is (item 1 of originalSize)) and (item 2 of actualSize is (item 2 of originalSize)) and ((item 1 of actualSize is not theWidth) or (item 2 of actualSize is not theHeight)) then
                            set resultsText to resultsText & "A window was blocked from resizing and stayed at " & (item 1 of actualSize) & "x" & (item 2 of actualSize) & ".\\n"
                        else if (item 1 of actualSize is not theWidth) or (item 2 of actualSize is not theHeight) then
                            set resultsText to resultsText & "A window resized to " & (item 1 of actualSize) & "x" & (item 2 of actualSize) & " because of app constraints.\\n"
                        else
                            set successCount to successCount + 1
                        end if
                    end repeat
                end tell

                tell application chosenApp to activate

                if resultsText is not "" then
                    if successCount > 0 then
                        return (successCount as string) & " window(s) resized.\\n\\n" & resultsText
                    end if
                    return resultsText
                else
                    return "Resized " & (successCount as string) & " window(s) of " & chosenApp & " to " & (theWidth as string) & "x" & (theHeight as string) & "."
                end if

            on error errMsg
                return "Failed: " & errMsg
            end try
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var errorDict: NSDictionary?

            guard let appleScript = NSAppleScript(source: script) else {
                DispatchQueue.main.async {
                    resultKind = .error
                    executionResult = "Could not parse the internal AppleScript."
                    isExecuting = false
                }
                return
            }

            let result = appleScript.executeAndReturnError(&errorDict)
            let resultMessage: String

            if let errorDict {
                resultMessage = "Script error: \(errorDict)"
            } else {
                resultMessage = result.stringValue ?? "Done."
            }

            DispatchQueue.main.async {
                resultKind = statusKind(for: resultMessage)
                executionResult = resultMessage
                isExecuting = false
            }
        }
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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

extension AXError {
    var readableDescription: String {
        switch self {
        case .success: "Success"
        case .failure: "General Accessibility failure"
        case .illegalArgument: "Illegal Accessibility argument"
        case .invalidUIElement: "The window is no longer available"
        case .invalidUIElementObserver: "Invalid Accessibility observer"
        case .cannotComplete: "The app could not complete the request"
        case .attributeUnsupported: "The window does not support that resize attribute"
        case .actionUnsupported: "The window does not support that action"
        case .notificationUnsupported: "Notification unsupported"
        case .notImplemented: "Not implemented"
        case .notificationAlreadyRegistered: "Notification already registered"
        case .notificationNotRegistered: "Notification not registered"
        case .apiDisabled: "Accessibility API disabled"
        case .noValue: "No Accessibility value"
        case .parameterizedAttributeUnsupported: "Parameterized attribute unsupported"
        case .notEnoughPrecision: "Not enough precision"
        @unknown default: "Unknown Accessibility error"
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension CGRect {
    func roundedForWindowManagement() -> CGRect {
        CGRect(
            x: round(minX),
            y: round(minY),
            width: round(width),
            height: round(height)
        )
    }
}

struct HeaderView: View {
    var body: some View {
        HStack(spacing: 14) {
            AppIconView()

            VStack(alignment: .leading, spacing: 3) {
                Text("Window Resizer")
                    .font(.title2.weight(.semibold))

                Text("Resize windows, split three, or open saved layouts.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

struct AppIconView: View {
    var body: some View {
        Group {
            if let icon = NSImage(named: "WindowResizerIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 5)
        .accessibilityHidden(true)
    }
}

struct PermissionBanner: View {
    let promptAction: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title3)
                .foregroundColor(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("Accessibility access required")
                    .font(.headline)

                Text("Window Resizer needs Accessibility permission to move and resize windows in other apps.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(spacing: 8) {
                Button("Prompt", action: promptAction)
                Button("Settings", action: settingsAction)
            }
            .controlSize(.small)
        }
        .padding(13)
        .background(Color.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }
}

struct Panel<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: symbolName)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }
}

struct DimensionField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)

            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.center)
        }
    }
}

struct StatusBanner: View {
    let text: String
    let kind: ResizeStatusKind

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: kind.symbolName)
                .foregroundColor(kind.color)
                .frame(width: 18)

            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(kind.color.opacity(0.24), lineWidth: 1)
        )
    }
}

struct WindowBackground: View {
    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color.blue.opacity(0.08),
                    Color.clear,
                    Color.cyan.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
    }
}
