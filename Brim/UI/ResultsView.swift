import SwiftUI

/// End of a run (REVIEW-1 P1-11): NEW BEST above the score, stars pop in one by one, the score counts up, a
/// glass-by-glass recap (mini glasses at their served levels against their lines) for every mode, the next unlock,
/// then Next / Retry / Menu. On a Duo the card sits on the top half and the buttons on the flat half; on a phone the
/// card and the buttons are one balanced, centred column. Daily adds the emoji share line.
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
        let streak = controller.store.dailyStreak(today: day)
        if let onFile = outcome.dailyOnFile {
            return ShareText.daily(day: day, judgements: onFile.judgements, score: onFile.score, streak: streak)
        }
        // Only the scored attempt is shared as "Brim Daily #N".
        guard outcome.dailyCounted else { return nil }
        return ShareText.daily(day: day, judgements: result.judgements, score: result.score, streak: streak)
    }

    /// A struck-out shift: "3 of 7 glasses" leads, the score steps down (REVIEW-5 P1-6).
    private var progressHero: String? { Self.progressLine(for: result) }

    /// Pure (tested): "Flawless" only when every glass was Perfect. A failed shift says what ended it (REVIEW-2 P2-6:
    /// never "So close" on a three-spill run).
    static func headline(for result: RunResult, dailyOnFile: Bool) -> String {
        switch result.mode {
        case .shift:
            if !result.judgements.isEmpty && result.judgements.allSatisfy({ $0 == .perfect }) { return "Flawless shift!" }
            if result.stars >= 3 { return "Great shift!" }
            if result.cleared { return "Shift cleared" }
            // REVIEW-5 P1-6: what ended it, counting every strike (short, over, spill), itemised when mixed:
            // "Shift over — 3 spills", "Shift over — 2 over, 1 spill".
            let misses = result.judgements.filter { !$0.isHit }
            if misses.count >= 3 { return "Shift over — \(missBreakdown(misses))" }
            return "Not quite"
        case .daily:
            return dailyOnFile ? "Practice pour" : "Daily poured"
        case .rush:
            // QA-2 P2-13: never "Last call!" (a bar's call for alcohol).
            return "Rush over!"
        case .practice:
            return "Nice pouring!"
        }
    }

    /// "3 spills", "3 shorts", "2 over, 1 spill" (one kind: the plural; mixed: each kind, most first). Pure.
    static func missBreakdown(_ misses: [Judgement]) -> String {
        let kinds: [(Judgement, String, String)] = [(.over, "over", "over"), (.short, "short", "shorts"),
                                                     (.spill, "spill", "spills")]
        var parts: [(count: Int, text: String)] = []
        for (kind, one, many) in kinds {
            let n = misses.filter { $0 == kind }.count
            if n > 0 { parts.append((count: n, text: "\(n) \(n == 1 ? one : many)")) }
        }
        if parts.count <= 1 { return parts.first?.text ?? "\(misses.count) misses" }
        // Stable: most first, ties in the order above.
        let ordered = parts.enumerated().sorted { a, b in
            a.element.count != b.element.count ? a.element.count > b.element.count : a.offset < b.offset
        }
        return ordered.map { $0.element.text }.joined(separator: ", ")
    }

    /// REVIEW-5 P1-6: one coaching line for a failed shift, from its venue and its most common miss. Pure; tested.
    static func coachingTip(for result: RunResult) -> String? {
        guard case let .shift(id) = result.mode, !result.cleared else { return nil }
        let misses = result.judgements.filter { !$0.isHit }
        guard !misses.isEmpty else { return nil }
        let overs = misses.filter { $0 == .over }.count
        let shorts = misses.filter { $0 == .short }.count
        let spills = misses.filter { $0 == .spill }.count
        let venue = LevelCatalog.level(id)?.venue
        if shorts > overs && shorts > spills {
            if venue == .conveyor { return "Start pouring before the glass reaches the spout." }
            return "A little longer: keep pouring until the line glows."
        }
        switch venue {
        case .sodaFountain?: return "Foam keeps rising after you stop. Stop early, let it settle, top up."
        case .milkshakeDiner?: return "Thick drinks keep coming. Stop well before the line."
        case .sandBar?: return "Sand slides all at once. Tip slowly, stop early."
        default: break
        }
        if spills > overs { return "Ease off near the brim: stop before the line." }
        return "Stop a little earlier: the stream keeps falling."
    }

    /// REVIEW-5 P1-6: a struck-out shift leads with how far it got ("3 of 7 glasses"), not a giant 0. nil otherwise.
    static func progressLine(for result: RunResult) -> String? {
        guard case let .shift(id) = result.mode, !result.cleared,
              let total = LevelCatalog.level(id)?.orders.count, total > 0 else { return nil }
        let served = min(result.judgements.count, total)
        return "\(served) of \(total) glass\(total == 1 ? "" : "es")"
    }

    /// REVIEW-5 P1-7: the Daily's ceremony line: "🔥 4 days in a row · best 1,240" (the streak only from 2 days). Pure.
    static func dailyLine(streak: Int, best: Int) -> String {
        var parts: [String] = []
        if streak >= 2 { parts.append("🔥 \(streak) days in a row") }
        if best > 0 { parts.append("best \(ShareText.grouped(best))") }
        return parts.isEmpty ? "First Daily Pour" : parts.joined(separator: " · ")
    }

    /// QA-2 P2-8: the Daily rolls over at 00:00 UTC, which is not "tomorrow" in most of the Americas. Says when, in the
    /// player's own clock: "New glasses at 7:00 PM." Pure (tested with a fixed zone and locale).
    static func dailyRolloverNote(now: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? timeZone
        let startOfDay = utc.startOfDay(for: now)
        guard let next = utc.date(byAdding: .day, value: 1, to: startOfDay) else {
            return "Today's scored pour. New glasses at midnight UTC."
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Today's scored pour. New glasses at \(formatter.string(from: next))."
    }

    var body: some View {
        ZStack {
            if info.hasFold {
                duoLayout
            } else {
                LinearGradient(colors: [BrimTheme.cream.opacity(0.93), BrimTheme.peach.opacity(0.9)],
                               startPoint: .top, endPoint: .bottom)
                VStack(spacing: 22) {
                    Spacer(minLength: 0)
                    cardBlock
                    buttonsBlock
                        .frame(maxWidth: 460)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, info.insets.top + 8)
                .padding(.bottom, max(info.insets.bottom, 12))
                .frame(width: info.size.width, height: info.size.height)
            }
        }
        .task { await playIntro() }
    }

    // MARK: Duo (REVIEW-2 P1-10): card on the raised half, the shift's glasses on the flat half's counter

    /// The raised half is a clean wall (opaque: no frozen play scene peeking out under the card); the flat half is a
    /// counter whose front edge sits on the crease, with the served glasses standing on it at their true levels and
    /// relative sizes, each on a coaster in its verdict colour; one row of buttons at the bottom.
    private var duoLayout: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Opaque (REVIEW-3 P2-4): no ghost of the tipped jug under the card.
                LinearGradient(colors: [BrimTheme.cream, BrimTheme.peach.opacity(0.95)],
                               startPoint: .top, endPoint: .bottom)
                    .background(BrimTheme.cream)
                    .frame(height: max(info.topHalfHeight, 0))
                ResultsCounter()
            }
            .frame(width: info.size.width, height: info.size.height)
            DuoSplit(info: info) {
                cardBlock
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            } bottom: {
                VStack(spacing: 0) {
                    if !summary.recap.isEmpty {
                        CounterRecap(recap: summary.recap, shown: appeared)
                            .padding(.top, 18)
                            .padding(.bottom, 12)
                    } else {
                        Spacer(minLength: 0)
                        if !result.judgements.isEmpty { judgementStrip }
                        Spacer(minLength: 0)
                    }
                    duoButtonRow
                        .frame(maxWidth: 560)
                        .offset(y: appeared ? 0 : 36)
                        .opacity(appeared ? 1 : 0)
                }
                .padding(.horizontal, 20)
            }
        }
        .frame(width: info.size.width, height: info.size.height)
    }

    private var duoButtonRow: some View {
        HStack(spacing: 10) {
            if let nextID = summary.nextLevelID {
                TapButton(kind: .primary, height: 60, hPad: 8, action: { controller.start(mode: .shift(nextID)) }) {
                    Label("Next shift", systemImage: "arrow.right")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            if let shareText {
                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .buttonStyle(BrimButtonStyle(kind: summary.nextLevelID == nil ? .primary : .secondary, height: 60,
                                             hPad: 8))
            }
            TapButton(kind: summary.nextLevelID == nil && shareText == nil ? .primary : .secondary, height: 60, hPad: 8,
                      action: { controller.restart() }) {
                Label(dailyDay != nil ? "Practice" : "Retry", systemImage: "arrow.counterclockwise")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            TapButton(kind: .quiet, height: 60, hPad: 8, action: { controller.quitToMenu() }) {
                Label("Menu", systemImage: "house.fill")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var cardBlock: some View {
        card
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
    }

    private var buttonsBlock: some View {
        buttons
            .offset(y: appeared ? 0 : 36)
            .opacity(appeared ? 1 : 0)
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: info.isCompact ? 6 : 8) {
            Text(summary.title.uppercased())
                .font(BrimTheme.text(12, .heavy))
                .kerning(1)
                .foregroundStyle(BrimTheme.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // A Daily that didn't count (already on file, or not the day's marked attempt) is practice.
            Text(Self.headline(for: result, dailyOnFile: outcome.dailyOnFile != nil || !outcome.dailyCounted))
                .font(BrimTheme.title(info.isCompact ? 25 : 29))
                .foregroundStyle(BrimTheme.ink)
            if isShift {
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < starsShown ? "star.fill" : "star")
                            .font(.system(size: i == 1 ? 40 : 33, weight: .heavy))
                            .foregroundStyle(i < starsShown ? BrimTheme.gold : BrimTheme.inkFaint.opacity(0.45))
                            .shadow(color: i < starsShown ? BrimTheme.goldDeep.opacity(0.5) : .clear, radius: 6, y: 2)
                            .scaleEffect(i < starsShown ? 1 : 0.8)
                            .offset(y: i == 1 ? -5 : 0)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(result.stars) of 3 stars")
            }
            VStack(spacing: 2) {
                if outcome.showsNewBest {
                    Pill(text: "NEW BEST", fill: BrimTheme.cyan, fontSize: 12)
                        .scaleEffect(showBadge ? 1 : 0.4)
                        .opacity(showBadge ? 1 : 0)
                }
                if let progressHero {
                    Text(progressHero)
                        .font(BrimTheme.title(info.isCompact ? 32 : 38))
                        .foregroundStyle(BrimTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(ShareText.grouped(shownScore))
                    .font(BrimTheme.number(progressHero != nil ? 28 : (info.isCompact ? 44 : 52)))
                    .foregroundStyle(progressHero != nil ? BrimTheme.inkSoft : BrimTheme.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel("Score \(result.score)")
            }
            Text(statsLine)
                .font(BrimTheme.text(13, .heavy))
                .foregroundStyle(BrimTheme.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            // On a Duo the glasses stand on the flat half's counter instead (duoLayout).
            if !info.hasFold {
                if !summary.recap.isEmpty {
                    // REVIEW-5 P1-7: the Daily's 10 glasses all fit on an iPhone card (smaller, tighter).
                    let narrow = info.size.width < 420
                    let compactDaily = narrow && dailyDay != nil
                    RecapRow(recap: summary.recap, maxCount: compactDaily ? 10 : (narrow ? 8 : 10),
                             glassWidth: compactDaily ? 24 : 30, spacing: compactDaily ? 4 : 6)
                        .padding(.top, 2)
                } else if !result.judgements.isEmpty {
                    judgementStrip
                }
            }
            if let note = note {
                Text(note)
                    .font(BrimTheme.text(13, .bold))
                    .foregroundStyle(BrimTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let unlock = unlockLine {
                Label(unlock, systemImage: "lock.open.fill")
                    .font(BrimTheme.text(13, .heavy))
                    .foregroundStyle(BrimTheme.goldDeep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: 480)
        .background(
            RoundedRectangle(cornerRadius: BrimTheme.cardRadius, style: .continuous)
                .fill(BrimTheme.card)
                .shadow(color: BrimTheme.ink.opacity(0.18), radius: 20, y: 8)
        )
    }

    private var statsLine: String {
        // REVIEW-5 P1-7: the Daily leads with its streak and best, never a row of zeros.
        if let day = dailyDay, outcome.dailyCounted || outcome.dailyOnFile != nil {
            return Self.dailyLine(streak: controller.store.dailyStreak(today: day),
                                  best: controller.store.data.bestDaily)
        }
        let glasses = result.judgements.count
        return "\(result.perfects) perfect · best streak \(result.bestStreak) · \(glasses) glass\(glasses == 1 ? "" : "es")"
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
            return outcome.dailyCounted ? Self.dailyRolloverNote(now: Date()) : nil
        }
        if case .rush = result.mode, !outcome.isNewBest, outcome.previousBest > 0 {
            return "Best \(ShareText.grouped(outcome.previousBest))"
        }
        // REVIEW-5 P1-6: a failed shift says what to try next.
        return Self.coachingTip(for: result)
    }

    /// "Next unlock: 3 more ★ for Milkshake Diner" (nothing when it was just unlocked or all are open). REVIEW-5: not
    /// on a Daily card, nor on a shift that wasn't cleared.
    private var unlockLine: String? {
        if dailyDay != nil { return nil }
        if isShift && !result.cleared { return nil }
        guard outcome.newlyUnlocked.isEmpty, let next = controller.store.data.nextUnlock else { return nil }
        let star = next.missing == 1 ? "1 more ★" : "\(next.missing) more ★"
        return "Next unlock: \(star) for \(LevelCatalog.title(of: next.venue))"
    }

    private var judgementStrip: some View {
        let shown = Array(result.judgements.suffix(20))
        return HStack(spacing: 4) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, judgement in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(BrimTheme.color(for: judgement))
                    .frame(width: 14, height: 14)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Buttons

    private var buttons: some View {
        VStack(spacing: 12) {
            if info.hasFold { Spacer(minLength: 0) }
            if let nextID = summary.nextLevelID {
                TapButton(kind: .primary, height: 64, action: { controller.start(mode: .shift(nextID)) }) {
                    Label("Next shift", systemImage: "arrow.right")
                }
            }
            if let shareText {
                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(BrimButtonStyle(kind: summary.nextLevelID == nil ? .primary : .secondary, height: 60))
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
            if info.hasFold { Spacer(minLength: 0) }
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
        if outcome.showsNewBest || (isShift && result.stars >= 3) {
            FeedbackDirector.shared.celebrate()
        }
    }
}

// MARK: - Recap row

/// Glass by glass: each served glass drawn small at its served level against its line, the judgement chip under it.
struct RecapRow: View {
    let recap: [GlassRecap]
    var maxCount: Int = 10
    /// Each mini glass's box width (height 4:3 of it), and the gap between glasses.
    var glassWidth: CGFloat = 30
    var spacing: CGFloat = 6

    var body: some View {
        let shown = Array(recap.suffix(maxCount))
        let hidden = recap.count - shown.count
        return HStack(alignment: .bottom, spacing: spacing) {
            if hidden > 0 {
                Text("+\(hidden)")
                    .font(BrimTheme.text(12, .heavy))
                    .foregroundStyle(BrimTheme.inkSoft)
                    .padding(.bottom, 14)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 4) {
                    MiniGlass(item: item)
                        .frame(width: glassWidth, height: glassWidth * 4 / 3)
                    // Colour plus a glyph, so the verdict reads without colour (REVIEW-3 P2-4).
                    Circle()
                        .fill(BrimTheme.color(for: item.judgement))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Image(systemName: RecapGlyph.symbol(for: item.judgement))
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(BrimTheme.ink)
                        )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recap.map { $0.judgement.rawValue }.joined(separator: ", "))
    }
}

// MARK: - Duo results: the shift on the counter

/// The flat half behind the Duo results: a counter whose front edge sits on the crease (like the play frame), a warm
/// surface with a few faint plank lines. Purely decorative.
struct ResultsCounter: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(brimHex: 0xEFC39C), Color(brimHex: 0xDFA27A)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var y: CGFloat = 70
                var row = 0
                while y < size.height {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(line, with: .color(BrimTheme.ink.opacity(0.06)), lineWidth: 1.5)
                    // A staggered plank joint on every row.
                    let jx = size.width * (row % 2 == 0 ? 0.3 : 0.7)
                    var joint = Path()
                    joint.move(to: CGPoint(x: jx, y: y))
                    joint.addLine(to: CGPoint(x: jx, y: min(y + 64, size.height)))
                    ctx.stroke(joint, with: .color(BrimTheme.ink.opacity(0.05)), lineWidth: 1.5)
                    y += 64
                    row += 1
                }
            }
            // The counter's front edge (on the crease band).
            VStack(spacing: 0) {
                Rectangle().fill(Color(brimHex: 0xF6D8B8)).frame(height: 10)
                Rectangle().fill(Color(brimHex: 0xC98A62)).frame(height: 4)
                LinearGradient(colors: [BrimTheme.ink.opacity(0.12), BrimTheme.ink.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 18)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The verdict glyph on a recap coaster: ✓ for a hit, a drop for a spill, ↓ for a short, ↑ for an over (REVIEW-3
/// P2-4: the coaster colour alone isn't colour-blind safe).
enum RecapGlyph {
    static func symbol(for judgement: Judgement) -> String {
        switch judgement {
        case .perfect, .great, .good: return "checkmark"
        case .spill: return "drop.fill"
        case .short: return "arrow.down"
        case .over: return "arrow.up"
        }
    }
}

/// The served glasses standing in a row on the counter, all at one scale (≈ 75 % of the play size, ~85 pt for a
/// tumbler; smaller if the row or the height needs it), each at its served level against its line, on a coaster in its
/// verdict colour with its verdict glyph.
struct CounterRecap: View {
    let recap: [GlassRecap]
    /// Slide in (one after another) once the results have appeared.
    let shown: Bool
    var maxCount: Int = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pure (tested): one scale for the whole row so it fits `size` (glass interiors only; coasters and gaps added).
    static func rowScale(_ items: [GlassRecap], size: CGSize, spacing: CGFloat, preferred: CGFloat = 0.75) -> CGFloat {
        guard !items.isEmpty, size.width > 0, size.height > 0 else { return preferred }
        let widths = items.map { 2 * max($0.shape.profile.map { $0.x }.max() ?? 1, 1) }
        let tallest = items.map { max($0.shape.interiorHeight, 1) }.max() ?? 1
        let gaps = spacing * CGFloat(items.count - 1)
        let byWidth = max(size.width - gaps, 1) / max(widths.reduce(0, +), 1)
        let byHeight = max(size.height - 26, 1) / tallest
        return max(min(preferred, byWidth, byHeight), 0.05)
    }

    var body: some View {
        GeometryReader { geo in
            let items = Array(recap.suffix(maxCount))
            let spacing: CGFloat = items.count > 7 ? 10 : 18
            let scale = Self.rowScale(items, size: geo.size, spacing: spacing)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let half = max(item.shape.profile.map { $0.x }.max() ?? 1, 1)
                    let width = 2 * half * scale + 6
                    VStack(spacing: -4) {
                        MiniGlass(item: item, scale: scale)
                            .frame(width: width, height: item.shape.interiorHeight * scale + 4)
                            .zIndex(1)
                        Ellipse()
                            .fill(BrimTheme.color(for: item.judgement))
                            .overlay(Ellipse().stroke(BrimTheme.ink.opacity(0.25), lineWidth: 1))
                            .overlay(
                                Image(systemName: RecapGlyph.symbol(for: item.judgement))
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(BrimTheme.ink.opacity(0.85))
                                    .offset(y: 2)
                            )
                            .frame(width: width + 14, height: 18)
                            .shadow(color: BrimTheme.ink.opacity(0.18), radius: 3, y: 2)
                    }
                    .offset(y: shown ? 0 : 26)
                    .opacity(shown ? 1 : 0)
                    // REVIEW-3 P2-4: the whole row is on the counter within ~0.3 s of the card.
                    .animation(reduceMotion ? nil
                               : BrimTheme.pop(false).delay(0.05 + 0.025 * Double(index)), value: shown)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recap.map { $0.judgement.rawValue }.joined(separator: ", "))
    }
}

/// One glass from its real profile, liquid at the served level, the fill line across it.
struct MiniGlass: View {
    let item: GlassRecap
    /// Points per world point; nil = fit the glass into the box.
    var scale: CGFloat? = nil

    var body: some View {
        Canvas { ctx, size in
            let profile = item.shape.profile
            guard let last = profile.last, last.y > 0 else { return }
            let maxHalf = max(profile.map { $0.x }.max() ?? 1, 1)
            let interior = last.y
            // Fit the glass (interior plus a little headroom for spills) into the box, keeping its aspect.
            let scale = self.scale ?? min(size.height * 0.92 / interior, size.width * 0.5 / maxHalf)
            let cx = size.width / 2
            let floorY = size.height - 1
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + x * scale, y: floorY - y * scale) }

            var outline = Path()
            outline.move(to: pt(-profile[0].x, profile[0].y))
            for p in profile { outline.addLine(to: pt(-p.x, p.y)) }
            for p in profile.reversed() { outline.addLine(to: pt(p.x, p.y)) }
            outline.closeSubpath()

            ctx.fill(outline, with: .color(Color.white.opacity(0.7)))
            // Liquid (and foam) up to the served level, clipped to the glass.
            let level = CGFloat(min(max(item.level, 0), 1)) * interior
            let foamLevel = CGFloat(min(max(item.foamLevel, 0), 1)) * interior
            var clipped = ctx
            clipped.clip(to: outline)
            let liquidRect = CGRect(x: 0, y: floorY - level * scale, width: size.width, height: level * scale + 2)
            clipped.fill(Path(liquidRect), with: .linearGradient(
                Gradient(colors: [Self.color(item.top), Self.color(item.bottom)]),
                startPoint: CGPoint(x: cx, y: floorY - level * scale), endPoint: CGPoint(x: cx, y: floorY)))
            if foamLevel > level + 0.5, let foam = item.foam {
                let foamRect = CGRect(x: 0, y: floorY - foamLevel * scale, width: size.width, height: (foamLevel - level) * scale)
                clipped.fill(Path(foamRect), with: .color(Self.color(foam)))
            }
            // A soft highlight down the left wall: glass, not a flat icon (REVIEW-3 P2-4).
            var gloss = Path()
            let gx = cx - maxHalf * scale * 0.62
            gloss.move(to: CGPoint(x: gx, y: floorY - interior * scale * 0.88))
            gloss.addLine(to: CGPoint(x: gx, y: floorY - interior * scale * 0.18))
            clipped.stroke(gloss, with: .color(Color.white.opacity(0.55)),
                           style: StrokeStyle(lineWidth: max(1.5, 4 * scale), lineCap: .round))
            ctx.stroke(outline, with: .color(BrimTheme.ink.opacity(0.75)), lineWidth: 1.4)
            // Spilled: a drip down the outside.
            if item.judgement == .spill {
                let rim = pt(last.x, interior)
                var drip = Path()
                drip.move(to: rim)
                drip.addLine(to: CGPoint(x: rim.x + 2, y: rim.y + 12))
                ctx.stroke(drip, with: .color(Self.color(item.top)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            // The line, overhanging both walls.
            let lineY = floorY - CGFloat(item.line) * interior * scale
            var line = Path()
            line.move(to: CGPoint(x: cx - maxHalf * scale - 3, y: lineY))
            line.addLine(to: CGPoint(x: cx + maxHalf * scale + 3, y: lineY))
            ctx.stroke(line, with: .color(BrimTheme.ink), lineWidth: 1.6)
        }
        .accessibilityHidden(true)
    }

    static func color(_ c: RGBA) -> Color {
        Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: max(c.a, 0.6))
    }
}
