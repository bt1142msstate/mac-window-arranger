import SwiftUI

struct LayoutBuilderSection: View {
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
