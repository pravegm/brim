# Round 9 brief (founder, pre-dawn): last polish before TestFlight 1.0 (4)

Inputs: `design/REVIEW-7.md` (overall 9.0; three small P1s), `design/QA-4.md` (no P0; one P1). Small, safe round: no
new features, no contract changes. CI must stay green.

| Owner | Items |
|---|---|
| Scene (`Brim/Scene/*`, SceneTests) | QA-4 P1-1: a stamp placed beside a tall glass must never sit over the waiting glass (pass the waiting glass's x-range into `GlassFrame`; pick the side that avoids it; if both are blocked, raise the stamp so its bottom clears the waiting rim by 10 pt within the crease limit) + test; REVIEW-7 P1-1: sand-slide telegraph visible (bigger outlined grains, a scoop shiver as `reposeProgress` → 1); conveyor jug badge no longer reads as clock hands; QA-4 P2: avoid main-thread backdrop pre-paint stutter mid-pour (paint between glasses, or spread across frames) |
| App (`Brim/App/*`, `Brim/UI/*`, `Brim/Persistence/*`, AppTests, `ci/scenarios.txt`, `ci/duo.sh` additively) | REVIEW-7 P1-2: `screen=cabinet` demo key + scenarios 34–36 (cabinet locked, partly unlocked, a vessel chosen in Rush) and a Duo UI frame in `ci/duo.sh`'s ui pass; P1-3: the cabinet must not spoil the secret Sand Bar (its vessel shows as a locked "???" silhouette until the Sand Bar is unlocked); star wording by quality (an all-Good 3★ shift is "Clean shift", "Great shift!" needs ≥ 50 % Perfect, "Flawless!" for a crown) + tests; scenario 33 low-jug must actually freeze (fix the demo path); Daily share-preview wrap; reset progress clears the chosen vessel immediately; no crown icon on the 3★ line; struck-out Daily gets ghost glasses |
