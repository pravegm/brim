#!/usr/bin/env bash
# Boots a regular iPhone simulator, installs the Debug build and captures one screenshot per demo scenario.
# ci/scenarios.txt lines: `name|demo args|seconds to wait before the capture`. The app interprets the demo args
# (Brim/App/DemoMode.swift, DEBUG only). App stdout/stderr per scenario: $OUT/logs/<name>.txt.
# Env: DEVICE (default "iPhone 18 Pro"), OUT (default ci-screens), SCENARIO_FILTER (regex on the name).
set -uo pipefail

DEVICE="${DEVICE:-iPhone 18 Pro}"
APP="build/Build/Products/Debug-iphonesimulator/Brim.app"
BUNDLE="com.pravegm.brim"
OUT="${OUT:-ci-screens}"
FILTER="${SCENARIO_FILTER:-.}"
mkdir -p "$OUT/logs"
OUT_ABS="$(cd "$OUT" && pwd)"

UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
want=sys.argv[1]
for rt,devs in json.load(sys.stdin)['devices'].items():
    for d in devs:
        if d['name']==want: print(d['udid']); sys.exit(0)
" "$DEVICE")
[[ -n "$UDID" ]] || { echo "no simulator named $DEVICE"; exit 1; }
echo "device $DEVICE $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

fails=0
while IFS='|' read -r name args wait; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  [[ "$name" =~ $FILTER ]] || continue
  wait="${wait:-6}"
  echo "== $name ($args) wait ${wait}s"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch --terminate-running-process \
    --stdout="$OUT_ABS/logs/$name.txt" --stderr="$OUT_ABS/logs/$name.txt" \
    "$UDID" "$BUNDLE" -brimDemo "$args" >/dev/null || { echo "launch failed: $name"; fails=$((fails+1)); continue; }
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT_ABS/$name.png" >/dev/null 2>&1 || { echo "screenshot failed: $name"; fails=$((fails+1)); }
  # The app writes Documents/AppIcon-1024.png for the `icon` scenario (rendered from SwiftUI, Brim/UI/AppIconArt.swift).
  if [[ "$args" == *icon* ]]; then
    data=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)
    [[ -n "$data" && -f "$data/Documents/AppIcon-1024.png" ]] && cp "$data/Documents/AppIcon-1024.png" "$OUT_ABS/AppIcon-1024.png"
  fi
  grep -E "BRIM-" "$OUT_ABS/logs/$name.txt" | tail -5 || true
done < ci/scenarios.txt

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
ls -la "$OUT_ABS"
echo "screenshot failures: $fails"
exit 0
