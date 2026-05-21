import AppKit
import SwiftUI

struct ContentView: View {
    @State private var store = WindowArrangerStore()

    private let appRefreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeaderView()

                if !store.hasAccessibilityAccess {
                    PermissionBanner(
                        promptAction: store.requestAccessibilityAccess,
                        settingsAction: store.openAccessibilitySettings
                    )
                }

                SavedLayoutsSection(store: store)
                TargetSection(store: store)
                LayoutBuilderSection(store: store)
                ResizeSection(store: store)
                OptionsSection(store: store)
                PrimaryActionSection(store: store)
            }
            .padding(22)
        }
        .frame(width: 560, height: 760)
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

private struct SavedLayoutsSection: View {
    @Bindable var store: WindowArrangerStore

    var body: some View {
        Panel(title: "Saved Layouts", symbolName: "rectangle.stack") {
            VStack(alignment: .leading, spacing: 11) {
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

                HStack(spacing: 10) {
                    TextField("Layout name", text: $store.layoutName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(store.isExecuting)

                    Button(action: store.saveCurrentLayout) {
                        Label("Save Layout", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.canSaveLayout)
                }

                HStack(spacing: 10) {
                    Button(action: store.applySelectedLayout) {
                        Label("Open & Arrange", systemImage: "play.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canApplyLayout)

                    Button(role: .destructive, action: store.deleteSelectedLayout) {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.selectedSavedLayout == nil || store.isExecuting)

                    Spacer()

                    Text("\(store.savedLayouts.count) saved")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                SavedLayoutPreview(layout: store.selectedSavedLayout)
            }
        }
    }
}

private struct SavedLayoutPreview: View {
    let layout: SavedLayout?

    var body: some View {
        if let layout {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(layout.layoutKind.title) - \(layout.slots.count) window(s)", systemImage: layout.layoutKind.symbolName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                ForEach(layout.slots.sorted { $0.position < $1.position }) { slot in
                    HStack(spacing: 8) {
                        Text(layout.layoutKind.slotTitle(for: slot.position))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 78, alignment: .leading)

                        Text(slot.appName)
                            .font(.caption)
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
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            Text("Choose a layout type, select the windows, name it, then save it. Opening a saved layout launches those apps and restores the saved arrangement.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TargetSection: View {
    @Bindable var store: WindowArrangerStore

    var body: some View {
        Panel(title: "Target", symbolName: "app.dashed") {
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

            if let selectedApp = store.runningApps.first(where: { $0.name == store.selectedAppName }) {
                Label(selectedApp.bundleIdentifier ?? "Running application", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct LayoutBuilderSection: View {
    @Bindable var store: WindowArrangerStore

    var body: some View {
        Panel(title: "Layout Builder", symbolName: store.selectedLayoutKind.symbolName) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Layout Type", selection: $store.selectedLayoutKind) {
                    ForEach(LayoutKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(store.isExecuting)

                HStack(spacing: 10) {
                    Label(store.selectedLayoutKind.detail, systemImage: store.selectedLayoutKind.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer()

                    Text("\(store.layoutSlotCount) window(s)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if store.selectedLayoutKind == .customPositions {
                    Stepper("Window count: \(store.customLayoutWindowCount)", value: $store.customLayoutWindowCount, in: store.customLayoutWindowRange)
                        .font(.caption)
                        .disabled(store.isExecuting)
                }

                ForEach(0..<store.layoutSlotCount, id: \.self) { index in
                    HStack(spacing: 10) {
                        Text(store.splitSlotTitle(for: index))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 78, alignment: .leading)

                        Picker(store.splitSlotTitle(for: index), selection: splitSelectionBinding(for: index)) {
                            Text("Choose window").tag("")

                            ForEach(store.availableWindows) { window in
                                Text(window.displayName).tag(window.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .disabled(store.isExecuting || store.availableWindows.isEmpty)
                    }
                }

                HStack(spacing: 10) {
                    Label(store.splitPickerStatusText, systemImage: "rectangle.split.3x1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer()

                    Button(action: store.executeThreeWaySplit) {
                        Label("Arrange Selected", systemImage: store.selectedLayoutKind.symbolName)
                    }
                    .buttonStyle(.bordered)
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

private struct ResizeSection: View {
    @Bindable var store: WindowArrangerStore

    var body: some View {
        Panel(title: "Size", symbolName: "aspectratio") {
            Picker("Preset", selection: $store.selectedPreset) {
                ForEach(ResizePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
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

private struct OptionsSection: View {
    @Bindable var store: WindowArrangerStore

    var body: some View {
        Panel(title: "Options", symbolName: "rectangle.3.group") {
            Toggle(isOn: $store.resizeAllWindows) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resize every standard window")
                    Text("Leave this off to target only the frontmost window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(store.isExecuting)
        }
    }
}

private struct PrimaryActionSection: View {
    let store: WindowArrangerStore

    var body: some View {
        VStack(spacing: 12) {
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
