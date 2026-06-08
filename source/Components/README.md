# Reusable Components

This folder contains AppKit/SwiftUI components that are intentionally separated from Mac Window Arranger's product logic. They should not import or reference saved layouts, resize logic, issue reporting, updates, or `AppDelegate`.

## Components

- `WindowPicking`: hover-to-highlight window picking with click-to-select behavior.
- `DockAttachedSurface`: Dock-adjacent mini surface plus grow/shrink transition behavior for an expanded `NSWindow`.

## Integration Pattern

Keep app-specific code outside this folder:

1. Copy the component folder into the target macOS app.
2. Provide small adapter types in that app's own `App` or `Services` layer.
3. Convert between the app's models and the component's neutral models.
4. Keep the SwiftUI content supplied to these components app-owned.

`source/App/WindowPickerAppIntegration.swift` is the current example of that adapter pattern.
