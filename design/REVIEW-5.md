# Brim: Fold to Pour: review 5, the late game (from frames and code)

*Reviewer: design critic. Date: 26 Oct 2026. REVIEW-1 to REVIEW-4 only covered the first three venues. This round looks at what a player reaches after 30–90 minutes: Conveyor, Potion Shop, Sand Bar, late Rush, Daily results, the failed shift and the full Venues list.*

*Inputs: `design/frames/r5/16`–`23` (iPhone 18 Pro, 1206×2622, so 402 pt wide; I quote coordinates in pt), the other r5 frames for context, `ci/scenarios.txt`, `Core/LevelCatalog.swift`, `Core/LiquidCatalog.swift`, `Core/GameSession.swift` (Rush plan, line fade, conveyor serve), `Scene/*`, `Feedback/SoundBook.swift`, `UI/ResultsView.swift`, `UI/VenuesView.swift`, `UI/ShareText.swift` and GAME-DESIGN §6 and §9.*

**Not re-reported**, because it is already in tonight's work (ROUND-5 / QA-2):
- the `.over` verdict and honest spill FX;
- jug refills between glasses;
- the flat gate at 168°;
- venue achievements on clear;
- the fading-line clock behind the gate;
- the conveyor in-mouth verdict and the belt moving during the intro;
- the Rush idle and quit score;
- the Daily attempt arming and the "midnight UTC" copy;
- "Last call!" and "7 IN A ROW";
- sand impact grains. The Scene owner is already changing these in the working tree (`SceneStream` granular drops, `SceneFX.splashCrown(granular:)`), after frame 19's "bubbles".

**Rule for tonight:** `LevelCatalog.swift` belongs to the balance engineer tonight. Every content change below that touches it is for **the next round**, not for build 1.0 (3).

---

## 0. Verdict

The first hour is an 8.7. The late game is about a **7.0**. The pour is as good as ever. The problems are elsewhere:
- **Each late venue's special mechanic is under-explained, under-signalled or (in one case) silently defeated.**
- **The "meta" screens a returning player sees most** (Daily results, failure, a full Venues list) carry little ceremony and give no next goal.

None of this blocks launch. All of it decides whether the player is still pouring on day 7.

| Area | Score | One line |
|---|---|---|
| The Conveyor | 7.0 | The belt reads, but the pour window doesn't. One glass at a time, no lead. |
| Potion Shop | 7.5 | The strongest identity in the game. The fading line is cancelled by the band shimmer. |
| Sand Bar | 6.5 | A lovely scoop, but the repose mechanic is invisible. It looks like the Lemonade Stand in beige. |
| Late Rush | 7.0 | The HUD escalates, the world doesn't. Belt glasses glide across a wooden counter. |
| Daily results | 7.0 | Clean. It hides 2 of the 10 glasses on iPhone and never mentions the streak. |
| Failed shift | 6.5 | A giant "0" as the hero, no "why", no "how close". |
| Venues (all ★) | 7.0 | 120 identical gold stars, nothing left to chase. |

---

## 1. Cross-cutting: late mechanics arrive with no teaching (P1)

**What happens:**
- `HintKind` has only `lift`, `stop` and `anticipate` (`App/GameController.swift:17`).
- The only explanation of the late mechanics is the Venues card subtitle: "Moving glasses", "Tiny vials, fading lines", "Sand waits, then rushes" (`UI/VenuesView.swift:205-214`).
- A player who taps **Next shift** on 3-8 goes straight into 4-1 and never sees that card. The same happens at 4-8 → 5-1.
- The 40 shift titles ("Slow Pour, Fast Belt", "Now You See It", "Vanishing Act") explain each twist, and they are never shown in play (QA-2 P2-17, not in tonight's scope).

**Fixes:**
- **P1. Venue intro card**, once per venue, on the first shift (shown only if the hint for it is unseen):
  - Venue name, a one-line *instruction* (a verb, not a noun), and a 2-frame mini diagram.
  - On the Duo, it goes on the raised half and clears on the first lift. On a phone, it clears on the first drag.
  - Copy:
    - Conveyor: "Glasses ride past. Start pouring *before* they reach the spout."
    - Potion Shop: "The line vanishes. Remember where it was."
    - Sand Bar: "Sand sticks, then slides all at once. Tip slowly, stop early."
  - Files: `App/GameController.swift` (3 new `HintKind`s: `belt`, `fade` and `sand`, using the existing `hasSeenHint`), `UI/PlayOverlays.swift` (card), `Persistence/ProgressStore.swift` (no schema change; `hintsSeen` is a string set).
- **P1. Shift banner at start**: "Shift 6 · Slow Pour, Fast Belt", 1.2 s, top half on the Duo and under the HUD on a phone. Show it during the existing intro phase. It costs nothing, and it is the only place the shift's difficulty is announced before it bites. It closes QA-2 P2-17. Files: `UI/PlayOverlays.swift`, `GameController.title(for:)`.
- **P2. Make the Venues subtitles instructions:**
  - "Moving glasses" → "Moving glasses: pour early"
  - "Tiny vials, fading lines" → "Fading lines: remember the mark"
  - "Sand waits, then rushes" → "Sand sticks, then slides"

  File: `UI/VenuesView.swift:205-214`.

---

## 2. The Conveyor (16-conveyor, shift 4-3)

**What works**
- The belt is unmistakable: steel rails with bolts, slats, a dark rubber band, and a steel counter. Paired with the ticket rail and the cloche on the shelf, it has a "kitchen pass" identity of its own.
- The tumbler stands squarely on the belt and the stream is centred in the mouth. The Perfect band's cyan edges are visible around the line.
- The difficulty curve in the data is sensible: the belt goes 16 → 36 (× `beltScale` 1.5). 4-6 slows the belt to 20 and adds thick drinks, a good "change of key".

**What's weak**
1. **The pour window is invisible (P1).**
   - The coaster and the slot coaster are hidden on the conveyor (`GameScene.swift:471-474, 503-506`), and nothing replaces them.
   - The player can't see *where* the glass will be under the stream or *how much* window is left.
   - At belt 36 the window is about 1.3 s, and the glass parks only `conveyorLeadIn` = 40 pt left of the stream (`CoreTuning.swift:174`) before the belt takes it. That is under 1 s from "I see it" to "it's under the spout".
2. **One glass at a time (P2).** In 16 the belt carries a single glass, and the next one is a 14-pt HUD icon (the brown mug at 85, 80 pt). A conveyor's pleasure is reading the queue: "mug, then shot, then bowl". Here the next glass is a surprise every time.
3. **The jug's "04" ticket badge (P2).** In shift 3, the pitcher says "04" in a 30-pt roundel. It reads as a count ("4 left?") or a shift number that is wrong. It's the Lemonade pitcher in orange with a confusing number.
4. **No conveyor delight.** There is no bell, no "ding" as a filled glass leaves, and missed glasses just slide off. The cloche on the shelf is a service bell begging to be rung.

**Fixes**
- **P1. Pour zone on the belt:**
  - Paint a lit amber band about the spout's landing width on the belt directly under the stream, with two small chevrons showing the direction of travel. Drive the band with `s.telemetry` / the landing x.
  - Make the **line tab drain** (fill → empty) as the mouth crosses the stream: the tab *is* the window timer, in the same place the eye already is.
  - Files: `Scene/SceneArt.swift paintBelt()` (static band) or a node in `GameScene.updateBelt`; `Scene/SceneGlass.swift drawLine` (tab drain uses `(x − rimHalf − landingX)` progress; Core already has both values in `GameSession.swift:962`).
- **P2. Show the next glass riding in** from the left edge at belt speed (two glasses on screen), instead of a fast slide to a 40-pt park. Put it behind a `CoreTuning.conveyorQueueVisible` flag and test it against BALANCE; it changes the lead time, not the window. Files: `Core/GameSession.swift` (conveyor arrival), `Core/CoreTuning.swift`.
- **P2. Swap the "04" ticket decal** for a plain arrow or gear roundel (`ScenePalette.swift` `.ticket`, `SceneJug` decal). Better still, show the belt speed as chevrons (▶, ▶▶, ▶▶▶), which signals difficulty for free.
- **P2. Ring the bell:** on a conveyor Perfect, the cloche on the shelf gives a tiny hop and a "ding" (`SoundBook` already synthesises a ting; reuse it pitched down). Files: `Scene/SceneArt.swift` (cloche as its own node), `Feedback/FeedbackDirector.swift`.

---

## 3. Potion Shop (17-potion 5-2, 18-potion-late 5-7)

**What works**
- **The best venue art in the game.**
  - The indigo stone wall, candles, the round flask on the shelf and dark planks are instantly "somewhere else".
  - The flask jug with cork, twine and the moon sigil is the most characterful vessel.
  - Blue and pink potions glow against the dark.
- PERFECT in 18 is crisp: a cyan line and ring on the beaker, the stamp well clear of the rim, the streak chip under the score.
- Precision is honestly ramped: the band tightens from ±2.5 % to ±1.8 %, the vials are tiny, and low lines in "Small Doses" make the venue feel like *surgery* after the Diner.

**What's weak**
1. **The fading line is defeated by sound (P1).**
   - The Perfect-band shimmer is driven by `telemetry.projectedDistanceToLine` (`Feedback/SoundBook.swift:196-198`). It ignores `lineOpacity`.
   - So in 5-3, 5-6, 5-8 (and in Daily orders 7–10 with `fade`), a player with sound on hears *exactly* when to stop, including the liquid still in the air: an easier cue than the visible line ever gives.
   - A muted player gets the intended memory test. The same shift is trivial or hard depending on the mute switch, and the headline mechanic of the venue doesn't exist for half the players.
2. **The line vanishes completely** (`SceneGlass.drawLine`: ink, glow, halo and tab all fade together). Nothing remains to anchor memory. The beakers have graduation ticks (visible in 17 at 33–40 pt), but they are unlabelled, and the vial and flute have none.
3. **The potions behave like weak sodas** (`potionBlue` and `potionPink` are just `fizzy` with 0.25–0.35 foam). Nothing magical happens: no shimmer in the liquid, no colour change, no puff. The *identity* is all backdrop.
4. **"Bubble Trouble" (5-7) is a prefill shift** with no bubbles. 18 shows the pink prefill in the waiting vial: the same colour as the order, so the twist is invisible until the glass arrives.
5. **The score is ink-on-indigo (P2).** "0" in 17 (at 310, 70 pt) is dark ink on #4D3B68, about 1.6:1. It's legible only thanks to a faint halo. "100" in 18 is the same. The pause button and pills are fine.

**Fixes**
- **P1. Mute the band shimmer while the active glass's line is faded** (`lineOpacity < 0.5`). Keep the lock-in tink *after* landing: it's a verdict, not a cue. Files: `Feedback/SoundBook.swift` (bed: gate `shimmer` by the active glass's `lineOpacity`), `Feedback/FeedbackDirector.swift` (pass it from the snapshot's active `GlassState`). Add a FeedbackTests case.
- **P2. Leave a memory anchor:**
  - Before the fade, the tab shows the volume ("60") against beaker ticks labelled 20/40/60/80. When it fades, the **ticks stay**.
  - That turns "Vanishing Act" into reading plus memory, which is very Potion Shop. For vials and flutes, keep a 6-pt notch on the rim edge at the line height.
  - Files: `Scene/SceneGlass.swift` (tick labels for `beaker`), `Core/GlassCatalog.swift` (tick spacing as data).
- **P2. A little magic on Perfect, Potion Shop only:** the liquid's top band brightens and the colour shifts toward violet for 0.4 s, and three star puffs rise from the surface (`SceneFX.perfectBurst` variant keyed by `palette.venue == .potionShop`). It's cheap and it is the venue's signature moment.
- **P2 (next round, balance).** Make 5-7's prefills the *other* potion (pink under blue). Rendering two layers needs a two-colour liquid in `SceneGlass.drawLiquid`. Only do this if cheap; otherwise rename 5-7 "Top It Off". File: `LevelCatalog.swift:396`.
- **P2. HUD on dark venues:** the score is cream with an ink shadow when `palette.isDark` (`UI/PlayOverlays.swift` score label; expose `isDark` via `CanvasInfo` or the HUD).

---

## 4. Sand Bar (19-sand, shift 6-1)

**What works**
- **The copper scoop is great**: an open mouth showing sand, a graduated sight glass, a stick handle, the sun roundel. It is the only vessel that *looks* like it pours something other than liquid.
- The sand stream is a straight, dry, opaque ribbon (wobble 0.02), the right call.
- The hourglass on the shelf names the venue at a glance.

**What's weak**
1. **The repose mechanic is invisible (P1).** Core holds the sand until the tip exceeds 30° past normal, then avalanches at ×2.6 for 0.4 s, and keeps flowing until the tip drops under the hysteresis (`GameSession.swift:375-421`, `CoreTuning.swift:97-103`). Nothing on screen or in the speaker hints that the slide is coming:
   - no creep in the sight glass;
   - no grains at the lip;
   - no creak.

   The player learns it only by overshooting. This is the "secret" reward for 3-starring 40 shifts, and its one idea arrives as a surprise spill.
2. **The sand behaves like liquid in the glass.** `drawLiquid` uses the same wave surface for sand (it sloshes) and a flat level. Sand heaps: a low cone under the stream that slumps flat. 19 shows a flat, water-like top.
3. **The identity is a recolour of Lemonade:** a cream wall, pale cyan tiles and light planks. Put a frame of 19 next to 15 and it is the same room in beige.
4. **Promised and missing:** GAME-DESIGN §6 says "Hourglasses and sand". There is no hourglass glass in `GlassCatalog`; the Sand Bar serves jars, beakers, vials and shots, borrowed from other venues.
5. **The scoop reads as a face.** The oval sight glass with tick marks is a grinning mouth with teeth, the sun is an eye and the stick is an antenna (s19 crop). It's charming or odd; check with 3 people.

**Fixes**
- **P1. Telegraph the slide.** Expose `reposeProgress` (0…1 as the effective tilt approaches the repose angle) on `JugState`. This is a contract field added by Core, read by Scene and Feedback.
  - From 0.7 to 1: a few cosmetic grains trickle from the lip (no volume), and the sand surface in the sight glass and the mouth tilts and creeps toward the spout.
  - Add a soft dry rustle, rising in level, plus light haptic ticks.
  - At the avalanche: a short "shff" thump.
  - Files: `Shared/Contracts.swift`, `Core/GameSession.swift` (near `:375`), `Scene/SceneJug.swift` (lip trickle, mouth fill), `Feedback/SoundBook.swift` (rustle bed; the sand hiss already exists at `:129-138`), `Feedback/BrimHaptics.swift`.
- **P2. Heap, don't slosh:** for granular liquids, replace the wave with a mound centred on the impact x (amplitude ≤ 6 pt, same area) that relaxes flat over about 0.5 s after the stream stops. It is judged after settling, so the verdict is unaffected. File: `Scene/SceneGlass.swift drawLiquid` (branch on `isGranular`, which the Scene owner is adding tonight).
- **P2. Give the room its own light:** a terracotta adobe wall (#E9A877 → #F3C79A), sand-coloured stucco instead of tiles, a sunset glow, and a layered sand-art bottle beside the hourglass. File: `ScenePalette.swift .sandBar`, `SceneArt` props.
- **P2 (next round, content).** Add an **hourglass glass** (narrow waist). The level speeds up through the waist: the one shape that makes sand pouring *different*. `GlassCatalog` is data and the Scene draws from profiles, so the risk is low. Use it in 6-1 and 6-4.

---

## 5. Late Rush (20-rush-late, 18-streak, ×5)

**What works**
- The HUD escalates well: "6,500" is big, the "×5 | 🔥18" chip has a gold ring, "18 served" sits on the left, and the strike cups are clear.
- The patience ring around the coaster (green, partly drained) is the best timer in the game: you read it without looking away from the glass.
- The dusk palette with string lights is warm and distinct from Shifts.

**What's weak**
1. **Belt glasses glide across a wooden counter (P1).**
   - From tier 3 (glass 24+), 35–50 % of Rush orders ride a belt (`GameSession.swift:1301-1303`).
   - Rush is always the Lemonade Stand at dusk (`GameScene.swift:740-746`), and the belt is painted and animated only when `palette.venue == .conveyor` (`SceneArt.swift:618`, `GameScene.swift:564`).
   - So the best Rush players, the ones who post scores, see glasses sliding on their own across planks, with no belt, no window cue and no coaster.
2. **The tiers are invisible.** Every 8 glasses, patience, drink pool, band and belts all change, and nothing announces it. Glass 18 looks exactly like glass 1. In a run of 3–4 minutes, that is the whole sense of progress.
3. **Nothing escalates after ×5.** The multiplier caps at a streak of 10. From there, 18 or 25 in a row looks and sounds the same. The world never reacts to a hot streak.
4. **Cream soda reads as beer (P2; P1 if this frame is ever used in the store).** In 20, a jar of pale gold liquid with a 40 % white head, in a bar with string lights at dusk, is a lager. QA-2 P2-14 covered root beer in mugs; cream soda (`LiquidCatalog.swift:29-32`, foam 0.6, #F2B457 under #FFF9EE) is worse, and it's in the Rush pool from tier 1.
5. **No low-jug warning.** The run ends when the shared jug runs dry, and the only cue is the jug's own level plus a buzz at empty (`FeedbackDirector.swift:338`).

**Fixes**
- **P1. Rush travels: one venue per tier, at dusk.**

  | Tier | Glasses | Venue |
  |---|---|---|
  | 0 | 1–8 | Lemonade |
  | 1 | 9–16 | Soda Fountain |
  | 2 | 17–24 | Diner |
  | 3 | 25–32 | Conveyor (the belt appears exactly when belt glasses start) |
  | 4 and up | 33+ | Potion Shop |

  - It fixes item 1 by construction, makes item 2 visible, and is the cheapest content multiplier in the project: the palettes, props and `duskified()` all exist.
  - Swap during the serve slide. The backdrop texture is cached per venue (`GameScene.buildBackdrop` key), so it's one rebuild per tier.
  - Core exposes `rushTier` on the snapshot.
  - Files: `Core/GameSession.swift` (snapshot field), `App/GameController.swift` (set `scene.venue`), `Scene/GameScene.swift` (allow a mid-run venue change without a reset).
- **P1. Tier banner:** "TIER 3 · BELTS!" for 1.2 s, plus a rising 3-note chord. Copy per tier:
  - "Fizz!"
  - "Thick and fast"
  - "Belts!"
  - "Potions!"
  - "Faster!" for every tier after that.

  Files: `UI/PlayOverlays.swift`, `Feedback/SoundBook.swift`.
- **P2. Hot-streak escalation:** at 10, 15, 20 and 25, the string lights brighten a step, then twinkle, then add a second strand. Cosmetic only (`SceneArt` dusk lights as nodes, or an alpha layer).
- **P2. A low-jug pulse:** under 20 % in Rush, the jug's glass tint pulses amber every 1.5 s, and a soft "slosh" plays once. Files: `Scene/SceneJug.swift`, `Feedback`.
- **P2 (next round). Recolour cream soda** to a candy pink-vanilla ("red cream soda", e.g. top #FFD3DC, bottom #F28BA8, foam #FFF3F6), or halve its foam. Keep pale-gold-with-head out of every store capture either way.

---

## 6. Daily results (21-daily-results)

**What works**
- The hierarchy is right: "DAILY POUR #297", then the 52-pt score, then the glass recap, then **Share** as the primary yellow button. Practice and Menu are secondary.
- The recap glasses use real profiles with verdict chips. Even at 8 glasses it reads as *your* pour.

**What's weak**
1. **2 of the 10 glasses are hidden on every iPhone (P1).**
   - `RecapRow` caps at 8 below 420 pt wide (`ResultsView.swift:219`), and the Daily is always exactly 10.
   - The card shows "+2" floating on the left (at 40, 330 pt). The two hidden glasses are the *warm-ups*, so the row starts at glass 3.
   - This is the card people screenshot.
2. **The streak, the whole point of a daily, is absent.**
   - `store.dailyStreak` exists and shows on Home ("🔥4"), but not here, at the one moment it means something.
   - The share line (`ShareText.daily`) has no streak either.
3. **The stats line scolds:** "0 perfect · best streak 0 · 10 glasses" over a row of eight green ✓ (in Shift terms that's a clean card). The Daily has no stars, so the stats line is the only judgement, and it leads with zeros.
4. **The share string isn't previewed.** The player taps Share without knowing what gets posted.
5. **Noise:** "Next unlock: 8 more ★ for Soda Fountain" on a Daily card.

**Fixes**
- **P1. All 10 glasses on iPhone:** for `.daily`, `maxCount: 10` at a 24-pt glass width and 4-pt spacing (10 × 28 = 280 pt, which fits the 338-pt card interior). File: `UI/ResultsView.swift:219`, `RecapRow`.
- **P1. Daily ceremony line**, under the score, replacing the stats line for the Daily:
  - `🔥 4 days in a row · best 1,240`, plus a 7-dot week strip (filled for the days played).
  - Add the streak to the share string: `Brim Daily #297 ⭐️🟩🟩🟨… 570 🔥4`.
  - All local.
  - Files: `UI/ResultsView.swift` (`statsLine`/`note` for `.daily`), `UI/ShareText.swift` (+ test), `Persistence/ProgressStore.swift` (best Daily = max of `daily` values; no schema change).
- **P2.** Put the exact share line in small type above the Share button (the emoji row *is* the summary), and drop "Next unlock" from Daily cards (`unlockLine` guard on `dailyDay == nil`).

---

## 7. Failed shift (22-shift-failed, 2-4 struck out)

**What works**
- It doesn't lie: "Shift over — 3 spills" (REVIEW-2 P2-6 held). Retry is primary and big, the grey stars say "none" without shouting, and the three recap glasses with red drop chips show *what* happened.

**What's weak**
1. **The hero is a 52-pt "0".** The biggest thing on the failure screen is the number that says you got nothing. Players don't quit on a fail; they quit on a fail that feels pointless.
2. **No "how close".** "3 glasses" in the stats line doesn't say "of 7". The four unserved glasses don't appear.
3. **No "why" and no "what next".** Three spills in a foam shift has one cause, and the game knows it. A one-line tip turns a quit into a retry.
4. **The headline only counts `.spill`** (`ResultsView.headline`, `:50-51`). From tonight, `.over` and `.short` also strike, so a run that ends 2 OVER + 1 SPILL falls through to **"Not quite"**: the soft copy REVIEW-2 banned for strike-outs. This is new because of tonight's contract change. App owner: please fold it in.
5. **The unlock line on a fail** ("Next unlock: 8 more ★ for Soda Fountain", on a Soda Fountain shift) is noise. In this frame it's also a demo-state artefact, since `progress` wasn't set, but it reads absurdly.

**Fixes**
- **P1. Headline by strikes:** `strikes >= max` → "Shift over: 3 misses". Itemise when mixed ("2 over, 1 spill"), and say "3 spills" only when all three are spills. Add a unit test for the `.over` mix. File: `UI/ResultsView.swift:44-58`, `ResultsTests`.
- **P1. Progress, not zero.** On a struck-out shift:
  - The score drops to 28 pt, and the hero becomes **"3 of 7 glasses"**.
  - The recap shows the unserved glasses as faint outlines (it's `CounterRecap`/`RecapRow` with ghost items).
  - Files: `UI/ResultsView.swift` (card, `RecapRow`), `ResultSummary` (needs `ordersTotal`, which the HUD already has).
- **P1. One coaching tip**, chosen by venue × dominant miss (a pure function, tested), shown once per (venue, miss) pair and then every 3rd fail:
  - foam + spill/over: "Foam keeps rising after you stop. Stop at half, let it settle, top up."
  - thick + over: "Thick drinks keep coming. Stop well before the line."
  - conveyor + short: "Start pouring before the glass reaches the spout."
  - fade + any: "Look at the line before it fades. The ticks stay."
  - sand + over: "Sand slides all at once. Tip slowly, stop early."
  - any + short: "A little longer: the line is the target, not the start."

  New `UI/FailTips.swift`, wired from `ResultsView.note`.
- **P2.** Hide `unlockLine` when the shift wasn't cleared.

---

## 8. Venues, everything unlocked (23-venues-full)

**What works:** 120★ in the header, each venue card in its own accent, and the "teaches" line per venue. Clean and calm.

**What's weak:** Once everything is 3-starred, 40 identical gold bubbles say "done". There is no per-shift best, no mark of a *flawless* shift, and no reason to replay 2-4 again. Most players will never see the Sand Bar card at all: it needs all 120★, and 3 stars means *every glass a hit and ≥ 60 % Perfect* (`Rules.stars`).

**Fixes:** see long-term items 3 and 4 below. Also:
- **P2 (next round).** Open the Sand Bar at **100★**, keeping the "secret" label, so committed players see the game's most different venue. File: `LevelCatalog.starsToUnlock`.

---

## 9. Long-term fun: will they still be pouring on day 7?

**Honest read.** On a Duo, the physical pour is a real hook. A player comes back on day 2 and day 3 *to pour*, and the Daily gives them a reason to open the app. By day 7, a typical player:
- has cleared 3 or 4 venues (about 40–60 min of shifts);
- has played Rush 10–20 times, in **the same room every time**;
- has done a Daily that ends on a card with **no streak and no history**;
- has stars that stop meaning anything at 3.

The core is a 9. The loop around it is a 6.5. Expect "yes, for the Daily, briefly" from perhaps a third of players, with the drop-off where variety and visible progress run out.

The five highest-impact, low-risk changes. All are local and cosmetic or presentational, with no server, accounts, ads or IAP:

| # | Change | Why it retains | Risk | Files |
|---|---|---|---|---|
| **1 · P1** | **Rush travels**: one venue per tier at dusk, plus a tier banner (§5) | Every Rush run becomes a short trip through the whole game. Tiers become goals ("I reached the Potion Shop"). It fixes the belt-on-wood bug. | Low: palettes, props and the belt exist. One backdrop rebuild per tier, during a serve. | `Core/GameSession` (snapshot `rushTier`), `App/GameController`, `Scene/GameScene`, `UI/PlayOverlays` |
| **2 · P1** | **The Daily ritual**: streak and best on the results card, streak in the share line, a 7-day dot strip, all 10 glasses (§6) | Streaks are the strongest no-server retention mechanic there is, and the data already exists. | Very low. | `UI/ResultsView`, `UI/ShareText`, `Persistence/ProgressStore` |
| **3 · P1** | **Mastery past 3 stars**: a "Flawless" crown per shift (all Perfect; the results card already detects it, `ResultsView.swift:47`), a cyan ring on the shift bubble, a per-venue crown count ("Crowns 3/8"), and the 3-star rule spelled out on results ("★★★: all hits, 5 of 8 Perfect. You had 3.") | 40 new goals with zero balance work. A replay target for every shift. | Very low: one `Set<String>` in `ProgressData` (tolerant decode, like QA-1 P2-15). | `Persistence/ProgressStore`, `UI/VenuesView ShiftBubble`, `UI/ResultsView` |
| **4 · P2** | **Glass Cabinet lite** (the GAME-DESIGN §9 promise): unlock the six venue *vessels* (pitcher, dispenser, shake tin, flask, scoop) and coaster styles for **Rush and Practice**, earned by milestones (venue cleared, 7-day streak, 10 L poured, 25 streak, 10 crowns). Pick one on a small Cabinet screen off Venues. | Collection plus self-expression. It makes lifetime stats *pay out*. | Low to medium: the art exists as `VesselStyle.form`. New: one screen and a palette override. | `UI/CabinetView` (new), `Persistence/ProgressStore`, `Scene/ScenePalette` (vessel override), `App/GameController` |
| **5 · P2** | **Daily themes by weekday**: the Daily's room and menu bias follow the day (Mon Lemonade … Fri Potion, Sat "Foam Frenzy", Sun "Thick Sunday"). The title says "Daily #297 · Potion Friday". | Novelty every day and something to talk about. "Did you get the honey Sunday?" | Low, **with one rule**: the generator is seeded per client, so gate the new generator by day number (`day >= launchDay + 14`). Every version then produces the same Daily on the same day and the leaderboards stay fair. Ship it in the update that adds it, never in a hotfix mid-week. | `Core/LevelCatalog.dailyOrders` (balance owner, next round), `Scene/GameScene` (`effectiveDaily` → venue) |

**Honourable mention (P2):** a "**Dead centre**" flourish inside Perfect: |err| < ¼ of the band gives a gold line, a higher ting and a lifetime counter. It raises the skill ceiling for the players who will recommend the game, at no balance cost (no score change). Files: `Core/GameSession.serve` (flag on the event), `Scene/SceneGlass`, `Feedback/SoundBook`, `Persistence` (counter).

---

## 10. All items by priority

**P1 (for 1.0.1, or tonight if an owner has room; none blocks 1.0 (3)):**
1. Fading lines defeated by the band shimmer: gate the shimmer on `lineOpacity` (§3). *Feedback.*
2. Late mechanics untaught: a venue intro card plus 3 `HintKind`s, and a shift-title banner at start (§1). *App/UI.*
3. Rush: belt glasses on a wooden counter and invisible tiers: venue per tier plus a tier banner (§5, long-term #1). *Core snapshot, App, Scene, UI.*
4. Conveyor window invisible: a pour zone on the belt plus a draining tab (§2). *Scene.*
5. Sand repose invisible: `reposeProgress`, a lip trickle, a rustle and haptic ticks (§4). *Core contract, Scene, Feedback.*
6. Failed shift: the headline counts every strike type (`.over`!), "3 of 7" progress, and one coaching tip (§7). *UI.*
7. Daily results: all 10 glasses, streak and best, streak in the share line (§6, long-term #2). *UI, Persistence.*
8. Flawless crowns plus the 3-star rule on results (§8, long-term #3). *Persistence, UI.*

**P2:**
- Next glass rides in on the belt.
- Replace the "04" ticket decal.
- Cloche "ding".
- Beaker tick labels and a memory anchor.
- Potion Perfect "magic".
- Two-colour prefill in 5-7.
- Score colour on dark venues.
- Sand heap instead of slosh.
- Sand Bar adobe palette.
- Hourglass glass.
- Check the scoop "face".
- Hot-streak lights in Rush.
- Rush low-jug pulse.
- Recolour cream soda.
- Share-line preview.
- Drop the unlock line on Daily and failed cards.
- Instructive venue subtitles.
- Sand Bar at 100★.
- Glass Cabinet lite.
- Daily weekday themes (version-gated).
- Dead centre.

**Content changes for the balance owner, next round only** (`LevelCatalog.swift` is theirs tonight): 5-7 prefill colour or name, the hourglass in 6-x, Sand Bar at 100★, Daily themes.
