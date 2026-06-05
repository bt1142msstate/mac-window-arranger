import SwiftUI

struct UpdateDetailsPopover: View {
    let status: AppUpdateStatus
    let installedVersion: String
    let latestUpdate: AppUpdate?
    let checkAction: () -> Void
    let downloadAction: () -> Void
    let releaseNotesAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(alignment: .leading, spacing: 8) {
                versionRow(title: "Installed", value: installedVersion)
                versionRow(title: "Latest", value: latestVersionText)
            }

            statusBlock

            if let releaseNotesText {
                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    Label("Release Notes", systemImage: "doc.text")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(.init(releaseNotesText))
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                }
            }

            HStack(spacing: 8) {
                Button(action: checkAction) {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                if canDownloadUpdate {
                    Button(action: downloadAction) {
                        Label("Download Update", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if latestUpdate != nil {
                    Button(action: releaseNotesAction) {
                        Label("Open Release", systemImage: "safari")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .help("Open GitHub release")
                }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text("Updates")
                    .font(.headline)

                Text(statusTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .checking, .downloading:
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
        default:
            Image(systemName: statusSymbolName)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 24, height: 24)
        }
    }

    private var statusBlock: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusSymbolName)
                .foregroundStyle(statusColor)
                .frame(width: 16)

            Text(statusDetail)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(statusColor.opacity(0.22), lineWidth: 1)
        )
    }

    private func versionRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private var latestVersionText: String {
        if let latestUpdate {
            return latestUpdate.version
        }

        switch status {
        case .checking:
            return "Checking"
        default:
            return "Unknown"
        }
    }

    private var releaseNotesText: String? {
        guard let notes = latestUpdate?.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else {
            return nil
        }

        return notes
    }

    private var canDownloadUpdate: Bool {
        switch status {
        case .available:
            return true
        default:
            return false
        }
    }

    private var statusTitle: String {
        switch status {
        case .idle:
            return "Ready to check"
        case .checking:
            return "Checking GitHub"
        case .upToDate(let version, let latestUpdate):
            if let latestUpdate, !version.hasPrefix(latestUpdate.version) {
                return "Ahead of release"
            }

            return "Up to date"
        case .available(let update):
            return "Version \(update.version) available"
        case .downloading(let update):
            return "Downloading \(update.version)"
        case .downloaded:
            return "Update opened"
        case .failed:
            return "Check failed"
        }
    }

    private var statusDetail: String {
        switch status {
        case .idle:
            return "No update check has run in this window yet."
        case .checking:
            return "Checking the latest GitHub release..."
        case .upToDate(let version, let latestUpdate):
            if let latestUpdate {
                if !version.hasPrefix(latestUpdate.version) {
                    return "Installed \(version) is newer than the latest GitHub release, \(latestUpdate.version)."
                }

                return "Installed \(version) matches the latest GitHub release, \(latestUpdate.version)."
            }

            return "Installed \(version) is up to date."
        case .available(let update):
            return "A newer GitHub release is available: \(update.title)."
        case .downloading(let update):
            return "Downloading \(update.assetName ?? update.title)..."
        case .downloaded(let update, let url):
            if url == update.releaseURL {
                return "Opened the GitHub release page."
            }

            return "Opened \(url.lastPathComponent)."
        case .failed(let message):
            return message
        }
    }

    private var statusSymbolName: String {
        switch status {
        case .idle, .checking, .downloading:
            return "arrow.triangle.2.circlepath"
        case .upToDate, .downloaded:
            return "checkmark.circle.fill"
        case .available:
            return "arrow.down.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .available, .downloading:
            return .blue
        case .upToDate, .downloaded:
            return .green
        case .failed:
            return .orange
        case .idle, .checking:
            return .secondary
        }
    }
}
