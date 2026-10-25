import CoreGraphics
import Foundation
import Testing
@testable import Brim

struct LevelTests {

    @Test func fortyFourLevelsWithUniqueIDs() {
        let levels: [Level] = LevelCatalog.levels
        #expect(levels.count == 44)
        let ids: [String] = levels.map { (l: Level) -> String in l.id }
        #expect(Set(ids).count == ids.count)
        for v in VenueID.allCases {
            let n: Int = LevelCatalog.levels(in: v).count
            #expect(n == (v == .sandBar ? 4 : 8), "\(v.rawValue) has \(n)")
            #expect(!LevelCatalog.title(of: v).isEmpty)
        }
        let firstTitle: String? = LevelCatalog.level("1-1")?.title
        #expect(firstTitle == String("Grand Opening"))
        #expect(LevelCatalog.level("6-4") != nil)
        #expect(LevelCatalog.level("9-9") == nil)
    }

    @Test func everyOrderIsPlayable() {
        let glassIDs: Set<String> = Set(GlassCatalog.all.map { (g: GlassShape) -> String in g.id })
        for l in LevelCatalog.levels {
            #expect(l.orders.count >= 5 && l.orders.count <= 8, "\(l.id) has \(l.orders.count) orders")
            #expect(!l.title.isEmpty)
            #expect(l.jugFill > 0.4 && l.jugFill <= 1.0)
            #expect(l.perfectBand >= 0.015 && l.perfectBand <= 0.05)
            for o in l.orders {
                #expect(glassIDs.contains(o.glass), "\(l.id) uses unknown glass \(o.glass)")
                #expect(o.line >= 0.3 && o.line <= 0.95, "\(l.id) line \(o.line)")
                #expect(o.prefill >= 0 && o.prefill < o.line - 0.1)
                if let p = o.patience { #expect(p >= 5) }
            }
            if l.venue == .conveyor {
                #expect(l.conveyorSpeed != nil)
            } else {
                #expect(l.conveyorSpeed == nil)
            }
            if l.venue == .sandBar {
                for o in l.orders { #expect(o.liquid == LiquidID.sand) }
            } else {
                for o in l.orders { #expect(o.liquid != LiquidID.sand) }
            }
        }
    }

    @Test func firstShiftIsGenerousAndEasy() {
        let first: Level? = LevelCatalog.level("1-1")
        guard let l = first else {
            Issue.record("missing 1-1")
            return
        }
        // The widest band in the game, the friendliest glass, still drinks, no timers, mid lines.
        for other in LevelCatalog.levels where other.id != "1-1" {
            #expect(l.perfectBand > other.perfectBand, "\(other.id) band \(other.perfectBand)")
        }
        #expect(l.perfectBand >= 0.04)
        #expect(l.orders.count == 5)
        for o in l.orders {
            #expect(o.glass == "tumbler")
            #expect(o.liquid == LiquidID.water || o.liquid == LiquidID.lemonade)
            #expect(o.patience == nil && o.lineFadesAfter == nil && o.prefill == 0)
            #expect(o.line >= 0.55 && o.line <= 0.75)
        }
    }

    @Test func venueOneHasMicroTwists() {
        let venue: [Level] = LevelCatalog.levels(in: .lemonadeStand)
        #expect(venue.count == 8)
        // 1-4 "Half Full": low lines in big glasses.
        let halfFull: Level? = LevelCatalog.level("1-4")
        if let l = halfFull {
            let low: [GlassOrder] = l.orders.filter { (o: GlassOrder) -> Bool in o.line <= 0.5 }
            #expect(low.count >= 4)
            for o in low {
                let g: GlassShape = GlassCatalog.shape(o.glass)
                #expect(GlassMath.capacity(g) >= 16000, "\(o.glass) is not a big glass")
            }
        }
        // 1-6 top-ups (prefilled glasses) and 1-8 last drops (a low jug).
        let topUps: Int = LevelCatalog.level("1-6")?.orders.filter { (o: GlassOrder) -> Bool in o.prefill > 0 }.count ?? 0
        #expect(topUps >= 4)
        let lastJug: Double = LevelCatalog.level("1-8")?.jugFill ?? 1
        #expect(lastJug <= 0.6)
        // Patience is introduced in 1-3, not before.
        for l in venue where l.index <= 2 {
            for o in l.orders { #expect(o.patience == nil) }
        }
    }

    @Test func dailyIsAFairVariedTest() {
        for day in [0, 1, 2, 57, 120, 297, 300, 1000] {
            let orders: [GlassOrder] = LevelCatalog.dailyOrders(day: day)
            #expect(orders.count == 10)
            // Warm-up: two basic still drinks in friendly glasses with mid lines.
            for o in orders.prefix(2) {
                #expect(o.liquid == LiquidID.water || o.liquid == LiquidID.lemonade || o.liquid == LiquidID.orangeJuice)
                #expect(["tumbler", "highball", "jar", "mug"].contains(o.glass), "warm-up glass \(o.glass)")
                #expect(o.line >= 0.55 && o.line <= 0.75)
                #expect(o.prefill == 0 && o.lineFadesAfter == nil)
            }
            var viscous: Int = 0
            var liquids: Set<LiquidID> = []
            var i: Int = 0
            while i < orders.count {
                let o: GlassOrder = orders[i]
                liquids.insert(o.liquid)
                if LiquidCatalog.liquid(o.liquid).lagTau >= 0.3 { viscous += 1 }
                if i > 0 {
                    #expect(o.glass != orders[i - 1].glass, "day \(day): same glass twice at \(i)")
                    #expect(o.liquid != orders[i - 1].liquid, "day \(day): same drink twice at \(i)")
                }
                i += 1
            }
            #expect(viscous <= 2, "day \(day): \(viscous) viscous drinks")
            #expect(liquids.count >= 4, "day \(day): only \(liquids.count) drinks")
        }
    }

    @Test func levelIDsFollowVenueAndIndex() {
        var venueNumber: Int = 1
        for v in VenueID.allCases {
            let levels: [Level] = LevelCatalog.levels(in: v)
            var i: Int = 1
            for l in levels {
                #expect(l.id == "\(venueNumber)-\(i)")
                #expect(l.index == i)
                i += 1
            }
            venueNumber += 1
        }
    }

    @Test func unlockThresholds() {
        #expect(LevelCatalog.starsToUnlock(.lemonadeStand) == 0)
        #expect(LevelCatalog.starsToUnlock(.sodaFountain) == 8)
        #expect(LevelCatalog.starsToUnlock(.milkshakeDiner) == 18)
        #expect(LevelCatalog.starsToUnlock(.conveyor) == 30)
        #expect(LevelCatalog.starsToUnlock(.potionShop) == 44)
        #expect(LevelCatalog.starsToUnlock(.sandBar) == 120)
    }

    @Test func dailyOrdersAreDeterministicAndValid() {
        let glassIDs: Set<String> = Set(GlassCatalog.all.map { (g: GlassShape) -> String in g.id })
        for day in [0, 1, 57, 300, 1000] {
            let a: [GlassOrder] = LevelCatalog.dailyOrders(day: day)
            let b: [GlassOrder] = LevelCatalog.dailyOrders(day: day)
            #expect(a == b)
            #expect(a.count == 10)
            for o in a {
                #expect(glassIDs.contains(o.glass))
                #expect(o.line >= 0.3 && o.line <= 0.95)
                #expect(o.liquid != LiquidID.sand)
                #expect(o.prefill < o.line)
            }
        }
        #expect(LevelCatalog.dailyOrders(day: 10) != LevelCatalog.dailyOrders(day: 11))
    }

    @Test func dayNumberCountsUTCDaysFrom2026() {
        var cal: Calendar = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        var c: DateComponents = DateComponents()
        c.year = 2026
        c.month = 1
        c.day = 1
        c.hour = 12
        let jan1: Date? = cal.date(from: c)
        c.month = 2
        c.day = 1
        c.hour = 0
        c.minute = 30
        let feb1: Date? = cal.date(from: c)
        if let d = jan1 { #expect(LevelCatalog.dayNumber(for: d) == 0) }
        if let d = feb1 { #expect(LevelCatalog.dayNumber(for: d) == 31) }
    }
}
