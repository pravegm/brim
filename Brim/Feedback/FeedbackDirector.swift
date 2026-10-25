import Foundation
import QuartzCore
import UIKit

/// The three feedback settings, persisted in UserDefaults (`brim.sound`, `brim.haptics`, `brim.silent`).
struct FeedbackSettings: Equatable {
    static let soundKey = "brim.sound"
    static let hapticsKey = "brim.haptics"
    static let silentKey = "brim.silent"

    var soundOn = true
    var hapticsOn = true
    var respectSilentSwitch = false

    static func load(from defaults: UserDefaults) -> FeedbackSettings {
        var settings = FeedbackSettings()
        if let value = defaults.object(forKey: soundKey) as? Bool { settings.soundOn = value }
        if let value = defaults.object(forKey: hapticsKey) as? Bool { settings.hapticsOn = value }
        if let value = defaults.object(forKey: silentKey) as? Bool { settings.respectSilentSwitch = value }
        return settings
    }

    func save(to defaults: UserDefaults) {
        defaults.set(soundOn, forKey: Self.soundKey)
        defaults.set(hapticsOn, forKey: Self.hapticsKey)
        defaults.set(respectSilentSwitch, forKey: Self.silentKey)
    }
}

/// Audio + haptics for Brim (GAME-DESIGN §5, §7). The App calls `start()` once at launch, then `handle(events:snapshot:)`
/// every frame. Everything audible is synthesised in real time (`PourSynth`); every touch is Core Haptics.
///
/// Per frame it only builds one small value (`PourBed`), pushes it into a lock-free queue (≤ 60 Hz) and steers the
/// haptic pour bed (≤ 30 Hz); events map to short recipes from `SoundBook` and `HapticBook`.
@MainActor
final class FeedbackDirector: FeedbackSink {
    static let shared = FeedbackDirector()

    var soundOn: Bool {
        didSet {
            guard oldValue != soundOn else { return }
            persist()
            audio.enabled = soundOn
            // Menus and pause cards keep this; a running game re-sends its bed on the next frame.
            audio.setBed(idleBed)
        }
    }

    var hapticsOn: Bool {
        didSet {
            guard oldValue != hapticsOn else { return }
            persist()
            haptics.enabled = hapticsOn
        }
    }

    var respectSilentSwitch: Bool {
        didSet {
            guard oldValue != respectSilentSwitch else { return }
            persist()
            audio.respectSilentSwitch = respectSilentSwitch
        }
    }

    private let defaults: UserDefaults
    private let audio = BrimAudioEngine()
    private let haptics = BrimHaptics()
    private var started = false
    private var paused = false
    /// `setIdle(true)` from the App (menus).
    private var menuIdle = false
    /// Paused for `pausedIdleDelay` s.
    private var pausedIdle = false
    private var pauseGeneration = 0
    private var activationObserver: NSObjectProtocol?
    private var dice = FeelDice(seed: 0xB1A1_F00D)
    private var lastBedSend: CFTimeInterval = 0
    private var lastHeal: CFTimeInterval = 0
    private var lastGlugSound: CFTimeInterval = 0
    private var lastGlugHaptic: CFTimeInterval = 0
    private var lastSplash: CFTimeInterval = 0
    private var lastCounterSplash: CFTimeInterval = 0
    private var lastWhoosh: CFTimeInterval = -.infinity
    /// A pause right after the whoosh must not cut it off (`.silence` stops every one-shot).
    private var whooshUntil: CFTimeInterval = -.infinity
    /// Glasses whose spill has already been heard (overflowStarted and served(.spill) arrive together; play once).
    private var spilledGlasses = Set<Int>()
    private var lockedGlasses = Set<Int>()
    /// The Perfect band as revealed by the glass under the spout (the distance at which `inPerfectBand` flips on).
    private var bandGlassID: Int?
    private var wasInBand = false
    private var observedBand: Double?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let settings = FeedbackSettings.load(from: defaults)
        soundOn = settings.soundOn
        hapticsOn = settings.hapticsOn
        respectSilentSwitch = settings.respectSilentSwitch
        audio.enabled = settings.soundOn
        audio.respectSilentSwitch = settings.respectSilentSwitch
        haptics.enabled = settings.hapticsOn
        // Menus play before any game frame: start from an audible, empty bed (a master of 0 mutes one-shots too).
        audio.setBed(idleBed)
    }

    /// No pour layers, master on (or 0 with sound off).
    private var idleBed: PourBed {
        SoundBook.idleBed(master: soundOn ? BrimAudioEngine.masterGain : 0)
    }

    /// Audio session + engines. Safe to call more than once; also called lazily by the first sound.
    func start() {
        guard !started else { return }
        started = true
        audio.start()
        haptics.start()
        activationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.audio.resume()
                self?.haptics.resume()
            }
        }
    }

    func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        pauseGeneration &+= 1
        if paused {
            // The pour layers stop; the master stays up so the pause card's buttons (and the closing whoosh) are heard.
            audio.setBed(idleBed)
            let now = CACurrentMediaTime()
            if now >= whooshUntil { audio.silence() }
            haptics.updateFlow(flow: 0, fill: 0, now: now)
            // A pause that lasts (the attract loop under the menus, a pause card left open) idles the engines too.
            let generation = pauseGeneration
            let delay = Self.pausedIdleDelay
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, self.paused, self.pauseGeneration == generation else { return }
                self.pausedIdle = true
                self.applyIdle()
            }
        } else if pausedIdle {
            pausedIdle = false
            applyIdle()
        }
    }

    /// Round 4 (QA P2-7, battery): the App calls `setIdle(true)` on screens with no pour (Home, Venues, Settings,
    /// Results once shown) and `setIdle(false)` when a run starts. Idle: the haptic pour-bed player stops and the haptic
    /// engine may shut down by itself; the audio engine pauses after a few quiet seconds. Menu sounds (`uiTap`,
    /// `uiConfirm`, `celebrate`) still play: the engines wake for them. Also entered by itself after
    /// `pausedIdleDelay` s of `setPaused(true)`, and left by `setPaused(false)` or by a pour in `handle`.
    func setIdle(_ idle: Bool) {
        guard idle != menuIdle else { return }
        menuIdle = idle
        if idle {
            audio.setBed(idleBed)
            haptics.updateFlow(flow: 0, fill: 0, now: CACurrentMediaTime())
        }
        applyIdle()
    }

    /// True while the engines are idling (menus, or a long pause).
    var isIdle: Bool { menuIdle || pausedIdle }

    /// Seconds of `setPaused(true)` before the engines idle by themselves.
    static let pausedIdleDelay: Double = 3

    private func applyIdle() {
        let sleepy = menuIdle || pausedIdle
        audio.idle = sleepy
        haptics.idle = sleepy
    }

    /// The App paused the run because the phone is closing (ROUND-3 decision 1): the pour stops at once and a soft
    /// whoosh plays (at most once a second). Call it with `setPaused(true)`, in either order. Nothing plays on resume;
    /// the pour stays quiet until the flat gate re-arms (`snapshot.needsFlat`).
    func autopaused() {
        ensureStarted()
        let now = CACurrentMediaTime()
        audio.setBed(idleBed)
        haptics.updateFlow(flow: 0, fill: 0, now: now)
        guard now - lastWhoosh >= 1 else { return }
        lastWhoosh = now
        // Stop whatever was ringing (the pour's splashes), then the whoosh; a pause right after must not cut it.
        audio.silence()
        audio.play(SoundBook.pauseWhoosh())
        whooshUntil = now + 0.5
    }

    // MARK: - Menu sounds

    func uiTap() {
        ensureStarted()
        audio.play(SoundBook.uiTap())
        haptics.play(HapticBook.uiTap)
    }

    func uiConfirm() {
        ensureStarted()
        audio.play(SoundBook.uiConfirm())
        haptics.play(HapticBook.uiConfirm)
    }

    /// New best / 3 stars: the little fanfare and a celebratory pattern.
    func celebrate() {
        ensureStarted()
        audio.play(SoundBook.finished(cleared: true))
        haptics.play(HapticBook.celebrate)
    }

    // MARK: - Per frame

    func handle(events: [GameEvent], snapshot: GameSnapshot) {
        ensureStarted()
        // Safety net: a live pour wakes the engines even if the App forgot `setIdle(false)` (a finished run behind the
        // results card sends no events and no flow, so it stays idle).
        if menuIdle && !paused && (snapshot.telemetry.flow > 0.004 || !events.isEmpty) {
            setIdle(false)
        }
        let now = CACurrentMediaTime()
        if now - lastHeal > 1 {
            lastHeal = now
            audio.heal()
            haptics.heal()
        }
        let telemetry = snapshot.telemetry
        let texture = SoundBook.texture(for: telemetry.liquid)
        let band = perfectBand(snapshot)
        let pourAudible = SoundBook.pourIsAudible(needsFlat: snapshot.needsFlat)

        if paused || !pourAudible {
            if !paused && now - lastBedSend >= 1.0 / 60 {
                lastBedSend = now
                audio.setBed(idleBed)
            }
            haptics.updateFlow(flow: 0, fill: 0, now: now)
        } else {
            if now - lastBedSend >= 1.0 / 60 {
                lastBedSend = now
                let master = soundOn ? BrimAudioEngine.masterGain : 0
                let bed = SoundBook.pourBed(telemetry: telemetry, foam: activeFoam(snapshot), texture: texture,
                                            master: master, band: band, streak: snapshot.streak)
                audio.setBed(bed)
            }
            haptics.updateFlow(flow: telemetry.flow, fill: telemetry.activeFill, now: now)
        }

        for event in events {
            if !pourAudible && Self.isPourTexture(event) { continue }
            react(to: event, snapshot: snapshot, texture: texture, now: now)
        }
    }

    /// The pour's own one-shots, kept quiet while the flat gate is shut.
    nonisolated static func isPourTexture(_ event: GameEvent) -> Bool {
        switch event {
        case .pourStarted, .glug, .splashInGlass, .splashOnCounter:
            return true
        default:
            return false
        }
    }

    // MARK: - Events

    private func react(to event: GameEvent, snapshot: GameSnapshot, texture: PourTexture, now: CFTimeInterval) {
        let fill = snapshot.telemetry.activeFill
        switch event {
        case .pourStarted:
            audio.play(SoundBook.pourStart(dice: &dice))
            haptics.play(HapticBook.pourStart)
        case .pourStopped:
            break
        case .glug(let intensity):
            if now - lastGlugSound >= texture.glugGap {
                lastGlugSound = now
                audio.play(SoundBook.glug(intensity: intensity, fill: fill, texture: texture, dice: &dice))
            }
            if now - lastGlugHaptic >= max(texture.glugGap, 0.045) {
                lastGlugHaptic = now
                haptics.play(HapticBook.glug(intensity: intensity, fill: fill))
            }
        case .splashInGlass(_, _, let strength):
            if now - lastSplash >= 0.12 {
                lastSplash = now
                audio.play(SoundBook.splashInGlass(strength: strength))
            }
        case .splashOnCounter(_, let strength):
            if now - lastCounterSplash >= 0.1 {
                lastCounterSplash = now
                audio.play(SoundBook.splashOnCounter(strength: strength))
            }
        case .enteredPerfectBand:
            break // the shimmer already sings it
        case .overflowStarted(let glassID):
            // Judged live: the spill lands the moment it happens (splash, sheet, "uh-oh", drips; heavy wobbly buzz).
            spill(glassID: glassID)
        case .glassArrived(let glassID):
            // Glass ids restart with every run: forget anything remembered about this id.
            spilledGlasses.remove(glassID)
            lockedGlasses.remove(glassID)
            audio.play(SoundBook.arrival(dice: &dice))
            haptics.play(HapticBook.arrival)
        case .served(let glassID, let judgement, _):
            if judgement == .spill { spill(glassID: glassID) }
            served(judgement, streak: snapshot.streak)
        case .lockedIn(let glassID):
            if !lockedGlasses.contains(glassID) {
                if lockedGlasses.count > 64 { lockedGlasses.removeAll() }
                lockedGlasses.insert(glassID)
                audio.play(SoundBook.lockedIn(streak: snapshot.streak, dice: &dice))
                haptics.play(HapticBook.lockedIn)
            }
        case .flatArmed:
            audio.play(SoundBook.flatArmed())
            haptics.play(HapticBook.flatArmed)
        case .streak:
            break // the ting reads the snapshot's streak; 0 simply restarts the scale
        case .multiplier(let value):
            if value > 1 {
                audio.play(SoundBook.multiplier(value))
                haptics.play(HapticBook.multiplier)
            }
        case .strike:
            break // the spill already spoke
        case .jugRefilled:
            audio.play(SoundBook.refill())
            haptics.play(HapticBook.refill)
        case .jugSwapped:
            audio.play(SoundBook.jugSwapped(dice: &dice))
            haptics.play(HapticBook.jugSwapped)
        case .jugEmpty:
            audio.play(SoundBook.jugEmpty())
            haptics.play(HapticBook.jugEmpty)
        case .nearingLine:
            break
        case .finished(let result):
            spilledGlasses.removeAll()
            lockedGlasses.removeAll()
            audio.play(SoundBook.finished(cleared: result.cleared))
            haptics.play(result.cleared ? HapticBook.celebrate : HapticBook.gentleEnd)
        }
    }

    /// The spill, exactly once per glass (Core emits `overflowStarted` and `served(.spill)` together; a brim-full
    /// judgement may arrive with only the latter).
    private func spill(glassID: Int) {
        if spilledGlasses.contains(glassID) { return }
        if spilledGlasses.count > 64 { spilledGlasses.removeAll() }
        spilledGlasses.insert(glassID)
        audio.play(SoundBook.spill(dice: &dice))
        haptics.play(HapticBook.spill)
    }

    private func served(_ judgement: Judgement, streak: Int) {
        switch judgement {
        case .perfect:
            audio.play(SoundBook.perfect(streak: max(streak, 1), dice: &dice))
            haptics.play(HapticBook.perfect)
        case .great:
            audio.play(SoundBook.softTing(great: true, dice: &dice))
            haptics.play(HapticBook.great)
        case .good:
            audio.play(SoundBook.softTing(great: false, dice: &dice))
            haptics.play(HapticBook.good)
        case .short:
            audio.play(SoundBook.short())
            haptics.play(HapticBook.short)
        case .spill:
            break // the spill already spoke (once); the slide below still runs
        }
        audio.play(SoundBook.serve(dice: &dice))
        haptics.play(HapticBook.serve)
    }

    // MARK: - Helpers

    private func ensureStarted() {
        if !started { start() }
    }

    /// The head on the glass under the spout, as a fraction of its interior height (soda fizz follows it).
    private func activeFoam(_ snapshot: GameSnapshot) -> Double {
        guard let glass = snapshot.glasses.first(where: { $0.phase == .filling }) else { return 0 }
        let interior = glass.shape.interiorHeight
        guard interior > 0 else { return 0 }
        return Double(glass.foamHeight / interior)
    }

    /// The Perfect band of the glass under the spout. The snapshot doesn't carry it, but the glass reveals it: the
    /// signed distance at which `inPerfectBand` switches on while the level rises is the band's lower edge.
    /// Until a glass shows it, the last one seen (or ±3 %) is used.
    private func perfectBand(_ snapshot: GameSnapshot) -> Double {
        guard let glass = snapshot.glasses.first(where: { $0.phase == .filling }) else {
            return observedBand ?? SoundBook.defaultBand
        }
        if glass.id != bandGlassID {
            bandGlassID = glass.id
            wasInBand = glass.inPerfectBand
        }
        if glass.inPerfectBand && !wasInBand {
            let distance = snapshot.telemetry.distanceToLine
            if distance.isFinite, distance < -0.004, distance > -0.12 {
                observedBand = -distance
            }
        }
        wasInBand = glass.inPerfectBand
        return observedBand ?? SoundBook.defaultBand
    }

    private func persist() {
        FeedbackSettings(soundOn: soundOn, hapticsOn: hapticsOn, respectSilentSwitch: respectSilentSwitch)
            .save(to: defaults)
    }
}
