import AppKit

@MainActor
struct DockAttachedSurfaceConfiguration {
    var miniTitle: String
    var transitionTitle: String
    var miniSize: CGSize
    var dockMargin: CGFloat
    var horizontalInset: CGFloat
    var windowLevel: NSWindow.Level
    var transitionDuration: TimeInterval
    var snapshotFadeDuration: TimeInterval
    var revealFadeDuration: TimeInterval
    var snapshotFadePolicy: TransitionSnapshotFadePolicy
    var snapshotProvider: any WindowTransitionSnapshotProviding

    init(
        miniTitle: String,
        transitionTitle: String,
        miniSize: CGSize,
        dockMargin: CGFloat = 12,
        horizontalInset: CGFloat = 12,
        windowLevel: NSWindow.Level = .floating,
        transitionDuration: TimeInterval = 0.26,
        snapshotFadeDuration: TimeInterval = 0.08,
        revealFadeDuration: TimeInterval = 0.08,
        snapshotFadePolicy: TransitionSnapshotFadePolicy = .keepVisibleWhileShrinking,
        snapshotProvider: (any WindowTransitionSnapshotProviding)? = nil
    ) {
        self.miniTitle = miniTitle
        self.transitionTitle = transitionTitle
        self.miniSize = miniSize
        self.dockMargin = dockMargin
        self.horizontalInset = horizontalInset
        self.windowLevel = windowLevel
        self.transitionDuration = transitionDuration
        self.snapshotFadeDuration = snapshotFadeDuration
        self.revealFadeDuration = revealFadeDuration
        self.snapshotFadePolicy = snapshotFadePolicy
        self.snapshotProvider = snapshotProvider ?? ScreenCaptureKitWindowTransitionSnapshotProvider()
    }
}
