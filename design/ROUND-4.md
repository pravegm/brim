# Round 4 brief (founder): final polish before launch

Inputs: `design/REVIEW-3.md` (8.4/10, launch call "yes" with conditions: fix its four P1s and re-shoot) and
`design/QA-1.md` (no P0, four P1s, 25 P2s). Everyone reads both. **Every P1 in both docs is mandatory.** P2s in your own
files: fix the ones that are low-risk and visible; list what you skip and why. Don't regress anything REVIEW-3 praises.

Short = strike in shifts/Daily, Rush strikes only on spills (GAME-DESIGN §5, now documented). Keep it.

## Cross-module assignments
| Item | Owner(s) |
|---|---|
| REVIEW-3 P1-1 waiting glass: smaller (≈0.8), dimmer, no line, on its coaster | Scene (art) + Core (scale/placement data if needed) |
| REVIEW-3 P1-1 "Fill to here" pill must avoid the waiting glass | App (`PlayOverlays`/`Layout`, read `GameScene.waitingGlassWorldFrame`) |
| REVIEW-3 P1-2 Duo home stream reads as beads | Scene (drop/stream art when flow is low) + App (menu capture timing in DemoMode) |
| REVIEW-3 P1-3 Venues row on the fold | App (`VenuesView`) |
| REVIEW-3 P1-4 iPhone next glass cut by the bezel | Core (`nextGlassEdgeMargin` ≥ 16 measured to the coaster edge) + Scene |
| QA P1-1 persisted hinge flag on a non-Duo | App |
| QA P1-2 Daily retry loophole (attempt-started marker) | App (`ProgressStore`, UI) |
| QA P1-3 canvas change restarts the run (keep the session, swap the scene) | App |
| QA P1-4 idle timer during hinge-only play | App |
| QA P2 engines running on menus (battery) | Feel (+ App calls) |
| QA P2 touch on a Duo between 70°–78° | Feel |
| QA P2 per-frame churn in the simulation | Core |
| QA P2 Daily across UTC midnight, GC queue, progress backup, Release log line | App |
| QA P2 review-notes text vs build | App (update `docs/appstore/review-notes.md` to match the build exactly) |
