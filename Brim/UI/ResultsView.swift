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
        if let onFile = outcome.dailyOnFile {
            return ShareText.daily(day: day, judgements: onFile.judgements, score: onFile.score)
        }
        return ShareText.daily(day: day, judgements: result.judgements, score: result.score)
    }

    /// Pure (tested): "Flawless" only when every glass was Perfect. A failed shift says what ended it (REVIEW-2 P2-6:
    /// never "So close" on a three-spill run).
    static func headline(for result: RunResult, dailyOnFile: Bool) -> String {
        switch result.mode {
        case .shift:
            if !result.judgements.isEmpty && result.judgements.allSatisfy({ $0 == .perfect }) { return "Flawless shift!" }
            if result.stars >= 3 { return "Great shift!" }
            if result.cleared { return "Shift cleared" }
            let spills = result.judgements.filter { $0 == .spill }.count
            if spills >= 3 { return "Shift over — \(spills) spills" }
            return "Not quite"
        case .daily:
            return dailyOnFile ? "Practice pour" : "Daily poured"
        case .rush, .practice:
            return "Last call!"
        }
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
                LinearGradient(colors: [BrimTheme.cream, BrimTheme.peach.opacity(0.95)],
                               startPoint: .top, endPoint: .bottom)
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
            Text(Self.headline(for: result, dailyOnFile: outcome.dailyOnFile != nil))
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
                Text(ShareText.grouped(shownScore))
                    .font(BrimTheme.number(info.isCompact ? 44 : 52))
                    .foregroundStyle(BrimTheme.ink)
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
                    RecapRow(recap: summary.recap, maxCount: info.size.width < 420 ? 8 : 10)
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
            return outcome.dailyCounted ? "Today's scored pour. New glasses tomorrow." : nil
        }
        if case .rush = result.mode, !outcome.isNewBest, outcome.previousBest > 0 {
            return "Best \(ShareText.grouped(outcome.previousBest))"
        }
        return nil
    }

    /// "Next unlock: 3 more ★ for Milkshake Diner" (nothing when it was just unlocked or all are open).
    private var unlockLine: String? {
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

    var body: some View {
        let shown = Array(recap.suffix(maxCount))
        let hidden = recap.count - shown.count
        return HStack(alignment: .bottom, spacing: 6) {
            if hidden > 0 {
                Text("+\(hidden)")
                    .font(BrimTheme.text(12, .heavy))
                    .foregroundStyle(BrimTheme.inkSoft)
                    .padding(.bottom, 14)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 4) {
                    MiniGlass(item: item)
                        .frame(width: 30, height: 40)
                    Circle()
                        .fill(BrimTheme.color(for: item.judgement))
                        .frame(width: 8, height: 8)
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

/// The served glasses standing in a row on the counter, all at one scale (≈ 60 % of the play size, smaller if the
/// row or the height needs it), each at its served level against its line, on a coaster in its verdict colour.
struct CounterRecap: View {
    let recap: [GlassRecap]
    /// Slide in (one after another) once the results have appeared.
    let shown: Bool
    var maxCount: Int = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pure (tested): one scale for the whole row so it fits `size` (glass interiors only; coasters and gaps added).
    static func rowScale(_ items: [GlassRecap], size: CGSize, spacing: CGFloat, preferred: CGFloat = 0.6) -> CGFloat {
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
                            .frame(width: width + 14, height: 12)
                            .shadow(color: BrimTheme.ink.opacity(0.18), radius: 3, y: 2)
                    }
                    .offset(y: shown ? 0 : 26)
                    .opacity(shown ? 1 : 0)
                    .animation(reduceMotion ? nil
                               : BrimTheme.pop(false).delay(0.35 + 0.07 * Double(index)), value: shown)
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
