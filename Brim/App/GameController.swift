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
    /// Round 6 (decision 1, REVIEW-5 §1): the one-time venue intro cards, on the first shift played in each venue that
    /// has a new idea. Cleared by the first pour (lift on a Duo, drag on a phone) or a tap.
    case foam, thick, belt, fade, sand

    /// The venue intro card for `venue` (nil for the Lemonade Stand: the lift/stop hints teach it).
    static func venueIntro(for venue: VenueID?) -> HintKind? {
        switch venue {
        case .sodaFountain?: return .foam
        case .milkshakeDiner?: return .thick
        case .conveyor?: return .belt
        case .potionShop?: return .fade
        case .sandBar?: return .sand
        case .lemonadeStand?, nil: return nil
        }
    }

    var isVenueIntro: Bool { introVenue != nil }

    /// The venue a venue intro card introduces (nil for the onboarding hints).
    var introVenue: VenueID? {
        switch self {
        case .foam: return .sodaFountain
        case .thick: return .milkshakeDiner
        case .belt: return .conveyor
        case .fade: return .potionShop
        case .sand: return .sandBar
        case .lift, .stop, .anticipate: return nil
        }
    }
}

/// Round 6: the short banner under the HUD row: the shift's number and title during the intro phase (decision 1), or
/// the Rush tier ("TIER 3 · BELTS!", decision 2). `serial` changes with every new banner so the same text re-animates.
struct PlayBanner: Equatable {
    enum Kind: Equatable { case shift, tier }
    var kind: Kind
    var text: String
    var serial: Int
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
    /// ROUND-5 decision 1: the gate has held for `GameController.touchOfferDelay` s: the card offers "Use touch instead".
    @Published var offerTouch = false
    /// QA-3 P2-10: the Duo's flat gate is closed right now (its card may still be waiting `gateCardDelay`). The venue
    /// intro card waits for it to open, so it never pops in and then vanishes under the gate card.
    @Published var gateClosed = false
    /// Where the jug and the glass under the spout are (world), for hints and the "Fill to here" callout.
    @Published var anchors: PlayAnchors?
    /// REVIEW-3 P1-4 fallback (phones): the next order's drink colour when no waiting glass fits on screen; the HUD
    /// shows it as a small glass beside the progress dots. nil = nothing to show.
    @Published var upcoming: RGBA?
    /// Round 6: the shift / Rush tier banner on screen now (nil = none).
    @Published var banner: PlayBanner?
    /// Round 6 (REVIEW-5 §3 P2): the scene behind the HUD is dark (Potion Shop, Rush at dusk): light score text.
    @Published var darkBackdrop = false

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
    /// ROUND-5 decision 1: seconds stuck on the flat gate before its card offers "Use touch instead".
    static let touchOfferDelay = 6.0
    /// The flat gate card waits this long, so a gate that opens at once (autopilot, a phone already flat) never flashes.
    static let gateCardDelay = 0.35

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
    /// QA-3 P1-3: while a venue intro card is up the run holds (`GameSession.setStartHold`), so "Pour to start" is true:
    /// no belt, patience or line fade runs under the card. Any change of hint (dismiss, first pour, a new run) re-syncs.
    @Published private(set) var activeHint: HintKind? {
        didSet {
            if activeHint != oldValue { syncStartHold() }
        }
    }
    /// A hinge has reported this launch (or on an earlier launch of this device), or demo `duo`.
    @Published private(set) var hingeSeen: Bool
    /// The lid is shut (hinge ≤ 15°, released at ≥ 20°).
    @Published private(set) var isShut = false
    /// The player pours by dragging (no hinge, the Duo touch setting, or touch chosen in book pose).
    @Published private(set) var usesTouch = true
    /// Book pose: the player chose "Play with touch instead"; the game runs in a portrait column.
    @Published private(set) var bookTouchOverride = false
    /// ROUND-5 decision 1: the player tapped "Use touch instead" on the flat gate. Round 7 (QA-3 P2-11): remembered for
    /// the app session (Next shift, Retry and the menu keep it) until the app relaunches or the hinge pours again (laid
    /// flat, then lifted: `hingePoursAgain`); then the next run is back on the hinge. Nothing is stored.
    @Published private(set) var runTouchOverride = false
    /// QA-1 P1-2: this run is today's one scored Daily attempt (the pause card has no Restart).
    @Published private(set) var isScoredDaily = false
    /// QA-1 P2-25: a Daily whose scored attempt is already on file: practice ("Daily #297 · Practice" in the HUD).
    @Published private(set) var isPracticeDaily = false

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

    /// The day of the scored Daily attempt being played (nil otherwise), and the run's judgements so far.
    private var scoredDailyDay: Int?
    private var runJudgements: [Judgement] = []
    /// The scored Daily's first glass has arrived / the attempt has been armed (`armDailyIfReady`).
    private var dailyGlassArrived = false
    private var dailyArmed = false
    /// The screen is being kept awake (`UIApplication.isIdleTimerDisabled`, QA-1 P1-4).
    private var screenKeptAwake = false
    /// Demo `screen=menu`: the attract loop has been held mid-pour once (REVIEW-3 P1-2).
    private var attractFrozeOnce = false
    /// What we last told `FeedbackDirector.setIdle` (nil = never).
    private var feedbackIdle: Bool?
    /// QA-3 P2-11: while the touch override is on, the hinge has read flat / has poured again since.
    private var touchOverrideSawFlat = false
    private var touchOverrideHingePoured = false
    /// QA-3 P1-3: what we last told `GameSession.setStartHold` (a new session starts unheld; see `buildSession`).
    private var startHeld = false
    /// Demo `freezeOn=tier`: session-sim time of the tier change being waited on (QA-3 P1-1, frame 26).
    private var tierChangedAt: Double?

    // Round 6: banners, the Rush tier, the venue look
    /// The banner of this run (shown until `bannerUntil`, session time; a shift banner also holds while the start gate
    /// does), and a counter so each new banner re-animates.
    private var banner: PlayBanner?
    private var bannerUntil = 0.0
    private var bannerHoldsOnGate = false
    private var bannerSerial = 0
    /// The Rush tier last seen in the snapshot (0 outside Rush).
    private var lastRushTier = 0
    /// Demo `freezeOn=tier`: a tier banner just went up.
    private var tierFreezePending = false
    /// The venue the scene was last told to show (nil = not yet).
    private var shownVenue: VenueID?

    init(store: ProgressStore, settings: SettingsStore, demo: DemoConfig?) {
        self.store = store
        self.settings = settings
        self.demo = demo
        self.hud = HUDState()
        self.systemReduceMotion = UIAccessibility.isReduceMotionEnabled
        self.hinge = HingeTiltSource()
        self.touch = TouchTiltSource(viewHeight: 844)
        self.feedback = FeedbackDirector.shared
        // QA-1 P1-1: `brim.hasHinge` comes back with a backup restored onto another iPhone. Believe it only on a screen
        // shaped like a Duo's; otherwise forget it (a real hinge report sets it again).
        let stored = UserDefaults.standard.bool(forKey: OrientationLock.hingeKey)
        let trusted = OrientationLock.trustsStoredHinge(stored, screen: UIScreen.main.bounds.size)
        if stored && !trusted { UserDefaults.standard.removeObject(forKey: OrientationLock.hingeKey) }
        self.hingeSeen = (demo?.duo ?? false) || trusted
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

    /// The HUD's chip for the current run: `chipTitle`, plus "· Practice" on a Daily already poured today.
    var hudTitle: String {
        let base = Self.chipTitle(for: mode)
        return isPracticeDaily ? "\(base) · Practice" : base
    }

    /// What the closed-pause card calls the run (QA-1 P2-21): "Your shift is paused", "Your Rush run is paused"…
    static func runNoun(for mode: GameMode) -> String {
        switch mode {
        case .shift: return "shift"
        case .rush: return "Rush run"
        case .daily: return "Daily Pour"
        case .practice: return "pour"
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
    /// calendar, Rush its dusk look, when the scene offers them). Round 6: the snapshot's `venue` wins when Core
    /// reports one (Rush travels one venue per tier), see `lookVenue(snapshot:mode:)`.
    static func venue(for mode: GameMode) -> VenueID {
        if case let .shift(id) = mode, let level = LevelCatalog.level(id) { return level.venue }
        return .lemonadeStand
    }

    /// Round 6 (decision 2): the venue to show now: the snapshot's (Rush tiers, shifts) else the mode's. Pure.
    static func lookVenue(snapshot venue: VenueID?, mode: GameMode) -> VenueID {
        venue ?? Self.venue(for: mode)
    }

    /// Round 6 (REVIEW-5 §3 P2): the scene behind the HUD is dark: the Potion Shop, and every Rush venue (dusk). Pure.
    static func isDarkLook(venue: VenueID, rush: Bool) -> Bool {
        rush || venue == .potionShop
    }

    /// Round 6 (decision 1): "Shift 6 · Slow Pour, Fast Belt" for a shift; nil for every other mode. Pure.
    static func shiftBanner(for mode: GameMode) -> String? {
        guard case let .shift(id) = mode, let level = LevelCatalog.level(id) else { return nil }
        return "Shift \(level.index) · \(level.title)"
    }

    /// Round 6 (decision 2, REVIEW-5 §5): the Rush tier banner, "TIER 3 · BELTS!". The word follows the venue the tier
    /// travels to (Core's `snapshot.venue`), else decision 2's order (2 Soda, 3 Conveyor, 4 Diner, 5 Potion); tier 6
    /// and up (and any return to the Lemonade Stand) say "FASTER!". nil for tier 1 (the start) and outside Rush. Pure.
    static func tierBanner(tier: Int, venue: VenueID?) -> String? {
        guard tier >= 2 else { return nil }
        let planned: [Int: VenueID] = [2: .sodaFountain, 3: .conveyor, 4: .milkshakeDiner, 5: .potionShop]
        var shown: VenueID? = nil
        if tier < 6 { shown = venue ?? planned[tier] }
        let word: String
        switch shown {
        case .sodaFountain?: word = "FIZZ!"
        case .conveyor?: word = "BELTS!"
        case .milkshakeDiner?: word = "THICK AND FAST!"
        case .potionShop?: word = "POTIONS!"
        case .sandBar?: word = "SAND!"
        case .lemonadeStand?, nil: word = "FASTER!"
        }
        return "TIER \(tier) · \(word)"
    }

    /// QA-3 P2-12: a venue's intro card is only for players new to it. TestFlight 1.0 (2) saves have no venue hint keys,
    /// so a veteran with stars there would be taught foam on a replay; any star in the venue counts as learned. Pure.
    static func showsVenueIntro(starsInVenue: Int) -> Bool {
        starsInVenue <= 0
    }

    /// QA-3 P2-1 (ROUND-7 App row): the belt queue the scene draws behind the lead glass in Rush, which has no shift
    /// list. The next order (`GameSession.upcomingOrder`, plan number `nextIndex` from 0) rides in on the belt only when
    /// it was drawn for a conveyor tier (`Rules.rushVenue`, a tier every `CoreTuning.rushTierEvery` glasses); a glass
    /// waiting in the slot is never a belt glass. Empty = no queue. Pure.
    static func rushBeltQueue(next: GlassOrder?, nextIndex: Int, slotGlassWaiting: Bool) -> [GlassOrder] {
        guard let next, !slotGlassWaiting, nextIndex >= 0 else { return [] }
        let tier = nextIndex / max(CoreTuning.rushTierEvery, 1) + 1
        return Rules.rushVenue(tier: tier) == .conveyor ? [next] : []
    }

    /// How long (session seconds) the shift banner stays up, and the tier banner after a change.
    static let shiftBannerSeconds = 1.6
    static let tierBannerSeconds = 1.6

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
        if !isAttract, let session {
            // QA-1 P1-3: the world is the same on every canvas (only the visible rect and the fold differ), so a run —
            // live, paused, or finished behind its results card — is kept; the session adopts the canvas (visible
            // rect, flat gate on with a fold, off without) and only the scene is swapped.
            let hadFold = session.layout.hasFold
            session.adoptCanvas(newLayout)
            if newLayout.hasFold && !hadFold && isLiveRun && !usesTouch {
                // Back on the fold (book-pose touch column → tabletop): the hinge may be anywhere, so the gate closes
                // until the phone lies flat (the pose's resume ran before the gate existed again).
                session.requireFlat()
                hinge.reset()
                flatSince = nil
                if hud.gateAfterPause != session.snapshot.needsFlat { hud.gateAfterPause = session.snapshot.needsFlat }
            }
            scene?.reset(for: session.snapshot)
            publishHUD(session.snapshot, now: CACurrentMediaTime(), force: true)
            trace(String(format: "BRIM-T canvas swap kept run t=%.2f", session.snapshot.time))
        } else if session != nil || route == .playing || isAttract {
            buildSession()
        }
    }

    /// The canvas changed size (RootView). QA-1 P2-4: the inner display coming back means the lid is open, even if no
    /// hinge sample has said so yet (a still hinge may not report), so "shut" is released.
    func canvasDidChange(_ canvas: CGSize) {
        if isShut && max(canvas.width, canvas.height) >= PoseRule.coverMaxSide { isShut = false }
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
        trackHingePourUnderTouch(angle: angle)
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
        let touchWanted = !hasHinge || settings.touchOnDuo || bookTouchOverride || runTouchOverride
        let wantsTouch: Bool
        if demo != nil, let demoSource, !runTouchOverride {
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

    /// ROUND-5 decision 1 (QA-2 P0-suspect): "Use touch instead" on the flat gate. From now on the game pours by drag
    /// (the touch source reads 0 until a drag, so the gate opens on the next step); nothing is persisted. Round 7 (QA-3
    /// P2-11): it lasts until the app relaunches or the hinge pours again (`hingePoursAgain`), so a Duo whose hinge can't
    /// reach flat isn't sent back to a 6 s gate at every Next shift and Retry.
    func useTouchForThisRun() {
        guard route == .playing, !isAttract, !runTouchOverride else { return }
        runTouchOverride = true
        touchOverrideSawFlat = false
        touchOverrideHingePoured = false
        touch.cancelled()
        refreshInputMode()
        flatSince = nil
        if hud.showFlatGate { hud.showFlatGate = false }
        if hud.offerTouch { hud.offerTouch = false }
        if hud.gateClosed { hud.gateClosed = false }
        trace("BRIM-T touch for this run")
    }

    /// Ends the touch override (the hinge poured again; see `trackHingePourUnderTouch`).
    private func clearRunTouchOverride() {
        touchOverrideSawFlat = false
        touchOverrideHingePoured = false
        guard runTouchOverride else { return }
        runTouchOverride = false
        refreshInputMode()
    }

    /// A new run or the menu: the touch override carries on unless the hinge has poured again since it was chosen.
    private func endTouchOverrideIfHingePoured() {
        if touchOverrideHingePoured { clearRunTouchOverride() }
    }

    /// Round 7 (QA-3 P2-11): lid tilt (degrees) a hinge must lift to, after reading flat, to count as pouring again.
    static let hingePourTilt = 20.0

    /// Round 7 (QA-3 P2-11): one hinge sample while "Use touch instead" is on. The hinge counts as pouring again once it
    /// has read flat (`Rules.readsFlat`) and then lifts past `hingePourTilt`. Returns the new `sawFlat` and whether it
    /// poured. Pure.
    static func hingePoursAgain(sawFlat: Bool, hingeAngle: Double) -> (sawFlat: Bool, poured: Bool) {
        let lid = HingeTiltSource.lidTilt(forHingeAngle: hingeAngle)
        if Rules.readsFlat(lidTilt: lid) { return (sawFlat: true, poured: false) }
        if sawFlat && lid >= hingePourTilt { return (sawFlat: false, poured: true) }
        return (sawFlat: sawFlat, poured: false)
    }

    /// Watches the hinge while the touch override is on. A pour mid-run never swaps the input under the player: the
    /// override ends at the next run (or at once when no run is live: menus, results).
    private func trackHingePourUnderTouch(angle: Double) {
        guard runTouchOverride, !touchOverrideHingePoured else { return }
        let step = Self.hingePoursAgain(sawFlat: touchOverrideSawFlat, hingeAngle: angle)
        touchOverrideSawFlat = step.sawFlat
        guard step.poured else { return }
        touchOverrideHingePoured = true
        trace("BRIM-T touch override ends: the hinge poured")
        if !isLiveRun { clearRunTouchOverride() }
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
        closeOutRushRun()
        closeOutDailyAttempt()
        endTouchOverrideIfHingePoured()
        isAttract = false
        self.mode = mode
        summary = nil
        // QA-1 P1-2: a Daily marks its scored attempt the moment it starts; a Daily already on file is practice.
        if case let .daily(day) = mode {
            let scored = store.beginDailyAttempt(day: day)
            scoredDailyDay = scored ? day : nil
            isScoredDaily = scored
            isPracticeDaily = !scored
        } else {
            scoredDailyDay = nil
            if isScoredDaily { isScoredDaily = false }
            if isPracticeDaily { isPracticeDaily = false }
        }
        clearRunPauses()
        setRoute(.playing)
        configureSources()
        buildSession()
        syncIdleTimer()
    }

    /// Leaving today's scored Daily before it finished (Menu, Restart, another mode) files the pour so far as the day's
    /// score (QA-1 P1-2: no free retries). Nothing served yet = nothing filed.
    private func closeOutDailyAttempt() {
        guard let day = scoredDailyDay else { return }
        scoredDailyDay = nil
        if isScoredDaily { isScoredDaily = false }
        guard !recordedFinish, let filed = store.closeDailyAttempt(day: day) else { return }
        let result = RunResult(mode: .daily(day), score: filed.score, stars: 0, perfects: filed.perfects, bestStreak: 0,
                               judgements: filed.judgements, poured: 0, cleared: false)
        var outcome = RecordOutcome()
        outcome.dailyCounted = true
        GameCenterManager.shared.report(result: result, outcome: outcome, progress: store.data)
        trace("BRIM-T daily left day=\(day) score=\(filed.score) glasses=\(filed.judgements.count)")
    }

    /// Round 5 (QA-2 P2-4, "Rush quit records the score"): leaving a Rush run before it ended (Menu, Restart, another
    /// mode) records it like a finished one: Rush best, lifetime stats and the Game Center score. Nothing served = nothing
    /// recorded.
    private func closeOutRushRun() {
        guard case .rush = mode, !isAttract, !recordedFinish, let session, !session.isFinished else { return }
        guard !runJudgements.isEmpty else { return }
        recordedFinish = true
        let s = session.snapshot
        let result = RunResult(mode: .rush, score: s.score, stars: 0, perfects: s.perfects,
                               bestStreak: Self.bestPerfectStreak(runJudgements), judgements: runJudgements, poured: 0,
                               cleared: true)
        let outcome = store.record(result, today: LevelCatalog.dayNumber(for: Date()))
        GameCenterManager.shared.report(result: result, outcome: outcome, progress: store.data)
        trace("BRIM-T rush left score=\(s.score) glasses=\(runJudgements.count)")
    }

    /// The longest run of consecutive Perfects (the session's streak rule). Pure.
    static func bestPerfectStreak(_ judgements: [Judgement]) -> Int {
        var best = 0
        var run = 0
        for j in judgements {
            run = j == .perfect ? run + 1 : 0
            best = max(best, run)
        }
        return best
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

    /// Marks the active hint learned and clears it. Also the venue intro card's tap (which releases the start hold).
    func dismissHint() {
        if let hint = activeHint { store.markHintSeen(hint.rawValue) }
        hintTask?.cancel()
        activeHint = nil
    }

    /// QA-3 P1-3: hold the run while a venue intro card is up; release it with the card (tap, first pour, a new run).
    /// Core also releases it by itself on `.pourStarted`.
    private func syncStartHold() {
        guard let session else { return }
        let on = !isAttract && activeHint?.isVenueIntro == true
        guard on != startHeld else { return }
        startHeld = on
        session.setStartHold(on)
        trace("BRIM-T start hold \(on ? 1 : 0)")
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
        // QA-1 P2-3: not while pouring by touch (the hinge isn't the input, and its guard latch would re-close the gate
        // every frame between 70° and 78°).
        // ROUND-5 decision 2 (QA-2 P1-1): `isClosing` is only the below-78° latch now; a brisk lift or a fast close that
        // stops short is cut by the hinge source itself and never re-locks the gate. A re-lock mid-run reads "Lay it flat
        // to carry on", never "to start".
        if closingGuardActive && !usesTouch && isLiveRun && hinge.isClosing && !session.snapshot.needsFlat {
            session.requireFlat()
            if session.snapshot.needsFlat && !hud.gateAfterPause { hud.gateAfterPause = true }
        }
        let events = session.step(dt: step, tilt: tilt)
        simTime += step
        let snapshot = session.snapshot
        if !isAttract {
            feedback.handle(events: events, snapshot: snapshot)
        }
        process(events, snapshot: snapshot)
        armDailyIfReady(snapshot)
        syncLook(snapshot)
        syncBeltQueue(snapshot)
        trackRushTier(snapshot)
        publishHUD(snapshot, now: now, force: false)
        checkFreeze(snapshot, events: events, now: now)
        return (snapshot, events)
    }

    // MARK: - Internals

    private var activeSource: TiltSource {
        if isAttract, let autopilot { return autopilot }
        if !isAttract, !runTouchOverride, let demoSource { return demoSource }
        if usesTouch { return touch }
        return hinge
    }

    private func setRoute(_ newRoute: AppRoute) {
        if route != newRoute {
            route = newRoute
            if demo != nil { print("BRIM-T screen \(newRoute.rawValue)") }
        }
        syncIdleTimer()
        syncFeedbackIdle()
    }

    /// QA-1 P2-7 (battery): the sound and haptic engines idle on every screen without a pour (Home and its silent
    /// attract loop, Venues, Settings, results) and wake when a run starts. Menu taps still sound (Feel wakes them).
    private func syncFeedbackIdle() {
        let idle = route != .playing || isAttract
        if feedbackIdle != idle {
            feedbackIdle = idle
            feedback.setIdle(idle)
        }
    }

    /// QA-1 P1-4: on a Duo a whole shift can pass without a touch (the hinge is the input), so Auto-Lock must not dim
    /// and lock the screen mid-pour. Kept awake only during a live, unpaused run; menus, results, pause and the
    /// background let the screen sleep as usual.
    var keepsScreenAwake: Bool {
        route == .playing && !isAttract && !isPaused && summary == nil
    }

    private func syncIdleTimer() {
        let awake = keepsScreenAwake
        guard awake != screenKeptAwake else { return }
        screenKeptAwake = awake
        UIApplication.shared.isIdleTimerDisabled = awake
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
        syncIdleTimer()
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
        closeOutRushRun()
        closeOutDailyAttempt()
        endTouchOverrideIfHingePoured()
        if isPracticeDaily { isPracticeDaily = false }
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
    /// with the tear-off calendar "#N" on the wall. Round 6: the venue follows `snapshot.venue` when Core reports one.
    private func applySceneLook() {
        guard let scene else { return }
        shownVenue = nil
        syncLook(session?.snapshot)
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

    /// Round 6 (decision 2): the scene shows the snapshot's venue (Rush travels one venue per tier; if the scene also
    /// follows `snapshot.venue` itself, setting the same value is a no-op), and the HUD learns whether it's dark.
    private func syncLook(_ s: GameSnapshot?) {
        let venue = Self.lookVenue(snapshot: s?.venue, mode: mode)
        guard venue != shownVenue else { return }
        shownVenue = venue
        if let scene, scene.venue != venue { scene.venue = venue }
        var rush = false
        if case .rush = mode { rush = true }
        let dark = Self.isDarkLook(venue: venue, rush: rush)
        if hud.darkBackdrop != dark { hud.darkBackdrop = dark }
    }

    /// QA-3 P2-1: Rush tells the scene which order rides in on the belt next (shifts leave it nil: the scene reads the
    /// level's own list). The scene is reused across runs, so every run sets it.
    private func syncBeltQueue(_ s: GameSnapshot) {
        guard let scene else { return }
        var orders: [GlassOrder]? = nil
        if !isAttract, case .rush = mode, let session {
            var onCounter = 0
            var waiting = false
            for g in s.glasses {
                if g.isWaitingInSlot {
                    waiting = true
                } else if g.result == nil && g.phase != .leaving {
                    onCounter += 1
                }
            }
            orders = Self.rushBeltQueue(next: session.upcomingOrder, nextIndex: s.ordersDone + onCounter,
                                        slotGlassWaiting: waiting)
        }
        if scene.upcomingOrders != orders { scene.upcomingOrders = orders }
    }

    /// Round 6 (decision 2): a Rush tier change puts up "TIER n · …" for `tierBannerSeconds` (Feel plays the chord).
    private func trackRushTier(_ s: GameSnapshot) {
        guard !isAttract, case .rush = mode, s.rushTier != lastRushTier else { return }
        let up = s.rushTier > lastRushTier
        lastRushTier = s.rushTier
        guard up, s.phase != .finished, let text = Self.tierBanner(tier: s.rushTier, venue: s.venue) else { return }
        bannerSerial += 1
        banner = PlayBanner(kind: .tier, text: text, serial: bannerSerial)
        bannerUntil = s.time + Self.tierBannerSeconds
        bannerHoldsOnGate = false
        tierFreezePending = true
        trace("BRIM-T tier \(s.rushTier) venue=\(Self.lookVenue(snapshot: s.venue, mode: mode).rawValue)")
    }

    /// Pure: whether a banner is on screen at session time `time`. A shift banner also holds while the start gate does
    /// (flat gate up, not after a pause, nothing served yet). Never on a finished run.
    static func bannerVisible(time: Double, until: Double, holdsOnGate: Bool, needsFlat: Bool, gateAfterPause: Bool,
                              ordersDone: Int, finished: Bool) -> Bool {
        if finished { return false }
        if time < until { return true }
        return holdsOnGate && needsFlat && !gateAfterPause && ordersDone == 0
    }

    private func buildSession() {
        guard let layout else { return }
        if scene == nil { makeScene(layout) }
        let newSession = GameSession(mode: mode, layout: layout, seed: seed(for: mode))
        session = newSession
        startHeld = false               // a new session starts unheld; the intro card below holds it again
        tierChangedAt = nil
        // After the session exists, so the look follows its snapshot (round 6), never the run being replaced.
        applySceneLook()
        frozen = false
        freezeAt = nil
        recordedFinish = false
        servedCount = 0
        simTime = 0
        lastHUDPublish = -1
        flatSince = nil
        recap = []
        runJudgements = []
        dailyGlassArrived = false
        dailyArmed = false
        if hud.offerTouch { hud.offerTouch = false }
        hintTask?.cancel()
        activeHint = nil
        hud.lastJudgement = nil
        if hud.gateAfterPause { hud.gateAfterPause = false }
        // Demo `streak=N`: really play the run up to an N-Perfect streak, so score, served count and streak agree.
        if demo != nil && streakSeed > 0 && !isAttract {
            let progress = DemoRunner.playUpToStreak(newSession, streak: streakSeed)
            recap = progress.recap
            runJudgements = progress.recap.map { $0.judgement }
            servedCount = progress.served
            if let last = progress.recap.last { hud.lastJudgement = last.judgement }
        }
        syncLook(newSession.snapshot)
        syncBeltQueue(newSession.snapshot)
        scene?.reset(for: newSession.snapshot)
        if !isAttract && hintsEnabled && servedCount == 0 {
            // Round 6: a venue's one-time intro card comes first (a player who reached it has poured before);
            // otherwise the very first run's lift hint.
            let venue = currentLevel?.venue
            var intro = HintKind.venueIntro(for: venue)
            if let card = intro, let venue, !store.hasSeenHint(card.rawValue),
               !Self.showsVenueIntro(starsInVenue: store.data.starsEarned(in: venue)) {
                // QA-3 P2-12: a TestFlight 1.0 (2) player who already has stars here knows the venue: learned.
                store.markHintSeen(card.rawValue)
                trace("BRIM-T intro card skipped \(card.rawValue)")
                intro = nil
            }
            if let intro, !store.hasSeenHint(intro.rawValue) {
                activeHint = intro
                trace("BRIM-T intro card \(intro.rawValue)")
            } else if !store.hasSeenHint(HintKind.lift.rawValue) {
                activeHint = .lift
            }
        }
        // Round 6: the shift banner (held while the start gate holds); the Rush tier starts where the run is.
        bannerSerial += 1
        banner = nil
        bannerUntil = 0
        bannerHoldsOnGate = false
        tierFreezePending = false
        lastRushTier = newSession.snapshot.rushTier
        if !isAttract, servedCount == 0, let text = Self.shiftBanner(for: mode) {
            banner = PlayBanner(kind: .shift, text: text, serial: bannerSerial)
            bannerUntil = newSession.snapshot.time + Self.shiftBannerSeconds
            bannerHoldsOnGate = true
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
                // The first pour clears the lift hint and a venue intro card (round 6: learned, never shown again).
                if activeHint == .lift || activeHint?.isVenueIntro == true { dismissHint() }
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
                runJudgements.append(judgement)
                // QA-1 P1-2: the scored Daily's pour so far is saved on every serve (leaving or a crash files it).
                if let day = scoredDailyDay {
                    store.updateDailyAttempt(day: day, score: snapshot.score, judgements: runJudgements,
                                             perfects: snapshot.perfects)
                }
                if activeHint == .stop {
                    store.markHintSeen(HintKind.stop.rawValue)
                    activeHint = nil
                }
                if activeHint == .lift {
                    store.markHintSeen(HintKind.lift.rawValue)
                    activeHint = nil
                }
                // Spilled, or filled past the band without spilling (round 5 `.over`): stop a little earlier.
                if servedCount == 1, judgement == .spill || judgement == .over, hintsEnabled,
                   !store.hasSeenHint(HintKind.anticipate.rawValue) {
                    showTimedHint(.anticipate, seconds: 4.0)
                }
            case .glassArrived:
                // Round 5 (QA-2 P2-5): see `armDailyIfReady`.
                if scoredDailyDay != nil { dailyGlassArrived = true }
            case .lockedIn:
                break
            case .flatArmed:
                if demo != nil { print(String(format: "BRIM-T flat armed t=%.2f", simTime)) }
            case let .finished(result):
                handleFinished(result)
            case .glug, .splashInGlass, .splashOnCounter, .enteredPerfectBand, .overflowStarted,
                 .streak, .multiplier, .strike, .jugRefilled, .jugSwapped, .jugEmpty:
                break
            }
        }
    }

    /// Round 5 (QA-2 P2-5, ROUND-5 App row): the scored Daily is filed once its first glass has ARRIVED (and, on a Duo,
    /// the flat gate is open, so the player could pour into it): from then on leaving files the attempt even at 0
    /// glasses served, so pausing mid-overpour on glass 1 and leaving is no free retry. Leaving before that (still on
    /// the gate, or in the first moment) costs nothing.
    private func armDailyIfReady(_ snapshot: GameSnapshot) {
        guard let day = scoredDailyDay, dailyGlassArrived, !dailyArmed, !snapshot.needsFlat else { return }
        dailyArmed = true
        store.armDailyAttempt(day: day)
        trace("BRIM-T daily armed day=\(day)")
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
        var offer = false
        let gateClosed = s.needsFlat && !isAttract && !usesTouch && s.phase != .finished
        if hud.gateClosed != gateClosed { hud.gateClosed = gateClosed }
        if gateClosed {
            let since = flatSince ?? now
            flatSince = since
            gate = now - since >= Self.gateCardDelay
            // ROUND-5 decision 1: still stuck after 6 s, offer touch for this run.
            offer = now - since >= Self.touchOfferDelay
        } else {
            flatSince = nil
        }
        if hud.showFlatGate != gate { hud.showFlatGate = gate }
        if hud.offerTouch != offer { hud.offerTouch = offer }
        var upcoming: RGBA?
        if !isAttract, s.phase != .finished, !(layout?.hasFold ?? false),
           !s.glasses.contains(where: { $0.isWaitingInSlot }), let order = session?.upcomingOrder {
            upcoming = LiquidCatalog.liquid(order.liquid).top
        }
        if hud.upcoming != upcoming { hud.upcoming = upcoming }
        var shownBanner: PlayBanner?
        if let banner, !isAttract,
           Self.bannerVisible(time: s.time, until: bannerUntil, holdsOnGate: bannerHoldsOnGate, needsFlat: s.needsFlat,
                              gateAfterPause: hud.gateAfterPause, ordersDone: s.ordersDone,
                              finished: s.phase == .finished) {
            shownBanner = banner
        }
        if hud.banner != shownBanner { hud.banner = shownBanner }
        if let layout {
            var anchors = AnchorMath.anchors(s, layout: layout)
            // The scene knows the jug's drawn bounds (walls, handle, lid); prefer them to the interior outline.
            if let drawn = scene?.jugWorldBounds, !drawn.isNull, !drawn.isEmpty {
                anchors.jug = drawn.insetBy(dx: -6, dy: -6)
            }
            // REVIEW-3 P1-1: the waiting glass as drawn (smaller, lower) when the scene has it; with its coaster.
            if let waiting = scene?.waitingGlassWorldFrame, !waiting.isNull, !waiting.isEmpty {
                anchors.waiting = waiting.insetBy(dx: -8, dy: -8)
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
        // The scored Daily is on file now (recorded above); nothing is left to close out.
        scoredDailyDay = nil
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
        guard let demo, !frozen else { return }
        let target: DemoConfig.Freeze
        if isAttract {
            // REVIEW-3 P1-2: the menu capture (`screen=menu`, with or without `freezeOn=midpour`) holds the attract
            // loop once, mid-pour with the jug really flowing, so the home frame shows a stream, never a tail of drops.
            guard demo.effectiveScreen == .menu, !attractFrozeOnce, route == .home else { return }
            guard s.jug.flow > 0.05 else { return }
            target = .midpour
        } else {
            guard let wanted = demo.freezeOn else { return }
            target = wanted
        }
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
        case .intro:
            // Round 6: during the intro phase (shift banner, venue intro card).
            if s.time >= 0.5 { freeze("intro", snapshot: s, now: now) }
        case .tier:
            // Round 6: just after a Rush tier change (the banner is up). Round 7 (QA-3 P1-1, frame 26): once the old
            // glass has left too (it slides off for `leaveDuration` after the change), so the frame shows the new
            // tier's glass on its own; never later than `tierFreezeLatest` (the banner is up for 1.6 s).
            if tierFreezePending {
                tierFreezePending = false
                tierChangedAt = simTime
            }
            if let since = tierChangedAt,
               Self.tierFreezeReady(sinceChange: simTime - since,
                                    oldGlassLeaving: s.glasses.contains(where: { $0.phase == .leaving })) {
                tierChangedAt = nil
                freeze(target.rawValue, snapshot: s, now: now)
            }
        }
    }

    /// Demo `freezeOn=tier` (QA-3 P1-1): at least this long after the tier change, and once no glass is leaving…
    static let tierFreezeEarliest = 0.35
    /// …but never later than this (session seconds after the change; the tier banner is up for 1.6 s).
    static let tierFreezeLatest = 1.2

    /// Pure: whether the `freezeOn=tier` capture may happen now.
    static func tierFreezeReady(sinceChange: Double, oldGlassLeaving: Bool) -> Bool {
        if sinceChange >= tierFreezeLatest { return true }
        return sinceChange >= tierFreezeEarliest && !oldGlassLeaving
    }

    private func freeze(_ reason: String, snapshot: GameSnapshot, now: TimeInterval) {
        frozen = true
        if isAttract { attractFrozeOnce = true }
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
