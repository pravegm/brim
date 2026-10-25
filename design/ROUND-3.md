# Round 3 brief (founder)

Input: `design/REVIEW-2.md` (7.5/10, launch call "close"). Target: ≥ 8.5 and a "yes". Everyone reads REVIEW-2 in full;
frames are in `design/frames/duo2/` (real Duo sim) and `design/frames/r2/` (iPhone).

## Founder decisions

1. **Closing never pours (P0).** Three layers:
   - *Input* (`HingeTiltSource`): output lid tilt 0 (jug upright, no pour) when the hinge is below 78° (re-enable only
     above 88°, hysteresis) or when it is closing faster than 160°/s (hold the cut for 0.35 s). Between 90° and 78°
     clamp to 90° of lid tilt. Expose `var isClosing: Bool` and `var lastAngle`.
   - *App*: auto-pause the run when the hinge goes below 70° (the inner display is about to go dark); every resume —
     user or automatic, demo included — calls `session.requireFlat()`, so play resumes only after laying it flat.
     The glass under the spout is NOT judged while paused (no step calls).
   - *Core*: nothing new is required, but make sure a run paused mid-pour resumes cleanly (stream in flight lands,
     no judgement until the player pours again and stops, patience frozen while `needsFlat`).
   - *CI proof*: `ci/duo.sh` gets a scenario that closes the phone mid-pour and reopens it (the founder adds it); the
     app must log `BRIM-T autopause` and `BRIM-T resume needsFlat=1` and no `served` judgement between them.
2. **Centre the pour.** Glass stop at world x ≤ 372 (was ~418), jug body never left of x 118 at any angle, still
   inside the HUD rules. The next glass waits visibly on the counter at x ≈ 165 (slides into place after the serve).
3. **Nothing on the fold.** No text, stamp, pop, card or button may cross the crease band (world y 456…496; on a
   landscape/book canvas the fold is the vertical centre band). The jug may cross only while tipping, never at rest.
4. **Puddles belong to their glass**: they grow for that glass's spill, then dry/fade within ~1.5 s after it leaves.

## Assignments

### Core — `Brim/Core/*`, Core/Level tests
Decision 2 (move the jug rig and stop x; keep all round-2 guarantees: landing ±8 pt, lip heights, HUD band, visible
x 130…540 for the glass under the spout), next-glass waiting slot, decision 4 puddle lifetime (keep `[CGPoint]`
encoding; drop a glass's puddle points ~1.5 s after it leaves and expose `puddleAge` if you need — no contract change;
Scene may fade by reading `puddles` count changes), decision 1 Core part. Re-tune if the move changes timing.
Add tests: pausing mid-pour (stop stepping, then `requireFlat`, tilt 0 for 2 s) produces no judgement.

### Scene — `Brim/Scene/*`, SceneTests
REVIEW-2 items: decision 3 (streak pop and stamps placed above the glass but below the crease, or above the jug —
never on the band); **fat, opaque stream** (≥ 20 pt at a typical pour, a darker edge + bright core like the icon,
saturated water `#7CC8F2`-ish, shakes 1.6×, liquid visible in the spout channel to the lip); draw the jug **lid**
properly (Core's `JugGeometry.lidIndices` 15…18 close the mouth — draw a lid with a knob, not an open white oval);
**signature vessels** — draw a different exterior around the same interior outline per venue: Soda = dispenser jug
(red + chrome bands, flat lid), Diner = brushed steel shake tin (no handle decal, steel), Potion = flask-like glass
with cork, Sand = scoop; **Diner contrast** (counter not pink: mint formica or checker); puddles per decision 4
(fade out when their points disappear); next-glass waiting slot drawn nicely (a glass on its own coaster); iPhone:
shelf props must not sit under the HUD's score/pause (top-left/top-right of the visible rect).

### Feel — `Brim/Input/*`, `Brim/Feedback/*`, Input/Feedback tests
Decision 1 Input part + tests (closing sweep 150°→20° at 300°/s produces tilt 0 within one sample; slow close below 78°
gives 0; reopen needs > 88°). Hinge noise: REVIEW-2 risk (±5° hinge → ±8° jug) — add a gentle hold stabiliser (when
the angle velocity is low, filter harder; One-Euro minCutoff lower at rest), without adding lag on deliberate moves;
test it. Autopilot unchanged except new layout. Audio: a soft "pause" whoosh on autopause, nothing on resume until
armed.

### App — `Brim/App/*`, `Brim/UI/*`, `Brim/Persistence/*`, AppTests
Decision 1 App part (autopause below 70°, `BRIM-T autopause`, resume → `requireFlat()` always, `BRIM-T resume
needsFlat=1`; a calm "Open me up and lay me flat" card when paused by closing); Duo Home: buttons must not cover the
glass (it now stops at x ≤ 372 world → put the left column at the far left and the right column at the far right,
narrower, or a single bottom row on the Duo too); **Duo results** use the flat half (the recap glasses big, at their
levels, on the counter; balanced composition); copy bugs: "So close"/"NEW BEST" on a failed first run; truncations
("7 se…" in the Rush HUD, "Turn the scre…" on the phone stand-up card); book-pose card content must not cross the
vertical fold (two columns, one per half); nothing of yours on the crease band (decision 3). Demo: the `duo.sh` close
scenario needs `-brimDemo "mode=shift:1-2;duo;orient=portrait"` to behave exactly like a real run.
