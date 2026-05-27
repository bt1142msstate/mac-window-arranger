import AppKit

final class WindowPickerCaptureView: NSView {
    weak var controller: WindowPickerController?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .inVisibleRect, .mouseMoved],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseMoved(with event: NSEvent) {
        controller?.updateHoveredWindow()
    }

    override func mouseDragged(with event: NSEvent) {
        controller?.updateHoveredWindow()
    }

    override func mouseDown(with event: NSEvent) {
        controller?.pickHoveredWindow()
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.cancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            controller?.cancel()
        } else {
            super.keyDown(with: event)
        }
    }
}

struct WindowPickerFocusOverlay {
    let focusedFrame: CGRect
}

final class WindowPickerFocusView: NSView {
    var overlay: WindowPickerFocusOverlay? {
        didSet {
            needsDisplay = true
        }
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard
            let overlay,
            let windowFrame = window?.frame,
            let focusedFrame = localFrame(from: overlay.focusedFrame, in: windowFrame)?
                .insetBy(dx: -5, dy: -5)
                .intersection(bounds),
            !focusedFrame.isNull,
            focusedFrame.width > 0,
            focusedFrame.height > 0
        else {
            return
        }

        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(roundedRect: focusedFrame, xRadius: 11, yRadius: 11))
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.34).setFill()
        path.fill()
    }

    private func localFrame(from screenFrame: CGRect, in windowFrame: CGRect) -> CGRect? {
        let localFrame = CGRect(
            x: screenFrame.minX - windowFrame.minX,
            y: screenFrame.minY - windowFrame.minY,
            width: screenFrame.width,
            height: screenFrame.height
        )

        guard localFrame.intersects(bounds) else {
            return nil
        }

        return localFrame
    }
}

final class WindowPickerHighlightView: NSView {
    private let badgeView = NSVisualEffectView()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private var previewImage: NSImage?
    private var foregroundFrames: [CGRect] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 3
        layer?.cornerRadius = 8

        badgeView.material = .hudWindow
        badgeView.blendingMode = .withinWindow
        badgeView.state = .active
        badgeView.wantsLayer = true
        badgeView.layer?.cornerRadius = 14
        badgeView.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        badgeView.layer?.borderWidth = 1
        addSubview(badgeView)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        badgeView.addSubview(iconView)

        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .white
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        badgeView.addSubview(titleField)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(for window: WindowItem, previewImage: NSImage?, foregroundFrames: [CGRect]) {
        self.previewImage = previewImage
        self.foregroundFrames = foregroundFrames
        iconView.image = appIcon(
            bundleIdentifier: window.bundleIdentifier,
            appName: window.appName
        )
        titleField.stringValue = window.appName
        needsDisplay = true
        needsLayout = true
    }

    func updatePreviewImage(_ image: NSImage?) {
        previewImage = image
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard
            !foregroundFrames.isEmpty,
            let windowFrame = window?.frame
        else {
            return
        }

        let imageRect = bounds.insetBy(dx: 4, dy: 4)

        for foregroundFrame in foregroundFrames {
            guard
                let localForegroundFrame = localFrame(from: foregroundFrame, in: windowFrame)?
                    .intersection(imageRect),
                !localForegroundFrame.isNull,
                localForegroundFrame.width > 0,
                localForegroundFrame.height > 0
            else {
                continue
            }

            NSGraphicsContext.saveGraphicsState()
            let clipPath = NSBezierPath(roundedRect: localForegroundFrame, xRadius: 7, yRadius: 7)
            clipPath.addClip()

            if let previewImage {
                previewImage.draw(
                    in: imageRect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 0.76,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
            }

            NSColor.white.withAlphaComponent(previewImage == nil ? 0.42 : 0.16).setFill()
            clipPath.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.22).setStroke()
            clipPath.lineWidth = 1
            clipPath.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override func layout() {
        super.layout()

        let badgeHeight: CGFloat = 28
        let horizontalPadding: CGFloat = 10
        let iconSize: CGFloat = 18
        let spacing: CGFloat = 7
        let preferredTextWidth = ceil(titleField.intrinsicContentSize.width)
        let maximumBadgeWidth = max(min(bounds.width - 24, 260), 78)
        let badgeWidth = min(
            max(horizontalPadding * 2 + iconSize + spacing + preferredTextWidth, 92),
            maximumBadgeWidth
        )
        let badgeX = (bounds.width - badgeWidth) / 2
        let badgeY = max(bounds.height - badgeHeight - 10, 8)

        badgeView.frame = CGRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)
        iconView.frame = CGRect(
            x: horizontalPadding,
            y: (badgeHeight - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        titleField.frame = CGRect(
            x: horizontalPadding + iconSize + spacing,
            y: 4,
            width: max(badgeWidth - horizontalPadding * 2 - iconSize - spacing, 10),
            height: badgeHeight - 8
        )
    }

    private func localFrame(from screenFrame: CGRect, in windowFrame: CGRect) -> CGRect? {
        let localFrame = CGRect(
            x: screenFrame.minX - windowFrame.minX,
            y: screenFrame.minY - windowFrame.minY,
            width: screenFrame.width,
            height: screenFrame.height
        )

        guard localFrame.intersects(bounds) else {
            return nil
        }

        return localFrame
    }

    private func appIcon(bundleIdentifier: String?, appName: String?) -> NSImage {
        if
            let bundleIdentifier,
            !bundleIdentifier.isEmpty,
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        if
            let appName,
            let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }),
            let bundleURL = runningApp.bundleURL
        {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
