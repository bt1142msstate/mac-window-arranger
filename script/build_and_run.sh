#!/usr/bin/env bash
set -euo pipefail

# macOS stores Accessibility/TCC grants against the app's code identity, not
# just the visible app name. Keep these stable across every update:
# - bundle id: com.custom.WindowArranger
# - installed path: /Applications/Window Arranger.app
# - signing certificate/designated requirement
#
# For a public release, replace the local signing identity below with an Apple
# Developer ID Application certificate and notarize the app. For local builds,
# this script creates and reuses one local certificate, verifies the designated
# requirement before install, and refuses to update if that identity changes.
# The source project can live in iCloud Drive, but the private local signing
# keychain stays in Application Support so it is not synced by iCloud.

MODE="${1:-run}"
APP_NAME="Window Arranger"
BUNDLE_ID="com.custom.WindowArranger"
LEGACY_APP_NAME="Window Resizer"
LEGACY_BUNDLE_ID="com.custom.WindowResizer"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
STAGING_DIR="${TMPDIR:-/tmp}/window-arranger-build/staging"
DMG_WORK_DIR="${TMPDIR:-/tmp}/window-arranger-build/dmg"
LEGACY_DIST_DIR="$ROOT_DIR/dist"
DIST_DIR="$ROOT_DIR/dist"
ICON_DIR="$BUILD_DIR/window-arranger-icon"
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
DMG_VOLUME_NAME="$APP_NAME"
ENTITLEMENTS_FILE="$ROOT_DIR/source/WindowArranger.entitlements"
SWIFT_TARGETS="${WINDOW_ARRANGER_SWIFT_TARGETS:-arm64-apple-macos14.0 x86_64-apple-macos14.0}"
INSTALL_PATH="/Applications/$APP_NAME.app"
LEGACY_INSTALL_PATH="/Applications/$LEGACY_APP_NAME.app"
INSTALL_BINARY="$INSTALL_PATH/Contents/MacOS/$APP_NAME"
SIGNING_IDENTITY="${WINDOW_ARRANGER_SIGNING_IDENTITY:-Window Arranger Local Signing}"
SIGNING_DIR="${WINDOW_ARRANGER_SIGNING_DIR:-$HOME/Library/Application Support/Window Arranger/CodeSigning}"
SIGNING_KEYCHAIN="$SIGNING_DIR/window-arranger-signing.keychain-db"
SIGNING_KEYCHAIN_PASSWORD="${WINDOW_ARRANGER_SIGNING_KEYCHAIN_PASSWORD:-window-arranger-local-signing}"
SIGNING_P12_PASSWORD="${WINDOW_ARRANGER_SIGNING_P12_PASSWORD:-window-arranger-local-signing-p12}"
# This tracked baseline protects Accessibility permission across local updates.
# If the signing cert is lost or changed, the build fails before replacing the
# installed app instead of silently resetting macOS privacy permission.
DESIGNATED_REQUIREMENT_FILE="$ROOT_DIR/script/window-arranger-designated-requirement.txt"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--install|--dmg]" >&2
  exit 2
}

kill_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -x "$LEGACY_APP_NAME" >/dev/null 2>&1 || true
}

cleanup_duplicate_build_artifacts() {
  rm -rf \
    "$LEGACY_DIST_DIR/$APP_NAME.app" \
    "$LEGACY_DIST_DIR/$LEGACY_APP_NAME.app" \
    "$BUILD_DIR/staging/$APP_NAME.app" \
    "$BUILD_DIR/staging/$LEGACY_APP_NAME.app" \
    "$STAGING_DIR" \
    "$DMG_WORK_DIR" \
    "${TMPDIR:-/tmp}/window-resizer-build/staging"
}

ensure_local_signing_identity() {
  mkdir -p "$SIGNING_DIR"

  if [[ -f "$SIGNING_KEYCHAIN" ]]; then
    security unlock-keychain -p "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null

    if security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" 2>/dev/null | grep -F "\"$SIGNING_IDENTITY\"" >/dev/null; then
      return
    fi

    security delete-keychain "$SIGNING_KEYCHAIN" >/dev/null 2>&1 || rm -f "$SIGNING_KEYCHAIN"
  fi

  security create-keychain -p "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null
  security set-keychain-settings -lut 21600 "$SIGNING_KEYCHAIN" >/dev/null
  security unlock-keychain -p "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null

  local openssl_config="$SIGNING_DIR/window-arranger-signing.openssl.cnf"
  local private_key="$SIGNING_DIR/window-arranger-signing.key.pem"
  local certificate="$SIGNING_DIR/window-arranger-signing.cert.pem"
  local p12="$SIGNING_DIR/window-arranger-signing.p12"

  cat >"$openssl_config" <<CONFIG
[ req ]
prompt = no
distinguished_name = dn
x509_extensions = extensions

[ dn ]
CN = $SIGNING_IDENTITY

[ extensions ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
CONFIG

  openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
    -keyout "$private_key" \
    -out "$certificate" \
    -config "$openssl_config" >/dev/null 2>&1

  openssl pkcs12 -export \
    -inkey "$private_key" \
    -in "$certificate" \
    -out "$p12" \
    -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES \
    -macalg sha1 \
    -passout "pass:$SIGNING_P12_PASSWORD" >/dev/null 2>&1

  security import "$p12" \
    -k "$SIGNING_KEYCHAIN" \
    -P "$SIGNING_P12_PASSWORD" \
    -T /usr/bin/codesign >/dev/null

  security add-trusted-cert \
    -d \
    -r trustRoot \
    -p codeSign \
    -k "$SIGNING_KEYCHAIN" \
    "$certificate" >/dev/null

  security set-key-partition-list \
    -S apple-tool:,apple: \
    -s \
    -k "$SIGNING_KEYCHAIN_PASSWORD" \
    "$SIGNING_KEYCHAIN" >/dev/null
}

ensure_signing_keychain_in_search_list() {
  local existing_keychains=()
  local keychain

  while IFS= read -r keychain; do
    [[ -n "$keychain" ]] && existing_keychains+=("$keychain")
  done < <(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')

  for keychain in "${existing_keychains[@]}"; do
    if [[ "$keychain" == "$SIGNING_KEYCHAIN" ]]; then
      return
    fi
  done

  security list-keychains -d user -s "$SIGNING_KEYCHAIN" "${existing_keychains[@]}" >/dev/null
}

sign_bundle() {
  ensure_local_signing_identity
  ensure_signing_keychain_in_search_list
  find "$APP_BUNDLE" -name ".DS_Store" -delete
  find "$APP_BUNDLE" -name "._*" -delete
  xattr -cr "$APP_BUNDLE"
  codesign \
    --force \
    --deep \
    --options runtime \
    --entitlements "$ENTITLEMENTS_FILE" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_BUNDLE" >/dev/null
}

designated_requirement() {
  codesign -d --requirements - "$1" 2>&1 | sed -n 's/^designated => //p'
}

verify_designated_requirement_stability() {
  local requirement
  requirement="$(designated_requirement "$APP_BUNDLE")"

  if [[ -z "$requirement" ]]; then
    echo "Could not read designated requirement for $APP_BUNDLE." >&2
    exit 1
  fi

  mkdir -p "$SIGNING_DIR"

  if [[ ! -f "$DESIGNATED_REQUIREMENT_FILE" ]]; then
    printf '%s\n' "$requirement" > "$DESIGNATED_REQUIREMENT_FILE"
    return
  fi

  local expected
  expected="$(cat "$DESIGNATED_REQUIREMENT_FILE")"

  if [[ "$requirement" == "$expected" ]]; then
    return
  fi

  cat >&2 <<MESSAGE
Refusing to install $APP_NAME because its designated requirement changed.

This would make macOS treat the update as a different app and can reset
Accessibility permission.

Expected:
$expected

Actual:
$requirement

If this is intentional, run once with:
WINDOW_ARRANGER_ACCEPT_NEW_REQUIREMENT=1 ./script/build_and_run.sh --install
MESSAGE

  if [[ "${WINDOW_ARRANGER_ACCEPT_NEW_REQUIREMENT:-0}" == "1" ]]; then
    printf '%s\n' "$requirement" > "$DESIGNATED_REQUIREMENT_FILE"
    return
  fi

  exit 1
}

build_icon() {
  mkdir -p "$ICON_DIR"
  xcrun swift "$ROOT_DIR/scripts/make-window-arranger-icon.swift" "$ICON_DIR" >/dev/null
  iconutil -c icns "$ICON_DIR/WindowArrangerIcon.iconset" -o "$ICON_DIR/WindowArrangerIcon.icns"
}

build_bundle() {
  mkdir -p "$BUILD_DIR" "$STAGING_DIR"
  build_icon

  local swift_sources=()
  local swift_source

  while IFS= read -r swift_source; do
    swift_sources+=("$swift_source")
  done < <(find "$ROOT_DIR/source" -name "*.swift" -print | sort)

  local built_binaries=()
  local swift_target

  for swift_target in $SWIFT_TARGETS; do
    local arch_name="${swift_target%%-*}"
    local target_binary="$BUILD_DIR/$APP_NAME-$arch_name"

    xcrun swiftc -parse-as-library \
      -target "$swift_target" \
      "${swift_sources[@]}" \
      -o "$target_binary" \
      -framework SwiftUI \
      -framework AppKit \
      -framework ScreenCaptureKit \
      -framework ApplicationServices

    built_binaries+=("$target_binary")
  done

  if [[ "${#built_binaries[@]}" -eq 1 ]]; then
    cp -X "${built_binaries[0]}" "$BUILD_DIR/$APP_NAME"
  else
    lipo -create "${built_binaries[@]}" -output "$BUILD_DIR/$APP_NAME"
  fi

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp -X "$BUILD_DIR/$APP_NAME" "$APP_BINARY"
  cp -X "$ROOT_DIR/source/Info.plist" "$APP_CONTENTS/Info.plist"
  cp -X "$ICON_DIR/WindowArrangerIcon.icns" "$APP_RESOURCES/WindowArrangerIcon.icns"
  cp -X "$ROOT_DIR/source/Resources/PrivacyInfo.xcprivacy" "$APP_RESOURCES/PrivacyInfo.xcprivacy"
  printf "APPL????" > "$APP_CONTENTS/PkgInfo"
  chmod +x "$APP_BINARY"
  sign_bundle
}

open_app() {
  /usr/bin/open "$INSTALL_PATH"
}

install_app() {
  cleanup_legacy_install
  rm -rf "$INSTALL_PATH"
  ditto "$APP_BUNDLE" "$INSTALL_PATH"
  xattr -cr "$INSTALL_PATH"
  rm -rf "$STAGING_DIR"
}

cleanup_legacy_install() {
  if [[ ! -d "$LEGACY_INSTALL_PATH" || "$LEGACY_INSTALL_PATH" == "$INSTALL_PATH" ]]; then
    return
  fi

  local legacy_bundle_id
  legacy_bundle_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$LEGACY_INSTALL_PATH/Contents/Info.plist" 2>/dev/null || true)"

  if [[ "$legacy_bundle_id" == "$LEGACY_BUNDLE_ID" || "$legacy_bundle_id" == "$BUNDLE_ID" ]]; then
    rm -rf "$LEGACY_INSTALL_PATH"
  fi
}

verify_installed_app() {
  codesign --verify --deep --strict "$INSTALL_PATH"

  local requirement
  requirement="$(designated_requirement "$INSTALL_PATH")"

  if [[ "$requirement" != "$(cat "$DESIGNATED_REQUIREMENT_FILE")" ]]; then
    echo "Installed app does not match the expected designated requirement." >&2
    exit 1
  fi
}

verify_no_duplicate_app_bundles() {
  local duplicates
  duplicates="$(
    find "$ROOT_DIR" /Applications "$HOME/Applications" -maxdepth 4 -name "$APP_NAME.app" -print 2>/dev/null \
      | grep -Fv "$INSTALL_PATH" || true
  )"

  if [[ -n "$duplicates" ]]; then
    echo "Warning: found another $APP_NAME.app outside $INSTALL_PATH." >&2
    printf '%s\n' "$duplicates" >&2
  fi
}

create_dmg() {
  local dmg_root="$DMG_WORK_DIR/root"
  local mounted_dmg_path="$DMG_WORK_DIR/$APP_NAME.dmg"

  rm -rf "$DMG_WORK_DIR"
  mkdir -p "$dmg_root" "$DIST_DIR"

  ditto "$APP_BUNDLE" "$dmg_root/$APP_NAME.app"
  ln -s /Applications "$dmg_root/Applications"
  xattr -cr "$dmg_root"

  rm -f "$DMG_PATH" "$mounted_dmg_path"
  hdiutil create \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$dmg_root" \
    -format UDZO \
    -ov \
    "$mounted_dmg_path" >/dev/null

  codesign --force --sign "$SIGNING_IDENTITY" "$mounted_dmg_path" >/dev/null
  ditto "$mounted_dmg_path" "$DMG_PATH"
  xattr -cr "$DMG_PATH"
  rm -rf "$DMG_WORK_DIR"
}

verify_dmg() {
  local mount_point="$DMG_WORK_DIR/mount"

  mkdir -p "$mount_point"
  hdiutil verify "$DMG_PATH" >/dev/null
  codesign --verify --verbose=2 "$DMG_PATH" >/dev/null
  hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$mount_point" >/dev/null

  local detach_needed=1
  cleanup_mount() {
    if [[ "$detach_needed" == "1" ]]; then
      hdiutil detach "$mount_point" -quiet >/dev/null 2>&1 || true
    fi
    rm -rf "$DMG_WORK_DIR"
  }
  trap cleanup_mount RETURN

  test -d "$mount_point/$APP_NAME.app"
  test -L "$mount_point/Applications"
  codesign --verify --deep --strict "$mount_point/$APP_NAME.app"
  lipo -archs "$mount_point/$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null

  hdiutil detach "$mount_point" -quiet >/dev/null
  detach_needed=0
  rm -rf "$DMG_WORK_DIR"
  trap - RETURN
}

install_built_app() {
  kill_running_app
  install_app
  verify_installed_app
  verify_no_duplicate_app_bundles
}

cleanup_duplicate_build_artifacts
build_bundle
verify_designated_requirement_stability

case "$MODE" in
  --dmg|dmg|--package|package)
    create_dmg
    verify_dmg
    printf '%s\n' "$DMG_PATH"
    ;;
  run)
    install_built_app
    open_app
    ;;
  --debug|debug)
    install_built_app
    lldb -- "$INSTALL_BINARY"
    ;;
  --logs|logs)
    install_built_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    install_built_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    install_built_app
    open_app
    for _ in {1..20}; do
      if pgrep -x "$APP_NAME" >/dev/null; then
        exit 0
      fi

      sleep 0.25
    done

    echo "$APP_NAME did not start within 5 seconds." >&2
    exit 1
    ;;
  --install|install)
    install_built_app
    open_app
    ;;
  *)
    usage
    ;;
esac
