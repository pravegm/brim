import CoreGraphics
import Foundation

/// The 11 glass styles. Profiles are interior half-widths (x) at heights (y) from the inner floor to the rim.
/// Volumes are 2D areas.
///
/// Round 2 scale (one 670 × 952 world): profiles are the round-1 shapes ×1.45–1.6 wide and ×1.25–1.45 tall, so a
/// tumbler's rim is ~115 pt wide outside (53 interior half-width + 4.5 wall) and holds ~17,000 pt². Every glass keeps
/// base + interior ≤ 312, so on the counter (y 104) its rim stays ≥ 40 pt below the crease (456).
enum GlassCatalog {

    /// Tallest allowed base + interior (rim ≥ 40 pt below `WorldLayout.creaseBottom` when standing on the counter).
    static let maxStandingHeight: CGFloat = 312

    static let all: [GlassShape] = [
        // Straight, gently tapered everyday glass. Level rises almost linearly.
        make("tumbler", "Tumbler", .tumbler,
             [(43, 0), (45, 9), (53, 174)], base: 16, wall: 4.5),
        // Tall and straight: fast-rising level, tall lines.
        make("highball", "Highball", .highball,
             [(34, 0), (36, 9), (39, 261)], base: 16, wall: 4.5),
        // Narrow tulip on a stem: a small flow error is a big level change.
        make("flute", "Flute", .flute,
             [(6, 0), (16.5, 15), (25.5, 50), (31.5, 112.5), (34, 187.5), (33, 256)], base: 50, wall: 3),
        // Wide diner mug: slow, steady rise.
        make("mug", "Diner Mug", .mug,
             [(56, 0), (59, 12), (60, 171)], base: 14, wall: 8),
        // Goblet bowl, wide at the top: rises fast at first, crawls near the rim.
        make("bowl", "Goblet", .bowl,
             [(8, 0), (31, 12), (55, 44), (73, 90), (85, 142), (91, 183)], base: 50, wall: 3.5),
        // Sundae tulip: bulb, waist, then a wide flare at the top.
        make("sundae", "Sundae Glass", .sundae,
             [(9.5, 0), (27, 17), (44.5, 55), (50, 99), (47, 133), (56.5, 174), (74, 215)], base: 42, wall: 4),
        // Tiny round-bottomed vial with a flared lip.
        make("vial", "Vial", .vial,
             [(7.5, 0), (16.5, 7), (21, 20), (22.5, 142), (33, 160)], base: 26, wall: 3),
        // Lab beaker with a slight lip (draw mL ticks on it).
        make("beaker", "Beaker", .beaker,
             [(43.5, 0), (45, 6), (45, 220), (49, 232)], base: 9, wall: 3.5),
        // Mason jar: wide body, shoulder, narrow mouth — the level speeds up near the top.
        make("jar", "Mason Jar", .jar,
             [(53.5, 0), (59.5, 12), (62.5, 157), (58, 183), (48, 200), (48, 217)], base: 14, wall: 5.5),
        // Tall soda glass: cone with a bulge near the top.
        make("pint", "Soda Glass", .pint,
             [(36, 0), (40.5, 14), (53.5, 203), (59.5, 232), (55, 255), (56.5, 270)], base: 14, wall: 5),
        // Thick-bottomed tiny cup: tiny volume, needs a trickle.
        make("shot", "Tiny Cup", .shot,
             [(22.5, 0), (25.5, 6), (34.5, 130)], base: 22, wall: 7),
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
