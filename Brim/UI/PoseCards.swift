import SwiftUI

// MARK: - Book pose

/// Full-screen card for the Duo in book pose (landscape inner canvas): the game is paused until the phone stands up
/// like a laptop. The inner display ignores orientation locks, so this has to exist (GAME-DESIGN §3).
struct StandUpCard: View {
    let onPlayWithTouch: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [BrimTheme.cream, BrimTheme.peach.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            HStack(spacing: 36) {
                FoldingPhoneDrawing()
                    .frame(width: 230, height: 200)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Stand me up like a little laptop")
                        .font(BrimTheme.title(32))
                        .foregroundStyle(BrimTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Turn your iPhone Duo so the fold runs across, rest the bottom half on the table and raise the top half. Then lift it to pour.")
                        .font(BrimTheme.text(16))
                        .foregroundStyle(BrimTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    TapButton(kind: .quiet, height: 54, action: onPlayWithTouch) {
                        Label("Play with touch instead", systemImage: "hand.draw.fill")
                    }
                    .frame(maxWidth: 320)
                    .padding(.top, 6)
                }
                .frame(maxWidth: 420, alignment: .leading)
            }
            .padding(32)
        }
    }
}

/// A phone that opens from flat into the laptop (tabletop) pose, on a loop.
struct FoldingPhoneDrawing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var raised = false

    var body: some View {
        // Drawn in a fixed 230 × 200 box; the fold (hinge) runs across at y = 120.
        ZStack {
            // Table shadow
            Ellipse()
                .fill(BrimTheme.ink.opacity(0.10))
                .frame(width: 210, height: 28)
                .position(x: 115, y: 150)
            // Bottom half, lying flat on the table (hinged along its top edge)
            half(glass: true)
                .frame(width: 170, height: 110)
                .rotation3DEffect(.degrees(-70), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.45)
                .position(x: 115, y: 175)
            // Top half: from lying back flat to standing like a laptop lid (hinged along its bottom edge)
            half(glass: false)
                .frame(width: 170, height: 110)
                .rotation3DEffect(.degrees(raised ? 10 : 70), axis: (x: 1, y: 0, z: 0), anchor: .bottom,
                                  perspective: 0.45)
                .position(x: 115, y: 65)
        }
        .frame(width: 230, height: 200)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                raised = true
            } else {
                withAnimation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.4)
                    .repeatForever(autoreverses: true)) {
                    raised = true
                }
            }
        }
    }

    private func half(glass: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(BrimTheme.ink)
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(glass ? BrimTheme.mint : BrimTheme.cream)
                    .padding(6)
                    .overlay(
                        Group {
                            if glass {
                                TumblerShape()
                                    .fill(BrimTheme.lemonade)
                                    .frame(width: 22, height: 28)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 26, weight: .black))
                                    .foregroundStyle(BrimTheme.goldDeep)
                            }
                        }
                    )
            )
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
                VStack(spacing: 12) {
                    row(icon: "bolt.fill", title: "Rush best",
                        value: store.rushBest > 0 ? ShareText.grouped(store.rushBest) : "—")
                    Rectangle().fill(BrimTheme.ink.opacity(0.07)).frame(height: 1)
                    row(icon: "calendar", title: "Daily Pour #\(today)", value: dailyValue)
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
