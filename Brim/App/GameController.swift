import Combine
import QuartzCore
import SpriteKit
import SwiftUI
import UIKit

/// The app's screens (inside the playable pose; the stand-up and cover cards sit above these).
enum AppRoute: String, Equatable {
    case home, venues, settings, playing, results
}

/// Onboarding hints (GAME-DESIGN §10, REVIEW-1 P1-10). Each is shown until learned, then never again
/// (ProgressStore.hintsSeen; the raw values are stored, never rename them).
/// - lift: goal first ("Fill to here" on the line) + the control, beside the jug, until the first pour starts.
/// - stop: DURING the first pour, at ~60 % of the line: "stop just before the line: the stream keeps falling".
/// - anticipate: after a first serve that spilled: "a little earlier next time".
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
    /// Duo flat gate: show "Lay it flat to start" (the session needs a flat lid and has for a moment).
    @Published var showFlatGate = false
    /// The gate was re-armed by a resume (after a pause or closing the phone): "Lay it flat to carry on".
    @Published var gateAfterPause = false
    /// Where the jug and the glass under the spout are (world), for hints and the "Fill to here" callout.
    @Published var anchors: PlayAnchors?

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
    /// Glass by glass, in serve order (the recap row).
    var recap: [GlassRecap] = []
}

/// The hub of the frame loop (ARCHITECTURE "The frame loop"): GameScene.update → advance(dt:now:) → tilt source →
/// GameSession.step → FeedbackDirector → HUD. Owns the session, the scene, the tilt sources and the app's route.
@MainActor
final class GameController: ObservableObject, SceneDriver {
    private enum PauseReason: Hashable { case user, inactive, pose, closing }

    /// ROUND-3 decision 1 (App layer): below this raw hinge angle the inner display is about to go dark, so a live
    /// run pauses itself.
    static let autopauseBelow = 70.0
    /// A run paused by closing resumes by itself once the phone is open past this again (and then waits for flat).
    static let autoResumeAbove = 100.0

    // MARK: Published state (changes rarely; the HUD lives in `hud`)

    @Published private(set) var route: AppRoute = .home
    @Published private(set) var scene: GameScene?
    @Published private(set) var sceneGeneration = 0
    @Published private(set) var layout: WorldLayout?
    @Published private(set) var mode: GameMode = .practice
    /// The home screen's backdrop: practice played by the autopilot, silent.
    @Published private(set) var isAttract = true
    @Published private(set) var isUserPaused = false
    /// The run paused itself because the phone was closing (hinge < 70°) or shut: the calm "Open me up" card.
    @Published private(set) var isClosedPaused = false
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
    private var systemReduceMotion: Bool

    // Loop bookkeeping
    private var frameCount = 0
    private var simTime = 0.0
    private var lastHUDPublish: TimeInterval = -1
    private var recordedFinish = false
    private var servedCount = 0
    private var lastRawAngle: Double?
    private var recap: [GlassRecap] = []
    private var flatSince: TimeInterval?
    /// True while start/attract clear the pauses of a run that is being replaced (no resume hook for it).
    private var replacingRun = false

    // Demo freeze / streak seed
    private var frozen = false
    private var freezeAt: Double?
    private var streakSeed = 0

    private var hintTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?

    init(store: ProgressStore, settings: SettingsStore, demo: DemoConfig?) {
        self.store = store
        self.settings = settings
        self.demo = demo
        self.hud = HUDState()
        self.systemReduceMotion = UIAccessibility.isReduceMotionEnabled
        self.hinge = HingeTiltSource()
        self.touch = TouchTiltSource(viewHeight: 844)
        self.feedback = FeedbackDirector.shared
        self.hingeSeen = (demo?.duo ?? false) || UserDefaults.standard.bool(forKey: OrientationLock.hingeKey)
        refreshInputMode()
    }

    // MARK: - Derived

    var isPaused: Bool { !pauseReasons.isEmpty }
    var hintsEnabled: Bool {
        if let demo { return demo.hints == .fresh }
        return true
    }
    /// Reduce Motion (system) or the "Calmer motion" setting.
    var calmMotion: Bool { systemReduceMotion || settings.calmMotion }

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

    /// The HUD's title chip: "Lemonade Stand · 1", "Daily #297", "Rush".
    static func chipTitle(for mode: GameMode) -> String {
        switch mode {
        case let .shift(id):
            if let level = LevelCatalog.level(id) { return "\(LevelCatalog.title(of: level.venue)) · \(level.index)" }
            return id
        case .rush: return "Rush"
        case let .daily(day): return "Daily #\(day)"
        case .practice: return "Practice"
        }
    }

    /// The scene's look for a mode: the shift's venue; Daily and Rush pour at the Lemonade Stand (Daily adds its
    /// calendar, Rush its dusk look, when the scene offers them).
    static func venue(for mode: GameMode) -> VenueID {
        if case let .shift(id) = mode, let level = LevelCatalog.level(id) { return level.venue }
        return .lemonadeStand
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
                presentDemoResults()
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
        let newLayout = WorldLayout.make(canvas: canvas, hasFold: hasFold)
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
            // A run already paused by closing keeps its calm card: reopening resumes it (then the flat gate).
            if isLiveRun && demo == nil && !isClosedPaused { setUserPaused(true) }
            setPause(.inactive, true)
        }
    }

    /// The display's pose changed. Book pose: the game holds still; a real run shows the pause card when it comes
    /// back, demo runs just hold (so CI's orientation request doesn't leave them paused). Cover / shut on a Duo: the
    /// run pauses as "closed" (the same as closing past 70°), and opening the phone resumes it behind the flat gate.
    /// Every resume re-arms the flat gate (`resumeHook`).
    func setPose(_ pose: DevicePose) {
        let paused = pose != .play
        if pose == .cover && closingGuardActive && isLiveRun {
            engageClosingPause(angle: lastRawAngle)
        } else if paused && isLiveRun && demo == nil && !isClosedPaused {
            setUserPaused(true)
        }
        setPause(.pose, paused)
    }

    /// Round-2 entry point (kept): true = the book-pose hold.
    func setPosePaused(_ paused: Bool) {
        setPose(paused ? .standUp : .play)
    }

    /// The system Reduce Motion setting changed.
    func setReduceMotion(_ on: Bool) {
        systemReduceMotion = on
        refreshMotion()
    }

    /// Reduce Motion or "Calmer motion" changed.
    func refreshMotion() {
        scene?.reduceMotion = calmMotion
    }

    // MARK: - Hinge

    func hingeSample(angle: Double, time: TimeInterval) {
        hinge.ingest(angleDegrees: angle, at: time)
        lastRawAngle = angle
        if !hingeSeen {
            hingeSeen = true
            UserDefaults.standard.set(true, forKey: OrientationLock.hingeKey)
            OrientationLock.hingeArrived()
            refreshInputMode()
        }
        if isShut {
            if angle >= 20 { isShut = false }
        } else if angle <= 15 {
            isShut = true
        }
        // ROUND-3 decision 1: closing never pours. Below 70° the run pauses (no step, so nothing is judged); open
        // past 100° again and it resumes behind the flat gate.
        guard closingGuardActive else { return }
        if angle < Self.autopauseBelow {
            if isLiveRun { engageClosingPause(angle: angle) }
        } else if isClosedPaused && angle >= Self.autoResumeAbove && !isShut {
            releaseClosingPause()
        }
    }

    /// The closing guard applies wherever the hinge is real input: every real run on a Duo, and demo runs with `duo`
    /// (ci/duo.sh's close-mid-pour scenario); autopilot store frames never pause themselves.
    private var closingGuardActive: Bool {
        guard hingeSeen else { return false }
        if let demo { return demo.duo && demo.autopilot == nil }
        return true
    }

    /// A run the player is in the middle of (not the attract loop, not finished, not on results, not a CI freeze).
    private var isLiveRun: Bool {
        guard route == .playing, !isAttract, summary == nil, !frozen, let session else { return false }
        return !session.isFinished
    }

    private func engageClosingPause(angle: Double?) {
        guard !isClosedPaused else { return }
        isClosedPaused = true
        touch.cancelled()
        setPause(.closing, true)
        feedback.autopaused()
        trace(String(format: "BRIM-T autopause angle=%.1f", angle ?? -1))
    }

    private func releaseClosingPause() {
        guard isClosedPaused else { return }
        isClosedPaused = false
        setPause(.closing, false)
    }

    /// "Open me up" card: the player taps Resume instead of opening further (re-pauses at once if still < 70°).
    func resumeFromClosed() {
        releaseClosingPause()
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
        clearRunPauses()
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

    /// The pause card's Resume. The flat gate re-arms when the last pause reason clears (`resumeHook`).
    func resume() {
        flatSince = nil
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
        // GameScene prints `BRIM-T frame 120` itself (ci/duo.sh waits on it); 600 is ours.
        if demo != nil && frameCount == 600 {
            print("BRIM-T frame \(frameCount)")
        }
        guard let session else { return nil }
        if isPaused || frozen {
            return (session.snapshot, [])
        }
        let step = min(max(dt, 0), 1.0 / 30.0)
        let tilt = activeSource.tilt(at: now)
        // ROUND-3 decision 1: a slow close between the input guard's cut (78°) and the autopause (70°) must not get the
        // glass judged as a Short; lock it behind the flat gate the moment the hinge reads as closing.
        if closingGuardActive && isLiveRun && hinge.isClosing && !session.snapshot.needsFlat {
            session.requireFlat()
        }
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
        let wasPaused = isPaused
        if on { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
        syncFeedbackPause()
        if wasPaused && !isPaused { resumeHook() }
    }

    /// Every resume of a live run — the pause card, reopening the phone, the app coming back, the book pose ending,
    /// demo included — re-arms the flat gate (ROUND-3 decision 1): the hinge may have moved while nothing was
    /// stepping, so no outflow until the phone has been laid flat again. `needsFlat` stays 0 without a fold (touch
    /// phones) and in practice. Logs `BRIM-T resume needsFlat=<0|1>`.
    private func resumeHook() {
        guard !replacingRun, isLiveRun, let session else { return }
        session.requireFlat()
        hinge.reset()
        flatSince = nil
        let needsFlat = session.snapshot.needsFlat
        if hud.gateAfterPause != needsFlat { hud.gateAfterPause = needsFlat }
        trace("BRIM-T resume needsFlat=\(needsFlat ? 1 : 0)")
    }

    /// Clears the pauses of a run that is being replaced (start, restart, menu) without the resume hook.
    private func clearRunPauses() {
        replacingRun = true
        isClosedPaused = false
        setPause(.closing, false)
        setUserPaused(false)
        replacingRun = false
    }

    /// CI / debug trace line (DEBUG builds only; flushed so ci/duo.sh sees it in order).
    private func trace(_ line: String) {
        #if DEBUG
        print(line)
        fflush(stdout)
        #endif
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
        clearRunPauses()
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
        newScene.reduceMotion = calmMotion
        scene = newScene
        sceneGeneration += 1
        applySceneLook()
    }

    /// Venue look for the current mode: the shift's venue; Rush at dusk (string lights); Daily at the Lemonade Stand
    /// with the tear-off calendar "#N" on the wall.
    private func applySceneLook() {
        guard let scene else { return }
        let venue = Self.venue(for: mode)
        if scene.venue != venue { scene.venue = venue }
        var rush = false
        var daily: Int?
        switch mode {
        case .rush: rush = true
        case let .daily(day): daily = day
        case .shift, .practice: break
        }
        if scene.rushLook != rush { scene.rushLook = rush }
        if scene.dailyNumber != daily { scene.dailyNumber = daily }
    }

    private func buildSession() {
        guard let layout else { return }
        if scene == nil { makeScene(layout) }
        applySceneLook()
        let newSession = GameSession(mode: mode, layout: layout, seed: seed(for: mode))
        session = newSession
        frozen = false
        freezeAt = nil
        recordedFinish = false
        servedCount = 0
        simTime = 0
        lastHUDPublish = -1
        flatSince = nil
        recap = []
        hintTask?.cancel()
        activeHint = nil
        hud.lastJudgement = nil
        if hud.gateAfterPause { hud.gateAfterPause = false }
        // Demo `streak=N`: really play the run up to an N-Perfect streak, so score, served count and streak agree.
        if demo != nil && streakSeed > 0 && !isAttract {
            let progress = DemoRunner.playUpToStreak(newSession, streak: streakSeed)
            recap = progress.recap
            servedCount = progress.served
            if let last = progress.recap.last { hud.lastJudgement = last.judgement }
        }
        scene?.reset(for: newSession.snapshot)
        if !isAttract && hintsEnabled && !store.hasSeenHint(HintKind.lift.rawValue) && servedCount == 0 {
            activeHint = .lift
        }
        syncFeedbackPause()
        publishHUD(newSession.snapshot, now: CACurrentMediaTime(), force: true)
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
                break
            case .nearingLine:
                // During the first pour, at ~60 % of the line: the actionable moment for "stop early".
                if hintsEnabled, activeHint == nil || activeHint == .lift,
                   !store.hasSeenHint(HintKind.stop.rawValue) {
                    if activeHint == .lift { store.markHintSeen(HintKind.lift.rawValue) }
                    hintTask?.cancel()
                    activeHint = .stop
                }
            case let .served(glassID, judgement, _):
                // ci/duo.sh: no `served` line may fall between `autopause` and `resume needsFlat=1`.
                trace("BRIM-T served id=\(glassID) judgement=\(judgement.rawValue)")
                servedCount += 1
                hud.lastJudgement = judgement
                hud.serveTick &+= 1
                if let item = GlassRecap.from(snapshot, glassID: glassID, judgement: judgement) {
                    recap.append(item)
                }
                if activeHint == .stop {
                    store.markHintSeen(HintKind.stop.rawValue)
                    activeHint = nil
                }
                if activeHint == .lift {
                    store.markHintSeen(HintKind.lift.rawValue)
                    activeHint = nil
                }
                if servedCount == 1, judgement == .spill, hintsEnabled,
                   !store.hasSeenHint(HintKind.anticipate.rawValue) {
                    showTimedHint(.anticipate, seconds: 4.0)
                }
            case .lockedIn:
                break
            case .flatArmed:
                if demo != nil { print(String(format: "BRIM-T flat armed t=%.2f", simTime)) }
            case let .finished(result):
                handleFinished(result)
            case .glug, .splashInGlass, .splashOnCounter, .enteredPerfectBand, .overflowStarted, .glassArrived,
                 .streak, .multiplier, .strike, .jugRefilled, .jugSwapped, .jugEmpty:
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
        hud.apply(score: s.score, streak: s.streak, multiplier: s.multiplier, strikes: s.strikes,
                  maxStrikes: s.maxStrikes, ordersDone: s.ordersDone, ordersTotal: s.ordersTotal, perfects: s.perfects)
        // The flat gate card waits a moment, so a gate that opens at once (autopilot, a phone already flat) never
        // flashes.
        var gate = false
        if s.needsFlat && !isAttract && !usesTouch && s.phase != .finished {
            let since = flatSince ?? now
            flatSince = since
            gate = now - since >= 0.35
        } else {
            flatSince = nil
        }
        if hud.showFlatGate != gate { hud.showFlatGate = gate }
        if let layout {
            var anchors = AnchorMath.anchors(s, layout: layout)
            // The scene knows the jug's drawn bounds (walls, handle, lid); prefer them to the interior outline.
            if let drawn = scene?.jugWorldBounds, !drawn.isNull, !drawn.isEmpty {
                anchors.jug = drawn.insetBy(dx: -6, dy: -6)
            }
            anchors = AnchorMath.quantized(anchors)
            if hud.anchors != anchors { hud.anchors = anchors }
        }
    }

    private func handleFinished(_ result: RunResult) {
        guard !recordedFinish else { return }
        recordedFinish = true
        // `screen=results` already shows its played run; the idle run behind it never replaces it.
        if demo?.effectiveScreen == .results { return }
        if case .practice = result.mode { return }
        hintTask?.cancel()
        activeHint = nil
        let today = LevelCatalog.dayNumber(for: Date())
        let outcome = store.record(result, today: today)
        GameCenterManager.shared.report(result: result, outcome: outcome, progress: store.data)
        let summary = makeSummary(result, outcome: outcome, recap: recap)
        let immediate = demo?.freezeOn == .finished
        resultsTask?.cancel()
        resultsTask = Task { @MainActor [weak self] in
            if !immediate { try? await Task.sleep(nanoseconds: 700_000_000) }
            guard !Task.isCancelled, let self, !self.isAttract else { return }
            self.summary = summary
            self.setRoute(.results)
        }
    }

    private func makeSummary(_ result: RunResult, outcome: RecordOutcome, recap: [GlassRecap]) -> ResultSummary {
        var next: String?
        if case let .shift(id) = result.mode { next = store.nextLevel(after: id)?.id }
        return ResultSummary(result: result, outcome: outcome, title: Self.title(for: result.mode), nextLevelID: next,
                             recap: recap)
    }

    /// `screen=results`: a real run of the mode played headless by the autopilot (`autopilot=` style; default perfect
    /// for shifts, great elsewhere), recorded into the in-memory demo progress, with its scene running idle behind.
    private func presentDemoResults() {
        guard let demo else { return }
        let mode = demo.mode ?? .shift(LevelCatalog.levels.first?.id ?? "1-1")
        let fallback: AutopilotStyle
        if case .shift = mode { fallback = .perfect } else { fallback = .great }
        let style = demo.autopilot.flatMap { AutopilotStyle(rawValue: $0.rawValue) } ?? fallback
        let played = DemoRunner.playRun(mode: mode, style: style, seed: seed(for: mode))
        start(mode: mode)
        let outcome = store.record(played.0, today: LevelCatalog.dayNumber(for: Date()))
        summary = makeSummary(played.0, outcome: outcome, recap: played.1)
        recordedFinish = true
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
        case .perfect:
            // The big Perfect, ~0.15 s after the verdict (rings, flash, hop and stamp all on screen).
            for event in events {
                if case let .served(_, judgement, _) = event, judgement == .perfect {
                    freezeAt = simTime + 0.15
                    break
                }
            }
        case .spill:
            // ~0.3 s after the liquid goes over the rim (live spill: the sheet, the shake, the puddle starting).
            for event in events {
                if case .overflowStarted = event {
                    freezeAt = simTime + 0.3
                    break
                }
                if case let .served(_, judgement, _) = event, judgement == .spill {
                    freezeAt = simTime + 0.3
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
        // The scene runs its cosmetics on the session clock, so the frame (burst, sheet, shake) holds at this instant.
        print(String(format: "BRIM-T freeze %@ t=%.2f served=%ld score=%ld streak=%ld", reason, simTime, servedCount,
                     snapshot.score, snapshot.streak))
    }

    static func activeGlass(_ s: GameSnapshot) -> GlassState? {
        s.glasses.first(where: { $0.phase == .filling })
            ?? s.glasses.first(where: { $0.phase == .arriving && !$0.isWaitingInSlot })
    }
}
