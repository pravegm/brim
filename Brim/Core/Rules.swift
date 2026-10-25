import CoreGraphics
import Foundation

/// Control mapping, judging, scoring and stars.
enum Rules {

    /// Lid tilt (degrees) below which the jug stays fully upright.
    static let deadZone: Double = 6

    /// Round 5 (founder decision 1, QA-2 P0-suspect): the flat gate opens at a lid tilt ≤ 12° (hinge ≥ 168°), not
    /// inside the 6° dead zone, so a Duo lying flat that reads a few degrees shy of 180° still starts. The dead zone
    /// and the jug mapping are unchanged (a phone lying flat still never dribbles).
    static let flatGateTilt: Double = 12

    /// Round 5: the lid tilt an input reports while it must hold the jug upright AND must not be read as "flat" by the
    /// gate (e.g. the hinge's closing guard). Negative, so it is outside the gate (`readsFlat` is false) and the jug
    /// stands upright (`jugAngle` clamps it to 0). The old `deadZone` value (6) now sits inside the gate.
    static let closedTilt: Double = -1

    /// Does this lid tilt open the flat gate? 0 ≤ tilt ≤ `flatGateTilt` (`closedTilt` never does).
    static func readsFlat(lidTilt t: Double) -> Bool {
        return t >= 0 && t <= flatGateTilt
    }

    /// Lid tilt → jug rotation: 0 inside the dead zone, then 1.55 × (t − 6) (lid 90° → jug ≈ 130°).
    static func jugAngle(forLidTilt t: Double) -> Double {
        let tilt: Double = CoreMath.clamp(t, 0, 90)
        if tilt < deadZone { return 0 }
        return 1.55 * (tilt - deadZone)
    }

    /// err = (top − line) / interior. Overflowed → spill. |err| within the Perfect band → perfect, ≤ 6 % great,
    /// ≤ 12 % good (either side); under by more → short; over by more than the Good band but nothing went over the
    /// rim → over (round 5, QA-2 P1-3: `spill` only when liquid really crossed the rim).
    static func judge(top: CGFloat, line: CGFloat, interior: CGFloat, overflowed: Bool, perfectBand: Double) -> Judgement {
        if overflowed { return .spill }
        let h: Double = max(1e-6, Double(interior))
        let err: Double = Double(top - line) / h
        let perfect: Double = max(0.005, perfectBand)
        let great: Double = max(CoreTuning.greatBand, perfect + 0.01)
        let good: Double = max(CoreTuning.goodBand, great + 0.02)
        let mag: Double = abs(err)
        if mag <= perfect { return .perfect }
        if mag <= great { return .great }
        if mag <= good { return .good }
        return err < 0 ? .short : .over
    }

    static func points(for j: Judgement, multiplier: Int) -> Int {
        let m: Int = max(1, multiplier)
        switch j {
        case .perfect: return CoreTuning.pointsPerfect * m
        case .great: return CoreTuning.pointsGreat * m
        case .good: return CoreTuning.pointsGood * m
        case .short, .over, .spill: return 0
        }
    }

    /// 1, 2 (streak ≥ 3), 3 (≥ 6), 5 (≥ 10).
    static func multiplier(forStreak s: Int) -> Int {
        if s >= 10 { return 5 }
        if s >= 6 { return 3 }
        if s >= 3 { return 2 }
        return 1
    }

    /// For a cleared shift: 3 = every glass a hit, ≥ 60 % Perfect and no spills; 2 = ≥ 80 % hits; else 1.
    /// (A shift that struck out is not cleared and earns 0; the session handles that.)
    static func stars(perfects: Int, hits: Int, spills: Int, total: Int) -> Int {
        if total <= 0 { return 0 }
        if hits >= total && spills == 0 && perfects * 10 >= total * 6 { return 3 }
        if hits * 10 >= total * 8 { return 2 }
        return 1
    }
}
