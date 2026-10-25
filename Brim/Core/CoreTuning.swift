import CoreGraphics
import Foundation

// MARK: - Every tunable number of the Core simulation, in one place.
//
// (Named `CoreTuning`, not `Tuning`, so it can never collide with another module's tunables in the single app target.)
// Units: world points (pt), seconds, degrees. Volumes are 2D areas (pt²), flows are pt²/s.
//
// Reference sizes for intuition: the standard jug holds ~28,400 pt²; a tumbler holds ~7,400 pt² (≈ 5,000 to a
// typical line); a tiny cup ("shot" id) ~3,600 pt². The stream falls ~310 pt from the lip to a tumbler's rim on the Duo.

enum CoreTuning {

    // MARK: Frame / integration

    /// Largest frame dt the session accepts (the App also clamps).
    static let maxFrameDt: Double = 1.0 / 30.0
    /// Largest simulation sub-step. Stream particles are emitted once per sub-step.
    static let maxSubstep: Double = 1.0 / 240.0
    /// Gravity for the stream and splash droplets, pt/s² (spec: 2000).
    static let gravity: Double = 2000

    // MARK: Jug outflow (weir law: target = flowK · head^1.5)

    /// Weir coefficient. 2.3 → a full jug held at 60° pours ~2,000 pt²/s (a tumbler to its line in ~2.5 s); at 30° a
    /// full jug pours ~420 pt²/s (gentle); a jug at 6 % needs ~90° to start and ~120° for a useful ~1,000 pt²/s.
    static let flowK: Double = 2.3
    /// Outflow that reads as `flow = 1.0` in snapshots/telemetry (≈ a full jug at ~80°).
    static let flowNormRef: Double = 4000
    /// Hard ceiling on the target outflow (a full jug flung to 130° would otherwise dump instantly).
    static let flowCap: Double = 6500
    /// Upright, a full jug's surface sits this far below the lip, so a full jug starts to pour at ~10° of jug angle
    /// (lid ≈ 12.5°) and never at 0.
    static let jugHeadroom: Double = 16
    /// With a zero target, outflow below this (pt²/s) snaps to 0 (ends long exponential tails of honey).
    static let outflowCutoff: Double = 6
    /// Jug counts as empty below this fill (shifts: auto-swap; Rush: run ends).
    static let jugEmptyFill: Double = 0.025
    /// No outflow for this long while a jug is swapped (empty jug, or a different drink's jug).
    static let jugSwapPause: Double = 0.6
    /// Rush: each Perfect refills this fraction of the jug's capacity.
    static let rushRefill: Double = 0.06
    /// Rush uses "one big shared jug": the standard jug scaled by this (area × scale²).
    static let rushJugScale: Double = 1.12
    /// The jug's interior never dips below `creaseMaxY + jugClearance`: at small angles the jug is lifted, so it
    /// appears to rock on the crease ledge before it swings about its lip.
    static let jugClearance: Double = 14
    /// The jug's pivot anchor sits this far below `layout.jugPivot`, so the lip pours from ≈ creaseMaxY + 55…90.
    static let jugAnchorDrop: Double = 22

    // MARK: Sand (angle of repose)

    /// Once sand is flowing, it keeps flowing until the jug is this many degrees below the repose angle.
    static let sandHysteresis: Double = 6
    /// Avalanche overshoot when sand starts to move: target × (1 + boost · remaining/duration).
    static let avalancheDuration: Double = 0.4
    static let avalancheBoost: Double = 1.6

    // MARK: Stream

    /// Exit speed at the lip = (min + perFlow · flow) / (1 + viscositySlow · lagTau).
    static let exitSpeedMin: Double = 25
    static let exitSpeedPerFlow: Double = 110
    static let exitViscositySlow: Double = 0.8
    /// The exit direction (degrees from +x, y up) is the spout direction clamped to this range, so a steeply tipped
    /// jug drops the stream almost straight down instead of flinging it backwards.
    static let exitDirMinDeg: Double = -55
    static let exitDirMaxDeg: Double = 10
    /// Ribbon width = max · √flow at emission, thinned as it accelerates: × max(floor, (v0/v)^thinning).
    static let streamWidthMax: Double = 18
    static let streamWidthMin: Double = 1.6
    static let streamThinning: Double = 0.5
    static let streamThinFloor: Double = 0.45
    /// Below this flow (0…1) the stream breaks into drips.
    static let dropFlowThreshold: Double = 0.012
    /// Volume (pt²) of one drip.
    static let dripVolume: Double = 30
    /// Two ribbon particles emitted further apart than this (s) are drawn as separate ribbons.
    static let streamGapTime: Double = 0.02
    /// Particle cap (stream + drips). Past it, new volume merges into the newest particle.
    static let maxParticles: Int = 400

    // MARK: Splash droplets (cosmetic)

    static let maxDroplets: Int = 80
    /// Chance per landing stream particle to throw a splash droplet = base + perFlow · flow.
    static let splashChanceBase: Double = 0.05
    static let splashChancePerFlow: Double = 0.3
    static let splashLifeMin: Double = 0.25
    static let splashLifeMax: Double = 0.5
    /// A landing that starts after this long without one emits a splash event (edges only).
    static let splashEdgeGap: Double = 0.12

    // MARK: Glasses, serving

    static let introDuration: Double = 0.8
    static let arriveDuration: Double = 0.7
    static let leaveDuration: Double = 0.6
    static let arriveFromX: Double = -120
    static let leaveToX: Double = 790
    /// Seconds a judged glass waits (showing its stamp) before it slides away.
    static let resultHold: Double = 0.45
    /// Served after this long with no outflow and nothing in the air (spec: 0.6 s).
    static let serveIdle: Double = 0.6
    /// If a head is still settling, serving waits up to this much longer (lets "pour slow, then top up" work).
    static let foamServeGrace: Double = 1.6
    /// A head below this fraction of the interior height counts as settled.
    static let foamSettledFraction: Double = 0.025
    /// A glass needs at least this much poured in (pt²) before it can be served by stopping.
    static let minServeVolume: Double = 40
    /// Overflow when liquid + foam exceeds capacity by this fraction.
    static let overflowTolerance: Double = 0.003
    /// Seconds for a "line fades" line to fade out.
    static let lineFadeDuration: Double = 0.4
    /// Conveyor: the glass slides in to this far left of the stream (mouth edge), then rides the belt.
    static let conveyorLeadIn: Double = 30
    /// Conveyor: judged when the mouth's left edge passes the stream's landing x by this much.
    static let conveyorExitMargin: Double = 6
    /// Delay between the deciding judgement and `finished`, so the last stamp is seen.
    static let finishDelay: Double = 0.9
    /// Reference pour used to place each glass under the stream, plus a bias that centres the glass on the whole
    /// range of real pours (landing x varies ≈ −19…+11 pt from the reference across 12°…130° of jug angle).
    static let refPourAngle: Double = 90
    static let refPourFlow: Double = 0.6
    static let glassPlacementBias: Double = -4

    // MARK: Foam

    /// Foam made per landed volume = foamPerVolume · clamp(flow / foamRefFlow, min, max).
    static let foamRefFlow: Double = 0.35
    static let foamFactorMin: Double = 0.2
    static let foamFactorMax: Double = 2.5
    /// The projection assumes the head settles for this long before judging.
    static let projectionFoamTime: Double = 0.9

    // MARK: Judging and score

    static let defaultPerfectBand: Double = 0.025
    static let greatBand: Double = 0.06
    static let goodBand: Double = 0.12
    static let pointsPerfect: Int = 100
    static let pointsGreat: Int = 60
    static let pointsGood: Int = 30

    // MARK: Events

    /// pourStarted when flow rises above `pourOnFlow`; pourStopped when it falls below `pourOffFlow`.
    static let pourOnFlow: Double = 0.012
    static let pourOffFlow: Double = 0.004
    /// Glug cadence (Hz) = (base + perFlow · flow) / (1 + viscositySlow · lagTau), ±15 % jitter.
    static let glugBaseHz: Double = 4
    static let glugPerFlowHz: Double = 5
    static let glugViscositySlow: Double = 1.2
    /// nearingLine fires once per glass when pouring with the top ≥ this fraction of the line.
    static let nearingLineFraction: Double = 0.6
    /// Telemetry landing-rate smoothing time constant (s).
    static let landingTau: Double = 0.08

    // MARK: Puddles

    static let puddleMergeDistance: Double = 22
    static let maxPuddles: Int = 10

    // MARK: Modes

    static let maxStrikes: Int = 3
    /// Rush: difficulty tier every N glasses.
    static let rushTierEvery: Int = 8
}

// MARK: - Small math helpers (namespaced to avoid clashing with other modules' globals)

enum CoreMath {
    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        return v < lo ? lo : (v > hi ? hi : v)
    }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        return a + (b - a) * t
    }
    static func easeOutCubic(_ t: Double) -> Double {
        let u: Double = 1.0 - clamp(t, 0, 1)
        return 1.0 - u * u * u
    }
    static func easeInQuad(_ t: Double) -> Double {
        let u: Double = clamp(t, 0, 1)
        return u * u
    }
    static func radians(_ deg: Double) -> Double {
        return deg * Double.pi / 180.0
    }
}

// MARK: - Deterministic RNG (SplitMix64)

struct CoreRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed ^ 0x9E37_79B9_7F4A_7C15
    }

    mutating func nextUInt64() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double {
        return Double(nextUInt64() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform in [lo, hi).
    mutating func range(_ lo: Double, _ hi: Double) -> Double {
        return lo + (hi - lo) * unit()
    }

    /// Uniform integer in 0..<n (n ≥ 1).
    mutating func int(_ n: Int) -> Int {
        if n <= 1 { return 0 }
        return Int(nextUInt64() % UInt64(n))
    }

    mutating func chance(_ p: Double) -> Bool {
        return unit() < p
    }

    mutating func pick<T>(_ items: [T]) -> T {
        return items[int(items.count)]
    }
}
