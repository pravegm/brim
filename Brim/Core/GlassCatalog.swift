import CoreGraphics
import Foundation

/// The 11 glass styles. Profiles are interior half-widths (x) at heights (y) from the inner floor to the rim.
/// Volumes are 2D areas; for reference a tumbler holds ~7,300 pt² and the standard jug ~28,400 pt².
enum GlassCatalog {

    static let all: [GlassShape] = [
        // Straight, gently tapered everyday glass. Level rises almost linearly.
        make("tumbler", "Tumbler", .tumbler,
             [(27, 0), (28, 6), (33, 120)], base: 12, wall: 3),
        // Tall and straight: fast-rising level, tall lines.
        make("highball", "Highball", .highball,
             [(23, 0), (24, 6), (26, 180)], base: 12, wall: 3),
        // Narrow tulip on a stem: a small flow error is a big level change.
        make("flute", "Flute", .flute,
             [(4, 0), (11, 12), (17, 40), (21, 90), (22.5, 150), (22, 205)], base: 40, wall: 2),
        // Wide diner mug: slow, steady rise.
        make("mug", "Diner Mug", .mug,
             [(40, 0), (42, 8), (43, 118)], base: 10, wall: 6),
        // Goblet bowl, wide at the top: rises fast at first, crawls near the rim.
        make("bowl", "Goblet", .bowl,
             [(6, 0), (24, 8), (42, 30), (56, 62), (65, 98), (70, 126)], base: 36, wall: 2.5),
        // Sundae tulip: bulb, waist, then a wide flare at the top.
        make("sundae", "Sundae Glass", .sundae,
             [(7, 0), (20, 12), (33, 38), (37, 68), (35, 92), (42, 120), (55, 148)], base: 30, wall: 3),
        // Tiny round-bottomed vial with a flared lip.
        make("vial", "Vial", .vial,
             [(5, 0), (11, 5), (14, 14), (15, 98), (22, 110)], base: 18, wall: 2),
        // Lab beaker with a slight lip (draw mL ticks on it).
        make("beaker", "Beaker", .beaker,
             [(30, 0), (31, 4), (31, 152), (34, 160)], base: 6, wall: 2.5),
        // Mason jar: wide body, shoulder, narrow mouth — the level speeds up near the top.
        make("jar", "Mason Jar", .jar,
             [(37, 0), (41, 8), (43, 108), (40, 126), (33, 138), (33, 150)], base: 10, wall: 4),
        // Tall soda glass: cone with a bulge near the top.
        make("pint", "Soda Glass", .pint,
             [(25, 0), (28, 10), (37, 140), (41, 160), (38, 176), (39, 186)], base: 10, wall: 3.5),
        // Thick-bottomed tiny cup: tiny volume, needs a trickle.
        make("shot", "Tiny Cup", .shot,
             [(15, 0), (17, 4), (23, 90)], base: 16, wall: 5),
    ]

    private static let byID: [String: GlassShape] = {
        var d: [String: GlassShape] = [:]
        for g in GlassCatalog.all { d[g.id] = g }
        return d
    }()

    /// Falls back to the tumbler for unknown ids.
    static func shape(_ id: String) -> GlassShape {
        if let g = byID[id] { return g }
        return all[0]
    }

    private static func make(_ id: String, _ name: String, _ style: GlassStyle, _ pts: [(Double, Double)],
                             base: Double, wall: Double) -> GlassShape {
        let profile: [CGPoint] = pts.map { (p: (Double, Double)) -> CGPoint in CGPoint(x: CGFloat(p.0), y: CGFloat(p.1)) }
        return GlassShape(id: id, name: name, style: style, profile: profile,
                          baseThickness: CGFloat(base), wall: CGFloat(wall))
    }
}

/// Volume ↔ height through a glass profile. Volume is 2D area: V(h) = ∫₀ʰ 2·halfWidth(y) dy.
enum GlassMath {

    static func halfWidth(_ s: GlassShape, at h: CGFloat) -> CGFloat {
        let p: [CGPoint] = s.profile
        guard let first = p.first, let last = p.last else { return 0 }
        if h <= first.y { return first.x }
        if h >= last.y { return last.x }
        var i: Int = 1
        while i < p.count {
            let a: CGPoint = p[i - 1]
            let b: CGPoint = p[i]
            if h <= b.y {
                let dy: CGFloat = b.y - a.y
                if dy <= 0 { return b.x }
                let t: CGFloat = (h - a.y) / dy
                return a.x + (b.x - a.x) * t
            }
            i += 1
        }
        return last.x
    }

    /// 2D area from the floor up to `h` (clamped to 0…rim).
    static func volume(_ s: GlassShape, upTo h: CGFloat) -> CGFloat {
        let p: [CGPoint] = s.profile
        if p.count < 2 { return 0 }
        let top: CGFloat = min(max(h, 0), s.interiorHeight)
        var v: CGFloat = 0
        var i: Int = 1
        while i < p.count {
            let a: CGPoint = p[i - 1]
            let b: CGPoint = p[i]
            i += 1
            if top <= a.y { break }
            let dy: CGFloat = b.y - a.y
            if dy <= 0 { continue }
            if top >= b.y {
                v += (a.x + b.x) * dy
            } else {
                let t: CGFloat = (top - a.y) / dy
                let xh: CGFloat = a.x + (b.x - a.x) * t
                v += (a.x + xh) * (top - a.y)
                break
            }
        }
        return v
    }

    /// Inverse of `volume`; at or above capacity → the rim height.
    static func height(_ s: GlassShape, forVolume v: CGFloat) -> CGFloat {
        if v <= 0 { return 0 }
        let p: [CGPoint] = s.profile
        if p.count < 2 { return 0 }
        var remaining: CGFloat = v
        var i: Int = 1
        while i < p.count {
            let a: CGPoint = p[i - 1]
            let b: CGPoint = p[i]
            i += 1
            let dy: CGFloat = b.y - a.y
            if dy <= 0 { continue }
            let seg: CGFloat = (a.x + b.x) * dy
            if remaining <= seg {
                // Area from a.y to a.y + d is 2·a.x·d + slope·d²; solve the quadratic in its stable form.
                let slope: CGFloat = (b.x - a.x) / dy
                let disc: CGFloat = max(0, a.x * a.x + slope * remaining)
                let denom: CGFloat = a.x + disc.squareRoot()
                let d: CGFloat = denom > 1e-9 ? remaining / denom : 0
                return min(a.y + min(max(d, 0), dy), s.interiorHeight)
            }
            remaining -= seg
        }
        return s.interiorHeight
    }

    static func capacity(_ s: GlassShape) -> CGFloat {
        return volume(s, upTo: s.interiorHeight)
    }
}
