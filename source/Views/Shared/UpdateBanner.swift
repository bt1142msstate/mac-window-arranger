import SwiftUI

struct UpdateBanner: View {
    let status: AppUpdateStatus
    let checkAction: () -> Void
    let installAction: () -> Void
    let releaseNotesAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            leadingIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            controls
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accentColor.opacity(0.24), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch status {
        case .checking, .downloading, .installing:
            ProgressView()
                .controlSize(.small)
                .frame(width: 18)
        default:
            Image(systemName: symbolName)
                .foregroundStyle(accentColor)
                .frame(width: 18)
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 7) {
            switch status {
            case .available:
                Button(action: installAction) {
                    Label("Install Update", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)

                Button(action: releaseNotesAction) {
                    Label("Notes", systemImage: "doc.text")
                }
                .labelStyle(.iconOnly)
                .help("Open release notes")

                dismissButton
            case .upToDate:
                dismissButton
            case .failed:
                Button(action: checkAction) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                dismissButton
            case .idle, .checking, .downloading, .installing:
                EmptyView()
            }
        }
        .controlSize(.small)
    }

    private var dismissButton: some View {
        Button(action: dismissAction) {
            Label("Dismiss", systemImage: "xmark")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help("Dismiss")
    }

    private var title: String {
        switch status {
        case .idle:
            return ""
        case .checking:
            return "Checking for updates..."
        case .upToDate:
            return "Window Arranger is up to date"
        case .available(let update):
            return "\(update.title) is available"
        case .downloading(let update):
            return "Downloading \(update.title)..."
        case .installing:
            return "Installing update..."
        case .failed:
            return "Update check failed"
        }
    }

    private var detail: String? {
        switch status {
        case .idle, .checking:
            return nil
        case .upToDate(let version, _):
            return "Installed version \(version)."
        case .available(let update):
            return update.assetName.map { "Installs automatically from \($0)." } ?? "Installs automatically from the latest GitHub release."
        case .downloading(let update):
            return update.assetName ?? "Downloading from GitHub."
        case .installing:
            return "Window Arranger will relaunch when the update is installed."
        case .failed(let message):
            return message
        }
    }

    private var symbolName: String {
        switch status {
        case .idle, .checking, .downloading, .installing:
            return "arrow.down.circle"
        case .upToDate:
            return "checkmark.circle.fill"
        case .available:
            return "arrow.down.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var accentColor: Color {
        switch status {
        case .available, .downloading, .installing:
            return .blue
        case .upToDate:
            return .green
        case .failed:
            return .orange
        case .idle, .checking:
            return .secondary
        }
    }
}
