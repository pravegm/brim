import SwiftUI

// MARK: - Book pose (landscape canvas on a Duo)

/// Full-screen card for a Duo whose inner canvas is landscape (book pose): the game holds until the phone is turned so
/// the fold runs side to side (ROUND-2 decision 2, REVIEW-1 P0-7). ViewThatFits: drawing beside the text when the
/// canvas is wide, stacked when it isn't, so the copy never breaks into a one-word column.
struct StandUpCard: View {
    var insets: EdgeInsets = EdgeInsets()
    let onTurnScreen: () -> Void
    let onPlayWithTouch: () -> Void

    /// The fold of a Duo in book pose runs down the middle of the canvas (40 pt band). Content keeps ≥ 24 pt clear.
    static let creaseHalf: CGFloat = 20
    static let creaseClear: CGFloat = 24

    /// Pure (tested): a Duo inner display in book pose, where the card splits into one column per page.
    static func splitsOnFold(_ size: CGSize) -> Bool {
        size.width > size.height && PoseRule.looksLikeDuoInner(size)
    }

    var body: some View {
        ZStack {
            // Opaque (REVIEW-3 P2-3): the paused scene never shows through the card.
            BrimTheme.cream
                .ignoresSafeArea()
            LinearGradient(colors: [BrimTheme.cream, BrimTheme.peach.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            GeometryReader { geo in
                if Self.splitsOnFold(geo.size) {
                    bookPages(geo.size)
                } else {
                    flowing
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .ignoresSafeArea()
        }
    }

    /// Book pose on a Duo (REVIEW-2 P2-7): the drawing on the left page, the words and buttons on the right page,
    /// nothing within 24 pt of the vertical fold.
    /// REVIEW-3 P2-6: each column is centred in its page with ≥ 32 pt margins (the text no longer runs to the edge).
    static let pageMargin: CGFloat = 32

    private func bookPages(_ size: CGSize) -> some View {
        let page = max(size.width / 2 - Self.creaseHalf - Self.creaseClear, 0)
        let leftInner = max(page - Self.pageMargin - insets.leading - Self.pageMargin, 0)
        let rightInner = max(page - Self.pageMargin - insets.trailing - Self.pageMargin, 0)
        let drawing = min(240, leftInner, max(size.height - 80, 120))
        return HStack(spacing: 0) {
            TurnPhoneDrawing()
                .frame(width: drawing, height: drawing)
                .frame(width: leftInner, height: size.height)
                .padding(.leading, Self.pageMargin + insets.leading)
                .padding(.trailing, Self.pageMargin)
            Color.clear
                .frame(width: 2 * (Self.creaseHalf + Self.creaseClear), height: size.height)
            ScrollView(showsIndicators: false) {
                copy
                    .frame(maxWidth: min(rightInner, 400), alignment: .leading)
                    .padding(.vertical, 24)
                    .frame(width: rightInner)
                    .frame(minHeight: max(size.height - insets.top - insets.bottom, 0))
            }
            .frame(width: rightInner, height: max(size.height - insets.top - insets.bottom, 0))
            .padding(.leading, Self.pageMargin)
            .padding(.trailing, Self.pageMargin + insets.trailing)
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
    }

    private var flowing: some View {
        ViewThatFits(in: .horizontal) {
                HStack(spacing: 36) {
                    TurnPhoneDrawing()
                        .frame(width: 220, height: 220)
                    copy
                        .frame(minWidth: 300, maxWidth: 440, alignment: .leading)
                }
                .padding(28)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        TurnPhoneDrawing()
                            .frame(width: 190, height: 190)
                        copy
                            .frame(minWidth: 280, maxWidth: 440, alignment: .leading)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Turn me so the fold runs side to side, then lay me flat.")
                .font(BrimTheme.title(28))
                .foregroundStyle(BrimTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("The top half holds the jug, the bottom half is the counter. Lay it flat, then lift the top half to pour.")
                .font(BrimTheme.text(16))
                .foregroundStyle(BrimTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            // Side by side when both labels fit whole, else stacked (REVIEW-2 P1-8: never "Turn the scre…").
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    turnButton
                    touchButton
                }
                VStack(spacing: 10) {
                    turnButton
                    touchButton
                }
            }
            .frame(maxWidth: 420)
            .padding(.top, 4)
        }
    }

    private var turnButton: some View {
        TapButton(kind: .primary, height: 52, action: onTurnScreen) {
            Label("Turn the screen", systemImage: "rotate.right.fill")
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var touchButton: some View {
        TapButton(kind: .quiet, height: 52, action: onPlayWithTouch) {
            Label("Use touch", systemImage: "hand.draw.fill")
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// A Duo seen from above: it turns from book pose (fold running up and down) to the fold running side to side, then
/// its top half (the jug) lifts while the bottom half (the glass) stays flat on the table. On a loop; still under
/// Reduce Motion.
struct TurnPhoneDrawing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Demo captures hold the clearest moment (turned, top half lifted: the tabletop pose) instead of a random
    /// mid-turn frame (REVIEW-3 P2-6).
    private var still: Bool { DemoConfig.current != nil }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || still)) { context in
            let t = reduceMotion ? 1.6
                : (still ? 3.0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.4))
            let turn = Self.ease(min(max((t - 0.3) / 0.9, 0), 1))                 // 0 = book, 1 = fold across
            let liftIn = Self.ease(min(max((t - 1.8) / 0.8, 0), 1))
            let liftOut = Self.ease(min(max((t - 3.4) / 0.7, 0), 1))
            let lift = reduceMotion ? 0 : liftIn * (1 - liftOut)                    // top half lifting off the table
            ZStack {
                Ellipse()
                    .fill(BrimTheme.ink.opacity(0.08))
                    .frame(width: 200, height: 200)
                VStack(spacing: 0) {
                    half(top: true)
                        .rotation3DEffect(.degrees(48 * lift), axis: (x: 1, y: 0, z: 0), anchor: .bottom,
                                          perspective: 0.5)
                        .zIndex(1)
                    Rectangle()
                        .fill(BrimTheme.ink.opacity(0.55))
                        .frame(width: 112, height: 3)
                    half(top: false)
                }
                .frame(width: 112, height: 163)
                .rotationEffect(.degrees(-90 * (1 - turn)))
            }
        }
        .accessibilityHidden(true)
    }

    private static func ease(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    /// One half of the inner display: the top half has the camera dot and the jug, the bottom half the glass.
    private func half(top: Bool) -> some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: top ? 18 : 3, bottomLeadingRadius: top ? 3 : 18,
                                   bottomTrailingRadius: top ? 3 : 18, topTrailingRadius: top ? 18 : 3,
                                   style: .continuous)
                .fill(BrimTheme.ink)
            UnevenRoundedRectangle(topLeadingRadius: top ? 13 : 2, bottomLeadingRadius: top ? 2 : 13,
                                   bottomTrailingRadius: top ? 2 : 13, topTrailingRadius: top ? 13 : 2,
                                   style: .continuous)
                .fill(top ? BrimTheme.cream : BrimTheme.mint)
                .padding(5)
            if top {
                Circle()
                    .fill(BrimTheme.ink)
                    .frame(width: 6, height: 6)
                    .offset(y: -30)
                JugGlyph()
                    .fill(Color(brimHex: 0x2BA59A))
                    .frame(width: 34, height: 34)
                    .offset(x: -6, y: 8)
            } else {
                TumblerShape()
                    .fill(BrimTheme.lemonade)
                    .overlay(TumblerShape().stroke(BrimTheme.ink.opacity(0.6), lineWidth: 1.5))
                    .frame(width: 24, height: 30)
                    .offset(x: 8, y: -4)
            }
        }
        .frame(width: 112, height: 80)
    }
}

/// A little pitcher: round belly, a spout at the upper right, a handle on the left.
struct JugGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        // Body
        p.move(to: CGPoint(x: x + w * 0.30, y: y + h * 0.10))
        p.addLine(to: CGPoint(x: x + w * 0.78, y: y + h * 0.10))
        p.addLine(to: CGPoint(x: x + w * 0.98, y: y + h * 0.02))       // spout tip
        p.addLine(to: CGPoint(x: x + w * 0.84, y: y + h * 0.24))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.74, y: y + h * 0.98), control: CGPoint(x: x + w * 0.98, y: y + h * 0.70))
        p.addLine(to: CGPoint(x: x + w * 0.34, y: y + h * 0.98))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.30, y: y + h * 0.10), control: CGPoint(x: x + w * 0.10, y: y + h * 0.60))
        p.closeSubpath()
        // Handle
        p.move(to: CGPoint(x: x + w * 0.30, y: y + h * 0.22))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.24, y: y + h * 0.66), control: CGPoint(x: x - w * 0.06, y: y + h * 0.40))
        p.addLine(to: CGPoint(x: x + w * 0.27, y: y + h * 0.56))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.30, y: y + h * 0.32), control: CGPoint(x: x + w * 0.10, y: y + h * 0.42))
        p.closeSubpath()
        return p
    }
}

// MARK: - Book pose with touch (DUO-AUDIT M2)

/// The left-hand page while the game plays by touch on the right-hand page in book pose (`PoseRule.bookPage`): a quiet
/// panel that says how to get the hinge back, never within 24 pt of the vertical fold, and no drag layer.
struct BookTouchPanel: View {
    /// The right page's left edge (the fold's trailing edge, 496 pt on the Duo).
    let pageMinX: CGFloat
    var insets: EdgeInsets = EdgeInsets()
    let onTurnScreen: () -> Void

    /// Width of the panel's column: the page left of the fold (40 pt band, 24 pt clear), less a page margin each side
    /// and the leading inset. 368 pt on the Duo. Pure.
    static func columnWidth(pageMinX: CGFloat, leading: CGFloat) -> CGFloat {
        max(pageMinX - 2 * StandUpCard.creaseHalf - StandUpCard.creaseClear - 2 * StandUpCard.pageMargin - leading, 0)
    }

    var body: some View {
        let column = Self.columnWidth(pageMinX: pageMinX, leading: insets.leading)
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [BrimTheme.cream, BrimTheme.peach.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 14) {
                TurnPhoneDrawing()
                    .frame(width: 200, height: 200)
                    .scaleEffect(0.66)
                    .frame(width: 132, height: 132)
                Text("Turn me and lay me flat to pour with the hinge.")
                    .font(BrimTheme.title(24))
                    .foregroundStyle(BrimTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Touch play is on: drag up on the right page to pour.", systemImage: "hand.draw.fill")
                    .font(BrimTheme.text(15, .bold))
                    .foregroundStyle(BrimTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                TapButton(kind: .primary, height: 52, action: onTurnScreen) {
                    Label("Turn the screen", systemImage: "rotate.right.fill")
                        .lineLimit(1)
                        .fixedSize()
                }
                .fixedSize()
                .padding(.top, 4)
            }
            .frame(width: column, alignment: .leading)
            .frame(maxHeight: .infinity)
            .padding(.leading, StandUpCard.pageMargin + insets.leading)
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
        }
        .frame(width: pageMinX)
    }
}

// MARK: - Cover display / shut, and windows too small to pour in

/// The calm card on the cover display (or while the Duo is shut): today's Daily status, best Rush, "Open me to pour".
/// DUO-AUDIT M3: it says when a run is paused underneath ("Open me to carry on", with the run and the glass), and
/// "Pour here with touch" plays on the cover display itself. DUO-AUDIT M1: the same card, titled "Make Brim full screen
/// to pour", stands in for a multitasking window too small for the counter (`DevicePose.cramped`).
struct CoverView: View {
    enum Kind: String, Equatable { case cover, cramped }

    @ObservedObject var store: ProgressStore
    @ObservedObject var controller: GameController
    @ObservedObject var hud: HUDState
    var kind: Kind = .cover
    var insets: EdgeInsets = EdgeInsets()

    private var today: Int { LevelCatalog.dayNumber(for: Date()) }
    private var paused: Bool { controller.hasPausedRun }

    /// Pure (tested).
    static func title(kind: Kind, paused: Bool) -> String {
        switch kind {
        case .cramped: return "Make Brim full screen to pour"
        case .cover: return paused ? "Open me to carry on" : "Open me to pour"
        }
    }

    /// Pure (tested). The Duo's split can't be resized (forum 847644), so never "drag to widen".
    static func subtitle(kind: Kind) -> String {
        switch kind {
        case .cramped: return "This window is too small for the counter."
        case .cover: return "Lay it flat, then lift the top half."
        }
    }

    /// The side insets the centred card keeps. In portrait none: the cover display reports its top-corner camera as a
    /// ~84 pt trailing inset (Duo run 40343397399), which pushed the card off centre, and the card sits far below the
    /// camera anyway. In landscape the camera is beside the card, so both are kept. Pure.
    static func sideInsets(_ insets: EdgeInsets, landscape: Bool) -> (leading: CGFloat, trailing: CGFloat) {
        landscape ? (insets.leading, insets.trailing) : (0, 0)
    }

    /// "Pour here with touch": the cover display of a Duo, never a cramped window. Pure.
    static func offersCoverTouch(kind: Kind, hingeSeen: Bool) -> Bool {
        kind == .cover && hingeSeen
    }

    var body: some View {
        ZStack {
            // Opaque (REVIEW-3 P2-3): a ghost of the live scene (a tipped jug) behind "Open me to pour" read as "it's
            // pouring while shut".
            BrimTheme.cream
                .ignoresSafeArea()
            LinearGradient(colors: [BrimTheme.cream, BrimTheme.peach.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            GeometryReader { geo in
                let side = Self.sideInsets(insets, landscape: geo.size.width > geo.size.height)
                ScrollView(showsIndicators: false) {
                    card
                        .padding(.horizontal, 24)
                        .padding(.leading, side.leading)
                        .padding(.trailing, side.trailing)
                        .padding(.vertical, 20)
                        .frame(width: geo.size.width)
                        .frame(minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
        }
        .onAppear { logCard() }
        .onChange(of: paused) { _, _ in logCard() }
    }

    private var card: some View {
        VStack(spacing: 16) {
            BrimWordmark(size: kind == .cramped ? 44 : 52)
            VStack(spacing: 6) {
                Text(Self.title(kind: kind, paused: paused))
                    .font(BrimTheme.title(26))
                    .foregroundStyle(BrimTheme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.subtitle(kind: kind))
                    .font(BrimTheme.text(15, .bold))
                    .foregroundStyle(BrimTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
                if paused {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(BrimTheme.goldDeep)
                            .frame(width: 22)
                        Text(GameController.coverPausedLine(mode: controller.mode, ordersDone: hud.ordersDone,
                                                            ordersTotal: hud.ordersTotal))
                            .font(BrimTheme.text(16, .heavy))
                            .foregroundStyle(BrimTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    Rectangle().fill(BrimTheme.ink.opacity(0.07)).frame(height: 1)
                }
                row(icon: "bolt.fill", title: "Rush best",
                    value: store.rushBest > 0 ? ShareText.grouped(store.rushBest) : "—")
                Rectangle().fill(BrimTheme.ink.opacity(0.07)).frame(height: 1)
                row(icon: "calendar", title: "Daily Pour #\(today)", value: dailyValue)
                if store.dailyStreak(today: today) > 1 {
                    Rectangle().fill(BrimTheme.ink.opacity(0.07)).frame(height: 1)
                    row(icon: "flame.fill", title: "Daily streak", value: "\(store.dailyStreak(today: today)) days")
                }
            }
            .brimCard(padding: 18, radius: 22)
            .frame(maxWidth: 340)
            if Self.offersCoverTouch(kind: kind, hingeSeen: controller.hingeSeen) {
                TapButton(kind: .secondary, height: 52, action: { controller.playOnCover() }) {
                    Label("Pour here with touch", systemImage: "hand.draw.fill")
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(maxWidth: 340)
                .accessibilityHint("Plays on this screen by dragging up. Open the phone to pour with the hinge again.")
            }
        }
    }

    private var dailyValue: String {
        if let record = store.dailyRecord(day: today) { return "Done · \(ShareText.grouped(record.score))" }
        return "Ready"
    }

    private func row(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(BrimTheme.goldDeep)
                .frame(width: 22)
            Text(title)
                .font(BrimTheme.text(16, .bold))
                .foregroundStyle(BrimTheme.ink)
            Spacer()
            Text(value)
                .font(BrimTheme.number(17))
                .foregroundStyle(BrimTheme.ink)
        }
    }

    private func logCard() {
        #if DEBUG
        print("BRIM-T cover card kind=\(kind.rawValue) paused=\(paused ? 1 : 0) touchOffer=\(Self.offersCoverTouch(kind: kind, hingeSeen: controller.hingeSeen) ? 1 : 0)")
        fflush(stdout)
        #endif
    }
}
