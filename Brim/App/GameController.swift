import Combine
import QuartzCore
import SpriteKit
import SwiftUI
import UIKit

/// The app's screens (inside the playable pose; the stand-up and cover cards sit above these).
enum AppRoute: String, Equatable {
    case home, venues, settings, playing, results
}

/// Onboarding hints (GAME-DESIGN §10). Each is shown until learned, then never again (ProgressStore.hintsSeen).
enum HintKind: String, Equatable {
    case lift, stop, anticipate
}

/// HUD values, published at ≤ 15 Hz. Separate from GameController so only the HUD redraws.
@MainActor
final class HUDState: ObservableObject {
    @Published var score = 0
    @Published var streak = 0
    @Published var multiplier = 1
    @Published var strikes = 0
    @Published var maxStrikes = 3
    @Published var ordersDone = 0
    @Published var ordersTotal: Int?
    @Published var perfects = 0
    /// The last served judgement and a counter that ticks on every serve (drives the HUD pop).
    @Published var lastJudgement: Judgement?
    @Published var serveTick = 0

    func apply(score: Int, streak: Int, multiplier: Int, strikes: Int, maxStrikes: Int, ordersDone: Int,
               ordersTotal: Int?, perfects: Int) {
        if self.score != score { self.score = score }
        if self.streak != streak { self.streak = streak }
        if self.multiplier != multiplier { self.multiplier = multiplier }
        if self.strikes != strikes { self.strikes = strikes }
        if self.maxStrikes != maxStrikes { self.maxStrikes = maxStrikes }
        if self.ordersDone != ordersDone { self.ordersDone = ordersDone }
        if self.ordersTotal != ordersTotal { self.ordersTotal = ordersTotal }
        if self.perfects != perfects { self.perfects = perfects }
    }
}

/// What the results card shows.
struct ResultSummary: Equatable {
    var result: RunResult
    var outcome: RecordOutcome
    var title: String
    var nextLevelID: String?
}

/// The hub of the frame loop (ARCHITECTURE "The frame loop"): GameScene.update → advance(dt:now:) → tilt source →
/// GameSession.step → FeedbackDirector → HUD. Owns the session, the scene, the tilt sources and the app's route.
@MainActor
final class GameController: ObservableObject, SceneDriver {
    private enum PauseReason: Hashable { case user, inactive, pose }

    // MARK: Published state (changes rarely; the HUD lives in `hud`)

    @Published private(set) var route: AppRoute = .home
    @Published private(set) var scene: GameScene?
    @Published private(set) var sceneGeneration = 0
    @Published private(set) var layout: WorldLayout?
    @Published private(set) var mode: GameMode = .practice
    /// The home screen's backdrop: practice played by the autopilot, silent.
    @Published private(set) var isAttract = true
    @Published private(set) var isUserPaused = false
    @Published private(set) var summary: ResultSummary?
    @Published private(set) var activeHint: HintKind?
    /// A hinge has reported this launch (or on an earlier launch of this device), or demo `duo`.
    @Published private(set) var hingeSeen: Bool
    /// The lid is shut (hinge ≤ 15°, released at ≥ 20°).
    @Published private(set) var isShut = false
    /// The player pours by dragging (no hinge, the Duo touch setting, or touch chosen in book pose).
    @Published private(set) var usesTouch = true
    /// Book pose: the player chose "Play with touch instead"; the game runs in a portrait column.
    @Published private(set) var bookTouchOverride = false

    let hud: HUDState
    let store: ProgressStore
    let settings: SettingsStore
    let demo: DemoConfig?

    let hinge: HingeTiltSource
    let touch: TouchTiltSource
    private let feedback: FeedbackDirector
    private var autopilot: AutopilotTiltSource?
    /// Demo override of the play source (autopilot, the hinge with `duo`, or touch).
    private var demoSource: TiltSource?

    private var session: GameSession?
    private var pauseReasons: Set<PauseReason> = []
    private var feedbackPaused: Bool?
    private var reduceMotion: Bool

    // Loop bookkeeping
    private var frameCount = 0
    private var simTime = 0.0
    private var lastHUDPublish: TimeInterval = -1
    private var recordedFinish = false
    private var servedCount = 0
    private var lastRawAngle: Double?

    // Demo freeze / streak seed
    private var frozen = false
    private var freezeAt: Double?
    private var streakSeed = 0
    private var streakSeedActive = false

    private var hintTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?

    init(store: ProgressStore, settings: SettingsStore, demo: DemoConfig?) {
        self.store = store
        self.settings = settings
        self.demo = demo
        self.hud = HUDState()
        self.reduceMotion = UIAccessibility.isReduceMotionEnabled
        self.hinge = HingeTiltSource()
        self.touch = TouchTiltSource(viewHeight: 844)
        self.feedback = FeedbackDirector.shared
        self.hingeSeen = (demo?.duo ?? false) || UserDefaults.standard.bool(forKey: "brim.hasHinge")
        refreshInputMode()
    }

    // MARK: - Derived

    var isPaused: Bool { !pauseReasons.isEmpty }
    var hintsEnabled: Bool {
        if let demo { return demo.hints == .fresh }
        return true
    }

    var currentLevel: Level? {
        if case let .shift(id) = mode { return LevelCatalog.level(id) }
        return nil
    }

    static func title(for mode: GameMode) -> String {
        switch mode {
        case let .shift(id):
            if let level = LevelCatalog.level(id) {
                return "\(LevelCatalog.title(of: level.venue)) · Shift \(level.index)"
            }
            return "Shift \(id)"
        case .rush: return "Rush"
        case let .daily(day): return "Daily Pour #\(day)"
        case .practice: return "Practice"
        }
    }

    // MARK: - Lifecycle hooks from RootView

    /// Applies demo routing once the view is up.
    func launch() {
        if let demo {
            store.replace(with: DemoConfig.progressData(demo.progress))
            if demo.hints == .fresh { store.resetHints() }
            streakSeed = max(demo.streak ?? 0, 0)
            switch demo.effectiveScreen {
            case .menu, .icon:
                startAttract()
            case .standup, .cover:
                if let mode = demo.mode { start(mode: mode) } else { startAttract() }
            case .venues:
                startAttract()
                setRoute(.venues)
            case .settings:
                startAttract()
                setRoute(.settings)
            case .game:
                start(mode: demo.mode ?? .shift(LevelCatalog.levels.first?.id ?? "1-1"))
            case .results:
                let result = demo.demoResult()
                start(mode: result.mode)
                presentDemoResults(result)
            }
        } else {
            startAttract()
        }
    }

    /// The play canvas (points) changed. Rebuilds the layout and scene only when the world actually changes.
    func updateCanvas(_ canvas: CGSize, hasFold: Bool) {
        guard canvas.width > 10, canvas.height > 10 else { return }
        // The drag span of the touch control follows the play view's height.
        if touch.viewHeight != canvas.height { touch.viewHeight = canvas.height }
        let crease: ClosedRange<CGFloat>? = hasFold
            ? (canvas.height / 2 - 20)...(canvas.height / 2 + 20)
            : nil
        let newLayout = WorldLayout.make(canvas: canvas, creaseFromTop: crease)
        guard newLayout != layout else { return }
        layout = newLayout
        makeScene(newLayout)
        if session != nil || route == .playing || isAttract {
            buildSession()
        }
    }

    func setAppActive(_ active: Bool) {
        if active {
            setPause(.inactive, false)
        } else {
            if route == .playing && !isAttract && summary == nil { setUserPaused(true) }
            setPause(.inactive, true)
        }
    }

    /// Book pose or cover display: the game holds still.
    func setPosePaused(_ paused: Bool) {
        if paused && route == .playing && !isAttract && summary == nil && !(demo != nil && frozen) {
            setUserPaused(true)
        }
        setPause(.pose, paused)
    }

    func setReduceMotion(_ on: Bool) {
        reduceMotion = on
        scene?.reduceMotion = on
    }

    // MARK: - Hinge

    func hingeSample(angle: Double, time: TimeInterval) {
        hinge.ingest(angleDegrees: angle, at: time)
        lastRawAngle = angle
        if !hingeSeen {
            hingeSeen = true
            UserDefaults.standard.set(true, forKey: "brim.hasHinge")
            refreshInputMode()
        }
        if isShut {
            if angle >= 20 { isShut = false }
        } else if angle <= 15 {
            isShut = true
        }
    }

    func hingeUnavailable() {
        // After a hinge has been seen, a nil is a display handover, never "no hinge" (research 02 §7).
    }

    /// Chooses the play input: the hinge on a Duo, touch elsewhere (or when the player asked for touch).
    func refreshInputMode() {
        let hasHinge = hingeSeen || hinge.hasHinge
        let touchWanted = !hasHinge || settings.touchOnDuo || bookTouchOverride
        let wantsTouch: Bool
        if demo != nil, let demoSource {
            wantsTouch = demoSource === touch
        } else {
            wantsTouch = touchWanted
        }
        if usesTouch != wantsTouch { usesTouch = wantsTouch }
    }

    func chooseTouchInBookPose() {
        bookTouchOverride = true
        refreshInputMode()
    }

    /// The canvas went back to portrait: the book-pose touch column is no longer needed.
    func clearBookTouchOverride() {
        guard bookTouchOverride else { return }
        bookTouchOverride = false
        refreshInputMode()
    }

    // MARK: - Commands

    func start(mode: GameMode) {
        resultsTask?.cancel()
        isAttract = false
        self.mode = mode
        summary = nil
        setUserPaused(false)
        setRoute(.playing)
        configureSources()
        buildSession()
    }

    func restart() {
        start(mode: mode)
    }

    func pause() {
        guard route == .playing, !isAttract else { return }
        setUserPaused(true)
    }

    func resume() {
        setUserPaused(false)
    }

    func quitToMenu() {
        startAttract()
    }

    func showVenues() { setRoute(.venues) }
    func showSettings() { setRoute(.settings) }
    func showHome() {
        if isAttract { setRoute(.home) } else { startAttract() }
    }

    /// Big Play button: the next shift to earn stars on.
    func playNextShift() {
        if let level = store.data.nextShift { start(mode: .shift(level.id)) }
    }

    func playDaily() {
        start(mode: .daily(LevelCatalog.dayNumber(for: Date())))
    }

    func dismissHint() {
        if let hint = activeHint { store.markHintSeen(hint.rawValue) }
        hintTask?.cancel()
        activeHint = nil
    }

    // MARK: - SceneDriver

    func advance(dt: Double, now: TimeInterval) -> (GameSnapshot, [GameEvent])? {
        frameCount += 1
        if demo != nil && (frameCount == 120 || frameCount == 600) {
            print("BRIM-T frame \(frameCount)")
        }
        guard let session else { return nil }
        if isPaused || frozen {
            return (session.snapshot, [])
        }
        let step = min(max(dt, 0), 1.0 / 30.0)
        let tilt = activeSource.tilt(at: now)
        let events = session.step(dt: step, tilt: tilt)
        simTime += step
        let snapshot = session.snapshot
        if !isAttract {
            feedback.handle(events: events, snapshot: snapshot)
        }
        process(events, snapshot: snapshot)
        publishHUD(snapshot, now: now, force: false)
        checkFreeze(snapshot, events: events, now: now)
        return (snapshot, events)
    }

    // MARK: - Internals

    private var activeSource: TiltSource {
        if isAttract, let autopilot { return autopilot }
        if !isAttract, let demoSource { return demoSource }
        if usesTouch { return touch }
        return hinge
    }

    private func setRoute(_ newRoute: AppRoute) {
        guard route != newRoute else { return }
        route = newRoute
        if demo != nil { print("BRIM-T screen \(newRoute.rawValue)") }
    }

    private func setUserPaused(_ paused: Bool) {
        if paused && !isUserPaused { touch.cancelled() }
        if isUserPaused != paused { isUserPaused = paused }
        setPause(.user, paused)
    }

    private func setPause(_ reason: PauseReason, _ on: Bool) {
        if on { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
        syncFeedbackPause()
    }

    private func syncFeedbackPause() {
        let paused = isPaused || isAttract || frozen
        guard feedbackPaused != paused else { return }
        feedbackPaused = paused
        feedback.setPaused(paused)
    }

    private func startAttract() {
        resultsTask?.cancel()
        isAttract = true
        mode = .practice
        summary = nil
        hintTask?.cancel()
        activeHint = nil
        setUserPaused(false)
        setRoute(.home)
        configureSources()
        buildSession()
    }

    private func configureSources() {
        autopilot = AutopilotTiltSource(style: .perfect, snapshot: { [weak self] in self?.session?.snapshot })
        demoSource = nil
        if let demo, !isAttract {
            if let style = demo.autopilot, let pilot = AutopilotStyle(rawValue: style.rawValue) {
                demoSource = AutopilotTiltSource(style: pilot, snapshot: { [weak self] in self?.session?.snapshot })
            } else if demo.duo {
                demoSource = hinge
            } else {
                demoSource = touch
            }
        }
        refreshInputMode()
    }

    private func makeScene(_ layout: WorldLayout) {
        let newScene = GameScene(layout: layout)
        newScene.scaleMode = .aspectFill
        newScene.driver = self
        newScene.reduceMotion = reduceMotion
        scene = newScene
        sceneGeneration += 1
    }

    private func buildSession() {
        guard let layout else { return }
        if scene == nil { makeScene(layout) }
        let newSession = GameSession(mode: mode, layout: layout, seed: seed(for: mode))
        session = newSession
        scene?.reset(for: newSession.snapshot)
        frozen = false
        freezeAt = nil
        recordedFinish = false
        servedCount = 0
        simTime = 0
        lastHUDPublish = -1
        streakSeedActive = streakSeed > 0 && !isAttract
        hintTask?.cancel()
        activeHint = nil
        hud.lastJudgement = nil
        if !isAttract && hintsEnabled && !store.hasSeenHint(HintKind.lift.rawValue) {
            activeHint = .lift
        }
        syncFeedbackPause()
        publishHUD(newSession.snapshot, now: 0, force: true)
    }

    private func seed(for mode: GameMode) -> UInt64 {
        if let seed = demo?.seed { return seed }
        if case let .daily(day) = mode { return UInt64(max(day, 0)) &+ 1 }
        if demo != nil { return 7 }
        return UInt64.random(in: 1...UInt64(UInt32.max))
    }

    private func process(_ events: [GameEvent], snapshot: GameSnapshot) {
        guard !events.isEmpty, !isAttract else { return }
        for event in events {
            switch event {
            case .pourStarted:
                if activeHint == .lift { dismissHint() }
            case .pourStopped:
                if activeHint == .stop { dismissHint() }
            case .nearingLine:
                if hintsEnabled, activeHint == nil || activeHint == .lift,
                   !store.hasSeenHint(HintKind.stop.rawValue) {
                    if activeHint == .lift { store.markHintSeen(HintKind.lift.rawValue) }
                    activeHint = .stop
                }
            case let .served(_, judgement, _):
                servedCount += 1
                hud.lastJudgement = judgement
                hud.serveTick &+= 1
                if !judgement.isHit { streakSeedActive = false }
                if activeHint == .stop { store.markHintSeen(HintKind.stop.rawValue); activeHint = nil }
                if servedCount == 1, hintsEnabled, !store.hasSeenHint(HintKind.anticipate.rawValue) {
                    showTimedHint(.anticipate, seconds: 4.5)
                }
            case let .finished(result):
                handleFinished(result)
            default:
                break
            }
        }
    }

    private func showTimedHint(_ hint: HintKind, seconds: Double) {
        hintTask?.cancel()
        activeHint = hint
        hintTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.activeHint == hint else { return }
            self.dismissHint()
        }
    }

    private func publishHUD(_ s: GameSnapshot, now: TimeInterval, force: Bool) {
        guard force || lastHUDPublish < 0 || now - lastHUDPublish >= 1.0 / 15.0 else { return }
        lastHUDPublish = now
        var streak = s.streak
        var multiplier = s.multiplier
        if streakSeedActive {
            streak += streakSeed
            multiplier = max(multiplier, Rules.multiplier(forStreak: streak))
        }
        hud.apply(score: s.score, streak: streak, multiplier: multiplier, strikes: s.strikes, maxStrikes: s.maxStrikes,
                  ordersDone: s.ordersDone, ordersTotal: s.ordersTotal, perfects: s.perfects)
    }

    private func handleFinished(_ result: RunResult) {
        guard !recordedFinish else { return }
        recordedFinish = true
        if case .practice = result.mode { return }
        hintTask?.cancel()
        activeHint = nil
        let today = LevelCatalog.dayNumber(for: Date())
        let outcome = store.record(result, today: today)
        GameCenterManager.shared.report(result: result, outcome: outcome, progress: store.data)
        let summary = makeSummary(result, outcome: outcome)
        let immediate = demo?.freezeOn == .finished
        resultsTask?.cancel()
        resultsTask = Task { @MainActor [weak self] in
            if !immediate { try? await Task.sleep(nanoseconds: 900_000_000) }
            guard !Task.isCancelled, let self, !self.isAttract else { return }
            self.summary = summary
            self.setRoute(.results)
        }
    }

    private func makeSummary(_ result: RunResult, outcome: RecordOutcome) -> ResultSummary {
        var next: String?
        if case let .shift(id) = result.mode { next = store.nextLevel(after: id)?.id }
        return ResultSummary(result: result, outcome: outcome, title: Self.title(for: result.mode), nextLevelID: next)
    }

    private func presentDemoResults(_ result: RunResult) {
        var outcome = RecordOutcome()
        if case let .shift(id) = result.mode {
            outcome.previousBest = store.data.bestScores[id] ?? 0
            outcome.starsBefore = store.stars(for: id)
            outcome.starsAfter = max(outcome.starsBefore, result.stars)
            outcome.isNewBest = result.score > outcome.previousBest
        } else if case .rush = result.mode {
            outcome.previousBest = store.rushBest
            outcome.isNewBest = result.score > store.rushBest
        } else if case .daily = result.mode {
            outcome.dailyCounted = true
        }
        summary = makeSummary(result, outcome: outcome)
        setRoute(.results)
    }

    // MARK: Demo freeze

    private func checkFreeze(_ s: GameSnapshot, events: [GameEvent], now: TimeInterval) {
        guard let target = demo?.freezeOn, !frozen, !isAttract else { return }
        if let at = freezeAt {
            if simTime >= at { freeze(target.rawValue, snapshot: s, now: now) }
            return
        }
        switch target {
        case .midpour:
            if !s.stream.isEmpty, let glass = Self.activeGlass(s), glass.lineHeight > 0,
               glass.liquidHeight + glass.foamHeight >= 0.55 * glass.lineHeight {
                freeze("midpour", snapshot: s, now: now)
            }
        case .perfect, .spill:
            for event in events {
                if case let .served(_, judgement, _) = event,
                   (target == .perfect && judgement == .perfect) || (target == .spill && judgement == .spill) {
                    freezeAt = simTime + 0.35
                    break
                }
            }
        case .finished:
            for event in events {
                if case .finished = event {
                    freeze("finished", snapshot: s, now: now)
                    break
                }
            }
        }
    }

    private func freeze(_ reason: String, snapshot: GameSnapshot, now: TimeInterval) {
        frozen = true
        hintTask?.cancel()
        if demo?.hints != .fresh { activeHint = nil }
        syncFeedbackPause()
        publishHUD(snapshot, now: now, force: true)
        print(String(format: "BRIM-T freeze %@ t=%.2f served=%ld score=%ld", reason, simTime, servedCount, snapshot.score))
    }

    static func activeGlass(_ s: GameSnapshot) -> GlassState? {
        s.glasses.first(where: { $0.phase == .filling }) ?? s.glasses.first(where: { $0.phase == .arriving })
    }
}
