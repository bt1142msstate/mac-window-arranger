import SwiftUI

struct LayoutMockupPreview: View {
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
