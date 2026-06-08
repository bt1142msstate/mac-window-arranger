import AppKit
import ScreenCaptureKit

enum TransitionSnapshotFadePolicy {
    case fadeBeforeResize
    case keepVisibleWhileShrinking
}

@MainActor
protocol WindowTransitionSnapshotProviding: Sendable {
    func snapshot(for window: NSWindow, completion: @escaping @MainActor @Sendable (NSImage?) -> Void)
}

@MainActor
final class AppKitWindowTransitionSnapshotProvider: WindowTransitionSnapshotProviding, @unchecked Sendable {
    func snapshot(for window: NSWindow, completion: @escaping @MainActor @Sendable (NSImage?) -> Void) {
        completion(snapshotImage(for: window))
    }

    private func snapshotImage(for window: NSWindow) -> NSImage? {
        guard
            let contentView = window.contentView,
            let snapshotView = contentView.superview ?? window.contentView,
            let representation = snapshotView.bitmapImageRepForCachingDisplay(in: snapshotView.bounds)
        else {
            return nil
        }

        snapshotView.displayIfNeeded()
        snapshotView.cacheDisplay(in: snapshotView.bounds, to: representation)

        let image = NSImage(size: snapshotView.bounds.size)
        image.addRepresentation(representation)
        return image
    }
}

@MainActor
final class ScreenCaptureKitWindowTransitionSnapshotProvider: WindowTransitionSnapshotProviding, @unchecked Sendable {
    private let fallback: any WindowTransitionSnapshotProviding

    init(fallback: (any WindowTransitionSnapshotProviding)? = nil) {
        self.fallback = fallback ?? AppKitWindowTransitionSnapshotProvider()
    }

    func snapshot(for window: NSWindow, completion: @escaping @MainActor @Sendable (NSImage?) -> Void) {
        let windowNumber = CGWindowID(window.windowNumber)

        guard windowNumber > 0 else {
            fallback.snapshot(for: window, completion: completion)
            return
        }

        Task(priority: .userInitiated) { [fallback] in
            let image = await Self.screenCaptureKitSnapshot(windowNumber: windowNumber)

            await MainActor.run {
                guard let image else {
                    fallback.snapshot(for: window, completion: completion)
                    return
                }

                completion(image)
            }
        }
    }

    private static func screenCaptureKitSnapshot(windowNumber: CGWindowID) async -> NSImage? {
        do {
            let content = try await SCShareableContent.current

            guard let scWindow = content.windows.first(where: { $0.windowID == windowNumber }) else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let scale = max(CGFloat(filter.pointPixelScale), 1)
            let sourceSize = filter.contentRect.size
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int((sourceSize.width * scale).rounded(.up)))
            configuration.height = max(1, Int((sourceSize.height * scale).rounded(.up)))
            configuration.scalesToFit = true
            configuration.preservesAspectRatio = true
            configuration.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )

            return NSImage(cgImage: image, size: sourceSize)
        } catch {
            return nil
        }
    }
}
