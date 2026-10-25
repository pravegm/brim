# Brim: Fold to Pour — design review, round 3

*Reviewer: design critic (premium mobile games). Date: 25 Oct 2026.*
*Inputs: `design/GAME-DESIGN.md`, `design/REVIEW-1.md`, `design/REVIEW-2.md`, `design/ROUND-3.md`; all 22 frames in `design/frames/duo3/` (real iPhone Duo simulator: inner 2007×2853, cover 1398×2034, book card 2853×2007) and all 15 in `design/frames/r3/` (iPhone 18 Pro, 1206×2622, scenarios in `ci/scenarios.txt`); code spot-checked in `Brim/UI/PlayOverlays.swift`, `Brim/UI/PoseCards.swift`, `Brim/Core/CoreTuning.swift`, `Brim/Core/GameSession.swift`.*
*CI facts taken as given (not visible in stills): 128/128 unit tests pass; Duo close-mid-pour check `CLOSE-GUARD autopause@31 resume@55 judged-between=0 PASS`; the one spill in that run was a legit 3 s held pour before the close. The streak-pop/PERFECT overlap in `store-s2-perfect` is already fixed after capture and is not re-reported.*
*Coordinates: **pt from the top-left of the canvas** (Duo inner 669×951, crease band y 455–495; iPhone 402×874).*

---

## 1. Scores

| Area | R1 | R2 | **R3** | One-line reason |
|---|---|---|---|---|
| (a) In-game frame, **Duo** | — | 7.5 | **8.5 / 10** | The magic frame is now centred and fat: glass centre ~366 pt (was 414), stream ~21 pt with dark edge and bright core, a lidded jug, a next glass waiting on the left, nothing on the hinge. Held back by a waiting glass that competes with the real one (and gets the "Fill to here" pill). |
| (a) In-game frame, **iPhone** | 4.5 | 7.5 | **8 / 10** | Props clear the HUD, no truncation, signature vessels and the mint Diner read well. But the next glass hugs the bezel (4 pt margin) with its coaster clipped in 6 of 8 play frames. |
| (b) UI / screens | 6 | 7 | **8 / 10** | Duo home is a clean bottom row, Duo results finally use the counter, honest copy, book card split on the fold, cover calm. Open: Venues buttons on the crease, a bead-chain "stream" on the Duo home, a small flat-style recap. |
| (c) Game design | 6.5 | 7.5 | **8.5 / 10** | The closing guard is designed properly (three layers + CI proof) and the reopen state is right ("Lay it flat to carry on", strike count unchanged). The next-glass preview and the patience ring add real information. One rules question: shorts are strikes in shifts. |
| (d) Satisfaction / juice (visible) | 4 | 7 | **8 / 10** | Streams now match the icon's language; Perfect is a firework; spill has opaque sheets and spray. Not yet seen in focus: the grown puddle. The shake stream wiggles like a ribbon instead of falling like a rope. |
| **Overall** | 5 | 7.5 | **8.4 / 10** | It now looks like a finished, premium, Duo-native game. The P0 is closed. Four cheap P1s (all layout) stand between it and the 8.5 / no-P1 bar. |

---

## 2. Status of the REVIEW-2 top 8

| # | Item | Status | Evidence / what's left |
|---|---|---|---|
| 1 | Closing guard (P0-1) | **Fixed** (real device pending) | duo-07 pouring at 140° → duo-08 cover: the ghosted scene behind the cover shows the jug **upright, no stream** → duo-09 reopen at 150°: "Lay it flat to carry on / Then lift the top half to pour" with an angled-lid glyph, a fresh glass, HUD strike count unchanged (1, from the pre-close overfill). CI: `judged-between=0 PASS`. |
| 2 | Centre the pour; use the left; home buttons | **Fixed** (follow-ups P1-1, P1-4) | Active glass x 309–423 pt (centre ~366), next glass x 107–221 pt (centre ~164) on its own coaster; the flat half is balanced. Duo home: one 4-button row at y 858–925 pt, clear of the glass. |
| 3 | Crease keep-out | **Mostly fixed** (P1-3) | No text, stamp, pop, hint or card on the band in any play frame: gate card 231–407 pt, PERFECT 537–609 pt, SPILL! 561–618 pt; the jug at rest ends at ~445 pt and only enters the band while tipped (allowed). Book card split: art on the left page, text from ~520 pt. **Left:** Venues (P1-3). |
| 4 | Fat, opaque, connected stream | **Fixed** (polish P2-1) | ~21 pt at a typical pour, darker edge + white core, saturated water `#7CC8F2`-ish (duo-02, r3/02, r3/07 — no longer the weakest frames), liquid visible in the spout channel (store-s3). Shake is wider, but it snakes ±20 pt. |
| 5 | Spill and puddle lifecycle | **Mostly fixed** (unverified grown puddle) | store-s6 / r3/04: opaque ~12 pt sheets on both walls, spray, no ghost tongue, jug still pouring under SPILL!. duo-09: the earlier puddle is gone after the glass left. No in-focus frame shows the 2–3× puddle (only the faded one behind the cover in duo-08, ~1.4× the coaster). |
| 6 | Signature vessels, Diner contrast | **Fixed** | Soda: red dispenser with chrome bands and a flat chrome lid (store-s3). Diner: brushed-steel tin with a pink sight window, on a mint speckled formica counter; pink now pops (store-s4, r3/06). Potion/Sand not shown. |
| 7 | Duo results on the counter, honest copy | **Fixed** (polish P2-4) | duo-06 / duo-ui-results: recap glasses stand on the flat half at their true levels with coloured coasters; "Not quite" with no NEW BEST on a failed run; "Flawless shift!" with 3 buttons in one row. |
| 8 | iPhone HUD polish | **Fixed** | "✓ 7" (r3/07) and "9 served" (store-s5) — no truncation; streak uses a flame-drop, not ★; shelf props sit below the HUD (r3/05, r3/06); stand-up card buttons stacked, "Turn the screen" whole (r3/11). |

R2 P2s: fixed — P2-2 (gate glyph now an angled lid in duo-09), P2-4, P2-5 (handles mirrored left, tab clear), P2-6, P2-7, P2-9 (faint cyan strip before pouring), P2-10. Still open — P2-3 (flat half doesn't react to the lift), P2-8 (attract tail, now worse: P1-2), P2-11 (now P1-3).

---

## 3. What works now (keep; don't touch)

1. **The Duo hero frame** (store-s1, duo-02, store-s3, store-s5): a centred, lidded jug tipping on the raised half, a fat glossy stream crossing the counter edge that *is* the hinge, into a glass that sits in the middle of the flat half. This is the screenshot that sells the device.
2. **The closing-guard UX**: no stream on close, a calm cover, and a reopen card that says exactly what to do. That's how a hardware game should treat its hardware.
3. **Signature vessels per venue** — the chrome soda dispenser and the steel shake tin with a sight window make five screenshots that look like five places.
4. **The Perfect beat** (store-s2, r3/03) and the **Rush/Daily dressing** (string lights, tear-off DAILY #297 calendar, green patience ring on the coaster).
5. **Duo results on the counter** — the served glasses lined up at their levels is the right idea and reads in a second.
6. **Copy discipline**: "Lay it flat to start", "Lift the top half to pour.", "Lay it flat to carry on", "Open me to pour", "Drag up to pour." One voice everywhere.

---

## 4. Ranked issues

### P0 — would embarrass at launch

None open. (P0-1 is closed in software; the real-device check is a launch condition, section 7.)

### P1 — clearly hurts

**P1-1. The waiting glass competes with the real one, and the first hint points from it.**
- *What I see:* duo-00/duo-01, store-s3, r3/12: the next glass is drawn at full size, full opacity, on an identical coaster, the same distance from the centre as the active glass. In the first-run frame two identical empty tumblers stand side by side and the gold **"Fill to here ▶" pill sits on top of the waiting glass** (duo-01: pill x 181–290 pt, y ~727; waiting glass x 107–221 pt; r3/12: pill x 44–155 pt over the waiting glass x 2–109 pt). The arrow points at the right line, but the label is literally on the wrong glass — in the one frame whose job is to say "this one".
- *Why (code):* `FillToHereCallout` (`UI/PlayOverlays.swift` ~l.313–318) picks the side with more room and has no idea the waiting glass exists (`GameScene.waitingGlassWorldFrame` is never consulted).
- *Fix:* (a) `Scene/SceneGlass.swift`: draw the waiting glass as *waiting* — 0.82 scale, ~60 % opacity or 30 % desaturated, no fill line or tab, a plain coaster, 8–12 pt lower; it brightens and grows as it slides to the stop. (b) `UI/PlayOverlays.swift`: pass the waiting frame in `PlayAnchors`; treat it as occupied. On the Duo put the pill to the **right** of the tab (room from ~470 to 653 pt fits 128 pt), on iPhone put it *above* the rim, never over the waiting glass. (c) Optional: hide the waiting glass until the first glass is served on `hints=fresh`.

**P1-2. Duo home: the attract stream is a chain of identical beads falling from an upright jug.**
- *What I see:* duo-ui-menu: the jug is upright (no tilt), yet a vertical column of ~17 evenly spaced, identical orange beads runs from x ≈ 364 pt, y ≈ 385 pt (mid-air beside the spout) down into the mug at ~685 pt. It reads as a dotted line or a bug, not liquid, and breaks pillar 2 on the first screen of every launch. (The iPhone home, r3/01, caught a real stream, so it's capture timing + drop art.)
- *Fix:* `Scene/SceneStream.swift`: the tail after the jug rights should be 3–6 drops, varied in size (60–100 %), with ballistic spacing that grows as they fall, starting from the spout lip, gone within ~0.4 s. `App/DemoMode.swift`: the menu capture waits for flow > 0 (mid-pour), like `freezeOn=midpour`. Re-shoot duo-ui-menu.

**P1-3. Venues on the Duo: a row of level buttons straddles the fold.**
- *What I see:* duo-ui-venues: the Soda Fountain row 1 (levels 1–4) spans y 447–502 pt, centred on the crease band (455–495). This was R2 P2-11 and is now an explicit violation of ROUND-3 decision 3 ("no button may cross the crease band"). On a Duo at 150° those are the buttons a player taps next.
- *Fix:* `UI/VenuesView.swift`: on `hasFold`, lay out the first screen as two pages — venue 1's card fills the top half (ends ≤ 447 pt), venue 2's card starts ≥ 503 pt — or insert a spacer sized from `info.bottomHalfTop` so the crease always falls in a gap between cards at the initial scroll position. Snap scrolling to card boundaries so it never comes to rest with a row on the fold.

**P1-4. iPhone: the next glass hugs the bezel and its coaster is cut off.**
- *What I see:* r3/02, 03, 04, 05, 07, 13: the waiting glass's left wall sits ~2–4 pt from the screen edge and its coaster is clipped (r3/13: the mason jar at x 2–129 pt; r3/07: tumbler at x 3–109 pt). Six of the eight iPhone play frames — i.e. most of the iPhone store set — look mis-cropped.
- *Why (code):* `CoreTuning.nextGlassEdgeMargin = 4`, measured to the glass, not the coaster (`GameSession.swift` ~l.1135).
- *Fix:* `Core/CoreTuning.swift` + `GameSession.swift`: margin ≥ 16 pt to the **coaster's** outer edge; on `!hasFold` draw it at 0.75 scale (it's information, not a target). If it still doesn't fit (narrow phones, wide glasses), don't draw it; show the next glass as a small icon in the HUD dots row instead. Re-shoot r3/02–07, 13.

### P2 — polish

- **P2-1 Shake stream snakes like a ribbon** (store-s4, r3/06: ±20 pt lateral waves). Thick liquids fall as a straight, slightly tapering rope that **coils on landing** (the coil at the surface is right). Cap lateral wobble at ~3 pt and express viscosity through width pulsing and a slower, lumpier landing. `Scene/SceneStream.swift`.
- **P2-2 Hints at the bottom of the Duo sit on the coasters, half-transparent** (duo-02: "Lay it flat just before the line…" at y 827–875 pt over both coasters; duo-03: "A little earlier next time…" at 862–914 pt). On the Duo the top-right of the raised half (where the flat-gate card lives, ~x 400–640, y 240–400 pt) is free during a pour: put stop/anticipate hints there. Also, the faded "Fill to here" pill lingering mid-pour (duo-02) should be gone once the level passes 30 %. `UI/PlayOverlays.swift` (`HintSpot`).
- **P2-3 Cover display shows the live scene through it** (duo-05: a ghosted, *tipped* jug behind "Brim"; duo-08: a ghosted overflowing glass and puddle). duo-ui-cover is clean, so it's the translucent gradient (`BrimTheme.peach.opacity(0.75)` in `CoverView`, `UI/PoseCards.swift`) or the cross-fade. A tipped jug on the cover reads as "it's pouring while shut" — the exact worry the P0 fixed. Make the cover background opaque.
- **P2-4 Results recap polish.** Glasses are ~64 pt wide flat icons (no gloss, all the same tumbler) — a different art language from the scene; coloured coasters are the only verdict cue (red/orange/blue — not colour-blind safe); duo-04 shows the results card with an *empty* counter and a ghost glass (the recap arrives late); a ghost of the tipped jug still peeks under the card (duo-04/06, y ~360–450 pt). Render the recap with the real glass shapes at ~85 pt, add a tiny glyph on each coaster (✓ / drop / ↓), slide them in within 0.3 s of the card, clean counter behind the card. `UI/ResultsView.swift`.
- **P2-5 Home: the mug's coaster kisses the button row** (duo-ui-menu: coaster bottom ~863 pt vs buttons top ~858; r3/01 the same). Keep ≥ 12 pt clear; derive it from the glass frame. `UI/HomeView.swift`.
- **P2-6 Book card balance** (duo-ui-book): the text column runs to ~20 pt from the right edge while the left page is mostly empty; the drawing is a diagonal phone, not the pose. Centre each column in its page with ≥ 32 pt margins, and reuse the tabletop drawing from r3/11 (it's clearer). `UI/PoseCards.swift`.
- **P2-7 Soda marble veins** (store-s3, r3/05) are scribbly dark lines that show *through* the glasses and read as cracks. Fewer, softer, lower-contrast veins, none behind the glass stop. `Scene/SceneArt.swift` / `ScenePalette.swift`.
- **P2-8 Perfect glow fills the glass headspace with white** (store-s2, r3/03): for a beat the glass looks full of milk above the line. Clip the white bloom to outside the glass or drop its alpha inside to ≤ 25 %. `Scene/SceneGlass.swift`.
- **P2-9 The flat half still doesn't react to the lift** (R2 P2-3): a soft shadow under the crease that deepens with tilt sells "the top half is up", in hand and in the App Preview video. `GameScene` / `SceneArt`.
- **P2-10 Spill sheet covers the fill tab** (store-s6, r3/04: the tab is half hidden behind the right sheet). Draw the tab above the sheets. `SceneGlass`.
- **P2-11 Rules vs bible: shorts are strikes in shifts** (`GameSession.swift` l.975–981: shifts and Daily strike on `.spill || .short`; GAME-DESIGN §5 says Short only resets the streak). duo-06 ends a first shift on 2 spills + 1 short, right after the hint told the player to "stop a little earlier". Either update the bible, or don't strike shorts in Lemonade Stand 1–2 so the first lesson ("stop early") isn't punished as hard as the opposite mistake.
- **P2-12 Capture consistency**: the Dynamic Island is drawn in r3/06, r3/10 and r3/13 but not in the others. Pick one for the store set. CI capture script.
- **P2-13 Icon vs game jug**: the icon is a solid, gradient teal mug without outline; the game's hero is an outlined glass pitcher with a lid and lemon roundel. Both are good; they don't look like the same object. Consider an icon jug with the lid knob and glass body so the store page reads as one product. `UI/AppIconArt.swift`.

---

## 5. Risks only a real Duo can settle

| Risk | Why it matters | How to check (TestFlight) |
|---|---|---|
| **Closing guard at real speeds** | Real closes are 0.3–0.8 s with a ~5° sensor and the `.closed`-at-~85° quirk; CI drives a clean simulated sweep. | Close the phone 10 times mid-pour at different speeds and from 120–160°. Zero new strikes, zero level change > 2 % of capacity, the "carry on" card every time. |
| **Hinge feel and the new hold stabiliser** | ±5° hinge × 1.55 gain; a stabiliser that filters harder at rest can add lag at the exact moment you lay it flat to stop. | Hold at ~150° for 5 s (stream width and level rise must be smooth); then do 10 fast "stop" flicks — the stream must cut within ~80 ms of the lid reaching flat. Log tilt σ and stop latency. |
| **Seeing the stream cross the fold** | At 120–140° the raised half is foreshortened; the stream may look kinked at the seam and the tipped jug's corner sits on the crease. | Photograph/screen-record from a seated eye position. If the stream kinks, add a 6–10 pt splash/blur where it crosses the seam. |
| **Sound** | Rising pitch, the band shimmer, Perfect tings climbing the scale, the autopause whoosh — the satisfaction core and invisible here. | 60 s of shift 1-1 with sound: the shimmer must lead the line; streak tings must climb; the whoosh on close must be soft, and nothing plays on reopen until armed. |
| **Haptics** | Glug transients, lock-in tick vs Perfect double tap within ~0.3 s, the spill buzz. | Do lock-in → Perfect read as two beats? If not, drop lock-in when a verdict follows within 0.25 s. |
| **First 60 seconds** | The launch promise: a novice pours in 10 s and hits a Perfect in a minute. P1-1 directly affects this. | 5 people who've never seen it, no explanation: 4/5 pour within 10 s, 3/5 Perfect within 60 s, nobody pours "at" the waiting glass. |
| **Hand and hinge comfort** | Pillar 5: a 2-minute Rush is many lifts. | Two Rush runs back to back: any wrist strain, any urge to slam? |
| **Performance** | Glow, particles, 120 Hz on the inner panel. | Instruments in Rush tier 3: no frame > 8.3 ms at 120 Hz (16 ms worst case). |

---

## 6. Top fixes for the final polish round (in order)

1. **Waiting glass hierarchy + "Fill to here" placement (P1-1).** Smaller, dimmer, no line; callout avoids it. *Files:* `Scene/SceneGlass.swift`, `UI/PlayOverlays.swift`, `Scene/GameScene.swift` (anchors).
2. **iPhone next-glass margin (P1-4).** ≥ 16 pt to the coaster, 0.75 scale, hide if it doesn't fit. *Files:* `Core/CoreTuning.swift`, `Core/GameSession.swift`.
3. **Venues off the crease (P1-3).** Two-page first screen / snap. *File:* `UI/VenuesView.swift`.
4. **Attract tail + menu capture (P1-2).** Real drops, mid-pour capture. *Files:* `Scene/SceneStream.swift`, `App/DemoMode.swift`.
5. **Opaque cover (P2-3)** and **hints off the coasters (P2-2).** *Files:* `UI/PoseCards.swift`, `UI/PlayOverlays.swift`.
6. **Shake falls straight (P2-1)** and **Perfect bloom outside the glass (P2-8).** *Files:* `Scene/SceneStream.swift`, `Scene/SceneGlass.swift`.
7. **Results recap with real glass shapes + glyphs (P2-4)**, home coaster clearance (P2-5). *Files:* `UI/ResultsView.swift`, `UI/HomeView.swift`.
8. **Re-shoot** both store sets after 1–4, plus one in-focus "spill + 0.6 s" frame to prove the grown puddle; pick DI on/off consistently (P2-12).

---

## 7. Launch call

**Yes, conditionally.** At £1.99 on the Duo this belongs on the shelf next to Alto and Threes: one idea, physically true, beautifully dressed, no IAP, no ads, no data — and an idea that only exists on this device. That is exactly the "made for the new hardware" story Apple's editors feature at a device launch; the hero frame (store-s1 / store-s3) is feature-art quality today. On non-folding iPhones it's a good, honest pouring game rather than a Threes-level classic, which is fine: the Duo is the product, the iPhone keeps it reviewable and useful.

It is not an unconditional yes yet because the bar in GAME-DESIGN §11 is ≥ 8.5 with **no open P1**, and four P1s are open. All four are layout fixes measured in hours, not redesigns.

**Conditions:**
1. **P1-1…P1-4 fixed** and the Duo + iPhone frames re-shot (home, first-run, all play frames, Venues). I'll sign off from those frames alone; no full round 4 is needed for the P2s.
2. **Real-device session on the TestFlight Duo** (section 5): 10 mid-pour closes with zero strikes, a smooth stream at a 5 s hold, stop latency < ~80 ms, sound shimmer leading the line, and 3 of 5 novices hitting a Perfect inside 60 s.
3. **Store kit uses the re-shot frames**, including one in-focus spill-puddle frame, and an App Preview video shot on a real Duo (the hinge motion is the pitch; stills can't sell it).

Meet those and this is an **8.6–8.8** and a launch. If the real-device check finds hinge jitter or stop lag, that outranks everything above.
