import Foundation
import GameKit
import UIKit

/// Thin, polite Game Center wrapper (GAME-DESIGN §9). Authentication is silent: if the system hands us a sign-in
/// view controller we never present it. Scores and achievements earned while signed out are queued and sent once a
/// player is authenticated. Every failure is silent. Skipped entirely in demo runs (`-brimDemo`).
@MainActor
final class GameCenterManager {
    static let shared = GameCenterManager()

    enum Leaderboard {
        static let rush = "brim.rush.best"
        static let daily = "brim.daily.score"
    }

    static let achievementIDs: [String] = [
        "brim.first.perfect", "brim.streak.10", "brim.streak.25", "brim.litres.10",
        "brim.venue.soda", "brim.venue.diner", "brim.venue.conveyor", "brim.venue.potions",
        "brim.allstars", "brim.sandbar",
    ]

    private(set) var isAuthenticated = false
    private var started = false
    private var disabled = false
    private let reportedKey = "brim.gc.reported"
    private let pendingKey = "brim.gc.pending"
    private let pendingScoresKey = "brim.gc.pendingScores"

    private init() {}

    /// Called once at launch.
    func authenticate() {
        guard !started else { return }
        started = true
        if ProcessInfo.processInfo.arguments.contains("-brimDemo") {
            disabled = true
            return
        }
        GKAccessPoint.shared.isActive = false
        GKLocalPlayer.local.authenticateHandler = { _, _ in
            // The sign-in view controller (if any) is ignored on purpose: no surprise sheets over the game.
            Task { @MainActor in
                GameCenterManager.shared.authenticationChanged()
            }
        }
    }

    /// After a run: leaderboard scores and any achievements the progress now earns.
    func report(result: RunResult, outcome: RecordOutcome, progress: ProgressData) {
        guard !disabled else { return }
        switch result.mode {
        case .rush:
            if result.score > 0 { queueScore(result.score, leaderboard: Leaderboard.rush, day: nil) }
        case let .daily(day):
            if outcome.dailyCounted { queueScore(result.score, leaderboard: Leaderboard.daily, day: day) }
        default:
            break
        }
        unlock(progress.earnedAchievements)
    }

    // MARK: - Queue entries (pure; tested)

    /// One queued score: `leaderboard|score|day|token` (day -1 = not a Daily). Round-3 entries were `leaderboard|score`.
    struct QueuedScore: Equatable {
        var leaderboard: String
        var score: Int
        var day: Int?
        var token: String
    }

    nonisolated static func encode(leaderboard: String, score: Int, day: Int?, token: String) -> String {
        "\(leaderboard)|\(score)|\(day ?? -1)|\(token)"
    }

    nonisolated static func parse(_ entry: String) -> QueuedScore? {
        let parts = entry.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty, let value = Int(parts[1]) else { return nil }
        var day: Int?
        if parts.count >= 3, let d = Int(parts[2]), d >= 0 { day = d }
        let token = parts.count >= 4 ? parts[3] : entry
        return QueuedScore(leaderboard: parts[0], score: value, day: day, token: token)
    }

    /// QA-1 P2-17: a Daily score flushed after its day has ended would land on the next day's recurring leaderboard,
    /// so it is dropped instead. Rush scores never go stale.
    nonisolated static func isStale(_ score: QueuedScore, today: Int) -> Bool {
        guard score.leaderboard == Leaderboard.daily else { return false }
        guard let day = score.day else { return true }
        return day != today
    }

    func unlock(_ ids: Set<String>) {
        guard !disabled else { return }
        let reported = Set(UserDefaults.standard.stringArray(forKey: reportedKey) ?? [])
        var pending = Set(UserDefaults.standard.stringArray(forKey: pendingKey) ?? [])
        pending.formUnion(ids.subtracting(reported).filter { Self.achievementIDs.contains($0) })
        UserDefaults.standard.set(Array(pending).sorted(), forKey: pendingKey)
        flush()
    }

    // MARK: - Internals

    private func authenticationChanged() {
        isAuthenticated = GKLocalPlayer.local.isAuthenticated
        flush()
    }

    private func queueScore(_ score: Int, leaderboard: String, day: Int?) {
        var queue = UserDefaults.standard.stringArray(forKey: pendingScoresKey) ?? []
        queue.append(Self.encode(leaderboard: leaderboard, score: score, day: day, token: UUID().uuidString))
        UserDefaults.standard.set(Array(queue.suffix(20)), forKey: pendingScoresKey)
        flush()
    }

    /// Scores submitted and not yet confirmed (by entry), so a second flush doesn't send them twice.
    private var inFlight: Set<String> = []

    private func flush() {
        guard isAuthenticated, !disabled else { return }

        // QA-1 P2-17: entries leave the queue only when Game Center confirms them (an offline submit stays queued);
        // stale Daily entries and unreadable ones are dropped first.
        let today = LevelCatalog.dayNumber(for: Date())
        let queued = UserDefaults.standard.stringArray(forKey: pendingScoresKey) ?? []
        let kept = queued.filter { entry in
            guard let parsed = Self.parse(entry) else { return false }
            return !Self.isStale(parsed, today: today)
        }
        if kept.count != queued.count { UserDefaults.standard.set(kept, forKey: pendingScoresKey) }
        for entry in kept where !inFlight.contains(entry) {
            guard let parsed = Self.parse(entry) else { continue }
            inFlight.insert(entry)
            GKLeaderboard.submitScore(parsed.score, context: 0, player: GKLocalPlayer.local,
                                      leaderboardIDs: [parsed.leaderboard]) { error in
                let ok = error == nil
                Task { @MainActor in
                    GameCenterManager.shared.didSubmit(entry, ok: ok)
                }
            }
        }

        let ids = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
        guard !ids.isEmpty else { return }
        let achievements: [GKAchievement] = ids.map { id in
            let achievement = GKAchievement(identifier: id)
            achievement.percentComplete = 100
            achievement.showsCompletionBanner = true
            return achievement
        }
        GKAchievement.report(achievements) { error in
            let ok = error == nil
            Task { @MainActor in
                GameCenterManager.shared.didReport(ids, ok: ok)
            }
        }
    }

    private func didSubmit(_ entry: String, ok: Bool) {
        inFlight.remove(entry)
        guard ok else { return }
        let queue = (UserDefaults.standard.stringArray(forKey: pendingScoresKey) ?? []).filter { $0 != entry }
        UserDefaults.standard.set(queue, forKey: pendingScoresKey)
    }

    private func didReport(_ ids: [String], ok: Bool) {
        guard ok else { return }
        var reported = Set(UserDefaults.standard.stringArray(forKey: reportedKey) ?? [])
        reported.formUnion(ids)
        UserDefaults.standard.set(Array(reported).sorted(), forKey: reportedKey)
        let pending = (UserDefaults.standard.stringArray(forKey: pendingKey) ?? []).filter { !reported.contains($0) }
        UserDefaults.standard.set(pending, forKey: pendingKey)
    }
}
