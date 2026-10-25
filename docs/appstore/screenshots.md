# Brim: App Store screenshot plan (v1.0)

*Owner: CI captures and captions, the launch lead writes captions, the founder approves. Every frame is the app's own rendering, captured by our CI from demo scenarios and captioned on the Mac runner: one workflow, `store.yml`, does all three sets (below). The scenarios and captions live in **`ci/store-scenarios.txt`**, which is the source of truth: change a caption there, not only here. The App Preview and the social clip storyboards are in `social-launch.md` §3.*

## Sets and sizes

| Set | Pixels (portrait) | Frames | Captured by (`store.yml`) | Artifact | Upload |
|---|---|---|---|---|---|
| **iPhone Duo, inner display** (the hero set) | **2007 × 2853** (the 669 × 951 pt tabletop canvas at 3×) | **6** (D1–D6) | job `duo`: `ci/duo.sh` store pass with `STORE_LIST=ci/store-scenarios.txt` | `store-duo` → `duo-screens/store/` | By hand in the web UI, **if** App Store Connect shows an iPhone Duo slot (`DECISIONS.md` #13) |
| **iPhone 6.9"** | **1320 × 2868** | **5** (P1–P5) | job `phones`: `ci/screenshots.sh` on the iPhone 18 Pro Max (fallback: newest `… Pro Max`) | `store-69` → `store-69/store/` | Web UI, "6.9-inch Display" |
| **iPhone 6.1" class** | **1179 × 2556** (or 1170 × 2532); **1206 × 2622** when the runner has no 6.1-inch simulator | **5** (P1–P5) | job `phones`: `ci/screenshots.sh` on the newest simulator with a 1179 × 2556 / 1170 × 2532 screen, else the iPhone 18 Pro (6.3") | `store-61` → `store-61/store/` | Web UI: 1179 × 2556 and 1206 × 2622 go in the **6.3-inch** slot, 1170 × 2532 in the **6.1-inch** slot. The MANIFEST header names the device used |

Rules: PNG or JPEG, **no alpha channel**, 1–10 per size. The first three frames of each set appear in search results, so **frames 1–3 must each sell the game alone**.

## Pipeline (`store.yml`, manual)

```bash
gh workflow run store.yml -R pravegm/brim --ref main                       # all three sets
gh workflow run store.yml -R pravegm/brim -f duo=false                      # phones only (no 8 GB runtime download)
gh run download <id> -R pravegm/brim -n store-69 -D <empty folder>          # or -n store-61 / -n store-duo
```

1. **Capture.** `ci/screenshots.sh` (phones) and `ci/duo.sh` (Duo, `PASSES=store`) launch each scenario with its demo keys; a `freezeOn=` scenario waits for the app's `BRIM-T freeze <x>` line before the screenshot. The app log at the moment of capture is kept as `logs/<name>.at-capture.txt`. Every simulator call has a timeout; a failed launch or screenshot is retried once and then skipped.
2. **Check.** `ci/store-set.sh` checks each capture against that log: the demo-starts line, the freeze line, `BRIM-T streak seeded n (asked m)` with n ≥ m, the optional `expect` regex, and on the Duo `BRIM-T orient portrait ok`. The raw capture must already be a slot size (a landscape Duo canvas or the wrong simulator is never letterboxed into a frame).
3. **Caption.** `ci/store-frame.swift` (compiled with `xcrun swiftc`, else run with `xcrun swift`) draws the frame at the exact slot size: brand background, caption on top, the screenshot inset below. Opaque sRGB PNG, no alpha.
4. **MANIFEST.** `<set>/store/MANIFEST.txt` lists every frame: output size, whether it matches the slot size, alpha, status (OK / FLAGGED / MISSING / FAILED), the caption, the cap height used and the app's freeze/streak lines. **Clean frames are in `store/`; a frame that failed a check is in `store/_flagged/`** (still framed, for review). The manifests are also in the run summary. One bad frame never fails the run.

**Fallback:** Apple accepts uncaptioned screenshots. If a captioned set is unusable, upload the raw captures (`<set>/<name>.png`, which are exact slot sizes) in the same order.

## Caption style (what `ci/store-frame.swift` draws)

- **Layout:** cream `#FFF4E2` → peach sweep with a soft gold glow. Caption band: the top 3–26% of the frame. Below it the **screenshot itself, unaltered**, scaled to fit (about 69% of the frame height), rounded corners, hairline edge, soft shadow. Because the caption sits above the screenshot, it can never cover the jug, the stream, the line, the glass or the Duo's crease band.
- **No device frame** is drawn on any set: a phone frame is never shown folded, and a Duo frame is a flat picture of its inner display.
- **Type:** SF Pro Rounded Heavy (the system font with the rounded design; plain system Heavy if unavailable, which the MANIFEST reports as `rounded=no`), ink `#2B2233`. Headline cap height starts at 4.6% of the image height and shrinks in 5% steps until it fits the band in ≤ 3 balanced lines (floor 3.0%; the MANIFEST prints the `cap=` used, so check it is ≥ 4%). **One** highlighted word, written `*word*` in `ci/store-scenarios.txt` (*in italics here*), drawn in ink on a brim-gold `#FFC23D` marker swash (gold text on cream is only 1.48:1, so never gold letters). Optional sub-line after ` / ` in SF Pro Rounded Semibold at ~46% (down to 36% to stay on one line), ink `#544760`.
- **Seven words maximum** per headline. No logo on any frame.

## A. iPhone Duo, inner display (2007 × 2853): 6 frames

Captioned frames: `duo-screens/store/<name>.png` in the `store-duo` artifact; raw captures `duo-screens/store-<name>.png`. Captured on the tabletop canvas (`;orient=portrait` added, hinge held at 150°).

| # | In-game moment | Caption: headline / sub-line | Scenario (`ci/store-scenarios.txt`) |
|---|---|---|---|
| **D1** | Lemonade Stand, shift 1-2: the jug tipped on the top half, the stream **crossing the fold**, glass ~60% to the line. The magic frame | **Lift the top half. *Pour.*** / *The fold is the jug.* | `D1-hero-pour` (`mode=shift:1-2;autopilot=perfect;freezeOn=midpour`) |
| **D2** | The glass judged Perfect: sparkle ring, PERFECT stamp, streak 4+ | **Stop *right* on the line.** / *Perfect: a ting, a sparkle, a streak.* | `D2-perfect-streak` (`mode=shift:1-4;…;freezeOn=perfect;streak=4`) |
| **D3** | Rush mid-pour, streak 9, multiplier showing | **Rush: keep the *streak* alive.** / *Perfects refill the jug. Up to ×5.* | `D3-rush` (`mode=rush;…;streak=9`) |
| **D4** | Soda Fountain: cola with a foam head climbing above the liquid | **Soda *foams*. Pour slowly.** / *Then top it up.* | `D4-soda-foam` (`mode=shift:2-2;…;freezeOn=midpour`) |
| **D5** | Milkshake Diner: a thick shake stream, still coming | **Thick shakes *keep* coming.** / *Stop early.* | `D5-shake` (`mode=shift:3-2;…;freezeOn=midpour`) |
| **D6** | Venues screen, mid progress: five venues, the sixth locked as "?" | **Five venues. One *secret*.** / *No ads. No in-app purchases.* | `D6-venues` (`screen=venues;progress=mid;duo`) |

Reserve (not captured by default; `duo_filter: ^D` adds it): `DR-spill`, **Too far? *Splash.*** / *Spills cost a strike.*

**Never upload from `duo-screens/`:** anything outside `store/` (raw captures, `raw/` panel probes), anything in `store/_flagged/` until reviewed. `duo.yml`'s own frames (`duo-01…06`, `duo-ui-cover`, `duo-ui-book`) are test frames.

**Optional later (1.0.1):** a 3D "store shot" of the Duo standing in tabletop pose with frame D1 on its screens, like Squish's `FoldStoreShot`, or a real photo of the Duo on a table. A flat inner frame shows the screen, not the lifted lid; the caption carries that until then.

## B. iPhone 6.9" (1320 × 2868) and 6.1" class (1179 × 2556 / 1206 × 2622): 5 frames each

Same frames and captions at both sizes. Captioned frames: `store-69/store/<name>.png`, `store-61/store/<name>.png`.

| # | In-game moment | Caption: headline / sub-line | Scenario (`ci/store-scenarios.txt`) |
|---|---|---|---|
| **P1** | Lemonade Stand mid-pour: jug tipped, stream falling, glass ~60% | **Tip the jug. Stop on the *line*.** / *Drag up to pour, on any iPhone.* | `P1-hero-pour` (`mode=shift:1-1;autopilot=perfect;freezeOn=midpour`) |
| **P2** | Perfect with a streak: sparkle ring and stamp, streak 4+ | **Right on the line. *Perfect.*** / *Then do it again.* | `P2-perfect-streak` (`mode=shift:1-4;…;freezeOn=perfect;streak=4`) |
| **P3** | Soda Fountain mid-pour: cola with a foam head | **Soda *foams*. Pour slowly.** / *Then top it up.* | `P3-soda-foam` (`mode=shift:2-1;…;freezeOn=midpour`) |
| **P4** | Rush mid-pour, streak 7, ×3 multiplier | **Rush: keep the *streak* alive.** / *Perfects refill the jug. Up to ×5.* | `P4-rush` (`mode=rush;…;streak=7`) |
| **P5** | Venues screen, mid progress, the secret one locked | **Five venues. One *secret*.** / *No ads. No in-app purchases.* | `P5-venues` (`screen=venues;progress=mid`) |

Reserves (not captured by default; `phone_filter: ^(P|R)[0-9]` adds them): `R1-daily` (**One *Daily Pour*. Same for everyone.** / *Ten glasses. One try. Share your row.*), `R2-shake` (**Thick shakes *keep* coming.**), `R3-spill` (**Too far? *Splash.***).

**Never upload:** anything outside `store/`, anything in `store/_flagged/` until reviewed, and nothing from `ci.yml`'s `screenshots` artifact (test and UI-check frames).

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
