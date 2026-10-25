#!/usr/bin/env bash
# iPhone Duo simulator capture for Brim (called by .github/workflows/duo.yml).
# Lessons inherited from Squish (docs there: DUO-CI.md):
#  - `simctl io screenshot` needs --display on the Duo; we probe the names and keep the lit panel.
#  - The Duo sim starts in book pose (landscape inner canvas). The app asks for portrait itself (demo key
#    `orient=portrait`, logs "BRIM-T orient portrait ok"), which gives the 669 × 951 tabletop canvas.
#  - Never run `simctl io … screenConfig` on the Duo (SpringBoard crash loop).
#  - Wait ~2.5 s after a hinge move for the display to settle; `hinge` occasionally fails a move, so retry.
# Env: UDID, OUT (duo-screens), PASSES ("hinge store ui").
set -uo pipefail

APP="build/Build/Products/Debug-iphonesimulator/Brim.app"
BUNDLE="com.pravegm.brim"
OUT="${OUT:-duo-screens}"
PASSES="${PASSES:-hinge store ui}"
mkdir -p "$OUT/raw" "$OUT/logs"
OUT_ABS="$(cd "$OUT" && pwd)"
RUNLOG="$OUT_ABS/logs/run.txt"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$RUNLOG" >&2; }
to() { local s="$1"; shift; gtimeout -k 5 "$s" "$@"; }

xcrun simctl install "$UDID" "$APP" || { log "install failed"; exit 1; }

INNER=""; COVER=""
for c in LCD-1 primary-1 3 internal; do
  to 30 xcrun simctl io "$UDID" screenshot --display="$c" "$OUT_ABS/raw/_p.png" >/dev/null 2>>"$RUNLOG" && { INNER="$c"; break; }
done
for c in LCD primary 1 external; do
  [[ "$c" == "$INNER" ]] && continue
  to 30 xcrun simctl io "$UDID" screenshot --display="$c" "$OUT_ABS/raw/_p.png" >/dev/null 2>>"$RUNLOG" && { COVER="$c"; break; }
done
rm -f "$OUT_ABS/raw/_p.png"
log "displays inner=$INNER cover=$COVER"

HAVE_HINGE=0; command -v hinge >/dev/null 2>&1 && HAVE_HINGE=1
CUR=180
hinge_set() { (( HAVE_HINGE )) || return 1; local a; for a in 1 2 3; do to 20 hinge -d "$UDID" -t 3 "$1" >>"$RUNLOG" 2>&1 && { CUR="$1"; return 0; }; sleep 1; done; log "WARN hinge set $1 failed"; return 1; }
hinge_sweep() {   # hinge_sweep <to> <seconds>: continuous 60 Hz stream so the app sees a real motion
  (( HAVE_HINGE )) || return 1
  to $(( ${2%.*} + 20 )) hinge -d "$UDID" sweep "$CUR" "$1" "$2" >>"$RUNLOG" 2>&1 || log "WARN sweep exited non-zero"
  CUR="$1"
}

# brightness of a PNG, 0-255 (sips → 16×16 BMP)
brightness() {
  local tmp="$OUT_ABS/raw/_b.bmp"
  to 20 sips -z 16 16 -s format bmp "$1" --out "$tmp" >/dev/null 2>&1 || { echo -1; return; }
  python3 -I - "$tmp" <<'PY' 2>/dev/null || echo -1
import struct, sys
b = open(sys.argv[1], "rb").read()
off = struct.unpack_from("<I", b, 10)[0]; w, h = struct.unpack_from("<ii", b, 18); bpp = struct.unpack_from("<H", b, 28)[0]
step = bpp // 8; row = (w * step + 3) & ~3; tot = n = 0
for y in range(abs(h)):
    for x in range(w):
        p = off + y * row + x * step; tot += b[p] + b[p + 1] + b[p + 2]; n += 3
print(int(tot / n))
PY
  rm -f "$tmp"
}

shoot() {   # shoot <name> <inner|cover>
  local name="$1" want="$2" ib=-1 cb=-1 pick
  [[ -n "$INNER" ]] && to 30 xcrun simctl io "$UDID" screenshot --display="$INNER" "$OUT_ABS/raw/$name-inner.png" >/dev/null 2>>"$RUNLOG" && ib=$(brightness "$OUT_ABS/raw/$name-inner.png")
  [[ -n "$COVER" ]] && to 30 xcrun simctl io "$UDID" screenshot --display="$COVER" "$OUT_ABS/raw/$name-cover.png" >/dev/null 2>>"$RUNLOG" && cb=$(brightness "$OUT_ABS/raw/$name-cover.png")
  if [[ -z "$INNER$COVER" ]]; then to 30 xcrun simctl io "$UDID" screenshot "$OUT_ABS/$name.png" >/dev/null 2>>"$RUNLOG"; return; fi
  if (( ib > 6 && cb <= 6 )); then pick=inner; elif (( cb > 6 && ib <= 6 )); then pick=cover; else pick="$want"; fi
  [[ -f "$OUT_ABS/raw/$name-$pick.png" ]] && cp "$OUT_ABS/raw/$name-$pick.png" "$OUT_ABS/$name.png"
  log "shot $name (inner=$ib cover=$cb -> $pick, hinge ${CUR}°) size=$(sips -g pixelWidth -g pixelHeight "$OUT_ABS/$name.png" 2>/dev/null | awk '/pixel/{printf "%s ", $2}')"
}

launch() {   # launch <name> <demo args>
  local name="$1" args="$2"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  : > "$OUT_ABS/logs/$name.txt"
  to 60 xcrun simctl launch --terminate-running-process --stdout="$OUT_ABS/logs/$name.txt" --stderr="$OUT_ABS/logs/$name.txt" \
    "$UDID" "$BUNDLE" -brimDemo "$args" >/dev/null 2>>"$RUNLOG" || log "WARN launch $name failed"
  local t=0
  while (( t < 45 )); do grep -q "BRIM-T frame 120" "$OUT_ABS/logs/$name.txt" 2>/dev/null && break; sleep 1; t=$((t+1)); done
  t=0
  while (( t < 30 )); do grep -q "BRIM-T orient portrait ok" "$OUT_ABS/logs/$name.txt" 2>/dev/null && break; sleep 1; t=$((t+1)); done
  log "launched $name after frame+orient wait; $(grep -c 'BRIM-H' "$OUT_ABS/logs/$name.txt" 2>/dev/null) hinge lines so far"
  sleep 2
}

# ---- pass: real hinge pours -------------------------------------------------------------------------------
if [[ " $PASSES " == *" hinge "* ]]; then
  hinge_set 178
  launch hinge-1-1 "mode=shift:1-1;duo;orient=portrait;hints=fresh"
  shoot duo-01-ready inner
  # Lift the lid: 178 → 135 over 1.5 s, hold, capture the stream crossing the fold.
  hinge_sweep 135 1.5; sleep 0.8; shoot duo-02-pouring inner
  hinge_sweep 120 1.0; sleep 0.6; shoot duo-03-pouring-steep inner
  hinge_sweep 176 1.0; sleep 2.5; shoot duo-04-served inner
  # Close the phone (cover display), reopen.
  hinge_sweep 40 2.0; hinge_set 0; sleep 3; shoot duo-05-closed cover
  hinge_sweep 170 2.5; sleep 3; shoot duo-06-reopened inner
  grep -E "BRIM-H" "$OUT_ABS/logs/hinge-1-1.txt" | head -3 >>"$RUNLOG"
  log "hinge lines in app log: $(grep -c 'BRIM-H' "$OUT_ABS/logs/hinge-1-1.txt")"
fi

# ---- pass: autopilot frames on the Duo canvas (store set) --------------------------------------------------
if [[ " $PASSES " == *" store "* ]]; then
  hinge_set 150 || true
  while IFS='|' read -r name args wait; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    launch "store-$name" "$args;orient=portrait"
    sleep "${wait:-8}"
    shoot "store-$name" inner
  done <<'EOF'
s1-midpour|mode=shift:1-2;autopilot=perfect;freezeOn=midpour|6
s2-perfect|mode=shift:1-4;autopilot=perfect;freezeOn=perfect;streak=4|10
s3-soda|mode=shift:2-2;autopilot=perfect;freezeOn=midpour|6
s4-shake|mode=shift:3-2;autopilot=perfect;freezeOn=midpour|6
s5-rush|mode=rush;autopilot=perfect;freezeOn=midpour;streak=9|8
s6-spill|mode=shift:1-3;autopilot=spill;freezeOn=spill|10
EOF
fi

# ---- pass: UI frames ---------------------------------------------------------------------------------------
if [[ " $PASSES " == *" ui "* ]]; then
  hinge_set 160 || true
  launch ui-menu "screen=menu;orient=portrait;duo"; shoot duo-ui-menu inner
  launch ui-venues "screen=venues;progress=mid;orient=portrait;duo"; shoot duo-ui-venues inner
  launch ui-results "mode=shift:1-1;screen=results;progress=mid;orient=portrait;duo"; shoot duo-ui-results inner
  # Book pose: no orient request, the sim's own landscape inner canvas → the "stand me up" card.
  launch ui-book "mode=shift:1-1;duo"; shoot duo-ui-book inner
  hinge_sweep 40 1.5; hinge_set 0; sleep 3; shoot duo-ui-cover cover
  hinge_set 170 || true
fi

ls -la "$OUT_ABS"
exit 0
