#!/usr/bin/env bash
# Requires macOS/Xcode; used by GitHub Actions. No DCloud SDK or camera permission.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/CameraPreviewRegression.app"
mkdir -p "$APP"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator clang -fobjc-arc -fmodules -arch "$(uname -m)" \
  -isysroot "$SDK" -mios-simulator-version-min=13.0 \
  -framework UIKit -framework AVFoundation -framework Foundation -framework CoreGraphics -framework QuartzCore \
  tests/CameraPreviewRegression.m -o "$APP/CameraPreviewRegression"
python3 - "$APP/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({
        'CFBundleIdentifier': 'io.github.uniidcardcapture.regression',
        'CFBundleExecutable': 'CameraPreviewRegression',
        'CFBundleName': 'CameraPreviewRegression',
        'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '1',
        'CFBundleShortVersionString': '1.0',
        'MinimumOSVersion': '13.0',
        'LSRequiresIPhoneOS': True,
        'UIDeviceFamily': [1, 2],
        'UILaunchScreen': {},
    }, output)
PY
codesign --force --sign - "$APP"
xcrun simctl list runtimes -j > build/simulator-runtimes.json
RUNTIME="$(python3 - <<'PY'
import json
with open('build/simulator-runtimes.json') as source:
    runtimes = [r for r in json.load(source)['runtimes'] if r['isAvailable'] and '.iOS-' in r['identifier']]
if not runtimes:
    raise SystemExit('No iOS Simulator runtime installed')
print(runtimes[-1]['identifier'])
PY
)"
DEVICE="$(xcrun simctl create CameraPreviewRegression com.apple.CoreSimulator.SimDeviceType.iPhone-15 "$RUNTIME")"
trap 'xcrun simctl shutdown "$DEVICE" >/dev/null 2>&1 || true; xcrun simctl delete "$DEVICE" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch "$DEVICE" io.github.uniidcardcapture.regression
CONTAINER="$(xcrun simctl get_app_container "$DEVICE" io.github.uniidcardcapture.regression data)"
for attempt in $(seq 1 30); do
  if [ -s "$CONTAINER/Documents/regression-result.json" ]; then
    cp "$CONTAINER/Documents/regression-result.json" build/regression-result.json
    python3 - <<'PY'
import json
with open('build/regression-result.json') as source:
    result = json.load(source)
print(json.dumps(result, indent=2))
raise SystemExit(0 if result['passed'] else 1)
PY
    exit 0
  fi
  sleep 1
done
echo '::error::Simulator regression app did not return a result within 30 seconds.'
exit 1
