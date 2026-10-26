#!/usr/bin/env bash
# The two optional App Store creative assets (docs/appstore/header-search.md), drawn by ci/store-banner.swift from
# the Duo store pass's REAL upright captures:
#
#   bash ci/store-placements.sh <duo-screens dir> <out dir>
#   e.g. bash ci/store-placements.sh duo-screens store-placements
#
# Writes <out>/header-3840x1646.png (product page header, 21:9) and <out>/search-3840x2560.png (search results, 3:2),
# both opaque sRGB PNGs, plus <out>/MANIFEST.txt, and for review only <out>/review/: the same art with Apple's template
# safe areas drawn on (*-guides.png), the search asset at search-card size (365 pt wide at 1x and 3x) and the header at
# iPhone width, and the alternative layout (search-trio.png). Upload only the two files at the top of <out>.
#
# A capture is used only if it is upright and clean: <dir>/store-<name>.png (2007 x 2853) whose captioned frame passed
# every ci/store-set.sh check (<dir>/store/<name>.png exists, not store/_flagged/), and whose app log shows no flip, no
# turn-round and the portrait canvas (founder, 26 Oct: nothing upside down, ever). Hero: D1-hero-pour. Extras (trio
# layout only): D2-perfect-streak, D4-soda-foam.
# Never fails the job: always exits 0. Every problem is a MANIFEST line (and a ::warning:: in the Actions log).
# Env: STORE_BANNER_BIN (where the compiled renderer is cached; default $RUNNER_TEMP or $TMPDIR),
#      SOURCE_RUN (the run the captures came from, for the MANIFEST), BANNER_ARGS_SEARCH / BANNER_ARGS_HEADER (extra
#      store-banner options, e.g. "--yaw 12 --elev 25", for iterating without editing the defaults;
#      "--snaps store-placements/review/snaps" saves the canvas after each drawing stage).
set -uo pipefail

DIR="${1:?usage: store-placements.sh <duo-screens dir> <out dir>}"
OUT="${2:-store-placements}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/store-banner.swift"
CACHE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
BIN="${STORE_BANNER_BIN:-${CACHE%/}/brim-store-banner}"

mkdir -p "$OUT/review"
OUT="$(cd "$OUT" && pwd)"
rm -f "$OUT"/*.png "$OUT"/review/*.png
MANIFEST="$OUT/MANIFEST.txt"
: > "$MANIFEST"

to() {
  local s="$1"; shift
  if command -v gtimeout >/dev/null 2>&1; then gtimeout -k 5 "$s" "$@"
  elif command -v timeout >/dev/null 2>&1; then timeout -k 5 "$s" "$@"
  else perl -e 'alarm shift; exec @ARGV or die "exec failed: $!\n"' "$s" "$@"; fi
}
note() { echo "$*" | tee -a "$MANIFEST"; }
warn() { echo "::warning::store placements: $*"; }

png_info() {
  local out w h a
  out=$(to 20 sips -g pixelWidth -g pixelHeight -g hasAlpha "$1" 2>/dev/null || true)
  w=$(awk '/pixelWidth/ {print $2}' <<< "$out")
  h=$(awk '/pixelHeight/ {print $2}' <<< "$out")
  a=$(awk '/hasAlpha/ {print $2}' <<< "$out")
  if [[ -n "$w" && -n "$h" ]]; then echo "${w}x${h} alpha=${a:-?}"; else echo "? alpha=?"; fi
}

if [[ ! -x "$BIN" || "$SRC" -nt "$BIN" ]]; then
  if to 600 xcrun swiftc -O -swift-version 5 -module-name StoreBanner "$SRC" -o "$BIN" > "$OUT/review/store-banner-build.log" 2>&1; then
    echo "compiled ci/store-banner.swift -> $BIN"
  else
    echo "warning: could not compile ci/store-banner.swift; falling back to xcrun swift"
    tail -40 "$OUT/review/store-banner-build.log" || true
    BIN=""
  fi
fi
render() {
  if [[ -n "$BIN" ]]; then to 300 "$BIN" "$@"; else to 900 xcrun swift "$SRC" "$@"; fi
}

note "Brim App Store creative assets (product page header, search results)"
note "built: $(date -u '+%Y-%m-%d %H:%M UTC')  commit: ${GITHUB_SHA:-local}  run: ${GITHUB_RUN_ID:-local}  captures from run: ${SOURCE_RUN:-${GITHUB_RUN_ID:-local}}"
note "upload: the two PNGs at the top of this folder only. review/ = guides, thumbnails and the alternative layout."
note ""

# clean <name>: prints the path of an upright, clean 2007x2853 capture, or nothing (with the reason on stderr).
clean() {
  local name="$1" raw log info
  raw="$DIR/store-$name.png"
  [[ -f "$raw" ]] || raw="$DIR/raw/store-$name-inner.png"
  if [[ ! -f "$raw" ]]; then echo "no capture store-$name.png" >&2; return 1; fi
  info=$(png_info "$raw")
  [[ "${info%% *}" == "2007x2853" ]] || { echo "$raw is ${info%% *}, not the 2007x2853 tabletop canvas" >&2; return 1; }
  if [[ ! -f "$DIR/store/$name.png" ]]; then
    echo "its store frame is not clean (missing from store/, see store/MANIFEST.txt)" >&2; return 1
  fi
  log="$DIR/logs/store-$name.at-capture.txt"
  [[ -f "$log" ]] || log="$DIR/logs/store-$name.txt"
  [[ -f "$log" ]] || { echo "no app log for store-$name" >&2; return 1; }
  if grep -qE "BRIM-T (turned round 1|interface upside down 1)|upsideDown=1|BRIM-T (hint|intro card) turnRound|flip" "$log"; then
    echo "the app log shows flip or a turn-round (never upload an upside-down picture)" >&2; return 1
  fi
  grep -q "BRIM-T orient portrait ok" "$log" || { echo "no 'BRIM-T orient portrait ok' in the app log" >&2; return 1; }
  echo "$raw"
}

hero=$(clean D1-hero-pour 2>"$OUT/review/_why.txt") || hero=""
if [[ -z "$hero" ]]; then
  note "hero D1-hero-pour: NOT USABLE ($(cat "$OUT/review/_why.txt")). Nothing rendered."
  warn "hero capture D1-hero-pour not usable: $(cat "$OUT/review/_why.txt")"
  rm -f "$OUT/review/_why.txt"
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && { echo "### Store placements"; echo '```'; cat "$MANIFEST"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi
note "hero: $(basename "$hero") (D1-hero-pour: Lemonade Stand mid-pour, upright, clean store frame)"
extras=()
for x in D2-perfect-streak D4-soda-foam; do
  if p=$(clean "$x" 2>"$OUT/review/_why.txt"); then extras+=("$p"); note "extra: $(basename "$p")"
  else note "extra $x: skipped ($(cat "$OUT/review/_why.txt"))"; fi
done
rm -f "$OUT/review/_why.txt"
note ""
note "$(printf '%-26s %-10s %-6s %-7s %s' file size alpha status notes)"

ok=0; bad=0
# one <file> <WxH> <args…>: render, check size and alpha, write a MANIFEST line.
one() {
  local file="$1" want="$2"; shift 2
  local report status info dims alpha
  report=$(render "$@" --out "$OUT/$file" 2>&1); status=$?
  if (( status != 0 )) || [[ ! -f "$OUT/$file" ]]; then
    note "$(printf '%-26s %-10s %-6s %-7s %s' "$file" - - FAILED "store-banner exit $status: $(tail -3 <<< "$report" | tr '\n' ' ')")"
    warn "$file: store-banner failed: $(tail -1 <<< "$report")"
    bad=$((bad + 1)); return
  fi
  info=$(png_info "$OUT/$file"); dims="${info%% *}"; alpha="${info##*alpha=}"
  local problems=()
  [[ "$dims" == "$want" ]] || problems+=("is $dims, not $want")
  [[ "$alpha" == no ]] || problems+=("alpha=$alpha (App Store Connect rejects alpha)")
  grep -q "text-iphone=yes" <<< "$report" || problems+=("text reaches outside the area an iPhone shows")
  grep -q "overlap=no" <<< "$report" || problems+=("text touches the device")
  if (( ${#problems[@]} > 0 )); then
    local joined; joined=$(printf '%s; ' "${problems[@]}"); joined="${joined%; }"
    note "$(printf '%-26s %-10s %-6s %-7s %s' "$file" "$dims" "$alpha" FLAGGED "$joined")"
    warn "$file FLAGGED: $joined"; bad=$((bad + 1))
  else
    note "$(printf '%-26s %-10s %-6s %-7s %s' "$file" "$dims" "$alpha" OK "$(du -k "$OUT/$file" | cut -f1) KB")"
    ok=$((ok + 1))
  fi
  note "    $(grep -m1 '^store-banner:' <<< "$report" | sed "s#$OUT/##")"
}

# shellcheck disable=SC2086
one header-3840x1646.png 3840x1646 --kind header --hero "$hero" --guides "$OUT/review/header-guides.png" ${BANNER_ARGS_HEADER:-}
# shellcheck disable=SC2086
# shellcheck disable=SC2086
one search-3840x2560.png 3840x2560 --kind search --hero "$hero" --guides "$OUT/review/search-guides.png" ${BANNER_ARGS_SEARCH:-}

# Review only: the alternative search layout with two more real frames, and thumbnails at the size people see.
if (( ${#extras[@]} > 0 )); then
  list=$(IFS=,; echo "${extras[*]}")
  # shellcheck disable=SC2086
  render --kind search --layout trio --hero "$hero" --extras "$list" --out "$OUT/review/search-trio.png" ${BANNER_ARGS_SEARCH:-} > /dev/null 2>&1 \
    || warn "review/search-trio.png failed"
fi
thumb() { [[ -f "$1" ]] && to 30 sips --resampleWidth "$2" "$1" --out "$3" > /dev/null 2>&1; }

# Review only: BANNER_VARIANTS="name=--kind search --yaw 14; name2=--kind header --device 0.8" renders each into
# review/variant-<name>.png (and a 1206 px wide copy), so one run can compare several looks.
if [[ -n "${BANNER_VARIANTS:-}" ]]; then
  IFS=';' read -r -a variants <<< "$BANNER_VARIANTS"
  for v in "${variants[@]}"; do
    vname=$(sed 's/=.*//; s/[^A-Za-z0-9_-]//g' <<< "$v"); vargs="${v#*=}"
    [[ -n "$vname" && "$vargs" != "$v" ]] || continue
    # shellcheck disable=SC2086
    vrep=$(render --hero "$hero" --out "$OUT/review/variant-$vname.png" $vargs 2>&1) || warn "variant $vname failed: $(tail -1 <<< "$vrep")"
    note "variant $vname: $vargs"
    note "    $(grep -m1 '^store-banner:' <<< "$vrep" | sed "s#$OUT/##")"
    thumb "$OUT/review/variant-$vname.png" 1206 "$OUT/review/variant-$vname-1206.png"
  done
fi
thumb "$OUT/search-3840x2560.png" 365 "$OUT/review/search-365pt@1x.png"
thumb "$OUT/search-3840x2560.png" 1095 "$OUT/review/search-365pt@3x.png"
thumb "$OUT/review/search-trio.png" 365 "$OUT/review/search-trio-365pt@1x.png"
thumb "$OUT/header-3840x1646.png" 1206 "$OUT/review/header-402pt@3x.png"

note ""
note "summary: ok $ok  problems $bad"
note "before upload (docs/appstore/header-search.md): eyeball both at full size and at review/ thumbnail size, then check"
note "them in App Store Connect's product page preview (crops differ by device). No prices, URLs, awards or badges."

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  { echo "### Store placements (header, search results)"; echo '```'; cat "$MANIFEST"; echo '```'; } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
fi
ls -la "$OUT" "$OUT/review" 2>/dev/null || true
exit 0
