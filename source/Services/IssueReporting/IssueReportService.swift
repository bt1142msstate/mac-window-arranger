import AppKit
import ApplicationServices
import Foundation

struct IssueDiagnostics {
    let appVersion: String
    let buildNumber: String
    let bundleIdentifier: String
    let macOSVersion: String
    let architecture: String
    let accessibilityGranted: Bool
    let screenRecordingGranted: Bool

    var markdown: String {
        """
        Window Arranger Diagnostics
        - App version: \(appVersion)
        - Build: \(buildNumber)
        - Bundle ID: \(bundleIdentifier)
        - macOS: \(macOSVersion)
        - Architecture: \(architecture)
        - Accessibility permission: \(accessibilityGranted ? "Granted" : "Not granted")
        - Screen Recording permission: \(screenRecordingGranted ? "Granted" : "Not granted")
        """
    }
}

enum IssueReportKind {
    case bug
    case feature
    case question

    var templateName: String {
        switch self {
        case .bug:
            return "bug_report.yml"
        case .feature:
            return "feature_request.yml"
        case .question:
            return "question.yml"
        }
    }

    var titlePrefix: String {
        switch self {
        case .bug:
            return "Bug: "
        case .feature:
            return "Feature: "
        case .question:
            return "Question: "
        }
    }
}

final class IssueReportService {
    private enum Constants {
        static let repositoryIssuesURL = "https://github.com/bt1142msstate/mac-window-arranger/issues"
        static let newIssueURL = "https://github.com/bt1142msstate/mac-window-arranger/issues/new"
    }

    private let bundle: Bundle
    private let workspace: NSWorkspace
    private let pasteboard: NSPasteboard

    init(
        bundle: Bundle = .main,
        workspace: NSWorkspace = .shared,
        pasteboard: NSPasteboard = .general
    ) {
        self.bundle = bundle
        self.workspace = workspace
        self.pasteboard = pasteboard
    }

    var diagnostics: IssueDiagnostics {
        IssueDiagnostics(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            bundleIdentifier: bundle.bundleIdentifier ?? "Unknown",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architectureName,
            accessibilityGranted: AXIsProcessTrusted(),
            screenRecordingGranted: CGPreflightScreenCaptureAccess()
        )
    }

    func copyDiagnosticsToPasteboard() {
        pasteboard.clearContents()
        pasteboard.setString(diagnostics.markdown, forType: .string)
    }

    func openReport(kind: IssueReportKind) {
        guard let url = reportURL(for: kind) else {
            openIssuesList()
            return
        }

        workspace.open(url)
    }

    func openIssuesList() {
        guard let url = URL(string: Constants.repositoryIssuesURL) else {
            return
        }

        workspace.open(url)
    }

    private func reportURL(for kind: IssueReportKind) -> URL? {
        guard var components = URLComponents(string: Constants.newIssueURL) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "template", value: kind.templateName),
            URLQueryItem(name: "title", value: kind.titlePrefix)
        ]

        return components.url
    }

    private var architectureName: String {
        #if arch(arm64)
        return "Apple Silicon"
        #elseif arch(x86_64)
        return "Intel"
        #else
        return "Unknown"
        #endif
    }
}
