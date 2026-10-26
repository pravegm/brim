import SwiftUI

/// Home (REVIEW-1 P0-2, P1-7, P2-4, P2-7; REVIEW-2 P1-2): the wordmark on the clean wall at the top, the attract loop
/// pouring in the middle, and the buttons kept clear of every glass. Round 3 centres the pour (glass stop x ≤ 372
/// world) and parks the next glass on the counter at x ≈ 165, so the whole counter above the front edge belongs to
/// the scene: the buttons are ONE row at the very bottom, on the counter front under the glasses, on every device.
/// - the Duo (roomy): a 64 pt row with full labels (Play + the shift, Rush best, Daily number and state, Venues ★),
///   plus a chalkboard beside the jug on the raised half carrying the Daily status and lifetime stats;
/// - a narrow phone: a 60 pt row with short labels.
struct HomeView: View {
    @ObservedObject var controller: GameController
    @ObservedObject var store: ProgressStore
    let info: CanvasInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    /// QA-1 P2-23: re-read every 30 s, so the Daily button rolls over at UTC midnight while Home stays open.
    @State private var today = LevelCatalog.dayNumber(for: Date())
    /// Round 8 (REVIEW-6 #6): the Glass Cabinet sheet is open.
    @State private var showCabinet = false

    /// Wide enough for the full-label row (the Duo's 669 pt).
    static let roomyWidth: CGFloat = 560
    /// How far a glass's coaster reaches below the counter line (world pt).
    static let coasterDepth: CGFloat = 14
    /// REVIEW-3 P2-5: clear space between the lowest coaster and the button row.
    static let coasterClearance: CGFloat = 12

    private var roomy: Bool { info.size.width >= Self.roomyWidth }

    /// Pure (tested): the button row's frame (canvas points), always ≥ 12 pt below the lowest coaster on the counter
    /// (`lowestGlassWorldY`: the lowest glass base, world; a waiting glass may stand a little lower than the counter).
    /// The row may shrink to 52 pt rather than sink into the home-indicator edge.
    static func rowFrame(info: CanvasInfo, roomy: Bool, lowestGlassWorldY: CGFloat = WorldLayout.counter) -> CGRect {
        let preferred: CGFloat = roomy ? 64 : 60
        let bottom = roomy ? info.size.height - max(info.insets.bottom, 12) - 6
                           : info.size.height - max(info.insets.bottom - 10, 8)
        let hardBottom = roomy ? info.size.height - max(info.insets.bottom * 0.5, 6)
                               : info.size.height - max(info.insets.bottom - 14, 6)
        let coasterBottom = info.mapper.y(min(lowestGlassWorldY, WorldLayout.counter) - coasterDepth)
        let minTop = max(coasterBottom + coasterClearance, info.counterY + 10)
        var top = max(bottom - preferred, minTop)
        var height = preferred
        if top + height > hardBottom {
            height = max(hardBottom - top, 52)
            top = min(top, hardBottom - height)
        }
        return CGRect(x: 0, y: top, width: info.size.width, height: height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            header
            ChalkboardLayer(hud: controller.hud, store: store, info: info, today: today)
                .opacity(appeared ? 1 : 0)
            bottomRow
            if showCabinet {
                CabinetSheet(store: store, info: info,
                             onChoose: { controller.chooseVessel($0) },
                             onClose: { showCabinet = false })
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(width: info.size.width, height: info.size.height, alignment: .topLeading)
        .animation(BrimTheme.settle(reduceMotion), value: showCabinet)
        .onAppear {
            withAnimation(BrimTheme.pop(reduceMotion).delay(0.05)) { appeared = true }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                let now = LevelCatalog.dayNumber(for: Date())
                if now != today { today = now }
            }
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
            HStack(spacing: 10) {
                // Round 8 (REVIEW-6 #6): the Glass Cabinet (vessels for Rush and Practice, unlocked by crowns).
                RoundIconButton(systemName: "cabinet.fill", size: 46, accessibility: "Glass Cabinet") {
                    showCabinet = true
                }
                RoundIconButton(systemName: "gearshape.fill", size: 46, accessibility: "Settings") {
                    controller.showSettings()
                }
            }
        }
        .padding(.leading, info.sidePad + 4)
        .padding(.trailing, info.sidePad)
        .padding(.top, info.hudTop)
        .frame(width: info.size.width, alignment: .leading)
        .scaleEffect(appeared ? 1 : 0.94, anchor: .topLeading)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: One row at the very bottom (both devices)

    /// The lowest glass base on the counter (world): the waiting glass stands ~10 pt nearer the player than the counter
    /// line (Scene's waiting look, REVIEW-3 P1-1). A constant, so the row never jumps.
    static let lowestGlassWorldY: CGFloat = WorldLayout.counter - 10

    private var bottomRow: some View {
        let frame = Self.rowFrame(info: info, roomy: roomy, lowestGlassWorldY: Self.lowestGlassWorldY)
        let h = frame.height
        return Group {
            if roomy {
                HStack(spacing: 8) {
                    playButton(compact: false, height: h)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                    rushButton(compact: false, height: h).frame(width: 132)
                    dailyButton(compact: false, height: h).frame(width: 142)
                    venuesButton(compact: false, height: h).frame(width: 112)
                }
                .padding(.horizontal, info.sidePad)
            } else {
                HStack(spacing: 7) {
                    playButton(compact: true, height: h)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                    rushButton(compact: true, height: h).frame(width: 74)
                    dailyButton(compact: true, height: h).frame(width: 74)
                    venuesButton(compact: true, height: h).frame(width: 74)
                }
                .padding(.horizontal, max(info.sidePad - 6, 10))
            }
        }
        .frame(width: info.size.width, height: frame.height)
        .offset(y: frame.minY)
        .offset(y: appeared ? 0 : 30)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Buttons

    private func playButton(compact: Bool, height: CGFloat) -> some View {
        let next = store.data.nextShift
        return TapButton(kind: .primary, height: height, hPad: compact ? 8 : 14,
                         action: { controller.playNextShift() }) {
            HStack(spacing: compact ? 8 : 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: compact ? 18 : 20, weight: .heavy))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Play")
                        .font(BrimTheme.title(compact ? 21 : 23))
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

    private func rushButton(compact: Bool, height: CGFloat) -> some View {
        TapButton(kind: .secondary, height: height, hPad: compact ? 4 : 8,
                  action: { controller.start(mode: .rush) }) {
            if compact {
                smallLabel("Rush", icon: "bolt.fill")
            } else {
                twoLine("Rush", icon: "bolt.fill",
                        detail: store.rushBest > 0 ? "Best \(ShareText.grouped(store.rushBest))" : "Endless")
            }
        }
        .accessibilityLabel(store.rushBest > 0 ? "Rush, best \(store.rushBest)" : "Rush")
    }

    private func dailyButton(compact: Bool, height: CGFloat) -> some View {
        let streak = store.dailyStreak(today: today)
        return TapButton(kind: .secondary, height: height, hPad: compact ? 4 : 8,
                         action: { controller.playDaily() }) {
            if compact {
                // REVIEW-2 P2-10: the number and the state on the phone too ("#297", "#297 ✓", "#297 🔥3").
                smallLabel(Self.compactDailyText(today: today, done: store.dailyRecord(day: today) != nil,
                                                 streak: streak),
                           icon: "calendar")
            } else {
                twoLine("Daily", icon: "calendar", detail: dailyStatus(streak: streak))
            }
        }
        .accessibilityLabel("Daily Pour number \(today)\(streak > 0 ? ", streak \(streak) days" : "")")
    }

    /// Pure (tested): the phone's Daily button text.
    static func compactDailyText(today: Int, done: Bool, streak: Int) -> String {
        if streak > 1 { return "#\(today) 🔥\(streak)" }
        return done ? "#\(today) ✓" : "#\(today)"
    }

    private func venuesButton(compact: Bool, height: CGFloat) -> some View {
        TapButton(kind: .quiet, height: height, hPad: compact ? 4 : 8,
                  action: { controller.showVenues() }) {
            if compact {
                smallLabel("\(store.totalStars)★", icon: "storefront.fill")
            } else {
                twoLine("Venues", icon: "storefront.fill", detail: "★ \(store.totalStars)")
            }
        }
        .accessibilityLabel("Venues, \(store.totalStars) stars")
    }

    /// A roomy button's label: icon + title, a small detail line under it.
    private func twoLine(_ title: String, icon: String, detail: String) -> some View {
        VStack(spacing: 2) {
            Label(title, systemImage: icon)
                .font(BrimTheme.text(18, .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(BrimTheme.text(12, .bold))
                .foregroundStyle(BrimTheme.ink.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
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
