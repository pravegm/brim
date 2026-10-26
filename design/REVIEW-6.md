# Brim: Fold to Pour: review 6 (rounds 5–6, from frames)

*Reviewer: design critic. Date: 26 Oct 2026. Inputs: `design/frames/r6/01–29` (iPhone 18 Pro, 1206×2622; coordinates in pt, 402 wide), `design/frames/duo6/*` (real iPhone Duo simulator, 2007×2853; pt on the 669×951 inner canvas, crease band y 455–495), `ci/scenarios.txt`, ROUND-5/6/7, QA-3, BALANCE.md, and spot reads of `UI/ResultsView.swift`, `Core/LiquidCatalog.swift`, `Core/GameSession.swift`.*

**Not re-reported** (they are in ROUND-7 / QA-3 tonight):
- the stamp that lingers over the next glass (26);
- the intro card that doesn't hold the belt, and its "Pour to start" copy (24);
- the chase line's old star rule (28);
- the intro-card flicker on the Duo gate;
- Rush belt queue, tier-edge bell, backdrop re-render, the tier banner touching the streak pill.

**Ground rules:**
- The duo-0* hinge script holds a steep tilt, so its glasses spill. I don't count those spills against the game.
- Demo-state oddities aren't findings: "Venues ★ 0" on duo-ui-menu, unlock lines with `progress` unset.

---

## 0. Verdict

Rounds 5–6 did what REVIEW-5 asked, almost item for item. **All eight of REVIEW-5's P1s have landed.** The late game moves from about **7.0 to 8.2**: every late venue now teaches itself, Rush is a trip through the whole game, and the Daily card finally has a ritual.

Two new things need attention, and only one of them might be a real problem:
1. **Frame 20 (late Rush) shows a run that has just died in the Fizz tier.** Its three strike cups are red, there's no glass at the stop and the streak is gone. The same scenario in r5 reached 6,500 at ×5 🔥18. This is either a capture or autopilot regression, or a real **foam wall at glass 13** that would stop most players from ever seeing "Rush travels". It needs verifying from the CI log (§3, N1).
2. **"3★ = no misses" changes what the stars mean.** Under it, frame 28 (six hits, 0 Perfect) is a 3★ card. The crown is now the only mastery signal, and it needs to be more visible than it is (§3, N2).

| Area | R4 sign-off | **R6** | One line |
|---|---|---|---|
| In-game, Duo | 8.8 | **8.9** | The gate card offers "Use touch instead"; the shift banner sits on the awning; nothing lands on the fold; the re-gate after a close reads well. |
| In-game, iPhone | 8.4 (8.6 after P1-A) | **8.5** | The conveyor zone and belt queue are excellent, and the dark-venue score is fixed. The intro card covers the jug, and the stamp issues (26, 18) hold it back. 8.7 after ROUND-7. |
| UI / screens | 8.7 | **8.9** | The Daily ceremony, the crowns, and "3 of 7" with a coaching tip are real upgrades. The failed card still has an orphan "0", and the share preview wraps. |
| Game design | 8.6 | **8.7** | Teaching, Rush travel and crowns are the right systems. The new star rule and the possible Fizz-tier wall are open questions. |
| Juice (visible) | 8.3 | **8.5** | Potion sparkles in the liquid, the amber belt zone, the tier banner, the crown chip. The shake rope still snakes (s4). |
| Late game | 7.0 (R5) | **8.2** | Every REVIEW-5 late-game P1 is on screen or in code. Day-7 retention now depends on what the crown chase looks like. |
| **Overall** | 8.7 | **8.8** | Better than the sign-off build, with no regressions in the first hour. |

---

## 1. REVIEW-5's top 8: status

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | Fading line defeated by the shimmer | **Fixed (code)** | Round 5 commit: "shimmer muted on faded lines". Stills can't show audio. No frame yet shows a faded line or the ghost tick (25 is captured before the fade). See N6. |
| 2 | Late mechanics untaught | **Fixed** | 24: the venue intro card has a belt diagram, "THE CONVEYOR" and an instruction verb ("Start pouring *before* they reach the spout"). 25: "Shift 3 · Now You See It". Venue subtitles are now instructions (09/23: "Foam: pour slow, then top up", "Thick drinks: stop early"). The hold and copy are in ROUND-7. |
| 3 | Rush: belt on wood, invisible tiers | **Fixed** | 26: "🔥 TIER 2 · FIZZ!" over the dusk Soda Fountain (keg jug, tap tower, checker tiles). 20: tier 2 at 20 served is the Soda Fountain. No belt-on-planks in any frame. |
| 4 | Conveyor window invisible | **Fixed (best in show)** | 16: an amber glow band under the stream with »» chevrons either side; the line tab is half drained (yellow half, at 300, 676 pt); the next mug rides in from the left edge on the belt. The "04" ticket decal is now a chevron roundel. |
| 5 | Sand repose invisible | **Fixed (code), identity fixed (frame)** | 19: terracotta wall, a zigzag tile band, a desert-sunset arch window, a cactus and an hourglass. It's a different room now, not Lemonade in beige. The scoop's sight glass is now a slot with ticks, so less of a face. No frame shows `reposeProgress` > 0.7, the trickle, the heap or the hourglass glass (N6). |
| 6 | Failed shift: headline, progress, tip | **Mostly fixed** | 22: "Shift over — 3 spills", hero "3 of 7 glasses", and the tip "Foam keeps rising after you stop. Stop early, let it settle, top up." The Duo version is the same (duo-04/06). **Left:** no ghost glasses for the unserved four, an orphan grey "0" under the hero, and the stats line repeats "3 glasses" (N3). |
| 7 | Daily: 10 glasses, streak, share | **Fixed** | 29: "🔥 2 days in a row", a T–M dot strip, 540, "best 1,840", all ten recap glasses, and a share preview ("Brim Daily #298 🟩🟩🟥… 540 🔥2"). The "Next unlock" line has gone from the Daily card. |
| 8 | Crowns plus the 3★ rule on results | **Fixed** (rule text in ROUND-7) | 27 and duo-ui-results: "Flawless shift!" with a "NEW FLAWLESS CROWN" chip. 23: cyan rings with a crown badge on each bubble, and "👑 8/8" per venue. `chaseLine` in the working tree already speaks the new rule and the crown line. |

**REVIEW-5 P2s also landed:**
- cream score on dark venues (17, 25);
- potion magic: star motes in the vial and flute (17, 18);
- belt queue (16);
- ticket decal replaced (16, 24);
- cream soda recoloured (`LiquidCatalog`: vanilla over caramel-amber, smaller head);
- unlock line dropped on Daily and failed cards (21, 22).

**Still open from earlier reviews:**
- the shake rope snakes (s4);
- root beer in a mug with a cream head reads as a beer stein (store-s3, QA-2 P2-14);
- the Perfect bloom whitens the headspace (03, s2).

Glass Cabinet, Daily themes and Dead centre are not started, as expected.

---

## 2. Better / worse

**Better:**
- The conveyor is now the most readable special mechanic in the game. Zone, chevrons, draining tab and queue all point at one window (16).
- Each venue now announces itself three ways: the venue pill, the banner and the card (24, 25). The Potion score is legible.
- Rush has a sense of place and progress (26). The tier banner in yellow with a flame is a proper "level up".
- The Sand Bar finally earns its secret slot (19).
- The Daily card is the share artefact it should be (29).
- The Duo gate card shows "Use touch instead" as a real button inside the card (duo-00), not a footnote. The Duo results recap on the flat half, with cyan ✓ coasters, is lovely (duo-ui-results).

**Worse or new:**
- **Frame 20** (N1).
- **Stars cheapen** under the new rule (N2).
- **The iPhone intro card covers the jug.** It sits from y ≈ 330 to 507 pt, over the jug's lower third and its badge, and stacks under the shift banner (24). That's three labels saying "Conveyor, shift 1" at once (N4).
- **On tall glasses the PERFECT stamp now sits on the rim** (18, flute 5-7: stamp bottom ≈ 537 pt against a rim at ≈ 531 pt, covering the tab). This is a different case from QA-3 P1-1 (N5).
- **08-results and 27-flawless are now the same frame.** The store has lost its "ordinary 2★" results shot (N7).

---

## 3. New issues, ranked

### P1

**N1. Rush dies in the Fizz tier in frame 20. Verify, and soften if it's real.**
- **What I see** (20-rush-late, `mode=rush;autopilot=perfect;streak=18`, 30 s):
  - "20 served", 4,500, all three strike cups red (105–157, 106 pt);
  - no streak chip and no glass at the stop;
  - only the waiting tumbler at the left (≈ 75, 720 pt);
  - a full cola keg jug.

  The r5 capture of the same line showed 6,500, ×5 🔥18, mid-pour.
- **Why it matters:**
  - Rush now ends only on 3 *rim* spills (or a dry jug).
  - Foam is exactly what makes rim spills, and BALANCE §6 already calls foam "the casual's hardest venue".
  - Tier 2 (glasses 13–24) is all foam under a patience ring.
  - If the autopilot, which pours foam carefully in shifts, strikes out there, many humans will too. They would never reach the Conveyor, Diner or Potion tiers, which defeats ROUND-6 decision 2.
- **Fix:**
  1. Tonight: read the frame-20 CI log (judgements for glasses 13–20). If it's autopilot, demo-arg or capture timing, fix the scenario. `streak=18` may no longer be honoured once tiers seed from the glass count; use `freezeOn=midpour` at glass ≥ 25.
  2. If it's real (next round, Core plus balance): cap foamy lines in Rush tier 2 at about 0.70, bias tier 2 toward cream soda (foam 0.4) over root beer, and give tier 2 two extra seconds of patience. Re-run BALANCE's Rush rows, aiming for ≥ 70 % of casual runs reaching tier 3.

  Files: `Core/GameSession.swift` (Rush plan near `:1419`), `Core/CoreTuning.swift`, `ci/scenarios.txt`. **Does not block TestFlight.** TestFlight is the right place to learn this; add it to the tester brief.

**N2. "3★ = no misses" inflates stars. Make the crown the visible chase.**
- **What I see:** 28 shows six ✓ glasses and "0 perfect · best streak 0". Under tonight's rule that's 3★. On 23, all 120 stars are gold, and only the cyan rings separate mastery.
- **Why it matters:** the stars stop meaning "good". The first card a player sees after a clean-but-sloppy shift says 3★ and then "0 perfect · best streak 0": praise and scold in the same breath.
- **Fix (UI, next round, low risk):**
  - On a cleared shift, replace the stats line with the crown line `chaseLine` already returns ("Flawless crown: every glass Perfect. You had 0 of 6.") and **drop "best streak 0"** whenever it is 0.
  - Store the **best Perfect count per shift** (one `[String: Int]` in ProgressData, decoded tolerantly like `crowns`). Show it under each 3★ bubble as a thin cyan arc or "4/6". The venue line becomes "👑 3/8 · ✦ 41/52".
  - Then a 3★ shift still shows how far it is from its crown.

  Files: `UI/ResultsView.swift` (`statsLine`), `UI/VenuesView.swift` (`ShiftBubble`), `Persistence/ProgressStore.swift` (+ AppTests). Ship the stats-line half with the star rule if the App owner has room; it's a two-line change.

### P2
**N3. Failed card, last mile** (22, duo-04/06):
- Draw the unserved glasses as faint outlines in the recap (`RecapRow` ghost items). "3 of 7" needs its picture: four empty slots on the phone, two on the Duo counter, where there's room to spare.
- Drop the grey "0" on a struck-out shift, or label it "0 pts".
- Remove "3 glasses" from the stats line: the hero already says it.

File: `UI/ResultsView.swift`.

**N4. iPhone venue intro card placement and stacking** (24):
- On phones, show the shift banner *after* the card is dismissed, not under it.
- Drop the "THE CONVEYOR" small caps: the venue pill already says it.
- Anchor the card low, over the empty floor between the counter (≈ 455 pt) and the glass rim (≈ 600 pt), shrunk to the diagram plus two lines. That keeps the jug and its new chevron badge visible while the player reads "start before the spout".

Files: `UI/LateGameOverlays.swift`, `UI/PlayOverlays.swift`.

**N5. The stamp crowds tall glasses** (18): on the flute, PERFECT's bottom edge sits on the rim and hides the line tab at the moment of the verdict. Keep a minimum 10 pt gap above the rim. When the space above the rim (below the counter at ≈ 455 pt) is too small, scale the stamp to 0.85. File: `Scene/SceneGlass.swift drawStamp` (the same function ROUND-7 touches; fold it in only if it's trivial, otherwise next round).

**N6. Evidence gaps for round-6 features no frame shows.** Add scenarios:
- `30-sand-slide` (6-1, `freezeOn=repose` at `reposeProgress` ≈ 0.85: trickle, sight-glass creep);
- `31-potion-faded` (5-3, freeze 1 s after the fade: the ghost tick);
- `32-hourglass` (once balance uses it; mind QA-3 P2-16's post width);
- `33-rush-low-jug` (fill < 20 %).

Files: `ci/scenarios.txt`, `App/DemoMode.swift` (`freezeOn` keys). Without them I can't score the sand telegraph, the most important new mechanic.

**N7. Scenario hygiene:**
- 08-results now duplicates 27 (both "Flawless shift!" 800). Point 08 at a 2★ run (`autopilot=great`).
- Re-shoot 28 with one miss, so it shows the new rule.
- Re-shoot 20 per N1.

File: `ci/scenarios.txt`.

**N8. Daily share-preview wrap** (21 against 29):
- With no streak, the emoji row breaks 9 + 1, and the tenth square drops beside "540". With a streak (29), it fits.
- Put the 10 squares on their own line with `lineLimit(1)` and `minimumScaleFactor(0.7)`, and the header "Brim Daily #298 · 540 🔥2" on the line above.
- "Day 1 of your streak" reads oddly on a first-ever Daily. "First Daily: come back tomorrow for 🔥2" sells the ritual.

Files: `UI/ResultsView.swift`, `UI/ShareText.swift`.

**N9. The Duo cover while a shift is paused** (duo-08): a mid-pour close shows the generic "Open me to pour" plus Rush best and Daily. Say what's waiting: "Lemonade Stand · 2 paused. Open to carry on." File: `UI/PoseCards.swift:244-260`.

**N10. Beer read, still** (store-s3):
- Root beer in a handled mug under a cream head is a stout in a stein. Store frame S3 should use the soda flute or the tumbler.
- Cream soda is now caramel-amber with a white head. In a pint glass that edges toward amber ale, though in a jug (26) it reads as iced coffee, which is fine. Check one Rush tier-2 frame with cream soda in a pint before any store use.

Files: `ci/store-scenarios.txt`, `Core/LiquidCatalog.swift:34-36`.

**N11. The conveyor jug badge rotates with the tip** (16): the »» roundel, tipped about 40°, reads as clock hands. Counter-rotate the decal or use a gear. File: `Scene/SceneJug.swift` (decal).

**N12. Note, not a finding:** the hinge script now strikes out 1-1 before the close test, so duo-04 and duo-06 are both results cards. The mid-shift close/reopen path is captured only on shift 2 (duo-07 to duo-09, which look right: "Lay it flat to carry on", strike count kept). Consider a gentler tilt for the first hold so duo-04 shows "served" as its name says. File: `ci/duo.sh`.

---

## 4. Top 6 for the next round

| # | Item | Owner / files | Why |
|---|---|---|---|
| 1 | **Rush Fizz-tier wall**: verify frame 20; if real, cap tier-2 foam lines at 0.70, bias to cream soda, +2 s patience; target ≥ 70 % of casual runs reaching tier 3 (N1) | Core: `GameSession` Rush plan, `CoreTuning`; Balance: Rush rows | Rush travel is worthless if runs die at glass 13. |
| 2 | **The crown is the chase**: the stats line becomes the crown line, no "best streak 0", best Perfects per shift on Venues bubbles (N2) | App: `ResultsView`, `VenuesView`, `ProgressStore` | The new star rule makes 3★ common; this keeps a goal on every shift. |
| 3 | **Evidence frames** for sand slide, potion fade, hourglass and low jug, plus re-shoots of 08, 20 and 28 (N6, N7) | App: `ci/scenarios.txt`, `DemoMode` | The headline round-6 mechanics are unreviewed until they're on screen. |
| 4 | **Failed card last mile**: ghost glasses, no orphan "0", deduped stats (N3) | App: `ResultsView` | The fail screen is where retries are won. |
| 5 | **Intro card on iPhone**: banner after the card, card low and compact, jug visible (N4); stamp gap on tall glasses (N5) | App: `LateGameOverlays`; Scene: `SceneGlass` | The first moment of every late venue on the most common device. |
| 6 | **Glass Cabinet lite** (REVIEW-5 long-term #4): unlock the venue vessels for Rush and Practice via milestones | App + Scene: `ScenePalette` vessel override, new `CabinetView` | The biggest unstarted retention lever. The crowns now give it currency ("10 crowns → potion flask"). |

---

## 5. Should 1.0 (3) go to TestFlight tonight?

**Yes**, if the following hold:
1. ROUND-7's three P1s and the `Rules.stars` change land in **one** green CI run, with the chase-line test updated in the same commit (QA-3 P1-2).
2. Frame 26 is re-shot after the stamp fix and shows no stamp over the new glass.
3. Someone reads frame 20's CI judgements and writes one line in PROJECT-LOG: "autopilot/scenario" or "real tier-2 wall".

Either answer still ships to TestFlight. If the wall is real, add it to the tester brief: "Rush: tell us which glass number ended your run."

**Not yet for App Store submission:**
- the REVIEW-3 condition-2 real-Duo session still gates release;
- N1 must be resolved;
- the store set needs a re-shoot: 08, S3's mug, and anything showing the old star rule.

**Tester brief additions:**
- whether the conveyor intro card left time to read;
- whether anyone noticed the sand about to slide before it did;
- Daily streak screenshots;
- the Rush glass number at game over.
