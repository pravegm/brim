import Combine
import Foundation

// MARK: - Stored data (pure value types, unit-tested in BrimTests/AppTests.swift)

/// One scored Daily Pour.
struct DailyRecord: Codable, Equatable {
    var score: Int
    var judgements: [Judgement]
    var perfects: Int

    init(score: Int, judgements: [Judgement], perfects: Int) {
        self.score = score
        self.judgements = judgements
        self.perfects = perfects
    }

    // QA-1 P2-15: tolerant, so a field added later never drops the whole Daily history.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        judgements = (try? c.decodeIfPresent([Judgement].self, forKey: .judgements)) ?? []
        perfects = (try? c.decodeIfPresent(Int.self, forKey: .perfects)) ?? 0
    }
}

/// Lifetime numbers for the home screen's stats line and the litres achievement.
struct LifetimeStats: Codable, Equatable {
    /// World volume poured (pt² of 2D liquid). 40 000 ≈ one litre (see `ProgressData.litres`).
    var poured: Double = 0
    var perfects: Int = 0
    var bestStreak: Int = 0
    var glasses: Int = 0
    var runs: Int = 0

    init(poured: Double = 0, perfects: Int = 0, bestStreak: Int = 0, glasses: Int = 0, runs: Int = 0) {
        self.poured = poured
        self.perfects = perfects
        self.bestStreak = bestStreak
        self.glasses = glasses
        self.runs = runs
    }

    // QA-1 P2-15: tolerant, so a field added later never wipes the lifetime stats.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        poured = (try? c.decodeIfPresent(Double.self, forKey: .poured)) ?? 0
        perfects = (try? c.decodeIfPresent(Int.self, forKey: .perfects)) ?? 0
        bestStreak = (try? c.decodeIfPresent(Int.self, forKey: .bestStreak)) ?? 0
        glasses = (try? c.decodeIfPresent(Int.self, forKey: .glasses)) ?? 0
        runs = (try? c.decodeIfPresent(Int.self, forKey: .runs)) ?? 0
    }
}

/// What recording a finished run changed, for the results card.
struct RecordOutcome: Equatable {
    var isNewBest = false
    var previousBest = 0
    var starsBefore = 0
    var starsAfter = 0
    var newlyUnlocked: [VenueID] = []
    /// Daily: this run is the day's one scored attempt.
    var dailyCounted = false
    /// Daily: the scored attempt already on file (when this run was practice).
    var dailyOnFile: DailyRecord?
    /// Round 6 (decision 4): this run earned the shift's Flawless crown for the first time.
    var crownEarned = false
    /// The shift holds its Flawless crown after this run (earned now or earlier).
    var hasCrown = false
    /// Round 8 (REVIEW-6 N2): the shift's best Perfect count before this run, and after it.
    var previousBestPerfects = 0
    var bestPerfects = 0

    /// The results card's NEW BEST badge (REVIEW-2 P2-6): only when this run beat an earlier best, never on the first
    /// run of a shift or of Rush.
    var showsNewBest: Bool { isNewBest && previousBest > 0 }
}

/// Everything the game remembers. Saved as JSON under `ProgressStore.key`.
struct ProgressData: Codable, Equatable {
    var version = 1
    /// Best stars per shift level id ("1-1" …).
    var stars: [String: Int] = [:]
    /// Best score per shift level id.
    var bestScores: [String: Int] = [:]
    var rushBest = 0
    /// Scored Daily Pours by day number (`LevelCatalog.dayNumber(for:)`).
    var daily: [Int: DailyRecord] = [:]
    /// QA-1 P1-2: the day's scored attempt while it is being played (marked when it starts, updated on every serve).
    /// Finishing moves it to `daily`; leaving it (Menu, Restart, another mode) or the app dying mid-run files the partial
    /// pour as the day's score, so the scored attempt can't be retried. An attempt left before its first glass arrived
    /// (see `dailyArmed`) is dropped.
    var dailyStarted: [Int: DailyRecord] = [:]
    /// Round 5 (QA-2 P2-5): days whose scored attempt has had its first glass arrive. From then on leaving (or the app
    /// dying) files the attempt even with nothing served yet (a 0), so bailing mid-pour on glass 1 is no free retry.
    var dailyArmed: Set<Int> = []
    var stats = LifetimeStats()
    /// Onboarding hints already learned (`HintKind.rawValue`; round 6 adds the venue intro cards).
    var hintsSeen: Set<String> = []
    /// Round 6 (decision 4, REVIEW-5 §9 #3): shift level ids cleared with every glass Perfect (the Flawless crown).
    var crowns: Set<String> = []
    /// Round 8 (REVIEW-6 N2): the most Perfects poured in one run of each shift (level id → count, capped at the
    /// shift's glasses): the crown chase under a 3★ bubble ("4/6") and on the venue card ("✦ 41/52").
    var bestPerfects: [String: Int] = [:]
    /// Round 8 (REVIEW-6 #6, Glass Cabinet lite): the vessel chosen for Rush and Practice (a venue's jug, unlocked by
    /// Flawless crowns); nil = the house jug. Stored as the venue's raw value; an unknown one decodes as nil.
    var vessel: VenueID? = nil

    static let pouredPerLitre: Double = 40_000

    var totalStars: Int { stars.values.reduce(0) { $0 + min(max($1, 0), 3) } }
    var litres: Double { stats.poured / Self.pouredPerLitre }

    func stars(for levelID: String) -> Int { stars[levelID] ?? 0 }

    // MARK: Flawless crowns (round 6)

    func hasCrown(_ levelID: String) -> Bool { crowns.contains(levelID) }

    /// Crowned shifts in `venue` (the Venues card's "3/8").
    func crownsEarned(in venue: VenueID) -> Int {
        LevelCatalog.levels(in: venue).filter { crowns.contains($0.id) }.count
    }

    /// Pure rule: a cleared shift where every glass served was Perfect (and at least one was served).
    static func isFlawless(_ result: RunResult) -> Bool {
        guard case .shift = result.mode, result.cleared, !result.judgements.isEmpty else { return false }
        return result.judgements.allSatisfy { $0 == .perfect }
    }

    /// Crowns on shifts that exist (the Glass Cabinet's currency).
    var totalCrowns: Int { crowns.filter { LevelCatalog.level($0) != nil }.count }

    // MARK: Best Perfects per shift (round 8, REVIEW-6 N2)

    /// The shift's best Perfect count (a crowned shift counts every glass, so a round-6/7 save reads right).
    func bestPerfects(for levelID: String) -> Int {
        let total = LevelCatalog.level(levelID)?.orders.count ?? 0
        let stored = max(bestPerfects[levelID] ?? 0, 0)
        if crowns.contains(levelID) && total > 0 { return total }
        return total > 0 ? min(stored, total) : stored
    }

    /// The venue's best Perfects summed over its shifts, against its glasses ("✦ 41/52").
    func perfectsEarned(in venue: VenueID) -> (best: Int, glasses: Int) {
        let levels = LevelCatalog.levels(in: venue)
        let best = levels.reduce(0) { $0 + bestPerfects(for: $1.id) }
        let glasses = levels.reduce(0) { $0 + $1.orders.count }
        return (best, glasses)
    }

    // MARK: Glass Cabinet (round 8, REVIEW-6 #6)

    /// The chosen vessel while the crowns (and, for the copper scoop, the found Sand Bar) still hold it (nil = the house
    /// jug).
    var activeVessel: VenueID? {
        guard let vessel, isVesselUnlocked(vessel) else { return nil }
        return vessel
    }

    /// Round 9 (REVIEW-7 P1-3): a cabinet vessel is open with its crowns, and the secret venue's only once the Sand Bar
    /// has been found.
    func isVesselUnlocked(_ venue: VenueID?) -> Bool {
        GlassCabinet.isUnlocked(venue, crowns: totalCrowns, sandBarFound: isUnlocked(.sandBar))
    }

    // MARK: Daily week strip (round 6, decision 5)

    /// The seven days ending `today`, oldest first: true = a scored Daily Pour is on file that day.
    func dailyWeek(today: Int) -> [Bool] {
        (0..<7).map { daily[today - 6 + $0] != nil }
    }

    // MARK: Unlocks

    /// Pure rule: a venue opens once the player holds its star threshold.
    static func unlockRule(totalStars: Int, threshold: Int) -> Bool { totalStars >= max(threshold, 0) }

    /// Every non-secret shift has three stars (`brim.allstars`). Round 9 (founder decision): no longer the Sand Bar's
    /// gate; see `campaignStars`.
    var hasAllStars: Bool {
        let levels = LevelCatalog.levels.filter { $0.venue != .sandBar }
        guard !levels.isEmpty else { return false }
        return levels.allSatisfy { stars(for: $0.id) >= 3 }
    }

    /// Round 9 (founder decision): stars on the five main venues' shifts (0…120). The secret Sand Bar opens at
    /// `LevelCatalog.starsToUnlock(.sandBar)` of them, not at "3★ on every shift" (a few late shifts were out of
    /// reach for experts, so the secret was nearly unreachable). Unknown level ids don't count.
    var campaignStars: Int {
        stars.reduce(0) { sum, entry in
            guard let level = LevelCatalog.level(entry.key), level.venue != .sandBar else { return sum }
            return sum + min(max(entry.value, 0), 3)
        }
    }

    func isUnlocked(_ venue: VenueID) -> Bool {
        if venue == .sandBar {
            return Self.unlockRule(totalStars: campaignStars, threshold: LevelCatalog.starsToUnlock(.sandBar))
        }
        return Self.unlockRule(totalStars: totalStars, threshold: LevelCatalog.starsToUnlock(venue))
    }

    var unlockedVenues: [VenueID] { VenueID.allCases.filter { isUnlocked($0) } }

    /// Shifts open in order inside an unlocked venue: the first one, then each after a shift with ≥ 1 star.
    func isPlayable(_ level: Level) -> Bool {
        guard isUnlocked(level.venue) else { return false }
        if level.index <= 1 { return true }
        let inVenue = LevelCatalog.levels(in: level.venue)
        guard let previous = inVenue.first(where: { $0.index == level.index - 1 }) else { return true }
        return stars(for: previous.id) >= 1
    }

    /// The shift the big Play button starts: the first playable one without stars, else the last playable one.
    var nextShift: Level? {
        let playable = LevelCatalog.levels.filter { isPlayable($0) }
        return playable.first(where: { stars(for: $0.id) == 0 }) ?? playable.last ?? LevelCatalog.levels.first
    }

    func starsEarned(in venue: VenueID) -> Int {
        LevelCatalog.levels(in: venue).reduce(0) { $0 + min(stars(for: $1.id), 3) }
    }

    /// The next venue the player can open with stars, and how many more stars it needs (nil when every star venue is
    /// open; the secret Sand Bar is never named).
    var nextUnlock: (venue: VenueID, missing: Int)? {
        let total = totalStars
        for venue in VenueID.allCases where venue != .sandBar && !isUnlocked(venue) {
            return (venue, max(LevelCatalog.starsToUnlock(venue) - total, 0))
        }
        return nil
    }

    // MARK: Daily streak

    /// Consecutive days with a scored Daily Pour, ending today (or yesterday, if today's isn't poured yet: the streak
    /// is still alive until today ends).
    func dailyStreak(today: Int) -> Int {
        var day = daily[today] != nil ? today : today - 1
        var count = 0
        while daily[day] != nil {
            count += 1
            day -= 1
        }
        return count
    }

    /// The best scored Daily Pour on file (0 if none). REVIEW-5 P1-7.
    var bestDaily: Int { daily.values.map { $0.score }.max() ?? 0 }

    // MARK: Recording

    /// Folds a finished run into the progress. `today` = `LevelCatalog.dayNumber(for: Date())`.
    mutating func record(_ result: RunResult, today: Int) -> RecordOutcome {
        var outcome = RecordOutcome()
        if case .practice = result.mode { return outcome }
        let unlockedBefore = Set(unlockedVenues)

        switch result.mode {
        case let .shift(id):
            outcome.previousBest = bestScores[id] ?? 0
            outcome.starsBefore = stars(for: id)
            if result.score > outcome.previousBest { bestScores[id] = result.score }
            outcome.isNewBest = result.score > outcome.previousBest && result.score > 0
            stars[id] = max(outcome.starsBefore, min(max(result.stars, 0), 3))
            outcome.starsAfter = stars(for: id)
            if Self.isFlawless(result) && !crowns.contains(id) {
                crowns.insert(id)
                outcome.crownEarned = true
            }
            outcome.hasCrown = crowns.contains(id)
            // Round 8 (REVIEW-6 N2): the shift's best Perfects (any run of it, capped at its glasses).
            outcome.previousBestPerfects = max(bestPerfects[id] ?? 0, 0)
            var runPerfects = result.judgements.filter { $0 == .perfect }.count
            if let total = LevelCatalog.level(id)?.orders.count, total > 0 { runPerfects = min(runPerfects, total) }
            if runPerfects > outcome.previousBestPerfects { bestPerfects[id] = runPerfects }
            outcome.bestPerfects = bestPerfects(for: id)
        case .rush:
            outcome.previousBest = rushBest
            outcome.isNewBest = result.score > rushBest && result.score > 0
            rushBest = max(rushBest, result.score)
        case let .daily(day):
            if let existing = daily[day] {
                outcome.dailyOnFile = existing
            } else if dailyStarted[day] != nil || day == today {
                // The marked attempt counts whatever the clock says now (QA-1 P2-1: a run started at 23:59 UTC that
                // ends after midnight is still that day's pour).
                daily[day] = DailyRecord(score: result.score, judgements: result.judgements, perfects: result.perfects)
                outcome.dailyCounted = true
            }
            dailyStarted[day] = nil
            dailyArmed.remove(day)
        case .practice:
            break
        }

        stats.poured += max(result.poured, 0)
        stats.perfects += result.perfects
        stats.bestStreak = max(stats.bestStreak, result.bestStreak)
        stats.glasses += result.judgements.count
        stats.runs += 1

        outcome.newlyUnlocked = VenueID.allCases.filter { isUnlocked($0) && !unlockedBefore.contains($0) }
        return outcome
    }

    // MARK: Daily attempt marker (QA-1 P1-2)

    /// A Daily for `day` is starting. True = this run is the day's one scored attempt (marked now); false = practice
    /// (already on file). A stale marker (an attempt that was never closed) is filed first.
    mutating func beginDailyAttempt(day: Int) -> Bool {
        if daily[day] != nil { return false }
        if dailyStarted[day] != nil {
            _ = closeDailyAttempt(day: day)
            if daily[day] != nil { return false }
        }
        dailyStarted[day] = DailyRecord(score: 0, judgements: [], perfects: 0)
        dailyArmed.remove(day)
        return true
    }

    /// Round 5 (QA-2 P2-5): the scored attempt's first glass has arrived. From now on the attempt is filed when left,
    /// even before anything is served (as a 0). Does nothing without a marked attempt.
    mutating func armDailyAttempt(day: Int) {
        guard dailyStarted[day] != nil, daily[day] == nil else { return }
        dailyArmed.insert(day)
    }

    /// The scored attempt served a glass: remember where it stands, so leaving or dying files the partial pour.
    mutating func updateDailyAttempt(day: Int, score: Int, judgements: [Judgement], perfects: Int) {
        guard dailyStarted[day] != nil, daily[day] == nil else { return }
        dailyStarted[day] = DailyRecord(score: max(score, 0), judgements: judgements, perfects: max(perfects, 0))
    }

    /// The scored attempt was left unfinished: its partial pour becomes the day's score (returned). Before its first
    /// glass arrived (not armed) with nothing served, the marker is simply dropped (nothing was seen) and nil is returned;
    /// once armed it is filed even at 0 glasses.
    mutating func closeDailyAttempt(day: Int) -> DailyRecord? {
        guard let partial = dailyStarted[day] else {
            dailyArmed.remove(day)
            return nil
        }
        dailyStarted[day] = nil
        let armed = dailyArmed.contains(day)
        dailyArmed.remove(day)
        guard daily[day] == nil, armed || !partial.judgements.isEmpty else { return nil }
        daily[day] = partial
        return partial
    }

    /// At launch: any attempt still marked belongs to a run whose app died; file it (or drop it if nothing was served).
    /// Returns true when something changed.
    mutating func closeAbandonedDailyAttempts() -> Bool {
        guard !dailyStarted.isEmpty || !dailyArmed.isEmpty else { return false }
        for day in Array(dailyStarted.keys) { _ = closeDailyAttempt(day: day) }
        dailyArmed = []
        return true
    }

    // MARK: Achievements (Game Center ids)

    var earnedAchievements: Set<String> {
        var ids = Set<String>()
        if stats.perfects >= 1 { ids.insert("brim.first.perfect") }
        if stats.bestStreak >= 10 { ids.insert("brim.streak.10") }
        if stats.bestStreak >= 25 { ids.insert("brim.streak.25") }
        if litres >= 10 { ids.insert("brim.litres.10") }
        // ROUND-5 decision 5 (QA-2 P1-4): venue achievements fire on clearing EVERY shift of the venue (≥ 1 star
        // each), as docs/appstore/achievements.md says, never on the venue opening.
        if clearedEveryShift(in: .sodaFountain) { ids.insert("brim.venue.soda") }
        if clearedEveryShift(in: .milkshakeDiner) { ids.insert("brim.venue.diner") }
        if clearedEveryShift(in: .conveyor) { ids.insert("brim.venue.conveyor") }
        if clearedEveryShift(in: .potionShop) { ids.insert("brim.venue.potions") }
        if hasAllStars { ids.insert("brim.allstars") }
        // Round 9 (founder decision): the hidden "Grain by Grain" fires when the Sand Bar is found (its star gate).
        if isUnlocked(.sandBar) { ids.insert("brim.sandbar") }
        return ids
    }

    /// Every shift of `venue` has been cleared (≥ 1 star). False for a venue with no shifts.
    func clearedEveryShift(in venue: VenueID) -> Bool {
        let levels = LevelCatalog.levels(in: venue)
        guard !levels.isEmpty else { return false }
        return levels.allSatisfy { stars(for: $0.id) >= 1 }
    }

    // MARK: Formatting

    /// "0.4 L", "2.5 L", "12 L", "1,204 L".
    static func litresText(poured: Double) -> String {
        let l = max(poured, 0) / pouredPerLitre
        if l < 10 { return String(format: "%.1f L", l) }
        return "\(ShareText.grouped(Int(l.rounded()))) L"
    }
}

// Tolerant decoding: a missing field (older or newer save) falls back to its default instead of losing everything.
extension ProgressData {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        stars = (try? c.decodeIfPresent([String: Int].self, forKey: .stars)) ?? [:]
        bestScores = (try? c.decodeIfPresent([String: Int].self, forKey: .bestScores)) ?? [:]
        rushBest = (try? c.decodeIfPresent(Int.self, forKey: .rushBest)) ?? 0
        daily = (try? c.decodeIfPresent([Int: DailyRecord].self, forKey: .daily)) ?? [:]
        dailyStarted = (try? c.decodeIfPresent([Int: DailyRecord].self, forKey: .dailyStarted)) ?? [:]
        dailyArmed = (try? c.decodeIfPresent(Set<Int>.self, forKey: .dailyArmed)) ?? []
        stats = (try? c.decodeIfPresent(LifetimeStats.self, forKey: .stats)) ?? LifetimeStats()
        hintsSeen = (try? c.decodeIfPresent(Set<String>.self, forKey: .hintsSeen)) ?? []
        // Round 6: tolerant like the rest (an older save has no crowns; a bad value never costs the stars).
        crowns = (try? c.decodeIfPresent(Set<String>.self, forKey: .crowns)) ?? []
        // Round 8: tolerant too (an older save has neither; a bad value costs only itself).
        bestPerfects = (try? c.decodeIfPresent([String: Int].self, forKey: .bestPerfects)) ?? [:]
        if let raw = try? c.decodeIfPresent(String.self, forKey: .vessel) {
            vessel = VenueID(rawValue: raw)
        }
    }
}

// MARK: - Glass Cabinet lite (round 8, REVIEW-6 #6)

/// Venue vessels the player unlocks with Flawless crowns and picks for Rush and Practice (the scene draws that venue's
/// jug: `GameScene.vesselOverride`). Shifts and the Daily keep their venue's own jug. Pure; tested.
enum GlassCabinet {
    struct Vessel: Equatable, Identifiable {
        /// The venue whose jug this is; nil = the house jug (each venue's own, as before).
        var venue: VenueID?
        var name: String
        /// Flawless crowns needed.
        var crowns: Int
        var id: String { venue?.rawValue ?? "house" }
    }

    static let vessels: [Vessel] = [
        Vessel(venue: nil, name: "House jug", crowns: 0),
        Vessel(venue: .sodaFountain, name: "Soda dispenser", crowns: 3),
        Vessel(venue: .milkshakeDiner, name: "Shake tin", crowns: 6),
        Vessel(venue: .potionShop, name: "Potion flask", crowns: 10),
        Vessel(venue: .sandBar, name: "Copper scoop", crowns: 14),
    ]

    /// Crowns `venue`'s vessel needs (nil for a venue with no vessel in the cabinet).
    static func crownsNeeded(_ venue: VenueID?) -> Int? {
        vessels.first(where: { $0.venue == venue })?.crowns
    }

    /// Round 9 (REVIEW-7 P1-3): the secret venue's vessel needs its crowns AND the Sand Bar found (`sandBarFound` =
    /// `ProgressData.isUnlocked(.sandBar)`), so nobody pours Rush from the scoop before finding the bar.
    static func isUnlocked(_ venue: VenueID?, crowns: Int, sandBarFound: Bool) -> Bool {
        guard let need = crownsNeeded(venue) else { return false }
        if venue == .sandBar && !sandBarFound { return false }
        return crowns >= need
    }

    /// Round 9 (REVIEW-7 P1-3): the vessel is the secret venue's and the venue hasn't been found: the cabinet shows a
    /// locked "???" silhouette, never its name, accent or symbol.
    static func isSecret(_ vessel: Vessel, sandBarFound: Bool) -> Bool {
        vessel.venue == .sandBar && !sandBarFound
    }

    /// What a secret tile says instead of the vessel's name and crowns.
    static let secretName = "???"
    static let secretCaption = "Find the secret venue"

    /// The next vessel still locked, and how many crowns it needs (nil once all are open). A secret vessel is never
    /// named here.
    static func nextUnlock(crowns: Int, sandBarFound: Bool) -> (vessel: Vessel, missing: Int)? {
        guard let next = vessels.first(where: { $0.crowns > crowns && !isSecret($0, sandBarFound: sandBarFound) })
        else { return nil }
        return (next, next.crowns - max(crowns, 0))
    }

    /// "3 more 👑 for the Shake tin" (nil once everything shown is open).
    static func nextLine(crowns: Int, sandBarFound: Bool) -> String? {
        guard let next = nextUnlock(crowns: crowns, sandBarFound: sandBarFound) else { return nil }
        return "\(next.missing) more 👑 for the \(next.vessel.name)"
    }
}

// MARK: - Store

/// The app's progress, persisted as JSON in UserDefaults (`brim.progress.v1`). Demo runs use an in-memory store
/// seeded from `progress=fresh|mid|full` and never write.
@MainActor
final class ProgressStore: ObservableObject {
    static let key = "brim.progress.v1"
    /// QA-1 P2-14: an undecodable save is copied here before a fresh one replaces it.
    static let corruptKey = "brim.progress.v1.corrupt"

    @Published private(set) var data: ProgressData
    private let defaults: UserDefaults?

    /// Persistent store backed by `defaults`.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        var loaded = ProgressData()
        if let raw = defaults.data(forKey: Self.key) {
            if let decoded = try? JSONDecoder().decode(ProgressData.self, from: raw) {
                loaded = decoded
            } else {
                // Keep the bytes: the next save would otherwise overwrite the player's only copy.
                defaults.set(raw, forKey: Self.corruptKey)
            }
        }
        // A Daily attempt still marked at launch belongs to a run whose app died mid-pour (QA-1 P1-2).
        let closed = loaded.closeAbandonedDailyAttempts()
        data = loaded
        if closed { save() }
    }

    /// In-memory store (demo mode, previews).
    init(inMemory data: ProgressData) {
        self.defaults = nil
        self.data = data
    }

    var isPersistent: Bool { defaults != nil }

    // MARK: Reads

    var totalStars: Int { data.totalStars }
    var rushBest: Int { data.rushBest }
    func stars(for levelID: String) -> Int { data.stars(for: levelID) }
    func isUnlocked(_ venue: VenueID) -> Bool { data.isUnlocked(venue) }
    func isPlayable(_ level: Level) -> Bool { data.isPlayable(level) }
    func dailyRecord(day: Int) -> DailyRecord? { data.daily[day] }
    func dailyStreak(today: Int) -> Int { data.dailyStreak(today: today) }
    func hasSeenHint(_ id: String) -> Bool { data.hintsSeen.contains(id) }
    func hasCrown(_ levelID: String) -> Bool { data.hasCrown(levelID) }
    func bestPerfects(for levelID: String) -> Int { data.bestPerfects(for: levelID) }

    /// The shift after `levelID` in play order, if it is playable now.
    func nextLevel(after levelID: String) -> Level? {
        let all = LevelCatalog.levels
        guard let i = all.firstIndex(where: { $0.id == levelID }), i + 1 < all.count else { return nil }
        let next = all[i + 1]
        return data.isPlayable(next) ? next : nil
    }

    // MARK: Writes

    @discardableResult
    func record(_ result: RunResult, today: Int) -> RecordOutcome {
        var copy = data
        let outcome = copy.record(result, today: today)
        data = copy
        save()
        return outcome
    }

    /// A Daily for `day` is starting: true = the day's scored attempt (marked and saved now), false = practice.
    func beginDailyAttempt(day: Int) -> Bool {
        var copy = data
        let scored = copy.beginDailyAttempt(day: day)
        data = copy
        save()
        return scored
    }

    /// The scored attempt served a glass (saved, so a crash files the partial pour).
    func updateDailyAttempt(day: Int, score: Int, judgements: [Judgement], perfects: Int) {
        guard data.dailyStarted[day] != nil else { return }
        var copy = data
        copy.updateDailyAttempt(day: day, score: score, judgements: judgements, perfects: perfects)
        data = copy
        save()
    }

    /// The scored attempt's first glass arrived (saved, so leaving or a crash from now on files the attempt).
    func armDailyAttempt(day: Int) {
        guard data.dailyStarted[day] != nil, !data.dailyArmed.contains(day) else { return }
        var copy = data
        copy.armDailyAttempt(day: day)
        data = copy
        save()
    }

    /// The scored attempt was left unfinished: files the partial pour (returned; nil when it was never armed and
    /// nothing was served).
    @discardableResult
    func closeDailyAttempt(day: Int) -> DailyRecord? {
        guard data.dailyStarted[day] != nil else { return nil }
        var copy = data
        let filed = copy.closeDailyAttempt(day: day)
        data = copy
        save()
        return filed
    }

    func markHintSeen(_ id: String) {
        guard !data.hintsSeen.contains(id) else { return }
        data.hintsSeen.insert(id)
        save()
    }

    /// Round 8 (Glass Cabinet): picks the Rush/Practice vessel (nil = the house jug). A locked vessel is refused.
    func setVessel(_ venue: VenueID?) {
        if let venue, !data.isVesselUnlocked(venue) { return }
        guard data.vessel != venue else { return }
        data.vessel = venue
        save()
    }

    /// Forgets hints only (demo `hints=fresh`).
    func resetHints() {
        data.hintsSeen = []
        save()
    }

    /// Settings › Reset progress. Daily Pour results stay (QA-1 P2-16: a reset must not reopen today's scored pour).
    func resetProgress() {
        var fresh = ProgressData()
        fresh.daily = data.daily
        fresh.dailyStarted = data.dailyStarted
        fresh.dailyArmed = data.dailyArmed
        data = fresh
        save()
    }

    func replace(with newData: ProgressData) {
        data = newData
        save()
    }

    private func save() {
        guard let defaults, let raw = try? JSONEncoder().encode(data) else { return }
        defaults.set(raw, forKey: Self.key)
    }
}
