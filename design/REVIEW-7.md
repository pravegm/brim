# Brim: Fold to Pour: review 7 (round 8, from frames)

*Reviewer: design critic. Date: 26 Oct 2026. Inputs: `design/frames/r8/01–33` (iPhone 18 Pro, 1206×2622; coordinates
are in the 920×2000 preview, ×1.31 for pixels), `ci/scenarios.txt`, ROUND-8, BALANCE §10, and code reads of
`UI/CabinetView.swift`, `Persistence/ProgressStore.swift` (`GlassCabinet`, `bestPerfects`), `UI/ResultsView.swift`
(`chaseLine`, `statsLine`), `UI/VenuesView.swift`, `Core/Rules.swift` (`stars`), `Shared/Contracts.swift` (`isHit`),
`Scene/SceneJug.swift` (`updateTrickle`), `App/GameController.swift` (demo freezes, `vesselOverride`). There are no round-8
Duo frames, so the Duo score is held and its round-8 items are judged from code only.*

---

## 0. Verdict

Round 8 removed the biggest risk REVIEW-6 found.
- **The Fizz-tier wall is gone.** BALANCE §10 confirmed it was real (casual players reached tier 3 in 23 % of runs) and
  moves that to **80 %**.
- **Frame 20 now shows the late game as it should look:** 25 served, 10,000, ×5 🔥25, no strikes, mid-pour in the
  Conveyor tier with two glasses queued.
- **The failed card and the iPhone intro card are finished.**
- **The crown chase is on screen** on both the results card and the Venues screen.

Three things stop this being a clean sign-off:
1. **The sand-slide telegraph barely shows** (30). It was the main evidence REVIEW-6 asked for, and it now reads as a
   handful of 2–3 pt specks, in sand colour, against a sand-coloured wall.
2. **The Glass Cabinet has no frame.** It is the round's headline retention feature, and from code it has three
   problems: it lists the secret venue's vessel by name, it shows icons instead of the vessels, and nothing anywhere
   announces an unlock.
3. **Frame 33 (low jug) didn't capture.** There's no stream, the jug is about 65 % full, and the freeze never fired.

| Area | R6 | **R7** | One line |
|---|---|---|---|
| In-game, Duo | 8.9 | **8.9 (held)** | No round-8 frames. The Cabinet's flat-half placement and the banner lane are right in code. Unverified. |
| In-game, iPhone | 8.5 | **8.8** | The intro card sits low with the jug in view (24). The stamp clears tall rims (18). Rush reaches late tiers (20). The sand telegraph is the weak spot. |
| UI / screens | 8.9 | **9.0** | The failed card is now the best fail screen in the genre (22), and the crown line works (28). Share wrap still open (21). Cabinet unseen. |
| Game design | 8.7 | **8.9** | Rush is fair, and every 3★ shift has a visible next goal. The star order can still invert (08 vs 28). |
| Juice (visible) | 8.5 | **8.6** | The hourglass glass is lovely (32) and the potion ghost tick reads (31). The sand trickle is invisible, and the conveyor badge still reads as clock hands. |
| Late game | 8.2 | **8.7** | "Rush travels" is now true for most players. Crowns are now worth earning, since they unlock vessels. |
| **Overall** | 8.8 | **9.0** | Best build yet, with no regressions in the first hour. Remaining issues are evidence gaps and polish on new features. |

---

## 1. REVIEW-6's top 6: status

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | Rush Fizz-tier wall | **Fixed** | BALANCE §10: Fizz lines capped at 0.70/0.65/0.61, tier 2 is cream soda 4 : cola 1, +2 s patience, jug 1.4→1.6×. Casual reachTier3 0.23 → 0.80, novice 0.03 → 0.64. **20**: 25 served, ×5 🔥25, 0 strikes, Conveyor tier. **26**: the tier banner sits over a clean new glass (QA-3 P1-1 holds). **05**: the foam-aware autopilot pours a genuine soda frame. |
| 2 | The crown is the chase | **Fixed** (nits in P2-3/P2-4) | **28**: "Flawless crown: every glass Perfect. You had 1 of 6. Best 3." There's no "best streak 0". **09**: cyan arcs on 3★ bubbles (2 and 6 nearly closed, 4 and 8 at ¾) and "👑 1/8 · ✦ 35/51". **23**: arcs with crowns layered on top. |
| 3 | Evidence frames | **Partial** | 08, 20 and 28 re-shot correctly. 08 is a real 2★ card again ("You had 1 miss.") and no longer duplicates 27. **31** potion fade: the ghost ticks outside the walls read. **32** hourglass: an honest 6-2 mid-pour. **30** sand slide: captured, but the telegraph isn't visible (P1-1). **33** low jug: failed capture (P2-1). |
| 4 | Failed card last mile | **Fixed** | **22**: dashed ghost glasses and dotted coaster rings for the four unserved, no orphan "0", no duplicate stats line, and the foam tip. |
| 5 | Intro card on iPhone + stamp gap | **Fixed** | **24**: the compact card sits on the floor band (≈ 1055–1350), with the jug and its badge fully visible. No banner stacks on it, and "THE CONVEYOR" small caps are gone. **18**: PERFECT now sits beside the flute at rim height, clear of the tab. It touches the halo ring's left end (P2-7). |
| 6 | Glass Cabinet lite | **Code landed, no frame** | `CabinetSheet`, `GlassCabinet` (3/6/10/14 crowns), `vesselOverride` in Rush and Practice only, tolerant persistence, and tests. 01 shows the entry icon (`cabinet.fill`, top right). **No scenario opens the sheet** (P1-2). Design issues from code: P1-3, P2-2, P2-5. |

**Regressions:** none in the first hour or in the frames REVIEW-6 scored.

**Still open from REVIEW-6** (not in the round-8 brief, so not regressions):
- N8: the Daily share preview still breaks 9 + 1 without a streak, and "Day 1 of your streak" is still the copy (21).
- N11: the conveyor badge, tipped, still reads as clock hands (16, 20).
- N9: the Duo paused cover. Not re-checked.

---

## 2. Better / worse

**Better:**
- **Frame 20 is the store's best late-game frame now:** the dusk diner, the Conveyor jug, the amber zone, ×5 🔥25. It's
  the image of "Rush travels" that ROUND-6 promised.
- **The failed card** (22) shows "3 of 7" as a picture: three spilled glasses, then four dashed outlines. It's
  readable in half a second, kind, and it makes you want to retry.
- **The iPhone intro card** (24) is now a quiet label on the floor, not a modal. It sits where the belt will be, and the
  diagram matches the scene.
- **The hourglass** (32) is the most elegant glass in the game. The wooden posts frame it, the line sits on the upper
  shoulder, and sand fills the lower bulb. It earns the Sand Bar.
- **Potion fade** (31): the line is gone and the two tick stubs outside the walls hold its memory. That's subtle and
  fair.

**Worse or new:**
- The sand telegraph is still unproven (30).
- **Star order can invert.** 08 is 2★ for 500 points with 4 of 5 Perfect. 28 is 3★ for 400 points with 1 of 6
  Perfect, all others "hits", under the headline "Great shift!" (§3, P2-3).
- **The Cabinet names the Sand Bar's vessel.** Venues hides the Sand Bar as "Secret venue", and the store caption says
  "One *secret*", but the Cabinet lists "Copper scoop" under the hourglass symbol in sand colour from the first launch
  (P1-3).

---

## 3. Issues, ranked

### P1 (fix before App Store submission; none blocks TestFlight)

**P1-1. The sand-slide telegraph is effectively invisible.** (30, Sand Bar 6-1, `freezeOn=repose`, reposeProgress ≥ 0.85)
- **What I see:**
  - the scoop is tipped about 45° with a full sight glass and an empty jar;
  - near the lip there are two or three tiny specks (≈ 520, 775 and 520, 830);
  - nothing a player at arm's length would read as "it's about to go".
- **Why** (`SceneJug.updateTrickle`, `:526–562`):
  - grain radius is 1.0–1.5 pt;
  - at u ≈ 0.5 that's about 3 sitting and 4 falling grains;
  - the colour is the sand stream's own body colour over a terracotta and sand backdrop;
  - alpha is 0.35 + u.
  REVIEW-6 called this the most important new mechanic, and the Sand Bar sits behind 120★. The "unfair slide" is
  the late-game complaint most likely to reach a review.
- **Fix** (Scene, small):
  - grain radius 2.2–3.0 pt with a 0.75 pt ink outline at 0.45 alpha, or a darker sand tone (`body` × 0.75);
  - falling grains `1 + u*6` → `2 + u*9`;
  - from u ≥ 0.5, a scoop shiver of ±1.2° at about 14 Hz, its amplitude growing with u (skip under Reduce Motion /
    calm);
  - pulse the sight-glass slot toward amber-red as u → 1.
- **Then:** re-shoot 30 and put it in the tester brief ("Did you see the sand about to slide?").
- **File:** `Scene/SceneJug.swift`.

**P1-2. The Glass Cabinet has no frame.** The brief asked for the Cabinet, and the critic can't review a screen that
was never rendered.
- **Add a DemoMode `screen=cabinet`** (Home with the sheet open) and these scenarios:
  - `34-cabinet-fresh|screen=cabinet;progress=fresh|6`: all locks; the first view most players will see;
  - `35-cabinet-mid|screen=cabinet;progress=mid|6`: 1 crown in the mid save; add a `crowns=4` override or a richer
    preset so one tile is open and "In use";
  - `36-rush-vessel|mode=rush;vessel=sodaFountain;autopilot=perfect;freezeOn=midpour|12`: the override drawn in Rush,
    to check that the keg reads with the Lemonade tier's backdrop;
  - a Duo pass of 34/35 in `ci/duo.sh`: the card should sit in the flat half under the crease.
- **Files:** `App/DemoMode.swift`, `UI/HomeView.swift` (open on demo), `ci/scenarios.txt`, `ci/duo.sh`.

**P1-3. The Cabinet spoils the secret venue.**
- **What's wrong:**
  - `GlassCabinet.vessels` lists "Copper scoop" (venue `.sandBar`, 14 👑) to everyone;
  - `CabinetSheet.tile` draws it in the venue accent (sand) with `BrimTheme.symbol(.sandBar)` = "hourglass", even
    while locked;
  - VenuesView hides the same venue as "Secret venue" ("Three-star every shift to find it"), and store frames P5/D6
    sell "Five venues. One *secret*."
- **Fix (10 minutes):**
  - until `store.isUnlocked(.sandBar)`, draw the tile as "?" / "Secret vessel" with the lock and no accent;
  - its caption is "Find the secret venue";
  - exclude it from `nextLine` until then;
  - also require the venue to be unlocked, not just 14 crowns, so a player can't pour Rush from the scoop before
    finding the bar;
  - update the accessibility label to match.
- **Files:** `UI/CabinetView.swift`, `Persistence/ProgressStore.swift` (`GlassCabinet.isUnlocked` takes the store's
  unlocks), and AppTests (`cabinetUnlocksVesselsByCrowns`).
- Cheap enough for tonight if the App owner has ten minutes; otherwise first thing next round.

### P2

**P2-1. Frame 33 (low jug) didn't capture.**
- **What I see:** 19 served, 1,140 points, the jug about 65 % full, tipped, no stream, an empty jar.
- **Why:**
  - `freezeOn=lowjug` needs `stream` non-empty and `fill < 0.2`, so the freeze never fired;
  - the frame is the 60 s timeout;
  - with the 1.6× jug and refills, a `great` autopilot never gets under 20 %.
- **Fix:**
  - add a demo key `jugFill=0.22` (set after `served=` seeding), or seed `served=10` with `autopilot=good`;
  - make `ci/screenshots.sh` flag any `freezeOn` scenario whose log lacks `BRIM-T freeze <x>`, as `store-set.sh`
    already does.
- **Files:** `App/DemoMode.swift`, `ci/scenarios.txt`, `ci/screenshots.sh`.

**P2-2. Cabinet tiles show glyphs, not vessels.**
- The reward is a jug, but each tile is an SF Symbol (sun, bubbles, shake, moon, hourglass) in a venue-coloured disc.
  A cabinet of glassware should show the glassware.
- **Fix:** render each vessel's outline as a SwiftUI `Shape` from the same polygon `SceneJug` builds (or a 104 pt
  pre-rendered PNG per venue). Draw locked vessels as a grey silhouette, so the shape is the tease.
- **File:** `UI/CabinetView.swift` (+ a small `VesselShape`).

**P2-3. The star order can invert. Fix the presentation, not the rule, for 1.0.**
- **How the rule works:**
  - `Rules.stars`: 3★ = no misses and no spills;
  - `isHit` includes **Good**, so an all-Good shift is 3★ and is headlined "Great shift!";
  - 28 (1 Perfect, 5 Greats) is 3★ for 400 points; 08 (4 Perfect, 1 over) is 2★ for 500 points.
- **Is it too generous?** The casual 3★ rate (0.61) is inside BALANCE's 0.4–0.8 target. The Sand Bar gate is 120★,
  every star in five venues, and that relies on clean pouring being enough. So no rule change before TestFlight data.
- **For 1.0:**
  1. **08's miss line uses the crown glyph** for a star rule. Use `star.fill` there, and keep the crown for the crown
     line.
  2. **A 2★ card with Perfects at least half the glasses** gets the line "4 Perfect. One slip from 3★." The near-crown
     run should feel close, not scolded.
  3. **A 3★ card with Perfects under half** gets the headline "Clean shift!", which keeps "Great shift!" meaning
     something.
- **After TestFlight:** if testers say 3★ feels cheap, model "Good doesn't count toward 3★" in the mirror (including the
  120★ gate) before changing anything.
- **Files:** `UI/ResultsView.swift` (`chaseLine`, headline), AppTests.

**P2-4. Crown-chase copy and legend.**
- **28:** the line wraps to a widow ("1 of 6. Best 3."). Tighten it to "Flawless crown: 1 of 6 Perfect (best 3)" so it
  fits on one line at 402 pt.
- **09:** "✦ 35/51" has no legend. Give it a one-time hint the first time a bubble shows an arc ("✦ best Perfects:
  close the ring for a crown"), or show "35/51 Perfect" on the venue line.
- **Files:** `UI/ResultsView.swift`, `UI/VenuesView.swift`.

**P2-5. Nothing announces a Cabinet unlock, and the entry is easy to miss.**
- **What's missing:**
  - the Cabinet button on Home is an unlabelled `cabinet.fill`. On a Duo-first app its two-door glyph reads like the
    device or book mode (01);
  - crossing 3/6/10/14 crowns shows nothing;
  - the "NEW FLAWLESS CROWN" chip (27) doesn't say what crowns buy.
- **Fix:**
  - **results card:** when `totalCrowns` crosses a threshold, show the note "New in the Glass Cabinet: Soda dispenser"
    (using the existing `note` slot, which takes priority over "Next unlock");
  - **otherwise:** under the crown chip, show "2 more 👑 for the Soda dispenser";
  - **Home:** a gold dot on the Cabinet icon until the sheet is opened after an unlock.
- **Files:** `UI/ResultsView.swift`, `UI/HomeView.swift`, `Persistence/ProgressStore.swift` (a `cabinetSeen` count).

**P2-6. Daily share wrap and first-day copy (21), unchanged from N8.**
- Put the ten squares on their own line with `lineLimit(1)`.
- "First Daily: come back tomorrow for 🔥2" replaces "Day 1 of your streak".
- **Files:** `UI/ResultsView.swift`, `UI/ShareText.swift`.

**P2-7. Tall-glass stamp touches the halo** (18): PERFECT's right edge overlaps the halo ring's left end at rim height.
Nudge the stamp 10 pt further left, or raise it 12 pt when it's placed beside the glass. File: `Scene/SceneGlass.swift`
(`drawStamp`).

**P2-8. Conveyor badge reads as clock hands** (16, 20; N11): counter-rotate the decal with the tip. File:
`Scene/SceneJug.swift`.

**P2-9. Scenario hygiene:**
- `ci/scenarios.txt` line 51 still says 32-hourglass is "NOT captured yet", but line 57 captures it. Delete the stale
  comment.
- The store set (P1–P5) still has no late-venue frame. Frame 20 or 16 would sell more than R2. Consider swapping one
  in when the store set is re-shot.

---

## 4. Top 6 for the next round

| # | Item | Owner / files |
|---|---|---|
| 1 | Sand telegraph you can see: bigger outlined grains, more of them, scoop shiver, sight-glass warning; re-shoot 30 (P1-1) | Scene: `SceneJug.updateTrickle` |
| 2 | Cabinet evidence: `screen=cabinet`, frames 34/35/36 + Duo pass (P1-2) | App: `DemoMode`, `HomeView`, `ci/scenarios.txt`, `ci/duo.sh` |
| 3 | Cabinet keeps the secret: "?" tile and venue-unlock gate for the scoop (P1-3) | App: `CabinetView`, `GlassCabinet`, AppTests |
| 4 | Cabinet as a reward: vessel silhouettes, unlock note on results, badge on Home (P2-2, P2-5) | App: `CabinetView`, `ResultsView`, `HomeView` |
| 5 | Star presentation: star glyph on the 3★ line, "One slip from 3★", "Clean shift!" (P2-3, P2-4) | App: `ResultsView`, `VenuesView` |
| 6 | Low-jug frame and freeze-timeout flagging; share wrap; badge counter-rotation (P2-1, P2-6, P2-8) | App + CI; Scene |

---

## 5. Verdicts

### (a) Should TestFlight 1.0 (4) go out tonight?

**Yes**, if round 8 is in one green CI run: all tests, and the balance sweep's casual `reachTier3` not WARN. Allow CI's
±0.12 noise around the mirror's 0.80, and treat a single value of 0.68–0.70 as noise, not a blocker.

P1-3 (the secret vessel) is a ten-minute change; include it if it's ready. Otherwise ship anyway: TestFlight testers
aren't the store audience.

**Tester brief additions:**
- "Rush: which glass number ended your run?" (keep this one: it checks the 0.80 in human hands);
- "Did you see the sand about to slide before it went?";
- "Did you find the Glass Cabinet? What did you pick, and why?";
- "Did your 3★ shifts feel earned?";
- Duo testers: a photo of the Cabinet on the flat half.

### (b) Is it ready for App Store submission once the founder's real-Duo session is done?

**Not yet, but close: one more short round.** From a design standpoint, submission needs these, in order:
1. **The founder's real-Duo session passes** (REVIEW-3 condition 2: hinge feel, squish/pour satisfaction, fold
   frames). This is still the gate that matters most.
2. **P1-1 is fixed and frame 30 visibly telegraphs the slide.**
3. **P1-2 and P1-3:** Cabinet frames on iPhone and Duo reviewed, and the secret kept.
4. **Round-8 Duo frames** (intro card plus banner lane, results crown line, Cabinet sheet) **show no fold
   collisions.**
5. **The store set is re-shot on the submission build** (REVIEW-6's 08/S3 items, the new star-rule text visible
   anywhere it appears) and passes `store-set.sh` with nothing in `_flagged/`.

If 2–5 land and the Duo session is good, I'd sign off on submission without another full review. A frame check of
30/34/35/36 and the Duo set is enough.
