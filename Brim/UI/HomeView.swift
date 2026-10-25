import SwiftUI

/// Home: the wordmark and lifetime stats on the top half (it faces the player), the big buttons on the bottom half
/// (it lies flat, like a keyboard). The attract loop (practice + autopilot) keeps pouring behind, through the gap.
struct HomeView: View {
    @ObservedObject var controller: GameController
    @ObservedObject var store: ProgressStore
    let info: CanvasInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var today: Int { LevelCatalog.dayNumber(for: Date()) }

    var body: some View {
        DuoSplit(info: info) {
            top
        } bottom: {
            bottom
        }
        .onAppear {
            withAnimation(BrimTheme.pop(reduceMotion).delay(0.05)) { appeared = true }
        }
    }

    // MARK: Top half

    private var top: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    BrimWordmark(size: info.isCompact ? 58 : 72)
                    Text("Fold to Pour")
                        .font(BrimTheme.text(17, .heavy))
                        .foregroundStyle(BrimTheme.inkSoft)
                        .padding(.leading, 4)
                }
                .padding(.leading, 22)
                .padding(.top, 14)
                Spacer()
                RoundIconButton(systemName: "gearshape.fill", accessibility: "Settings") {
                    controller.showSettings()
                }
                .padding(.trailing, 18)
                .padding(.top, 16)
            }
            .scaleEffect(appeared ? 1 : 0.92, anchor: .topLeading)
            .opacity(appeared ? 1 : 0)
            Spacer(minLength: 8)
            statsLine
                .padding(.horizontal, 22)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statsLine: some View {
        let stats = store.data.stats
        let text: String
        if stats.runs == 0 {
            text = "Fill every glass to the line."
        } else {
            text = "\(ProgressData.litresText(poured: stats.poured)) poured · \(stats.perfects) perfect · best streak \(stats.bestStreak)"
        }
        return Text(text)
            .font(BrimTheme.text(14, .bold))
            .foregroundStyle(BrimTheme.ink.opacity(0.75))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(BrimTheme.card.opacity(0.85)))
    }

    // MARK: Bottom half

    private var bottom: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            playButton
            HStack(spacing: 12) {
                TapButton(kind: .secondary, height: 64, action: { controller.start(mode: .rush) }) {
                    VStack(spacing: 2) {
                        Label("Rush", systemImage: "bolt.fill")
                        Text(store.rushBest > 0 ? "Best \(ShareText.grouped(store.rushBest))" : "Endless")
                            .font(BrimTheme.text(12, .bold))
                            .foregroundStyle(BrimTheme.ink.opacity(0.7))
                    }
                }
                TapButton(kind: .secondary, height: 64, action: { controller.playDaily() }) {
                    VStack(spacing: 2) {
                        Label("Daily Pour", systemImage: "calendar")
                        Text(dailyStatus)
                            .font(BrimTheme.text(12, .bold))
                            .foregroundStyle(BrimTheme.ink.opacity(0.7))
                    }
                }
            }
            TapButton(kind: .quiet, height: 52, action: { controller.showVenues() }) {
                HStack(spacing: 8) {
                    Image(systemName: "storefront.fill")
                    Text("Venues")
                    Spacer(minLength: 4)
                    Image(systemName: "star.fill").foregroundStyle(BrimTheme.goldDeep)
                    Text("\(store.totalStars)")
                        .font(BrimTheme.number(18))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .frame(maxWidth: 520)
        .offset(y: appeared ? 0 : 40)
        .opacity(appeared ? 1 : 0)
    }

    private var playButton: some View {
        let next = store.data.nextShift
        return TapButton(kind: .primary, height: 76, action: { controller.playNextShift() }) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 24, weight: .heavy))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Play")
                        .font(BrimTheme.title(26))
                    if let next {
                        Text("\(LevelCatalog.title(of: next.venue)) · Shift \(next.index)")
                            .font(BrimTheme.text(13, .bold))
                            .foregroundStyle(BrimTheme.ink.opacity(0.75))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
        }
    }

    private var dailyStatus: String {
        if let record = store.dailyRecord(day: today) {
            return "Done · \(ShareText.grouped(record.score))"
        }
        return "#\(today) · new"
    }
}
