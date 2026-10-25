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
