import CoreGraphics
import Foundation
import Testing
@testable import Brim

// MARK: - Headless balance playtest (design/BALANCE.md)
//
// A "human" (`BalanceHuman`) plays real `GameSession`s at 60 Hz with no UI: it sees the glass under the spout with a
// reaction delay, aims to stop when the level it sees plus the rise it expects still to come reaches the line (an
// anticipation it learns imperfectly, glass after glass), tips by hand (a spring with a speed limit, tremor), through a
// Duo-like hinge (30 Hz reports, noise, 5° steps) and the app's tilt filter (One-Euro + hold stabiliser, copied in
// spirit from Input/, not linked). Three seeded skill profiles: novice, casual, expert.
//
// It prints one machine-readable line per level/profile, Rush profile and Daily profile:
//   BRIM-BAL level=1-3 profile=casual clear=0.83 stars=2.1 three=0.17 perfect=0.41 ... short=0.05 dur=48.2 n=6
// Assertions are LOOSE sanity bounds (CI stays green while numbers move); the target curve is printed as WARN lines.
//
// Cost: a 60 Hz frame of a debug-build GameSession costs ~2–3 ms on CI, so a full sweep (44 levels × 3 profiles × N,
// Rush, Daily) is ~1–2 M frames. The default tier is a small smoke sample (~25 k frames); run a sweep with
// `TEST_RUNNER_BRIM_BAL=standard` (or `full`) in xcodebuild's environment, or flip `BalanceConfig.defaultTier` for one
// push. Overrides: BRIM_BAL_ATTEMPTS, BRIM_BAL_RUSH_SEEDS, BRIM_BAL_DAYS, BRIM_BAL_BUDGET (s per suite, 0 = none),
// BRIM_BAL_LEVELS (e.g. "1-1,2-7"), BRIM_BAL_PROFILES (e.g. "casual"). Every unit is seeded: a unit's result never
// depends on the tier, the budget or the thread it ran on.

// MARK: - Configuration

enum BalanceTier: String {
    case smoke, standard, full
}

enum BalanceConfig {
    /// Flip to `.standard` (~10 min of CI) or `.full` (~20+ min) for a one-off balance push; keep `.smoke` on main.
    static let defaultTier: BalanceTier = .smoke

    /// The app's frame step and the hinge model.
    static let frameDt: Double = 1.0 / 60.0
    static let hingeReportDt: Double = 1.0 / 30.0
    /// Reported hinge steps (degrees of lid tilt). The Duo is quoted at ~5° accuracy; the app filters it.
    static let hingeStep: Double = 5
    /// Seconds of play after which an attempt is abandoned (counted as `capped`).
    static let shiftCap: Double = 180
    static let dailyCap: Double = 240

    static var env: [String: String] {
        return ProcessInfo.processInfo.environment
    }

    static var tier: BalanceTier {
        if let raw = env["BRIM_BAL"], let t = BalanceTier(rawValue: raw.lowercased()) { return t }
        return defaultTier
    }

    static func int(_ key: String, _ fallback: Int) -> Int {
        if let raw = env[key], let v = Int(raw), v >= 0 { return v }
        return fallback
    }

    static func list(_ key: String) -> [String]? {
        guard let raw = env[key], !raw.isEmpty else { return nil }
        let parts: [String] = raw.split(separator: ",").map { (s: Substring) -> String in
            s.trimmingCharacters(in: .whitespaces)
        }
        return parts.isEmpty ? nil : parts
    }

    /// Wall-clock budget per suite (seconds); nil = run everything.
    static func budget(_ fallback: Double?) -> Double? {
        if let raw = env["BRIM_BAL_BUDGET"], let v = Double(raw) { return v > 0 ? v : nil }
        return fallback
    }
}

// MARK: - Skill profiles

struct BalanceProfile {
    let name: String
    /// Reaction delay (s), drawn per glass.
    let reactionMin: Double
    let reactionMax: Double
    /// The hand: spring rate (1/s) and speed limit (°/s of lid tilt).
    let omega: Double
    let maxSpeed: Double
    /// Hand tremor (° σ, slow) and hinge report noise (° σ, fast).
    let tremor: Double
    let hingeNoise: Double
    /// Tipping in to find the pour point (°/s), from this far below where it poured last time (°).
    let search: Double
    let startBack: Double
    /// Novices think in stream thickness (flows 0…1); the others in how fast the level climbs (interior heights/s),
    /// sizing up the glass by eye (`sizeNoise`, log σ).
    let prefFlow: Double
    let nearDist: Double
    let nearFlow: Double
    let sizeAware: Bool
    let farRate: Double
    let nearRate: Double
    let sizeNoise: Double
    /// Flow correction gain (°/s per unit of flow error) and the error of the hand's tilt→flow model (σ, fraction).
    let gain: Double
    let modelNoise: Double
    /// Anticipation prior (s): base + per second of the drink's lag + foam offset. Learned per key afterwards:
    /// keyMode 0 = one value for everything, 1 = per drink class, 2 = per drink.
    let antBase: Double
    let antLag: Double
    let antFoam: Double
    let keyMode: Int
    let learn: Double
    let learnNoise: Double
    /// Per-glass misjudgements: rise rate (fraction σ), aim (interior σ), a faded line's remembered height (σ).
    let rateNoise: Double
    let aimSigma: Double
    let memSigma: Double
    /// Chance per glass of over-eagerness ("just a drop more"): half the anticipation, a faster pour.
    let eager: Double
    /// Where the hand rests between pours: flat (nil) or this far below the pour point (°).
    let layBack: Double?
    /// Reads the judged top (liquid + at most a settled head) instead of the visible top.
    let judgedTop: Bool
    let topUpMargin: Double
    let maxTopUps: Int
    /// Plans against the patience ring / belt window (0 = only panics late).
    let plan: Double
    /// Pour speed multiplier for foamy drinks.
    let foamFactor: Double

    static let novice: BalanceProfile = BalanceProfile(
        name: "novice", reactionMin: 0.24, reactionMax: 0.32, omega: 7, maxSpeed: 120, tremor: 1.5, hingeNoise: 3.0,
        search: 12, startBack: 6, prefFlow: 0.5, nearDist: 0.05, nearFlow: 0.35, sizeAware: false, farRate: 0,
        nearRate: 0, sizeNoise: 0.3, gain: 20, modelNoise: 0.35, antBase: 0.25, antLag: 0, antFoam: 0, keyMode: 0,
        learn: 0.3, learnNoise: 0.05, rateNoise: 0.30, aimSigma: 0.02, memSigma: 0.06, eager: 0.15, layBack: nil,
        judgedTop: false, topUpMargin: 0.10, maxTopUps: 1, plan: 0, foamFactor: 1.0)

    static let casual: BalanceProfile = BalanceProfile(
        name: "casual", reactionMin: 0.20, reactionMax: 0.26, omega: 9, maxSpeed: 160, tremor: 1.2, hingeNoise: 2.5,
        search: 18, startBack: 6, prefFlow: 0.55, nearDist: 0.2, nearFlow: 0.25, sizeAware: true, farRate: 0.3,
        nearRate: 0.15, sizeNoise: 0.3, gain: 25, modelNoise: 0.2, antBase: 0.45, antLag: 0.4, antFoam: -0.1,
        keyMode: 1, learn: 0.4, learnNoise: 0.03, rateNoise: 0.18, aimSigma: 0.012, memSigma: 0.035, eager: 0.08,
        layBack: 12, judgedTop: false, topUpMargin: 0.05, maxTopUps: 1, plan: 0.5, foamFactor: 0.8)

    static let expert: BalanceProfile = BalanceProfile(
        name: "expert", reactionMin: 0.17, reactionMax: 0.21, omega: 11, maxSpeed: 200, tremor: 1.0, hingeNoise: 2.0,
        search: 25, startBack: 5, prefFlow: 0.6, nearDist: 0.35, nearFlow: 0.15, sizeAware: true, farRate: 0.35,
        nearRate: 0.1, sizeNoise: 0.15, gain: 30, modelNoise: 0.1, antBase: 0.55, antLag: 0.7, antFoam: -0.2,
        keyMode: 2, learn: 0.5, learnNoise: 0.015, rateNoise: 0.08, aimSigma: 0.006, memSigma: 0.015, eager: 0.03,
        layBack: 8, judgedTop: true, topUpMargin: 0.025, maxTopUps: 2, plan: 1.0, foamFactor: 0.55)

    static let all: [BalanceProfile] = [BalanceProfile.novice, BalanceProfile.casual, BalanceProfile.expert]
}

/// Standard normal from the Core RNG (Box–Muller).
private func balanceGauss(_ rng: inout CoreRNG) -> Double {
    let u: Double = max(1e-12, rng.unit())
    let v: Double = rng.unit()
    return (-2.0 * log(u)).squareRoot() * cos(2.0 * Double.pi * v)
}

// MARK: - The human

/// What the player sees in one frame (they act on a delayed copy).
struct BalancePercept {
    var t: Double
    var gid: Int? = nil
    var flow: Double = 0
    var hand: Double = 0
    var lipX: Double = 0
    var jugEmpty: Bool = false
    /// (top they read − line) / interior height.
    var d: Double = 0
    /// Visible top / interior height (the head included).
    var brim: Double = 0
    var lineVisible: Bool = true
    var x: Double = 0
    var rimHalf: Double = 0
    /// Belt speed read from the glass's motion (pt/s); nil = standing glass.
    var belt: Double? = nil
    var patience: Double? = nil
    var liquid: Liquid? = nil
    var capacity: Double = 1

    init(t: Double) {
        self.t = t
    }
}

struct BalanceHuman {
    enum Stage {
        case wait, search, pour, stopped, rest
    }

    struct StopRecord {
        var d: Double
        var r: Double
        var key: String
        var gid: Int
    }

    let profile: BalanceProfile
    var rng: CoreRNG

    // Learned (kept across attempts).
    var anticipation: [String: Double] = [:]
    var caution: [String: Double] = [:]
    var learnedPour: Double = 16

    // The current glass.
    var stage: Stage = .wait
    var gid: Int? = nil
    var command: Double = 0
    var stageT: Double = 0
    var restUntil: Double = 0
    var reaction: Double? = nil
    var lastKey: String? = nil
    var aimBias: Double = 0
    var rateMis: Double = 0
    var memErr: Double = 0
    var eager: Bool = false
    var topUps: Int = 0
    var trickle: Bool = false
    var rEst: Double = 0
    var prevD: Double? = nil
    var prevT: Double = 0
    var stopRec: StopRecord? = nil
    var bias: Double = 0
    var modelErr: Double = 0
    var kVis: Double = 0.6

    // Hand, hinge, app filter.
    var hand: Double = 0
    var handV: Double = 0
    var tremor: Double = 0
    var noise: Double = 0
    var report: Double = 0
    var nextReport: Double = 0
    var reportTimes: [Double] = []
    var reportAngles: [Double] = []
    var euro: Double? = nil
    var euroD: Double = 0
    var euroT: Double = 0
    var hold: Double? = nil
    var holdMotion: Double = 0
    var holdT: Double = 0
    var percepts: [BalancePercept] = []

    init(profile: BalanceProfile, seed: UInt64) {
        self.profile = profile
        self.rng = CoreRNG(seed: seed)
    }

    /// A new attempt: forget the moment-to-moment state, keep what was learned.
    mutating func beginRun() {
        stage = .wait
        gid = nil
        command = 0
        hand = 0
        handV = 0
        tremor = 0
        noise = 0
        report = 0
        nextReport = 0
        reportTimes.removeAll()
        reportAngles.removeAll()
        euro = nil
        euroD = 0
        hold = nil
        holdMotion = 0
        percepts.removeAll()
        stopRec = nil
        reaction = nil
        learnedPour = min(learnedPour, 20)
    }

    func key(_ l: Liquid) -> String {
        if profile.keyMode == 0 { return "all" }
        if profile.keyMode == 2 { return l.id.rawValue }
        if l.reposeDegrees > 0 { return "sand" }
        if l.lagTau >= 0.3 { return "thick" }
        if l.foamPerVolume > 0.3 { return "foam" }
        return "still"
    }

    func care(_ l: Liquid) -> Double {
        return caution[key(l)] ?? 1
    }

    func prior(_ l: Liquid) -> Double {
        let foam: Double = l.foamPerVolume > 0.3 ? profile.antFoam : 0
        return profile.antBase + profile.antLag * l.lagTau + foam
    }

    mutating func ant(_ l: Liquid) -> Double {
        let k: String = key(l)
        if let a = anticipation[k] { return a }
        let p: Double = prior(l)
        anticipation[k] = p
        return p
    }

    func restTilt() -> Double {
        guard let back = profile.layBack else { return 0 }
        return max(0, learnedPour - back)
    }

    // MARK: Seeing

    mutating func perceive(_ s: GameSnapshot, now: Double) {
        var pc: BalancePercept = BalancePercept(t: now)
        pc.flow = s.jug.flow
        pc.hand = hand
        pc.lipX = Double(s.jug.lip.x)
        pc.jugEmpty = s.jug.fill <= 0.0001
        let active: GlassState? = s.glasses.first(where: { (g: GlassState) -> Bool in
            g.phase == .filling && g.result == nil
        })
        if s.phase == .playing, let g = active {
            let interior: Double = max(1, Double(g.shape.interiorHeight))
            let liquidTop: Double = Double(g.liquidHeight)
            let visibleTop: Double = liquidTop + Double(g.foamHeight)
            let settledTop: Double = liquidTop + CoreTuning.foamSettledFraction * interior
            let top: Double = profile.judgedTop ? min(visibleTop, settledTop) : visibleTop
            pc.gid = g.id
            pc.d = (top - Double(g.lineHeight)) / interior
            pc.brim = visibleTop / interior
            pc.lineVisible = g.lineOpacity > 0.5
            pc.x = Double(g.x)
            pc.rimHalf = Double(g.shape.rimHalfWidth)
            if let prev = percepts.last, prev.gid == g.id, now > prev.t {
                let v: Double = (pc.x - prev.x) / (now - prev.t)
                if v > 2 { pc.belt = v }
            }
            pc.patience = g.patienceLeft
            pc.liquid = g.liquid
            pc.capacity = Double(GlassMath.capacity(g.shape))
        }
        percepts.append(pc)
        while percepts.count > 2 && percepts[0].t < now - 1.0 {
            percepts.removeFirst()
        }
    }

    /// The latest percept at least `delay` old.
    func delayed(_ now: Double, _ delay: Double) -> BalancePercept? {
        var i: Int = percepts.count - 1
        while i >= 0 {
            if percepts[i].t <= now - delay { return percepts[i] }
            i -= 1
        }
        return nil
    }

    mutating func newGlass(_ pd: BalancePercept, liquid: Liquid) {
        gid = pd.gid
        stage = .search
        stageT = pd.t
        lastKey = key(liquid)
        reaction = rng.range(profile.reactionMin, profile.reactionMax)
        let g1: Double = balanceGauss(&rng)
        aimBias = g1 * profile.aimSigma
        let g2: Double = balanceGauss(&rng)
        rateMis = g2 * profile.rateNoise
        let g3: Double = balanceGauss(&rng)
        memErr = g3 * profile.memSigma
        eager = rng.chance(profile.eager)
        topUps = 0
        trickle = false
        rEst = 0
        prevD = nil
        prevT = 0
        stopRec = nil
        bias = 0
        let g4: Double = balanceGauss(&rng)
        modelErr = g4 * profile.modelNoise
        let g5: Double = balanceGauss(&rng)
        let eye: Double = profile.sizeAware ? 10000 / max(1000, pd.capacity) : 0.6
        kVis = eye * exp(g5 * profile.sizeNoise)
        command = max(command, learnedPour - profile.startBack)
    }

    // MARK: Deciding

    mutating func decide(_ s: GameSnapshot, now: Double, dt: Double) {
        let p: BalanceProfile = profile
        if s.needsFlat {
            command = 0
            return
        }
        let delay: Double = reaction ?? p.reactionMax
        guard let pd = delayed(now, delay), let pgid = pd.gid, let liq = pd.liquid else {
            if stage != .rest {
                stage = .wait
                command = restTilt()
            }
            if stage == .rest && now >= restUntil { stage = .wait }
            return
        }
        if pgid != gid { newGlass(pd, liquid: liq) }
        if stage == .wait {
            stage = .search
            stageT = now
            command = max(command, learnedPour - p.startBack)
        }
        // The rise rate they see.
        if let pv = prevD, pd.t > prevT {
            let raw: Double = (pd.d - pv) / (pd.t - prevT)
            rEst += (raw - rEst) * min(1, (pd.t - prevT) / 0.15)
        }
        prevD = pd.d
        prevT = pd.t
        let dSeen: Double = pd.d + (pd.lineVisible ? 0 : memErr)
        let aim: Double = -0.004 + aimBias + (eager ? 0.01 : 0)
        let lag: Double = liq.lagTau

        if stage == .rest {
            command = 0
            if now >= restUntil {
                stage = .search
                stageT = now
                command = max(0, learnedPour - p.startBack)
            }
            return
        }
        // The jug ran dry mid-glass: lay it back for the refill.
        if pd.jugEmpty && (stage == .search || stage == .pour) {
            stage = .rest
            restUntil = now + 0.9
            command = 0
            return
        }

        switch stage {
        case .search:
            // Foamy drinks: tip in gently too (the venue's lesson).
            let gentle: Double = liq.foamPerVolume > 0.3 ? p.foamFactor : 1
            command += p.search * gentle * care(liq) * dt
            if pd.flow > 0.03 {
                learnedPour = CoreMath.clamp(0.6 * learnedPour + 0.4 * pd.hand, 8, 80)
                stage = .pour
                stageT = now
                command = min(command, pd.hand + 4)     // "it's coming": stop tipping further
            } else if command >= 85 && now - stageT > 2.5 {
                stage = .rest
                restUntil = now + 0.8
                command = 0
                return
            }
            command = CoreMath.clamp(command, 0, 88)
            shouldStop(pd, dSeen: dSeen, aim: aim, liquid: liq)
        case .pour:
            if shouldStop(pd, dSeen: dSeen, aim: aim, liquid: liq) { return }
            if pd.flow < 0.01 && now - stageT > 0.6 {
                stage = .search
                stageT = now
                return
            }
            pour(pd, dSeen: dSeen, aim: aim, liquid: liq, lag: lag, dt: dt)
        case .stopped:
            command = restTilt()
            // Top-up: once the jug has stopped, if what is still falling won't reach the line, tip straight back in.
            if pd.flow < 0.004 && now - stageT > 0.15 {
                let short: Double = aim - (dSeen + max(rEst, 0) * 0.25)
                if topUps < p.maxTopUps && short > p.topUpMargin && pd.belt == nil {
                    topUps += 1
                    trickle = true
                    stage = .search
                    stageT = now
                    command = max(command, learnedPour - 1)
                }
            }
        case .wait, .rest:
            break
        }
    }

    /// Steer the flow while pouring.
    mutating func pour(_ pd: BalancePercept, dSeen: Double, aim: Double, liquid liq: Liquid, lag: Double, dt: Double) {
        let p: BalanceProfile = profile
        let remaining: Double = aim - dSeen
        // How far is left once what they expect still to come has landed: ease off as that closes.
        let a: Double = ant(liq)
        let ahead: Double = remaining - max(rEst, 0) * a
        let k: Double = kVis
        let far: Double = p.sizeAware ? p.farRate / k : p.prefFlow
        let near: Double = p.sizeAware ? p.nearRate / k : p.nearFlow
        var f: Double = near
        if !trickle {
            let foamy: Double = liq.foamPerVolume > 0.3 ? p.foamFactor : 1
            f = far * foamy * care(liq)
            if p.nearDist > 0 && ahead < p.nearDist {
                f = near + (f - near) * CoreMath.clamp(ahead / p.nearDist, 0, 1)
            }
        }
        if eager { f *= 1.25 }
        // Time pressure: the patience ring, or the window before the glass rides out from under the stream.
        var window: Double? = nil
        if let patience = pd.patience { window = patience - 1.0 }
        if let belt = pd.belt { window = ((pd.lipX + 14) - (pd.x - pd.rimHalf)) / max(1, belt) - 0.35 }
        if let w = window {
            if p.plan > 0 && w < 6 {
                let need: Double = (remaining / max(w, 0.3)) / k * 1.15
                f = max(f, f + (min(0.95, need) - f) * p.plan)
            } else if p.plan == 0 && w < 1.5 {
                f = max(f, 0.75)
            }
        }
        f = CoreMath.clamp(f, 0.05, 0.95)
        // The hand's model: "this far past where it started pouring gives that much flow" (weir: flow ~ offset^1.5),
        // plus a slow correction from the stream they see (the pour point creeps up as the jug drains).
        let offset: Double = 15 * pow(f / 0.6, 2.0 / 3.0) * (1 + modelErr)
        let correction: Double = CoreMath.clamp((f - pd.flow) * p.gain / (1 + 4 * lag), -45, 45)
        bias = CoreMath.clamp(bias + correction * dt, -30, 40)
        command = CoreMath.clamp(learnedPour + offset + bias, 0, 88)
    }

    /// Stop when the level they read plus what they expect still to come reaches their aim (or the head nears the
    /// rim, or a belt glass is about to ride out from under the stream).
    @discardableResult
    mutating func shouldStop(_ pd: BalancePercept, dSeen: Double, aim: Double, liquid: Liquid) -> Bool {
        let r: Double = max(rEst, 0) * (1 + rateMis)
        var a: Double = ant(liquid)
        if eager { a *= 0.5 }
        let byLine: Bool = dSeen + r * a >= aim || pd.brim > 0.96
        var forced: Bool = false
        if let belt = pd.belt {
            let w: Double = ((pd.lipX + 14) - (pd.x - pd.rimHalf)) / max(1, belt)
            forced = w < 0.45
        }
        if !byLine && !forced { return false }
        if byLine, let g = pd.gid {
            stopRec = StopRecord(d: pd.d, r: r, key: key(liquid), gid: g)
        } else {
            stopRec = nil
        }
        stage = .stopped
        stageT = pd.t + (reaction ?? 0)
        command = restTilt()
        return true
    }

    // MARK: Learning

    mutating func handle(_ events: [GameEvent], _ s: GameSnapshot, now: Double) {
        for e in events {
            switch e {
            case .served(let id, let j, _):
                learn(glass: id, judgement: j, snapshot: s)
            case .jugSwapped:
                if stage == .pour || stage == .search {
                    stage = .rest
                    restUntil = (percepts.last?.t ?? now) + 0.9
                    command = 0
                }
            default:
                break
            }
        }
    }

    /// Compare where the glass was judged with where they stopped: the anticipation that would have been exact.
    mutating func learn(glass id: Int, judgement j: Judgement, snapshot s: GameSnapshot) {
        if let rec = stopRec, rec.gid == id {
            let served: GlassState? = s.glasses.first(where: { (g: GlassState) -> Bool in g.id == id })
            if rec.r > 0.03, let g = served {
                let interior: Double = max(1, Double(g.shape.interiorHeight))
                let liquidTop: Double = Double(g.liquidHeight)
                let top: Double = min(liquidTop + Double(g.foamHeight),
                                      liquidTop + CoreTuning.foamSettledFraction * interior)
                let n: Double = balanceGauss(&rng)
                let dFinal: Double = (top - Double(g.lineHeight)) / interior + n * profile.learnNoise
                let aTrue: Double = CoreMath.clamp((dFinal - rec.d) / rec.r, -0.5, 2.5)
                let old: Double = anticipation[rec.key] ?? aTrue
                anticipation[rec.key] = old + (aTrue - old) * profile.learn
            }
            stopRec = nil
        }
        // Burnt by a spill: more careful with that drink next time; clean pours restore confidence.
        if let k = lastKey {
            let c: Double = caution[k] ?? 1
            let raw: String = j.rawValue
            if raw == "spill" || raw == "over" {
                caution[k] = max(0.5, c * 0.8)
            } else if raw != "short" {
                caution[k] = min(1, c * (raw == "good" ? 1.05 : 1.15))
            }
        }
    }

    // MARK: The hand, the hinge, the app's filter

    static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let r: Double = 2 * Double.pi * cutoff * dt
        return r / (r + 1)
    }

    mutating func output(now: Double, dt: Double) -> Double {
        let p: BalanceProfile = profile
        let target: Double = command
        let omega: Double = target < hand - 1 ? p.omega * 1.6 : p.omega
        // Critically damped spring (closed form) with a speed limit.
        let x0: Double = hand - target
        let decay: Double = exp(-omega * dt)
        let nx: Double = (x0 + (handV + omega * x0) * dt) * decay
        handV = (handV - omega * (handV + omega * x0) * dt) * decay
        var nh: Double = target + nx
        let maxStep: Double = p.maxSpeed * dt
        if nh - hand > maxStep {
            nh = hand + maxStep
            handV = min(handV, p.maxSpeed)
        }
        if hand - nh > maxStep {
            nh = hand - maxStep
            handV = max(handV, -p.maxSpeed)
        }
        hand = CoreMath.clamp(nh, 0, 90)
        // Tremor (slow) and hinge noise (fast), Ornstein–Uhlenbeck.
        let g1: Double = balanceGauss(&rng)
        tremor += -tremor * dt / 0.3 + p.tremor * (2 * dt / 0.3).squareRoot() * g1
        let g2: Double = balanceGauss(&rng)
        noise += -noise * dt / 0.08 + p.hingeNoise * (2 * dt / 0.08).squareRoot() * g2
        let lid: Double = hand + (hand > 0.5 ? tremor : 0)
        // Hinge reports at 30 Hz, in steps (a phone flat on the table reports nothing new).
        if now >= nextReport {
            nextReport = now + BalanceConfig.hingeReportDt
            let raw: Double = hand > 1 ? CoreMath.clamp(lid + noise, 0, 90) : hand
            report = (raw / BalanceConfig.hingeStep).rounded() * BalanceConfig.hingeStep
            reportTimes.append(now)
            reportAngles.append(report)
            if reportTimes.count > 12 {
                reportTimes.removeFirst()
                reportAngles.removeFirst()
            }
        }
        // One-Euro (minCutoff 2.0, β 0.12, dCutoff 1.5), as in Input/TiltFilters.
        var x: Double = report
        if let e = euro {
            let edt: Double = CoreMath.clamp(now - euroT, 1.0 / 240.0, 0.2)
            euroT = now
            euroD += ((x - e) / edt - euroD) * BalanceHuman.alpha(1.5, edt)
            let cutoff: Double = 2.0 + 0.12 * abs(euroD)
            x = e + (x - e) * BalanceHuman.alpha(cutoff, edt)
        } else {
            euroT = now
        }
        euro = x
        // Hold stabiliser: filters hard while the reports hold still, gets out of the way while they move.
        if let h = hold {
            let hdt: Double = CoreMath.clamp(now - holdT, 1.0 / 240.0, 0.2)
            holdT = now
            var speed: Double = 0
            let n: Int = reportTimes.count
            if n >= 2 && now - reportTimes[n - 1] <= 0.25 {
                var i: Int = n - 1
                while i > 0 && reportTimes[n - 1] - reportTimes[i - 1] <= 0.25 {
                    i -= 1
                }
                if i < n - 1 {
                    speed = abs(reportAngles[n - 1] - reportAngles[i]) / max(reportTimes[n - 1] - reportTimes[i], 1.0 / 60.0)
                } else {
                    speed = abs(reportAngles[n - 1] - reportAngles[n - 2]) / (1.0 / 30.0)
                }
            }
            let bySpeed: Double = CoreMath.clamp((speed - 6) / 14, 0, 1)
            let byDeviation: Double = CoreMath.clamp((abs(x - h) - 4) / 4, 0, 1)
            let u: Double = max(bySpeed, byDeviation)
            let k: Double = max(u * u * (3 - 2 * u), holdMotion * exp(-hdt / 0.12))
            holdMotion = k
            let rr: Double = 2 * Double.pi * 0.6 * hdt
            let rest: Double = rr / (rr + 1)
            hold = h + (x - h) * (rest + (1 - rest) * k)
        } else {
            hold = x
            holdT = now
        }
        return CoreMath.clamp(hold ?? 0, 0, 90)
    }
}

// MARK: - Running attempts

struct BalanceSpec {
    var mode: GameMode
    var seed: UInt64
    var cap: Double
}

struct BalanceAttempt {
    var cleared: Bool
    var stars: Int
    var judgements: [Judgement]
    var score: Int
    var duration: Double
    var capped: Bool
    var frames: Int
}

/// One player's sequence of attempts (learning carries from one to the next). Mutated only by the thread running it.
final class BalanceChain {
    let label: String
    let profileIndex: Int
    let specs: [BalanceSpec]
    var human: BalanceHuman
    var results: [BalanceAttempt] = []

    init(label: String, profileIndex: Int, seed: UInt64, specs: [BalanceSpec]) {
        self.label = label
        self.profileIndex = profileIndex
        self.specs = specs
        self.human = BalanceHuman(profile: BalanceProfile.all[profileIndex], seed: seed)
    }
}

struct BalanceStats {
    var attempts: Int = 0
    var clears: Int = 0
    var stars: Int = 0
    var threeStars: Int = 0
    var capped: Int = 0
    var frames: Int = 0
    var glasses: Int = 0
    var perfect: Int = 0
    var great: Int = 0
    var good: Int = 0
    var short: Int = 0
    var over: Int = 0
    var spill: Int = 0
    var duration: Double = 0
    var score: Int = 0

    mutating func add(_ a: BalanceAttempt) {
        attempts += 1
        if a.cleared { clears += 1 }
        stars += a.stars
        if a.stars >= 3 { threeStars += 1 }
        if a.capped { capped += 1 }
        frames += a.frames
        duration += a.duration
        score += a.score
        for j in a.judgements {
            glasses += 1
            switch j.rawValue {
            case "perfect": perfect += 1
            case "great": great += 1
            case "good": good += 1
            case "short": short += 1
            case "over": over += 1
            case "spill": spill += 1
            default: break
            }
        }
    }

    mutating func merge(_ o: BalanceStats) {
        attempts += o.attempts
        clears += o.clears
        stars += o.stars
        threeStars += o.threeStars
        capped += o.capped
        frames += o.frames
        glasses += o.glasses
        perfect += o.perfect
        great += o.great
        good += o.good
        short += o.short
        over += o.over
        spill += o.spill
        duration += o.duration
        score += o.score
    }

    func per(_ n: Int) -> Double {
        return attempts > 0 ? Double(n) / Double(attempts) : 0
    }

    func frac(_ n: Int) -> Double {
        return glasses > 0 ? Double(n) / Double(glasses) : 0
    }

    var clearRate: Double { return per(clears) }
    var meanStars: Double { return per(stars) }
    var threeRate: Double { return per(threeStars) }
    var meanDuration: Double { return attempts > 0 ? duration / Double(attempts) : 0 }
    var meanGlasses: Double { return per(glasses) }
    var meanScore: Double { return per(score) }
}

enum BalanceRun {
    static let layout: WorldLayout = WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: true)

    static func now() -> Double {
        return ProcessInfo.processInfo.systemUptime
    }

    static func f2(_ v: Double) -> String {
        return String(format: "%.2f", v)
    }

    static func f1(_ v: Double) -> String {
        return String(format: "%.1f", v)
    }

    /// Print + flush (CI's build.log captures the test process's stdout).
    static func say(_ line: String) {
        print(line)
        fflush(stdout)
    }

    static func play(_ spec: BalanceSpec, human: inout BalanceHuman) -> BalanceAttempt {
        let s: GameSession = GameSession(mode: spec.mode, layout: layout, seed: spec.seed)
        human.beginRun()
        let dt: Double = BalanceConfig.frameDt
        var now: Double = 0
        var frames: Int = 0
        var judged: [Judgement] = []
        while !s.isFinished && now < spec.cap {
            let before: GameSnapshot = s.snapshot
            human.perceive(before, now: now)
            human.decide(before, now: now, dt: dt)
            let tilt: Double = human.output(now: now, dt: dt)
            let events: [GameEvent] = s.step(dt: dt, tilt: tilt)
            for e in events {
                if case .served(_, let j, _) = e { judged.append(j) }
            }
            human.handle(events, s.snapshot, now: now)
            now += dt
            frames += 1
        }
        if let r = s.result {
            return BalanceAttempt(cleared: r.cleared, stars: r.stars, judgements: judged, score: r.score,
                                  duration: s.snapshot.time, capped: false, frames: frames)
        }
        return BalanceAttempt(cleared: false, stars: 0, judgements: judged, score: s.snapshot.score, duration: now,
                              capped: true, frames: frames)
    }

    /// Runs the chains breadth-first: round r plays every chain's r-th attempt, in parallel. A round that starts
    /// after the deadline is skipped (so a budget trims attempts evenly; it never changes a unit's result).
    static func run(_ chains: [BalanceChain], budget: Double?) -> (frames: Int, wall: Double, skipped: Int) {
        let start: Double = now()
        var rounds: Int = 0
        for c in chains { rounds = max(rounds, c.specs.count) }
        var r: Int = 0
        while r < rounds {
            if let b = budget, now() - start > b { break }
            let round: Int = r
            DispatchQueue.concurrentPerform(iterations: chains.count) { (i: Int) -> Void in
                let c: BalanceChain = chains[i]
                if round >= c.specs.count { return }
                var h: BalanceHuman = c.human
                let a: BalanceAttempt = BalanceRun.play(c.specs[round], human: &h)
                c.human = h
                c.results.append(a)
            }
            r += 1
        }
        var frames: Int = 0
        var skipped: Int = 0
        for c in chains {
            for a in c.results { frames += a.frames }
            skipped += c.specs.count - c.results.count
        }
        return (frames: frames, wall: now() - start, skipped: skipped)
    }

    static func profileIndices() -> [Int] {
        guard let names = BalanceConfig.list("BRIM_BAL_PROFILES") else { return [0, 1, 2] }
        var out: [Int] = []
        var i: Int = 0
        while i < BalanceProfile.all.count {
            if names.contains(BalanceProfile.all[i].name) { out.append(i) }
            i += 1
        }
        return out.isEmpty ? [0, 1, 2] : out
    }

    static func timing(_ suite: String, _ t: (frames: Int, wall: Double, skipped: Int), attempts: Int) {
        let fps: Double = t.wall > 0 ? Double(t.frames) / t.wall : 0
        say("BRIM-BAL timing suite=\(suite) tier=\(BalanceConfig.tier.rawValue) attempts=\(attempts) skipped=\(t.skipped) "
            + "frames=\(t.frames) wall=\(f1(t.wall)) fps=\(Int(fps.rounded()))")
    }

    static func warn(_ text: String) {
        say("BRIM-BAL WARN " + text)
    }
}

// MARK: - The suites

@Suite(.serialized)
struct BalanceTests {

    /// Level seeds: one per (level, attempt), shared by every profile so they face the same glasses.
    private func levelSeed(_ l: Level, attempt: Int) -> UInt64 {
        let venue: Int = venueNumber(l)
        return UInt64(101 + attempt * 7919 + l.index * 31 + venue * 977)
    }

    /// 1…6, as in the level ids.
    private func venueNumber(_ l: Level) -> Int {
        var n: Int = 1
        for v in VenueID.allCases {
            if v == l.venue { return n }
            n += 1
        }
        return n
    }

    /// (level id, profile index, attempts) for the chosen tier.
    private func levelUnits() -> [(id: String, profile: Int, attempts: Int)] {
        let tier: BalanceTier = BalanceConfig.tier
        var out: [(id: String, profile: Int, attempts: Int)] = []
        if tier == .smoke && BalanceConfig.list("BRIM_BAL_LEVELS") == nil {
            let smoke: [(id: String, profile: Int, attempts: Int)] = [
                (id: "1-1", profile: 0, attempts: BalanceConfig.int("BRIM_BAL_ATTEMPTS", 3)),
                (id: "2-2", profile: 1, attempts: BalanceConfig.int("BRIM_BAL_ATTEMPTS", 1)),
                (id: "4-4", profile: 1, attempts: BalanceConfig.int("BRIM_BAL_ATTEMPTS", 1)),
                (id: "5-5", profile: 1, attempts: BalanceConfig.int("BRIM_BAL_ATTEMPTS", 1)),
                (id: "3-4", profile: 2, attempts: BalanceConfig.int("BRIM_BAL_ATTEMPTS", 1)),
                (id: "4-8", profile: 2, attempts: BalanceConfig.int("BRIM_BAL_ATTEMPTS", 1)),
            ]
            for u in smoke where LevelCatalog.level(u.id) != nil { out.append(u) }
            return out
        }
        let attempts: Int = BalanceConfig.int("BRIM_BAL_ATTEMPTS", tier == .full ? 4 : (tier == .standard ? 2 : 1))
        let only: [String]? = BalanceConfig.list("BRIM_BAL_LEVELS")
        for l in LevelCatalog.levels {
            if let ids = only, !ids.contains(l.id) { continue }
            for p in BalanceRun.profileIndices() {
                out.append((id: l.id, profile: p, attempts: attempts))
            }
        }
        return out
    }

    @Test func campaignCurve() {
        let units: [(id: String, profile: Int, attempts: Int)] = levelUnits()
        var chains: [BalanceChain] = []
        for u in units {
            guard let l = LevelCatalog.level(u.id) else { continue }
            var specs: [BalanceSpec] = []
            var a: Int = 0
            while a < u.attempts {
                specs.append(BalanceSpec(mode: .shift(l.id), seed: levelSeed(l, attempt: a), cap: BalanceConfig.shiftCap))
                a += 1
            }
            let humanSeed: UInt64 = UInt64(1000 * venueNumber(l) + l.index * 7 + u.profile * 101 + 17)
            chains.append(BalanceChain(label: l.id, profileIndex: u.profile, seed: humanSeed, specs: specs))
        }
        let tier: BalanceTier = BalanceConfig.tier
        let budget: Double? = BalanceConfig.budget(tier == .smoke ? nil : (tier == .full ? 900 : 600))
        BalanceRun.say("BRIM-BAL meta model=1 hz=60 hinge=\(Int(BalanceConfig.hingeStep)) tier=\(tier.rawValue) "
                       + "chains=\(chains.count)")
        let t = BalanceRun.run(chains, budget: budget)

        // Per level × profile.
        var byKey: [String: BalanceStats] = [:]
        var total: BalanceStats = BalanceStats()
        for c in chains {
            var st: BalanceStats = BalanceStats()
            for a in c.results { st.add(a) }
            byKey[c.label + "|" + String(c.profileIndex)] = st
            total.merge(st)
            if st.attempts == 0 { continue }
            let name: String = BalanceProfile.all[c.profileIndex].name
            var line: String = "BRIM-BAL level=\(c.label) profile=\(name) clear=\(BalanceRun.f2(st.clearRate))"
            line += " stars=\(BalanceRun.f1(st.meanStars)) three=\(BalanceRun.f2(st.threeRate))"
            line += " perfect=\(BalanceRun.f2(st.frac(st.perfect))) great=\(BalanceRun.f2(st.frac(st.great)))"
            line += " good=\(BalanceRun.f2(st.frac(st.good))) spill=\(BalanceRun.f2(st.frac(st.spill)))"
            line += " over=\(BalanceRun.f2(st.frac(st.over))) short=\(BalanceRun.f2(st.frac(st.short)))"
            line += " dur=\(BalanceRun.f1(st.meanDuration)) n=\(st.attempts)"
            BalanceRun.say(line)
        }
        BalanceRun.timing("levels", t, attempts: total.attempts)

        // Venue summaries and the target curve (design/BALANCE.md §2), as WARN lines.
        func stats(_ id: String, _ p: Int) -> BalanceStats? {
            guard let s = byKey[id + "|" + String(p)], s.attempts > 0 else { return nil }
            return s
        }
        for v in VenueID.allCases {
            let levels: [Level] = LevelCatalog.levels(in: v)
            for p in 0..<BalanceProfile.all.count {
                var sum: BalanceStats = BalanceStats()
                var count: Int = 0
                for l in levels {
                    if let s = stats(l.id, p) {
                        sum.merge(s)
                        count += 1
                    }
                }
                guard count > 0, let firstLevel = levels.first else { continue }
                let vn: Int = venueNumber(firstLevel)
                var line: String = "BRIM-BAL venue=\(vn) profile=\(BalanceProfile.all[p].name) levels=\(count)"
                line += " clear=\(BalanceRun.f2(sum.clearRate)) stars=\(BalanceRun.f1(sum.meanStars))"
                line += " three=\(BalanceRun.f2(sum.threeRate)) perfect=\(BalanceRun.f2(sum.frac(sum.perfect)))"
                line += " dur=\(BalanceRun.f1(sum.meanDuration))"
                BalanceRun.say(line)
            }
        }
        for id in ["1-1", "1-2", "1-3", "1-4"] {
            if let s = stats(id, 0), s.attempts >= 3, s.clearRate < 0.85 {
                BalanceRun.warn("novice clears \(id) \(BalanceRun.f2(s.clearRate)) < 0.85")
            }
        }
        for v in 2...5 {
            if let first = stats("\(v)-1", 1), let last = stats("\(v - 1)-8", 1), first.attempts >= 2, last.attempts >= 2,
               first.meanStars + 0.25 < last.meanStars {
                BalanceRun.warn("casual: \(v)-1 (\(BalanceRun.f1(first.meanStars))★) is harder than \(v - 1)-8 "
                                + "(\(BalanceRun.f1(last.meanStars))★)")
            }
        }
        var casualLevels: Int = 0
        var casualThreeLikely: Int = 0
        var expertLevels: Int = 0
        var expertAnyClear: Int = 0
        var expertClearSum: Double = 0
        for l in LevelCatalog.levels {
            if let s = stats(l.id, 1), s.attempts >= 2 {
                casualLevels += 1
                // Chance of a 3★ within five tries.
                if 1 - pow(1 - s.threeRate, 5) >= 0.5 { casualThreeLikely += 1 }
            }
            if let s = stats(l.id, 2) {
                expertLevels += 1
                expertClearSum += s.clearRate
                if s.clears > 0 {
                    expertAnyClear += 1
                } else {
                    BalanceRun.warn("expert never cleared \(l.id) (n=\(s.attempts))")
                }
            }
        }
        if casualLevels >= 10 {
            let share: Double = Double(casualThreeLikely) / Double(casualLevels)
            if share < 0.25 || share > 0.6 {
                BalanceRun.warn("casual likely 3★ (within 5 tries) on \(BalanceRun.f2(share)) of levels, target ~0.40")
            }
        }
        if expertLevels >= 10 && expertClearSum / Double(expertLevels) < 0.9 {
            BalanceRun.warn("expert mean clear \(BalanceRun.f2(expertClearSum / Double(expertLevels))) < 0.90")
        }

        // Loose sanity bounds (hard).
        #expect(total.attempts > 0, "no attempts ran")
        let cappedShare: Double = total.attempts > 0 ? Double(total.capped) / Double(total.attempts) : 0
        #expect(cappedShare <= 0.1, "\(total.capped) of \(total.attempts) attempts never finished")
        if let s = stats("1-1", 0), s.attempts >= 3 {
            // A first-timer clears the first shift (model: ~90 %); the bar is far below that so CI only flags a break.
            #expect(s.clears >= 1, "novice never cleared 1-1 in \(s.attempts) tries")
            if s.attempts >= 6 { #expect(s.clearRate >= 0.5, "novice clears 1-1 only \(s.clearRate)") }
        }
        if expertLevels >= 20 {
            let share: Double = Double(expertAnyClear) / Double(expertLevels)
            #expect(share >= 0.75, "experts cleared only \(expertAnyClear) of \(expertLevels) levels")
        }
    }

    @Test func rushRuns() {
        let tier: BalanceTier = BalanceConfig.tier
        let seeds: Int = BalanceConfig.int("BRIM_BAL_RUSH_SEEDS", tier == .full ? 12 : (tier == .standard ? 4 : 1))
        let cap: Double = tier == .smoke ? 60 : 600
        let perChain: Int = tier == .full ? 3 : 2
        let profiles: [Int] = tier == .smoke && BalanceConfig.list("BRIM_BAL_PROFILES") == nil ? [1] : BalanceRun.profileIndices()
        var chains: [BalanceChain] = []
        for p in profiles {
            var k: Int = 0
            var block: Int = 0
            while k < seeds {
                var specs: [BalanceSpec] = []
                var j: Int = 0
                while j < perChain && k < seeds {
                    specs.append(BalanceSpec(mode: .rush, seed: UInt64(5000 + k), cap: cap))
                    j += 1
                    k += 1
                }
                chains.append(BalanceChain(label: "rush", profileIndex: p, seed: UInt64(77 + p * 101 + block * 13),
                                           specs: specs))
                block += 1
            }
        }
        let budget: Double? = BalanceConfig.budget(tier == .smoke ? nil : (tier == .full ? 400 : 240))
        let t = BalanceRun.run(chains, budget: budget)
        var total: BalanceStats = BalanceStats()
        var minGlasses: Int = Int.max
        for p in profiles {
            var st: BalanceStats = BalanceStats()
            for c in chains where c.profileIndex == p {
                for a in c.results {
                    st.add(a)
                    minGlasses = min(minGlasses, a.judgements.count)
                }
            }
            total.merge(st)
            if st.attempts == 0 { continue }
            let name: String = BalanceProfile.all[p].name
            var line: String = "BRIM-BAL rush profile=\(name) runs=\(st.attempts) glasses=\(BalanceRun.f1(st.meanGlasses))"
            line += " dur=\(BalanceRun.f1(st.meanDuration)) perfect=\(BalanceRun.f2(st.frac(st.perfect)))"
            line += " spill=\(BalanceRun.f2(st.frac(st.spill))) over=\(BalanceRun.f2(st.frac(st.over)))"
            line += " short=\(BalanceRun.f2(st.frac(st.short))) score=\(Int(st.meanScore.rounded())) capped=\(st.capped)"
            BalanceRun.say(line)
            if tier != .smoke {
                if name == "casual" && (st.meanDuration < 120 || st.meanDuration > 180) {
                    BalanceRun.warn("rush casual run \(BalanceRun.f1(st.meanDuration)) s, target 120–180")
                }
                if name == "expert" && (st.meanDuration < 300 || st.meanDuration > 480) {
                    BalanceRun.warn("rush expert run \(BalanceRun.f1(st.meanDuration)) s, target 300–480")
                }
            }
        }
        BalanceRun.timing("rush", t, attempts: total.attempts)
        #expect(total.attempts > 0, "no Rush runs")
        #expect(minGlasses >= 1, "a Rush run served no glass")
        for p in profiles where BalanceProfile.all[p].name == "expert" {
            var st: BalanceStats = BalanceStats()
            for c in chains where c.profileIndex == p {
                for a in c.results { st.add(a) }
            }
            if st.attempts >= 2 {
                #expect(st.meanDuration >= 30 && st.meanDuration <= 600, "expert Rush runs \(st.meanDuration) s")
            }
        }
    }

    @Test func dailyPours() {
        let tier: BalanceTier = BalanceConfig.tier
        let days: Int = BalanceConfig.int("BRIM_BAL_DAYS", tier == .full ? 20 : (tier == .standard ? 6 : 1))
        let perChain: Int = tier == .full ? 5 : 3
        let profiles: [Int] = tier == .smoke && BalanceConfig.list("BRIM_BAL_PROFILES") == nil ? [1] : BalanceRun.profileIndices()
        var chains: [BalanceChain] = []
        for p in profiles {
            var d: Int = 0
            var block: Int = 0
            while d < days {
                var specs: [BalanceSpec] = []
                var j: Int = 0
                while j < perChain && d < days {
                    // The same player comes back day after day (learning carries).
                    specs.append(BalanceSpec(mode: .daily(300 + d), seed: UInt64(300 + d), cap: BalanceConfig.dailyCap))
                    j += 1
                    d += 1
                }
                chains.append(BalanceChain(label: "daily", profileIndex: p, seed: UInt64(999 + p * 101 + block * 13),
                                           specs: specs))
                block += 1
            }
        }
        let budget: Double? = BalanceConfig.budget(tier == .smoke ? nil : (tier == .full ? 300 : 180))
        let t = BalanceRun.run(chains, budget: budget)
        var total: BalanceStats = BalanceStats()
        var minGlasses: Int = Int.max
        for p in profiles {
            var st: BalanceStats = BalanceStats()
            for c in chains where c.profileIndex == p {
                for a in c.results {
                    st.add(a)
                    minGlasses = min(minGlasses, a.judgements.count)
                }
            }
            total.merge(st)
            if st.attempts == 0 { continue }
            let name: String = BalanceProfile.all[p].name
            var line: String = "BRIM-BAL daily profile=\(name) days=\(st.attempts) clear=\(BalanceRun.f2(st.clearRate))"
            line += " perfect=\(BalanceRun.f2(st.frac(st.perfect))) spill=\(BalanceRun.f2(st.frac(st.spill)))"
            line += " over=\(BalanceRun.f2(st.frac(st.over))) short=\(BalanceRun.f2(st.frac(st.short)))"
            line += " dur=\(BalanceRun.f1(st.meanDuration)) score=\(Int(st.meanScore.rounded()))"
            BalanceRun.say(line)
            if name == "casual" && st.attempts >= 5 && st.clearRate < 0.7 {
                BalanceRun.warn("daily casual clear \(BalanceRun.f2(st.clearRate)) < 0.70")
            }
        }
        BalanceRun.timing("daily", t, attempts: total.attempts)
        #expect(total.attempts > 0, "no Daily runs")
        #expect(total.capped == 0, "\(total.capped) Daily runs never finished")
        #expect(minGlasses >= 3, "a Daily run ended after \(minGlasses) glasses")
    }
}
