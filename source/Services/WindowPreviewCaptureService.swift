import AppKit
import ScreenCaptureKit

final class WindowPreviewCaptureService {
    private static var didRequestScreenCaptureAccess = false

    func requestScreenCaptureAccessIfNeeded() {
        guard !CGPreflightScreenCaptureAccess(), !Self.didRequestScreenCaptureAccess else {
            return
        }

        Self.didRequestScreenCaptureAccess = true
        DispatchQueue.main.async {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    func capturePreview(
        for window: WindowItem,
        displaySize: CGSize,
        completion: @escaping (NSImage?) -> Void
    ) {
        guard window.windowNumber != 0, CGPreflightScreenCaptureAccess() else {
            completion(nil)
            return
        }

        let windowNumber = window.windowNumber

        Task(priority: .userInitiated) {
            let image = await Self.capturePreviewImage(windowNumber: windowNumber)

            await MainActor.run {
                completion(image.map { NSImage(cgImage: $0, size: displaySize) })
            }
        }
    }

    private static func capturePreviewImage(windowNumber: CGWindowID) async -> CGImage? {
        do {
            let content = try await SCShareableContent.current

            guard let window = content.windows.first(where: { $0.windowID == windowNumber }) else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = max(CGFloat(filter.pointPixelScale), 1)
            let sourceSize = filter.contentRect.size
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int((sourceSize.width * scale).rounded(.up)))
            configuration.height = max(1, Int((sourceSize.height * scale).rounded(.up)))
            configuration.scalesToFit = true
            configuration.preservesAspectRatio = true
            configuration.showsCursor = false

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            return nil
        }
    }
}
