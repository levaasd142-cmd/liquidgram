#!/usr/bin/env bash
# Leaves the data of the loopback version of the app on a simulator for TransportTests/testLegacyDataMovesToAppOrigin:
# builds the app at a Git revision that served the web app from http://127.0.0.1:47821, such as the last commit of
# version 1, installs it in place of this build, runs it once with the demo account and Fixtures/legacy-seed.js, then
# quits it. run-ui-tests.sh calls it when UI_TESTS_LEGACY_REF is set, after `build-ipa.sh` filled
# ios/Liquidgram/WebApp, whose web build the old app gets as well.
#
# Usage: seed-legacy-app.sh <git revision> <simulator UDID> <work dir>
set -euo pipefail

REVISION="$1"
UDID="$2"
WORK_DIR="$3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FIXTURES_DIR="$ROOT/ios/LiquidgramUITests/Fixtures"
WEBAPP_DIR="$ROOT/ios/Liquidgram/WebApp"
BUNDLE_ID="org.liquidgram.messenger"
SETTINGS_BUNDLE_ID="com.apple.Preferences"
SOURCE_DIR="$WORK_DIR/legacy-source"
DERIVED_DIR="$WORK_DIR/legacy-build"
BUILD_LOG="$WORK_DIR/legacy-build.log"
SEED_FIXTURES=(page-errors offline-api demo-account legacy-seed)
# The web app caches the demo account in IndexedDB within seconds, and at once when it goes to the background
RUN_SECONDS=20
BACKGROUND_SECONDS=5

echo "Building the loopback version at $REVISION"
# CI checks out a single commit
if ! git -C "$ROOT" cat-file -e "$REVISION^{commit}" 2> /dev/null; then
  git -C "$ROOT" fetch --quiet --depth 1 origin "$REVISION"
  REVISION="FETCH_HEAD"
fi
rm -rf "$SOURCE_DIR" "$DERIVED_DIR"
mkdir -p "$SOURCE_DIR"
git -C "$ROOT" archive "$REVISION" ios | tar -x -C "$SOURCE_DIR"
cp -R "$WEBAPP_DIR" "$SOURCE_DIR/ios/Liquidgram/WebApp"
xcodegen generate --spec "$SOURCE_DIR/ios/project.yml" --project "$SOURCE_DIR/ios" > /dev/null
if ! xcodebuild build \
  -project "$SOURCE_DIR/ios/Liquidgram.xcodeproj" \
  -scheme Liquidgram \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  > "$BUILD_LOG" 2>&1; then
  tail -n 40 "$BUILD_LOG" >&2
  echo "error: the loopback version did not build" >&2
  exit 1
fi

echo "Running the loopback version with the demo account"
# A clean data container, so only the old version's data is there
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true
xcrun simctl install "$UDID" "$DERIVED_DIR/Build/Products/Debug-iphonesimulator/Liquidgram.app"
user_script=""
for fixture in "${SEED_FIXTURES[@]}"; do
  user_script+="$(cat "$FIXTURES_DIR/$fixture.js")"$'\n;\n'
done
# `simctl launch` passes SIMCTL_CHILD_-prefixed variables to the app without the prefix
SIMCTL_CHILD_LIQUIDGRAM_TEST_USER_SCRIPT="$(printf '%s' "$user_script" | base64 | tr -d '\n')" \
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -AppleLanguages "(en)" -AppleLocale en_US
sleep "$RUN_SECONDS"
xcrun simctl launch "$UDID" "$SETTINGS_BUNDLE_ID" > /dev/null 2>&1 || true
sleep "$BACKGROUND_SECONDS"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true
xcrun simctl terminate "$UDID" "$SETTINGS_BUNDLE_ID" > /dev/null 2>&1 || true
echo "The loopback version left its data"
