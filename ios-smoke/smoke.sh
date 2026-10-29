#!/usr/bin/env bash
# Scratch smoke test of the native features on the iOS Simulator: builds the Release IPA and the Debug app with the
# scratch UI tests around a small bridge test page, collects compiler warnings
# and runs the UI tests (status bar tap, keyboard, focus after openSearch, lock, links, quick action), leaving
# everything in $RESULTS.
set -uo pipefail

RESULTS="${RESULTS:?}"
BUNDLE_ID=org.liquidgram.messenger
mkdir -p "$RESULTS/shots"

note() {
  echo "== $*" | tee -a "$RESULTS/steps.txt"
}

shot() {
  xcrun simctl io "$UDID" screenshot "$RESULTS/shots/$1.png" > /dev/null 2>&1 || note "screenshot $1 failed"
}

# A page that reports what the bridge offers and every action it receives
mkdir -p dist
cat > dist/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#ffffff">
<title>Bridge smoke test</title>
<style>
  body { font: 14px -apple-system, sans-serif; margin: 0; padding: calc(env(safe-area-inset-top) + 8px) 12px 12px; background: #fff; color: #111; }
  pre { white-space: pre-wrap; word-break: break-all; font-size: 11px; margin: 0; }
  h3 { margin: 0 0 6px; }
  input { font-size: 16px; width: 90%; margin: 6px 0; }
  p { margin: 2px 0; font-weight: 600; }
</style>
</head>
<body>
<h3>Bridge smoke test</h3>
<input id="field" type="text" aria-label="Smoke field" placeholder="Smoke field">
<div id="state"></div>
<div id="actions"></div>
<pre id="out"></pre>
<script>
  const out = document.getElementById('out');
  function log(line) { out.textContent += line + '\n'; }
  function show(parentId, text) {
    const line = document.createElement('p');
    line.textContent = text;
    document.getElementById(parentId).append(line);
  }
  const field = document.getElementById('field');
  field.addEventListener('focus', () => show('state', 'field focused'));
  // A test's user script sets this to check that a focus without a native action brings up no keyboard
  if (window.__smokeFocusOnLoad) setTimeout(() => field.focus(), 1000);
  const native = window.__liquidgramNative;
  log('UA: ' + navigator.userAgent);
  log('native: ' + (native ? Object.keys(native).join(',') : 'missing'));
  if (native && native.setActionHandler) {
    native.setActionHandler((action) => {
      log('action: ' + JSON.stringify(action));
      show('actions', 'action ' + action.type + (action.url ? ' ' + action.url : ''));
      // Like the web app, which focuses its search field once the search screen has opened
      if (action.type === 'openSearch') setTimeout(() => field.focus(), 500);
    });
    native.request('getNativeSettings').then((response) => {
      log('settings: ' + JSON.stringify(response));
      show('state', 'ready');
    }, (err) => log('request error: ' + err));
  }
</script>
</body>
</html>
HTML

note "Release device build"
bash ios/build-ipa.sh > "$RESULTS/build-device.log" 2>&1
echo "device build exit: $?" | tee -a "$RESULTS/steps.txt"
grep -E "(warning|error):" "$RESULTS/build-device.log" | sort -u > "$RESULTS/warnings-device.txt"

UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
runtimes = sorted((runtime for runtime in devices if "iOS" in runtime), reverse=True)
for runtime in runtimes:
    for device in devices[runtime]:
        if device["name"].startswith("iPhone") and "Pro" in device["name"]:
            print(device["udid"]); sys.exit()
')"
note "Simulator $UDID"
xcrun simctl list devices | grep "$UDID" | tee -a "$RESULTS/steps.txt"
# The software keyboard shows only without a hardware keyboard, which Simulator reads when the device boots
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
defaults write com.apple.iphonesimulator DevicePreferences -dict-add "$UDID" \
  '<dict><key>ConnectHardwareKeyboard</key><false/></dict>'
xcrun simctl boot "$UDID"

note "Debug build for testing"
xcodebuild build-for-testing -project ios/Liquidgram.xcodeproj -scheme Liquidgram -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$RUNNER_TEMP/sim" CODE_SIGNING_ALLOWED=NO \
  > "$RESULTS/build-sim.log" 2>&1
echo "simulator build exit: $?" | tee -a "$RESULTS/steps.txt"
grep -E "(warning|error):" "$RESULTS/build-sim.log" | sort -u > "$RESULTS/warnings-sim.txt"
APP="$RUNNER_TEMP/sim/Build/Products/Debug-iphonesimulator/Liquidgram.app"

xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl ui "$UDID" appearance light
xcrun simctl install "$UDID" "$APP"
echo "install exit: $?" | tee -a "$RESULTS/steps.txt"

xcrun simctl spawn "$UDID" log stream --level debug --style compact \
  --predicate 'subsystem == "org.liquidgram.messenger"' > "$RESULTS/app-stream.log" 2>&1 &
LOG_STREAM=$!
sleep 2

note "UI tests"
TEST_RUNNER_SMOKE_SHOTS="$RESULTS/shots" xcodebuild test-without-building -project ios/Liquidgram.xcodeproj \
  -scheme Liquidgram -destination "id=$UDID" -derivedDataPath "$RUNNER_TEMP/sim" \
  -resultBundlePath "$RUNNER_TEMP/ui.xcresult" > "$RESULTS/ui-tests.log" 2>&1
echo "ui tests exit: $?" | tee -a "$RESULTS/steps.txt"
grep -E "Test Case .*(passed|failed)|error: |Executed [0-9]+ test" "$RESULTS/ui-tests.log" > "$RESULTS/ui-summary.txt"
xcrun xcresulttool export attachments --path "$RUNNER_TEMP/ui.xcresult" --output-path "$RESULTS/attachments" \
  > /dev/null 2>&1 || note "attachment export failed"

note "App log"
sleep 1
kill "$LOG_STREAM"
xcrun simctl spawn "$UDID" log show --last 30m --style compact \
  --predicate 'subsystem == "org.liquidgram.messenger"' > "$RESULTS/app.log" 2>&1
tail -c 200000 "$RESULTS/ui-tests.log" > "$RESULTS/ui-tests-tail.log"
rm -f "$RESULTS/ui-tests.log"

note "done"
