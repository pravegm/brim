import SpriteKit
import UIKit

/// Stateless drawing helpers (no actor isolation; safe inside image-renderer closures). UIKit coordinates (y down).
enum SceneDraw {
    static func fillVertical(_ ctx: CGContext, rect: CGRect, colors: [UIColor], locations: [CGFloat]) {
        guard rect.width > 0, rect.height > 0, colors.count >= 2, colors.count == locations.count else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        let cgColors = colors.map { $0.cgColor } as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations) {
            ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.restoreGState()
    }

    static func fillHorizontal(_ ctx: CGContext, rect: CGRect, colors: [UIColor], locations: [CGFloat]) {
        guard rect.width > 0, rect.height > 0, colors.count >= 2, colors.count == locations.count else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        let cgColors = colors.map { $0.cgColor } as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations) {
            ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.midY), end: CGPoint(x: rect.maxX, y: rect.midY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.restoreGState()
    }

    static func fillRadial(_ ctx: CGContext, clip: CGRect, center: CGPoint, radius: CGFloat,
                           colors: [UIColor], locations: [CGFloat]) {
        guard radius > 0, colors.count >= 2, colors.count == locations.count else { return }
        ctx.saveGState()
        ctx.clip(to: clip)
        let cgColors = colors.map { $0.cgColor } as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations) {
            ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                                   options: [.drawsAfterEndLocation])
        }
        ctx.restoreGState()
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    /// Five-point star path (UIKit coordinates).
    static func star(center c: CGPoint, outer: CGFloat, inner: CGFloat) -> UIBezierPath {
        let p = UIBezierPath()
        for i in 0..<10 {
            let a = -CGFloat.pi / 2 + CGFloat(i) * CGFloat.pi / 5
            let r = i % 2 == 0 ? outer : inner
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.close()
        return p
    }

    /// The jug's belly decal (and the little framed print on the Duo's wall). A roundel in the icon's style:
    /// thick rim, glossy top-left highlight, soft drop shadow. UIKit coordinates, centre `c`, radius `r`.
    static func drawDecal(_ ctx: CGContext, decal: VesselDecal, accent: UIColor, center c: CGPoint, radius r: CGFloat) {
        let ink = SceneColor.ink
        func hex(_ v: UInt32) -> UIColor { SceneColor.hex(v) }
        // Disc + shadow.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: r * 0.08), blur: r * 0.18, color: ink.withAlphaComponent(0.28).cgColor)
        let discColor: UIColor
        switch decal {
        case .lemon: discColor = hex(0xF4C230)
        case .fizz: discColor = hex(0xE8505B)
        case .cherry: discColor = hex(0xFFC4D3)
        case .ticket: discColor = hex(0xFFF4DC)
        case .moon: discColor = hex(0x2E2350)
        case .sun: discColor = hex(0xF6E4C4)
        }
        discColor.setFill()
        UIBezierPath(ovalIn: circle(c, r)).fill()
        ctx.restoreGState()

        switch decal {
        case .lemon:
            hex(0xFFF8DC).setFill()
            UIBezierPath(ovalIn: circle(c, r * 0.86)).fill()
            hex(0xFFE166).setFill()
            UIBezierPath(ovalIn: circle(c, r * 0.76)).fill()
            UIColor.white.setStroke()
            for i in 0..<8 {
                let a = CGFloat(i) / 8 * 2 * CGFloat.pi + 0.2
                let seg = UIBezierPath()
                seg.move(to: CGPoint(x: c.x + cos(a) * r * 0.1, y: c.y + sin(a) * r * 0.1))
                seg.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.72, y: c.y + sin(a) * r * 0.72))
                seg.lineWidth = max(1, r * 0.07)
                seg.lineCapStyle = .round
                seg.stroke()
            }
            UIColor.white.setFill()
            UIBezierPath(ovalIn: circle(c, r * 0.1)).fill()
        case .fizz:
            UIColor.white.setStroke()
            let ring = UIBezierPath(ovalIn: circle(c, r * 0.8))
            ring.lineWidth = max(1, r * 0.07)
            ring.stroke()
            UIColor.white.setFill()
            star(center: CGPoint(x: c.x - r * 0.06, y: c.y + r * 0.04), outer: r * 0.44, inner: r * 0.19).fill()
            for (dx, dy, br) in [(CGFloat(0.42), CGFloat(-0.4), CGFloat(0.1)), (0.56, -0.12, 0.07), (0.3, -0.6, 0.06)] {
                UIBezierPath(ovalIn: circle(CGPoint(x: c.x + dx * r, y: c.y + dy * r), br * r)).fill()
            }
        case .cherry:
            UIColor.white.setStroke()
            let ring = UIBezierPath(ovalIn: circle(c, r * 0.82))
            ring.lineWidth = max(1, r * 0.06)
            ring.stroke()
            let stem = UIBezierPath()
            let top = CGPoint(x: c.x + r * 0.08, y: c.y - r * 0.46)
            stem.move(to: CGPoint(x: c.x - r * 0.22, y: c.y + r * 0.02))
            stem.addQuadCurve(to: top, controlPoint: CGPoint(x: c.x - r * 0.16, y: c.y - r * 0.3))
            stem.move(to: CGPoint(x: c.x + r * 0.24, y: c.y + r * 0.08))
            stem.addQuadCurve(to: top, controlPoint: CGPoint(x: c.x + r * 0.24, y: c.y - r * 0.24))
            stem.lineWidth = max(1, r * 0.07)
            stem.lineCapStyle = .round
            hex(0x3F8F5A).setStroke()
            stem.stroke()
            hex(0x6CC28A).setFill()
            let leaf = UIBezierPath()
            leaf.move(to: top)
            leaf.addQuadCurve(to: CGPoint(x: top.x + r * 0.36, y: top.y - r * 0.08), controlPoint: CGPoint(x: top.x + r * 0.16, y: top.y - r * 0.22))
            leaf.addQuadCurve(to: top, controlPoint: CGPoint(x: top.x + r * 0.2, y: top.y + r * 0.1))
            leaf.fill()
            for (dx, dy) in [(CGFloat(-0.22), CGFloat(0.2)), (0.24, 0.26)] {
                let cc = CGPoint(x: c.x + dx * r, y: c.y + dy * r)
                hex(0xE2324A).setFill()
                UIBezierPath(ovalIn: circle(cc, r * 0.22)).fill()
                UIColor(white: 1, alpha: 0.7).setFill()
                UIBezierPath(ovalIn: CGRect(x: cc.x - r * 0.12, y: cc.y - r * 0.13, width: r * 0.09, height: r * 0.07)).fill()
            }
        case .ticket:
            accent.setStroke()
            let ring = UIBezierPath(ovalIn: circle(c, r * 0.8))
            ring.lineWidth = max(1, r * 0.12)
            ring.stroke()
            let font = UIFont.systemFont(ofSize: r * 0.62, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            let s = "04" as NSString
            let ts = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: c.x - ts.width / 2, y: c.y - ts.height / 2), withAttributes: attrs)
        case .moon:
            let gold = hex(0xF5C84C)
            gold.setFill()
            UIBezierPath(ovalIn: circle(CGPoint(x: c.x - r * 0.08, y: c.y), r * 0.46)).fill()
            hex(0x2E2350).setFill()
            UIBezierPath(ovalIn: circle(CGPoint(x: c.x + r * 0.12, y: c.y - r * 0.1), r * 0.4)).fill()
            gold.setFill()
            star(center: CGPoint(x: c.x + r * 0.42, y: c.y + r * 0.3), outer: r * 0.15, inner: r * 0.06).fill()
            UIBezierPath(ovalIn: circle(CGPoint(x: c.x + r * 0.5, y: c.y - r * 0.38), r * 0.06)).fill()
            gold.setStroke()
            let ring = UIBezierPath(ovalIn: circle(c, r * 0.86))
            ring.lineWidth = max(1, r * 0.05)
            ring.stroke()
        case .sun:
            accent.setStroke()
            let ring = UIBezierPath(ovalIn: circle(c, r * 0.84))
            ring.lineWidth = max(1, r * 0.09)
            ring.stroke()
            let gold = hex(0xF2A93B)
            gold.setFill()
            for i in 0..<10 {
                let a = CGFloat(i) / 10 * 2 * CGFloat.pi
                let ray = UIBezierPath()
                ray.move(to: CGPoint(x: c.x + cos(a - 0.14) * r * 0.36, y: c.y + sin(a - 0.14) * r * 0.36))
                ray.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.66, y: c.y + sin(a) * r * 0.66))
                ray.addLine(to: CGPoint(x: c.x + cos(a + 0.14) * r * 0.36, y: c.y + sin(a + 0.14) * r * 0.36))
                ray.close()
                ray.fill()
            }
            hex(0xFFC94A).setFill()
            UIBezierPath(ovalIn: circle(c, r * 0.34)).fill()
        }
        // Gloss + crisp rim.
        ctx.saveGState()
        ctx.addEllipse(in: circle(c, r))
        ctx.clip()
        UIColor(white: 1, alpha: 0.26).setFill()
        UIBezierPath(ovalIn: CGRect(x: c.x - r * 0.9, y: c.y - r * 1.25, width: r * 1.4, height: r * 1.05)).fill()
        ctx.restoreGState()
        ink.withAlphaComponent(0.42).setStroke()
        let edge = UIBezierPath(ovalIn: circle(c, r - max(0.5, r * 0.025)))
        edge.lineWidth = max(1, r * 0.05)
        edge.stroke()
    }
}

/// A texture plus the size (in world points) to draw it at. SKTexture(image:) sizes are not trusted.
struct SceneSprite {
    let texture: SKTexture
    let size: CGSize
}

/// Everything pre-rendered with UIKit (gradients, the café backdrop, particle dots, text stamps, decals) and cached.
/// All drawing is done once; per-frame code only swaps cached textures.
@MainActor
enum SceneArt {
    private static var cache: [String: SKTexture] = [:]
    private static var labels: [String: SceneSprite] = [:]

    // MARK: Fonts

    static func roundedFont(_ size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: d, size: size)
        }
        return base
    }

    /// Vertical gradient texture (top colour at the top). Used as SKShapeNode.fillTexture, which stretches it over
    /// the shape's bounding box: liquids get a lighter top band and a darker bottom (GAME-DESIGN §8).
    static func verticalGradient(key: String, colors: [UIColor], locations: [CGFloat]) -> SKTexture {
        if let t = cache[key] { return t }
        let size = CGSize(width: 4, height: 128)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
            SceneDraw.fillVertical(rc.cgContext, rect: CGRect(origin: .zero, size: size), colors: colors, locations: locations)
        }
        let t = SKTexture(image: img)
        t.filteringMode = .linear
        cache[key] = t
        return t
    }

    static func liquidTexture(_ l: Liquid) -> SKTexture {
        let g = SceneLiquidLook.gradient(l)
        let top = g.top
        let bottom = g.bottom
        return verticalGradient(key: "liquid2-\(l.id.rawValue)",
                                colors: [SceneColor.lighter(top, 0.34), top, SceneColor.mix(top, bottom, 0.55), bottom],
                                locations: [0, 0.06, 0.45, 1])
    }

    static func foamTexture(_ l: Liquid) -> SKTexture {
        let foam = SceneColor.opaque(l.foam?.skColor ?? SceneColor.foamDefault)
        return verticalGradient(key: "foam-\(l.id.rawValue)",
                                colors: [SceneColor.lighter(foam, 0.7), SceneColor.lighter(foam, 0.2), foam,
                                         SceneColor.mix(foam, SceneColor.opaque(l.top.skColor), 0.3)],
                                locations: [0, 0.18, 0.55, 1])
    }

    /// Horizontal metal gradient (chrome / steel / ceramic sheen) for SKShapeNode fills.
    static func sheenTexture(key: String, base: UIColor) -> SKTexture {
        if let t = cache[key] { return t }
        let size = CGSize(width: 128, height: 4)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
            SceneDraw.fillHorizontal(rc.cgContext, rect: CGRect(origin: .zero, size: size),
                                     colors: [SceneColor.lighter(base, 0.25), SceneColor.lighter(base, 0.55), base,
                                              SceneColor.darker(base, 0.12), SceneColor.darker(base, 0.22)],
                                     locations: [0, 0.22, 0.5, 0.82, 1])
        }
        let t = SKTexture(image: img)
        t.filteringMode = .linear
        cache[key] = t
        return t
    }

    // MARK: Particles

    /// Soft white disc (tinted per particle via colorBlendFactor).
    static var dot: SKTexture {
        if let t = cache["dot"] { return t }
        let s: CGFloat = 32
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 2
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: fmt).image { rc in
            let ctx = rc.cgContext
            let c = CGPoint(x: s / 2, y: s / 2)
            SceneDraw.fillRadial(ctx, clip: CGRect(x: 0, y: 0, width: s, height: s), center: c, radius: s / 2,
                       colors: [UIColor.white, UIColor.white, UIColor(white: 1, alpha: 0)], locations: [0, 0.72, 1])
        }
        let t = SKTexture(image: img)
        cache["dot"] = t
        return t
    }

    /// Four-point twinkle with a soft halo.
    static var sparkle: SKTexture {
        if let t = cache["sparkle"] { return t }
        let s: CGFloat = 48
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 2
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: fmt).image { rc in
            let ctx = rc.cgContext
            let c = CGPoint(x: s / 2, y: s / 2)
            SceneDraw.fillRadial(ctx, clip: CGRect(x: 0, y: 0, width: s, height: s), center: c, radius: s * 0.32,
                       colors: [UIColor(white: 1, alpha: 0.55), UIColor(white: 1, alpha: 0)], locations: [0, 1])
            let r = s * 0.48, k = s * 0.07
            let p = UIBezierPath()
            p.move(to: CGPoint(x: c.x, y: c.y - r))
            p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), controlPoint: CGPoint(x: c.x + k, y: c.y - k))
            p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), controlPoint: CGPoint(x: c.x + k, y: c.y + k))
            p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), controlPoint: CGPoint(x: c.x - k, y: c.y + k))
            p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), controlPoint: CGPoint(x: c.x - k, y: c.y - k))
            p.close()
            UIColor.white.setFill()
            p.fill()
        }
        let t = SKTexture(image: img)
        cache["sparkle"] = t
        return t
    }

    /// Soft radial glow (white, tinted per use). Used for the Perfect surface flash and bulb glows.
    static var glow: SKTexture {
        if let t = cache["glow"] { return t }
        let s: CGFloat = 64
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 2
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: fmt).image { rc in
            SceneDraw.fillRadial(rc.cgContext, clip: CGRect(x: 0, y: 0, width: s, height: s), center: CGPoint(x: s / 2, y: s / 2),
                                 radius: s / 2, colors: [UIColor.white, UIColor(white: 1, alpha: 0.55), UIColor(white: 1, alpha: 0)],
                                 locations: [0, 0.35, 1])
        }
        let t = SKTexture(image: img)
        cache["glow"] = t
        return t
    }

    // MARK: Decals

    /// The jug decal, `diameter` world points across (drawn at 3×, with room for its shadow).
    static func decal(_ d: VesselDecal, accent: UIColor, diameter: CGFloat) -> SceneSprite {
        let dia = max(8, (diameter / 2).rounded() * 2)
        let key = "decal-\(d.rawValue)-\(Int(dia))-\(accent.hashValue)"
        let pad = ceil(dia * 0.16)
        let size = CGSize(width: dia + pad * 2, height: dia + pad * 2)
        if let t = cache[key] { return SceneSprite(texture: t, size: size) }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 3
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
            SceneDraw.drawDecal(rc.cgContext, decal: d, accent: accent, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                radius: dia / 2)
        }
        let t = SKTexture(image: img)
        t.filteringMode = .linear
        cache[key] = t
        return SceneSprite(texture: t, size: size)
    }

    // MARK: Text (stamps, streak pops). SF Pro Rounded Heavy via the .rounded design.

    static func label(_ text: String, pointSize: CGFloat, fill: UIColor, outline: UIColor, key: String) -> SceneSprite {
        if let l = labels[key] { return l }
        let font = roundedFont(pointSize, weight: .heavy)
        let plain: [NSAttributedString.Key: Any] = [.font: font, .kern: pointSize * 0.02]
        let textSize = (text as NSString).size(withAttributes: plain)
        let pad = ceil(pointSize * 0.32)
        let size = CGSize(width: ceil(textSize.width + pad * 2), height: ceil(textSize.height + pad * 2))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 3
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
            let ctx = rc.cgContext
            let origin = CGPoint(x: pad, y: pad)
            // 1. soft drop shadow + fat outline
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: pointSize * 0.08), blur: pointSize * 0.16,
                          color: SceneColor.ink.withAlphaComponent(0.4).cgColor)
            let outlineAttrs: [NSAttributedString.Key: Any] = [
                .font: font, .kern: pointSize * 0.02,
                .strokeColor: outline, .strokeWidth: NSNumber(value: Double(28)),
            ]
            (text as NSString).draw(at: origin, withAttributes: outlineAttrs)
            ctx.restoreGState()
            // 2. fill, with a light top sheen
            let fillAttrs: [NSAttributedString.Key: Any] = [.font: font, .kern: pointSize * 0.02, .foregroundColor: fill]
            (text as NSString).draw(at: origin, withAttributes: fillAttrs)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: size.width, height: pad + textSize.height * 0.42))
            let sheenAttrs: [NSAttributedString.Key: Any] = [.font: font, .kern: pointSize * 0.02,
                                                             .foregroundColor: UIColor(white: 1, alpha: 0.3)]
            (text as NSString).draw(at: origin, withAttributes: sheenAttrs)
            ctx.restoreGState()
            // 3. thin ink keyline so it reads on any backdrop
            let keyAttrs: [NSAttributedString.Key: Any] = [
                .font: font, .kern: pointSize * 0.02,
                .strokeColor: SceneColor.darker(fill, 0.45), .strokeWidth: NSNumber(value: Double(3)),
            ]
            (text as NSString).draw(at: origin, withAttributes: keyAttrs)
        }
        let t = SKTexture(image: img)
        t.filteringMode = .linear
        let sprite = SceneSprite(texture: t, size: size)
        labels[key] = sprite
        return sprite
    }

    /// Judgement stamps, 1.5× the round-1 size (REVIEW-1 P0-5).
    static func stamp(_ j: Judgement) -> SceneSprite {
        switch j {
        case .perfect: return label("PERFECT", pointSize: 64, fill: SceneColor.perfect, outline: .white, key: "stamp2-perfect")
        case .great: return label("GREAT", pointSize: 56, fill: SceneColor.gold, outline: .white, key: "stamp2-great")
        case .good: return label("GOOD", pointSize: 50, fill: SceneColor.hex(0x5FCB8F), outline: .white, key: "stamp2-good")
        case .short: return label("SHORT", pointSize: 46, fill: SceneColor.hex(0x9A8FB0), outline: .white, key: "stamp2-short")
        case .spill: return label("SPILL!", pointSize: 58, fill: SceneColor.coral, outline: .white, key: "stamp2-spill")
        }
    }

    static func streak(_ n: Int) -> SceneSprite {
        // Streaks climb one at a time: drop the label a few steps back so a long Rush streak doesn't keep one
        // texture per value forever (QA-1 P2-12). A sprite still on screen keeps its own texture reference.
        if n > 4 { labels["streak2-\(n - 4)"] = nil }
        return label("×\(n) STREAK", pointSize: 30, fill: SceneColor.gold, outline: SceneColor.ink.withAlphaComponent(0.88),
              key: "streak2-\(n)")
    }

    // MARK: Backdrop (one texture for the whole canvas)

    static func backdrop(layout: WorldLayout, palette: ScenePalette, dailyNumber: Int?, scale: CGFloat) -> SKTexture {
        let size = CGSize(width: max(1, layout.size.width), height: max(1, layout.size.height))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = min(max(scale, 1), 3)
        fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
            SceneBackdropPainter(layout: layout, palette: palette, dailyNumber: dailyNumber, ctx: rc.cgContext).paint()
        }
        let t = SKTexture(image: img)
        t.filteringMode = .linear
        return t
    }
}

// MARK: - Backdrop painter

/// Paints the café in UIKit coordinates (y down). World y converts with `uy(_:)`.
/// Composition (REVIEW-1 P0-2, ROUND-2 decision 1): the world is the Duo's inner canvas in tabletop pose.
///   y 842…952  HUD band: calm wall (Lemonade: a soft awning).
///   y 496…842  the raised half = back bar: wall, backsplash, a slim ledge + venue props on the right (the tipped jug
///              swings up-left, so the right wall is where props can live without fighting it).
///   y 456…496  the fold: the trim where wall meets counter (a hinge seam on the Duo).
///   y   0…456  the flat half = the counter top seen from above, receding toward the fold.
/// Important things stay inside x 130…540 (the iPhone crop); Duo-only decoration lives outside it.
@MainActor
private struct SceneBackdropPainter {
    let layout: WorldLayout
    let palette: ScenePalette
    let dailyNumber: Int?
    let ctx: CGContext

    var W: CGFloat { layout.size.width }
    var H: CGFloat { layout.size.height }
    var p: ScenePalette { palette }

    static let hudBandY: CGFloat = 842
    static let ledgeY: CGFloat = 766
    /// Phones: wall props (ledge, shelf props, tap tower, neon, calendar, string lights) sit this much lower so their
    /// tops stay ≥ ~35 pt below the score and pause button.
    static let phonePropDrop: CGFloat = 48

    func uy(_ worldY: CGFloat) -> CGFloat { H - worldY }

    /// World rect spanning world y0 (bottom) … y1 (top).
    func band(_ x: CGFloat, _ w: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> CGRect {
        CGRect(x: x, y: uy(max(y0, y1)), width: w, height: abs(y1 - y0))
    }

    /// World point → UIKit point.
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: uy(y)) }

    func paint() {
        p.wallBottom.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        paintWall()
        paintCounter()
        paintCrease()
        paintWallProps()
    }

    // MARK: Raised half: the wall

    private func paintWall() {
        let y0 = layout.creaseMaxY
        guard H - y0 > 1 else { return }
        let wallRect = band(0, W, y0, H)
        SceneDraw.fillVertical(ctx, rect: wallRect, colors: [p.wallTop, p.wallBottom], locations: [0, 1])

        if p.dusk {
            // A few early stars high on the dusk wall (kept faint behind the HUD).
            var rng = SceneRNG(seed: 404)
            for _ in 0..<26 {
                let x = rng.range(10, W - 10), y = rng.range(700, H - 8)
                let r = rng.range(0.8, 1.9)
                UIColor(white: 1, alpha: rng.range(0.25, 0.6)).setFill()
                UIBezierPath(ovalIn: SceneDraw.circle(pt(x, y), r)).fill()
            }
            // Warm horizon glow just above the counter.
            SceneDraw.fillVertical(ctx, rect: band(0, W, y0, y0 + 220),
                                   colors: [SceneColor.hex(0xFFB27A, 0), SceneColor.hex(0xFFB27A, 0.35)], locations: [0, 1])
        }

        // Backsplash.
        let tileTop = y0 + 150
        switch p.venue {
        case .sodaFountain:
            paintChecker(y0: y0, y1: tileTop, a: SceneColor.mix(p.tile, p.wallBottom, 0.15), b: p.grout, size: 26)
        case .potionShop:
            paintTiles(y0: y0, y1: tileTop, tile: p.tile, grout: p.grout, tileW: 58, tileH: 30, seed: 5, radius: 6)
        default:
            paintTiles(y0: y0, y1: tileTop, tile: p.tile, grout: p.grout, tileW: 46, tileH: 23, seed: 7, radius: 3.5)
        }
        // Trim rail on top of the backsplash.
        let metal = p.venue == .sodaFountain || p.venue == .milkshakeDiner
        if metal {
            SceneDraw.fillVertical(ctx, rect: band(0, W, tileTop, tileTop + 8),
                                   colors: [UIColor.white, SceneColor.chrome, SceneColor.darker(SceneColor.chrome, 0.2)],
                                   locations: [0, 0.45, 1])
        } else {
            (p.isDark ? SceneColor.darker(p.trim, 0.3) : p.trim).setFill()
            ctx.fill(band(0, W, tileTop, tileTop + 7))
            UIColor(white: 1, alpha: 0.5).setFill()
            ctx.fill(band(0, W, tileTop + 5.5, tileTop + 7))
        }
        SceneDraw.fillVertical(ctx, rect: band(0, W, tileTop - 7, tileTop),
                               colors: [SceneColor.ink.withAlphaComponent(0.12), SceneColor.ink.withAlphaComponent(0)],
                               locations: [0, 1])

        // Warm light pooled behind the jug.
        let jp = layout.jugPivot
        SceneDraw.fillRadial(ctx, clip: wallRect, center: pt(jp.x - 20, jp.y + 40), radius: 300,
                             colors: [p.glow, p.glow.withAlphaComponent(0)], locations: [0, 1])
        // Vignette.
        let topH = H - y0
        let c = pt(W * 0.5, y0 + topH * 0.45)
        let r = hypot(W * 0.5, topH * 0.62) * 1.08
        SceneDraw.fillRadial(ctx, clip: wallRect, center: c, radius: r,
                             colors: [p.vignette.withAlphaComponent(0), p.vignette.withAlphaComponent(0), p.vignette],
                             locations: [0, 0.6, 1])
    }

    private func paintTiles(y0: CGFloat, y1: CGFloat, tile: UIColor, grout: UIColor, tileW: CGFloat, tileH: CGFloat,
                            seed: UInt64, radius: CGFloat) {
        guard y1 > y0 else { return }
        let rect = band(0, W, y0, y1)
        ctx.saveGState()
        ctx.clip(to: rect)
        grout.setFill()
        ctx.fill(rect)
        var rng = SceneRNG(seed: seed)
        let gap: CGFloat = 2.5
        var row = 0
        var y = y0 + 1
        while y < y1 {
            var x: CGFloat = (row % 2 == 0) ? -tileW * 0.5 : -tileW
            while x < W {
                let tint = rng.range(-0.05, 0.05)
                let col = tint >= 0 ? SceneColor.lighter(tile, tint * 2) : SceneColor.darker(tile, -tint)
                let r = CGRect(x: x + gap * 0.5, y: uy(y + tileH - gap * 0.5), width: tileW - gap, height: tileH - gap)
                col.setFill()
                UIBezierPath(roundedRect: r, cornerRadius: radius).fill()
                UIColor(white: 1, alpha: p.isDark ? 0.12 : 0.3).setFill()
                UIBezierPath(roundedRect: CGRect(x: r.minX + 3, y: r.minY + 1.5, width: r.width - 6, height: 2), cornerRadius: 1).fill()
                x += tileW
            }
            y += tileH
            row += 1
        }
        ctx.restoreGState()
    }

    private func paintChecker(y0: CGFloat, y1: CGFloat, a: UIColor, b: UIColor, size: CGFloat) {
        let rect = band(0, W, y0, y1)
        ctx.saveGState()
        ctx.clip(to: rect)
        b.setFill()
        ctx.fill(rect)
        a.setFill()
        var row = 0
        var y = y0
        while y < y1 {
            var col = 0
            var x: CGFloat = 0
            while x < W {
                if (row + col) % 2 == 0 { ctx.fill(band(x, size, y, y + size)) }
                x += size
                col += 1
            }
            y += size
            row += 1
        }
        // Glaze sheen.
        SceneDraw.fillVertical(ctx, rect: rect, colors: [UIColor(white: 1, alpha: 0.18), UIColor(white: 1, alpha: 0)],
                               locations: [0, 1])
        ctx.restoreGState()
    }

    // MARK: Flat half: the counter top seen from above

    private func paintCounter() {
        let top = layout.creaseMinY
        guard top > 1 else { return }
        let rect = band(0, W, 0, top)
        SceneDraw.fillVertical(ctx, rect: rect, colors: [p.counterTopBack, p.counterTop], locations: [0, 1])
        ctx.saveGState()
        ctx.clip(to: rect)
        switch p.surface {
        case .wood: paintPlanks(top: top, dark: false)
        case .darkWood: paintPlanks(top: top, dark: true)
        case .marble: paintMarble(top: top)
        case .formica: paintFormica(top: top)
        case .steel: paintSteel(top: top)
        }
        if p.venue == .conveyor { paintBelt() }

        // Warm pool of light where the glass stands.
        let gx = layout.jugPivot.x + 18
        SceneDraw.fillRadial(ctx, clip: rect, center: pt(gx, layout.counterY + 70), radius: 300,
                             colors: [p.glow.withAlphaComponent(p.dusk ? 0.55 : 0.45), p.glow.withAlphaComponent(0)],
                             locations: [0, 1])
        // The raised half casts a soft shadow onto the flat half (and the wall meets the counter on phones).
        let shadowH: CGFloat = layout.hasFold ? 84 : 56
        SceneDraw.fillVertical(ctx, rect: band(0, W, top - shadowH, top),
                               colors: [SceneColor.ink.withAlphaComponent(layout.hasFold ? 0.22 : 0.14),
                                        SceneColor.ink.withAlphaComponent(0.05), SceneColor.ink.withAlphaComponent(0)],
                               locations: [0, 0.4, 1])
        // Near edge (bull-nose) toward the player.
        SceneDraw.fillVertical(ctx, rect: band(0, W, 0, 12),
                               colors: [p.counterEdge, p.counterFront], locations: [0, 1])
        UIColor(white: 1, alpha: 0.4).setFill()
        ctx.fill(band(0, W, 11, 12.5))
        // Vignette toward the corners.
        SceneDraw.fillRadial(ctx, clip: rect, center: pt(W * 0.5, top * 0.55), radius: hypot(W * 0.5, top * 0.7) * 1.08,
                             colors: [p.vignette.withAlphaComponent(0), p.vignette.withAlphaComponent(0),
                                      p.vignette.withAlphaComponent(0.85 * SceneColor.rgba(p.vignette).a)],
                             locations: [0, 0.6, 1])
        ctx.restoreGState()
    }

    /// Plank seams run side to side and crowd together toward the fold (foreshortening).
    private func paintPlanks(top: CGFloat, dark: Bool) {
        var rng = SceneRNG(seed: dark ? 71 : 29)
        var seams: [CGFloat] = []
        var y: CGFloat = 12
        var gap: CGFloat = 70
        while y < top - 6 {
            seams.append(y)
            y += gap
            gap = max(22, gap * 0.85)
        }
        seams.append(top)
        let grainColor = SceneColor.darker(p.counterTop, dark ? 0.4 : 0.3)
        for i in 0..<(seams.count - 1) {
            let y0 = seams[i], y1 = seams[i + 1]
            let h = y1 - y0
            // Each plank a hair different.
            let tint = rng.range(-0.05, 0.05)
            let plankCol = tint >= 0 ? UIColor(white: 1, alpha: tint * 1.4) : SceneColor.ink.withAlphaComponent(-tint * 1.1)
            plankCol.setFill()
            ctx.fill(band(0, W, y0, y1))
            // Grain: long, gently wavy strokes, thinner in the distance.
            let lines = 3 + Int(h / 18)
            for _ in 0..<lines {
                let gy = rng.range(y0 + 2, y1 - 2)
                let gx = rng.range(-60, W)
                let len = rng.range(90, 300)
                let g = UIBezierPath()
                g.move(to: pt(gx, gy))
                g.addCurve(to: pt(gx + len, gy + rng.range(-1.2, 1.2)),
                           controlPoint1: pt(gx + len * 0.33, gy + rng.range(-2.5, 2.5)),
                           controlPoint2: pt(gx + len * 0.66, gy + rng.range(-2.5, 2.5)))
                g.lineWidth = max(0.5, rng.range(0.6, 1.5) * min(1, h / 50))
                grainColor.withAlphaComponent(rng.range(0.10, 0.2)).setStroke()
                g.stroke()
            }
            // A knot now and then.
            if rng.unit() < 0.35 && h > 30 {
                let k = pt(rng.range(40, W - 40), (y0 + y1) * 0.5)
                grainColor.withAlphaComponent(0.18).setStroke()
                let knot = UIBezierPath(ovalIn: CGRect(x: k.x - 9, y: k.y - h * 0.12, width: 18, height: h * 0.24))
                knot.lineWidth = 1
                knot.stroke()
            }
            // Butt joints, staggered.
            let jx = rng.range(60, W - 60)
            SceneColor.ink.withAlphaComponent(0.16).setFill()
            ctx.fill(CGRect(x: jx, y: uy(y1), width: 1.4, height: h))
            // Seam: dark gap with a light chamfer on the near side.
            SceneColor.ink.withAlphaComponent(dark ? 0.35 : 0.2).setFill()
            ctx.fill(band(0, W, y1 - 1.3, y1))
            UIColor(white: 1, alpha: dark ? 0.08 : 0.16).setFill()
            ctx.fill(band(0, W, y1 - 2.4, y1 - 1.3))
        }
    }

    private func paintMarble(top: CGFloat) {
        // REVIEW-3 P2-7: fewer, softer, lower-contrast veins that drift gently sideways (no zig-zags that read as
        // cracks), and none behind the glasses: they live in the far band toward the fold (above the tallest rim,
        // world y ≥ 350) and in the near band in front of the coasters (y ≤ 78).
        var rng = SceneRNG(seed: 88)
        let bands: [(CGFloat, CGFloat)] = [(352, top - 10), (352, top - 10), (352, top - 10), (352, top - 10),
                                           (20, 76), (20, 76), (20, 76)]
        for (i, b) in bands.enumerated() {
            guard b.1 > b.0 else { continue }
            let v = UIBezierPath()
            var x = rng.range(-120, W - 80)
            var y = rng.range(b.0, b.1)
            v.move(to: pt(x, y))
            for _ in 0..<4 {
                let nx = x + rng.range(70, 160)
                let ny = min(max(y + rng.range(-9, 9), b.0), b.1)
                v.addQuadCurve(to: pt(nx, ny), controlPoint: pt((x + nx) * 0.5 + rng.range(-12, 12), (y + ny) * 0.5 + rng.range(-6, 6)))
                x = nx
                y = ny
            }
            v.lineWidth = rng.range(0.6, i % 3 == 0 ? 1.5 : 1.0)
            v.lineCapStyle = .round
            (i % 3 == 0 ? UIColor(white: 1, alpha: 0.5) : SceneColor.hex(0x8A8FA0, rng.range(0.06, 0.11))).setStroke()
            v.stroke()
        }
        // Polished reflection band.
        SceneDraw.fillVertical(ctx, rect: band(0, W, top * 0.35, top * 0.62),
                               colors: [UIColor(white: 1, alpha: 0), UIColor(white: 1, alpha: 0.22), UIColor(white: 1, alpha: 0)],
                               locations: [0, 0.5, 1])
    }

    private func paintFormica(top: CGFloat) {
        var rng = SceneRNG(seed: 52)
        // Mint formica (REVIEW-2 P1-9: the pink shake pops against it), with white, ink and cherry flecks.
        let colors: [UIColor] = [SceneColor.ink.withAlphaComponent(0.14), UIColor(white: 1, alpha: 0.7),
                                 SceneColor.hex(0xE2324A, 0.3), SceneColor.hex(0x2F8F84, 0.3)]
        for i in 0..<320 {
            let x = rng.range(0, W), y = rng.range(14, top)
            let len = rng.range(3, 7) * (0.5 + 0.5 * (1 - y / max(top, 1)))
            let a = rng.range(0, 3.1)
            let d = UIBezierPath()
            d.move(to: pt(x, y))
            d.addQuadCurve(to: pt(x + cos(a) * len, y + sin(a) * len * 0.5),
                           controlPoint: pt(x + cos(a + 0.8) * len * 0.6, y + sin(a + 0.8) * len * 0.4))
            d.lineWidth = 1.2
            d.lineCapStyle = .round
            colors[i % colors.count].setStroke()
            d.stroke()
        }
        // Chrome band along the near edge.
        SceneDraw.fillVertical(ctx, rect: band(0, W, 0, 22),
                               colors: [UIColor.white, SceneColor.chrome, SceneColor.darker(SceneColor.chrome, 0.25)],
                               locations: [0, 0.4, 1])
    }

    private func paintSteel(top: CGFloat) {
        var rng = SceneRNG(seed: 61)
        for _ in 0..<160 {
            let y = rng.range(0, top)
            let x = rng.range(-40, W)
            let len = rng.range(60, 260)
            (rng.unit() < 0.5 ? UIColor(white: 1, alpha: rng.range(0.08, 0.2)) : SceneColor.ink.withAlphaComponent(rng.range(0.03, 0.07))).setFill()
            ctx.fill(CGRect(x: x, y: uy(y), width: len, height: 0.7))
        }
    }

    /// The conveyor belt (rubber + rails + roller caps). The moving slats are a node in GameScene.
    private func paintBelt() {
        let cy = layout.counterY
        let b0 = cy - 46, b1 = cy + 46
        SceneDraw.fillVertical(ctx, rect: band(0, W, b0, b1),
                               colors: [SceneColor.hex(0x56626F), SceneColor.hex(0x3A4450), SceneColor.hex(0x2E3742)],
                               locations: [0, 0.5, 1])
        for (r0, r1) in [(b1, b1 + 14), (b0 - 14, b0)] {
            SceneDraw.fillVertical(ctx, rect: band(0, W, r0, r1),
                                   colors: [UIColor.white, SceneColor.chrome, SceneColor.darker(SceneColor.chrome, 0.3)],
                                   locations: [0, 0.35, 1])
            var x: CGFloat = 24
            while x < W {
                let c = pt(x, (r0 + r1) * 0.5)
                SceneColor.darker(SceneColor.chrome, 0.35).setFill()
                UIBezierPath(ovalIn: SceneDraw.circle(c, 4.2)).fill()
                UIColor(white: 1, alpha: 0.8).setFill()
                UIBezierPath(ovalIn: SceneDraw.circle(CGPoint(x: c.x - 1, y: c.y - 1), 1.5)).fill()
                x += 48
            }
        }
        // Shadow of the rails on the belt.
        SceneDraw.fillVertical(ctx, rect: band(0, W, b1 - 8, b1),
                               colors: [SceneColor.ink.withAlphaComponent(0.35), SceneColor.ink.withAlphaComponent(0)],
                               locations: [0, 1])
    }

    // MARK: The fold

    private func paintCrease() {
        let minY = layout.creaseMinY, maxY = layout.creaseMaxY
        guard maxY - minY > 0.5 else { return }
        let rect = band(0, W, minY, maxY)
        let base = p.isDark ? SceneColor.darker(p.trim, 0.45) : SceneColor.mix(p.trim, p.counterTopBack, 0.35)
        SceneDraw.fillVertical(ctx, rect: rect,
                               colors: [SceneColor.lighter(base, 0.25), base, SceneColor.darker(base, 0.18)],
                               locations: [0, 0.55, 1])
        UIColor(white: 1, alpha: 0.45).setFill()
        ctx.fill(band(0, W, maxY - 1.5, maxY))
        SceneColor.ink.withAlphaComponent(0.25).setFill()
        ctx.fill(band(0, W, minY, minY + 1.2))
        if layout.hasFold {
            // The hinge.
            let mid = (minY + maxY) * 0.5
            SceneColor.ink.withAlphaComponent(0.22).setFill()
            ctx.fill(band(0, W, mid - 0.8, mid + 0.8))
            UIColor(white: 1, alpha: 0.22).setFill()
            ctx.fill(band(0, W, mid - 2, mid - 0.8))
        }
    }

    // MARK: Props

    private func paintWallProps() {
        switch p.venue {
        case .lemonadeStand: paintAwning()
        default: break
        }
        // iPhone (REVIEW-2 P1-7): the aspect-fill crop + Dynamic Island push the HUD (score, pause, title chip) ~60 pt
        // down into the wall art the Duo keeps clear, so every wall prop drops `Self.phonePropDrop` on phones.
        ctx.saveGState()
        if !layout.hasFold { ctx.translateBy(x: 0, y: Self.phonePropDrop) }
        defer { ctx.restoreGState() }
        paintFramedPrint()
        switch p.venue {
        case .lemonadeStand:
            paintLedge()
            lemonBowl(x: 452)
            lemonadeJar(x: 514)
            plant(x: 586, base: Self.ledgeY + 8, w: 34, h: 30)
        case .sodaFountain:
            paintTapTower(x: 510)
            paintLedge()
            bottle(x: 436, base: Self.ledgeY + 8, w: 20, h: 56, color: SceneColor.hex(0xE8505B))
            bottle(x: 464, base: Self.ledgeY + 8, w: 22, h: 58, color: SceneColor.hex(0x7A4A2E))
            strawCup(x: 516)
            bottle(x: 580, base: Self.ledgeY + 8, w: 20, h: 50, color: SceneColor.hex(0xF2E3C0))
        case .milkshakeDiner:
            paintNeon()
            paintLedge()
            shakeGlass(x: 446)
            steelTin(x: 500)
            jar(x: 560, base: Self.ledgeY + 8, w: 26, h: 30, color: SceneColor.hex(0xFFD8E2))
        case .conveyor:
            paintTicketRail()
            paintLedge()
            cups(x: 450, base: Self.ledgeY + 8, w: 30, color: SceneColor.hex(0xF2F0EA))
            bell(x: 510)
            jar(x: 572, base: Self.ledgeY + 8, w: 28, h: 34, color: SceneColor.hex(0xD9E4EC))
        case .potionShop:
            paintLedge()
            candle(x: 432, h: 34)
            roundFlask(x: 474, color: SceneColor.hex(0xB06CFF))
            candle(x: 520, h: 22)
            bottle(x: 566, base: Self.ledgeY + 8, w: 20, h: 54, color: SceneColor.hex(0x3FC9A8))
        case .sandBar:
            paintLedge()
            hourglass(x: 466, h: 60)
            cactus(x: 528)
            jar(x: 582, base: Self.ledgeY + 8, w: 26, h: 28, color: SceneColor.hex(0xF0D9A8))
        }
        if let n = dailyNumber { paintCalendar(n) }
        if p.dusk { paintStringLights() }
    }

    /// The slim ledge on the right wall, well under the HUD band.
    private func paintLedge() {
        let y = Self.ledgeY
        let plank = band(404, W - 404 + 20, y, y + 8)
        p.shelf.setFill()
        UIBezierPath(roundedRect: plank, cornerRadius: 3).fill()
        SceneColor.lighter(p.shelf, 0.3).setFill()
        ctx.fill(CGRect(x: plank.minX + 2, y: plank.minY, width: plank.width - 4, height: 2))
        SceneDraw.fillVertical(ctx, rect: band(404, W - 404, y - 14, y),
                               colors: [SceneColor.ink.withAlphaComponent(0.14), SceneColor.ink.withAlphaComponent(0)],
                               locations: [0, 1])
        SceneColor.darker(p.shelf, 0.15).setFill()
        for bx in [CGFloat(440), CGFloat(600)] {
            let br = UIBezierPath()
            br.move(to: pt(bx - 3, y))
            br.addLine(to: pt(bx + 12, y))
            br.addLine(to: pt(bx - 3, y - 16))
            br.close()
            br.fill()
        }
    }

    /// Duo-only (outside the iPhone crop): a little framed print of the venue's emblem on the left wall.
    private func paintFramedPrint() {
        let frame = band(28, 80, 712, 806)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 6, color: SceneColor.ink.withAlphaComponent(0.18).cgColor)
        p.shelf.setFill()
        UIBezierPath(roundedRect: frame, cornerRadius: 5).fill()
        ctx.restoreGState()
        (p.isDark ? SceneColor.hex(0x2A2147) : SceneColor.hex(0xFFFBF3)).setFill()
        UIBezierPath(roundedRect: frame.insetBy(dx: 6, dy: 6), cornerRadius: 2).fill()
        SceneDraw.drawDecal(ctx, decal: p.vessel.decal, accent: p.vessel.accent,
                            center: CGPoint(x: frame.midX, y: frame.midY), radius: 24)
    }

    // MARK: Venue signatures

    /// Lemonade Stand: a striped awning in the HUD band, low contrast so the HUD stays readable.
    private func paintAwning() {
        let bottom = Self.hudBandY + 6
        let rect = band(0, W, bottom, H)
        let a = p.dusk ? SceneColor.mix(SceneColor.hex(0xFFF3DC), p.wallTop, 0.45) : SceneColor.hex(0xFFF7E6)
        let b = p.dusk ? SceneColor.mix(SceneColor.hex(0xFFDE8A), p.wallTop, 0.45) : SceneColor.hex(0xFFE39A)
        let stripe: CGFloat = 42
        var x: CGFloat = -stripe * 0.5
        var i = 0
        while x < W {
            (i % 2 == 0 ? a : b).setFill()
            ctx.fill(CGRect(x: x, y: rect.minY, width: stripe, height: rect.height))
            x += stripe
            i += 1
        }
        // Fabric shading: darker toward the wall, a lit fold line.
        SceneDraw.fillVertical(ctx, rect: rect,
                               colors: [SceneColor.ink.withAlphaComponent(0.10), SceneColor.ink.withAlphaComponent(0)],
                               locations: [0, 1])
        // Scalloped valance.
        x = -stripe * 0.5
        i = 0
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 6, color: SceneColor.ink.withAlphaComponent(0.16).cgColor)
        while x < W {
            let scallop = UIBezierPath()
            scallop.move(to: pt(x, bottom))
            scallop.addArc(withCenter: pt(x + stripe * 0.5, bottom), radius: stripe * 0.5, startAngle: CGFloat.pi,
                           endAngle: 0, clockwise: false)
            scallop.close()
            (i % 2 == 0 ? a : b).setFill()
            scallop.fill()
            x += stripe
            i += 1
        }
        ctx.restoreGState()
        UIColor(white: 1, alpha: 0.55).setFill()
        ctx.fill(band(0, W, bottom - 1, bottom + 1))
    }

    /// Soda Fountain: a chrome tap tower on the wall.
    private func paintTapTower(x: CGFloat) {
        let colRect = band(x - 13, 26, 568, 692)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 3, height: 4), blur: 6, color: SceneColor.ink.withAlphaComponent(0.2).cgColor)
        SceneDraw.fillHorizontal(ctx, rect: colRect,
                                 colors: [SceneColor.darker(SceneColor.chrome, 0.2), UIColor.white, SceneColor.chrome,
                                          SceneColor.darker(SceneColor.chrome, 0.3)], locations: [0, 0.3, 0.6, 1])
        ctx.restoreGState()
        // Dome cap + base plate.
        SceneDraw.fillHorizontal(ctx, rect: band(x - 18, 36, 692, 704),
                                 colors: [SceneColor.chrome, UIColor.white, SceneColor.darker(SceneColor.chrome, 0.25)],
                                 locations: [0, 0.35, 1])
        SceneColor.hex(0xE8505B).setFill()
        UIBezierPath(ovalIn: SceneDraw.circle(pt(x, 712), 8)).fill()
        SceneDraw.fillHorizontal(ctx, rect: band(x - 22, 44, 558, 568),
                                 colors: [SceneColor.chrome, UIColor.white, SceneColor.darker(SceneColor.chrome, 0.25)],
                                 locations: [0, 0.35, 1])
        // Two spouts with lever handles (red, cream).
        for (sy, knob) in [(CGFloat(650), SceneColor.hex(0xE8505B)), (CGFloat(606), SceneColor.hex(0xFFF3DC))] {
            SceneDraw.fillVertical(ctx, rect: band(x - 36, 26, sy - 4, sy + 4),
                                   colors: [UIColor.white, SceneColor.darker(SceneColor.chrome, 0.2)], locations: [0, 1])
            SceneDraw.fillHorizontal(ctx, rect: band(x - 38, 7, sy - 16, sy),
                                     colors: [UIColor.white, SceneColor.darker(SceneColor.chrome, 0.3)], locations: [0, 1])
            let lever = UIBezierPath()
            lever.move(to: pt(x - 24, sy + 4))
            lever.addLine(to: pt(x - 30, sy + 24))
            lever.lineWidth = 4
            lever.lineCapStyle = .round
            SceneColor.darker(SceneColor.chrome, 0.2).setStroke()
            lever.stroke()
            knob.setFill()
            UIBezierPath(ovalIn: CGRect(x: x - 37, y: uy(sy + 34), width: 13, height: 15)).fill()
            UIColor(white: 1, alpha: 0.6).setFill()
            UIBezierPath(ovalIn: CGRect(x: x - 34, y: uy(sy + 31), width: 4, height: 4)).fill()
        }
    }

    /// Milkshake Diner: a neon DINER sign.
    private func paintNeon() {
        let board = band(414, 132, 650, 714)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 8, color: SceneColor.ink.withAlphaComponent(0.3).cgColor)
        SceneColor.hex(0x2B2233, 0.94).setFill()
        UIBezierPath(roundedRect: board, cornerRadius: 12).fill()
        ctx.restoreGState()
        let teal = SceneColor.hex(0x5FF2E6)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 7, color: teal.cgColor)
        teal.setStroke()
        let border = UIBezierPath(roundedRect: board.insetBy(dx: 6, dy: 6), cornerRadius: 8)
        border.lineWidth = 2
        border.stroke()
        ctx.restoreGState()
        let pink = SceneColor.hex(0xFF7FB0)
        let font = UIFont.systemFont(ofSize: 30, weight: .heavy)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: SceneColor.lighter(pink, 0.45), .kern: 2]
        let s = "DINER" as NSString
        let ts = s.size(withAttributes: attrs)
        let origin = CGPoint(x: board.midX - ts.width / 2, y: board.midY - ts.height / 2)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 12, color: pink.cgColor)
        s.draw(at: origin, withAttributes: attrs)
        s.draw(at: origin, withAttributes: attrs)
        ctx.restoreGState()
        // Glow spill onto the wall.
        SceneDraw.fillRadial(ctx, clip: band(340, 280, 590, 780), center: CGPoint(x: board.midX, y: board.midY), radius: 130,
                             colors: [pink.withAlphaComponent(0.16), pink.withAlphaComponent(0)], locations: [0, 1])
    }

    /// Conveyor: a steel ticket rail with order slips.
    private func paintTicketRail() {
        let y: CGFloat = 712
        SceneDraw.fillVertical(ctx, rect: band(412, 150, y, y + 8),
                               colors: [UIColor.white, SceneColor.chrome, SceneColor.darker(SceneColor.chrome, 0.3)],
                               locations: [0, 0.4, 1])
        var rng = SceneRNG(seed: 12)
        for (i, tx) in [CGFloat(432), CGFloat(476), CGFloat(522)].enumerated() {
            let ang = rng.range(-0.06, 0.06)
            ctx.saveGState()
            ctx.translateBy(x: tx + 16, y: uy(y + 2))
            ctx.rotate(by: ang)
            ctx.setShadow(offset: CGSize(width: 1, height: 3), blur: 4, color: SceneColor.ink.withAlphaComponent(0.18).cgColor)
            UIColor(white: 0.99, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: -16, y: 0, width: 32, height: 48 - CGFloat(i) * 4)).fill()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.translateBy(x: tx + 16, y: uy(y + 2))
            ctx.rotate(by: ang)
            SceneColor.ink.withAlphaComponent(0.3).setFill()
            for k in 0..<4 {
                ctx.fill(CGRect(x: -11, y: 12 + CGFloat(k) * 7, width: CGFloat(14 + (k * 5 + i * 3) % 9), height: 2))
            }
            SceneColor.hex(0xE8505B).setFill()
            ctx.fill(CGRect(x: -11, y: 4, width: 22, height: 3))
            ctx.restoreGState()
        }
    }

    /// Daily: a tear-off calendar on the wall with today's number.
    private func paintCalendar(_ n: Int) {
        let page = band(446, 88, 620, 726)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 2, height: 4), blur: 7, color: SceneColor.ink.withAlphaComponent(0.22).cgColor)
        UIColor.white.setFill()
        UIBezierPath(roundedRect: page, cornerRadius: 6).fill()
        ctx.restoreGState()
        // Torn-off sheets peeking underneath.
        SceneColor.hex(0xF2EADC).setFill()
        let torn = UIBezierPath()
        torn.move(to: CGPoint(x: page.minX + 4, y: page.maxY))
        var tx = page.minX + 4
        var up = true
        while tx < page.maxX - 4 {
            tx = min(page.maxX - 4, tx + 6)
            torn.addLine(to: CGPoint(x: tx, y: page.maxY + (up ? 5 : 1.5)))
            up.toggle()
        }
        torn.addLine(to: CGPoint(x: page.maxX - 4, y: page.maxY))
        torn.close()
        torn.fill()
        // Header.
        let header = CGRect(x: page.minX, y: page.minY, width: page.width, height: 28)
        SceneColor.hex(0xE8505B).setFill()
        UIBezierPath(roundedRect: header, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 6, height: 6)).fill()
        let hFont = SceneArt.roundedFont(13, weight: .heavy)
        let hAttrs: [NSAttributedString.Key: Any] = [.font: hFont, .foregroundColor: UIColor.white, .kern: 1.5]
        let hs = "DAILY" as NSString
        let hsz = hs.size(withAttributes: hAttrs)
        hs.draw(at: CGPoint(x: header.midX - hsz.width / 2, y: header.midY - hsz.height / 2 + 1), withAttributes: hAttrs)
        // Binder rings.
        for rx in [page.minX + 22, page.maxX - 22] {
            SceneColor.ink.withAlphaComponent(0.55).setFill()
            UIBezierPath(roundedRect: CGRect(x: rx - 2.5, y: page.minY - 7, width: 5, height: 13), cornerRadius: 2.5).fill()
        }
        // The number, shrunk to fit.
        let text = "#\(n)" as NSString
        var size: CGFloat = 36
        var attrs: [NSAttributedString.Key: Any] = [.font: SceneArt.roundedFont(size, weight: .heavy), .foregroundColor: SceneColor.ink]
        while text.size(withAttributes: attrs).width > page.width - 12 && size > 14 {
            size -= 2
            attrs[.font] = SceneArt.roundedFont(size, weight: .heavy)
        }
        let ns = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: page.midX - ns.width / 2, y: header.maxY + 8), withAttributes: attrs)
        let sAttrs: [NSAttributedString.Key: Any] = [.font: SceneArt.roundedFont(11, weight: .bold),
                                                     .foregroundColor: SceneColor.ink.withAlphaComponent(0.45), .kern: 1.2]
        let sub = "POUR" as NSString
        let ssz = sub.size(withAttributes: sAttrs)
        sub.draw(at: CGPoint(x: page.midX - ssz.width / 2, y: page.maxY - ssz.height - 8), withAttributes: sAttrs)
    }

    /// Rush at dusk: a strand of warm bulbs sagging across the wall, under the HUD band.
    private func paintStringLights() {
        let yTop: CGFloat = 834, sag: CGFloat = 46
        func wireY(_ x: CGFloat) -> CGFloat {
            let t = (x - W * 0.5) / (W * 0.5 + 10)
            return yTop - sag * (1 - t * t)
        }
        let wire = UIBezierPath()
        var x: CGFloat = -10
        wire.move(to: pt(x, wireY(x)))
        while x < W + 10 {
            x += 10
            wire.addLine(to: pt(x, wireY(x)))
        }
        wire.lineWidth = 1.6
        SceneColor.ink.withAlphaComponent(0.6).setStroke()
        wire.stroke()
        let colors: [UIColor] = [SceneColor.hex(0xFFD37A), SceneColor.hex(0xFF9D6B), SceneColor.hex(0xFFF0B8), SceneColor.hex(0xFF7FA8)]
        var i = 0
        x = 12
        while x < W {
            let wy = wireY(x)
            let c = colors[i % colors.count]
            let bulbCentre = pt(x, wy - 9)
            SceneDraw.fillRadial(ctx, clip: CGRect(x: bulbCentre.x - 30, y: bulbCentre.y - 30, width: 60, height: 60),
                                 center: bulbCentre, radius: 28, colors: [c.withAlphaComponent(0.55), c.withAlphaComponent(0)],
                                 locations: [0, 1])
            SceneColor.ink.withAlphaComponent(0.75).setFill()
            ctx.fill(CGRect(x: x - 2.5, y: uy(wy) - 1, width: 5, height: 5))
            c.setFill()
            UIBezierPath(ovalIn: CGRect(x: x - 4.5, y: uy(wy) + 3, width: 9, height: 12)).fill()
            UIColor(white: 1, alpha: 0.75).setFill()
            UIBezierPath(ovalIn: CGRect(x: x - 2.5, y: uy(wy) + 5, width: 3, height: 4)).fill()
            x += 44
            i += 1
        }
    }

    // MARK: Small props (stand on the ledge)

    private var ledgeTop: CGFloat { Self.ledgeY + 8 }

    private func lemonBowl(x: CGFloat) {
        let base = ledgeTop
        // Lemons peeking out.
        for (dx, dy, r) in [(CGFloat(-14), CGFloat(20), CGFloat(11)), (CGFloat(10), CGFloat(22), CGFloat(12)), (CGFloat(-1), CGFloat(29), CGFloat(11))] {
            let c = pt(x + dx, base + dy)
            SceneColor.hex(0xFFD84A).setFill()
            UIBezierPath(ovalIn: CGRect(x: c.x - r * 1.15, y: c.y - r, width: r * 2.3, height: r * 2)).fill()
            UIColor(white: 1, alpha: 0.45).setFill()
            UIBezierPath(ovalIn: CGRect(x: c.x - r * 0.6, y: c.y - r * 0.7, width: r * 0.6, height: r * 0.4)).fill()
        }
        // Teal ceramic bowl.
        let bowl = UIBezierPath()
        bowl.move(to: pt(x - 32, base + 22))
        bowl.addQuadCurve(to: pt(x + 32, base + 22), controlPoint: pt(x, base - 18))
        bowl.close()
        SceneColor.teal.setFill()
        bowl.fill()
        UIColor(white: 1, alpha: 0.3).setFill()
        UIBezierPath(ovalIn: CGRect(x: x - 22, y: uy(base + 16), width: 14, height: 4)).fill()
        SceneColor.tealDark.setFill()
        ctx.fill(CGRect(x: x - 12, y: uy(base + 2), width: 24, height: 2))
    }

    private func lemonadeJar(x: CGFloat) {
        let base = ledgeTop
        let body = band(x - 15, 30, base, base + 42)
        SceneColor.hex(0xFFE57A).setFill()
        UIBezierPath(roundedRect: body.insetBy(dx: 2, dy: 6).offsetBy(dx: 0, dy: 5), cornerRadius: 5).fill()
        UIColor(white: 1, alpha: 0.35).setFill()
        UIBezierPath(roundedRect: body, cornerRadius: 7).fill()
        SceneColor.ink.withAlphaComponent(0.25).setStroke()
        let outline = UIBezierPath(roundedRect: body, cornerRadius: 7)
        outline.lineWidth = 1.2
        outline.stroke()
        // Striped straw.
        let straw = UIBezierPath()
        straw.move(to: pt(x + 4, base + 30))
        straw.addLine(to: pt(x + 12, base + 62))
        straw.lineWidth = 4
        straw.lineCapStyle = .round
        UIColor.white.setStroke()
        straw.stroke()
        let dash: [CGFloat] = [4, 4]
        straw.setLineDash(dash, count: 2, phase: 0)
        SceneColor.hex(0xFF6B5B).setStroke()
        straw.stroke()
        // Lemon wheel on the rim.
        SceneDraw.drawDecal(ctx, decal: .lemon, accent: SceneColor.teal, center: pt(x - 10, base + 42), radius: 8)
    }

    private func strawCup(x: CGFloat) {
        let base = ledgeTop
        for (i, dx) in [CGFloat(-6), CGFloat(0), CGFloat(6)].enumerated() {
            let s = UIBezierPath()
            s.move(to: pt(x + dx * 0.5, base + 20))
            s.addLine(to: pt(x + dx * 1.6, base + 56 - CGFloat(i) * 4))
            s.lineWidth = 3
            s.lineCapStyle = .round
            (i % 2 == 0 ? SceneColor.hex(0xE8505B) : UIColor.white).setStroke()
            s.stroke()
        }
        let cup = UIBezierPath()
        cup.move(to: pt(x - 14, base + 34))
        cup.addLine(to: pt(x + 14, base + 34))
        cup.addLine(to: pt(x + 10, base))
        cup.addLine(to: pt(x - 10, base))
        cup.close()
        UIColor.white.setFill()
        cup.fill()
        SceneColor.hex(0xE8505B).setFill()
        ctx.fill(CGRect(x: x - 13, y: uy(base + 26), width: 26, height: 5))
        ctx.fill(CGRect(x: x - 11, y: uy(base + 12), width: 22, height: 5))
    }

    private func shakeGlass(x: CGFloat) {
        let base = ledgeTop
        // Cream dome + cherry.
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: x - 16, y: uy(base + 56), width: 32, height: 18)).fill()
        SceneColor.hex(0xE2324A).setFill()
        UIBezierPath(ovalIn: SceneDraw.circle(pt(x + 2, base + 59), 5)).fill()
        // Glass with pink shake.
        let g = UIBezierPath()
        g.move(to: pt(x - 16, base + 48))
        g.addLine(to: pt(x + 16, base + 48))
        g.addQuadCurve(to: pt(x + 4, base + 12), controlPoint: pt(x + 12, base + 20))
        g.addLine(to: pt(x + 3, base + 4))
        g.addLine(to: pt(x + 10, base))
        g.addLine(to: pt(x - 10, base))
        g.addLine(to: pt(x - 3, base + 4))
        g.addLine(to: pt(x - 4, base + 12))
        g.addQuadCurve(to: pt(x - 16, base + 48), controlPoint: pt(x - 12, base + 20))
        g.close()
        SceneColor.hex(0xFFA3BE).setFill()
        g.fill()
        UIColor(white: 1, alpha: 0.4).setFill()
        ctx.fill(CGRect(x: x - 10, y: uy(base + 44), width: 3, height: 22))
        let straw = UIBezierPath()
        straw.move(to: pt(x + 6, base + 50))
        straw.addLine(to: pt(x + 13, base + 64))
        straw.lineWidth = 3.5
        straw.lineCapStyle = .round
        SceneColor.hex(0x6CC4C9).setStroke()
        straw.stroke()
    }

    private func steelTin(x: CGFloat) {
        let base = ledgeTop
        let tin = UIBezierPath()
        tin.move(to: pt(x - 16, base + 46))
        tin.addLine(to: pt(x + 16, base + 46))
        tin.addLine(to: pt(x + 12, base))
        tin.addLine(to: pt(x - 12, base))
        tin.close()
        ctx.saveGState()
        tin.addClip()
        SceneDraw.fillHorizontal(ctx, rect: band(x - 16, 32, base, base + 46),
                                 colors: [SceneColor.darker(SceneColor.chrome, 0.2), UIColor.white, SceneColor.chrome,
                                          SceneColor.darker(SceneColor.chrome, 0.35)], locations: [0, 0.3, 0.55, 1])
        ctx.restoreGState()
        SceneColor.darker(SceneColor.chrome, 0.3).setFill()
        ctx.fill(CGRect(x: x - 16, y: uy(base + 47), width: 32, height: 3))
    }

    private func bell(x: CGFloat) {
        let base = ledgeTop
        let dome = UIBezierPath()
        dome.move(to: pt(x - 18, base + 6))
        dome.addQuadCurve(to: pt(x + 18, base + 6), controlPoint: pt(x, base + 44))
        dome.close()
        ctx.saveGState()
        dome.addClip()
        SceneDraw.fillHorizontal(ctx, rect: band(x - 18, 36, base + 6, base + 26),
                                 colors: [SceneColor.hex(0xC9962E), SceneColor.hex(0xFFE7A0), SceneColor.hex(0xE0AE3E), SceneColor.hex(0xA87A20)],
                                 locations: [0, 0.3, 0.6, 1])
        ctx.restoreGState()
        SceneColor.hex(0x7D8A96).setFill()
        UIBezierPath(roundedRect: band(x - 22, 44, base, base + 6), cornerRadius: 2).fill()
        UIBezierPath(ovalIn: SceneDraw.circle(pt(x, base + 28), 3.5)).fill()
    }

    private func candle(x: CGFloat, h: CGFloat) {
        let base = ledgeTop
        let flameC = pt(x, base + h + 9)
        SceneDraw.fillRadial(ctx, clip: CGRect(x: flameC.x - 60, y: flameC.y - 60, width: 120, height: 120),
                             center: flameC, radius: 56,
                             colors: [SceneColor.hex(0xFFC27A, 0.42), SceneColor.hex(0xFFC27A, 0)], locations: [0, 1])
        SceneColor.hex(0xF4EAD8).setFill()
        UIBezierPath(roundedRect: band(x - 7, 14, base, base + h), cornerRadius: 3).fill()
        // A wax drip.
        UIBezierPath(roundedRect: band(x - 7, 4, base + h - 12, base + h), cornerRadius: 2).fill()
        SceneColor.ink.withAlphaComponent(0.6).setFill()
        ctx.fill(CGRect(x: x - 0.6, y: uy(base + h + 4), width: 1.2, height: 4))
        let flame = UIBezierPath()
        flame.move(to: pt(x, base + h + 18))
        flame.addQuadCurve(to: pt(x, base + h + 3), controlPoint: pt(x + 7, base + h + 6))
        flame.addQuadCurve(to: pt(x, base + h + 18), controlPoint: pt(x - 7, base + h + 6))
        SceneColor.hex(0xFFC94A).setFill()
        flame.fill()
        SceneColor.hex(0xFFF6D0).setFill()
        UIBezierPath(ovalIn: CGRect(x: x - 2, y: uy(base + h + 10), width: 4, height: 6)).fill()
    }

    private func roundFlask(x: CGFloat, color: UIColor) {
        let base = ledgeTop
        let r: CGFloat = 17
        let c = pt(x, base + r)
        color.withAlphaComponent(0.85).setFill()
        UIBezierPath(ovalIn: SceneDraw.circle(c, r)).fill()
        UIBezierPath(roundedRect: band(x - 5, 10, base + r * 1.6, base + r * 2 + 18), cornerRadius: 2).fill()
        SceneColor.hex(0xB07858).setFill()
        UIBezierPath(roundedRect: band(x - 6, 12, base + r * 2 + 16, base + r * 2 + 24), cornerRadius: 2).fill()
        UIColor(white: 1, alpha: 0.5).setFill()
        UIBezierPath(ovalIn: CGRect(x: c.x - r * 0.6, y: c.y - r * 0.6, width: r * 0.45, height: r * 0.35)).fill()
    }

    private func hourglass(x: CGFloat, h: CGFloat) {
        let base = ledgeTop
        let wood = SceneColor.hex(0x9A6A3E)
        wood.setFill()
        UIBezierPath(roundedRect: band(x - 22, 44, base, base + 6), cornerRadius: 2).fill()
        UIBezierPath(roundedRect: band(x - 22, 44, base + h - 6, base + h), cornerRadius: 2).fill()
        let g = UIBezierPath()
        g.move(to: pt(x - 16, base + h - 6))
        g.addQuadCurve(to: pt(x, base + h * 0.5), controlPoint: pt(x - 16, base + h * 0.62))
        g.addQuadCurve(to: pt(x - 16, base + 6), controlPoint: pt(x - 16, base + h * 0.38))
        g.addLine(to: pt(x + 16, base + 6))
        g.addQuadCurve(to: pt(x, base + h * 0.5), controlPoint: pt(x + 16, base + h * 0.38))
        g.addQuadCurve(to: pt(x + 16, base + h - 6), controlPoint: pt(x + 16, base + h * 0.62))
        g.close()
        UIColor(white: 1, alpha: 0.45).setFill()
        g.fill()
        // Sand: a pile below, a little left on top, a thread between.
        let sand = SceneColor.hex(0xE8B86A)
        sand.setFill()
        let pile = UIBezierPath()
        pile.move(to: pt(x - 14, base + 7))
        pile.addQuadCurve(to: pt(x + 14, base + 7), controlPoint: pt(x, base + h * 0.42))
        pile.close()
        pile.fill()
        let topSand = UIBezierPath()
        topSand.move(to: pt(x - 9, base + h * 0.64))
        topSand.addLine(to: pt(x + 9, base + h * 0.64))
        topSand.addLine(to: pt(x, base + h * 0.52))
        topSand.close()
        topSand.fill()
        ctx.fill(CGRect(x: x - 0.7, y: uy(base + h * 0.52), width: 1.4, height: h * 0.26))
        SceneColor.ink.withAlphaComponent(0.25).setStroke()
        g.lineWidth = 1.2
        g.stroke()
        wood.setFill()
        for dx in [CGFloat(-19), CGFloat(16)] {
            ctx.fill(band(x + dx, 3, base + 6, base + h - 6))
        }
    }

    private func cactus(x: CGFloat) {
        let base = ledgeTop
        let green = SceneColor.hex(0x6FB98A)
        green.setFill()
        UIBezierPath(roundedRect: band(x - 7, 14, base + 16, base + 56), cornerRadius: 7).fill()
        UIBezierPath(roundedRect: band(x - 19, 9, base + 28, base + 44), cornerRadius: 4.5).fill()
        UIBezierPath(roundedRect: band(x - 19, 16, base + 28, base + 34), cornerRadius: 3).fill()
        UIBezierPath(roundedRect: band(x + 10, 9, base + 32, base + 50), cornerRadius: 4.5).fill()
        UIBezierPath(roundedRect: band(x + 4, 14, base + 32, base + 38), cornerRadius: 3).fill()
        SceneColor.hex(0xFF8FA3).setFill()
        UIBezierPath(ovalIn: SceneDraw.circle(pt(x, base + 58), 4)).fill()
        let pot = UIBezierPath()
        pot.move(to: pt(x - 15, base + 20))
        pot.addLine(to: pt(x + 15, base + 20))
        pot.addLine(to: pt(x + 11, base))
        pot.addLine(to: pt(x - 11, base))
        pot.close()
        SceneColor.terracotta.setFill()
        pot.fill()
    }

    private func bottle(x: CGFloat, base: CGFloat, w: CGFloat, h: CGFloat, color: UIColor) {
        let bodyH = h * 0.6, neckW = w * 0.36
        let path = UIBezierPath()
        path.move(to: pt(x - w / 2, base))
        path.addLine(to: pt(x - w / 2, base + bodyH))
        path.addQuadCurve(to: pt(x - neckW / 2, base + bodyH + h * 0.14), controlPoint: pt(x - w / 2, base + bodyH + h * 0.12))
        path.addLine(to: pt(x - neckW / 2, base + h))
        path.addLine(to: pt(x + neckW / 2, base + h))
        path.addLine(to: pt(x + neckW / 2, base + bodyH + h * 0.14))
        path.addQuadCurve(to: pt(x + w / 2, base + bodyH), controlPoint: pt(x + w / 2, base + bodyH + h * 0.12))
        path.addLine(to: pt(x + w / 2, base))
        path.close()
        color.setFill()
        path.fill()
        SceneColor.darker(color, 0.2).setFill()
        UIBezierPath(roundedRect: CGRect(x: x - neckW / 2 - 1.5, y: uy(base + h + 4), width: neckW + 3, height: 6), cornerRadius: 2).fill()
        UIColor(white: 1, alpha: 0.85).setFill()
        UIBezierPath(roundedRect: band(x - w / 2 + 2, w - 4, base + bodyH * 0.25, base + bodyH * 0.6), cornerRadius: 2).fill()
        color.withAlphaComponent(0.6).setFill()
        UIBezierPath(ovalIn: SceneDraw.circle(pt(x, base + bodyH * 0.425), w * 0.16)).fill()
        UIColor(white: 1, alpha: 0.35).setFill()
        UIBezierPath(roundedRect: CGRect(x: x - w / 2 + 3, y: uy(base + bodyH + 4), width: 3, height: bodyH * 0.3), cornerRadius: 1.5).fill()
    }

    private func jar(x: CGFloat, base: CGFloat, w: CGFloat, h: CGFloat, color: UIColor) {
        color.setFill()
        UIBezierPath(roundedRect: CGRect(x: x - w / 2, y: uy(base + h - 6), width: w, height: h - 6), cornerRadius: 6).fill()
        SceneColor.darker(color, 0.18).setFill()
        UIBezierPath(roundedRect: CGRect(x: x - w / 2 - 2, y: uy(base + h + 2), width: w + 4, height: 9), cornerRadius: 3).fill()
        UIColor(white: 1, alpha: 0.35).setFill()
        UIBezierPath(roundedRect: CGRect(x: x - w / 2 + 4, y: uy(base + h - 12), width: 3.5, height: h * 0.45), cornerRadius: 1.75).fill()
    }

    private func plant(x: CGFloat, base: CGFloat, w: CGFloat, h: CGFloat) {
        p.plant.setFill()
        let leaves: [(CGFloat, CGFloat, CGFloat)] = [(-16, 30, -0.7), (14, 34, 0.6), (-4, 40, -0.1), (22, 24, 1.1), (-24, 20, -1.2)]
        for (dx, len, ang) in leaves {
            ctx.saveGState()
            ctx.translateBy(x: x, y: uy(base + h - 2))
            ctx.rotate(by: ang)
            UIBezierPath(ovalIn: CGRect(x: -6 + dx * 0.15, y: -len, width: 12, height: len)).fill()
            ctx.restoreGState()
        }
        let pot = UIBezierPath()
        pot.move(to: pt(x - w / 2, base + h))
        pot.addLine(to: pt(x + w / 2, base + h))
        pot.addLine(to: pt(x + w * 0.36, base))
        pot.addLine(to: pt(x - w * 0.36, base))
        pot.close()
        SceneColor.terracotta.setFill()
        pot.fill()
        SceneColor.lighter(SceneColor.terracotta, 0.2).setFill()
        ctx.fill(CGRect(x: x - w / 2 - 1, y: uy(base + h + 2), width: w + 2, height: 6))
    }

    private func cups(x: CGFloat, base: CGFloat, w: CGFloat, color: UIColor) {
        for i in 0..<4 {
            let y0 = base + CGFloat(i) * 9
            let cup = UIBezierPath()
            cup.move(to: pt(x - w / 2, y0 + 16))
            cup.addLine(to: pt(x + w / 2, y0 + 16))
            cup.addLine(to: pt(x + w * 0.38, y0))
            cup.addLine(to: pt(x - w * 0.38, y0))
            cup.close()
            (i % 2 == 0 ? color : SceneColor.darker(color, 0.08)).setFill()
            cup.fill()
            SceneColor.ink.withAlphaComponent(0.15).setStroke()
            cup.lineWidth = 1
            cup.stroke()
        }
    }
}
