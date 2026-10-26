import Foundation

// Round 6 (ROUND-6 "Feel", REVIEW-5 §2–§5): the late game's cues, read from the snapshot. Each watcher is a small pure
// state machine (no audio, no haptics) so it is unit-tested; `FeedbackDirector` plays what they report.

/// Sand: light haptic ticks as the tip nears the angle of repose (`JugState.reposeProgress` → 1), spaced closer and
/// closer: from `slowGap` at `SoundBook.rustleStart` down to `fastGap` just before the slide. None while sand flows.
final class SandTelegraph {
    static let slowGap = 0.42
    static let fastGap = 0.06
    /// Calm (Reduce Motion / "Calmer motion"): never busier than this.
    static let calmFastGap = 0.12

    private var lastTick = -Double.infinity

    init() {}

    /// Seconds between ticks at `progress` (nil = no ticks: below the start, or nonsense). Geometric, so the ticks
    /// audibly accelerate all the way to the slide.
    static func tickGap(progress: Double, calm: Bool = false) -> Double? {
        guard progress.isFinite, progress > SoundBook.rustleStart else { return nil }
        let u = min((progress - SoundBook.rustleStart) / (1 - SoundBook.rustleStart), 1)
        let gap = slowGap * pow(fastGap / slowGap, u)
        return calm ? max(gap * 1.5, calmFastGap) : gap
    }

    /// One frame at `now` (seconds). Returns the progress to tick at, or nil.
    func update(progress: Double, flowing: Bool, live: Bool, now: Double, calm: Bool = false) -> Double? {
        guard live, !flowing, now.isFinite, let gap = Self.tickGap(progress: progress, calm: calm) else { return nil }
        if now - lastTick < gap { return nil }
        lastTick = now
        return progress
    }
}

/// Rush: the tier went up. Never for the run's first tier (a new run, or the first frames of one, only sets the
/// baseline); a tier that drops (a restarted run) just resets it. Outside Rush it forgets everything.
final class RushTierWatch {
    /// The tier seen last frame in this Rush run (nil = not in a Rush run yet).
    private(set) var lastTier: Int?

    init() {}

    /// One frame. True when the chord should play.
    func update(tier: Int, isRush: Bool) -> Bool {
        guard isRush else {
            lastTier = nil
            return false
        }
        let previous = lastTier
        lastTier = tier
        guard let before = previous else { return false }
        return tier > before && tier >= 2
    }

    func update(snapshot: GameSnapshot) -> Bool {
        var isRush = false
        if case .rush = snapshot.mode { isRush = true }
        return update(tier: snapshot.rushTier, isRush: isRush)
    }
}

/// Rush: the shared jug dipped under `lowFill`. Fires once per dip; re-arms only once the jug is back above
/// `rearmFill` (a Perfect's refill, or a new run), so hovering around 20 % never repeats it. Not on an empty jug
/// (`jugEmpty` ends the run with its own cue).
final class LowJugWatch {
    static let lowFill = 0.20
    static let rearmFill = 0.30

    private(set) var armed = false

    init() {}

    /// One frame. True when the heartbeat should play now.
    func update(fill: Double, live: Bool) -> Bool {
        guard fill.isFinite else { return false }
        if fill >= Self.rearmFill {
            armed = true
            return false
        }
        guard armed, live, fill < Self.lowFill, fill > DryJugWatch.dryFill else { return false }
        armed = false
        return true
    }

    /// Live = a playing, unpaused, ungated Rush run that this frame did not just end.
    func update(snapshot: GameSnapshot, events: [GameEvent], paused: Bool) -> Bool {
        var live = !paused && !snapshot.needsFlat && snapshot.phase == .playing
        var isRush = false
        if case .rush = snapshot.mode { isRush = true }
        if !isRush { live = false }
        for event in events {
            switch event {
            case .jugEmpty, .finished(_):
                live = false
            default:
                break
            }
        }
        return update(fill: snapshot.jug.fill, live: live)
    }
}

/// Conveyor: a served glass starts to ride off (its phase goes `.served` → `.leaving`) on a conveyor venue. Reports
/// the best hit leaving this frame (misses leave quietly: a bell on a spill would be cheering it). Phases are kept
/// per glass id for one frame only, so ids that restart with every run never confuse it.
final class ConveyorBellWatch {
    private var phases: [Int: GlassPhase] = [:]

    init() {}

    /// One frame. Call it every frame (it tracks the phases even when `conveyor` is false).
    func update(glasses: [GlassState], conveyor: Bool) -> Judgement? {
        var next: [Int: GlassPhase] = [:]
        var ding: Judgement?
        for glass in glasses {
            let before = phases[glass.id]
            next[glass.id] = glass.phase
            guard conveyor, glass.phase == .leaving, before == .served else { continue }
            guard let result = glass.result, result.isHit else { continue }
            if ding == nil || result == .perfect { ding = result }
        }
        phases = next
        return ding
    }

    func update(snapshot: GameSnapshot) -> Judgement? {
        update(glasses: snapshot.glasses, conveyor: snapshot.venue == .conveyor)
    }
}
