import SwiftUI
import UIKit

// MARK: - Demo mode (CI screenshots, design review). DEBUG builds only.
//
// Launch argument: `-brimDemo "key=value;key;key=value"` (ci/scenarios.txt, ci/duo.sh). Values can't contain `;`.
// Unknown keys are ignored. Every line CI greps starts with `BRIM-` (CLAUDE.md: never rename them).
//
// Keys
// - `screen=menu|venues|results|settings|game|standup|cover|icon|badges`
//     menu      home screen over the attract loop (practice + perfect autopilot behind it). Round 4 (REVIEW-3 P1-2):
//               the attract loop is held ONCE, mid-pour, the first time the jug is really flowing (flow > 0.05) and
//               the glass is ≥ 55 % of its line — so the menu capture shows a real stream, never the drops of a tail.
//               Logs `BRIM-T freeze midpour …`; add `freezeOn=midpour` to the args to make CI wait for that line.
//     venues    venue / shift select.
//     results   the results card for `mode`: a REAL run of it, played headless at launch by the autopilot
//               (`autopilot=` style; default perfect for shifts, great for rush/daily) and recorded into the demo
//               progress, so score, stars, recap and NEW BEST are all true (REVIEW-1 P1-8). Logs `BRIM-T demo run`.
//               The mode's scene runs idle behind it.
//     settings  the settings screen.
//     game      play `mode` (the default when `mode` is given without `screen`).
//     standup   force the book-pose card ("Turn me so the fold runs side to side, then lay me flat").
//     cover     force the cover-display card ("Open me to pour").
//     icon      render AppIconArt with ImageRenderer to Documents/AppIcon-1024.png (logs `BRIM-T icon ok|failed`)
//               and show it full width on black.
//     badges    render every Game Center achievement badge (UI/AchievementArt.swift, GameCenterManager.achievementIDs)
//               with ImageRenderer, 1024 × 1024 px opaque, to Documents/badges/<id>.png (logs `BRIM-T badges done <n>`).
//               Not a Screen case (only sets `badges`), so the app itself opens on the menu.
// - `mode=shift:<id>|rush|daily|practice`   e.g. `mode=shift:1-2`. `daily` = today's Daily Pour.
// - `autopilot=perfect|great|short|spill`   AutopilotTiltSource plays the run.
// - `freezeOn=midpour|perfect|spill|finished`
//     Stops calling GameSession.step (the scene's cosmetics run on the session clock, so the frame holds) and logs
//     `BRIM-T freeze <reason> t=… served=… score=… streak=…`:
//     midpour   the stream is non-empty and the active glass's visible top is ≥ 55 % of its line.
//     perfect   0.15 s (session time) after the first live Perfect is served (the big burst on screen).
//     spill     0.3 s after the liquid first goes over the rim (`overflowStarted`, or a Spill verdict).
//     finished  when the run finishes; the results card shows at once.
// - `streak=N`     the run is really PLAYED up to an N-Perfect streak (perfect autopilot, headless, at launch) before
//                  the live frames, leaving at least one order; score, served count and streak agree. Logs
//                  `BRIM-T streak seeded <n> (asked N) score=… served=…`.
// - `progress=fresh|mid|full`   in-memory progress (demo runs never write UserDefaults). Default fresh.
// - `hints=fresh|off`           onboarding hints shown from scratch, or never. Default in demo: off.
// - `orient=portrait`   asks the window scene for portrait (requestGeometryUpdate), re-asking every 2 s, and logs
//                       `BRIM-T orient portrait ok` once the interface, the window and the screen are all portrait and
//                       the window fills the screen (never a letterboxed column) (`… failed` after 30 s, `… lost` if it
//                       rotates back later). Without it a Duo follows the way it is held (App/OrientationLock.swift).
// - `duo`        treat the canvas as a Duo (crease band) from the first frame and use the real hinge tilt source
//                (HingeTiltSource) even in demo. Without `autopilot`/`duo` a demo game uses TouchTiltSource.
// - `seed=N`     GameSession seed (default: day number for daily, 7 otherwise, so CI frames are stable).
//
// Log lines
// - `BRIM-T demo '<args>' starts` at launch (stdout is line-buffered in demo runs).
// - `BRIM-T frame 120` after the 120th scene frame (ci/duo.sh waits on it).
// - `BRIM-T freeze <reason> t=<session s>`, `BRIM-T orient portrait ok|failed|lost`, `BRIM-T icon ok|failed`,
//   `BRIM-T badges done <n>` (`BRIM-T badges failed <id>: …` per failure),
//   `BRIM-T screen <route>` when the app's screen changes, `BRIM-T flat armed t=` when the Duo flat gate opens.
// - `BRIM-T canvas <w>x<h> hasFold=<bool> pose=play|book|cover` whenever the canvas, fold or pose changes (every DEBUG
//   build, demo or not).
// - Round 3, closing never pours (every DEBUG build, flushed; GameController):
//   `BRIM-T autopause angle=<a>`   a live run paused itself: raw hinge < 70° (or the Duo shut / went to the cover).
//                                  Real runs, and demo runs with `duo` and no `autopilot`.
//   `BRIM-T resume needsFlat=<0|1>` a live run resumed (any path: reopening, the pause card, the app or the pose
//                                  coming back); the flat gate re-armed (1 on a fold outside practice).
//   `BRIM-T served id=<glassID> judgement=<perfect|great|good|short|spill>`   every live serve. ci/duo.sh fails if
//                                  one falls between `autopause` and the next `resume needsFlat=1`.
//   `-brimDemo "mode=shift:1-2;duo;orient=portrait"` plays on the real hinge exactly like a real run (pause, card,
//   resume, flat gate); only the book-pose hold differs (demo runs hold instead of showing the pause card).
// - Round 4 (every DEBUG build, GameController):
//   `BRIM-T canvas swap kept run t=<session s>`   the canvas changed mid-run (book-pose "Use touch", back to
//                                  tabletop): the scene was swapped and the run kept (QA-1 P1-3).
//   `BRIM-T daily left day=<n> score=<s> glasses=<g>`   today's scored Daily was left unfinished; the pour so far was
//                                  filed as the day's score (QA-1 P1-2).
// - Demo runs keep the scene rendering on every screen (the real app pauses it under Venues, Settings, results and the
//   pose cards), so `BRIM-T frame 120` always arrives.

enum DemoAutopilot: String, Equatable { case perfect, great, short, over, spill }

struct DemoConfig: Equatable {
    enum Screen: String, Equatable { case menu, venues, results, settings, game, standup, cover, icon }
    enum Freeze: String, Equatable { case midpour, perfect, spill, finished }
    enum ProgressPreset: String, Equatable { case fresh, mid, full }
    enum HintsPreset: String, Equatable { case fresh, off }

    var raw: String
    var screen: Screen?
    var mode: GameMode?
    var autopilot: DemoAutopilot?
    var freezeOn: Freeze?
    var streak: Int?
    var progress: ProgressPreset?
    var hints: HintsPreset?
    var orientPortrait = false
    var duo = false
    var seed: UInt64?
    var badges = false

    /// The screen the app opens on.
    var effectiveScreen: Screen {
        if let screen { return screen }
        return mode == nil ? .menu : .game
    }

    /// Parses `key=value;key` (pure; tested). `today` resolves `mode=daily`.
    static func parse(_ raw: String, today: Int) -> DemoConfig {
        var config = DemoConfig(raw: raw)
        for part in raw.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let key = pieces.first, !key.isEmpty else { continue }
            let value = pieces.count > 1 ? pieces[1] : ""
            switch key {
            case "screen":
                config.screen = Screen(rawValue: value)
                config.badges = value == "badges"
            case "mode": config.mode = parseMode(value, today: today)
            case "autopilot": config.autopilot = DemoAutopilot(rawValue: value)
            case "freezeOn": config.freezeOn = Freeze(rawValue: value)
            case "streak": config.streak = Int(value)
            case "progress": config.progress = ProgressPreset(rawValue: value)
            case "hints": config.hints = HintsPreset(rawValue: value)
            case "orient": config.orientPortrait = value == "portrait"
            case "duo": config.duo = value.isEmpty || value == "on" || value == "1" || value == "true"
            case "seed": config.seed = UInt64(value)
            default: break
            }
        }
        return config
    }

    static func parseMode(_ value: String, today: Int) -> GameMode? {
        if value == "rush" { return .rush }
        if value == "practice" { return .practice }
        if value == "daily" { return .daily(today) }
        if value.hasPrefix("daily:"), let day = Int(value.dropFirst(6)) { return .daily(day) }
        if value.hasPrefix("shift:") {
            let id = String(value.dropFirst(6))
            return id.isEmpty ? nil : .shift(id)
        }
        return nil
    }

    /// The scenario for this launch: DEBUG builds with `-brimDemo` only; nil otherwise.
    static let current: DemoConfig? = {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "brimDemo") else { return nil }
        // CI redirects stdout to a file (fully buffered); line-buffer it so the scripts see BRIM- lines on time.
        setvbuf(stdout, nil, _IOLBF, 0)
        let config = DemoConfig.parse(raw, today: LevelCatalog.dayNumber(for: Date()))
        if config.badges {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                BadgeExport.renderAll()
            }
        }
        return config
        #else
        return nil
        #endif
    }()

    // MARK: Seeded state

    /// In-memory progress for `progress=`.
    static func progressData(_ preset: ProgressPreset?) -> ProgressData {
        var data = ProgressData()
        switch preset ?? .fresh {
        case .fresh:
            return data
        case .mid:
            let pattern = [3, 3, 2, 3, 1, 3, 2, 3]
            for (i, level) in LevelCatalog.levels(in: .lemonadeStand).enumerated() {
                data.stars[level.id] = pattern[i % pattern.count]
                data.bestScores[level.id] = 900 + 140 * i
            }
            for (i, level) in LevelCatalog.levels(in: .sodaFountain).prefix(3).enumerated() {
                data.stars[level.id] = [3, 2, 2][i]
                data.bestScores[level.id] = 1100 + 120 * i
            }
            data.rushBest = 2140
            let today = LevelCatalog.dayNumber(for: Date())
            data.daily[today - 1] = DailyRecord(score: 1840, judgements: [.perfect, .great, .great, .good, .spill,
                                                                           .perfect, .great, .perfect, .good, .great],
                                                perfects: 3)
            data.stats = LifetimeStats(poured: 498_000, perfects: 37, bestStreak: 11, glasses: 142, runs: 21)
        case .full:
            for level in LevelCatalog.levels where level.venue != .sandBar {
                data.stars[level.id] = 3
                data.bestScores[level.id] = 1600
            }
            data.rushBest = 5320
            data.stats = LifetimeStats(poured: 2_150_000, perfects: 412, bestStreak: 27, glasses: 980, runs: 160)
        }
        return data
    }
}

// MARK: - Orientation (Duo simulator starts in book pose; CI asks for the tabletop canvas)

@MainActor
enum DemoOrientation {
    private static var started = false

    static func requestPortrait() {
        guard !started else { return }
        started = true
        Task { @MainActor in
            let start = Date()
            var reported = false
            var failedLogged = false
            var lostLogged = false
            var lastRequest = Date.distantPast
            var matchedSince: Date?
            while Date().timeIntervalSince(start) < 600 {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                    continue
                }
                let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
                let w = window?.bounds.size ?? .zero
                let s = scene.screen.bounds.size
                // Run 40203342285 logged "ok" for a 469 × 669 letterboxed column: the window must fill the screen.
                let portrait = scene.effectiveGeometry.interfaceOrientation.isPortrait
                    && w.height > w.width && s.height > s.width
                    && w.width >= s.width - 2 && w.height >= s.height - 2
                let shape = "window=\(Int(w.width))x\(Int(w.height)) screen=\(Int(s.width))x\(Int(s.height))"
                if portrait {
                    let since = matchedSince ?? Date()
                    matchedSince = since
                    if !reported && Date().timeIntervalSince(since) >= 0.8 {
                        reported = true
                        lostLogged = false
                        print("BRIM-T orient portrait ok \(shape)")
                    }
                } else {
                    matchedSince = nil
                    if reported && !lostLogged {
                        lostLogged = true
                        reported = false
                        print("BRIM-T orient portrait lost \(shape); re-requesting")
                    }
                    if Date().timeIntervalSince(lastRequest) >= 2 {
                        lastRequest = Date()
                        window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                            print("BRIM-T orient request error: \(error.localizedDescription)")
                        }
                    }
                    if !failedLogged && Date().timeIntervalSince(start) > 30 {
                        failedLogged = true
                        print("BRIM-T orient portrait failed after 30s \(shape)")
                    }
                }
            }
        }
    }
}

// MARK: - App icon render (`screen=icon`)

@MainActor
enum IconExport {
    static let side: CGFloat = 1024

    /// Renders AppIconArt at 1024 × 1024 px, opaque, to Documents/AppIcon-1024.png.
    static func render() {
        let renderer = ImageRenderer(content: AppIconArt().frame(width: side, height: side))
        renderer.proposedSize = ProposedViewSize(width: side, height: side)
        renderer.scale = 1
        renderer.isOpaque = true
        guard let cgImage = renderer.cgImage else {
            print("BRIM-T icon failed: renderer returned no image")
            return
        }
        // Redraw into an opaque 1× context so the PNG carries no alpha channel (App Store requirement).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let data = image.pngData(),
              let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("BRIM-T icon failed: no PNG data")
            return
        }
        do {
            try data.write(to: directory.appendingPathComponent("AppIcon-1024.png"))
            print("BRIM-T icon ok \(cgImage.width)x\(cgImage.height)")
        } catch {
            print("BRIM-T icon failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Achievement badges render (`screen=badges`)

@MainActor
enum BadgeExport {
    static let side: CGFloat = 1024

    /// Renders every AchievementBadge at 1024 × 1024 px, opaque, to Documents/badges/<id>.png.
    static func renderAll() {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("BRIM-T badges done 0 (no Documents directory)")
            return
        }
        let directory = documents.appendingPathComponent("badges", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written = 0
        for id in GameCenterManager.achievementIDs {
            let renderer = ImageRenderer(content: AchievementBadge(id: id).frame(width: side, height: side))
            renderer.proposedSize = ProposedViewSize(width: side, height: side)
            renderer.scale = 1
            renderer.isOpaque = true
            guard let cgImage = renderer.cgImage else {
                print("BRIM-T badges failed \(id): renderer returned no image")
                continue
            }
            // Redraw into an opaque 1× context so the PNG carries no alpha channel (App Store requirement).
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
                UIImage(cgImage: cgImage).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            }
            guard let data = image.pngData() else {
                print("BRIM-T badges failed \(id): no PNG data")
                continue
            }
            do {
                try data.write(to: directory.appendingPathComponent("\(id).png"))
                written += 1
            } catch {
                print("BRIM-T badges failed \(id): \(error.localizedDescription)")
            }
        }
        print("BRIM-T badges done \(written)")
    }
}
