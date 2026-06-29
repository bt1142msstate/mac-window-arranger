#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/source/Info.plist"
TAG_NAME="${1:-${GITHUB_REF_NAME:-}}"
BUILD_NUMBER="${2:-}"

if [[ -z "$TAG_NAME" ]]; then
  echo "usage: $0 <release-tag> [build-number]" >&2
  exit 2
fi

VERSION="${TAG_NAME#v}"

if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+){1,2}$ ]]; then
  echo "Release tag \"$TAG_NAME\" must look like v1.12 or v1.12.0." >&2
  exit 1
fi

if [[ -z "$BUILD_NUMBER" ]]; then
  IFS=. read -r major minor patch_extra <<< "$VERSION"
  patch="${patch_extra:-0}"
  BUILD_NUMBER="$((major * 10000 + minor * 100 + patch))"
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
  echo "Build number \"$BUILD_NUMBER\" must contain only digits and periods." >&2
  exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"

printf 'Prepared Window Arranger %s build %s from %s\n' "$VERSION" "$BUILD_NUMBER" "$TAG_NAME"
