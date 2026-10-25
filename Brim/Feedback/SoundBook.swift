import Foundation

/// Tiny deterministic RNG for sound variation (main thread). Named to avoid clashing with Core's seeded generator.
struct FeelDice {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0…1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// Uniform in lower…upper.
    mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * unit()
    }

    mutating func seed32() -> UInt32 {
        UInt32(truncatingIfNeeded: next()) | 1
    }
}

/// How each drink sounds while it pours (GAME-DESIGN §5 liquid personalities).
struct PourTexture: Sendable, Equatable {
    /// Centre of the broad splash band (Hz): darker for thick drinks.
    var splashCenter: Float
    var splashMix: Float
    var resonanceMix: Float
    var resonanceQ: Float
    /// Multiplies the vessel resonance for glug pitch (thick drinks glug lower).
    var pitchScale: Double
    /// Glug pop decay (s): thick drinks are slower, rounder pops.
    var glugDecay: Float
    /// Glug pitch rise over the pop.
    var glugChirp: Float
    var glugGain: Float
    /// Minimum time between audible glugs (s): thick drinks glug slower.
    var glugGap: Double
    /// 0…1 soda fizz.
    var fizz: Float
    /// 0…1 dry sand hiss (sand has no glugs, it rattles).
    var hiss: Float
    var turbulence: Float
}

/// Pure sound design: every recipe returns synth commands; nothing here touches audio hardware, so it is unit-tested.
enum SoundBook {
    // MARK: The filling-vessel resonance

    /// Empty glass pitch and brim pitch of the singing pour (Hz).
    static let emptyHz = 180.0
    static let brimHz = 1600.0
    /// Shortest air column considered (fraction of the glass), so the pitch stays finite at the brim.
    static let minColumn = 0.08

    /// The resonant pitch of the air column above the liquid: L = 1 − fill, f = f0 / L (quarter-wave/Helmholtz shape),
    /// with the exponent eased so the whole range maps from `emptyHz` (empty) to `brimHz` (L = 0.08, at the brim).
    /// f = 180 · L^(−k), k = ln(1600/180) / ln(1/0.08) ≈ 0.87. Monotonic: the pitch audibly rises as the glass fills.
    static func resonanceHz(activeFill: Double) -> Double {
        let fill = activeFill.isFinite ? min(max(activeFill, 0), 1) : 0
        let column = max(1 - fill, minColumn)
        let k = log(brimHz / emptyHz) / log(1 / minColumn)
        return emptyHz * pow(column, -k)
    }

    // MARK: The streak scale

    /// Major pentatonic degrees (semitones) the Perfect ting climbs, one step per Perfect in a streak.
    static let pentatonic: [Int] = [0, 2, 4, 7, 9, 12, 14, 16]
    /// The first Perfect's ting (E6).
    static let tingBaseHz = 1318.51

    /// Ting fundamental for the n-th Perfect of a streak (1-based; 0 or less plays the first note).
    static func tingFrequency(streak: Int) -> Double {
        let index = min(max(streak - 1, 0), pentatonic.count - 1)
        return tingBaseHz * pow(2, Double(pentatonic[index]) / 12)
    }

    // MARK: Liquids

    static func texture(for liquid: LiquidID) -> PourTexture {
        let still = PourTexture(splashCenter: 2400, splashMix: 1, resonanceMix: 1, resonanceQ: 5, pitchScale: 1,
                                glugDecay: 0.045, glugChirp: 1.45, glugGain: 1, glugGap: 0.045, fizz: 0, hiss: 0,
                                turbulence: 0.3)
        switch liquid {
        case .cola, .rootBeer, .creamSoda:
            var soda = still
            soda.splashCenter = 3000
            soda.fizz = 1
            soda.turbulence = 0.35
            return soda
        case .milkshake, .berrySmoothie:
            var thick = still
            thick.splashCenter = 1300
            thick.splashMix = 0.65
            thick.resonanceMix = 0.8
            thick.resonanceQ = 3.5
            thick.pitchScale = 0.78
            thick.glugDecay = 0.085
            thick.glugChirp = 1.2
            thick.glugGain = 1.15
            thick.glugGap = 0.11
            thick.turbulence = 0.2
            return thick
        case .honey, .mapleSyrup:
            var syrup = still
            syrup.splashCenter = 900
            syrup.splashMix = 0.45
            syrup.resonanceMix = 0.6
            syrup.resonanceQ = 3
            syrup.pitchScale = 0.68
            syrup.glugDecay = 0.11
            syrup.glugChirp = 1.12
            syrup.glugGain = 1.2
            syrup.glugGap = 0.16
            syrup.turbulence = 0.15
            return syrup
        case .sand:
            var sand = still
            sand.splashCenter = 4200
            sand.splashMix = 0.35
            sand.resonanceMix = 0.25
            sand.resonanceQ = 2.5
            sand.glugGap = 0.03
            sand.hiss = 1
            sand.turbulence = 0.45
            return sand
        default:
            return still
        }
    }

    // MARK: The Perfect-band shimmer (REVIEW-1 P2-8)

    /// Perfect-band half width (fraction of interior height) assumed until the glass reveals its own.
    static let defaultBand = 0.03
    /// Peak level of the shimmer (before master): a faint, clearly pitched layer over the rush.
    static let shimmerPeak: Float = 0.055

    /// 0…1 shimmer level for the projected distance to the line: silent beyond 1.3 bands, swelling (smoothstep)
    /// through the band edge (≈ 0.4 there), full in the inner 60 % of the band. Symmetric: past the line it fades too.
    static func shimmerLevel(projectedDistance: Double, band: Double) -> Double {
        guard projectedDistance.isFinite else { return 0 }
        let b = band.isFinite && band > 0.005 ? band : defaultBand
        let x = abs(projectedDistance) / b
        if x >= 1.3 { return 0 }
        if x <= 0.6 { return 1 }
        let u = (1.3 - x) / 0.7
        return u * u * (3 - 2 * u)
    }

    /// Line opacity below which the line counts as faded (Potion Shop, late Daily glasses).
    static let fadedLineOpacity = 0.5

    /// REVIEW-5 P1-1: the shimmer and the lock-in tink reveal where the line is. On a glass whose line has faded
    /// (opacity < 0.5) they stay silent, or sound would cancel the fading-line mechanic. NaN counts as faded.
    static func lineCuesAudible(lineOpacity: Double) -> Bool {
        lineOpacity >= fadedLineOpacity
    }

    /// The shimmer sings the note the next Perfect will ting, an octave down (the reward then resolves it).
    static func shimmerHz(streak: Int) -> Double {
        tingFrequency(streak: max(streak, 0) + 1) / 2
    }

    /// The continuous pour layers for this frame. `foam` is the active glass's head as a fraction of its interior
    /// height (fizz keeps crackling while it settles). Levels follow √(rush) for a perceptually even swell.
    /// `band` is the Perfect band (fraction of interior height) and `streak` the current streak, for the shimmer.
    /// `lineOpacity` is the active glass's line opacity: once the line has faded (`lineCuesAudible`), the shimmer stays
    /// silent, or it would tell the player exactly when to stop (REVIEW-5 P1-1).
    static func pourBed(telemetry: PourTelemetry, foam: Double, texture: PourTexture, master: Float,
                        band: Double = defaultBand, streak: Int = 0, lineOpacity: Double = 1) -> PourBed {
        let flow = clamp01(telemetry.flow)
        let landing = clamp01(telemetry.landingRate)
        let rush = 0.35 * flow + 0.65 * landing
        let level = Float(rush.squareRoot())
        var bed = PourBed()
        bed.master = master
        bed.splashGain = level * 0.18 * texture.splashMix
        bed.splashCenter = texture.splashCenter * (0.9 + 0.2 * Float(flow))
        bed.resonance = Float(resonanceHz(activeFill: telemetry.activeFill))
        bed.resonanceGain = Float(landing.squareRoot()) * 1.1 * texture.resonanceMix
        bed.resonanceQ = texture.resonanceQ
        if texture.fizz > 0 {
            let head = Float(clamp01(foam))
            bed.fizzRate = texture.fizz * (Float(flow) * 900 + head * 2600)
            bed.fizzGain = bed.fizzRate > 1 ? 0.22 * texture.fizz : 0
        }
        if texture.hiss > 0 {
            bed.hissGain = texture.hiss * level * 0.22
            bed.hissCenter = 5200
        }
        bed.turbulence = texture.turbulence
        // The shimmer only matters while the pour is still deciding the level (pouring, or the stream still landing);
        // once everything has landed it fades and the lock-in tink takes over.
        let live = (flow > 0.004 || landing > 0.01) && lineCuesAudible(lineOpacity: lineOpacity)
        let shimmer = live ? shimmerLevel(projectedDistance: telemetry.projectedDistanceToLine, band: band) : 0
        bed.shimmerGain = Float(shimmer) * shimmerPeak
        bed.shimmerHz = Float(shimmerHz(streak: streak))
        return bed
    }

    /// No pour layers, master kept: menus, pause cards and one-shots stay audible (sound off is the engine's job).
    static func idleBed(master: Float) -> PourBed {
        var bed = PourBed()
        bed.master = master
        bed.turbulence = 0
        return bed
    }

    /// The pour bed and the pour's own one-shots (pour start, glugs, splashes) stay quiet while the flat gate is shut:
    /// at a run's start nothing pours anyway, and after a resume (ROUND-3: every resume re-arms the gate) nothing
    /// sounds until the player has laid the phone flat and the latch clicks.
    static func pourIsAudible(needsFlat: Bool) -> Bool {
        !needsFlat
    }

    // MARK: Pausing

    /// Closing the phone paused the run: a soft, falling breath of air (two filtered-noise sweeps, ~0.4 s), like a lid
    /// settling. Quieter than any judgement; nothing plays on resume (the flat latch is the cue that play is back).
    static func pauseWhoosh() -> [SynthCommand] {
        [
            .noise(SynthNoise(.bandPass, cutoff: 1900, to: 520, sweep: 0.34, q: 0.8, attack: 0.07, decay: 0.16,
                              gain: 0.075)),
            .noise(SynthNoise(.lowPass, cutoff: 700, to: 260, sweep: 0.3, q: 0.7, attack: 0.05, decay: 0.14,
                              gain: 0.05, delay: 0.04)),
        ]
    }

    // MARK: Pour moments

    /// One glug: a resonant bubble pop at the vessel's current pitch (it rises as the glass fills), plus a tiny wet tick.
    static func glug(intensity: Double, fill: Double, texture: PourTexture, dice: inout FeelDice) -> [SynthCommand] {
        let strength = Float(0.45 + 0.55 * clamp01(intensity))
        if texture.hiss > 0 {
            // Sand doesn't glug: a soft dry "shff" of grains.
            return [.noise(SynthNoise(.highPass, cutoff: 3200, q: 0.7, attack: 0.004, decay: 0.03,
                                      gain: 0.05 * strength))]
        }
        let pitch = resonanceHz(activeFill: fill) * texture.pitchScale * dice.range(0.93, 1.08)
        let decay = texture.glugDecay * Float(dice.range(0.8, 1.2))
        return [
            .bubble(SynthBubble(frequency: Float(pitch), chirp: texture.glugChirp, decay: decay,
                                gain: 0.24 * texture.glugGain * strength)),
            .noise(SynthNoise(.bandPass, cutoff: Float(min(pitch * 2.2, 9000)), q: 2, attack: 0.001, decay: 0.006,
                              gain: 0.05 * strength)),
        ]
    }

    /// The jug starts to pour: a soft glass knock.
    static func pourStart(dice: inout FeelDice) -> [SynthCommand] {
        [.ring(SynthRing(.glass, fundamental: Float(dice.range(1450, 1600)), partials: 3, decay: 0.035,
                         brightness: 0.4, gain: 0.06, seed: dice.seed32()))]
    }

    /// The first splash of a stream landing in liquid (rate-limited by the director).
    static func splashInGlass(strength: Double) -> [SynthCommand] {
        let s = Float(clamp01(strength))
        return [.noise(SynthNoise(.bandPass, cutoff: 2600, to: 1500, sweep: 0.05, q: 0.9, attack: 0.002, decay: 0.035,
                                  gain: 0.06 * (0.4 + 0.6 * s)))]
    }

    /// Liquid hitting the counter: a wet slap.
    static func splashOnCounter(strength: Double) -> [SynthCommand] {
        let s = Float(clamp01(strength))
        return [.noise(SynthNoise(.lowPass, cutoff: 1100, to: 450, sweep: 0.08, q: 0.9, attack: 0.002, decay: 0.05,
                                  gain: 0.14 * (0.4 + 0.6 * s)))]
    }

    // MARK: Judgements

    /// Perfect: a bright glass ting (inharmonic partials 1, 2.32, 4.25, 6.63), climbing the pentatonic with the streak.
    static func perfect(streak: Int, dice: inout FeelDice) -> [SynthCommand] {
        let f = Float(tingFrequency(streak: streak))
        // Higher notes sit in the ear's most sensitive band: a touch quieter.
        let gain: Float = 0.34 * (1 - 0.04 * Float(min(max(streak - 1, 0), 7)))
        return [
            .noise(SynthNoise(.highPass, cutoff: 6500, q: 0.7, attack: 0.0005, decay: 0.004, gain: 0.08)),
            .ring(SynthRing(.glass, fundamental: f, partials: 5, decay: 0.32, brightness: 0.62, gain: gain,
                            seed: dice.seed32())),
            // A quiet octave shimmer just after: the sparkle.
            .ring(SynthRing(.glass, fundamental: f * 2, partials: 2, decay: 0.14, brightness: 0.4, gain: 0.07,
                            delay: 0.05, seed: dice.seed32())),
        ]
    }

    /// Great / Good: softer, shorter tings at the scale's root and a fourth below.
    static func softTing(great: Bool, dice: inout FeelDice) -> [SynthCommand] {
        let f = Float(tingBaseHz * (great ? 1 : pow(2, -5.0 / 12)))
        return [.ring(SynthRing(.glass, fundamental: f, partials: great ? 4 : 3, decay: great ? 0.2 : 0.14,
                                brightness: 0.5, gain: great ? 0.2 : 0.14, seed: dice.seed32()))]
    }

    /// Short: a low, soft "hmm" (two descending soft tones).
    static func short() -> [SynthCommand] {
        [
            .tone(SynthTone(start: 392, end: 370, glide: 0.2, duration: 0.26, attack: 0.04, decay: 0.16, gain: 0.09,
                            harmonics: 3, vibratoRate: 5, vibratoDepth: 0.008)),
            .tone(SynthTone(start: 330, end: 300, glide: 0.35, duration: 0.42, attack: 0.05, decay: 0.25, gain: 0.08,
                            harmonics: 3, vibratoRate: 5, vibratoDepth: 0.01, delay: 0.22)),
        ]
    }

    /// Over (round 5, decision 4: past the Good band, nothing over the rim): a soft, puzzled "hm-mm?". A low tone that
    /// lifts a whole step (where Short's sinks), then a slightly higher one that sags back with a slow wobble, over a
    /// faint low slosh of a brimming glass. No burst, no slap, no drips: as quiet as Short and nothing like the spill.
    static func over() -> [SynthCommand] {
        [
            .tone(SynthTone(start: 311.1, end: 349.2, glide: 0.16, duration: 0.22, attack: 0.03, decay: 0.14,
                            gain: 0.085, harmonics: 3, vibratoRate: 5, vibratoDepth: 0.006)),
            .tone(SynthTone(start: 370, end: 349.2, glide: 0.3, duration: 0.42, attack: 0.05, decay: 0.24,
                            gain: 0.075, harmonics: 2, vibratoRate: 3.5, vibratoDepth: 0.018, delay: 0.2)),
            .noise(SynthNoise(.lowPass, cutoff: 520, to: 380, sweep: 0.3, q: 0.9, attack: 0.05, decay: 0.12,
                              gain: 0.03, delay: 0.02)),
        ]
    }

    /// The jug ran dry mid-pour (round 5, decision 3: no refill mid-glass, the stream just stops): the last gulps of
    /// air into an empty jug, "glug… glg… g…", each lower, slower and softer, a faint hollow breath, then a dry tap of
    /// the empty ceramic. Soft (under any judgement): "that's all there is", not an alarm.
    static func glugOut(dice: inout FeelDice) -> [SynthCommand] {
        let base = dice.range(300, 340)
        let times: [Float] = [0, 0.13, 0.3, 0.52]
        let ratios: [Double] = [1, 0.88, 0.76, 0.66]
        let gains: [Float] = [0.16, 0.13, 0.1, 0.07]
        let decays: [Float] = [0.06, 0.07, 0.085, 0.1]
        var commands: [SynthCommand] = []
        for index in 0..<times.count {
            let frequency = Float(base * ratios[index] * dice.range(0.97, 1.03))
            commands.append(.bubble(SynthBubble(frequency: frequency, chirp: 1.35, decay: decays[index],
                                                gain: gains[index], delay: times[index])))
        }
        commands.append(.noise(SynthNoise(.bandPass, cutoff: 900, to: 500, sweep: 0.5, q: 0.8, attack: 0.04,
                                          decay: 0.16, gain: 0.025)))
        commands.append(.ring(SynthRing(.ceramic, fundamental: Float(dice.range(380, 420)), partials: 3, decay: 0.05,
                                        brightness: 0.3, gain: 0.07, delay: 0.72, seed: dice.seed32())))
        return commands
    }

    /// Spill (played once, the instant the glass overflows — Core judges it live): the lip breaks in a wet burst, a
    /// low slap of liquid on the counter, the sheet running down the glass (~0.6 s, as Scene draws it), a little
    /// falling "uh-oh", then drip plinks.
    static func spill(dice: inout FeelDice) -> [SynthCommand] {
        var commands: [SynthCommand] = [
            .noise(SynthNoise(.bandPass, cutoff: 1500, to: 500, sweep: 0.3, q: 0.7, attack: 0.004, decay: 0.18,
                              gain: 0.3)),
            .noise(SynthNoise(.lowPass, cutoff: 800, q: 0.8, attack: 0.002, decay: 0.07, gain: 0.2)),
            .noise(SynthNoise(.lowPass, cutoff: 280, to: 140, sweep: 0.12, q: 0.9, attack: 0.003, decay: 0.09,
                              gain: 0.24, delay: 0.05)),
            .noise(SynthNoise(.bandPass, cutoff: 950, to: 600, sweep: 0.6, q: 0.8, attack: 0.06, decay: 0.22,
                              gain: 0.07, delay: 0.04)),
            .tone(SynthTone(start: 523.3, end: 493.9, glide: 0.12, duration: 0.16, attack: 0.01, decay: 0.1,
                            gain: 0.045, harmonics: 2, delay: 0.14)),
            .tone(SynthTone(start: 392, end: 349.2, glide: 0.2, duration: 0.32, attack: 0.015, decay: 0.18,
                            gain: 0.045, harmonics: 2, vibratoRate: 5, vibratoDepth: 0.006, delay: 0.29)),
        ]
        let dripTimes: [Float] = [0.36, 0.62, 0.94, 1.34]
        for (index, time) in dripTimes.enumerated() {
            commands.append(.bubble(SynthBubble(frequency: Float(dice.range(1700, 2600)), chirp: 1.7, decay: 0.035,
                                                gain: 0.13 - 0.02 * Float(index), delay: time)))
        }
        return commands
    }

    /// Lock-in (the stream finished landing with the top inside the Perfect band): a tiny glassy "tink", the octave
    /// of the Perfect note that is about to confirm it, kept quiet and short so the ting stays the reward.
    static func lockedIn(streak: Int, dice: inout FeelDice) -> [SynthCommand] {
        var frequency = tingFrequency(streak: max(streak, 0) + 1) * 2
        while frequency > 4200 { frequency /= 2 }
        return [
            .noise(SynthNoise(.highPass, cutoff: 7500, q: 0.7, attack: 0.0004, decay: 0.0025, gain: 0.018)),
            .ring(SynthRing(.glass, fundamental: Float(frequency), partials: 2, decay: 0.07, brightness: 0.28,
                            gain: 0.05, seed: dice.seed32())),
        ]
    }

    /// The flat gate opened (phone laid flat): a soft two-stage latch, "thk-tk", low and woody, barely there.
    static func flatArmed() -> [SynthCommand] {
        [
            .ring(SynthRing(.wood, fundamental: 820, partials: 3, decay: 0.016, brightness: 0.35, gain: 0.075)),
            .noise(SynthNoise(.lowPass, cutoff: 650, q: 0.7, attack: 0.0008, decay: 0.012, gain: 0.045)),
            .ring(SynthRing(.wood, fundamental: 1230, partials: 2, decay: 0.012, brightness: 0.3, gain: 0.04,
                            delay: 0.048)),
        ]
    }

    /// Serve: the coaster slides out (filtered noise sweep) and the glass gives a soft clink as it goes.
    static func serve(dice: inout FeelDice, delay: Float = 0.3) -> [SynthCommand] {
        [
            .noise(SynthNoise(.bandPass, cutoff: 500, to: 1500, sweep: 0.35, q: 1.2, attack: 0.06, decay: 0.13,
                              gain: 0.08, delay: delay)),
            .ring(SynthRing(.glass, fundamental: Float(dice.range(2300, 2500)), partials: 3, decay: 0.06,
                            brightness: 0.45, gain: 0.06, delay: delay + 0.32, seed: dice.seed32())),
        ]
    }

    /// A glass arrives on the counter: a soft glass knock.
    static func arrival(dice: inout FeelDice) -> [SynthCommand] {
        [
            .ring(SynthRing(.glass, fundamental: Float(dice.range(1050, 1250)), partials: 4, decay: 0.05,
                            brightness: 0.35, gain: 0.1, seed: dice.seed32())),
            .noise(SynthNoise(.lowPass, cutoff: 420, q: 0.8, attack: 0.001, decay: 0.03, gain: 0.1)),
        ]
    }

    /// The empty jug is swapped: a ceramic clunk.
    static func jugSwapped(dice: inout FeelDice) -> [SynthCommand] {
        [
            .ring(SynthRing(.ceramic, fundamental: Float(dice.range(400, 440)), partials: 5, decay: 0.07,
                            brightness: 0.45, gain: 0.22, seed: dice.seed32())),
            .noise(SynthNoise(.lowPass, cutoff: 320, q: 0.8, attack: 0.001, decay: 0.045, gain: 0.2)),
        ]
    }

    /// Rush refill (a Perfect tops the jug up): three quick rising bubbles.
    static func refill() -> [SynthCommand] {
        [
            .bubble(SynthBubble(frequency: 480, chirp: 1.5, decay: 0.04, gain: 0.12)),
            .bubble(SynthBubble(frequency: 620, chirp: 1.5, decay: 0.04, gain: 0.12, delay: 0.07)),
            .bubble(SynthBubble(frequency: 800, chirp: 1.5, decay: 0.05, gain: 0.12, delay: 0.14)),
        ]
    }

    /// Rush: the jug ran dry.
    static func jugEmpty() -> [SynthCommand] {
        [.tone(SynthTone(start: 520, end: 260, glide: 0.5, duration: 0.6, attack: 0.02, decay: 0.3, gain: 0.08,
                         harmonics: 2))]
    }

    /// The multiplier steps up: a little sparkle.
    static func multiplier(_ value: Int) -> [SynthCommand] {
        let step = Float(min(max(value, 1), 5))
        return [
            .ring(SynthRing(.bell, fundamental: 2093 + 120 * step, partials: 3, decay: 0.12, brightness: 0.4,
                            gain: 0.07)),
            .ring(SynthRing(.bell, fundamental: 2637 + 150 * step, partials: 3, decay: 0.14, brightness: 0.4,
                            gain: 0.07, delay: 0.07)),
        ]
    }

    /// End of a run: a little fanfare (3–4 note arpeggio) when cleared, a gentle two-note otherwise.
    static func finished(cleared: Bool) -> [SynthCommand] {
        if cleared {
            let c6 = 1046.5
            let semitones: [Double] = [0, 4, 7, 12]
            let delays: [Float] = [0, 0.11, 0.22, 0.36]
            var commands: [SynthCommand] = []
            for index in 0..<semitones.count {
                let last = index == semitones.count - 1
                let frequency = Float(c6 * pow(2, semitones[index] / 12))
                commands.append(.ring(SynthRing(.bell, fundamental: frequency, partials: 4, decay: last ? 0.6 : 0.3,
                                                brightness: 0.5, gain: last ? 0.22 : 0.17, delay: delays[index],
                                                seed: UInt32(index + 3))))
            }
            return commands
        }
        return [
            .ring(SynthRing(.bell, fundamental: 784, partials: 3, decay: 0.3, brightness: 0.4, gain: 0.12)),
            .ring(SynthRing(.bell, fundamental: 659.3, partials: 3, decay: 0.4, brightness: 0.4, gain: 0.11,
                            delay: 0.24)),
        ]
    }

    // MARK: UI

    /// A soft wooden click.
    static func uiTap() -> [SynthCommand] {
        [
            .ring(SynthRing(.wood, fundamental: 1500, partials: 3, decay: 0.012, brightness: 0.4, gain: 0.12)),
            .noise(SynthNoise(.highPass, cutoff: 3000, q: 0.7, attack: 0.0005, decay: 0.003, gain: 0.05)),
        ]
    }

    /// Two wooden clicks, the second higher.
    static func uiConfirm() -> [SynthCommand] {
        var commands = uiTap()
        commands.append(.ring(SynthRing(.wood, fundamental: 2000, partials: 3, decay: 0.014, brightness: 0.4,
                                        gain: 0.12, delay: 0.06)))
        return commands
    }

    // MARK: Helpers

    static func clamp01(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}
