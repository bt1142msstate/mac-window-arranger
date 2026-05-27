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
