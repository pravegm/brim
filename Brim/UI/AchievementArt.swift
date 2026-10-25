import SwiftUI

/// Game Center achievement badges (docs/appstore/achievements.md): one 1024 × 1024 image per achievement, in the app
/// icon's style (AppIconArt): a warm cream → peach background with sun rays and the Duo fold seam, a medallion whose
/// ring marks the tier (teal for 25–50 points, deep teal with gold studs for 75, gold for 100), an inner disc tinted
/// for the achievement, and one simple ink-outlined motif in the middle.
///
/// Pure vector in a 1024-unit design space, opaque, square-cornered; no text except short numerals. Rendered to
/// Documents/badges/<id>.png by demo `screen=badges` (BadgeExport in App/DemoMode.swift). Unknown ids draw the
/// First Perfect glass.
struct AchievementBadge: View {
    let id: String
    var side: CGFloat = 1024

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            let scale = min(size.width, size.height) / 1024
            context.scaleBy(x: scale, y: scale)
            BadgePainter.paint(&context, id: id)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

private enum BadgePainter {
    // Palette (AppIconArt / BrimTheme)
    static let ink = Color(brimHex: 0x2B2233)
    static let cream = Color(brimHex: 0xFFF4E2)
    static let card = Color(brimHex: 0xFFFBF4)
    static let gold = Color(brimHex: 0xFFC23D)
    static let goldDeep = Color(brimHex: 0xE09A12)
    static let lemonTop = Color(brimHex: 0xFFE772)
    static let lemonBottom = Color(brimHex: 0xFFAA2C)
    static let tealLight = Color(brimHex: 0x45C2B4)
    static let teal = Color(brimHex: 0x2A9A8E)
    static let tealDark = Color(brimHex: 0x1B6E66)
    static let terracotta = Color(brimHex: 0xD9825B)
    static let terracottaDeep = Color(brimHex: 0xB4613D)
    static let spill = Color(brimHex: 0xE5484D)

    static let center = CGPoint(x: 512, y: 512)
    static let line: CGFloat = 14

    enum Tier { case one, two, three }

    struct Style {
        let tier: Tier
        let accent: Color
    }

    static func style(for id: String) -> Style {
        switch id {
        case "brim.first.perfect": return Style(tier: .one, accent: Color(brimHex: 0xFFE066))
        case "brim.streak.10": return Style(tier: .one, accent: Color(brimHex: 0xFF9A5A))
        case "brim.streak.25": return Style(tier: .three, accent: Color(brimHex: 0xFF9A5A))
        case "brim.litres.10": return Style(tier: .two, accent: Color(brimHex: 0x3FD0FF))
        case "brim.venue.soda": return Style(tier: .one, accent: Color(brimHex: 0xF0857A))
        case "brim.venue.diner": return Style(tier: .one, accent: Color(brimHex: 0xF6A5C0))
        case "brim.venue.conveyor": return Style(tier: .two, accent: Color(brimHex: 0x7FB8E8))
        case "brim.venue.potions": return Style(tier: .two, accent: Color(brimHex: 0xA78BFA))
        case "brim.allstars": return Style(tier: .three, accent: Color(brimHex: 0xFFC23D))
        case "brim.sandbar": return Style(tier: .three, accent: Color(brimHex: 0xE4C08A))
        default: return Style(tier: .one, accent: Color(brimHex: 0xFFE066))
        }
    }

    static func paint(_ ctx: inout GraphicsContext, id: String) {
        let look = style(for: id)
        background(&ctx, tier: look.tier)
        medallion(&ctx, style: look)
        switch id {
        case "brim.streak.10": flame(&ctx, number: "10", embers: 3)
        case "brim.streak.25": flame(&ctx, number: "25", embers: 6)
        case "brim.litres.10": drop(&ctx)
        case "brim.venue.soda": sodaDispenser(&ctx)
        case "brim.venue.diner": shakeTin(&ctx)
        case "brim.venue.conveyor": conveyor(&ctx)
        case "brim.venue.potions": potionFlask(&ctx)
        case "brim.allstars": threeStars(&ctx)
        case "brim.sandbar": hourglass(&ctx)
        default: perfectGlass(&ctx)
        }
    }

    // MARK: Helpers

    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    static func polar(_ angle: Double, _ radius: CGFloat, around c: CGPoint) -> CGPoint {
        CGPoint(x: c.x + radius * CGFloat(cos(angle)), y: c.y + radius * CGFloat(sin(angle)))
    }

    static func vertical(_ colors: [Color], _ top: CGFloat, _ bottom: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 512, y: top), endPoint: CGPoint(x: 512, y: bottom))
    }

    static func horizontal(_ colors: [Color], _ left: CGFloat, _ right: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: left, y: 512), endPoint: CGPoint(x: right, y: 512))
    }

    /// Fills `path`, then strokes it in ink with round joins.
    static func inked(_ ctx: inout GraphicsContext, _ path: Path, _ shading: GraphicsContext.Shading,
                      width: CGFloat = 14) {
        ctx.fill(path, with: shading)
        ctx.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// A blob of overlapping circles with one outline round the union (foam, a milkshake mound).
    static func blob(_ ctx: inout GraphicsContext, _ circles: [(CGFloat, CGFloat, CGFloat)], fill: Color,
                     width: CGFloat = 12) {
        for (x, y, r) in circles {
            ctx.fill(circle(CGPoint(x: x, y: y), r + width / 2), with: .color(ink))
        }
        for (x, y, r) in circles {
            ctx.fill(circle(CGPoint(x: x, y: y), r - width / 2), with: .color(fill))
        }
    }

    /// A four-point twinkle.
    static func sparkle(_ ctx: inout GraphicsContext, at c: CGPoint, size s: CGFloat, color: Color = .white) {
        let k = s * 0.16
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - s))
        p.addQuadCurve(to: CGPoint(x: c.x + s, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + s), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x - s, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - s), control: CGPoint(x: c.x - k, y: c.y - k))
        p.closeSubpath()
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: gold.opacity(0.9), radius: s * 0.35, x: 0, y: 0))
            layer.fill(p, with: .color(color))
        }
    }

    /// A short numeral in cream with a thick ink outline.
    static func numeral(_ ctx: inout GraphicsContext, _ text: String, at p: CGPoint, size: CGFloat) {
        let font = Font.system(size: size, weight: .black, design: .rounded)
        let outline = ctx.resolve(Text(text).font(font).foregroundStyle(ink))
        let fill = ctx.resolve(Text(text).font(font).foregroundStyle(card))
        let r = size * 0.055
        for i in 0..<16 {
            let a = Double(i) * Double.pi / 8
            ctx.draw(outline, at: polar(a, r, around: p), anchor: .center)
        }
        ctx.draw(fill, at: p, anchor: .center)
    }

    /// The glowing gold fill line from AppIconArt, with its tab on the right.
    static func goldLine(_ ctx: inout GraphicsContext, y: CGFloat, from left: CGFloat, to right: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: left, y: y))
        path.addLine(to: CGPoint(x: right, y: y))
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: gold.opacity(0.95), radius: 22, x: 0, y: 0))
            layer.stroke(path, with: .color(gold), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        }
        ctx.stroke(path, with: .color(Color(brimHex: 0xFFE9A6)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        let tab = CGRect(x: right + 8, y: y - 14, width: 28, height: 28)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: gold.opacity(0.8), radius: 10, x: 0, y: 0))
            layer.fill(Path(roundedRect: tab, cornerRadius: 8), with: .color(gold))
        }
        ctx.stroke(Path(roundedRect: tab, cornerRadius: 8), with: .color(ink), lineWidth: 6)
    }

    /// A tapered tumbler: rim at the top, rounded base.
    struct Glass {
        let cx: CGFloat
        let rimY: CGFloat
        let baseY: CGFloat
        let rimHalf: CGFloat
        let baseHalf: CGFloat

        func half(at y: CGFloat) -> CGFloat {
            let t = min(max((y - rimY) / (baseY - rimY), 0), 1)
            return rimHalf + (baseHalf - rimHalf) * t
        }

        var path: Path {
            let r = min(baseHalf * 0.3, 28)
            var p = Path()
            p.move(to: CGPoint(x: cx - rimHalf, y: rimY))
            p.addLine(to: CGPoint(x: cx + rimHalf, y: rimY))
            p.addLine(to: CGPoint(x: cx + baseHalf, y: baseY - r))
            p.addQuadCurve(to: CGPoint(x: cx + baseHalf - r, y: baseY), control: CGPoint(x: cx + baseHalf, y: baseY))
            p.addLine(to: CGPoint(x: cx - baseHalf + r, y: baseY))
            p.addQuadCurve(to: CGPoint(x: cx - baseHalf, y: baseY - r), control: CGPoint(x: cx - baseHalf, y: baseY))
            p.closeSubpath()
            return p
        }
    }

    /// Glass body, optional liquid up to `level`, gloss and ink outline.
    static func drawGlass(_ ctx: inout GraphicsContext, _ glass: Glass, level: CGFloat?, liquid: [Color],
                          width: CGFloat = 14) {
        let path = glass.path
        ctx.fill(path, with: .color(Color.white.opacity(0.55)))
        if let level {
            let height = glass.baseY - level
            ctx.drawLayer { layer in
                layer.clip(to: path)
                let rect = CGRect(x: glass.cx - glass.rimHalf - 4, y: level, width: glass.rimHalf * 2 + 8, height: height + 4)
                layer.fill(Path(rect), with: .linearGradient(Gradient(colors: liquid),
                                                             startPoint: CGPoint(x: glass.cx, y: level),
                                                             endPoint: CGPoint(x: glass.cx, y: glass.baseY)))
                let band = CGRect(x: rect.minX, y: level, width: rect.width, height: max(height * 0.06, 6))
                layer.fill(Path(band), with: .color(Color.white.opacity(0.45)))
            }
        }
        // Gloss streak down the left wall.
        let h = glass.baseY - glass.rimY
        let x = glass.cx - glass.half(at: glass.rimY + h * 0.2) + glass.rimHalf * 0.2
        let streak = CGRect(x: x, y: glass.rimY + h * 0.12, width: max(glass.rimHalf * 0.13, 8), height: h * 0.6)
        ctx.fill(Path(roundedRect: streak, cornerRadius: streak.width / 2), with: .color(Color.white.opacity(0.6)))
        ctx.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    // MARK: Background and medallion

    static func background(_ ctx: inout GraphicsContext, tier: Tier) {
        let all = Path(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let colors: [Color]
        switch tier {
        case .one: colors = [Color(brimHex: 0xFFF4E2), Color(brimHex: 0xFFE3C4), Color(brimHex: 0xFFCFA6)]
        case .two: colors = [Color(brimHex: 0xFFEBD3), Color(brimHex: 0xFFC9A3), Color(brimHex: 0xFFB085)]
        case .three: colors = [Color(brimHex: 0xFFE2B0), Color(brimHex: 0xFFB98A), Color(brimHex: 0xF4906A)]
        }
        ctx.fill(all, with: .linearGradient(Gradient(colors: colors),
                                            startPoint: CGPoint(x: 380, y: 0), endPoint: CGPoint(x: 640, y: 1024)))
        // Sun rays from the middle.
        var rays = Path()
        let count = 24
        for i in stride(from: 0, to: count, by: 2) {
            let a0 = Double(i) / Double(count) * 2 * Double.pi
            let a1 = Double(i + 1) / Double(count) * 2 * Double.pi
            rays.move(to: center)
            rays.addLine(to: polar(a0, 900, around: center))
            rays.addLine(to: polar(a1, 900, around: center))
            rays.closeSubpath()
        }
        ctx.fill(rays, with: .color(Color.white.opacity(0.14)))
        ctx.fill(all, with: .radialGradient(Gradient(colors: [Color.white.opacity(0.4), Color.white.opacity(0)]),
                                            center: center, startRadius: 0, endRadius: 560))
        seam(&ctx)
    }

    /// The Duo's fold across the middle, as on the app icon.
    static func seam(_ ctx: inout GraphicsContext) {
        let y: CGFloat = 512
        ctx.fill(Path(CGRect(x: 0, y: y - 22, width: 1024, height: 44)), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(brimHex: 0xC9835E).opacity(0), location: 0),
                .init(color: Color(brimHex: 0xC9835E).opacity(0.3), location: 0.48),
                .init(color: Color(brimHex: 0xC9835E).opacity(0), location: 1),
            ]),
            startPoint: CGPoint(x: 0, y: y - 22), endPoint: CGPoint(x: 0, y: y + 22)))
        var dark = Path()
        dark.move(to: CGPoint(x: 0, y: y - 1.5))
        dark.addLine(to: CGPoint(x: 1024, y: y - 1.5))
        ctx.stroke(dark, with: .color(Color(brimHex: 0xB8704C).opacity(0.45)), lineWidth: 5)
        var light = Path()
        light.move(to: CGPoint(x: 0, y: y + 3.5))
        light.addLine(to: CGPoint(x: 1024, y: y + 3.5))
        ctx.stroke(light, with: .color(Color.white.opacity(0.55)), lineWidth: 3)
    }

    static func medallion(_ ctx: inout GraphicsContext, style: Style) {
        let ring: [Color]
        let stud: Color
        let pin: Color
        switch style.tier {
        case .one:
            ring = [tealLight, teal, tealDark]
            stud = cream.opacity(0.9)
            pin = gold
        case .two:
            ring = [Color(brimHex: 0x2FA79A), tealDark, Color(brimHex: 0x15524C)]
            stud = gold
            pin = gold
        case .three:
            ring = [Color(brimHex: 0xFFE38A), gold, goldDeep]
            stud = card
            pin = teal
        }
        let outer = circle(center, 410)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: Color(brimHex: 0x7A3E22).opacity(0.3), radius: 24, x: 0, y: 14))
            layer.fill(outer, with: .color(ink))
        }
        ctx.fill(outer, with: vertical(ring, 102, 922))
        ctx.stroke(circle(center, 396), with: .color(Color.white.opacity(0.3)), lineWidth: 6)
        for i in 0..<20 {
            let a = Double(i) / 20 * 2 * Double.pi - Double.pi / 2
            ctx.fill(circle(polar(a, 372, around: center), 10), with: .color(stud))
        }
        ctx.stroke(circle(center, 345), with: .color(pin), lineWidth: 8)

        let inner = circle(center, 330)
        ctx.fill(inner, with: .color(card))
        ctx.fill(inner, with: vertical([style.accent.opacity(0.12), style.accent.opacity(0.5)], 182, 842))
        ctx.fill(inner, with: .radialGradient(Gradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)]),
                                              center: CGPoint(x: 512, y: 420), startRadius: 0, endRadius: 300))
        ctx.stroke(inner, with: .color(ink), lineWidth: 12)
        ctx.stroke(outer, with: .color(ink), lineWidth: 18)
    }

    // MARK: brim.first.perfect: a glass filled exactly to a glowing line

    static func perfectGlass(_ ctx: inout GraphicsContext) {
        let coaster = CGRect(x: 512 - 210, y: 702, width: 420, height: 56)
        inked(&ctx, Path(ellipseIn: coaster), vertical([terracotta, terracottaDeep], 702, 758), width: 10)
        let glass = Glass(cx: 512, rimY: 300, baseY: 726, rimHalf: 172, baseHalf: 132)
        let level: CGFloat = 430
        drawGlass(&ctx, glass, level: level, liquid: [lemonTop, lemonBottom])
        for (x, y, r) in [(470.0, 560.0, 12.0), (560.0, 520.0, 9.0), (530.0, 640.0, 8.0), (590.0, 610.0, 13.0),
                          (450.0, 660.0, 7.0)] {
            ctx.fill(circle(CGPoint(x: x, y: y), CGFloat(r)), with: .color(Color.white.opacity(0.55)))
        }
        let half = glass.half(at: level)
        goldLine(&ctx, y: level, from: 512 - half - 26, to: 512 + half + 26)
        sparkle(&ctx, at: CGPoint(x: 735, y: 318), size: 44)
        sparkle(&ctx, at: CGPoint(x: 296, y: 372), size: 30)
        sparkle(&ctx, at: CGPoint(x: 668, y: 262), size: 22)
    }

    // MARK: brim.streak.*: flame and number

    static func flamePath(scale s: CGFloat, base: CGPoint) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: base.x + x * s, y: base.y + y * s) }
        var p = Path()
        p.move(to: pt(0, -540))
        p.addCurve(to: pt(190, -210), control1: pt(60, -430), control2: pt(205, -330))
        p.addCurve(to: pt(0, 0), control1: pt(180, -80), control2: pt(100, 0))
        p.addCurve(to: pt(-190, -210), control1: pt(-100, 0), control2: pt(-180, -80))
        p.addCurve(to: pt(-120, -400), control1: pt(-200, -300), control2: pt(-160, -360))
        p.addCurve(to: pt(-60, -300), control1: pt(-100, -350), control2: pt(-80, -320))
        p.addCurve(to: pt(0, -540), control1: pt(-60, -400), control2: pt(-30, -480))
        p.closeSubpath()
        return p
    }

    static func flame(_ ctx: inout GraphicsContext, number: String, embers: Int) {
        let base = CGPoint(x: 512, y: 796)
        let outer = flamePath(scale: 1, base: base)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: Color(brimHex: 0xFF8A2C).opacity(0.6), radius: 30, x: 0, y: 0))
            layer.fill(outer, with: .color(Color(brimHex: 0xFF8A2C)))
        }
        inked(&ctx, outer, vertical([Color(brimHex: 0xF0603A), Color(brimHex: 0xFF8A2C), lemonBottom], 256, 796))
        ctx.fill(flamePath(scale: 0.64, base: CGPoint(x: 512, y: 786)), with: vertical([gold, lemonTop], 440, 786))
        ctx.fill(flamePath(scale: 0.34, base: CGPoint(x: 512, y: 776)), with: .color(Color(brimHex: 0xFFF6B8)))
        let spots: [(CGFloat, CGFloat, CGFloat)] = [(310, 360, 13), (722, 400, 11), (690, 286, 9), (296, 470, 8),
                                                    (742, 520, 9), (352, 286, 7)]
        for (x, y, r) in spots.prefix(embers) {
            inked(&ctx, circle(CGPoint(x: x, y: y), r), .color(lemonBottom), width: 6)
        }
        numeral(&ctx, number, at: CGPoint(x: 512, y: 620), size: 230)
        if embers > 3 {
            sparkle(&ctx, at: CGPoint(x: 700, y: 640), size: 34)
            sparkle(&ctx, at: CGPoint(x: 318, y: 600), size: 26)
        }
    }

    // MARK: brim.litres.10: a big drop, "10 L"

    static func drop(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(ellipseIn: CGRect(x: 362, y: 768, width: 300, height: 40)), with: .color(teal.opacity(0.3)))
        var p = Path()
        p.move(to: CGPoint(x: 512, y: 214))
        p.addCurve(to: CGPoint(x: 700, y: 590), control1: CGPoint(x: 560, y: 320), control2: CGPoint(x: 700, y: 440))
        p.addCurve(to: CGPoint(x: 512, y: 778), control1: CGPoint(x: 700, y: 694), control2: CGPoint(x: 616, y: 778))
        p.addCurve(to: CGPoint(x: 324, y: 590), control1: CGPoint(x: 408, y: 778), control2: CGPoint(x: 324, y: 694))
        p.addCurve(to: CGPoint(x: 512, y: 214), control1: CGPoint(x: 324, y: 440), control2: CGPoint(x: 464, y: 320))
        p.closeSubpath()
        inked(&ctx, p, vertical([Color(brimHex: 0x9BEAF2), Color(brimHex: 0x3FC6D8), teal], 214, 778))
        var gloss = Path()
        gloss.move(to: CGPoint(x: 410, y: 470))
        gloss.addQuadCurve(to: CGPoint(x: 378, y: 640), control: CGPoint(x: 370, y: 540))
        ctx.stroke(gloss, with: .color(Color.white.opacity(0.7)), style: StrokeStyle(lineWidth: 24, lineCap: .round))
        ctx.fill(circle(CGPoint(x: 432, y: 418), 12), with: .color(Color.white.opacity(0.7)))
        numeral(&ctx, "10", at: CGPoint(x: 518, y: 570), size: 190)
        numeral(&ctx, "L", at: CGPoint(x: 518, y: 700), size: 100)
        inked(&ctx, circle(CGPoint(x: 312, y: 742), 16), .color(Color(brimHex: 0x3FC6D8)), width: 7)
        inked(&ctx, circle(CGPoint(x: 724, y: 724), 12), .color(Color(brimHex: 0x3FC6D8)), width: 7)
        sparkle(&ctx, at: CGPoint(x: 690, y: 300), size: 34)
    }

    // MARK: brim.venue.soda: soda dispenser with a foaming glass

    static func sodaDispenser(_ ctx: inout GraphicsContext) {
        // Drip tray.
        inked(&ctx, Path(roundedRect: CGRect(x: 362, y: 760, width: 300, height: 36), cornerRadius: 14),
              vertical([tealLight, tealDark], 760, 796), width: 10)
        // Body, cap and window.
        let body = Path(roundedRect: CGRect(x: 372, y: 262, width: 280, height: 278), cornerRadius: 38)
        inked(&ctx, body, horizontal([Color(brimHex: 0xF6A097), Color(brimHex: 0xF0857A), Color(brimHex: 0xD9655A)],
                                     372, 652))
        ctx.fill(Path(roundedRect: CGRect(x: 396, y: 300, width: 20, height: 210), cornerRadius: 10),
                 with: .color(Color.white.opacity(0.35)))
        inked(&ctx, Path(roundedRect: CGRect(x: 352, y: 236, width: 320, height: 60), cornerRadius: 28),
              vertical([tealLight, teal, tealDark], 236, 296))
        let window = Path(roundedRect: CGRect(x: 430, y: 312, width: 164, height: 130), cornerRadius: 24)
        ctx.fill(window, with: .color(card))
        ctx.drawLayer { layer in
            layer.clip(to: window)
            layer.fill(Path(CGRect(x: 430, y: 356, width: 164, height: 90)),
                       with: vertical([Color(brimHex: 0xF26A5E), Color(brimHex: 0xC94A45)], 356, 442))
            for (x, y, r) in [(462.0, 400.0, 8.0), (520.0, 420.0, 6.0), (560.0, 384.0, 9.0), (496.0, 372.0, 5.0)] {
                layer.fill(circle(CGPoint(x: x, y: y), CGFloat(r)), with: .color(Color.white.opacity(0.7)))
            }
        }
        ctx.stroke(window, with: .color(ink), lineWidth: 10)
        inked(&ctx, circle(CGPoint(x: 512, y: 494), 22), .color(gold), width: 10)
        // Nozzle and stream.
        var nozzle = Path()
        nozzle.move(to: CGPoint(x: 486, y: 540))
        nozzle.addLine(to: CGPoint(x: 538, y: 540))
        nozzle.addLine(to: CGPoint(x: 530, y: 582))
        nozzle.addLine(to: CGPoint(x: 494, y: 582))
        nozzle.closeSubpath()
        ctx.fill(Path(roundedRect: CGRect(x: 504, y: 578, width: 16, height: 52), cornerRadius: 8),
                 with: .color(Color(brimHex: 0xF26A5E)))
        inked(&ctx, nozzle, .color(tealDark), width: 10)
        // Glass with a foam head.
        let glass = Glass(cx: 512, rimY: 640, baseY: 760, rimHalf: 74, baseHalf: 58)
        drawGlass(&ctx, glass, level: 668, liquid: [Color(brimHex: 0xF26A5E), Color(brimHex: 0xC94A45)], width: 11)
        blob(&ctx, [(462, 650, 24), (494, 640, 26), (530, 642, 26), (562, 652, 22), (512, 618, 26)], fill: card)
        sparkle(&ctx, at: CGPoint(x: 690, y: 640), size: 30)
        sparkle(&ctx, at: CGPoint(x: 330, y: 600), size: 22)
    }

    // MARK: brim.venue.diner: a shake tin topped with milkshake

    static func shakeTin(_ ctx: inout GraphicsContext) {
        // Straw (behind the shake).
        var straw = Path()
        straw.move(to: CGPoint(x: 548, y: 330))
        straw.addLine(to: CGPoint(x: 622, y: 224))
        ctx.stroke(straw, with: .color(ink), style: StrokeStyle(lineWidth: 40, lineCap: .round))
        ctx.stroke(straw, with: .color(teal), style: StrokeStyle(lineWidth: 26, lineCap: .round))
        ctx.stroke(straw, with: .color(card), style: StrokeStyle(lineWidth: 26, lineCap: .butt, dash: [16, 18]))
        // Tin: wide at the top, narrowing down.
        let top: CGFloat = 360
        let bottom: CGFloat = 780
        func half(_ y: CGFloat) -> CGFloat { 112 + (76 - 112) * (y - top) / (bottom - top) }
        var tin = Path()
        tin.move(to: CGPoint(x: 512 - 112, y: top))
        tin.addLine(to: CGPoint(x: 512 + 112, y: top))
        tin.addLine(to: CGPoint(x: 512 + 76, y: bottom - 24))
        tin.addQuadCurve(to: CGPoint(x: 512 + 52, y: bottom), control: CGPoint(x: 512 + 76, y: bottom))
        tin.addLine(to: CGPoint(x: 512 - 52, y: bottom))
        tin.addQuadCurve(to: CGPoint(x: 512 - 76, y: bottom - 24), control: CGPoint(x: 512 - 76, y: bottom))
        tin.closeSubpath()
        ctx.fill(tin, with: horizontal([Color(brimHex: 0xF4F7F8), Color(brimHex: 0xC9D5DA), Color(brimHex: 0x9FB1B8)],
                                       400, 624))
        ctx.fill(Path(roundedRect: CGRect(x: 430, y: 430, width: 22, height: 270), cornerRadius: 11),
                 with: .color(Color.white.opacity(0.75)))
        for y in [CGFloat(414), CGFloat(722)] {
            var band = Path()
            band.move(to: CGPoint(x: 512 - half(y), y: y))
            band.addLine(to: CGPoint(x: 512 + half(y), y: y))
            ctx.stroke(band, with: .color(ink), lineWidth: 8)
        }
        ctx.stroke(tin, with: .color(ink), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        // Milkshake mound, cherry on top.
        blob(&ctx, [(452, 352, 50), (512, 334, 62), (572, 352, 50), (512, 288, 44)], fill: Color(brimHex: 0xF6A5C0))
        ctx.fill(circle(CGPoint(x: 486, y: 300), 12), with: .color(Color.white.opacity(0.6)))
        ctx.fill(circle(CGPoint(x: 444, y: 346), 9), with: .color(Color.white.opacity(0.55)))
        var stem = Path()
        stem.move(to: CGPoint(x: 522, y: 222))
        stem.addQuadCurve(to: CGPoint(x: 552, y: 196), control: CGPoint(x: 526, y: 200))
        ctx.stroke(stem, with: .color(ink), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        inked(&ctx, circle(CGPoint(x: 518, y: 240), 26), .color(spill), width: 10)
        ctx.fill(circle(CGPoint(x: 509, y: 232), 7), with: .color(Color.white.opacity(0.75)))
        // Shake lines either side.
        for side in [CGFloat(-1), CGFloat(1)] {
            for (dy, reach) in [(CGFloat(-40), CGFloat(44)), (CGFloat(10), CGFloat(56)), (CGFloat(60), CGFloat(44))] {
                var m = Path()
                let x0 = 512 + side * 150
                m.move(to: CGPoint(x: x0, y: 520 + dy))
                m.addQuadCurve(to: CGPoint(x: x0 + side * reach, y: 520 + dy + 14),
                               control: CGPoint(x: x0 + side * reach * 0.5, y: 520 + dy - 10))
                ctx.stroke(m, with: .color(ink), style: StrokeStyle(lineWidth: 11, lineCap: .round))
            }
        }
    }

    // MARK: brim.venue.conveyor: rollers carrying glasses

    static func conveyor(_ ctx: inout GraphicsContext) {
        // Direction arrow.
        var arrow = Path()
        arrow.move(to: CGPoint(x: 344, y: 300))
        arrow.addLine(to: CGPoint(x: 590, y: 300))
        arrow.addLine(to: CGPoint(x: 590, y: 256))
        arrow.addLine(to: CGPoint(x: 680, y: 322))
        arrow.addLine(to: CGPoint(x: 590, y: 388))
        arrow.addLine(to: CGPoint(x: 590, y: 344))
        arrow.addLine(to: CGPoint(x: 344, y: 344))
        arrow.closeSubpath()
        inked(&ctx, arrow, vertical([tealLight, teal], 256, 388))
        for (x, w) in [(CGFloat(286), CGFloat(30)), (CGFloat(250), CGFloat(18))] {
            var dash = Path()
            dash.move(to: CGPoint(x: x, y: 322))
            dash.addLine(to: CGPoint(x: x + w, y: 322))
            ctx.stroke(dash, with: .color(ink), style: StrokeStyle(lineWidth: 12, lineCap: .round))
        }
        // Glasses riding the belt.
        let left = Glass(cx: 386, rimY: 446, baseY: 600, rimHalf: 64, baseHalf: 48)
        drawGlass(&ctx, left, level: 494, liquid: [lemonTop, lemonBottom], width: 11)
        goldLine(&ctx, y: 494, from: 386 - left.half(at: 494) - 14, to: 386 + left.half(at: 494) + 14)
        let right = Glass(cx: 630, rimY: 446, baseY: 600, rimHalf: 64, baseHalf: 48)
        drawGlass(&ctx, right, level: 548, liquid: [Color(brimHex: 0xF6A5C0), Color(brimHex: 0xE57FA5)], width: 11)
        // Belt and rollers.
        let belt = Path(roundedRect: CGRect(x: 244, y: 600, width: 536, height: 110), cornerRadius: 55)
        inked(&ctx, belt, vertical([Color(brimHex: 0x6E7C8C), Color(brimHex: 0x4A5568)], 600, 710))
        for x in [CGFloat(302), CGFloat(407), CGFloat(512), CGFloat(617), CGFloat(722)] {
            let c = CGPoint(x: x, y: 655)
            inked(&ctx, circle(c, 34), .linearGradient(Gradient(colors: [Color(brimHex: 0xEEF3F5), Color(brimHex: 0xA9BAC2)]),
                                                       startPoint: CGPoint(x: x - 34, y: 621),
                                                       endPoint: CGPoint(x: x + 34, y: 689)), width: 9)
            ctx.fill(circle(c, 9), with: .color(ink))
        }
        sparkle(&ctx, at: CGPoint(x: 712, y: 450), size: 28)
    }

    // MARK: brim.venue.potions: a round flask measured to the line

    static func potionFlask(_ ctx: inout GraphicsContext) {
        let bulb = CGPoint(x: 512, y: 580)
        let radius: CGFloat = 190
        let neckHalf: CGFloat = 50
        let phi = asin(Double(neckHalf / radius))
        let start = -Double.pi / 2 - phi
        let sweep = 2 * Double.pi - 2 * phi
        var flask = Path()
        flask.move(to: CGPoint(x: 512 - neckHalf, y: 276))
        let steps = 120
        for i in 0...steps {
            flask.addLine(to: polar(start - sweep * Double(i) / Double(steps), radius, around: bulb))
        }
        flask.addLine(to: CGPoint(x: 512 + neckHalf, y: 276))
        flask.closeSubpath()

        ctx.fill(flask, with: .color(Color.white.opacity(0.55)))
        let level: CGFloat = 500
        ctx.drawLayer { layer in
            layer.clip(to: flask)
            layer.fill(Path(CGRect(x: 300, y: level, width: 424, height: 300)),
                       with: vertical([Color(brimHex: 0xC4B0FF), Color(brimHex: 0xA78BFA), Color(brimHex: 0x7C5CE0)],
                                      level, 770))
            layer.fill(Path(CGRect(x: 300, y: level, width: 424, height: 14)), with: .color(Color(brimHex: 0xE6DCFF)))
            for (x, y, r) in [(470.0, 640.0, 14.0), (560.0, 600.0, 10.0), (530.0, 700.0, 8.0), (600.0, 670.0, 12.0),
                              (440.0, 560.0, 7.0)] {
                layer.fill(circle(CGPoint(x: x, y: y), CGFloat(r)), with: .color(Color.white.opacity(0.55)))
            }
        }
        var gloss = Path()
        for i in 0...24 {
            let a = Double.pi * (1.12 + 0.3 * Double(i) / 24)
            let p = polar(a, 150, around: bulb)
            if i == 0 { gloss.move(to: p) } else { gloss.addLine(to: p) }
        }
        ctx.stroke(gloss, with: .color(Color.white.opacity(0.7)), style: StrokeStyle(lineWidth: 22, lineCap: .round))
        ctx.stroke(flask, with: .color(ink), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        let surfaceHalf = CGFloat(sqrt(Double(radius * radius - (level - bulb.y) * (level - bulb.y))))
        goldLine(&ctx, y: level, from: 512 - surfaceHalf - 22, to: 512 + surfaceHalf + 22)
        // Lip and cork.
        inked(&ctx, Path(roundedRect: CGRect(x: 446, y: 264, width: 132, height: 28), cornerRadius: 14), .color(card),
              width: 10)
        inked(&ctx, Path(roundedRect: CGRect(x: 468, y: 222, width: 88, height: 46), cornerRadius: 12),
              vertical([terracotta, terracottaDeep], 222, 268), width: 10)
        sparkle(&ctx, at: CGPoint(x: 690, y: 336), size: 34)
        sparkle(&ctx, at: CGPoint(x: 336, y: 370), size: 24)
        sparkle(&ctx, at: CGPoint(x: 640, y: 250), size: 18)
    }

    // MARK: brim.allstars: three stars

    static func starPath(center c: CGPoint, radius r: CGFloat) -> Path {
        var p = Path()
        for i in 0..<10 {
            let a = -Double.pi / 2 + Double(i) * Double.pi / 5
            let point = polar(a, i % 2 == 0 ? r : r * 0.47, around: c)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }

    static func star(_ ctx: inout GraphicsContext, center c: CGPoint, radius r: CGFloat) {
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [lemonTop, gold, goldDeep]),
            startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r))
        inked(&ctx, starPath(center: c, radius: r), shading)
        ctx.fill(starPath(center: CGPoint(x: c.x - r * 0.06, y: c.y - r * 0.1), radius: r * 0.42),
                 with: .color(Color.white.opacity(0.35)))
    }

    static func threeStars(_ ctx: inout GraphicsContext) {
        ctx.fill(circle(CGPoint(x: 512, y: 470), 260), with: .radialGradient(
            Gradient(colors: [gold.opacity(0.55), gold.opacity(0)]),
            center: CGPoint(x: 512, y: 470), startRadius: 0, endRadius: 260))
        star(&ctx, center: CGPoint(x: 336, y: 610), radius: 112)
        star(&ctx, center: CGPoint(x: 688, y: 610), radius: 112)
        star(&ctx, center: CGPoint(x: 512, y: 452), radius: 190)
        sparkle(&ctx, at: CGPoint(x: 700, y: 330), size: 34)
        sparkle(&ctx, at: CGPoint(x: 320, y: 360), size: 26)
        sparkle(&ctx, at: CGPoint(x: 512, y: 740), size: 30)
    }

    // MARK: brim.sandbar: an hourglass

    static func hourglass(_ ctx: inout GraphicsContext) {
        // Posts behind the glass.
        for x in [CGFloat(372), CGFloat(628)] {
            inked(&ctx, Path(roundedRect: CGRect(x: x, y: 270, width: 24, height: 480), cornerRadius: 12),
                  horizontal([terracotta, terracottaDeep], x, x + 24), width: 10)
        }
        var glass = Path()
        glass.move(to: CGPoint(x: 412, y: 280))
        glass.addLine(to: CGPoint(x: 612, y: 280))
        glass.addCurve(to: CGPoint(x: 526, y: 512), control1: CGPoint(x: 612, y: 410), control2: CGPoint(x: 532, y: 450))
        glass.addCurve(to: CGPoint(x: 612, y: 744), control1: CGPoint(x: 532, y: 574), control2: CGPoint(x: 612, y: 614))
        glass.addLine(to: CGPoint(x: 412, y: 744))
        glass.addCurve(to: CGPoint(x: 498, y: 512), control1: CGPoint(x: 412, y: 614), control2: CGPoint(x: 492, y: 574))
        glass.addCurve(to: CGPoint(x: 412, y: 280), control1: CGPoint(x: 492, y: 450), control2: CGPoint(x: 412, y: 410))
        glass.closeSubpath()
        ctx.fill(glass, with: .color(Color.white.opacity(0.55)))
        let sand = vertical([Color(brimHex: 0xF2D7A6), Color(brimHex: 0xE4C08A), Color(brimHex: 0xC99A5B)], 380, 744)
        ctx.drawLayer { layer in
            layer.clip(to: glass)
            layer.fill(Path(CGRect(x: 400, y: 404, width: 224, height: 110)), with: sand)
            layer.fill(Path(roundedRect: CGRect(x: 507, y: 500, width: 10, height: 160), cornerRadius: 5), with: sand)
            var mound = Path()
            mound.move(to: CGPoint(x: 380, y: 770))
            mound.addLine(to: CGPoint(x: 380, y: 732))
            mound.addQuadCurve(to: CGPoint(x: 512, y: 640), control: CGPoint(x: 444, y: 650))
            mound.addQuadCurve(to: CGPoint(x: 644, y: 732), control: CGPoint(x: 580, y: 650))
            mound.addLine(to: CGPoint(x: 644, y: 770))
            mound.closeSubpath()
            layer.fill(mound, with: sand)
        }
        var gloss = Path()
        gloss.move(to: CGPoint(x: 438, y: 306))
        gloss.addQuadCurve(to: CGPoint(x: 470, y: 420), control: CGPoint(x: 440, y: 380))
        ctx.stroke(gloss, with: .color(Color.white.opacity(0.75)), style: StrokeStyle(lineWidth: 16, lineCap: .round))
        var gloss2 = Path()
        gloss2.move(to: CGPoint(x: 470, y: 600))
        gloss2.addQuadCurve(to: CGPoint(x: 436, y: 690), control: CGPoint(x: 440, y: 640))
        ctx.stroke(gloss2, with: .color(Color.white.opacity(0.6)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
        ctx.stroke(glass, with: .color(ink), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        // Caps.
        for y in [CGFloat(236), CGFloat(744)] {
            inked(&ctx, Path(roundedRect: CGRect(x: 352, y: y, width: 320, height: 44), cornerRadius: 18),
                  vertical([terracotta, terracottaDeep], y, y + 44), width: 12)
        }
        sparkle(&ctx, at: CGPoint(x: 712, y: 420), size: 32)
        sparkle(&ctx, at: CGPoint(x: 312, y: 600), size: 24)
        sparkle(&ctx, at: CGPoint(x: 560, y: 560), size: 16, color: Color(brimHex: 0xFFF6B8))
    }
}
