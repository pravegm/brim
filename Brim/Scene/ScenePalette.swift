import SpriteKit
import UIKit

// MARK: - Colour helpers (Scene-owned; deliberately namespaced so no other module's extensions can clash)

extension RGBA {
    /// UIKit / SpriteKit colour for a Contracts colour. Named `skColor` so Feedback/App/UI never collide with it.
    var skColor: UIColor {
        UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }
}

enum SceneColor {
    static func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255,
                alpha: alpha)
    }

    static func rgba(_ c: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !c.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var w: CGFloat = 0
            if c.getWhite(&w, alpha: &a) { r = w; g = w; b = w }
        }
        return (r, g, b, a)
    }

    /// Linear mix a→b by t (0…1), including alpha.
    static func mix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        let x = rgba(a), y = rgba(b)
        let k = min(max(t, 0), 1)
        return UIColor(red: x.r + (y.r - x.r) * k, green: x.g + (y.g - x.g) * k,
                       blue: x.b + (y.b - x.b) * k, alpha: x.a + (y.a - x.a) * k)
    }

    /// Mix toward white, keeping the source alpha.
    static func lighter(_ c: UIColor, _ t: CGFloat) -> UIColor {
        let a = rgba(c).a
        return mix(c, UIColor(white: 1, alpha: a), t)
    }

    /// Mix toward the ink colour, keeping the source alpha.
    static func darker(_ c: UIColor, _ t: CGFloat) -> UIColor {
        let a = rgba(c).a
        return mix(c, ink.withAlphaComponent(a), t)
    }

    static func opaque(_ c: UIColor) -> UIColor { c.withAlphaComponent(1) }

    // GAME-DESIGN §8 palette.
    static let cream = hex(0xFFF4E2)
    static let mint = hex(0xBFE8D8)
    static let terracotta = hex(0xD9825B)
    static let ink = hex(0x2B2233)
    static let gold = hex(0xFFC23D)
    static let perfect = hex(0x3FD0FF)
    static let coral = hex(0xFF6B5B)
    static let leaf = hex(0x5FCB8F)
    /// ROUND-5 decision 4: the "OVER" stamp — warm amber, clearly not GREAT's gold nor SPILL!'s coral.
    static let overAmber = hex(0xF59B2E)
    static let jugGlass = hex(0xE4F5FB)
    static let foamDefault = hex(0xFFF6E6)
    /// The icon's teal ceramic (REVIEW-1 P1-9).
    static let teal = hex(0x2BA59A)
    static let tealDark = hex(0x1D7C74)
    static let lemon = hex(0xFFD84A)
    static let chrome = hex(0xC9D3DB)
}

// MARK: - The pouring vessel's dressing (one signature vessel per venue, REVIEW-1 P1-6)

/// The decal painted on the jug's belly.
enum VesselDecal: String {
    case lemon      // Lemonade Stand: the icon's lemon roundel
    case fizz       // Soda Fountain: red roundel with fizz bubbles and a star
    case cherry     // Milkshake Diner: cherry on a pink roundel
    case ticket     // Conveyor: a numbered order tag
    case moon       // Potion Shop: crescent + stars sigil
    case sun        // Sand Bar: a desert sun
}

/// The signature vessel per venue (REVIEW-2 P1-9): a different EXTERIOR drawn around Core's one interior outline.
enum VesselForm: String {
    case pitcher      // Lemonade Stand / Conveyor: clear glass pitcher, ceramic lid with a knob, loop handle
    case dispenser    // Soda Fountain: glass dispenser jug, red handle, chrome hoops, flat chrome lid
    case shakeTin     // Milkshake Diner: brushed-steel shake tin with a sight window, rolled lip, no handle
    case flask        // Potion Shop: thick glass flask with a cork and twine
    case scoop        // Sand Bar: copper measuring scoop, open top, wooden stick handle, graduated sight glass
}

/// How the jug is dressed. The shape itself comes from Core (`JugState.outline`); the scene only paints it.
struct VesselStyle {
    /// Ceramic / metal accent: rim band, handle, foot band, spout lip.
    var accent: UIColor
    var accentDark: UIColor
    /// Translucent fill of the jug's interior (what you see where there is no liquid).
    var glassTint: UIColor
    /// The glass wall stroke.
    var wall: UIColor
    var decal: VesselDecal
    /// Brushed-metal accents (soda chrome, the diner's steel shake tin): adds hairline highlights.
    var metallic: Bool
    /// The exterior drawn around the interior outline.
    var form: VesselForm = .pitcher
}

/// The flat half's surface (seen from above on a Duo).
enum CounterSurface {
    case wood, marble, formica, steel, darkWood
}

// MARK: - Per-venue palette

/// Everything the backdrop and the props need, per venue. Switch with `GameScene.venue` (+ `rushLook`).
struct ScenePalette {
    var venue: VenueID
    var wallTop: UIColor
    var wallBottom: UIColor
    var tile: UIColor
    var grout: UIColor
    var trim: UIColor
    var shelf: UIColor
    var silhouette: UIColor
    var plant: UIColor
    var board: UIColor
    var counterTopBack: UIColor     // far edge of the counter (toward the fold)
    var counterTop: UIColor         // near edge (toward the player)
    var counterEdge: UIColor
    var counterFront: UIColor
    var counterFrontDark: UIColor
    var coaster: UIColor
    var coasterRing: UIColor
    var vignette: UIColor
    var glow: UIColor
    var seam: UIColor
    var surface: CounterSurface
    var vessel: VesselStyle
    /// Dark venues (Potion Shop, Rush dusk) flip a few contrast choices.
    var isDark: Bool
    /// Rush: the dusk look with string lights.
    var dusk: Bool = false

    static func forVenue(_ venue: VenueID?) -> ScenePalette {
        func h(_ x: UInt32, _ a: CGFloat = 1) -> UIColor { SceneColor.hex(x, a) }
        let v = venue ?? .lemonadeStand
        switch v {
        case .lemonadeStand:
            return ScenePalette(
                venue: v,
                wallTop: h(0xFFF8EC, 1), wallBottom: h(0xFFEFD8, 1),
                tile: h(0xBFE8D8, 1), grout: h(0xE8F6EE, 1), trim: h(0xF6D3A1, 1),
                shelf: h(0xC9875E, 1), silhouette: h(0xEBDAC0, 1), plant: h(0x8FD0A8, 1), board: h(0x3E4A44, 1),
                counterTopBack: h(0xF0B98F, 1), counterTop: h(0xD98A5C, 1), counterEdge: h(0xF2B892, 1),
                counterFront: h(0xC66F4A, 1), counterFrontDark: h(0xA4573A, 1),
                coaster: h(0xEBCB9F, 1), coasterRing: h(0xC99A6B, 1),
                vignette: h(0x8A4B2A, 0.20), glow: h(0xFFE2AE, 0.55), seam: h(0xCDB69A, 1),
                surface: .wood,
                vessel: VesselStyle(accent: SceneColor.teal, accentDark: SceneColor.tealDark,
                                    glassTint: h(0xF2FBF9, 0.42), wall: h(0xE6F7F4, 0.80), decal: .lemon, metallic: false),
                isDark: false)
        case .sodaFountain:
            return ScenePalette(
                venue: v,
                wallTop: h(0xFFF6F3, 1), wallBottom: h(0xFFE9E5, 1),
                tile: h(0xFFCAD3, 1), grout: h(0xFFF3F0, 1), trim: h(0xD5DEE5, 1),
                shelf: h(0xB9C5CD, 1), silhouette: h(0xF3D6D6, 1), plant: h(0x9ED9C4, 1), board: h(0x3B3F4A, 1),
                counterTopBack: h(0xFDFDFE, 1), counterTop: h(0xE6EBEF, 1), counterEdge: h(0xFFFFFF, 1),
                counterFront: h(0xE8505B, 1), counterFrontDark: h(0xC23A47, 1),
                coaster: h(0xFFD5DB, 1), coasterRing: h(0xE8505B, 1),
                vignette: h(0x8A2F3F, 0.16), glow: h(0xFFE0E4, 0.55), seam: h(0xD9B5B5, 1),
                surface: .marble,
                vessel: VesselStyle(accent: h(0xE8505B), accentDark: h(0xB8323F),
                                    glassTint: h(0xFFF6F7, 0.40), wall: h(0xF4F7FA, 0.82), decal: .fizz, metallic: false,
                                    form: .dispenser),
                isDark: false)
        case .milkshakeDiner:
            return ScenePalette(
                venue: v,
                wallTop: h(0xFFF9EE, 1), wallBottom: h(0xFFF0DB, 1),
                tile: h(0xBFDDF5, 1), grout: h(0xEBF5FD, 1), trim: h(0xC9D3DB, 1),
                shelf: h(0x9BAAB6, 1), silhouette: h(0xEBE0CD, 1), plant: h(0xA6D8BE, 1), board: h(0x34404D, 1),
                counterTopBack: h(0xE2F7EF, 1), counterTop: h(0xA9DECB, 1), counterEdge: h(0xE3E8EC, 1),
                counterFront: h(0x4FAFA4, 1), counterFrontDark: h(0x3A8F86, 1),
                coaster: h(0xFFFFFF, 1), coasterRing: h(0xFF8FA3, 1),
                vignette: h(0x5A3A4A, 0.15), glow: h(0xFFE9C4, 0.5), seam: h(0xC9C0B4, 1),
                surface: .formica,
                vessel: VesselStyle(accent: h(0xAEB9C3), accentDark: h(0x7D8A96),
                                    glassTint: h(0xE9EEF2, 0.46), wall: h(0xDCE3E9, 0.86), decal: .cherry, metallic: true,
                                    form: .shakeTin),
                isDark: false)
        case .conveyor:
            return ScenePalette(
                venue: v,
                wallTop: h(0xF6F3EC, 1), wallBottom: h(0xEAE5DA, 1),
                tile: h(0xFCE6A6, 1), grout: h(0xFFF6DA, 1), trim: h(0x6C8EAD, 1),
                shelf: h(0x7F8C99, 1), silhouette: h(0xDDD6C7, 1), plant: h(0x9FCFAF, 1), board: h(0x3A4450, 1),
                counterTopBack: h(0xC9D4DD, 1), counterTop: h(0xA3B3C1, 1), counterEdge: h(0xCBD7E0, 1),
                counterFront: h(0x4E6378, 1), counterFrontDark: h(0x3A4A5B, 1),
                coaster: h(0x4A5663, 1), coasterRing: h(0x6B7C8E, 1),
                vignette: h(0x2E3A46, 0.18), glow: h(0xFFF0C8, 0.5), seam: h(0xB9B2A4, 1),
                surface: .steel,
                vessel: VesselStyle(accent: h(0xF2A93B), accentDark: h(0xC27F1E),
                                    glassTint: h(0xF4F8FB, 0.42), wall: h(0xE8F0F5, 0.82), decal: .ticket, metallic: false),
                isDark: false)
        case .potionShop:
            return ScenePalette(
                venue: v,
                wallTop: h(0x3F3163, 1), wallBottom: h(0x4E3E78, 1),
                tile: h(0x5E4F88, 1), grout: h(0x3D3063, 1), trim: h(0xC9A3FF, 1),
                shelf: h(0x6B4B3A, 1), silhouette: h(0x5A4A80, 1), plant: h(0x6FBF9A, 1), board: h(0x241C38, 1),
                counterTopBack: h(0x8A5A44, 1), counterTop: h(0x6A3F31, 1), counterEdge: h(0xB07858, 1),
                counterFront: h(0x5A3529, 1), counterFrontDark: h(0x40251C, 1),
                coaster: h(0xA68BD6, 1), coasterRing: h(0x7E63B0, 1),
                vignette: h(0x120B20, 0.38), glow: h(0xFFC27A, 0.34), seam: h(0x281F40, 1),
                surface: .darkWood,
                vessel: VesselStyle(accent: h(0xE8B84A), accentDark: h(0xB0862A),
                                    glassTint: h(0xD9C8FF, 0.30), wall: h(0xE6DAFF, 0.70), decal: .moon, metallic: false,
                                    form: .flask),
                isDark: true)
        case .sandBar:
            return ScenePalette(
                venue: v,
                wallTop: h(0xFFF3DB, 1), wallBottom: h(0xFFE6BE, 1),
                tile: h(0x9FD8E5, 1), grout: h(0xE3F5F8, 1), trim: h(0xF2B66D, 1),
                shelf: h(0xB78A5E, 1), silhouette: h(0xF0DDBA, 1), plant: h(0x8CCB9B, 1), board: h(0x45503F, 1),
                counterTopBack: h(0xF0D7B2, 1), counterTop: h(0xD1AA80, 1), counterEdge: h(0xEDD6B6, 1),
                counterFront: h(0xA9815E, 1), counterFrontDark: h(0x886645, 1),
                coaster: h(0xF5E5C6, 1), coasterRing: h(0xC9A27E, 1),
                vignette: h(0x7A5530, 0.2), glow: h(0xFFE7B5, 0.55), seam: h(0xD2B892, 1),
                surface: .wood,
                vessel: VesselStyle(accent: h(0xC9824B), accentDark: h(0x94602D),
                                    glassTint: h(0xFFF4DE, 0.40), wall: h(0xFFF2DD, 0.80), decal: .sun, metallic: true,
                                    form: .scoop),
                isDark: false)
        }
    }

    /// Rush: the same venue at dusk — indigo sky fading to a peach glow at the counter, deeper wood, warm lamps.
    func duskified() -> ScenePalette {
        var p = self
        func h(_ x: UInt32, _ a: CGFloat = 1) -> UIColor { SceneColor.hex(x, a) }
        p.dusk = true
        p.wallTop = h(0x3B3566)
        p.wallBottom = h(0xC9787A)
        p.tile = SceneColor.mix(tile, h(0x6A5A8E), 0.55)
        p.grout = SceneColor.mix(grout, h(0x4A3F6E), 0.6)
        p.trim = SceneColor.mix(trim, h(0xF0A070), 0.5)
        p.shelf = SceneColor.darker(shelf, 0.25)
        p.silhouette = SceneColor.mix(silhouette, h(0x5A4A7A), 0.6)
        p.counterTopBack = SceneColor.mix(counterTopBack, h(0xB0705E), 0.45)
        p.counterTop = SceneColor.darker(counterTop, 0.28)
        p.counterEdge = SceneColor.darker(counterEdge, 0.2)
        p.counterFront = SceneColor.darker(counterFront, 0.3)
        p.counterFrontDark = SceneColor.darker(counterFrontDark, 0.35)
        p.coaster = SceneColor.mix(coaster, h(0xF2B48A), 0.3)
        p.vignette = h(0x1A1033, 0.42)
        p.glow = h(0xFFB86B, 0.45)
        p.seam = h(0x5A4570)
        p.isDark = true
        return p
    }
}

// MARK: - How a drink looks in the air and in the glass (REVIEW-2 P1-5)

/// Stream + in-glass colours. Streams are opaque and saturated: a darker keyline, a rich body, a bright core, like
/// the icon. Water gets its own saturated blue (`#7CC8F2`) so it reads on warm wood.
enum SceneLiquidLook {
    struct Stream {
        var edge: UIColor
        var body: UIColor
        var core: UIColor
        /// Never below 0.9 (P1-5: "never below 70 %").
        var alpha: CGFloat
    }

    static let waterBody = SceneColor.hex(0x7CC8F2)

    static func stream(_ l: Liquid) -> Stream {
        let top = SceneColor.opaque(l.top.skColor)
        let bottom = SceneColor.opaque(l.bottom.skColor)
        var body = SceneColor.mix(bottom, top, 0.4)
        var core = SceneColor.lighter(top, 0.55)
        if l.id == .water {
            body = waterBody
            core = SceneColor.hex(0xE4F6FF)
        } else if l.id == .lemonade {
            body = SceneColor.hex(0xFFE04F)
            core = SceneColor.hex(0xFFFBD6)
        }
        let edge = SceneColor.darker(body, 0.3)
        return Stream(edge: edge, body: body, core: core, alpha: CGFloat(max(0.9, min(1, l.opacity + 0.2))))
    }

    /// Top and bottom colours for the in-glass / in-jug gradient (water saturated so a full glass reads as water).
    static func gradient(_ l: Liquid) -> (top: UIColor, bottom: UIColor) {
        if l.id == .water { return (SceneColor.hex(0xBEE9FF), SceneColor.hex(0x5DB9EE)) }
        return (SceneColor.opaque(l.top.skColor), SceneColor.opaque(l.bottom.skColor))
    }

    /// Opacity of the drink inside a glass (water ≥ 0.8 so it isn't invisible).
    static func glassAlpha(_ l: Liquid) -> CGFloat {
        let o = CGFloat(min(max(l.opacity, 0), 1))
        return max(l.id == .water ? 0.82 : 0.7, 0.62 + 0.38 * o)
    }
}
