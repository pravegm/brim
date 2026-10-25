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
            BrimTheme.cream.opacity(0.97)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    ForEach(Array(VenueID.allCases.enumerated()), id: \.element) { index, venue in
                        VenueCard(venue: venue, store: store, onPick: { level in controller.start(mode: .shift(level.id)) })
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 30)
                            .animation(BrimTheme.pop(reduceMotion).delay(reduceMotion ? 0 : 0.04 * Double(index)),
                                       value: appeared)
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
        .onAppear { appeared = true }
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
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").foregroundStyle(BrimTheme.goldDeep)
                            Text("\(store.data.starsEarned(in: venue))/\(levels.count * 3)")
                                .font(BrimTheme.number(13))
                                .foregroundStyle(BrimTheme.ink)
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
                                    accent: accent) {
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
        case .conveyor: return "Moving glasses"
        case .potionShop: return "Tiny vials, fading lines"
        case .sandBar: return "Sand waits, then rushes"
        }
    }
}

private struct ShiftBubble: View {
    let level: Level
    let stars: Int
    let playable: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button {
            FeedbackDirector.shared.uiTap()
            action()
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(playable ? accent : BrimTheme.creamDeep)
                        .overlay(Circle().stroke(BrimTheme.ink.opacity(playable ? 0.12 : 0.06), lineWidth: 2))
                        .shadow(color: BrimTheme.ink.opacity(playable ? 0.15 : 0), radius: 4, y: 3)
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
                .frame(width: 54, height: 54)
                StarRow(filled: stars, size: 11, spacing: 1)
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Shift \(level.index), \(stars) stars\(playable ? "" : ", locked")")
    }
}
