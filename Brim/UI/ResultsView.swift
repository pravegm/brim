import SwiftUI

/// End of a run: stars pop in one by one, the score counts up, perfects and best streak, a New Best badge; Next /
/// Retry / Menu on the bottom half (flat on a Duo). Daily adds the emoji-grid share line.
struct ResultsView: View {
    @ObservedObject var controller: GameController
    let summary: ResultSummary
    let info: CanvasInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var starsShown = 0
    @State private var shownScore = 0
    @State private var showBadge = false

    private var result: RunResult { summary.result }
    private var outcome: RecordOutcome { summary.outcome }

    private var isShift: Bool {
        if case .shift = result.mode { return true }
        return false
    }

    private var dailyDay: Int? {
        if case let .daily(day) = result.mode { return day }
        return nil
    }

    /// The line the Share button sends: the day's scored attempt (this run, or the one already on file).
    private var shareText: String? {
        guard let day = dailyDay else { return nil }
        if let onFile = outcome.dailyOnFile {
            return ShareText.daily(day: day, judgements: onFile.judgements, score: onFile.score)
        }
        return ShareText.daily(day: day, judgements: result.judgements, score: result.score)
    }

    private var headline: String {
        if isShift {
            if result.stars >= 3 { return "Flawless shift!" }
            if result.cleared { return "Shift cleared" }
            return "So close"
        }
        if dailyDay != nil { return outcome.dailyOnFile == nil ? "Daily poured" : "Practice pour" }
        return "Last call!"
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [BrimTheme.cream.opacity(0.92), BrimTheme.peach.opacity(0.88)],
                           startPoint: .top, endPoint: .bottom)
            DuoSplit(info: info) {
                card
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .scaleEffect(appeared ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)
            } bottom: {
                buttons
                    .padding(.horizontal, 22)
                    .frame(maxWidth: 520)
                    .offset(y: appeared ? 0 : 36)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .task { await playIntro() }
    }

    // MARK: Card (top half)

    private var card: some View {
        VStack(spacing: 10) {
            Text(summary.title.uppercased())
                .font(BrimTheme.text(13, .heavy))
                .kerning(1)
                .foregroundStyle(BrimTheme.inkSoft)
            Text(headline)
                .font(BrimTheme.title(info.isCompact ? 26 : 30))
                .foregroundStyle(BrimTheme.ink)
            if isShift {
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < starsShown ? "star.fill" : "star")
                            .font(.system(size: i == 1 ? 46 : 38, weight: .heavy))
                            .foregroundStyle(i < starsShown ? BrimTheme.gold : BrimTheme.inkFaint.opacity(0.45))
                            .shadow(color: i < starsShown ? BrimTheme.goldDeep.opacity(0.5) : .clear, radius: 6, y: 2)
                            .scaleEffect(i < starsShown ? 1 : 0.8)
                            .offset(y: i == 1 ? -6 : 0)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(result.stars) of 3 stars")
            }
            ZStack(alignment: .topTrailing) {
                Text(ShareText.grouped(shownScore))
                    .font(BrimTheme.number(info.isCompact ? 48 : 58))
                    .foregroundStyle(BrimTheme.ink)
                    .monospacedDigit()
                    .padding(.horizontal, 30)
                    .accessibilityLabel("Score \(result.score)")
                if outcome.isNewBest && showBadge {
                    Pill(text: "NEW BEST", fill: BrimTheme.cyan, fontSize: 12)
                        .rotationEffect(.degrees(8))
                        .offset(x: 26, y: -10)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            HStack(spacing: 14) {
                stat(value: "\(result.perfects)", label: "perfect")
                stat(value: "\(result.bestStreak)", label: "best streak")
                stat(value: "\(result.judgements.count)", label: "glasses")
            }
            if !result.judgements.isEmpty && !isShift {
                judgementStrip
            }
            if let note = note {
                Text(note)
                    .font(BrimTheme.text(13, .bold))
                    .foregroundStyle(BrimTheme.inkSoft)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .frame(maxWidth: 480)
        .background(
            RoundedRectangle(cornerRadius: BrimTheme.cardRadius, style: .continuous)
                .fill(BrimTheme.card)
                .shadow(color: BrimTheme.ink.opacity(0.18), radius: 20, y: 8)
        )
    }

    private var note: String? {
        if !outcome.newlyUnlocked.isEmpty {
            let names = outcome.newlyUnlocked.map { LevelCatalog.title(of: $0) }.joined(separator: ", ")
            return "Unlocked: \(names)!"
        }
        if dailyDay != nil {
            if let onFile = outcome.dailyOnFile {
                return "Practice — today's scored pour: \(ShareText.grouped(onFile.score))"
            }
            return outcome.dailyCounted ? "Today's scored pour. New glasses tomorrow." : nil
        }
        if case .rush = result.mode, !outcome.isNewBest, outcome.previousBest > 0 {
            return "Best \(ShareText.grouped(outcome.previousBest))"
        }
        return nil
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(BrimTheme.number(22))
                .foregroundStyle(BrimTheme.ink)
            Text(label)
                .font(BrimTheme.text(11, .heavy))
                .foregroundStyle(BrimTheme.inkSoft)
        }
        .frame(minWidth: 70)
        .accessibilityElement(children: .combine)
    }

    private var judgementStrip: some View {
        let shown = Array(result.judgements.suffix(20))
        return HStack(spacing: 4) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, judgement in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(BrimTheme.color(for: judgement))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: "star.fill")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.white)
                            .opacity(judgement == .perfect ? 1 : 0)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Buttons (bottom half)

    private var buttons: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            if let nextID = summary.nextLevelID {
                TapButton(kind: .primary, height: 66, action: { controller.start(mode: .shift(nextID)) }) {
                    Label("Next shift", systemImage: "arrow.right")
                }
            }
            if let shareText {
                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(BrimButtonStyle(kind: summary.nextLevelID == nil ? .primary : .secondary, height: 62))
            }
            HStack(spacing: 12) {
                TapButton(kind: summary.nextLevelID == nil && shareText == nil ? .primary : .secondary,
                          action: { controller.restart() }) {
                    Label(dailyDay != nil ? "Practice" : "Retry", systemImage: "arrow.counterclockwise")
                }
                TapButton(kind: .quiet, action: { controller.quitToMenu() }) {
                    Label("Menu", systemImage: "house.fill")
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Intro

    @MainActor
    private func playIntro() async {
        withAnimation(BrimTheme.pop(reduceMotion)) { appeared = true }
        if reduceMotion {
            shownScore = result.score
            starsShown = isShift ? result.stars : 0
            showBadge = true
            celebrateIfEarned()
            return
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        // Score count-up (~0.9 s, ease-out).
        let steps = 36
        for i in 1...steps {
            if Task.isCancelled { return }
            let t = Double(i) / Double(steps)
            let eased = 1 - pow(1 - t, 3)
            shownScore = Int((Double(result.score) * eased).rounded())
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        shownScore = result.score
        // Stars, one by one.
        if isShift && result.stars > 0 {
            for i in 1...min(result.stars, 3) {
                try? await Task.sleep(nanoseconds: 330_000_000)
                if Task.isCancelled { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { starsShown = i }
                FeedbackDirector.shared.uiConfirm()
            }
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { showBadge = true }
        celebrateIfEarned()
    }

    private func celebrateIfEarned() {
        if outcome.isNewBest || (isShift && result.stars >= 3) {
            FeedbackDirector.shared.celebrate()
        }
    }
}
