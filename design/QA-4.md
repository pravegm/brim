# QA-4: rounds 7–8 audit (QA lead, fourth pass)

Scope: `git diff HEAD~5 -- Brim` (rounds 6 → 8, focus on 7/8: `bcc4d33`, `8b373de`, `f9ff718`). Read-only static
audit: code paths traced by hand, geometry worked out from the catalog numbers, and CI frames `design/frames/r8`
checked. **Verified** means I followed the code path end to end. **Suspect** means it is plausible from the code but
needs a device or a frame to confirm.

**Result: no P0, one P1, six P2s.** The risky new mechanics all hold up: the start hold, Rush look-ahead determinism,
the Fizz pools, the foam autopilot, the save migration and the cabinet unlock math.

---

## P1

### P1-1 (verified): a tall glass's PERFECT stamp floats over the *waiting* glass
`Brim/Scene/SceneGlass.swift:1379` (`placeStamp`, side choice). Compare `:1508`, where the streak pop already knows
"right first: the next glass waits on the left".

Round 8's N5 fix moves the stamp beside a glass that is too tall for it to fit above (flute, highball, soda glass/pint).
It tries the **left** side first. It checks only `safeX` and the glass's own reach, never the next-glass slot, which
sits on the left at `CoreTuning.nextGlassX` = 165.

Duo numbers (world pt; the stamp texture is about 354 × 118 for 64 pt "PERFECT", with its ink about 0.46 W / 0.3 H):
- **Highball at the stop (x 372):** `leftRoom` = 372 − 43.5 − 8 − 14 = 306, so the scale is 0.86 and the stamp
  centre lands at x ≈ 167. The waiting glass's centre is at x 165.
- **Height:** the ink spans y ≈ 351–411. A waiting highball or pint reaches the top at about 321–327, and a waiting
  flute at about 345. So PERFECT hovers 6–30 pt above the next, empty glass and is centred on it.
- **Phone (iPhone 18 Pro, safeX 130…540):** the stamp stays on the left at scale ≈ 0.55, centre x ≈ 229, spanning
  x 138–320. The waiting glass sits at x ≈ 180–190. Same picture.

**Repro:** on a Duo, play 1-7 "First Flute", any Soda Fountain shift with a highball or pint, or Practice/Rush (a
highball or pint is often at the stop). Pour a Perfect while a glass waits in the slot. The verdict reads as the
waiting glass's.

This is the Duo tabletop frame and the core juice moment. The existing test
(`SceneTests.swift:1014`) checks only that the stamp clears its *own* glass.

**Minimal fix:**
1. Pass the waiting glass's x-range into `GlassFrame`. The scene already computes `waitingGlassWorldFrame` at
   `GameScene.swift:552`, so this needs ordering or caching from the previous frame.
2. In `placeStamp`, pick the side whose ink box doesn't intersect that range. On the Duo the right side fits at about
   0.54 (656 − (372 + 43.5 + 42 + 8) = 190 pt).
3. If both sides are blocked (phones), raise the left stamp so its ink bottom clears the waiting rim by 10 pt, still
   capped by the keep-out.
4. Add a SceneTests case with a waiting glass.

---

## P2

### P2-1 (verified): Settings › Reset progress leaves the cabinet vessel on the Home attract loop
`Brim/UI/SettingsView.swift:97`. Reset calls `store.resetProgress()` only. `GameController.showHome()`
(`GameController.swift:790`) goes back to `.home` without `syncVessel()` (`:1032`), so `scene.vesselOverride` keeps
the old Shake tin or Potion flask behind Home.

**Repro:** reach 6 crowns, choose the Shake tin, reset progress, go back to Home. The loop still pours from the tin and
the cabinet says "House jug · In use". It corrects itself at the next run (`applySceneLook`). The store itself is right:
`vessel` is nil and `activeVessel` is gated.

**Fix:** call `syncVessel()` from `showHome()` (or expose a `progressDidReset()` that Settings calls).

### P2-2 (suspect): a continuous pour through Rush belt serves keeps the old drink in the stream
`GameSession.swift:373` and `:1439`. The Rush drink only changes once `outflow <= 0 && particles.isEmpty`.

A player who keeps the jug tipped across a belt serve (natural on the Conveyor tier) pours the previous drink's colour
for every following belt glass, for as long as the stream never breaks. For example, an orange stream lands in a cola
glass: the glass foams by its own drink (`glasses[gi].liquid`, `:793`), but flow lag follows `jugLiquid` (`:511`). The
mismatch is cosmetic plus a small lag error, and it is the deliberate QA-3 P2-3 trade-off taken one step too far.

**Fix:** also hand over once the stream has landed in the new glass for about 0.2 s, or when the old glass leaves the
stream x-range, cross-fading the colour over about 0.15 s.

### P2-3 (suspect, perf): the forced Rush look pre-paint can hitch mid-pour
`GameScene.swift:1289`. At glass 10 of each tier, the next tier's backdrop (2×, about 10 MB, `SceneArt.backdrop`) is
painted synchronously on the main thread, even while pouring. That is at most one hitch per 12 glasses. Core clamps
`dt` to 1/30, so judging is safe, but the stream and wobble stutter.

The memory side is fine: Rush keeps at most 3 × 10 MB, other modes 2 × 23 MB, and the LRU trims when you leave Rush.

**Fix:** paint the `UIImage` on a background queue (`UIGraphicsImageRenderer` is thread-safe) and install the texture on
the main thread. Keep the cache-miss path as the fallback.

### P2-4 (verified): the crown icon also shows on the "3★ needs every glass a hit" line
`ResultsView.swift:519` (`statsIsCrownChase`) and `:433`. `chaseLine` returns the stars message for 1–2★ clears, so the
crown glyph sits beside a stars goal.

**Fix:** set `statsIsCrownChase` only when `result.stars >= 3`.

### P2-5 (verified): the venue card's "✦ best/glasses" under-reports for 1.0 (2)/(3) veterans
`ProgressStore.swift:137–150`. Older saves have no `bestPerfects`. Crowned shifts count in full, but 3★ shifts count 0
until they are replayed, so a veteran can see, say, "✦ 12/52" on a venue they nearly mastered. Decoding is tolerant,
nothing is lost, and the bubble arcs correctly stay hidden (`crownArc` needs > 0).

**Fix:** hide the venue line while any 3★ shift of that venue has no record.

### P2-6 (verified, minor): a struck-out Daily gets no ghost glasses
`ResultsView.swift` `ghostRecap` and `progressLine` handle shifts only. A Daily that strikes out shows only the served
glasses, unlike shifts. Shifts and conveyors are correct: at most 8 orders fit `RecapRow.maxCount` 8, and judgement
order matches the belt order.

**Fix:** extend `ghostRecap` to `.daily(day)` using `LevelCatalog.dailyOrders(day:)`, or leave it as is by design.

---

## Checked and clean (no finding)

- **`setStartHold`: no stuck-held path.**
  - Core clears the hold on `.pourStarted` (`GameSession.swift:574`). `process` dismisses the card in the same step,
    and `syncStartHold` is idempotent through `startHeld`.
  - `buildSession` resets `startHeld` before `activeHint = nil`, then re-sets the hold, so Retry with the card up is
    correct.
  - Menu, Restart and Attract release the hold on the old session.
  - Pause, autopause and resume add `needsFlat` on top of the hold. The card stays hidden while the gate is closed and
    reappears when it opens. Pouring and tapping both still release it.
  - `.stop`, `.anticipate` and `.lift` can't replace an intro card (their guards), and no serve can happen while held.
  - On the Daily and Rush there is no intro, so no hold.
- **`upcomingOrders` determinism.** The getter is pure. `topUpRushPeek` runs only where a plan is consumed, and plans
  keep their generation index, so tiers are unchanged. In shifts the order is `peeked → plans[nextPlanIndex]`. The App
  queue index (`ordersDone + onCounter`) equals Core's peeked plan index, and the tier boundary maths matches
  `makeRushPlan`. The scene draws the queue only in the Conveyor room (`beltMode`) and only for patience-less orders.
- **Rush Fizz and pools.**
  - No empty pool: `rushLiquidPool` and `rushMenu` are non-empty for every venue, and `rushVenue` never returns the Sand
    Bar.
  - Line caps come out at 0.70 / 0.65 / 0.61.
  - With a 1.6× jug (about 138k pt²), the largest Rush need is a goblet or jar to 0.9 (about 21–25k).
  - A jug too low for the next glass ends the run cleanly: the glass is served short (no strike) or `jugDry` hits, then
    the finish.
  - Dry jug + `dryServeNow` (round 7) has no hold leak.
- **Foam autopilot.** `.settling` always ends within `maxPause` 1.4 s. Each pour cycle adds liquid, and `shouldStop`
  runs before the foam pause, so there is no infinite loop. The Home attract loop is Practice (water, lemonade,
  orange juice, foam 0), so `foamCare` is never on there and the still-drink lead is untouched.
- **Persistence and migration.** `bestPerfects` and `vessel` decode tolerantly, and an unknown vessel becomes nil.
  Synthesized `encode` includes both. Crowned shifts read as full best. `setVessel` refuses locked vessels.
  `activeVessel` re-gates on crowns, so a stale vessel never draws in a run.
- **Glass Cabinet math.** There are 44 shifts, so all thresholds (3/6/10/14) are reachable, and `totalCrowns` ignores
  unknown ids. Captions and accessibility are correct. The sheet fits both canvases (Duo 5 columns × 1 row, phone
  3 × 2).
- **Daily.** The round-8 edit to 2-7 keeps the de-duplicated `dailyMenu` insertion order, and sand levels are excluded,
  so the Daily is unchanged from round 7.
- **Phone intro card.** It clears the waiting glass. On a very tall first glass it rises into the raised half by
  design ("as low as it can sit above the rim"), and the first pour dismisses it.
