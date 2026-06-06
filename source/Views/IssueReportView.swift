import SwiftUI

struct IssueReportView: View {
    let diagnostics: IssueDiagnostics
    let reportBugAction: () -> Void
    let requestFeatureAction: () -> Void
    let askQuestionAction: () -> Void
    let openIssuesAction: () -> Void
    let copyDiagnosticsAction: () -> Void

    @State private var copiedDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                AppIconView(size: 38, cornerRadius: 8, shadow: false)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Report an Issue")
                        .font(.title3.weight(.semibold))

                    Text("Open a GitHub issue and include safe diagnostics when useful.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("Choose the issue type, then paste the diagnostics below into GitHub if they help explain the problem. Diagnostics do not include window titles, saved layouts, or app names.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: reportBugAction) {
                    Label("Report Bug", systemImage: "exclamationmark.bubble")
                }
                .buttonStyle(.borderedProminent)

                Button(action: requestFeatureAction) {
                    Label("Request Feature", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)

                Button(action: askQuestionAction) {
                    Label("Ask Question", systemImage: "questionmark.circle")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.regular)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Safe Diagnostics", systemImage: "stethoscope")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        copyDiagnosticsAction()
                        copiedDiagnostics = true
                    } label: {
                        Label(copiedDiagnostics ? "Copied" : "Copy", systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc")
                    }
                    .controlSize(.small)
                }

                ScrollView {
                    Text(diagnostics.markdown)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 150)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
            }

            HStack {
                Spacer()

                Button(action: openIssuesAction) {
                    Label("View Existing Issues", systemImage: "tray.full")
                }
                .controlSize(.small)
            }
        }
        .padding(22)
        .frame(width: 620)
        .background(WindowBackground())
    }
}
