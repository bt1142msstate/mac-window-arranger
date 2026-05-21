# Mac Window Arranger

Mac Window Arranger is a small native macOS SwiftUI utility for resizing and arranging windows from other apps. It starts as a compact Dock-adjacent Mini Mode control, expands into the full arranger when needed, and returns to Mini Mode after successful window actions.

<p align="center">
  <img src="docs/assets/mac-window-arranger-mini.png" alt="Mac Window Arranger Mini Mode screenshot" width="520">
</p>

<p align="center">
  <img src="docs/assets/mac-window-arranger-resize.png" alt="Mac Window Arranger Resize mode screenshot" width="520">
</p>

<p align="center">
  <img src="docs/assets/mac-window-arranger-preview.png" alt="Mac Window Arranger Arrange mode screenshot" width="520">
</p>

## Features

- Resize the frontmost window or every standard window for a selected app.
- Pick the resize target from a menu, or use Pick Window to outline a hovered window and resize it on click.
- Use presets for common sizes like 1080p, 720p, mobile, tablet, and square.
- Arrange selected windows into two-column, three-column, four-grid, and focus-stack layouts.
- Save custom layouts and reopen the matching apps later with Open & Arrange.
- Keep Resize and Arrange modes separate so each workflow stays compact.
- Restore minimized saved-layout windows before arranging them.
- Start in Mini Mode, switch saved layouts from the compact control, and return to a small Dock-adjacent control after successful actions.
- Preserve local Accessibility permission across rebuilds with stable signing metadata.

## Current Status

- Built as a local signed, hardened-runtime universal macOS app (`arm64` and `x86_64`).
- Installed by the build script at `/Applications/Window Arranger.app`.
- Privacy manifest is bundled at `Contents/Resources/PrivacyInfo.xcprivacy`.
- Planned public release: low-cost paid Mac App Store version, likely around $2 to $4, to support continued development.
- Current App Store blocker: App Sandbox is intentionally disabled because sandboxed builds cannot access other apps' windows through Accessibility. Developer ID signing plus notarization is the fallback path while that blocker is unresolved.

See [docs/STORE_SUBMISSION.md](docs/STORE_SUBMISSION.md) for distribution details and remaining release work.

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

On first use, grant Accessibility permission in System Settings so the app can read, move, unminimize, and resize windows owned by other apps.

## App Icon

<p>
  <img src="docs/assets/mac-window-arranger-icon.png" alt="Mac Window Arranger app icon" width="160">
</p>

## Build and Run

```sh
./script/build_and_run.sh
```

The build script compiles the Swift sources, generates the app icon, signs the app with a stable local signing identity, installs it at `/Applications/Window Arranger.app`, and opens it in Mini Mode.

Use `--verify` to build, install, launch, and confirm the app starts:

```sh
./script/build_and_run.sh --verify
```

Useful modes:

- `./script/build_and_run.sh --install`: build, install, and launch the app.
- `./script/build_and_run.sh --dmg`: build a signed drag-to-Applications DMG at `dist/Window Arranger.dmg`.
- `./script/build_and_run.sh --logs`: launch and stream process logs.
- `./script/build_and_run.sh --telemetry`: launch and stream app-subsystem logs.

## DMG Installer

```sh
./script/build_and_run.sh --dmg
```

This creates `dist/Window Arranger.dmg`, a read-only compressed disk image with `Window Arranger.app` and an `Applications` shortcut so users can drag the app into `/Applications`.

Local DMGs are signed with the stable local signing identity so they validate on this Mac. Public direct-download releases should be rebuilt with a Developer ID Application certificate and notarized before distribution.

## Privacy

Mac Window Arranger does not collect analytics, tracking data, or network data. It reads the local list of running apps and window titles so you can select windows to arrange. Saved layouts stay on this Mac in app preferences. See [docs/PRIVACY.md](docs/PRIVACY.md).

## Signing

The script keeps the bundle identifier, install path, and local signing requirement stable so macOS Accessibility permission survives local rebuilds. The local signing keychain is stored under `~/Library/Application Support/Window Arranger/CodeSigning` instead of this repository.

For public distribution, replace the local signing identity with an Apple Developer ID Application certificate and notarize the app.

## Source Availability

Mac Window Arranger is source-available, not MIT/open-source. You can inspect the code, build it for personal or internal non-commercial use, and modify it for your own needs.

The Mac App Store version is planned as the easiest supported install path, likely priced around $2 to $4. Redistribution, resale, paid use, publishing modified builds, app-store submission, and use of the app name/icon as your own product require prior written permission. See [LICENSE](LICENSE) for details.
