# Brim: App Review notes (v1.0)

*Written 25 Oct 2026 from `design/GAME-DESIGN.md` and `design/ARCHITECTURE.md`. The block between the markers is what you paste. Apple limits the field to 4,000 bytes; the block is **3,609 bytes**, plain ASCII (no smart quotes or symbols) so bytes = characters. Before submission, tick the "Check against the build" table at the end; if a line is false, change the block, never the other way round.*

## Where this goes

App Store Connect → the app → the **1.0** version page → **App Review Information**:
- **Sign-in required:** unticked (there are no accounts).
- **Contact:** the founder's first name, last name, phone and email (founder-only; never in the repo).
- **Notes:** the block below.
- **Attachment (optional, recommended):** a 20–30 s screen recording, or a phone video, of one pour on the Duo in tabletop pose: lift, pour, lay back, Perfect. The notes don't depend on it.

<!-- REVIEW-NOTES:BEGIN -->
```
Thanks for reviewing Brim: a paid game with no ads, no in-app purchases, no accounts, no data collection and no network requests of its own.

1. TESTING WITHOUT AN iPHONE DUO (start here)
You don't need a Duo. Every mode, venue, unlock and achievement works on any iPhone and in the Simulator.
- Tap Play. A jug sits at the top of the screen and a glass on the counter below, with a dashed fill line.
- Put a finger anywhere and drag UP: the jug tips and pours. Let go and the jug eases back upright and the pour stops.
- The stream takes a moment to fall, so stop just before the line. The glass is judged Perfect / Great / Good / Short / Spill once the pour has landed.

2. HOW THE HINGE IS USED (iPhone Duo)
Brim reads the hinge angle only through the public iOS 27.1 API (SwiftUI onHingeChange), behind an availability check. No private API is used.
a) Open the Duo fully and lay it on a table, inner screen up, fold running left to right. The jug is drawn on the far half, the glass on the near half.
b) Raise the far half off the table, like lifting a laptop lid. The jug tips with it and pours across the fold into the glass. Nothing pours until the lid is about 6 degrees up, so a phone lying flat never dribbles.
c) Lower the lid back toward flat to stop. Play happens between about 175 and 95 degrees (never past upright), mostly with slow, held angles. A full jug pours with a small lift; an emptier jug needs a bigger one.
d) Book pose (fold running top to bottom): the game pauses and shows "Stand me up like a little laptop".
e) Closed: the outer display shows a calm status card (today's Daily Pour, best Rush score, "Open me to pour"). Nothing happens while closed.

3. KIND TO THE DEVICE (Guidelines 2.4.2 and 1.4.5)
- Brim never asks the user to close the phone, fold quickly or fold repeatedly. The hinge is used like a slow dial in the middle of its range.
- Nothing is placed on or between the screens; everything is on screen.
- No score, achievement or bonus rewards folding speed or the number of folds. Flapping the lid only spills drinks, which costs points.
- The game reads the angle, never the closed state, during play.

4. MODES AND UNLOCKS (nothing hidden, nothing to buy)
- Shifts: five venues (Lemonade Stand, Soda Fountain, Milkshake Diner, The Conveyor, Potion Shop). Stars earned in one venue open the next.
- A sixth, secret venue (Sand Bar) opens after earning 3 stars on every shift. There is no code, shortcut or purchase for it.
- Rush: endless; ends after 3 spills or when the jug runs dry.
- Daily Pour: 10 glasses, the same for everyone that day, one scored attempt; practice afterwards is unscored. The result can be shared as text through the system share sheet.

5. CONTENT
Every drink is non-alcoholic: water, lemonade, juice, sodas (cola, root beer, cream soda), milkshakes, honey, syrup and fictional coloured potions. No characters are harmed; a spill makes a puddle.

6. PRIVACY
No third-party SDKs, analytics, ads, accounts or tracking, and no network requests of our own. Progress and settings are stored only on the device. App Privacy: Data Not Collected.

7. GAME CENTER
Optional. 2 leaderboards (Rush best, Daily Pour) and 10 achievements (700 points); one achievement is hidden until earned. If the player isn't signed in, Brim works fully.

8. OTHER
- No notifications are requested.
- Sound plays when the silent switch is on (playback audio, mixing with other audio); Settings > "Respect silent mode" turns that off.
- All sound is synthesized in the app; there are no recorded or licensed assets.
- Release builds contain no debug or demo modes.
```
<!-- REVIEW-NOTES:END -->

## Check against the build (before submission)

| Claim in the block | Source today | Check |
|---|---|---|
| Drag **up** anywhere tips; release eases upright | `TouchTiltSource` (ARCHITECTURE: "drag up = tip; eases back to 0 on release") | [ ] |
| "Tap Play" is the real first button label | App UI (not built yet) | [ ] change the word if the button says something else |
| Public `onHingeChange` only, behind `#available(iOS 27.1, *)` | `HingeReader` (ARCHITECTURE), CLAUDE.md | [ ] |
| Dead zone 6° (≈175°), play to about 95° | `Rules.deadZone`, bible §4 | [ ] update the numbers if tuning moves them |
| Book-pose card text "Stand me up like a little laptop" | Bible §3 | [ ] exact wording |
| Cover card content | Bible §3 | [ ] |
| Never uses `status == .closed` in play | CLAUDE.md, bible §4 | [ ] grep |
| Unlock rule for Sand Bar = 3 stars on every shift | Bible §6 | [ ] |
| Daily: one scored attempt, then unscored practice | Bible §6 | [ ] |
| Setting name "Respect silent mode", default off | Bible §7 | [ ] exact label |
| No notifications, no rating prompt claims | — | [ ] if a rating prompt (`requestReview`) is added, add a line: "A one-time rating prompt may appear after a finished run, never mid-pour." |
| Demo mode compiled out of Release | ARCHITECTURE ("Demo mode (DEBUG and CI)") | [ ] |
| 2 leaderboards, 10 achievements, 700 points, 1 hidden | `achievements.md` | [ ] |

**One line to add only if it ships:** if engineering adds a Duo setting to pour by dragging (requested in `DECISIONS.md` §3), add to §1 of the block: `- On iPhone Duo: Settings > "Pour by dragging" turns on the same drag control.`

## If rejected under 2.4.2 (hardware) or 1.4.5 (physical harm)

Reply in the Resolution Center, calmly and specifically:
> "Brim never asks users to close the phone or to fold quickly or repeatedly. Play uses the hinge like a slow dial between about 175 and 95 degrees, the range the Duo's hinge is designed to hold, and most of the time the user is holding a still angle. No score, achievement or bonus rewards folding speed or fold count; fast lid movements only spill drinks and cost points. Nothing is ever placed on the device. Any iPhone without a hinge plays the full game by dragging. We're happy to add an on-screen line such as 'Slow and steady pours best' to the first-run hint if that helps."

## If rejected under 2.3.1 (hidden features)

Point to §4: the secret venue is reachable through normal play (3 stars on every shift), is described in the store copy as a tease ("three-star everything to find out what's behind the counter"), and has no code, shortcut or purchase.

## If rejected under 2.1 (couldn't use the hinge)

Point to §1: the full game is playable without a Duo. Offer the screen recording attachment.

## Sources
- App Review Guidelines (2.1, 2.3.1, 2.4.2, 1.4.5): https://developer.apple.com/app-store/review/guidelines/
- App Store Connect Help, *Platform version information* (App Review notes up to 4,000 bytes): https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- Squish's reviewed notes (structure mirrored): `C:\Users\59527\Squish\docs\appstore\review-notes.md`
