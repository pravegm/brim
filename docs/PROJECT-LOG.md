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
