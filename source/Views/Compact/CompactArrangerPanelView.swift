import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CompactLayoutOption: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let isSelected: Bool
}

struct CompactArrangerPanelView: View {
    let message: String
    let kind: ResizeStatusKind
    let layoutTitle: String?
    let layoutOptions: [CompactLayoutOption]
    let selectLayoutAction: (String) -> Void
    let expandAction: () -> Void
    let quitAction: () -> Void
    @State private var isShowingLayoutPicker = false

    var body: some View {
        HStack(spacing: 11) {
            AppIconView(size: 34, cornerRadius: 7, shadow: false)

            VStack(alignment: .leading, spacing: 2) {
                layoutControl
                    .font(.callout.weight(.semibold))

                Label(message, systemImage: kind.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: expandAction) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help("Open Window Arranger")
            .accessibilityLabel("Open Window Arranger")

            Button(action: quitAction) {
                Image(systemName: "xmark")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help("Quit Window Arranger")
            .accessibilityLabel("Quit Window Arranger")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(kind.color.opacity(0.28), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var layoutControl: some View {
        if layoutOptions.isEmpty {
            Text("Window Arranger")
                .lineLimit(1)
        } else {
            Button {
                isShowingLayoutPicker.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(layoutTitle ?? "Unsaved Layout")
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .help("Choose and apply a saved layout")
            .accessibilityLabel("Choose saved layout")
            .popover(isPresented: $isShowingLayoutPicker, arrowEdge: .bottom) {
                CompactLayoutPicker(
                    options: layoutOptions,
                    selectLayout: { layoutID in
                        isShowingLayoutPicker = false
                        selectLayoutAction(layoutID)
                    }
                )
            }
        }
    }
}

private struct CompactLayoutPicker: View {
    let options: [CompactLayoutOption]
    let selectLayout: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Saved Layouts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(options) { option in
                Button {
                    selectLayout(option.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: option.isSelected ? "checkmark.circle.fill" : "rectangle.3.group")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(option.isSelected ? .blue : .secondary)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)

                            Text(option.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(option.isSelected ? Color.blue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 250, alignment: .leading)
    }
}
