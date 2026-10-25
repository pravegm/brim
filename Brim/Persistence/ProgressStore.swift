import Combine
import Foundation

// MARK: - Stored data (pure value types, unit-tested in BrimTests/AppTests.swift)

/// One scored Daily Pour.
struct DailyRecord: Codable, Equatable {
    var score: Int
    var judgements: [Judgement]
    var perfects: Int
}

/// Lifetime numbers for the home screen's stats line and the litres achievement.
struct LifetimeStats: Codable, Equatable {
    /// World volume poured (pt² of 2D liquid). 40 000 ≈ one litre (see `ProgressData.litres`).
    var poured: Double = 0
    var perfects: Int = 0
    var bestStreak: Int = 0
    var glasses: Int = 0
    var runs: Int = 0
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
    var stats = LifetimeStats()
    /// Onboarding hints already learned (`HintKind.rawValue`).
    var hintsSeen: Set<String> = []

    static let pouredPerLitre: Double = 40_000

    var totalStars: Int { stars.values.reduce(0) { $0 + min(max($1, 0), 3) } }
    var litres: Double { stats.poured / Self.pouredPerLitre }

    func stars(for levelID: String) -> Int { stars[levelID] ?? 0 }

    // MARK: Unlocks

    /// Pure rule: a venue opens once the player holds its star threshold.
    static func unlockRule(totalStars: Int, threshold: Int) -> Bool { totalStars >= max(threshold, 0) }

    /// Every non-secret shift has three stars (opens the Sand Bar, `brim.allstars`).
    var hasAllStars: Bool {
        let levels = LevelCatalog.levels.filter { $0.venue != .sandBar }
        guard !levels.isEmpty else { return false }
        return levels.allSatisfy { stars(for: $0.id) >= 3 }
    }

    func isUnlocked(_ venue: VenueID) -> Bool {
        if venue == .sandBar { return hasAllStars }
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
        case .rush:
            outcome.previousBest = rushBest
            outcome.isNewBest = result.score > rushBest && result.score > 0
            rushBest = max(rushBest, result.score)
        case let .daily(day):
            if let existing = daily[day] {
                outcome.dailyOnFile = existing
            } else if day == today {
                daily[day] = DailyRecord(score: result.score, judgements: result.judgements, perfects: result.perfects)
                outcome.dailyCounted = true
            }
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

    // MARK: Achievements (Game Center ids)

    var earnedAchievements: Set<String> {
        var ids = Set<String>()
        if stats.perfects >= 1 { ids.insert("brim.first.perfect") }
        if stats.bestStreak >= 10 { ids.insert("brim.streak.10") }
        if stats.bestStreak >= 25 { ids.insert("brim.streak.25") }
        if litres >= 10 { ids.insert("brim.litres.10") }
        if isUnlocked(.sodaFountain) { ids.insert("brim.venue.soda") }
        if isUnlocked(.milkshakeDiner) { ids.insert("brim.venue.diner") }
        if isUnlocked(.conveyor) { ids.insert("brim.venue.conveyor") }
        if isUnlocked(.potionShop) { ids.insert("brim.venue.potions") }
        if hasAllStars { ids.insert("brim.allstars") }
        if LevelCatalog.levels(in: .sandBar).contains(where: { stars(for: $0.id) >= 1 }) { ids.insert("brim.sandbar") }
        return ids
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
        stats = (try? c.decodeIfPresent(LifetimeStats.self, forKey: .stats)) ?? LifetimeStats()
        hintsSeen = (try? c.decodeIfPresent(Set<String>.self, forKey: .hintsSeen)) ?? []
    }
}

// MARK: - Store

/// The app's progress, persisted as JSON in UserDefaults (`brim.progress.v1`). Demo runs use an in-memory store
/// seeded from `progress=fresh|mid|full` and never write.
@MainActor
final class ProgressStore: ObservableObject {
    static let key = "brim.progress.v1"

    @Published private(set) var data: ProgressData
    private let defaults: UserDefaults?

    /// Persistent store backed by `defaults`.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let raw = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(ProgressData.self, from: raw) {
            data = decoded
        } else {
            data = ProgressData()
        }
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
    func hasSeenHint(_ id: String) -> Bool { data.hintsSeen.contains(id) }

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

    func markHintSeen(_ id: String) {
        guard !data.hintsSeen.contains(id) else { return }
        data.hintsSeen.insert(id)
        save()
    }

    /// Forgets hints only (demo `hints=fresh`).
    func resetHints() {
        data.hintsSeen = []
        save()
    }

    /// Settings › Reset progress.
    func resetProgress() {
        data = ProgressData()
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
