# Brim project log

## Sun 25 Oct 2026: day 1

- **Brief (founder):** an iPhone Duo-first game that is simple, fun, addictive and satisfying, sold once for about £2.
  It must use the hinge, must not be Squish, and the whole thing runs unsupervised for 2–3 days to a launch-ready build.
- **Research** (3 agents in parallel):
  - `research/01-market.md`: about 45 hinge-as-verb apps already exist, so most metaphors are taken. No one pours
    with the hinge. No hinge game has Game Center or a daily mode.
  - `research/02-hinge-tech.md`: real-Duo facts. Updates arrive at 25–30 Hz only while the hinge moves. Accuracy is
    ±5°. Play should stay at 170°–60°.
  - `research/03-concepts.md`: 10 scored pitches.
- **Concept: Brim, fold to pour.** The founder's own shortlist (`00`) and the concept agent picked it independently.
  It scored 61/70, the top mark. Why it won:
  - Tipping a container is the most natural thing a hinge does.
  - The glass stays still while only the jug moves, which a normal phone can't do.
  - It tolerates sensor noise.
  - Its loop is the shape of Stack, not of a toy.
- **Name:** "Brim: Fold to Pour". "Brim" alone is crowded on the store, and "Pour Decisions" and "Fill Line" are taken.
- **Theme:** non-alcoholic café drinks, to keep the 4+ rating.
- **Infrastructure:** Squish's CI was adapted (`ci.yml`, `duo.yml`, `testflight.yml`). The repo `pravegm/brim` is
  **private**: the permission guard blocked creating a public repo without the founder's OK. The first probe run
  confirmed the macOS runner picks up jobs.
- **Team round 1** (4 engineers with disjoint file ownership, plus a launch lead):
  - Core: simulation and levels.
  - Scene: SpriteKit art.
  - Feel: input, synth audio and haptics.
  - App: shell, UI, persistence, Game Center and demo mode.

## Round 1 result (25 Oct, afternoon)
- The first integrated build compiled and passed **66/66 tests on the first CI run** (40202703065). Demo frames
  captured on the iPhone 18 Pro. The autopilot landed a real Perfect and a real Spill.
- App icon rendered by CI and committed (critic: 8/10, "best art in the project").
- **REVIEW-1: 5/10, "not yet".** The biggest finding was the rest pose: "stand it up like a laptop" was ~70° of
  tilt, which meant an instant pour and a spill. Others: the glass is tiny, the stream is thin and lands on the rim,
  a stream ran from an upright jug, Perfect and Spill have no drama, venues are just recolours, and safe areas were
  ignored.
- **First Duo simulator run (40203342285):** the `hinge` CLI drives the app; 100 `BRIM-H` samples were logged in one
  sweep. But the app was letterboxed: a portrait-only Info.plist on the Duo's landscape inner display gave a
  469 × 669 window, and a "small canvas = cover" rule then showed the cover card on every frame.
- **Founder decisions for round 2** (`design/ROUND-2.md`):
  - One 670 × 952 world for every device, aspect-filled.
  - **Flat rest pose** with a "lay it flat to start" gate.
  - Bigger hero objects.
  - All three orientations declared.

## Round 2 result (25 Oct, evening)
- 104/104 tests green after one test fix: the test, not the game, was wrong.
- **First real Duo game frames.** The orientation fix worked: the inner display is 2007 × 2853 portrait, and the flat
  gate shows at 120°. A hinge lift from 179° to 140° produced a stream crossing the fold into the glass, with 113
  `BRIM-H` samples.
- Visible wins:
  - venue identity: lemon jug with an awning, a neon DINER sign, a coiling milkshake stream;
  - Perfect fireworks with a streak pop, and a dramatic live spill with a puddle;
  - "Fill to here" and in-pour hints, and a results recap.
- Known leftovers:
  - the jug lid is drawn as an open white oval;
  - the Duo Home right-column buttons overlap the glass;
  - the glass sits right of centre.

## Round 3 (25 Oct, evening)
- **REVIEW-2: 7.5/10, "close".** New P0 from the Duo frames: closing the phone mid-pour read as a full tip and cost a
  strike.
- The fix is three layers:
  - an input guard that stops pouring below 78° or when the phone is closing fast;
  - an autopause below 70°;
  - a flat re-arm on every resume, plus `requireFlat` the moment the hinge reads as closing.
- CI proof on the Duo simulator: `CLOSE-GUARD autopause@31 resume@55 judged-between=0 PASS`.
- Other changes:
  - the pour is centred and the next glass waits in a slot;
  - signature vessels per venue: soda dispenser, steel shake tin, potion flask, sand scoop;
  - a fat, opaque stream, and puddles that dry;
  - nothing sits on the fold.
- 128/128 tests pass. The store pipeline's first run gave 10 captioned frames, all at slot size, 0 flagged.
- **REVIEW-3: 8.4/10. Launch call "yes"** on three conditions: fix its 4 P1s and re-shoot, pass a real-Duo TestFlight
  session, and build the store kit from the new frames. The critic calls it "a strong candidate for an Apple Duo
  feature".
- **QA-1** (code audit) found no P0 and 4 P1s:
  - the persisted hinge flag on a non-Duo;
  - the Daily retry loophole;
  - a canvas change restarts the run;
  - the idle timer can lock the screen.
- Achievement badge art: 10 badges at 1024 px, rendered by CI.

## Round 4 (final polish): in progress
- The REVIEW-3 and QA-1 P1s are mandatory (`design/ROUND-4.md`).
- **Round 4 result:** 156/156 tests green after hoisting mutating calls out of `#expect`.
  - The final Duo run passed `CLOSE-GUARD` again.
  - The final store set came out as 16 captioned frames: 6.9", 6.1" and Duo, at slot sizes, 0 flagged.
  - 10 achievement badges were rendered.
  - One overprint was found in D2: the streak pop sat on the PERFECT stamp because the stamp was measured at its
    pop-in scale. The fix is committed but **not compiled**.
- **CI blocked:** the run was refused with "recent account payments have failed or your spending limit needs to be
  increased". Private-repo Mac minutes ran out. The founder must make the repo public or raise the limit
  (`docs/HANDOVER.md` item 0).

## Mon 26 Oct
- The founder made the repo public, which unblocked CI. CI is green with the two uncompiled fixes: 156/156 tests.
- The store set was re-shot (run 40234263161) with 0 flagged. P2/D2 are verified clean: no overprint, and the full
  score shows on 6.1-inch.
- `testflight.yml` gained `check_only`, an unsigned Release archive: it passes (2.5 MB, privacy manifest OK, no demo
  code).
- TestFlight is now blocked only on the founder: the app record and the 4 ASC secrets.

## Night of 25–26 Oct (founder asleep; unsupervised)
- The founder added the 4 ASC secrets and the app record (Apple ID 6826940959).
- **TestFlight 1.0 (2) was uploaded** in 3m50s (run 40240439898). App Store Connect then reported it VALID and
  IN_BETA_TESTING (`tf-status.yml`).
- New CI frames for the venues no one had reviewed: conveyor, potion, sand, late Rush, Daily results, a failed
  shift, full venues.
- **QA-2** (first-hour real-device audit):
  - Suspected P0: the flat gate opened only at ≥174°, while a real flat Duo may read 170–174°.
  - P1s: a quick lift read as closing and re-locked the gate; the mid-pour jug refill flooded the glass; "SPILL"
    was stamped with no overflow; venue achievements fired when a venue unlocked.
- **Round 5** (`design/ROUND-5.md`):
  - gate opens at ≥168° with a "Use touch" escape;
  - "closing" only counts below 120°;
  - refills happen between glasses;
  - new `over` verdict;
  - achievements fire on clear.
- In parallel: the balance engineer (simulated novice, casual and expert players over all levels) and the critic
  (REVIEW-5: late venues and day-7 fun).
- **Round 5 landed green** (191/191 tests, run 40245461314). A foam test's simulated pourer was too fast for soda:
  that's the "pour slowly" mechanic working, so the test now pours like a careful player.
- **REVIEW-5** (late game): about 7.0, against 8.7 for the first hour. The special mechanics are never taught or
  signalled, and there's nothing to chase after 3★. It became round 6 (`design/ROUND-6.md`):
  - venue intro cards, and shift and tier banners;
  - Rush travels a venue per 12-glass tier;
  - Flawless crowns;
  - a Daily streak and week strip;
  - conveyor pour zone and belt queue, a potion ghost line, a real Sand Bar with a slide telegraph, an hourglass glass.
- **Balance harness:** simulated novice, casual and expert players. Rush was found too short and was rebalanced:
  bigger refills, and only rim spills strike in Rush. `serveIdle` went to 0.5 s so players can top up. Level 2-7 was
  rebuilt (it was a wall). `balance.yml` runs the full sweep.
- Round 6 compiled first try: 219/220 tests, with one stale test value fixed.
- **REVIEW-6:** overall 8.8, late game 8.2 (was 7.0). All of REVIEW-5's top 8 landed. The "perfect" autopilot
  struck out in Rush's Fizz tier; simulated human experts average 53 glasses, so the problem is mostly the bot's
  weakness with foam.
- **Balance pass 2:**
  - stars are now 3★ = no misses, 2★ = one miss, 1★ = cleared, with the Flawless crown for all-Perfect;
  - casual players are likely to get 3★ on 0.61 of shifts (was 0.09);
  - novices clear 1-1…1-4 85–93 % of the time;
  - the soda and conveyor entries are smoother;
  - casual players clear the Daily about 82 % of the time.
- **QA-3:** no P0. Its P1s, fixed in round 7:
  - a stamp lingered over the next glass;
  - the intro card didn't hold the belt (`setStartHold`);
  - the results chase line didn't match the new star rule.
- Round 7 + balance: **231/231 tests green.**
- **TestFlight 1.0 (3) uploaded** (run 40255370648).
- **Round 8** (`design/ROUND-8.md`), in progress:
  - Rush Fizz tier and an autopilot that handles foam;
  - a belt queue that looks ahead;
  - the crown chase;
  - a Glass Cabinet of unlockable vessels;
  - evidence frames;
  - the failed-shift card;
  - stamp placement on tall glasses.
- **Round 8 green** (259/259). REVIEW-7 scored 9.0 overall. QA-4 found no P0; its one P1 was the stamp over the
  waiting glass. Balance pass 4 put the Sand Bar unlock at 105★ and softened the walls.
- **Round 9 green** (268/268):
  - stamp placement fixed;
  - a visible sand-slide telegraph;
  - Glass Cabinet frames, with the secret vessel kept secret;
  - star wording by quality.
- Final balance sweep (run 40266626417), all on target:
  - casual clear rates: V1 .97, V2 .78, V3 .94, V4 .84, V5 .88, V6 .81;
  - casual likely-3★ .70;
  - experts reach 119.8★ after 10 tries, against 105 needed;
  - Rush: casual reaches tier 3 .75 of runs (4.2 min), experts run 8.6 min;
  - Daily: casual clears .75.
- The Duo CLOSE-GUARD passed again on rounds 8 and 9.
- **TestFlight 1.0 (4) failed** with "maximum number of certificates": automatic signing on CI made a new Apple
  Development certificate every run, and Squish's CI does the same on the same account. Fix in `testflight.yml`:
  - the archive is no longer development-signed;
  - it is archived unsigned, then the entitlements are stamped on with an ad-hoc signature;
  - the export signs for the App Store with Apple's cloud-managed **distribution** certificate.
  
  **TestFlight 1.0 (5) uploaded** that way, but without the Game Center entitlement; 1.0 (6) adds the ad-hoc stamp
  to restore it.
