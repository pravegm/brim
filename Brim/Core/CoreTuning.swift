import CoreGraphics
import Foundation

// MARK: - Every tunable number of the Core simulation, in one place.
//
// (Named `CoreTuning`, not `Tuning`, so it can never collide with another module's tunables in the single app target.)
// Units: world points (pt), seconds, degrees. Volumes are 2D areas (pt²), flows are pt²/s.
//
// Round 2 (one 670 × 952 world): glasses are ×1.45–1.6 bigger, so glass volumes are ~2.2× round 1. The jug is drawn
// at ~170 × 225 but holds `jugVolumeScale` × its 2D area (it is a deep 3D pitcher), so it still serves a shift.
// Reference sizes: a tumbler holds ~17,000 pt² (≈ 11,600 to a 0.7 line); the standard jug's polygon is ~24,600 pt²
// and holds ~86,000 pt² of drink (≈ 7 tumblers to the line). The stream falls ~150–450 pt from the lip to a rim.
// Round 3: the jug is drawn at `jugScale` 0.93 (polygon ~21,300 pt², same ~86,000 pt² of drink, same flow).
// `RunResult.poured` is in these units: ~2.2× round 1 per glass (App: rescale any litres conversion).

enum CoreTuning {

    // MARK: Frame / integration

    /// Largest frame dt the session accepts (the App also clamps).
    static let maxFrameDt: Double = 1.0 / 30.0
    /// Largest simulation sub-step. Stream particles are emitted once per sub-step.
    static let maxSubstep: Double = 1.0 / 240.0
    /// Gravity for the stream and splash droplets, pt/s² (spec: 2000).
    static let gravity: Double = 2000

    // MARK: Jug placement (world)

    /// The jug rotates about its spout lip. Resting lip position = layout.jugPivot + (lipOffsetX, −lipDrop):
    /// (359, 552) on the standard world, 56 pt above the crease. While the jug is too upright for its body to clear
    /// the crease it is lifted (it rocks up on the crease ledge), so the lip sits ~+56…+78 for jug angles ≥ 55°
    /// (mid/low jug) and higher for the first, shallow pours of a full jug.
    /// Round 3 (centre the pour): the lip moved 43 pt left and the jug is drawn at `jugScale`, so glasses stop at
    /// x ≈ 361…369 (≤ 372) and the body (interior + 9 pt wall) stays right of x ≈ 120 at every angle (≥ 118 rule)
    /// and left of x ≈ 470, its top ≤ ~786 (under the HUD band).
    static let lipOffsetX: Double = 7
    static let lipDrop: Double = 88
    /// Uniform scale of the house jug's interior (round 3: 0.93, so the tipped body clears x 118 with the pour
    /// centred). Flow and volume are compensated below so the pour timing is unchanged.
    static let jugScale: Double = 0.93
    /// While tipping, the jug's interior never dips below `creaseMaxY + jugClearance` (it may cross the crease band
    /// with its walls only while tipping).
    static let jugClearance: Double = 4
    /// At rest (upright) the interior sits this far above `creaseMaxY`, so the drawn walls (~9 pt) clear the fold
    /// keep-out (crease + 8). The clearance eases from this to `jugClearance` over the first `jugRestBlendAngle`
    /// degrees of jug angle (a full jug starts pouring at ~10.5°, so pours are unaffected).
    static let jugRestClearance: Double = 21
    static let jugRestBlendAngle: Double = 10

    // MARK: Jug outflow (weir law: target = flowK · head^1.5)

    /// Weir coefficient (pt²/s per pt^1.5 of head above the lip). With `jugVolumeScale` 3.5 a tumbler to a 0.7 line
    /// takes ~2.3–2.7 s (after the stream lands) at 15° of lid past the pour point (4 s from a 0.9 jug, whose head
    /// grows slowly), and ~1.5–2.1 s at 20°. A held tilt slowly eases off as the jug drains: tip further as it empties.
    /// (Round 3: 17 at scale 1, divided by jugScale^1.5 because the head shrinks with the jug.)
    static let flowK: Double = 17.0 / (jugScale * jugScale.squareRoot())
    /// Drink volume (glass pt²) the jug holds per pt² of its 2D interior polygon. (3.5 at scale 1, divided by
    /// jugScale² so the drink volume of a full jug is unchanged.)
    static let jugVolumeScale: Double = 3.5 / (jugScale * jugScale)
    /// Outflow that reads as `flow = 1.0` in snapshots/telemetry (≈ a mid jug tipped ~22° of lid past its pour point).
    static let flowNormRef: Double = 10000
    /// Hard ceiling on the target outflow.
    static let flowCap: Double = 16000
    /// Upright, a full jug's surface sits this far below the lip (local pt), so a full jug starts to pour at ~10.5° of
    /// jug angle (lid ≈ 13°) and never at 0.
    static let jugHeadroom: Double = 16
    /// Rising outflow follows the weir target with τ = riseTauBase + riseTauPerLag · lagTau (viscous drinks swell in).
    static let riseTauBase: Double = 0.03
    static let riseTauPerLag: Double = 0.2
    /// Falling outflow while the jug can still deliver (head > 0): τ = declineTauPerLag · lagTau (the surface lags,
    /// briefly).
    static let declineTauPerLag: Double = 0.5
    /// Once the head is gone (jug too upright to pour) only the rope in the spout drains: τ = ropeTauPerLag · lagTau,
    /// clamped to ropeTauMin…ropeTauMax, and the rope always snaps within `ropeMaxTime`. No stream from an upright jug.
    static let ropeTauPerLag: Double = 0.3
    static let ropeTauMin: Double = 0.02
    static let ropeTauMax: Double = 0.2
    static let ropeMaxTime: Double = 0.4
    /// With no head, outflow below this snaps to 0: cutoff + lagTau · ropeSnapPerLag (viscous ropes snap thick).
    static let outflowCutoff: Double = 15
    static let ropeSnapPerLag: Double = 320
    /// Jug counts as empty below this fill (shifts: auto-swap; Rush: run ends).
    static let jugEmptyFill: Double = 0.025
    /// No outflow for this long while a jug is swapped (empty jug, or a different drink's jug).
    static let jugSwapPause: Double = 0.6
    /// Rush: a Perfect refills this fraction of the jug's capacity, a Great `rushRefillGreat`.
    /// Budget (tier-0 orders need ~14,000 pt²; the Rush jug holds ~121,000): a decent player (50 % Perfect, 30 % Great)
    /// nets −3,700 per glass → ~33 glasses ≈ 2.4 min; a strong one (75 % Perfect) runs 4+ min until the tiers bite;
    /// a beginner (30 % / 30 %) ~17 glasses ≈ 75 s.
    static let rushRefill: Double = 0.14
    static let rushRefillGreat: Double = 0.05
    /// Rush's "one big shared jug": same drawn shape (scale 1.0 keeps it inside x 130…540 and under the HUD band at
    /// every angle), but it holds `rushVolumeBoost` × the standard jug.
    static let rushJugScale: Double = 1.0
    static let rushVolumeBoost: Double = 1.4

    // MARK: Sand (angle of repose)

    /// Once sand is flowing, it keeps flowing until the jug is this many degrees below the repose angle.
    static let sandHysteresis: Double = 6
    /// Avalanche overshoot when sand starts to move: target × (1 + boost · remaining/duration).
    static let avalancheDuration: Double = 0.4
    static let avalancheBoost: Double = 1.6

    // MARK: Stream

    /// Exit speed at the lip = (min + perFlow · flow) / (1 + viscositySlow · lagTau). Kept low so the stream drops
    /// almost straight down: it lands ~4–20 pt right of the lip for every angle and flow, and glasses stop on the
    /// middle of that range, so every pour lands within ±8 pt of the glass centre. (Round 3: 12 + 10·flow, so it
    /// lands ~3…10 pt right of the lip and the glass can stand closer to the centre.)
    static let exitSpeedMin: Double = 12
    static let exitSpeedPerFlow: Double = 10
    static let exitViscositySlow: Double = 0.8
    /// The exit direction (degrees from +x, y up) is the spout direction clamped to this range.
    static let exitDirMinDeg: Double = -60
    static let exitDirMaxDeg: Double = 0
    /// Ribbon width = max · √flow at emission, thinned as it falls: × max(floor, (thinRef / v)^thinning).
    static let streamWidthMax: Double = 26
    static let streamWidthMin: Double = 1.6
    static let streamThinning: Double = 0.35
    static let streamThinRefSpeed: Double = 250
    static let streamThinFloor: Double = 0.6
    /// Below this flow (0…1) the stream breaks into drips.
    static let dropFlowThreshold: Double = 0.012
    /// Volume (pt²) of one drip.
    static let dripVolume: Double = 60
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
    /// Splashes thrown up inside a glass stay inside its mouth (|x − centre| ≤ rimHalf − inset) and die at the surface.
    static let splashMouthInset: Double = 5
    /// A landing that starts after this long without one emits a splash event (edges only).
    static let splashEdgeGap: Double = 0.12

    // MARK: Glasses, serving

    static let introDuration: Double = 0.8
    /// Arrive and leave overlap: the next glass starts sliding in the moment the judged one starts sliding out.
    static let arriveDuration: Double = 0.45
    static let leaveDuration: Double = 0.45
    static let arriveFromX: Double = -130
    static let leaveToX: Double = 800
    /// Leaving: x = start + d · (leaveLinear · u + (1 − leaveLinear) · u²), so it gets out of the way at once.
    static let leaveLinear: Double = 0.35
    /// Seconds a judged glass waits (showing its stamp) before it slides away. Changeover = resultHold + arrive.
    static let resultHold: Double = 0.3
    /// A judged glass doesn't leave while the stream is still running or falling (a live spill, a patience timeout):
    /// it keeps catching (and sheeting) until the stream has landed, at most this long past `resultHold`, so the
    /// next glass never slides in under a falling stream.
    static let changeoverWaitMax: Double = 1.0
    /// Served after this long with no outflow and nothing in the air (`.lockedIn` fires at the start of it).
    static let serveIdle: Double = 0.35
    /// If a head is still settling, serving waits up to this much longer (lets "pour slow, then top up" work).
    static let foamServeGrace: Double = 1.2
    /// A head below this fraction of the interior height counts as settled.
    static let foamSettledFraction: Double = 0.025
    /// A glass needs at least this much poured in (pt²) before it can be served by stopping.
    static let minServeVolume: Double = 90
    /// Overflow when liquid + foam exceeds capacity by this fraction.
    static let overflowTolerance: Double = 0.003
    /// Seconds for a "line fades" line to fade out.
    static let lineFadeDuration: Double = 0.4
    /// Conveyor: the glass slides in to this far left of the stream (mouth edge), then rides the belt.
    static let conveyorLeadIn: Double = 40
    /// Conveyor: judged when the mouth's left edge passes the stream's landing x by this much.
    static let conveyorExitMargin: Double = 6
    /// Delay between the deciding judgement and `finished`, so the last stamp is seen.
    static let finishDelay: Double = 0.9
    /// Glass placement: the landing x is sampled over the pours this jug fill will really use (pour point … +span of
    /// jug angle, flows 0.15…0.9) and the glass stops on the middle of that range, plus this bias.
    static let glassPlacementBias: Double = 0
    static let placementAngleSpan: Double = 45
    /// Round 3: the next glass waits on the counter (phase `.arriving`, `lineOpacity` 0, standing still) at this
    /// world x, then slides into place as the judged one leaves while the one after slides into the slot. Nudged right
    /// so it is never cropped on narrow phones, and left so it keeps `nextGlassGap` from the glass at the stop. Not used
    /// on conveyors (glasses ride the belt) or in practice.
    /// Round 4 (REVIEW-3 P1-4): `nextGlassEdgeMargin` is measured from `visibleRect.minX` to the slot's outermost drawn
    /// edge — its COASTER (or the scaled glass / mug handle if wider) — see `NextGlassSlot`. When it can't be kept
    /// (narrow phone + wide glasses) there is no waiting glass for that order.
    static let nextGlassX: Double = 165
    static let nextGlassEdgeMargin: Double = 16
    static let nextGlassGap: Double = 8
    /// Round 4 (REVIEW-3 P1-1 / P1-4): the waiting glass is information, not a target — Scene draws it (and may draw
    /// its coaster) at this scale, about its base centre: 0.82 on the Duo, 0.75 on phones without a fold. Core places
    /// the slot for exactly these scales (`NextGlassSlot.scale(hasFold:)`).
    static let nextGlassScaleFold: Double = 0.82
    static let nextGlassScalePhone: Double = 0.75
    /// Round 3 (pause / resume): after `requireFlat()`, the glass under the spout is not judged by stopping (no
    /// lock-in, no idle serve) until the player pours again. If they never do, it is served after this long flat.
    static let resumeServeIdle: Double = 4.0

    // MARK: Foam

    /// Foam made per landed volume = foamPerVolume · clamp(flow / foamRefFlow, min, max).
    static let foamRefFlow: Double = 0.35
    static let foamFactorMin: Double = 0.2
    static let foamFactorMax: Double = 2.5
    /// The projection assumes the head settles for this long before judging.
    static let projectionFoamTime: Double = 0.6

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

    // MARK: Puddles (live spill)

    /// Spilt volume pools into puddles; a puddle of volume V has radius clamp(base + k·√V, base, max).
    static let puddleBaseRadius: Double = 12
    static let puddleRadiusPerSqrtVolume: Double = 0.9
    static let puddleMaxRadius: Double = 105
    /// A spill within (radius + this) of a puddle's centre joins it.
    static let puddleJoinMargin: Double = 10
    /// Snapshot encoding: each puddle is a run of points along the counter, `puddlePointSpacing` apart, spanning
    /// centre ± (radius − puddlePointInset). One point = a small puddle; more points = a wider one.
    static let puddlePointSpacing: Double = 12
    static let puddlePointInset: Double = 8
    static let maxPuddlePoints: Int = 48
    /// Round 3: a puddle belongs to the glass that spilled it. Once that glass starts leaving (or for a spill with
    /// no glass nearby, at once) it dries: its encoded run shrinks (radius × (1 − u²), u = age / dryTime) and its
    /// points are gone `puddleDryTime` seconds later.
    static let puddleDryTime: Double = 1.5
    /// Puddle centres are kept inside the always-visible band (x 130…540), radius included.
    static let safeMinX: Double = 130
    static let safeMaxX: Double = 540

    // MARK: Modes

    static let maxStrikes: Int = 3
    /// Rush: difficulty tier every N glasses.
    static let rushTierEvery: Int = 8
    /// Rush patience scales with √(volume to the line / this).
    static let rushPatienceVolumeRef: Double = 11000
    /// Belts were tuned for round-1 glasses; ×1.5 bigger glasses get ×1.5 faster belts (same window in seconds).
    static let beltScale: Double = 1.5
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
