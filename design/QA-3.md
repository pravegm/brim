# QA-3: rounds 5 and 6 audit (read-only)

*QA lead, third pass, 26 Oct 2026. This is a code-reading audit of `9c2c7cc..264756e` (round 5 = QA-2 fixes, round 6 = late game), plus the uncommitted `Rules.stars` change in the working tree. It covers Core, Input, Feedback, Scene, App, UI and Persistence, and the r6 CI frames. Nothing was built or run: there's no Mac, and CI is the compiler. **Verified** means the code path was traced end to end. **Suspect** means it depends on timing or hardware, or on numbers I estimated.*

**Summary.**
- **No P0.** I found no crash, data loss or soft-lock. Every stuck state I could build in the dry-jug, gate and swap logic heals itself.
- **Frame 26:** the empty glass under PERFECT is not a redraw bug. The stamp belongs to the *previous* glass, which is already sliding off screen. A safe-area clamp pins the stamp in place, so it hangs over the next glass. This happens on every glass changeover, not just tier changes. It is P1-1.
- **P1-2:** the new results "3★ needs …" line will state the wrong rule once the balance engineer's `Rules.stars` lands.
- **P1-3:** the conveyor venue intro card says "Pour to start", but the belt is already running underneath it.

---

## P0: crash, data loss, unplayable

None verified.

---

## P1: visible bugs a paying player will hit

### P1-1. The last glass's stamp hangs over the next, empty glass on every changeover (CI frame 26)
**Where:**
- `Scene/SceneGlass.swift:1222-1226` (`clampedLocalX`) and `:1259-1268` (`drawStamp`): every frame, the stamp's world x is clamped into `safeX`.
- `Scene/GameScene.swift:516-519` passes `safeX` (phones: about 130…540; Duo: about 14…656).
- Core: `GameSession.swift:997-1001`. The served glass goes `.leaving` after `resultHold` (0.3 s) and slides to x = 800 over 0.45 s. In the same step, `advanceQueue → sendToStop` (`:1324-1377`) slides the next glass in. In Rush, that is also where `rushTierNow` changes (`:1376`), so the tier banner, the chord and the venue cross-fade all start at this instant.

**Why frame 26 looks the way it does:**
- `freezeOn=tier` freezes 0.35 s after the tier change. At that moment glass 12 is at u = 0.78 of its leave (x ≈ 335 + 465 × 0.67 ≈ 646), so it is already off the phone crop (x ≤ 554).
- Its PERFECT stamp is clamped to `safeX.upper − halfWidth` ≈ 540 − 150 = 390. That is right above the stop (≈ 335), where glass 13 (a Soda Fountain flute) has just arrived (easeOutCubic(0.78) ≈ 0.99). Glass 13 is correctly empty.
- So the glass views are **not** rebuilt on a venue change, and the liquid is drawn correctly. The stamp is not attached to the new glass either; it is pinned on screen while its own glass leaves.
- The same thing happens for about 0.25 s on every changeover in every mode. On the Duo the stamp pins at x ≈ 506 as its glass rides out.

**Repro:** play 1-1 on an iPhone. After any verdict, watch the stamp stay put as the old glass slides right, landing over the next glass. Or look at `design/frames/r6/26-rush-tier.png`.

**Minimal fix** (SceneGlass `drawStamp`): clamp only while the glass is not leaving. Once it leaves, keep the last local x so the stamp rides out with its glass, and fade it quickly:
```swift
if g.phase == .leaving {
    stamp.removeAction(forKey: "pop")            // or removeAllActions(): the pop is long done after resultHold
    stamp.alpha = max(0, stamp.alpha - f.dt * 8) // gone in ~0.12 s, rides out at its last local x
} else {
    stamp.position = CGPoint(x: clampedLocalX(...), y: min(desired, limit - top))
}
```
Re-shoot 26 afterwards. It is a likely store-frame candidate, and right now it shows something the app doesn't mean (bar 3).

### P1-2. The results line will contradict the new star rule (note only; the change is mid-flight)
**Where:**
- `UI/ResultsView.swift:128-143` (`chaseLine`) hard-codes the old rule: *"3★ needs every glass a hit and 5 of 8 Perfect. You had 3 Perfect, 1 miss."*
- The uncommitted `Core/Rules.swift:81-87` makes 3★ = **no misses** (Perfect count ignored), 2★ = 1 miss, 1★ = 2 misses.

**Repro (once Rules lands):** clear 1-2 with one Short and the rest Perfect. The card shows 2★ and says 3★ needs "every glass a hit and 4 of 6 Perfect", but the player had 5 Perfects. The real reason is the one miss.

**Fix:** when `stars < 3`, say *"3★ needs every glass a hit. You had 1 miss."*, keep the crown line for 3★, and update the AppTests expectation in the same commit as `Rules.stars`. Two more things go with that change:
- `GameSession.finish` (`:1200`, `if stars < 1 { cleared = false }`) is now dead code: a cleared shift always has ≤ 2 misses, so at least 1★.
- The Sand Bar (all 40 shifts at 3★) gets much easier. That's the balance owner's call; flag it to them.

### P1-3. The conveyor intro card says "Pour to start", but the belt is already moving under it
**Where:**
- `App/GameController.swift:934-937` puts the card up at run start.
- `UI/LateGameOverlays.swift:111` says "Pour to start, or tap to close".
- `Core/GameSession.swift:991` moves the belt as soon as `phase != .intro && !needsFlat`. Nothing knows a card is up.
- On a phone the card sits mid-screen over the stream path (`LateGameOverlays.swift:48-51`; see frame 24), and only the card takes touches, so a drag that starts on it doesn't pour.
- On a Duo the card appears the moment the flat gate opens, which is also when the belt starts.

**Repro:** with fresh hints, play 4-1 ("Belt It Out", belt 16 × 1.5 = 24 pt/s). Read the card. Glass 1's window ends about 5 s after the intro (lead-in 21.6 + 2 × rim + 6 pt at 24 pt/s). A first-timer who reads the card, then drags (from the card, which fails), is likely to pour too late: a Short and a strike on the glass meant to teach the belt.
- **Suspect part:** how often it happens; it depends on reading speed.
- The same holds for patience rings on the first shift of other venues. It's milder there: patience is ≥ 12 s.

**Minimal fix:** while a venue intro card is up, hold the run the way the flat gate does.
- Add `GameSession.setStartHold(_ on: Bool)`. It freezes the belt, patience and `lineClock` exactly where `needsFlat` already does (`:991, :1021, :1073`).
- The App sets it with the card and clears it in `dismissHint()` and on `.pourStarted`.
- Or keep the card's copy honest: "Tap to start".

---

## P2: minor, edge cases, polish

**Rush travels (round 6)**
1. **Rush's conveyor tier has no belt queue.** `GameScene.upcomingOrders` (`GameScene.swift:57, 653-657`) is never set by the App, and Rush has no `shiftOrders`. Decision 3's "next glasses visible on the belt" only exists in shifts. Fix: publish `session.upcomingOrder` (or the next two plans) from the App.
2. **At the 3→4 (and 7→8…) tier change, the first Diner glass slides in on top of the last belt glass (suspect, ~0.1–0.2 s).**
   - A belt serve calls `advanceQueue` at once (`GameSession.swift:1186`). The new glass slides from x = −130 to the stop in 0.45 s. The served belt glass sits at landing + rim + 6 and only starts leaving after `resultHold`.
   - My estimate is 10–20 pt of overlap around t ≈ 0.3 s. At the same moment the belt slats vanish (palette switch) under the still-riding glass.
   - Fix: for a belt → non-belt change, send the next glass only when the belt glass leaves, as non-belt glasses do.
3. **In Rush, the stream changes drink in mid-air at belt serves.** `GameSession.swift:1335-1336` sets `jugLiquid` instantly in `sendToStop`, which on a belt runs at the serve, often mid-pour. The stream's colour and its rope/lag (water → honey at tiers 3→4) flip under the player's hand. Cosmetic in most cases. Fix: defer the change until `outflow == 0`.
4. **The conveyor bell's sound and visuals disagree at tier edges.**
   - Feel rings on `.served → .leaving` while `snapshot.venue == .conveyor` (`LateGameCues.swift:113-129`). Scene flicks on `.served` of a belt glass (`GameScene.swift:974-979`), 0.3 s earlier.
   - At 2→3, the last Soda glass (not on a belt) leaves in the same step the venue becomes Conveyor, so the bell **dings for a non-belt glass**.
   - At 3→4, the venue changes at the last belt glass's serve, so that glass leaves silently.
   - Fix: let Feel use the Scene's rule (`patienceTotal == nil` and served on a belt), or have Core flag belt glasses.
5. **Performance (suspect): every tier change re-renders the full backdrop on the main thread.**
   - `buildBackdrop` (`GameScene.swift:1161-1178`) keeps at most two looks and clears the cache on the third, and Rush cycles four venues. Every 12 glasses, `SceneArt.backdrop` paints a ~2010 × 2856 (3×) texture (~23 MB) synchronously.
   - This happens at the exact moment the next glass slides in, and the old texture is held for the 0.8 s fade, so peak memory goes to about 46 MB of backdrops.
   - Fix: pre-render the next tier's look off the main thread a few glasses early (glass 10 of 12), or render Rush looks at 2×.
6. Other per-frame work added this round is fine:
   - The sand trickle rebuilds an `SKShapeNode` path every frame while `reposeProgress > 0.7` (`SceneJug.swift:658-695`). That's about 12 ellipses: acceptable; could be pre-built.
   - Potion motes (7 sprites per potion glass), belt ghosts (2 `SceneGlass` updates, early-out at h = 0) and `updateBeltQueue`/`upcomingBase` are all O(glasses) with no allocations.
   - The PourSynth rustle and sparkle paths don't allocate on the audio thread.

**Dry jug / refill (round 5)**

7. **A refill after a dry jug adds about 4.6 s of dead air before the verdict.**
   - Laying the jug back is how a player stops pouring. When the jug ran dry on the last drops, that lay-back triggers `refillDryJug` (`GameSession.swift:577-583`), which sets `resumeHold = 0`. If the player doesn't pour again, the glass is judged only after `resumeServeIdle` (4 s) + `serveIdle` (0.5 s), after the 0.6 s swap.
   - Repro: 1-8 "Last Drops", drain the jug exactly onto the line, then lay back. About 5 s pass before the stamp.
   - Fix: after a dry refill, use a short hold (about 1.2 s), or none when the glass is already within the Good band.
8. **No stuck states found.**
   - A glass with no patience behind a dry jug waits for a lay-back. That always heals: the tip-back angle is ≥ 0 and the gate passes angle 0.
   - `tipBackLimit` clears at angle 0 even when the limit is 0 (a full jug).
   - Swaps and refills behind the flat gate run on their timer and clear the limit (angle 0 behind the gate).
   - A pending swap that lands under 2.5 % marks the jug dry at once and refills after 0.4 s upright (harmless).
9. **Conveyor refills ask for a lay-back on a moving belt (suspect, rare).** On a belt, `sendToStop` runs at the serve, while the player is usually still tipped. A `jugShort` refill there gets `tipBackLimit`, so the fresh jug is held just short of its pour point until the player lays back nearly flat (a full jug's hold angle is about 0). That can cost the next glass's window. Conveyor jugs start at 1.0, so it is rare. Fix: on belts, refill without the tip-back hold but cap the outflow ramp, or refill only when the jug is truly dry.

**Flat gate, closing guard, "Use touch" (round 5): verified, with two notes**

10. **Venue intro card flicker on the Duo.** For the gate card's first 0.35 s (`gateCardDelay`, `GameController.swift:1056-1059`), `showFlatGate` is false, so the intro card pops in and is then replaced by the gate card (`LateGameOverlays.swift:69`). Fix: hide the intro card while `hud.anchors`/`snapshot.needsFlat` says the gate is closed, not only while its card shows.
11. **"Use touch instead" is forgotten every run.** `clearRunTouchOverride()` runs in `start()` (`GameController.swift:565`). A Duo whose hinge can't reach 168° flat waits 6 s on the gate at every Next shift and Retry. That matches the founder's "this run only", but consider keeping it until the app relaunches, or offering it at once after the first use.

**Venue intro cards, banners, migration (round 6)**

12. **TestFlight 1.0 (2) players who already cleared venues get the intro cards anyway.** `hintsSeen` has no venue keys yet (`GameController.swift:934-936`). That's harmless (once each), but a veteran replaying 2-3 is told how foam works. Fix: skip a venue's intro when `store.data.starsEarned(in: venue) > 0`.
13. Persistence and migration from 1.0 (2) are **verified clean**:
    - `crowns` and `dailyArmed` decode tolerantly (`ProgressStore.swift:344-348`). Old stars are kept as max.
    - Queued venue achievements earned under the old rule are dropped before sending (`GameCenterManager.pending`).
    - `Judgement` is `String`-coded, so adding `over` doesn't shift old values.
    - Crowns are not awarded retroactively, since there's no history (expected; "0/8" appears only once all stars are in).
14. **iPhone overlap (suspect):**
    - On wide phones (Pro Max) where the lift hint fits beside the jug, `HintSpot.place` (top gap 8) and the shift banner lane (`PlayBannerView.lane`, +6…+46) can overlap during the 1.6 s banner on the very first run (1-1).
    - In frame 26 the tier banner's top touches the stacked streak pill (about 1 pt).
    - Fix: give `HintSpot.place` `topGap: VenueIntroCard.bannerLane` while `hud.banner != nil`.
15. **The Daily results card on small phones (suspect, SE-size 667 pt):** lead + week dots + score + stats + a 10-glass recap + rollover note + 2-line share preview + three buttons. The CI frames are 874 pt tall only. Check with a 375 × 667 scenario, or drop the share preview when `info.isCompact`.

**Latent (not reachable yet)**

16. **The hourglass's wooden posts are wider than Core's slot contract.** `buildHourglassFrame` sets `maxHW = postX + 6` = 67 pt (`SceneGlass.swift:1569`), but `NextGlassSlot.bodyHalfWidth` uses the profile + wall = 58.5 (`GameSession.swift:1818-1822`). The slot's edge margin and the gap to the stop glass shrink by about 7 pt (at 0.82 scale). Two hourglasses in a row may touch posts. No level uses `hourglass` yet; tell the balance engineer before they add it.

---

## Verified clean (no action)
- **`.over` everywhere:**
  - `Rules.judge` gives `.spill` only when overflowed.
  - Points are 0. A strike in shifts and the Daily; none in Rush (`GameSession.swift:1146-1157`). Streak resets.
  - Scene: stamp only, no sheet or shake (`GameScene.swift:987-993`). Feel: its own sound and haptic.
  - Share 🟪, recap colour and icon, failed-shift breakdown and coaching tip, anticipate hint on a first `.over`, autopilot style.
  - Rush ends only on 3 rim spills or an empty jug; HUD strikes match.
- **Flat gate:**
  - Opens at lid ≤ 12° (`Rules.readsFlat`); the guard's `closedTilt` = −1 can never open it.
  - `isClosing` = only the below-78° latch; fast close below 120° only cuts for 0.35 s.
  - The App re-gates only on the latch and says "to carry on".
  - Autopause below 70°, resume at ≥ 100° (latch released above 88°, so no double gate).
  - Resume from background toggles `onHingeChange` (fresh reading).
  - Under touch: no re-gate, and the gate opens on the next step (touch reads 0).
  - No path pours while closing: the latch cuts below 78°; 78–90° is the designed full-tilt band.
- **Rush tiers:**
  - The tier changes when the first glass of the new tier is sent to the stop. The banner, chord and Scene cross-fade follow `snapshot.venue`; the App's `scene.venue` set is a no-op because `snapshotVenue` wins.
  - Dusk sets `isDark` for every Rush venue, so glass ink and HUD colours stay consistent across tiers.
  - Glass views are keyed by id and never rebuilt on a venue change.
- **Daily:**
  - Armed on the first glass with the gate open; filed at 0 if left after that; abandoned attempts filed at launch.
  - The week strip and streak lead are fine. Day 0 is a Thursday (`weekdayLetter`).
- **Achievements on clear:** `clearedEveryShift(in:)` for the four venues and the Sand Bar.
- **Rush quit:** banks the score once (`recordedFinish`); nothing is recorded with 0 served.
