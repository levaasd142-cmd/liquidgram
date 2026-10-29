#!/usr/bin/env bash
# Builds the unsigned iPhone app, dist-ios/Liquidgram.ipa, from a production web build.
# Needs macOS with Xcode 16 or newer, XcodeGen (`brew install xcodegen`) and Node.js.
#
# Usage: ios/build-ipa.sh [repo-root] [dist-dir]
#   repo-root  defaults to the parent folder of this script
#   dist-dir   defaults to <repo-root>/dist, the output of `npm run build:production`
# BUILD_NUMBER sets CFBundleVersion; it defaults to the number of commits.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${1:-"$SCRIPT_DIR/.."}" && pwd)"
DIST_ARG="${2:-"$ROOT/dist"}"
IOS_DIR="$ROOT/ios"
WEBAPP_DIR="$IOS_DIR/Liquidgram/WebApp"
OUT_DIR="$ROOT/dist-ios"
IPA="$OUT_DIR/Liquidgram.ipa"
APP_NAME="Liquidgram"
BYTES_IN_MEGABYTE=1048576

fail() {
  echo "error: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" > /dev/null || fail "$1 is required. $2"
}

require_tool xcodebuild "Install Xcode 16 or newer."
require_tool xcodegen "Install it with: brew install xcodegen"
require_tool node "Install Node.js, which the web build needs as well."
require_tool zip "It ships with macOS."
[[ -f "$DIST_ARG/index.html" ]] || fail "No web build in $DIST_ARG. Run: npm ci && npm run build:production"
DIST="$(cd "$DIST_ARG" && pwd)"

# CFBundleShortVersionString takes up to three numbers, the form package.json uses
VERSION="$(node -p 'require(process.argv[1]).version' "$ROOT/package.json")"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || fail "package.json version $VERSION is not a valid app version"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2> /dev/null || echo 1)}"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "BUILD_NUMBER must be a whole number, got $BUILD_NUMBER"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/liquidgram-ios.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Copying the web build from $DIST"
# Source maps only add weight, and the PHP helper shipped with the emoji images is never requested
rm -rf "$WEBAPP_DIR"
mkdir -p "$WEBAPP_DIR"
cp -R "$DIST/." "$WEBAPP_DIR/"
find "$WEBAPP_DIR" -type f \( -name '*.map' -o -name '*.php' \) -delete

echo "Generating the Xcode project"
xcodegen generate --spec "$IOS_DIR/project.yml" --project "$IOS_DIR"

echo "Building $APP_NAME $VERSION ($BUILD_NUMBER)"
xcodebuild \
  -project "$IOS_DIR/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$WORK_DIR/DerivedData" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP="$WORK_DIR/DerivedData/Build/Products/Release-iphoneos/$APP_NAME.app"
# A misconfigured project can build an app that lacks the web app or the bridge, so check before packing
for required in Info.plist "$APP_NAME" Assets.car bridge.js WebApp/index.html; do
  [[ -e "$APP/$required" ]] || fail "The app bundle lacks $required"
done

echo "Packing $IPA"
mkdir -p "$WORK_DIR/Payload" "$OUT_DIR"
ditto "$APP" "$WORK_DIR/Payload/$APP_NAME.app"
rm -f "$IPA"
(cd "$WORK_DIR" && zip -qryX "$IPA" Payload)

SIZE_BYTES="$(wc -c < "$IPA" | tr -d ' ')"
SHA256="$(shasum -a 256 "$IPA" | cut -d ' ' -f 1)"
echo "Built $IPA"
echo "Version: $VERSION ($BUILD_NUMBER)"
echo "Size: $(awk -v bytes="$SIZE_BYTES" -v unit="$BYTES_IN_MEGABYTE" 'BEGIN { printf "%.1f MB", bytes / unit }') ($SIZE_BYTES bytes)"
echo "SHA-256: $SHA256"
