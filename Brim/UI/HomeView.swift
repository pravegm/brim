import SwiftUI

/// Home (REVIEW-1 P0-2, P1-7, P2-4, P2-7): the wordmark on the clean wall at the top, the attract loop pouring in the
/// middle, and the buttons kept clear of the glass:
/// - a wide canvas (the Duo's flat half): two button columns, left and right of the centre ~220 pt where the glass
///   stands, plus a chalkboard beside the jug carrying the Daily status and lifetime stats;
/// - a narrow phone: one 60 pt row at the very bottom, on the counter front under the glass.
struct HomeView: View {
    @ObservedObject var controller: GameController
    @ObservedObject var store: ProgressStore
    let info: CanvasInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var today: Int { LevelCatalog.dayNumber(for: Date()) }

    /// Width the glass needs clear in the middle of the flat half.
    static let glassClear: CGFloat = 220
    static let columnMin: CGFloat = 170

    private var columnWidth: CGFloat {
        min((info.size.width - Self.glassClear) / 2 - info.sidePad, 230)
    }

    private var usesColumns: Bool { columnWidth >= Self.columnMin }

    var body: some View {
        ZStack(alignment: .topLeading) {
            header
            ChalkboardLayer(hud: controller.hud, store: store, info: info, today: today)
                .opacity(appeared ? 1 : 0)
            if usesColumns {
                columns
            } else {
                bottomRow
            }
        }
        .frame(width: info.size.width, height: info.size.height, alignment: .topLeading)
        .onAppear {
            withAnimation(BrimTheme.pop(reduceMotion).delay(0.05)) { appeared = true }
        }
    }

    // MARK: Top: wordmark on the clean wall, settings

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                BrimWordmark(size: info.hasFold ? 58 : 44)
                Text("Fold to Pour")
                    .font(BrimTheme.text(info.hasFold ? 16 : 14, .heavy))
                    .foregroundStyle(BrimTheme.inkSoft)
                    .padding(.leading, 3)
            }
            Spacer()
            RoundIconButton(systemName: "gearshape.fill", size: 46, accessibility: "Settings") {
                controller.showSettings()
            }
        }
        .padding(.leading, info.sidePad + 4)
        .padding(.trailing, info.sidePad)
        .padding(.top, info.hudTop)
        .frame(width: info.size.width, alignment: .leading)
        .scaleEffect(appeared ? 1 : 0.94, anchor: .topLeading)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Wide: two columns on the flat half, the glass between them

    private var columns: some View {
        let top = info.bottomHalfTop + 14
        let bottom = info.size.height - max(info.insets.bottom, 12) - 8
        return HStack(alignment: .center, spacing: 0) {
            VStack(spacing: 12) {
                playButton(compact: false)
                venuesButton(compact: false)
            }
            .frame(width: columnWidth)
            Spacer(minLength: Self.glassClear)
            VStack(spacing: 12) {
                rushButton(compact: false)
                dailyButton(compact: false)
            }
            .frame(width: columnWidth)
        }
        .padding(.horizontal, info.sidePad)
        .frame(width: info.size.width, height: max(bottom - top, 0))
        .offset(y: top)
        .offset(y: appeared ? 0 : 30)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Narrow: one row at the very bottom

    private var bottomRow: some View {
        let height: CGFloat = 60
        let bottom = info.size.height - max(info.insets.bottom - 10, 8)
        return HStack(spacing: 7) {
            playButton(compact: true)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            rushButton(compact: true).frame(width: 74)
            dailyButton(compact: true).frame(width: 74)
            venuesButton(compact: true).frame(width: 74)
        }
        .padding(.horizontal, max(info.sidePad - 6, 10))
        .frame(width: info.size.width, height: height)
        .offset(y: bottom - height)
        .offset(y: appeared ? 0 : 30)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Buttons

    private func playButton(compact: Bool) -> some View {
        let next = store.data.nextShift
        return TapButton(kind: .primary, height: compact ? 60 : 84, hPad: compact ? 8 : 14,
                         action: { controller.playNextShift() }) {
            HStack(spacing: compact ? 8 : 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: compact ? 18 : 22, weight: .heavy))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Play")
                        .font(BrimTheme.title(compact ? 21 : 26))
                    if let next {
                        Text(compact ? "Shift \(next.venueNumber)-\(next.index)"
                                     : "\(LevelCatalog.title(of: next.venue)) · \(next.index)")
                            .font(BrimTheme.text(compact ? 11 : 12, .bold))
                            .foregroundStyle(BrimTheme.ink.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityLabel("Play \(next.map { GameController.title(for: .shift($0.id)) } ?? "")")
    }

    private func rushButton(compact: Bool) -> some View {
        TapButton(kind: .secondary, height: compact ? 60 : 72, hPad: compact ? 4 : 12,
                  action: { controller.start(mode: .rush) }) {
            if compact {
                smallLabel("Rush", icon: "bolt.fill")
            } else {
                VStack(spacing: 2) {
                    Label("Rush", systemImage: "bolt.fill")
                    Text(store.rushBest > 0 ? "Best \(ShareText.grouped(store.rushBest))" : "Endless")
                        .font(BrimTheme.text(12, .bold))
                        .foregroundStyle(BrimTheme.ink.opacity(0.7))
                }
            }
        }
        .accessibilityLabel(store.rushBest > 0 ? "Rush, best \(store.rushBest)" : "Rush")
    }

    private func dailyButton(compact: Bool) -> some View {
        let streak = store.dailyStreak(today: today)
        return TapButton(kind: .secondary, height: compact ? 60 : 72, hPad: compact ? 4 : 12,
                         action: { controller.playDaily() }) {
            if compact {
                smallLabel(streak > 0 ? "\(streak)🔥" : "Daily", icon: "calendar")
            } else {
                VStack(spacing: 2) {
                    Label("Daily Pour", systemImage: "calendar")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(dailyStatus(streak: streak))
                        .font(BrimTheme.text(12, .bold))
                        .foregroundStyle(BrimTheme.ink.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
        .accessibilityLabel("Daily Pour number \(today)\(streak > 0 ? ", streak \(streak) days" : "")")
    }

    private func venuesButton(compact: Bool) -> some View {
        TapButton(kind: .quiet, height: compact ? 60 : 56, hPad: compact ? 4 : 12,
                  action: { controller.showVenues() }) {
            if compact {
                smallLabel("\(store.totalStars)★", icon: "storefront.fill")
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "storefront.fill")
                    Text("Venues")
                    Spacer(minLength: 2)
                    Image(systemName: "star.fill").foregroundStyle(BrimTheme.goldDeep)
                    Text("\(store.totalStars)")
                        .font(BrimTheme.number(17))
                }
            }
        }
        .accessibilityLabel("Venues, \(store.totalStars) stars")
    }

    private func smallLabel(_ text: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .heavy))
            Text(text)
                .font(BrimTheme.text(13, .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func dailyStatus(streak: Int) -> String {
        let flame = streak > 0 ? " · 🔥\(streak)" : ""
        if let record = store.dailyRecord(day: today) {
            return "Done · \(ShareText.grouped(record.score))\(flame)"
        }
        return "#\(today) · new\(flame)"
    }
}

private extension Level {
    /// 1-based venue number from the id ("2-3" → 2).
    var venueNumber: Int { Int(id.split(separator: "-").first ?? "") ?? 1 }
}

/// Places the chalkboard beside the attract jug in the top half, on the side with room, when there is room (the Duo;
/// narrow phones have none and show no board). The jug's footprint is the union of every pose seen so far (a tipped
/// jug swings its body the other way from the spout), so the board settles after the first pour and never covers it.
struct ChalkboardLayer: View {
    @ObservedObject var hud: HUDState
    @ObservedObject var store: ProgressStore
    let info: CanvasInfo
    let today: Int

    @State private var footprint: CGRect? = nil

    static let size = CGSize(width: 200, height: 176)

    var body: some View {
        ZStack {
            if let spot = spot {
                Chalkboard(store: store, today: today)
                    .frame(width: Self.size.width)
                    .position(spot)
                    .transition(.opacity)
            }
        }
        .frame(width: info.size.width, height: info.size.height)
        .animation(.easeInOut(duration: 0.3), value: spot)
        .onAppear { absorb(hud.anchors) }
        .onChange(of: hud.anchors) { _, anchors in absorb(anchors) }
    }

    private func absorb(_ anchors: PlayAnchors?) {
        guard let jug = anchors?.jug else { return }
        let grown = footprint.map { $0.union(jug) } ?? jug
        // Only republish when it grows by a visible amount.
        if let old = footprint, abs(old.minX - grown.minX) < 6, abs(old.maxX - grown.maxX) < 6,
           abs(old.minY - grown.minY) < 6, abs(old.maxY - grown.maxY) < 6 { return }
        footprint = grown
    }

    private var spot: CGPoint? {
        let top = info.hudTop + HUDMetrics.rowHeight + 40
        let area = CGRect(x: info.sidePad - 4, y: top, width: info.size.width - 2 * (info.sidePad - 4),
                          height: max(info.topHalfHeight - 14 - top, 0))
        let world = footprint ?? CGRect(x: WorldLayout.pivot.x - 120, y: WorldLayout.pivot.y - 130, width: 200, height: 260)
        return CardPlacement.beside(info.mapper.rect(world), size: Self.size, in: area, gap: 12)
    }
}

/// The wall chalkboard (P2-4): today's Daily status, the Daily streak and the lifetime stats.
struct Chalkboard: View {
    @ObservedObject var store: ProgressStore
    let today: Int

    var body: some View {
        let stats = store.data.stats
        let streak = store.dailyStreak(today: today)
        let record = store.dailyRecord(day: today)
        VStack(alignment: .leading, spacing: 6) {
            Text("TODAY")
                .font(BrimTheme.text(11, .heavy))
                .kerning(1.2)
                .foregroundStyle(Color.white.opacity(0.6))
            Text("Daily #\(today)")
                .font(BrimTheme.title(20))
                .foregroundStyle(Color.white.opacity(0.95))
            Text(record.map { "Poured · \(ShareText.grouped($0.score))" } ?? "Not poured yet")
                .font(BrimTheme.text(14, .bold))
                .foregroundStyle(record == nil ? BrimTheme.gold : Color.white.opacity(0.85))
            if streak > 0 {
                Text("🔥 \(streak) day\(streak == 1 ? "" : "s") in a row")
                    .font(BrimTheme.text(13, .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
                .padding(.vertical, 2)
            Text(stats.runs == 0
                 ? "Fill every glass to the line."
                 : "\(ProgressData.litresText(poured: stats.poured)) poured · \(stats.perfects) perfect")
                .font(BrimTheme.text(12, .bold))
                .foregroundStyle(Color.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(brimHex: 0x2F4A3F))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(brimHex: 0xB4613D), lineWidth: 6)
                )
                .shadow(color: BrimTheme.ink.opacity(0.2), radius: 8, y: 4)
        )
        .accessibilityElement(children: .combine)
    }
}
