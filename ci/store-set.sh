#!/usr/bin/env bash
# Assemble one App Store screenshot set from a capture folder (ci/screenshots.sh or ci/duo.sh output):
# frame every scenario of ci/store-scenarios.txt that matches <filter> under its caption (ci/store-frame.swift) and
# write <dir>/store/<name>.png plus <dir>/store/MANIFEST.txt.
#
#   bash ci/store-set.sh <dir> <label> "<slot sizes>" [scenarios] [filter] [raw prefix]
#   e.g. bash ci/store-set.sh store-69 'iPhone 6.9"' "1320x2868" ci/store-scenarios.txt '^P[0-9]'
#        bash ci/store-set.sh duo-screens 'iPhone Duo inner' "2007x2853" ci/store-scenarios.txt '^D[0-9]' store-
#
#  <slot sizes>  the WxH sizes App Store Connect accepts for this slot, space separated. The captioned frame is made at
#                the raw capture's size when that is one of them; a raw capture of any other size (wrong device, a
#                landscape Duo canvas) is FLAGGED and not framed.
#  raw prefix    ci/duo.sh names store captures store-<name>.png (logs/store-<name>.txt); ci/screenshots.sh uses none.
#
# Per frame, against the app log snapshotted at capture (logs/<prefix><name>.at-capture.txt, else logs/<prefix><name>.txt):
#   the "BRIM-T demo '…' starts" line; "BRIM-T freeze <x>" for freezeOn=<x>; "BRIM-T streak seeded <n> (asked <m>)"
#   with n >= m for streak=<m>; the scenario's expect regex (5th column); $REQUIRE_LOG if set (the Duo job:
#   "BRIM-T orient portrait ok"). A frame that fails a check is still framed but goes to store/_flagged/, so store/
#   holds only clean frames. Output size and alpha are checked with sips.
# Never fails the job: always exits 0. Every problem is a MANIFEST line (and a ::warning:: in the Actions log).
# Env: STORE_RADIUS (screenshot corner radius as a fraction of its width, default 0.08), REQUIRE_LOG (regex),
#      STORE_FRAME_BIN (where the compiled compositor is cached; default $RUNNER_TEMP or $TMPDIR).
set -uo pipefail

DIR="${1:?usage: store-set.sh <dir> <label> <slot sizes> [scenarios] [filter] [raw prefix]}"
LABEL="${2:-store}"
SIZES="${3:?slot sizes, e.g. 1320x2868}"
SCEN="${4:-ci/store-scenarios.txt}"
FILTER="${5:-.}"
PREFIX="${6:-}"
RADIUS="${STORE_RADIUS:-0.08}"
REQUIRE_LOG="${REQUIRE_LOG:-}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/store-frame.swift"
CACHE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
BIN="${STORE_FRAME_BIN:-${CACHE%/}/brim-store-frame}"

mkdir -p "$DIR/store/_flagged" "$DIR/logs"
STORE="$(cd "$DIR/store" && pwd)"
rm -f "$STORE"/*.png "$STORE"/_flagged/*.png
MANIFEST="$STORE/MANIFEST.txt"
: > "$MANIFEST"

to() {
  local s="$1"; shift
  if command -v gtimeout >/dev/null 2>&1; then gtimeout -k 5 "$s" "$@"
  elif command -v timeout >/dev/null 2>&1; then timeout -k 5 "$s" "$@"
  else perl -e 'alarm shift; exec @ARGV or die "exec failed: $!\n"' "$s" "$@"; fi
}

note() { echo "$*" | tee -a "$MANIFEST"; }
warn() { echo "::warning::$LABEL: $*"; }

# png_info <file>: "WxH alpha=<yes|no|?>" via sips, or "? alpha=?".
png_info() {
  local out w h a
  out=$(to 20 sips -g pixelWidth -g pixelHeight -g hasAlpha "$1" 2>/dev/null || true)
  w=$(awk '/pixelWidth/ {print $2}' <<< "$out")
  h=$(awk '/pixelHeight/ {print $2}' <<< "$out")
  a=$(awk '/hasAlpha/ {print $2}' <<< "$out")
  if [[ -n "$w" && -n "$h" ]]; then echo "${w}x${h} alpha=${a:-?}"; else echo "? alpha=?"; fi
}

# The compositor: compiled once (cached across sets in one job), else interpreted with `xcrun swift`.
if [[ ! -x "$BIN" || "$SRC" -nt "$BIN" ]]; then
  if to 600 xcrun swiftc -O -swift-version 5 -module-name StoreFrame "$SRC" -o "$BIN" > "$DIR/logs/store-frame-build.log" 2>&1; then
    echo "compiled ci/store-frame.swift -> $BIN"
  else
    echo "warning: could not compile ci/store-frame.swift; falling back to xcrun swift"
    tail -30 "$DIR/logs/store-frame-build.log" || true
    BIN=""
  fi
fi
compose() {
  if [[ -n "$BIN" ]]; then to 180 "$BIN" "$@"; else to 600 xcrun swift "$SRC" "$@"; fi
}

device="(see the capture log)"
if [[ -f "$DIR/device.txt" ]]; then
  device="$(sed -n 's/^name=//p' "$DIR/device.txt") [$(sed -n 's/^resolved=//p' "$DIR/device.txt")]"
fi
note "Brim App Store set: $LABEL"
note "slot sizes: $SIZES   device: $device"
note "built: $(date -u '+%Y-%m-%d %H:%M UTC')  commit: ${GITHUB_SHA:-local}  run: ${GITHUB_RUN_ID:-local}"
note "upload: store/*.png only (in name order). store/_flagged/ = framed but a check failed: fix or eyeball first."
note ""
note "$(printf '%-24s %-10s %-5s %-6s %-8s %s' frame size slot alpha status notes)"

ok=0; flagged=0; missing=0
while IFS= read -r -u 3 line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  IFS='|' read -r name args wait caption expect <<< "$line"
  [[ -n "$name" && "$name" =~ $FILTER ]] || continue
  raw="$DIR/$PREFIX$name.png"
  applog="$DIR/logs/$PREFIX$name.at-capture.txt"
  [[ -f "$applog" ]] || applog="$DIR/logs/$PREFIX$name.txt"
  problems=()

  if [[ ! -f "$raw" ]]; then
    note "$(printf '%-24s %-10s %-5s %-6s %-8s %s' "$name.png" - no - MISSING "no capture $PREFIX$name.png (launch or screenshot failed; see the capture log)")"
    warn "$name MISSING (no capture)"
    missing=$((missing + 1))
    continue
  fi
  rawinfo=$(png_info "$raw")
  rawdims="${rawinfo%% *}"

  # Content checks against the app's log at capture.
  if [[ ! -f "$applog" ]]; then
    problems+=("no app log for this capture")
  else
    grep -q "BRIM-T demo '.*' starts" "$applog" || problems+=("no \"BRIM-T demo '…' starts\" line (demo args not applied?)")
    if [[ "$args" =~ freezeOn=([a-z]+) ]]; then
      fz="${BASH_REMATCH[1]}"
      grep -q "BRIM-T freeze $fz" "$applog" || problems+=("never froze on $fz before the capture")
    fi
    if [[ "$args" =~ streak=([0-9]+) ]]; then
      asked="${BASH_REMATCH[1]}"
      seeded=$(sed -nE 's/.*BRIM-T streak seeded ([0-9]+).*/\1/p' "$applog" | tail -1)
      if [[ -z "$seeded" ]]; then problems+=("no 'BRIM-T streak seeded' line (asked $asked)")
      elif (( seeded < asked )); then problems+=("streak seeded $seeded, asked $asked"); fi
    fi
    # Founder, 26 Oct: no store asset may ever be upside down. Store frames never use `flip`, and the app must never
    # have turned round (drawn or by iOS) or shown the one-time turn-round card before the capture.
    [[ "$args" == *flip* ]] && problems+=("demo args contain 'flip' (store frames are always upright)")
    if grep -qE "BRIM-T (turned round 1|interface upside down 1)|upsideDown=1|BRIM-T (hint|intro card) turnRound" "$applog"; then
      problems+=("the app turned round before the capture (upside-down frame)")
    fi
    if [[ -n "$expect" ]] && ! grep -qE "$expect" "$applog"; then problems+=("log has no line matching '$expect'"); fi
    if [[ -n "$REQUIRE_LOG" ]] && ! grep -qE "$REQUIRE_LOG" "$applog"; then problems+=("log has no line matching '$REQUIRE_LOG'"); fi
  fi
  facts=$(grep -oE "BRIM-T (freeze|streak seeded) .*" "$applog" 2>/dev/null | sed 's/^BRIM-T //' | tr '\n' ';' | sed 's/;$//; s/;/; /g')

  if [[ " $SIZES " != *" $rawdims "* ]]; then
    note "$(printf '%-24s %-10s %-5s %-6s %-8s %s' "$name.png" "$rawdims" no - FLAGGED "raw capture is $rawdims, not a slot size ($SIZES): not framed")"
    warn "$name raw capture is $rawdims, not one of $SIZES (not framed)"
    flagged=$((flagged + 1))
    continue
  fi

  dest="$STORE/$name.png"
  (( ${#problems[@]} > 0 )) && dest="$STORE/_flagged/$name.png"
  report=$(compose --in "$raw" --out "$dest" --size "$rawdims" --radius "$RADIUS" --caption "$caption" 2>&1)
  status=$?
  if (( status != 0 )) || [[ ! -f "$dest" ]]; then
    note "$(printf '%-24s %-10s %-5s %-6s %-8s %s' "$name.png" - no - FAILED "store-frame exit $status: $(tail -1 <<< "$report")")"
    warn "$name: store-frame failed ($(tail -1 <<< "$report"))"
    missing=$((missing + 1))
    continue
  fi
  outinfo=$(png_info "$dest")
  outdims="${outinfo%% *}"
  alpha="${outinfo##*alpha=}"
  match=no
  [[ " $SIZES " == *" $outdims "* ]] && match=yes
  [[ "$match" == yes ]] || problems+=("output is $outdims, not a slot size")
  [[ "$alpha" == no ]] || problems+=("output alpha=$alpha (App Store Connect rejects alpha)")
  cap=$(grep -oE 'cap=[0-9.]+%' <<< "$report" | head -1)
  rounded=$(grep -oE 'rounded=(yes|no)' <<< "$report" | head -1)
  if (( ${#problems[@]} > 0 )); then
    if [[ "$dest" == "$STORE/$name.png" ]]; then mv -f "$dest" "$STORE/_flagged/$name.png"; fi
    joined=$(printf '%s; ' "${problems[@]}"); joined="${joined%; }"
    note "$(printf '%-24s %-10s %-5s %-6s %-8s %s' "_flagged/$name.png" "$outdims" "$match" "$alpha" FLAGGED "$joined")"
    warn "$name FLAGGED: $joined"
    flagged=$((flagged + 1))
  else
    note "$(printf '%-24s %-10s %-5s %-6s %-8s %s' "$name.png" "$outdims" "$match" "$alpha" OK "raw $rawdims; $cap $rounded")"
    ok=$((ok + 1))
  fi
  note "    caption: $caption"
  [[ -n "$facts" ]] && note "    app log: $facts"
done 3< "$SCEN"

note ""
note "summary: ok $ok  flagged $flagged  missing $missing"
note "before upload (manual, docs/appstore/screenshots.md): eyeball every frame. The checks read the app log, not the"
note "picture: the stream must be in the air, the caption must be true of the frame, no stale hint text, no alcohol cues."

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  { echo "### $LABEL"; echo '```'; cat "$MANIFEST"; echo '```'; } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
fi
ls -la "$STORE" "$STORE/_flagged" 2>/dev/null || true
exit 0
