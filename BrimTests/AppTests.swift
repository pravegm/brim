import Foundation
import QuartzCore
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

    @Test func resetKeepsTheDailyPours() throws {
        // QA-1 P2-16: a reset must not reopen today's scored Daily.
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProgressStore(defaults: defaults)
        store.record(RunResult(mode: .daily(50), score: 700, stars: 0, perfects: 1, bestStreak: 1,
                               judgements: [.perfect, .good], poured: 10, cleared: true), today: 50)
        store.resetProgress()
        let reloaded = ProgressStore(defaults: defaults)
        #expect(reloaded.dailyRecord(day: 50)?.score == Int(700))
        #expect(reloaded.data.stats == LifetimeStats())
        #expect(!reloaded.data.isUnlocked(.sandBar))
    }

    @Test func aCorruptSaveIsKeptAside() throws {
        // QA-1 P2-14: undecodable bytes are copied before a fresh save can overwrite them.
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let junk = Data("[1, 2, 3]".utf8)
        defaults.set(junk, forKey: ProgressStore.key)
        let store = ProgressStore(defaults: defaults)
        #expect(store.data == ProgressData())
        #expect(defaults.data(forKey: ProgressStore.corruptKey) == junk)
    }

    @Test func toleratesNewFieldsInsideStatsAndDailies() throws {
        // QA-1 P2-15: an unknown or missing field inside stats / a Daily keeps everything else.
        let json = Data(#"{"stats": {"perfects": 9, "runs": 2, "futureField": true}}"#.utf8)
        let data = try JSONDecoder().decode(ProgressData.self, from: json)
        #expect(data.stats.perfects == 9)
        #expect(data.stats.runs == 2)
        #expect(data.stats.glasses == 0)
        let record = try JSONDecoder().decode(DailyRecord.self, from: Data(#"{"score": 1840, "perfects": 2}"#.utf8))
        #expect(record.score == 1840)
        #expect(record.judgements.isEmpty)
        // And the whole save still round-trips with the new attempt marker in it.
        var full = ProgressData()
        full.daily[12] = record
        full.dailyStarted[13] = DailyRecord(score: 5, judgements: [.good], perfects: 0)
        let back = try JSONDecoder().decode(ProgressData.self, from: JSONEncoder().encode(full))
        #expect(back == full)
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
        // Round 4 (REVIEW-3 P2-4): ~85 pt tumblers, i.e. 0.75 of the play size when the row has room.
        #expect(abs(CounterRecap.rowScale(few, size: CGSize(width: 629, height: 320), spacing: 18) - 0.75) < 0.0001)
        let many = Array(repeating: GlassRecap(glass: glass, judgement: .great), count: 10)
        let s = CounterRecap.rowScale(many, size: CGSize(width: 629, height: 320), spacing: 10)
        #expect(s < 0.75)
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

// MARK: - Round 4: QA-1 P1s and REVIEW-3 P1s (App)

struct DailyAttemptTests {
    private func run(_ day: Int, score: Int, _ judgements: [Judgement]) -> RunResult {
        RunResult(mode: .daily(day), score: score, stars: 0, perfects: judgements.filter { $0 == .perfect }.count,
                  bestStreak: 1, judgements: judgements, poured: 100, cleared: true)
    }

    @Test func leavingTheScoredAttemptFilesThePourSoFar() {
        // QA-1 P1-2: start, spill twice, leave: that IS the day's score; the next run is practice.
        var data = ProgressData()
        let hoisted564 = data.beginDailyAttempt(day: 298)
        #expect(hoisted564)
        data.updateDailyAttempt(day: 298, score: 0, judgements: [.spill, .spill], perfects: 0)
        let filed = data.closeDailyAttempt(day: 298)
        #expect(filed?.judgements == [Judgement.spill, .spill])
        #expect(data.daily[298]?.score == Int(0))
        #expect(data.dailyStarted.isEmpty)
        let hoisted570 = data.beginDailyAttempt(day: 298)
        #expect(!hoisted570)
        // The "retry" is practice: it never replaces the filed score.
        let retry = data.record(run(298, score: 2900, [.perfect, .perfect]), today: 298)
        #expect(!retry.dailyCounted)
        #expect(retry.dailyOnFile?.score == Int(0))
        #expect(data.daily[298]?.score == Int(0))
    }

    @Test func leavingBeforeTheFirstServeCostsNothing() {
        var data = ProgressData()
        let hoisted580 = data.beginDailyAttempt(day: 10)
        #expect(hoisted580)
        let hoisted581 = data.closeDailyAttempt(day: 10)
        #expect(hoisted581 == nil)
        #expect(data.daily[10] == nil)
        let hoisted583 = data.beginDailyAttempt(day: 10)
        #expect(hoisted583)
    }

    @Test func finishingTheMarkedAttemptCountsEvenAfterMidnight() {
        // QA-1 P2-1: started on day 100, finished at 00:00:30 on day 101.
        var data = ProgressData()
        let hoisted589 = data.beginDailyAttempt(day: 100)
        #expect(hoisted589)
        let outcome = data.record(run(100, score: 1500, [.perfect, .great]), today: 101)
        #expect(outcome.dailyCounted)
        #expect(data.daily[100]?.score == Int(1500))
        #expect(data.dailyStarted[100] == nil)
    }

    @MainActor
    @Test func anAttemptLeftByACrashIsFiledAtLaunch() throws {
        let suite = "brim.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProgressStore(defaults: defaults)
        #expect(store.beginDailyAttempt(day: 7))
        store.updateDailyAttempt(day: 7, score: 450, judgements: [.good, .short], perfects: 0)
        // The app dies here. Next launch:
        let relaunched = ProgressStore(defaults: defaults)
        #expect(relaunched.dailyRecord(day: 7)?.score == Int(450))
        #expect(relaunched.data.dailyStarted.isEmpty)
        #expect(!relaunched.beginDailyAttempt(day: 7))
    }

    @MainActor
    @Test func theControllerMarksTheAttemptAndPracticeIsLabelled() {
        let store = ProgressStore(inMemory: ProgressData())
        let c = GameController(store: store, settings: SettingsStore(defaults: nil),
                               demo: DemoConfig.parse("mode=daily:33", today: 33))
        c.updateCanvas(CGSize(width: 402, height: 874), hasFold: false)
        c.start(mode: .daily(33))
        #expect(c.isScoredDaily)
        #expect(!c.isPracticeDaily)
        #expect(store.data.dailyStarted[33] != nil)
        #expect(c.hudTitle == "Daily #33")
        // Nothing served: leaving costs nothing, and the next start is the scored attempt again.
        c.quitToMenu()
        #expect(store.dailyRecord(day: 33) == nil)
        #expect(store.data.dailyStarted[33] == nil)
        // Once on file, a Daily is practice and says so.
        store.record(run(33, score: 900, [.good]), today: 33)
        c.start(mode: .daily(33))
        #expect(!c.isScoredDaily)
        #expect(c.isPracticeDaily)
        #expect(c.hudTitle == "Daily #33 · Practice")
    }
}

@MainActor
struct LifecycleTests {
    private func makeController(_ args: String, canvas: CGSize = CGSize(width: 669, height: 951),
                                fold: Bool = true) -> GameController {
        let c = GameController(store: ProgressStore(inMemory: ProgressData()), settings: SettingsStore(defaults: nil),
                               demo: DemoConfig.parse(args, today: 1))
        c.updateCanvas(canvas, hasFold: fold)
        return c
    }

    @Test func aStoredHingeFlagIsOnlyBelievedOnADuoShapedScreen() {
        // QA-1 P1-1: a Duo backup restored onto an iPhone 18 Pro or an SE must not lock it into Duo mode.
        #expect(OrientationLock.trustsStoredHinge(true, screen: CGSize(width: 669, height: 951)))
        #expect(OrientationLock.trustsStoredHinge(true, screen: CGSize(width: 466, height: 678)))
        #expect(OrientationLock.trustsStoredHinge(true, screen: CGSize(width: 951, height: 669)))
        #expect(!OrientationLock.trustsStoredHinge(true, screen: CGSize(width: 402, height: 874)))
        #expect(!OrientationLock.trustsStoredHinge(true, screen: CGSize(width: 375, height: 667)))
        #expect(!OrientationLock.trustsStoredHinge(false, screen: CGSize(width: 669, height: 951)))
        #expect(!OrientationLock.trustsStoredHinge(true, screen: .zero))
    }

    @Test func changingTheCanvasKeepsTheRun() {
        // QA-1 P1-3: tabletop, then book pose "Use touch" (a 468 x 669 column, no fold) mid-shift keeps the session.
        let c = makeController("mode=shift:1-1;duo")
        c.start(mode: .shift("1-1"))
        var now = 100.0
        var before = 0.0
        for _ in 0..<40 {
            now += 1.0 / 60.0
            before = c.advance(dt: 1.0 / 60.0, now: now)?.0.time ?? 0
        }
        #expect(before > 0.3)
        let generation = c.sceneGeneration
        c.updateCanvas(CGSize(width: 468, height: 669), hasFold: false)
        #expect(c.sceneGeneration == generation + 1)
        let after = c.advance(dt: 0, now: now + 0.01)?.0.time ?? 0
        #expect(after >= before - 0.0001)
        #expect(c.mode == GameMode.shift("1-1"))
        #expect(c.route == .playing)
        // And back to tabletop: still the same run.
        c.updateCanvas(CGSize(width: 669, height: 951), hasFold: true)
        let back = c.advance(dt: 0, now: now + 0.02)?.0.time ?? 0
        #expect(back >= before - 0.0001)
    }

    @Test func theAttractLoopIsRebuiltOnACanvasChange() {
        let c = makeController("screen=menu")
        c.updateCanvas(CGSize(width: 402, height: 874), hasFold: false)
        #expect(c.isAttract)
        #expect(c.route == .home)
    }

    @Test func theScreenStaysAwakeOnlyDuringALiveRun() {
        // QA-1 P1-4: hinge-only play never touches the screen.
        let c = makeController("mode=shift:1-1;duo")
        #expect(!c.keepsScreenAwake)                 // home
        c.start(mode: .shift("1-1"))
        #expect(c.keepsScreenAwake)
        c.pause()
        #expect(!c.keepsScreenAwake)
        c.resume()
        #expect(c.keepsScreenAwake)
        c.quitToMenu()
        #expect(!c.keepsScreenAwake)
    }

    @Test func closedCardNamesTheRun() {
        #expect(GameController.runNoun(for: .shift("1-1")) == "shift")
        #expect(GameController.runNoun(for: .rush) == "Rush run")
        #expect(GameController.runNoun(for: .daily(3)) == "Daily Pour")
    }
}

@MainActor
struct Round4LayoutTests {
    private let duo = CanvasInfo(size: CGSize(width: 669, height: 951), insets: EdgeInsets(), hasFold: true)
    private let phone = CanvasInfo(size: CGSize(width: 402, height: 874),
                                   insets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), hasFold: false)

    private func glass(x: CGFloat) -> GlassAnchor {
        GlassAnchor(id: 1, x: x, lineY: 190, halfWidthAtLine: 58, rimY: 264, baseY: WorldLayout.counter, filling: false)
    }

    private func rect(_ center: CGPoint) -> CGRect {
        let s = CalloutPlacement.pillSize
        return CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height)
    }

    @Test func fillToHereGoesRightOfTheTabOnTheDuo() {
        // REVIEW-3 P1-1: active glass at the centre stop, the waiting glass on the left.
        let waiting = CGRect(x: 105, y: 88, width: 120, height: 170)
        let p = CalloutPlacement.place(glass: glass(x: 366), waiting: waiting, info: duo)
        #expect(p.side == CalloutPlacement.Side.right)
        let r = rect(p.center)
        #expect(!r.intersects(duo.mapper.rect(waiting)))
        #expect(r.minY >= duo.bottomHalfTop + 8 - 0.5)
        #expect(r.maxX <= 669 - duo.sidePad + 0.5)
    }

    @Test func fillToHereNeverSitsOnTheWaitingGlassOnAPhone() {
        let waiting = CGRect(x: 105, y: 88, width: 120, height: 170)
        let p = CalloutPlacement.place(glass: glass(x: 366), waiting: waiting, info: phone)
        let r = rect(p.center)
        #expect(!r.intersects(phone.mapper.rect(waiting)))
        #expect(r.minX >= phone.sidePad - 0.5 && r.maxX <= 402 - phone.sidePad + 0.5)
        // Without a waiting glass the pill stays on screen too.
        let free = CalloutPlacement.place(glass: glass(x: 366), waiting: nil, info: phone)
        #expect(rect(free.center).minX >= phone.sidePad - 0.5)
    }

    @Test func duoVenuesNeverPutACardOnTheFold() {
        // REVIEW-3 P1-3: two venues a screen, one per half, paged.
        let pages = VenuesView.duoPages(VenueID.allCases)
        #expect(pages.count == 3)
        #expect(pages.allSatisfy { !$0.isEmpty && $0.count <= 2 })
        #expect(pages.flatMap { $0 } == VenueID.allCases)
        let slots = VenuesView.duoSlots(info: duo)
        #expect(slots.top.upperBound <= duo.topHalfHeight - 8 + 0.01)
        #expect(slots.bottom.lowerBound >= duo.bottomHalfTop + 8 - 0.01)
        #expect(slots.bottom.upperBound <= 951)
        // A venue card (two rows of shift bubbles, ~260 pt) fits each slot; the first also holds the header.
        #expect(slots.top.upperBound - slots.top.lowerBound >= 260 + 60)
        #expect(slots.bottom.upperBound - slots.bottom.lowerBound >= 260)
    }

    @Test func duoHomeRowClearsTheCoasters() {
        // REVIEW-3 P2-5: at least 12 pt between the lowest coaster (the waiting glass sits 10 pt low) and the buttons.
        let row = HomeView.rowFrame(info: duo, roomy: true, lowestGlassWorldY: HomeView.lowestGlassWorldY)
        let coasterBottom = duo.mapper.y(HomeView.lowestGlassWorldY - HomeView.coasterDepth)
        #expect(row.minY >= coasterBottom + 12 - 0.5)
        #expect(row.maxY <= 951)
        #expect(row.height >= 52)
    }

    @Test func recapGlyphsAreNotColourOnly() {
        #expect(RecapGlyph.symbol(for: .perfect) == "checkmark")
        #expect(RecapGlyph.symbol(for: .spill) == "drop.fill")
        #expect(RecapGlyph.symbol(for: .short) == "arrow.down")
    }
}

@MainActor
struct GameCenterQueueTests {
    @Test func entriesRoundTripAndOldOnesStillParse() {
        let entry = GameCenterManager.encode(leaderboard: "brim.daily.score", score: 1840, day: 298, token: "abc")
        let parsed = GameCenterManager.parse(entry)
        #expect(parsed?.leaderboard == "brim.daily.score")
        #expect(parsed?.score == Int(1840))
        #expect(parsed?.day == Int(298))
        #expect(parsed?.token == "abc")
        let old = GameCenterManager.parse("brim.rush.best|2140")
        #expect(old?.score == Int(2140))
        #expect(old?.day == nil)
        #expect(GameCenterManager.parse("garbage") == nil)
    }

    @Test func dailyScoresGoStaleAfterTheirDay() {
        // QA-1 P2-17: never submitted onto the next day's recurring leaderboard.
        let daily = GameCenterManager.QueuedScore(leaderboard: "brim.daily.score", score: 10, day: 298, token: "t")
        #expect(!GameCenterManager.isStale(daily, today: 298))
        #expect(GameCenterManager.isStale(daily, today: 299))
        let rush = GameCenterManager.QueuedScore(leaderboard: "brim.rush.best", score: 10, day: nil, token: "t")
        #expect(!GameCenterManager.isStale(rush, today: 400))
    }
}

// MARK: - Round 5: QA-2 and REVIEW-5 (App)

@MainActor
struct Round5AppTests {
    private func makeController(_ args: String, canvas: CGSize = CGSize(width: 669, height: 951), fold: Bool = true,
                                store: ProgressStore? = nil, settings: SettingsStore? = nil) -> GameController {
        let c = GameController(store: store ?? ProgressStore(inMemory: ProgressData()),
                               settings: settings ?? SettingsStore(defaults: nil),
                               demo: DemoConfig.parse(args, today: 33))
        c.updateCanvas(canvas, hasFold: fold)
        return c
    }

    // ROUND-5 decision 5 (QA-2 P1-4): a venue achievement needs every shift of the venue cleared, not the venue open.
    @Test func venueAchievementsNeedEveryShiftCleared() {
        var data = ProgressData()
        for level in LevelCatalog.levels(in: .lemonadeStand) { data.stars[level.id] = 3 }
        if LevelCatalog.starsToUnlock(.sodaFountain) <= data.totalStars {
            #expect(data.isUnlocked(.sodaFountain))
        }
        #expect(!data.earnedAchievements.contains("brim.venue.soda"))
        let soda = LevelCatalog.levels(in: .sodaFountain)
        #expect(!soda.isEmpty)
        for level in soda.dropLast() { data.stars[level.id] = 1 }
        #expect(!data.earnedAchievements.contains("brim.venue.soda"))
        if let last = soda.last { data.stars[last.id] = 1 }
        #expect(data.earnedAchievements.contains("brim.venue.soda"))
        #expect(!data.earnedAchievements.contains("brim.venue.diner"))
        // The Sand Bar: one cleared shift isn't "every Sand Bar shift cleared".
        let sand = LevelCatalog.levels(in: .sandBar)
        if let first = sand.first {
            data.stars[first.id] = 1
            #expect(data.earnedAchievements.contains("brim.sandbar") == (sand.count == 1))
            for level in sand { data.stars[level.id] = 1 }
            #expect(data.earnedAchievements.contains("brim.sandbar"))
        }
        // The ids never change (they are live in App Store Connect).
        for id in ["brim.venue.soda", "brim.venue.diner", "brim.venue.conveyor", "brim.venue.potions", "brim.sandbar"] {
            #expect(GameCenterManager.achievementIDs.contains(id))
        }
    }

    @Test func staleQueuedAchievementsAreDropped() {
        let pending = GameCenterManager.pending(earned: ["brim.first.perfect", "brim.unknown"],
                                                reported: ["brim.streak.10"])
        #expect(pending == Set(["brim.first.perfect"]))
        #expect(GameCenterManager.pending(earned: ["brim.streak.10"], reported: ["brim.streak.10"]).isEmpty)
    }

    // `.over` everywhere (contract change, ROUND-5 decision 4).
    @Test func overHasItsOwnSquareGlyphAndColour() {
        #expect(ShareText.emoji(for: .over) == "🟪")
        #expect(ShareText.daily(day: 5, judgements: [.perfect, .over, .short, .spill], score: 300)
                == "Brim Daily #5 ⭐️🟪🟧🟥 300")
        #expect(RecapGlyph.symbol(for: .over) == "arrow.up")
        let all: [Judgement] = [.perfect, .great, .good, .short, .over, .spill]
        #expect(Set(all.map { ShareText.emoji(for: $0) }).count == all.count)
        #expect(Set(all.map { RecapGlyph.symbol(for: $0) }).count == 4)
        #expect(!Judgement.over.isHit)
    }

    // REVIEW-5 P1-7: the streak rides in the share line from 2 days.
    @Test func shareLineCarriesTheStreak() {
        #expect(ShareText.daily(day: 297, judgements: [.perfect, .great], score: 570, streak: 4)
                == "Brim Daily #297 ⭐️🟩 570 🔥4")
        #expect(ShareText.daily(day: 297, judgements: [.perfect], score: 570, streak: 1) == "Brim Daily #297 ⭐️ 570")
        #expect(ResultsView.dailyLine(streak: 4, best: 1240) == "🔥 4 days in a row · best 1,240")
        #expect(ResultsView.dailyLine(streak: 1, best: 300) == "best 300")
        var data = ProgressData()
        #expect(data.bestDaily == 0)
        data.daily[3] = DailyRecord(score: 900, judgements: [], perfects: 0)
        data.daily[4] = DailyRecord(score: 1240, judgements: [], perfects: 0)
        #expect(data.bestDaily == 1240)
    }

    // REVIEW-5 P1-6: the headline counts every strike kind; a struck-out shift shows progress and a tip.
    @Test func failedShiftHeadlineProgressAndTip() throws {
        let level = try #require(LevelCatalog.levels(in: .lemonadeStand).first)
        func shift(_ judgements: [Judgement], id: String? = nil) -> RunResult {
            RunResult(mode: .shift(id ?? level.id), score: 0, stars: 0, perfects: 0, bestStreak: 0,
                      judgements: judgements, poured: 0, cleared: false)
        }
        #expect(ResultsView.headline(for: shift([.good, .over, .spill, .over]), dailyOnFile: false)
                == "Shift over — 2 over, 1 spill")
        #expect(ResultsView.headline(for: shift([.spill, .spill, .spill]), dailyOnFile: false) == "Shift over — 3 spills")
        #expect(ResultsView.headline(for: shift([.short, .short, .short]), dailyOnFile: false) == "Shift over — 3 shorts")
        #expect(ResultsView.headline(for: shift([.over, .good]), dailyOnFile: false) == "Not quite")
        let failed = shift([.good, .over, .spill, .over])
        #expect(ResultsView.progressLine(for: failed) == "4 of \(level.orders.count) glasses")
        #expect(ResultsView.coachingTip(for: failed) == "Stop a little earlier: the stream keeps falling.")
        #expect(ResultsView.coachingTip(for: shift([.short, .short, .good])) != nil)
        if let foam = LevelCatalog.levels(in: .sodaFountain).first {
            #expect(ResultsView.coachingTip(for: shift([.over, .spill, .over], id: foam.id))?.contains("Foam") == true)
        }
        var cleared = failed
        cleared.cleared = true
        cleared.stars = 1
        #expect(ResultsView.progressLine(for: cleared) == nil)
        #expect(ResultsView.coachingTip(for: cleared) == nil)
        let rush = RunResult(mode: .rush, score: 900, stars: 0, perfects: 0, bestStreak: 0, judgements: [.good],
                             poured: 0, cleared: true)
        let headline = ResultsView.headline(for: rush, dailyOnFile: false)
        #expect(headline == "Rush over!")
        #expect(!headline.lowercased().contains("call"))
    }

    // QA-2 P2-8: the Daily rolls over at 00:00 UTC; say when, on the player's clock.
    @Test func dailyRolloverNoteSaysWhenInLocalTime() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(utc.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 15)))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let gb = Locale(identifier: "en_GB")
        #expect(ResultsView.dailyRolloverNote(now: now, timeZone: newYork, locale: gb)
                == "Today's scored pour. New glasses at 20:00.")
        #expect(ResultsView.dailyRolloverNote(now: now, timeZone: utc.timeZone, locale: gb)
                == "Today's scored pour. New glasses at 00:00.")
        #expect(!ResultsView.dailyRolloverNote(now: now).contains("tomorrow"))
    }

    // QA-2 P2-5: once the first glass has arrived, leaving files the attempt (a 0 with nothing served).
    @Test func anArmedAttemptIsFiledEvenWithNothingServed() {
        var data = ProgressData()
        let began = data.beginDailyAttempt(day: 40)
        #expect(began)
        data.armDailyAttempt(day: 40)
        #expect(data.dailyArmed.contains(40))
        let filed = data.closeDailyAttempt(day: 40)
        #expect(filed?.score == Int(0))
        #expect(filed?.judgements.isEmpty == true)
        #expect(data.daily[40]?.score == Int(0))
        #expect(data.dailyArmed.isEmpty)
        let again = data.beginDailyAttempt(day: 40)
        #expect(!again)
        // Arming without a marked attempt does nothing.
        var other = ProgressData()
        other.armDailyAttempt(day: 41)
        #expect(other.dailyArmed.isEmpty)
    }

    @Test func anArmedAttemptLeftByACrashIsFiledAtLaunch() throws {
        let suite = "brim.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProgressStore(defaults: defaults)
        #expect(store.beginDailyAttempt(day: 8))
        store.armDailyAttempt(day: 8)
        let relaunched = ProgressStore(defaults: defaults)
        #expect(relaunched.dailyRecord(day: 8)?.score == Int(0))
        #expect(relaunched.data.dailyArmed.isEmpty)
        #expect(!relaunched.beginDailyAttempt(day: 8))
    }

    @Test func theControllerFilesTheDailyOnceTheFirstGlassArrives() {
        let store = ProgressStore(inMemory: ProgressData())
        let c = makeController("mode=daily:33", canvas: CGSize(width: 402, height: 874), fold: false, store: store)
        c.start(mode: .daily(33))
        #expect(c.isScoredDaily)
        var now = 50.0
        var frames = 0
        while !store.data.dailyArmed.contains(33) && frames < 1200 {
            now += 1.0 / 60.0
            _ = c.advance(dt: 1.0 / 60.0, now: now)
            frames += 1
        }
        #expect(store.data.dailyArmed.contains(33))
        // Bail out on glass 1 (nothing served yet): that is the day's score now, not a free retry.
        c.pause()
        c.quitToMenu()
        #expect(store.dailyRecord(day: 33) != nil)
        c.start(mode: .daily(33))
        #expect(!c.isScoredDaily)
        #expect(c.isPracticeDaily)
    }

    // QA-2 P2-4 / ROUND-5 App row: quitting Rush keeps the score.
    @Test func quittingRushRecordsTheScore() {
        let store = ProgressStore(inMemory: ProgressData())
        let c = makeController("mode=rush;autopilot=perfect", canvas: CGSize(width: 402, height: 874), fold: false,
                               store: store)
        c.start(mode: .rush)
        var now = 50.0
        var frames = 0
        var score = 0
        while c.hud.serveTick == 0 && frames < 4000 {
            now += 1.0 / 60.0
            score = c.advance(dt: 1.0 / 60.0, now: now)?.0.score ?? score
            frames += 1
        }
        #expect(c.hud.serveTick > 0)
        #expect(store.data.stats.runs == 0)
        c.quitToMenu()
        #expect(store.data.stats.runs == 1)
        #expect(store.rushBest == score)
        #expect(store.data.stats.glasses >= 1)
        // Leaving the attract loop afterwards records nothing more.
        c.showHome()
        #expect(store.data.stats.runs == 1)
    }

    @Test func pauseCardSaysWhatLeavingDoes() {
        #expect(PauseView.leavingNote(scoredDaily: false, mode: .rush) != nil)
        #expect(PauseView.leavingNote(scoredDaily: true, mode: .daily(3)) != nil)
        #expect(PauseView.leavingNote(scoredDaily: false, mode: .shift("1-1")) == nil)
        #expect(GameController.bestPerfectStreak([.perfect, .perfect, .good, .perfect, .perfect, .perfect, .over]) == 3)
        #expect(GameController.bestPerfectStreak([]) == 0)
    }

    // ROUND-5 decision 1: after 6 s stuck on the flat gate, "Use touch instead" switches to touch. Round 7 (QA-3
    // P2-11): it is remembered across runs until the hinge pours again (flat, then lifted) or the app relaunches.
    @Test func stuckOnTheGateOffersTouchUntilTheHingePoursAgain() {
        let settings = SettingsStore(defaults: nil)
        let c = makeController("mode=shift:1-1;duo", settings: settings)
        c.start(mode: .shift("1-1"))
        #expect(!c.usesTouch)
        // The gate clock runs on the frame clock (CACurrentMediaTime, as the scene passes it).
        let t0 = CACurrentMediaTime()
        var now = t0
        c.hingeSample(angle: 140, time: now)          // held up, never flat
        var last: GameSnapshot?
        while now < t0 + 5.5 {
            now += 1.0 / 60.0
            last = c.advance(dt: 1.0 / 60.0, now: now)?.0
        }
        #expect(last?.needsFlat == true)
        #expect(c.hud.showFlatGate)
        #expect(!c.hud.offerTouch)
        while now < t0 + 6.6 {
            now += 1.0 / 60.0
            last = c.advance(dt: 1.0 / 60.0, now: now)?.0
        }
        #expect(c.hud.offerTouch)
        c.useTouchForThisRun()
        #expect(c.usesTouch)
        #expect(c.runTouchOverride)
        #expect(!c.hud.showFlatGate)
        now += 1.0 / 60.0
        last = c.advance(dt: 1.0 / 60.0, now: now)?.0
        #expect(last?.needsFlat == false)
        // Nothing persisted: the setting is untouched.
        #expect(!settings.touchOnDuo)
        // Retry and Next shift keep touch (no second 6 s on the gate).
        c.restart()
        #expect(c.runTouchOverride)
        #expect(c.usesTouch)
        c.start(mode: .shift("1-2"))
        #expect(c.usesTouch)
        now += 1.0 / 60.0
        last = c.advance(dt: 1.0 / 60.0, now: now)?.0
        #expect(last?.needsFlat == false)
        #expect(!c.hud.showFlatGate)
        // Lifting without having been flat is not a hinge pour.
        now += 0.1
        c.hingeSample(angle: 130, time: now)
        c.restart()
        #expect(c.runTouchOverride)
        // Flat, then lifted mid-run: the input never swaps under the player; the next run is back on the hinge.
        now += 0.1
        c.hingeSample(angle: 180, time: now)
        now += 0.1
        c.hingeSample(angle: 150, time: now)
        #expect(c.runTouchOverride)
        #expect(c.usesTouch)
        c.restart()
        #expect(!c.runTouchOverride)
        #expect(!c.usesTouch)
    }

    // QA-3 P2-11: what counts as the hinge pouring again. Pure.
    @Test func hingePoursAgainAfterReadingFlat() {
        let flat = GameController.hingePoursAgain(sawFlat: false, hingeAngle: 179)
        #expect(flat.sawFlat && !flat.poured)
        let liftedFirst = GameController.hingePoursAgain(sawFlat: false, hingeAngle: 120)
        #expect(!liftedFirst.sawFlat && !liftedFirst.poured)
        let nudge = GameController.hingePoursAgain(sawFlat: true, hingeAngle: 180 - GameController.hingePourTilt + 5)
        #expect(nudge.sawFlat && !nudge.poured)
        let pour = GameController.hingePoursAgain(sawFlat: true, hingeAngle: 180 - GameController.hingePourTilt - 1)
        #expect(pour.poured)
    }

    // QA-2 P2-9: the Home gesture waits for a second swipe while a run is live.
    @Test func bottomEdgeIsDeferredOnlyWhileLive() {
        #expect(RootView.deferredEdges(paused: false) == .bottom)
        #expect(RootView.deferredEdges(paused: true).isEmpty)
    }
}

// MARK: - Round 6: the late game (ROUND-6 decisions 1, 2, 4, 5; REVIEW-5)

@MainActor
struct Round6AppTests {
    private func makeController(_ args: String, canvas: CGSize = CGSize(width: 669, height: 951), fold: Bool = true,
                                store: ProgressStore? = nil) -> GameController {
        let c = GameController(store: store ?? ProgressStore(inMemory: ProgressData()),
                               settings: SettingsStore(defaults: nil),
                               demo: DemoConfig.parse(args, today: 33))
        c.updateCanvas(canvas, hasFold: fold)
        return c
    }

    private func shiftResult(_ level: Level, _ judgements: [Judgement], stars: Int, cleared: Bool = true) -> RunResult {
        RunResult(mode: .shift(level.id), score: 1000, stars: stars,
                  perfects: judgements.filter { $0 == .perfect }.count, bestStreak: 0, judgements: judgements,
                  poured: 0, cleared: cleared)
    }

    // Decision 4: a Flawless crown per shift, earned once, never lost.
    @Test func flawlessCrownIsEarnedOnceAndKept() throws {
        let level = try #require(LevelCatalog.levels(in: .lemonadeStand).first)
        let total = level.orders.count
        var data = ProgressData()
        let flawless = shiftResult(level, Array(repeating: .perfect, count: total), stars: 3)
        let first = data.record(flawless, today: 10)
        #expect(first.crownEarned)
        #expect(first.hasCrown)
        #expect(data.hasCrown(level.id))
        #expect(data.crownsEarned(in: .lemonadeStand) == 1)
        let again = data.record(flawless, today: 10)
        #expect(!again.crownEarned)
        #expect(again.hasCrown)
        // A later run with a Great keeps the crown.
        var mixed = Array(repeating: Judgement.perfect, count: total)
        mixed[0] = .great
        let later = data.record(shiftResult(level, mixed, stars: 3), today: 11)
        #expect(!later.crownEarned)
        #expect(later.hasCrown)
        #expect(data.crowns == Set([level.id]))
        // Not flawless: a Great, a failed run, nothing served, or another mode.
        #expect(!ProgressData.isFlawless(shiftResult(level, mixed, stars: 3)))
        #expect(!ProgressData.isFlawless(shiftResult(level, [.perfect, .perfect], stars: 0, cleared: false)))
        #expect(!ProgressData.isFlawless(shiftResult(level, [], stars: 0)))
        let rush = RunResult(mode: .rush, score: 10, stars: 0, perfects: 1, bestStreak: 1, judgements: [.perfect],
                             poured: 0, cleared: true)
        #expect(!ProgressData.isFlawless(rush))
        var other = ProgressData()
        let notCrowned = other.record(shiftResult(level, mixed, stars: 3), today: 10)
        #expect(!notCrowned.hasCrown)
        #expect(other.crowns.isEmpty)
    }

    // Tolerant decode: an older save has no crowns; a bad crowns value never costs the stars.
    @Test func crownsDecodeTolerantlyAndRoundTrip() throws {
        let old = try JSONDecoder().decode(ProgressData.self, from: Data(#"{"stars": {"1-1": 3}}"#.utf8))
        #expect(old.crowns.isEmpty)
        #expect(old.stars(for: "1-1") == 3)
        let bad = try JSONDecoder().decode(ProgressData.self,
                                           from: Data(#"{"stars": {"1-1": 2}, "crowns": 42}"#.utf8))
        #expect(bad.crowns.isEmpty)
        #expect(bad.stars(for: "1-1") == 2)
        var data = ProgressData()
        data.crowns = ["1-1", "2-3"]
        let encoded = try JSONEncoder().encode(data)
        let back = try JSONDecoder().decode(ProgressData.self, from: encoded)
        #expect(back.crowns == Set(["1-1", "2-3"]))
        #expect(back == data)
    }

    @Test func crownsPersistThroughTheStoreAndResetClearsThem() throws {
        let suite = "brim.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let level = try #require(LevelCatalog.levels.first)
        let store = ProgressStore(defaults: defaults)
        let outcome = store.record(shiftResult(level, Array(repeating: .perfect, count: level.orders.count), stars: 3),
                                   today: 5)
        #expect(outcome.crownEarned)
        let reloaded = ProgressStore(defaults: defaults)
        #expect(reloaded.hasCrown(level.id))
        reloaded.resetProgress()
        #expect(!reloaded.hasCrown(level.id))
    }

    // Venues: the crown count shows once there is a crown or every star is in.
    @Test func venueCrownLine() {
        #expect(VenuesView.crownLine(crowns: 0, shifts: 8, stars: 20) == nil)
        #expect(VenuesView.crownLine(crowns: 0, shifts: 8, stars: 24) == "0/8")
        #expect(VenuesView.crownLine(crowns: 3, shifts: 8, stars: 12) == "3/8")
        #expect(VenuesView.crownLine(crowns: 3, shifts: 0, stars: 0) == nil)
        let full = DemoConfig.progressData(.full)
        #expect(full.crownsEarned(in: .lemonadeStand) == LevelCatalog.levels(in: .lemonadeStand).count)
    }

    // Results: under 3★ say what 3★ needs; at 3★ name the crown; nothing once crowned or on a fail.
    // Round 7 (QA-3 P1-2): the decided rule is 3★ = no misses, 2★ = one miss, 1★ = cleared; Perfects only crown.
    @Test func resultsSayWhatIsLeftToChase() throws {
        let level = try #require(LevelCatalog.levels(in: .lemonadeStand).first)
        let total = level.orders.count
        try #require(total >= 3)
        // QA-3's repro: one Short and the rest Perfect is 2★, and the reason is the miss, not the Perfects.
        var oneShort = Array(repeating: Judgement.perfect, count: total)
        oneShort[0] = .short
        let oneShortStars = Rules.stars(perfects: total - 1, hits: total - 1, spills: 0, total: total)
        #expect(oneShortStars == 2)
        let line = try #require(ResultsView.chaseLine(for: shiftResult(level, oneShort, stars: oneShortStars),
                                                      hasCrown: false))
        #expect(line == "3★ needs every glass a hit. You had 1 miss.")
        #expect(!line.contains("Perfect"))
        // Two misses (a spill and an over) with no Perfects at all: 1★, plural.
        var twoMisses = Array(repeating: Judgement.great, count: total)
        twoMisses[0] = .spill
        twoMisses[1] = .over
        let twoMissStars = Rules.stars(perfects: 0, hits: total - 2, spills: 1, total: total)
        #expect(twoMissStars == 1)
        let plural = ResultsView.chaseLine(for: shiftResult(level, twoMisses, stars: twoMissStars), hasCrown: false)
        #expect(plural == "3★ needs every glass a hit. You had 2 misses.")
        // Every glass a hit with no Perfect is 3★ now: the crown line, not a 3★ line.
        let allGreat = Array(repeating: Judgement.great, count: total)
        let allGreatStars = Rules.stars(perfects: 0, hits: total, spills: 0, total: total)
        #expect(allGreatStars == 3)
        let greatLine = ResultsView.chaseLine(for: shiftResult(level, allGreat, stars: allGreatStars), hasCrown: false)
        #expect(greatLine == "Flawless crown: every glass Perfect. You had 0 of \(total).")
        let threeStar = Array(repeating: Judgement.perfect, count: total - 1) + [Judgement.great]
        let crownLine = ResultsView.chaseLine(for: shiftResult(level, threeStar, stars: 3), hasCrown: false)
        #expect(crownLine == "Flawless crown: every glass Perfect. You had \(total - 1) of \(total).")
        #expect(ResultsView.chaseLine(for: shiftResult(level, threeStar, stars: 3), hasCrown: true) == nil)
        #expect(ResultsView.chaseLine(for: shiftResult(level, [.spill, .spill, .spill], stars: 0, cleared: false),
                                      hasCrown: false) == nil)
        let rush = RunResult(mode: .rush, score: 10, stars: 0, perfects: 0, bestStreak: 0, judgements: [.good],
                             poured: 0, cleared: true)
        #expect(ResultsView.chaseLine(for: rush, hasCrown: false) == nil)
    }

    // Decision 5: the Daily card leads with the streak and a 7-day strip.
    @Test func dailyCeremonyStreakAndWeek() {
        var data = ProgressData()
        for day in [10, 12, 13] { data.daily[day] = DailyRecord(score: 100 * day, judgements: [.good], perfects: 0) }
        #expect(data.dailyWeek(today: 13) == [false, false, false, true, false, true, true])
        #expect(data.dailyWeek(today: 14) == [false, false, true, false, true, true, false])
        #expect(ResultsView.dailyLead(streak: 4) == "🔥 4 days in a row")
        #expect(ResultsView.dailyLead(streak: 1) == "🔥 Day 1 of your streak")
        #expect(ResultsView.dailyStats(best: 1240, perfects: 3) == "best 1,240 · 3 Perfect")
        #expect(!ResultsView.dailyStats(best: 0, perfects: 0).contains("0"))
        // Day 0 is Thursday 1 January 2026; day 4 a Monday.
        #expect(ResultsView.weekdayLetter(day: 0) == "T")
        #expect(ResultsView.weekdayLetter(day: 1) == "F")
        #expect(ResultsView.weekdayLetter(day: 4) == "M")
        #expect(ResultsView.weekdayLetter(day: -3) == "M")
    }

    // Decision 2: the tier banner copy, and the shift banner.
    @Test func bannerCopy() throws {
        #expect(GameController.tierBanner(tier: 1, venue: .lemonadeStand) == nil)
        #expect(GameController.tierBanner(tier: 0, venue: nil) == nil)
        #expect(GameController.tierBanner(tier: 3, venue: .conveyor) == "TIER 3 · BELTS!")
        #expect(GameController.tierBanner(tier: 2, venue: nil) == "TIER 2 · FIZZ!")
        #expect(GameController.tierBanner(tier: 4, venue: .milkshakeDiner) == "TIER 4 · THICK AND FAST!")
        #expect(GameController.tierBanner(tier: 5, venue: .potionShop) == "TIER 5 · POTIONS!")
        #expect(GameController.tierBanner(tier: 7, venue: .sodaFountain) == "TIER 7 · FASTER!")
        let level = try #require(LevelCatalog.levels(in: .conveyor).first)
        #expect(GameController.shiftBanner(for: .shift(level.id)) == "Shift \(level.index) · \(level.title)")
        #expect(GameController.shiftBanner(for: .rush) == nil)
        #expect(GameController.shiftBanner(for: .daily(3)) == nil)
        // Visible during its time, held by the start gate (not after a pause), never on a finished run.
        #expect(GameController.bannerVisible(time: 0.5, until: 1.6, holdsOnGate: true, needsFlat: false,
                                             gateAfterPause: false, ordersDone: 0, finished: false))
        #expect(!GameController.bannerVisible(time: 2, until: 1.6, holdsOnGate: true, needsFlat: false,
                                              gateAfterPause: false, ordersDone: 0, finished: false))
        #expect(GameController.bannerVisible(time: 9, until: 1.6, holdsOnGate: true, needsFlat: true,
                                             gateAfterPause: false, ordersDone: 0, finished: false))
        #expect(!GameController.bannerVisible(time: 9, until: 1.6, holdsOnGate: true, needsFlat: true,
                                              gateAfterPause: true, ordersDone: 0, finished: false))
        #expect(!GameController.bannerVisible(time: 9, until: 1.6, holdsOnGate: false, needsFlat: true,
                                              gateAfterPause: false, ordersDone: 0, finished: false))
        #expect(!GameController.bannerVisible(time: 0.5, until: 1.6, holdsOnGate: true, needsFlat: false,
                                              gateAfterPause: false, ordersDone: 0, finished: true))
    }

    // The banner lane and the intro card stay off the fold on a Duo and on screen on a phone.
    @Test func bannerAndIntroCardStayOffTheFold() {
        let duo = CanvasInfo(size: CGSize(width: 669, height: 951),
                             insets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0), hasFold: true)
        let lane = PlayBannerView.lane(info: duo)
        #expect(lane.maxY < duo.topHalfHeight)
        #expect(lane.minY >= duo.hudTop + HUDMetrics.rowHeight)
        let spot = VenueIntroCard.spot(anchors: nil, info: duo)
        let card = CGRect(x: spot.center.x - spot.width / 2, y: spot.center.y - VenueIntroCard.estimatedHeight / 2,
                          width: spot.width, height: VenueIntroCard.estimatedHeight)
        #expect(card.maxY <= duo.topHalfHeight + 0.5)
        #expect(card.minY >= lane.maxY - 0.5)
        #expect(card.minX >= 0 && card.maxX <= duo.size.width)

        let phone = CanvasInfo(size: CGSize(width: 402, height: 874),
                               insets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), hasFold: false)
        let phoneLane = PlayBannerView.lane(info: phone)
        #expect(phoneLane.minY >= phone.hudTop + HUDMetrics.rowHeight)
        let p = VenueIntroCard.spot(anchors: nil, info: phone)
        let phoneHeight = VenueIntroCard.height(for: phone)
        #expect(p.width <= phone.size.width - 2 * phone.sidePad + 0.5)
        #expect(p.center.y - phoneHeight / 2 >= phoneLane.maxY - 0.5)
        #expect(p.center.y + phoneHeight / 2 <= phone.size.height)
    }

    // Decision 1: venue intro cards are hints (stored by raw value), one per venue with a new idea.
    @Test func venueIntroKinds() {
        #expect(HintKind.venueIntro(for: .lemonadeStand) == nil)
        #expect(HintKind.venueIntro(for: nil) == nil)
        let venues: [VenueID] = [.sodaFountain, .milkshakeDiner, .conveyor, .potionShop, .sandBar]
        let kinds = venues.compactMap { HintKind.venueIntro(for: $0) }
        #expect(kinds.count == venues.count)
        #expect(Set(kinds.map { $0.rawValue }) == Set(["foam", "thick", "belt", "fade", "sand"]))
        for (venue, kind) in zip(venues, kinds) {
            #expect(kind.isVenueIntro)
            #expect(kind.introVenue == venue)
            #expect(!VenueIntroCard.line(for: kind).isEmpty)
        }
        #expect(!HintKind.lift.isVenueIntro)
        #expect(VenueIntroCard.line(for: .belt).contains("before"))
    }

    @Test func theFirstConveyorShiftShowsItsCardOnce() {
        let store = ProgressStore(inMemory: ProgressData())
        let c = makeController("mode=shift:4-1;hints=fresh", canvas: CGSize(width: 402, height: 874), fold: false,
                               store: store)
        c.start(mode: .shift("4-1"))
        #expect(c.activeHint == HintKind.belt)
        // Round 8 (REVIEW-6 N4): on a phone the shift banner waits for the card, then follows it.
        #expect(c.hud.banner == nil)
        c.dismissHint()
        #expect(store.hasSeenHint("belt"))
        #expect(c.activeHint != HintKind.belt)
        #expect(c.hud.banner?.kind == PlayBanner.Kind.shift)
        c.restart()
        #expect(c.activeHint != HintKind.belt)
        // The Lemonade Stand has no card: the first run's lift hint instead.
        c.start(mode: .shift("1-1"))
        #expect(c.activeHint == HintKind.lift)
        // Rush and the Daily have no shift banner.
        c.start(mode: .rush)
        #expect(c.hud.banner == nil)
    }

    // The HUD score turns light on dark venues (REVIEW-5 §3 P2).
    @Test func hudKnowsWhenTheBackdropIsDark() throws {
        #expect(GameController.isDarkLook(venue: .potionShop, rush: false))
        #expect(!GameController.isDarkLook(venue: .lemonadeStand, rush: false))
        #expect(GameController.isDarkLook(venue: .lemonadeStand, rush: true))
        #expect(GameController.lookVenue(snapshot: .conveyor, mode: .rush) == .conveyor)
        #expect(GameController.lookVenue(snapshot: nil, mode: .rush) == .lemonadeStand)
        let potion = try #require(LevelCatalog.levels(in: .potionShop).first)
        let c = makeController("mode=shift:\(potion.id)", canvas: CGSize(width: 402, height: 874), fold: false)
        c.start(mode: .shift(potion.id))
        #expect(c.hud.darkBackdrop)
        c.start(mode: .shift("1-1"))
        #expect(!c.hud.darkBackdrop)
        #expect(HUDView.scoreColors(dark: true).text == BrimTheme.cream)
        #expect(HUDView.scoreColors(dark: false).text == BrimTheme.ink)
    }

    @Test func demoParsesTheRound6FreezeKeys() {
        #expect(DemoConfig.parse("mode=shift:4-1;freezeOn=intro", today: 1).freezeOn == DemoConfig.Freeze.intro)
        #expect(DemoConfig.parse("mode=rush;freezeOn=tier", today: 1).freezeOn == DemoConfig.Freeze.tier)
    }
}

// MARK: - Round 7: QA-3 fixes (ROUND-7 App row)

@MainActor
struct Round7AppTests {
    private let phone = CGSize(width: 402, height: 874)

    private func makeController(_ args: String, canvas: CGSize = CGSize(width: 669, height: 951), fold: Bool = true,
                                store: ProgressStore? = nil) -> GameController {
        let c = GameController(store: store ?? ProgressStore(inMemory: ProgressData()),
                               settings: SettingsStore(defaults: nil),
                               demo: DemoConfig.parse(args, today: 33))
        c.updateCanvas(canvas, hasFold: fold)
        return c
    }

    /// Steps the controller `seconds` at 60 Hz from frame clock `start`; returns the last snapshot and the clock.
    private func run(_ c: GameController, seconds: Double, from start: TimeInterval) -> (GameSnapshot?, TimeInterval) {
        var now = start
        var last: GameSnapshot?
        let frames = Int(seconds * 60)
        for _ in 0..<frames {
            now += 1.0 / 60.0
            if let step = c.advance(dt: 1.0 / 60.0, now: now) { last = step.0 }
        }
        return (last, now)
    }

    // P1-3: the conveyor card says "Pour to start", so the belt waits under it (GameSession.setStartHold), and a tap
    // on the card lets it ride.
    @Test func theBeltWaitsUnderTheIntroCard() throws {
        let level = try #require(LevelCatalog.level("4-1"))
        try #require(level.venue == .conveyor)
        let c = makeController("mode=shift:4-1;hints=fresh", canvas: phone, fold: false)
        c.start(mode: .shift("4-1"))
        #expect(c.activeHint == HintKind.belt)
        // Well past glass 1's window on a running belt (about 5 s after the intro), with nothing poured.
        let first = run(c, seconds: 8, from: CACurrentMediaTime())
        let heldSnap = try #require(first.0)
        let heldGlass = try #require(GameController.activeGlass(heldSnap))
        let second = run(c, seconds: 4, from: first.1)
        let laterSnap = try #require(second.0)
        let laterGlass = try #require(GameController.activeGlass(laterSnap))
        #expect(laterSnap.ordersDone == 0)
        #expect(laterGlass.id == heldGlass.id)
        #expect(abs(laterGlass.x - heldGlass.x) < 0.5)
        #expect(laterGlass.result == nil)
        #expect(c.activeHint == HintKind.belt)
        c.dismissHint()
        #expect(c.activeHint == nil)
        let third = run(c, seconds: 2, from: second.1)
        let movingSnap = try #require(third.0)
        let moved = try #require(movingSnap.glasses.first(where: { $0.id == heldGlass.id }))
        #expect(moved.x > heldGlass.x + 5)
    }

    // P2-10: on a Duo the intro card waits while the flat gate is closed, even before the gate's own card shows.
    @Test func theIntroCardWaitsForTheFlatGate() {
        #expect(!VenueIntroCard.isVisible(hint: .belt, gateClosed: true, showFlatGate: false))
        #expect(!VenueIntroCard.isVisible(hint: .belt, gateClosed: false, showFlatGate: true))
        #expect(VenueIntroCard.isVisible(hint: .belt, gateClosed: false, showFlatGate: false))
        #expect(!VenueIntroCard.isVisible(hint: .lift, gateClosed: false, showFlatGate: false))
        #expect(!VenueIntroCard.isVisible(hint: nil, gateClosed: false, showFlatGate: false))
        let c = makeController("mode=shift:4-1;hints=fresh;duo")
        c.start(mode: .shift("4-1"))
        #expect(c.activeHint == HintKind.belt)
        let t0 = CACurrentMediaTime()
        c.hingeSample(angle: 140, time: t0)
        // Inside the gate card's 0.35 s delay: closed, no gate card yet, and no intro card either.
        let early = run(c, seconds: 0.15, from: t0)
        #expect(early.0?.needsFlat == true)
        #expect(c.hud.gateClosed)
        #expect(!c.hud.showFlatGate)
        let earlyVisible = VenueIntroCard.isVisible(hint: c.activeHint, gateClosed: c.hud.gateClosed,
                                                    showFlatGate: c.hud.showFlatGate)
        #expect(!earlyVisible)
        // Laid flat: the gate opens and the card shows (nothing poured, so it is still up).
        var now = early.1
        var flatSnap: GameSnapshot?
        for _ in 0..<90 {
            now += 1.0 / 60.0
            c.hingeSample(angle: 180, time: now)
            if let step = c.advance(dt: 1.0 / 60.0, now: now) { flatSnap = step.0 }
        }
        #expect(flatSnap?.needsFlat == false)
        #expect(!c.hud.gateClosed)
        #expect(c.activeHint == HintKind.belt)
        let flatVisible = VenueIntroCard.isVisible(hint: c.activeHint, gateClosed: c.hud.gateClosed,
                                                   showFlatGate: c.hud.showFlatGate)
        #expect(flatVisible)
    }

    // P2-12: a TestFlight 1.0 (2) player with stars in a venue isn't taught it again.
    @Test func veteransWithStarsInAVenueSkipItsIntroCard() throws {
        #expect(GameController.showsVenueIntro(starsInVenue: 0))
        #expect(!GameController.showsVenueIntro(starsInVenue: 1))
        let belt = try #require(LevelCatalog.levels(in: .conveyor).first)
        var data = ProgressData()
        data.stars[belt.id] = 2
        let store = ProgressStore(inMemory: data)
        let c = makeController("mode=shift:\(belt.id);hints=fresh", canvas: phone, fold: false, store: store)
        c.start(mode: .shift(belt.id))
        #expect(c.activeHint != HintKind.belt)
        #expect(store.hasSeenHint("belt"))
        // The banner still announces the shift.
        #expect(c.hud.banner?.kind == PlayBanner.Kind.shift)
    }

    // P2-1: Rush has no shift list, so the App tells the scene what rides the belt (conveyor tiers only).
    @Test func rushTellsTheSceneWhatRidesTheBelt() throws {
        let every = CoreTuning.rushTierEvery
        let order = try #require(LevelCatalog.levels(in: .conveyor).first?.orders.first)
        #expect(GameController.rushBeltQueue(next: order, nextIndex: 2 * every, slotGlassWaiting: false) == [order])
        #expect(GameController.rushBeltQueue(next: order, nextIndex: 3 * every - 1, slotGlassWaiting: false) == [order])
        #expect(GameController.rushBeltQueue(next: order, nextIndex: 3 * every, slotGlassWaiting: false).isEmpty)
        #expect(GameController.rushBeltQueue(next: order, nextIndex: every, slotGlassWaiting: false).isEmpty)
        #expect(GameController.rushBeltQueue(next: order, nextIndex: 2 * every, slotGlassWaiting: true).isEmpty)
        #expect(GameController.rushBeltQueue(next: nil, nextIndex: 2 * every, slotGlassWaiting: false).isEmpty)
        let c = makeController("mode=rush", canvas: phone, fold: false)
        c.start(mode: .rush)
        #expect(c.scene != nil)
        #expect(c.scene?.upcomingOrders?.isEmpty == true)
        // The scene is reused: a shift afterwards goes back to its own list.
        c.start(mode: .shift("4-1"))
        #expect(c.scene != nil)
        #expect(c.scene?.upcomingOrders == nil)
    }

    // P1-1 (frame 26): `freezeOn=tier` waits for the old glass to leave, within the banner's time.
    @Test func theTierFrameWaitsForTheOldGlassToLeave() {
        #expect(!GameController.tierFreezeReady(sinceChange: 0.2, oldGlassLeaving: false))
        #expect(!GameController.tierFreezeReady(sinceChange: 0.4, oldGlassLeaving: true))
        #expect(GameController.tierFreezeReady(sinceChange: 0.5, oldGlassLeaving: false))
        #expect(GameController.tierFreezeReady(sinceChange: GameController.tierFreezeLatest, oldGlassLeaving: true))
        #expect(GameController.tierFreezeLatest < GameController.tierBannerSeconds)
    }
}

// MARK: - Round 8: REVIEW-6 #2–#6 (ROUND-8 App row)

@MainActor
struct Round8AppTests {
    private let phone = CGSize(width: 402, height: 874)

    private func makeController(_ args: String, canvas: CGSize = CGSize(width: 669, height: 951), fold: Bool = true,
                                store: ProgressStore? = nil) -> GameController {
        let c = GameController(store: store ?? ProgressStore(inMemory: ProgressData()),
                               settings: SettingsStore(defaults: nil),
                               demo: DemoConfig.parse(args, today: 33))
        c.updateCanvas(canvas, hasFold: fold)
        return c
    }

    private func shift(_ id: String, _ judgements: [Judgement], stars: Int, cleared: Bool = true,
                       bestStreak: Int = 0, score: Int = 1000) -> RunResult {
        RunResult(mode: .shift(id), score: score, stars: stars,
                  perfects: judgements.filter { $0 == .perfect }.count, bestStreak: bestStreak,
                  judgements: judgements, poured: 0, cleared: cleared)
    }

    /// A save with Flawless crowns on the first `count` campaign shifts.
    private func crowned(_ count: Int) -> ProgressData {
        var data = ProgressData()
        for level in LevelCatalog.levels.prefix(count) { data.crowns.insert(level.id) }
        return data
    }

    // #2 (N2): the best Perfects of each shift are kept (any run of it), capped at its glasses.
    @Test func bestPerfectsPerShiftAreKeptAndCapped() throws {
        let level = try #require(LevelCatalog.levels(in: .lemonadeStand).first)
        let total = level.orders.count
        try #require(total >= 4)
        var data = ProgressData()
        var two = Array(repeating: Judgement.great, count: total)
        two[0] = .perfect
        two[1] = .perfect
        let first = data.record(shift(level.id, two, stars: 3), today: 1)
        #expect(first.previousBestPerfects == 0)
        #expect(first.bestPerfects == 2)
        #expect(data.bestPerfects(for: level.id) == 2)
        let worse = data.record(shift(level.id, Array(repeating: .great, count: total), stars: 3), today: 1)
        #expect(worse.previousBestPerfects == 2)
        #expect(worse.bestPerfects == 2)
        // A struck-out run's Perfects count too.
        let failedRun = shift(level.id, [.perfect, .perfect, .perfect, .spill, .spill, .spill], stars: 0, cleared: false)
        let failed = data.record(failedRun, today: 1)
        #expect(failed.bestPerfects == min(3, total))
        // Never more than the shift's glasses.
        let overfull = data.record(shift(level.id, Array(repeating: .perfect, count: total + 4), stars: 3), today: 1)
        #expect(overfull.bestPerfects == total)
        #expect((data.bestPerfects[level.id] ?? 0) <= total)
        // Rush doesn't touch it.
        let rush = RunResult(mode: .rush, score: 10, stars: 0, perfects: 5, bestStreak: 5,
                             judgements: Array(repeating: .perfect, count: 5), poured: 0, cleared: true)
        _ = data.record(rush, today: 1)
        #expect(data.bestPerfects.count == 1)
    }

    // A round-6/7 save has crowns but no best Perfects: a crowned shift counts every glass.
    @Test func aCrownCountsAsEveryGlassPerfect() throws {
        let level = try #require(LevelCatalog.levels(in: .lemonadeStand).first)
        var data = ProgressData()
        data.crowns = [level.id]
        #expect(data.bestPerfects(for: level.id) == level.orders.count)
        let sums = data.perfectsEarned(in: .lemonadeStand)
        #expect(sums.best == level.orders.count)
        #expect(sums.glasses == LevelCatalog.levels(in: .lemonadeStand).reduce(0) { $0 + $1.orders.count })
        let mid = DemoConfig.progressData(.mid)
        #expect(mid.perfectsEarned(in: .lemonadeStand).best > 0)
    }

    // Tolerant decode: older saves have neither field; a bad value costs only itself.
    @Test func bestPerfectsAndVesselDecodeTolerantly() throws {
        let old = try JSONDecoder().decode(ProgressData.self,
                                           from: Data(#"{"stars": {"1-1": 3}, "crowns": ["1-1"]}"#.utf8))
        #expect(old.bestPerfects.isEmpty)
        #expect(old.vessel == nil)
        #expect(old.hasCrown("1-1"))
        let bad = try JSONDecoder().decode(ProgressData.self, from: Data(
            #"{"stars": {"1-1": 2}, "bestPerfects": "lots", "vessel": "teapot"}"#.utf8))
        #expect(bad.bestPerfects.isEmpty)
        #expect(bad.vessel == nil)
        #expect(bad.stars(for: "1-1") == 2)
        let wrongType = try JSONDecoder().decode(ProgressData.self, from: Data(#"{"vessel": 7}"#.utf8))
        #expect(wrongType.vessel == nil)
        var data = ProgressData()
        data.bestPerfects = ["1-1": 4, "2-3": 2]
        data.vessel = .potionShop
        let encoded = try JSONEncoder().encode(data)
        let back = try JSONDecoder().decode(ProgressData.self, from: encoded)
        #expect(back == data)
        #expect(back.vessel == VenueID.potionShop)
    }

    @Test func bestPerfectsAndVesselPersistThroughTheStore() throws {
        let suite = "brim.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProgressStore(defaults: defaults)
        let three = Array(LevelCatalog.levels(in: .lemonadeStand).prefix(3))
        try #require(three.count == 3)
        for level in three {
            store.record(shift(level.id, Array(repeating: .perfect, count: level.orders.count), stars: 3), today: 2)
        }
        #expect(store.data.totalCrowns == 3)
        store.setVessel(.sandBar)                 // 14 crowns: refused
        #expect(store.data.vessel == nil)
        store.setVessel(.sodaFountain)
        #expect(store.data.vessel == VenueID.sodaFountain)
        let reloaded = ProgressStore(defaults: defaults)
        #expect(reloaded.data.vessel == VenueID.sodaFountain)
        #expect(reloaded.data.activeVessel == VenueID.sodaFountain)
        #expect(reloaded.bestPerfects(for: three[0].id) == three[0].orders.count)
        reloaded.resetProgress()
        #expect(reloaded.data.vessel == nil)
        #expect(reloaded.data.bestPerfects.isEmpty)
    }

    // #6: the Glass Cabinet's vessels open with crowns.
    @Test func cabinetUnlocksVesselsByCrowns() {
        #expect(GlassCabinet.crownsNeeded(nil) == 0)
        #expect(GlassCabinet.crownsNeeded(.sodaFountain) == 3)
        #expect(GlassCabinet.crownsNeeded(.milkshakeDiner) == 6)
        #expect(GlassCabinet.crownsNeeded(.potionShop) == 10)
        #expect(GlassCabinet.crownsNeeded(.sandBar) == 14)
        #expect(GlassCabinet.crownsNeeded(.conveyor) == nil)
        #expect(GlassCabinet.isUnlocked(nil, crowns: 0))
        #expect(!GlassCabinet.isUnlocked(.sodaFountain, crowns: 2))
        #expect(GlassCabinet.isUnlocked(.sodaFountain, crowns: 3))
        #expect(!GlassCabinet.isUnlocked(.conveyor, crowns: 99))
        #expect(GlassCabinet.nextUnlock(crowns: 4)?.vessel.venue == VenueID.milkshakeDiner)
        #expect(GlassCabinet.nextUnlock(crowns: 4)?.missing == 2)
        #expect(GlassCabinet.nextUnlock(crowns: 14) == nil)
        #expect(GlassCabinet.nextLine(crowns: 0) == "3 more 👑 for the Soda dispenser")
        #expect(GlassCabinet.nextLine(crowns: 20) == nil)
        let soda = GlassCabinet.vessels[1]
        #expect(CabinetSheet.caption(for: soda, crowns: 1, chosen: nil) == "3 👑")
        #expect(CabinetSheet.caption(for: soda, crowns: 3, chosen: nil) == "Tap to use")
        #expect(CabinetSheet.caption(for: soda, crowns: 3, chosen: .sodaFountain) == "In use")
        // The pick falls back to the house jug while the crowns don't hold it; unknown level ids don't count.
        var data = ProgressData()
        data.vessel = .potionShop
        #expect(data.activeVessel == nil)
        data = crowned(10)
        data.vessel = .potionShop
        data.crowns.insert("9-99")
        #expect(data.totalCrowns == 10)
        #expect(data.activeVessel == VenueID.potionShop)
    }

    // The cabinet sits off the fold: in the flat half on a Duo.
    @Test func cabinetSheetStaysOffTheFold() {
        let duo = CanvasInfo(size: CGSize(width: 669, height: 951),
                             insets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0), hasFold: true)
        #expect(CabinetSheet.margins(info: duo).top > duo.bottomHalfTop)
        let phoneInfo = CanvasInfo(size: phone, insets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0),
                                   hasFold: false)
        #expect(CabinetSheet.margins(info: phoneInfo).bottom >= 34)
    }

    // #6: the scene draws the cabinet's vessel in Rush and Practice, never in a shift or the Daily.
    @Test func theVesselDrawsInRushAndPracticeOnly() {
        #expect(GameController.vesselOverride(for: .rush, chosen: .potionShop) == VenueID.potionShop)
        #expect(GameController.vesselOverride(for: .practice, chosen: .sandBar) == VenueID.sandBar)
        #expect(GameController.vesselOverride(for: .shift("1-1"), chosen: .potionShop) == nil)
        #expect(GameController.vesselOverride(for: .daily(3), chosen: .potionShop) == nil)
        #expect(GameController.vesselOverride(for: .rush, chosen: nil) == nil)
        var data = crowned(3)
        data.vessel = .sodaFountain
        let store = ProgressStore(inMemory: data)
        let c = makeController("mode=rush", canvas: phone, fold: false, store: store)
        c.start(mode: .rush)
        #expect(c.scene != nil)
        #expect(c.scene?.vesselOverride == VenueID.sodaFountain)
        c.start(mode: .shift("1-1"))
        #expect(c.scene != nil)
        #expect(c.scene?.vesselOverride == nil)
        c.start(mode: .rush)
        c.chooseVessel(nil)
        #expect(c.scene?.vesselOverride == nil)
        #expect(store.data.vessel == nil)
    }

    // #2 (N2) and #4 (N3): the line under the score.
    @Test func statsLineIsTheCrownChaseAndNeverAZero() throws {
        let level = try #require(LevelCatalog.levels(in: .lemonadeStand).first)
        let total = level.orders.count
        try #require(total >= 3)
        let allGreat = shift(level.id, Array(repeating: .great, count: total), stars: 3)
        let chase = ResultsView.statsLine(for: allGreat, hasCrown: false, bestPerfects: 0)
        #expect(chase == "Flawless crown: every glass Perfect. You had 0 of \(total).")
        #expect(!(chase ?? "").contains("streak"))
        let withBest = ResultsView.statsLine(for: allGreat, hasCrown: false, bestPerfects: 2)
        #expect(withBest == "Flawless crown: every glass Perfect. You had 0 of \(total). Best 2.")
        var oneShort = Array(repeating: Judgement.perfect, count: total)
        oneShort[0] = .short
        let underThree = ResultsView.statsLine(for: shift(level.id, oneShort, stars: 2, bestStreak: total - 1),
                                               hasCrown: false, bestPerfects: total)
        #expect(underThree == "3★ needs every glass a hit. You had 1 miss.")
        let flawless = shift(level.id, Array(repeating: .perfect, count: total), stars: 3, bestStreak: total)
        #expect(ResultsView.statsLine(for: flawless, hasCrown: true, bestPerfects: total)
                == "\(total) of \(total) Perfect · best streak \(total)")
        // Struck out: no glass count (the hero has it) and no zeros.
        let noPerfects = shift(level.id, [.great, .spill, .spill, .spill], stars: 0, cleared: false)
        #expect(ResultsView.statsLine(for: noPerfects, hasCrown: false, bestPerfects: 0) == nil)
        let twoPerfects = shift(level.id, [.perfect, .perfect, .spill, .spill, .spill], stars: 0, cleared: false,
                                bestStreak: 2)
        #expect(ResultsView.statsLine(for: twoPerfects, hasCrown: false, bestPerfects: 2) == "2 Perfect · best streak 2")
        // Rush: glasses first, no "0 perfect", a streak only from 2.
        let rushPlain = RunResult(mode: .rush, score: 900, stars: 0, perfects: 0, bestStreak: 1,
                                  judgements: Array(repeating: .great, count: 5), poured: 0, cleared: true)
        #expect(ResultsView.statsLine(for: rushPlain, hasCrown: false, bestPerfects: 0) == "5 glasses")
        let rushGood = RunResult(mode: .rush, score: 900, stars: 0, perfects: 3, bestStreak: 3,
                                 judgements: [.perfect, .perfect, .perfect, .great, .spill], poured: 0, cleared: true)
        #expect(ResultsView.statsLine(for: rushGood, hasCrown: false, bestPerfects: 0)
                == "5 glasses · 3 Perfect · best streak 3")
    }

    // #4 (N3): ghost outlines for the unserved glasses, and no orphan "0".
    @Test func aStruckOutShiftShowsItsUnservedGlassesAndNoOrphanZero() throws {
        let level = try #require(LevelCatalog.level("2-4"))
        try #require(level.orders.count > 4)
        let failed = shift(level.id, [.good, .spill, .spill, .spill], stars: 0, cleared: false, score: 0)
        let ghosts = ResultsView.ghostRecap(for: failed)
        #expect(ghosts.count == level.orders.count - 4)
        #expect(ghosts.allSatisfy { $0.ghost && $0.level == 0 })
        #expect(ghosts.first?.line == level.orders[4].line)
        #expect(ghosts.first?.shape.id == level.orders[4].glass)
        #expect(ResultsView.ghostRecap(for: shift(level.id, [.good], stars: 1)).isEmpty)
        let rush = RunResult(mode: .rush, score: 1, stars: 0, perfects: 0, bestStreak: 0, judgements: [.spill],
                             poured: 0, cleared: false)
        #expect(ResultsView.ghostRecap(for: rush).isEmpty)
        #expect(ResultsView.scoreText(0, hasHero: true) == nil)
        #expect(ResultsView.scoreText(1240, hasHero: true) == "1,240 pts")
        #expect(ResultsView.scoreText(0, hasHero: false) == "0")
        #expect(RecapGlyph.accessibilityText(ghosts).contains("\(ghosts.count) not served"))
    }

    // #2 (N2): Venues show the best Perfects and a cyan arc on 3★ shifts without a crown.
    @Test func venuesShowBestPerfectsAndTheCrownArc() {
        #expect(VenuesView.perfectLine(best: 0, glasses: 52) == nil)
        #expect(VenuesView.perfectLine(best: 41, glasses: 52) == "41/52")
        #expect(VenuesView.perfectLine(best: 60, glasses: 52) == "52/52")
        #expect(VenuesView.crownArc(stars: 3, crowned: false, bestPerfects: 3, glasses: 6) == 0.5)
        #expect(VenuesView.crownArc(stars: 2, crowned: false, bestPerfects: 3, glasses: 6) == 0)
        #expect(VenuesView.crownArc(stars: 3, crowned: true, bestPerfects: 6, glasses: 6) == 0)
        #expect(VenuesView.crownArc(stars: 3, crowned: false, bestPerfects: 0, glasses: 6) == 0)
    }

    // #5 (N4): the phone card is compact and sits low, between the counter's back edge and the glass rim.
    @Test func thePhoneIntroCardSitsLowAndLeavesTheJugInView() {
        let phoneInfo = CanvasInfo(size: phone, insets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0),
                                   hasFold: false)
        let h = VenueIntroCard.height(for: phoneInfo)
        #expect(h < VenueIntroCard.estimatedHeight)
        let glass = GlassAnchor(id: 1, x: 335, lineY: 200, halfWidthAtLine: 40, rimY: 264, baseY: 104, filling: false)
        let jug = CGRect(x: 250, y: 520, width: 200, height: 250)
        let spot = VenueIntroCard.spot(anchors: PlayAnchors(jug: jug, glass: glass, waiting: nil), info: phoneInfo)
        let card = CGRect(x: spot.center.x - spot.width / 2, y: spot.center.y - h / 2, width: spot.width, height: h)
        #expect(card.minY >= phoneInfo.bottomHalfTop - 0.5)
        #expect(!card.intersects(phoneInfo.mapper.rect(jug)))
        #expect(card.maxY <= phoneInfo.mapper.y(glass.rimY) + 0.5)
        #expect(spot.width <= VenueIntroCard.compactMaxWidth)
        let duo = CanvasInfo(size: CGSize(width: 669, height: 951), insets: EdgeInsets(), hasFold: true)
        #expect(VenueIntroCard.height(for: duo) == VenueIntroCard.estimatedHeight)
    }

    // #5 (N4): the banner waits for the card on a phone only, and never leaks into the next run.
    @Test func theShiftBannerWaitsForTheCardOnAPhoneOnly() {
        #expect(GameController.defersShiftBanner(hasFold: false, introCardUp: true))
        #expect(!GameController.defersShiftBanner(hasFold: true, introCardUp: true))
        #expect(!GameController.defersShiftBanner(hasFold: false, introCardUp: false))
        let duo = makeController("mode=shift:4-1;hints=fresh")
        duo.start(mode: .shift("4-1"))
        #expect(duo.activeHint == HintKind.belt)
        #expect(duo.hud.banner?.kind == PlayBanner.Kind.shift)
        let p = makeController("mode=shift:4-1;hints=fresh", canvas: phone, fold: false)
        p.start(mode: .shift("4-1"))
        #expect(p.activeHint == HintKind.belt)
        #expect(p.hud.banner == nil)
        p.start(mode: .rush)
        #expect(p.hud.banner == nil)
    }

    // #3: the evidence keys.
    @Test func demoParsesTheRound8Keys() {
        let c = DemoConfig.parse("mode=rush;autopilot=great;served=25;missAt=3;freezeOn=lowjug", today: 1)
        #expect(c.served == Int(25))
        #expect(c.missAt == Int(3))
        #expect(c.freezeOn == DemoConfig.Freeze.lowjug)
        #expect(DemoConfig.parse("freezeOn=repose", today: 1).freezeOn == DemoConfig.Freeze.repose)
        #expect(DemoConfig.parse("freezeOn=faded", today: 1).freezeOn == DemoConfig.Freeze.faded)
        let bad = DemoConfig.parse("served=x;missAt=", today: 1)
        #expect(bad.served == nil)
        #expect(bad.missAt == nil)
    }

    @Test func theNewFreezesWaitForTheirMoment() {
        #expect(!GameController.reposeFreezeReady(progress: 0.5, servedSoFar: 0))
        #expect(GameController.reposeFreezeReady(progress: 0.9, servedSoFar: 0))
        #expect(!GameController.reposeFreezeReady(progress: 1.0, servedSoFar: 0))
        #expect(GameController.reposeFreezeReady(progress: 1.0, servedSoFar: GameController.reposeFreezeGiveUp))
        #expect(!GameController.reposeFreezeReady(progress: .nan, servedSoFar: 9))
        #expect(!GameController.fadedFreezeReady(sinceFade: 0.2, pouring: true, fillOfLine: 0.9))
        #expect(GameController.fadedFreezeReady(sinceFade: 0.5, pouring: true, fillOfLine: 0.7))
        #expect(!GameController.fadedFreezeReady(sinceFade: 0.5, pouring: false, fillOfLine: 0.7))
        #expect(GameController.fadedFreezeReady(sinceFade: 1.0, pouring: false, fillOfLine: 0))
        #expect(GameController.lowJugFreezeBelow > 0 && GameController.lowJugFreezeBelow < 0.5)
        #expect(DemoMissPilot.pouringMissGlass(ordersDone: 2, missAt: 3))
        #expect(!DemoMissPilot.pouringMissGlass(ordersDone: 3, missAt: 3))
        #expect(!DemoMissPilot.pouringMissGlass(ordersDone: 0, missAt: 0))
    }

    // Frame 08: a real all-Great run whose 4th glass is poured over is a one-miss card, not 3★.
    @Test func theMissPilotMakesAnHonestOneMissRun() throws {
        let played = DemoRunner.playRun(mode: .shift("1-1"), style: .great, seed: 7, missAt: 4)
        let result = played.0
        try #require(result.judgements.count >= 4)
        #expect(!result.judgements[3].isHit)
        #expect(result.stars <= 2)
    }

    // `served=N` leaves a live run behind it.
    @Test func theServedSeedLeavesTheRunLive() {
        let session = GameSession(mode: .rush, layout: DemoRunner.headlessLayout, seed: 7)
        let progress = DemoRunner.playUpToServed(session, served: 3, style: .perfect)
        #expect(progress.served >= 1)
        #expect(!session.isFinished)
        #expect(session.snapshot.ordersDone == 3 || session.snapshot.jug.fill < DemoRunner.rushJugFloor)
    }

    // ROUND-8 Core row: Rush's belt queue takes up to two peeked orders, belt tiers only.
    @Test func rushBeltQueueTakesUpToTwoBeltOrders() throws {
        let every = CoreTuning.rushTierEvery
        let orders = try #require(LevelCatalog.levels(in: .conveyor).first?.orders)
        try #require(orders.count >= 3)
        let a = orders[0], b = orders[1], c = orders[2]
        #expect(GameController.rushBeltQueue(next: [a, b], nextIndex: 2 * every, slotGlassWaiting: false) == [a, b])
        #expect(GameController.rushBeltQueue(next: [a, b, c], nextIndex: 2 * every, slotGlassWaiting: false) == [a, b])
        #expect(GameController.rushBeltQueue(next: [a, b], nextIndex: 3 * every - 1, slotGlassWaiting: false) == [a])
        #expect(GameController.rushBeltQueue(next: [a, b], nextIndex: 2 * every - 1, slotGlassWaiting: false).isEmpty)
        #expect(GameController.rushBeltQueue(next: [a, b], nextIndex: 2 * every, slotGlassWaiting: true).isEmpty)
        #expect(GameController.rushBeltQueue(next: [GlassOrder](), nextIndex: 2 * every, slotGlassWaiting: false).isEmpty)
    }
}
