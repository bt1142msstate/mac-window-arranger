import AppKit
import QuartzCore

final class WindowTransitionCoordinator {
    private let duration: TimeInterval = 0.26
    private let snapshotFadeDuration: TimeInterval = 0.08
    private let revealFadeDuration: TimeInterval = 0.08
    private var activePanel: NSPanel?

    func cancelActiveTransition() {
        activePanel?.alphaValue = 0
        activePanel?.orderOut(nil)
        activePanel?.close()
        activePanel = nil
    }

    func transition(
        from sourceWindow: NSWindow?,
        sourceFrame: NSRect,
        to targetFrame: NSRect,
        prepareDestination: (() -> Void)? = nil,
        revealDestination: @escaping () -> Void,
        completion: (() -> Void)? = nil
    ) {
        activePanel?.alphaValue = 0
        activePanel?.orderOut(nil)
        activePanel?.close()
        activePanel = nil

        let panel = makePanel(
            frame: sourceFrame,
            snapshot: sourceWindow.flatMap(snapshotImage)
        )
        activePanel = panel

        sourceWindow?.alphaValue = 0
        sourceWindow?.orderOut(nil)
        prepareDestination?()

        if let contentView = panel.contentView as? WindowTransitionSurfaceView {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = snapshotFadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                contentView.imageView.animator().alphaValue = 0
            }
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            panel.animator().setFrame(targetFrame, display: true)

            if let contentView = panel.contentView as? WindowTransitionSurfaceView {
                contentView.surfaceView.animator().alphaValue = 0.96
            }
        } completionHandler: { [weak self, weak panel] in
            revealDestination()

            guard let panel else {
                completion?()
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = self?.revealFadeDuration ?? 0.08
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self, weak panel] in
                panel?.orderOut(nil)
                panel?.close()

                if self?.activePanel === panel {
                    self?.activePanel = nil
                }

                completion?()
            }
        }
    }

    func setFrame(
        of window: NSWindow,
        to targetFrame: NSRect,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        guard animated, window.isVisible else {
            window.setFrame(targetFrame, display: true)
            completion?()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            window.setFrame(targetFrame, display: true)
            completion?()
        }
    }

    private func makePanel(frame: NSRect, snapshot: NSImage?) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Window Arranger Transition"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]

        panel.contentView = WindowTransitionSurfaceView(frame: NSRect(origin: .zero, size: frame.size), snapshot: snapshot)
        panel.orderFrontRegardless()
        return panel
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

final class WindowTransitionSurfaceView: NSView {
    let surfaceView: NSView
    let imageView: NSImageView

    init(frame frameRect: NSRect, snapshot: NSImage?) {
        surfaceView = NSView(frame: NSRect(origin: .zero, size: frameRect.size))
        imageView = NSImageView(frame: NSRect(origin: .zero, size: frameRect.size))

        super.init(frame: frameRect)

        wantsLayer = true
        layer?.masksToBounds = false

        surfaceView.wantsLayer = true
        surfaceView.autoresizingMask = [.width, .height]
        surfaceView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        surfaceView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        surfaceView.layer?.borderWidth = 1
        surfaceView.layer?.cornerRadius = 10
        surfaceView.layer?.masksToBounds = true
        surfaceView.alphaValue = 0.86
        addSubview(surfaceView)

        imageView.image = snapshot
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        imageView.alphaValue = snapshot == nil ? 0 : 1
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
