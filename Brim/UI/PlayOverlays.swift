import SwiftUI

// MARK: - HUD

/// In-game HUD (REVIEW-1 P0-2 / P1-7): ONE compact row (≤ 56 pt) at the top of the top half, under the real safe area
/// (Dynamic Island, the Duo's inner camera cut-out). Left: a title chip ("Lemonade Stand · 1", "Daily #297", "Rush")
/// over the progress dots and strike cups. Right: the streak pill, the score, pause. The centre stays empty (the
/// island / camera sit there), and the row stays inside the world's 110 pt HUD band the scene keeps clear.
struct HUDView: View {
    @ObservedObject var hud: HUDState
    let mode: GameMode
    let title: String
    let info: CanvasInfo
    /// Reduce Motion or "Calmer motion": no score pop.
    let calm: Bool
    let onPause: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bump = false

    private var isPractice: Bool {
        if case .practice = mode { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(BrimTheme.text(13, .heavy))
                    .foregroundStyle(BrimTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(BrimTheme.card.opacity(0.92)))
                    .accessibilityLabel(title)
                HStack(spacing: 8) {
                    orders
                    if hud.maxStrikes > 0 && !isPractice {
                        strikes
                    }
                }
            }
            .frame(maxWidth: info.size.width * 0.48, alignment: .leading)
            Spacer(minLength: 4)
            if hud.streak > 0 {
                streakPill
                    .fixedSize()
                    .layoutPriority(1)
                    .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            }
            if !isPractice {
                Text(ShareText.grouped(hud.score))
                    .font(BrimTheme.number(info.isCompact ? 28 : 32))
                    .foregroundStyle(BrimTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : Animation.snappy(duration: 0.25), value: hud.score)
                    .scaleEffect(bump ? 1.14 : 1, anchor: .trailing)
                    .shadow(color: BrimTheme.cream.opacity(0.9), radius: 3)
                    .layoutPriority(1)
                    .accessibilityLabel("Score \(hud.score)")
            }
            RoundIconButton(systemName: "pause.fill", size: 44, accessibility: "Pause", action: onPause)
        }
        .frame(height: HUDMetrics.rowHeight)
        .padding(.leading, info.sidePad)
        .padding(.trailing, info.sidePad)
        .padding(.top, info.hudTop)
        .frame(width: info.size.width, height: info.size.height, alignment: .top)
        .animation(BrimTheme.pop(reduceMotion), value: hud.streak > 0)
        .onChange(of: hud.serveTick) { _, _ in
            guard !reduceMotion && !calm else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { bump = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 160_000_000)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { bump = false }
            }
        }
    }

    /// "×3 · 🔥7": the multiplier, then the streak with a flame (★ means stars earned everywhere else, P2-4).
    private var streakPill: some View {
        HStack(spacing: 4) {
            if hud.multiplier > 1 {
                Text("×\(hud.multiplier)")
                    .font(BrimTheme.number(16))
                Rectangle()
                    .fill(BrimTheme.ink.opacity(0.25))
                    .frame(width: 1.5, height: 14)
            }
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .black))
            Text("\(hud.streak)")
                .font(BrimTheme.number(14))
        }
        .lineLimit(1)
        .foregroundStyle(BrimTheme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(hud.multiplier > 1 ? BrimTheme.gold : BrimTheme.mint))
        .overlay(Capsule().stroke(BrimTheme.cyan.opacity(hud.multiplier >= 5 ? 0.9 : 0), lineWidth: 2.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak \(hud.streak), multiplier \(hud.multiplier)")
    }

    private var strikes: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(hud.maxStrikes, 0), id: \.self) { i in
                let used = i < hud.strikes
                TumblerShape()
                    .fill(used ? BrimTheme.spill : BrimTheme.card.opacity(0.85))
                    .overlay(TumblerShape().stroke(used ? BrimTheme.spill : BrimTheme.ink.opacity(0.4), lineWidth: 1.6))
                    .frame(width: 12, height: 15)
                    .scaleEffect(used ? 1.12 : 1)
                    .animation(BrimTheme.pop(reduceMotion), value: used)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(BrimTheme.card.opacity(0.75)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(hud.strikes) of \(hud.maxStrikes) spills")
    }

    @ViewBuilder private var orders: some View {
        if let total = hud.ordersTotal, total > 0 {
            HStack(spacing: total > 8 ? 3 : 4) {
                ForEach(0..<total, id: \.self) { i in
                    Circle()
                        .fill(i < hud.ordersDone ? BrimTheme.goldDeep : BrimTheme.ink.opacity(0.15))
                        .frame(width: total > 8 ? 7 : 8, height: total > 8 ? 7 : 8)
                        .overlay(Circle().stroke(BrimTheme.ink.opacity(0.5), lineWidth: i == hud.ordersDone ? 1.5 : 0))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Capsule().fill(BrimTheme.card.opacity(0.75)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(hud.ordersDone) of \(total) glasses")
        } else if !isPractice {
            // Rush: "7 served", or "✓ 7" when the row is tight (REVIEW-2 P1-8: never "7 se…").
            ViewThatFits(in: .horizontal) {
                servedChip(Text("\(hud.ordersDone) served"))
                servedChip(Text("\(Image(systemName: "checkmark")) \(hud.ordersDone)"))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(hud.ordersDone) served")
        }
    }

    private func servedChip(_ label: Text) -> some View {
        label
            .font(BrimTheme.text(12, .heavy))
            .foregroundStyle(BrimTheme.inkSoft)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(BrimTheme.card.opacity(0.75)))
    }
}

// MARK: - Onboarding hints (GAME-DESIGN §10, REVIEW-1 P1-10)

/// Goal first: a pulsing "Fill to here" callout on the glass's line, beside the glass. The control hint sits BESIDE
/// the jug (the side with room; on narrow phones in the counter band at the bottom), never over it, with a bobbing
/// glyph (no button-like background).
struct HintsOverlay: View {
    @ObservedObject var hud: HUDState
    let hint: HintKind?
    /// Touch play (drag) instead of the hinge.
    let touch: Bool
    let info: CanvasInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false

    static func text(for hint: HintKind, touch: Bool) -> String {
        switch hint {
        case .lift: return touch ? "Drag up to pour." : "Lift the top half to pour."
        case .stop:
            return touch ? "Let go just before the line: the stream keeps falling."
                         : "Lay it flat just before the line: the stream keeps falling."
        case .anticipate: return "A little earlier next time: the stream keeps falling."
        }
    }

    private func glyph(for hint: HintKind) -> String? {
        switch hint {
        case .lift: return touch ? "hand.point.up.left.fill" : "arrow.up"
        case .stop: return touch ? "hand.raised.fill" : "arrow.down"
        case .anticipate: return nil
        }
    }

    private var cardWidth: CGFloat { min(max(info.size.width * 0.34, 190), 240) }

    var body: some View {
        ZStack {
            if let hint, !hud.showFlatGate {
                if hint == .lift || hint == .stop, let glass = hud.anchors?.glass, glass.filling || hint == .lift {
                    FillToHereCallout(glass: glass, info: info, bob: bob)
                        .transition(.opacity)
                }
                hintCard(hint)
                    .id(hint)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .frame(width: info.size.width, height: info.size.height)
        .animation(BrimTheme.pop(reduceMotion), value: hint)
        .animation(BrimTheme.pop(reduceMotion), value: hud.showFlatGate)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { bob = true }
        }
    }

    private func hintCard(_ hint: HintKind) -> some View {
        let height: CGFloat = hint == .lift ? 104 : 96
        let size = CGSize(width: cardWidth, height: height)
        let spot = HintSpot.place(size: size, anchors: hud.anchors, info: info)
        let symbol = glyph(for: hint)
        let lift: CGFloat = bob ? (hint == .stop ? 6 : -8) : 0
        let message = Text(Self.text(for: hint, touch: touch))
            .font(BrimTheme.text(spot.compact ? 15 : 16, .heavy))
            .foregroundStyle(BrimTheme.ink)
        let cardShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Group {
            if spot.compact {
                // The counter band is short: glyph and text side by side in one card.
                HStack(spacing: 10) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(BrimTheme.goldDeep)
                            .offset(y: lift * 0.5)
                    }
                    message
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(cardShape.fill(BrimTheme.card).shadow(color: BrimTheme.ink.opacity(0.18), radius: 10, y: 5))
            } else {
                VStack(spacing: 6) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 26, weight: .black))
                            .foregroundStyle(BrimTheme.goldDeep)
                            .shadow(color: BrimTheme.card, radius: 4)
                            .offset(y: lift)
                    }
                    message
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(cardShape.fill(BrimTheme.card)
                            .shadow(color: BrimTheme.ink.opacity(0.18), radius: 10, y: 5))
                }
            }
        }
        .frame(width: spot.width)
        .position(spot.center)
        .animation(.easeOut(duration: 0.25), value: spot.center)
        .accessibilityElement(children: .combine)
    }
}

/// Where a hint card goes: beside the jug in the top half (the side with room), else (narrow phones) centred in the
/// counter band under the glasses, else just under the HUD row.
struct HintSpot: Equatable {
    var center: CGPoint
    var width: CGFloat
    var compact: Bool

    static func place(size: CGSize, anchors: PlayAnchors?, info: CanvasInfo) -> HintSpot {
        let top = info.hudTop + HUDMetrics.rowHeight + 8
        let topHalf = CGRect(x: info.sidePad - 6, y: top, width: info.size.width - 2 * (info.sidePad - 6),
                             height: max(info.topHalfHeight - 8 - top, 0))
        let jug = anchors.map { info.mapper.rect($0.jug) }
            ?? info.mapper.rect(CGRect(x: WorldLayout.pivot.x - 110, y: WorldLayout.pivot.y - 130, width: 220, height: 250))
        if let p = CardPlacement.beside(jug, size: size, in: topHalf) {
            return HintSpot(center: p, width: size.width, compact: false)
        }
        // Narrow phone: the counter band under the glasses (the front of the counter), full width.
        let bandTop = info.counterY + 6
        let bandBottom = info.size.height - max(info.insets.bottom - 6, 8)
        let width = min(info.size.width - 2 * info.sidePad, 360)
        if bandBottom - bandTop >= 44 {
            return HintSpot(center: CGPoint(x: info.size.width / 2, y: (bandTop + bandBottom) / 2), width: width,
                            compact: true)
        }
        return HintSpot(center: CGPoint(x: info.size.width / 2, y: top + size.height / 2), width: width, compact: true)
    }
}

/// "Fill to here": a pill with an arrow pointing at the glass's line, beside the glass on the side with more room.
struct FillToHereCallout: View {
    let glass: GlassAnchor
    let info: CanvasInfo
    let bob: Bool

    var body: some View {
        let m = info.mapper
        // Never on the crease (ROUND-3 decision 3): the pill's top stays ≥ 8 pt below the fold.
        let lineY = info.hasFold ? max(m.y(glass.lineY), info.bottomHalfTop + 8 + 15) : m.y(glass.lineY)
        let left = m.x(glass.x - glass.halfWidthAtLine)
        let right = m.x(glass.x + glass.halfWidthAtLine)
        let pillWidth: CGFloat = 128
        let roomRight = info.size.width - info.sidePad - right
        let onRight = roomRight >= pillWidth + 12 && roomRight >= left - info.sidePad
        let x = onRight ? right + 10 + pillWidth / 2 : left - 10 - pillWidth / 2
        let nudge: CGFloat = bob ? 4 : 0
        return HStack(spacing: 5) {
            if onRight {
                Image(systemName: "arrowtriangle.left.fill").font(.system(size: 11, weight: .black))
            }
            Text("Fill to here")
                .font(BrimTheme.text(14, .heavy))
                .lineLimit(1)
            if !onRight {
                Image(systemName: "arrowtriangle.right.fill").font(.system(size: 11, weight: .black))
            }
        }
        .foregroundStyle(BrimTheme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(BrimTheme.gold).shadow(color: BrimTheme.ink.opacity(0.18), radius: 5, y: 2))
        .frame(width: pillWidth)
        .position(x: x + (onRight ? nudge : -nudge), y: lineY)
        .animation(.easeOut(duration: 0.25), value: lineY)
        .accessibilityLabel("Fill to the line")
    }
}

// MARK: - Duo flat gate (ROUND-2 decision 2)

/// "Lay it flat to start": shown while the session waits for the lid to lie flat (`snapshot.needsFlat`, Duo only),
/// beside the jug like the hints.
struct FlatGateOverlay: View {
    @ObservedObject var hud: HUDState
    let info: CanvasInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if hud.showFlatGate {
                let size = CGSize(width: min(max(info.size.width * 0.34, 200), 240), height: 190)
                let spot = HintSpot.place(size: size, anchors: hud.anchors, info: info)
                VStack(spacing: 10) {
                    LayFlatGlyph()
                        .frame(width: 96, height: 64)
                    Text(hud.gateAfterPause ? "Lay it flat to carry on" : "Lay it flat to start")
                        .font(BrimTheme.title(20))
                        .foregroundStyle(BrimTheme.ink)
                        .multilineTextAlignment(.center)
                    Text("Then lift the top half to pour.")
                        .font(BrimTheme.text(14, .bold))
                        .foregroundStyle(BrimTheme.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(width: spot.width)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(BrimTheme.card)
                        .shadow(color: BrimTheme.ink.opacity(0.2), radius: 12, y: 6)
                )
                .position(spot.center)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .frame(width: info.size.width, height: info.size.height)
        .animation(BrimTheme.pop(reduceMotion), value: hud.showFlatGate)
    }
}

/// A Duo seen side-on, its top half easing down to flat (the gate's little drawing).
struct LayFlatGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = reduceMotion ? 1.0 : min(max((t.truncatingRemainder(dividingBy: 2.4)) / 1.4, 0), 1)
            let eased = 1 - pow(1 - phase, 3)
            let lidAngle = 60.0 * (1 - eased)       // degrees above flat
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let hingeX = w * 0.5, baseY = h * 0.78
                let half = w * 0.42
                var table = Path()
                table.move(to: CGPoint(x: 0, y: baseY + 6))
                table.addLine(to: CGPoint(x: w, y: baseY + 6))
                ctx.stroke(table, with: .color(BrimTheme.ink.opacity(0.2)), lineWidth: 2)
                var bottom = Path()
                bottom.move(to: CGPoint(x: hingeX, y: baseY))
                bottom.addLine(to: CGPoint(x: hingeX + half, y: baseY))
                ctx.stroke(bottom, with: .color(BrimTheme.ink), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                let r = lidAngle * Double.pi / 180
                let dx = half * CGFloat(cos(r)), dy = half * CGFloat(sin(r))
                var lid = Path()
                lid.move(to: CGPoint(x: hingeX, y: baseY))
                lid.addLine(to: CGPoint(x: hingeX - dx, y: baseY - dy))
                ctx.stroke(lid, with: .color(BrimTheme.goldDeep), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                let dot = CGRect(x: hingeX - 4, y: baseY - 4, width: 8, height: 8)
                ctx.fill(Path(ellipseIn: dot), with: .color(BrimTheme.ink))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Paused by closing (ROUND-3 decision 1)

/// The calm card when the run paused itself because the phone was closing (hinge < 70°) or shut: nothing is judged
/// while it shows; opening the phone resumes the run behind the flat gate ("Lay it flat to carry on"). The card sits
/// on the raised half, the two quiet buttons on the flat half, nothing on the crease.
struct ClosedPauseView: View {
    @ObservedObject var controller: GameController
    let info: CanvasInfo

    var body: some View {
        ZStack {
            BrimTheme.ink.opacity(0.3)
                .contentShape(Rectangle())
                .onTapGesture {}
            DuoSplit(info: info) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 10) {
                        LayFlatGlyph()
                            .frame(width: 110, height: 72)
                        Text("Open me up and lay me flat")
                            .font(BrimTheme.title(info.isCompact ? 22 : 25))
                            .foregroundStyle(BrimTheme.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Your shift is paused. It carries on once the phone lies flat.")
                            .font(BrimTheme.text(14, .bold))
                            .foregroundStyle(BrimTheme.inkSoft)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .frame(maxWidth: 400)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(BrimTheme.card)
                            .shadow(color: BrimTheme.ink.opacity(0.2), radius: 14, y: 6)
                    )
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
            } bottom: {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        TapButton(kind: .secondary, height: 56, action: { controller.resumeFromClosed() }) {
                            Label("Resume", systemImage: "play.fill")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        TapButton(kind: .quiet, height: 56, action: { controller.quitToMenu() }) {
                            Label("Menu", systemImage: "house.fill")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: 420)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
            }
        }
    }
}

// MARK: - Pause

struct PauseView: View {
    @ObservedObject var controller: GameController
    let info: CanvasInfo

    var body: some View {
        ZStack {
            BrimTheme.ink.opacity(0.42)
                .contentShape(Rectangle())
                .onTapGesture {}
            DuoSplit(info: info) {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text("Paused")
                        .font(BrimTheme.title(44))
                        .foregroundStyle(BrimTheme.cream)
                    Text(GameController.title(for: controller.mode))
                        .font(BrimTheme.text(17, .heavy))
                        .foregroundStyle(BrimTheme.cream.opacity(0.85))
                    if !controller.usesTouch {
                        Text("Lay it flat, then lift the top half to pour.")
                            .font(BrimTheme.text(14, .bold))
                            .foregroundStyle(BrimTheme.cream.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
            } bottom: {
                VStack(spacing: 12) {
                    Spacer(minLength: 0)
                    TapButton(kind: .primary, height: 66, action: { controller.resume() }) {
                        Label("Resume", systemImage: "play.fill")
                    }
                    HStack(spacing: 12) {
                        TapButton(kind: .secondary, action: { controller.restart() }) {
                            Label("Restart", systemImage: "arrow.counterclockwise")
                        }
                        TapButton(kind: .quiet, action: { controller.quitToMenu() }) {
                            Label("Menu", systemImage: "house.fill")
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: 520)
            }
        }
    }
}
