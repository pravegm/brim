# Brim: Fold to Pour: round 4 sign-off (from frames)

*Reviewer: design critic. Date: 25 Oct 2026. This is the frame-only sign-off promised in REVIEW-3 §7. It is not a full round.*
*Inputs: `design/ROUND-4.md`, `design/QA-1.md`, and all 47 frames in `design/frames/final/`. Store sets are checked at slot size (6.9" 1320×2868, 6.1" 1179×2556, Duo 2007×2853, all 24-bit RGB with no alpha). Coordinates are in pt from the top-left of the canvas (Duo inner 669×951, crease band y 455–495; iPhone 402 wide).*

---

## 1. REVIEW-3 P1s

| # | Item | Verdict | Evidence |
|---|---|---|---|
| P1-1 | Waiting glass competes; "Fill to here" sits on it | **Fixed** | duo-00/01: the waiting glass is about 0.8 scale, lighter outline, no line or tab, plain coaster, sits about 10 pt lower. The pill is to the **right** of the tab (x about 455–565 pt), clear of both glasses. On iPhone (12-first-run) the pill sits **above** the rim ("Fill to here ▼"). Both frames now point at one glass. |
| P1-2 | Duo home stream drawn as beads | **Fixed** | duo-ui-menu is captured mid-pour: the jug is tipped and the orange stream is fat and continuous from the spout lip to the mug, with bubbles at the surface. P2-5 is fixed in the same frame: about 19 pt between the coaster and the buttons. |
| P1-3 | Venues row crosses the fold | **Fixed** | duo-ui-venues: the Lemonade card ends at about 339 pt and the Soda card starts at about 503 pt, so the crease falls in the gap. No button is on the band. |
| P1-4 | iPhone next glass hugs the bezel | **Fixed** | 02, 03, 04, 05, 07, 12, 13: the waiting glass is smaller, and its coaster stands about 30–35 pt clear of the edge, uncut. Where it doesn't fit (the wide mug in P2), it isn't drawn and shows as a HUD icon instead. That fallback causes the new P1 below. |

**Also verified closed:** P2-3 (the cover is opaque in duo-05, duo-08 and duo-ui-cover, with no ghosted jug) and P2-4 (the recap uses real glass shapes with a ✓ on each coaster).

**Still open, not blocking:** P2-1 (the shake stream still snakes in D5 and 06), P2-8 (the Perfect bloom still whitens the headspace in the P2 frames), and P2-12 (the 6.1" set has the Dynamic Island on P3–P5 but not on P1–P2).

**QA-1 P1s:** these are code and lifecycle fixes, so stills can't show them. I take them as fixed per ROUND-4. One quick manual pass on device covers them: Daily → Pause → Restart, rotating to book pose mid-shift, and 90 s of hinge-only play without dimming.

**Observation, not a finding:** duo-07 → duo-09 shows the strike count going from 0 to 1 across the close, with spill drops by the coaster. The CI log (`judged-between=0`) says this strike came before the close, but the stills alone read as "it struck me while shut". Capture duo-07 at the moment of the close so the evidence explains itself. The real-device close test (REVIEW-3 §7 condition 2) remains the actual gate.

---

## 2. New upload blockers

**P1-A. The 6.1" HUD cuts off the score when a streak is showing in a shift.**
- **What I see:** In 61-P2 the right cluster reads `×2 | 🔥5  ꞓ  ⏸`. The score "800" is clipped to a sliver of the "8" between the streak chip and Pause. 69-P2 (wider canvas) and 61-P4 (Rush, with a shorter left cluster) both fit.
- **Cause:** the left cluster in shift mode is 7 dots + the next-glass icon (the P1-4 fallback) + 3 cups. At 393 pt there isn't room, and the score is the element that gives way.
- **Who sees it:** every player on a 393-pt iPhone (the base 6.1" models, the most common width) once they build a streak with a 3-digit score. It is a game bug as well as a screenshot problem.
- **Fix:** in the HUD (`UI/PlayOverlays.swift`), give the score `layoutPriority(1)` and `fixedSize()` so it never truncates. Let the streak chip compress first: drop the `×N` half below about 400 pt wide. Fold the next-glass icon *into* the dots pill, replacing the next dot, instead of giving it its own chip. Check this at 375 pt (SE/mini width) with a score of "12,400" and a ×5 streak.

**P1-B. The streak pop overprints PERFECT in all three P2 frames, not only D2.**
- **What I see:** 69-P2 and 61-P2 show the same collision as D2: "×5 STREAK" is printed across "PERFECT".
- **Fix:** none needed in code; the fix you already have covers it. All three need the re-shoot.

---

## 3. Per-frame upload verdict

| Frame | Verdict | Note |
|---|---|---|
| 69-P1 hero pour | **Upload** | Clean. Coaster clear, stream fat. |
| 69-P2 perfect streak | **Re-shoot** | P1-B. |
| 69-P3 soda foam | **Upload** | |
| 69-P4 rush | **Upload** | "7 served" and "1,400" fit. |
| 69-P5 venues | **Upload** | |
| 61-P1 hero pour | **Upload** | |
| 61-P2 perfect streak | **Re-shoot** | P1-B, plus P1-A (score clipped). Re-shoot only after the P1-A fix. |
| 61-P3 soda foam | **Upload** | |
| 61-P4 rush | **Upload** | HUD fits. |
| 61-P5 venues | **Upload** | |
| D1 hero pour | **Upload** | The device's best frame. |
| D2 perfect streak | **Re-shoot** (do not upload as is, do not retouch) | P1-B. It is the #2 frame and its caption promises "a ting, a sparkle, a streak" over a garbled stamp. Re-shoot it from the fixed build; a hand-patched composite isn't what the build renders. |
| D3 rush | **Upload** | |
| D4 soda foam | **Upload** | |
| D5 shake | **Upload** | The snaking stream (P2-1) is acceptable. |
| D6 venues | **Drop** | Flat on a store page, without the fold visible, the deliberate crease gap between the cards (y 339–503 pt) reads as a broken layout. It also shows only 2 of the 5 venues it advertises. The "No ads. No in-app purchases." line stays in the iPhone sets and the description. |

**Re-shoot scope:** one CI run, after the P1-A HUD fix lands, covering 69-P2, 61-P2 and D2. If the 6.1" Dynamic Island toggle is cheap, make it consistent in the same run (P2-12).

**Upload order:**
- **6.9" and 6.1":** P1 hero → P2 perfect → P3 soda → P4 rush → P5 venues.
- **Duo:** D1 hero → D2 perfect → D4 soda → D5 shake → D3 rush. This puts three different looks in the first three slots shown in search.

**Fallback if CI minutes don't come back before submission:**
- Ship the 6.9" set as P1, P3, P4, P5.
- Don't upload the 6.1" set; App Store Connect scales 6.9" down.
- Ship the Duo set as D1, D4, D5, D3.
- Add the P2 frames with the next version.
- This is the worse option: screenshots can only change with a new submission, and Perfect is the second-best selling frame. Prefer waiting one CI run.

---

## 4. Final scores and launch call

| Area | R3 | **Final** | Why |
|---|---|---|---|
| (a) In-game, Duo | 8.5 | **8.8** | One clear target, a quiet waiting glass, the pill in open space, nothing on the fold. |
| (a) In-game, iPhone | 8 | **8.4** | The margins are fixed. Held back by P1-A until it is fixed; 8.6 after. |
| (b) UI / screens | 8 | **8.7** | A live attract pour, Venues off the crease, an opaque cover, a recap with real glasses and ✓ glyphs. |
| (c) Game design | 8.5 | **8.6** | The Short rule is documented, the Daily loophole is closed (per QA), and run state survives canvas changes. |
| (d) Juice (visible) | 8 | **8.3** | Strong as it was. The shake rope and the Perfect bloom are still P2. |
| **Overall** | 8.4 | **8.7** | Above the 8.5 bar. Once P1-A and the re-shoot are done, no P1 is open. |

**Launch call: Yes.** The four REVIEW-3 P1s are verified fixed in the frames.

Before submission:
1. Fix the 393-pt HUD (P1-A).
2. Re-shoot the three P2 frames.
3. Drop D6.

Submit with **manual release**. REVIEW-3 condition 2 still gates the release button: the real-Duo session with 10 mid-pour closes and zero strikes, a smooth 5 s hold, stop latency under about 80 ms, sound, and 3 of 5 novices reaching a Perfect inside 60 s. No further design round is needed.
