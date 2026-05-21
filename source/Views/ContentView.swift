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

                let currentSize = store.workflowMode.contentSize
                let newSize = newMode.contentSize
                if newSize.height < currentSize.height || newSize.width < currentSize.width {
                    store.workflowMode = newMode
                    DispatchQueue.main.async {
                        AppDelegate.shared?.fitMainWindowToContentSize(newSize)
                    }
                    return
                }

                AppDelegate.shared?.fitMainWindowToContentSize(newMode.contentSize) {
                    store.workflowMode = newMode
                }
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

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(layout.slots.sorted { $0.position < $1.position }) { slot in
                        SavedSlotPreviewRow(layout: layout, slot: slot)
                    }
                }
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

private struct SavedSlotPreviewRow: View {
    let layout: SavedLayout
    let slot: SavedLayoutSlot

    var body: some View {
        HStack(spacing: 8) {
            Text(layout.layoutKind.slotTitle(for: slot.position))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)

            Text(slot.appName)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            if !slot.windowTitle.isEmpty {
                Text(slot.windowTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
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

                VStack(spacing: 6) {
                    ForEach(0..<store.layoutSlotCount, id: \.self) { index in
                        SlotPickerRow(
                            title: store.splitSlotTitle(for: index),
                            selection: splitSelectionBinding(for: index),
                            windows: store.availableWindows,
                            isDisabled: store.isExecuting || store.availableWindows.isEmpty
                        )
                    }
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

    private func splitSelectionBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                store.splitWindowID(at: index)
            },
            set: { selectedID in
                store.setSplitWindowSelection(selectedID, at: index)
            }
        )
    }
}

private struct SlotPickerRow: View {
    let title: String
    let selection: Binding<String>
    let windows: [WindowItem]
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)

            Picker(title, selection: selection) {
                Text("Choose window").tag("")

                ForEach(windows) { window in
                    Text(window.displayName).tag(window.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .disabled(isDisabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
