import CoreGraphics
import Foundation

/// All shifts (40 campaign levels + 4 secret Sand Bar levels), venue titles and unlocks, and the Daily Pour.
///
/// Difficulty levers (GAME-DESIGN §6, research/03 ramp): jug fill (emptier = steeper tip), glass geometry (straight →
/// flute/bowl/jar/shot), patience, the Perfect band (±3.5 % → ±1.8 %), behaviour stacking (foam, viscosity), and
/// curveballs introduced one at a time (prefilled glasses, fading lines). Conveyor belts shrink the time under the
/// spout from ~4 s to ~1.3 s.
enum LevelCatalog {

    static let levels: [Level] = LevelCatalog.buildLevels()

    static func level(_ id: String) -> Level? {
        return levels.first(where: { (l: Level) -> Bool in l.id == id })
    }

    static func levels(in venue: VenueID) -> [Level] {
        return levels.filter { (l: Level) -> Bool in l.venue == venue }
    }

    static func title(of venue: VenueID) -> String {
        switch venue {
        case .lemonadeStand: return "Lemonade Stand"
        case .sodaFountain: return "Soda Fountain"
        case .milkshakeDiner: return "Milkshake Diner"
        case .conveyor: return "The Conveyor"
        case .potionShop: return "Potion Shop"
        case .sandBar: return "Sand Bar"
        }
    }

    /// Total stars needed to open a venue. The Sand Bar needs every campaign shift 3-starred (40 × 3 = 120).
    static func starsToUnlock(_ venue: VenueID) -> Int {
        switch venue {
        case .lemonadeStand: return 0
        case .sodaFountain: return 8
        case .milkshakeDiner: return 18
        case .conveyor: return 30
        case .potionShop: return 44
        case .sandBar: return 120
        }
    }

    /// Ten seeded orders for a day (the same for everyone). Drinks come from the campaign's own menu.
    /// A fair, varied test: two warm-up basics (still drinks, friendly glasses, mid lines), then never the same glass
    /// or the same drink twice in a row, at most two viscous drinks and three foamy ones, patience tightening from
    /// 14 s to 9 s, and the curveballs (prefills, fading lines) only in the back half.
    static func dailyOrders(day: Int) -> [GlassOrder] {
        var rng: CoreRNG = CoreRNG(seed: UInt64(bitPattern: Int64(day)) &* 0x2545_F491_4F6C_DD1D &+ 0xDA11_7C0F_FEE5_0001)
        let menu: [(String, LiquidID)] = dailyMenu
        let warmUp: [(String, LiquidID)] = menu.filter { (p: (String, LiquidID)) -> Bool in
            let basicGlass: Bool = p.0 == "tumbler" || p.0 == "highball" || p.0 == "jar" || p.0 == "mug"
            let basicDrink: Bool = p.1 == .water || p.1 == .lemonade || p.1 == .orangeJuice
            return basicGlass && basicDrink
        }
        var out: [GlassOrder] = []
        var lastGlass: String = ""
        var lastLiquid: LiquidID? = nil
        var viscous: Int = 0
        var foamy: Int = 0
        var used: Set<LiquidID> = []
        var i: Int = 0
        while i < 10 {
            let pool: [(String, LiquidID)] = (i < 2 && !warmUp.isEmpty) ? warmUp : menu
            // From the 7th order on, insist on a new drink until at least four different ones have been served.
            let needNew: Bool = i >= 6 && used.count < 4
            func acceptable(_ p: (String, LiquidID)) -> Bool {
                let l: Liquid = LiquidCatalog.liquid(p.1)
                if p.0 == lastGlass || p.1 == lastLiquid { return false }
                if l.lagTau >= 0.3 && viscous >= 2 { return false }
                if l.foamPerVolume > 0.3 && foamy >= 3 { return false }
                if needNew && used.contains(p.1) { return false }
                return true
            }
            var pair: (String, LiquidID) = pool[rng.int(pool.count)]
            var tries: Int = 0
            while tries < 12 && !acceptable(pair) {
                pair = pool[rng.int(pool.count)]
                tries += 1
            }
            if !acceptable(pair) {
                // Deterministic fallback: the first acceptable pair after a seeded offset.
                let offset: Int = rng.int(pool.count)
                var k: Int = 0
                while k < pool.count {
                    let candidate: (String, LiquidID) = pool[(offset + k) % pool.count]
                    if acceptable(candidate) {
                        pair = candidate
                        break
                    }
                    k += 1
                }
            }
            lastGlass = pair.0
            lastLiquid = pair.1
            used.insert(pair.1)
            let chosen: Liquid = LiquidCatalog.liquid(pair.1)
            if chosen.lagTau >= 0.3 { viscous += 1 }
            if chosen.foamPerVolume > 0.3 { foamy += 1 }
            let progress: Double = Double(i) / 9.0
            // Round 5 balance pass (design/BALANCE.md): one scored attempt a day should be cleared by most casual
            // players (~70 %). Lines 0.45–0.85 (the extremes were over-pour and spill magnets), foamy drinks capped
            // below their head's comfort zone (root beer 0.68, other heads 0.8), patience 15 → 10 s.
            var line: Double = i < 2 ? rng.range(0.55, 0.75) : rng.range(0.45, 0.85)
            let headCap: Double = chosen.foamPerVolume > 1.0 ? 0.68 : (chosen.foamPerVolume > 0.3 ? 0.8 : 0.95)
            line = (min(line, headCap) * 100).rounded() / 100
            let patience: Double = (CoreMath.lerp(15, 10, progress) * 2).rounded() / 2
            var fade: Double? = nil
            var prefill: Double = 0
            if i >= 6 && rng.chance(0.3) { fade = 1.5 }
            if i >= 4 && line >= 0.6 && rng.chance(0.2) {
                prefill = (rng.range(0.15, 0.3) * 100).rounded() / 100
            }
            out.append(GlassOrder(glass: pair.0, liquid: pair.1, line: line, patience: patience,
                                  lineFadesAfter: fade, prefill: prefill))
            i += 1
        }
        return out
    }

    /// Days since 2026-01-01 00:00 UTC (UTC calendar, so the Daily Pour rolls over at one moment worldwide).
    static func dayNumber(for date: Date) -> Int {
        var cal: Calendar = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        var comps: DateComponents = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 1
        guard let epoch = cal.date(from: comps) else { return 0 }
        let a: Date = cal.startOfDay(for: epoch)
        let b: Date = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }

    // MARK: - Menu for the daily (every glass/drink pair the campaign serves, minus sand), in a stable order.

    static let dailyMenu: [(String, LiquidID)] = {
        var seen: Set<String> = []
        var out: [(String, LiquidID)] = []
        for l in LevelCatalog.levels where l.venue != .sandBar {
            for o in l.orders {
                let key: String = o.glass + "|" + o.liquid.rawValue
                if !seen.contains(key) {
                    seen.insert(key)
                    out.append((o.glass, o.liquid))
                }
            }
        }
        return out
    }()

    // MARK: - Content

    private static func o(_ glass: String, _ liquid: LiquidID, _ line: Double, p: Double? = nil, fade: Double? = nil,
                          pre: Double = 0) -> GlassOrder {
        return GlassOrder(glass: glass, liquid: liquid, line: line, patience: p, lineFadesAfter: fade, prefill: pre)
    }

    private static func venueNumber(_ v: VenueID) -> Int {
        var n: Int = 1
        for c in VenueID.allCases {
            if c == v { return n }
            n += 1
        }
        return n
    }

    private static func lv(_ venue: VenueID, _ index: Int, _ title: String, jug: Double, band: Double,
                           belt: Double? = nil, _ orders: [GlassOrder]) -> Level {
        return Level(id: "\(venueNumber(venue))-\(index)", venue: venue, index: index, title: title, orders: orders,
                     jugFill: jug, conveyorSpeed: belt, perfectBand: band)
    }

    private static func buildLevels() -> [Level] {
        var all: [Level] = []
        all.append(contentsOf: lemonadeStand())
        all.append(contentsOf: sodaFountain())
        all.append(contentsOf: milkshakeDiner())
        all.append(contentsOf: conveyorBelt())
        all.append(contentsOf: potionShop())
        all.append(contentsOf: sandBar())
        return all
    }

    // Venue 1 — basics: water, lemonade, orange juice; tumblers → highballs → a flute. The jug starts emptier
    // as the venue goes on, so you learn to tip further. One micro-twist every other shift (REVIEW-1 P2-9):
    // 1-3 a waiting customer (patience), 1-4 "half full" (low lines in big glasses), 1-6 top-ups (prefilled glasses),
    // 1-7 the first flute, 1-8 last drops (a nearly empty jug: tip far).
    //
    // 1-1 is the first minute of the game: a generous band (±4.5 %), the friendliest glass (wide tumbler, mid lines,
    // still drinks), a full jug that pours at a slight tip, no timers. A first Perfect lands within ~10 s.
    //
    // Round 5 balance pass (design/BALANCE.md): the simulated novice cleared 1-1 only ~75 % of the time. Lines sit at
    // 0.66–0.72 (a longer pour gives a first-timer time to see the level coming; lower lines ended too fast to judge)
    // and the first two glasses are both water (no jug swap before the second pour). Novice clear ≈ 0.9. (The first
    // line stays ≤ 0.66: CoreTests' "over, not spill" check overfills 1-1's first glass by 20 % and needs the headroom.)
    // 1-3 (first patience ring) waits 16 s, 1-4's lowest lines rise a little (0.35/0.38 were over-pour magnets),
    // 1-7's tallest flute lines drop to 0.75–0.8 and 1-8 waits 12 s with a 0.82 top line, so the novice's first wall
    // is venue 2–3, not shift 1-7.
    private static func lemonadeStand() -> [Level] {
        let v: VenueID = .lemonadeStand
        return [
            lv(v, 1, "Grand Opening", jug: 0.9, band: 0.045, [
                o("tumbler", .water, 0.66), o("tumbler", .water, 0.7), o("tumbler", .lemonade, 0.72),
                o("tumbler", .lemonade, 0.68), o("tumbler", .water, 0.72),
            ]),
            lv(v, 2, "Squeeze the Day", jug: 0.9, band: 0.038, [
                o("tumbler", .lemonade, 0.7), o("highball", .lemonade, 0.6), o("tumbler", .lemonade, 0.55),
                o("highball", .lemonade, 0.75), o("tumbler", .lemonade, 0.8), o("highball", .lemonade, 0.65),
            ]),
            lv(v, 3, "Fresh Squeezed", jug: 0.9, band: 0.034, [
                o("tumbler", .orangeJuice, 0.65, p: 16), o("highball", .orangeJuice, 0.7, p: 16),
                o("jar", .orangeJuice, 0.6, p: 16), o("tumbler", .orangeJuice, 0.75, p: 16),
                o("highball", .orangeJuice, 0.6, p: 16), o("jar", .orangeJuice, 0.7, p: 16),
            ]),
            lv(v, 4, "Half Full", jug: 0.85, band: 0.032, [
                o("mug", .water, 0.5, p: 14), o("jar", .lemonade, 0.42, p: 14), o("tumbler", .orangeJuice, 0.7, p: 14),
                o("pint", .water, 0.42, p: 14), o("mug", .lemonade, 0.45, p: 14), o("jar", .orangeJuice, 0.4, p: 14),
                o("tumbler", .lemonade, 0.72, p: 14),
            ]),
            lv(v, 5, "Tall Order", jug: 0.8, band: 0.03, [
                o("highball", .lemonade, 0.85, p: 13), o("pint", .water, 0.8, p: 13),
                o("highball", .orangeJuice, 0.9, p: 13), o("pint", .lemonade, 0.85, p: 13),
                o("highball", .water, 0.8, p: 13), o("pint", .orangeJuice, 0.88, p: 13),
            ]),
            lv(v, 6, "Top It Up", jug: 0.75, band: 0.03, [
                o("tumbler", .lemonade, 0.8, p: 12, pre: 0.45), o("highball", .water, 0.75, p: 12, pre: 0.3),
                o("jar", .orangeJuice, 0.7, p: 12, pre: 0.5), o("tumbler", .water, 0.65, p: 12),
                o("pint", .lemonade, 0.85, p: 12, pre: 0.6), o("mug", .orangeJuice, 0.8, p: 12, pre: 0.35),
                o("highball", .lemonade, 0.7, p: 12, pre: 0.25),
            ]),
            lv(v, 7, "First Flute", jug: 0.7, band: 0.028, [
                o("flute", .lemonade, 0.7, p: 14), o("flute", .water, 0.75, p: 14), o("tumbler", .lemonade, 0.6, p: 14),
                o("flute", .orangeJuice, 0.72, p: 14), o("highball", .lemonade, 0.7, p: 14),
                o("flute", .lemonade, 0.8, p: 14),
            ]),
            lv(v, 8, "Last Drops", jug: 0.5, band: 0.026, [
                o("tumbler", .lemonade, 0.7, p: 12), o("flute", .water, 0.75, p: 12), o("pint", .orangeJuice, 0.72, p: 12),
                o("jar", .lemonade, 0.5, p: 12), o("highball", .water, 0.82, p: 12), o("flute", .orangeJuice, 0.65, p: 12),
                o("mug", .lemonade, 0.6, p: 12, pre: 0.3), o("tumbler", .water, 0.5, p: 12),
            ]),
        ]
    }

    // Venue 2 — foam: cola, root beer, cream soda. "Pour slow, then top up."
    //
    // Round 5 balance pass (design/BALANCE.md): the head is what overflows. A pour at flow f settles toward a head of
    // ≈ foamPerVolume × clamp(f / 0.35, 0.2, 2.5) × f × 10,000 × foamSettle pt². For root beer (1.3, 2 s) at a calm
    // f ≈ 0.3 that is ~6,700 pt² — a third of a mug — so root beer lines stay ≤ ~0.68 (≤ 0.75 in the tall soda glass);
    // the old 0.85–0.9 lines of 2-7 needed f ≲ 0.13 (10 s a glass) and no simulated player cleared it. Cola gets
    // ~16 % headroom at the same flow, so its lines stay ≤ ~0.8. Patience in 2-4/2-6/2-8 gives a slow pour time.
    private static func sodaFountain() -> [Level] {
        let v: VenueID = .sodaFountain
        return [
            lv(v, 1, "Fizz Ed", jug: 1.0, band: 0.035, [
                o("highball", .cola, 0.6), o("tumbler", .cola, 0.55), o("highball", .cola, 0.65),
                o("tumbler", .cola, 0.6), o("highball", .cola, 0.5),
            ]),
            lv(v, 2, "Head Start", jug: 1.0, band: 0.032, [
                o("mug", .rootBeer, 0.55), o("mug", .rootBeer, 0.6), o("pint", .rootBeer, 0.6),
                o("mug", .rootBeer, 0.58), o("pint", .rootBeer, 0.55), o("mug", .rootBeer, 0.62),
            ]),
            lv(v, 3, "Cream of the Crop", jug: 0.9, band: 0.03, [
                o("tumbler", .creamSoda, 0.7, p: 14), o("highball", .creamSoda, 0.75, p: 14),
                o("pint", .creamSoda, 0.65, p: 14), o("flute", .creamSoda, 0.7, p: 14),
                o("tumbler", .creamSoda, 0.8, p: 14), o("highball", .creamSoda, 0.6, p: 14),
            ]),
            lv(v, 4, "Pop Quiz", jug: 0.9, band: 0.03, [
                o("highball", .cola, 0.7, p: 13), o("mug", .rootBeer, 0.6, p: 13), o("pint", .creamSoda, 0.7, p: 13),
                o("tumbler", .cola, 0.72, p: 13), o("pint", .rootBeer, 0.58, p: 13),
                o("highball", .creamSoda, 0.78, p: 13), o("mug", .cola, 0.6, p: 13),
            ]),
            lv(v, 5, "Fizzy Lifting", jug: 0.85, band: 0.028, [
                o("flute", .cola, 0.7, p: 14), o("flute", .creamSoda, 0.75, p: 14), o("flute", .rootBeer, 0.6, p: 14),
                o("flute", .cola, 0.72, p: 14), o("tumbler", .creamSoda, 0.7, p: 14), o("flute", .rootBeer, 0.6, p: 14),
            ]),
            lv(v, 6, "Soda Jerk", jug: 0.8, band: 0.028, [
                o("highball", .cola, 0.72, p: 12, pre: 0.3), o("mug", .rootBeer, 0.62, p: 12, pre: 0.25),
                o("pint", .creamSoda, 0.75, p: 12, pre: 0.35), o("tumbler", .lemonade, 0.7, p: 12, pre: 0.2),
                o("pint", .cola, 0.7, p: 12), o("mug", .rootBeer, 0.66, p: 12, pre: 0.3),
                o("highball", .cola, 0.65, p: 12, pre: 0.2),
            ]),
            // The slow-pour exam: every glass root beer, lines just under the head's comfort zone, time to pour slowly.
            lv(v, 7, "Root of the Problem", jug: 1.0, band: 0.026, [
                o("pint", .rootBeer, 0.72, p: 15), o("mug", .rootBeer, 0.65, p: 15), o("highball", .rootBeer, 0.65, p: 15),
                o("pint", .rootBeer, 0.75, p: 15), o("jar", .rootBeer, 0.62, p: 15), o("mug", .rootBeer, 0.68, p: 15),
            ]),
            lv(v, 8, "Fizz Finale", jug: 0.8, band: 0.025, [
                o("flute", .cola, 0.72, p: 11), o("mug", .rootBeer, 0.62, p: 11), o("pint", .creamSoda, 0.78, p: 11),
                o("highball", .lemonade, 0.6, p: 11), o("tumbler", .cola, 0.78, p: 11), o("jar", .rootBeer, 0.58, p: 11),
                o("flute", .creamSoda, 0.7, p: 11), o("pint", .cola, 0.75, p: 11),
            ]),
        ]
    }

    // Venue 3 — viscosity: shakes, honey, maple syrup. It keeps coming after you stop.
    private static func milkshakeDiner() -> [Level] {
        let v: VenueID = .milkshakeDiner
        return [
            lv(v, 1, "Shake It Easy", jug: 1.0, band: 0.035, [
                o("tumbler", .milkshake, 0.6), o("sundae", .milkshake, 0.6), o("tumbler", .milkshake, 0.7),
                o("sundae", .milkshake, 0.7), o("tumbler", .milkshake, 0.55),
            ]),
            lv(v, 2, "Thick and Thin", jug: 1.0, band: 0.032, [
                o("tumbler", .milkshake, 0.65), o("tumbler", .lemonade, 0.65), o("highball", .milkshake, 0.6),
                o("highball", .water, 0.7), o("sundae", .milkshake, 0.65), o("jar", .lemonade, 0.6),
            ]),
            lv(v, 3, "Sweet as Honey", jug: 1.0, band: 0.03, [
                o("jar", .honey, 0.45, p: 16), o("jar", .honey, 0.55, p: 16), o("shot", .honey, 0.6, p: 16),
                o("jar", .honey, 0.4, p: 16), o("shot", .honey, 0.7, p: 16), o("jar", .honey, 0.5, p: 16),
            ]),
            lv(v, 4, "Short Stack", jug: 0.9, band: 0.03, [
                o("shot", .mapleSyrup, 0.6, p: 15), o("shot", .mapleSyrup, 0.75, p: 15), o("mug", .mapleSyrup, 0.4, p: 15),
                o("shot", .mapleSyrup, 0.5, p: 15), o("jar", .mapleSyrup, 0.4, p: 15), o("shot", .mapleSyrup, 0.8, p: 15),
            ]),
            lv(v, 5, "Sundae Best", jug: 0.9, band: 0.028, [
                o("sundae", .milkshake, 0.7, p: 14), o("sundae", .berrySmoothie, 0.75, p: 14),
                o("bowl", .milkshake, 0.6, p: 14), o("sundae", .berrySmoothie, 0.65, p: 14),
                o("bowl", .berrySmoothie, 0.7, p: 14), o("sundae", .milkshake, 0.85, p: 14),
            ]),
            lv(v, 6, "Smooth Operator", jug: 0.8, band: 0.028, [
                o("highball", .berrySmoothie, 0.7, p: 13), o("bowl", .berrySmoothie, 0.5, p: 13),
                o("tumbler", .berrySmoothie, 0.75, p: 13), o("highball", .berrySmoothie, 0.85, p: 13),
                o("bowl", .berrySmoothie, 0.65, p: 13), o("pint", .berrySmoothie, 0.6, p: 13),
                o("tumbler", .berrySmoothie, 0.6, p: 13),
            ]),
            lv(v, 7, "Sticky Situation", jug: 0.75, band: 0.026, [
                o("jar", .honey, 0.6, p: 15, pre: 0.25), o("shot", .mapleSyrup, 0.7, p: 15, pre: 0.2),
                o("mug", .honey, 0.5, p: 15), o("jar", .mapleSyrup, 0.55, p: 15, pre: 0.3),
                o("shot", .honey, 0.8, p: 15), o("mug", .mapleSyrup, 0.6, p: 15, pre: 0.2),
            ]),
            lv(v, 8, "Blue Plate Special", jug: 0.7, band: 0.025, [
                o("sundae", .milkshake, 0.75, p: 12), o("jar", .honey, 0.5, p: 12), o("highball", .berrySmoothie, 0.7, p: 12),
                o("shot", .mapleSyrup, 0.65, p: 12), o("tumbler", .lemonade, 0.8, p: 12), o("bowl", .milkshake, 0.6, p: 12),
                o("mug", .cola, 0.65, p: 12), o("shot", .honey, 0.75, p: 12),
            ]),
        ]
    }

    // Venue 4 — moving glasses: they slide under the spout and keep going; fill inside the window.
    // Window ≈ 2 × rim half-width / (belt × CoreTuning.beltScale): ~4 s at the start, ~1.4 s at the end.
    private static func conveyorBelt() -> [Level] {
        let v: VenueID = .conveyor
        return [
            lv(v, 1, "Belt It Out", jug: 1.0, band: 0.035, belt: 16, [
                o("tumbler", .water, 0.55), o("tumbler", .lemonade, 0.6), o("tumbler", .water, 0.5),
                o("mug", .lemonade, 0.45), o("tumbler", .water, 0.6),
            ]),
            lv(v, 2, "Moving Day", jug: 1.0, band: 0.032, belt: 18, [
                o("mug", .lemonade, 0.5), o("tumbler", .lemonade, 0.55), o("bowl", .orangeJuice, 0.5),
                o("tumbler", .lemonade, 0.6), o("mug", .orangeJuice, 0.55), o("bowl", .lemonade, 0.45),
            ]),
            lv(v, 3, "Keep It Rolling", jug: 1.0, band: 0.03, belt: 21, [
                o("tumbler", .orangeJuice, 0.55), o("mug", .cola, 0.45), o("bowl", .orangeJuice, 0.55),
                o("tumbler", .cola, 0.5), o("shot", .orangeJuice, 0.6), o("mug", .cola, 0.5),
            ]),
            lv(v, 4, "Fizz on the Move", jug: 1.0, band: 0.03, belt: 22, [
                o("mug", .cola, 0.45), o("bowl", .creamSoda, 0.5), o("mug", .rootBeer, 0.4),
                o("tumbler", .cola, 0.5), o("shot", .creamSoda, 0.55), o("bowl", .rootBeer, 0.45),
            ]),
            // Round 5 balance pass: 4-5 was the hardest belt of the venue for simulated casual players (shorts), harder
            // than 4-6/4-7; belt 26 → 23 and its last tiny cup 0.7 → 0.6. 4-7 30 → 27, 4-8 36 → 33 keep the finale the
            // peak without making it a wall.
            lv(v, 5, "Assembly Line", jug: 1.0, band: 0.028, belt: 23, [
                o("bowl", .water, 0.6), o("shot", .lemonade, 0.6), o("mug", .orangeJuice, 0.5),
                o("tumbler", .water, 0.55), o("sundae", .lemonade, 0.5), o("shot", .orangeJuice, 0.6),
                o("mug", .water, 0.55),
            ]),
            lv(v, 6, "Slow Pour, Fast Belt", jug: 1.0, band: 0.028, belt: 20, [
                o("mug", .milkshake, 0.45), o("bowl", .honey, 0.4), o("sundae", .milkshake, 0.5),
                o("shot", .mapleSyrup, 0.5), o("mug", .berrySmoothie, 0.45), o("shot", .honey, 0.45),
            ]),
            lv(v, 7, "Rush Hour", jug: 1.0, band: 0.026, belt: 27, [
                o("bowl", .cola, 0.5), o("mug", .lemonade, 0.45), o("shot", .orangeJuice, 0.55),
                o("sundae", .water, 0.55), o("mug", .rootBeer, 0.4), o("bowl", .lemonade, 0.6),
                o("shot", .water, 0.65),
            ]),
            lv(v, 8, "Full Speed Ahead", jug: 1.0, band: 0.025, belt: 33, [
                o("bowl", .water, 0.55), o("sundae", .lemonade, 0.55), o("mug", .orangeJuice, 0.45),
                o("bowl", .cola, 0.5), o("shot", .water, 0.5), o("mug", .lemonade, 0.5),
                o("bowl", .creamSoda, 0.45), o("sundae", .orangeJuice, 0.6),
            ]),
        ]
    }

    // Venue 5 — precision: tiny vials, beakers, lines that fade.
    private static func potionShop() -> [Level] {
        let v: VenueID = .potionShop
        return [
            lv(v, 1, "Apprentice Hours", jug: 1.0, band: 0.025, [
                o("beaker", .potionBlue, 0.5), o("beaker", .potionBlue, 0.6), o("vial", .potionBlue, 0.7),
                o("beaker", .potionBlue, 0.45), o("vial", .potionBlue, 0.6),
            ]),
            lv(v, 2, "Love Potion No. 9", jug: 1.0, band: 0.024, [
                o("vial", .potionPink, 0.65), o("beaker", .potionPink, 0.55), o("vial", .potionPink, 0.8),
                o("shot", .potionPink, 0.6), o("beaker", .potionPink, 0.7), o("vial", .potionPink, 0.5),
            ]),
            lv(v, 3, "Now You See It", jug: 0.9, band: 0.024, [
                o("beaker", .potionBlue, 0.6, p: 14, fade: 1.5), o("vial", .potionPink, 0.7, p: 14, fade: 1.5),
                o("flute", .potionBlue, 0.65, p: 14, fade: 1.5), o("beaker", .potionPink, 0.5, p: 14, fade: 1.5),
                o("vial", .potionBlue, 0.75, p: 14, fade: 1.5), o("flute", .potionPink, 0.7, p: 14, fade: 1.5),
            ]),
            lv(v, 4, "Double Trouble", jug: 0.9, band: 0.022, [
                o("shot", .potionBlue, 0.5, p: 13), o("shot", .potionPink, 0.7, p: 13), o("vial", .potionBlue, 0.6, p: 13),
                o("shot", .potionPink, 0.55, p: 13), o("beaker", .potionBlue, 0.8, p: 13), o("vial", .potionPink, 0.45, p: 13),
            ]),
            lv(v, 5, "Small Doses", jug: 0.8, band: 0.022, [
                o("vial", .potionBlue, 0.35, p: 13), o("shot", .potionPink, 0.4, p: 13), o("beaker", .potionBlue, 0.32, p: 13),
                o("vial", .potionPink, 0.4, p: 13), o("shot", .potionBlue, 0.35, p: 13), o("beaker", .potionPink, 0.38, p: 13),
                o("vial", .potionBlue, 0.45, p: 13),
            ]),
            lv(v, 6, "Vanishing Act", jug: 0.8, band: 0.02, [
                o("flute", .potionPink, 0.75, p: 13, fade: 1.0), o("beaker", .potionBlue, 0.55, p: 13, fade: 1.0),
                o("vial", .potionPink, 0.65, p: 13, fade: 1.0), o("flute", .potionBlue, 0.8, p: 13, fade: 1.0),
                o("shot", .potionPink, 0.6, p: 13, fade: 1.0), o("beaker", .potionBlue, 0.7, p: 13, fade: 1.0),
            ]),
            lv(v, 7, "Bubble Trouble", jug: 0.75, band: 0.02, [
                o("beaker", .potionBlue, 0.7, p: 11, pre: 0.3), o("vial", .potionPink, 0.75, p: 11, pre: 0.25),
                o("flute", .potionBlue, 0.8, p: 11, pre: 0.35), o("beaker", .potionPink, 0.6, p: 11),
                o("shot", .potionBlue, 0.7, p: 11, pre: 0.3), o("flute", .potionPink, 0.65, p: 11, pre: 0.2),
                o("vial", .potionBlue, 0.85, p: 11, pre: 0.4),
            ]),
            lv(v, 8, "Grand Elixir", jug: 0.7, band: 0.018, [
                o("vial", .potionBlue, 0.7, p: 11, fade: 1.0), o("beaker", .potionPink, 0.65, p: 11, fade: 1.0),
                o("flute", .potionBlue, 0.75, p: 11, fade: 1.0), o("shot", .potionPink, 0.55, p: 11, fade: 1.0),
                o("beaker", .potionBlue, 0.85, p: 11, fade: 1.0, pre: 0.3), o("vial", .potionPink, 0.6, p: 11, fade: 1.0),
                o("shot", .potionBlue, 0.7, p: 11, fade: 1.0), o("flute", .potionPink, 0.8, p: 11, fade: 1.0),
            ]),
        ]
    }

    // Secret — sand: nothing moves until ~30° of extra tip, then it avalanches.
    private static func sandBar() -> [Level] {
        let v: VenueID = .sandBar
        return [
            lv(v, 1, "Hourglass Figure", jug: 1.0, band: 0.03, [
                o("jar", .sand, 0.5), o("beaker", .sand, 0.6), o("jar", .sand, 0.65), o("vial", .sand, 0.7),
                o("beaker", .sand, 0.5),
            ]),
            lv(v, 2, "Grain Check", jug: 0.9, band: 0.028, [
                o("shot", .sand, 0.6), o("jar", .sand, 0.55), o("bowl", .sand, 0.5), o("vial", .sand, 0.6),
                o("beaker", .sand, 0.7), o("shot", .sand, 0.75),
            ]),
            lv(v, 3, "Shifting Sands", jug: 0.8, band: 0.025, [
                o("tumbler", .sand, 0.7, p: 14), o("flute", .sand, 0.65, p: 14), o("jar", .sand, 0.6, p: 14, pre: 0.2),
                o("bowl", .sand, 0.6, p: 14), o("vial", .sand, 0.8, p: 14), o("beaker", .sand, 0.55, p: 14),
            ]),
            lv(v, 4, "Sands of Time", jug: 0.7, band: 0.022, [
                o("beaker", .sand, 0.7, p: 12), o("vial", .sand, 0.65, p: 12), o("flute", .sand, 0.8, p: 12),
                o("jar", .sand, 0.5, p: 12), o("shot", .sand, 0.6, p: 12), o("bowl", .sand, 0.65, p: 12),
                o("tumbler", .sand, 0.75, p: 12, pre: 0.25), o("beaker", .sand, 0.85, p: 12),
            ]),
        ]
    }
}
