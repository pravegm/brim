# Brim — balance: the difficulty curve and how we measure it

*Owner: balance design. Round 5, 26 Oct 2026. The harness is `BrimTests/BalanceTests.swift`; the content is
`Brim/Core/LevelCatalog.swift`. Numbers below come from a Node mirror of Core + the same player model (the Swift test
is a straight port); CI's `BRIM-BAL` lines replace them once a sweep has run. Treat every number as a model estimate
until the real-Duo TestFlight session calibrates it (§7).*

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

| Measure | Target | Why |
|---|---|---|
| Novice clears 1-1 … 1-4 | ≥ 85 % each | first minutes; no early churn |
| Novice first wall (clear < 50 %) | venue 2–3, not venue 1 | learn the pour before the twists |
| Casual clears every shift | ≥ 50 % (venue finales x-8 ≥ 35 %; Sand Bar exempt) | no shift is a paywall-style blocker |
| Casual 3★ likely | ~40 % of shifts | stars feel earnable; 3★ everywhere is mastery |
| Expert clears | ≥ 90 % mean; no shift at 0 % | hard ≠ broken |
| Venue v shift 1 vs venue v−1 shift 8 | shift 1 easier (casual ★) | each venue opens with a breather |
| Rush run length | casual 2–3 min, expert 5–8 min | the long session; leaderboard spread |
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
BRIM-BAL rush profile=expert runs=12 glasses=22.2 dur=135.0 perfect=0.38 spill=0.01 over=0.06 short=0.05 score=2380 capped=0
BRIM-BAL daily profile=casual days=20 clear=0.60 perfect=0.23 spill=0.06 over=0.11 short=0.05 dur=57.8 score=466
BRIM-BAL timing suite=levels tier=standard attempts=264 skipped=0 frames=634000 wall=540.2 fps=1174
BRIM-BAL WARN rush casual run 95.2 s, target 120–180
```
`spill` = drink crossed the rim; `over` = filled past the Good band (a strike since round 5); `three` = 3★ attempts;
`dur` = seconds of play per attempt.

**Cost and tiers.** A debug-build 60 Hz `GameSession` frame costs roughly 2–3 ms on CI (estimate: CoreTests step
~100 k frames and take 240–300 s), so a full sweep (~1–2 M frames) cannot run on every push. The first CI run's
`timing` lines replace the estimate.

| Tier | What | CI wall (est.) |
|---|---|---|
| `smoke` (default) | novice 1-1 ×3; casual 2-2, 4-4, 5-5; expert 3-4, 4-8; one casual Rush (60 s cap); one casual Daily | ~30 s |
| `standard` | 44 shifts × 3 profiles × 2; Rush 4 seeds × 3; Daily 6 days × 3 | ~10–12 min |
| `full` | × 4 attempts; Rush 12 seeds; Daily 20 days (budgets 900/400/300 s) | ~20–25 min |

Pick a tier with `TEST_RUNNER_BRIM_BAL=standard` in the environment of `xcodebuild test` (xcodebuild strips the prefix
and hands it to the test process), or flip `BalanceConfig.defaultTier` for one push and back. Other knobs (same prefix):
`BRIM_BAL_ATTEMPTS`, `BRIM_BAL_RUSH_SEEDS`, `BRIM_BAL_DAYS`, `BRIM_BAL_BUDGET` (s per suite, 0 = none),
`BRIM_BAL_LEVELS=2-1,2-2`, `BRIM_BAL_PROFILES=casual`. Rounds run breadth-first in parallel (`concurrentPerform`), so a
budget trims attempts evenly; every unit is seeded, so a unit's numbers never depend on tier, budget or thread.

**Assertions are loose sanity bounds** (CI stays green while numbers move): runs finish (≤ 10 % hit the 180 s cap),
novices clear 1-1 at least once in 3 tries (and ≥ 50 % from 6), experts clear ≥ 75 % of shifts (when ≥ 20 were sampled), every
Rush run serves a glass and expert Rush runs last 30–600 s, Daily runs finish and serve ≥ 3 glasses. The §2 targets are
WARN lines only.

## 4. Baseline (round-5 Core, content before this pass; Node mirror, 12 tries per shift and profile)

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

## 5. Changes this pass (`LevelCatalog.swift`, content only)

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

## 6. After (same model and seeds)

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

**Still off target** (needs data or another owner):
1. **Casual 3★ is rare** — likely on ~10 % of shifts (target ~40 %); experts ~40 %. 3★ needs every glass a hit and
   ≥ 60 % Perfect; the model casual lands ~20–45 % Perfect in ±2.5–4.5 % bands. Not changed yet: Perfect rates are
   the least calibrated number in the model, and the band is the feel of the game.
2. **Venue 2 is the casual's hardest venue** (0.65), harder than venues 3 and 5; venue 3 shift 1 is a breather after
   it, as intended, but the foam venue sits early. If the real Duo agrees, lower root-beer lines again or move 2-7's
   exam to venue 3's slot.
3. **Rush is short for everyone**: ~1.6 min casual, ~2.3 min expert (targets 2–3 and 5–8).
4. Novices hit the venue-4 belts hard (0–0.4 on 4-5…4-8). Acceptable: by then they are casual players.

## 7. Recommendations for other owners

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
