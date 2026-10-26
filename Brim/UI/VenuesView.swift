import SwiftUI

/// Venue and shift select: one card per venue (stars, lock state), shifts as numbered bubbles with their stars.
struct VenuesView: View {
    @ObservedObject var controller: GameController
    @ObservedObject var store: ProgressStore
    let info: CanvasInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .top) {
            BrimTheme.cream
            if info.hasFold {
                duoPages
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                        ForEach(Array(VenueID.allCases.enumerated()), id: \.element) { index, venue in
                            card(venue, index: index)
                        }
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, info.insets.top + 8)
                    .padding(.bottom, info.insets.bottom + 24)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { appeared = true }
    }

    private func card(_ venue: VenueID, index: Int) -> some View {
        VenueCard(venue: venue, store: store, onPick: { level in controller.start(mode: .shift(level.id)) })
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 30)
            .animation(BrimTheme.pop(reduceMotion).delay(reduceMotion ? 0 : 0.04 * Double(index)), value: appeared)
    }

    // MARK: Duo (REVIEW-3 P1-3): nothing on the fold

    /// Round 6 (decision 4): the venue card's crown count, "3/8", shown once a crown is earned or every star of the
    /// venue is in (then the crowns are what's left to chase). nil otherwise. Pure; tested.
    static func crownLine(crowns: Int, shifts: Int, stars: Int) -> String? {
        guard shifts > 0, crowns > 0 || stars >= shifts * 3 else { return nil }
        return "\(min(max(crowns, 0), shifts))/\(shifts)"
    }

    /// Round 8 (REVIEW-6 N2): the venue's best Perfects against its glasses, "41/52" beside the crowns. nil until a
    /// Perfect is on file. Pure; tested.
    static func perfectLine(best: Int, glasses: Int) -> String? {
        guard glasses > 0, best > 0 else { return nil }
        return "\(min(best, glasses))/\(glasses)"
    }

    /// Round 8 (REVIEW-6 N2): how much of a 3★ bubble's cyan arc is drawn: its best Perfects of its glasses. 0 = no
    /// arc (under 3★, crowned, nothing on file). Pure; tested.
    static func crownArc(stars: Int, crowned: Bool, bestPerfects: Int, glasses: Int) -> Double {
        guard stars >= 3, !crowned, glasses > 0, bestPerfects > 0 else { return 0 }
        return min(Double(bestPerfects) / Double(glasses), 1)
    }

    /// Pure (tested): venues two to a screen, one per half (the first screen's top half also holds the header).
    static func duoPages(_ venues: [VenueID]) -> [[VenueID]] {
        var pages: [[VenueID]] = []
        var i = 0
        while i < venues.count {
            pages.append(Array(venues[i..<min(i + 2, venues.count)]))
            i += 2
        }
        return pages
    }

    /// Pure (tested): the two card slots of one screen (canvas y, from the top): the raised half above the crease and
    /// the flat half below it, each ≥ 8 pt clear of the band.
    static func duoSlots(info: CanvasInfo) -> (top: ClosedRange<CGFloat>, bottom: ClosedRange<CGFloat>) {
        let topStart = info.insets.top + 8
        let topEnd = max(info.topHalfHeight - 8, topStart)
        let bottomStart = info.bottomHalfTop + 8
        let bottomEnd = max(info.size.height - max(info.insets.bottom, 8), bottomStart)
        return (topStart...topEnd, bottomStart...bottomEnd)
    }

    /// One screen per two venues, paged: the scroll always comes to rest on a screen boundary, so the crease always
    /// falls in the gap between the two cards and no shift button ever sits on the fold.
    private var duoPages: some View {
        let slots = Self.duoSlots(info: info)
        let pages = Self.duoPages(VenueID.allCases)
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, venues in
                    VStack(spacing: 0) {
                        VStack(spacing: 14) {
                            if pageIndex == 0 { header }
                            if let first = venues.first {
                                card(first, index: pageIndex * 2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.top, slots.top.lowerBound)
                        .frame(height: slots.top.upperBound, alignment: .top)
                        Color.clear
                            .frame(height: max(slots.bottom.lowerBound - slots.top.upperBound, 0))
                        VStack(spacing: 0) {
                            if venues.count > 1 {
                                card(venues[1], index: pageIndex * 2 + 1)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(height: max(info.size.height - slots.bottom.lowerBound, 0), alignment: .top)
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: 560)
                    .frame(width: info.size.width, height: info.size.height)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundIconButton(systemName: "chevron.left", size: 46, accessibility: "Back") {
                controller.showHome()
            }
            Text("Venues")
                .font(BrimTheme.title(32))
                .foregroundStyle(BrimTheme.ink)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "star.fill").foregroundStyle(BrimTheme.goldDeep)
                Text("\(store.totalStars)").font(BrimTheme.number(22))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(BrimTheme.card))
        }
        .padding(.top, 6)
    }
}

private struct VenueCard: View {
    let venue: VenueID
    @ObservedObject var store: ProgressStore
    let onPick: (Level) -> Void

    @State private var lockedNote: String? = nil

    private var levels: [Level] { LevelCatalog.levels(in: venue) }
    private var unlocked: Bool { store.isUnlocked(venue) }
    private var accent: Color { BrimTheme.color(for: venue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(accent.opacity(unlocked ? 1 : 0.35))
                    Image(systemName: unlocked ? BrimTheme.symbol(for: venue) : "lock.fill")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(BrimTheme.ink.opacity(unlocked ? 0.85 : 0.5))
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(venue == .sandBar && !unlocked ? "Secret venue" : LevelCatalog.title(of: venue))
                        .font(BrimTheme.title(20))
                        .foregroundStyle(BrimTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(subtitle)
                        .font(BrimTheme.text(13, .bold))
                        .foregroundStyle(BrimTheme.inkSoft)
                    if unlocked {
                        HStack(spacing: 10) {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill").foregroundStyle(BrimTheme.goldDeep)
                                Text("\(store.data.starsEarned(in: venue))/\(levels.count * 3)")
                                    .font(BrimTheme.number(13))
                                    .foregroundStyle(BrimTheme.ink)
                            }
                            // Round 6 (decision 4): the crown count, once there is one or every star is in.
                            if let crowns = VenuesView.crownLine(crowns: store.data.crownsEarned(in: venue),
                                                                 shifts: levels.count,
                                                                 stars: store.data.starsEarned(in: venue)) {
                                HStack(spacing: 3) {
                                    Image(systemName: "crown.fill").foregroundStyle(BrimTheme.goldDeep)
                                    Text(crowns)
                                        .font(BrimTheme.number(13))
                                        .foregroundStyle(BrimTheme.ink)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(store.data.crownsEarned(in: venue)) of \(levels.count) flawless crowns")
                            }
                            // Round 8 (REVIEW-6 N2): the best Perfects per shift, summed: how far the crowns are.
                            let earned = store.data.perfectsEarned(in: venue)
                            if let perfects = VenuesView.perfectLine(best: earned.best, glasses: earned.glasses) {
                                HStack(spacing: 3) {
                                    Image(systemName: "sparkle").foregroundStyle(BrimTheme.cyan)
                                    Text(perfects)
                                        .font(BrimTheme.number(13))
                                        .foregroundStyle(BrimTheme.ink)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Best Perfects \(earned.best) of \(earned.glasses) glasses")
                            }
                        }
                        .font(.system(size: 11, weight: .heavy))
                        .padding(.top, 1)
                    }
                }
                Spacer(minLength: 4)
            }
            if unlocked && !levels.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(levels) { level in
                        ShiftBubble(level: level, stars: store.stars(for: level.id), playable: store.isPlayable(level),
                                    accent: accent, crowned: store.hasCrown(level.id),
                                    bestPerfects: store.bestPerfects(for: level.id)) {
                            if store.isPlayable(level) {
                                onPick(level)
                            } else {
                                lockedNote = "Shift \(level.index) · \(level.title): earn a star on shift \(max(level.index - 1, 1)) first."
                            }
                        }
                    }
                }
                if let lockedNote {
                    Label(lockedNote, systemImage: "lock.fill")
                        .font(BrimTheme.text(13, .bold))
                        .foregroundStyle(BrimTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lockedNote)
        .brimCard(padding: 16)
        .opacity(unlocked ? 1 : 0.82)
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String {
        if unlocked { return teaches }
        if venue == .sandBar { return "Three-star every shift to find it" }
        let need = LevelCatalog.starsToUnlock(venue)
        let missing = max(need - store.totalStars, 0)
        return "★ \(need) to unlock · \(missing) to go"
    }

    private var teaches: String {
        switch venue {
        case .lemonadeStand: return "Pour to the line"
        case .sodaFountain: return "Foam: pour slow, then top up"
        case .milkshakeDiner: return "Thick drinks: stop early"
        // REVIEW-5 §1 P2: instructions, not nouns.
        case .conveyor: return "Moving glasses: pour early"
        case .potionShop: return "Fading lines: remember the mark"
        case .sandBar: return "Sand sticks, then slides"
        }
    }
}

private struct ShiftBubble: View {
    let level: Level
    let stars: Int
    let playable: Bool
    let accent: Color
    /// Round 6: the Flawless crown (every glass Perfect): a cyan ring and a crown on the bubble.
    var crowned: Bool = false
    /// Round 8 (REVIEW-6 N2): the most Perfects poured in one run of this shift.
    var bestPerfects: Int = 0
    let action: () -> Void

    /// The thin cyan arc on a 3★ bubble: how close the shift is to its crown.
    private var arc: Double {
        playable ? VenuesView.crownArc(stars: stars, crowned: crowned, bestPerfects: bestPerfects,
                                       glasses: level.orders.count) : 0
    }

    var body: some View {
        Button {
            FeedbackDirector.shared.uiTap()
            action()
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(playable ? accent : BrimTheme.creamDeep)
                        .overlay(Circle().stroke(crowned ? BrimTheme.cyan : BrimTheme.ink.opacity(playable ? 0.12 : 0.06),
                                                 lineWidth: crowned ? 3.5 : 2))
                        .overlay {
                            if arc > 0 {
                                Circle()
                                    .trim(from: 0, to: CGFloat(arc))
                                    .stroke(BrimTheme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                        }
                        .shadow(color: BrimTheme.ink.opacity(playable ? 0.15 : 0), radius: 4, y: 3)
                    if crowned && playable {
                        CrownMark(size: 20)
                            .offset(x: 5, y: -5)
                    }
                }
                .frame(width: 54, height: 54)
                .overlay {
                    if playable {
                        Text("\(level.index)")
                            .font(BrimTheme.number(22))
                            .foregroundStyle(BrimTheme.ink)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(BrimTheme.inkFaint)
                    }
                }
                StarRow(filled: stars, size: 11, spacing: 1)
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Shift \(level.index), \(stars) stars\(crowned ? ", flawless crown" : "")"
                            + "\(arc > 0 ? ", best \(bestPerfects) of \(level.orders.count) Perfect" : "")"
                            + "\(playable ? "" : ", locked")")
    }
}
