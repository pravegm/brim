# QA-2: first-hour audit, real Duo and iPhone 16 (read-only)

*QA lead, second pass, 26 Oct 2026. Like QA-1, this audit is code reading only: Core, Input, Feedback, Scene, App, UI, Persistence and the store docs. I also did numeric checks in Node, porting `JugGeometry`, `GlassMath`, the level catalog and the foam model (scratch only). Every item below was traced end to end. Items marked **suspect** depend on hardware or OS behaviour that code can't settle. The round-4 fixes for QA-1's four P1s are in place and look correct (stored-hinge trust, the Daily attempt marker, keeping the run on a canvas swap, the idle timer).*

**Summary.** I verified no P0. One **suspect** could block play entirely on the real Duo: the flat gate's 174° threshold. I verified four P1s:
- the closing guard re-arms the flat gate on any brisk lift;
- the empty-jug auto-refill gushes in mid-pour;
- foam and other over-the-band pours are stamped "SPILL!" when nothing spilled;
- the four venue achievements fire on unlock instead of on clearing the venue.

All four will show up in the first hour on the Duo. The first two are Duo-feel bugs that the CI autopilot can't hit: it is capped at 160°/s and plays perfect pours.

---

## P0: crash, data loss, unplayable

None verified.

### P0-suspect. The flat gate may never open on a real Duo, and there's no way out
- **Where:** `Core/Rules.swift:8` (`deadZone = 6`). `Core/GameSession.swift:259-262` opens the gate only when `lidTilt < 6`, which means a filtered hinge angle above 174°. `UI/PlayOverlays.swift:405-445` (the gate card has no button). `App/GameController.swift:811-818` hides the card only under touch.
- **Why I suspect it:** research/02 §summary says "A hand at rest reads ~175°" and "~±5° accuracy". research/03 suggested ≥ 172°. If the founder's Duo, lying flat on a table, reads 170–174°, the scenario below follows.
- **Repro (if the hardware reads ≤ 174° when flat):** tap Play, see "Lay it flat to start", lay the phone flat. The card never clears, no outflow ever happens, patience stays frozen, and the run never starts. The only escape is Settings → "Touch controls on iPhone Duo", and a first-time player has no reason to look there.
- **Minimal fix:** arm the gate at `lidTilt < 12` (θ ≥ 168°), or arm on "within 4° of the highest angle seen in the last 2 s while still". After 6 s on the gate, show a quiet "Can't get it flat? Use touch" button that calls `chooseTouchInBookPose`-style logic, as a run-only override. **Check this first in the TestFlight session:** lay the phone flat and log `BRIM-H`. In Release the log is off, so watch whether the card clears.

---

## P1: visible bugs a paying player will hit in the first hour

### P1-1. A brisk lift (or resuming a lift after a hold) re-arms the flat gate mid-glass
- **Where:**
  - `App/GameController.swift:529-531` calls `session.requireFlat()` whenever `hinge.isClosing` is true.
  - `Input/HingeTiltSource.swift:42-46`: `isClosing` is `closingGuard.isCut`.
  - `Input/TiltFilters.swift:107-129` cuts on any closing speed above **160°/s at any angle**. The first report after ≥ 0.25 s of silence is timed as 1/30 s, so a single report with a drop above 5.3° counts as fast. The report gap is clamped to ≥ 1/60 s, so two callbacks that arrive bunched inflate the speed.
  - On the Duo, **pouring is closing the hinge** (180° toward 90°).
  - CI can't see this: `BrimTests/InputTests.swift:561-562, 612` caps the autopilot at 160°/s.
- **Repro:** on a Duo in 1-1, with the gate open:
  - (a) flick the lid up about 30° in 0.15 s (200°/s); or
  - (b) pour, hold still for 0.5 s (the Duo stops reporting), then tip further. The first report after the silence shows a drop of 6° or more.

  → The jug snaps upright and the stream is cut (`requireFlat` sets `outflow = 0` and `headlessTime = ropeMax`). About 0.35 s later the card **"Lay it flat to start"** appears mid-glass. It says "to start" because `hud.gateAfterPause` is only set by `resumeHook`. The glass is then held (`resumeHold`) until the player lays the phone flat and pours again. Repeat on every quick tip. Pushing past 78° to drain the last drops does the same through the below-78° latch.
- **Suspect part:** how often real hands go over 160°/s, and how large the first report after a hold is. The code path is verified.
- **Minimal fix:**
  - In `advance`, call `requireFlat()` only for the latched below-78° state (`closingGuard.belowLatch`), not for the fast-close hold. During the hold, `tilt()` already returns `closedTilt`, so the jug is upright with no outflow.
  - In `ClosingGuard.sample`, count a fast close only when `angle < 120°`, or when two consecutive reports are fast.
  - If a re-gate stays, set `gateAfterPause = true` there so the card doesn't say "to start".

### P1-2. The empty-jug auto-refill arrives mid-pour and gushes into the glass
- **Where:**
  - `Core/GameSession.swift:518-538` (`checkJugEmpty`, non-Rush): when fill drops below 2.5 % (which only happens *while pouring*), it starts a 0.6 s swap to `max(startFill, 0.5)`.
  - `:291-302` swaps the fill.
  - `:394-446`: the next sub-step pours at the player's **current** angle, with rise τ = 0.03 + 0.2·lag.
  - `Scene/GameScene.swift:678-708`: the new jug slides in already tipped.
  - No test covers this (no `swap` or `refill` in BrimTests).
- **Numbers (Node port):**
  - To get below 2.5 % the player is at jug ≈ 77–80° (lid about 56°, hinge about 124°).
  - A refilled 0.5 jug at 77° pours about 8,400 pt²/s. A 0.8–0.9 jug pours at the 16,000 pt²/s cap.
  - Sand also gets the avalanche ×2.6, about 41,000 pt²/s.
  - A tumbler's Perfect band is ±~450 pt². Even a 0.3 s reaction plus the 0.45 s fall puts 5,000–12,000 pt² in the glass.
- **Which shifts are certain to hit it** (drink demand ÷ jug, excluding waste):
  - Certain: 1-3 Fresh Squeezed 1.08, 2-7 Root of the Problem 1.71, 3-6 Smooth Operator 1.30, 6-4 Sands of Time 1.45.
  - Borderline (any overpour or foam spill tips them over): 1-2 0.93, 2-2 0.96, 2-3 0.99.
  - In 2-7 the gush is root beer at the maximum foam factor, so the glass is all but certain to overflow.
- **Repro:** play 1-3 accurately. During glass 6 (jar, line 0.75) the jug runs low, so you tip further. The jug flies away and a full one drops in already tipped. Orange juice floods the jar: a Spill, and a strike in the shift's last glass.
- **Minimal fix (either):**
  - (a) Refill between glasses: in `sendToStop`, if the jug's fill × volume is under the order's need × 1.3, refill there while the player is upright. Keep the < 2.5 % swap as a fallback only.
  - (b) After an empty-jug swap, hold the outflow until the jug angle drops below the new fill's `pourThreshold` (a "tip back" gate like `requireFlat`), and hold serving (`resumeHold`).

### P1-3. "SPILL!" for glasses that never spilled (foam judged before it settles, and any over-the-band pour)
- **Where:**
  - `Core/Rules.swift:30` returns `.spill` whenever `err > goodBand`, even if nothing overflowed. GAME-DESIGN §5 says Spill = "any liquid over the brim" and Good = "over but below the brim".
  - `Core/GameSession.swift:980-983` serves a foamy glass after a fixed `serveIdle + foamServeGrace` (0.35 + 1.2 s, `CoreTuning.swift:162-166`), even if the head is unsettled.
  - `:987-992` judges `visibleTop` with the foam included.
  - Root beer's settle τ is 2.0 s (`LiquidCatalog.swift:26-28`).
  - `Scene/GameScene.swift:622-624, 641-650` plays the full spill on a judgement-only `.spill`: overflow sheet, droplet burst, screen shake. `FeedbackDirector.swift:310-311` adds the splash sound and the heavy buzz.
- **Repro (Node foam model):** Soda Fountain 2-2, mug of root beer, line 0.60. Pour at a normal flow (about 0.35, roughly lid 15° past the pour point) until the *liquid* reaches the line, then stop.
  - About 1.9 s later the judged top is about 0.74 (+13.8 %), so the glass is stamped **SPILL!**: a strike, the streak lost, a splash and a shake. The head then settles, leaving the liquid **exactly on the line**, with nothing ever over the rim.
  - Same model, but stopping when the *visible* top hits the line: judged 0.43, a Short.
  - Non-foam version: in 1-1, fill a 0.60 tumbler to 0.75. It is stamped SPILL! and a fake overflow sheet runs down a glass that is a quarter empty.
- **Minimal fix:**
  - Judge `.spill` only when `overflowed`. Map err > good to a miss that strikes like Short but is named and drawn honestly, for example "TOO FULL", with no sheet and no shake.
  - For foam, judge `liquid + min(foam, settled allowance)`, or wait for `settled` up to about 2.5 × `foamSettle` (cap 4 s) before serving.

### P1-4. Venue achievements unlock when the venue *opens*, not when it's cleared
- **Where:** `Persistence/ProgressStore.swift:249-252` (`isUnlocked(.sodaFountain)` → `brim.venue.soda`, and the same for diner, conveyor and potions). `docs/appstore/achievements.md:38-41` defines them as "Clear every shift at the …". `:43`: `brim.sandbar` is "Every Sand Bar shift cleared", but the code grants it at 1 star on any Sand Bar shift (`:254`).
- **Repro:** finish Lemonade Stand shift 8 and reach 8 stars. A Game Center banner says "Head for Foam: Foam tamed. Slow, then top up." before the player has poured any soda. Game Center reports can't be taken back once they're sent.
- **Minimal fix:** grant each one when `LevelCatalog.levels(in: v).allSatisfy { stars(for: $0.id) >= 1 }`, and do the same for the Sand Bar.

---

## P2: minor, edge cases, polish

**Venue mechanics**
1. **Fading lines keep fading behind the Duo flat gate.** `GameSession.swift:920-924` fades the line from `arrivedAt`, but patience (`:968`) is frozen while `needsFlat`. In 5-3, 5-6 and 5-8 the player taps Play in tabletop pose, lays the phone flat (about 1–2 s), and the first glass's line has already faded before they can pour. **Fix:** start the fade from the gate opening (track an `armedAt`), or pause it while `needsFlat`.
2. **Conveyor verdict misses liquid already inside the mouth.** `:960-966` judges when the mouth passes the stream. Particles with `glassID == id` that are still falling inside the glass land after the verdict (`:625-644`). Pouring at flow 1 at the exit puts about 0.08 s ≈ 800 pt² (+5 % on a tumbler) on top of a "Perfect" or "Great". **Fix:** include in-mouth particle volume in the conveyor judgement, or judge once no particle has `glassID == id`.
3. **The belt runs during the 0.8 s intro on phones.** `:890-893` moves the belt, but pouring is blocked until `phase == .playing` (`:395`). The first glass of each conveyor shift loses about 0.35 s of its roughly 0.9 s lead-in. On the Duo the gate hides this. **Fix:** move the belt only when `phase == .playing`.
4. **Rush still never ends if you stop playing** (QA-1 P2-2, still open, `:1025-1027`). Pause → Menu throws the run away: no `rushBest`, no Game Center score (`GameController.swift:486-488`). The only way to bank a good run is to spill three times. **Fix:** count 3 timeouts in a row as the end, or offer "End run and keep 8,000?" on Menu.

**Daily**

5. **Free retry by bailing during glass 1.** `closeDailyAttempt` drops an attempt with no serves (`ProgressStore.swift:228`). Pause in mid-overpour on glass 1 (pausing stops it from being served), then Menu, and a fresh scored Daily is back. **Fix:** file a 0 once the first pour has started.
6. **A Daily filed silently after the app is killed.** A call, a backgrounded app, then iOS ends the process: at the next launch the partial pour becomes the day's score (`ProgressStore.swift:309-312`) with no message. **Fix:** show "Daily #298 saved at 3 glasses" once on Home.
7. **A Daily that crosses UTC midnight counts locally but never reaches Game Center.** `isStale` drops it because `day != today` (`GameCenterManager.swift:88-92, 125-131`).
8. **"Today's scored pour. New glasses tomorrow."** (`ResultsView.swift:264`) is wrong for most of the Americas: the Daily rolls over at UTC midnight (`LevelCatalog.swift:118-130`), which is 7–8 pm local time on the US East Coast. Say "New glasses at midnight UTC", or show a countdown.

**Input, platform and interruptions**

9. **Home gesture on touch phones (suspect).** "Drag up anywhere" (`RootView.swift:209-228`) has no `.defersSystemGestures(on: .bottom)`, and `.persistentSystemOverlays(.hidden)` (`:46`) doesn't defer it. On an iPhone 16, a drag that starts in the bottom ~20 pt goes Home mid-pour. The narrow-phone hint card sits in that band too. **Fix:** add `.defersSystemGestures(on: .bottom)` to the play layer while `usesTouch`.
10. **Unplugging AirPods keeps the game playing on the speaker.** `BrimAudioEngine.swift:314-319` restarts the engine on every route change. That's acceptable for a game. If it isn't wanted, check `.oldDeviceUnavailable` and duck or pause.
11. With "Touch controls on iPhone Duo" on, the closed-pause card still says "It carries on once the phone lies flat" (`PlayOverlays.swift:503-508`). Under touch it carries on as soon as the phone is opened past 100°.
12. The Settings toggle "Touch controls on iPhone Duo" shows on every iPhone (`SettingsView.swift:35`). Show it only when `hingeSeen`.

**Copy (4+ rating, consistency)**

13. **"Last call!"** is the headline of every Rush result (`ResultsView.swift:56`). It's the bartender's call for the final alcoholic orders, and it sits awkwardly next to "Alcohol references: None" and the "no alcohol words" rule (`metadata.md:151`). Suggest "Closing time!" or "Shift's over!".
14. Soda Fountain 2-2 "Head Start" and 2-7 "Root of the Problem" fill Diner Mugs and "Soda Glasses" (pints) with foamy amber root beer to 0.85–0.9. In play that reads as beer, which `metadata.md:221` warns against for store frames. Keep root beer out of captures, and consider cola or cream soda for the mug and pint lines.
15. **"×7 STREAK"** stamp (`SceneArt.swift:419`) uses × for the streak count, while the HUD uses × for the *multiplier* ("×3 · 🔥7", `PlayOverlays.swift:120-130`). Use "7 IN A ROW" or "🔥7".
16. The "Respect silent mode" footnote says "ring switch" (`SettingsView.swift:32`). iPhone 15 and later, and the Duo, have no switch. Use "even in Silent Mode".
17. 40 shift titles ("Grand Opening", "Fizzy Lifting"…) appear only in the locked-shift note (`VenuesView.swift:177`). Show them on the pause and results cards, or drop them. "Fizzy Lifting" echoes Wonka's "Fizzy Lifting Drinks", which is low IP risk.
18. `metadata.md:75`: in Rush, "Three spills, or an empty jug, and the **shift** is over". It's a run, not a shift.
19. No in-app path to the leaderboards: `GKAccessPoint` is off (`GameCenterManager.swift:40`) and there's no Game Center button. The store copy says "Chase your best on the Game Center leaderboard". It's reachable only through Apple's Games app.

---

## Verified clean (no action)
- **Frame-rate independence (low power, 120 → 60 Hz):**
  - Scene `dt` is clamped to ≤ 1/30 s (`GameScene.swift:300-304`), the App clamps again (`GameController.swift:523`), and Core sub-steps at ≤ 1/240 s for any frame rate.
  - Touch springs, One-Euro, the predictor and the HUD 15 Hz gate all use real time.
  - Below 30 fps the simulation slows down rather than tunnelling.
- **Interruptions:**
  - Control Center, Siri, the app switcher, calls and screen lock make the app inactive. A live run then gets the user pause and touch is cancelled. Resume re-arms the gate.
  - A notification banner doesn't pause (correct). The idle timer is off only during a live, unpaused run.
  - An audio interruption silences queued one-shots and stops `heal()` from churning.
  - "Respect silent mode" switches `.playback` ↔ `.ambient` live. Sound and Haptics off really stop their engines and drop one-shots.
  - "Calmer motion" gates the shake, the camera bump and the HUD pop.
  - Reset keeps Daily results, as the alert says. It also clears the learned hints, which the alert doesn't mention (harmless).
- **Progression:**
  - Thresholds 8/18/30/44 against the stars available (24/48/72/96) all work. Every one is reachable with 1 star per shift plus a few extras.
  - The Sand Bar needs all 40 shifts at 3 stars, exactly as the card says.
  - "Next shift": at the last shift of a venue it shows only if the next venue is open, otherwise "Next unlock: N more ★". At 5-8 it leads into the Sand Bar only after all stars. At 6-4 there is none.
  - Locked shift bubbles explain themselves.
  - The Daily marker files leave, restart and crash. The share line uses the scored attempt.
- **Venue physics:**
  - Sand flows at maximum tilt at every fill: it needs at most jug 107° of the 130° available.
  - No jug soft-locks, because the auto-refill covers it (but see P1-2).
  - Every line is reachable: the stream (≤ 13 pt half-width) plus the ±8 pt placement fits every mouth, the narrowest being the flute at 32 pt.
  - Clean root-beer pours fit inside every patience timer (the slowest, pint 0.9, takes about 8.6 s against 13 s).
  - Viscous serving waits for the rope and the tail to land.
- **First launch:**
  - Book pose shows the turn card with "Use touch". Closed shows the cover card.
  - Half-open in tabletop gives Home, then on Play the gate (lift hint hidden), then the lift hint plus "Fill to here", then the stop hint at 60 %, then the anticipate hint after a first spill.
  - Game Center never presents its sheet.
  - On an iPhone 16 the same sequence runs with drag copy, in portrait only, with a stale `brim.hasHinge` ignored.
