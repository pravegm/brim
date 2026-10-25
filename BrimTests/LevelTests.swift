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
            #expect(l.perfectBand >= 0.015 && l.perfectBand <= 0.04)
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
