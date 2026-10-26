import CoreGraphics
import Foundation

/// Every drink's look and personality. Pure data.
enum LiquidCatalog {

    static func liquid(_ id: LiquidID) -> Liquid {
        switch id {
        case .water:
            return Liquid(id: .water, name: "Water",
                          top: RGBA(hex: 0xC9F0FF, alpha: 0.75), bottom: RGBA(hex: 0x6CC4F2, alpha: 0.85), foam: nil,
                          lagTau: 0.04, foamPerVolume: 0, foamSettle: 1, reposeDegrees: 0, opacity: 0.45, fizzy: false)
        case .lemonade:
            return Liquid(id: .lemonade, name: "Lemonade",
                          top: RGBA(hex: 0xFFF7A6), bottom: RGBA(hex: 0xFFDB3D), foam: nil,
                          lagTau: 0.05, foamPerVolume: 0, foamSettle: 1, reposeDegrees: 0, opacity: 0.8, fizzy: false)
        case .orangeJuice:
            return Liquid(id: .orangeJuice, name: "Orange Juice",
                          top: RGBA(hex: 0xFFC04D), bottom: RGBA(hex: 0xFF7F11), foam: nil,
                          lagTau: 0.08, foamPerVolume: 0, foamSettle: 1, reposeDegrees: 0, opacity: 0.95, fizzy: false)
        case .cola:
            return Liquid(id: .cola, name: "Cola",
                          top: RGBA(hex: 0x7A4422), bottom: RGBA(hex: 0x2B1206), foam: RGBA(hex: 0xEACDA2),
                          lagTau: 0.05, foamPerVolume: 0.9, foamSettle: 1.4, reposeDegrees: 0, opacity: 0.95, fizzy: true)
        case .rootBeer:
            return Liquid(id: .rootBeer, name: "Root Beer",
                          top: RGBA(hex: 0x8A4318), bottom: RGBA(hex: 0x3E1605), foam: RGBA(hex: 0xF5E2C0),
                          lagTau: 0.06, foamPerVolume: 1.3, foamSettle: 2.0, reposeDegrees: 0, opacity: 0.95, fizzy: true)
        case .creamSoda:
            // Round 6 (REVIEW-5 §5.4, founder decision 6): pale gold under a tall white head read as lager. Now a warm
            // vanilla top over a caramel-amber bottom (redder and browner than any beer, lighter than cola/root beer)
            // and a smaller, whiter head (foamPerVolume × foamSettle 0.66 → 0.36). foamPerVolume stays in the same
            // Daily class (> 0.3, ≤ 1.0: "foamy", line cap 0.8) so every version still generates the same Daily.
            return Liquid(id: .creamSoda, name: "Cream Soda",
                          top: RGBA(hex: 0xFCE3C4), bottom: RGBA(hex: 0xD2844A), foam: RGBA(hex: 0xFFFFFD),
                          lagTau: 0.05, foamPerVolume: 0.4, foamSettle: 0.9, reposeDegrees: 0, opacity: 0.82, fizzy: true)
        case .milkshake:
            return Liquid(id: .milkshake, name: "Strawberry Shake",
                          top: RGBA(hex: 0xFFC7DA), bottom: RGBA(hex: 0xFF8AB3), foam: nil,
                          lagTau: 0.45, foamPerVolume: 0, foamSettle: 1, reposeDegrees: 0, opacity: 1.0, fizzy: false)
        case .honey:
            return Liquid(id: .honey, name: "Honey",
                          top: RGBA(hex: 0xFFCB45), bottom: RGBA(hex: 0xD9850A), foam: nil,
                          lagTau: 0.8, foamPerVolume: 0, foamSettle: 1, reposeDegrees: 0, opacity: 0.9, fizzy: false)
        case .mapleSyrup:
            return Liquid(id: .mapleSyrup, name: "Maple Syrup",
                          top: RGBA(hex: 0xD27E2C), bottom: RGBA(hex: 0x7A3B0C), foam: nil,
                          lagTau: 0.6, foamPerVolume: 0, foamSettle: 1, reposeDegrees: 0, opacity: 0.92, fizzy: false)
        case .berrySmoothie:
            return Liquid(id: .berrySmoothie, name: "Berry Smoothie",
                          top: RGBA(hex: 0xE065A8), bottom: RGBA(hex: 0x7C2A80), foam: nil,
                          lagTau: 0.35, foamPerVolume: 0, foamSettle: 1, reposeDegrees: 0, opacity: 1.0, fizzy: false)
        case .potionBlue:
            return Liquid(id: .potionBlue, name: "Sky Draught",
                          top: RGBA(hex: 0x7BF5FF), bottom: RGBA(hex: 0x2B55FF), foam: RGBA(hex: 0xD2FCFF),
                          lagTau: 0.03, foamPerVolume: 0.25, foamSettle: 0.8, reposeDegrees: 0, opacity: 0.85, fizzy: true)
        case .potionPink:
            return Liquid(id: .potionPink, name: "Fizzy Charm",
                          top: RGBA(hex: 0xFFA3F2), bottom: RGBA(hex: 0xC026D9), foam: RGBA(hex: 0xFFE3FB),
                          lagTau: 0.15, foamPerVolume: 0.35, foamSettle: 1.0, reposeDegrees: 0, opacity: 0.85, fizzy: true)
        case .sand:
            return Liquid(id: .sand, name: "Sand",
                          top: RGBA(hex: 0xF5DCA8), bottom: RGBA(hex: 0xD6A256), foam: nil,
                          lagTau: 0.03, foamPerVolume: 0, foamSettle: 1, reposeDegrees: 30, opacity: 1.0, fizzy: false)
        }
    }

    static let all: [Liquid] = LiquidID.allCases.map { (id: LiquidID) -> Liquid in LiquidCatalog.liquid(id) }
}
