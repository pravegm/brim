import AVFoundation
import Foundation
import os
import QuartzCore
import UIKit

/// Owns the audio session and the AVAudioEngine that hosts `PourSynth` (adapted from Squish's `AudioController`).
///
/// Session: `.playback` + `.mixWithOthers` by default (a silent switch that mutes a game reads as "no sound");
/// `.ambient` when the player turns on "Respect silent mode" (GAME-DESIGN §7).
/// Self-healing: interruptions, route changes, engine configuration changes and media-services resets all restart or
/// rebuild it; `heal()` (called ~1/s by the director) restarts a stopped engine. Every failure is logged and the game
/// simply goes silent: nothing here can crash.
@MainActor
final class BrimAudioEngine {
    /// Master trim applied to everything (the bed's master).
    static let masterGain: Float = 1.4

    private static let log = Logger(subsystem: "com.pravegm.brim", category: "audio")

    /// Sound on/off. Off pauses the engine (no battery spent); on starts it again.
    var enabled = true {
        didSet {
            guard oldValue != enabled else { return }
            if enabled {
                if isStarted { ensureRunning(reason: "sound switched on") } else if wantsStart { start() }
            } else {
                synth?.send(.silence)
                if engine.isRunning { engine.pause() }
            }
        }
    }

    var respectSilentSwitch = false {
        didSet {
            guard oldValue != respectSilentSwitch, isStarted else { return }
            configureSession()
            activateSession()
            ensureRunning(reason: "silent-mode setting changed")
        }
    }

    private var engine = AVAudioEngine()
    private(set) var synth: PourSynth?
    private var sourceNode: AVAudioSourceNode?
    private var observers: [NSObjectProtocol] = []
    private var engineObserver: NSObjectProtocol?
    private(set) var isStarted = false
    private var wantsStart = false
    private(set) var lastError: String?
    private var startFailures = 0
    private var lastRebuild: CFTimeInterval = -.infinity

    init() {}

    var isRunning: Bool { engine.isRunning }

    /// Session, graph, engine. Lazy: does nothing until sound is on.
    func start() {
        wantsStart = true
        guard enabled, !isStarted else { return }
        isStarted = true
        configureSession()
        activateSession()
        buildGraph()
        startEngine(reason: "launch")
        observeSystem()
    }

    /// Queue a one-shot sound (dropped while sound is off or the engine never came up).
    func play(_ commands: [SynthCommand]) {
        guard enabled, let synth else { return }
        for command in commands { synth.send(command) }
    }

    /// The continuous pour layers (always forwarded, so a master of 0 reaches the synth).
    func setBed(_ bed: PourBed) {
        synth?.send(.bed(bed))
    }

    func silence() {
        synth?.send(.silence)
    }

    /// The app became active again (calls, Siri, background).
    func resume() {
        guard isStarted, enabled else { return }
        activateSession()
        ensureRunning(reason: "app active again")
    }

    /// Cheap check from the frame loop (the director calls it about once a second).
    func heal() {
        guard isStarted, enabled, synth != nil, !engine.isRunning else { return }
        guard UIApplication.shared.applicationState != .background else { return }
        ensureRunning(reason: "found stopped")
    }

    // MARK: - Session and graph

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            if respectSilentSwitch {
                try session.setCategory(.ambient, mode: .default, options: [])
            } else {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
        } catch {
            record("Couldn't set the audio category", error)
        }
        try? session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(0.005)
    }

    private func activateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            record("Couldn't activate the audio session", error)
        }
    }

    /// Source node → main mixer → output, mono Float32 at the session rate (the mixer converts on route changes).
    private func buildGraph() {
        let session = AVAudioSession.sharedInstance()
        let sampleRate = session.sampleRate > 0 ? session.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            lastError = "Couldn't make a \(Int(sampleRate)) Hz format"
            Self.log.error("Couldn't make an audio format")
            return
        }
        let synth = PourSynth(sampleRate: Float(sampleRate))
        let node = AVAudioSourceNode(format: format, renderBlock: Self.renderBlock(for: synth))
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        engine.prepare()
        self.synth = synth
        sourceNode = node

        if let engineObserver { NotificationCenter.default.removeObserver(engineObserver) }
        engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.ensureRunning(reason: "audio hardware changed")
            }
        }
    }

    /// Built outside the main actor on purpose: the block runs on the real-time audio thread and touches only the
    /// synth (an `@unchecked Sendable` object whose render path is lock-free).
    private nonisolated static func renderBlock(for synth: PourSynth) -> AVAudioSourceNodeRenderBlock {
        return { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let first = buffers.first, let data = first.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            synth.render(frames: Int(frameCount), into: data)
            if buffers.count > 1 {
                for index in 1..<buffers.count {
                    buffers[index].mData?.copyMemory(from: data, byteCount: Int(first.mDataByteSize))
                }
            }
            return noErr
        }
    }

    private func startEngine(reason: String) {
        guard sourceNode != nil, enabled else { return }
        do {
            try engine.start()
            startFailures = 0
        } catch {
            startFailures += 1
            record("Couldn't start the audio engine (\(reason), try \(startFailures))", error)
            if startFailures == 2 {
                // Let the mixer → output connection renegotiate the hardware format, then try once more.
                engine.disconnectNodeOutput(engine.mainMixerNode)
                engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
                do {
                    try engine.start()
                    startFailures = 0
                } catch {
                    startFailures += 1
                    record("Couldn't start the audio engine after reconnecting", error)
                }
            } else if startFailures >= 4 {
                let now = CACurrentMediaTime()
                if now - lastRebuild > 5 {
                    lastRebuild = now
                    startFailures = 0
                    rebuild()
                }
            }
        }
    }

    private func ensureRunning(reason: String) {
        guard isStarted, enabled else { return }
        if synth == nil {
            rebuild()
            return
        }
        guard !engine.isRunning else { return }
        activateSession()
        startEngine(reason: reason)
    }

    /// The audio server restarted (or the engine kept failing): every audio object is dead, so start from scratch.
    private func rebuild() {
        guard isStarted else { return }
        engine = AVAudioEngine()
        synth = nil
        sourceNode = nil
        configureSession()
        activateSession()
        buildGraph()
        startEngine(reason: "rebuild")
    }

    private func observeSystem() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                            queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let ended = raw.flatMap { AVAudioSession.InterruptionType(rawValue: $0) } == .ended
            MainActor.assumeIsolated {
                if ended { self?.resume() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.ensureRunning(reason: "route changed")
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuild()
            }
        })
    }

    private func record(_ what: String, _ error: Error) {
        let nsError = error as NSError
        let message = "\(what): \(nsError.localizedDescription) (code \(nsError.code))"
        lastError = message
        Self.log.error("\(message, privacy: .public)")
    }
}
