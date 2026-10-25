# Brim: Game Center leaderboards and achievements (v1.0)

*Written 25 Oct 2026 from bible §6 and §9. IDs are the ones the brief fixed; **IDs are permanent once created in App Store Connect**, so the App engineer must use exactly these strings. All work identically with the hinge (Duo) and with drag (other iPhones). Nothing rewards folding speed or the number of folds (App Review 2.4.2).*

## Apple's limits (checked against Squish's sourced notes)
- ≤ 100 points per achievement, ≤ 1,000 points per app, ≤ 100 achievements.
- IDs ≤ 100 characters, letters, digits, `.` and `_`; permanent.
- Each achievement needs a **1024 × 1024** image (PNG or JPEG, RGB, no transparency, ≥ 72 dpi). Leaderboard images are optional.
- Achievements and leaderboards only go live attached to a version that includes them (runbook §4.6).

## Leaderboards (2)

| | `brim.rush.best` | `brim.daily.score` |
|---|---|---|
| Type | **Classic** (all-time) | **Recurring** |
| Reference name | `Rush best` | `Daily Pour` |
| Display name (en-GB and en-US) | `Rush` | `Daily Pour` |
| Score format | Integer | Integer |
| Format suffix (singular / plural) | ` point` / ` points` | ` point` / ` points` |
| Sort order | High to Low | High to Low |
| Score submission | Best score | Best score (the app submits only the day's one scored attempt) |
| Score range (optional) | 0 – 10,000,000 | 0 – 1,000,000 |
| Recurring settings | — | Start **Sun 1 Nov 2026, 00:00 UTC**; duration **1 day**; repeats every **1 day** |
| What the app submits | final Rush score | the Daily Pour score from the first completed scored run that day |

**Why the Daily start is 1 Nov, not launch day:** TestFlight testers (Game Center sandbox) can then see the board before launch. It costs nothing.

**One engineering point (must be settled before 1.0):** a recurring leaderboard resets at the same UTC moment for everyone, but the design keys the Daily seed to the player's **local** date (`LevelCatalog.dayNumber(for:)` "in the user's calendar"). That would mix different days' glasses on one board around midnight. Recommendation: key the Daily Pour to the **UTC date**, so it changes at 00:00 UTC (midnight in the UK in winter, 4 pm Pacific). See `DECISIONS.md` #16.

## Achievements (10, 700 points)

| # | Achievement ID | Title (en-GB / en-US) | Pre-earned description | Earned description | Points | Hidden | Trigger (for the App engineer) |
|---|---|---|---|---|---|---|---|
| 1 | `brim.first.perfect` | First Perfect | Pour your first Perfect. | Right on the line. Ting! | 25 | No | First glass judged `.perfect`, any mode |
| 2 | `brim.streak.10` | Steady Hand | Pour 10 Perfects in a row. | Ten in a row. The glasses are getting nervous. | 50 | No | `streak` reaches 10 within one run (Rush, Daily or a shift). Shifts have 5–8 glasses, so in practice Rush or a flawless Daily Pour |
| 3 | `brim.streak.25` | Not a Drop Out of Place | Pour 25 Perfects in a row. | Twenty-five. Not a drop out of place. | 100 | No | `streak` reaches 25 within one run (Rush only, in practice) |
| 4 | `brim.litres.10` | Ten Litres / Ten Liters | Pour 10 litres in total. / Pour 10 liters in total. | Ten litres, give or take a drop. / Ten liters, give or take a drop. | 75 | No | Lifetime "litres poured" stat ≥ 10, all modes, the same number the Stats screen shows. Suggested scale: a standard tumbler at its line = 250 mL, so ≈ 40 glasses (about 5 shifts). Report `percentComplete` as litres × 10 |
| 5 | `brim.venue.soda` | Head for Foam | Clear every shift at the Soda Fountain. | Foam tamed. Slow, then top up. | 50 | No | Every Soda Fountain shift has `cleared == true` (≥ 1 star) |
| 6 | `brim.venue.diner` | Thick and Slow | Clear every shift at the Milkshake Diner. | You stopped early. It paid off. | 50 | No | Every Milkshake Diner shift cleared |
| 7 | `brim.venue.conveyor` | Moving Target | Clear every shift on The Conveyor. | Nothing got past you. | 75 | No | Every Conveyor shift cleared |
| 8 | `brim.venue.potions` | Steady Alchemist | Clear every shift at the Potion Shop. | Measured to the drop. | 75 | No | Every Potion Shop shift cleared |
| 9 | `brim.allstars` | All Stars | Earn 3 stars on every shift in all five venues. | Every shift, three stars. Something just opened behind the counter. | 100 | No | Every shift in the five main venues has 3 stars (this is also the Sand Bar unlock) |
| 10 | `brim.sandbar` | Grain by Grain | There's one more venue. Keep pouring. | The Sand Bar, cleared. Every last grain. | 100 | **Yes** | Every Sand Bar shift cleared |
| | | | | | **700** | | |

Points: 25 + 50 + 100 + 75 + 50 + 50 + 75 + 75 + 100 + 100 = **700**. **300 points stay in reserve** for later updates (for example a holiday menu or Bubble Tea venue), well under the 1,000 cap.

**Achievable more than once:** No, for all ten. **No Lemonade Stand achievement:** it's the tutorial venue, and `brim.first.perfect` covers the first win.

**Why only the Sand Bar is hidden:** it's the secret venue; its pre-earned text teases without naming it, and stays safe if hidden achievements are ever shown greyed out. All Stars is visible on purpose: it tells players a reward exists for 3-starring everything.

## The ladder (does it feel right?)
- First Perfect: first session, usually within 5 glasses.
- Ten Litres, Head for Foam, Thick and Slow: the first few sessions.
- Steady Hand: a good Rush run or one flawless Daily Pour.
- Moving Target, Steady Alchemist: mid-game.
- All Stars, Not a Drop Out of Place, Grain by Grain: the long tail.

## Copy rules
- Titles short (Game Center truncates long ones). Count each title in the App Store Connect form; Apple's help doesn't state a field limit.
- Nothing mentions speed, slamming, flapping or alcohol. No "bar" except the venue's own name, which appears only after it's earned.
- en-US differs only in the litres line (#4). Everything else is identical: enter it once per locale.

## Images (needed before you can save each achievement)
Ten 1024 × 1024 PNGs, one per achievement, opaque (no alpha channel), in the app icon's style: a cream → peach background with the fold seam, a medallion whose ring shows the tier (teal for 25–50 points, deep teal with gold studs for 75, gold for 100) and one motif: a glass filled to a glowing line (First Perfect), a flame with 10 / 25 (streaks), a drop with 10 L (litres), a soda dispenser, a shake tin, conveyor rollers, a potion flask, three stars (All Stars), an hourglass (Sand Bar). No words, only short numerals.

**Where they come from:** the app draws them itself (`Brim/UI/AchievementArt.swift`, `AchievementBadge(id:)`). Every CI run (`.github/workflows/ci.yml`) plays the scenario `15-badges` (`ci/scenarios.txt`, demo key `screen=badges` in `Brim/App/DemoMode.swift`), which renders all ten into the app's Documents/badges/; `ci/screenshots.sh` copies them into the **`screenshots` artifact, folder `screenshots/badges/`**, one file per achievement named by its ID (e.g. `brim.first.perfect.png`). Download that artifact from the latest green run and upload each file to its achievement in App Store Connect. The app log line `BRIM-T badges done 10` (`logs/15-badges.txt` in the same artifact) confirms all ten were written.

## Implementation checklist (App engineer)
- [ ] IDs in code match this table exactly (one constant per ID).
- [ ] Authenticate once at launch; if the player declines, never show the sign-in sheet again uninvited.
- [ ] Progress reported with `percentComplete` for #2, #3 (best streak / target), #4 (litres), #5–#10 (cleared shifts / total).
- [ ] Banners never appear mid-pour: queue them until the glass is served or the run ends.
- [ ] Daily: submit only the first scored run of the (UTC) day.
- [ ] Drag control can earn every achievement.

## Sources
- App Store Connect Help, *Achievements* (limits, hidden, images): https://developer.apple.com/help/app-store-connect/reference/game-center/achievements
- App Store Connect Help, *Leaderboards* (classic and recurring; start date, duration, restart): https://developer.apple.com/help/app-store-connect/reference/game-center/leaderboards
- Apple Developer, *Rewarding players with achievements*: https://developer.apple.com/documentation/gamekit/rewarding-players-with-achievements
- Squish's Game Center plan (format mirrored): `C:\Users\59527\Squish\docs\appstore\achievements.md`
