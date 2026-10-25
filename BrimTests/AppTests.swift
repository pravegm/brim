import Foundation
import SwiftUI
import Testing
@testable import Brim

// App engineer tests: ProgressStore round-trip and unlocks, DemoMode parsing, share-text formatting, and (round 2)
// the Duo pose rules, the world → screen mapping, card placement, the results headline and the daily streak.

@MainActor
struct ProgressStoreTests {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "brim.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    @Test func roundTripsThroughUserDefaults() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProgressStore(defaults: defaults)
        let level = try #require(LevelCatalog.levels.first)
        let shift = RunResult(mode: .shift(level.id), score: 1200, stars: 2, perfects: 3, bestStreak: 3,
                              judgements: [.perfect, .perfect, .perfect, .great, .short], poured: 80_000, cleared: true)
        store.record(shift, today: 300)
        let rush = RunResult(mode: .rush, score: 2500, stars: 0, perfects: 6, bestStreak: 6,
                             judgements: [.perfect, .spill, .spill, .spill], poured: 40_000, cleared: false)
        store.record(rush, today: 300)
        store.markHintSeen("lift")

        let reloaded = ProgressStore(defaults: defaults)
        #expect(reloaded.data == store.data)
        #expect(reloaded.stars(for: level.id) == 2)
        #expect(reloaded.rushBest == 2500)
        #expect(reloaded.data.stats.perfects == 9)
        #expect(reloaded.data.stats.bestStreak == 6)
        #expect(reloaded.data.stats.glasses == 9)
        #expect(reloaded.hasSeenHint("lift"))
        #expect(abs(reloaded.data.litres - 3.0) < 0.0001)
    }

    @Test func keepsBestStarsAndFlagsNewBest() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProgressStore(defaults: defaults)
        let level = try #require(LevelCatalog.levels.first)

        let good = RunResult(mode: .shift(level.id), score: 1500, stars: 3, perfects: 5, bestStreak: 5,
                             judgements: [.perfect], poured: 1000, cleared: true)
        let first = store.record(good, today: 1)
        #expect(first.isNewBest)
        #expect(first.starsAfter == 3)

        let worse = RunResult(mode: .shift(level.id), score: 400, stars: 1, perfects: 0, bestStreak: 0,
                              judgements: [.short], poured: 1000, cleared: true)
        let second = store.record(worse, today: 1)
        #expect(!second.isNewBest)
        #expect(second.previousBest == 1500)
        #expect(store.stars(for: level.id) == 3)
    }

    @Test func dailyCountsOnceAndOnlyToday() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProgressStore(defaults: defaults)

        let first = RunResult(mode: .daily(42), score: 1840, stars: 0, perfects: 2, bestStreak: 2,
                              judgements: [.perfect, .great], poured: 100, cleared: true)
        let a = store.record(first, today: 42)
        #expect(a.dailyCounted)

        let again = RunResult(mode: .daily(42), score: 3000, stars: 0, perfects: 5, bestStreak: 5,
                              judgements: [.perfect], poured: 100, cleared: true)
        let b = store.record(again, today: 42)
        #expect(!b.dailyCounted)
        #expect(b.dailyOnFile?.score == Int(1840))
        #expect(store.dailyRecord(day: 42)?.score == Int(1840))

        let stale = RunResult(mode: .daily(41), score: 900, stars: 0, perfects: 0, bestStreak: 0,
                              judgements: [], poured: 0, cleared: true)
        let c = store.record(stale, today: 42)
        #expect(!c.dailyCounted)
        #expect(store.dailyRecord(day: 41) == nil)
    }

    @Test func practiceRecordsNothing() {
        let store = ProgressStore(inMemory: ProgressData())
        let practice = RunResult(mode: .practice, score: 999, stars: 0, perfects: 4, bestStreak: 4,
                                 judgements: [.perfect], poured: 5000, cleared: false)
        store.record(practice, today: 1)
        #expect(store.data == ProgressData())
    }

    @Test func unlockRule() {
        #expect(ProgressData.unlockRule(totalStars: 0, threshold: 0))
        #expect(!ProgressData.unlockRule(totalStars: 7, threshold: 8))
        #expect(ProgressData.unlockRule(totalStars: 8, threshold: 8))
    }

    @Test func venuesUnlockWithStars() {
        var data = ProgressData()
        #expect(data.isUnlocked(.lemonadeStand))
        #expect(!data.isUnlocked(.sandBar))
        let soda = LevelCatalog.starsToUnlock(.sodaFountain)
        if soda > 0 {
            #expect(!data.isUnlocked(.sodaFountain))
        }
        // Three stars on every campaign shift opens everything, the secret Sand Bar included.
        for level in LevelCatalog.levels where level.venue != .sandBar {
            data.stars[level.id] = 3
        }
        for venue in VenueID.allCases {
            #expect(data.isUnlocked(venue))
        }
        #expect(data.earnedAchievements.contains("brim.allstars"))
        #expect(data.earnedAchievements.contains("brim.venue.potions"))
    }

    @Test func shiftsOpenInOrder() throws {
        var data = ProgressData()
        let venueLevels = LevelCatalog.levels(in: .lemonadeStand)
        let first = try #require(venueLevels.first)
        #expect(data.isPlayable(first))
        if venueLevels.count > 1 {
            let second = venueLevels[1]
            #expect(!data.isPlayable(second))
            data.stars[first.id] = 1
            #expect(data.isPlayable(second))
        }
        #expect(data.nextShift?.id != nil)
    }

    @Test func resetClearsProgress() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProgressStore(defaults: defaults)
        store.record(RunResult(mode: .rush, score: 10, stars: 0, perfects: 1, bestStreak: 1, judgements: [.perfect],
                               poured: 10, cleared: false), today: 1)
        store.resetProgress()
        #expect(ProgressStore(defaults: defaults).data == ProgressData())
    }

    @Test func toleratesMissingFields() throws {
        let json = Data(#"{"rushBest": 77}"#.utf8)
        let data = try JSONDecoder().decode(ProgressData.self, from: json)
        #expect(data.rushBest == 77)
        #expect(data.stars.isEmpty)
    }

    @Test func litresText() {
        #expect(ProgressData.litresText(poured: 0) == "0.0 L")
        #expect(ProgressData.litresText(poured: 100_000) == "2.5 L")
        #expect(ProgressData.litresText(poured: 480_000) == "12 L")
        #expect(ProgressData.litresText(poured: 48_000_000) == "1,200 L")
    }
}

struct DemoModeTests {
    @Test func parsesTheCIScenarioKeys() {
        let c = DemoConfig.parse("mode=shift:1-2;autopilot=perfect;freezeOn=perfect;streak=4;orient=portrait;duo;seed=7",
                                 today: 300)
        #expect(c.mode == GameMode.shift("1-2"))
        #expect(c.autopilot == DemoAutopilot.perfect)
        #expect(c.freezeOn == DemoConfig.Freeze.perfect)
        #expect(c.streak == Int(4))
        #expect(c.orientPortrait)
        #expect(c.duo)
        #expect(c.seed == UInt64(7))
        #expect(c.screen == nil)
        #expect(c.effectiveScreen == .game)
    }

    @Test func parsesScreensAndPresets() {
        let c = DemoConfig.parse("screen=venues;progress=mid;hints=fresh", today: 1)
        #expect(c.screen == DemoConfig.Screen.venues)
        #expect(c.progress == DemoConfig.ProgressPreset.mid)
        #expect(c.hints == DemoConfig.HintsPreset.fresh)
        #expect(c.mode == nil)
        #expect(!c.duo)
        #expect(!c.orientPortrait)

        let menu = DemoConfig.parse("screen=menu", today: 1)
        #expect(menu.effectiveScreen == .menu)
        #expect(DemoConfig.parse("", today: 1).effectiveScreen == .menu)
    }

    @Test func parsesModes() {
        #expect(DemoConfig.parse("mode=daily", today: 297).mode == GameMode.daily(297))
        #expect(DemoConfig.parse("mode=rush", today: 1).mode == GameMode.rush)
        #expect(DemoConfig.parse("mode=practice", today: 1).mode == GameMode.practice)
        #expect(DemoConfig.parse("mode=nonsense", today: 1).mode == nil)
        #expect(DemoConfig.parse("mode=shift:", today: 1).mode == nil)
    }

    @Test func ignoresUnknownKeysAndBadValues() {
        let c = DemoConfig.parse("foo=bar;autopilot=wild;streak=x;freezeOn=midpour", today: 1)
        #expect(c.autopilot == nil)
        #expect(c.streak == nil)
        #expect(c.freezeOn == DemoConfig.Freeze.midpour)
    }

    @Test func autopilotNamesMatchTheInputModule() {
        for style in [DemoAutopilot.perfect, .great, .short, .spill] {
            #expect(AutopilotStyle(rawValue: style.rawValue) != nil)
        }
    }

    @Test func demoProgressPresets() {
        #expect(DemoConfig.progressData(.fresh) == ProgressData())
        let mid = DemoConfig.progressData(.mid)
        #expect(mid.totalStars > 0)
        #expect(mid.isUnlocked(.sodaFountain))
        let full = DemoConfig.progressData(.full)
        #expect(full.hasAllStars)
    }
}

// MARK: - Round 2: pose, layout, safe placement, honest results

struct PoseRuleTests {
    private let duoPortrait = CGSize(width: 669, height: 951)
    private let duoLandscape = CGSize(width: 951, height: 669)
    private let duoCover = CGSize(width: 466, height: 678)
    private let iPhone = CGSize(width: 402, height: 874)
    private let iPhoneSE = CGSize(width: 375, height: 667)

    @Test func duoInnerPortraitPlaysWithAFold() {
        #expect(PoseRule.pose(canvas: duoPortrait, hingeSeen: true, isShut: false, bookTouchOverride: false) == .play)
        #expect(PoseRule.hasFold(canvas: duoPortrait, hingeSeen: true))
        // Before any hinge report the inner display still looks like a Duo.
        #expect(PoseRule.hasFold(canvas: duoPortrait, hingeSeen: false))
    }

    @Test func duoLandscapeShowsTheTurnCard() {
        #expect(PoseRule.pose(canvas: duoLandscape, hingeSeen: true, isShut: false, bookTouchOverride: false) == .standUp)
        #expect(PoseRule.pose(canvas: duoLandscape, hingeSeen: false, isShut: false, bookTouchOverride: false) == .standUp)
        #expect(PoseRule.pose(canvas: duoLandscape, hingeSeen: true, isShut: false, bookTouchOverride: true) == .play)
        #expect(!PoseRule.hasFold(canvas: duoLandscape, hingeSeen: true))
    }

    @Test func coverOnlyWhenShutOrOnTheSmallDisplay() {
        #expect(PoseRule.pose(canvas: duoCover, hingeSeen: true, isShut: false, bookTouchOverride: false) == .cover)
        #expect(PoseRule.pose(canvas: duoPortrait, hingeSeen: true, isShut: true, bookTouchOverride: false) == .cover)
        // The inner canvas never shows the cover just because a hinge was seen (round-1 Duo bug).
        #expect(PoseRule.pose(canvas: duoLandscape, hingeSeen: true, isShut: false, bookTouchOverride: false) != .cover)
    }

    @Test func phonesWithoutAHingeAlwaysPlay() {
        #expect(PoseRule.pose(canvas: iPhone, hingeSeen: false, isShut: false, bookTouchOverride: false) == .play)
        #expect(PoseRule.pose(canvas: iPhoneSE, hingeSeen: false, isShut: false, bookTouchOverride: false) == .play)
        #expect(!PoseRule.hasFold(canvas: iPhone, hingeSeen: false))
    }

    @Test func bookPoseTouchColumnIsPortrait() {
        let rect = PoseRule.playRect(in: duoLandscape)
        #expect(rect.height == 669)
        #expect(rect.width < rect.height)
        #expect(abs(rect.midX - 951 / 2) < 1)
        #expect(PoseRule.playRect(in: iPhone) == CGRect(origin: .zero, size: iPhone))
    }

    @Test func orientationPolicy() {
        #expect(OrientationLock.allowsLandscape(hasHinge: true, screen: CGSize(width: 402, height: 874)))
        #expect(OrientationLock.allowsLandscape(hasHinge: false, screen: CGSize(width: 669, height: 951)))
        #expect(!OrientationLock.allowsLandscape(hasHinge: false, screen: CGSize(width: 402, height: 874)))
        #expect(!OrientationLock.allowsLandscape(hasHinge: false, screen: .zero))
    }
}

struct WorldMapperTests {
    @Test func duoMapsTheCreaseOntoTheFold() {
        let info = CanvasInfo(size: CGSize(width: 669, height: 951), insets: EdgeInsets(), hasFold: true)
        let crease = info.crease
        #expect(crease != nil)
        if let crease {
            #expect(abs(crease.lowerBound - 455.5) < 2)
            #expect(abs(crease.upperBound - 495.5) < 2)
        }
        let top = info.mapper.point(CGPoint(x: 0, y: WorldLayout.worldHeight))
        #expect(abs(top.x) < 1 && abs(top.y) < 1)
    }

    @Test func phoneCropsTheSidesAndKeepsTheHeight() {
        let mapper = WorldMapper(canvas: CGSize(width: 402, height: 874))
        #expect(abs(mapper.x(116) - 0) < 3)
        #expect(abs(mapper.x(554) - 402) < 3)
        #expect(abs(mapper.y(0) - 874) < 0.5)
        #expect(abs(mapper.y(WorldLayout.worldHeight)) < 0.5)
        let info = CanvasInfo(size: CGSize(width: 402, height: 874), insets: EdgeInsets(), hasFold: false)
        #expect(info.crease == nil)
        #expect(info.topHalfHeight < info.bottomHalfTop)
        #expect(info.hudBandBottom > 90 && info.hudBandBottom < 110)
    }

    @Test func rectsFlipToScreenSpace() {
        let mapper = WorldMapper(canvas: CGSize(width: 670, height: 952))
        let r = mapper.rect(CGRect(x: 100, y: 800, width: 50, height: 100))
        #expect(abs(r.minX - 100) < 0.01)
        #expect(abs(r.minY - 52) < 0.01)
        #expect(abs(r.height - 100) < 0.01)
    }

    @Test func cardsGoBesideNeverOver() {
        let bounds = CGRect(x: 0, y: 0, width: 669, height: 450)
        let jug = CGRect(x: 250, y: 100, width: 220, height: 250)
        let size = CGSize(width: 200, height: 100)
        let p = CardPlacement.beside(jug, size: size, in: bounds)
        #expect(p != nil)
        if let p {
            let card = CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height)
            #expect(!card.intersects(jug))
            #expect(bounds.contains(card))
        }
        // A phone-width canvas has no room beside the jug.
        let narrow = CGRect(x: 0, y: 0, width: 402, height: 420)
        #expect(CardPlacement.beside(CGRect(x: 120, y: 80, width: 200, height: 230), size: size, in: narrow) == nil)
    }

    @Test func glassHalfWidthInterpolatesTheProfile() {
        let shape = GlassShape(id: "t", name: "t", style: .tumbler,
                               profile: [CGPoint(x: 40, y: 0), CGPoint(x: 60, y: 100)], baseThickness: 10, wall: 4)
        #expect(abs(AnchorMath.halfWidth(shape, at: 50) - 50) < 0.001)
        #expect(abs(AnchorMath.halfWidth(shape, at: 0) - 40) < 0.001)
        #expect(abs(AnchorMath.halfWidth(shape, at: 500) - 60) < 0.001)
    }
}

@MainActor
struct ResultsCopyTests {
    private func run(_ judgements: [Judgement], stars: Int) -> RunResult {
        RunResult(mode: .shift("1-1"), score: 500, stars: stars, perfects: judgements.filter { $0 == .perfect }.count,
                  bestStreak: 1, judgements: judgements, poured: 0, cleared: stars > 0)
    }

    @Test func flawlessOnlyWhenEveryGlassIsPerfect() {
        #expect(ResultsView.headline(for: run([.perfect, .perfect, .perfect], stars: 3), dailyOnFile: false) == "Flawless shift!")
        #expect(ResultsView.headline(for: run([.perfect, .good, .perfect], stars: 3), dailyOnFile: false) == "Great shift!")
        #expect(ResultsView.headline(for: run([.good, .short], stars: 1), dailyOnFile: false) == "Shift cleared")
        // REVIEW-2 P2-6: a failed shift never says "So close"; three spills say what ended it.
        #expect(ResultsView.headline(for: run([.spill, .spill], stars: 0), dailyOnFile: false) == "Not quite")
        #expect(ResultsView.headline(for: run([.good, .spill, .spill, .spill], stars: 0), dailyOnFile: false)
                == "Shift over — 3 spills")
    }

    @Test func newBestOnlyWhenAnEarlierBestExisted() {
        var data = ProgressData()
        let first = data.record(RunResult(mode: .shift("1-1"), score: 30, stars: 0, perfects: 0, bestStreak: 0,
                                          judgements: [.spill, .spill, .spill], poured: 0, cleared: false), today: 1)
        #expect(first.isNewBest)
        #expect(!first.showsNewBest)
        let second = data.record(RunResult(mode: .shift("1-1"), score: 400, stars: 1, perfects: 1, bestStreak: 1,
                                           judgements: [.perfect, .good], poured: 0, cleared: true), today: 1)
        #expect(second.showsNewBest)
        let rush = data.record(RunResult(mode: .rush, score: 900, stars: 0, perfects: 0, bestStreak: 0,
                                         judgements: [.good], poured: 0, cleared: false), today: 1)
        #expect(!rush.showsNewBest)
    }
}

// MARK: - Round 3: closing never pours, nothing on the fold, Duo home and results

@MainActor
struct ClosingGuardTests {
    private func makeController(_ args: String) -> GameController {
        let store = ProgressStore(inMemory: ProgressData())
        let settings = SettingsStore(defaults: nil)
        let demo = DemoConfig.parse(args, today: 1)
        let controller = GameController(store: store, settings: settings, demo: demo)
        controller.updateCanvas(CGSize(width: 669, height: 951), hasFold: true)
        return controller
    }

    @Test func closingPausesTheRunAndReopeningResumesBehindTheFlatGate() {
        let c = makeController("mode=shift:1-2;duo;orient=portrait")
        c.start(mode: .shift("1-2"))
        c.hingeSample(angle: 150, time: 10)
        #expect(!c.isPaused)
        c.hingeSample(angle: 65, time: 10.3)
        #expect(c.isClosedPaused)
        #expect(c.isPaused)
        // Nothing steps while paused: the session clock holds, so no glass can be judged.
        let a = c.advance(dt: 1.0 / 60.0, now: 10.31)?.0.time
        let b = c.advance(dt: 1.0 / 60.0, now: 10.35)?.0.time
        #expect(a != nil && a == b)
        // Still closed-ish: no resume yet.
        c.hingeSample(angle: 90, time: 11)
        #expect(c.isClosedPaused)
        c.hingeSample(angle: 130, time: 11.4)
        #expect(!c.isClosedPaused)
        #expect(!c.isPaused)
        // The resume re-armed the flat gate.
        #expect(c.hud.gateAfterPause)
    }

    @Test func userResumeAlsoReArmsTheGate() {
        let c = makeController("mode=shift:1-1;duo")
        c.start(mode: .shift("1-1"))
        c.pause()
        #expect(c.isUserPaused)
        c.resume()
        #expect(!c.isPaused)
        #expect(c.hud.gateAfterPause)
    }

    @Test func autopilotDemoFramesNeverPauseThemselves() {
        let c = makeController("mode=shift:1-1;duo;autopilot=perfect")
        c.start(mode: .shift("1-1"))
        c.hingeSample(angle: 40, time: 5)
        #expect(!c.isClosedPaused)
    }

    @Test func theAttractLoopNeverPauses() {
        let c = makeController("screen=menu;duo")
        c.hingeSample(angle: 40, time: 5)
        #expect(!c.isClosedPaused)
        #expect(!c.isPaused)
    }
}

@MainActor
struct Round3LayoutTests {
    @Test func duoHomeRowSitsUnderTheCounter() {
        let duo = CanvasInfo(size: CGSize(width: 669, height: 951), insets: EdgeInsets(), hasFold: true)
        let row = HomeView.rowFrame(info: duo, roomy: true)
        #expect(row.minY >= duo.counterY + 10)
        #expect(row.maxY <= 951)
        #expect(row.minY > duo.bottomHalfTop)
        let phone = CanvasInfo(size: CGSize(width: 402, height: 874),
                               insets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), hasFold: false)
        let phoneRow = HomeView.rowFrame(info: phone, roomy: false)
        #expect(phoneRow.minY >= phone.counterY + 10)
        #expect(phoneRow.maxY <= 874)
    }

    @Test func compactDailyShowsNumberAndState() {
        #expect(HomeView.compactDailyText(today: 297, done: false, streak: 0) == "#297")
        #expect(HomeView.compactDailyText(today: 297, done: true, streak: 1) == "#297 ✓")
        #expect(HomeView.compactDailyText(today: 297, done: true, streak: 4) == "#297 🔥4")
    }

    @Test func bookCardSplitsOnlyOnADuoInBookPose() {
        #expect(StandUpCard.splitsOnFold(CGSize(width: 951, height: 669)))
        #expect(!StandUpCard.splitsOnFold(CGSize(width: 669, height: 951)))
        #expect(!StandUpCard.splitsOnFold(CGSize(width: 874, height: 402)))
    }

    @Test func counterRecapFitsTheFlatHalf() {
        let shape = GlassShape(id: "t", name: "t", style: .tumbler,
                               profile: [CGPoint(x: 40, y: 0), CGPoint(x: 57, y: 150)], baseThickness: 10, wall: 4)
        let liquid = Liquid(id: .water, name: "Water", top: RGBA(hex: 0x7CC8F2), bottom: RGBA(hex: 0x4FA9DE), foam: nil,
                            lagTau: 0.04, foamPerVolume: 0, foamSettle: 1, reposeDegrees: 0, opacity: 0.8, fizzy: false)
        let glass = GlassState(id: 1, shape: shape, liquid: liquid, x: 300, phase: .served, liquidHeight: 100,
                               foamHeight: 0, lineHeight: 105, lineOpacity: 1, inPerfectBand: true, overflowing: false,
                               patienceLeft: nil, patienceTotal: nil, result: .perfect)
        let few = Array(repeating: GlassRecap(glass: glass, judgement: .perfect), count: 4)
        #expect(abs(CounterRecap.rowScale(few, size: CGSize(width: 629, height: 320), spacing: 18) - 0.6) < 0.0001)
        let many = Array(repeating: GlassRecap(glass: glass, judgement: .great), count: 10)
        let s = CounterRecap.rowScale(many, size: CGSize(width: 629, height: 320), spacing: 10)
        #expect(s < 0.6)
        #expect(10 * 114 * s + 9 * 10 <= 629.5)
        let short = CounterRecap.rowScale(few, size: CGSize(width: 629, height: 80), spacing: 18)
        #expect(150 * short <= 80 - 26 + 0.5)
    }
}

struct DailyStreakTests {
    @Test func countsBackFromTodayOrYesterday() {
        var data = ProgressData()
        let rec = DailyRecord(score: 1, judgements: [], perfects: 0)
        #expect(data.dailyStreak(today: 100) == 0)
        data.daily[99] = rec
        data.daily[98] = rec
        #expect(data.dailyStreak(today: 100) == 2)       // today not poured yet: the streak is still alive
        data.daily[100] = rec
        #expect(data.dailyStreak(today: 100) == 3)
        data.daily[98] = nil
        #expect(data.dailyStreak(today: 100) == 2)
        #expect(data.dailyStreak(today: 102) == 0)       // missed yesterday
    }

    @Test func nextUnlockNamesTheNextStarVenue() {
        let fresh = ProgressData()
        if LevelCatalog.starsToUnlock(.sodaFountain) > 0 {
            #expect(fresh.nextUnlock?.venue == VenueID.sodaFountain)
            #expect((fresh.nextUnlock?.missing ?? 0) > 0)
        }
        #expect(DemoConfig.progressData(.full).nextUnlock == nil)
    }
}

struct ShareTextTests {
    @Test func dailyLine() {
        let text = ShareText.daily(day: 12, judgements: [.perfect, .great, .great, .good, .spill], score: 1840)
        #expect(text == "Brim Daily #12 ⭐️🟩🟩🟨🟥 1,840")
    }

    @Test func shortIsOrange() {
        #expect(ShareText.daily(day: 3, judgements: [.short], score: 0) == "Brim Daily #3 🟧 0")
    }

    @Test func grouping() {
        #expect(ShareText.grouped(0) == "0")
        #expect(ShareText.grouped(999) == "999")
        #expect(ShareText.grouped(1000) == "1,000")
        #expect(ShareText.grouped(1_234_567) == "1,234,567")
        #expect(ShareText.grouped(-4200) == "-4,200")
    }
}
