# QA-1: code audit before launch (read-only)

*QA lead, 25 Oct 2026. I audited by reading the code: Core, Input, Feedback, Scene, App, UI, Persistence, project.yml, PrivacyInfo, review notes. Nothing was run. Every item below was traced through the code. Items marked **suspect** depend on device or OS behaviour that can't be confirmed from code alone.*

**Summary:** I found no P0. Core is NaN-guarded throughout (`step` sanitises dt and tilt, `GlassMath.height` handles NaN, fall-time square roots are guarded, every polygon helper checks its counts). I found no force-unwraps, `try!` or unguarded indexing. The audio render path is lock-free and allocation-free. Every Core Haptics and AVAudioSession callback hops back to the main actor. DemoMode is compiled out of Release (`DemoConfig.current` is `#if DEBUG`). The privacy manifest covers what is actually used (UserDefaults CA92.1, CACurrentMediaTime 35F9.1); I found no file-timestamp or disk-space APIs. The real risks are four P1s around state and lifecycle, plus a set of P2s.

---

## P0: crash, data loss or review rejection

None verified.

---

## P1: visible bugs a paying player will hit

### P1-1. Moving a Duo's data to another iPhone leaves the game unplayable
- **Where:** `App/GameController.swift:146` (`hingeSeen` read from `brim.hasHinge`, which is never cleared), `:345-355` (`refreshInputMode`), `UI/Layout.swift:77-93` (`PoseRule.pose` / `hasFold` trust `hingeSeen`), `App/OrientationLock.swift:21-31`, `UI/RootView.swift:197` (the drag layer exists only when `usesTouch`).
- **Scenario:** A player restores an iCloud/Finder backup (or does a Quick Start transfer) from an iPhone Duo to any other iPhone. UserDefaults travel with the backup, so `brim.hasHinge = true`.
  - On an iPhone 18 Pro: `usesTouch = false`, so there is no drag layer and nothing can pour. `hasFold` is true (long side ≥ 760), so the Duo flat gate and closing guard are active. Landscape is allowed, so turning the phone shows "Turn me so the fold runs side to side".
  - On an iPhone SE (667 pt long side): `PoseRule.pose` returns `.cover` permanently. The screen shows "Open me to pour" with no way out.
  - The only escape on larger phones is Settings → "Touch controls on iPhone Duo", which a non-Duo owner has no reason to try.
- **Fix:** Stop trusting the persisted flag on hardware that can't be a Duo. In `GameController.init`, keep `hingeSeen` from UserDefaults only if `OrientationLock.allowsLandscape(hasHinge: false, screen: UIScreen.main.bounds.size)` is true (Duo displays are about 0.7 wide-to-tall, other iPhones about 0.46). Otherwise remove `brim.hasHinge` and start with `hingeSeen = false`. Mirror the same check in `OrientationLock.mask`.

### P1-2. The Daily Pour's "one scored attempt" can be retried without limit
- **Where:** `Persistence/ProgressStore.swift:143-149` writes `daily[day]` only when a run finishes, through `App/GameController.swift:701-711`. The pause card's **Restart** (`UI/PlayOverlays.swift:528`) and **Menu** (`:531`), the closed-pause **Menu** (`:476`) and force-quitting the app all throw the run away without recording it.
- **Scenario:** A player starts Daily #298 and spills the first two glasses, so the score is 0 with 2 strikes. They tap Pause → Restart, and get a fresh, identical seeded run (`seed = day + 1`, `GameController.swift:609`) that counts as the scored attempt. Repeating this until they get a near-perfect run pushes an inflated score to the `brim.daily.score` leaderboard. That contradicts GAME-DESIGN §6.3 and the App Review notes (§4: "one scored attempt").
- **Fix:** Persist an attempt marker when a Daily starts. In `start(mode:)`, if the mode is `.daily(day)` and `store.dailyRecord(day:) == nil`, store `dailyStarted[day] = true` (a new tolerant field). In `record`, count the run only if no record exists. Treat a later Daily whose day is already marked started as practice: record the abandoned attempt as a score of 0 with the judgements so far, or show "Practice pour". If the marker feels too harsh, the minimum fix is to hide Restart on the pause card in a scored Daily and record the partial run on Menu.

### P1-3. Changing the canvas mid-run silently restarts the run (Duo)
- **Where:** `App/GameController.swift:227-238`. `updateCanvas` calls `buildSession()` whenever the `WorldLayout` changes and `session != nil`. Triggered from `UI/RootView.swift:126-134` and `:357-367` (`chooseTouchInBookPose`, `clearBookTouchOverride`).
- **Scenario:** On a Duo, mid-shift (glass 5 of 7, score 640), the player turns the phone to book pose. The run pauses and the "Turn me" card shows. The player taps **Use touch**. The canvas becomes a 468 × 669 column with `hasFold` false, which is a different `visibleRect` and `hasFold`, so `buildSession()` runs. A brand-new session starts at glass 1 with score 0, under the still-showing Pause card. Turning back to tabletop rebuilds it again. In a Daily this is another free retry (it compounds P1-2).
  - The same path on the **Results** route starts a new live session behind the card. It isn't a "live run", so nothing pauses it. With patience orders it times out to 3 Shorts about 40 s later, `handleFinished` records a junk run (it adds to `stats.runs` and `glasses`), and the results card is replaced by "Not quite".
- **Fix:** The world is identical on every canvas: size, crease, counter and pivot are constants, and only `visibleRect` and `hasFold` differ. In `updateCanvas`, rebuild the session only when `isAttract || session == nil`. Otherwise call `makeScene(newLayout)` and `scene?.reset(for: session.snapshot)` and keep the run. If the flat gate should follow the new `hasFold`, add a `GameSession.setUsesFlatGate(_:)` setter rather than rebuilding.

### P1-4. The screen can dim and lock during hinge-only play (suspect: verify on a Duo)
- **Where:** `isIdleTimerDisabled` appears nowhere in `Brim/`.
- **Scenario:** On a Duo the hinge is the only input, so a whole shift (60–120 s) can pass without a touch. Hinge reports are sensor events, not touches. Unless iOS 27.1 treats hinge motion as user activity, Auto-Lock (30 s minimum) dims and then locks the inner display mid-pour. The app goes inactive and the run is paused (`setAppActive(false)`). The code can't show whether hinge motion resets the idle timer, which is why this is marked suspect.
- **Fix:** In `GameController.setRoute` / `setPause` / `syncFeedbackPause`, set `UIApplication.shared.isIdleTimerDisabled = (route == .playing && !isAttract && !isPaused)`. It then turns off on menus, results, pause and background.

---

## P2: minor bugs, latent risks and polish

**Game state**
1. **A Daily that crosses UTC midnight is silently not scored.** `ProgressStore.swift:146` counts the run only when `day == today`, with `today` computed at finish (`GameController.swift:709`). A run started at 23:59 that ends at 00:00:30 gets neither `dailyCounted` nor `dailyOnFile`. The headline still says "Daily poured" (`ResultsView.swift:52`), there is no note (`:259`) and no leaderboard submit. **Fix:** also count when `day == today - 1` and the run started before midnight, or record against `result.mode`'s day without the `today` check (the start-time check from P1-2 covers abuse).
2. **Rush never ends if the player stops playing.** Patience timeouts are Shorts, which aren't strikes in Rush (`GameSession.swift:978-979`), and the jug never drains. An idle Rush runs forever. Harmless, but consider counting a patience-timeout Short as a strike in Rush, or ending after N consecutive idle Shorts.
3. **Touch control on a Duo soft-locks between 70° and 78°.** `GameController.swift:438-440` calls `requireFlat()` every frame while `hinge.isClosing`. The guard's below-78° latch only clears above 88° (`Input/TiltFilters.swift:117-121`). With touch on (Duo setting or book-pose override), a touch at 0 opens the gate, the next frame closes it again, and `resumeHold` resets each frame. Nothing pours and nothing is judged by stopping, and the gate card is hidden because `usesTouch` is true. **Fix:** skip that `requireFlat` when `usesTouch`.
4. **`isShut` can stick (suspect).** `GameController.swift:291-295` clears `isShut` only on a hinge sample ≥ 20°, and `PoseRule.pose` (`Layout.swift:78`) shows the cover card whenever `isShut` is true. If no sample arrives after the inner display comes back (the Squish lesson about still hinges), the open inner display keeps showing "Open me to pour". **Fix:** clear `isShut` when the canvas's long side is ≥ `coverMaxSide`.
5. **First launch on the cover display (suspect).** Before any hinge sample, a 466 × 678 cover canvas has `hingeSeen` false, so the full game runs there with touch. The 0.69 aspect also allows landscape (`OrientationLock.swift:27-31`), which gives a 326-pt-wide game column. Acceptable, but if the hinge API returns nil on the cover display, the cover card never appears.
6. **Mid-tilt rotation (suspect).** On a Duo the mask is `.allButUpsideDown`. If the lid is raised near vertical and the phone is tilted sideways, the interface may rotate to landscape. That shows the book card and pauses a live run. Consider requesting portrait whenever a run starts on a Duo. The `OrientationLock` header says this already happens "at launch on a Duo", but no code does it.

**Lifecycle, feedback and performance**

7. **Battery and thermal cost on menus.** On Home, Venues and Settings (where the scene is fully covered):
   - The attract SpriteView keeps rendering at 120 fps (`RootView.swift:159`).
   - The audio engine keeps rendering the idle bed.
   - Core Haptics runs a looping continuous player at intensity 0 with `isAutoShutdownEnabled = false` (`Feedback/BrimHaptics.swift:128, 189-209`).

   **Fix:** set `isPaused` on the SpriteView or scene on Venues and Settings, and stop the flow player and enable auto-shutdown outside `.playing`.
8. **Per-step allocations in Core.** Every sub-step, `JugGeometry.head` (`GameSession.swift:363`) transforms the outline and bisects `levelForArea` 34 times, and each `clipBelow` allocates (`JugGeometry.swift:79-90, 223-240`). Each frame, `makeJugState` does the same again (`GameSession.swift:1434`). `integrateParticles` allocates `kept` every sub-step (`:527`). That is roughly 100 small heap allocations per 120 Hz frame. **Fix:** cache the rotated outline per angle, reuse scratch buffers, and lower the bisection to about 20 iterations.
9. **Scene paths rebuilt every frame.** `SceneStream.swift:95-179` (three ribbons over up to about 1,200 smoothed points) and the jug liquid (`SceneJug.swift:384`) rebuild their SKShapeNode paths every frame, which re-tessellates them. Profile this on a Duo.
10. **Stale one-shots replay after the engine restarts (suspect).** While the engine is stopped (an interruption) with sound still on, `BrimAudioEngine.play` (`:71-75`) keeps queueing one-shots into the 512-slot ring (`PourSynth.swift:348-355`). On restart they drain 128 per callback and play as a burst. **Fix:** drop `play` when `!engine.isRunning`.
11. **Restart churn during a call (suspect).** During an active interruption (phone call), `heal()` (`BrimAudioEngine.swift:96-100`) retries `engine.start()` every second. After 4 failures, `rebuild()` creates a new AVAudioEngine every 5 s (`:193-200`). **Fix:** skip `heal` while an interruption is in progress (track `.began` and `.ended`).
12. **Streak label textures never evicted.** `SceneArt.streak` caches one texture per streak value (`SceneArt.swift:415-418`). Memory grows with the longest Rush streak.
13. **Backdrop cache size.** It holds up to 3 textures of about 2010 × 2856 px (about 23 MB each) per scene (`GameScene.swift:712-728`). Lower the cache to 1–2, or render at 2×.

**Persistence**

14. **A corrupt save is overwritten.** If the progress blob fails to decode (for example, the root isn't an object), `ProgressStore.init` (`:220-225`) silently starts fresh, and the next `save()` overwrites the old data. **Fix:** copy the undecodable data to `brim.progress.v1.corrupt` before replacing it.
15. **Future fields could wipe stats or Daily history.** `LifetimeStats` and `DailyRecord` use synthesized `Decodable` (`ProgressStore.swift:7-21`). Adding any field later without a default-tolerant `init(from:)` makes `try?` at `:200-201` drop all lifetime stats or all Daily history. Add tolerant decoders now.
16. **Reset progress reopens today's Daily.** It erases `daily`, so today's scored Daily can be replayed and submitted again. Consider keeping `daily` across a reset.

**Game Center**

17. **Queued scores can be lost or land on the wrong day.** `flush()` (`GameCenterManager.swift:89-97`) clears the pending score queue before submitting, so an offline or failed submit loses the score. A Daily score queued offline and flushed after midnight UTC lands on the next day's recurring leaderboard. **Fix:** clear entries in the completion handler, and drop Daily entries whose day ≠ today.

**App Review and Release hygiene**

18. **Release log line.** `GameScene.swift:293-296` prints `BRIM-T frame 120` unconditionally, once per scene. Wrap it in `#if DEBUG`.
19. **Review notes don't match the build.**
    - §2d quotes the book card as "Stand me up like a little laptop", but the build says "Turn me so the fold runs side to side, then lay me flat." (`PoseCards.swift:90`).
    - The Duo touch setting ships (`SettingsView.swift:35`), so add the line `review-notes.md:78` asks for.
    - "Release builds contain no debug or demo modes" is true in behaviour (Demo code is compiled but unreachable).
20. **Mac availability.** iPhone-only apps are offered on Apple-silicon Macs by default. Decide in App Store Connect; nothing in the code blocks it, and haptics and the hinge degrade safely.

**UI copy and accessibility**

21. The closing-pause card says "Your shift is paused" in Rush and Daily too (`PlayOverlays.swift:449`).
22. The HUD strike cups' VoiceOver label says "N of 3 spills", but Shorts also strike in shifts and Daily (`PlayOverlays.swift:125`).
23. Home's Daily button number and state (`HomeView.swift:18`) don't refresh at UTC midnight while Home stays open, so the button can show yesterday's "Done" and then start today's Daily.
24. **Dynamic Type isn't supported, and nothing breaks.** All fonts are fixed `.system(size:)` (`BrimTheme.swift:23-27`). `docs/appstore/accessibility.md:18` says "menus scale"; they don't. The nutrition label is set to "No", so there is no false claim, but correct the doc.
25. **No sign of practice in a Daily replay.** Starting a Daily that is already on file looks exactly like the scored run until the results ("Practice pour"). Add "Practice" to the HUD chip when `store.dailyRecord(day:) != nil`.

---

## Verified clean (no action)
- `GameSession.step` clamps dt to ≤ 1/30 and handles non-finite dt and tilt. Every `sqrt` and division in fall-time and telemetry is guarded. `CoreRNG.pick` is only called on non-empty pools.
- The jug can still pour at the lowest fill that isn't treated as empty: pour threshold is about 77° of jug angle at fill 0.025, below the 130° maximum. So neither shifts nor Rush can soft-lock on an unpourable remainder.
- A run that finishes while paused can't happen early: the session doesn't step while paused, and `pendingFinish` keeps ticking behind the flat gate.
- `requireFlat` during arrival and leaving freezes patience and conveyor belts correctly. Practice and attract never finish (no strikes, the jug auto-refills).
- Audio: SPSC ring with atomics, and no ARC, locks or allocation on the render thread. Observers use `queue: .main` with `assumeIsolated`. Haptic `stoppedHandler` and `resetHandler` hop to `@MainActor` and restart.
- Backgrounding mid-pour: user pause, then `setPaused(true)`, which sets the idle bed, silences one-shots and zeroes haptic flow. Touch is cancelled. Resume re-arms the flat gate and resets the hinge filters.
- Game Center never presents its sign-in view controller (no launch popup) and is disabled in demo runs. VoiceOver labels are present on every icon-only button (Settings, Pause, Back).
