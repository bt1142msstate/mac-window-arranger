import AppKit
import Foundation

@MainActor
private final class AppWindowPickerWindowProvider: WindowPickingWindowProviding, @unchecked Sendable {
    private let service = WindowManagementService()

    func windowUnderMouse() -> WindowPickerItem? {
        service.windowUnderMouse().map(WindowPickerItem.init(windowItem:))
    }

    func appKitFrame(for window: WindowPickerItem) -> CGRect? {
        service.appKitFrame(for: WindowItem(pickerItem: window))
    }

    func foregroundAppKitFrames(overlapping window: WindowPickerItem) -> [CGRect] {
        service.foregroundAppKitFrames(overlapping: WindowItem(pickerItem: window))
    }
}

@MainActor
private final class AppWindowPickerPreviewCaptureService: WindowPickingPreviewCapturing, @unchecked Sendable {
    private let service = WindowPreviewCaptureService()

    func requestScreenCaptureAccessIfNeeded() {
        service.requestScreenCaptureAccessIfNeeded()
    }

    func capturePreview(
        for window: WindowPickerItem,
        displaySize: CGSize,
        completion: @escaping @MainActor @Sendable (NSImage?) -> Void
    ) {
        service.capturePreview(
            for: WindowItem(pickerItem: window),
            displaySize: displaySize,
            completion: completion
        )
    }
}

extension WindowPickerController {
    static func appDefault() -> WindowPickerController {
        WindowPickerController(
            windowProvider: AppWindowPickerWindowProvider(),
            previewCaptureService: AppWindowPickerPreviewCaptureService()
        )
    }
}

extension WindowPickerItem {
    init(windowItem: WindowItem) {
        self.init(
            id: windowItem.id,
            appName: windowItem.appName,
            bundleIdentifier: windowItem.bundleIdentifier,
            processIdentifier: windowItem.processIdentifier,
            windowNumber: windowItem.windowNumber,
            windowIndex: windowItem.windowIndex,
            title: windowItem.title,
            frame: windowItem.frame
        )
    }
}

extension WindowItem {
    init(pickerItem: WindowPickerItem) {
        self.init(
            id: pickerItem.id,
            appName: pickerItem.appName,
            bundleIdentifier: pickerItem.bundleIdentifier,
            processIdentifier: pickerItem.processIdentifier,
            windowNumber: pickerItem.windowNumber,
            windowIndex: pickerItem.windowIndex,
            title: pickerItem.title,
            frame: pickerItem.frame
        )
    }
}
