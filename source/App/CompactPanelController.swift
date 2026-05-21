import AppKit
import SwiftUI

final class CompactArrangerPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

final class CompactPanelController {
    private let panelSize = CGSize(width: 430, height: 68)
    private var panel: CompactArrangerPanel?

    var currentFrame: NSRect? {
        panel?.frame
    }

    var currentWindow: NSWindow? {
        panel
    }

    func owns(_ window: NSWindow) -> Bool {
        panel === window
    }

    func show(
        message: String,
        kind: ResizeStatusKind,
        on preferredScreen: NSScreen?,
        expandAction: @escaping () -> Void,
        quitAction: @escaping () -> Void
    ) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.alphaValue = 1

        panel.contentView = NSHostingView(
            rootView: CompactArrangerPanelView(
                message: compactMessage(from: message),
                kind: kind,
                expandAction: expandAction,
                quitAction: quitAction
            )
            .frame(width: panelSize.width, height: panelSize.height)
        )
        panel.setContentSize(panelSize)
        panel.setFrame(frame(on: preferredScreen), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> CompactArrangerPanel {
        let panel = CompactArrangerPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Window Arranger Mini"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        return panel
    }

    func frame(on preferredScreen: NSScreen?) -> NSRect {
        guard let screen = preferredScreen ?? panel?.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(origin: .zero, size: panelSize)
        }

        let visibleFrame = screen.visibleFrame
        let horizontalInset: CGFloat = 12
        let x = min(
            max(visibleFrame.minX + horizontalInset, visibleFrame.midX - (panelSize.width / 2)),
            visibleFrame.maxX - panelSize.width - horizontalInset
        )
        let y = visibleFrame.minY + 12

        return NSRect(origin: CGPoint(x: x, y: y), size: panelSize)
    }

    private func compactMessage(from message: String) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedMessage.isEmpty else {
            return "Ready to arrange windows."
        }

        return trimmedMessage.components(separatedBy: .newlines).first ?? trimmedMessage
    }
}
