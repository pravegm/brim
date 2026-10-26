# Brim: App Review notes (v1.0)

*Written 25 Oct 2026; rewritten 26 Oct for "Glasses on the sharp half" (upside down by default on a Duo), Split View on the Duo inner display (touch) and QA-5 P1-2. The block between the markers is what you paste. Apple limits the field to 4,000 bytes; the block is **3,847 bytes**, plain ASCII (no smart quotes or symbols) so bytes = characters. Guideline 2.3.1(a) wants every feature described specifically here, and 2.5.19 (new, 16 Oct 2026) forbids undocumented features, so the secret venue and both Duo settings are named. Before submission, tick the "Check against the build" table at the end; if a line is false, change the block, never the other way round.*

**A reviewer on a normal iPhone** needs only §1. **A reviewer on a Duo** needs §2a first: the game appears upside down until the phone is turned round.

## Where this goes

App Store Connect → the app → the **1.0** version page → **App Review Information**:
- **Sign-in required:** unticked (there are no accounts).
- **Contact:** the founder's first name, last name, phone and email (founder-only; never in the repo).
- **Notes:** the block below.
- **Attachment (optional, recommended):** a 20–30 s screen recording, or a phone video, of one pour on the Duo in tabletop pose: lift, pour, lay back, Perfect. The notes don't depend on it.

<!-- REVIEW-NOTES:BEGIN -->
```
Thanks for reviewing Brim: a paid game with no ads, no in-app purchases, no accounts, no data collection and no network requests of its own.

1. ANY iPHONE (start here)
You don't need a Duo. Every mode, venue, unlock and achievement works on any iPhone and in the Simulator.
- Tap Play. A jug sits at the top, a glass with a fill line on the counter below.
- Drag UP anywhere: the jug tips and pours. Let go: it eases upright and the pour stops.
- The stream takes a moment to fall, so stop just before the line. Each glass is judged Perfect / Great / Good / Short / Over (too full, nothing over the rim) / Spill (over the rim).

2. iPHONE DUO (hinge)
Brim reads the hinge angle only through the public iOS 27.1 API (SwiftUI onHingeChange), behind an availability check. No private API.
a) Upside down by default: as a fold starts, iOS blurs one physical half of the inner display for about 2 s (all apps), so Brim runs the inner screen upside down to keep the glasses on the half that stays sharp. If the game looks upside down, turn the phone round once (hold it up for a second so iOS turns too). Settings > Controls > "Glasses on the sharp half" (Duo only) switches this off and restores the usual orientation.
b) Lay the Duo open on a table, inner screen up, fold running left to right: jug on the far half, glass on the near half. "Lay it flat to start" opens at about 168 degrees; after 6 s it also offers "Use touch instead".
c) Lift the far half like a laptop lid: the jug tips and pours across the fold. Nothing pours until the lid is about 6 degrees up. Lower it to stop. Play stays between about 174 and 90 degrees, with slow, held angles.
d) Book pose (fold top to bottom): the game pauses with "Turn me so the fold runs side to side, then lay me flat." and a "Use touch" button.
e) Below about 70 degrees a run pauses and nothing is judged; it resumes once open and flat. Closed, the outer display shows a status card ("Open me to pour").
f) Split View, or any window smaller than the inner display: Brim uses touch (drag up), as on other iPhones.
g) Settings > Controls > "Touch controls on iPhone Duo" uses drag full time.

3. KIND TO THE DEVICE (Guidelines 2.4.2, 1.4.5)
- Brim never asks the user to close the phone, fold quickly or fold repeatedly. The hinge is a slow dial in the middle of its range, read by angle, never by the closed state.
- Nothing is placed on or between the screens.
- Nothing rewards folding speed or fold count; flapping the lid only spills drinks, which costs points.

4. MODES AND UNLOCKS (nothing hidden, nothing to buy)
- Shifts: five venues (Lemonade Stand, Soda Fountain, Milkshake Diner, The Conveyor, Potion Shop). Stars open the next venue.
- A sixth, secret venue (Sand Bar) opens at 105 of the 120 stars in the five main venues. No code, shortcut or purchase.
- Rush: endless; ends after 3 spills or when the jug runs dry. Quitting from the pause menu keeps the score.
- Daily Pour: 10 glasses, the same for everyone, new each day at 00:00 UTC; one scored attempt (leaving part-way keeps the score so far), then unscored practice. The result can be shared as text via the share sheet.

5. CONTENT
Every drink is non-alcoholic: water, lemonade, juice, sodas (cola, root beer, cream soda), milkshakes, honey, syrup and fictional coloured potions. A spill makes a puddle; nothing is harmed.

6. PRIVACY
No third-party SDKs, analytics, ads, accounts or tracking. Progress and settings stay on the device. App Privacy: Data Not Collected.

7. GAME CENTER
Optional. 2 leaderboards (Rush, Daily Pour) and 10 achievements (700 points, 1 hidden). Brim works fully when not signed in.

8. OTHER
- No notifications, no rating prompt.
- Sound plays in Silent Mode (playback, mixes with other audio); Settings > "Respect silent mode" turns that off.
- Debug and demo modes are disabled in Release builds.
```
<!-- REVIEW-NOTES:END -->

## Check against the build (before submission)

Round 4 (App engineer) checked each line against the code; "Source today" names where it lives. Rows marked *26 Oct* were added or re-checked by the store lead.

| Claim in the block | Source today | Check |
|---|---|---|
| Drag **up** anywhere tips; release eases upright | `Input/TouchTiltSource.swift`, `UI/RootView.swift` (drag layer) | [x] |
| "Tap Play" is the real first button label | `UI/HomeView.swift` (`Play` + the shift) | [x] |
| Duo setting "Touch controls on iPhone Duo" | `UI/SettingsView.swift` | [x] exact label |
| Public `onHingeChange` only, behind `#available(iOS 27.1, *)` | `Input/HingeReader.swift` | [x] |
| "Lay it flat to start" before each Duo run | `UI/PlayOverlays.swift` (`FlatGateOverlay`) | [x] |
| Dead zone 6° (≈174°), play to about 90° (lid tilt = 180 − hinge, capped at 90) | `Core/Rules.swift` `deadZone`, `Input/TiltFilters.swift` | [x] update if tuning moves them |
| Book-pose card "Turn me so the fold runs side to side, then lay me flat." + "Use touch" | `UI/PoseCards.swift` (`StandUpCard`) | [x] exact wording |
| Closing below ~70° pauses, nothing judged, resumes behind the flat gate | `App/GameController.swift` (`autopauseBelow`, `resumeHook`), CI `CLOSE-GUARD` | [x] |
| Cover card: Rush best, Daily Pour #N, "Open me to pour" | `UI/PoseCards.swift` (`CoverView`) | [x] |
| Never uses `status == .closed` in play | `Input/HingeReader.swift` (angle only) | [x] grep |
| Rush ends after 3 spills or a dry jug | `Core/GameSession.swift` | [x] |
| Unlock rule for Sand Bar = 105 stars in the five main venues (round 9; `LevelCatalog.starsToUnlock(.sandBar)`) | `Persistence/ProgressStore.swift` (`isUnlocked`, `campaignStars`) | [x] |
| Daily: one scored attempt (marked at start; leaving files the score so far), then unscored practice | `Persistence/ProgressStore.swift` (`dailyStarted`), `App/GameController.swift` | [x] |
| Setting name "Respect silent mode", default off | `UI/SettingsView.swift`, `Feedback/FeedbackDirector.swift` | [x] exact label |
| No notifications, no rating prompt | no `UNUserNotificationCenter` / `requestReview` in `Brim/` | [x] if a rating prompt is added, add a line: "A one-time rating prompt may appear after a finished run, never mid-pour." |
| *26 Oct:* "Glasses on the sharp half" in Settings › Controls, on by default, Duo only (shown when a hinge has reported); off restores upright | `UI/SettingsView.swift` (`hingeSeen`), `Persistence/SettingsStore.swift` (`sharpSide`), `App/OrientationLock.swift`, `UI/RootView.swift` (`turnsRound`) | [x] code; [ ] real Duo |
| *26 Oct:* Split View / any window smaller than the inner display uses touch | QA-5 P1-2, being implemented 26 Oct (today a short window reads as the cover display, `PoseRule.coverMaxSide`) | [ ] **must land before submission**, or delete line 2f |
| *26 Oct:* Release has no `UIRequiresFullScreen` (needed for upside down and Split View) | `project.yml` post-build script, `testflight.yml` check | [x] |
| *26 Oct:* Daily Pour resets at 00:00 UTC | `Core/LevelCatalog.swift` `dayNumber` (UTC calendar) | [x] |
| *26 Oct:* "Use touch instead" after 6 s on the flat gate | `App/GameController.swift` `touchOfferDelay = 6` | [x] |
| Debug and demo modes disabled in Release | `App/DemoMode.swift` (`DemoConfig.current` is nil outside `#if DEBUG`; every `BRIM-T` trace is DEBUG-only) | [x] |
| 2 leaderboards, 10 achievements, 700 points, 1 hidden | `App/GameCenterManager.swift`, `achievements.md` | [x] |

## If rejected under 2.4.2 (hardware) or 1.4.5 (physical harm)

Reply in the Resolution Center, calmly and specifically:
> "Brim never asks users to close the phone or to fold quickly or repeatedly. Play uses the hinge like a slow dial between about 174 and 90 degrees (flat to upright), the range the Duo's hinge is designed to hold, and most of the time the user is holding a still angle. No score, achievement or bonus rewards folding speed or fold count; fast lid movements only spill drinks and cost points. Nothing is ever placed on the device. Any iPhone without a hinge plays the full game by dragging. We're happy to add an on-screen line such as 'Slow and steady pours best' to the first-run hint if that helps."

## If rejected under 2.5.19 or 2.3.1 (hidden or undocumented features)

Hidden features moved from 2.3.1 to the new 2.5.19 on 16 Oct 2026. Point to §4: the secret venue is reachable through normal play (105 of the 120 stars in the five main venues), is described in the store copy as a tease ("collect enough to find out what's behind the counter"), and has no code, shortcut or purchase.

## If rejected under 2.1 (couldn't use the hinge, or "the screen is upside down")

Point to §1: the full game is playable without a Duo. On a Duo, point to §2a: upside down is deliberate (iOS blurs one fixed half of the inner display as a fold starts), turning the phone round once fixes it, and Settings › Controls › "Glasses on the sharp half" switches it off. Offer the screen recording attachment.

## Sources
- App Review Guidelines, last updated 16 Oct 2026 (1.4.5, 2.1, 2.3.1(a) "described with specificity in the Notes for Review", 2.4.2, 2.5.19 hidden features): https://developer.apple.com/app-store/review/guidelines/
- App Store Connect Help, *Platform version information* (App Review notes up to 4,000 bytes): https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- Squish's reviewed notes (structure mirrored): `C:\Users\59527\Squish\docs\appstore\review-notes.md`
