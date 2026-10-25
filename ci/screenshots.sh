#!/usr/bin/env bash
# Boots a regular iPhone simulator, installs the Debug build and captures one screenshot per demo scenario.
# ci/scenarios.txt lines: `name|demo args|seconds to wait before the capture`. The app interprets the demo args
# (Brim/App/DemoMode.swift, DEBUG only). App stdout/stderr per scenario: $OUT/logs/<name>.txt, plus a snapshot of it
# taken right after the screenshot: $OUT/logs/<name>.at-capture.txt (what ci/store-set.sh checks the frame against).
# Extra columns after the wait (ci/store-scenarios.txt: caption, expect) are ignored here; ci/store-set.sh reads them.
# Every simulator call has a timeout; a failed launch or screenshot is retried once, then skipped (the run goes on).
# Env:
#  DEVICE          default "iPhone 18 Pro". One candidate, or several separated by `|`, tried in order:
#                    <exact name>          an available simulator with that name (created from the device type of that
#                                          name if none exists yet)
#                    auto:<suffix>         the newest iPhone whose name ends with <suffix>, e.g. `auto:Pro Max`
#                    screen:<WxH>[,<WxH>]  the newest iPhone device type whose screen is one of these pixel sizes
#                                          (portrait, first size preferred), e.g. `screen:1179x2556,1170x2532`
#                  e.g. "screen:1179x2556,1170x2532|iPhone 18 Pro". The pick is written to $OUT/device.txt.
#  OUT             default ci-screens.
#  SCENARIOS       default ci/scenarios.txt.
#  SCENARIO_FILTER regex on the name (default ".").
#  EXPECT_SIZE     space-separated WxH list (e.g. "1320x2868"): warn when a capture is another size (never fails).
#  WAIT_FREEZE     1 = for a scenario with freezeOn=<x>, wait (up to max(wait, 60) s) for the app's
#                  "BRIM-T freeze <x>" line, then 2 s, instead of the fixed wait. Default 0 (fixed wait, as before).
# Writes $OUT/captures.tsv: name <TAB> ok|launch-failed|screenshot-failed <TAB> WxH.
set -uo pipefail

DEVICE="${DEVICE:-iPhone 18 Pro}"
APP="build/Build/Products/Debug-iphonesimulator/Brim.app"
BUNDLE="com.pravegm.brim"
OUT="${OUT:-ci-screens}"
FILTER="${SCENARIO_FILTER:-.}"
SCENARIOS="${SCENARIOS:-ci/scenarios.txt}"
EXPECT_SIZE="${EXPECT_SIZE:-}"
WAIT_FREEZE="${WAIT_FREEZE:-0}"
mkdir -p "$OUT/logs"
OUT_ABS="$(cd "$OUT" && pwd)"
INDEX="$OUT_ABS/captures.tsv"
: > "$INDEX"

# to <seconds> <command…>: run with a timeout (gtimeout / timeout from coreutils, else perl's alarm).
to() {
  local s="$1"; shift
  if command -v gtimeout >/dev/null 2>&1; then gtimeout -k 5 "$s" "$@"
  elif command -v timeout >/dev/null 2>&1; then timeout -k 5 "$s" "$@"
  else perl -e 'alarm shift; exec @ARGV or die "exec failed: $!\n"' "$s" "$@"; fi
}

# png_dims <file>: "WxH" via sips, or "?".
png_dims() {
  local w h
  w=$(to 20 sips -g pixelWidth "$1" 2>/dev/null | awk '/pixelWidth/ {print $2}')
  h=$(to 20 sips -g pixelHeight "$1" 2>/dev/null | awk '/pixelHeight/ {print $2}')
  if [[ -n "$w" && -n "$h" ]]; then echo "${w}x${h}"; else echo "?"; fi
}

# Prints "<udid><TAB><name><TAB><how>", or "CREATE<TAB><type id><TAB><runtime id><TAB><name><TAB><how>" when the device
# has to be created. Exits 1 when no candidate matches.
RESOLVE_PY='
import json, os, plistlib, re, subprocess, sys

def simctl(*what):
    return json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j", *what], timeout=120))

def model(name):
    m = re.search(r"iPhone (\d+)", name)
    return int(m.group(1)) if m else 0

def rt_version(identifier):
    m = re.search(r"iOS-(\d+)-(\d+)", identifier)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)

# Portrait pixel sizes for when a device type profile cannot be read.
KNOWN = {
    "iPhone 12": "1170x2532", "iPhone 12 Pro": "1170x2532", "iPhone 13": "1170x2532", "iPhone 13 Pro": "1170x2532",
    "iPhone 14": "1170x2532", "iPhone 16e": "1170x2532",
    "iPhone 14 Pro": "1179x2556", "iPhone 15": "1179x2556", "iPhone 15 Pro": "1179x2556", "iPhone 16": "1179x2556",
    "iPhone 16 Pro": "1206x2622", "iPhone 17": "1206x2622", "iPhone 17 Pro": "1206x2622", "iPhone 18 Pro": "1206x2622",
    "iPhone 16 Pro Max": "1320x2868", "iPhone 17 Pro Max": "1320x2868", "iPhone 18 Pro Max": "1320x2868",
}

def screen(t):
    path = os.path.join(t.get("bundlePath", ""), "Contents", "Resources", "profile.plist")
    try:
        with open(path, "rb") as f:
            p = plistlib.load(f)
        w, h = int(p["mainScreenWidth"]), int(p["mainScreenHeight"])
        return "%dx%d" % (min(w, h), max(w, h))
    except Exception:
        return KNOWN.get(t.get("name", ""), "")

devices = simctl("devices", "available")["devices"]
existing = [(d, rt) for rt, ds in devices.items() if "iOS" in rt for d in ds]
types = [t for t in simctl("devicetypes")["devicetypes"] if t.get("name", "").startswith("iPhone")]
runtimes = sorted((r for r in simctl("runtimes")["runtimes"] if r.get("isAvailable") and "iOS" in r.get("identifier", "")),
                  key=lambda r: rt_version(r["identifier"]), reverse=True)

def supports(r, t):
    s = r.get("supportedDeviceTypes")
    return s is None or any(x.get("identifier") == t["identifier"] for x in s)

def done(udid, name, how):
    print(udid + "\t" + name + "\t" + how)
    sys.exit(0)

def from_types(cands, how):
    for t in cands:
        have = sorted(((rt_version(rt), d["udid"], d["name"]) for d, rt in existing
                       if d.get("deviceTypeIdentifier") == t["identifier"] or d["name"] == t["name"]), reverse=True)
        if have:
            done(have[0][1], have[0][2], how + " " + t["name"])
        for r in runtimes:
            if supports(r, t):
                print("CREATE\t" + t["identifier"] + "\t" + r["identifier"] + "\t" + t["name"] + "\t" + how + " " + t["name"] + " (created)")
                sys.exit(0)

cands = [c.strip() for c in sys.argv[1].split("|") if c.strip()]
for i, c in enumerate(cands):
    tag = "candidate %d/%d (%s)%s:" % (i + 1, len(cands), c, "" if i == 0 else " FALLBACK")
    if c.startswith("auto:"):
        suffix = c[5:]
        found = sorted(((model(d["name"]), rt_version(rt)), d["udid"], d["name"]) for d, rt in existing
                       if d["name"].startswith("iPhone") and d["name"].endswith(suffix))
        if found:
            done(found[-1][1], found[-1][2], tag)
        from_types(sorted((t for t in types if t["name"].endswith(suffix)), key=lambda t: model(t["name"]), reverse=True), tag)
    elif c.startswith("screen:"):
        sizes = [s.strip().lower() for s in c[7:].split(",") if s.strip()]
        ranked = []
        for t in types:
            px = screen(t)
            if px in sizes:
                ranked.append((sizes.index(px), -model(t["name"]), t["name"], t))
        ranked.sort(key=lambda x: (x[0], x[1], x[2]))
        from_types([x[3] for x in ranked], tag + " screen " + ",".join(sizes))
    else:
        found = sorted((rt_version(rt), d["udid"], d["name"]) for d, rt in existing if d["name"] == c)
        if found:
            done(found[-1][1], found[-1][2], tag)
        from_types([t for t in types if t["name"] == c], tag)
sys.exit(1)
'
RESOLVED=$(to 300 python3 -I -c "$RESOLVE_PY" "$DEVICE") || {
  echo "no simulator named $DEVICE"
  to 60 xcrun simctl list devices available || true
  exit 1
}
HOW=""
if [[ "$RESOLVED" == CREATE* ]]; then
  IFS=$'\t' read -r _ TYPE_ID RUNTIME_ID DEVICE_NAME HOW <<< "$RESOLVED"
  echo "creating '$DEVICE_NAME' ($TYPE_ID, $RUNTIME_ID)"
  UDID=$(to 120 xcrun simctl create "$DEVICE_NAME" "$TYPE_ID" "$RUNTIME_ID") || { echo "could not create $DEVICE_NAME"; exit 1; }
else
  IFS=$'\t' read -r UDID DEVICE_NAME HOW <<< "$RESOLVED"
fi
[[ -n "${UDID:-}" ]] || { echo "no simulator named $DEVICE"; exit 1; }
echo "device $DEVICE_NAME $UDID ($HOW)"
printf 'requested=%s\nname=%s\nudid=%s\nresolved=%s\n' "$DEVICE" "$DEVICE_NAME" "$UDID" "$HOW" > "$OUT_ABS/device.txt"

to 120 xcrun simctl boot "$UDID" 2>/dev/null || true
to 600 xcrun simctl bootstatus "$UDID" -b || echo "warning: bootstatus did not finish for $DEVICE_NAME"
to 30 xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 2>/dev/null || true
to 300 xcrun simctl install "$UDID" "$APP" || {
  echo "install failed, retrying"; sleep 5
  to 300 xcrun simctl install "$UDID" "$APP" || echo "install failed"
}

fails=0
size_warnings=0
while IFS='|' read -r -u 3 name args wait _caption _expect; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  [[ "$name" =~ $FILTER ]] || continue
  wait="${wait:-6}"
  wait="${wait%%.*}"
  [[ "$wait" =~ ^[0-9]+$ ]] || wait=6
  echo "== $name ($args) wait ${wait}s"
  applog="$OUT_ABS/logs/$name.txt"
  rm -f "$OUT_ABS/$name.png"
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  launched=0
  for attempt in 1 2; do
    if to 90 xcrun simctl launch --terminate-running-process \
      --stdout="$applog" --stderr="$applog" \
      "$UDID" "$BUNDLE" -brimDemo "$args" >/dev/null; then
      launched=1; break
    fi
    echo "launch attempt $attempt failed: $name"
    sleep 3
  done
  if (( ! launched )); then
    echo "launch failed: $name"; fails=$((fails+1))
    printf '%s\tlaunch-failed\t-\n' "$name" >> "$INDEX"
    continue
  fi

  freeze=""
  if [[ "$WAIT_FREEZE" == 1 && "$args" =~ freezeOn=([a-z]+) ]]; then freeze="${BASH_REMATCH[1]}"; fi
  if [[ -n "$freeze" ]]; then
    limit=$(( wait > 60 ? wait : 60 )); t=0
    while (( t < limit )); do grep -q "BRIM-T freeze $freeze" "$applog" 2>/dev/null && break; sleep 1; t=$((t+1)); done
    if grep -q "BRIM-T freeze $freeze" "$applog" 2>/dev/null; then
      echo "froze ($freeze) after ${t}s"; sleep 2
    else
      echo "warning: $name: no 'BRIM-T freeze $freeze' line after ${limit}s (capturing anyway)"
    fi
  else
    sleep "$wait"
  fi

  shot=0
  for attempt in 1 2; do
    to 60 xcrun simctl io "$UDID" screenshot "$OUT_ABS/$name.png" >/dev/null 2>&1 && { shot=1; break; }
    sleep 2
  done
  cp "$applog" "$OUT_ABS/logs/$name.at-capture.txt" 2>/dev/null || : > "$OUT_ABS/logs/$name.at-capture.txt"
  if (( shot )); then
    dims=$(png_dims "$OUT_ABS/$name.png")
    printf '%s\tok\t%s\n' "$name" "$dims" >> "$INDEX"
    if [[ -n "$EXPECT_SIZE" && " $EXPECT_SIZE " != *" $dims "* ]]; then
      echo "warning: $name is $dims, expected one of: $EXPECT_SIZE"
      size_warnings=$((size_warnings+1))
    fi
  else
    echo "screenshot failed: $name"; fails=$((fails+1))
    printf '%s\tscreenshot-failed\t-\n' "$name" >> "$INDEX"
  fi
  # The app writes Documents/AppIcon-1024.png for the `icon` scenario (rendered from SwiftUI, Brim/UI/AppIconArt.swift).
  if [[ "$args" == *icon* ]]; then
    data=$(to 30 xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)
    [[ -n "$data" && -f "$data/Documents/AppIcon-1024.png" ]] && cp "$data/Documents/AppIcon-1024.png" "$OUT_ABS/AppIcon-1024.png"
  fi
  # The app writes Documents/badges/<id>.png for the `badges` scenario (Game Center achievement images, rendered from
  # SwiftUI, Brim/UI/AchievementArt.swift). They land in $OUT/badges/ (the `screenshots` artifact's badges/ folder).
  if [[ "$args" == *badges* ]]; then
    data=$(to 30 xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)
    if [[ -n "$data" && -d "$data/Documents/badges" ]]; then
      mkdir -p "$OUT_ABS/badges"
      cp "$data/Documents/badges/"*.png "$OUT_ABS/badges/" 2>/dev/null || echo "warning: $name: no PNGs in Documents/badges"
      echo "badges: $(ls "$OUT_ABS/badges" | wc -l | tr -d ' ') PNGs"
    else
      echo "warning: $name: no Documents/badges folder"
    fi
  fi
  grep -E "BRIM-" "$applog" | tail -5 || true
done 3< "$SCENARIOS"

to 30 xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
ls -la "$OUT_ABS"
echo "screenshot failures: $fails"
if [[ -n "$EXPECT_SIZE" ]]; then echo "size warnings: $size_warnings (expected $EXPECT_SIZE on $DEVICE_NAME)"; fi
exit 0
