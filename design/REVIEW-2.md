# Brim: Fold to Pour — design review, round 2

*Reviewer: design critic (premium mobile games). Date: 25 Oct 2026.*
*Inputs: `design/GAME-DESIGN.md`, `design/REVIEW-1.md`, `design/ROUND-2.md`; all 18 frames in `design/frames/duo2/` (iPhone Duo simulator: inner 2007×2853 portrait, cover 1398×2034, book card 2853×2007) and all 15 in `design/frames/r2/` (iPhone 18 Pro, 1206×2622); code skimmed in `Brim/App`, `Brim/Core`, `Brim/Scene`, `Brim/Input`, `Brim/Feedback`.*
*Coordinates: **pt from the top-left of the canvas** (Duo inner 669×951, crease band y 455–495; iPhone 402×874) unless marked "world" (SpriteKit, y up).*

---

## 1. Scores

| Area | R1 | **R2** | One-line reason |
|---|---|---|---|
| (a) In-game frame, **Duo** | — | **7.5 / 10** | The magic frame exists: jug on the raised half, stream crossing the fold, a 115 pt glass on the flat half, clean HUD. Held back by a lopsided flat half (glass at 62 % across, left half empty), a slender stream, text on the hinge, and old puddles swallowing the next glass. |
| (a) In-game frame, **iPhone** | 4.5 | **7.5 / 10** | The aspect-fill crop works: glass ~106 pt wide, the jug and glass fill the frame, nothing important cropped. Shelf props now collide with the score, and the Rush chip truncates. |
| (b) UI / screens | 6 | **7 / 10** | Safe areas fixed, the stand-up card reflows, the Duo home with its chalkboard is charming, results are honest with a per-glass recap. But the Duo home buttons sit on the glass, Duo results leave ~45 % of the screen empty, and two labels truncate. |
| (c) Game design | 6.5 | **7.5 / 10** | The flat gate, "Fill to here", tighter serve timing, live spill, venue-1 micro-twists, Rush/Daily identity: all right. One open hole that only a Duo can have: **closing the phone pours** (P0-1). |
| (d) Satisfaction / juice (visible) | 4 | **7 / 10** | Perfect is now a real moment (2.5× ring, flash, cyan line, big stamp, streak pop). The pour itself is still a thin rope next to the icon's fat glossy stream; spill is livelier but the puddle is coaster-sized. |
| **Overall** | 5 | **7.5 / 10** | A big, honest jump: this now looks like a premium game on the Duo. One P0 and ~10 P1s stand between it and launch, and none of them is a redesign. |

---

## 2. Status of the REVIEW-1 top 8

| # | Item | Status | Evidence / what's left |
|---|---|---|---|
| 1 | Rescale and recompose both canvases | **Fixed** (follow-ups P1-1, P1-2) | Duo tumbler rim ~114 pt (duo-01, x 357–471), iPhone ~106 pt (r2/02). Chalkboard/clock gone from the play top half; HUD is one band; the counter edge sits exactly on the crease; the flat half is a counter. Left: the landing is off-centre, so the flat half is lopsided, and the Duo home buttons cover the glass. |
| 2 | Duo rest pose | **Fixed** | duo-00, launched at 120°: "Lay it flat to start / Then lift the top half to pour." Copy matches on the cover, book card, Settings and hints. New gap: closing the phone (P0-1). |
| 3 | Pour physically true and fat | **Partly** | No stream from an upright jug in any frame; the stream starts at the spout tip; landing centred in the glass (store-s1: stream x ≈ 416 pt vs glass centre 414); splashes stay inside the mouth. Still thin (~15 pt at the lip on a 115 pt rim), the spout channel is drawn empty, and the shake stream isn't 1.6× wider (P1-5). |
| 4 | Perfect fireworks, Spill disaster | **Perfect fixed; Spill partly** | store-s2 / r2-03: ring ≈ 2.4× the rim, white flash, solid cyan line, 64 pt stamp, "×5 STREAK". Spill is live (the jug is still pouring under "SPILL!") with droplets and wall sheets, but the puddle is barely wider than the coaster (store-s6) and there's a ghost "tongue" inside the liquid (P1-6). |
| 5 | Readable line, Perfect band, lock cue, timing | **Fixed** (polish P2-9) | Solid ink line with white halo and a big gold tab; the gold halo lights when the level is in the band (duo-03); `serveIdle` 0.35, `resultHold` 0.3, leave/arrive 0.45 overlapped; `.lockedIn` wired to Scene and Feedback. The band before pouring is two cyan hairlines, not a strip. |
| 6 | Safe areas, stand-up card | **Fixed** (one truncation) | Dynamic Island is clear on r2/08, 09, 10; the HUD sits under it. The card is a `ViewThatFits` with a phone-with-fold drawing. "Turn the scre…" truncates on iPhone (P1-8). |
| 7 | Venue identity, icon art language | **Partly** | Palettes and props are now distinct: awning + lemon print, checkerboard + chrome tap tower + marble, neon DINER + sprinkle counter, dusk string lights for Rush, a tear-off "DAILY #297" calendar. Teal accents and roundel decals on the jug. **The signature vessel is not done**: Soda and Diner pour from the same pitcher, recoloured (P1-9). |
| 8 | Honest store frames and screens | **Mostly fixed** | Results 800 = 5 Perfect, streak 5, 5 glasses; Rush "9 served, ×3, 2,000" is plausible; title chips; "Fill to here"; hints beside the action. Left: the Duo results layout (P1-10), "NEW BEST" on a failed first run (P2-6), and CI's hinge path skipping the flat gate on resume (P0-1). |

---

## 3. What works now (keep; don't touch)

1. **The Duo magic frame.** duo-02 / store-s1: a teal-trimmed pitcher tipping on the raised half, the stream dropping across the counter edge that *is* the hinge, into a glass on the flat half. It reads in one second. The counter edge placed on the crease is a smart choice: the physical seam becomes the bar's edge.
2. **The flat gate** and the copy system ("Lay it flat, then lift the top half to pour" everywhere). The first-run trio on the Duo (duo-01): "Lift the top half to pour ↑" on the moving half, "Fill to here ▶" on the line, then "Lay it flat just before the line" during the pour. That is textbook goal-first onboarding.
3. **The Perfect moment** (store-s2, r2/03). Keep it exactly; just move the streak pop (P1-3).
4. **Venue dressing**: the Soda Fountain tap tower and marble, the neon DINER, the Rush string lights and the Daily calendar make five store screenshots that no longer look the same.
5. **The Duo home chalkboard** ("TODAY · Daily #297 · Not poured yet"), the cover card ("Open me to pour" with live Rush and Daily status) and Settings (Calmer motion, Touch on Duo, honest About text).
6. **Honest results with a mini-glass recap** (duo-ui-results, r2/08).

---

## 4. Ranked issues

### P0 — would embarrass at launch

**P0-1. Closing the Duo pours the jug and can end the run.**
- *What I see:* duo-05 (closed, cover display): behind the cover card the ghosted scene shows the jug **tipped ~130° with a stream in the air** and a glass a quarter full. duo-06 (reopened): the results show **4 glasses, the 4th a spill**: 3 strikes, shift over, "So close". The player didn't pour that glass; the hinge did on its way shut.
- *Why (code):* `Rules.jugAngle` clamps tilt to 90, so any hinge angle below 90° is a full tip. `GameController.hingeSample` only treats the phone as shut at θ ≤ 15°. A human closes 180° → 0° in ~0.4–0.8 s, so the jug spends roughly the last half of that at maximum tip. The One-Euro filter and the 25–30 Hz hinge make the "shut" detection later still, and liquid already in the air lands after the resume. CI's demo path (`setPosePaused`, `demo != nil`) also skips the pause card and the flat-gate re-arm, so the reopen in duo-06 poured again. Pillar 5 says "never require closing the phone"; it also must never *punish* closing it. Every Duo owner will fold it shut mid-shift to answer a message.
- *Fix:* (1) **Closing guard** in `Input/HingeTiltSource.swift` + `Core/GameSession.swift`: play lives in θ 175…95 (pillar 5). Below θ ≈ 85°, or when θ falls faster than ~150°/s at any angle below 150°, treat it as "closing": stop outflow at once (the jug keeps its angle on screen, `outflow = 0`), freeze `incomingVolume` accounting for the current glass, re-arm `needsFlat`, and pause. Optionally roll back the volume emitted in the last ~0.2 s before the guard fired (a short ring buffer in `GameSession`), so the fast flick that triggered it costs nothing. (2) `App/GameController.swift`: on pose resume, demo or not, call `session?.requireFlat()` so CI shows the true behaviour. (3) CI: a hinge script 179° → 0° in 0.6 s mid-pour, then reopen to 179°; assert the glass level changed < 2 % of capacity and the strike count is unchanged.

### P1 — clearly hurts

**P1-1. The flat half is lopsided: everything lands at 62 % across, the left half is empty.**
- *What I see:* in every Duo play frame (duo-00…04, store-s1…s6) the glass stands at x 357–471 pt (centre ~414) and the stream falls at x ~410. The region x 0–340, y 500–930 (≈ 36 % of the whole flat half) is bare wood or marble. On the top half the jug sits centred (x ~180–415), so the frame reads as "pitcher left, glass right, nothing bottom-left".
- *Fix:* (a) In `Shared/Contracts.swift` `WorldLayout`, move the jug pivot left so the *landing* x for typical pour angles is ~335 (the canvas centre), and re-check `CoreTuning.glassPlacementBias`. That centres the glass on both the Duo and the iPhone crop (x 116–554). (b) On the Duo only, use the empty left: **show the next glass waiting on the counter** (x ~110–210, 60 % opacity, sliding up as the current one leaves). It is information (the next glass shape and liquid), it fills the composition, and it sells the conveyor-counter fiction. Files: `Contracts.swift`, `Core/CoreTuning.swift`, `Scene/SceneGlass.swift` (a queue node), `Core/GameSession.swift` (expose the next order in the snapshot).

**P1-2. Duo home: Rush and Daily buttons sit on top of the glass.**
- *What I see:* duo-ui-menu: the attract glass spans x 333–499, y 650–860 pt with its line at y ≈ 699. The Rush button (x 445–651, y 632–706) covers the rim, the line and the right wall; Daily (y 716–789) covers the handle. The brief kept the *canvas* centre clear, but the glass isn't at the centre (P1-1).
- *Fix:* `UI/HomeView.swift` (Duo branch): after P1-1, keep x 230–440 pt clear, with Play and Venues in the left column and Rush and Daily in the right, each column ≤ 215 pt wide. Or put all four in one 64 pt row at y ≥ 870 pt. Derive the keep-out from the scene's glass frame, not a constant.

**P1-3. Text and FX on the hinge.**
- *What I see:* store-s2: "×5 STREAK" spans y 476–504 pt, **on the crease band**. On a real Duo at 120–150° it will be split across two panels at an angle. Tall glasses (highball, mason jar in store-s5: rim at ~610 pt) push the stamp and pop even higher. The tipped jug's lower corner also dips into the band (duo-02 at ~459 pt, store-s1 at ~461 pt).
- *Fix:* add a **crease keep-out** to `WorldLayout` (`foldKeepOut = creaseMin-8 … creaseMax+8`, Duo only). In `SceneGlass` (streak pop at line ~848, stamp at ~836), clamp text so its top stays below the band. If it doesn't fit, put the streak pop *beside* the PERFECT stamp (to its right on the flat half), not above it. Nudge the jug pivot up ~12 world pt or limit the hull so it clears `creaseMaxY`. Same rule for hints and the `FlatGate` card.

**P1-4. Puddles outlive their glass and swallow the next one.**
- *What I see:* duo-03 / duo-04: a blue-and-yellow puddle spanning x 200–637 pt sits under a **new, clean** glass; the coaster is hidden. The next glass reads as leaking, and a perfect pour in it would look wet. Cause: `GameSession` keeps every puddle for the whole run (merging by x), and `GameScene` z-orders puddles (−10) **above** the coaster (−20).
- *Fix:* `Scene/GameScene.swift`: puddles under the coaster. `Core/GameSession.swift` + `Scene/SceneFX.swift`: a puddle belongs to the glass that spilled it. It spreads during the spill (P1-6), leaves a short drip trail as the glass slides right, then the stain fades over ~1.2 s, or a quick cloth wipe crosses the counter as the next glass arrives (a nice beat). Keep at most one faint stain from earlier glasses.

**P1-5. The stream is still a rope, and water is nearly invisible.**
- *What I see:* store-s1 crop: ~15 pt wide at the lip on a 114 pt rim (13 %). In the icon the stream is ~28 % of the rim. Water streams (duo-02, r2/02, r2/07) are pale, translucent blue on warm wood: the weakest frames in the set. Milkshake (store-s4, r2/06) wiggles but isn't wider. The spout channel between the body and the lip is drawn empty (crop: liquid stops at the body wall, then the stream starts at the tip).
- *Fix:* `Scene/SceneStream.swift` / `Core/CoreTuning.swift`: map *typical* flow (the autopilot's median) to ≥ 20 pt and full flow to 26 pt; apply the viscosity width ×1.6 for shake/honey; give every stream a 1.5 pt darker edge (liquid colour −25 % lightness) and a bright specular core like the icon. Water: saturate to ~`#6EC6F0` with a white core; never below 70 % opacity. `Scene/SceneJug.swift`: fill the spout channel with a liquid sheet from the body to the lip whenever outflow > 0.

**P1-6. Spill is livelier but still not a disaster.**
- *What I see:* store-s6 / r2/04: "SPILL!" stamp, droplets at the rim, translucent sheets on both walls (~6 pt), and a puddle no wider than the coaster (x 328–485 pt vs coaster 342–485). Inside the glass a lighter, tongue-shaped "ghost" (the stream's plunge, x ~395–435 pt, down to ~2/3 depth) reads as a rendering artefact.
- *Fix:* `Scene/SceneFX.swift`: the puddle spreads to 2–3× the coaster width over 0.4 s with a glossy rim and a few satellite drops (the same art that duo-04 already draws by accident, but per glass, see P1-4). `Scene/SceneGlass.swift`: overflow sheets at ≥ 60 % opacity, ≥ 12 pt wide, with a lip bulge and a drip that falls to the counter; replace the plunge "tongue" with a short foam/bubble plume. Keep the 0.25 s shake (verify it fires; a still can't show it).

**P1-7. iPhone: shelf props collide with the HUD.**
- *What I see:* r2/05: the score "0" (x 310–330, y 81–105 pt) sits on the brown bottle's neck (x 308–328, top at y 107); the striped straw cup pokes up behind the pause button (x 356–378). r2/06: the sundae's cherry and straw touch the "0" (x ~305, y ~108). The aspect-fill crop plus the Dynamic Island inset push the HUD ~60 pt down into the art that the Duo keeps clear.
- *Fix:* `Scene/SceneArt.swift`: compute the HUD band per device as `visibleRect.maxY − (110 + safeInsetTop)` world pt and keep prop tops below it. On iPhone, lower the shelf ~50 pt or drop the rightmost props when `!hasFold`. Re-shoot 05/06.

**P1-8. Truncated labels.**
- r2/07 Rush: "**7 se…**" (x 17–69, y 96–116 pt) because the "×3 ★ 7" pill and "1,400" eat the row. Fix `UI/PlayOverlays.swift`: show "7 ✓" or move "served" under the score; `minimumScaleFactor(0.8)` and `lineLimit(1)` with a shorter fallback via `ViewThatFits`.
- r2/11: "**Turn the scre…**" (x 24–195, y 470–524 pt). Fix `UI/PoseCards.swift`: "Rotate" or "Turn it", or stack the two buttons vertically on compact widths.

**P1-9. Signature vessels are missing, and the Diner hero has no contrast.**
- *What I see:* store-s3 (Soda) and store-s4 (Diner) pour from the *same pitcher outline* in red and grey; the steel shake tin from the brief sits on the Diner shelf as a prop, not in your hand. In the Diner, a pink stream falls onto a pink sprinkle counter into pink shake (store-s4, r2/06): the lowest-contrast hero frame in the set.
- *Fix:* `Scene/SceneJug.swift` + `Core/JugGeometry.swift` (outline per venue, physics unchanged or rescaled): Soda = a chrome-collared dispenser jug with a squat spout; Diner = a steel shake tin with a rolled lip. Keep the liquid readable (a sight window down the tin's side, or a frosted band), because players read the jug level. `Scene/ScenePalette.swift`: Diner counter to mint or teal formica with a chrome edge, so pink pops.

**P1-10. Duo results: half the screen is empty peach.**
- *What I see:* duo-ui-results / duo-06: card at y 64–392 pt, buttons at 637–780; y 392–637 and 780–951 (≈ 45 % of the screen, all of the flat half except the buttons) is gradient. In duo-06 a ghost of the tipped jug peeks out under the card (y 404–461).
- *Fix:* `UI/ResultsView.swift` + `App/GameController.swift`: on the Duo, keep the card on the raised half and use the **flat half for the real shift**: the 5–8 served glasses slide back in as a row on the counter at ~60 % scale, each at its true level against its line, with its stamp colour on the coaster. Buttons in one 64 pt row at the bottom. Use a clean blurred counter behind the card, not the frozen play scene. That gives the store its best "results" screenshot.

### P2 — polish

- **P2-1 Jug base reads as a second liquid.** The thick teal base band under the water (duo-00, r2/12) looks like a teal layer of drink. Make it clearly ceramic (outside the liquid polygon, with a highlight and an ink line), or thin it. `SceneJug`.
- **P2-2 Flat-gate card glyph** (duo-00, x 497–592, y 316–335 pt): two short strokes that few will parse. Reuse the PoseCards phone drawing, animating from 120° to flat. `UI/PlayOverlays.swift`.
- **P2-3 The flat half doesn't react to the lift.** Add a soft shadow just below the crease whose depth grows with tilt. It sells "the top half is up" on the device and in video. Optional: plank lines that converge slightly toward the fold. `SceneArt` / `GameScene`.
- **P2-4 Streak iconography.** "×2 ★ 5" uses ★, which elsewhere means stars earned (Venues, Home). Use a flame or droplet for the streak, and separate the multiplier. `PlayOverlays`.
- **P2-5 Fill tab over mug handles** (store-s2, store-s3, r2/01: tab x 494–523 pt overlaps the handle at 476–514). Mirror the handle to the left, or put the tab on the left wall for handled glasses. `SceneGlass`.
- **P2-6 Results tone.** duo-06: "So close" + "NEW BEST" on a 0-star, 3-spill first run. Use "Shift over — 3 spills" when strikes end it, and show NEW BEST only when a previous best existed. `ResultsView`.
- **P2-7 Book-pose card crosses the vertical crease** (duo-ui-book: headline and "Turn the screen" span x 384–820 pt; the crease is 455–495). Put the drawing on the left page and the text on the right page starting ≥ 24 pt past the crease, and show the phone *lying flat* (the copy says "lay me flat"; the drawing shows it upright). `PoseCards`.
- **P2-8 Attract-loop tail** (duo-ui-menu, x ≈ 409 pt, y 376–694): the end of the pour renders as a rigid 2 pt stick starting in mid-air. Break the tail into falling drops, and make the menu capture avoid that instant. `SceneStream`, `DemoMode`.
- **P2-9 Perfect band before pouring** (duo-01 at y ~720/735 pt): two cyan hairlines. Make it a 20–25 % cyan strip so "aim here" reads before the first drop. `SceneGlass`.
- **P2-10 Daily button on iPhone** (r2/01) says only "Daily"; the Duo shows "#297 · new". Add the number, state and streak 🔥 on both. `HomeView`.
- **P2-11 Venues on Duo**: the Soda row 1 circles straddle the crease (y 447–502 pt) on first open; add a top inset so the first screen's crease falls between cards. `VenuesView`.

---

## 5. Risks I can't judge from stills (and how to check)

| Risk | Why it matters | How to check |
|---|---|---|
| **Hinge feel and noise** | ±5° hinge accuracy × 1.55 gain = ±7.75° of jug, and a ~2.5 s fill: jitter could pulse the stream or make Perfect luck. | TestFlight on the real Duo: hold at ~150° for 5 s and screen-record. Stream width and level rise should be smooth. Log `BRIM-T` tilt variance; if σ > 1.5°, raise One-Euro minCutoff or add hysteresis near the pour threshold. |
| **Closing guard** (P0-1) | Only real hardware has real close speeds and the `.closed`-at-85° quirk. | Close the phone 10 times mid-pour at different speeds; zero strikes allowed. |
| **Viewing the fold** | At 120–140° the raised half is foreshortened and the stream "bends" at the seam. The magic frame could look broken in the hand. | Photograph the device at 130° from a seated eye position; if the stream looks kinked, add a 6–10 pt splash/blur where it crosses the seam. |
| **Sound** | Pitch rise, the band shimmer, the lock-in "tink", the spill buzz are the satisfaction core and invisible here. | Record 60 s of 1-1 with sound; check that the shimmer starts *before* the line (it should lead you) and that Perfect tings climb the pentatonic scale across a streak. |
| **Haptics** | `.lockedIn` tick + Perfect double tap may blur together within 0.3 s. | On device: does lock-in → Perfect feel like two distinct beats? If not, drop lock-in when the verdict follows within 0.25 s. |
| **First 60 seconds** | The brief wants a first Perfect within ~10 s for a novice. | Hand the Duo to 5 people who've never seen it, with no explanation. Target: 4/5 pour within 10 s and 3/5 hit a Perfect inside 60 s. |
| **Performance** | Particles + glow + 120 Hz on the Duo inner panel. | Instruments on device during Rush tier 3; no frame > 16 ms. |

---

## 6. Top 8 for round 3 (in order)

1. **Closing guard (P0-1).** Outflow stops below θ ≈ 85° or on a fast fold; re-arm the flat gate on any pose resume (CI too); CI close-mid-pour test. *Files:* `Input/HingeTiltSource.swift`, `Core/GameSession.swift`, `App/GameController.swift`, CI scenarios.
2. **Centre the pour; use the left of the flat half (P1-1, P1-2).** Landing at x ≈ 335; next glass waiting on the Duo counter; home buttons clear of the real glass frame. *Files:* `Shared/Contracts.swift`, `Core/CoreTuning.swift`, `Scene/SceneGlass.swift`, `UI/HomeView.swift`.
3. **Crease keep-out (P1-3, P2-7).** No text, stamp, pop, hint or jug hull inside the band ±8 pt; the book card splits on the crease. *Files:* `Contracts.swift`, `Scene/SceneGlass.swift`, `Scene/SceneJug.swift`, `UI/PoseCards.swift`.
4. **A fat, opaque, connected stream (P1-5).** ≥ 20 pt at typical flow, edge + specular core, saturated water, viscous ×1.6, liquid in the spout channel. *Files:* `Scene/SceneStream.swift`, `Scene/SceneJug.swift`, `Core/CoreTuning.swift`.
5. **Spill and puddle lifecycle (P1-4, P1-6).** Per-glass puddle that spreads 2–3×, opaque sheets, no ghost tongue, dries or wipes as the next glass arrives, under the coaster. *Files:* `Core/GameSession.swift`, `Scene/SceneFX.swift`, `Scene/SceneGlass.swift`, `Scene/GameScene.swift`.
6. **Signature vessels and Diner contrast (P1-9).** Soda dispenser jug, steel shake tin with a sight window, a non-pink Diner counter. *Files:* `Scene/SceneJug.swift`, `Core/JugGeometry.swift`, `Scene/ScenePalette.swift`.
7. **Duo results on the counter (P1-10, P2-6).** Real served glasses on the flat half, one button row, honest headline and NEW BEST. *Files:* `UI/ResultsView.swift`, `App/GameController.swift`.
8. **iPhone HUD polish (P1-7, P1-8, P2-4).** Props below the device-specific HUD band, no truncation, streak icon ≠ star. *Files:* `Scene/SceneArt.swift`, `UI/PlayOverlays.swift`, `UI/PoseCards.swift`.

---

## 7. Launch call

**Close.** Round 2 is a genuine transformation: on the Duo it now looks and reads like the premium, one-idea game the bible describes, and the Perfect beat finally lands. It is not a yes while closing the phone can pour a glass and end a run. That is a Duo-only failure, so it would hit exactly the audience the product is built for, in its first session.

**What makes it a yes:**
1. P0-1 fixed and proven: a CI close-mid-pour hinge test passes, plus 10 real closes on the TestFlight Duo with zero strikes.
2. P1-1…P1-10 closed, and the Duo + iPhone store frames re-shot from real autopilot runs (centred pour, fat stream, a per-glass spill, results on the counter).
3. One real-device session confirming hinge feel and sound (section 5): a smooth stream at a held angle, the shimmer leading the line, 3 of 5 novices hitting a Perfect inside 60 s.

Do those and I'd expect round 3 to score **8.5+** with no open P0/P1, which meets the launch bar in GAME-DESIGN §11.
