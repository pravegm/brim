# Round 2 brief (founder)

Input: `design/REVIEW-1.md` (score 5/10, "not yet"). Target for round 2: ≥ 7.5. Everyone reads REVIEW-1 in full.

## Founder decisions (already made — build to these)

1. **One world for every device** (`Contracts.swift` → `WorldLayout`): always 670 × 952 world pt, shaped like the Duo
   inner canvas in tabletop pose. Crease band y 456…496. Counter (glass base) y = 104. Jug pivot (352, 640).
   The scene is **aspect-filled**: the Duo shows all of it; an iPhone 18 Pro (402 × 874) shows x ≈ 116…554 (full
   height). `layout.visibleRect` gives the visible world rect. **Everything the player must see stays inside
   x 130…540**; the jug, the glass under the spout, stamps, puddles, FX. Glasses enter/leave from off-screen.
   `WorldLayout.make(canvas:hasFold:)` is the new call (old signature kept).
2. **Rest pose = flat.** Lay the Duo open and flat (fold running side to side); lifting the top half toward upright
   tips the jug (tray metaphor). Mapping stays absolute (tilt = 180 − θ). New **flat gate**: at the start of a run and
   after resume, no outflow until the tilt has been inside the dead zone once (`snapshot.needsFlat`, event `.flatArmed`).
   Copy everywhere: **"Lay it flat, then lift the top half to pour."** Book pose card: "Turn me so the fold runs side to
   side, then lay me flat." On phones without a fold the gate is skipped (touch starts at 0).
3. New contract bits: `GameSnapshot.needsFlat` (default false), `GameEvent.lockedIn(glassID:)` (instant cue when the
   stream has finished landing with the top inside the Perfect band), `GameEvent.flatArmed`. Add the new cases to any
   exhaustive `switch` you own.
4. Scale: the hero objects get bigger. On the Duo a tumbler is ~110–130 pt wide (rim), tallest glass ≤ 300 pt so its
   rim stays ≥ 40 pt below the crease; the jug ~170 × 230 pt. The lip while pouring sits ~50–90 pt above the crease.
   HUD band is the top 110 pt of the world (y ≥ 842): keep the jug and art clear of it.

## Assignments (disjoint files; no git; report compile risks)

### Core engineer — `Brim/Core/*`, `BrimTests/CoreTests.swift`, `BrimTests/LevelTests.swift`
- Adopt the new world constants; scale glass profiles (×1.35–1.5) and the jug so the targets in decision 4 hold;
  retune `flowK` so fill times stay ~2–3 s for a tumbler. Keep every pour landing within ±8 pt of the glass centre
  (P1-4), across the typical pour angles; glass stop x = where the stream lands.
- P0-4 physics: no stream from an upright jug (cap outflow by the head the jug can actually deliver; lag only the
  *decline* briefly and let viscous streams thin and snap); open the jug mouth in the physics polygon (or model a lid
  consistently — coordinate the drawing with Scene via `JugState.outline`), so liquid visibly reaches the lip.
- Flat gate (decision 2) + `needsFlat` + `.flatArmed`. Only when `layout.hasFold`.
- P1-1 timing: `serveIdle` 0.35, `resultHold` 0.3, overlap leave/arrive (≤ 0.45 s each), emit `.lockedIn`.
- P1-2: judge **Spill live** the moment liquid goes over the rim (emit `overflowStarted` then `served(.spill)` at once);
  overflow keeps sheeting for ~0.6 s while the glass leaves; puddles bigger (store a radius per puddle if useful —
  `snapshot.puddles` stays `[CGPoint]`; encode growth however Scene can read, e.g. repeated points).
- P2-9 content: 1-4 "half full" (low line in a big glass), and two more micro-twists in venue 1; make the first 60
  seconds of 1-1 delightful (generous band, easy glasses, a first Perfect within ~10 s).
- Rush tuning: the run should last 2–4 minutes for a decent player; Daily 10 orders feel like a fair, varied test.

### Scene engineer — `Brim/Scene/*`, `BrimTests/SceneTests.swift`
- Recompose for the one world (decision 1/4): top half = back bar with no chalkboard/clock behind the HUD/jug; the
  shelf (if any) as a slim ledge clear of the HUD band; **bottom half on a Duo = counter top seen from above** (wood
  grain receding toward the fold, soft shadow from the raised half), glass in the middle of the flat half. On phones
  (hasFold false) the same art is fine but nothing important outside x 130…540.
- P1-9: bring the icon's art language in: teal ceramic accents, lemon roundel decal on the lemonade jug, thicker ink
  outlines, stronger highlights. One signature vessel + prop set per venue (P1-6): lemon pitcher + awning (Lemonade
  Stand), soda dispenser jug + checkerboard + chrome (Soda Fountain), steel shake tin + neon DINER (Milkshake Diner),
  visible belt with rollers (Conveyor), round flask + candles (Potion Shop), hourglass (Sand Bar); Rush dusk palette
  with string lights; Daily = Lemonade Stand art + a tear-off calendar "#N" on the wall (the App sets `venue`; you
  may add `var dailyNumber: Int?`).
- P0-5 Perfect fireworks: ring ≥ 2.5× rim width, 2 rings, white flash on the surface, line turns solid cyan, glass
  hop (6 % squash/stretch), stamp 1.5× bigger sitting just above the rim, streak number popping. Make sure it fires.
- P1-2 Spill disaster: shake 0.25 s (not under reduceMotion), thick overflow sheet with a lip bulge, puddle that
  spreads 2–3× across coaster and counter, droplets, wet glass leaves dripping.
- P1-3 line: solid 3 pt ink line with 1.5 pt white halo overhanging walls by 8 pt, bigger gold tab; translucent cyan
  Perfect band (±perfectBand × interior height) visible while the glass is filling, brightening when the projected
  level is in it; on `.lockedIn` the line flashes.
- P1-4/P1-5 stream: thicker (max ~26 pt), per-liquid width/wobble (shake/honey 1.6× with coiling at landing),
  glossy core, connect visually to the liquid inside the jug (liquid fills the spout channel to the lip), splash
  droplets contained inside the mouth and drawn behind the front wall.
- P2-2 patience ring attached to the glass; P2-3 bumpy foam dome with settling.

### Feel engineer — `Brim/Input/*`, `Brim/Feedback/*`, `BrimTests/InputTests.swift`, `BrimTests/FeedbackTests.swift`
- `.lockedIn` → soft tick haptic + a tiny glassy "tink"; `.flatArmed` → soft confirm click.
- P2-8: a pitched shimmer layer that fades in when `telemetry.projectedDistanceToLine` is inside the Perfect band
  (needs the band: use ±0.03 unless you can read it from the snapshot's active glass `inPerfectBand`).
- Live spill: make the spill sound/haptic match the new live judgement (fires once).
- Autopilot: retune for the new Core (bigger glasses, faster serve); the CI Perfect frame must be a real Perfect,
  the spill frame a real dramatic overflow. Autopilot must respect `needsFlat` (start at 0 tilt).
- Touch fallback: drag distance for full tilt should feel good on a 6.1" phone (~40 % of height) and start pouring
  on a small drag; add a gentle haptic detent when the pour starts.

### App engineer — `Brim/App/*`, `Brim/UI/*`, `Brim/Persistence/*`, `BrimTests/AppTests.swift`
- **P0 from the first Duo run (40203342285, frames in `design/frames/duo1/`):** (a) Info.plist was portrait-only, so
  on the Duo's landscape inner display iOS letterboxed the app into a 469 × 669 column (`BRIM-T orient portrait ok
  window=469x669`). The founder has now declared portrait + both landscapes in `project.yml`; the app must request
  portrait (as Squish's OrientationLock does: supportedInterfaceOrientations via an app delegate +
  requestGeometryUpdate) and show the pose card when the canvas is landscape. (b) **Every** Duo frame showed CoverView
  because of the "canvas < 800 pt once a hinge was seen" rule. The cover display is 466 × 678 pt; the inner canvas is
  669 × 951 (portrait) or 951 × 669 (landscape). Show CoverView only when the hinge angle ≤ 15° (release ≥ 20°) or
  when max(canvas w, h) < 760. Log `BRIM-T canvas <w>x<h> hasFold=<bool> pose=<name>` on every change for CI.
- Use `WorldLayout.make(canvas:hasFold:)`; SpriteView aspect-fill.
- P0-6 safe areas (read real insets; HUD clear of the Dynamic Island and corners; Duo inner camera cut-out).
- P0-7 + decision 2: rewrite PoseCards (ViewThatFits, a phone drawing with the fold running across, the copy). Add
  the "Lay it flat to start" overlay driven by `snapshot.needsFlat` (Duo only).
- P0-2/P1-7 HUD: one compact row ≤ 56 pt in the top 110 pt; a title chip ("Lemonade Stand · 1", "Daily #297",
  "Rush"); hints placed beside the jug, never over it; Home: wordmark on clean wall, buttons on the flat half kept
  clear of the centre ~220 pt where the glass stands (left/right columns or one 64 pt row at the very bottom).
- P1-8 honest demo states: results generated by really running a headless session with the autopilot; seeded streak
  by actually playing; "Flawless" only if all Perfect.
- P1-10 onboarding: goal-first ("Fill to here" callout on the line), the "stream keeps falling" hint *during* the first
  pour at ~60 %, arrow as a glyph not a button.
- P1-11 results: glass-by-glass recap row (mini glasses at their levels vs lines) for every mode, NEW BEST above the
  score, next-unlock line, balanced vertical layout (Duo: card on the top half, buttons on the flat half).
- P2-1 venues polish, P2-4 home chalkboard/daily status, P2-6 reduce-motion row, P2-7 daily streak 🔥 on the Daily
  button. Set `scene.venue` from the mode (Rush → a dusk look if Scene offers it; Daily → lemonade + calendar).
- Demo: keep all keys working; the new `freezeOn` moments must capture the big Perfect at ~0.15 s after the verdict
  and the spill at ~0.3 s after overflow.
