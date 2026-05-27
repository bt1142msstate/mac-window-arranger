import AppKit
import SwiftUI

struct ContentView: View {
    @State private var store = WindowArrangerStore()

    private let appRefreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var store = store
        let contentSize = store.workflowMode.contentSize

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !store.hasAccessibilityAccess {
                    PermissionBanner(
                        promptAction: store.requestAccessibilityAccess,
                        settingsAction: store.openAccessibilitySettings
                    )
                }

                switch store.workflowMode {
                case .resize:
                    ResizeWorkflowSection(store: store)
                case .arrange:
                    ArrangeWorkflowSection(store: store)
                }
            }
            .padding(18)
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .background(WindowBackground())
        .tint(.blue)
        .toolbar {
            ToolbarItem(placement: .principal) {
                WorkflowModePicker(store: store)
                    .frame(width: 116)
            }

            ToolbarItem {
                Button(action: store.compactToDock) {
                    Label("Mini Mode", systemImage: "minus.rectangle")
                }
                .help("Switch to Mini Mode")
            }
        }
        .onAppear {
            store.start()
            AppDelegate.shared?.fitMainWindowToContentSize(contentSize, animated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshAccessibilityAccess()
            store.loadRunningApps(preserveSelection: true)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            store.loadRunningApps(preserveSelection: true)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            store.loadRunningApps(preserveSelection: true)
        }
        .onReceive(appRefreshTimer) { _ in
            store.refreshAccessibilityAccess()
            store.loadRunningApps(preserveSelection: true)
        }
        .onChange(of: store.selectedLayoutID) { _, _ in
            store.syncSelectedLayoutMetadata()
        }
        .onChange(of: store.selectedLayoutKind) { _, _ in
            store.normalizeLayoutSelectionAndRefresh()
        }
        .onChange(of: store.customLayoutWindowCount) { _, _ in
            store.normalizeLayoutSelectionAndRefresh()
        }
        .animation(.snappy(duration: 0.18), value: store.selectedPreset)
        .animation(.snappy(duration: 0.18), value: store.executionResult.isEmpty)
        .animation(.snappy(duration: 0.18), value: store.availableWindows.count)
    }
}

private struct WorkflowModePicker: View {
    @Bindable var store: WindowArrangerStore
    @State private var visualMode: WindowWorkflowMode?
    @State private var pendingMode: WindowWorkflowMode?

    private let pillTransitionDuration: TimeInterval = 0.36
    private let pillAnimation: Animation = .spring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.06)
    private let modes = WindowWorkflowMode.allCases

    var body: some View {
        GeometryReader { proxy in
            let mode = visualMode ?? store.workflowMode
            let segmentWidth = proxy.size.width / CGFloat(max(modes.count, 1))
            let selectedIndex = CGFloat(index(of: mode))
            let indicatorWidth = min(42, max(segmentWidth - 16, 0))
            let indicatorHeight = max(proxy.size.height - 12, 0)
            let indicatorX = (selectedIndex * segmentWidth) + ((segmentWidth - indicatorWidth) / 2)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.clear)

                Capsule()
                    .fill(.ultraThinMaterial)
                    .frame(width: indicatorWidth, height: indicatorHeight)
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.38), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.10), radius: 3, x: 0, y: 1)
                    .offset(x: indicatorX)
                    .animation(pillAnimation, value: selectedIndex)

                HStack(spacing: 0) {
                    ForEach(modes) { pickerMode in
                        Button {
                            guard !isInteractionDisabled else {
                                return
                            }

                            requestMode(pickerMode)
                        } label: {
                            Image(systemName: pickerMode.symbolName)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: segmentWidth, height: proxy.size.height)
                                .foregroundStyle(mode == pickerMode ? .primary : .secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.clear)
                        .help(pickerMode.title)
                        .accessibilityLabel(pickerMode.title)
                        .accessibilityAddTraits(.isButton)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                guard !isInteractionDisabled else {
                                    return
                                }

                                requestMode(pickerMode)
                            }
                        )
                    }
                }
            }
            .overlay(
                Capsule()
                    .stroke(Color.secondary.opacity(0.30), lineWidth: 1)
            )
        }
        .frame(height: 34)
        .opacity(store.isExecuting || store.isPickingWindow ? 0.58 : 1)
        .onAppear {
            visualMode = store.workflowMode
        }
        .onChange(of: store.workflowMode) { _, newMode in
            guard pendingMode == nil else {
                return
            }

            visualMode = newMode
        }
    }

    private var isInteractionDisabled: Bool {
        store.isExecuting || store.isPickingWindow || pendingMode != nil
    }

    private func requestMode(_ newMode: WindowWorkflowMode) {
        let currentMode = visualMode ?? store.workflowMode

        guard newMode != currentMode, pendingMode == nil else {
            return
        }

        pendingMode = newMode

        withAnimation(pillAnimation) {
            visualMode = newMode
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pillTransitionDuration) {
            guard pendingMode == newMode else {
                return
            }

            guard let appDelegate = AppDelegate.shared else {
                store.workflowMode = newMode
                pendingMode = nil
                return
            }

            appDelegate.fitMainWindowToContentSize(
                newMode.contentSize,
                prepareContent: {
                    store.workflowMode = newMode
                },
                completion: {
                    pendingMode = nil
                }
            )
        }
    }

    private func index(of mode: WindowWorkflowMode) -> Int {
        modes.firstIndex(of: mode) ?? 0
    }
}

private struct ResizeWorkflowSection: View {
    @Bindable var store: WindowArrangerStore

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 14) {
                TargetSection(store: store)
                ResizeSection(store: store)
            }
            .frame(width: 400, alignment: .top)

            VStack(spacing: 14) {
                OptionsSection(store: store)
                PrimaryActionSection(store: store)
            }
            .frame(width: 310, alignment: .top)
        }
    }
}

private struct ArrangeWorkflowSection: View {
    @Bindable var store: WindowArrangerStore

    var body: some View {
        VStack(spacing: 14) {
            SavedLayoutsSection(store: store)
            LayoutBuilderSection(store: store)

            if !store.executionResult.isEmpty {
                StatusBanner(text: store.executionResult, kind: store.resultKind)
            }
        }
    }
}

private struct SavedLayoutsSection: View {
    @Bindable var store: WindowArrangerStore

    var body: some View {
        Panel(title: "Saved Layouts", symbolName: "rectangle.stack") {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 9) {
                    TextField("Layout name", text: $store.layoutName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220)
                        .layoutPriority(1)
                        .disabled(store.isExecuting)

                    Button(action: store.createNewLayoutDraft) {
                        Image(systemName: "plus")
                            .frame(width: 22)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isExecuting)
                    .help("Start a new saved layout")
                    .accessibilityLabel("Start a new saved layout")

                    Button(action: store.saveCurrentLayout) {
                        Image(systemName: "square.and.arrow.down")
                            .frame(width: 22)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.canSaveLayout)
                    .help("Save the current layout")
                    .accessibilityLabel("Save the current layout")

                    Button(action: store.applySelectedLayout) {
                        Label("Open & Arrange", systemImage: "play.rectangle")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .fixedSize()
                    .disabled(!store.canApplyLayout)

                    Button(role: .destructive, action: store.deleteSelectedLayout) {
                        Image(systemName: "trash")
                            .frame(width: 22)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.selectedSavedLayout == nil || store.isExecuting)
                    .help("Delete selected layout")
                    .accessibilityLabel("Delete selected layout")
                }

                HStack(alignment: .top, spacing: 12) {
                    SavedLayoutLibrary(
                        layouts: store.savedLayouts,
                        selectedLayoutID: $store.selectedLayoutID,
                        isDisabled: store.isExecuting
                    )
                    .frame(width: 246, alignment: .top)

                    SavedLayoutPreview(layout: store.selectedSavedLayout)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }
}

private struct SavedLayoutLibrary: View {
    let layouts: [SavedLayout]
    @Binding var selectedLayoutID: String
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("Layouts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                MetricBadge(text: "\(layouts.count) saved")
            }

            if layouts.isEmpty {
                SavedLayoutsEmptyState()
                    .frame(height: 112)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(layouts) { layout in
                            Button {
                                selectedLayoutID = layout.id.uuidString
                            } label: {
                                SavedLayoutLibraryRow(
                                    layout: layout,
                                    isSelected: selectedLayoutID == layout.id.uuidString
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isDisabled)
                        }
                    }
                    .padding(1)
                }
                .frame(height: 112)
            }
        }
    }
}

private struct SavedLayoutsEmptyState: View {
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "rectangle.stack")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("No saved layouts yet")
                .font(.caption.weight(.semibold))

            Text("Choose windows below, name the layout, then save it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct SavedLayoutLibraryRow: View {
    let layout: SavedLayout
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            SavedLayoutIconStack(slots: layout.slots)

            VStack(alignment: .leading, spacing: 2) {
                Text(layout.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text("\(layout.layoutKind.title) - \(layout.slots.count) windows")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .blue : .secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.blue.opacity(0.13) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? Color.blue.opacity(0.36) : Color.secondary.opacity(0.10), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct SavedLayoutIconStack: View {
    let slots: [SavedLayoutSlot]

    private var visibleSlots: [SavedLayoutSlot] {
        Array(slots.sorted { $0.position < $1.position }.prefix(3))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if visibleSlots.isEmpty {
                Image(systemName: "macwindow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                ForEach(visibleSlots.indices, id: \.self) { index in
                    let slot = visibleSlots[index]

                    ApplicationIconImage(
                        bundleIdentifier: slot.bundleIdentifier,
                        appName: slot.appName,
                        size: 22
                    )
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                    )
                    .offset(x: CGFloat(index) * 11)
                    .zIndex(Double(index))
                }
            }
        }
        .frame(width: 46, height: 24, alignment: .leading)
        .accessibilityHidden(true)
    }
}

private struct SavedLayoutPreview: View {
    let layout: SavedLayout?

    var body: some View {
        if let layout {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(layout.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)

                        Label(layout.layoutKind.title, systemImage: layout.layoutKind.symbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        MetricBadge(text: "\(layout.slots.count) windows")

                        Text(layout.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                LayoutMockupPreview(panes: layout.previewPanes, height: 98)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Ready for a new layout", systemImage: "sparkles")
                    .font(.callout.weight(.semibold))

                Text("Name the layout, choose windows in the builder, then save it. Select a saved layout to preview and restore it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
    }
}

private struct LayoutMockupPreview: View {
    let panes: [LayoutPreviewPane]
    var windows: [WindowItem] = []
    var height: CGFloat = 142
    var isDisabled = false
    var selectWindow: ((Int, String) -> Void)?
    var chooseWindow: ((Int) -> Void)?
    @State private var activePanePosition: Int?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.secondary.opacity(0.07))

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)

                ForEach(panes) { pane in
                    paneContent(for: pane)
                        .frame(width: previewFrame(for: pane, in: proxy.size).width, height: previewFrame(for: pane, in: proxy.size).height)
                        .offset(x: previewFrame(for: pane, in: proxy.size).minX, y: previewFrame(for: pane, in: proxy.size).minY)
                }
            }
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func paneContent(for pane: LayoutPreviewPane) -> some View {
        if let selectWindow {
            Button {
                activePanePosition = pane.position
            } label: {
                LayoutMockupPaneView(pane: pane, showsMenuIndicator: true)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .help("Choose \(pane.slotTitle)")
            .popover(isPresented: isPopoverPresented(for: pane.position), arrowEdge: .bottom) {
                LayoutPaneWindowChooser(
                    pane: pane,
                    panes: panes,
                    windows: windows,
                    chooseWindow: {
                        activePanePosition = nil
                        chooseWindow?(pane.position)
                    },
                    clearSelection: {
                        activePanePosition = nil
                        selectWindow(pane.position, "")
                    },
                    selectWindow: { selectedID in
                        activePanePosition = nil
                        selectWindow(pane.position, selectedID)
                    }
                )
            }
        } else {
            LayoutMockupPaneView(pane: pane)
        }
    }

    private func isPopoverPresented(for position: Int) -> Binding<Bool> {
        Binding(
            get: {
                activePanePosition == position
            },
            set: { isPresented in
                if !isPresented {
                    activePanePosition = nil
                }
            }
        )
    }

    private func previewFrame(for pane: LayoutPreviewPane, in size: CGSize) -> CGRect {
        let inset: CGFloat = 7
        let paneSpacing: CGFloat = 5
        let availableWidth = max(size.width - (inset * 2), 1)
        let availableHeight = max(size.height - (inset * 2), 1)

        return CGRect(
            x: inset + (pane.frame.minX * availableWidth),
            y: inset + (pane.frame.minY * availableHeight),
            width: max((pane.frame.width * availableWidth) - paneSpacing, 38),
            height: max((pane.frame.height * availableHeight) - paneSpacing, 38)
        )
    }
}

private struct LayoutPaneWindowChooser: View {
    let pane: LayoutPreviewPane
    let panes: [LayoutPreviewPane]
    let windows: [WindowItem]
    let chooseWindow: () -> Void
    let clearSelection: () -> Void
    let selectWindow: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pane.slotTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button(action: chooseWindow) {
                Label("Choose Window", systemImage: "scope")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)

            if pane.selectedWindowID != nil {
                Button(action: clearSelection) {
                    Label("Clear Selection", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            if windows.isEmpty {
                Label("No visible windows listed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(windows) { window in
                            let isCurrentSelection = pane.selectedWindowID == window.id
                            let isUsedElsewhere = panes.contains { otherPane in
                                otherPane.position != pane.position && otherPane.selectedWindowID == window.id
                            }

                            Button {
                                selectWindow(window.id)
                            } label: {
                                HStack(spacing: 7) {
                                    ZStack(alignment: .bottomTrailing) {
                                        ApplicationIconImage(
                                            bundleIdentifier: window.bundleIdentifier,
                                            appName: window.appName,
                                            size: 20
                                        )

                                        if isCurrentSelection {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white, .blue)
                                                .offset(x: 2, y: 2)
                                        }
                                    }
                                    .frame(width: 22)

                                    Text(window.displayName)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(isUsedElsewhere && !isCurrentSelection ? .secondary : .primary)
                            .disabled(isUsedElsewhere && !isCurrentSelection)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(isCurrentSelection ? Color.blue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 210)
            }
        }
        .padding(12)
        .frame(width: 310, alignment: .leading)
    }
}

private struct LayoutMockupPaneView: View {
    let pane: LayoutPreviewPane
    var showsMenuIndicator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(pane.slotTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)

                Image(systemName: pane.hasWindow ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.caption2)
                    .foregroundStyle(pane.hasWindow ? .blue : .secondary)
                    .accessibilityHidden(true)

                if showsMenuIndicator {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                if pane.hasWindow {
                    ApplicationIconImage(
                        bundleIdentifier: pane.bundleIdentifier,
                        appName: pane.appName,
                        size: 14
                    )
                }

                Text(pane.primaryLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Text(pane.secondaryLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(pane.hasWindow ? Color.blue.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(pane.hasWindow ? Color.blue.opacity(0.42) : Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityLabel("\(pane.slotTitle), \(pane.primaryLabel), \(pane.secondaryLabel)")
    }
}

private struct MetricBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.10), in: Capsule())
    }
}

private struct TargetSection: View {
    @Bindable var store: WindowArrangerStore

    var body: some View {
        Panel(title: "Target", symbolName: "app.dashed") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ApplicationSelectionMenu(
                        apps: store.runningApps,
                        selection: $store.selectedAppName,
                        isDisabled: store.isExecuting || store.isPickingWindow
                    )
                    .frame(maxWidth: .infinity)

                    Button(action: store.pickWindowAndResize) {
                        Label(store.isPickingWindow ? "Picking" : "Pick Window", systemImage: "scope")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isExecuting || store.isPickingWindow)
                }

                if let selectedApp = store.selectedApp {
                    Label(selectedApp.bundleIdentifier ?? selectedApp.statusLabel, systemImage: selectedApp.isRunning ? "checkmark.circle" : "arrow.down.app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct ApplicationSelectionMenu: View {
    let apps: [AppItem]
    @Binding var selection: String
    let isDisabled: Bool
    @State private var isShowingPicker = false
    @State private var searchText = ""

    private var selectedApp: AppItem? {
        apps.first { $0.name == selection }
    }

    private var filteredApps: [AppItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return apps
        }

        return apps.filter { app in
            app.name.localizedCaseInsensitiveContains(query)
                || app.bundleIdentifier?.localizedCaseInsensitiveContains(query) == true
        }
    }

    var body: some View {
        Button {
            searchText = ""
            isShowingPicker.toggle()
        } label: {
            HStack(spacing: 8) {
                if let selectedApp {
                    ApplicationIconImage(
                        bundleIdentifier: selectedApp.bundleIdentifier,
                        appName: selectedApp.name,
                        size: 18
                    )
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedApp?.name ?? "Search apps")
                        .lineLimit(1)

                    if let selectedApp {
                        Text(selectedApp.statusLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || apps.isEmpty)
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 9) {
                TextField("Search apps", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                if filteredApps.isEmpty {
                    Label("No apps found", systemImage: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredApps) { app in
                                Button {
                                    selection = app.name
                                    isShowingPicker = false
                                } label: {
                                    ApplicationPickerRow(app: app, isSelected: app.name == selection)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(app.name == selection ? Color.blue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
            }
            .padding(12)
            .frame(width: 330, alignment: .leading)
        }
    }
}

private struct ApplicationPickerRow: View {
    let app: AppItem
    var isSelected = false

    var body: some View {
        HStack(spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                ApplicationIconImage(
                    bundleIdentifier: app.bundleIdentifier,
                    appName: app.name,
                    size: 20
                )

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white, .blue)
                        .offset(x: 2, y: 2)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .lineLimit(1)

                Text(app.bundleIdentifier ?? app.statusLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(app.statusLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(app.isRunning ? .green : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.10), in: Capsule())
        }
    }
}

private struct LayoutBuilderSection: View {
    @Bindable var store: WindowArrangerStore

    var body: some View {
        Panel(title: "Layout Builder", symbolName: store.selectedLayoutKind.symbolName) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Picker("Layout Type", selection: $store.selectedLayoutKind) {
                        ForEach(LayoutKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 172)
                    .disabled(store.isExecuting)

                    Label(store.selectedLayoutKind.detail, systemImage: store.selectedLayoutKind.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    MetricBadge(text: "\(store.layoutSlotCount) windows")
                }

                if store.selectedLayoutKind == .customPositions {
                    Stepper("Window count: \(store.customLayoutWindowCount)", value: $store.customLayoutWindowCount, in: store.customLayoutWindowRange)
                        .font(.caption)
                        .disabled(store.isExecuting)
                }

                LayoutMockupPreview(
                    panes: store.layoutPreviewPanes,
                    windows: store.availableWindows,
                    height: 172,
                    isDisabled: store.isExecuting || store.isPickingWindow,
                    selectWindow: { position, selectedID in
                        store.setSplitWindowSelection(selectedID, at: position)
                    },
                    chooseWindow: { position in
                        store.pickWindowForLayoutSlot(at: position)
                    }
                )

                HStack(alignment: .center, spacing: 10) {
                    Label(store.splitPickerStatusText, systemImage: "rectangle.split.3x1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer()

                    Button(action: store.autoArrangeVisibleWindows) {
                        Label("Auto Arrange", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.canAutoArrangeVisibleWindows)
                    .accessibilityLabel("Auto Arrange")
                    .help("Arrange visible app windows so they do not overlap.")

                    Button(action: store.executeThreeWaySplit) {
                        Label("Arrange Selected", systemImage: store.selectedLayoutKind.symbolName)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canSplitSelectedWindows)
                    .accessibilityLabel("Arrange Selected")
                }
            }
        }
    }
}

private struct ResizeSection: View {
    @Bindable var store: WindowArrangerStore

    var body: some View {
        Panel(title: "Size", symbolName: "aspectratio") {
            VStack(alignment: .leading, spacing: 9) {
                Picker("Preset", selection: $store.selectedPreset) {
                    ForEach(ResizePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(store.isExecuting)

                HStack(spacing: 10) {
                    Label(store.selectedPreset.detail, systemImage: store.selectedPreset.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer()

                    Text(store.dimensionsLabel)
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                        .foregroundStyle(store.targetDimensions == nil ? .red : .primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                if store.selectedPreset == .custom {
                    HStack(spacing: 10) {
                        DimensionField(title: "Width", text: $store.customWidth)
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        DimensionField(title: "Height", text: $store.customHeight)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    if store.targetDimensions == nil {
                        Text("Enter whole-pixel dimensions between 100 and 10000.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}

private struct OptionsSection: View {
    @Bindable var store: WindowArrangerStore

    var body: some View {
        Panel(title: "Options", symbolName: "rectangle.3.group") {
            Toggle(isOn: $store.resizeAllWindows) {
                Text("Resize every standard window")
            }
            .toggleStyle(.switch)
            .disabled(store.isExecuting)
        }
    }
}

private struct PrimaryActionSection: View {
    let store: WindowArrangerStore

    var body: some View {
        Panel(title: "Resize", symbolName: store.resizeAllWindows ? "rectangle.3.group.bubble.left" : "macwindow") {
            VStack(spacing: 10) {
                Button(action: store.executeResize) {
                    HStack(spacing: 8) {
                        if store.isExecuting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: store.resizeAllWindows ? "rectangle.3.group.bubble.left" : "macwindow")
                        }

                        Text(store.isExecuting ? "Resizing..." : "Resize \(store.resizeAllWindows ? "Windows" : "Window")")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!store.canResize)
                .keyboardShortcut(.return, modifiers: .command)

                HStack {
                    Text(store.selectedAppName.isEmpty ? "Choose a running app." : "\(store.selectedAppName) -> \(store.dimensionsLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text(store.resizeAllWindows ? "All windows" : "Front window")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if !store.executionResult.isEmpty {
                    StatusBanner(text: store.executionResult, kind: store.resultKind)
                }
            }
        }
    }
}
