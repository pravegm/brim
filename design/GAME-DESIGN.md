# Brim — game design bible (v1)

*Working title **Brim** ("fill it to the brim"). Owner: the founder (Claude). Written 25 Oct 2026. This is the single source of truth for what the game is. Research behind it: `research/00–03`.*

## 1. The one-liner

**Your iPhone Duo is the jug.** Lay it open and flat, fold running side to side. The top half holds a jug of drink; lift the top half off the table and the jug tips, pouring a real stream across the fold into a glass waiting on the flat half. Stop exactly on the line.

Paid, one time (£1.99 / $1.99 tier), no ads, no in-app purchases, no data collected. Rated 4+ (every drink is non-alcoholic).

## 2. Pillars (every decision is judged against these)

1. **The fold is the jug.** On a Duo the only control is the hinge. The glass stays still on the table while only the jug half moves; no normal phone can do that. A first-time player understands it in 3 seconds with one line of text: *"Lift the top half to pour."*
2. **Physically true.** The liquid surface in the jug stays level, so a full jug pours at a slight tip and a nearly empty one needs a steep tip, exactly like real life. The stream takes time to fall, so you must stop *before* the line. The glass sings: the pour pitch rises as it fills (real "filling vessel" acoustics), so experts pour by ear.
3. **Juice on everything.** Glug haptics, a rising pitch, a wobbling surface, foam that climbs and settles, a bright *ting* + sparkle ring on Perfect, a coaster thump as the glass slides away, a rising musical note for every Perfect in a streak.
4. **One more go.** Runs are 60–120 s. Precision + push-your-luck ("just a drop more…") + a Perfect streak multiplier + stars + a daily pour everyone shares.
5. **Kind to the phone and the hand.** Play lives between 175° and ~95°, mostly slow holds. Never reward slamming or flapping. Never require closing the phone.

## 3. The pose and the screen

- **Seated (tabletop) pose, portrait canvas** (inner display ~669 × 951 pt, crease band ~40 pt across the middle). The bottom half lies on the table. **Rest pose = flat (180°)**; lifting the top half toward upright (90°) tips the jug, like lifting the far edge of a tray (round 2 decision, REVIEW-1 P0-3). Each run starts with a "Lay it flat to start" gate.
- **Top half = the back bar.** Tiled wall, shelf, the jug held near the crease, its spout just above the fold.
- **Bottom half = the counter.** The glass stands on a coaster under the spout; a conveyor/counter slides glasses in from the left and out to the right.
- **The stream crosses the fold.** This is the magic frame of the whole game: liquid leaves a spout on one physical surface and lands in a glass on the other.
- **Book pose / landscape canvas** (crease vertical): show a friendly full-screen card "Turn me so the fold runs side to side, then lay me flat" with an animated phone illustration; the game pauses. (The inner display ignores orientation locks, so this must exist.)
- **Closed / cover display:** a calm card: today's daily status, best Rush score, "Open me to pour".
- **Non-folding iPhones (fallback):** same scene in a portrait screen. Control = drag anywhere: drag **up** to tip the jug, release and it eases back upright. A small "Made for iPhone Duo: on Duo, the fold is the jug" note in Settings/About. This keeps the app useful (and reviewable) on every iPhone, but every design judgement is made on the Duo frame first.

## 4. Controls (hinge → jug)

- `θ` = hinge angle (180° flat). `tilt = clamp(180° − θ, 0…90°)`.
- **Dead zone:** tilt < 6° (θ > 174°) = jug fully upright, nothing pours (a phone lying flat never dribbles).
- Jug rotation shown on screen `φ = 0° + 1.55 × (tilt − 6°)` for tilt ≥ 6° (so a lid tilt of 90° tips the jug ~130°).
- **Flow is computed from geometry, not from the angle directly**: the jug is a 2D polygon, its liquid is the area below a horizontal line through it, and flow ∝ (height of surface above the spout lip)^1.5 (a weir). So a full jug pours at small tilt, an empty one needs a big tip, and flow ramps smoothly.
- Input is smoothed with the Squish-proven tracker: predict between 25–30 Hz hinge samples, One-Euro filter (minCutoff 2.0, β 0.12). Never use `status == .closed` for anything in play.

## 5. The pour (the satisfying core)

- **Stream:** a continuous ribbon from the spout, width ∝ √flow, falling ballistically (~0.35–0.5 s from spout to glass), plus droplets at the start/end and a splash crown where it hits the surface. When you stop, the tail of the stream still lands: the skill is anticipation.
- **Glass:** profile-defined (width as a function of height), so level vs volume is non-linear for flutes, bowls, mugs, cones. Surface is a spring-mass wave (wobbles on impact, sloshes on arrival/departure). Glossy glass with rim highlight and refraction-ish darker edges.
- **Fill line:** a glowing dashed line with a small tick tab. The **Perfect band** shows as a faint glow around the line while pouring.
- **Liquid personalities** (data, not code):
  - *Water / lemonade / juice* — the basics.
  - *Soda* — **foam**: fast pours create a head that rises above the liquid then settles (~1.5 s). Foam counts toward the visible top and can overflow.
  - *Milkshake / honey / syrup* — **viscosity lag**: flow responds slowly (τ 0.4–0.8 s); it keeps coming after you stop.
  - *Bubble tea (later)* — pearls first, then tea (two lines).
  - *Sand (secret unlock)* — nothing flows until ~30° of jug tip, then a rush (angle of repose).
- **Judging** (when the glass is served): `err = (top − line) / capacity`.
  - **Perfect** |err| ≤ 2.5% → ting, sparkle ring, streak +1.
  - **Great** ≤ 6%; **Good** ≤ 12% (under or over but below the brim).
  - **Short** (under by more) — sad "hmm" from the customer, streak resets, and in shifts and the Daily it is a strike (the customer got short-changed); in Rush only spills are strikes. (Founder decision, round 1; confirmed after REVIEW-3.)
  - **Spill** (any liquid over the brim) — overflow drips down the glass, puddle on the counter, a strike.
- **Serving:** a glass is served when the jug has been upright (no flow) and the stream has fully landed for 0.6 s **after** some liquid went in, or when its patience timer runs out. In conveyor levels it's served when it leaves the spout zone.

## 6. Modes

1. **Shifts (campaign).** Venues of 8 shifts each; each shift is 5–8 glasses, earns 1–3 stars (3★ = no misses, 2★ = one miss, 1★ = cleared; a Flawless crown for all Perfect: BALANCE.md §9). Stars unlock the next venue.
   | Venue | Teaches |
   |---|---|
   | 1. **Lemonade Stand** | Basics: water, lemonade, orange juice; straight tumblers → highballs → a flute. Jug empties across the shift so you must tip further. |
   | 2. **Soda Fountain** | Foam: cola, root beer, cream soda; "pour slow, then top up". |
   | 3. **Milkshake Diner** | Viscosity: shakes, honey, maple syrup; stop early. |
   | 4. **The Conveyor** | Moving glasses: they slide under the spout and keep going; fill inside the window. |
   | 5. **Potion Shop** | Precision: tiny vials, beakers with mL lines, lines that fade after 1 s. |
   | Secret: **Sand Bar** | Hourglasses and sand (repose threshold). Unlocked by 3-starring everything. |
2. **Rush (endless).** One big shared jug. Glasses keep coming, mixed liquids, speed tiers every 8 glasses. Perfect refills the jug +6% and grows the multiplier (×1→×2→×3→×5); Spills and Shorts break the streak; the run ends after **3 spills** or when the jug runs dry. Local best + Game Center leaderboard.
3. **Daily Pour.** A seeded 10-glass run, the same for everyone that day, one scored attempt (practice afterwards doesn't count). Leaderboard. A shareable result card (e.g. `Brim · Daily #12 · 🟨🟩🟩⭐️⭐️🟩🟥⭐️🟩🟩 · 1,840`).

## 7. Feedback spec

| Moment | Sound | Haptic | Visual |
|---|---|---|---|
| Jug starts to tip | soft glass knock | light tick | jug rotates, liquid inside sloshes level |
| Pouring | filtered rush + glugs whose resonant pitch rises as the glass fills (Helmholtz: f ∝ 1/air-column) | continuous, intensity ∝ flow, sharpness ∝ fill; transient on each glug | ribbon stream, splash crown, surface ripples, bubbles in fizzy drinks |
| Approaching the line | — | — | line glows brighter inside the Perfect band |
| Perfect | bright glass *ting*; streak notes climb a pentatonic scale | crisp double tap | sparkle ring + "PERFECT" stamp + streak counter pop |
| Great / Good | softer ting | single tap | small label |
| Short | low "hmm" | soft thud | glass looks sad (level line pulses) |
| Spill | splash + drip | heavy wobbly buzz | overflow sheets down the glass, puddle |
| Serve | coaster slide + clink | coaster thump | glass slides right, next slides in |
| New best / 3 stars | little fanfare | celebratory pattern | confetti of droplets |

All sound is synthesized at runtime (no licensed assets needed). Respect the ring/silent switch? **No**: games use `.playback`-style ambient-with-mix; Squish learned that a silent switch muting everything reads as "no sound". Use `.ambient` only if the user turns on "Respect silent mode" in Settings (default off → `.playback` with `mixWithOthers`).

## 8. Look

- Warm, bright, modern flat illustration with soft gradients. Not pixel art, not skeuomorphic.
- Palette: cream wall `#FFF4E2`, mint tiles `#BFE8D8`, counter terracotta/wood `#D9825B`, ink `#2B2233`, accent "brim gold" `#FFC23D`, Perfect cyan `#3FD0FF`.
- Liquids are saturated with a lighter top band and a darker bottom; each has a signature colour.
- Typography: SF Pro Rounded, heavy for numbers.
- Motion: everything eases (spring), nothing teleports. Respect Reduce Motion (no screen shake, fewer particles).

## 9. Meta, retention, respect

- Stars, venues, a "Glass Cabinet" of glassware unlocked by milestones (cosmetic glass skins in Rush).
- Game Center: leaderboards (Rush best, Daily), ~10 achievements (first Perfect, 10-streak, pour 100 L lifetime, every venue, secret Sand Bar…).
- Lifetime stats: litres poured, Perfects, best streak.
- No timers that nag, no notifications, no data collection, no accounts.

## 10. Onboarding (no tutorial screens)

1. First launch on Duo in tabletop: the jug, one glass, one line, and the hint *"Lay it flat, then lift the top half to pour."* with a small animated arrow on the top half.
2. When the stream reaches 60% of the line and the player is still pouring: *"Lay it back to stop."*
3. On the first serve: the result + *"The stream keeps falling — stop just before the line."*
4. Then shift 1 continues. Hints never repeat once learned.

## 11. Success bar for launch

- A design-critic agent scores the Duo tabletop frames and the app ≥ 8.5/10, with no open P0/P1.
- CI green: all unit tests, the Duo simulator hinge pass captures a pour in progress across the fold, a Perfect, a Spill and the menus.
- Store kit ready: name/subtitle/keywords/description, screenshots (Duo + 6.9" + 6.1"), privacy (no data), review notes, support/privacy pages, founder runbook.
