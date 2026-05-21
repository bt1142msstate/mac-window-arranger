# Mac Window Arranger

Mac Window Arranger is a small macOS SwiftUI utility for resizing and arranging windows from other apps. It can resize the front window or all standard windows for a selected app, arrange selected windows into common layouts, and save layouts that reopen apps and restore their window positions.

<p align="center">
  <img src="docs/assets/mac-window-arranger-preview.png" alt="Mac Window Arranger interface preview" width="900">
</p>

## Features

- Resize the frontmost window or every standard window for a selected app.
- Use presets for common sizes like 1080p, 720p, mobile, tablet, and square.
- Arrange selected windows into two-column, three-column, four-grid, and focus-stack layouts.
- Save custom layouts and reopen the matching apps later.
- Start in Mini Mode, keep the arranger above other windows, and return to a small Dock-adjacent control after successful actions.
- Preserve local Accessibility permission across rebuilds with stable signing metadata.

## Source Layout

The app follows a small native macOS SwiftUI structure:

- `source/App`: app entry point, window delegate, and compact panel controller.
- `source/Views`: SwiftUI screens and reusable view components.
- `source/Stores`: observable UI state and user actions.
- `source/Services`: Accessibility, app launching, window discovery, and resize/arrange logic.
- `source/Models` and `source/Support`: data types and shared helpers.

## Requirements

- macOS 14 or newer
- Xcode command line tools
- Accessibility permission for Window Arranger

## App Icon

<p>
  <img src="docs/assets/mac-window-arranger-icon.png" alt="Mac Window Arranger app icon" width="160">
</p>

## Build and Run

```sh
./script/build_and_run.sh
```

The build script compiles the Swift sources, generates the app icon, signs the app with a local signing identity, installs it at `/Applications/Window Arranger.app`, and opens it.

Use `--verify` to build, install, launch, and confirm the app starts:

```sh
./script/build_and_run.sh --verify
```

## Signing

The script keeps the bundle identifier, install path, and local signing requirement stable so macOS Accessibility permission survives local rebuilds. The local signing keychain is stored under `~/Library/Application Support/Window Arranger/CodeSigning` instead of this repository.

For distribution details, see [docs/STORE_SUBMISSION.md](docs/STORE_SUBMISSION.md). The current working release path is Developer ID signing plus notarization; Mac App Store submission is blocked until the App Sandbox limitation around Accessibility window control is resolved.

## Open Source

Mac Window Arranger is open source under the MIT License. See [LICENSE](LICENSE) for details.
