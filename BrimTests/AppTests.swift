import Foundation
import Testing
@testable import Brim

// App engineer tests: ProgressStore round-trip and unlocks, DemoMode parsing, share-text formatting.

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
