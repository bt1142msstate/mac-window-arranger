import CoreGraphics
import Foundation

struct WindowPickerItem: Identifiable, Hashable {
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
