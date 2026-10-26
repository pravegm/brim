# Brim on iPhone Duo: platform audit and improvement plan

*26 Oct 2026, by the Duo platform specialist. This is a read-only audit: no code was changed. Sources:*
- *the code at `0e48224` plus the uncommitted QA-5 P1-1 work in the tree (`Layout.swift`, `RootView.swift`,
  `GameController.swift`, `OrientationLock.swift`, `DemoMode.swift`);*
- *Duo CI run 40314293608 (hinge, turned and close-mid-pour frames and logs), Duo run 40266632798 (UI frames) and the
  store run 40270623298 (`store-duo`);*
- *Apple's iPhone Duo Tech Talks, the forum Q&A thread 847644, the "Three steps" page and the App Store news post (list
  at the end);*
- *`design/QA-5.md`. Nothing QA-5 already reports is repeated here; it is only cross-referenced.*

## Verdict

Brim already gets the hard part right, the part nobody else has: the tabletop frame.
- The world is composed for the 669 × 951 canvas. The crease band in world space (456…496) lands exactly on iOS's own
  fold region (CI logs `fold active 0,456 669x40`), and the stream really crosses the fold.
- The hinge pipeline is careful: predictor, One-Euro, hold stabiliser, a closing guard and a flat gate. Squish's
  real-device lessons are all applied, and closing the phone mid-pour is proven harmless on CI (`CLOSE-GUARD … PASS`).

Brim is weaker away from that one pose:
- **Book pose with touch** draws the jug and glass straddling the vertical fold.
- **The cover display**, which is the pose a Duo spends most of its life in, shows a static card that doesn't even
  mention a paused run.
- **Split View** misread a window as the cover display. QA-5 P1-1 is fixing this in the tree now; small gaps remain.

Apple's one instruction for games on Duo is "make your game playable in every device pose … prefer changing aspect
ratio over letterboxing". The featuring nomination already claims "every pose". Today that claim holds for tabletop and
Split View only.

None of the fixes is large. Four Musts total about 1.5 engineer-days, and they turn "great in one pose, polite in the
others" into "plays in every pose". Everything else can wait for 1.0.x.

Non-Duo fallback is solid:
- Touch copy is right everywhere.
- Other phones get the same world, aspect-filled.
- iPad compatibility mode is fine.
- Mac and Vision Pro are correctly planned as opted out.

---

## Pose-by-pose

Grades: A = Duo-native and verified · B = correct but leaves value on the table or is unverified · C = works, weak ·
F = wrong.

| # | Pose / transition | What happens now | Grade | Gap |
|---|---|---|---|---|
| 1 | **Flat, at rest** (inner 669 × 951, fold across) | "Lay it flat to start" gate opens at ≥ 168°. Dead zone below 6° of lid tilt. Hint card on the raised half, Play row on the flat half (`duo-ui-menu`) | A− | The 6° dead zone vs ~±5° hinge accuracy leaves ~1° of margin if a unit reads 175° lying flat. The jug geometry's headroom probably hides it. Device check (M4) |
| 2 | **Tabletop / seated, pouring** | Jug on the raised half, stream across the fold, glass on the flat half (duo-02/03). One world, aspect-filled. The crease matches the `.division` frame. 120 fps SpriteView | A | Unverified on device: does iOS's fold-start blur (~2 s) now land on the **jug** at every pour start? (M4) No thermal step-down (S1). The pause button sits on the raised lid (L5) |
| 3 | **"Glasses on the sharp half"** (default on: upside down) | iOS is asked for `.portraitUpsideDown`. If refused, RootView draws the game turned round, with insets swapped and both home edges deferred (duo-10/11/12: TURNED-ROUND PASS, fallback path) | B | CI proves only the fallback (Debug keeps `UIRequiresFullScreen`, and iOS refuses). The Release path, where iOS turns round itself, is untested (S3). Nothing in the app explains it: that's **QA-5 P1-2**, owned there |
| 4 | **Book pose** (fold vertical, 951 × 669) | Opaque "Turn me…" card: drawing on the left page, copy and buttons on the right, nothing within 24 pt of the fold (`duo-ui-book`). "Use touch" plays in a centred 468 pt column | **C** | **Defect:** that column is centred on the fold. The jug pivot lands at x ≈ 488 and the stream and glass at x ≈ 498; the fold is 456…496. The jug and the glass straddle the crease (**M2**) |
| 5 | **Tent / standing** (partly closed, outer display facing you) | Below 70° a live run pauses with nothing judged. Once iOS moves Brim to the cover display, CoverView shows | B+ | No special handling needed; this is effectively "closed". Covered by M3 |
| 6 | **Closed → cover display** (466 × 678) | `CoverView`: wordmark, "Open me to pour", Rush best, Daily status, streak (duo-05). A run that was live is closed-paused underneath, invisible | **C** | The game world fits this canvas better than any other iPhone's (98 % of its width visible), yet the cover can't play. It doesn't say a run is paused. It allows landscape for no reason (**M3**) |
| 7 | **Reopening** | Canvas back to ≥ 760 releases "shut". The flat gate re-arms ("Lay it flat to carry on", duo-09). `HingeReader` re-enables on activation | A− | With M3 the handover becomes cover touch → inner hinge mid-run: the same `requireFlat` path, so it needs a CI check |
| 8 | **Fast close mid-pour** | `ClosingGuard` cuts the pour below 120° at > 160°/s. Autopause at < 70°. Proven on CI: `CLOSE-GUARD autopause@44 resume@74 judged-between=0 PASS` | A | — |
| 9 | **Split View, 50/50** (book: ≈ 475 × 669 per app) | At `0e48224`: read as the cover display ("Open me to pour") and closed-paused (QA-5 P1-1). In the tree now: `isWindowed` gives `.play` with touch and no fold, and the cover is decided from the *screen* | F → B once landed | The 475 × 669 pane fits the world almost exactly (scale 0.709, 100 % of the width). Good. Narrow panes are unverified (M1) |
| 10 | **Narrow / stacked windows** (portrait side-by-side ≈ 334 × 951; stacked above a pinned PiP ≈ 669 × 475) | In the tree: `.play`, touch. 334 wide shows only world x 168…502 (narrower than any phone; the waiting glass is cropped, and the Home row has 4 buttons in 334 pt). 669 × 475 becomes a 333 pt column | ? | Unverified. Show a status card below a minimum size instead of a broken layout (M1) |
| 11 | **Slide Over / PiP** | Brim has no video and can't be pinned. Another app's pinned PiP resizes Brim vertically (row 10). Apple: no Stage Manager on Duo | B | Covered by M1's minimum-size rule |
| 12 | **Background → foreground** | `HingeReader` toggles `isEnabled` for 30 ms to force a fresh reading. A live run pauses on inactive | A | — |
| 13 | **Regular iPhones** | The same world, aspect-filled (an iPhone 18 Pro sees x ≈ 116…554). Drag up to tip. Every hint swaps "Lift the top half" for "Drag up" (`HintsOverlay.text`, `PauseView`). No Duo copy leaks (Settings › About explains the Duo) | A | — |
| 14 | **iPad** (iPhone app in compatibility mode, `TARGETED_DEVICE_FAMILY 1`) | Runs as a portrait iPhone window with touch. `isWindowed` may read true there (canvas < iPad screen), but the only effect is touch, which it already uses | B+ | Fine for 1.0. Don't add iPad to the family: it would need iPad screenshots and multitasking support |
| 15 | **Mac (Apple silicon) / Vision Pro** | `metadata.md:242` says to untick both in App Store Connect | A (if ticked) | Keep them opted out: mouse-drag pouring and window rotation are untested. Make sure it's in runbook §4 |
| 16 | **Touch on a Duo** (accessibility, or a Duo that can't lie flat) | Settings "Touch controls on iPhone Duo". The flat gate offers "Use touch instead" after 6 s. Book-pose "Use touch". Closing still pauses | A− | VoiceOver can't pour (deliberately not claimed, `accessibility.md`). `ClosedPauseView` still says "lay me flat" in touch mode (S4) |

### Display specifics

- **Reserved regions.**
  - *Fold (`.division`).* The crease is hard-coded in world space and lands on iOS's fold exactly: tabletop
    `0,456 669x40`, book `456,0 40x669`. Every overlay avoids it (`CanvasInfo.band`, `HintSpot`, `CalloutPlacement`,
    `DuoSplit`). The region is read only for a DEBUG log. That is fine for one device, but CI should fail if it ever
    moves (S2).
  - *Inner camera (`.occlusion`).* It sits under the display and its region is active only while the camera runs
    ("Strike a pose", 111463), so nothing in Brim can collide with it.
  - *Outer camera.* A punch-hole that is always present. Today only the centred CoverView is drawn there. Cover play
    (M3) puts the HUD there, so take the safe area plus any `.occlusion` frames (S5).
- **No HUD or button sits under the crease or a camera in any pose we capture.** That covers tabletop upright,
  tabletop turned round (insets swapped, `RootView.insets`), book card, cover card and results. The one exception is the
  book-touch game itself (M2).
- **Edge-to-edge.** Built with the Xcode 27.1 / iOS 27.1 SDK (`duo.yml`, `testflight.yml`), so there is no
  letterboxing. `statusBarHidden` and `persistentSystemOverlays(.hidden)`. No system toolbars, so the vertical-bar
  behaviour doesn't apply.
- **120 Hz.** `CADisableMinimumFrameDurationOnPhone` and `SpriteView(preferredFramesPerSecond: 120)`
  (`RootView.swift:273`). There is no fallback for thermal state or Low Power, and reviewers say the Duo runs warm (S1).
- **Dynamic Island.** It is on the outer display only (a punch-hole that grows for Live Activities). Brim has no Live
  Activity. Relevant only to M3's HUD top inset.

### Hinge use

- **Mapping.** `tilt = clamp(180 − θ, 0…90)`, `jug = 1.55 × (tilt − 6)`. Play runs 174°…~95°, the closing pause is
  below 70°, and nothing ever needs the lid past upright. Comfortable, and kind to the hinge.
- **Accuracy (~±5°).** Irrelevant in practice: the player closes the loop by eye and ear, and no target angle is ever
  asked for.
- **Latency and noise.** Squish's tuned pipeline is in use. Irreversible events fire from measured angles only.
- **Fold-start blur.** The iOS blur on one physical half is handled by moving the glasses off that half. Two things
  are open:
  1. whether the blur now hits the jug at the start of *every* pour;
  2. whether it fires only when leaving true flat (180°, `fullyOpen` status). If so, coaching a "nearly flat" rest
     between glasses (the dead zone already allows ~170°) would avoid it altogether.
  Only the founder's Duo can answer either, so they go in the runbook (M4).
- **Unexploited.** Home's attract jug could follow the hinge instead of pouring by itself (L1). Stereo is unused,
  though the Duo has one speaker per half (L2). Haptics don't change with the lid angle. Results has no hinge gesture
  (L4).

### Store presence

- **Copy.** The promotional text and description lead with the Duo ("Your iPhone Duo is the jug … PLAYS ON EVERY
  iPhone") and say "drag up" for every other iPhone. Good.
- **Duo set.** D1–D5 at 2007 × 2853, upright and truthful (the player sees this after turning round). D6 was dropped.
  Submitting Duo screenshots earns the "optimized for iPhone Duo" badge (Apple news post). Duo screenshots become
  mandatory in April 2027.
- **Gap.** There is no **outer display set** (1398 × 2034), and no frame shows the hinge itself. M3 makes a truthful
  outer-display frame possible (S6). A real-Duo App Preview comes later (L7).

---

## Improvements, ranked

### Must (before submission)

**M1. Land QA-5 P1-1 (Split View) and close its three gaps.** About 2 h on top of the in-tree work.

The in-tree diff is right in principle:
- `PoseRule.isWindowed`, with the cover decided by *screen* size: `Layout.swift:80-125`;
- `OrientationLock.windowScreenSize()`;
- `GameController.setWindowed`: `GameController.swift:625`;
- `handleCanvas` calls `setWindowed` first: `RootView.swift:192`.

It needs three more things before it ships:
1. **A minimum window.** Below 360 pt wide or 520 pt tall:
   - Return a new `DevicePose.cramped` from `PoseRule.pose` (after the cover check, before `isWindowed → .play`).
   - Have RootView show a `CoverView` variant: the same Rush and Daily rows, a paused-run line (M3), and the title
     "Make Brim full screen to pour".
   - The Duo's 50/50 split can't be resized (forum 847644: "Free resizing: Not supported"), so don't promise "drag to
     widen". Add `.cramped` to `setPose`'s pause branch exactly like `.standUp`, never as a closing pause.
2. **Keep M2's book-page rule out of windows.** `bookPage` returns nil when `isWindowed`.
3. **CI frames.** Use the new `window=` key in the `ui` pass of `ci/duo.sh` (lines ~197-213):
   ```
   launch ui-split "mode=shift:1-1;window=475x669;autopilot=perfect;freezeOn=midpour;duo"; store_wait ui-split "freezeOn=midpour" 8; shoot duo-ui-split inner
   launch ui-split-narrow "window=334x951;duo";  shoot duo-ui-split-narrow inner   # expect the cramped card
   launch ui-split-stack  "window=669x475;duo";  shoot duo-ui-split-stack inner    # expect the cramped card
   ```
   Then grep each log for `BRIM-T windowed 1` and `pose=play` / `pose=cramped`.

   Re-run the `close-mid-pour` scenario unchanged. During the cover → inner handover the canvas can briefly be smaller
   than the screen, and `CLOSE-GUARD … PASS` (`resume needsFlat=1`) proves that the transient never turns into a user
   pause.

   Unit tests:
   - `pose(475×669, screen 951×669) == .play`;
   - `pose(334×951, screen 669×951) == .cramped`;
   - `pose(466×678, screen 466×678) == .cover`.

   Keep review-notes line 2f as written.

**M2. Book pose with touch: play on one page, never across the fold.** About 2 h.

- **Where:** `PoseRule.playRect(in:)` at `Layout.swift:116`; `RootView.content` at `RootView.swift:79-87` (the
  `column` insets); the `.play` branch at `:90`.
- **Today:** a 468 pt column centred at x 475. Jug pivot ≈ 488, glass ≈ 498, fold 456…496.
- **Change:**
  1. Add a pure `PoseRule.bookPage(canvas:hingeSeen:screen:fold:) -> CGRect?`. When the canvas is landscape, not
     windowed, and (`hingeSeen || looksLikeDuoInner`), return the right-hand page: `x = foldMaxX`,
     `width = canvas.width − foldMaxX`, full height.
     - `foldMaxX` comes from `proxy.reservedRegions(kind: .division, options: .includeInactive).first?.frame.maxX`
       (iOS 27.1, read in `RootView.body` where `activeDivision` already lives).
     - Fallback: `canvas.width / 2 + 20`, which is 496 on the Duo and matches CI.
  2. Use it in place of `playRect` when it is non-nil. The page is 455 × 669, a 0.68 aspect against the world's 0.704,
     so scale 0.703 crops only ~8 pt each side. The jug lands at x ≈ 736 and the glass at ≈ 745, well clear of the fold.
  3. **The left page** gets a quiet panel:
     - cream background with the small `TurnPhoneDrawing`;
     - "Turn me and lay me flat to pour with the hinge";
     - the existing "Turn the screen" button.
     It sits within `StandUpCard.pageMargin` and never within 24 pt of the fold. Only the right page hosts the drag
     layer.
  4. **Insets:** for the page, keep `safe.trailing` and `top` / `bottom`, and zero only `leading`. Today `column` zeroes
     both sides.
- **Edge cases:**
  - Turning back to portrait already clears `bookTouchOverride` (`RootView.swift:201`), so the session adopts the fold
    and closes the flat gate (`GameController.updateCanvas`).
  - The flipped landscape gives the same page split.
  - Left-handed play on the left page comes later (L9).
- **Test:**
  - Unit tests: `bookPage(951×669, hingeSeen) == (496, 0, 455, 669)`; nil for a 475 × 669 window and for a portrait
    canvas.
  - Add a DEBUG demo key `bookTouch` that sets `bookTouchOverride` at launch.
  - In `ci/duo.sh`, add it next to `ui-book` (no `orient=portrait`, so the sim stays in book pose):
    `launch ui-book-touch "mode=shift:1-1;duo;bookTouch;autopilot=perfect;freezeOn=midpour"; store_wait ui-book-touch "freezeOn=midpour" 8; shoot duo-ui-book-touch inner`.
    A critic checks that the stream and glass sit right of x 496 pt (1488 px).

**M3. The cover display: say what's paused, and let it play with touch.** About half a day. If it slips, ship parts
(a) and (d) alone (30 min) and move (b) and (c) to 1.0.1.

- **Where:**
  - `CoverView`: `PoseCards.swift:245-303`
  - `PoseRule.pose`: `Layout.swift:91`
  - `GameController`: `setPose` `:530`, `hingeSample` `:558`, `closingGuardActive` `:585`, `refreshInputMode` `:635`
  - `RootView.content` `.cover` at `:100`, `handleCanvas` `:192`
  - `OrientationLock.duoMask`: `OrientationLock.swift:42`
- **Why:** the game world fits the 466 × 678 cover better than any phone (scale 0.712, 654 of 670 world pt visible).
  Apple's game guidance is "playable in every device pose". The featuring nomination claims every pose. Closed is the
  pose a Duo is in most of the day.
- **Change:**
  - **(a) Paused-run line.** When `controller.isClosedPaused`, CoverView's card gets a top row: "Paused ·
    `GameController.title(for: mode)` · glass `ordersDone + 1` of N", and the title becomes "Open me to carry on". Pass
    `controller` into `CoverView`.
  - **(b) "Pour here with touch" button.**
    - CoverView gets a secondary button that calls a new `controller.playOnCover()`. It sets
      `@Published coverTouchOverride = true`, then `releaseClosingPause()`, then `setUserPaused(true)` if `isLiveRun`
      (so the player resumes on purpose; the PauseView shows), then `refreshInputMode()`.
    - `PoseRule.pose` gains a `coverTouch: Bool` parameter. When it is true and the *screen* is cover-sized, return
      `.play`; this check comes before the `isShut` line. `hasFold` is already false there.
    - `refreshInputMode`: add `|| coverTouchOverride` to `touchWanted`.
    - `closingGuardActive`: return false while `coverTouchOverride`. Otherwise the shut hinge (≈ 0°) re-pauses at once.
  - **(c) Back to the inner display.** In `handleCanvas`, when the screen's long side is ≥ 760, call
    `controller.clearCoverTouch()` *before* `updateCanvas` (mirror `clearBookTouchOverride`). The existing
    `newLayout.hasFold && !hadFold && isLiveRun && !usesTouch` branch then calls `requireFlat()`, and the run carries
    on with the hinge behind "Lay it flat to carry on".
  - **(d) Cover is portrait-only.** In `duoMask`, change `sharpSide && inner ? .all : .allButUpsideDown` to
    `inner ? (sharpSide ? .all : .allButUpsideDown) : .portrait`. Brim is portrait on every phone-shaped screen, and
    the outer display honours supported orientations (forum 847644). Update the doc comment and test.
- **Edge cases:**
  - Today's scored Daily keeps its attempt; nothing about scoring changes.
  - A brand-new install launched closed never saw a hinge, so it already plays with touch on the cover (`hingeSeen`
    false). Keep that.
  - HUD top inset: see S5 for the punch-hole.
  - Reopening mid-pour: the touch drag is cancelled by `touch.cancelled()` in the pose change. Add that call to
    `clearCoverTouch()`.
- **Test:**
  - Unit tests: `pose(466×678, screen 466×678, hingeSeen, isShut: true, coverTouch: true) == .play`; `coverTouch`
    false gives `.cover`; `duoMask(sharpSide: true, screen: 466×678) == .portrait`.
  - Add a DEBUG demo key `coverPlay`.
  - In `ci/duo.sh`, after `duo-06-reopened`:
    ```
    hinge_set 0; launch cover-play "mode=shift:1-1;duo;coverPlay;autopilot=perfect;freezeOn=midpour"; store_wait cover-play "freezeOn=midpour" 10; shoot duo-13-cover-play cover
    ```
    Add a handover check: launch `mode=shift:1-2;duo;coverPlay` shut, `hinge_sweep 170 2.5`, and assert
    `BRIM-T resume needsFlat=1` (or `gate`) in its log.
  - Re-shoot the cover card (`duo-05`) for the paused line using the `close-mid-pour` scenario's `duo-08`.
  - Update review-notes 2e ("Closed, the outer display shows a status card, and 'Pour here with touch' plays there")
    and the featuring line ("touch play on the outer display").

**M4. Add a 3-minute "Duo specifics" block to the real-Duo check** (`docs/LAUNCH-RUNBOOK.md` §3, after row 8–9). About
20 min, doc only.

The founder is the only real-Duo tester, and these answers decide whether S1/L2/L3 and the sharp-half default are
right:
1. With the phone turned round as Brim asks, lift from flat 5 times. *Which half blurs: jug or glasses? Every lift, or
   only the first?*
2. Rest the lid just off the table (about a finger's width) between glasses instead of fully flat. *Does the blur still
   happen?*
3. Settings › About: copy the "Screen: … · iOS turn: …" line.
4. Book pose: open Safari, then put Brim beside it in Split View. *What does Brim's half show? Can you pour by
   dragging?*
5. Close the phone mid-shift, then look at the outer screen. *Does it say the shift is paused?* (After M3: tap "Pour
   here with touch", pour one glass, open the phone, lay it flat, carry on.)
6. Lying flat and untouched, *does anything ever dribble?*
7. Pour with your ear near each half. *Which half is the glug louder on?* (input for L2)

Add the answers to the feedback template.

*Also before submission, owned elsewhere:* QA-5 P1-2, the one-time "turn me round" hint plus the review-notes line.

### Should (if cheap)

**S1. Step down from 120 Hz when hot or in Low Power.** About 30 min.
- Add `@Published frameRate` in `GameController`.
- Compute it with a pure `static func frameRate(thermal: ProcessInfo.ThermalState, lowPower: Bool) -> Int`:
  120, or 60 at `.serious` and above or in Low Power.
- Observe `ProcessInfo.thermalStateDidChangeNotification` and `.NSProcessInfoPowerStateDidChange`.
- Feed it into `SpriteView(preferredFramesPerSecond:)` at `RootView.swift:273`.
- Unit-test the rule. The pour simulation is dt-clamped and sub-stepped, so physics is unaffected.

**S2. CI asserts the fold.** About 20 min. In `ci/duo.sh`, after the hinge pass:
```
grep -q "fold active 0,456 669x40" "$OUT_ABS/logs/hinge-1-1.txt" && log "FOLD-MATCH PASS" || log "FOLD-MATCH FAIL"
```
This matches `WorldLayout.creaseBottom/Top`. Add the book equivalent (`456,0 40x669`) to `ui-book`. It catches a
simulator or OS update that moves the fold before a store frame shows it.

**S3. One Duo CI pass with the Release orientation setup.** About 1 h.
- Add a `duo.yml` input `drop_fullscreen` (default false).
- When true, run
  `/usr/libexec/PlistBuddy -c "Delete :UIRequiresFullScreen" "$APP/Info.plist" && codesign -f -s - "$APP"` before
  `simctl install`, then run only the `turned` scenario.
- Expect `TURNED-ROUND PASS (system upside down)`. If the in-app `orient=portrait` can't rotate without the key, the log
  says so, and that is useful too.
- This is the only way to see the shipping orientation path before the founder's device does.

**S4. `ClosedPauseView` copy in touch mode.** About 5 min. `PlayOverlays.swift:545` always says "Open me up and lay me
flat". Use `controller.usesTouch ? "Open me up" : "Open me up and lay me flat"`, matching the sub-line, which is
already touch-aware.

**S5. Fold `.occlusion` regions into the insets.** About 30 min; do it with M3.
- In `RootView.body`, also read `proxy.reservedRegions(kind: .occlusion)` (iOS 27.1).
- For each frame touching the top or bottom 120 pt, raise `safe.top` / `.bottom` to clear it (+6 pt) before
  `CanvasInfo` is built.
- Apple: custom elements overlapping a camera region "may have touches suppressed". The punch-hole only matters on the
  cover display, where M3 puts a pause button.
- Log the frames in DEBUG so `duo-13` documents them.

**S6. Outer display screenshot set** (1398 × 2034, after M3). About 1 h of CI.
- Add `C1` to `ci/store-scenarios.txt`: `mode=shift:1-1;coverPlay;autopilot=perfect;freezeOn=midpour`, captioned
  "Closed? *Keep pouring.* / Touch play on the outer screen."
- Teach the store pass to `hinge_set 0` and shoot `cover` for `C*` names.
- It is truthful only once M3 ships. Upload it if App Store Connect shows an outer-display slot.

**S7. Stop sizing from `UIScreen.main`.** About 5 min. `GameController.swift:262` passes `UIScreen.main.bounds.size` to
`trustsStoredHinge`. Apple's Duo checklist (step 2) says don't. The value is harmless today (both Duo screens are ~0.7),
but use `OrientationLock.windowScreenSize() ?? UIScreen.main.bounds.size` so the app resizability scan comes up clean.

### Later (1.0.x)

- **L1. Home attract follows the hinge on a Duo.** When `hingeSeen && !usesTouch`, drive the attract practice with
  `HingeTiltSource` instead of the autopilot: lifting the lid on the menu pours, silently. It teaches the verb before
  Play and answers the founder's "it pours by itself" more natively than the DEMO tag.
- **L2. Stereo across the halves.** The Duo has one speaker per half. The engine is mono today
  (`BrimAudioEngine.swift:204`, `channels: 1`).
  - Render stereo with the glug and pour bed panned to the jug half and the ting and splash to the glass half.
  - Map the pan per orientation, including upside down. Needs M4 answer 7 first.
- **L3. Per-device flat calibration**, if M4 answer 6 is ever yes. Record the hinge's max reading while the flat gate is
  satisfied and treat it as 180 (offset capped at 6°).
- **L4. Hinge gesture on Results.** "Lift to pour the next shift" on the Duo results card, so no one taps the raised
  half.
- **L5. Pause button on the flat half** (`PlayOverlays.swift:83`). Apple puts touch controls on the "stable base" in a
  propped pose. This needs a store re-shoot, so not for 1.0.
- **L6. Venues on the Duo.** The paged layout leaves a gap at the fold even when flat (why D6 was dropped). Apple:
  "scrollable content doesn't need to avoid this region". Use the gap only while the `.division` region is active, then
  restore D6.
- **L7. Real-Duo App Preview** (or a 3D tabletop store shot). The flat frames can't show the lid lifting.
- **L8. `deviceMotionBody` seated check.** Tell "on a table" from "in the hand" and coach toward tabletop. The IMU half
  is unverified.
- **L9. Left-page option** for book-pose touch (left-handers).

---

## Sources

Apple:
- Tech Talks: *Design for iPhone Duo* (111466), *Prepare your app for iPhone Duo* (111461), *Strike a pose with adaptive
  layouts* (111463), *Leverage multiple displays and scenes* (111464): https://developer.apple.com/videos/play/tech-talks/111463/
  and the sibling IDs.
- Developer Forums Q&A 847644 (pose, reserved regions, cover, Split View, games): https://developer.apple.com/forums/thread/847644
- *Three steps to make your app shine on iPhone Duo* (resizability checklist; featuring: "supports all device poses"): https://developer.apple.com/iphone-duo/prepare/
- *Prepare and submit your apps for iPhone Duo* (badge, preview tool, April 2027 requirement): https://developer.apple.com/news/?id=kkphp5qo

Press:
- Speaker per half: SamMobile, https://www.sammobile.com/news/apple-iphone-duo-solved-speaker-issue-samsung-couldnt-galaxy-z-fold-8/
- Under-display inner camera: iThinkDiff, https://www.ithinkdiff.com/iphone-duo-inner-display-deep-dive/

Repo:
- `research/02-hinge-tech.md`, `design/QA-5.md`, `docs/appstore/{review-notes,metadata,screenshots,featuring-nomination}.md`
- CI runs 40314293608, 40266632798, 40270623298. The frames are in the session scratchpad, `duo-audit/`.
