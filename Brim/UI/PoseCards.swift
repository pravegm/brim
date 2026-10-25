import SwiftUI

// MARK: - Book pose (landscape canvas on a Duo)

/// Full-screen card for a Duo whose inner canvas is landscape (book pose): the game holds until the phone is turned so
/// the fold runs side to side (ROUND-2 decision 2, REVIEW-1 P0-7). ViewThatFits: drawing beside the text when the
/// canvas is wide, stacked when it isn't, so the copy never breaks into a one-word column.
struct StandUpCard: View {
    var insets: EdgeInsets = EdgeInsets()
    let onTurnScreen: () -> Void
    let onPlayWithTouch: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [BrimTheme.cream, BrimTheme.peach.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
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
            HStack(spacing: 10) {
                TapButton(kind: .primary, height: 52, action: onTurnScreen) {
                    Label("Turn the screen", systemImage: "rotate.right.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                TapButton(kind: .quiet, height: 52, action: onPlayWithTouch) {
                    Label("Use touch", systemImage: "hand.draw.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: 420)
            .padding(.top, 4)
        }
    }
}

/// A Duo seen from above: it turns from book pose (fold running up and down) to the fold running side to side, then
/// its top half (the jug) lifts while the bottom half (the glass) stays flat on the table. On a loop; still under
/// Reduce Motion.
struct TurnPhoneDrawing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = reduceMotion ? 1.6 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.4)
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

// MARK: - Cover display / shut

/// The calm card on the cover display (or while the Duo is shut): today's Daily status, best Rush, "Open me to pour".
struct CoverView: View {
    @ObservedObject var store: ProgressStore

    private var today: Int { LevelCatalog.dayNumber(for: Date()) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [BrimTheme.cream, BrimTheme.peach.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                BrimWordmark(size: 52)
                Text("Open me to pour")
                    .font(BrimTheme.title(26))
                    .foregroundStyle(BrimTheme.ink)
                Text("Lay it flat, then lift the top half.")
                    .font(BrimTheme.text(15, .bold))
                    .foregroundStyle(BrimTheme.inkSoft)
                VStack(spacing: 12) {
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
            }
            .padding(24)
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
}
