import SwiftUI

/// The café look (GAME-DESIGN §8): cream wall, mint tiles, terracotta counter, ink, brim gold, Perfect cyan.
/// SF Pro Rounded everywhere, heavy for numbers. Every screen takes colour, type and motion from here.
enum BrimTheme {
    static let cream = Color(brimHex: 0xFFF4E2)
    static let creamDeep = Color(brimHex: 0xFBE6C8)
    static let mint = Color(brimHex: 0xBFE8D8)
    static let mintDeep = Color(brimHex: 0x7CCBB0)
    static let terracotta = Color(brimHex: 0xD9825B)
    static let terracottaDeep = Color(brimHex: 0xB4613D)
    static let ink = Color(brimHex: 0x2B2233)
    static let inkSoft = Color(brimHex: 0x5E5263)
    static let inkFaint = Color(brimHex: 0x9A8E9C)
    static let gold = Color(brimHex: 0xFFC23D)
    static let goldDeep = Color(brimHex: 0xE09A12)
    static let cyan = Color(brimHex: 0x3FD0FF)
    static let peach = Color(brimHex: 0xFFC9A3)
    static let card = Color(brimHex: 0xFFFBF4)
    static let spill = Color(brimHex: 0xE5484D)
    static let lemonade = Color(brimHex: 0xFFE066)

    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let cardRadius: CGFloat = 26
    static let buttonRadius: CGFloat = 22

    /// Springy by default; Reduce Motion turns movement into a short crossfade.
    static func pop(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.68)
    }
    static func settle(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.84)
    }

    /// Colour for a judgement chip.
    static func color(for judgement: Judgement) -> Color {
        switch judgement {
        case .perfect: return cyan
        case .great: return mintDeep
        case .good: return gold
        case .short: return terracotta
        case .spill: return spill
        }
    }

    /// Accent per venue (cards, bubbles).
    static func color(for venue: VenueID) -> Color {
        switch venue {
        case .lemonadeStand: return Color(brimHex: 0xFFD54A)
        case .sodaFountain: return Color(brimHex: 0xF0857A)
        case .milkshakeDiner: return Color(brimHex: 0xF6A5C0)
        case .conveyor: return Color(brimHex: 0x7FB8E8)
        case .potionShop: return Color(brimHex: 0xA78BFA)
        case .sandBar: return Color(brimHex: 0xE4C08A)
        }
    }

    static func symbol(for venue: VenueID) -> String {
        switch venue {
        case .lemonadeStand: return "sun.max.fill"
        case .sodaFountain: return "bubbles.and.sparkles.fill"
        case .milkshakeDiner: return "cup.and.saucer.fill"
        case .conveyor: return "arrow.right.circle.fill"
        case .potionShop: return "flask.fill"
        case .sandBar: return "hourglass"
        }
    }
}

extension Color {
    /// 0xRRGGBB.
    init(brimHex hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Where the screen's halves are, in full-canvas points measured from the top (safe area ignored).
struct CanvasInfo: Equatable {
    var size: CGSize
    var insets: EdgeInsets
    /// The crease band (Duo tabletop) from the top; nil on phones without a fold.
    var crease: ClosedRange<CGFloat>?

    var topHalfHeight: CGFloat { crease?.lowerBound ?? size.height * 0.5 }
    var bottomHalfTop: CGFloat { crease?.upperBound ?? size.height * 0.5 }
    var isCompact: Bool { size.height < 760 }
}

// MARK: - Buttons

/// A big friendly button: rounded slab with a darker lip, presses down with a spring, ticks a haptic.
struct BrimButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, danger }
    var kind: Kind = .primary
    var height: CGFloat = 60

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color
        let lip: Color
        let text: Color
        switch kind {
        case .primary: fill = BrimTheme.gold; lip = BrimTheme.goldDeep; text = BrimTheme.ink
        case .secondary: fill = BrimTheme.mint; lip = BrimTheme.mintDeep; text = BrimTheme.ink
        case .quiet: fill = BrimTheme.card; lip = BrimTheme.creamDeep; text = BrimTheme.ink
        case .danger: fill = BrimTheme.spill; lip = Color(brimHex: 0xB0303A); text = .white
        }
        let pressed = configuration.isPressed
        return configuration.label
            .font(BrimTheme.text(19, .heavy))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: BrimTheme.buttonRadius, style: .continuous)
                        .fill(lip)
                        .offset(y: pressed ? 1 : 5)
                    RoundedRectangle(cornerRadius: BrimTheme.buttonRadius, style: .continuous)
                        .fill(fill)
                        .offset(y: pressed ? 3 : 0)
                }
            )
            .offset(y: pressed ? 3 : 0)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: pressed)
    }
}

/// A button that ticks the UI haptic/sound (FeedbackDirector.uiTap) before acting.
struct TapButton<Label: View>: View {
    var kind: BrimButtonStyle.Kind = .primary
    var height: CGFloat = 60
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            FeedbackDirector.shared.uiTap()
            action()
        } label: {
            label()
        }
        .buttonStyle(BrimButtonStyle(kind: kind, height: height))
    }
}

/// A round icon button (gear, pause, close).
struct RoundIconButton: View {
    let systemName: String
    var size: CGFloat = 48
    var accessibility: String
    let action: () -> Void

    var body: some View {
        Button {
            FeedbackDirector.shared.uiTap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .heavy, design: .rounded))
                .foregroundStyle(BrimTheme.ink)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(BrimTheme.card)
                        .shadow(color: BrimTheme.ink.opacity(0.14), radius: 6, y: 3)
                )
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(accessibility)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Cards and small pieces

extension View {
    /// A cream card with a soft ink shadow.
    func brimCard(padding: CGFloat = 20, radius: CGFloat = BrimTheme.cardRadius) -> some View {
        self.padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(BrimTheme.card)
                    .shadow(color: BrimTheme.ink.opacity(0.16), radius: 18, y: 8)
            )
    }
}

/// Three stars, `filled` of them gold.
struct StarRow: View {
    let filled: Int
    var total: Int = 3
    var size: CGFloat = 14
    var spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<total, id: \.self) { i in
                Image(systemName: i < filled ? "star.fill" : "star")
                    .font(.system(size: size, weight: .heavy))
                    .foregroundStyle(i < filled ? BrimTheme.gold : BrimTheme.inkFaint.opacity(0.6))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filled) of \(total) stars")
    }
}

/// A tumbler outline (strike icons, glass counters).
struct TumblerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let inset = rect.width * 0.14
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - rect.height * 0.08))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - inset - rect.width * 0.08, y: rect.maxY),
                       control: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + inset + rect.width * 0.08, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + inset, y: rect.maxY - rect.height * 0.08),
                       control: CGPoint(x: rect.minX + inset, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// A teardrop (the wordmark's drip).
struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let r = w / 2
        let cy = rect.maxY - r
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: cy),
                   control1: CGPoint(x: rect.midX + w * 0.12, y: rect.minY + h * 0.25),
                   control2: CGPoint(x: rect.maxX, y: cy - r * 0.9))
        p.addArc(center: CGPoint(x: rect.midX, y: cy), radius: r, startAngle: .degrees(0), endAngle: .degrees(180),
                 clockwise: false)
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                   control1: CGPoint(x: rect.minX, y: cy - r * 0.9),
                   control2: CGPoint(x: rect.midX - w * 0.12, y: rect.minY + h * 0.25))
        p.closeSubpath()
        return p
    }
}

/// "Brim" in heavy rounded type over a glowing gold fill line, with a little drip off the m.
struct BrimWordmark: View {
    var size: CGFloat = 76
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drip = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: size * 0.02) {
                Text("Brim")
                    .font(BrimTheme.title(size))
                    .foregroundStyle(BrimTheme.ink)
                    .kerning(-size * 0.02)
                Capsule()
                    .fill(BrimTheme.gold)
                    .frame(width: size * 1.9, height: max(4, size * 0.07))
                    .shadow(color: BrimTheme.gold.opacity(0.8), radius: size * 0.1)
            }
            DropShape()
                .fill(LinearGradient(colors: [BrimTheme.cyan, Color(brimHex: 0x1FA3D6)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.16, height: size * 0.24)
                .offset(x: -size * 0.12, y: drip ? size * 0.34 : size * 0.16)
                .opacity(drip ? 0.0 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Brim")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeIn(duration: 1.6).repeatForever(autoreverses: false).delay(0.6)) { drip = true }
        }
    }
}

/// A rounded "pill" label.
struct Pill: View {
    let text: String
    var fill: Color = BrimTheme.gold
    var foreground: Color = BrimTheme.ink
    var fontSize: CGFloat = 15

    var body: some View {
        Text(text)
            .font(BrimTheme.number(fontSize))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(fill))
    }
}

/// Lays content out on the two halves of a Duo in tabletop pose (top faces the player, bottom lies flat: buttons go
/// there), keeping clear of the crease band. Without a fold the halves simply stack around the middle.
struct DuoSplit<Top: View, Bottom: View>: View {
    let info: CanvasInfo
    @ViewBuilder let top: () -> Top
    @ViewBuilder let bottom: () -> Bottom

    var body: some View {
        VStack(spacing: 0) {
            top()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, info.insets.top)
                .frame(height: info.topHalfHeight)
            Color.clear.frame(height: max(info.bottomHalfTop - info.topHalfHeight, 0))
            bottom()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, max(info.insets.bottom, 12))
                .frame(height: max(info.size.height - info.bottomHalfTop, 0))
        }
        .padding(.leading, info.insets.leading)
        .padding(.trailing, info.insets.trailing)
        .frame(width: info.size.width, height: info.size.height)
    }
}
