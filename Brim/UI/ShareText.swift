import Foundation

/// The Daily Pour share line (GAME-DESIGN §6.3), e.g. `Brim Daily #12 ⭐️🟩🟩🟨🟥 1,840`. Pure; tested.
enum ShareText {
    static func emoji(for judgement: Judgement) -> String {
        switch judgement {
        case .perfect: return "⭐️"
        case .great: return "🟩"
        case .good: return "🟨"
        case .short: return "🟧"
        case .spill: return "🟥"
        }
    }

    static func daily(day: Int, judgements: [Judgement], score: Int) -> String {
        let grid = judgements.map(emoji(for:)).joined()
        return "Brim Daily #\(day) \(grid) \(grouped(score))"
    }

    /// Thousands with commas whatever the locale, so the shared line reads the same everywhere: 1840 → "1,840".
    static func grouped(_ value: Int) -> String {
        let digits = String(value.magnitude)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return value < 0 ? "-" + out : out
    }
}
