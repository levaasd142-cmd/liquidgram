#!/usr/bin/env bash
# Runs the UI tests of ios/LiquidgramUITests on an iPhone simulator and writes a report that is readable without
# Xcode: README.md (summary.md with the screenshots), summary.md (a table of the tests and the self-test checks),
# summary.json, screenshots/, ax/ (accessibility trees the tests attached) and logs/. The demo account test runs a
# second time with the simulator in dark mode. Exits with 1 when a test failed or the tests did not build.
#
# Needs macOS with Xcode 16 or newer and Node.js. Run ios/build-ipa.sh first: it copies the web build into
# ios/Liquidgram/WebApp and generates ios/Liquidgram.xcodeproj, which this script uses.
#
# Usage: ios/run-ui-tests.sh [output-dir]
#   output-dir  defaults to <repo-root>/dist-ios/ui-tests
# Environment:
#   UI_TESTS_ONLY       comma-separated -only-testing filters, such as LiquidgramUITests/CoreTests
#   UI_TESTS_DEVICE     a simulator name to use instead of an iPhone 17 Pro or 16 Pro
#   UI_TESTS_SKIP_DARK  1 skips the second run of the demo account test in dark mode
#   UI_TESTS_WORK_DIR   where the result bundles go, <repo-root>/dist-ios/ui-tests-work by default
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$ROOT/ios"
PROJECT="$IOS_DIR/Liquidgram.xcodeproj"
SCHEME="Liquidgram"
TESTS_DIR="$IOS_DIR/LiquidgramUITests"
REPORT_TOOL="$TESTS_DIR/Tools/report.mjs"
WEBAPP_DIR="$IOS_DIR/Liquidgram/WebApp"
# The `worker` check of the self-test loads this echo worker from the app's origin; only the test build has it
SELFTEST_WORKER="liquidgram-selftest-worker.js"
DARK_MODE_TEST="LiquidgramUITests/CoreTests/testDemoAccount"
APP_LOG_PREDICATE='subsystem == "org.liquidgram.messenger"'
APP_LOG_WINDOW="30m"
# Seconds per test; XCTest rounds them up to whole minutes
DEFAULT_TEST_TIME_ALLOWANCE=180
MAX_TEST_TIME_ALLOWANCE=300

fail() {
  echo "error: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" > /dev/null || fail "$1 is required. $2"
}

require_tool xcodebuild "Install Xcode 16 or newer."
require_tool node "Install Node.js."
[[ -f "$WEBAPP_DIR/index.html" ]] || fail "No web build in $WEBAPP_DIR. Run ios/build-ipa.sh first."
if [[ ! -d "$PROJECT" ]]; then
  require_tool xcodegen "Install it with: brew install xcodegen"
  xcodegen generate --spec "$IOS_DIR/project.yml" --project "$IOS_DIR"
fi

OUT_DIR="${1:-"$ROOT/dist-ios/ui-tests"}"
WORK_DIR="${UI_TESTS_WORK_DIR:-"$ROOT/dist-ios/ui-tests-work"}"
mkdir -p "$OUT_DIR" "$WORK_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"
# Only the entries this script writes, so a wrong output folder loses nothing else
rm -rf "$OUT_DIR/screenshots" "$OUT_DIR/ax" "$OUT_DIR/logs" \
  "$OUT_DIR/README.md" "$OUT_DIR/summary.md" "$OUT_DIR/summary.json"
rm -rf "$WORK_DIR/DerivedData" "$WORK_DIR/light" "$WORK_DIR/dark" "$WORK_DIR/light.xcresult" "$WORK_DIR/dark.xcresult" \
  "$WORK_DIR/light.log" "$WORK_DIR/dark.log" "$WORK_DIR/build-for-testing.log" "$WORK_DIR/app.log" \
  "$WORK_DIR/simulator.txt"

cp "$TESTS_DIR/Fixtures/$SELFTEST_WORKER" "$WEBAPP_DIR/$SELFTEST_WORKER"
trap 'rm -f "$WEBAPP_DIR/$SELFTEST_WORKER"' EXIT

echo "Picking a simulator"
SIMULATOR="$(xcrun simctl list -j devices available | node "$REPORT_TOOL" pick-simulator "${UI_TESTS_DEVICE:-}")"
IFS=$'\t' read -r UDID DEVICE_NAME RUNTIME_NAME <<< "$SIMULATOR"
echo "Using $DEVICE_NAME, $RUNTIME_NAME ($UDID)"
echo "$DEVICE_NAME, $RUNTIME_NAME, $UDID" > "$WORK_DIR/simulator.txt"

# The tests check the software keyboard, which the simulator hides while a hardware keyboard is connected. Simulator
# reads these settings when the device boots.
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false \
  || echo "warning: could not disconnect the hardware keyboard"
defaults write com.apple.iphonesimulator DevicePreferences -dict-add "$UDID" \
  '<dict><key>ConnectHardwareKeyboard</key><false/></dict>' \
  || echo "warning: could not disconnect the hardware keyboard of $DEVICE_NAME"

was_booted=0
if xcrun simctl list devices booted | grep -q "$UDID"; then
  was_booted=1
else
  # Booting goes on while the tests build
  xcrun simctl boot "$UDID" || echo "warning: could not start booting $DEVICE_NAME"
fi

build_status=0
echo "Building the app and the tests"
xcodebuild build-for-testing \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath "$WORK_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  2>&1 | tee "$WORK_DIR/build-for-testing.log" || build_status=$?

xcrun simctl bootstatus "$UDID" -b > /dev/null || echo "warning: $DEVICE_NAME did not report a finished boot"

# Settings inside the simulator: no autocorrection or predictions changing typed text, and no swipe typing
# introduction over the keyboard
sim_defaults() {
  xcrun simctl spawn "$UDID" defaults write "$@" > /dev/null 2>&1 || true
}
sim_defaults com.apple.Preferences KeyboardAutocorrection -bool false
sim_defaults com.apple.Preferences KeyboardPrediction -bool false
sim_defaults com.apple.Preferences KeyboardContinuousPathEnabled -bool false
sim_defaults com.apple.Preferences DidShowContinuousPathIntroduction -bool true
sim_defaults com.apple.keyboard.ContinuousPath DidShowContinuousPathIntroduction -bool true
# The same status bar in every screenshot
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 > /dev/null 2>&1 || true

# Runs the built tests once with the simulator in the light or dark appearance; the arguments go to xcodebuild
run_tests() {
  local appearance="$1"
  shift
  echo "Running the UI tests ($appearance)"
  xcrun simctl ui "$UDID" appearance "$appearance"
  # Screenshots of the dark run get a `-dark` suffix. `xcodebuild` passes TEST_RUNNER_-prefixed variables to the
  # test runner without the prefix.
  local suffix=""
  [[ "$appearance" == light ]] || suffix="$appearance"
  local status=0
  env "TEST_RUNNER_LIQUIDGRAM_APPEARANCE=$suffix" xcodebuild test-without-building \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "id=$UDID" \
    -derivedDataPath "$WORK_DIR/DerivedData" \
    -resultBundlePath "$WORK_DIR/$appearance.xcresult" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance "$DEFAULT_TEST_TIME_ALLOWANCE" \
    -maximum-test-execution-time-allowance "$MAX_TEST_TIME_ALLOWANCE" \
    "$@" \
    2>&1 | tee "$WORK_DIR/$appearance.log" || status=$?
  return "$status"
}

# Exports what a pass left in its result bundle for report.mjs
export_results() {
  local pass="$1"
  local bundle="$WORK_DIR/$pass.xcresult"
  [[ -d "$bundle" ]] || return 0
  mkdir -p "$WORK_DIR/$pass/attachments"
  xcrun xcresulttool export attachments --path "$bundle" --output-path "$WORK_DIR/$pass/attachments" > /dev/null \
    || echo "warning: could not export the attachments of the $pass run"
  xcrun xcresulttool get test-results tests --path "$bundle" > "$WORK_DIR/$pass/tests.json" \
    || echo "warning: could not read the test results of the $pass run"
  xcrun xcresulttool get test-results summary --path "$bundle" > "$WORK_DIR/$pass/summary.json" \
    || echo "warning: could not read the test summary of the $pass run"
}

# The dark run repeats the demo account test when the filters include it
only_testing=()
runs_dark_mode_test=1
if [[ -n "${UI_TESTS_ONLY:-}" ]]; then
  runs_dark_mode_test=0
  IFS=',' read -r -a filters <<< "$UI_TESTS_ONLY"
  for filter in "${filters[@]}"; do
    only_testing+=("-only-testing:$filter")
    [[ "$DARK_MODE_TEST" == "$filter"* ]] && runs_dark_mode_test=1
  done
fi
[[ "${UI_TESTS_SKIP_DARK:-}" == 1 ]] && runs_dark_mode_test=0

test_status=0
if [[ "$build_status" == 0 ]]; then
  run_tests light ${only_testing[@]+"${only_testing[@]}"} || test_status=1
  export_results light

  if [[ "$runs_dark_mode_test" == 1 ]]; then
    run_tests dark "-only-testing:$DARK_MODE_TEST" || test_status=1
    export_results dark
    xcrun simctl ui "$UDID" appearance light
  fi
fi

echo "Collecting the app log"
xcrun simctl spawn "$UDID" log show --style compact --info --debug --last "$APP_LOG_WINDOW" \
  --predicate "$APP_LOG_PREDICATE" > "$WORK_DIR/app.log" 2>&1 || echo "warning: could not read the app log"
if [[ "$was_booted" == 0 ]]; then
  xcrun simctl shutdown "$UDID" > /dev/null 2>&1 || true
fi

report_options=(--work "$WORK_DIR" --out "$OUT_DIR" --device "$DEVICE_NAME" --runtime "$RUNTIME_NAME")
[[ "$build_status" == 0 ]] || report_options+=(--build-failed)
node "$REPORT_TOOL" summarize "${report_options[@]}"

if [[ "$build_status" != 0 ]]; then
  echo "error: the UI tests did not build; see $OUT_DIR/logs/build-for-testing.log" >&2
  exit 1
fi
if [[ "$test_status" != 0 ]]; then
  echo "error: UI tests failed; see $OUT_DIR/README.md" >&2
  exit 1
fi
echo "All UI tests passed"
