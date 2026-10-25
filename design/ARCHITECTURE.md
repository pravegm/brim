# Brim — architecture and module contracts

The types shared between modules are in `Brim/Shared/Contracts.swift` (founder-owned). This file says who owns what
and the exact API each module must expose so the others compile against it **without a compiler on our side**
(CI on GitHub's macOS runner is our only compiler; see `CLAUDE.md`).

Language: Swift 5 mode, iOS 18 deployment target, iOS 27.1 SDK (Xcode 27.1). Hinge code behind `#available(iOS 27.1, *)`.
Everything that touches views/nodes/audio is `@MainActor`. Core is plain value types + one final class, not actor-isolated
(mark Core types `nonisolated` only if the compiler demands it; they hold no UI state).

## The frame loop

```
SpriteView(GameScene)                     ← SwiftUI hosts SpriteKit, preferredFramesPerSecond = 120
  GameScene.update(currentTime)
    → driver.advance(dt:now:)             ← GameController (App), the hub
         tilt = tiltSource.tilt(at: now)    (HingeTiltSource on Duo, TouchTiltSource elsewhere, DemoTiltSource in CI)
         events = session.step(dt, tilt)    (Core: GameSession)
         feedback.handle(events, snapshot)  (Feedback: FeedbackDirector)
         publish HUD state (score, streak…) at ≤ 15 Hz to SwiftUI
    ← (snapshot, events)
    GameScene.render(snapshot) + spawn FX for events
```

`dt` is clamped to ≤ 1/30 s; the session sub-steps internally at ≤ 1/240 s.

## Module ownership

| Module | Folder | Owner (agent role) |
|---|---|---|
| Contracts | `Brim/Shared/` | founder |
| Core simulation | `Brim/Core/` | **Core engineer** |
| Input (hinge, touch, demo tilt) | `Brim/Input/` | **Feel engineer** |
| Feedback (audio synth, haptics) | `Brim/Feedback/` | **Feel engineer** |
| Scene (SpriteKit) | `Brim/Scene/` | **Scene engineer** |
| App shell, UI, persistence, Game Center, demo mode | `Brim/App/`, `Brim/UI/`, `Brim/Persistence/` | **App engineer** |
| Tests | `BrimTests/` | each engineer writes `BrimTests/<Module>Tests.swift` |
| CI | `.github/`, `ci/` | founder |

## Core API (Core engineer must provide exactly these; others may rely on them)

```swift
enum LiquidCatalog {
    static func liquid(_ id: LiquidID) -> Liquid
    static var all: [Liquid] { get }
}

enum GlassCatalog {
    static func shape(_ id: String) -> GlassShape          // falls back to "tumbler" for unknown ids
    static var all: [GlassShape] { get }                    // ids: tumbler, highball, flute, mug, bowl, sundae, vial, beaker, jar, pint, shot
}

enum GlassMath {
    static func halfWidth(_ s: GlassShape, at h: CGFloat) -> CGFloat
    static func volume(_ s: GlassShape, upTo h: CGFloat) -> CGFloat      // 2D area from floor to h (clamped to rim)
    static func height(_ s: GlassShape, forVolume v: CGFloat) -> CGFloat // inverse; above capacity → rim
    static func capacity(_ s: GlassShape) -> CGFloat
}

struct JugShape { var outline: [CGPoint]; var lip: CGPoint; var pivot: CGPoint; var capacity: CGFloat }  // local coords
enum JugGeometry {
    static let standard: JugShape
    /// World-space outline + liquid polygon + lip for a given rotation/fill, positioned so `pivot` sits at `at`.
    static func pose(_ jug: JugShape, angle: Double, fill: Double, at pivot: CGPoint) -> (outline: [CGPoint], liquid: [CGPoint], lip: CGPoint, headAboveLip: CGFloat)
}

enum Rules {
    static let deadZone: Double                 // 6° of lid tilt
    static func jugAngle(forLidTilt t: Double) -> Double      // 0 below the dead zone, then 1.55 × (t − 6)
    static func judge(top: CGFloat, line: CGFloat, interior: CGFloat, overflowed: Bool, perfectBand: Double) -> Judgement
    static func points(for j: Judgement, multiplier: Int) -> Int
    static func multiplier(forStreak s: Int) -> Int          // 1, 2 (≥3), 3 (≥6), 5 (≥10)
    static func stars(perfects: Int, hits: Int, spills: Int, total: Int) -> Int
}

enum LevelCatalog {
    static var levels: [Level] { get }                       // all shift levels, in play order
    static func level(_ id: String) -> Level?
    static func levels(in venue: VenueID) -> [Level]
    static func title(of venue: VenueID) -> String
    static func starsToUnlock(_ venue: VenueID) -> Int       // 0 for the first venue
    static func dailyOrders(day: Int) -> [GlassOrder]        // deterministic per day
    static func dayNumber(for date: Date) -> Int             // days since 2026-01-01 in the user's calendar
}

final class GameSession {
    init(mode: GameMode, layout: WorldLayout, seed: UInt64)
    func step(dt: Double, tilt: Double) -> [GameEvent]       // tilt = LID tilt in degrees (0…90)
    var snapshot: GameSnapshot { get }
    var isFinished: Bool { get }
    var result: RunResult? { get }
}
```

`GameSession` behaviour (spec: `design/GAME-DESIGN.md` §4–§6):
- `.intro` for 0.8 s while the first glass slides in, then `.playing`; `.finished` after the last order (shift/daily),
  3 spills or an empty jug (Rush). Practice never finishes.
- The jug's outflow follows `JugGeometry` head-above-lip: `flowTarget = k · head^1.5`, lagged by the liquid's `lagTau`.
- Stream: Lagrangian particles emitted at the lip along the spout direction; each carries volume; gravity 2000 pt/s².
  `snapshot.stream` is the ordered polyline of live particles (spout → tail), widths ∝ √(local flow).
- Particles crossing a glass's rim height inside the mouth go in (volume added when they reach the surface);
  outside the mouth they hit the counter (`splashOnCounter`, lost; adds a puddle).
- Foam (`foamPerVolume`, `foamSettle`) adds visible height; overflow above the rim → `overflowStarted`, judged Spill.
- Serving: glass at the spout, some liquid in, no outflow and no particles left in flight for 0.6 s → judged;
  or patience runs out; conveyor levels judge when the glass leaves the spout zone.
- Glass x positions: arrive from x = −120 to the spout landing x in 0.7 s (ease-out); leave to x = 790 in 0.6 s.
- Daily: `LevelCatalog.dailyOrders(day:)`, 10 orders, 3 strikes.
- Rush: one jug that never swaps, starts full (capacity ≈ 4.5 tumblers); each Perfect refills 6 % of capacity;
  difficulty tier every 8 glasses (patience shrinks, conveyor appears from tier 3, foamy/viscous liquids mix in).
- All randomness from a seeded generator (`seed`) so CI and tests are deterministic.

## Input API (Feel engineer)

```swift
@MainActor final class HingeTiltSource: TiltSource {     // fed by HingeReader (SwiftUI modifier) samples
    func ingest(angleDegrees: Double, at time: TimeInterval)
    var hasHinge: Bool { get }                            // true once any real sample arrived
    var lastAngle: Double? { get }                        // filtered hinge angle (180 = flat)
}
@MainActor final class TouchTiltSource: TiltSource {     // drag up = tip; eases back to 0 on release
    func began(at y: CGFloat); func moved(to y: CGFloat); func ended()
}
@MainActor final class DemoTiltSource: TiltSource {      // CI scripts: piecewise-linear keyframes
    init(keyframes: [(t: Double, tilt: Double)], start: TimeInterval)
}
struct HingeReader: ViewModifier                          // wraps onHingeChange; (angle°, time) callback + onUnavailable
// usage: view.modifier(HingeReader(onUpdate: { angle, time in … }, onUnavailable: { … }))
enum AutopilotStyle: String { case perfect, great, short, spill }
@MainActor final class AutopilotTiltSource: TiltSource { // plays the game (CI frames, menu attract loop)
    init(style: AutopilotStyle, snapshot: @escaping () -> GameSnapshot?)
}
/// Lid tilt → hinge angle helpers for HUD/debug: hingeAngle = 180 − tilt.
```

## Feedback API (Feel engineer)

```swift
@MainActor final class FeedbackDirector: FeedbackSink {
    static let shared: FeedbackDirector
    func start()                          // audio session + engines
    var soundOn: Bool; var hapticsOn: Bool; var respectSilentSwitch: Bool
    func uiTap(); func uiConfirm(); func celebrate()   // menu sounds
}
```

## Scene API (Scene engineer)

```swift
@MainActor final class GameScene: SKScene {
    init(layout: WorldLayout)             // scene.size = layout.size, scaleMode = .aspectFill handled by host
    weak var driver: SceneDriver?
    var reduceMotion: Bool
    func reset(for snapshot: GameSnapshot)   // new session: clear glasses/FX
}
```

The scene draws only from snapshots and events. It owns cosmetic state (surface waves, splash particles, sparkle
rings, stamps). It never changes game state.

## App API (App engineer)

`GameController` (`@MainActor ObservableObject`, `SceneDriver`) owns the session, tilt source, feedback, and exposes
HUD state for SwiftUI. Persistence in `ProgressStore` (UserDefaults JSON, versioned key). Demo mode (DEBUG and CI):
launch argument `-brimDemo "key=value;key"`; keys documented at the top of `Brim/App/DemoMode.swift`, and every app
log line CI greps starts with `BRIM-`.
