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
    static let jugGlass = hex(0xE4F5FB)
    static let foamDefault = hex(0xFFF6E6)
}

// MARK: - Per-venue palette

/// Everything the backdrop and the props need, per venue. Switch with `GameScene.venue`.
struct ScenePalette {
    var wallTop: UIColor
    var wallBottom: UIColor
    var tile: UIColor
    var grout: UIColor
    var trim: UIColor
    var shelf: UIColor
    var silhouette: UIColor
    var plant: UIColor
    var board: UIColor
    var counterTopBack: UIColor
    var counterTop: UIColor
    var counterEdge: UIColor
    var counterFront: UIColor
    var counterFrontDark: UIColor
    var coaster: UIColor
    var coasterRing: UIColor
    var vignette: UIColor
    var glow: UIColor
    var seam: UIColor
    /// Dark venues (Potion Shop) flip a few contrast choices.
    var isDark: Bool

    static func forVenue(_ venue: VenueID?) -> ScenePalette {
        let h = SceneColor.hex
        switch venue ?? .lemonadeStand {
        case .lemonadeStand:
            return ScenePalette(
                wallTop: h(0xFFF8EC, 1), wallBottom: h(0xFFEFD8, 1),
                tile: h(0xBFE8D8, 1), grout: h(0xE8F6EE, 1), trim: h(0xF6D3A1, 1),
                shelf: h(0xC9875E, 1), silhouette: h(0xEBDAC0, 1), plant: h(0xA9D9BC, 1), board: h(0x3E4A44, 1),
                counterTopBack: h(0xEBA57F, 1), counterTop: h(0xD9825B, 1), counterEdge: h(0xF2B892, 1),
                counterFront: h(0xC66F4A, 1), counterFrontDark: h(0xA4573A, 1),
                coaster: h(0xEBCB9F, 1), coasterRing: h(0xC99A6B, 1),
                vignette: h(0x8A4B2A, 0.20), glow: h(0xFFE2AE, 0.55), seam: h(0xCDB69A, 1), isDark: false)
        case .sodaFountain:
            return ScenePalette(
                wallTop: h(0xFFF5F2, 1), wallBottom: h(0xFFE8E4, 1),
                tile: h(0xFFCAD3, 1), grout: h(0xFFF1F3, 1), trim: h(0xE8505B, 1),
                shelf: h(0xB9C5CD, 1), silhouette: h(0xF3D6D6, 1), plant: h(0x9ED9C4, 1), board: h(0x3B3F4A, 1),
                counterTopBack: h(0xFAFBFC, 1), counterTop: h(0xE2E8EC, 1), counterEdge: h(0xFFFFFF, 1),
                counterFront: h(0xE8505B, 1), counterFrontDark: h(0xC23A47, 1),
                coaster: h(0xFFD5DB, 1), coasterRing: h(0xE8505B, 1),
                vignette: h(0x8A2F3F, 0.18), glow: h(0xFFE0E4, 0.55), seam: h(0xD9B5B5, 1), isDark: false)
        case .milkshakeDiner:
            return ScenePalette(
                wallTop: h(0xFFF9EE, 1), wallBottom: h(0xFFF0DB, 1),
                tile: h(0xBFDDF5, 1), grout: h(0xEBF5FD, 1), trim: h(0xFF8FA3, 1),
                shelf: h(0x9BAAB6, 1), silhouette: h(0xEBE0CD, 1), plant: h(0xA6D8BE, 1), board: h(0x34404D, 1),
                counterTopBack: h(0xFFEAF0, 1), counterTop: h(0xF7C6D3, 1), counterEdge: h(0xE3E8EC, 1),
                counterFront: h(0x6CC4C9, 1), counterFrontDark: h(0x4CA3AA, 1),
                coaster: h(0xFFFFFF, 1), coasterRing: h(0xFF8FA3, 1),
                vignette: h(0x5A3A4A, 0.16), glow: h(0xFFE9C4, 0.5), seam: h(0xC9C0B4, 1), isDark: false)
        case .conveyor:
            return ScenePalette(
                wallTop: h(0xF6F3EC, 1), wallBottom: h(0xEAE5DA, 1),
                tile: h(0xFCE6A6, 1), grout: h(0xFFF6DA, 1), trim: h(0x6C8EAD, 1),
                shelf: h(0x7F8C99, 1), silhouette: h(0xDDD6C7, 1), plant: h(0x9FCFAF, 1), board: h(0x3A4450, 1),
                counterTopBack: h(0xA9BCCB, 1), counterTop: h(0x8399AD, 1), counterEdge: h(0xCBD7E0, 1),
                counterFront: h(0x4E6378, 1), counterFrontDark: h(0x3A4A5B, 1),
                coaster: h(0x3E4955, 1), coasterRing: h(0x5D6E80, 1),
                vignette: h(0x2E3A46, 0.18), glow: h(0xFFF0C8, 0.5), seam: h(0xB9B2A4, 1), isDark: false)
        case .potionShop:
            return ScenePalette(
                wallTop: h(0x4C3C6E, 1), wallBottom: h(0x3B2E5A, 1),
                tile: h(0x5E4F88, 1), grout: h(0x44366C, 1), trim: h(0xC9A3FF, 1),
                shelf: h(0x6B4B3A, 1), silhouette: h(0x5A4A80, 1), plant: h(0x6FBF9A, 1), board: h(0x241C38, 1),
                counterTopBack: h(0x93624A, 1), counterTop: h(0x7A4B3A, 1), counterEdge: h(0xB07858, 1),
                counterFront: h(0x5A3529, 1), counterFrontDark: h(0x40251C, 1),
                coaster: h(0xA68BD6, 1), coasterRing: h(0x7E63B0, 1),
                vignette: h(0x120B20, 0.38), glow: h(0xB78CFF, 0.38), seam: h(0x281F40, 1), isDark: true)
        case .sandBar:
            return ScenePalette(
                wallTop: h(0xFFF3DB, 1), wallBottom: h(0xFFE6BE, 1),
                tile: h(0x9FD8E5, 1), grout: h(0xE3F5F8, 1), trim: h(0xF2B66D, 1),
                shelf: h(0xB78A5E, 1), silhouette: h(0xF0DDBA, 1), plant: h(0x8CCB9B, 1), board: h(0x45503F, 1),
                counterTopBack: h(0xE6C9A2, 1), counterTop: h(0xC9A27E, 1), counterEdge: h(0xEDD6B6, 1),
                counterFront: h(0xA9815E, 1), counterFrontDark: h(0x886645, 1),
                coaster: h(0xF5E5C6, 1), coasterRing: h(0xC9A27E, 1),
                vignette: h(0x7A5530, 0.2), glow: h(0xFFE7B5, 0.55), seam: h(0xD2B892, 1), isDark: false)
        }
    }
}
