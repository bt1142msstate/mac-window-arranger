import AppKit
import SwiftUI

@MainActor
final class DockAttachedMiniPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class DockAttachedMiniPanelController {
    private let configuration: DockAttachedSurfaceConfiguration
    private var panel: DockAttachedMiniPanel?
    nonisolated(unsafe) private var moveObserver: NSObjectProtocol?
    private var isConstrainingFrame = false

    init(configuration: DockAttachedSurfaceConfiguration) {
        self.configuration = configuration
    }

    var currentFrame: NSRect? {
        panel?.frame
    }

    var currentWindow: NSWindow? {
        panel
    }

    func owns(_ window: NSWindow) -> Bool {
        panel === window
    }

    func show<Content: View>(
        on preferredScreen: NSScreen?,
        @ViewBuilder content: () -> Content
    ) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.alphaValue = 1
        panel.contentView = NSHostingView(
            rootView: content()
                .frame(width: configuration.miniSize.width, height: configuration.miniSize.height)
        )
        panel.setContentSize(configuration.miniSize)
        panel.setFrame(frame(on: preferredScreen), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func frame(on preferredScreen: NSScreen?) -> NSRect {
        guard let screen = preferredScreen ?? panel?.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(origin: .zero, size: configuration.miniSize)
        }

        let visibleFrame = screen.visibleFrame
        let x = min(
            max(
                visibleFrame.minX + configuration.horizontalInset,
                visibleFrame.midX - (configuration.miniSize.width / 2)
            ),
            visibleFrame.maxX - configuration.miniSize.width - configuration.horizontalInset
        )
        let y = visibleFrame.minY + configuration.dockMargin

        return NSRect(origin: CGPoint(x: x, y: y), size: configuration.miniSize)
    }

    deinit {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
    }

    private func makePanel() -> DockAttachedMiniPanel {
        let panel = DockAttachedMiniPanel(
            contentRect: NSRect(origin: .zero, size: configuration.miniSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = configuration.miniTitle
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = configuration.windowLevel
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        trackPanelMovement(panel)
        return panel
    }

    private func trackPanelMovement(_ panel: DockAttachedMiniPanel) {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] notification in
            guard let panel = notification.object as? DockAttachedMiniPanel else {
                return
            }

            MainActor.assumeIsolated {
                self?.constrainPanelAboveDock(panel)
            }
        }
    }

    private func constrainPanelAboveDock(_ panel: DockAttachedMiniPanel) {
        guard !isConstrainingFrame else {
            return
        }

        guard let screen = NSScreen.bestScreen(for: panel.frame, fallback: panel.screen) else {
            return
        }

        let minimumY = screen.visibleFrame.minY + configuration.dockMargin

        guard panel.frame.minY < minimumY else {
            return
        }

        var frame = panel.frame
        frame.origin.y = minimumY

        isConstrainingFrame = true
        panel.setFrame(frame, display: true)
        isConstrainingFrame = false
    }
}
