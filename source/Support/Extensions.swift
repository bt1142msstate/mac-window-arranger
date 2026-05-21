import ApplicationServices
import CoreGraphics
import Foundation

extension AXError {
    var readableDescription: String {
        switch self {
        case .success: "Success"
        case .failure: "General Accessibility failure"
        case .illegalArgument: "Illegal Accessibility argument"
        case .invalidUIElement: "The window is no longer available"
        case .invalidUIElementObserver: "Invalid Accessibility observer"
        case .cannotComplete: "The app could not complete the request"
        case .attributeUnsupported: "The window does not support that resize attribute"
        case .actionUnsupported: "The window does not support that action"
        case .notificationUnsupported: "Notification unsupported"
        case .notImplemented: "Not implemented"
        case .notificationAlreadyRegistered: "Notification already registered"
        case .notificationNotRegistered: "Notification not registered"
        case .apiDisabled: "Accessibility API disabled"
        case .noValue: "No Accessibility value"
        case .parameterizedAttributeUnsupported: "Parameterized attribute unsupported"
        case .notEnoughPrecision: "Not enough precision"
        @unknown default: "Unknown Accessibility error"
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension CGRect {
    func roundedForWindowManagement() -> CGRect {
        CGRect(
            x: round(minX),
            y: round(minY),
            width: round(width),
            height: round(height)
        )
    }
}
