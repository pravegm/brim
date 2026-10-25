# Round 5 brief (founder, overnight 26 Oct)

Input: `design/QA-2.md` (a suspected P0 and 4 P1s, all things a player on a REAL Duo hits in the first hour). TestFlight
1.0 (2) is with the founder for the morning; tonight's goal is build 1.0 (3) with these fixed. Every QA-2 P0/P1 is
mandatory; fix the P2s in your files that are low-risk. CI must stay green.

## Founder decisions
1. **Flat gate opens at hinge ≥ 168°** (lid tilt ≤ 12°), not 174°. The no-pour dead zone stays 6° of lid tilt (a phone
   lying flat still never dribbles; the jug angle mapping is unchanged). After 6 s stuck on the gate, the card offers
   "Use touch instead". (QA-2 suspected P0.)
2. **Lifting is not closing.** Fast hinge motion only counts as "closing the phone" below 120°; the gate re-locks only
   below 78° (decision from ROUND-3 stays: autopause below 70°). A quick tip at 150°→110° must pour, never re-lock. (P1-1)
3. **Jug refills happen between glasses**, never mid-pour: if the jug runs dry mid-glass, the stream stops (the player
   sees an empty jug, a soft "glug-out" cue), and the swap happens once the glass is served or the jug is tipped back
   below the pour threshold for 0.4 s. (P1-2)
4. **New verdict `over`** (contract change, done): past the Good band but no liquid over the rim → stamp "OVER", miss +
   strike, streak resets, no spill FX/puddle/shake. **`spill` only when liquid actually crossed the rim.** Foamy drinks are
   judged when the head has settled (cap 3 s), so pouring the liquid to the line and letting the foam settle is fair. (P1-3)
5. **Venue achievements fire on clearing every shift of the venue**, as `docs/appstore/achievements.md` says. (P1-4)

## Ownership
| Owner | Files | Items |
|---|---|---|
| Core | `Brim/Core/*` except `LevelCatalog.swift` (the balance engineer owns it tonight), Core tests | decisions 1 (gate threshold in GameSession/Rules: add a separate `Rules.flatGateTilt = 12`, keep `deadZone`), 3, 4 (Rules.judge, foam settle timing, Rules.points for `.over` = 0), QA-2 P2s in Core (fading lines frozen behind the gate, conveyor verdict waits for liquid already inside the glass, belt still during intro, Rush idle → ends after 20 s of no pouring with a glass waiting? *no*: keep Rush endless but patience timers already end it — verify and leave a note) |
| Feel | `Brim/Input/*`, `Brim/Feedback/*`, their tests | decision 2 + tests (150°→110° at 400°/s pours and never re-locks; 120°→20° at 400°/s cuts); `.over` sound/haptic (a soft "hmm" like short, distinct from spill); dry-jug "glug-out" cue; autopilot handles `.over` |
| Scene | `Brim/Scene/*`, SceneTests | `.over` stamp ("OVER", warm amber, no FX); spill FX only on `overflowStarted` / real `.spill`; streak pop copy "7 IN A ROW" (QA-2 P2: "×7 STREAK" clashes with the HUD multiplier); empty-jug look when dry |
| App | `Brim/App/*`, `Brim/UI/*`, `Brim/Persistence/*`, AppTests, `docs/appstore/*` copy | decision 1's "Use touch instead" after 6 s on the gate; decision 5; `.over` in recap/share (🟧 for short, 🟨 for over? pick clear emoji), results copy; QA-2 copy P2s ("Last call!" → non-bar phrase, "New glasses tomorrow" → truthful UTC wording, "ring switch" → "silent mode"); Daily: quitting during glass 1 must not give a free retry (file the attempt once the first glass ARRIVES, not when served); Rush quit records the score; Home-gesture edge for drags (defer system gestures on the bottom edge in play) |
| Balance | `Brim/Core/LevelCatalog.swift`, `BrimTests/BalanceTests.swift`, `design/BALANCE.md` | (already running) |
