#!/usr/bin/env bash
set -euo pipefail

# macOS stores Accessibility/TCC grants against the app's code identity, not
# just the visible app name. Keep these stable across every update:
# - bundle id: com.custom.WindowResizer
# - installed path: /Applications/Window Resizer.app
# - signing certificate/designated requirement
#
# For a public release, replace the local signing identity below with an Apple
# Developer ID Application certificate and notarize the app. For local builds,
# this script creates and reuses one local certificate, verifies the designated
# requirement before install, and refuses to update if that identity changes.
# The source project can live in iCloud Drive, but the private local signing
# keychain stays in Application Support so it is not synced by iCloud.

MODE="${1:-run}"
APP_NAME="Window Resizer"
BUNDLE_ID="com.custom.WindowResizer"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
STAGING_DIR="${TMPDIR:-/tmp}/window-resizer-build/staging"
LEGACY_DIST_DIR="$ROOT_DIR/dist"
ICON_DIR="$BUILD_DIR/window-resizer-icon"
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INSTALL_PATH="/Applications/$APP_NAME.app"
INSTALL_BINARY="$INSTALL_PATH/Contents/MacOS/$APP_NAME"
SIGNING_IDENTITY="${WINDOW_RESIZER_SIGNING_IDENTITY:-Window Resizer Local Signing}"
SIGNING_DIR="${WINDOW_RESIZER_SIGNING_DIR:-$HOME/Library/Application Support/Window Resizer/CodeSigning}"
SIGNING_KEYCHAIN="$SIGNING_DIR/window-resizer-signing.keychain-db"
SIGNING_KEYCHAIN_PASSWORD="${WINDOW_RESIZER_SIGNING_KEYCHAIN_PASSWORD:-window-resizer-local-signing}"
SIGNING_P12_PASSWORD="${WINDOW_RESIZER_SIGNING_P12_PASSWORD:-window-resizer-local-signing-p12}"
# This tracked baseline protects Accessibility permission across local updates.
# If the signing cert is lost or changed, the build fails before replacing the
# installed app instead of silently resetting macOS privacy permission.
DESIGNATED_REQUIREMENT_FILE="$ROOT_DIR/script/window-resizer-designated-requirement.txt"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--install]" >&2
  exit 2
}

kill_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

cleanup_duplicate_build_artifacts() {
  rm -rf "$LEGACY_DIST_DIR/$APP_NAME.app" "$BUILD_DIR/staging/$APP_NAME.app" "$STAGING_DIR"
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

  local openssl_config="$SIGNING_DIR/window-resizer-signing.openssl.cnf"
  local private_key="$SIGNING_DIR/window-resizer-signing.key.pem"
  local certificate="$SIGNING_DIR/window-resizer-signing.cert.pem"
  local p12="$SIGNING_DIR/window-resizer-signing.p12"

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
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE" >/dev/null
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
WINDOW_RESIZER_ACCEPT_NEW_REQUIREMENT=1 ./script/build_and_run.sh --install
MESSAGE

  if [[ "${WINDOW_RESIZER_ACCEPT_NEW_REQUIREMENT:-0}" == "1" ]]; then
    printf '%s\n' "$requirement" > "$DESIGNATED_REQUIREMENT_FILE"
    return
  fi

  exit 1
}

build_icon() {
  mkdir -p "$ICON_DIR"
  xcrun swift "$ROOT_DIR/scripts/make-window-resizer-icon.swift" "$ICON_DIR" >/dev/null
  iconutil -c icns "$ICON_DIR/WindowResizerIcon.iconset" -o "$ICON_DIR/WindowResizerIcon.icns"
}

build_bundle() {
  mkdir -p "$BUILD_DIR" "$STAGING_DIR"
  build_icon

  xcrun swiftc -parse-as-library \
    "$ROOT_DIR/source/main.swift" \
    -o "$BUILD_DIR/$APP_NAME" \
    -framework SwiftUI \
    -framework AppKit \
    -framework ApplicationServices

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp -X "$BUILD_DIR/$APP_NAME" "$APP_BINARY"
  cp -X "$ROOT_DIR/source/Info.plist" "$APP_CONTENTS/Info.plist"
  cp -X "$ICON_DIR/WindowResizerIcon.icns" "$APP_RESOURCES/WindowResizerIcon.icns"
  printf "APPL????" > "$APP_CONTENTS/PkgInfo"
  chmod +x "$APP_BINARY"
  sign_bundle
}

open_app() {
  /usr/bin/open "$INSTALL_PATH"
}

install_app() {
  rm -rf "$INSTALL_PATH"
  ditto "$APP_BUNDLE" "$INSTALL_PATH"
  xattr -cr "$INSTALL_PATH"
  rm -rf "$STAGING_DIR"
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

cleanup_duplicate_build_artifacts
build_bundle
verify_designated_requirement_stability
kill_running_app
install_app
verify_installed_app
verify_no_duplicate_app_bundles

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$INSTALL_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --install|install)
    open_app
    ;;
  *)
    usage
    ;;
esac
