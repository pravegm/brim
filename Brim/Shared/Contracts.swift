import CoreGraphics
import Foundation

// MARK: - Contracts between the modules (owned by the founder; change only in a founder round)
//
// Core   (Brim/Core)      pure Swift simulation: no SpriteKit, no UIKit, no SwiftUI. Unit-tested.
// Scene  (Brim/Scene)     SpriteKit rendering of a GameSnapshot + cosmetic FX from GameEvents.
// Feedback (Brim/Feedback) audio synth + Core Haptics from GameEvents + PourTelemetry.
// App/UI (Brim/App, Brim/UI, Brim/Persistence) SwiftUI shell, input, the loop glue, menus, persistence.
//
// World space: points, origin bottom-left, y up (SpriteKit convention). Width is always 670.
// Height follows the device's play canvas (951 on the Duo inner display in tabletop pose).
// The crease band is horizontal; the jug lives above it, glasses stand on the counter below it.

// MARK: World layout

/// Where things are in world space. Built once per canvas size by the App, handed to the session and the scene.
public struct WorldLayout: Equatable, Sendable {
    /// World size in points (width 670; height = 670 × canvas aspect).
    public var size: CGSize
    /// The crease band in world y (bottom, top). On non-folding phones a virtual band of 0 height at mid-screen.
    public var creaseMinY: CGFloat
    public var creaseMaxY: CGFloat
    /// The counter top the glasses stand on (world y). Fixed distance below the crease so the fall time is the same
    /// on every device.
    public var counterY: CGFloat
    /// Where the jug's pivot sits (world). The spout lip ends up close to (spoutX, creaseMaxY + ~70) while pouring.
    public var jugPivot: CGPoint
    /// Whether this canvas has a real fold (Duo). False = touch fallback.
    public var hasFold: Bool
    /// The part of the world actually on screen (the scene is aspect-FILLED into the canvas, so narrower phones crop
    /// the left and right edges). Anything the player must see — jug, stream, the glass under the spout, puddles,
    /// stamps — must stay inside this rect. Glasses may enter/leave from outside it.
    public var visibleRect: CGRect

    public init(size: CGSize, creaseMinY: CGFloat, creaseMaxY: CGFloat, counterY: CGFloat, jugPivot: CGPoint, hasFold: Bool,
                visibleRect: CGRect? = nil) {
        self.size = size; self.creaseMinY = creaseMinY; self.creaseMaxY = creaseMaxY
        self.counterY = counterY; self.jugPivot = jugPivot; self.hasFold = hasFold
        self.visibleRect = visibleRect ?? CGRect(origin: .zero, size: size)
    }

    // ONE world for every device, shaped like the iPhone Duo's inner canvas in tabletop pose (669 × 951 pt).
    // Round 2 decision (REVIEW-1 P0-1/P0-2): the Duo frame is composed once and other iPhones show the same world
    // aspect-filled, cropping the sides (an iPhone 18 Pro sees x ≈ 116…554).
    public static let worldWidth: CGFloat = 670
    public static let worldHeight: CGFloat = 952
    public static let creaseBottom: CGFloat = 456      // creaseMinY
    public static let creaseTop: CGFloat = 496         // creaseMaxY (40 pt band, the physical fold on a Duo)
    public static let counter: CGFloat = 104           // glass base line on the flat half
    public static let pivot = CGPoint(x: 352, y: 640)  // jug pivot on the raised half

    /// Layout for a play canvas of `canvas` points. `hasFold` = this is a Duo inner display (a hinge was seen).
    public static func make(canvas: CGSize, hasFold: Bool) -> WorldLayout {
        let size = CGSize(width: worldWidth, height: worldHeight)
        let cw = max(canvas.width, 1), ch = max(canvas.height, 1)
        let scale = max(cw / size.width, ch / size.height)          // aspect fill
        let visW = min(size.width, cw / scale), visH = min(size.height, ch / scale)
        let visible = CGRect(x: (size.width - visW) / 2, y: (size.height - visH) / 2, width: visW, height: visH)
        return WorldLayout(size: size, creaseMinY: creaseBottom, creaseMaxY: creaseTop, counterY: counter,
                           jugPivot: pivot, hasFold: hasFold, visibleRect: visible)
    }

    /// Round 1 signature, kept so older call sites compile: a non-nil crease means a fold.
    public static func make(canvas: CGSize, creaseFromTop: ClosedRange<CGFloat>?) -> WorldLayout {
        make(canvas: canvas, hasFold: creaseFromTop != nil)
    }
}

// MARK: Colours (platform-neutral so Core stays UIKit-free)

public struct RGBA: Codable, Hashable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    /// 0xRRGGBB
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255, alpha)
    }
}

// MARK: Liquids

public enum LiquidID: String, Codable, CaseIterable, Sendable {
    case water, lemonade, orangeJuice, cola, rootBeer, creamSoda, milkshake, honey, mapleSyrup, berrySmoothie,
         potionBlue, potionPink, sand
}

/// A liquid's look and personality. Pure data; the catalog lives in Core (`LiquidCatalog`).
public struct Liquid: Codable, Hashable, Sendable {
    public var id: LiquidID
    public var name: String
    public var top: RGBA            // colour near the surface
    public var bottom: RGBA         // colour at the bottom of the glass
    public var foam: RGBA?          // nil = no head
    /// Seconds for the jug's outflow to follow the target flow (0.04 water … 0.8 honey).
    public var lagTau: Double
    /// Foam created per unit volume poured at reference flow (0 = still drink).
    public var foamPerVolume: Double
    /// Seconds for foam to settle to 1/e.
    public var foamSettle: Double
    /// Extra jug tip (degrees) needed before anything moves (0 for liquids, ~30 for sand).
    public var reposeDegrees: Double
    /// Stream opacity 0…1 (water is clear-ish, milkshake opaque).
    public var opacity: Double
    /// Fizzy drinks show rising bubbles.
    public var fizzy: Bool
}

// MARK: Glasses

public enum GlassStyle: String, Codable, Sendable { case tumbler, highball, flute, mug, bowl, sundae, vial, beaker, jar, pint, shot }

/// A glass's interior profile: half-widths at heights from the inner floor (y = 0) to the rim (y = interiorHeight).
/// Volume is 2D area (pt²): V(h) = ∫ 2·halfWidth(y) dy. Points must be sorted by y, first y = 0, last y = rim.
public struct GlassShape: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var style: GlassStyle
    public var profile: [CGPoint]      // x = half-width, y = height
    public var baseThickness: CGFloat  // solid glass under the floor (drawn by the scene)
    public var wall: CGFloat           // wall thickness (drawn by the scene)
    public var interiorHeight: CGFloat { profile.last?.y ?? 0 }
    public var rimHalfWidth: CGFloat { profile.last?.x ?? 0 }
}

// MARK: Orders, levels, modes

public struct GlassOrder: Codable, Hashable, Sendable {
    public var glass: String          // GlassShape.id
    public var liquid: LiquidID
    /// Fill line as a fraction of interior HEIGHT (0…1).
    public var line: Double
    /// Seconds the customer waits once the glass is in place (nil = no timer).
    public var patience: Double?
    /// Line fades out this many seconds after arrival (nil = always visible).
    public var lineFadesAfter: Double?
    /// Pre-filled fraction of interior height (curveball).
    public var prefill: Double
    public init(glass: String, liquid: LiquidID, line: Double, patience: Double? = nil, lineFadesAfter: Double? = nil, prefill: Double = 0) {
        self.glass = glass; self.liquid = liquid; self.line = line; self.patience = patience
        self.lineFadesAfter = lineFadesAfter; self.prefill = prefill
    }
}

public enum VenueID: String, Codable, CaseIterable, Sendable { case lemonadeStand, sodaFountain, milkshakeDiner, conveyor, potionShop, sandBar }

public struct Level: Codable, Hashable, Identifiable, Sendable {
    public var id: String              // "1-1" … venue index - shift index
    public var venue: VenueID
    public var index: Int              // 1-based within the venue
    public var title: String
    public var orders: [GlassOrder]
    /// The jug's starting fill (fraction of its capacity). One jug per shift; it auto-refills when empty
    /// (costs time, no penalty) except in Rush.
    public var jugFill: Double
    /// Conveyor speed in world pt/s (nil = glasses stop under the spout).
    public var conveyorSpeed: Double?
    /// Perfect-band half width as a fraction of interior height (default 0.025).
    public var perfectBand: Double
}

public enum GameMode: Hashable, Sendable {
    case shift(String)        // Level.id
    case rush
    case daily(Int)           // days since 2026-01-01 (seed)
    case practice             // endless, no scoring, no fail (menu backdrop / onboarding)
}

// MARK: Judging

public enum Judgement: String, Codable, Sendable {
    /// Round 5 (QA-2 P1-3): `over` = filled past the Good band but nothing went over the rim. A miss and a strike like
    /// `short`, but no spill FX, no puddle. `spill` now means liquid really overflowed the rim.
    case perfect, great, good, short, over, spill
    public var isHit: Bool { self == .perfect || self == .great || self == .good }
}

// MARK: Snapshot (what the scene draws, every frame)

public struct StreamPoint: Sendable {
    public var position: CGPoint
    public var width: CGFloat         // ribbon width at this point
    public init(position: CGPoint, width: CGFloat) { self.position = position; self.width = width }
}

public struct Droplet: Sendable {
    public var position: CGPoint
    public var velocity: CGVector
    public var radius: CGFloat
    public init(position: CGPoint, velocity: CGVector, radius: CGFloat) { self.position = position; self.velocity = velocity; self.radius = radius }
}

public enum GlassPhase: String, Sendable { case arriving, filling, served, leaving }

public struct GlassState: Sendable, Identifiable {
    public var id: Int
    public var shape: GlassShape
    public var liquid: Liquid
    /// World x of the glass's centre line; the glass's outer base sits on `WorldLayout.counterY`.
    public var x: CGFloat
    public var phase: GlassPhase
    /// Heights above the inner floor (interior coordinates).
    public var liquidHeight: CGFloat
    public var foamHeight: CGFloat      // extra height of the head above the liquid (0 if none)
    public var lineHeight: CGFloat
    public var lineOpacity: Double      // 1 visible, fades for "line fades" orders
    public var inPerfectBand: Bool       // visible top currently inside the Perfect band
    public var overflowing: Bool
    public var patienceLeft: Double?     // seconds, nil = no timer
    public var patienceTotal: Double?
    public var result: Judgement?
}

public struct JugState: Sendable {
    public var liquid: Liquid
    /// Jug rotation in degrees: 0 upright, positive tips the spout down (clockwise on screen).
    public var angle: Double
    /// 0…1 of capacity.
    public var fill: Double
    /// World-space polygon of the jug's interior outline (already rotated and positioned).
    public var outline: [CGPoint]
    /// World-space polygon of the liquid inside the jug (empty if none).
    public var liquidPolygon: [CGPoint]
    /// World-space spout lip.
    public var lip: CGPoint
    public var pivot: CGPoint
    /// Current outflow, 0…1 of the jug's maximum flow.
    public var flow: Double
}

public enum SessionPhase: String, Sendable { case intro, playing, finished }

public struct GameSnapshot: Sendable {
    public var time: Double
    public var phase: SessionPhase
    public var mode: GameMode
    public var jug: JugState
    public var stream: [StreamPoint]       // ordered spout → tail; empty when not pouring and fully landed
    public var droplets: [Droplet]
    public var glasses: [GlassState]       // at most ~3 on screen
    public var puddles: [CGPoint]          // spill marks on the counter (world, x on the counter line)
    public var score: Int
    public var streak: Int
    public var multiplier: Int
    public var strikes: Int
    public var maxStrikes: Int
    public var ordersDone: Int
    public var ordersTotal: Int?           // nil in Rush
    public var perfects: Int
    public var telemetry: PourTelemetry
    /// Round 2: true until the player has laid the phone flat (lid tilt inside the dead zone) once at the start of a
    /// run or after a resume; no outflow while true. The UI shows "Lay it flat to start".
    public var needsFlat: Bool = false
}

/// Continuous values Feedback maps to sound/haptics every frame.
public struct PourTelemetry: Sendable {
    public var flow: Double                // 0…1 outflow from the jug
    public var landingRate: Double         // 0…1 volume landing in the active glass
    public var activeFill: Double          // 0…1 visible top / interior height of the glass under the spout
    public var distanceToLine: Double      // (top − line) / interiorHeight, signed
    /// Same, but as if everything already in the air (and the jug's lagged outflow still to come) had landed.
    /// The autopilot and the "stop now" hint use it.
    public var projectedDistanceToLine: Double
    public var liquid: LiquidID
    public init(flow: Double = 0, landingRate: Double = 0, activeFill: Double = 0, distanceToLine: Double = -1,
                projectedDistanceToLine: Double = -1, liquid: LiquidID = .water) {
        self.flow = flow; self.landingRate = landingRate; self.activeFill = activeFill
        self.distanceToLine = distanceToLine; self.projectedDistanceToLine = projectedDistanceToLine; self.liquid = liquid
    }
}

// MARK: Events (edges; Feedback and Scene FX react to these)

public enum GameEvent: Sendable {
    case pourStarted
    case pourStopped
    case glug(intensity: Double)                       // one bubble of air entering the jug
    case splashInGlass(glassID: Int, x: CGFloat, strength: Double)
    case splashOnCounter(x: CGFloat, strength: Double)
    case enteredPerfectBand(glassID: Int)
    case overflowStarted(glassID: Int)
    case glassArrived(glassID: Int)
    case served(glassID: Int, judgement: Judgement, points: Int)
    case streak(Int)
    case multiplier(Int)
    case strike(Int)                                    // strikes so far
    case jugRefilled(fraction: Double)
    case jugSwapped                                     // empty jug replaced (shifts)
    case jugEmpty                                       // Rush: run ends
    case nearingLine(glassID: Int)                      // still pouring with the top at ≥ 60% of the line (hint)
    case lockedIn(glassID: Int)                         // round 2: the stream finished landing with the top inside
                                                        // the Perfect band (instant cue before the verdict)
    case flatArmed                                      // round 2: the start gate opened (phone laid flat)
    case finished(RunResult)
}

public struct RunResult: Sendable, Equatable {
    public var mode: GameMode
    public var score: Int
    public var stars: Int                    // 0…3 (shifts); 0 elsewhere
    public var perfects: Int
    public var bestStreak: Int
    public var judgements: [Judgement]       // in order, for the share card
    public var poured: Double                // world volume poured (for lifetime stats)
    public var cleared: Bool                 // shifts: met the minimum (≥ 1 star)
}

// MARK: Seams the App wires together

/// Something that supplies the jug-tilt control, in degrees of LID tilt (0 = flat/upright jug … 90).
@MainActor public protocol TiltSource: AnyObject {
    /// Tilt to use for the frame drawn at `time` (CACurrentMediaTime). Implementations may predict between samples.
    func tilt(at time: TimeInterval) -> Double
}

/// The scene asks its driver to advance the game once per frame.
@MainActor public protocol SceneDriver: AnyObject {
    func advance(dt: Double, now: TimeInterval) -> (GameSnapshot, [GameEvent])?
}

/// Audio + haptics.
@MainActor public protocol FeedbackSink: AnyObject {
    func handle(events: [GameEvent], snapshot: GameSnapshot)
    func setPaused(_ paused: Bool)
}
