# Brim: Fold to Pour — design review, round 1

*Reviewer: design critic (premium mobile games). Date: 25 Oct 2026.*
*Inputs: `design/GAME-DESIGN.md`; all 15 frames in `design/frames/r1/` (iPhone 18 Pro sim, 1206×2622, fallback layout); code in `Brim/Scene`, `Brim/Core`, `Brim/UI`, `Brim/Feedback`, `Brim/Shared/Contracts.swift`.*
*Coordinates below are native frame pixels (1206×2622, origin top-left) unless marked "world" (SpriteKit world points, y up) or "pt".*

---

## 1. Scores

| Area | Score | One-line reason |
|---|---|---|
| (a) In-game frame | **4.5 / 10** | Clean, warm flat style, but the glass (the thing you are judged on) is ~43 pt wide, ~45 % of the screen is dead wall/wood, and two frames show physically impossible pours. |
| (b) UI / screens | **6 / 10** | Buttons and cards are chunky, legible and on-brand. Undermined by safe-area collisions (Dynamic Island over "Settings"), a broken stand-up card, a wordmark sitting on the shelf, and a results screen with a dead lower third. |
| (c) Game design (loop, ramp, retention) | **6.5 / 10** | The concept is genuinely great and the content plan (5 venues × 8 shifts, 11 glasses, Rush, Daily) is right-sized for £1.99. Hurt by a ~1 s gap between action and verdict, ~2.3 s of dead time per glass, venues that are recolours, and a Duo rest-pose that contradicts the onboarding copy. |
| (d) Satisfaction / juice (as implemented) | **4 / 10** | The sound and haptic recipes are thoughtful (rising Helmholtz pitch, pentatonic streak tings, wobbly spill buzz) — on paper a 7. But the pixels don't deliver: no visible Perfect burst, a polite spill, a hair-thin stream, splash droplets that look like leaks. |
| **Overall** | **5 / 10** | A strong idea with a competent shell. Not yet a hit: the hero moment (stream → glass → line → Perfect) is too small, too quiet and occasionally untrue. |

The launch bar in GAME-DESIGN §11 is 8.5 with no open P0/P1. This round is far from it, but almost every fix below is layout, art and feedback work — not a redesign.

---

## 2. What already works (keep)

1. **The concept and its fallback.** "Fill to the line, the stream keeps falling" is a 3-second read and an endless skill ceiling. Drag-to-tip on regular iPhones is a respectable fallback.
2. **The physics model.** Weir-law outflow from a polygon jug (`JugGeometry`), fall-time anticipation, foam and viscosity lag as data (`LiquidCatalog`). Emptier jug = steeper tip is a lovely learnable rule.
3. **The palette and typography.** Cream `#FFF4E2` / mint tiles / terracotta counter / SF Rounded heavy is warm and premium. The cards and the 3D-lipped buttons (`BrimTheme`) feel tactile.
4. **The menu has an attract loop.** A pour runs behind the home screen (01). Keep it — it is the best store-video seed you have.
5. **The icon (14, AppIcon-1024).** Teal ceramic jug with a lemon slice, a fat golden stream, a rocks glass with a gold fill line, and a fold seam across the middle. It is the best piece of art in the project. **8/10.** (Issue: the in-game art does not live up to it, see P1-9.)
6. **Sound / haptic design.** `SoundBook.resonanceHz` (180 → 1600 Hz as the air column shortens), streak tings climbing a pentatonic scale, the four-hit wobbly spill buzz, the coaster thump timed to the slide. That is exactly the right recipe set; keep it all.
7. **Strike cups on the shelf** (02, top-left: three empty tumblers that turn red on a spill, 04). Diegetic and charming. Keep the idea, fix the placement.
8. **Content and ramp skeleton** (`LevelCatalog`): band tightening (±3.5 % → ±1.8 %), jug emptying across a venue, one new behaviour per venue, prefills and fading lines as late curveballs. Daily seeded on UTC days, shareable emoji line. All right.
9. **Settings copy** (10): honest, warm, "no ads, no IAP, no tracking", "Made for iPhone Duo — on a Duo, the fold is the jug." Good.

---

## 3. Ranked issues

### P0 — would embarrass at launch

**P0-1. The glass is tiny and the frame is half empty.**
- *What I see:* 02-midpour: the tumbler spans x 662–790, y 1660–1915 — 128 px, i.e. **~43 pt wide**, ~1.2 % of the screen area. The fill line it all hinges on is ~5 px tall. Meanwhile the wall above the tiles (y 200–835) holds only a chalkboard and a clock, and the wood counter front (y 1940–2622) is **26 % of the screen with nothing on it**. Same in 03, 04, 05, 06, 07, 12, 13.
- *Why:* A precision game must make the judged object the hero. At 43 pt nobody can see foam vs liquid, the Perfect band, or "just a drop more". Store screenshots at thumbnail size will show a wall.
- *Fix:* In `Shared/Contracts.swift` `WorldLayout.make`, stop fixing `worldWidth = 670` on non-fold canvases: use a zoomed world (≈ 460–480 world pt across) so everything scales ×1.4–1.45, and set the virtual crease at ~52 % of height instead of 50 %. Clamp the counter so the front panel is ≤ 12 % of the screen (`counterY` ≥ 0.12·h + 26). Target: glass ≥ 64 pt wide on 6.1", fill line ≥ 3 pt. On the Duo (scale ≈ 1) also scale glass art ×1.35 (`SceneGlass` draw scale, with `GlassCatalog` volumes unchanged) so a tumbler is ~90 pt wide.

**P0-2. Duo layout will collide and hide the glass (predicted from the code, must fix before Duo frames).**
- *What the code gives on 669×951 (crease 455–495 pt from top):* world h = 952, crease 457–497, `counterY` = 127, jug pivot y = 592. The upright jug is clamped to start at `creaseMaxY + 14` = 511 and reaches ~740; tipped, its handle reaches ~755. `SceneArt` puts the tile top at 706, a **chalkboard at 736–841** and a clock beside it, the shelf at 875. The SwiftUI HUD (score, strike cups, dots / "served" pill) occupies 0–116 pt (shifts) or 0–153 pt (Rush) from the top → world 836–952 / 799–952. The first-run hint sits at `insets.top + 150` pt → world ~750–800. **Result: jug handle, chalkboard, hint pill and HUD all stack into the same 100 pt band.**
- Bottom half: the counter top is a 50 pt strip at 111–161, the front panel 0–101, and **~300 pt of vertical tile wall** fills the half that is lying flat on the table. The glass stands at 139–283. On Home and Results, `DuoSplit` puts ~222 pt of buttons at the bottom of that half → **the Play button covers the glass and the landing stream of the attract loop.**
- *Why:* The design bible says every judgement is made on the Duo frame first, and the crossing stream is "the magic frame". As built, the magic frame will be cluttered on top and buried under buttons below.
- *Fix:* (1) `SceneArt.paintBackBar`: when `layout.hasFold`, drop the chalkboard/clock (or move them to x < 60 / x > 610 strips the HUD never uses) and shrink the shelf to a 10 pt ledge under the HUD. (2) `PlayOverlays` HUD: one compact row (score · strike cups · progress dots) ≤ 56 pt tall; anchor hints to the jug's world position, not `insets.top + 150`. (3) `SceneArt.paintCounterSide`: on fold, paint the bottom half as **counter top seen from above** (wood grain receding toward the crease, soft shadow cast by the raised half) instead of a tiled wall — it is the surface lying on the table. (4) `WorldLayout.make`: on fold, raise the jug (pivot at crease + 170) and the glass (rim ~150 pt below the crease) so the fall stays ~310 pt but the glass sits in the middle of the flat half, away from the buttons. (5) `HomeView` / `ResultsView` bottom halves: put buttons in a left/right column pair or a single 64 pt row, leaving the centre 200 pt of the flat half (the glass) clear.

**P0-3. The Duo rest pose contradicts the copy: "Stand me up like a little laptop" = an instant full pour.**
- *What I see:* `HingeTiltSource`: tilt = clamp(180 − θ, 0…90); `Rules.jugAngle`: dead zone only below 6° of tilt (θ > 174°). A Duo standing like a laptop (θ ≈ 105–115°) is tilt 65–75° → jug ~90–107° → near-maximum flow. The stand-up card (11), the one-liner ("Stand it up like a little laptop"), and `FoldingPhoneDrawing` (lid animating to 10° from vertical) all teach that pose as the rest pose. There is no "arm" gate anywhere (`grep armed|requireUpright` finds nothing).
- *Why:* The very first thing a Duo owner does — exactly what the app told them — dumps the jug into glass 1 and spills it. That is the worst possible first three seconds for a Duo-first product.
- *Fix (pick one, then make all copy match):* (a) **Relative calibration (recommended):** when a glass arrives and the jug is idle, take the current hinge angle as "upright" (clamped to 95–178°) and pour on lift *beyond* it (`HingeTiltSource` gains a `rest` angle; `Rules.jugAngle` uses tilt − rest). Players can hold any comfortable pose. (b) Or keep absolute angles but rewrite the card and hints to "Open me flat on the table, then lift the top half to pour", redraw `FoldingPhoneDrawing` to start flat, and add an arming gate in `GameSession`: no outflow for a new glass until tilt has been < dead zone once, with the hint "Lay it flat to start". Either way, verify on the real Duo (Squish's TestFlight loop).

**P0-4. Store frames that show impossible physics.**
- *06-shake:* the jug is **fully upright** (x 275–730, rim at y ≈ 885) and a pink stream still leaves the spout at (700, 905) and runs to the glass. Cause: `GameSession` applies `lagTau` (0.45 for milkshake, 0.8 honey) to the outflow, so flow continues after the head above the lip is gone.
- *02-midpour, 07-rush, 13-daily:* in the tipped jug the liquid surface (02: y ≈ 1025) is ~200 px **above** the spout tip (y ≈ 1200) and level with the open mouth, yet the spout channel is empty and only a 6–8 px thread leaves the tip. The physics polygon (`JugGeometry.makeStandard`) closes the mouth with an edge (`(86,214) → (40,216) → (-56,216)`), so the jug behaves like a sealed bottle with a pinhole at the lip. The art draws an open pitcher.
- *Why:* "Physically true" is pillar 2, and the stream is the money shot. A sharp-eyed reviewer will spot a stream from an upright jug immediately.
- *Fix:* (1) Viscosity: keep the lag but make it visible and possible. Lag the *liquid surface inside the jug* (it stays sloshed toward the spout for τ s, `SceneJug` draws the tilted surface), cap `outflow` by what the lagged head can deliver, and when the jug is upright let the stream **thin into a rope and snap** (taper the last 0.3 s of particles in `SceneStream`) rather than flow out of the lip. (2) Jug: either give the pitcher a lid (draw a hinged lid in `SceneJug`, and the sealed polygon becomes true), or open the mouth in the polygon so the lowest mouth point is the lip and cap the jug angle so the surface never rises above the mouth line. Also draw liquid filling the spout channel up to the lip, so the stream visibly connects to the body (today there's a ~60–80 px empty gap between the liquid and the stream's start).

**P0-5. The Perfect moment is invisible.**
- *What I see:* 03-perfect (0.35 s after the judgement): a cyan "PERFECT" word (x 540–905, y 1490–1580) and a "1 perfect" pill. **No sparkle ring, no twinkles, no confetti, no camera bump** — even though `SceneFX.perfectBurst` should still be at ~60 % alpha at 0.35 s. Either the burst never fires on this path, or it's too small/faint (rings scale to `(rimHalfWidth + 75)/100` ≈ 1.05 of a 100-pt ring on a 43 pt glass).
- *Why:* This is the reward the whole game is built around and the frame you will put first in the store.
- *Fix:* Check in `GameScene.handle(.served)` that the burst and `bump()` fire (and aren't frozen by DemoMode `freezeOn`). Then make it big: ring ≥ 2.5× the rim width, 2 rings + a 0.12 s white flash on the liquid surface, the line turning solid cyan, the glass doing a 6 % squash-and-stretch hop, the stamp 1.5× larger, sitting above the rim (not floating 60 px up), and the streak counter flying from the glass into the HUD. Capture the store frame at 0.15 s.

**P0-6. Safe area is ignored: UI under the Dynamic Island and screen corners.**
- *What I see:* 10-settings: the island (x 460–745, y 40–150) sits on the title — "Setti▮▮". 06 and 11 show it too. In every screen the top controls are ~10 pt from the top edge: the pause button (x 1015–1155, y 30–170) sits inside the rounded-corner radius; "Venues" (09, x 230–585) runs under where the island will be on a device.
- *Cause:* `RootView` applies `.ignoresSafeArea()` to the `GeometryReader`, then passes `geo.safeAreaInsets` as `info.insets` — the frames show they arrive as ~0.
- *Fix:* In `RootView`, read insets from a non-ignoring background `GeometryReader` (or `UIApplication.shared.connectedScenes … safeAreaInsets`) and pass those in `CanvasInfo`; keep the SpriteView full-bleed. Re-check on the Duo inner display (camera cut-out position).

**P0-7. The stand-up card breaks in portrait.**
- *What I see:* 11-standup: `HStack` of a fixed 230 pt drawing + 36 pt spacing leaves a ~70 pt text column: "Sta / nd / me / up / like / a / littl / e / lapt / op", the "Play" button letters stacked vertically, and the laptop drawing floating mid-left.
- *Why:* It's in the frame set, it will show on any narrow or large-Dynamic-Type canvas, and the drawing (a generic laptop seen from the front) doesn't show a phone with a horizontal fold.
- *Fix:* `UI/PoseCards.swift`: wrap in `ViewThatFits` (HStack → VStack), give the text `minWidth: 280`, and redraw `FoldingPhoneDrawing` as a phone (camera dot, rounded corners), with the fold running across, the glass on the bottom half and a jug on the top half. Make the copy match the P0-3 decision.

### P1 — clearly hurts

**P1-1. The verdict arrives ~1 s after the decision, and each glass has ~2.3 s of dead time.**
- *Code:* serve after `serveIdle` 0.6 s of no flow (plus stream fall ~0.4 s, plus `foamServeGrace` up to 1.6 s), then `resultHold` 0.45 + `leaveDuration` 0.6 + `arriveDuration` 0.7.
- *Why:* The satisfying beat is "stop… *ting*". A 1 s gap splits the cause from the reward, and the 2.3 s changeover makes a 6-glass shift ~35 % waiting.
- *Fix:* `CoreTuning`: serveIdle 0.35, resultHold 0.3; overlap leave and arrive (the next glass enters while the last one exits, 0.45 s each). Add an **instant "lock" cue** the moment the stream finishes landing with the level inside the band: a soft tick haptic and a line glow (`FeedbackDirector`, new event from `GameSession` when `incomingVolume` hits 0). The Perfect stamp then confirms it.

**P1-2. The spill is polite, not dramatic.**
- *What I see:* 04-spill: the glass is full to the rim, two 5 px orange sheets run down its walls, one small puddle (x 790–860, y 1890–1915), a "SPILL" word (x 618–830, y 1510–1580). The jug is already upright and there's no stream, splash or shake. The only consequence is a red cup top-left.
- *Why:* Failure must be as satisfying as success in push-your-luck games (Threes' "game over" reveal, Alto's crash tumble). It's also the moment that teaches "stop earlier".
- *Fix:* Judge SPILL **live** in `GameSession` the moment it overflows (don't wait for serve), and in `GameScene`/`SceneFX`: a 0.25 s screen shake (skipped under Reduce Motion), a thick overflow sheet (≥ 40 % of the rim width) with a lip "bulge" before it breaks, a puddle that spreads 2–3× wider across the coaster and counter, droplets hitting the counter, the strike cup flying from the shelf and turning red, and the customer's "hmm". The glass then slides out wet and dripping.

**P1-3. The fill line and the Perfect band are unreadable.**
- *What I see:* the line is a dashed white stroke with a thin gold edge, ~5 px tall (02 y ≈ 1752; 03 y ≈ 1730). On lemonade (03) the white dashes vanish into `#FFF7A6`. No Perfect band glow is visible in any mid-pour frame (02, 05, 06, 07, 13), despite GAME-DESIGN §5.
- *Fix (`SceneGlass`):* a solid 3 pt ink line (`#2B2233` at 85 %) with a 1.5 pt white halo, overhanging both walls by 8 pt; keep the gold tab but make it 1.5× larger. While pouring, draw the Perfect band as a translucent cyan `#3FD0FF` strip of exactly ±band × interior height, brightening as the projected level enters it. That band is also the best teaching device for "stop before the line".

**P1-4. The stream lands hugging the right wall; splash droplets look like leaks.**
- *What I see:* 02: stream lands at x ≈ 755, glass centre 726, interior ±~40 px → right third. 05/07: same, and splash droplets fly out *through* the right wall (05: brown dots at x ≈ 775–795, y ≈ 1800–1870, outside the glass's right wall at x ≈ 770; 07: orange dots at x ≈ 770–810 falling down to the coaster), so a perfect pour reads as spilling.
- *Fix:* `CoreTuning.glassPlacementBias` −4 → about +10 (re-measure against the autopilot's typical angle). In `SceneFX.splashCrown`, constrain droplets to the mouth (|x − glass.x| < rimHalfWidth − 3) and render them on the glass-back layer, so they stay inside.

**P1-5. The stream is a thread, and thick drinks look like water.**
- *What I see:* 02, 07, 13: the ribbon is 6–10 px at the lip, 4–5 px at the glass. 06 (milkshake) is a 6 px pink line; 05 (cola) a 5 px brown line.
- *Fix (`CoreTuning` / `SceneStream`):* streamWidthMax 18 → 26, streamThinFloor 0.45 → 0.6. Add per-liquid width and wobble: milkshake/honey 1.6× width with slow "coiling" folds where they land; water/lemonade a glassy highlight core (already there, so widen it); cola with a few rising bubbles in the stream. A thick, glossy pour is half of the satisfaction.

**P1-6. Venues are recolours.**
- *What I see:* 05 (Soda Fountain) = pink tiles and a red front; 06 (Milkshake Diner) = blue tiles, a pink counter and a teal front. Same shelf, same bottles, same chalkboard, same clock, same glass pitcher in every venue. Daily (13) and Rush (07) are the Lemonade Stand.
- *Why:* Venues are the progression reward. If venue 2 looks like venue 1 with a filter, the unlock doesn't land, and five store screenshots look the same.
- *Fix:* `ScenePalette` + `SceneArt`: one signature prop set and **one signature vessel** per venue. Lemonade Stand = striped awning and a lemon-slice pitcher (the icon's teal jug). Soda Fountain = chrome tap tower, checkerboard backsplash, a soda-jerk dispenser jug. Milkshake Diner = steel shake tin to pour from, neon "DINER" sign, chrome counter edge. Conveyor = visible belt with rollers. Potion Shop = candles, a round-bottom flask to pour from. Rush: a dusk palette with string lights. Daily: a calendar tear-off with "#297" on the wall.

**P1-7. HUD collisions and missing context.**
- *What I see:* 02/03/04: the score numeral (x 50–270, y 50–145) sits over the jar/bottle silhouettes. The strike cups (y 195–260) hang off the shelf board (y 190–205). 01: the "Brim" wordmark (x 75–540, y 85–250) is pierced by the shelf at y ≈ 195, with the plant pot behind the "i" and the gear button (x 1008–1150) over the bottles. 12/01: the hint pills overlap the jug (12: "Drag up to pour." x 135–685, y 792–930 covers the jug rim and spout; 01: "Fill every glass to the line." y 1178–1266 covers the jug's belly). No shift name or "glass 2 of 5" anywhere in play; Daily and Rush show nothing that says Daily or Rush.
- *Fix:* `SceneArt.paintShelf`: when HUD is shown, keep the top 120 pt of the wall clear (move the shelf down under the HUD or drop silhouettes behind text). `PlayOverlays`: add a small title chip ("Lemonade Stand · 1", "Daily #297", "Rush"). `HomeView`: put the wordmark on a clean wall area (shelf moved to y ≥ 300 pt or removed on Home). Hints: place by the jug's world bounds (to its left on the phone, above it on the Duo), never over it.

**P1-8. Store-frame truthfulness (fabricated states).**
- *07-rush:* score "0" with "×3 · 7 in a row" and "0 served" — impossible together (`DemoMode streak=7` seeds the pill but not the score or count).
- *08-results:* "Lemonade Stand · Shift 1 — Flawless shift!" with 6 glasses (shift 1-1 has 5 orders), 4 perfect + 1 great + 1 good, and a score of 1,240 that the scoring rules can't produce from those judgements (≈ 590 max). "Flawless" is also wrong for a run with a Good in it.
- *06:* the upright-jug stream (P0-4).
- *Fix:* `App/DemoMode.swift`: generate demo results by actually running the session headless with the autopilot (or compute the score with `Rules.points` / `Rules.multiplier`), seed the streak by playing 7 real Perfects, and pick the level whose order count matches. `ResultsView.headline`: "Flawless" only when every glass is Perfect; 3 stars with non-Perfects → "Great shift!".

**P1-9. The game doesn't look like its icon.**
- *What I see:* the icon has an opaque teal ceramic jug, a lemon roundel, a thick glossy stream with highlights, and a chunky rocks glass. The game has a pale, low-contrast glass pitcher (1.5 px grey outline, white-on-cream) whose transparency makes it read washed-out on mint tiles.
- *Fix:* `SceneJug`: keep the liquid visible (players need it to read the jug level) but give the jug body the icon's language: a coloured rim band and handle (teal `#2BA59A`), the lemon roundel decal, a 3 pt ink-tinted outline, and a stronger glass highlight. Same treatment on `SceneGlass` (thicker rim, brighter specular). Then the icon, the store frames and the first second of play feel like one product.

**P1-10. Onboarding teaches the control, not the goal.**
- *What I see:* 12-first-run: "Drag up to pour." and a floating ↑ arrow in a white circle (x 325–495, y 565–735) that looks like a button, wedged against the chalkboard. Nothing points at the line or says "fill to the line" in play (that copy only exists on Home).
- *Fix:* `PlayOverlays.HintsOverlay`: hint 1 = "Drag up to pour" with an animated finger (or the lid on Duo) beside the jug, plus a pulsing callout on the glass's line: "Fill to here". Make the arrow a non-button glyph (no card background). Hint 3 ("The stream keeps falling — stop just before the line") should appear **during** the first pour at 60 % (when it's actionable), not after the serve.

**P1-11. Results screen: dead space, no per-glass story.**
- *What I see:* 08: the card ends at y 1097; y 1100–1740 is an empty peach gradient with a ghost of the jug; buttons at y 1740–2165; y 2165–2622 empty. The "NEW BEST" pill (x 770–1030, y 650–748) overlaps the "0" of 1,240. Shifts hide the judgement strip (`ResultsView` shows it only for non-shift modes).
- *Fix:* Show the glass-by-glass strip for shifts too, as a row of mini glasses filled to their actual levels against their lines (the recap *is* the content). Move "NEW BEST" above the score. Vertically centre the card in the top half and the buttons in the bottom half (`DuoSplit` on phone should split at 52 % with real content in each half). Show "next unlock: 3★ to Milkshake Diner" under the stars.

### P2 — polish

- **P2-1 Venues screen (09):** solid but generic. "Lemonade Stand" wraps to two lines next to "20/24" (shrink to 26 pt or let the stars sit under the subtitle). The Milkshake Diner icon is a coffee cup and saucer (use a shake glass with a straw). Locked shift circles are beige blobs: show the shift name on tap, and a venue-level lock line ("12 more ★"). Add a small illustrated header per venue, which reuses the P1-6 art. File: `UI/VenuesView.swift`.
- **P2-2 Rush patience ring (07, 13):** a 30 px green ring floats at (812, 1525), ~60 px off the glass rim, unexplained. Attach it to the glass (a ring around the coaster, or a draining band on the glass wall). File: `SceneGlass`.
- **P2-3 Foam (05):** the head is a flat beige band with a hard top edge, which reads as a layered drink. Give it a bumpy dome top, micro-bubbles, a lighter rim, and visible settling (the top edge sinking). File: `SceneGlass`.
- **P2-4 Home (01):** the stats pill sits on the virtual crease, over the jug. The middle band y 400–835 is wasted; put the lifetime stats or the daily streak there, on a chalkboard (the chalkboard is already drawn, so make it *carry* the Daily status: "Daily #297 · not poured yet").
- **P2-5 Icon:** the fold seam (1 px at 1024) disappears at home-screen size; make it 4–5 px with a soft shadow so "foldable" survives at 60 px. File: `UI/AppIconArt.swift`.
- **P2-6 Reduce motion** is shown as "Off · Follows your system setting" with no control: either make it a toggle or remove the row.
- **P2-7 Retention layer is thin on screen:** the Glass Cabinet (GAME-DESIGN §9) isn't visible anywhere, and there's no daily streak counter. Add a "Daily streak 🔥 4" on the Daily button and a cabinet of unlocked glass skins (cheap, high-value collection hook).
- **P2-8 Audio for the line:** experts "pour by ear", but nothing marks the band in sound. Add a faint, pitched "shimmer" layer that fades in when the *projected* level enters the Perfect band (`SoundBook.pourBed`). It's also a great accessibility aid.
- **P2-9 Venue 1 is long and samey:** 8 shifts of one verb before the first twist, although stars unlock Soda at 8★ (good). Add one micro-twist mid-venue: 1-4 "a customer wants it half full" (a low line in a big glass), 1-6 two glasses side by side (choose which to fill first). File: `Core/LevelCatalog.swift`.

---

## 4. Top 8 fixes for round 2 (in order)

1. **Rescale and recompose both canvases (P0-1, P0-2).** Phone: zoomed world (glass ≥ 64 pt, counter front ≤ 12 %). Duo: no chalkboard/clock in the top half, a one-row HUD, the bottom half painted as a counter top, the glass centred in the flat half and clear of buttons. *Files:* `Shared/Contracts.swift`, `Scene/SceneArt.swift`, `Scene/SceneGlass.swift`, `UI/PlayOverlays.swift`, `UI/HomeView.swift`, `UI/ResultsView.swift`.
2. **Fix the Duo rest pose (P0-3).** Relative hinge calibration (or a flat-start gate) and copy/drawing that match it. *Files:* `Input/HingeTiltSource.swift`, `Core/Rules.swift`, `Core/GameSession.swift`, `UI/PoseCards.swift`, `UI/PlayOverlays.swift`.
3. **Make the pour physically true and fat (P0-4, P1-5, P1-4).** No stream from an upright jug, liquid connected to the spout, a ≥ 1.5× thicker ribbon, glass centred under the stream, splashes contained. *Files:* `Core/GameSession.swift`, `Core/JugGeometry.swift`, `Scene/SceneJug.swift`, `Scene/SceneStream.swift`, `Scene/SceneFX.swift`, `Core/CoreTuning.swift`.
4. **Make Perfect a fireworks moment and Spill a disaster (P0-5, P1-2).** A big ring, flash, glass hop, stamp on the rim, streak flying to the HUD; a live spill with shake, a sheet, a spreading puddle and a flying strike cup. *Files:* `Scene/SceneFX.swift`, `Scene/GameScene.swift`, `Scene/SceneGlass.swift`, `Core/GameSession.swift`.
5. **A readable line and a visible Perfect band, plus an instant lock cue and tighter serve timing (P1-3, P1-1).** *Files:* `Scene/SceneGlass.swift`, `Core/CoreTuning.swift`, `Feedback/FeedbackDirector.swift`.
6. **Safe areas and the broken stand-up card (P0-6, P0-7).** *Files:* `UI/RootView.swift`, `UI/PoseCards.swift`.
7. **Venue identity and the icon's art language in game (P1-6, P1-9).** A signature vessel and props per venue; a teal-accented jug. *Files:* `Scene/ScenePalette.swift`, `Scene/SceneArt.swift`, `Scene/SceneJug.swift`.
8. **Honest, well-composed store frames and screens (P1-7, P1-8, P1-10, P1-11).** Real demo results, a HUD title chip, hints that don't cover the jug, a goal-first first run, results with a per-glass recap. *Files:* `App/DemoMode.swift`, `UI/ResultsView.swift`, `UI/PlayOverlays.swift`, `UI/HomeView.swift`.

---

## 5. Launch call

**Not yet.** The idea is a hit-shaped idea and the engineering underneath (physics, synthesized audio, haptics) is better than most £1.99 games ship with. But today the hero moment is small, quiet and sometimes physically wrong. The Duo frame, the reason this app exists, is predicted to collide on top and bury the glass below, and the rest pose will spill the first glass for anyone who follows the on-screen instruction. Fix the top 8, capture real Duo tabletop frames, and I'd expect round 2 to land around 7–7.5, with launch quality reachable in round 3.
