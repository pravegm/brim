# CLAUDE.md: working on Brim

**Brim: Fold to Pour** is a paid (£1.99, no ads, no IAP, no data collected) iPhone game built **iPhone Duo first**.
The Duo is Apple's foldable (iOS 27.1). Stand it up like a laptop: the top half holds a jug, and lifting the top half
tips it. The stream crosses the fold into a glass on the flat half, and you stop exactly on the line.

The founder (GitHub `pravegm`) is the product owner and was away while this was built. Claude runs the studio:
founder, designer, developer, with parallel subagents per role and a design-critic loop. Sister project: **Squish**
(`C:\Users\59527\Squish`, pravegm/squish). Never modify it. Its CI and hinge lessons were reused here.

## The bar
1. **Duo-first.** Judge every change on the Duo tabletop frame first: the jug on the raised half, the stream
   crossing the fold, the glass on the flat half. The fallback for phones without a fold (drag up to tip) is secondary.
2. **Satisfying and addictive.** Juice is the product: sound, haptics, wobble, foam, the streak.
3. **Truthful store frames.** Nothing on a frame that the app doesn't do.

## Working rules
- Push straight to `main` (solo project, the founder's standing rule for Squish carries over). No PRs.
- Repo: https://github.com/pravegm/brim. It is **private**: making it public (free macOS minutes, as Squish
  does) needs the founder's OK. Keep personal and employer data out of it either way.
- **No Mac on the Claude side. CI is the compiler.** A Swift change is unverified until a GitHub Actions run passes.
- This Windows host: Bash ignores `cd`, so use absolute paths and `git -C`. There's no Python; use Node for quick maths.

## Build
`brew install xcodegen && xcodegen generate && open Brim.xcodeproj` (Xcode 27.1, iOS 27.1 SDK; deployment target
iOS 18; hinge code behind `#available(iOS 27.1, *)`; Swift 5 mode). `.xcodeproj` and `Info.plist` are generated.

## CI
| Workflow | Trigger | What |
|---|---|---|
| `ci.yml` | push | build + unit tests (iPhone 18 Pro sim) + demo screenshots (`ci/scenarios.txt`) + app icon render |
| `duo.yml` | manual | iPhone Duo sim (iOS 27.1 runtime), real hinge sweeps with the `hinge` CLI, tabletop frames (`ci/duo.sh`) |
| `testflight.yml` | manual | signed Release archive and upload (needs the 4 ASC secrets) |

```bash
gh run list -R pravegm/brim -L 5
gh workflow run duo.yml -R pravegm/brim --ref main
gh run download <id> -R pravegm/brim -D <empty dir>
```
App ↔ CI talk through stdout lines starting with `BRIM-` (`BRIM-T` timing/demo, `BRIM-H` hinge samples). Don't rename them.

## Docs (read in this order)
1. `design/GAME-DESIGN.md`: the game.
2. `design/ARCHITECTURE.md` + `Brim/Shared/Contracts.swift`: modules, owners, APIs.
3. `design/REVIEW-N.md`: design-critic rounds. `docs/PROJECT-LOG.md`: what happened when.
4. `research/00–03`: market, hinge tech facts, concepts.
5. `docs/LAUNCH-RUNBOOK.md`: what only the founder can do (Apple login steps).

## Hinge facts that bite (from Squish's real-Duo log)
- Use the **angle**, never `status == .closed` (it turns on at ~85° on hardware).
- Samples arrive at 25–30 Hz while moving and not at all while still, so predict between samples and smooth with One-Euro.
- Re-enable `onHingeChange` on each activation to get a fresh reading.
- The inner display ignores orientation locks. Tabletop = portrait canvas 669 × 951 pt with a horizontal fold;
  book pose = landscape.
