import AppKit

struct WindowPickerConfiguration {
    var behavior: WindowPickerBehavior
    var style: WindowPickerVisualStyle

    init(
        behavior: WindowPickerBehavior = WindowPickerBehavior(),
        style: WindowPickerVisualStyle = WindowPickerVisualStyle()
    ) {
        self.behavior = behavior
        self.style = style
    }

    static let `default` = WindowPickerConfiguration()
}

struct WindowPickerBehavior {
    var dimsBackground: Bool
    var showsWindowBadge: Bool
    var previewsOccludingWindows: Bool
    var requestsScreenCapturePermission: Bool
    var activatesAppDuringPick: Bool

    init(
        dimsBackground: Bool = true,
        showsWindowBadge: Bool = true,
        previewsOccludingWindows: Bool = true,
        requestsScreenCapturePermission: Bool = true,
        activatesAppDuringPick: Bool = true
    ) {
        self.dimsBackground = dimsBackground
        self.showsWindowBadge = showsWindowBadge
        self.previewsOccludingWindows = previewsOccludingWindows
        self.requestsScreenCapturePermission = requestsScreenCapturePermission
        self.activatesAppDuringPick = activatesAppDuringPick
    }
}

struct WindowPickerVisualStyle {
    var accentColor: NSColor
    var focusDimmingOpacity: CGFloat
    var focusCutoutInset: CGFloat
    var highlightInset: CGFloat
    var highlightFillOpacity: CGFloat
    var highlightBorderWidth: CGFloat
    var highlightCornerRadius: CGFloat
    var badgeMaterial: NSVisualEffectView.Material
    var occludingPreviewOpacity: CGFloat
    var occludingFallbackOpacity: CGFloat

    init(
        accentColor: NSColor = .controlAccentColor,
        focusDimmingOpacity: CGFloat = 0.34,
        focusCutoutInset: CGFloat = 5,
        highlightInset: CGFloat = 4,
        highlightFillOpacity: CGFloat = 0.12,
        highlightBorderWidth: CGFloat = 3,
        highlightCornerRadius: CGFloat = 8,
        badgeMaterial: NSVisualEffectView.Material = .hudWindow,
        occludingPreviewOpacity: CGFloat = 0.76,
        occludingFallbackOpacity: CGFloat = 0.42
    ) {
        self.accentColor = accentColor
        self.focusDimmingOpacity = focusDimmingOpacity
        self.focusCutoutInset = focusCutoutInset
        self.highlightInset = highlightInset
        self.highlightFillOpacity = highlightFillOpacity
        self.highlightBorderWidth = highlightBorderWidth
        self.highlightCornerRadius = highlightCornerRadius
        self.badgeMaterial = badgeMaterial
        self.occludingPreviewOpacity = occludingPreviewOpacity
        self.occludingFallbackOpacity = occludingFallbackOpacity
    }
}

enum WindowPickerResult {
    case selected(WindowPickerItem)
    case cancelled
}

protocol WindowPickingWindowProviding {
    func windowUnderMouse() -> WindowPickerItem?
    func appKitFrame(for window: WindowPickerItem) -> CGRect?
    func foregroundAppKitFrames(overlapping window: WindowPickerItem) -> [CGRect]
}

protocol WindowPickingPreviewCapturing {
    func requestScreenCaptureAccessIfNeeded()

    func capturePreview(
        for window: WindowPickerItem,
        displaySize: CGSize,
        completion: @escaping (NSImage?) -> Void
    )
}
