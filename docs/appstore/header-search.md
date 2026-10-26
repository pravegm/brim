# Brim: product page header and search results art

*Written 26 Oct 2026. Owner: CI draws them, the founder approves and uploads. Both are optional (Guideline 2.3.14, App Store on iOS 27 and later, turned on 5 Oct 2026). Brim 1.0 can ship with or without them; without them, search shows the first screenshots and the product page has no header.*

## What they are

| Placement | Where people see it | Brim's file | Size |
|---|---|---|---|
| **Product page header** | Across the top of Brim's product page, above the icon, the name and the Get button. On an iPhone in portrait it keeps its full height and loses about 8 % on each side; the back and share buttons sit over its top corners | `store-placements/header-3840x1646.png` | 3840 × 1646 (21:9), opaque PNG |
| **Search results art** | Brim's card in the Search tab, in place of the first three screenshots. Small: about 365 pt wide on an iPhone, next to other apps' cards. Shown whole on an iPhone | `store-placements/search-3840x2560.png` | 3840 × 2560 (3:2, the largest Apple takes), opaque PNG |

Brim is iPhone-only (`TARGETED_DEVICE_FAMILY` 1, Mac and Vision Pro availability off), so the iPhone views are the ones that matter. Apple's templates draw a smaller "safe area" in the middle (header x 1097–2743, y 493–1154; search x 836–3004, y 765–1795, as others measured them; Apple publishes no numbers) for other devices. Both designs put the **fold and the stream on that centre line**; the text sits inside the iPhone area but not all of it inside the template area. The MANIFEST reports both.

We make **two dedicated files**, not Apple's universal 5244 × 2950 asset, so each crop is designed rather than guessed.

## The designs

**Search results (3:2).** One idea at thumbnail size: an iPhone Duo standing on a table in the tabletop pose, drawn as a clean device (graphite frame, black glass, no logo, no buttons), with the real D1 frame on its two halves: the jug tipping on the raised half, the lemonade stream running down it, across the fold, into the glass on the flat half. To its left, in the screenshot captions' type (SF Pro Rounded Heavy, ink on cream, one word on the gold swash): the small Brim wordmark, **Lift to *pour.*** in two big lines and **Stop on the line.** under it. At 365 pt wide the headline is about 17 pt tall and the jug, stream and glass still read. The "trio" alternative (the same Duo smaller, with the D2 Perfect and D4 Soda frames as flat cards beside it) is in `review/search-trio.png`; it was rejected because at card size it is three small pictures instead of one clear one. Founder's call: the search card is seen by every iPhone user, and "Lift to pour" is the Duo control (other iPhones drag up). The picture shows a Duo, so the line is true of it; if you want a device-neutral line, re-render with `banner_args_search: --headline "Tip the jug. Stop on the *line.*" --sub "Lift the Duo, or drag up."` (check it at card size: it is longer).

**Product page header (21:9).** A brand banner with air: the Brim wordmark as the app draws it (Rounded Black, the glowing gold fill line, the cyan drip off the m) with **Fold to Pour** under it on the left; the same tabletop Duo pouring on the right, angled a little toward the words; the cream-to-peach sweep with a gold glow behind the device. No icon and no app name in the art (they sit right under it on the page), no headline that repeats the subtitle.

**Truthfulness.** The screen is the app's own D1 capture (Lemonade Stand, shift 1-2, autopilot, frozen mid-pour), only resampled and put in perspective; nothing is painted into the game. It is the **upright** capture: the top of the picture is on the raised half, the glass on the flat half, the same picture the store frames show (founder's rule: nothing upside down, ever; `ci/store-placements.sh` refuses any capture whose log shows `flip`, a turn-round or no portrait canvas, or whose store frame was flagged). "Lift to pour" is what Brim does on the Duo; on other iPhones it is drag-up, which the screenshots and the description say. No prices, no "#1", no awards, no URLs, no Apple logos or the "Made for iPhone Duo" badge, nothing for 4+ to worry about.

## How they're made

`store.yml` job **`placements`** (after the Duo pass, or on its own):

```bash
# Full store run: phones, Duo, then the placements from that Duo pass
gh workflow run store.yml -R pravegm/brim --ref main
# Placements only, from an earlier run's Duo captures (about 2 minutes, no capture, never cancels a capture run)
gh workflow run store.yml -R pravegm/brim --ref main -f phones=false -f duo=false -f placements_from=<run id>
gh run download <id> -R pravegm/brim -n store-placements -D <empty folder>
```

- `ci/store-placements.sh <duo-screens> <out>` picks the clean upright captures (hero `D1-hero-pour`; `D2`, `D4` for the trio review), runs `ci/store-banner.swift`, checks size and alpha with `sips`, checks the text stays inside the iPhone area and off the device, and writes `MANIFEST.txt`.
- `ci/store-banner.swift` (Core Graphics, Core Text, Core Image) builds the Duo with a small 3D model and a pinhole camera, splits the capture at the fold (row 1427 of 2853), Lanczos-scales each half and warps it onto its half of the screen. Knobs for iterating without editing defaults (store.yml inputs `banner_args_header` / `banner_args_search`): `--yaw`, `--elev`, `--tilt`, `--device`, `--hinge`, `--fold`, `--headline "Lift to *pour.*"`, `--sub`, `--cap`, `--frame 4A4350`, `--layout trio`, `--snaps <dir>`.
- `review/` (never upload): `*-guides.png` (red dashed = template safe area, blue = what an iPhone shows), `search-365pt@1x.png` and `@3x` (the card at real size), `header-402pt@3x.png`, `search-trio.png`.

**Current art: store run `40376904797`** (`store-placements` artifact, commit a7d6532; captures from store run 40363198536, commit 818fce5). It is `DEFAULT_PLACEMENTS_RUN` in `asc.yml`, which the `validate` job checks on every run. The founder signs it off by looking at it.

## Upload

### By API (preferred once the app record exists)

App Store Connect API 4.5 has the **App Asset Library** (`appAssetLibraryImages`, `appAssetLibraryPlacements`), and `tools/appstore/asc.swift` has a **`placements`** step for it:

1. `gh workflow run asc.yml -R pravegm/brim -f asc=true -f mode=plan -f only=placements -f placements_run=<store run id>`: read `plan.txt` (it lists the placement types and groups the API offers, then each placement it would make).
2. Same with `-f mode=push`. The tool uploads each PNG once as a `CREATIVE_ASSETS` image (reserve, PUT the parts, commit with `uploaded: true`, wait for `PREPARE_FOR_SUBMISSION`), then creates one placement of type `PRODUCT_PAGE_HEADER_ASSET` (header) and one of the search results type (developers report `APP_STORE_SEARCH_RESULTS_ASSET`; the tool reads the real IDs and groups from `GET /v1/appAssetLibraryRefData`) on the en-GB and en-US 1.0 version localizations. Re-running changes nothing; a new file replaces the old placement (placements can't be edited, so delete + create).
3. They go to App Review **with version 1.0**. After 1.0 is live, changing them needs either a new version or, as developers report, a separate review submission for the assets (`reviewSubmissions` + `reviewSubmissionItems`); the tool doesn't do that part.

Nothing has been pushed yet: the founder runs step 1 and 2.

### By hand (App Store Connect web)

1. App Store Connect → **Apps → Brim: Fold to Pour → (iOS App) 1.0 Prepare for Submission**.
2. Language menu (top right): **English (U.K.)**.
3. Scroll to **Product Page Header** (above "Previews and Screenshots"): **Choose File** (or drag) → `header-3840x1646.png`.
4. **Search Results** (the creative asset for search, same area): **Choose File** → `search-3840x2560.png`.
5. Open the **product page preview** (the "Preview" control by the media), look at the iPhone view: the header's sides are cropped about 8 %, the back and share buttons cover its top corners; nothing important should be under them. Then the search card.
6. **Save**. Switch the language menu to **English (U.S.)** and repeat 3–6 (same files: the text is spelling-neutral).
7. They are submitted with the version (**Add for Review → Submit to App Review**).

If the page shows the assets under a separate **Creative Assets** or **Asset Library** section instead (Apple has moved things around since 5 Oct), upload there and place them on the 1.0 page for both languages.

## Review notes

- Guideline 2.3.14: the art pertains to the app's content (it is gameplay) and brand, has no pricing, no references to other apps, no unverifiable claims, and is fine for all ages.
- Asset best practices: one focused idea, current UI, no URLs, no © symbol, no Apple-designated recognitions, no other platforms.
- The drawn device is a plain folding-phone silhouette: no Apple logo, no product name, no buttons, no badge. If App Review objects to it, remove the placements (or upload nothing): the search card falls back to the first three screenshots and the page simply has no header.
- The text is the same in en-GB and en-US ("Lift to pour.", "Stop on the line.", "Fold to Pour"), so one file serves both localizations.

## Later: a 5–30 s looping video version

Both placements also take video (header 3840 × 1646, search 3840 × 2560; 30 or 60 fps; 5–30 s; muted in search, loops in both). The idea: the same tabletop Duo, the camera still, the raised half **lifting** from flat to ~110° over 1 s, the jug tipping with it, the stream crossing the fold, the line glowing, a clean stop and the PERFECT stamp with its sparkle, then the glass slides away and the next one slides in, looping back to the start in 8–10 s. The text holds still on the left ("Lift to *pour.*"), so the poster frame (Apple takes the frame at 5 s) works alone. Make it from real captures: a `ci/duo.sh` pass that records the inner display (`simctl io recordVideo`) during `D1-hero-pour`, plus a hinge sweep for the lift, composited per frame by `store-banner.swift` (the camera and warp are already per-image).

## Sources

- App Store Connect Help, *Creative assets specifications* (sizes, formats, no alpha, video rules): https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications/
- *App Store asset best practices* (one idea, safe areas in the templates, do's and don'ts): https://developer.apple.com/app-store/asset-best-practices/
- App Review Guideline 2.3.14: https://developer.apple.com/app-store/review/guidelines/
- App Store Connect API, *Understanding the App Asset Library*, *Uploading and managing image assets*, *Placing assets on your App Store surfaces*, *Discovering asset specifications*: https://developer.apple.com/documentation/appstoreconnectapi/understanding-the-app-asset-library
- Safe-area measurements and the iPhone preview crop (not Apple's numbers): https://objectgraph.com/blog/ios-27-app-store-header-and-search-results-art/ and https://dev.to/teroxai/app-store-creative-assets-sizes-api-upload-and-review-231j
