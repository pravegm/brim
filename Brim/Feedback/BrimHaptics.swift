import CoreHaptics
import Foundation
import os
import QuartzCore
import UIKit

/// One haptic note: a transient tap or a short continuous buzz (times relative to the cue's start).
struct HapticNote: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case transient, continuous }
    var kind: Kind
    var time: Double
    var intensity: Float
    var sharpness: Float
    var duration: Double

    static func tap(_ intensity: Float, _ sharpness: Float, at time: Double = 0) -> HapticNote {
        HapticNote(kind: .transient, time: time, intensity: intensity, sharpness: sharpness, duration: 0)
    }

    static func buzz(_ intensity: Float, _ sharpness: Float, at time: Double = 0, duration: Double) -> HapticNote {
        HapticNote(kind: .continuous, time: time, intensity: intensity, sharpness: sharpness, duration: duration)
    }
}

/// One point of an intensity-control curve.
struct HapticPoint: Sendable, Equatable {
    var time: Double
    var value: Float
}

/// A haptic cue: notes plus an optional intensity wobble (the spill's heavy wobbly buzz).
struct HapticCue: Sendable, Equatable {
    var notes: [HapticNote]
    /// Intensity-control points (time, 0…1 multiplier) applied across the cue (≤ 16); empty = none.
    var wobble: [HapticPoint]

    init(notes: [HapticNote], wobble: [HapticPoint] = []) {
        self.notes = notes
        self.wobble = wobble
    }
}

/// The haptic vocabulary of Brim (GAME-DESIGN §7). Pure data, so it is testable.
enum HapticBook {
    /// The pour's continuous bed: intensity ∝ flow (0.15…0.7), sharpness ∝ fill of the glass (0.2…0.8).
    static func flowLevel(flow: Double) -> Float {
        let f = SoundBook.clamp01(flow)
        guard f > 0.01 else { return 0 }
        return Float(0.15 + 0.55 * f)
    }

    static func flowSharpness(fill: Double) -> Float {
        Float(0.2 + 0.6 * SoundBook.clamp01(fill))
    }

    static func glug(intensity: Double, fill: Double) -> HapticCue {
        let i = Float(0.22 + 0.22 * SoundBook.clamp01(intensity))
        return HapticCue(notes: [.tap(i, Float(0.3 + 0.4 * SoundBook.clamp01(fill)))])
    }

    /// The pour starts: a gentle detent, a crisp click that settles (felt most on the touch fallback, where the finger
    /// has no hinge to feel).
    static let pourStart = HapticCue(notes: [.tap(0.42, 0.78), .tap(0.14, 0.5, at: 0.03)])
    static let arrival = HapticCue(notes: [.tap(0.3, 0.45)])
    /// Lock-in: the stream has landed with the top inside the Perfect band. A soft, crisp tick (the Perfect's double
    /// tap confirms it a beat later).
    static let lockedIn = HapticCue(notes: [.tap(0.32, 0.88)])
    /// The flat gate opened: a soft confirm click, a low latch then a lighter catch.
    static let flatArmed = HapticCue(notes: [.tap(0.4, 0.42), .tap(0.2, 0.7, at: 0.048)])
    /// Perfect: a crisp double tap.
    static let perfect = HapticCue(notes: [.tap(0.9, 0.9), .tap(0.75, 0.95, at: 0.075)])
    static let great = HapticCue(notes: [.tap(0.6, 0.7)])
    static let good = HapticCue(notes: [.tap(0.45, 0.55)])
    /// Short: a soft, dull thud.
    static let short = HapticCue(notes: [.tap(0.45, 0.1), .buzz(0.3, 0.05, duration: 0.12)])
    /// Spill (once, the instant it overflows): a heavy wobbly buzz — three decaying hits over a wobbling rumble that
    /// runs out with the overflow sheet (~0.55 s).
    static let spill = HapticCue(
        notes: [.tap(1.0, 0.35), .tap(0.7, 0.3, at: 0.09), .tap(0.45, 0.25, at: 0.2), .buzz(0.65, 0.15, duration: 0.55)],
        wobble: [HapticPoint(time: 0, value: 1), HapticPoint(time: 0.05, value: 0.45),
                 HapticPoint(time: 0.1, value: 0.95), HapticPoint(time: 0.15, value: 0.4),
                 HapticPoint(time: 0.2, value: 0.8), HapticPoint(time: 0.26, value: 0.3),
                 HapticPoint(time: 0.32, value: 0.55), HapticPoint(time: 0.4, value: 0.25),
                 HapticPoint(time: 0.47, value: 0.3), HapticPoint(time: 0.55, value: 0)]
    )
    /// Serve: the coaster thump (lands with the slide, ~0.3 s after the result).
    static let serve = HapticCue(notes: [.tap(0.65, 0.2, at: 0.3), .buzz(0.35, 0.1, at: 0.3, duration: 0.06)])
    static let jugSwapped = HapticCue(notes: [.tap(0.6, 0.3), .buzz(0.3, 0.15, duration: 0.05)])
    static let refill = HapticCue(notes: [.tap(0.3, 0.5), .tap(0.35, 0.6, at: 0.07), .tap(0.4, 0.7, at: 0.14)])
    static let multiplier = HapticCue(notes: [.tap(0.45, 0.85), .tap(0.5, 0.9, at: 0.07)])
    static let jugEmpty = HapticCue(notes: [.buzz(0.4, 0.1, duration: 0.3)])
    static let celebrate = HapticCue(notes: [.tap(0.5, 0.6), .tap(0.6, 0.7, at: 0.11), .tap(0.75, 0.8, at: 0.22),
                                             .tap(1.0, 0.9, at: 0.36)])
    static let gentleEnd = HapticCue(notes: [.tap(0.4, 0.4), .tap(0.3, 0.3, at: 0.24)])
    static let uiTap = HapticCue(notes: [.tap(0.35, 0.7)])
    static let uiConfirm = HapticCue(notes: [.tap(0.5, 0.8), .tap(0.4, 0.9, at: 0.06)])
}

/// Core Haptics for Brim: one advanced player carries the continuous pour (steered by dynamic parameters, ≤ 30 Hz),
/// and every moment plays as its own short pattern. Self-healing after stops and server resets (Squish's pattern).
@MainActor
final class BrimHaptics {
    private static let log = Logger(subsystem: "com.pravegm.brim", category: "haptics")

    var enabled = true {
        didSet {
            if !enabled { setFlow(level: 0, sharpness: 0.5, now: CACurrentMediaTime(), force: true) }
        }
    }

    /// Round 4 (QA P2-7, battery): menus. While idle there is no looping pour-bed player and the engine may shut the
    /// hardware down by itself (`isAutoShutdownEnabled`); a cue (a menu tap, the fanfare) still plays — the engine is
    /// started again for it. Off: the pour bed is rebuilt at once for the game.
    var idle = false {
        didSet {
            guard oldValue != idle else { return }
            if idle {
                if let player = flowPlayer {
                    try? player.stop(atTime: CHHapticTimeImmediate)
                }
                flowPlayer = nil
                lastLevel = 0
                engine?.isAutoShutdownEnabled = true
            } else {
                engine?.isAutoShutdownEnabled = false
                if engine != nil && (!isRunning || flowPlayer == nil) { restart() }
            }
        }
    }

    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var flowPlayer: CHHapticAdvancedPatternPlayer?
    private var isRunning = false
    private var lastRecovery: CFTimeInterval = 0
    private var lastSend: CFTimeInterval = 0
    private var lastLevel: Float = 0
    private var lastSharpness: Float = 0.5
    private(set) var lastError: String?

    init() {}

    func start() {
        guard supportsHaptics, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = idle
            // Both handlers arrive on an engine-internal queue: hop to the main actor with a strong, immutable capture.
            engine.stoppedHandler = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.isRunning = false
                    self.flowPlayer = nil
                }
            }
            engine.resetHandler = { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.isRunning = false
                    self.flowPlayer = nil
                    self.restart()
                }
            }
            self.engine = engine
            restart()
        } catch {
            record("Couldn't create the haptic engine", error)
            engine = nil
        }
    }

    /// The app became active again: the system stops the engine on suspension.
    func resume() {
        guard supportsHaptics else { return }
        if engine == nil {
            start()
        } else if !isRunning || (!idle && flowPlayer == nil) {
            restart()
        }
    }

    /// Throttled recovery from the frame loop.
    func heal() {
        guard engine != nil, !isRunning || (!idle && flowPlayer == nil) else { return }
        guard UIApplication.shared.applicationState != .background else { return }
        restart()
    }

    private func restart() {
        guard let engine else { return }
        do {
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
            record("Couldn't start the haptic engine", error)
            return
        }
        flowPlayer = nil
        // Menus have no pour: no looping player to keep the hardware awake.
        if idle { return }
        do {
            try makeFlowPlayer()
        } catch {
            record("Couldn't build the pour bed", error)
        }
    }

    /// One looping continuous event at intensity 1 / sharpness 0.5; the dynamic parameters scale and shift it.
    private func makeFlowPlayer() throws {
        guard let engine else { return }
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
            ],
            relativeTime: 0,
            duration: 30
        )
        let pattern = try CHHapticPattern(events: [event], parameters: [])
        let player = try engine.makeAdvancedPlayer(with: pattern)
        player.loopEnabled = true
        try player.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 0,
                                                            relativeTime: 0)], atTime: CHHapticTimeImmediate)
        try player.start(atTime: CHHapticTimeImmediate)
        try player.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 0,
                                                            relativeTime: 0)], atTime: CHHapticTimeImmediate)
        flowPlayer = player
        lastLevel = 0
    }

    // MARK: - Per frame

    /// The pour bed: call every frame; sends at most ~30 times a second, ramping between values (no zipper).
    func updateFlow(flow: Double, fill: Double, now: CFTimeInterval) {
        let level = enabled ? HapticBook.flowLevel(flow: flow) : 0
        setFlow(level: level, sharpness: HapticBook.flowSharpness(fill: fill), now: now, force: false)
    }

    private func setFlow(level: Float, sharpness: Float, now: CFTimeInterval, force: Bool) {
        guard let player = flowPlayer, isRunning else { return }
        let silencing = level == 0 && lastLevel > 0
        let changed = abs(level - lastLevel) > 0.015 || abs(sharpness - lastSharpness) > 0.03
        guard force || silencing || changed else { return }
        guard force || silencing || now - lastSend >= 1.0 / 30 else { return }
        lastSend = now
        let ramp: TimeInterval = silencing ? 0.04 : 1.0 / 30
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: lastLevel),
                CHHapticParameterCurve.ControlPoint(relativeTime: ramp, value: level),
            ],
            relativeTime: 0
        )
        try? player.scheduleParameterCurve(curve, atTime: CHHapticTimeImmediate)
        // Sharpness control is an offset from the event's 0.5.
        try? player.sendParameters([CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                                             value: sharpness - 0.5, relativeTime: 0)],
                                   atTime: CHHapticTimeImmediate)
        lastLevel = level
        lastSharpness = sharpness
    }

    // MARK: - Moments

    func play(_ cue: HapticCue) {
        guard enabled, supportsHaptics, !cue.notes.isEmpty else { return }
        if !isRunning || engine == nil {
            let now = CACurrentMediaTime()
            if now - lastRecovery > 0.5 {
                lastRecovery = now
                resume()
            }
        }
        guard let engine, isRunning else { return }
        let events: [CHHapticEvent] = cue.notes.map { (note: HapticNote) -> CHHapticEvent in
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: min(max(note.intensity, 0), 1))
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: min(max(note.sharpness, 0), 1))
            switch note.kind {
            case .transient:
                return CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness],
                                     relativeTime: note.time)
            case .continuous:
                return CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness],
                                     relativeTime: note.time, duration: max(note.duration, 0.01))
            }
        }
        var curves: [CHHapticParameterCurve] = []
        if !cue.wobble.isEmpty {
            var points: [CHHapticParameterCurve.ControlPoint] = []
            for point in cue.wobble.prefix(16) {
                points.append(CHHapticParameterCurve.ControlPoint(relativeTime: point.time, value: point.value))
            }
            curves.append(CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: points,
                                                 relativeTime: 0))
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            record("Couldn't play a haptic", error)
        }
    }

    private func record(_ what: String, _ error: Error) {
        let nsError = error as NSError
        let message = "\(what): \(nsError.localizedDescription) (code \(nsError.code))"
        lastError = message
        Self.log.error("\(message, privacy: .public)")
    }
}
