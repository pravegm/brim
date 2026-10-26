import Foundation

/// The Daily Pour share line (GAME-DESIGN §6.3), e.g. `Brim Daily #12 ⭐️🟩🟩🟨🟥 1,840`. Pure; tested.
enum ShareText {
    static func emoji(for judgement: Judgement) -> String {
        switch judgement {
        case .perfect: return "⭐️"
        case .great: return "🟩"
        case .good: return "🟨"
        case .short: return "🟧"
        // Round 5: over the Good band without spilling. Purple, so it never reads as Good (🟨) or Short (🟧).
        case .over: return "🟪"
        case .spill: return "🟥"
        }
    }

    /// `streak` = consecutive Daily Pours ending that day; shown as " 🔥4" from 2 days (REVIEW-5 P1-7).
    static func daily(day: Int, judgements: [Judgement], score: Int, streak: Int = 0) -> String {
        let parts = dailyParts(day: day, judgements: judgements, score: score, streak: streak)
        return "\(parts.title) \(parts.grid)"
    }

    /// Round 9 (REVIEW-7 P2-6): the share line in two pieces for the results card's preview, so the ten squares sit on
    /// their own line and never break 9 + 1: `title` "Brim Daily #12", `grid` "⭐️🟩🟩🟨🟥 1,840 🔥4". `daily(…)` is
    /// exactly `title + " " + grid`, so the preview shows what Share posts. Pure; tested.
    static func dailyParts(day: Int, judgements: [Judgement], score: Int,
                           streak: Int = 0) -> (title: String, grid: String) {
        let squares = judgements.map(emoji(for:)).joined()
        let fire = streak >= 2 ? " 🔥\(streak)" : ""
        return ("Brim Daily #\(day)", "\(squares) \(grouped(score))\(fire)")
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
