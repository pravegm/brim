# 02 — The iPhone Duo hinge as a real-time game input

*25 Oct 2026. Built from the Squish repo (sister app, read-only) and web research. The only real-device hinge data is the Squish founder's log from 24–25 Oct.*

**Tags:**
- **[Duo]** real iPhone Duo log (Squish Tuning Lab CSV)
- **[Doc]** Apple docs, a Tech Talk or Apple staff
- **[Sim]** the Xcode 27.1 simulator
- **[R]** third-party report
- **[G]** our inference
- **UNVERIFIED** nobody has measured it

---

## Design constraints (summary)

| Constraint | Design for | Confidence |
|---|---|---|
| Angle scale | 180° = flat. A hand at rest reads ~175° | [Doc]/[Duo] |
| Accuracy | ~±5° (Federighi). Apple publishes no figure | [R] |
| Core play band | **170°→60°**. Below ~55° "may be dark". ≤10° = shut | [G] |
| Inner display off when closing | **UNVERIFIED.** Still lit below 85° [Duo]. Founder's rough guess ~45° (not logged). Simulator reports: 55° or 20° | mixed |
| Reopen from shut | Cover stays lit to **~150°**. Handover takes 1–2.5 s | [Sim] |
| `status == .closed` | **A posture, not "shut."** Sets at ~85° when closing, clears at ~21° on reopen | [Duo] |
| Shut noise | 0–6.5° of jitter. Shut ≤10°, release ≥15° | [Duo] |
| Update rate | **25–30 Hz while moving**, 100–200 ms gaps, **no events while still**. "System policy" | [Duo]/[Doc] |
| Latency | **Unknown.** Samples carry no timestamp | UNVERIFIED |
| Hand speed | Slow 25–60°/s. Fast close 175→0° in 0.37 s (~470°/s) | [Duo] |
| Trustworthy steps | ~20–25 across 170→60° | [G] |
| Pose API | None. Combine angle, size class, the `.division` region and CoreMotion | [Doc] |
| IMU half | **UNVERIFIED**, undocumented | — |
| Inner canvas | 669×951 pt seated / 951×669 pt book @3x. 40 pt crease band. 120 Hz ProMotion | [Doc]/[R] |
| Orientation | The inner display ignores orientation locks. Handle both fold axes | [Doc] |
| Force inner display | **Not possible.** The system moves the app between displays | [Doc] |
| Ergonomics | 254 g, two-handed to open, free-stop hinge, magnet at close, no fold-cycle rating | [R] |
| CI | The simulator only, driven by the private-API `hinge` CLI. Works on GitHub `xcode-27` | Squish |
| Non-Duo | `hinge == nil` before any reading means no hinge. Duo-only games *may* pass review | [Doc] |

---

## 1. Usable angle range and hysteresis

**API [Doc].** SwiftUI `onHingeChange(isEnabled:_:)` gives `(old, new)` `DeviceHingeContext`, whose `hinge: DeviceHinge?` holds `angle: Angle` and `status`.
- `status` is a struct, so a `switch` needs `default:`.
- UIKit `UIHingeInteraction` gives `UIHinge.angle` in **radians**, and its status has `.unknown`.
- The callback fires with the initial state, then on each change.
- While `isEnabled == false`, updates are dropped, not queued.
- `nil` means no hinge, or the view has left a hinge-providing hierarchy.
- Apple: use the hinge "for interactions and effects", and reserved regions for layout.

**Closing [Duo].**
- `.closed` sets at ~84–88° on a slow close and 76–86° on a fast one, while the inner display is **still lit**.
- Squish 1.0 (3) treated `.closed` as shut. It sealed "at the wrong angle", and the founder called it "jumpy, out of sync".
- **Never use `status` for gameplay thresholds. Use the angle.**
- The display-off angle was not captured. Squish's config says "~45° (the founder)" next to "UNMEASURED on hardware".
- Simulator reports conflict (20° vs 55°), and the switch is path-dependent ([hinge CLI](https://github.com/artemnovichkov/hinge), [simulator skill](https://github.com/WhitenWhiten/iphone-duo-simulator-skill)).

**Opening.**
- `.closed` clears at ~21° [Duo].
- In the simulator the cover stays lit to ~150° and a system blur covers the switch.
- A reopen "reveal" is a **discrete event**, not a ramp. Squish fires it at "reopen past 25°" or "inner display is back", whichever comes first.

**Hysteresis.**
- Shut ≤10°, open again ≥15°. A single threshold chattered [Duo].
- Use 4–6° bands for gameplay states.
- DuoBird flaps at +10° above the running minimum and re-arms after a 5° fold-back. Bend uses 6° ([Devpost](https://devpost.com/software/bend)).

**Bands [G]:**

| Band | Use |
|---|---|
| 180–165° | Rest/dead zone (Crate: 4% dead zone; Duogami arms at ≥155°) |
| 165–60° | All visible, continuous play. Viewing degrades below ~90° as the halves face each other |
| 60–15° | Blind. Samples *may* still arrive (UNVERIFIED). Audio/haptic follow-through only |
| ≤10° | Shut: one event, and the app is now on the cover display |

**Lifecycle traps [Duo].**
- Returning to the foreground with the phone open and still may produce **no** event, which leaves stale state. Squish toggles `isEnabled` off and on (30 ms) on every activation to force a reading (`HingeReader.swift`).
- Ignore input for ~1.5 s after activation (Crate).

---

## 2. Update rate, latency, smoothing

**Measured [Duo]:** 25–30 Hz while moving (20–60 ms intervals), with occasional 100–200 ms gaps and nothing while still. The simulator gives about the same (~30 Hz).

**What Apple says [Doc]:**
- "Rate and granularity… are system policy… don't depend on a particular update frequency or precision" ([UIHinge.angle](https://developer.apple.com/documentation/uikit/uihinge/angle)).
- Asked directly about low-latency hinge gameplay, an Apple engineer said there is no guaranteed frequency and suggested smoothing such as a spring. Whether samples are timestamped got no answer ([forum 847866](https://developer.apple.com/forums/thread/847866)).

**Latency is UNVERIFIED.** The stream is pre-smoothed by the system [R], which implies some lag. Plan for ~10 Hz under thermal or Low Power load [G].

| Use | Verdict [G] | How |
|---|---|---|
| (a) Slow analog control | **Good**, the sweet spot | 1–2° per sample at slow speeds, and the free-stop hinge holds any angle. Use ~20 coarse zones or "more/less", never "hit 47°" |
| (b) Fast snaps/flaps | **Good as events** | Detected within 1–2 samples (≈35–70 ms). Use min-tracking with a 10° trigger and 5° re-arm. Keep snaps in the open range (100↔170°), because snaps toward shut land on the cover display. Don't read the trajectory inside a snap |
| (c) Rhythm timing | **Weak** | 0–40 ms quantisation, 100–200 ms gaps, unknown latency. Windows ≥ ±100 ms (±60 ms "perfect"). Interpolate the threshold-crossing time between samples, schedule on the audio clock, and calibrate the offset per player. Prefer forgiving call-and-response |

**Squish's smoothing after real-device feedback** (`Core/HingeTracker.swift`, `Filters.swift`, `PressConfig.swift`). The first build's One-Euro plus spring felt "steppy, not in sync."
1. **Visuals:** an alpha-beta tracker (α 0.75, β 0.35) sampled at display rate.
   - It extrapolates one sample interval at the tracked velocity, then eases to a stop.
   - Once reports stop, it glides onto the last raw reading (50 ms).
   - Corrections blend in over ~40 ms. Jumps > 90° snap.
   - Zero lag at steady speed, stable from 5 to 120 Hz.
2. **Logic:** a One-Euro filter (minCutoff 2.0, β 0.12, dCutoff 1.5), ~0.5° behind at 20°/s, with dt clamped to 1/240–0.2 s.
3. A critical spring (ω 40) only for jumps.
4. Irreversible events fire only from the filtered *measured* angle, never from prediction.

**Rule:** don't stack heavy filters on a pre-smoothed stream. Stamp samples with `CACurrentMediaTime()` on receipt.

---

## 3. Pose and real gravity

**No pose API [Doc].**
- "There's no single system-provided pose value" ([forum 847644](https://developer.apple.com/forums/thread/847644)).
- There is also no "is this a Duo" API ([847775](https://developer.apple.com/forums/thread/847775)).
- Apple's names: **book** (inner display in landscape), **tent** (outer display faces you), **seated** (inner display in portrait, one half on a surface: our "tabletop"), and standing. No angle ranges are published ([MacObserver](https://www.macobserver.com/news/iphone-duo-posable-positions-rebuilt-standby-what-apple-documents/)).

**Fold axis.**
- Read it from `reservedRegions(kind: .division, options: .includeInactive)`: a frame wider than tall means a horizontal hinge (seated), taller than wide means book.
- When flat, the region is inactive with zero width but still has its line.
- Activation lagged ~1 s and happened anywhere from 98° to 173° [Sim]. **Lay out once per canvas size**, never on activation.

**CoreMotion, iOS 27 [Doc, as quoted in Squish's Apple-docs review; the page didn't render for me].**
- Set `CMMotionManager.deviceMotionBody` to a `UIView`. Gravity and attitude are then transformed to that view's orientation.
- On the Duo it "identifies which display your app occupies… and detect[s] which face is up."
- **Which half holds the IMU is UNVERIFIED.** Squish never ran its Week-0 check and ships no CoreMotion.
  - **5-minute device test [G]:** lay half A flat and fold half B from 180° to 90°. If gravity stays constant, the IMU is in A. If it rotates ~90°, it's in B.
  - The other half's gravity is then the measured vector rotated about the hinge axis by (180° − θ). Errors stack (±5° from the hinge plus IMU error).

**Classifiers (Squish spec, never shipped) [G]:**
- **Seated:** the base half within ~30° of level.
- **Handheld:** the base pitch β.
- **Tent:** a partial angle with the outer display facing the user. An app can't draw on the outer display while open, except through camera or AlarmKit accessories [Doc].
- Ignore gravity during strong haptics (the HIG says haptics disturb the gyroscope).

---

## 4. Wear and ergonomics

**Facts [R]:**
- 254 g.
- "Very much a two-handed operation" to open ([9to5Mac](https://9to5mac.com/2026/10/21/iphone-duo-review/)). PetaPixel found no comfortable one-handed configuration ([PetaPixel](https://petapixel.com/2026/10/21/iphone-duo-review-a-compromise-but-not-compromised/)).
- Variable torque, a free-stop hinge, and a magnet array that snaps it shut.
- A robot made 32,640 folds: slightly stiffer by gauge, no failure ([MacRumors](https://macrumors.com/2026/10/21/iphone-duo-fold-test-hinge/)).
- **Apple publishes no fold-cycle rating.** Samsung rates its Folds at ≥200k.

**Review [Doc]:**
- 2.4.2: no use that risks "damage to the device" or "excessive heat".
- 1.4.5: don't urge use "that risks physical harm".
- No guideline mentions the hinge.

**Comfortable motions [R/G]:**
- **Seated (best):** the base rests on the table and one finger moves the upper half. Precise and weight-free. This is Squish's hero pose.
- **Book, two hands:** natural for flaps and pumps, but both halves move, so the view shifts.
- **One hand holding one half:** possible but jerky, given the weight and torque.
- The magnet zone (< ~15–20°) grabs the lid, so it can't be used for analog control.

**Budget [G]:**
- Favour partial strokes in 170↔90°: no magnet, no display switch, no full cycles.
- A flap per second is ~180 strokes per 3-minute run. Heavy play could reach the 32k-test order of magnitude in a year.
- Add rests between levels, offer a touch mode, and never reward slamming. Squish coaches "slowly" above 250°/s.

---

## 5. Rendering across the fold

**Canvas [Doc/R]:**
- Inner 669×951 pt seated, 951×669 pt book. Outer 466×678 pt. ~6.02 pt/mm.
- Rounded corners, and `.occlusion` regions (Dynamic Island, cameras) on **both** displays.
- You must build with the iOS 27.1 SDK or the app is letterboxed.
- The HIG asks games to be "playable in every device pose" and to change aspect ratio rather than letterbox.

**Crease:**
- The `.division` frame includes Apple's margins. Squish used a fixed 40 pt (~6.6 mm) band.
- Keep controls and critical objects out of it, and fill it with art.
- When folded, anything crossing it looks bent.
- Squish's rule: draw content *on* each half; "nothing is ever drawn in the air between the halves."

**120 Hz:**
- Set `CADisableMinimumFrameDurationOnPhone = YES` and request 120 fps.
- Fall back to 60 Hz at thermal `.serious`. Reviewers report the Duo runs hot under load [R].

**How Squish split the halves:**
- **Bottom:** a RealityKit `ARView` with an off-axis homography warp (`CATransform3D`), so objects stand out of the glass.
- **Top:** a 2D Core Animation stack.
- **Overlay:** a SwiftUI bezel.
- One update per frame drives all three. The views are parked while the inner display can't be seen (`FoldRenderGate`), and a "blind clock" keeps audio and haptics running.
- Two ARViews were rejected because an entity can't live in two scenes.

**Recommendation for a 2D game [G]:**
- Use **one SpriteKit `SKView`** (or one `MTKView`) over the full inner canvas.
- Give it two root nodes, one per half, positioned from the division frame, plus a decorative crease node.
- Sample the hinge tracker in `update(_:)`.
- Host it in UIKit with `UIHingeInteraction` (convert from radians), or put `onHingeChange` on the parent of a SwiftUI `SpriteView`.
- Use Metal only for custom shaders or heavy particles. SwiftUI `Canvas` + `TimelineView` suits light scenes only.

---

## 6. Simulator and CI (Squish)

**Pipeline (`duo.yml`, `ci/duo-screenshots.sh`, `docs/DUO-CI.md`):**
1. GitHub `xcode-27` runner, Xcode 27.1.
2. Download the **iOS 27.1 runtime** (7.85 GB, Duo-only) with `xcodebuild -downloadPlatform iOS`. Retry, because the first try can fail with Code=41. Cache it (~7.9 GB of the 10 GB quota) and import it.
3. `simctl create … iPhone-Duo … iOS-27-1`, booted in parallel with the build.
4. **Hinge:** [`artemnovichkov/hinge`](https://github.com/artemnovichkov/hinge) runs inside the simulator and posts Device Hub's private HID event.
   - `hinge sweep A B secs` streams at 60 Hz, giving realistic `onHingeChange` traffic.
   - **This is what worked in production runs** (store set, previews).
   - Fallbacks, probed automatically: duo-fold-control (set-only, ~1–1.5 s per call) and foldctl. Appium WDA ≥16.14 has `setSimulatedHingeAngle` (not wired).
5. The app is driven by **launch-argument demo modes** and prints log markers the script waits on. It can save its own screenshots.

**Failures and gotchas:**
- `simctl io screenshot` needs `--display`, and the names vary (`LCD`/`LCD-1`, `primary`/`primary-1`, 1/3). Capture both panels and keep the lit one.
- **Never run `simctl io … screenConfig`.** It crash-loops SpringBoard.
- Allow 2.5 s to settle after each move.
- The simulator sometimes stops following the hinge; reboot it.
- `hinge` sometimes drops a move; retry up to three times.
- There is no CLI rotate. Squish rotates in-app (DEBUG `requestGeometryUpdate`), which needs `UIRequiresFullScreen`.
- Taps on the inner display are unreliable through XCUI. `XCUIScreen.main` is the cover display.
- In the simulator, `.closed` can stick to ~150° on reopen, unlike the real device.
- Nothing in the simulator gives haptics, latency, display-off angles, thermals or ergonomics.
- Each run takes ~25–55 macOS minutes. The tools rely on private APIs, so an Xcode update can break them.

**For us:**
- Commit real-device hinge CSVs (receipt-timestamped) as fixtures, and replay them at 30, 15 and 10 Hz in unit tests (see Squish's `PressEngineTests.realHingeLogSealsOnlyWhenShutAndRevealsOnReopen`).
- Use the simulator for screenshots and smoke tests only.
- Device builds go through TestFlight CI.

---

## 7. Fallback for non-folding iPhones

**How Squish does it:**
- **One engine.** `PressEngine.setVirtualAngle(_:at:)` feeds the same `ingestSample` path as the real hinge, so thresholds fire at the same fraction of travel on every device.
- **Touch:** a `DragGesture(minimumDistance: 0)` maps downward translation to virtual degrees.
  - It's scaled to the room below the finger, so a press always completes.
  - Lifting the finger springs the virtual hinge open.
- **Accessibility:** a VoiceOver adjustable action. A "Press without folding" setting offers touch on a Duo too.
- **Detection (`HingePresence`):**
  - `nil` before any reading this launch means no hinge, so fall back at once.
  - **After a hinge has been seen, never fall back on `nil`**, because transient nils happen at display handovers.

**What Apple says [Doc]:**
- There is no hinge capability key, and Apple generally discourages Duo-exclusive apps.
- For games whose core mechanic needs the hinge, DTS suggests a graceful "this needs iPhone Duo" screen, with no approval guarantee ([forum 847857](https://developer.apple.com/forums/thread/847857)).
- Keyboard extensions get no hinge updates ([847490](https://developer.apple.com/forums/thread/847490)).

**Recommendation [G]:** choose a core verb that maps naturally to a vertical drag or pinch, and feed the same engine with the same thresholds.

---

## Day-one checks on our own Duo

1. The display-off angle (slow and fast close) and the reopen switch angle.
2. Whether samples arrive on the cover display.
3. End-to-end latency, by filming the screen and hinge at 240 fps.
4. Which half holds the IMU.
5. The rate under Low Power and thermal load.
6. Taptic strength (the founder found it weak).

## Sources

**Squish (read-only):**
- `research/05-hinge-ux.md`
- `design/FOLD-PRESS.md` (§4, §9, §9.8.1)
- `design/research/APPLE-DUO-GUIDE.md`
- `docs/{DUO-CI,HANDOVER,PROJECT-LOG}.md`, `CLAUDE.md`
- `Squish/App/HingeReader.swift`
- `Squish/Core/{HingeTracker,Filters,HingePresence,PressConfig,PressEngine}.swift`
- `Squish/UI/RootView.swift`

**Apple:**
- [UIHinge.angle](https://developer.apple.com/documentation/uikit/uihinge/angle) · [onHingeChange](https://developer.apple.com/documentation/swiftui/view/onhingechange(isenabled:_:)) · [UIHingeInteraction](https://developer.apple.com/documentation/uikit/uihingeinteraction)
- [deviceMotionBody](https://developer.apple.com/documentation/coremotion/cmmotionmanager/devicemotionbody)
- [HIG: iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [Tech Talk 111464](https://developer.apple.com/videos/play/tech-talks/111464/)
- Forums [847644](https://developer.apple.com/forums/thread/847644), [847866](https://developer.apple.com/forums/thread/847866), [847857](https://developer.apple.com/forums/thread/847857), [847775](https://developer.apple.com/forums/thread/847775), [847490](https://developer.apple.com/forums/thread/847490)
- [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

**Code:**
- [iPhone-Duo-by-Examples](https://github.com/artemnovichkov/iPhone-Duo-by-Examples): Hinge Angle, Angle History, Tabletop & Book, Avoid the Crease. Simulator-observed, "not documented guarantees."
- [hinge](https://github.com/artemnovichkov/hinge), [duo-fold-control](https://github.com/tosbaha/duo-fold-control), [foldctl](https://github.com/tatsuz0u/foldctl), [WDA #1287](https://github.com/appium/WebDriverAgent/pull/1287)
- DuoBird, Duogami (artemnovichkov) · [Crate](https://github.com/odoisveryverygood/crate-duo) · [Bend](https://devpost.com/software/bend)

**Press:**
- [9to5Mac review](https://9to5mac.com/2026/10/21/iphone-duo-review/), [PetaPixel](https://petapixel.com/2026/10/21/iphone-duo-review-a-compromise-but-not-compromised/), [MacRumors fold test](https://macrumors.com/2026/10/21/iphone-duo-fold-test-hinge/), [MacObserver](https://www.macobserver.com/news/iphone-duo-posable-positions-rebuilt-standby-what-apple-documents/), [Federighi ~5°](https://9to5mac.com/2026/09/29/craig-federighi-on-how-apple-helps-developers-make-the-most-of-the-iphone-duo-video/)
