# DockAttachedSurface

Reusable Dock-adjacent mini surface and animated expanded-window transition for macOS apps.

## What It Owns

- A borderless mini `NSPanel` positioned just above the Dock.
- Drag clamping so the mini panel and tracked expanded window stay above the Dock.
- Bottom-anchored frame calculation for an expanded `NSWindow`.
- Grow/shrink transition animation between mini and expanded surfaces.
- Snapshot fade policy through `TransitionSnapshotFadePolicy`.
- Snapshot capture strategy through `WindowTransitionSnapshotProviding`.

## What The App Provides

- `DockAttachedSurfaceConfiguration`: title, mini size, margins, transition timing, fade policy, and snapshot provider.
- SwiftUI mini content passed to `showMini(on:content:)`.
- The expanded `NSWindow` that should be positioned, constrained, and transitioned.
- Product-specific actions such as selecting layouts, resizing windows, quitting, or opening settings.

## Minimal Use

```swift
let surface = DockAttachedWindowSurfaceController(
    configuration: DockAttachedSurfaceConfiguration(
        miniTitle: "My App Mini",
        transitionTitle: "My App Transition",
        miniSize: CGSize(width: 420, height: 64)
    )
)

surface.showMini(on: NSScreen.main) {
    MyMiniView()
}

surface.trackExpandedWindow(window)
surface.positionExpandedWindowAboveDock(window)
```

The component does not depend on Mac Window Arranger saved layouts, resize logic, app lists, updates, or issue-reporting code.
