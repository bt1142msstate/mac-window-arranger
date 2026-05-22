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

        Task.detached(priority: .userInitiated) {
            let image = await Self.capturePreview(
                windowNumber: windowNumber,
                displaySize: displaySize
            )

            await MainActor.run {
                completion(image)
            }
        }
    }

    private static func capturePreview(windowNumber: CGWindowID, displaySize: CGSize) async -> NSImage? {
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
            configuration.backgroundColor = NSColor.clear.cgColor

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )

            return NSImage(cgImage: image, size: displaySize)
        } catch {
            return nil
        }
    }
}
