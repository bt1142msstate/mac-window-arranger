import ApplicationServices
import CoreGraphics
import Foundation

struct AppItem: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    let isRunning: Bool
    let hasVisibleWindows: Bool
    let isFocused: Bool

    init(
        id: String,
        name: String,
        bundleIdentifier: String?,
        bundleURL: URL? = nil,
        isRunning: Bool = true,
        hasVisibleWindows: Bool = false,
        isFocused: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.isRunning = isRunning
        self.hasVisibleWindows = hasVisibleWindows
        self.isFocused = isFocused
    }

    var statusLabel: String {
        if isFocused {
            return "Focused"
        }

        if hasVisibleWindows {
            return "Visible"
        }

        return isRunning ? "Running" : "Installed"
    }
}

struct WindowItem: Identifiable, Hashable {
    let id: String
    let appName: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let windowNumber: CGWindowID
    let windowIndex: Int
    let title: String
    let frame: CGRect

    var displayName: String {
        if title.isEmpty {
            return "\(appName) - Window \(windowIndex + 1)"
        }

        return "\(appName) - \(title)"
    }
}
