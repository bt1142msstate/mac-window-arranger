# WindowPicking

Reusable AppKit window picker for macOS apps.

## What It Owns

- Full-screen transparent capture panels.
- Hover tracking and click-to-select behavior.
- Highlight outline, app icon/name badge, and focus dimming.
- Optional foreground-overlap preview through a caller-provided preview capture service.
- Escape/right-click cancellation.

## What The App Provides

- `WindowPickingWindowProviding`: tells the component which window is visually under the cursor, converts that window to AppKit coordinates, and returns overlapping foreground frames.
- `WindowPickingPreviewCapturing`: optionally captures a preview image for the selected window.
- App-specific conversion between the app's window model and `WindowPickerItem`.

## Minimal Use

```swift
let picker = WindowPickerController(
    windowProvider: MyWindowProvider(),
    previewCaptureService: MyPreviewCaptureService()
)

picker.pickWindow { result in
    switch result {
    case .selected(let item):
        handlePickedWindow(item)
    case .cancelled:
        break
    }
}
```

The component does not depend on Mac Window Arranger layout, resize, persistence, or app delegate code.
