import SwiftUI
import UIKit

// MARK: - Demo mode (CI screenshots, design review). DEBUG builds only.
//
// Launch argument: `-brimDemo "key=value;key;key=value"` (ci/scenarios.txt, ci/duo.sh). Values can't contain `;`.
// Unknown keys are ignored. Every line CI greps starts with `BRIM-` (CLAUDE.md: never rename them).
//
// Keys
// - `screen=menu|venues|results|settings|game|standup|cover|icon|badges|cabinet`
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
//     cabinet   round 9 (REVIEW-7 P1-2, frames 34/35 and duo-ui-cabinet): Home over the attract loop with the Glass
//               Cabinet sheet open (HomeView opens it on appear). Like `menu`, the loop is held once mid-pour (add
//               `freezeOn=midpour` to make CI wait for it). Logs `BRIM-T cabinet open crowns=<n> vessel=<v|house>
//               sandBar=<0|1>`.
// - `mode=shift:<id>|rush|daily|practice`   e.g. `mode=shift:1-2`. `daily` = today's Daily Pour.
// - `autopilot=perfect|great|short|spill`   AutopilotTiltSource plays the run.
// - `freezeOn=midpour|perfect|spill|finished|intro|tier|repose|faded|lowjug`
//     Stops calling GameSession.step (the scene's cosmetics run on the session clock, so the frame holds) and logs
//     `BRIM-T freeze <reason> t=… served=… score=… streak=…`:
//     midpour   the stream is non-empty and the active glass's visible top is ≥ 55 % of its line.
//     perfect   0.15 s (session time) after the first live Perfect is served (the big burst on screen).
//     spill     0.3 s after the liquid first goes over the rim (`overflowStarted`, or a Spill verdict).
//     finished  when the run finishes; the results card shows at once.
//     intro     round 6: 0.5 s (session time) into the run, during the intro phase: the shift banner ("Shift 6 · …")
//               and, with `hints=fresh` on a venue's shift, the one-time venue intro card are on screen.
//     tier      round 6 (Rush): after the Rush tier changes ("TIER 2 · FIZZ!" banner on screen). Round 7 (QA-3 P1-1):
//               ≥ 0.35 s after the change AND once the old glass has finished leaving (no `.leaving` glass), at the
//               latest 1.2 s after it, so the frame never shows the old glass's stamp riding out. Pair it with
//               `streak=11` (tiers change every `CoreTuning.rushTierEvery` = 12 glasses) so the change comes a glass
//               or two into the live frames. Logs `BRIM-T tier <n> venue=<v>` too.
//     repose    round 8 (REVIEW-6 N6, frame 30): sand only: the jug's `reposeProgress` is in 0.85…1 (the slide is
//               telegraphed: trickle, sight-glass creep, rustle) but the sand still holds. After 3 glasses served
//               without catching that window, any `reposeProgress` ≥ 0.85 will do.
//     faded     round 8 (frame 31): the glass under the spout has a line that has fully faded (`lineOpacity` 0, the
//               ghost tick on): 1 s after the fade, or sooner (≥ 0.3 s after it) once that glass is being poured
//               and is ≥ 60 % of the way to its line.
//     lowjug    round 8 (frame 33, Rush): mid-pour with the jug under 20 % full.
// - `streak=N`     the run is really PLAYED up to an N-Perfect streak (perfect autopilot, headless, at launch) before
//                  the live frames, leaving at least one order; score, served count and streak agree. Logs
//                  `BRIM-T streak seeded <n> (asked N) score=… served=…`.
// - `served=N`     round 8 (REVIEW-6 N1/N7): the run is really PLAYED (headless, at launch, the `autopilot=` style,
//                  default perfect) until N glasses are served, whatever their verdicts, leaving the run live (a shift
//                  keeps one order; Rush stops early once its jug is under 30 %). For late-Rush frames: Rush tiers
//                  follow the glass count, so a long Perfect streak is no longer needed to get there. Ignored when
//                  `streak` is given. Logs `BRIM-T served seeded <n> (asked N) score=… tier=… fill=… strikes=…`.
// - `missAt=N`     round 8 (REVIEW-6 N7): glass N (1-based) is poured by the `over` autopilot (always past the Good
//                  band), every other glass by `autopilot=` (results runs, live runs and `served` seeding), so a 2★
//                  card is a real one-miss run.
// - `progress=fresh|mid|full`   in-memory progress (demo runs never write UserDefaults). Default fresh.
// - `hints=fresh|off`           onboarding hints shown from scratch, or never. Default in demo: off.
// - `orient=portrait`   asks the window scene for portrait (requestGeometryUpdate), re-asking every 2 s, and logs
//                       `BRIM-T orient portrait ok` once the interface, the window and the screen are all portrait and
//                       the window fills the screen (never a letterboxed column) (`… failed` after 30 s, `… lost` if it
//                       rotates back later). Without it a Duo follows the way it is held (App/OrientationLock.swift).
// - `duo`        treat the canvas as a Duo (crease band) from the first frame and use the real hinge tilt source
//                (HingeTiltSource) even in demo. Without `autopilot`/`duo` a demo game uses TouchTiltSource.
// - `flip`       draw the game turned round (RootView.turnsRound), as the real app does on a Duo by default. Without
//                it demo runs (store frames) keep the upright layout. Logs `BRIM-T turned round <0|1>`.
// - `seed=N`     GameSession seed (default: day number for daily, 7 otherwise, so CI frames are stable).
// - Round 9:
//   `crowns=N`   on top of `progress=`: Flawless crowns on the first campaign shifts in play order (never the Sand Bar)
//                until the save holds at least N; each crowned shift is a 3★ all-Perfect clear (stars, best, best
//                Perfects follow). Never removes a crown. Frame 35: `progress=mid;crowns=4` opens the Soda dispenser.
//   `vessel=sodaFountain|milkshakeDiner|potionShop|sandBar|house`   the Glass Cabinet pick (Rush, Practice, the Home
//                loop), applied after `crowns`; only if the save really holds it (crowns, and the Sand Bar found for
//                the scoop), else the house jug. Frame 36: `mode=rush;crowns=3;vessel=sodaFountain`.
//   `jugFill=x`  (0…1) the live run's jug fill, set after any `streak`/`served` seeding (REVIEW-7 P2-1, frame 33:
//                `freezeOn=lowjug` needs the jug under 20 % mid-pour, which a `great` pilot with refills never reaches).
//                Logs `BRIM-T jug fill set <x>`.
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
// - Round 6 (every DEBUG build, GameController):
//   `BRIM-T tier <n> venue=<v>`    a Rush tier change the player sees (banner shown).
//   `BRIM-T intro card <hint>`     a one-time venue intro card was put up (`belt`, `fade`, `sand`, `foam`, `thick`).
// - Round 7 (every DEBUG build, GameController):
//   `BRIM-T start hold <0|1>`      the run is held under a venue intro card (1) / released (0) (QA-3 P1-3).
//   `BRIM-T intro card skipped <hint>`   a player with stars in the venue already knows it (QA-3 P2-12).
//   `BRIM-T touch override ends: the hinge poured`   "Use touch instead" ends at the next run (QA-3 P2-11).
// - Demo runs keep the scene rendering on every screen (the real app pauses it under Venues, Settings, results and the
//   pose cards), so `BRIM-T frame 120` always arrives.

enum DemoAutopilot: String, Equatable { case perfect, great, short, over, spill }

struct DemoConfig: Equatable {
    enum Screen: String, Equatable { case menu, venues, results, settings, game, standup, cover, icon, cabinet }
    enum Freeze: String, Equatable { case midpour, perfect, spill, finished, intro, tier, repose, faded, lowjug }
    enum ProgressPreset: String, Equatable { case fresh, mid, full }
    enum HintsPreset: String, Equatable { case fresh, off }

    var raw: String
    var screen: Screen?
    var mode: GameMode?
    var autopilot: DemoAutopilot?
    var freezeOn: Freeze?
    var streak: Int?
    /// Round 8: `served=N`, `missAt=N`.
    var served: Int?
    var missAt: Int?
    var progress: ProgressPreset?
    var hints: HintsPreset?
    var orientPortrait = false
    var duo = false
    /// `flip`: draw the game turned round, as the "Glasses on the sharp half" setting does on a real Duo.
    var flip = false
    var seed: UInt64?
    var badges = false
    /// Round 9: `crowns=N`, `vessel=<venue>|house`, `jugFill=x`.
    var crowns: Int?
    var vessel: VenueID?
    var jugFill: Double?

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
            case "served": config.served = Int(value)
            case "missAt": config.missAt = Int(value)
            case "progress": config.progress = ProgressPreset(rawValue: value)
            case "hints": config.hints = HintsPreset(rawValue: value)
            case "orient": config.orientPortrait = value == "portrait"
            case "duo": config.duo = value.isEmpty || value == "on" || value == "1" || value == "true"
            case "flip": config.flip = value.isEmpty || value == "on" || value == "1" || value == "true"
            case "seed": config.seed = UInt64(value)
            case "crowns": config.crowns = Int(value).map { max($0, 0) }
            case "vessel": config.vessel = VenueID(rawValue: value)
            case "jugFill":
                if let f = Double(value), f.isFinite { config.jugFill = min(max(f, 0), 1) }
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

    /// In-memory progress for `progress=`, then (round 9) the `crowns=N` and `vessel=` overrides on top.
    static func progressData(_ preset: ProgressPreset?, crowns: Int? = nil, vessel: VenueID? = nil) -> ProgressData {
        var data = presetData(preset)
        if let crowns { addCrowns(to: &data, upTo: crowns) }
        // Only a vessel the save really holds (crowns, and the Sand Bar found for the scoop): never a fake pick.
        if let vessel, data.isVesselUnlocked(vessel) { data.vessel = vessel }
        return data
    }

    /// Round 9 (`crowns=N`): Flawless crowns on the first campaign shifts (play order, never the Sand Bar) until the
    /// save holds at least N. A crowned shift is a real 3★ all-Perfect clear, so its stars, best and best Perfects
    /// follow. Never removes a crown. Pure; tested.
    static func addCrowns(to data: inout ProgressData, upTo target: Int) {
        for level in LevelCatalog.levels where level.venue != .sandBar {
            if data.totalCrowns >= target { return }
            guard !data.crowns.contains(level.id) else { continue }
            data.crowns.insert(level.id)
            data.stars[level.id] = 3
            data.bestScores[level.id] = max(data.bestScores[level.id] ?? 0, 1600)
            data.bestPerfects[level.id] = level.orders.count
        }
    }

    private static func presetData(_ preset: ProgressPreset?) -> ProgressData {
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
            // Round 6: one Flawless crown, so the Venues frame shows what one looks like.
            if let first = LevelCatalog.levels(in: .lemonadeStand).first { data.crowns.insert(first.id) }
            // Round 8 (REVIEW-6 N2): best Perfects per shift, so the 3★ bubbles show how far each is from its crown.
            let shortOfCrown = [0, 1, 3, 2, 4, 1, 2, 3]
            for (i, level) in LevelCatalog.levels(in: .lemonadeStand).enumerated() {
                data.bestPerfects[level.id] = max(level.orders.count - shortOfCrown[i % shortOfCrown.count], 1)
            }
            for (i, level) in LevelCatalog.levels(in: .sodaFountain).prefix(3).enumerated() {
                data.stars[level.id] = [3, 2, 2][i]
                data.bestScores[level.id] = 1100 + 120 * i
                data.bestPerfects[level.id] = max(level.orders.count - [2, 3, 4][i], 1)
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
            // Round 6: a full save still has crowns to chase: every Lemonade Stand shift and every other Soda one.
            for level in LevelCatalog.levels(in: .lemonadeStand) { data.crowns.insert(level.id) }
            for (i, level) in LevelCatalog.levels(in: .sodaFountain).enumerated() where i % 2 == 0 {
                data.crowns.insert(level.id)
            }
            // Round 8: every uncrowned shift is a Perfect or three short of its crown.
            for (i, level) in LevelCatalog.levels.enumerated() where level.venue != .sandBar {
                data.bestPerfects[level.id] = max(level.orders.count - (1 + i % 3), 1)
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
                // With `flip` the tabletop is upside down (OrientationLock.sharpSide).
                let wanted: UIInterfaceOrientation = OrientationLock.sharpSide ? .portraitUpsideDown : .portrait
                let portrait = scene.effectiveGeometry.interfaceOrientation == wanted
                    && w.height > w.width && s.height > s.width
                    && w.width >= s.width - 2 && w.height >= s.height - 2
                let shape = "window=\(Int(w.width))x\(Int(w.height)) screen=\(Int(s.width))x\(Int(s.height))"
                if portrait {
                    let since = matchedSince ?? Date()
                    matchedSince = since
                    if !reported && Date().timeIntervalSince(since) >= 0.8 {
                        reported = true
                        lostLogged = false
                        let upsideDown = scene.effectiveGeometry.interfaceOrientation == .portraitUpsideDown
                        print("BRIM-T orient portrait ok \(shape) upsideDown=\(upsideDown ? 1 : 0)")
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
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: OrientationLock.tabletop)) { error in
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
