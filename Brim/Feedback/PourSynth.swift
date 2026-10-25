import Foundation
import Synchronization

// MARK: - Commands (main thread → audio thread)
//
// Every payload is a plain value (Floats, Ints, enums without payloads), so copying a command never touches ARC and
// the audio thread can read it from the lock-free queue without allocating or locking.

enum SynthFilterMode: Sendable, Equatable {
    case lowPass, bandPass, highPass
}

/// Partial tables for struck resonators.
enum SynthRingKind: Sendable, Equatable {
    /// Drinking glass: sparse, bright, inharmonic (1, 2.32, 4.25, 6.63 …).
    case glass
    /// Ceramic jug: dull, clustered low partials.
    case ceramic
    /// Wooden click (UI).
    case wood
    /// Small bell (fanfare).
    case bell
}

/// A one-shot filtered-noise burst (splashes, slides, clicks), optionally sweeping its cutoff.
struct SynthNoise: Sendable, Equatable {
    var mode: SynthFilterMode
    var cutoff: Float
    var cutoffEnd: Float
    var sweep: Float
    var q: Float
    var attack: Float
    /// Exponential decay time constant (s).
    var decay: Float
    var gain: Float
    var delay: Float

    init(_ mode: SynthFilterMode, cutoff: Float, to cutoffEnd: Float? = nil, sweep: Float = 0, q: Float = 0.8,
         attack: Float = 0.002, decay: Float, gain: Float, delay: Float = 0) {
        self.mode = mode
        self.cutoff = cutoff
        self.cutoffEnd = cutoffEnd ?? cutoff
        self.sweep = sweep
        self.q = q
        self.attack = attack
        self.decay = decay
        self.gain = gain
        self.delay = delay
    }
}

/// A pitched tone with a glide, vibrato and a 1/n harmonic stack (the "hmm", soft notes).
struct SynthTone: Sendable, Equatable {
    var start: Float
    var end: Float
    var glide: Float
    var duration: Float
    var attack: Float
    var decay: Float
    var gain: Float
    var harmonics: Int
    var vibratoRate: Float
    var vibratoDepth: Float
    var delay: Float

    init(start: Float, end: Float? = nil, glide: Float = 0.1, duration: Float, attack: Float = 0.01, decay: Float,
         gain: Float, harmonics: Int = 1, vibratoRate: Float = 0, vibratoDepth: Float = 0, delay: Float = 0) {
        self.start = start
        self.end = end ?? start
        self.glide = glide
        self.duration = duration
        self.attack = attack
        self.decay = decay
        self.gain = gain
        self.harmonics = harmonics
        self.vibratoRate = vibratoRate
        self.vibratoDepth = vibratoDepth
        self.delay = delay
    }
}

/// A struck modal resonator: up to `PourSynth.maxPartials` decaying sinusoids.
struct SynthRing: Sendable, Equatable {
    var kind: SynthRingKind
    var fundamental: Float
    var partials: Int
    /// Decay time constant of the fundamental (s); higher partials decay faster.
    var decay: Float
    /// Amplitude roll-off per partial, 0…1 (higher = brighter).
    var brightness: Float
    var gain: Float
    var delay: Float
    /// Seeds a ±1.5 % partial detune so two strikes never sound identical.
    var seed: UInt32

    init(_ kind: SynthRingKind, fundamental: Float, partials: Int = 4, decay: Float, brightness: Float = 0.6,
         gain: Float, delay: Float = 0, seed: UInt32 = 1) {
        self.kind = kind
        self.fundamental = fundamental
        self.partials = partials
        self.decay = decay
        self.brightness = brightness
        self.gain = gain
        self.delay = delay
        self.seed = seed
    }
}

/// A bubble pop (Minnaert): a decaying sine whose pitch chirps upward as the bubble rises.
struct SynthBubble: Sendable, Equatable {
    var frequency: Float
    /// Pitch ratio reached by the end of the pop (> 1 rises).
    var chirp: Float
    var decay: Float
    var gain: Float
    var delay: Float

    init(frequency: Float, chirp: Float = 1.4, decay: Float, gain: Float, delay: Float = 0) {
        self.frequency = frequency
        self.chirp = chirp
        self.decay = decay
        self.gain = gain
        self.delay = delay
    }
}

/// The continuous pour layers, sent every frame and smoothed per sample on the audio thread.
struct PourBed: Sendable, Equatable {
    /// Master gain (0 = silent; sound off and pause go through here).
    var master: Float = 0
    /// Broad splash noise (liquid hitting liquid).
    var splashGain: Float = 0
    var splashCenter: Float = 2400
    /// The filling vessel's air-column resonance excited by the same noise: the "singing" pitch that rises.
    var resonance: Float = 180
    var resonanceGain: Float = 0
    var resonanceQ: Float = 5
    /// Soda fizz: sparse random high-passed clicks per second, and their level.
    var fizzRate: Float = 0
    var fizzGain: Float = 0
    /// Sand: dry grainy hiss.
    var hissGain: Float = 0
    var hissCenter: Float = 5200
    /// Depth of the slow random level wobble on the rush (0…0.6).
    var turbulence: Float = 0.3

    mutating func approach(_ target: PourBed, _ k: Float) {
        master += (target.master - master) * k
        splashGain += (target.splashGain - splashGain) * k
        splashCenter += (target.splashCenter - splashCenter) * k
        resonance += (target.resonance - resonance) * k
        resonanceGain += (target.resonanceGain - resonanceGain) * k
        resonanceQ = target.resonanceQ
        fizzRate += (target.fizzRate - fizzRate) * k
        fizzGain += (target.fizzGain - fizzGain) * k
        hissGain += (target.hissGain - hissGain) * k
        hissCenter = target.hissCenter
        turbulence += (target.turbulence - turbulence) * k
    }
}

enum SynthCommand: Sendable, Equatable {
    case bed(PourBed)
    case noise(SynthNoise)
    case tone(SynthTone)
    case ring(SynthRing)
    case bubble(SynthBubble)
    /// Stop every one-shot voice now (pause, sound switched off).
    case silence

    /// Peak gain parameter (0 for `bed`/`silence`), for tests.
    var gain: Float {
        switch self {
        case .noise(let spec): return spec.gain
        case .tone(let spec): return spec.gain
        case .ring(let spec): return spec.gain
        case .bubble(let spec): return spec.gain
        case .bed, .silence: return 0
        }
    }
}

// MARK: - DSP building blocks (audio thread)

/// Topology-preserving state-variable filter (Zavalishin), from Squish. Band-pass normalised to 0 dB at the centre.
private struct SynthSVF {
    var a1: Float = 0, a2: Float = 0, a3: Float = 0, k: Float = 1
    var ic1: Float = 0, ic2: Float = 0

    mutating func tune(cutoff: Float, q: Float, sampleRate: Float) {
        let f = min(max(cutoff, 20), sampleRate * 0.45)
        let g = tan(Float.pi * f / sampleRate)
        k = 1 / max(q, 0.1)
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }

    mutating func process(_ x: Float, _ mode: SynthFilterMode) -> Float {
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        switch mode {
        case .lowPass: return v2
        case .bandPass: return v1 * k
        case .highPass: return x - k * v1 - v2
        }
    }
}

private enum SynthVoiceKind {
    case noise, tone, ring, bubble
}

private struct SynthVoice {
    var active = false
    var kind: SynthVoiceKind = .noise
    var delay = 0
    var age = 0
    var attack = 1
    var length = 0
    var decayRate: Float = 1
    var level: Float = 1
    var gain: Float = 0
    // Noise.
    var filter = SynthSVF()
    var mode: SynthFilterMode = .bandPass
    var q: Float = 1
    var cutoff: Float = 1000
    var cutoffEnd: Float = 1000
    var sweepSamples = 0
    // Tone and bubble.
    var phase: Float = 0
    var frequency: Float = 0
    var startFrequency: Float = 0
    var endFrequency: Float = 0
    var glide = 1
    var harmonics = 1
    var vibratoPhase: Float = 0
    var vibratoRate: Float = 0
    var vibratoDepth: Float = 0
    var chirpPerSample: Float = 1
    // Ring (its partial state lives in the synth's bank at this voice's slot).
    var partialCount = 0
}

// MARK: - Synth

/// Brim's real-time synth, rendered inside an `AVAudioSourceNode` (mono Float32).
///
/// Threading: the main thread calls `send` (single producer); the audio thread calls `render` (single consumer).
/// Commands cross through a fixed-capacity single-producer/single-consumer ring whose two indices are atomics
/// (acquire/release), so the render path takes no locks, never allocates and never touches ARC.
/// Master chain: DC blocker → peak follower gain (ceiling 0.92) → tanh soft clip, so the output can never clip.
final class PourSynth: @unchecked Sendable {
    let sampleRate: Float

    static let voiceCount = 40
    static let maxPartials = 6
    static let queueCapacity = 512
    static let ceiling: Float = 0.92
    private static let partialStride = 5 // re, im, cos, sin, decay

    private let queue: UnsafeMutablePointer<SynthCommand>
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)
    private let peakBits = Atomic<UInt32>(0)
    private let renderCount = Atomic<Int>(0)

    // Audio-thread-only state below.
    private let voices: UnsafeMutablePointer<SynthVoice>
    private let bank: UnsafeMutablePointer<Float>
    private var bed = PourBed()
    private var target = PourBed()
    private var noiseState: UInt32 = 0x2545_F491
    private var retuneCounter = 0
    private var splash = SynthSVF()
    private var resonator = SynthSVF()
    private var fizzFilter = SynthSVF()
    private var hissFilter = SynthSVF()
    private var fizzLevel: Float = 0
    private var grainLevel: Float = 0
    private var turbulence: Float = 0.5
    private var turbulenceTarget: Float = 0.5
    private var turbulenceCountdown = 0
    private var dcIn: Float = 0
    private var dcOut: Float = 0
    private var envelope: Float = 0

    private let smoothing: Float
    private let turbulenceStep: Float
    private let fizzDecay: Float
    private let grainDecay: Float
    private let envelopeRelease: Float
    private let dcCoefficient: Float

    init(sampleRate: Float) {
        let rate: Float = sampleRate > 1000 ? sampleRate : 48_000
        self.sampleRate = rate
        queue = UnsafeMutablePointer<SynthCommand>.allocate(capacity: PourSynth.queueCapacity)
        queue.initialize(repeating: .silence, count: PourSynth.queueCapacity)
        voices = UnsafeMutablePointer<SynthVoice>.allocate(capacity: PourSynth.voiceCount)
        voices.initialize(repeating: SynthVoice(), count: PourSynth.voiceCount)
        let bankSize = PourSynth.voiceCount * PourSynth.maxPartials * PourSynth.partialStride
        bank = UnsafeMutablePointer<Float>.allocate(capacity: bankSize)
        bank.initialize(repeating: 0, count: bankSize)
        smoothing = 1 - exp(-1 / (0.02 * rate))
        turbulenceStep = 1 - exp(-1 / (0.025 * rate))
        fizzDecay = exp(-1 / (0.0012 * rate))
        grainDecay = exp(-1 / (0.004 * rate))
        envelopeRelease = exp(-1 / (0.08 * rate))
        dcCoefficient = 1 - 2 * Float.pi * 30 / rate
        splash.tune(cutoff: 2400, q: 0.7, sampleRate: rate)
        resonator.tune(cutoff: 180, q: 5, sampleRate: rate)
        fizzFilter.tune(cutoff: 4500, q: 0.7, sampleRate: rate)
        hissFilter.tune(cutoff: 5200, q: 0.6, sampleRate: rate)
    }

    deinit {
        queue.deinitialize(count: PourSynth.queueCapacity)
        queue.deallocate()
        voices.deinitialize(count: PourSynth.voiceCount)
        voices.deallocate()
        bank.deallocate()
    }

    // MARK: Main thread

    /// Queue a command (main thread only). Returns false if the queue is full (the command is dropped, never blocks).
    @discardableResult
    func send(_ command: SynthCommand) -> Bool {
        let write = writeIndex.load(ordering: .relaxed)
        let next = (write + 1) % PourSynth.queueCapacity
        guard next != readIndex.load(ordering: .acquiring) else { return false }
        queue[write] = command
        writeIndex.store(next, ordering: .releasing)
        return true
    }

    /// Loudest output sample so far (linear), for tests and diagnostics.
    var peak: Float { Float(bitPattern: peakBits.load(ordering: .relaxed)) }

    /// Render callbacks so far: if it stops climbing, the engine isn't pulling audio.
    var renderCallbacks: Int { renderCount.load(ordering: .relaxed) }

    // MARK: Audio thread

    func render(frames: Int, into out: UnsafeMutablePointer<Float>) {
        drain()
        var blockPeak: Float = 0
        for frame in 0..<frames {
            bed.approach(target, smoothing)
            retuneCounter += 1
            if retuneCounter >= 32 {
                retuneCounter = 0
                splash.tune(cutoff: bed.splashCenter, q: 0.7, sampleRate: sampleRate)
                resonator.tune(cutoff: bed.resonance, q: bed.resonanceQ, sampleRate: sampleRate)
                hissFilter.tune(cutoff: bed.hissCenter, q: 0.6, sampleRate: sampleRate)
            }

            var sample: Float = 0
            // The rush: one noise source through a broad splash band and the vessel's resonance.
            if bed.splashGain > 0.00002 || bed.resonanceGain > 0.00002 {
                turbulenceCountdown -= 1
                if turbulenceCountdown <= 0 {
                    turbulenceTarget = unitNoise()
                    turbulenceCountdown = Int(sampleRate * (0.02 + 0.03 * unitNoise())) + 1
                }
                turbulence += (turbulenceTarget - turbulence) * turbulenceStep
                let wobble = 1 + bed.turbulence * (2 * turbulence - 1)
                let n = nextNoise()
                let rush = splash.process(n, .bandPass) * bed.splashGain + resonator.process(n, .bandPass) * bed.resonanceGain
                sample += rush * wobble
            }
            // Fizz: sparse random clicks, high-passed.
            if bed.fizzGain > 0.00002 && (bed.fizzRate > 0.5 || fizzLevel > 0.0001) {
                if unitNoise() < bed.fizzRate / sampleRate { fizzLevel = 0.3 + 0.7 * unitNoise() }
                fizzLevel *= fizzDecay
                sample += fizzFilter.process(nextNoise() * fizzLevel, .highPass) * bed.fizzGain
            }
            // Sand: dry grainy hiss.
            if bed.hissGain > 0.00002 {
                if unitNoise() < 700 / sampleRate { grainLevel = 0.4 + 0.6 * unitNoise() }
                grainLevel *= grainDecay
                sample += hissFilter.process(nextNoise() * (0.3 + grainLevel), .bandPass) * bed.hissGain
            }
            for index in 0..<PourSynth.voiceCount where voices[index].active {
                sample += renderVoice(&voices[index], slot: index)
            }
            sample *= bed.master

            // DC blocker (30 Hz), then a peak follower that keeps the drive at or below the ceiling, then tanh.
            let blocked = sample - dcIn + dcCoefficient * dcOut
            dcIn = sample
            dcOut = blocked
            let magnitude = abs(blocked)
            envelope = max(magnitude, envelope * envelopeRelease)
            let drive = envelope > PourSynth.ceiling ? PourSynth.ceiling / envelope : 1
            var shaped = tanh(blocked * drive)
            if !shaped.isFinite {
                shaped = 0
                resetFilters()
            }
            shaped = min(max(shaped, -0.98), 0.98)
            blockPeak = max(blockPeak, abs(shaped))
            out[frame] = shaped
        }
        let previous = Float(bitPattern: peakBits.load(ordering: .relaxed))
        if blockPeak > previous { peakBits.store(blockPeak.bitPattern, ordering: .relaxed) }
        renderCount.store(renderCount.load(ordering: .relaxed) &+ 1, ordering: .relaxed)
    }

    private func drain() {
        var read = readIndex.load(ordering: .relaxed)
        let write = writeIndex.load(ordering: .acquiring)
        var handled = 0
        while read != write && handled < 128 {
            let command = queue[read]
            read = (read + 1) % PourSynth.queueCapacity
            handled += 1
            apply(command)
        }
        readIndex.store(read, ordering: .releasing)
    }

    private func apply(_ command: SynthCommand) {
        switch command {
        case .bed(let params):
            target = params
        case .silence:
            for index in 0..<PourSynth.voiceCount { voices[index].active = false }
            fizzLevel = 0
            grainLevel = 0
        case .noise, .tone, .ring, .bubble:
            start(command)
        }
    }

    private func resetFilters() {
        splash = SynthSVF()
        resonator = SynthSVF()
        fizzFilter = SynthSVF()
        hissFilter = SynthSVF()
        splash.tune(cutoff: bed.splashCenter, q: 0.7, sampleRate: sampleRate)
        resonator.tune(cutoff: bed.resonance, q: bed.resonanceQ, sampleRate: sampleRate)
        fizzFilter.tune(cutoff: 4500, q: 0.7, sampleRate: sampleRate)
        hissFilter.tune(cutoff: bed.hissCenter, q: 0.6, sampleRate: sampleRate)
        envelope = 0
        dcIn = 0
        dcOut = 0
        for index in 0..<PourSynth.voiceCount { voices[index].active = false }
    }

    private func nextNoise() -> Float {
        noiseState ^= noiseState << 13
        noiseState ^= noiseState >> 17
        noiseState ^= noiseState << 5
        return Float(Int32(bitPattern: noiseState)) / Float(Int32.max)
    }

    private func unitNoise() -> Float {
        (nextNoise() + 1) * 0.5
    }

    private func start(_ command: SynthCommand) {
        var slot = -1
        var oldest = -1
        var oldestAge = -1
        for index in 0..<PourSynth.voiceCount {
            if !voices[index].active {
                slot = index
                break
            }
            if voices[index].age > oldestAge {
                oldestAge = voices[index].age
                oldest = index
            }
        }
        if slot < 0 { slot = oldest }
        guard slot >= 0 else { return }
        var voice = SynthVoice()
        voice.active = true
        switch command {
        case .noise(let spec):
            voice.kind = .noise
            voice.delay = Int(max(spec.delay, 0) * sampleRate)
            voice.attack = max(Int(spec.attack * sampleRate), 1)
            voice.decayRate = exp(-1 / max(spec.decay * sampleRate, 1))
            voice.length = voice.attack + Int(spec.decay * sampleRate * 7)
            voice.gain = spec.gain
            voice.mode = spec.mode
            voice.q = spec.q
            voice.cutoff = spec.cutoff
            voice.cutoffEnd = spec.cutoffEnd
            voice.sweepSamples = abs(spec.cutoffEnd - spec.cutoff) > 1 ? max(Int(spec.sweep * sampleRate), 1) : 0
            voice.filter.tune(cutoff: spec.cutoff, q: spec.q, sampleRate: sampleRate)
        case .tone(let spec):
            voice.kind = .tone
            voice.delay = Int(max(spec.delay, 0) * sampleRate)
            voice.attack = max(Int(spec.attack * sampleRate), 1)
            voice.length = max(Int(spec.duration * sampleRate), voice.attack + 1)
            voice.decayRate = exp(-1 / max(spec.decay * sampleRate, 1))
            voice.gain = spec.gain
            voice.startFrequency = spec.start
            voice.endFrequency = spec.end
            voice.glide = max(Int(spec.glide * sampleRate), 1)
            voice.harmonics = min(max(spec.harmonics, 1), 8)
            voice.vibratoRate = spec.vibratoRate
            voice.vibratoDepth = spec.vibratoDepth
        case .bubble(let spec):
            voice.kind = .bubble
            voice.delay = Int(max(spec.delay, 0) * sampleRate)
            voice.attack = max(Int(0.0015 * sampleRate), 1)
            voice.decayRate = exp(-1 / max(spec.decay * sampleRate, 1))
            voice.length = voice.attack + Int(spec.decay * sampleRate * 6)
            voice.gain = spec.gain
            voice.frequency = min(max(spec.frequency, 40), sampleRate * 0.4)
            voice.chirpPerSample = pow(max(spec.chirp, 0.25), 1 / Float(max(voice.length, 1)))
        case .ring(let spec):
            voice.kind = .ring
            voice.delay = Int(max(spec.delay, 0) * sampleRate)
            voice.attack = max(Int(0.0005 * sampleRate), 1)
            voice.decayRate = 1
            voice.length = min(Int(spec.decay * sampleRate * 7), Int(sampleRate * 4))
            voice.gain = 1
            configureRing(spec, slot: slot, voice: &voice)
        case .bed, .silence:
            return
        }
        voices[slot] = voice
    }

    private static func ratio(_ kind: SynthRingKind, _ n: Int) -> Float {
        switch kind {
        case .glass:
            switch n {
            case 0: return 1
            case 1: return 2.32
            case 2: return 4.25
            case 3: return 6.63
            case 4: return 9.38
            default: return 12.1
            }
        case .ceramic:
            switch n {
            case 0: return 1
            case 1: return 1.62
            case 2: return 2.41
            case 3: return 3.37
            case 4: return 4.48
            default: return 5.9
            }
        case .wood:
            switch n {
            case 0: return 1
            case 1: return 2.6
            case 2: return 3.9
            case 3: return 5.4
            case 4: return 6.9
            default: return 8.6
            }
        case .bell:
            switch n {
            case 0: return 1
            case 1: return 2.0
            case 2: return 2.4
            case 3: return 3.0
            case 4: return 4.07
            default: return 5.2
            }
        }
    }

    private func configureRing(_ spec: SynthRing, slot: Int, voice: inout SynthVoice) {
        let count = min(max(spec.partials, 1), PourSynth.maxPartials)
        voice.partialCount = count
        let brightness = min(max(spec.brightness, 0.05), 0.98)
        var total: Float = 0
        for n in 0..<count { total += pow(brightness, Float(n)) }
        var jitter = spec.seed | 1
        let base = slot * PourSynth.maxPartials * PourSynth.partialStride
        for n in 0..<count {
            jitter ^= jitter << 13
            jitter ^= jitter >> 17
            jitter ^= jitter << 5
            let detune: Float = n == 0 ? 1 : 1 + 0.015 * (Float(jitter % 2001) / 1000 - 1)
            let frequency = spec.fundamental * PourSynth.ratio(spec.kind, n) * detune
            let offset = base + n * PourSynth.partialStride
            guard frequency > 20, frequency < sampleRate * 0.45 else {
                bank[offset] = 0
                bank[offset + 1] = 0
                bank[offset + 2] = 1
                bank[offset + 3] = 0
                bank[offset + 4] = 0
                continue
            }
            var tau = spec.decay / (1 + 0.7 * Float(n))
            if frequency > 2500 && frequency < 4500 && n > 0 { tau *= 0.5 } // no lingering screech in the ear's peak
            let omega = 2 * Float.pi * frequency / sampleRate
            bank[offset] = spec.gain * pow(brightness, Float(n)) / total * 1.6
            bank[offset + 1] = 0
            bank[offset + 2] = cos(omega)
            bank[offset + 3] = sin(omega)
            bank[offset + 4] = exp(-1 / max(tau * sampleRate, 1))
        }
    }

    private func renderVoice(_ voice: inout SynthVoice, slot: Int) -> Float {
        if voice.delay > 0 {
            voice.delay -= 1
            return 0
        }
        let age = voice.age
        voice.age += 1
        if age >= voice.length {
            voice.active = false
            return 0
        }
        let envelope: Float
        if age < voice.attack {
            envelope = Float(age) / Float(voice.attack)
        } else {
            voice.level *= voice.decayRate
            envelope = voice.level
        }
        if envelope < 0.0003 && age > voice.attack {
            voice.active = false
            return 0
        }
        let twoPi = 2 * Float.pi
        switch voice.kind {
        case .noise:
            if voice.sweepSamples > 0 && age % 32 == 0 {
                let progress = min(Float(age) / Float(voice.sweepSamples), 1)
                let cutoff = voice.cutoff * pow(voice.cutoffEnd / max(voice.cutoff, 1), progress)
                voice.filter.tune(cutoff: cutoff, q: voice.q, sampleRate: sampleRate)
            }
            return voice.filter.process(nextNoise(), voice.mode) * envelope * voice.gain
        case .tone:
            let progress = min(Float(age) / Float(voice.glide), 1)
            var frequency = voice.startFrequency + (voice.endFrequency - voice.startFrequency) * progress
            if voice.vibratoDepth > 0 {
                voice.vibratoPhase += twoPi * voice.vibratoRate / sampleRate
                if voice.vibratoPhase > twoPi { voice.vibratoPhase -= twoPi }
                frequency *= 1 + voice.vibratoDepth * sin(voice.vibratoPhase)
            }
            voice.phase += twoPi * frequency / sampleRate
            if voice.phase > twoPi { voice.phase -= twoPi }
            var value: Float = 0
            let limit = sampleRate * 0.45
            var harmonic = 1
            while harmonic <= voice.harmonics {
                if frequency * Float(harmonic) < limit {
                    value += sin(voice.phase * Float(harmonic)) / Float(harmonic)
                }
                harmonic += 1
            }
            // A gentle release over the last 30 ms so long tones never click off.
            let left = voice.length - age
            let release = min(Float(left) / (0.03 * sampleRate), 1)
            return value * envelope * voice.gain * release
        case .bubble:
            voice.frequency *= voice.chirpPerSample
            voice.phase += twoPi * voice.frequency / sampleRate
            if voice.phase > twoPi { voice.phase -= twoPi }
            return sin(voice.phase) * envelope * voice.gain
        case .ring:
            let base = slot * PourSynth.maxPartials * PourSynth.partialStride
            var sum: Float = 0
            for n in 0..<voice.partialCount {
                let o = base + n * PourSynth.partialStride
                let re = bank[o]
                let im = bank[o + 1]
                let c = bank[o + 2]
                let s = bank[o + 3]
                let d = bank[o + 4]
                let newIm = (re * s + im * c) * d
                bank[o] = (re * c - im * s) * d
                bank[o + 1] = newIm
                sum += newIm
            }
            return sum * envelope
        }
    }
}
