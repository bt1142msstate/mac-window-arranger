import SwiftUI

struct TargetSection: View {
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

struct ResizeSection: View {
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

struct OptionsSection: View {
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

struct PrimaryActionSection: View {
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
