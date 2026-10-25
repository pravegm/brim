import SpriteKit
import UIKit

/// Stateless drawing helpers (no actor isolation; safe inside image-renderer closures).
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

}

/// A texture plus the size (in world points) to draw it at. SKTexture(image:) sizes are not trusted.
struct SceneSprite {
    let texture: SKTexture
    let size: CGSize
}

/// Everything pre-rendered with UIKit (gradients, the café backdrop, particle dots, text stamps) and cached.
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
        let top = SceneColor.opaque(l.top.skColor)
        let bottom = SceneColor.opaque(l.bottom.skColor)
        return verticalGradient(key: "liquid-\(l.id.rawValue)",
                                colors: [SceneColor.lighter(top, 0.28), top, SceneColor.mix(top, bottom, 0.55), bottom],
                                locations: [0, 0.07, 0.45, 1])
    }

    static func foamTexture(_ l: Liquid) -> SKTexture {
        let foam = SceneColor.opaque(l.foam?.skColor ?? SceneColor.foamDefault)
        return verticalGradient(key: "foam-\(l.id.rawValue)",
                                colors: [SceneColor.lighter(foam, 0.6), foam, SceneColor.mix(foam, SceneColor.opaque(l.top.skColor), 0.25)],
                                locations: [0, 0.35, 1])
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
            ctx.setShadow(offset: CGSize(width: 0, height: pointSize * 0.07), blur: pointSize * 0.14,
                          color: SceneColor.ink.withAlphaComponent(0.35).cgColor)
            let outlineAttrs: [NSAttributedString.Key: Any] = [
                .font: font, .kern: pointSize * 0.02,
                .strokeColor: outline, .strokeWidth: NSNumber(value: Double(26)),
            ]
            (text as NSString).draw(at: origin, withAttributes: outlineAttrs)
            ctx.restoreGState()
            // 2. fill, with a light top sheen
            let fillAttrs: [NSAttributedString.Key: Any] = [.font: font, .kern: pointSize * 0.02, .foregroundColor: fill]
            (text as NSString).draw(at: origin, withAttributes: fillAttrs)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: size.width, height: pad + textSize.height * 0.42))
            let sheenAttrs: [NSAttributedString.Key: Any] = [.font: font, .kern: pointSize * 0.02,
                                                             .foregroundColor: UIColor(white: 1, alpha: 0.28)]
            (text as NSString).draw(at: origin, withAttributes: sheenAttrs)
            ctx.restoreGState()
        }
        let t = SKTexture(image: img)
        t.filteringMode = .linear
        let sprite = SceneSprite(texture: t, size: size)
        labels[key] = sprite
        return sprite
    }

    static func stamp(_ j: Judgement) -> SceneSprite {
        switch j {
        case .perfect: return label("PERFECT", pointSize: 44, fill: SceneColor.perfect, outline: .white, key: "stamp-perfect")
        case .great: return label("GREAT", pointSize: 40, fill: SceneColor.gold, outline: .white, key: "stamp-great")
        case .good: return label("GOOD", pointSize: 36, fill: SceneColor.hex(0x5FCB8F), outline: .white, key: "stamp-good")
        case .short: return label("SHORT", pointSize: 34, fill: SceneColor.hex(0x9A8FB0), outline: .white, key: "stamp-short")
        case .spill: return label("SPILL", pointSize: 40, fill: SceneColor.coral, outline: .white, key: "stamp-spill")
        }
    }

    static func streak(_ n: Int) -> SceneSprite {
        label("STREAK \(n)", pointSize: 22, fill: SceneColor.gold, outline: SceneColor.ink.withAlphaComponent(0.85),
              key: "streak-\(n)")
    }

    // MARK: Backdrop (one texture for the whole canvas)

    static func backdrop(layout: WorldLayout, palette: ScenePalette, scale: CGFloat) -> SKTexture {
        let size = CGSize(width: max(1, layout.size.width), height: max(1, layout.size.height))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = min(max(scale, 1), 3)
        fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
            SceneBackdropPainter(layout: layout, palette: palette, ctx: rc.cgContext).paint()
        }
        let t = SKTexture(image: img)
        t.filteringMode = .linear
        return t
    }
}

// MARK: - Backdrop painter

/// Paints the café in UIKit coordinates (y down). World y converts with `uy(_:)`.
/// Runs synchronously inside `UIGraphicsImageRenderer.image` on the main actor.
@MainActor
private struct SceneBackdropPainter {
    let layout: WorldLayout
    let palette: ScenePalette
    let ctx: CGContext

    var W: CGFloat { layout.size.width }
    var H: CGFloat { layout.size.height }

    func uy(_ worldY: CGFloat) -> CGFloat { H - worldY }

    /// World rect spanning world y0 (bottom) … y1 (top).
    func band(_ x: CGFloat, _ w: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> CGRect {
        CGRect(x: x, y: uy(max(y0, y1)), width: w, height: abs(y1 - y0))
    }

    func paint() {
        let p = palette
        let topY = layout.creaseMaxY
        let botY = layout.creaseMinY

        // Base fill so nothing is ever transparent.
        p.wallBottom.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        paintBackBar(fromY: topY)
        paintCounterSide(belowY: botY)
        paintCrease(minY: botY, maxY: topY)
    }

    // MARK: Top half: the back bar

    private func paintBackBar(fromY y0: CGFloat) {
        let p = palette
        let topH = max(0, H - y0)
        guard topH > 1 else { return }
        let wallRect = band(0, W, y0, H)
        SceneDraw.fillVertical(ctx, rect: wallRect, colors: [p.wallTop, p.wallBottom], locations: [0, 1])

        // Mint tiles from the crease up.
        let tileTop = y0 + min(topH * 0.46, 260)
        paintTiles(y0: y0, y1: tileTop, tile: p.tile, grout: p.grout, tileW: 46, tileH: 23, seed: 7)
        // Trim rail.
        p.trim.setFill()
        ctx.fill(band(0, W, tileTop, tileTop + 7))
        UIColor(white: 1, alpha: 0.5).setFill()
        ctx.fill(band(0, W, tileTop + 5.5, tileTop + 7))
        SceneDraw.fillVertical(ctx, rect: band(0, W, tileTop - 6, tileTop),
                              colors: [SceneColor.ink.withAlphaComponent(0.10), SceneColor.ink.withAlphaComponent(0)],
                              locations: [0, 1])

        // Shelf near the top with silhouetted bottles and a plant.
        let shelfY = H - max(64, min(104, topH * 0.17))
        let roomBelowShelf = (shelfY - 34) - (tileTop + 30)
        if roomBelowShelf >= 70 {
            paintChalkboard(x: 40, y0: tileTop + 30, y1: min(shelfY - 34, tileTop + 30 + 118))
            paintClock(center: CGPoint(x: W - 104, y: (tileTop + 30 + min(shelfY - 34, tileTop + 148)) * 0.5),
                       radius: min(30, roomBelowShelf * 0.32))
        }
        if shelfY > tileTop + 40 {
            paintShelf(y: shelfY)
        }

        // Warm light pooled behind the jug.
        let jp = layout.jugPivot
        SceneDraw.fillRadial(ctx, clip: wallRect, center: CGPoint(x: jp.x, y: uy(jp.y + 30)), radius: 300,
                            colors: [p.glow, p.glow.withAlphaComponent(0)], locations: [0, 1])
        // Vignette.
        let c = CGPoint(x: W * 0.5, y: uy(y0 + topH * 0.45))
        let r = hypot(W * 0.5, topH * 0.62) * 1.08
        SceneDraw.fillRadial(ctx, clip: wallRect, center: c, radius: r,
                            colors: [p.vignette.withAlphaComponent(0), p.vignette.withAlphaComponent(0), p.vignette],
                            locations: [0, 0.6, 1])
    }

    private func paintTiles(y0: CGFloat, y1: CGFloat, tile: UIColor, grout: UIColor, tileW: CGFloat, tileH: CGFloat, seed: UInt64) {
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
                UIBezierPath(roundedRect: r, cornerRadius: 3.5).fill()
                UIColor(white: 1, alpha: 0.28).setFill()
                UIBezierPath(roundedRect: CGRect(x: r.minX + 3, y: r.minY + 1.5, width: r.width - 6, height: 2), cornerRadius: 1).fill()
                x += tileW
            }
            y += tileH
            row += 1
        }
        ctx.restoreGState()
    }

    private func paintChalkboard(x: CGFloat, y0: CGFloat, y1: CGFloat) {
        let p = palette
        let w: CGFloat = 132
        let frame = band(x, w, y0, y1)
        p.shelf.setFill()
        UIBezierPath(roundedRect: frame, cornerRadius: 9).fill()
        let inner = frame.insetBy(dx: 6, dy: 6)
        p.board.setFill()
        UIBezierPath(roundedRect: inner, cornerRadius: 5).fill()
        // Chalk "menu" lines (no text: purely decorative).
        let chalk = UIColor(white: 1, alpha: p.isDark ? 0.30 : 0.38)
        chalk.setStroke()
        let lines = Int(max(2, min(5, (inner.height - 22) / 16)))
        let lengths: [CGFloat] = [0.72, 0.5, 0.64, 0.42, 0.58]
        for i in 0..<lines {
            let ly = inner.minY + 20 + CGFloat(i) * 16
            let path = UIBezierPath()
            path.move(to: CGPoint(x: inner.minX + 30, y: ly))
            path.addLine(to: CGPoint(x: inner.minX + 30 + (inner.width - 42) * lengths[i % lengths.count], y: ly))
            path.lineWidth = 2.2
            path.lineCapStyle = .round
            path.stroke()
            // tiny cup glyph
            let cup = UIBezierPath(roundedRect: CGRect(x: inner.minX + 12, y: ly - 5, width: 9, height: 9), cornerRadius: 2)
            cup.lineWidth = 1.6
            cup.stroke()
        }
        // brim-gold chalk star
        SceneColor.gold.withAlphaComponent(0.8).setFill()
        UIBezierPath(ovalIn: CGRect(x: inner.maxX - 16, y: inner.minY + 8, width: 7, height: 7)).fill()
    }

    private func paintClock(center: CGPoint, radius: CGFloat) {
        guard radius >= 14 else { return }
        let p = palette
        let c = CGPoint(x: center.x, y: uy(center.y))
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 6, color: SceneColor.ink.withAlphaComponent(0.15).cgColor)
        p.trim.setFill()
        UIBezierPath(ovalIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)).fill()
        ctx.restoreGState()
        let face = radius - 4
        (p.isDark ? SceneColor.hex(0xEDE3FF) : UIColor.white).setFill()
        UIBezierPath(ovalIn: CGRect(x: c.x - face, y: c.y - face, width: face * 2, height: face * 2)).fill()
        SceneColor.ink.withAlphaComponent(0.7).setStroke()
        let hands = UIBezierPath()
        hands.move(to: c)
        hands.addLine(to: CGPoint(x: c.x, y: c.y - face * 0.62))
        hands.move(to: c)
        hands.addLine(to: CGPoint(x: c.x + face * 0.45, y: c.y + face * 0.12))
        hands.lineWidth = 2.4
        hands.lineCapStyle = .round
        hands.stroke()
        for i in 0..<12 {
            let a = CGFloat(i) / 12 * 2 * .pi
            let r0 = face * 0.82, r1 = face * (i % 3 == 0 ? 0.66 : 0.74)
            let tick = UIBezierPath()
            tick.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
            tick.addLine(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
            tick.lineWidth = 1.3
            tick.stroke()
        }
    }

    private func paintShelf(y: CGFloat) {
        let p = palette
        // Items first (they stand on the plank).
        let sil = p.silhouette
        let items: [(CGFloat, Int, CGFloat, CGFloat)] = [
            // (x centre, kind, width, height). kinds: 0 tall bottle, 1 round bottle, 2 jar, 3 plant, 4 cup stack
            (66, 0, 24, 72), (100, 1, 32, 52), (146, 2, 36, 38), (214, 3, 36, 30),
            (W - 236, 4, 34, 40), (W - 176, 0, 22, 62), (W - 136, 0, 28, 78), (W - 92, 2, 30, 30),
        ]
        for (x, kind, w, h) in items {
            switch kind {
            case 0: bottle(x: x, base: y, w: w, h: h, color: sil)
            case 1: roundBottle(x: x, base: y, w: w, h: h, color: sil)
            case 2: jar(x: x, base: y, w: w, h: h, color: sil)
            case 3: plant(x: x, base: y, w: w, h: h)
            default: cups(x: x, base: y, w: w, h: h, color: sil)
            }
        }
        // Plank.
        let plank = band(22, W - 44, y - 10, y)
        p.shelf.setFill()
        UIBezierPath(roundedRect: plank, cornerRadius: 3).fill()
        SceneColor.lighter(p.shelf, 0.3).setFill()
        ctx.fill(CGRect(x: plank.minX + 2, y: plank.minY, width: plank.width - 4, height: 2.5))
        SceneDraw.fillVertical(ctx, rect: band(22, W - 44, y - 26, y - 10),
                              colors: [SceneColor.ink.withAlphaComponent(0.13), SceneColor.ink.withAlphaComponent(0)],
                              locations: [0, 1])
        // Brackets.
        SceneColor.darker(p.shelf, 0.15).setFill()
        for bx in [CGFloat(84), W - 84] {
            let br = UIBezierPath()
            br.move(to: CGPoint(x: bx - 4, y: uy(y - 10)))
            br.addLine(to: CGPoint(x: bx + 14, y: uy(y - 10)))
            br.addLine(to: CGPoint(x: bx - 4, y: uy(y - 28)))
            br.close()
            br.fill()
        }
    }

    private func bottle(x: CGFloat, base: CGFloat, w: CGFloat, h: CGFloat, color: UIColor) {
        let bodyH = h * 0.6, neckW = w * 0.36
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x - w / 2, y: uy(base)))
        path.addLine(to: CGPoint(x: x - w / 2, y: uy(base + bodyH)))
        path.addQuadCurve(to: CGPoint(x: x - neckW / 2, y: uy(base + bodyH + h * 0.14)), controlPoint: CGPoint(x: x - w / 2, y: uy(base + bodyH + h * 0.12)))
        path.addLine(to: CGPoint(x: x - neckW / 2, y: uy(base + h)))
        path.addLine(to: CGPoint(x: x + neckW / 2, y: uy(base + h)))
        path.addLine(to: CGPoint(x: x + neckW / 2, y: uy(base + bodyH + h * 0.14)))
        path.addQuadCurve(to: CGPoint(x: x + w / 2, y: uy(base + bodyH)), controlPoint: CGPoint(x: x + w / 2, y: uy(base + bodyH + h * 0.12)))
        path.addLine(to: CGPoint(x: x + w / 2, y: uy(base)))
        path.close()
        color.setFill()
        path.fill()
        SceneColor.darker(color, 0.12).setFill()
        UIBezierPath(roundedRect: CGRect(x: x - neckW / 2 - 1.5, y: uy(base + h + 4), width: neckW + 3, height: 6), cornerRadius: 2).fill()
        UIColor(white: 1, alpha: 0.3).setFill()
        UIBezierPath(roundedRect: CGRect(x: x - w / 2 + 4, y: uy(base + bodyH - 6), width: 3.5, height: bodyH * 0.6), cornerRadius: 1.75).fill()
    }

    private func roundBottle(x: CGFloat, base: CGFloat, w: CGFloat, h: CGFloat, color: UIColor) {
        color.setFill()
        let body = CGRect(x: x - w / 2, y: uy(base + w), width: w, height: w)
        UIBezierPath(ovalIn: body).fill()
        let neckW = w * 0.3
        UIBezierPath(roundedRect: CGRect(x: x - neckW / 2, y: uy(base + h), width: neckW, height: h - w * 0.8), cornerRadius: 2).fill()
        SceneColor.darker(color, 0.12).setFill()
        UIBezierPath(roundedRect: CGRect(x: x - neckW / 2 - 1.5, y: uy(base + h + 3), width: neckW + 3, height: 5), cornerRadius: 2).fill()
    }

    private func jar(x: CGFloat, base: CGFloat, w: CGFloat, h: CGFloat, color: UIColor) {
        color.setFill()
        UIBezierPath(roundedRect: CGRect(x: x - w / 2, y: uy(base + h - 6), width: w, height: h - 6), cornerRadius: 6).fill()
        SceneColor.darker(color, 0.14).setFill()
        UIBezierPath(roundedRect: CGRect(x: x - w / 2 - 2, y: uy(base + h + 2), width: w + 4, height: 9), cornerRadius: 3).fill()
        UIColor(white: 1, alpha: 0.28).setFill()
        UIBezierPath(roundedRect: CGRect(x: x - w / 2 + 4, y: uy(base + h - 12), width: 3.5, height: h * 0.45), cornerRadius: 1.75).fill()
    }

    private func plant(x: CGFloat, base: CGFloat, w: CGFloat, h: CGFloat) {
        let p = palette
        // Leaves.
        let leaf = p.plant
        leaf.setFill()
        let leaves: [(CGFloat, CGFloat, CGFloat)] = [(-16, 34, -0.7), (14, 38, 0.6), (-4, 46, -0.1), (22, 26, 1.1), (-24, 22, -1.2)]
        for (dx, len, ang) in leaves {
            ctx.saveGState()
            ctx.translateBy(x: x, y: uy(base + h - 2))
            ctx.rotate(by: ang)
            UIBezierPath(ovalIn: CGRect(x: -6 + dx * 0.15, y: -len, width: 12, height: len)).fill()
            ctx.restoreGState()
        }
        // Pot.
        let pot = UIBezierPath()
        pot.move(to: CGPoint(x: x - w / 2, y: uy(base + h)))
        pot.addLine(to: CGPoint(x: x + w / 2, y: uy(base + h)))
        pot.addLine(to: CGPoint(x: x + w * 0.36, y: uy(base)))
        pot.addLine(to: CGPoint(x: x - w * 0.36, y: uy(base)))
        pot.close()
        SceneColor.terracotta.setFill()
        pot.fill()
        SceneColor.lighter(SceneColor.terracotta, 0.2).setFill()
        ctx.fill(CGRect(x: x - w / 2 - 1, y: uy(base + h + 2), width: w + 2, height: 6))
    }

    private func cups(x: CGFloat, base: CGFloat, w: CGFloat, h: CGFloat, color: UIColor) {
        for i in 0..<3 {
            let y0 = base + CGFloat(i) * 9
            let cup = UIBezierPath()
            cup.move(to: CGPoint(x: x - w / 2, y: uy(y0 + 16)))
            cup.addLine(to: CGPoint(x: x + w / 2, y: uy(y0 + 16)))
            cup.addLine(to: CGPoint(x: x + w * 0.38, y: uy(y0)))
            cup.addLine(to: CGPoint(x: x - w * 0.38, y: uy(y0)))
            cup.close()
            (i % 2 == 0 ? color : SceneColor.darker(color, 0.06)).setFill()
            cup.fill()
        }
        _ = h
    }

    // MARK: Bottom half: backsplash + counter

    private func paintCounterSide(belowY y1: CGFloat) {
        let p = palette
        guard y1 > 1 else { return }
        let cy = layout.counterY
        let topBack = min(cy + 34, y1)

        // Backsplash (the wall continues behind the counter), slightly deeper than the top half.
        if y1 > topBack {
            let rect = band(0, W, topBack, y1)
            SceneDraw.fillVertical(ctx, rect: rect, colors: [p.wallBottom, p.wallBottom], locations: [0, 1])
            paintTiles(y0: topBack, y1: y1, tile: SceneColor.darker(p.tile, 0.035), grout: SceneColor.darker(p.grout, 0.03),
                       tileW: 46, tileH: 23, seed: 11)
            // Ambient occlusion under the raised half (Duo only), and above the counter.
            if layout.hasFold {
                SceneDraw.fillVertical(ctx, rect: band(0, W, max(topBack, y1 - 90), y1),
                                      colors: [SceneColor.ink.withAlphaComponent(p.isDark ? 0.30 : 0.13), SceneColor.ink.withAlphaComponent(0)],
                                      locations: [0, 1])
            }
            SceneDraw.fillVertical(ctx, rect: band(0, W, topBack, min(y1, topBack + 36)),
                                  colors: [SceneColor.ink.withAlphaComponent(0), SceneColor.ink.withAlphaComponent(p.isDark ? 0.25 : 0.10)],
                                  locations: [0, 1])
            // Warm pool of light where the glass stands.
            let jp = layout.jugPivot
            SceneDraw.fillRadial(ctx, clip: rect, center: CGPoint(x: jp.x, y: uy(topBack + 40)), radius: 260,
                                colors: [p.glow.withAlphaComponent(0.4), p.glow.withAlphaComponent(0)], locations: [0, 1])
        }

        // Counter top (seen slightly from above): lighter at the back, richer at the front edge.
        let topFront = max(0, cy - 16)
        let topRect = band(0, W, topFront, topBack)
        SceneDraw.fillVertical(ctx, rect: topRect, colors: [p.counterTopBack, p.counterTop], locations: [0, 1])
        var rng = SceneRNG(seed: 29)
        ctx.saveGState()
        ctx.clip(to: topRect)
        for _ in 0..<16 {
            let gy = rng.range(topFront + 3, topBack - 3)
            let gx = rng.range(-40, W)
            let len = rng.range(60, 220)
            let grain = UIBezierPath()
            grain.move(to: CGPoint(x: gx, y: uy(gy)))
            grain.addQuadCurve(to: CGPoint(x: gx + len, y: uy(gy + rng.range(-1.5, 1.5))),
                               controlPoint: CGPoint(x: gx + len * 0.5, y: uy(gy + rng.range(-2.5, 2.5))))
            grain.lineWidth = rng.range(0.8, 1.6)
            SceneColor.darker(p.counterTop, 0.25).withAlphaComponent(0.16).setStroke()
            grain.stroke()
        }
        ctx.restoreGState()
        SceneColor.ink.withAlphaComponent(0.12).setFill()
        ctx.fill(band(0, W, topBack - 1.2, topBack))
        UIColor(white: 1, alpha: 0.10).setFill()
        ctx.fill(band(0, W, topFront + 2, topFront + 8))

        // Bull-nose front edge.
        let edgeBottom = max(0, cy - 26)
        SceneDraw.fillVertical(ctx, rect: band(0, W, edgeBottom, topFront),
                              colors: [p.counterEdge, p.counterFront], locations: [0, 1])
        UIColor(white: 1, alpha: 0.5).setFill()
        ctx.fill(band(0, W, topFront - 1.5, topFront))

        // Front panel with vertical boards.
        if edgeBottom > 0 {
            let panel = band(0, W, 0, edgeBottom)
            SceneDraw.fillVertical(ctx, rect: panel, colors: [p.counterFront, p.counterFrontDark], locations: [0, 1])
            var x: CGFloat = 28
            while x < W {
                SceneColor.ink.withAlphaComponent(0.13).setFill()
                ctx.fill(CGRect(x: x, y: panel.minY, width: 2, height: panel.height))
                UIColor(white: 1, alpha: 0.09).setFill()
                ctx.fill(CGRect(x: x + 2, y: panel.minY, width: 1.5, height: panel.height))
                x += 64
            }
            SceneDraw.fillVertical(ctx, rect: band(0, W, max(0, edgeBottom - 14), edgeBottom),
                                  colors: [SceneColor.ink.withAlphaComponent(0.22), SceneColor.ink.withAlphaComponent(0)],
                                  locations: [0, 1])
        }

        // Bottom vignette.
        let all = band(0, W, 0, y1)
        SceneDraw.fillRadial(ctx, clip: all, center: CGPoint(x: W * 0.5, y: uy(y1 * 0.6)), radius: hypot(W * 0.5, y1 * 0.7) * 1.05,
                            colors: [p.vignette.withAlphaComponent(0), p.vignette.withAlphaComponent(0), p.vignette.withAlphaComponent(0.9 * SceneColor.rgba(p.vignette).a)],
                            locations: [0, 0.62, 1])
    }

    // MARK: The fold

    private func paintCrease(minY: CGFloat, maxY: CGFloat) {
        let p = palette
        guard maxY - minY > 0.5 else { return }   // phones without a fold: nothing
        let rect = band(0, W, minY, maxY)
        let top = SceneColor.darker(p.wallBottom, 0.10)
        let mid = SceneColor.mix(p.seam, SceneColor.darker(p.wallBottom, 0.2), 0.5)
        let bottom = SceneColor.darker(p.wallBottom, 0.14)
        SceneDraw.fillVertical(ctx, rect: rect, colors: [top, mid, bottom], locations: [0, 0.5, 1])
        // The hinge line.
        let midY = (minY + maxY) * 0.5
        SceneColor.ink.withAlphaComponent(0.16).setFill()
        ctx.fill(band(0, W, midY - 0.75, midY + 0.75))
        // Edge catch-lights.
        UIColor(white: 1, alpha: 0.28).setFill()
        ctx.fill(band(0, W, maxY - 1, maxY))
        UIColor(white: 1, alpha: 0.12).setFill()
        ctx.fill(band(0, W, minY, minY + 1))
        // The raised half casts a soft shadow onto the flat half.
        SceneDraw.fillVertical(ctx, rect: band(0, W, max(0, minY - 22), minY),
                              colors: [SceneColor.ink.withAlphaComponent(0.12), SceneColor.ink.withAlphaComponent(0)],
                              locations: [0, 1])
    }
}
