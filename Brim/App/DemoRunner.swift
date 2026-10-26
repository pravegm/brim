import CoreGraphics
import Foundation

/// One served glass, as the results recap draws it: the glass's shape with its liquid at the level it was served at,
/// against its line (REVIEW-1 P1-11).
struct GlassRecap: Equatable {
    var shape: GlassShape
    /// Liquid top / interior height (may exceed 1 for a spill).
    var level: Double
    /// Foam top / interior height (== level when there's no head).
    var foamLevel: Double
    /// Fill line / interior height.
    var line: Double
    var top: RGBA
    var bottom: RGBA
    var foam: RGBA?
    var judgement: Judgement
    /// Round 8 (REVIEW-6 N3): an order the shift never reached (struck out first): drawn as a faint outline with its
    /// line, no liquid and no verdict. `judgement` means nothing for a ghost.
    var ghost = false

    /// The unserved order `order`, as a ghost.
    init(ghostOf order: GlassOrder) {
        let shape = GlassCatalog.shape(order.glass)
        let liquid = LiquidCatalog.liquid(order.liquid)
        self.shape = shape
        level = 0
        foamLevel = 0
        line = order.line
        top = liquid.top
        bottom = liquid.bottom
        foam = liquid.foam
        judgement = .short
        ghost = true
    }

    init(glass: GlassState, judgement: Judgement) {
        let interior = max(Double(glass.shape.interiorHeight), 1)
        shape = glass.shape
        level = max(Double(glass.liquidHeight), 0) / interior
        foamLevel = max(Double(glass.liquidHeight + glass.foamHeight), 0) / interior
        line = Double(glass.lineHeight) / interior
        top = glass.liquid.top
        bottom = glass.liquid.bottom
        foam = glass.liquid.foam
        self.judgement = judgement
    }

    /// The served glass in a snapshot (it's still on screen, phase `.served`, when the event fires).
    static func from(_ snapshot: GameSnapshot, glassID: Int, judgement: Judgement) -> GlassRecap? {
        guard let glass = snapshot.glasses.first(where: { $0.id == glassID }) else { return nil }
        return GlassRecap(glass: glass, judgement: judgement)
    }
}

/// Plays sessions headless with the autopilot (REVIEW-1 P1-8: demo states are played, never invented). DEBUG demo
/// runs use it for `screen=results` (a real finished run) and `streak=N` (the run is played up to a real N-Perfect
/// streak before the live frames).
@MainActor
enum DemoRunner {
    struct Progress {
        var recap: [GlassRecap] = []
        var finished: RunResult?
        var seconds: Double = 0
        var served = 0
    }

    /// The canvas headless runs use: the world is the same on every device; no fold, so no flat gate.
    static var headlessLayout: WorldLayout {
        WorldLayout.make(canvas: CGSize(width: 669, height: 951), hasFold: false)
    }

    /// Steps `session` with `pilot` at 60 Hz until `stop` says so, the run finishes, or `maxSeconds` of game time pass.
    static func advance(_ session: GameSession, pilot: TiltSource, maxSeconds: Double,
                        stop: (GameSnapshot, [GameEvent]) -> Bool) -> Progress {
        var progress = Progress()
        let dt = 1.0 / 60.0
        var t = 0.0
        while t < maxSeconds {
            let events = session.step(dt: dt, tilt: pilot.tilt(at: t))
            t += dt
            let snapshot = session.snapshot
            for event in events {
                switch event {
                case let .served(id, judgement, _):
                    progress.served += 1
                    if let recap = GlassRecap.from(snapshot, glassID: id, judgement: judgement) {
                        progress.recap.append(recap)
                    }
                case let .finished(result):
                    progress.finished = result
                default:
                    break
                }
            }
            if progress.finished != nil || session.isFinished || stop(snapshot, events) { break }
        }
        progress.seconds = t
        if progress.finished == nil { progress.finished = session.result }
        return progress
    }

    /// The demo pilot: the autopilot in `style`, with glass `missAt` (1-based, demo `missAt=N`) poured by the `over`
    /// autopilot instead (an honest one-miss run, round 8). `over` aims +18 % (±2.5 %) past the line, always outside
    /// the 12 % Good band, where `short`'s −16 % (±6 %) can still land a Good. nil / < 1 = the plain autopilot.
    static func pilot(style: AutopilotStyle, missAt: Int?, snapshot: @escaping () -> GameSnapshot?) -> TiltSource {
        let base = AutopilotTiltSource(style: style, snapshot: snapshot)
        guard let missAt, missAt >= 1 else { return base }
        let miss = AutopilotTiltSource(style: .over, snapshot: snapshot)
        return DemoMissPilot(base: base, miss: miss, missAt: missAt, snapshot: snapshot)
    }

    /// A whole run of `mode`, played by the autopilot. Always returns a result (a capped run is summarised from its
    /// last snapshot).
    static func playRun(mode: GameMode, style: AutopilotStyle, seed: UInt64,
                        missAt: Int? = nil) -> (RunResult, [GlassRecap]) {
        let session = GameSession(mode: mode, layout: headlessLayout, seed: seed)
        let pilot = Self.pilot(style: style, missAt: missAt, snapshot: { session.snapshot })
        let progress = advance(session, pilot: pilot, maxSeconds: 480, stop: { _, _ in false })
        let s = session.snapshot
        let result = progress.finished ?? RunResult(mode: mode, score: s.score, stars: 0, perfects: s.perfects,
                                                    bestStreak: s.streak, judgements: progress.recap.map { $0.judgement },
                                                    poured: 0, cleared: false)
        print(String(format: "BRIM-T demo run %@ score=%ld stars=%ld glasses=%ld perfects=%ld t=%.1f",
                     GameController.title(for: mode), result.score, result.stars, result.judgements.count,
                     result.perfects, progress.seconds))
        return (result, progress.recap)
    }

    /// Plays `session` (just built, live) with the perfect autopilot until its streak reaches `streak`, leaving at
    /// least one order for the live frames. Returns what was served on the way.
    static func playUpToStreak(_ session: GameSession, streak: Int) -> Progress {
        let pilot = AutopilotTiltSource(style: .perfect, snapshot: { session.snapshot })
        let progress = advance(session, pilot: pilot, maxSeconds: 300) { snapshot, events in
            let served = events.contains { event in
                if case .served = event { return true }
                return false
            }
            guard served else { return false }
            if snapshot.streak >= streak { return true }
            if let total = snapshot.ordersTotal, snapshot.ordersDone >= total - 1 { return true }
            return false
        }
        let s = session.snapshot
        print(String(format: "BRIM-T streak seeded %ld (asked %ld) score=%ld served=%ld t=%.1f",
                     s.streak, streak, s.score, progress.served, progress.seconds))
        return progress
    }

    /// Round 8 (demo `served=N`, REVIEW-6 N1/N7): plays `session` (just built, live) with the autopilot in `style` until
    /// N glasses are served, whatever their verdicts, so a late-Rush frame is a real moment of a real run. Leaves the
    /// run live: stops one order early in a shift, and in Rush once the jug is under `rushJugFloor` (the next glass
    /// would end it). Returns what was served on the way. Logs `BRIM-T served seeded …`.
    static let rushJugFloor = 0.3

    static func playUpToServed(_ session: GameSession, served: Int, style: AutopilotStyle,
                               missAt: Int? = nil) -> Progress {
        let pilot = Self.pilot(style: style, missAt: missAt, snapshot: { session.snapshot })
        let progress = advance(session, pilot: pilot, maxSeconds: 600) { snapshot, events in
            Self.servedSeedDone(snapshot, events: events, asked: served)
        }
        let s = session.snapshot
        print(String(format: "BRIM-T served seeded %ld (asked %ld) score=%ld tier=%ld fill=%.2f strikes=%ld t=%.1f",
                     s.ordersDone, served, s.score, s.rushTier, s.jug.fill, s.strikes, progress.seconds))
        return progress
    }

    /// Pure: whether the `served=N` seed stops at this step (only right after a serve).
    static func servedSeedDone(_ snapshot: GameSnapshot, events: [GameEvent], asked: Int) -> Bool {
        let served = events.contains { event in
            if case .served = event { return true }
            return false
        }
        guard served else { return false }
        if snapshot.ordersDone >= asked { return true }
        if let total = snapshot.ordersTotal, snapshot.ordersDone >= total - 1 { return true }
        if case .rush = snapshot.mode, snapshot.jug.fill < rushJugFloor { return true }
        return false
    }
}

/// Round 8 (demo `missAt=N`): glass N (1-based) is poured by the `over` autopilot, every other glass by `base`, so a
/// results frame can show an honest 2★ run (one miss) under the "3★ = no misses" rule. Both pilots are asked every
/// frame, so each keeps its own idea of which glass it is on.
@MainActor
final class DemoMissPilot: TiltSource {
    private let base: TiltSource
    private let miss: TiltSource
    private let missAt: Int
    private let snapshot: () -> GameSnapshot?

    init(base: TiltSource, miss: TiltSource, missAt: Int, snapshot: @escaping () -> GameSnapshot?) {
        self.base = base
        self.miss = miss
        self.missAt = missAt
        self.snapshot = snapshot
    }

    func tilt(at time: TimeInterval) -> Double {
        let a = base.tilt(at: time)
        let b = miss.tilt(at: time)
        guard let s = snapshot() else { return a }
        return Self.pouringMissGlass(ordersDone: s.ordersDone, missAt: missAt) ? b : a
    }

    /// Pure: glass `missAt` is the one being poured while `missAt − 1` glasses are done.
    static func pouringMissGlass(ordersDone: Int, missAt: Int) -> Bool {
        missAt >= 1 && ordersDone == missAt - 1
    }
}
