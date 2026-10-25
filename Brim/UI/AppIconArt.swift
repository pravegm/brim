import SwiftUI

/// The App Store icon: a tipped teal jug pours a glossy lemonade stream down into a glass filled exactly to a glowing
/// gold line, on a warm cream → peach gradient, with a subtle horizontal fold seam across the middle (the iPhone Duo:
/// jug on the top half, glass on the bottom half, the stream crossing the fold).
///
/// Pure vector in a 1024-unit design space (no text, no symbols, no images), full-bleed, opaque and square-cornered:
/// the system applies the mask. Rendered to Documents/AppIcon-1024.png by demo `screen=icon` (IconExport).
struct AppIconArt: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                let scale = min(size.width, size.height) / 1024
                context.scaleBy(x: scale, y: scale)
                IconPainter.paint(&context)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private enum IconPainter {
    // Palette
    static let cream = Color(brimHex: 0xFFF4E2)
    static let apricot = Color(brimHex: 0xFFDDBB)
    static let peach = Color(brimHex: 0xFFB689)
    static let gold = Color(brimHex: 0xFFC23D)
    static let lemonTop = Color(brimHex: 0xFFE772)
    static let lemonBottom = Color(brimHex: 0xFFAA2C)
    static let tealLight = Color(brimHex: 0x45C2B4)
    static let teal = Color(brimHex: 0x2A9A8E)
    static let tealDark = Color(brimHex: 0x1B6E66)
    static let coaster = Color(brimHex: 0xD9825B)
    static let coasterDark = Color(brimHex: 0xB4613D)

    // Glass geometry (design space, y down)
    static let rimY: CGFloat = 588
    static let floorY: CGFloat = 888
    static let baseY: CGFloat = 930
    static let lineY: CGFloat = 702
    static let glassCenterX: CGFloat = 604

    static func paint(_ ctx: inout GraphicsContext) {
        background(&ctx)
        seam(&ctx)
        coasterShape(&ctx)
        glassBack(&ctx)
        liquid(&ctx)
        stream(&ctx)
        glassFront(&ctx)
        fillLine(&ctx)
        splash(&ctx)
        jug(&ctx)
    }

    // MARK: Background and fold

    static func background(_ ctx: inout GraphicsContext) {
        let all = Path(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        ctx.fill(all, with: .linearGradient(
            Gradient(stops: [
                .init(color: cream, location: 0),
                .init(color: apricot, location: 0.55),
                .init(color: peach, location: 1),
            ]),
            startPoint: CGPoint(x: 380, y: 0), endPoint: CGPoint(x: 640, y: 1024)))
        // Warm glow behind the glass.
        ctx.fill(all, with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)]),
            center: CGPoint(x: glassCenterX, y: 740), startRadius: 0, endRadius: 420))
    }

    /// The Duo's fold: a soft shaded band with a highlight lip, right across the middle.
    static func seam(_ ctx: inout GraphicsContext) {
        let y: CGFloat = 512
        ctx.fill(Path(CGRect(x: 0, y: y - 22, width: 1024, height: 44)), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(brimHex: 0xC9835E).opacity(0), location: 0),
                .init(color: Color(brimHex: 0xC9835E).opacity(0.34), location: 0.48),
                .init(color: Color(brimHex: 0xC9835E).opacity(0.0), location: 1),
            ]),
            startPoint: CGPoint(x: 0, y: y - 22), endPoint: CGPoint(x: 0, y: y + 22)))
        // REVIEW-1 P2-5: a 5-unit seam with a soft shadow, so "foldable" survives at home-screen size.
        var dark = Path()
        dark.move(to: CGPoint(x: 0, y: y - 1.5))
        dark.addLine(to: CGPoint(x: 1024, y: y - 1.5))
        ctx.stroke(dark, with: .color(Color(brimHex: 0xB8704C).opacity(0.5)), lineWidth: 5)
        var light = Path()
        light.move(to: CGPoint(x: 0, y: y + 3.5))
        light.addLine(to: CGPoint(x: 1024, y: y + 3.5))
        ctx.stroke(light, with: .color(Color.white.opacity(0.6)), lineWidth: 3)
    }

    // MARK: Glass

    static func coasterShape(_ ctx: inout GraphicsContext) {
        let rect = CGRect(x: glassCenterX - 210, y: baseY - 18, width: 420, height: 50)
        ctx.fill(Path(ellipseIn: rect.offsetBy(dx: 0, dy: 10)), with: .color(coasterDark.opacity(0.9)))
        ctx.fill(Path(ellipseIn: rect), with: .color(coaster))
    }

    /// Interior half-width at height `y` (linear taper rim → floor).
    static func interiorX(_ y: CGFloat) -> (CGFloat, CGFloat) {
        let rimHalf: CGFloat = 150
        let floorHalf: CGFloat = 118
        let t = min(max((y - rimY) / (floorY - rimY), 0), 1)
        let half = rimHalf + (floorHalf - rimHalf) * t
        return (glassCenterX - half, glassCenterX + half)
    }

    static func outerPath() -> Path {
        var p = Path()
        let rimHalf: CGFloat = 172
        let baseHalf: CGFloat = 134
        let r: CGFloat = 34
        p.move(to: CGPoint(x: glassCenterX - rimHalf, y: rimY - 8))
        p.addLine(to: CGPoint(x: glassCenterX + rimHalf, y: rimY - 8))
        p.addLine(to: CGPoint(x: glassCenterX + baseHalf + 4, y: baseY - r))
        p.addQuadCurve(to: CGPoint(x: glassCenterX + baseHalf - r, y: baseY),
                       control: CGPoint(x: glassCenterX + baseHalf, y: baseY))
        p.addLine(to: CGPoint(x: glassCenterX - baseHalf + r, y: baseY))
        p.addQuadCurve(to: CGPoint(x: glassCenterX - baseHalf - 4, y: baseY - r),
                       control: CGPoint(x: glassCenterX - baseHalf, y: baseY))
        p.closeSubpath()
        return p
    }

    static func interiorPath(from top: CGFloat) -> Path {
        let (tl, tr) = interiorX(top)
        let (bl, br) = interiorX(floorY)
        let r: CGFloat = 22
        var p = Path()
        p.move(to: CGPoint(x: tl, y: top))
        p.addLine(to: CGPoint(x: tr, y: top))
        p.addLine(to: CGPoint(x: br, y: floorY - r))
        p.addQuadCurve(to: CGPoint(x: br - r, y: floorY), control: CGPoint(x: br, y: floorY))
        p.addLine(to: CGPoint(x: bl + r, y: floorY))
        p.addQuadCurve(to: CGPoint(x: bl, y: floorY - r), control: CGPoint(x: bl, y: floorY))
        p.closeSubpath()
        return p
    }

    static func glassBack(_ ctx: inout GraphicsContext) {
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: Color(brimHex: 0x8A4A2A).opacity(0.25), radius: 18, x: 0, y: 10))
            layer.fill(outerPath(), with: .color(Color.white.opacity(0.42)))
        }
        ctx.fill(interiorPath(from: rimY), with: .color(Color(brimHex: 0xFFF8EE).opacity(0.55)))
    }

    static func liquid(_ ctx: inout GraphicsContext) {
        let body = interiorPath(from: lineY)
        ctx.fill(body, with: .linearGradient(
            Gradient(colors: [lemonTop, lemonBottom]),
            startPoint: CGPoint(x: glassCenterX, y: lineY), endPoint: CGPoint(x: glassCenterX, y: floorY)))
        // Lighter surface band.
        let (l, r) = interiorX(lineY)
        ctx.fill(Path(CGRect(x: l, y: lineY, width: r - l, height: 16)), with: .color(Color(brimHex: 0xFFF6B8).opacity(0.9)))
        // Bubbles.
        for (x, y, rad) in [(560.0, 800.0, 9.0), (640.0, 760.0, 7.0), (600.0, 846.0, 6.0), (668.0, 830.0, 10.0),
                            (530.0, 740.0, 5.0)] {
            ctx.fill(Path(ellipseIn: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)),
                     with: .color(Color.white.opacity(0.55)))
        }
    }

    static func glassFront(_ ctx: inout GraphicsContext) {
        ctx.stroke(outerPath(), with: .color(Color.white.opacity(0.95)),
                   style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
        // Rim highlight.
        var rim = Path()
        rim.move(to: CGPoint(x: glassCenterX - 166, y: rimY - 8))
        rim.addLine(to: CGPoint(x: glassCenterX + 166, y: rimY - 8))
        ctx.stroke(rim, with: .color(Color.white), style: StrokeStyle(lineWidth: 16, lineCap: .round))
        // Glossy vertical streak.
        ctx.fill(Path(roundedRect: CGRect(x: glassCenterX - 128, y: rimY + 34, width: 22, height: 250), cornerRadius: 11),
                 with: .color(Color.white.opacity(0.6)))
        ctx.fill(Path(roundedRect: CGRect(x: glassCenterX - 96, y: rimY + 40, width: 8, height: 120), cornerRadius: 4),
                 with: .color(Color.white.opacity(0.45)))
        // Darker refractive right edge.
        var edge = Path()
        edge.move(to: CGPoint(x: glassCenterX + 150, y: rimY + 20))
        edge.addLine(to: CGPoint(x: glassCenterX + 124, y: baseY - 40))
        ctx.stroke(edge, with: .color(Color(brimHex: 0xC98A50).opacity(0.35)),
                   style: StrokeStyle(lineWidth: 8, lineCap: .round))
    }

    /// The glowing gold fill line, right at the surface, with its little tab.
    static func fillLine(_ ctx: inout GraphicsContext) {
        let (l, r) = interiorX(lineY)
        var line = Path()
        line.move(to: CGPoint(x: l - 24, y: lineY))
        line.addLine(to: CGPoint(x: r + 24, y: lineY))
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: gold.opacity(0.95), radius: 26, x: 0, y: 0))
            layer.stroke(line, with: .color(gold), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        }
        ctx.stroke(line, with: .color(Color(brimHex: 0xFFE9A6)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        let tab = CGRect(x: r + 30, y: lineY - 15, width: 30, height: 30)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: gold.opacity(0.8), radius: 12, x: 0, y: 0))
            layer.fill(Path(roundedRect: tab, cornerRadius: 9), with: .color(gold))
        }
    }

    // MARK: Stream

    static let spout = CGPoint(x: 552, y: 268)

    static func streamPath() -> Path {
        var p = Path()
        p.move(to: spout)
        p.addCurve(to: CGPoint(x: glassCenterX, y: lineY + 4),
                   control1: CGPoint(x: 598, y: 284),
                   control2: CGPoint(x: glassCenterX + 6, y: 440))
        return p
    }

    static func stream(_ ctx: inout GraphicsContext) {
        let path = streamPath()
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: Color(brimHex: 0xE08A10).opacity(0.35), radius: 10, x: 6, y: 4))
            layer.stroke(path, with: .linearGradient(
                Gradient(colors: [lemonTop, Color(brimHex: 0xFFC53A)]),
                startPoint: spout, endPoint: CGPoint(x: glassCenterX, y: lineY)),
                         style: StrokeStyle(lineWidth: 46, lineCap: .round, lineJoin: .round))
        }
        // Glossy highlight down the stream.
        ctx.drawLayer { layer in
            layer.translateBy(x: -9, y: 0)
            layer.stroke(path, with: .color(Color.white.opacity(0.7)),
                         style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round, dash: [150, 26], dashPhase: 10))
        }
    }

    static func splash(_ ctx: inout GraphicsContext) {
        // Ripple ring where the stream lands.
        ctx.stroke(Path(ellipseIn: CGRect(x: glassCenterX - 74, y: lineY - 8, width: 148, height: 22)),
                   with: .color(Color.white.opacity(0.75)), lineWidth: 5)
        for (x, y, r) in [(548.0, 664.0, 13.0), (662.0, 652.0, 11.0), (632.0, 626.0, 7.5), (568.0, 630.0, 6.5),
                          (690.0, 676.0, 6.0)] {
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(lemonTop))
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: r * 0.45, dy: r * 0.45).offsetBy(dx: -r * 0.25, dy: -r * 0.25)),
                     with: .color(Color.white.opacity(0.85)))
        }
    }

    // MARK: Jug (top half), tipped toward the glass

    static func jug(_ ctx: inout GraphicsContext) {
        ctx.drawLayer { layer in
            layer.translateBy(x: 322, y: 300)
            layer.rotate(by: .degrees(38))
            layer.addFilter(.shadow(color: Color(brimHex: 0x7A3E22).opacity(0.28), radius: 20, x: -6, y: 16))

            // Handle (behind the body).
            var handle = Path()
            handle.move(to: CGPoint(x: -96, y: -96))
            handle.addCurve(to: CGPoint(x: -104, y: 92), control1: CGPoint(x: -212, y: -104),
                            control2: CGPoint(x: -214, y: 96))
            layer.stroke(handle, with: .color(teal), style: StrokeStyle(lineWidth: 30, lineCap: .round))

            // Body with the spout at the top right.
            var body = Path()
            body.move(to: CGPoint(x: -100, y: -150))
            body.addLine(to: CGPoint(x: 96, y: -150))
            body.addLine(to: CGPoint(x: 160, y: -178))
            body.addQuadCurve(to: CGPoint(x: 122, y: -112), control: CGPoint(x: 152, y: -140))
            body.addCurve(to: CGPoint(x: 104, y: 160), control1: CGPoint(x: 156, y: -36), control2: CGPoint(x: 146, y: 118))
            body.addQuadCurve(to: CGPoint(x: 72, y: 180), control: CGPoint(x: 98, y: 180))
            body.addLine(to: CGPoint(x: -72, y: 180))
            body.addQuadCurve(to: CGPoint(x: -104, y: 160), control: CGPoint(x: -98, y: 180))
            body.addCurve(to: CGPoint(x: -100, y: -150), control1: CGPoint(x: -144, y: 118), control2: CGPoint(x: -134, y: -60))
            body.closeSubpath()
            layer.fill(body, with: .linearGradient(Gradient(colors: [tealLight, teal, tealDark]),
                                                   startPoint: CGPoint(x: -130, y: 0), endPoint: CGPoint(x: 150, y: 0)))

            // Lemonade at the lip, about to leave the spout.
            var lip = Path()
            lip.move(to: CGPoint(x: 92, y: -150))
            lip.addLine(to: CGPoint(x: 160, y: -178))
            lip.addQuadCurve(to: CGPoint(x: 112, y: -136), control: CGPoint(x: 140, y: -150))
            lip.closeSubpath()
            layer.fill(lip, with: .color(lemonTop))

            // Rim opening.
            layer.fill(Path(ellipseIn: CGRect(x: -104, y: -164, width: 204, height: 30)), with: .color(tealDark))
            layer.fill(Path(ellipseIn: CGRect(x: -92, y: -158, width: 180, height: 18)), with: .color(lemonBottom))

            // Gloss.
            layer.fill(Path(roundedRect: CGRect(x: -78, y: -104, width: 26, height: 210), cornerRadius: 13),
                       with: .color(Color.white.opacity(0.38)))
            layer.fill(Path(roundedRect: CGRect(x: -40, y: -100, width: 10, height: 90), cornerRadius: 5),
                       with: .color(Color.white.opacity(0.28)))
            // A lemon-slice badge on the jug.
            layer.fill(Path(ellipseIn: CGRect(x: -6, y: 6, width: 92, height: 92)), with: .color(Color(brimHex: 0xFFF1C7)))
            layer.fill(Path(ellipseIn: CGRect(x: 4, y: 16, width: 72, height: 72)), with: .color(lemonTop))
            for i in 0..<6 {
                var seg = Path()
                let a = Double(i) * .pi / 3
                seg.move(to: CGPoint(x: 40, y: 52))
                seg.addLine(to: CGPoint(x: 40 + 34 * cos(a), y: 52 + 34 * sin(a)))
                layer.stroke(seg, with: .color(Color(brimHex: 0xFFF1C7)), lineWidth: 4)
            }
        }
    }
}
