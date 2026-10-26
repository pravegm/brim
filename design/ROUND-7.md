# Round 7 brief (founder, overnight): QA-3 fixes

Input: `design/QA-3.md` (no P0, 3 P1s, 16 P2s on the round 5/6 code). Everyone reads it. Every P1 is mandatory; fix the
P2s in your files that are low-risk. The balance engineer is concurrently changing `Rules.stars` (decided: **3★ =
cleared with no misses; 2★ = at most 1 miss; 1★ = cleared; Flawless crown = all Perfect**) and `LevelCatalog.swift`;
nobody else touches those two.

| Owner | Items |
|---|---|
| Core (`Brim/Core/*` except `Rules.swift` stars + `LevelCatalog.swift`; CoreTests) | P1-3: a **start hold** (`func setStartHold(_ on: Bool)` on GameSession) that freezes belts, patience and line-fade clocks exactly like `needsFlat` while an intro card is up, released by the App on dismiss or automatically on `.pourStarted`; P2s: Rush tier 3→4 overlap of a Diner glass over a riding belt glass, the stream's drink flipping mid-air at Rush belt serves, dry-jug refill dead air (≤ 1.5 s to the verdict); tests |
| Scene (`Brim/Scene/*`, SceneTests) | P1-1: a stamp rides out with its leaving glass (no safeX clamp while `.leaving`, fades at ~dt·8); Rush conveyor tier shows the belt queue (read upcoming glasses from the snapshot if available, else the App sets `upcomingOrders`); cache backdrop textures per venue so a tier change doesn't re-render ~23 MB on the main thread; hourglass posts within Core's slot contract |
| Feel (`Brim/Input/*`, `Brim/Feedback/*`, tests) | conveyor bell only for a glass that actually rode a belt (e.g. it was moving when served), not at the tier 2→3 change |
| App (`Brim/App/*`, `Brim/UI/*`, `Brim/Persistence/*`, AppTests, ci/scenarios.txt) | P1-2: results chase line for the new star rule ("3★ needs every glass a hit — you had N misses") + its test; P1-3 wiring: `setStartHold(true)` while an intro card shows, false on dismiss; intro card flicker on the Duo gate; "Use touch instead" remembered for the session (until app relaunch or a hinge pour); TestFlight veterans: skip a venue's intro card if they already have stars there; Rush: set `scene.upcomingOrders` if Scene needs it; re-shoot scenario 26 at a moment after the old glass has left |
