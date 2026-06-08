import AppKit
import QuartzCore

@MainActor
final class DockAttachedWindowTransitionCoordinator {
    private let configuration: DockAttachedSurfaceConfiguration
    private var activePanel: NSPanel?
    private var transitionGeneration = 0

    init(configuration: DockAttachedSurfaceConfiguration) {
        self.configuration = configuration
    }

    func cancelActiveTransition() {
        transitionGeneration += 1
        activePanel?.alphaValue = 0
        activePanel?.orderOut(nil)
        activePanel?.close()
        activePanel = nil
    }

    func transition(
        from sourceWindow: NSWindow?,
        sourceFrame: NSRect,
        to targetFrame: NSRect,
        prepareDestination: (@MainActor @Sendable () -> Void)? = nil,
        revealDestination: @escaping @MainActor @Sendable () -> Void,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        cancelActiveTransition()
        transitionGeneration += 1
        let generation = transitionGeneration

        guard let sourceWindow else {
            runTransition(
                generation: generation,
                snapshot: nil,
                sourceWindow: nil,
                sourceFrame: sourceFrame,
                targetFrame: targetFrame,
                prepareDestination: prepareDestination,
                revealDestination: revealDestination,
                completion: completion
            )
            return
        }

        configuration.snapshotProvider.snapshot(for: sourceWindow) { [weak self, weak sourceWindow] snapshot in
            self?.runTransition(
                generation: generation,
                snapshot: snapshot,
                sourceWindow: sourceWindow,
                sourceFrame: sourceFrame,
                targetFrame: targetFrame,
                prepareDestination: prepareDestination,
                revealDestination: revealDestination,
                completion: completion
            )
        }
    }

    private func runTransition(
        generation: Int,
        snapshot: NSImage?,
        sourceWindow: NSWindow?,
        sourceFrame: NSRect,
        targetFrame: NSRect,
        prepareDestination: (@MainActor @Sendable () -> Void)?,
        revealDestination: @escaping @MainActor @Sendable () -> Void,
        completion: (@MainActor @Sendable () -> Void)?
    ) {
        guard transitionGeneration == generation else {
            return
        }

        let revealFadeDuration = configuration.revealFadeDuration
        let panel = makePanel(frame: sourceFrame, snapshot: snapshot)
        activePanel = panel

        sourceWindow?.alphaValue = 0
        sourceWindow?.orderOut(nil)
        prepareDestination?()

        if shouldFadeSnapshotBeforeResize(from: sourceFrame, to: targetFrame) {
            fadeSnapshot(in: panel)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = configuration.transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            panel.animator().setFrame(targetFrame, display: true)

            if let contentView = panel.contentView as? DockAttachedTransitionSurfaceView {
                contentView.surfaceView.animator().alphaValue = 0.96
            }
        } completionHandler: { [weak self, weak panel] in
            MainActor.assumeIsolated {
                revealDestination()

                guard let panel else {
                    completion?()
                    return
                }

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = revealFadeDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    context.allowsImplicitAnimation = true
                    MainActor.assumeIsolated {
                        panel.animator().alphaValue = 0
                    }
                } completionHandler: { [weak self, weak panel] in
                    MainActor.assumeIsolated {
                        panel?.orderOut(nil)
                        panel?.close()

                        if self?.activePanel === panel {
                            self?.activePanel = nil
                        }

                        completion?()
                    }
                }
            }
        }
    }

    func setFrame(
        of window: NSWindow,
        to targetFrame: NSRect,
        animated: Bool,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        guard animated, window.isVisible else {
            window.setFrame(targetFrame, display: true)
            completion?()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = configuration.transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            MainActor.assumeIsolated {
                window.animator().setFrame(targetFrame, display: true)
            }
        } completionHandler: {
            MainActor.assumeIsolated {
                window.setFrame(targetFrame, display: true)
                completion?()
            }
        }
    }

    private func makePanel(frame: NSRect, snapshot: NSImage?) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = configuration.transitionTitle
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = configuration.windowLevel
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]

        panel.contentView = DockAttachedTransitionSurfaceView(
            frame: NSRect(origin: .zero, size: frame.size),
            snapshot: snapshot
        )
        panel.orderFrontRegardless()
        return panel
    }

    private func shouldFadeSnapshotBeforeResize(from sourceFrame: NSRect, to targetFrame: NSRect) -> Bool {
        switch configuration.snapshotFadePolicy {
        case .fadeBeforeResize:
            return true
        case .keepVisibleWhileShrinking:
            return targetFrame.positiveArea >= sourceFrame.positiveArea
        }
    }

    private func fadeSnapshot(in panel: NSPanel) {
        guard let contentView = panel.contentView as? DockAttachedTransitionSurfaceView else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = configuration.snapshotFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            contentView.imageView.animator().alphaValue = 0
        }
    }
}

@MainActor
final class DockAttachedTransitionSurfaceView: NSView {
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
