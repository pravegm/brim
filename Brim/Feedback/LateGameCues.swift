import CoreGraphics
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

/// Conveyor: a served glass starts to ride off (its phase goes `.served` → `.leaving`). Reports the best hit leaving
/// this frame (misses leave quietly: a bell on a spill would be cheering it). Glasses are tracked by id for one frame
/// only, so ids that restart with every run never confuse it.
///
/// Round 7 (QA-3 P2-4): the director asks `rideOff(snapshot:)`, which rings only for a glass that really rode a belt:
/// it moved while `.served` (Core carries a served belt glass on with the belt for `resultHold`; a counter glass
/// stands still until it leaves). That is the Scene's rule too (`SceneGlass.rodeBelt`), so the bell's sound and its
/// flick agree, and neither depends on the venue at that instant: at Rush's tier 2→3 change the last Soda glass
/// leaves silently, and at 3→4 the last belt glass still rings although the room is already turning into the Diner.
final class ConveyorBellWatch {
    /// A served glass that has moved more than this (pt) rode a belt.
    static let rideThreshold: CGFloat = 0.5

    private struct Track {
        var id: Int
        var phase: GlassPhase
        /// x when it was first seen `.served` (nil before).
        var servedX: CGFloat?
        var rode: Bool
    }

    /// Last frame's glasses, and a second buffer swapped in each frame (no per-frame allocation once they have held
    /// the few glasses on the counter).
    private var tracks: [Track] = []
    private var scratch: [Track] = []

    init() {
        tracks.reserveCapacity(8)
        scratch.reserveCapacity(8)
    }

    /// One frame. Call it every frame (it tracks the glasses even when `conveyor` is false). `conveyor`: the glasses
    /// are on a conveyor venue, so any served glass counts (the round-6 rule, kept for callers that know the venue).
    func update(glasses: [GlassState], conveyor: Bool) -> Judgement? {
        return step(glasses, gate: conveyor, needsRide: false)
    }

    /// The round-6 rule, from the snapshot's venue.
    func update(snapshot: GameSnapshot) -> Judgement? {
        return update(glasses: snapshot.glasses, conveyor: snapshot.venue == .conveyor)
    }

    /// Round 7: only a glass that rode a belt (it moved while served), whatever the venue is this frame.
    func rideOff(glasses: [GlassState]) -> Judgement? {
        return step(glasses, gate: true, needsRide: true)
    }

    func rideOff(snapshot: GameSnapshot) -> Judgement? {
        return rideOff(glasses: snapshot.glasses)
    }

    private func step(_ glasses: [GlassState], gate: Bool, needsRide: Bool) -> Judgement? {
        scratch.removeAll(keepingCapacity: true)
        var ding: Judgement?
        for glass in glasses {
            var before: Track?
            for t in tracks where t.id == glass.id {
                before = t
                break
            }
            var servedX: CGFloat? = before?.servedX
            var rode: Bool = before?.rode ?? false
            if glass.phase == .served {
                if let sx = servedX {
                    if abs(glass.x - sx) > ConveyorBellWatch.rideThreshold { rode = true }
                } else {
                    servedX = glass.x
                }
            }
            scratch.append(Track(id: glass.id, phase: glass.phase, servedX: servedX, rode: rode))
            guard gate, glass.phase == .leaving, let b = before, b.phase == .served else { continue }
            if needsRide && !rode { continue }
            guard let result = glass.result, result.isHit else { continue }
            if ding == nil || result == .perfect { ding = result }
        }
        let last = tracks
        tracks = scratch
        scratch = last
        return ding
    }
}
