# 03 — Game concepts for iPhone Duo (hinge-first)

Brief: an iPhone Duo-first game that is simple, fun, addictive and satisfying. Paid, about £2 one-time. The fold has to be the controller.
Excluded: Squish, Toastie, and anything whose core verb is "close the phone onto an object" (crush, cook, clamp).

> **Note on anchoring.** These ten concepts were drafted before reading `00-founder-shortlist.md`. Two of them ended up close to the founder's list: **Pour Decisions** is near **A (Pour)**, and **Chute** is near **B (Skee-fold)**. That is independent agreement, not copying. Where the two versions differ, the differences are spelled out in the recommendation.

---

## Ground rules all ten concepts follow

- **θ** means the hinge angle. 180° is fully flat, 90° is an L shape, and 0° is shut. All active play happens between **60° and 180°**.
- **Tabletop pose:** held landscape, the crease runs horizontally, the bottom half lies flat on a table and the top half stands up like a laptop lid. The lid's tilt from horizontal is **180° − θ**: flat at 180°, vertical at 90°.
- **Book pose:** held portrait with the crease vertical and one half in each hand.
- **The game's own reading is the truth.** Every concept shows the angle the game is using on screen (a protractor, an on-screen lid, a liquid level), so players tune to that reading and the ~5° sensor error doesn't show. The raw signal goes through a 1€ (one-euro) filter, and nothing depends on a single sample. This one rule makes hinge noise mostly invisible.
- **No flapping.** No mechanic rewards motion faster than about 1 stroke per second. Most mechanics are "hold an angle" or "drift slowly".
- **The Duo magic is two objects:** one half stays still and the other moves. The best concepts below give the static half a role (a glass, a table, a river) and the moving half a different one (a bottle, a ramp, a bridge). A single-slab phone cannot do this. Tilting the whole phone moves both.
- **Touch fallback** on non-folding iPhones is a vertical drag or a slider that drives a virtual θ, plus an on-screen lid that mirrors it. It always works, and it always feels worse. That gap is the point.

---

## 1. Pour Decisions

**Hook:** The top half of your phone is the bottle. Tip it to pour, and stop exactly on the line.

**Hinge mapping (tabletop):**
- A bottle is drawn on the top half with its neck at the crease. Flat (θ = 180°) means the bottle lies on its side and nothing pours.
- Raising the lid (θ falling toward 90°) tips the neck down. Flow rate is `f(tilt, fill level)`, where tilt = 180° − θ.
- The liquid surface stays level with real gravity: it is a plane cut through the bottle shape at the current tilt. A full bottle starts pouring at about 15° of tilt. A nearly empty one needs 60–80°. This is exactly how a real bottle behaves, so the angle you need keeps changing and players have to keep adjusting.
- Opening back toward 180° stops the pour, with a short drip tail.

**30-second loop:** Glasses ride a conveyor along the flat bottom half. Each passes under the spout for 2–4 seconds and has a fill line. You raise the lid to start the stream, ease it to slow the stream, and lay it flat to stop. Scoring: within ±2% is Perfect, ±6% is Good, short is Miss, and over the brim is Spill. Spills leave a puddle on the bar and cost a strike. Three strikes and your shift is over. Between glasses you lay the lid flat while the next one slides in.

**Why it's addictive:**
- **Push your luck:** every pour invites "a bit more".
- **Mastery:** the angle-to-flow curve changes as the bottle empties, so you never fully master it.
- **Score chase:** a Perfect streak multiplies your score.
- **Collection:** drinks, glassware and bars to unlock.

**Satisfying moments:**
- The real filling-vessel sound: the pitch rises as the glass fills, so good players learn to pour by ear.
- A haptic tick on every glug.
- Foam that climbs and settles.
- A bright *ting* and a sparkle ring on a Perfect, and a coaster-thump haptic when the glass slides away.
- A Spill makes a slow overflow drip down the glass and a sad splat haptic.

**First 10 seconds:** The phone lies open and flat on the table, showing a bottle on the top half and an empty pint glass with a glowing line on the bottom. One prompt: "Lift the top half to pour." Liquid starts to trickle and the glug sound kicks in. The player lowers the lid when the liquid reaches the line, and a Perfect lands within about 8 seconds. Nothing else needs explaining.

**Risks:**
- 2D liquid can look cheap. Fix: a particle stream, plus a glass fill drawn as a rising level with a wobble shader, plus a foam layer. Do not build a real fluid sim.
- A normal iPhone can mimic this by tilting the whole phone. On the Duo the glass stays still on the table while only the bottle moves, so lean on that in marketing.
- Theme: avoid alcohol branding for an under-17s audience. Mix in milkshakes, syrup and potions.

---

## 2. Chute

**Hook:** The lid is a ramp. Set the slope, let go of the puck, and slide it onto the target across the fold.

**Hinge mapping (tabletop, viewed top-down on both surfaces):**
- Ramp steepness = lid tilt (180° − θ). It changes the puck's acceleration as it slides down the top half toward the crease. Flat (180°) means a gentle nudge; nearly upright (100°) means a rocket.
- After the crease the puck slides across the flat bottom half with friction and comes to rest.
- **The skill layer:** the hinge keeps working while the puck is still on the ramp, which takes about 1 second. Steepen to add speed or flatten to brake. This turns a power meter into continuous control.

**30-second loop:**
- Drag the puck sideways along the top edge to aim, then tap to release and ride the slope.
- The puck crosses the fold and slides toward a target drawn on the bottom half: a curling house, a shuffleboard grid or skee rings.
- Five pucks make an end. Pucks stay on the board, so later throws can knock earlier ones and promote or bump them, like curling.
- Anything that slides off the near edge is a foul.

**Why it's addictive:**
- **Score chase:** best end, best game.
- **Physics knock-ons:** you never get the same position twice.
- **"One more end":** an end takes about 30 seconds.
- **Mastery:** braking with the hinge in mid-slide.

**Satisfying moments:**
- A rumbling haptic that grows as the puck speeds up.
- A distinct *thock* plus a haptic bump as it crosses the crease.
- Stone-on-stone clacks when pucks collide.
- A slow-motion "will it stop?" final half-second with rising tension audio.
- A bullseye triggers a ring flash and a crowd murmur.

**First 10 seconds:** In tabletop pose, a puck sits at the top of the lid and a glowing target sits on the flat half. Prompt: "Tilt the lid to set the slope. Tap to let go." The first throw is almost guaranteed to reach the scoring rings, because the rings are wide and friction is forgiving.

**Risks:**
- Turn-based pacing has less flow than a real-time game.
- The front-on viewing angle onto the lid in tabletop pose can make the top half hard to read. Keep the ramp art simple and high-contrast.
- Too close to a generic "power meter" game unless the mid-slide braking is emphasised.

---

## 3. Pop-Up

**Hook:** Your phone is a pop-up book. Open and close it to raise and flatten the paper world your hero runs through.

**Hinge mapping (book pose, portrait):**
- Each paper piece has a "stand curve" tied to θ, the way real pop-ups rise when a book closes toward 90°.
- **Walls and spikes** stand at θ < 130° and lie flat at θ > 160°.
- **Ramps and springboards** are only up in the 110–150° band.
- **Bridges** are fold-out flaps that span gaps only when the book is nearly flat (> 165°).
- In 2D, a piece standing up is a sprite whose `yScale` goes from 0 to 1 with a paper-flex wobble. It reads clearly as pop-up paper.

**30-second loop:**
- The hero auto-runs left to right across a two-page spread (about 4–5 seconds per spread).
- You read what is coming and set the book's angle: open flat to lay a bridge, close a little to raise a ramp, and keep away from the "too closed" zone where walls spring up in your face.
- At the right edge the page turns with a real paper-turn animation, and a new spread appears.
- In endless mode, spreads are drawn from a growing pool. Coins are tucked under flaps that only show at certain angles.

**Why it's addictive:**
- Runner score chase (pages survived).
- Readable pattern mastery.
- Collection: stickers hidden under flaps, and new storybooks with their own art (Fairy Tale, Haunted House, Space Atlas).

**Satisfying moments:**
- The paper *fwip* of pieces standing up, with a light haptic per piece.
- A big page-turn whoosh.
- Hidden flaps revealing coins with a paper rustle.
- Death makes the whole spread fold flat with a slap and the hero becomes a pressed-flower sticker.

**First 10 seconds:** The phone opens like a book onto a storybook spread, with a little knight on the left page. Prompt: "Open the book flat to unfold the bridge." The player opens it, the bridge flops out and the knight runs across. The next spread shows a spike pit, with "Close a little to raise the ramp."

**Risks:**
- Art and level-design heavy, which is hard to fit in 2 engineering days. You need around 30 hand-made spreads to launch.
- Clarity: players have to learn which pieces respond to which angles. Colour-code them by band.
- The book pose is held in the air, which is fine for 2-minute runs.

---

## 4. Lob

**Hook:** The lid is your launcher arm. Its real angle is your shot angle.

**Hinge mapping (tabletop):**
- Launch elevation = lid tilt from horizontal (0–90°, covering θ 180° down to 90°), mirrored 1:1 by an on-screen cannon or arm drawn at the hinge.
- Hold a finger on the bottom half to charge power and release to fire. The hinge sets the angle, and touch sets power and timing.

**30-second loop:**
- Side-view arcade "basket toss" on the bottom half: lob a ball into a hoop, cup or bin at a varying distance, with wind and moving targets.
- Make it and the target moves. Miss three and the run is over.
- Bonus: bank shots off bumpers.

**Why it's addictive:** Streak-based score chase (as in Flappy or Ketchapp games), with fast restarts and readable improvement.

**Satisfying moments:**
- A *swish* with net ripple and a haptic thunk.
- A satisfying "the lid IS the arm" moment when you watch the on-screen arm match your hand.
- A combo fire trail.

**First 10 seconds:** In tabletop pose, a bin sits on the flat half. "Tilt the lid to aim. Hold and release to throw." First shot lands.

**Risks:**
- Lowest Duo-uniqueness here. The hinge is essentially an angle slider and a finger drag could do the same job.
- Competes with hundreds of toss games.

---

## 5. Pump

**Hook:** Your folded phone is a halfpipe. Pump it like a playground swing to send the skater higher and higher.

**Hinge mapping (book pose; the V cross-section is the pipe):**
- The skater rides top-down across both halves, crossing the crease at the bottom of the V.
- The pull back toward the crease is proportional to how steep the walls are (180° − θ).
- **Pumping:** steepen the V (close toward about 120°) while the skater drops toward the crease, then flatten it (toward 175°) while they climb. This adds energy, the way pumping works on a real swing or halfpipe. Mistimed pumps bleed energy.
- The pipe is wide and slow: about 2.5 seconds per side-to-side swing, so about 1 fold stroke per second at most.

**30-second loop:** Build height for 10–15 seconds. At the lip, tap to throw a trick (spin, grab, flip) while airborne. Land it or bail. Each run lasts 3 bails.

**Why it's addictive:**
- **Rhythm mastery:** the feel of being "in phase" with the swing.
- **Push your luck:** bigger air means bigger tricks but a riskier landing.
- Score chase.

**Satisfying moments:**
- The *whoosh* gets louder with speed.
- A wheel rumble haptic at the bottom.
- Floaty silence and slow-mo at peak air, then a clean landing *clack*.

**First 10 seconds:** In book pose, a skater rocks gently in the crease. "Fold a little as they drop, open as they climb." The meter rises visibly on the first correct pump.

**Risks:**
- Pumping isn't obvious to everyone, so clarity suffers.
- The most hinge strokes of any concept: about 60 per minute. That is fine for the hinge's rated life, but it looks like wear to an anxious owner.
- Update-rate jitter during the strokes.

---

## 6. Tumbler

**Hook:** Crack safes by feel. Open the phone slowly and listen and feel for the click.

**Hinge mapping (book or tabletop):**
- The hinge angle is your lock pick's position. Each lock hides 3–5 "gates" at secret angles between 70° and 175°. Gates are 8–12° wide, which is safely above the sensor error.
- As θ nears a gate, haptic and audio "grit" increase. Hold a thumb on the screen inside a gate to "set the pin" with a firm click.
- Pins must be set in order, and overshooting a gate while pressing resets the lock.

**30-second loop:** A vault with a timer. Sweep slowly, feel the grit, press, click. Finish 3 pins, the door swings open and the loot spills out. A guard alarm timer adds pressure. The heist run continues room to room.

**Why it's addictive:** Tactile mastery, a loot collection, and push-your-luck: leave now, or try the bonus safe before the alarm.

**Satisfying moments:** This is a haptics showcase:
- Rising textured buzz near a gate.
- A heavy *chunk* on set.
- A mechanical cascade when the door opens.
- Coins rain down with tiny clinks.

**First 10 seconds:** A big steel dial shows on screen. "Open the phone slowly. Feel for the click." The first gate is huge and the haptic is obvious.

**Risks:**
- Screenshots are dull: a safe.
- Haptic-led play won't come across in store video.
- Clarity: "feel" isn't instant for everyone, and plays poorly with sound off and haptics at system-low.

---

## 7. Swoop

**Hook:** Your phone is the bird. Spread its wings to soar and fold them to dive.

**Hinge mapping (book pose, held like a bird's spread wings):**
- Wing spread = θ.
- **Near 180° (open):** glide and lift. You climb, bleeding speed.
- **About 120–140° (tucked):** dive. You fall fast, gaining speed.
- Below 110° is a full tuck: maximum dive with no control.
- Energy is conserved between height and speed (Tiny Wings' core): dive into a valley or onto a thermal, then open at the right moment to turn speed into big height.
- No flapping at all. It's gliding only, and the loading screen says so ("No flapping, no flapping your phone").
- The bird is drawn top-down with its body on the crease and a wing on each half. When you fold, the on-screen wings fold too.

**30-second loop:**
- Endless flight over a scrolling world: altitude is shown by scale, shadow and parallax.
- Dive under low bridges, pick fish off the water's surface, and catch thermals (open fully inside them).
- Clear ridges by arriving with speed and opening wide.
- Sunset ends the day: distance is your score.

**Why it's addictive:**
- Tiny Wings-style momentum mastery.
- Distance score chase.
- Daily "sunset" runs.
- Collect birds: swift, owl, albatross, each with a different glide curve.

**Satisfying moments:**
- Wind whistle rising with dive speed.
- The "pop" as you open out of a dive and the world zooms out.
- Water spray on a fish snatch.
- A haptic heartbeat when you nearly clip a cliff.

**First 10 seconds:** The phone is held open with a bird spread across both halves. "Fold your wings to dive." The bird drops toward a river and a fish glints. "Open them to soar." The bird swoops up with a fish.

**Risks:**
- Holding the phone in the air in two hands for long runs gets tiring.
- Mechanically it's an altitude slider, though the energy model saves it.
- Top-down altitude can be hard to read. Shadow offset is the key cue.

---

## 8. Jib

**Hook:** The lid is a crane's boom. Lower it to reach out, raise it to pull in, and stack the swinging cargo sky-high.

**Hinge mapping (tabletop):**
- A luffing crane: boom angle = lid tilt, which sets the hook's horizontal reach over the bottom half.
- A raised boom (θ near 90°) means a short reach. A flatter boom (θ near 170°) means a long reach.
- The load swings like a pendulum under the hook, so moving the boom fast makes it swing more.
- Tap to drop.

**30-second loop:** Stack-style: blocks drop onto a tower and any overhang is sliced off, so the tower narrows as you miss. Wind gusts and odd shapes (girders, pianos, cows) add variety. Get the swing settled, line up the drop and tap. Each drop takes about 3 seconds.

**Why it's addictive:** Proven Stack and Tower Bloxx loop: height score, perfect-drop streaks, and the dread of a narrowing tower.

**Satisfying moments:**
- A heavy *thunk* with haptic and dust puff.
- Perfect drops make a chime that climbs the scale with each streak.
- The tower sways and creaks as it grows.
- A camera pull-back reveals the skyline.

**First 10 seconds:** In tabletop pose, a crane hangs a block over a foundation. "Tilt the lid to move the crane. Tap to drop." The first drop always lands.

**Risks:**
- Derivative of Stack and Tower Bloxx.
- The hinge only replaces horizontal timing.
- Moderate Duo-uniqueness: a touch drag works almost as well.

---

## 9. Bascule

**Hook:** You run a drawbridge. The lid is the bridge: raise it for ships, lower it for cars, and don't let either crash.

**Hinge mapping (tabletop):**
- The top half is the bridge leaf, mirrored 1:1 on screen in side view. The bottom half is the river and road.
- **θ ≥ 170° (flat):** cars cross.
- **About 140°:** small boats pass under, but cars can't cross.
- **About 110°:** sailboats pass.
- **≤ 95°:** tall ships pass.
- The leaf's real-world motion is the motion of the bridge.

**30-second loop:**
- Traffic queues build on both sides of the road (honking, then a rage meter).
- Boats of different mast heights sail toward the bridge at different speeds.
- Raise it just high enough, just long enough, then drop it for the cars.
- A mast strike means a crash and a strike. A car going over the raised edge means a splash and a strike.
- Survive the rush hour.

**Why it's addictive:** Traffic-management stress (Mini Motorways or Traffic Rush energy), with combos for "threading" a boat through while the queue keeps moving, and escalating rush hours.

**Satisfying moments:**
- Clanking chains and a warning bell as the leaf moves.
- The ship horn's *BWAAAMP* as it clears.
- Cars streaming across in a satisfying flood.
- A heavy *clunk* haptic when the leaf seats at flat.

**First 10 seconds:** In tabletop pose, a sailboat approaches a flat bridge. "Raise the lid to lift the bridge." The boat passes with a toot. "Now lower it, cars are waiting."

**Risks:**
- Two simultaneous queues can overload a casual player.
- Side-view art on the upright lid is seen at an angle.
- Balancing the angle bands against ~5° error: make each band at least 15° wide.

---

## 10. Lunker

**Hook:** The lid is your fishing rod. Raise it to haul, drop it to give slack, and land the monster before the line snaps.

**Hinge mapping (tabletop; the lid is the rod butt-end at the hinge):**
- Raising the lid (θ toward 90°) increases line tension. Lowering it (toward 180°) gives slack.
- Hold a thumb on the bottom half to reel.
- A tension gauge shows a green band that moves as the fish surges.
- Too much tension snaps the line. Too little for 2 seconds lets the fish throw the hook.

**30-second loop:**
- Cast: a slow lid flick-back with a generous angle window.
- Wait, then strike with a quick raise of the lid.
- Fight for 10–20 seconds: ride the tension band while reeling.
- Land the fish and get a big reveal card with weight and species.
- Each pond or sea has its own catalogue.

**Why it's addictive:**
- Collection: a fish-dex with rarities and record weights.
- Push your luck: a bigger fish means a narrower band.
- A gentle, cosy mastery loop. Fishing minigames are reliably sticky.

**Satisfying moments:**
- The reel's ratchet clicking (haptic per click).
- Line creak that rises in pitch with tension.
- A splash and a slow-mo "LUNKER!" reveal of the weight.
- The line-snap *ping* is painful in a good way.

**First 10 seconds:** In tabletop pose, a bobber floats on a pond on the flat half. "A bite! Raise the lid to strike." Then the fight, with a forgiving tension band, and the first fish is landed in about 15 seconds.

**Risks:**
- Art cost for fish variety.
- Snapping a strike may tempt fast flicks. Make the strike window about 400 ms with only a 15° motion needed.
- Many fishing games exist, although none where the phone is the rod.

---

## Scorecard (1–10)

| # | Concept | Duo-unique | Instant clarity | Addictive | Satisfaction / juice | Comfort | Buildable (2 days) | Screenshot appeal | **Total /70** |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Pour Decisions** | 9 | 10 | 8 | 9 | 9 | 7 | 9 | **61** |
| 2 | **Chute** | 9 | 8 | 8 | 8 | 9 | 9 | 7 | **58** |
| 3 | Pop-Up | 10 | 7 | 8 | 8 | 8 | 5 | 10 | **56** |
| 7 | Swoop | 9 | 9 | 8 | 7 | 6 | 8 | 9 | **56** |
| 8 | Jib | 6 | 9 | 9 | 8 | 9 | 9 | 6 | **56** |
| 10 | Lunker | 7 | 9 | 8 | 8 | 8 | 7 | 8 | **55** |
| 4 | Lob | 5 | 9 | 7 | 7 | 9 | 9 | 6 | **52** |
| 9 | Bascule | 8 | 8 | 7 | 7 | 8 | 7 | 7 | **52** |
| 6 | Tumbler | 7 | 6 | 6 | 9 | 9 | 9 | 4 | **50** |
| 5 | Pump | 9 | 5 | 7 | 8 | 5 | 8 | 7 | **49** |

**Scoring notes:**
- **Duo-unique** asks whether the game needs two halves at a real angle, rather than just an analog value.
- **Comfort** penalises holding the phone in the air (Pop-Up, Swoop) and repetitive strokes (Pump).
- **Buildable** assumes SpriteKit, one engineer, 2 days, and simple art.

---

## Recommendation

### #1: Pour Decisions

- **It's the purest "two objects" design.** The glass stays still on the table and only the bottle moves. Tipping a container is the most natural thing a hinged object can do, so no tutorial is needed.
- **The hinge mapping is physically true.** The liquid surface stays level, and the angle you need rises as the bottle empties. A slider can't fake that feeling, and it removes the "1D slider" smell that sinks Lob and Jib.
- **It's tolerant of the sensor.** Flow is a smooth function of angle and the player closes the loop by watching the level, so 5° noise and update jitter are absorbed. Play stays in 180–100°, mostly slow continuous holds.
- **The loop is Stack-shaped, not toy-shaped:** precision plus push-your-luck plus a streak. The rising fill-pitch is a free piece of sound design that experts can play by ear.
- **It's buildable:** a particle stream, a level-and-wobble glass shader and an analytic bottle-surface cut. No fluid sim.
- **It fits Squish:** the same tabletop pose and the same hinge-input layer (reuse Squish's filtered hinge reader).

Compared with founder concept **A (sand Pour):** liquid gives foam, glugs and viscosity as difficulty levers, plus the rising-pitch audio. Sand gives angle-of-repose realism and more watchable grains. Best of both: launch with liquids, and make sand a later unlockable bar ("Sand Bar", using an angle-of-repose threshold). Also adopt the founder's best idea, **perfects refill the bottle**, as the endless-mode resource (below).

### #2: Chute

It is the most buildable hinge-native game: the SpriteKit physics comes free and it could ship in under 2 days. It is very tolerant of sensor error and the gentlest on the hinge (set it and release). Mid-slide braking gives it a skill ceiling that a plain power meter lacks. It shares the tabletop pose with #1, so the two could even ship as **one app with two modes**.

**Bigger swing:** **Pop-Up** has the strongest "only on a foldable" wow and the best screenshots, but it needs about 4–5 days of content and art. Consider it as the second title.

---

## #1 deep dive: Pour Decisions progression and difficulty

### Structure: Shifts plus Endless Happy Hour

**1. Shifts (the campaign, about 40 levels across 5 bars).** Each shift is 60–90 seconds with a target number of glasses and earns 1–3 stars (based on fills, Perfects and zero spills). Stars unlock the next bar. Each bar introduces one new liquid behaviour, so the game teaches itself one idea at a time.

| Bar | New mechanic | What it adds |
|---|---|---|
| 1. The Local (pub) | Water, juice and lager | The basics: flow ∝ tilt, and the bottle empties so you tip further. Lager adds **foam**: pouring steep makes a head that rises fast and then settles, so you must "pour slow, top up". |
| 2. Diner | Milkshake, **maple syrup** | **Viscosity lag:** syrup keeps flowing for about 0.8 s after you lay the bottle flat, so you must stop early. |
| 3. Wedding | **Champagne** | Huge, fast foam. Pour in two stages and wait for the fizz to settle while the conveyor moves. Timing pressure. |
| 4. Apothecary | Potions in measured vials (mL, no line drawn on some glasses) | **Precision and memory:** read the order ticket ("45 mL") off a graduated beaker, or remember the line, which fades out after 1 second. |
| 5. Cocktail Lounge | **Layered drinks**: 2–3 bottles, tap to swap bottles mid-shift | **Sequencing:** fill to line 1 with grenadine, swap, then line 2 with juice. Pouring too fast breaks the layers. |
| Unlockable: Sand Bar | Sand and hourglasses | Angle-of-repose threshold (nothing flows until about 30° of tilt, then a sudden rush). The founder's mechanic, as a mastery bar. |

**2. Endless Happy Hour (the score chase, unlocked after Bar 1).**
- Infinite conveyor, mixed drinks from every unlocked bar, and **one shared bottle (a keg).**
- **The resource:** spills and over-pours waste keg volume. **A Perfect refills the keg by +5%** and builds a streak multiplier (×2, ×3, ×5).
- The run ends when the keg runs dry or after 3 spills.
- Local best plus a Game Center leaderboard, plus a **Daily Last Orders**: a seeded run, the same for everyone, one attempt.

**3. Collection (no in-app purchases, it's paid).** Tips earned in shifts unlock cosmetic glassware (tiki mug, boot glass, test tube, goldfish bowl), bottle skins, bar themes and a "Spill-o-meter" of lifetime litres poured.

### Difficulty ramp (applied within each bar and in Endless over time)

1. **Conveyor speed:** time under the spout shrinks from 4 s to 1.5 s.
2. **Glass geometry:** start with straight-sided pints, where level rises linearly. Add flutes (narrow, so a small angle error means a big level change), bowls (fast at first, slow at the top), and shot glasses (tiny, needing a trickle with a barely-raised lid).
3. **Bottle state:** later glasses start with a nearly empty bottle, so you need a steep tip (θ near 90–100°) and get sputtering, uneven flow.
4. **Line tolerance:** the Perfect band shrinks from ±4% to ±2%, and the Good band from ±10% to ±6%.
5. **Behaviour stacking:** foam, viscosity, fizz and layers start mixing in the same shift.
6. **Curveballs, introduced singly:** a glass that slides in early, a glass already part-full, a "double" order (two glasses side by side under a wide spout, both lines matter), and wobbly-table gusts that slosh the glass.
7. **Endless pacing:** every 10 glasses the speed tier goes up and a new curveball enters the pool. A short "last call" bell every 25 glasses gives a breather and a 3-glass bonus round.

### Hinge-handling specifics

- Filter θ with a 1€ filter. Treat **θ ≥ 172° as fully closed** (a dead zone, so a phone resting "flat" never dribbles).
- Flow starts only past the liquid's lip angle, so there's no accidental pouring.
- Play happens between 180° and 90°. Below 90° the flow is clamped at maximum.
- An on-screen bottle mirrors the filtered angle at all times.
- **Touch fallback:** drag up on the top half to tip the on-screen bottle. Accelerometer tilt is an optional alternative.

### 2-day build sketch

- **Day 1:**
  - Hinge input, reusing the filter from Squish.
  - Bottle surface-cut maths and a particle stream.
  - Glass fill level, wobble shader and line-scoring.
  - Conveyor.
  - Bar 1.
- **Day 2:**
  - Foam and viscosity parameters.
  - Endless keg loop.
  - Audio (glug samples pitched by fill fraction) and haptics.
  - Stars and unlocks.
  - Touch fallback.
  - TestFlight.
- Bars 2–5 are mostly parameter tables (flow curve, foam rate, lag, glass shapes), which is content work rather than engineering.
