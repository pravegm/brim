# QA-5: final pre-submission audit (QA lead, fifth pass)

Scope: everything since round 9 (`33162e9..0e48224`): "Glasses on the sharp half" (`RootView.turnsRound`/`insets`/
`deferredEdges`, `OrientationLock` `duoMask`/`adoptMask`/`requestPortrait`/`settleTabletop`/`requestFailed`/
`turnStatus`, `DemoMode.flip`, `SettingsStore.sharpSide`, Settings), the Release-only removal of `UIRequiresFullScreen`,
and the fold-region read. I also swept the whole app for submission blockers. I didn't re-report anything already in
QA-1 to QA-4 or REVIEW-7.

This is a read-only audit. It draws on the code, Duo CI run 40314293608 (the `turned` log and frames duo-10/11/12) and
the TestFlight run 40321571132 log.

## Verdict

**No P0. Two P1s. Fix both before submitting; neither one blocks TestFlight.**

- **P1-1 (main risk).** Release now lets iOS run Brim in Split View or Slide Over on the Duo's inner display, and in
  every one of those sizes Brim shows the cover card ("Open me to pour") on an open phone. A live run also gets the
  closing pause. A Split View half (≈475 × 669) is almost the same size as the cover display (466 × 678), so the canvas
  alone can't tell them apart. The fix has to read the screen size.
- **P1-2.** On a Duo, every screen is now drawn upside down for someone holding the phone the usual way. Only a Settings
  footnote explains it, and the App Review notes don't mention it.
- **Only the fallback is proven.** The Duo simulator still refuses upside down, because Debug keeps
  `UIRequiresFullScreen` (log: "Requested: portraitUpsideDown; Supported: portrait, landscapeLeft, landscapeRight"). So
  CI only proves the fallback path, where Brim draws the game turned round itself. The path where iOS itself runs
  upside down (Release, build 12) is untested until the founder's Duo session.

---

## P0

None verified.

---

## P1

### P1-1 (verified in code): Split View, Slide Over and resized windows show "Open me to pour", and a live run gets the closing pause

**Where:**
- `Brim/UI/Layout.swift:79-81` (`PoseRule.pose`): once a hinge has been seen, any canvas whose long side is < 760 is
  `.cover`.
- `Brim/UI/Layout.swift:89-93` (`hasFold`).
- `Brim/UI/Layout.swift:97-101` (`playRect`): it only makes a column for landscape canvases.
- `Brim/UI/RootView.swift:122-133, 183-192`.
- `Brim/App/GameController.swift:530-539` (`setPose`) and `:622-632` (`refreshInputMode`).

**What happens** (inner display 951 × 669 in landscape; the fold is vertical at x 456…496, per CI "fold active 456,0
40x669"):
- **A 50/50 split** gives a canvas of about 475 × 669. Its long side, 669, is under 760, so the pose is `.cover` and
  `CoverView` shows "Open me to pour" on an open phone.
- **A run that was live** goes through `setPose(.cover)` → `engageClosingPause`. When the player goes back to full
  screen, the "Open me up and lay me flat" card stays up until a hinge sample of 100° or more arrives, or the player
  taps Resume. A still hinge sends no samples, so in practice it waits for Resume.
- **A 1/3 split (≈317 × 669) or Slide Over (≈320 × 640)** also shows `.cover`.
- **A 2/3 split or freeform window (e.g. 634 × 669)** shows `.cover` too. Even once it is classed as play, the canvas is
  wider than the world's 0.704 aspect, so `WorldLayout.make` crops it vertically: scale 0.946, visible world y 122…829.
  The counter (y 104) and the glass bases are off screen, and so is the HUD band.
- **The canvas can't tell a split half from the cover display:** a split half is 475 × 669 and the cover is 466 × 678.
  The rule must compare the canvas with the window scene's screen.

**Repro:** on the inner display in landscape, open Safari, then drag Brim in from the Dock (or use the multitasking
menu) into Split View. Brim's half reads "Open me to pour". Do it mid-shift: back in full screen, the run sits on the
closed-pause card.

**Right behaviour:**
- A window smaller than its screen is a **windowed phone canvas**: pose `.play`, no fold, touch input, inside a
  world-aspect column. This is the tested iPhone path.
- Hinge play makes no sense in a shared window. In landscape the fold runs down the divider, and lifting a half tips
  the other app too.
- The cover card only appears on the cover screen itself, or when the phone is shut.

**Fix:**

1. `Layout.swift`: add the windowed rule and pass the screen in. Existing callers and tests keep compiling through the
   default `nil`.
```swift
/// A multitasking window (Split View, Slide Over, a resized window) smaller than its screen. Pure.
static func isWindowed(canvas: CGSize, screen: CGSize?) -> Bool {
    guard let screen, screen.width > 10, screen.height > 10, canvas.width > 10, canvas.height > 10 else { return false }
    let c = (min(canvas.width, canvas.height), max(canvas.width, canvas.height))
    let s = (min(screen.width, screen.height), max(screen.width, screen.height))
    return c.0 < s.0 - 2 || c.1 < s.1 - 2          // sorted sides: immune to rotation order
}

static func pose(canvas: CGSize, hingeSeen: Bool, isShut: Bool, bookTouchOverride: Bool,
                 screen: CGSize? = nil) -> DevicePose {
    if hingeSeen && isShut { return .cover }
    let display = screen ?? canvas                  // the cover is a SCREEN size, not a window size
    if hingeSeen && display.width > 10 && display.height > 10 && max(display.width, display.height) < coverMaxSide {
        return .cover
    }
    if isWindowed(canvas: canvas, screen: screen) { return .play }
    if canvas.width > canvas.height && !bookTouchOverride && (hingeSeen || looksLikeDuoInner(canvas)) {
        return .standUp
    }
    return .play
}

static func hasFold(canvas: CGSize, hingeSeen: Bool, screen: CGSize? = nil) -> Bool {
    if isWindowed(canvas: canvas, screen: screen) { return false }
    guard canvas.height > canvas.width else { return false }
    if hingeSeen { return max(canvas.width, canvas.height) >= coverMaxSide }
    return looksLikeDuoInner(canvas)
}

static func playRect(in canvas: CGSize) -> CGRect {
    // A column whenever the canvas is wider than the world (0.704), not only in landscape: 669 × 951 stays full.
    guard canvas.width > (canvas.height * WorldLayout.worldWidth / WorldLayout.worldHeight).rounded(.up) else {
        return CGRect(origin: .zero, size: canvas)
    }
    let width = min(canvas.width, (canvas.height * 0.70).rounded())
    return CGRect(x: ((canvas.width - width) / 2).rounded(), y: 0, width: width, height: canvas.height)
}
```

2. `OrientationLock.swift`: add a screen reader next to `windowSafeArea()`. It reads the key window's `windowScene.screen`
   (the window, not `UIScreen.main`, so it follows the cover↔inner handover).
```swift
static func windowScreenSize() -> CGSize? {
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    return (windows.first(where: { $0.isKeyWindow }) ?? windows.first)?.windowScene?.screen.bounds.size
}
```

3. `RootView.swift`:
   - Add `@State private var screenSize: CGSize?`.
   - Set it in `refreshWindowInsets()`, both right away and in the 350 ms re-read, the same way as `windowInsets`.
   - Add `.onChange(of: screenSize) { _, _ in handleCanvas(canvas) }` beside the other `onChange`s at `:115-117`.
   - Pass `screen: screenSize` into `PoseRule.pose` (`:127`) and `PoseRule.hasFold` (`:132`).
   - In `handleCanvas`, first line:
     `controller.setWindowed(PoseRule.isWindowed(canvas: canvas, screen: screenSize))`
     That call must come before `setPose` and `updateCanvas`, so the input is already right when the session adopts the
     canvas. On the way back to full screen, `updateCanvas`'s `newLayout.hasFold && !hadFold && !usesTouch` branch then
     closes the flat gate as designed.

4. `GameController.swift`:
```swift
@Published private(set) var isWindowed = false
func setWindowed(_ on: Bool) {
    guard on != isWindowed else { return }
    if on && isLiveRun && demo == nil && !isClosedPaused { setUserPaused(true) }   // never switch input under a pour
    isWindowed = on
    refreshInputMode()
}
```
   In `refreshInputMode` (`:624`):
   `let touchWanted = !hasHinge || settings.touchOnDuo || bookTouchOverride || runTouchOverride || isWindowed`.

5. **Very narrow windows.** At widths under 360 pt (a 1/3 split or Slide Over), the compact Home row
   (`HomeView.swift:134-141`: 3 × 74 + spacing + padding = 263 pt) leaves Play about 55 pt. Either check this with the
   CI key below, or, while `isWindowed && canvas.width < 360`, show a one-line card instead of the HUD: "Make Brim wider
   to pour".

6. **Tests and CI:**
   - `PoseRule.pose(canvas: 475×669, hingeSeen: true, …, screen: 951×669) == .play` and `hasFold == false`.
   - `pose(canvas: 466×678, …, screen: 466×678) == .cover`.
   - `playRect(in: 634×669).width == 468` and `playRect(in: 669×951) == full`.
   - A DEBUG demo key `window=WxH` that frames RootView's content at that size inside the full screen, with its
     `screenSize` set to the real screen, plus one Duo frame each for 475×669, 317×669 and 634×669.

### P1-2 (verified in code): on a Duo, the whole app is upside down for a phone held the usual way, and only a Settings footnote says why

**Where:**
- `Brim/UI/RootView.swift:162-175`: `turnsRound` applies to every route with `pose == .play && hasFold`: Home, Venues,
  Settings, Results and play.
- `Brim/App/OrientationLock.swift:59-62`: `settleTabletop` asks iOS for upside down on every `handleCanvas`.
- `Brim/UI/SettingsView.swift:40-41`: the only explanation.
- `docs/appstore/review-notes.md:26` (§2a).

**What happens:**
- On a Duo with defaults, Brim's content is fixed so that the phone's natural top sits at the drawn bottom.
- Pick the Duo up open, the usual way round. Either iOS forces upside down (Release, request honoured) or it keeps
  upright and Brim draws the content turned round. Either way, Home reads upside down until the player turns the phone.
- A first-time player, or an App Review tester who has a Duo, sees what looks like a rotation bug on the first screen.
  Nothing in the app says to turn the phone. The review notes say "lay it on a table … the jug is drawn on the far
  half", and that's only true once the tester has turned it round.
- The design is defensible: one orientation everywhere, so there's no spinning the phone between menu and play. It is
  only explained in Settings.

**Fix:**
1. **Review notes §2a:** add the line *"On iPhone Duo the inner screen runs upside down by default (Settings > 'Glasses
   on the sharp half'), because iOS blurs one half for about 2 seconds whenever a fold starts and this keeps the glasses
   sharp. If the game looks upside down, turn the phone round."*
   - That is about 230 bytes, and the block is at 3,967 of 4,000. To make room, drop §8's "All sound is synthesized in
     the app; there are no recorded or licensed assets." (about 75 bytes), shorten §2c's second sentence, and trim §1's
     last bullet.
   - Re-count the bytes and add a row to the "Check against the build" table.
2. **In the app:** add a one-time hint on the Duo, using the existing hint system (`HintKind`, `store.markHintSeen`).
   Show it on Home the first time `turnedRound || OrientationLock.interfaceIsUpsideDown()` holds with `hasFold`:
   *"Upside down on purpose: turn your Duo round. iOS blurs the other half when you fold, so the glasses live here."*
   Dismiss it on a tap, and never show it again.

---

## P2

1. **Diagnostics ship in Release Settings.**
   - **Where:** `SettingsView.swift:87-91` shows `OrientationLock.turnStatus()` to every Duo owner. In the fallback
     state it reads "Screen: upright, game drawn turned round · iOS turn: refused: None of the requested orientations
     are supported by the view controller. Requested: portraitUpsideDown; Supported: …" (`OrientationLock.swift:68`
     stores `localizedDescription`).
   - **Staleness:** it is computed once per body evaluation and observes nothing, so it can go stale.
   - **Fix:** show it only in DEBUG or TestFlight: `#if DEBUG` or
     `Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"`. Then the founder still sees it on build 12
     and store players never do.
2. **In the fallback state, system-presented UI comes up upside down relative to the game.**
   - **Where:** while `turnsRound` is true (interface upright, content rotated 180°), the "Reset all progress?" alert
     (`SettingsView.swift:103`), the share sheet (`ResultsView.swift:339, 619`) and Game Center achievement banners all
     present in interface orientation, upside down to a player who has turned the phone.
   - **Fix:** replace the `.alert` with an in-content confirmation card inside `SettingsView`, which turns with the rest
     of the content. Accept the share sheet and banners for 1.0; they only appear in the refused-request fallback.
3. **`adoptMask` patches every window's root class.** `refreshSupportedOrientations` (`OrientationLock.swift:108-115`)
   calls `adoptMask` on the root controller of *every* window in the scene. Any system or keyboard window that ever
   joins `scene.windows` would get its private UIKit class patched with Brim's mask. Restrict it to SwiftUI's host:
   `guard NSStringFromClass(cls).contains("UIHostingController") else { return }` at the top of `adoptMask` (`:160`).
   The class in CI is `_TtGC7SwiftUI19UIHostingController…`, so the guard keeps today's behaviour.
4. **`RootView.swift:89`:** `.position(x: rect.midX, y: rect.midY)            case .standUp:` puts the case label on the
   same line as the expression. It compiles (CI is green) but a merge or format pass can easily break it. Put
   `case .standUp:` on its own line.
5. **Every canvas change repaints the backdrop at 3× on the main thread** (CI: "backdrop scale=3 … ms=275"), through
   `updateCanvas` → `makeScene`. Once P1-1 makes split resizing a normal path, each snap of the divider costs about
   275 ms. The run is paused while iOS resizes (inactive), so the only cost is a hitch. Fix: reuse the outgoing scene's
   cached backdrop texture when only `visibleRect` changed, since the world is identical.

---

## Checked and clean (no finding)

- **Release archive:** `UIRequiresFullScreen` is absent (TestFlight run 40321571132: "UIRequiresFullScreen: absent
  (good)"). The script edits the built Info.plist before signing. iPhone-only (`TARGETED_DEVICE_FAMILY 1`), so no iPad
  multitasking validation applies. All four orientations are in the plist.
- **Non-Duo iPhones:**
  - `adoptMask` runs at launch on every iPhone (`setSharpSide(true)`), but it answers `mask(screen:)` = `.portrait`,
    which is the same result as before.
  - `requestTabletopIfSupported` never asks there.
  - `turnsRound` needs `hasFold`, so it is never true.
  - The Settings toggle and status line show only when `hingeSeen`.
- **Runtime method replacement:** it uses only public Objective-C runtime calls (`class_replaceMethod`,
  `imp_implementationWithBlock`) on Brim's own hosting-controller class. That is not private API, and it's
  low risk under 2.5.1. The block runs only on the main thread (UIKit calls the getter there), so
  `MainActor.assumeIsolated` is safe.
- **Turned-round geometry:**
  - The 180° inset swap and `[.top, .bottom]` gesture deferral are correct. The edges are in interface terms, because
    the preference isn't transformed by `rotationEffect`.
  - DragGesture locations are in the rotated local space, so "drag up" still tips.
  - Frame duo-11 shows the whole tabletop and the HUD turned consistently, with the stream crossing the fold.
- **Turning the setting off while upside down:** the mask drops upside down, `setNeedsUpdateOfSupportedInterfaceOrientations`
  rotates back, and `requestPortrait` asks for upright.
- **Never stuck sideways:** a refused upside-down request while sideways falls back to a portrait request
  (`requestFailed`).
- **Release builds don't trace:**
  - Every new `BRIM-T` line is `#if DEBUG`.
  - `DemoConfig.current` is nil in Release, so `flip`, `DemoOrientation` and DemoRunner can't be reached.
  - `BRIM-H` and the Game Center bypass need the `-brimDemo` launch argument, which a player can't pass.
- **Fold region:** `reservedRegions(kind: .division)` is read in the body and used only for a DEBUG log, behind
  `#available(iOS 27.1, *)`.
- **Privacy manifest:** UserDefaults (CA92.1) and system boot time (35F9.1, `CACurrentMediaTime`) cover what is used. No
  file-timestamp, disk-space or keyboard APIs. `FileManager` appears only in DEBUG demo exports.
- **Game Center:** IDs in `GameCenterManager.swift:13-21` match `docs/appstore/achievements.md` exactly (2 leaderboards,
  10 achievements). The sign-in view controller is never presented.
- **Daily:** keyed to UTC (`LevelCatalog.dayNumber`), with the rollover note in local time. No new edge cases since QA-2.
- **New code is crash-safe:** no force unwraps or indexing in the new code. `SettingsStore.sharpSide` defaults to on
  and is off in demo runs (tested).
