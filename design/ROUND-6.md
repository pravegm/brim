# Round 6 brief (founder, overnight): the late game

Input: `design/REVIEW-5.md` (late game ≈ 7.0 vs 8.7 for the first hour: special mechanics untaught and unsignalled,
nothing to chase after 3★). Everyone reads REVIEW-5 in full. Round 5 (QA-2 fixes) is landing first; don't regress it.
Contract additions (done, all with defaults): `JugState.reposeProgress`, `GameSnapshot.rushTier`, `GameSnapshot.venue`.

## Founder decisions
1. **Teach every new mechanic once**: a one-time venue intro card on the first shift of each venue (one line + a tiny
   illustration), and a shift banner during the intro phase ("Shift 6 · Slow Pour, Fast Belt").
2. **Rush travels**: tier 1 Lemonade Stand, 2 Soda Fountain, 3 Conveyor (real belt), 4 Milkshake Diner, 5 Potion Shop,
   6+ cycles, all with the dusk look. A tier banner ("TIER 3 · BELTS!") + rising chord on each change.
3. **Signal the special mechanics**: Conveyor pour zone on the belt and the line tab draining as the glass passes +
   the next glasses visible on the belt; Potion: a faint ghost tick of the line remains after it fades, potions shimmer
   magically, prefilled vials visibly distinct; Sand: grains trickle at the lip and a rising rustle + light ticks as
   `reposeProgress` → 1, sand heaps (cone) instead of sloshing, a real sandy identity and an **hourglass** glass.
4. **Something to chase after 3★**: a **Flawless crown** per shift (every glass Perfect), shown on Venues and results;
   results say what 3★ needs when you got fewer.
5. **Daily ceremony**: the card leads with the day streak and a 7-day dot strip; the share text is previewed.
6. Cream soda must not read as beer (colour/foam change).

## Ownership
| Owner | Items |
|---|---|
| Core (`Brim/Core/*` except LevelCatalog) | `reposeProgress`; `rushTier` + `venue` in the snapshot (Rush: one venue per tier as in decision 2, using that venue's liquids/glasses and belts on the Conveyor tier; shifts report their venue); hourglass `GlassShape` (id `hourglass`, style — reuse `.jar` if adding a GlassStyle case would break exhaustive switches elsewhere; prefer adding the shape only); cream soda colours; tests |
| Scene | decision 3 visuals, Rush venue-per-tier looks (read `snapshot.venue`, fall back to `venue` property), sandy Sand Bar identity + less face-like scoop, conveyor bell "ding" visual on leave, potion magic shimmer, potion prefill look |
| Feel | sand rustle + ticks from `reposeProgress`; tier-up chord (on `rushTier` increase); Rush low-jug warning (fill < 20 %: gentle heartbeat glug, once per dip); conveyor leave "ding" |
| App | decisions 1, 4, 5; tier banner (decision 2) in the HUD layer; HUD score contrast on dark venues (Potion indigo); results "3★ needs …" line; Flawless crowns in ProgressStore (+ tests) and Venues/results UI |
| Balance (after its current pass) | use the hourglass in the Sand Bar; themed Dailies only behind a fixed future day number |
