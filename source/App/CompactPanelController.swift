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
    private var moveObserver: NSObjectProtocol?
    private var isConstrainingFrame = false

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
        layoutTitle: String?,
        layoutOptions: [CompactLayoutOption],
        on preferredScreen: NSScreen?,
        selectLayoutAction: @escaping (String) -> Void,
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
                layoutTitle: layoutTitle,
                layoutOptions: layoutOptions,
                selectLayoutAction: selectLayoutAction,
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

    deinit {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
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
        trackPanelMovement(panel)
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

    private func trackPanelMovement(_ panel: CompactArrangerPanel) {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] notification in
            guard let panel = notification.object as? CompactArrangerPanel else {
                return
            }

            self?.constrainPanelAboveDock(panel)
        }
    }

    private func constrainPanelAboveDock(_ panel: CompactArrangerPanel) {
        guard !isConstrainingFrame else {
            return
        }

        guard let screen = bestScreen(for: panel.frame, fallback: panel.screen) else {
            return
        }

        let margin: CGFloat = 12
        let minimumY = screen.visibleFrame.minY + margin

        guard panel.frame.minY < minimumY else {
            return
        }

        var frame = panel.frame
        frame.origin.y = minimumY

        isConstrainingFrame = true
        panel.setFrame(frame, display: true)
        isConstrainingFrame = false
    }

    private func bestScreen(for frame: NSRect, fallback: NSScreen?) -> NSScreen? {
        let candidates = NSScreen.screens.map { screen in
            (screen: screen, area: screen.frame.intersection(frame).positiveArea)
        }
        let bestMatch = candidates.max { first, second in
            first.area < second.area
        }

        if let bestMatch, bestMatch.area > 0 {
            return bestMatch.screen
        }

        return fallback ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func compactMessage(from message: String) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedMessage.isEmpty else {
            return "Ready to arrange windows."
        }

        return trimmedMessage.components(separatedBy: .newlines).first ?? trimmedMessage
    }
}

private extension NSRect {
    var positiveArea: CGFloat {
        guard width > 0, height > 0 else {
            return 0
        }

        return width * height
    }
}
