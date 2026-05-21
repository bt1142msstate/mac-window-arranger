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
                HStack(alignment: .center, spacing: 16) {
                    HeaderView()
                        .layoutPriority(1)

                    WorkflowModePicker(store: store)
                        .frame(width: 240)
                }

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

    var body: some View {
        Picker("Mode", selection: workflowModeBinding) {
            ForEach(WindowWorkflowMode.allCases) { mode in
                Label(mode.title, systemImage: mode.symbolName)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(store.isExecuting || store.isPickingWindow)
    }

    private var workflowModeBinding: Binding<WindowWorkflowMode> {
        Binding(
            get: {
                store.workflowMode
            },
            set: { newMode in
                guard newMode != store.workflowMode else {
                    return
                }

                AppDelegate.shared?.fitMainWindowToContentSize(
                    newMode.contentSize,
                    prepareContent: {
                        store.workflowMode = newMode
                    }
                )
            }
        )
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
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Layout name", text: $store.layoutName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(store.isExecuting)

                    SavedLayoutPreview(layout: store.selectedSavedLayout)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Picker("Saved Layout", selection: $store.selectedLayoutID) {
                            if store.savedLayouts.isEmpty {
                                Text("No saved layouts").tag("")
                            } else {
                                ForEach(store.savedLayouts) { layout in
                                    Text(layout.name).tag(layout.id.uuidString)
                                }
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .disabled(store.isExecuting || store.savedLayouts.isEmpty)

                        MetricBadge(text: "\(store.savedLayouts.count) saved")
                    }

                    Button(action: store.applySelectedLayout) {
                        Label("Open & Arrange", systemImage: "play.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canApplyLayout)

                    HStack(spacing: 8) {
                        Button(action: store.saveCurrentLayout) {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!store.canSaveLayout)

                        Button(role: .destructive, action: store.deleteSelectedLayout) {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.selectedSavedLayout == nil || store.isExecuting)
                    }
                }
                .frame(width: 246, alignment: .top)
            }
        }
    }
}

private struct SavedLayoutPreview: View {
    let layout: SavedLayout?

    var body: some View {
        if let layout {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(layout.layoutKind.title, systemImage: layout.layoutKind.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    MetricBadge(text: "\(layout.slots.count) windows")
                }

                LayoutMockupPreview(panes: layout.previewPanes, height: 112)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
            )
        } else {
            Text("Name a layout, choose the windows below, then save it. Open & Arrange restores the matching apps and window positions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        }
    }
}

private struct LayoutMockupPreview: View {
    let panes: [LayoutPreviewPane]
    var windows: [WindowItem] = []
    var height: CGFloat = 142
    var isDisabled = false
    var selectWindow: ((Int, String) -> Void)?

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
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func paneContent(for pane: LayoutPreviewPane) -> some View {
        if let selectWindow {
            Menu {
                if windows.isEmpty {
                    Label("No windows available", systemImage: "exclamationmark.triangle")
                } else {
                    Button {
                        selectWindow(pane.position, "")
                    } label: {
                        Label("Choose window", systemImage: pane.selectedWindowID == nil ? "checkmark.circle.fill" : "circle")
                    }

                    Divider()

                    ForEach(windows) { window in
                        let isCurrentSelection = pane.selectedWindowID == window.id
                        let isUsedElsewhere = panes.contains { otherPane in
                            otherPane.position != pane.position && otherPane.selectedWindowID == window.id
                        }

                        Button {
                            selectWindow(pane.position, window.id)
                        } label: {
                            Label(window.displayName, systemImage: isCurrentSelection ? "checkmark.circle.fill" : "macwindow")
                        }
                        .disabled(isUsedElsewhere && !isCurrentSelection)
                    }
                }
            } label: {
                LayoutMockupPaneView(pane: pane, showsMenuIndicator: true)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .help("Choose \(pane.slotTitle)")
        } else {
            LayoutMockupPaneView(pane: pane)
        }
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

            Text(pane.primaryLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

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
                    Picker("Application", selection: $store.selectedAppName) {
                        if store.runningApps.isEmpty {
                            Text("No running apps found").tag("")
                        }

                        ForEach(store.runningApps) { app in
                            Text(app.name).tag(app.name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .disabled(store.isExecuting || store.isPickingWindow)

                    Button(action: store.pickWindowAndResize) {
                        Label(store.isPickingWindow ? "Picking" : "Pick Window", systemImage: "scope")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isExecuting || store.isPickingWindow)
                }

                if let selectedApp = store.runningApps.first(where: { $0.name == store.selectedAppName }) {
                    Label(selectedApp.bundleIdentifier ?? "Running application", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
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
                    isDisabled: store.isExecuting
                ) { position, selectedID in
                    store.setSplitWindowSelection(selectedID, at: position)
                }

                HStack(alignment: .center, spacing: 10) {
                    Label(store.splitPickerStatusText, systemImage: "rectangle.split.3x1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer()

                    Button(action: store.executeThreeWaySplit) {
                        Label("Arrange Selected", systemImage: store.selectedLayoutKind.symbolName)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canSplitSelectedWindows)
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
