#!/usr/bin/env bash
# Runs the UI tests of ios/LiquidgramUITests on an iPhone simulator and writes a report that is readable without
# Xcode: README.md (summary.md with the contact sheet and the screenshots), summary.md (a table of the tests and the
# self-test checks), summary.json, contact-sheet.png, screenshots/, ax/ (accessibility trees of failed tests) and
# logs/. The tests of DARK_MODE_TESTS run a second time with the simulator in dark mode. Exits with 1 when a test
# failed or the tests did not build.
#
# Needs macOS with Xcode 16 or newer and Node.js. Run ios/build-ipa.sh first: it copies the web build into
# ios/Liquidgram/WebApp and generates ios/Liquidgram.xcodeproj, which this script uses.
#
# Usage: ios/run-ui-tests.sh [output-dir]
#   output-dir  defaults to <repo-root>/dist-ios/ui-tests
# Environment:
#   UI_TESTS_ONLY       comma-separated tests to run: a class or a class/test, with or without the LiquidgramUITests/
#                       prefix, such as `GestureTests,UsabilityTests/testAppStaysPortrait`; an entry that starts with
#                       `-` is skipped instead, such as `-FeatureTests/testPrivacyShieldCoversAppWhileInactive`
#   UI_TESTS_DARK       comma-separated tests for the dark mode pass instead of DARK_MODE_TESTS, in the same form;
#                       the pass runs those of them that UI_TESTS_ONLY selects
#   UI_TESTS_DEVICE     a simulator name to use instead of an iPhone 17 Pro or 16 Pro
#   UI_TESTS_SKIP_DARK  1 skips the dark mode pass
#   UI_TESTS_WORK_DIR   where the result bundles go, <repo-root>/dist-ios/ui-tests-work by default
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$ROOT/ios"
PROJECT="$IOS_DIR/Liquidgram.xcodeproj"
SCHEME="Liquidgram"
TEST_BUNDLE="LiquidgramUITests"
APP_BUNDLE_ID="org.liquidgram.messenger"
TESTS_DIR="$IOS_DIR/LiquidgramUITests"
REPORT_TOOL="$TESTS_DIR/Tools/report.mjs"
WEBAPP_DIR="$IOS_DIR/Liquidgram/WebApp"
# The `worker` check of the self-test loads this echo worker from the app's origin; only the test build has it
SELFTEST_WORKER="liquidgram-selftest-worker.js"
DARK_MODE_TEST="LiquidgramUITests/CoreTests/testDemoAccount"
APP_LOG_PREDICATE='subsystem == "org.liquidgram.messenger"'
APP_LOG_WINDOW="30m"
# Tests that also run with the simulator in dark mode: the demo account and the color of the status bar strip
DARK_MODE_TESTS="$DARK_MODE_TEST,UsabilityTests/testStatusBarStripMatchesTheme"
# Recording tests would stop at the system's permission prompts; a grant that a runtime lacks only logs a warning
PRIVACY_GRANTS=(microphone camera photos)
# Seconds per test; XCTest rounds them up to whole minutes
DEFAULT_TEST_TIME_ALLOWANCE=180
MAX_TEST_TIME_ALLOWANCE=300

fail() {
  echo "error: $*" >&2
  exit 1
}

# Prints `LiquidgramUITests/<class>[/<test>]` for `GestureTests`, `LiquidgramUITests/GestureTests` or
# `GestureTests/testX`, and nothing for an empty entry
normalize_test() {
  local test="$1"
  test="${test#"${test%%[![:space:]]*}"}"
  test="${test%"${test##*[![:space:]]}"}"
  test="${test#"$TEST_BUNDLE/"}"
  [[ -n "$test" ]] || return 1
  echo "$TEST_BUNDLE/$test"
}

# Whether a test (`LiquidgramUITests/<class>/<test>`) is selected by the filters of this run
is_selected() {
  local test="$1" filter is_listed=0
  [[ "${#only_filters[@]}" == 0 ]] && is_listed=1
  for filter in ${only_filters[@]+"${only_filters[@]}"}; do
    [[ "$test" == "$filter" || "$test" == "$filter/"* ]] && is_listed=1
  done
  for filter in ${skip_filters[@]+"${skip_filters[@]}"}; do
    [[ "$test" == "$filter" || "$test" == "$filter/"* ]] && is_listed=0
  done
  [[ "$is_listed" == 1 ]]
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
  "$OUT_DIR/README.md" "$OUT_DIR/summary.md" "$OUT_DIR/summary.json" "$OUT_DIR/contact-sheet.png"
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

# Microphone, camera and photo permissions in advance, so a recording test never stops at the system prompt. The
# grant needs the app on the simulator; `xcodebuild test-without-building` installs the same build again and keeps it.
app_path="$WORK_DIR/DerivedData/Build/Products/Debug-iphonesimulator/Liquidgram.app"
if [[ "$build_status" == 0 && -d "$app_path" ]]; then
  xcrun simctl install "$UDID" "$app_path" > /dev/null 2>&1 \
    || echo "warning: could not install the app to grant its permissions"
  for service in "${PRIVACY_GRANTS[@]}"; do
    xcrun simctl privacy "$UDID" grant "$service" "$APP_BUNDLE_ID" > /dev/null 2>&1 \
      || echo "warning: could not grant $service to the app"
  done
fi

# Keyboard preferences inside the simulator, on a best-effort basis: no autocorrection changing typed text and no
# swipe typing introduction over the keyboard
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
    "$@" ${skip_testing[@]+"${skip_testing[@]}"} \
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

# UI_TESTS_ONLY becomes -only-testing and -skip-testing filters
only_filters=()
skip_filters=()
IFS=',' read -r -a requested_tests <<< "${UI_TESTS_ONLY:-}"
for entry in ${requested_tests[@]+"${requested_tests[@]}"}; do
  entry="${entry#"${entry%%[![:space:]]*}"}"
  if [[ "$entry" == -* ]]; then
    filter="$(normalize_test "${entry#-}")" && skip_filters+=("$filter")
  else
    filter="$(normalize_test "$entry")" && only_filters+=("$filter")
  fi
done
only_testing=()
for filter in ${only_filters[@]+"${only_filters[@]}"}; do
  only_testing+=("-only-testing:$filter")
done
# `run_tests` adds these to every pass
skip_testing=()
for filter in ${skip_filters[@]+"${skip_filters[@]}"}; do
  skip_testing+=("-skip-testing:$filter")
done

# The dark pass repeats the tests of DARK_MODE_TESTS that this run selects
dark_arguments=()
if [[ "${UI_TESTS_SKIP_DARK:-}" != 1 ]]; then
  IFS=',' read -r -a dark_tests <<< "${UI_TESTS_DARK:-$DARK_MODE_TESTS}"
  for entry in ${dark_tests[@]+"${dark_tests[@]}"}; do
    test="$(normalize_test "$entry")" || continue
    if is_selected "$test"; then
      dark_arguments+=("-only-testing:$test")
    fi
  done
fi

test_status=0
if [[ "$build_status" == 0 ]]; then
  run_tests light ${only_testing[@]+"${only_testing[@]}"} || test_status=1
  export_results light

  if [[ "${#dark_arguments[@]}" -gt 0 ]]; then
    run_tests dark "${dark_arguments[@]}" || test_status=1
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
# A filter that matches no test must not pass as a green run
if [[ "$(node -p 'require(process.argv[1]).status' "$OUT_DIR/summary.json")" == no-results ]]; then
  echo "error: no UI test ran; check UI_TESTS_ONLY" >&2
  exit 1
fi
echo "All UI tests passed"
