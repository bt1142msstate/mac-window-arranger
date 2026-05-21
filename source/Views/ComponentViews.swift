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

struct AppIconView: View {
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 12
    var shadow = true

    var body: some View {
        Group {
            if let icon = NSImage(named: "WindowArrangerIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(shadow ? 0.14 : 0), radius: shadow ? 10 : 0, x: 0, y: shadow ? 5 : 0)
        .accessibilityHidden(true)
    }
}

struct ApplicationIconImage: View {
    let bundleIdentifier: String?
    let appName: String?
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            .accessibilityHidden(true)
    }

    private var icon: NSImage {
        if
            let bundleIdentifier,
            !bundleIdentifier.isEmpty,
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        if
            let appName,
            let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }),
            let bundleURL = runningApp.bundleURL
        {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

struct PermissionBanner: View {
    let promptAction: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("Accessibility access required")
                    .font(.headline)

                Text("Window Arranger needs Accessibility permission to move, resize, and arrange windows in other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(spacing: 8) {
                Button("Prompt", action: promptAction)
                Button("Settings", action: settingsAction)
            }
            .controlSize(.small)
        }
        .padding(13)
        .background(Color.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }
}

struct Panel<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }
}

struct DimensionField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.center)
        }
    }
}

struct StatusBanner: View {
    let text: String
    let kind: ResizeStatusKind

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: kind.symbolName)
                .foregroundStyle(kind.color)
                .frame(width: 18)

            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(kind.color.opacity(0.24), lineWidth: 1)
        )
    }
}

struct WindowBackground: View {
    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color.blue.opacity(0.07),
                    Color.clear,
                    Color.teal.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
    }
}

extension ResizeStatusKind {
    var symbolName: String {
        switch self {
        case .neutral: "clock"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .neutral: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
