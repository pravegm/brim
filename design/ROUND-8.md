# Round 8 brief (founder, overnight): REVIEW-6 top 6

Input: `design/REVIEW-6.md` (overall 8.8, late game 8.2). TestFlight 1.0 (3) goes out from round 7 first; this round
targets 1.0 (4) for the founder's morning. Everyone reads REVIEW-6 §3–§4.

Frame 20 finding (founder, from the CI log): the "perfect" autopilot struck out in Rush's Fizz tier with a streak of 0.
The simulated human experts average 53 Rush glasses, so the wall is mostly the bot vs foam. Still: cap the tier-2 foam
lines and make the bot competent at foam (store frames and the menu attract loop use it).

| Owner | Items |
|---|---|
| Balance (`LevelCatalog.swift`, `BalanceTests.swift`, `BALANCE.md`; Rush menu tunables in `GameSession`/`CoreTuning` if needed) | #1 Rush Fizz tier: foam lines ≤ 0.70, bias to cream soda, +2 s patience; target ≥ 70 % of casual runs reaching tier 3. Re-check the full curve with the new star rule. |
| Core (`Brim/Core/*` except LevelCatalog; CoreTests) | Rush belt queue: peek the next plans while a belt glass is on the counter so `upcomingOrder(s)` is non-nil in the belt tier (expose `upcomingOrders: [GlassOrder]` up to 2); any Core part of #1 the balance owner asks for |
| Feel (`Brim/Input/*`, `Brim/Feedback/*`, tests) | Autopilot competent at foam: for foamy drinks stop on the settled-head projection with a gentler pour, so its Rush Fizz tier and soda store frames are genuine Perfects |
| Scene (`Brim/Scene/*`, SceneTests) | #5 stamp gap on tall glasses (PERFECT clears the rim); Glass Cabinet lite (#6) Scene part: a vessel override (`var vesselOverride: VenueID?` drawing that venue's jug in Rush/Practice) |
| App (`Brim/App/*`, `Brim/UI/*`, `Brim/Persistence/*`, AppTests, `ci/scenarios.txt`) | #2 crown chase (stats line → crown line, no "best streak 0", best Perfects per shift on Venues bubbles); #3 evidence frames (sand slide mid-telegraph, potion line faded with ghost tick, hourglass glass, Rush low-jug, re-shoot 08/20/28); #4 failed card last mile (ghost glasses for unserved, no orphan "0", dedupe stats); #5 intro card on iPhone (banner after the card, card low and compact, jug visible); #6 Glass Cabinet lite: unlock venue vessels by crowns (e.g. 3 crowns → soda dispenser, 6 → shake tin, 10 → potion flask, 14 → copper scoop), a small Cabinet sheet from Home to pick the Rush/Practice vessel, persisted tolerantly; wire `upcomingOrders` from Core |
