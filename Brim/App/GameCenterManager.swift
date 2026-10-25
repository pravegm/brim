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
            if result.score > 0 { queueScore(result.score, leaderboard: Leaderboard.rush) }
        case .daily:
            if outcome.dailyCounted { queueScore(result.score, leaderboard: Leaderboard.daily) }
        default:
            break
        }
        unlock(progress.earnedAchievements)
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

    private func queueScore(_ score: Int, leaderboard: String) {
        var queue = UserDefaults.standard.stringArray(forKey: pendingScoresKey) ?? []
        queue.append("\(leaderboard)|\(score)")
        UserDefaults.standard.set(Array(queue.suffix(20)), forKey: pendingScoresKey)
        flush()
    }

    private func flush() {
        guard isAuthenticated, !disabled else { return }

        let scores = UserDefaults.standard.stringArray(forKey: pendingScoresKey) ?? []
        if !scores.isEmpty {
            UserDefaults.standard.set([String](), forKey: pendingScoresKey)
            for entry in scores {
                let parts = entry.split(separator: "|").map(String.init)
                guard parts.count == 2, let value = Int(parts[1]) else { continue }
                GKLeaderboard.submitScore(value, context: 0, player: GKLocalPlayer.local,
                                          leaderboardIDs: [parts[0]]) { _ in }
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

    private func didReport(_ ids: [String], ok: Bool) {
        guard ok else { return }
        var reported = Set(UserDefaults.standard.stringArray(forKey: reportedKey) ?? [])
        reported.formUnion(ids)
        UserDefaults.standard.set(Array(reported).sorted(), forKey: reportedKey)
        let pending = (UserDefaults.standard.stringArray(forKey: pendingKey) ?? []).filter { !reported.contains($0) }
        UserDefaults.standard.set(pending, forKey: pendingKey)
    }
}
