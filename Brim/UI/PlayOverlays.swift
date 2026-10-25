import SwiftUI

// MARK: - HUD

/// In-game HUD. It lives in the TOP half (on a Duo that half faces the player; the bottom half lies flat), hugging the
/// top-left corner so it stays clear of the jug (centre-right, just above the crease) and of the crease band.
struct HUDView: View {
    @ObservedObject var hud: HUDState
    let mode: GameMode
    let info: CanvasInfo
    let onPause: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bump = false

    private var isPractice: Bool {
        if case .practice = mode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    if !isPractice {
                        Text(ShareText.grouped(hud.score))
                            .font(BrimTheme.number(info.isCompact ? 34 : 40))
                            .foregroundStyle(BrimTheme.ink)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : Animation.snappy(duration: 0.25), value: hud.score)
                            .scaleEffect(bump ? 1.12 : 1, anchor: .leading)
                            .shadow(color: BrimTheme.cream.opacity(0.9), radius: 3)
                            .accessibilityLabel("Score \(hud.score)")
                    }
                    if hud.streak > 0 {
                        streakPill
                            .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                    }
                    if hud.maxStrikes > 0 && !isPractice {
                        strikes
                    }
                    orders
                }
                .padding(.leading, info.insets.leading + 16)
                .padding(.top, info.insets.top + 10)
                Spacer(minLength: 0)
                RoundIconButton(systemName: "pause.fill", size: 48, accessibility: "Pause", action: onPause)
                    .padding(.trailing, info.insets.trailing + 16)
                    .padding(.top, info.insets.top + 10)
            }
            Spacer(minLength: 0)
        }
        .frame(width: info.size.width, height: info.topHalfHeight, alignment: .top)
        .frame(width: info.size.width, height: info.size.height, alignment: .top)
        .animation(BrimTheme.pop(reduceMotion), value: hud.streak > 0)
        .onChange(of: hud.serveTick) { _, _ in
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { bump = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 160_000_000)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { bump = false }
            }
        }
    }

    private var streakPill: some View {
        HStack(spacing: 6) {
            if hud.multiplier > 1 {
                Text("×\(hud.multiplier)")
                    .font(BrimTheme.number(17))
            }
            Text(hud.streak == 1 ? "1 perfect" : "\(hud.streak) in a row")
                .font(BrimTheme.text(14, .heavy))
        }
        .foregroundStyle(BrimTheme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(hud.multiplier > 1 ? BrimTheme.gold : BrimTheme.mint))
        .overlay(Capsule().stroke(BrimTheme.cyan.opacity(hud.multiplier >= 5 ? 0.9 : 0), lineWidth: 2.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak \(hud.streak), multiplier \(hud.multiplier)")
    }

    private var strikes: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(hud.maxStrikes, 0), id: \.self) { i in
                let used = i < hud.strikes
                TumblerShape()
                    .fill(used ? BrimTheme.spill : BrimTheme.card.opacity(0.85))
                    .overlay(TumblerShape().stroke(used ? BrimTheme.spill : BrimTheme.ink.opacity(0.35), lineWidth: 2))
                    .frame(width: 16, height: 20)
                    .scaleEffect(used ? 1.08 : 1)
                    .animation(BrimTheme.pop(reduceMotion), value: used)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(hud.strikes) of \(hud.maxStrikes) spills")
    }

    @ViewBuilder private var orders: some View {
        if let total = hud.ordersTotal, total > 0 {
            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { i in
                    Circle()
                        .fill(i < hud.ordersDone ? BrimTheme.goldDeep : BrimTheme.ink.opacity(0.15))
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(BrimTheme.card, lineWidth: i == hud.ordersDone ? 2 : 0))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Capsule().fill(BrimTheme.card.opacity(0.75)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(hud.ordersDone) of \(total) glasses")
        } else if !isPractice {
            Text("\(hud.ordersDone) served")
                .font(BrimTheme.text(13, .heavy))
                .foregroundStyle(BrimTheme.inkSoft)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(BrimTheme.card.opacity(0.75)))
        }
    }
}

// MARK: - Onboarding hints (GAME-DESIGN §10)

struct HintsOverlay: View {
    let hint: HintKind?
    /// Touch play (drag) instead of the hinge.
    let touch: Bool
    let info: CanvasInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false

    private func text(for hint: HintKind) -> String {
        switch hint {
        case .lift: return touch ? "Drag up to pour." : "Lift the top half to pour."
        case .stop: return touch ? "Let go to stop." : "Lay it back to stop."
        case .anticipate: return "The stream keeps falling — stop just before the line."
        }
    }

    private func arrow(for hint: HintKind) -> String? {
        switch hint {
        case .lift: return "arrow.up"
        case .stop: return "arrow.down"
        case .anticipate: return nil
        }
    }

    var body: some View {
        ZStack {
            if let hint {
                VStack(spacing: 10) {
                    if let arrow = arrow(for: hint) {
                        Image(systemName: arrow)
                            .font(.system(size: 30, weight: .black))
                            .foregroundStyle(BrimTheme.goldDeep)
                            .padding(12)
                            .background(Circle().fill(BrimTheme.card).shadow(color: BrimTheme.ink.opacity(0.15), radius: 6, y: 3))
                            .offset(y: bob ? (hint == .lift ? -10 : 10) : 0)
                    }
                    Text(text(for: hint))
                        .font(BrimTheme.text(19, .heavy))
                        .foregroundStyle(BrimTheme.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(BrimTheme.card)
                                .shadow(color: BrimTheme.ink.opacity(0.18), radius: 10, y: 5)
                        )
                        .frame(maxWidth: min(info.size.width - 48, 360))
                }
                .id(hint)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                // Top half, left of the jug, below the HUD.
                .position(x: info.size.width * 0.34, y: hintY)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(width: info.size.width, height: info.size.height)
        .animation(BrimTheme.pop(reduceMotion), value: hint)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { bob = true }
        }
    }

    private var hintY: CGFloat {
        let top = info.insets.top + 150
        let halfMid = info.topHalfHeight * 0.58
        return min(max(top, halfMid), info.topHalfHeight - 60)
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
                        Text("Lay the top half back before you resume.")
                            .font(BrimTheme.text(14, .bold))
                            .foregroundStyle(BrimTheme.cream.opacity(0.75))
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
