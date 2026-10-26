# Brim — balance: the difficulty curve and how we measure it

*Owner: balance design. Rounds 5–6, 26 Oct 2026. The harness is `BrimTests/BalanceTests.swift`; the content is
`Brim/Core/LevelCatalog.swift`, and since round 6 the star rule (`Rules.stars`). The first full CI sweep ran on the
round-5 content (§9); this pass was tuned on the Node mirror of Core + the same player model and waits for the next
sweep. Treat every number as a model estimate until the real-Duo TestFlight session calibrates it (§8).*

**Latest pass: §11 (round 8 pass 2: Sand Bar at 105★, CI walls). §10: Rush Fizz tier, hourglass.**

## 1. What we want, and why

Brim is a £1.99 premium casual game: no ads, no IAP, no energy, no paywall. The player paid once, so the game owes them
the content. That sets the shape:

- **Generous early.** The first venue is where people decide whether the fold-to-pour idea "works". A first-timer must
  clear the first shifts nearly every time and land Perfects within a minute. Failing 1-1 on a phone you just bought
  for the gimmick is the worst possible review.
- **Mastery later.** Stars, 3★ and the Sand Bar are where the skill ceiling lives. Experts should still meet shifts
  that take a few tries; the secret venue (every campaign shift 3★) is for them only.
- **Walls are lessons, not tolls.** A venue may be hard for a while (foam, belts) but every shift must be clearable by a
  casual player within a few tries, and stars to open the next venue must come without grinding the hardest shift.
- **One more go.** Shifts last ~30–60 s; Rush is the long session; the Daily is one fair, scored attempt a day.

## 2. Target curve

Rates are per attempt unless stated. "Casual 3★ likely" = the chance of at least one 3★ in five tries is ≥ 50 %.
Stars (round 6, founder): 3★ = cleared with no miss, 2★ = one miss, 1★ = cleared (a miss is a short, over or spill);
the Flawless crown (every glass Perfect) is the mastery goal.

| Measure | Target | Why |
|---|---|---|
| Novice clears 1-1 … 1-4 | ≥ 85 % each | first minutes; no early churn |
| Novice first wall (clear < 50 %) | venue 2–3, not venue 1 | learn the pour before the twists |
| Casual clears every shift | ≥ 50 % (venue finales x-8 ≥ 35 %; Sand Bar exempt) | no shift is a paywall-style blocker |
| Casual 3★ likely | 40–80 % of shifts (WARN outside) | stars are earnable by clean pouring; crowns are mastery |
| Expert clears | ≥ 90 % mean; no shift at 0 % | hard ≠ broken |
| Venue v shift 1 vs venue v−1 shift 8 | shift 1 easier (casual ★) | each venue opens with a breather |
| Rush reaches tier 3 | casual ≥ 70 % of runs (round 8) | "Rush travels" is worthless if runs die in the Fizz tier |
| Rush run length | casual 3–5 min, expert 5–9 min (round 8; were 2–3 and 5–8) | the long session; leaderboard spread |
| Sand Bar reachable | an expert holds ≥ 105★ after 10 tries a shift (`expertBest10`); no shift where 3★ is unlikely | it opens at 105 of 120★ (round 8; was all 120) |
| Daily clear | casual ≥ 70 % | one scored attempt; most should finish it |
| Shift length | 30–70 s | "one more go" |

The Swift harness prints a `BRIM-BAL WARN …` line for each target it can check with enough samples.

## 3. The harness (`BrimTests/BalanceTests.swift`)

**Player model** (`BalanceHuman`, Core only, deterministic per seed). Each frame (60 Hz) it records what it sees: the
glass under the spout, the level relative to the line, the stream's flow, the patience ring, belt motion. It acts on
what it saw a reaction delay ago. It tips in until the stream appears (remembering where the pour point was), steers the
pour with a hand model ("this far past the pour point gives that much flow" plus a slow correction), eases off as the
line nears, and lays the jug back when *seen level + rise rate × anticipation* reaches its aim. The anticipation (s) is
learned from each served glass, per drink or class, with noise; spills make it more careful with that drink. Experts
read the judged top (liquid + a settled head), others the visible top. The hand is a spring with a speed limit and
tremor; the hinge reports at 30 Hz with noise in 5° steps; the app's One-Euro + hold stabiliser smooth it (re-implemented
in the test, not linked to `Input/`).

| | reaction | pours by | anticipation prior / learning | aim σ | eager | rests at |
|---|---|---|---|---|---|---|
| novice | 0.24–0.32 s | stream thickness (0.5) | 0.25 s, one value for all drinks, slow | 2 % | 15 % | flat |
| casual | 0.20–0.26 s | rise rate 0.30/s, sizes up the glass (±30 %) | 0.45 + 0.4·lag, per class | 1.2 % | 8 % | pour point − 12° |
| expert | 0.17–0.21 s | rise rate 0.35/s → 0.10/s near the line (±15 %) | 0.55 + 0.7·lag, per drink | 0.6 % | 3 % | pour point − 8° |

A player keeps what it learned across its attempts at a shift (retries), across Rush seeds and across Daily days. It
does not carry lessons between shifts (each shift starts from the profile's priors): the closest cheap stand-in for "has
played the venue so far". Known limits: foam is handled crudely (it learns caution, not the multi-stage top-up), and
belt play has no pre-hover.

**Output** — one line per unit, `print` + `fflush` (CI's `build.log` keeps test stdout):

```
BRIM-BAL level=2-7 profile=casual clear=0.50 stars=0.6 three=0.00 perfect=0.14 great=… good=… spill=0.36 over=0.02 short=0.08 dur=59.2 n=12
BRIM-BAL venue=2 profile=casual levels=8 clear=0.65 stars=1.0 three=0.00 perfect=0.22 dur=54.1
BRIM-BAL rush profile=expert runs=12 glasses=22.2 dur=135.0 perfect=0.38 spill=0.01 over=0.06 short=0.05 score=2380 capped=0 reachTier3=1.00
BRIM-BAL stars casualLikely3=0.61 expertLikely3=0.90 sandWalls=0 n=44/40
BRIM-BAL daily profile=casual days=20 clear=0.60 perfect=0.23 spill=0.06 over=0.11 short=0.05 dur=57.8 score=466
BRIM-BAL timing suite=levels tier=standard attempts=264 skipped=0 frames=634000 wall=540.2 fps=1174
BRIM-BAL WARN rush casual reachTier3 0.42 < 0.70
```
`spill` = drink crossed the rim; `over` = filled past the Good band (a strike since round 5); `three` = 3★ attempts;
`dur` = seconds of play per attempt.

**Cost and tiers.** Measured on CI (run 40248384068, `full`): the level suite ran 1.29 M frames in 448 s (2,900 fps
across the runner's cores), Rush 0.44 M at 5,700 fps, Daily 0.21 M at 4,300 fps: about 9.5 min for the whole `full`
sweep, so it stays opt-in (`balance.yml`) and the default `smoke` tier stays small.

| Tier | What | CI wall (est.) |
|---|---|---|
| `smoke` (default) | novice 1-1 ×3; casual 2-2, 4-4, 5-5; expert 3-4, 4-8; one casual Rush (60 s cap); one casual Daily | ~10 s |
| `standard` | 44 shifts × 3 profiles × 2; Rush 4 seeds × 3; Daily 6 days × 3 | ~4 min |
| `full` | × 4 attempts; Rush 12 seeds; Daily 20 days (budgets 900/400/300 s) | ~9.5 min (measured) |

Reading a `full` sweep: each shift line is four tries by a *fresh* player (no lessons from earlier shifts), so it
measures first contact, and one line moves by 0.25 per try. Judge venues and trends, not single shifts.

Pick a tier with `TEST_RUNNER_BRIM_BAL=standard` in the environment of `xcodebuild test` (xcodebuild strips the prefix
and hands it to the test process), or flip `BalanceConfig.defaultTier` for one push and back. Other knobs (same prefix):
`BRIM_BAL_ATTEMPTS`, `BRIM_BAL_RUSH_SEEDS`, `BRIM_BAL_DAYS`, `BRIM_BAL_BUDGET` (s per suite, 0 = none),
`BRIM_BAL_LEVELS=2-1,2-2`, `BRIM_BAL_PROFILES=casual`. Rounds run breadth-first in parallel (`concurrentPerform`), so a
budget trims attempts evenly; every unit is seeded, so a unit's numbers never depend on tier, budget or thread.

**Assertions are loose sanity bounds** (CI stays green while numbers move): runs finish (≤ 10 % hit the 180 s cap),
novices clear 1-1 at least once in 3 tries (and ≥ 50 % from 6), experts clear ≥ 75 % of shifts (when ≥ 20 were sampled), every
Rush run serves a glass and expert Rush runs last 30–600 s, Daily runs finish and serve ≥ 3 glasses. The §2 targets are
WARN lines only.

## 4. Round 5 pass — baseline (round-5 Core, content before the pass; Node mirror, 12 tries per shift and profile)

Mean clear / mean stars per venue (lowest shift in brackets):

| Venue | novice | casual | expert |
|---|---|---|---|
| 1 Lemonade Stand | 0.76 / 1.3 (0.50) | 0.91 / 1.7 (0.58) | 0.97 / 2.1 (0.75) |
| 2 Soda Fountain | 0.49 / 0.7 (0.00) | 0.61 / 0.9 (**0.00**) | 0.85 / 1.7 (**0.08**) |
| 3 Milkshake Diner | 0.79 / 1.2 (0.33) | 0.89 / 1.6 (0.58) | 0.98 / 1.9 (0.92) |
| 4 The Conveyor | 0.42 / 0.6 (0.00) | 0.67 / 1.0 (0.33) | 0.91 / 1.7 (0.67) |
| 5 Potion Shop | 0.41 / 0.5 (0.00) | 0.77 / 1.3 (0.58) | 0.96 / 1.8 (0.83) |
| 6 Sand Bar | 0.58 / 0.8 (0.25) | 0.90 / 1.5 (0.75) | 0.96 / 1.8 (0.92) |

Against §2: novice 1-1 0.75 and 1-3 0.67 (< 0.85); **2-7 "Root of the Problem" was a wall for everyone** (expert 8 %,
casual 0 %: root beer at 0.85–0.9 lines overflows from the head alone); venue 2's root-beer shifts 0.5–0.6 casual;
4-5 was harder than the venue's finale for casual players; Daily casual 0.50; Rush ~1.5 min casual, ~2.3 min expert.
(The other big wall the model found first — a shift jug running dry mid-glass and being judged short during the
swap — was fixed in round 5's Core: refills now happen between glasses.)

## 5. Round 5 pass — changes (`LevelCatalog.swift`, content only)

- **1-1** lines 0.6–0.7 → 0.66–0.72, first two glasses both water (no early jug swap). A longer pour gives a
  first-timer time to see the level coming. First line kept ≤ 0.66 for CoreTests' "over, not spill" headroom.
- **1-3** patience 14 → 16 s (the first timer), tallest line 0.8 → 0.75. **1-4** lowest lines 0.35/0.38 → 0.40/0.42
  (over-pour magnets), patience 13 → 14. **1-7** patience 14, flute lines ≤ 0.8. **1-8** patience 12, top line 0.9 →
  0.82.
- **Venue 2 (foam).** The head is what overflows. Poured at flow f, a head settles toward
  ≈ foamPerVolume × clamp(f/0.35, 0.2, 2.5) × f × 10,000 × foamSettle pt². Root beer at a calm f ≈ 0.3 → ~6,700 pt²,
  a third of a mug, so root beer lines are now ≤ 0.62–0.68 (≤ 0.75 in the tall soda glass); cola keeps ~16 % headroom
  at the same flow, so cola lines ≤ ~0.78. **2-7** rebuilt as the slow-pour exam: all root beer, lines 0.62–0.75,
  patience 15, full jug. **2-4/2-6/2-8** patience +1 s; **2-8** jug 0.7 → 0.8; **2-1** top lines 0.7 → 0.65.
- **Venue 4.** 4-5 belt 26 → 23 and its last tiny cup 0.7 → 0.6; 4-7 30 → 27; 4-8 36 → 33.
- **Daily.** Lines 0.42–0.88 → 0.45–0.85 (both extremes were miss magnets), foamy drinks capped (root beer 0.68,
  other heads 0.8), patience 14 → 9 s becomes 15 → 10 s. Same RNG calls, same warm-up and variety rules.

All of `LevelTests` still holds (checked against a mirror of every assertion; 44 shifts, ids, counts, 1-1 rules,
1-4/1-6/1-8 twists, Daily rules). Venue unlock thresholds unchanged.

## 6. Round 5 pass — after (same model and seeds)

| Venue | novice | casual | expert |
|---|---|---|---|
| 1 | 0.84 / 1.4 (0.58) | 0.95 / 1.7 (0.83) | 0.98 / 2.1 (0.92) |
| 2 | 0.53 / 0.7 (0.00) | 0.65 / 1.0 (0.42) | 0.98 / 2.0 (0.92) |
| 3 | 0.79 / 1.2 (0.33) | 0.91 / 1.7 (0.58) | 0.97 / 1.9 (0.92) |
| 4 | 0.39 / 0.6 (0.00) | 0.64 / 1.1 (0.17*) | 0.95 / 1.8 (0.83) |
| 5 | 0.41 / 0.5 (0.00) | 0.79 / 1.2 (0.67) | 0.95 / 1.8 (0.92) |
| 6 | 0.58 / 0.8 (0.25) | 0.90 / 1.5 (0.75) | 0.96 / 1.8 (0.92) |

Novice 1-1…1-4: 0.83–0.93 (1-1 0.90 and 1-3 0.93 over 30–40 tries). Expert mean clear 0.97, no shift below 0.83. Casual mean clear 0.80.
Daily casual 0.60–0.75 depending on sample. Rush unchanged (Core). \*4-8 casual swings 0.17–0.5 between samples: noise at
12 tries is ±0.14.

**Still off target after round 5** (round 6's answers are in §9):
1. **Casual 3★ is rare** — likely on ~10 % of shifts (target ~40 %); experts ~40 %. 3★ needs every glass a hit and
   ≥ 60 % Perfect; the model casual lands ~20–45 % Perfect in ±2.5–4.5 % bands. Not changed yet: Perfect rates are
   the least calibrated number in the model, and the band is the feel of the game.
2. **Venue 2 is the casual's hardest venue** (0.65), harder than venues 3 and 5; venue 3 shift 1 is a breather after
   it, as intended, but the foam venue sits early. If the real Duo agrees, lower root-beer lines again or move 2-7's
   exam to venue 3's slot.
3. **Rush is short for everyone**: ~1.6 min casual, ~2.3 min expert (targets 2–3 and 5–8).
4. Novices hit the venue-4 belts hard (0–0.4 on 4-5…4-8). Acceptable: by then they are casual players.

## 7. Round 5 recommendations for other owners

*All taken in round 6: refills 0.20/0.10, tiers every 12, only rim spills strike in Rush, `serveIdle` 0.5 s, and the
new 3★ rule in §9.*

- **Rush (Core: `CoreTuning`, `GameSession.serve`).** Two limits: the jug runs dry (economy), and once it doesn't, 3
  strikes end it (round 5 made over-pours strike in Rush). Modelled (10 seeds, same players):

  | Change | novice | casual | expert |
  |---|---|---|---|
  | today (refill P 0.14 / G 0.05, tiers every 8) | 97 s | 89 s | 131 s |
  | refills P 0.20 / G 0.10, tiers every 16 | 102 s | 111 s | 183 s |
  | … and only rim spills strike in Rush (overs break the streak only) | 173 s | 158 s | 323 s |

  The last row hits the targets (casual 2–3 min, expert 5–8). It reverses a round-5 founder decision, so it is the
  founder's call; the refill/tier changes alone are safe.
- **3★ (Rules / founder).** If real casual Perfect rates come in near the model's, either widen venue 1–3 bands by
  ~+0.008 (content, my file) or make 3★ "all hits, no spills, ≥ 50 % Perfect" (Rules).
- **Top-ups (CoreTuning.serveIdle 0.35 s).** A still drink is served 0.35 s after the stream lands, so a human (0.2 s
  reaction + tip time) can almost never top up a short pour; only foam gets the grace. GAME-DESIGN §5 says 0.6 s. A
  0.5 s idle would make "stop early, then top up" a real skill for still drinks.
- **Hinge steps.** The model reports in 5° steps (brief: "±5° like the real Duo"). Its filtered effect on clear rates
  was small (±0.03 vs 1° steps), but the first real-Duo log should replace the guess.

## 8. Calibration and the loop

1. Push; read the smoke lines and `BRIM-BAL timing` (frames per second sets the real cost of a sweep).
2. Run one `standard` sweep (`TEST_RUNNER_BRIM_BAL=standard`); compare with §6. Model and CI share the player logic, so
   agreement within sampling noise means the Node mirror can drive fast tuning and CI confirms.
3. Real-Duo TestFlight session (REVIEW-3 condition 2: 3 of 5 novices land a Perfect within 60 s): log per-glass
   judgements for a few players on 1-1…1-4, 2-1, 2-2. Fit reaction, aim σ and anticipation learning so the novice and
   casual rows match; then redo §2's gaps (3★ first, then foam, then Rush with Core).
4. Tune `LevelCatalog` (lines, patience, bands, belts, jug fill) against the WARN lines; keep LevelTests green.

## 9. Round 6 pass (founder decisions after the first full sweep)

**The sweep** (CI run 40248384068, `full`, round-5 content and round-6 Core). Venue clear rates: V1 novice 0.75
(1-2 and 1-4 only 0.50), casual 0.94; V2 novice 0.41, casual 0.59, with **2-1 harder than 1-8 for casual (1.0★ vs
2.0★)**; V3 casual 0.91; V4 novice 0.41, casual 0.62; V5 novice 0.28, casual 0.84; V6 casual 0.94. Casual likely-3★ on
0.09 of shifts. Rush casual 138 s, expert 334 s (on target after round 6's Rush changes). Daily casual 0.65. Mean clear
over all shifts: CI 0.53 / 0.80 / 0.96 (novice / casual / expert) against the Node mirror's 0.59 / 0.80 / 0.97, so the
mirror tracks CI. CI's per-shift numbers are four tries by a cold player, which is why its venue-1 novice rate sat
below the mirror's (which had averaged twelve learning tries).

**Founder decisions and what changed**

1. **Stars count clean pours** (`Rules.stars`, CoreTests `starRules`): 3★ = no miss, 2★ = one miss, 1★ = cleared.
   The Flawless crown carries the all-Perfect goal. Model: casual likely-3★ 0.09 → **0.61** of shifts, expert 0.86,
   novice 0.36. Open item for the App owner: `ResultsView.chaseLine` still says "3★ needs every glass a hit and N of
   M Perfect", which is no longer true; it should read "3★ needs every glass a hit. You had …"
   (`AppTests.resultsSayWhatIsLeftToChase` checks the old copy).
2. **Venue 1 genuinely gentle** (target: a cold novice clears 1-1…1-4 ≥ 85 % over the first four tries). 1-1…1-4 start
   with a full jug (a smaller first gush) and the jug only empties from 1-5; Perfect bands widen to 0.05 → 0.03 across
   the venue (they shape Perfects, not misses); 1-1's later lines rise to 0.75 with three waters first; 1-2 and 1-3
   lean on soda glasses and mason jars (a wide glass rises ~35 % slower per unit of flow than a tumbler, which helps a
   fixed-pace novice most) and 1-3 waits 18 s; 1-4's low lines sit at 0.5 in the widest glasses, 16 s. 1-8 stays the
   finale (third flute, 10 s). Cold novice, first four tries (40–60 players): **1-1 0.85, 1-2 0.88, 1-3 0.93, 1-4 0.88**.
3. **Venue-2 and conveyor entries.** 2-1 is now cream soda (round 6's smaller head) with one cola; 2-2 "Head Start" is
   cola and cream soda at 0.45–0.6, five glasses; root beer, the tallest head, now arrives in 2-4 (this also answers
   QA-2's "no root beer in a mug at 2-2" for the store frame). 2-7's first glass is an untimed mug of root beer to 0.55:
   it is the shift CoreTests' foam-settling check picks, and that check was written against exactly that glass. 4-1 belt
   16 → 14, 4-2 18 → 16 in mugs and tumblers. Fresh casual, first four tries, mean stars: **2-1 2.15, 2-2 2.12 vs 1-8
   2.00; 4-1 2.13, 4-2 1.86 vs 3-8 1.31.**
4. **Daily casual ≥ 70 %.** The Daily menu drops the tiny cup and the vial (over-poured 40 % of the time), allows at
   most two foamy drinks (root beer and cola were the most-missed Daily glasses, 43 % and 31 %), lines 0.52–0.82,
   patience 16 → 11 s (+2 s for root beer). Casual clear measured CI-style (fresh player every 5 days, 100 days):
   0.70 → **0.82**. Novice ~0.5.

**After (Node mirror, 12 tries per shift and profile, new stars):**

| Venue | novice | casual | expert |
|---|---|---|---|
| 1 | 0.91 / 1.8 (0.67) | 0.94 / 2.2 (0.67) | 1.00 / 2.5 (1.00) |
| 2 | 0.61 / 1.0 (0.08) | 0.74 / 1.4 (0.58) | 1.00 / 2.4 (1.00) |
| 3 | 0.77 / 1.4 (0.17) | 0.91 / 1.9 (0.75) | 0.98 / 2.3 (0.92) |
| 4 | 0.45 / 0.8 (0.00) | 0.64 / 1.1 (0.17) | 0.95 / 2.1 (0.83) |
| 5 | 0.33 / 0.4 (0.00) | 0.77 / 1.4 (0.58) | 0.96 / 2.1 (0.83) |
| 6 | 0.71 / 1.2 (0.42) | 0.94 / 1.8 (0.75) | 0.96 / 2.3 (0.92) |

(Stars use the new rule, so they read higher than §6's for the same play.) The late shifts of each venue stay the
challenge: 2-7/2-8, 3-8, 4-7/4-8 and 5-8 are where casual clear dips to 0.2–0.6. The Node mirror carries the round-6
Core changes that matter for shifts (`serveIdle` 0.5, cream soda's smaller head, the new stars, Rush refills, tiers
and strikes) but not Rush's per-venue menus, so its Rush numbers are not quoted; CI's are.

**For the next sweep, watch:** the venue-1 novice WARN lines (1-1…1-4), the 2-1/2-2 vs 1-8 WARN, casual likely-3★
(WARN outside 0.4–0.8) and Daily casual (WARN under 0.70).

## 10. Round 8 pass (REVIEW-6 N1: the Rush Fizz-tier wall; hourglass; star re-check)

**The mirror now carries Rush as shipped** (round 6–7 Core: per-venue menus, `Rules.rushVenue`, every Conveyor glass on
a belt, Fizz head caps). It tracks the tier each glass reached, so the Rush line gains `reachTier3`: the share of runs
whose tier-3 glass reached the stop (got through the Fizz tier). Casual runs are chained three seeds to a player, as
on CI; 300 casual runs over two seed sets, because the spread between players is wide (two sets of 150 differed by up
to 0.12).

**N1 is real, and it is two walls.** Round-7 Rush, casual: **reachTier3 0.23**, novice 0.03, expert 0.97. Casual
deaths in tier 2 split roughly evenly between three rim spills (root beer spilled 40 % of the time, cola 24 %, cream
soda 3 %, even at the existing 0.68/0.8 caps) and a **dry jug**: the Lemonade tier alone takes the 1.4× jug to about
half full (overs and Goods don't refill), so the jug runs out in the Fizz tier. The REVIEW-6 fix (caps, cream soda,
+2 s) on its own reaches about 0.4–0.55, so the jug had to grow as well.

**Changes** (Rush tunables only):

| What | Where | Was → now |
|---|---|---|
| Fizz line cap: 0.70 − 0.1 × (foam − 0.4), so cream soda 0.70, cola 0.65, root beer 0.61 | `CoreTuning.rushFizzLineCap/PerFoam`, `makeRushPlan` | 0.8 / 0.68 head caps only |
| Fizz drinks: tier 2 cream soda 4 : cola 1, no root beer; later Fizz visits (tiers 6, 10: experts) 3 : 1 : 1 | `GameSession.rushLiquidPool` (one `pick`, as before) | 1 : 1 : 1 |
| Fizz patience +2 s a glass | `CoreTuning.rushFizzPatienceBonus` | — |
| Rush jug volume 1.4 → 1.6 × the standard jug (same drawn shape; refills unchanged) | `CoreTuning.rushVolumeBoost` | 1.4 |

Alternatives that were modelled: also allowing root beer in tier 2 at 1 in 5 or 1 in 7 (0.59–0.66); refills of 0.22/0.14
on the 1.4 jug instead of a bigger jug (0.73–0.76); Great refill 0.12 on top (≈ +0.03).

**After (mirror):**

| | reachTier3 | run | ends (spill / dry) |
|---|---|---|---|
| casual (300 runs) | **0.23 → 0.80** (0.83 / 0.77 per seed set) | 157 → 255 s | 0.43 / 0.57 → 0.60 / 0.40 |
| novice (90) | 0.03 → 0.64 | 142 → 198 s | |
| expert (72) | 0.97 → 1.00 | 405 → ~510 s (≈ 20 % of runs hit the 600 s cap) | experts now die at tier 7 (the second Conveyor) |

Casual tier-2 spill rate ~22 % → ~9 %. A run that gets through tier 2 lasts beyond 2–3 minutes, so the Rush length
targets move to casual 3–5 min and expert 5–9 min (§2); the harness WARNs on casual `reachTier3` < 0.70. CI's `full`
tier runs 12 Rush seeds per profile, so expect its casual reachTier3 to wander ±0.12 around the mirror's figure. The Feel
owner's foam-competent autopilot should fix frame 20's capture separately (REVIEW-6 N1 step 1).

**Star rule re-check** (3★ = no miss; mirror, 12 tries per shift and profile): casual likely-3★ on **0.61** of shifts
(target 0.4–0.8), expert 0.91, novice 0.36. Mean clear 0.63 / 0.81 / 0.97. Daily casual 0.87. The new
`BRIM-BAL stars` line also counts **Sand Bar walls**: campaign shifts where an expert is unlikely to 3★ within ten
tries. There was one: **2-7 "Root of the Problem"** (expert cleared 12/12 but 3★ 0/12: root beer to 0.72–0.75 in a pint
and 0.62 in a jar spilled 26–31 % even for experts), so the 120-star unlock was out of reach. 2-7 now pours 0.5–0.65
(mug, pint, highball, jar; untimed mug to 0.55 first, kept for CoreTests): expert 3★ 0.00 → 0.42 a try, casual clear
0.53 → 0.67, novice 0.33 → 0.58. Same glass/drink pairs, so `dailyMenu` and every Daily stay byte-identical (checked).
Sand walls now: none.

**Hourglass** (GAME-DESIGN §6). The level crawls through the bulbs and races over the shoulders and the waist. In the
model, lines at 0.4–0.55 are over-pour magnets (casual over 16–25 %), while 0.3 and 0.65–0.85 play like a jar. It is
served in 6-2 (first glass, 0.75, so CI/store can freeze an honest `mode=shift:6-2` mid-pour frame, scenario 32), 6-3
(0.32 and 0.75) and 6-4 (0.72). Sand Bar after (casual / expert clear): 6-2 0.75 / 1.00, 6-3 0.92 / 1.00, 6-4 0.92 /
0.75: within noise of before.

## 11. Round 8 pass 2 (first `full` sweep of round 8: CI run 40261158155)

**The sweep.** Rush on target (casual reachTier3 0.75, 252 s; expert 514 s). Daily casual 0.75, casual likely-3★ 0.57.
Still off: novice 1-1/1-2 0.75; venue 2 casual 0.69 (2-4 0.25, 2-8 0.25; 2-6 novice 0); venue 4 casual 0.62 (4-7 0);
and six shifts where no expert try 3-starred (3-6, 4-4, 4-5, 4-8, 5-1, 5-5).

**A CI-shaped mirror.** CI plays each shift and profile with one fresh player over four tries, so one line moves 0.25
per try. The mirror now does the same with ten players each (`ci.js`, `cisweep.js`: 40 cold tries per unit), which is
the number the CI line scatters around. Per-glass miss tables showed what was going on:
- **Foam:** root beer and cola in wide glasses (mug, pint, jar) spill 45–60 % for the casual. The model's casual
  pours a wide glass faster, and the head grows with flow.
- **Tiny cups on fast belts:** casual short 84–100 %, expert over 45–60 %.
- **Low lines:** potion lines at 0.32–0.45 and the late conveyor mugs at 0.45–0.5 are over magnets, even for experts.

**Founder decision: the Sand Bar opens at 105★** (`starsToUnlock(.sandBar)`; LevelTests updated; the App's gate reads
it). The harness now projects what an expert holds after ten tries at every campaign shift: `expertBest10` on the
`BRIM-BAL stars` line, from per-try rates smoothed as (k + 0.5)/(n + 1). It WARNs when that is under 105 or more than
three shifts make a 3★ unlikely. Four cold tries without a 3★ no longer read as a wall.

**Changes** (`LevelCatalog`; every glass/drink pair keeps its first appearance, so `dailyMenu` and every Daily are
byte-identical; checked):
- **1-1:** later lines 0.75 → 0.65. The first stays 0.66 for CoreTests' fill-time and "over, not spill" checks.
- **1-2:** lines 0.58–0.65 (were 0.62–0.72).
- **2-4:** lines 0.5–0.7, 15 s, and 6 glasses (the 0.78 cream soda goes).
- **2-6:** 14 s, lower lines, and the second root beer becomes a cola mug.
- **2-8:** 12 s, lower lines, and the jar of root beer becomes a highball of cream soda.
- **3-6:** smoothie lines 0.55–0.8. The over-prone low pint and bowl move up.
- **4-4:** belt foam lines −0.05 to −0.15.
- **4-5:** belt 23 → 21; the two tiny cups become tumblers.
- **4-6:** the maple tiny cup becomes a mug; lines 0.4–0.55.
- **4-7:** belt 27 → 25; tiny cups at 0.45.
- **4-8:** belt 33 → 28; no tiny cup, 7 glasses, mugs at 0.6. It stays the venue's peak.
- **5-1:** lines +0.05 to +0.1.
- **5-5:** "small doses" at 0.4–0.5 (were 0.32–0.45).

**After (mirror, CI-shaped, 40 cold tries per unit; CI's run in brackets):**

| | novice | casual | expert |
|---|---|---|---|
| 1-1 / 1-2 | 0.85 / 0.88 (0.75 / 0.75) | 0.97 / 1.00 | 1.00 |
| venue 2 | 0.73 | **0.80** (0.69) | 0.99 |
| venue 4 | 0.54 | **0.80** (0.62) | 0.98 |
| all shifts, mean clear | 0.61 | 0.86 | 0.98 |
| likely-3★ share | 0.36 | 0.68 (0.57) | 0.98 (0.85) |

Expert 3★ a try, before → after: 3-6 0.23 → 0.42; 4-4 0.35 → 0.60; 4-5 0.17 → 0.63; 4-8 0.02 → 0.63; 5-1 0.33 → 0.42;
5-5 0.27 → 0.35. No campaign shift is below 0.35, so `expertBest10` is about 119 against the 105 needed.

Casual walls, before → after: 2-4 0.55 → 0.65, 2-6 0.63 → 0.80, 2-8 0.60 → 0.72, 4-7 0.47 → 0.68, 4-8 0.28 → 0.68.

2-7 stays the venue's exam (casual 0.55). Novice 2-6 goes 0.57 → 0.75. CI's own lines will scatter around these by
about ±0.2 per shift and ±0.07 per venue.
