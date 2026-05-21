# Distribution Readiness

This project is intended to launch as a low-cost paid Mac App Store app, likely
around $2 to $4, while keeping the source available for users who want
to build or customize it themselves. The current build is close to a signed,
notarized direct-distribution shape, but Mac App Store submission is blocked by
App Sandbox: sandboxed builds cannot see or arrange other apps' windows through
Accessibility on this Mac, which breaks the app's core feature.

## Implemented In The App

- Hardened runtime signing in the local build script.
- Privacy manifest at `Contents/Resources/PrivacyInfo.xcprivacy`.
- `UserDefaults` required-reason API declaration using reason `CA92.1`.
- In-app Privacy Policy window from the Help menu.
- Local privacy policy draft at `docs/PRIVACY.md`.
- App category, copyright, export-compliance, Accessibility usage, and icon
  metadata in `Info.plist`.
- Universal macOS build by default: `arm64` and `x86_64`.
- AppleScript/System Events dependency removed from the app source.
- App Sandbox intentionally disabled so Accessibility window discovery and
  resizing work.

## Mac App Store Blocker

Apple requires App Sandbox for Mac App Store distribution. Window Arranger needs
Accessibility APIs to inspect, unminimize, move, and resize windows owned by
other apps. Local testing showed:

- Unsandboxed hardened-runtime build: `Work Layout` opens and arranges
  minimized browser, notes, and editor windows successfully.
- Sandboxed build: the app reports that it cannot find any layout windows.
- Sandboxed build plus a temporary `com.apple.axserver` Mach lookup exception:
  still cannot find the layout windows.

Until Apple provides or approves a viable sandbox exception for this behavior,
Developer ID signing plus notarization remains the fallback distribution path.

Apple references:

- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
  documents the Mac App Store sandbox requirement.
- [App Sandbox information](https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-sandbox-information)
  documents the extra App Store Connect review information required for
  temporary exception entitlements.

## Remaining Before Public Release

- Register a production bundle identifier in Apple Developer. The current local
  ID is `com.custom.WindowArranger`; replace it with the final reverse-DNS
  identifier before release.
- Sign the archive with Apple distribution credentials and the correct
  provisioning profile. The local certificate intentionally is not accepted by
  Gatekeeper.
- Notarize the Developer ID build.
- Rebuild the DMG with the Developer ID-signed app, sign the DMG, notarize it,
  staple the notarization ticket, and verify Gatekeeper acceptance.
- Provide the Privacy Policy as a public URL. The included `docs/PRIVACY.md` is
  the draft content.
- Fill privacy disclosures: no tracking, no analytics, no network collection;
  disclose on-device window/app title access in release notes or reviewer notes.
- Prepare screenshots, app description, support URL, marketing URL if desired,
  age rating, category, and low-cost paid pricing.

## Local Validation

Run:

```sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --dmg
codesign -dvvv --entitlements :- "/Applications/Window Arranger.app"
codesign --verify --deep --strict --verbose=2 "/Applications/Window Arranger.app"
codesign --verify --verbose=2 "dist/Window Arranger.dmg"
hdiutil verify "dist/Window Arranger.dmg"
plutil -p "/Applications/Window Arranger.app/Contents/Resources/PrivacyInfo.xcprivacy"
lipo -archs "/Applications/Window Arranger.app/Contents/MacOS/Window Arranger"
```

Expected local result:

- Code signature verifies on disk.
- `dist/Window Arranger.dmg` exists and contains `Window Arranger.app` plus an
  `Applications` shortcut for drag-to-install.
- Entitlements do not include App Sandbox.
- CodeDirectory flags include hardened runtime.
- Privacy manifest is bundled.
- Binary includes `arm64 x86_64`.
- `spctl` rejects the local build until Apple distribution signing and
  notarization are used.
