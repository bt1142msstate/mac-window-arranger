import SwiftUI

struct SavedLayoutsSection: View {
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
