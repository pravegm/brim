# Brim: App Store screenshot plan (v1.0)

*Owner: CI captures, the launch lead writes captions, the founder approves. Every frame is the app's own rendering, captured by our CI from demo scenarios (`ci/scenarios.txt`, `ci/duo.sh`). Captions are added afterwards. The App Preview and the social clip storyboards are in `social-launch.md` §3.*

## Sets and sizes

| Set | Pixels (portrait) | Frames | Captured by | Upload |
|---|---|---|---|---|
| **iPhone Duo, inner display** (the hero set) | **2007 × 2853** (the 669 × 951 pt tabletop canvas at 3×) | **6** | `duo.yml` → `ci/duo.sh`, passes `store` + `ui`, artifact `duo-screens` | By hand in the web UI, **if** App Store Connect shows an iPhone Duo slot (`DECISIONS.md` #13) |
| **iPhone 6.9"** | **1320 × 2868** | **5** | `ci/screenshots.sh` with `DEVICE="iPhone 18 Pro Max"` | Web UI, "6.9-inch Display" |
| **iPhone 6.1"** | **1206 × 2622** | **5** | `ci/screenshots.sh` with `DEVICE="iPhone 18 Pro"` (what `ci.yml` runs today), artifact `screenshots` | Web UI, "6.1-inch Display" (or whichever Dynamic Island medium slot App Store Connect asks for) |

Rules: PNG or JPEG, **no alpha channel**, 1–10 per size. The first three frames of each set appear in search results, so **frames 1–3 must each sell the game alone**.

**Two CI gaps (engineering, not founder; `DECISIONS.md` §3):**
1. `ci.yml` always captures on the iPhone 18 Pro. The 6.9" set needs one extra run with `DEVICE="iPhone 18 Pro Max"` (a workflow input or a small `store.yml`), plus a size check that fails if the frame isn't exactly 1320 × 2868 / 1206 × 2622 / 2007 × 2853.
2. Brim has no caption renderer yet. Port Squish's `ci/store-frame.swift` approach (caption band drawn on the Mac runner). **Fallback:** Apple accepts uncaptioned screenshots, so if captions aren't ready by code freeze, upload the raw frames in the order below; they still sell, because the pour itself is the picture.

## Caption style

- **Band:** the top ~18% of the frame, over the back-bar wall, so the jug, the stream, the crease band and the glass stay clear. On Duo frames the caption must **never cross the crease band** (the middle ~4% of the height).
- **Type:** SF Pro Rounded Heavy, ink `#2B2233` on cream `#FFF4E2`, headline cap height ≥ 4% of the image height. **One** highlighted word, shown *in italics here*, drawn in ink on a brim-gold `#FFC23D` marker swash (gold text on cream is only 1.48:1, so never gold letters). Optional sub-line in SF Pro Rounded Medium at ~45% size.
- **Seven words maximum** per headline. No logo on frames 2–6.

## A. iPhone Duo, inner display (2007 × 2853): 6 frames

Raw files are at `duo-screens/<name>.png` in the `duo-screens` artifact (`gh run download <id> -R pravegm/brim -D <empty folder>`).

| # | In-game moment | Caption: headline / sub-line | Scenario (`ci/duo.sh`) → file |
|---|---|---|---|
| **D1** | Lemonade Stand, shift 1-2: the jug tipped on the top half, the stream **crossing the fold**, glass ~60% to the line. The magic frame | **Lift the lid. *Pour.*** / *The fold is the jug.* | `store` pass `s1-midpour` (`mode=shift:1-2;autopilot=perfect;freezeOn=midpour`) → `store-s1-midpour.png` |
| **D2** | The glass judged Perfect: sparkle ring, PERFECT stamp, streak 4 | **Stop *right* on the line.** / *Perfect: a ting, a sparkle, a streak.* | `s2-perfect` (`mode=shift:1-4;…;freezeOn=perfect;streak=4`) → `store-s2-perfect.png` |
| **D3** | Rush mid-pour, streak 9, multiplier showing | **Rush: keep the *streak* alive.** / *Perfects refill the jug. Up to ×5.* | `s5-rush` (`mode=rush;…;streak=9`) → `store-s5-rush.png` |
| **D4** | Soda Fountain: cola with a foam head climbing above the liquid | **Soda *foams*. Pour slowly.** / *Then top it up.* | `s3-soda` (`mode=shift:2-2;…;freezeOn=midpour`) → `store-s3-soda.png` |
| **D5** | Milkshake Diner: a thick shake stream, still coming | **Thick shakes *keep* coming.** / *Stop early.* | `s4-shake` (`mode=shift:3-2;…;freezeOn=midpour`) → `store-s4-shake.png` |
| **D6** | Venues screen, mid progress: five venues, the sixth locked as "?" | **Five venues. One *secret*.** / *No ads. No in-app purchases.* | `ui` pass `ui-venues` (`screen=venues;progress=mid;orient=portrait;duo`) → `duo-ui-venues.png` |

Reserve (not uploaded unless one above fails): `store-s6-spill.png`, **Too far? *Splash.*** / *Spills cost a strike.*

**Never upload from `duo-screens/`:** `duo-01…06` (hinge-pass test frames, some taken mid-sweep), `duo-05-closed` / `duo-ui-cover` (outer display, wrong size), `duo-ui-book` (landscape), anything in `raw/`.

**Optional later (1.0.1):** a 3D "store shot" of the Duo standing in tabletop pose with frame D1 on its screens, like Squish's `FoldStoreShot`, or a real photo of the Duo on a table. A flat inner frame shows the screen, not the lifted lid; the caption carries that until then.

## B. iPhone 6.9" (1320 × 2868) and 6.1" (1206 × 2622): 5 frames each

Same frames and captions at both sizes. Files from `ci/screenshots.sh`: `<OUT>/<name>.png` (artifact `screenshots` for the 6.1" run).

| # | In-game moment | Caption: headline / sub-line | Scenario (`ci/scenarios.txt`) |
|---|---|---|---|
| **P1** | Lemonade Stand mid-pour: jug tipped, stream falling, glass ~60% | **Tip the jug. Stop on the *line*.** / *Drag up to pour, on any iPhone.* | `02-midpour` |
| **P2** | Perfect: sparkle ring and stamp | **Right on the line. *Perfect.*** / *Then do it again.* | `03-perfect` |
| **P3** | Rush mid-pour, streak 7, ×3 multiplier | **Rush: keep the *streak* alive.** / *Perfects refill the jug. Up to ×5.* | `07-rush` |
| **P4** | Daily Pour mid-pour | **One *Daily Pour*. Same for everyone.** / *Ten glasses. One try. Share your row.* | `13-daily` |
| **P5** | Venues screen, mid progress, the secret one locked | **Five venues. One *secret*.** / *No ads. No in-app purchases.* | `09-venues` |

Reserve: `05-soda-foam` (**Soda *foams*. Pour slowly.**), `06-shake` (**Thick shakes *keep* coming.**), `04-spill` (**Too far? *Splash.***).

**Never upload:** `01-menu`, `10-settings`, `11-standup`, `12-first-run`, `14-icon` (test and UI-check frames), `08-results` (unless its numbers are reviewed), and nothing from the hinge pass.

## Truthfulness rules (check every frame before upload)

- [ ] **Only what the app renders.** Every frame is an unedited capture from the app; captions sit on top and never cover the jug, stream, line or glass. No composited effects.
- [ ] **No hands, no people, no device photos** in the iPhone sets, and **never a non-folding iPhone drawn folded**.
- [ ] **Every caption is true of the build:** "Drag up" (P1) only if drag-up is the control; "Up to ×5" only if Rush's top multiplier is ×5; "Ten glasses. One try." only if the Daily is 10 glasses with one scored try; "Five venues. One secret." only if the venue screen shows 5 + a locked "?".
- [ ] **Seeded states are reachable states:** streak 4/7/9 and "mid progress" are numbers a real player reaches. Don't seed impossible scores or every venue unlocked.
- [ ] **The secret venue never appears** except as a locked "?". Never write "Sand Bar" on a frame.
- [ ] **No alcohol cues:** no amber drink with a white head in a pint-style glass, no root beer, no "shot" or "pint" labels on screen.
- [ ] **No prices, no dates, no "#1", no Apple logos or the "Made for iPhone Duo" badge** drawn into a frame (Guideline 2.3.7; Apple adds its own badge).
- [ ] **No stale hint text** that contradicts the caption (for example the first-run "Lift the top half to pour" on an iPhone frame).
- [ ] **Exact size, PNG, no alpha.** Captions readable at 25% zoom.

## Upload order and checks (founder, runbook §4.5)
1. 6.9" slot: P1–P5. 2. 6.1" slot: P1–P5. 3. If an **iPhone Duo** entry appears in the device list: D1–D6, then check them in App Store Connect's iPhone Duo preview tool. If there's no Duo entry, skip; the Duo set ships with 1.0.1 (screenshots can only change with a new version).

## Sources
- App Store Connect Help, *Screenshot specifications* (iPhone Duo inner 2007 × 2853; 6.9" 1320 × 2868; 6.1" class 1206 × 2622; 1–10 per size; no alpha): https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- Apple Developer Forums 845505 (Duo slot not yet in the selector or API, Oct 2026): https://developer.apple.com/forums/thread/845505
- App Review Guideline 2.3.7 (no prices in screenshots): https://developer.apple.com/app-store/review/guidelines/
- Squish's screenshot plan and sign-off (rules mirrored): `C:\Users\59527\Squish\docs\appstore\screenshots.md`, `DECISIONS.md` §3–4
