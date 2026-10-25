import Foundation
import Testing
@testable import Brim

struct FeedbackTests {
    @Test func resonancePitchRisesMonotonicallyAsTheGlassFills() {
        var previous = 0.0
        for step in 0...100 {
            let hz = SoundBook.resonanceHz(activeFill: Double(step) / 100)
            #expect(hz >= previous)
            previous = hz
        }
        #expect(abs(SoundBook.resonanceHz(activeFill: 0) - 180) < 0.5)
        #expect(abs(SoundBook.resonanceHz(activeFill: 1) - 1600) < 1)
        #expect(SoundBook.resonanceHz(activeFill: 0.5) > 300)
        #expect(SoundBook.resonanceHz(activeFill: 0.5) < 600)
        // Strictly rising across the playable range.
        #expect(SoundBook.resonanceHz(activeFill: 0.8) > SoundBook.resonanceHz(activeFill: 0.7))
        // Out-of-range input is clamped, never NaN.
        #expect(SoundBook.resonanceHz(activeFill: -3) == SoundBook.resonanceHz(activeFill: 0))
        #expect(SoundBook.resonanceHz(activeFill: Double.nan).isFinite)
    }

    @Test func glugPitchFollowsTheFill() {
        var dice = FeelDice(seed: 7)
        let texture = SoundBook.texture(for: .water)
        let low = SoundBook.glug(intensity: 0.5, fill: 0.1, texture: texture, dice: &dice)
        let high = SoundBook.glug(intensity: 0.5, fill: 0.8, texture: texture, dice: &dice)
        var lowHz: Float = 0
        var highHz: Float = 0
        if case .bubble(let spec)? = low.first { lowHz = spec.frequency }
        if case .bubble(let spec)? = high.first { highHz = spec.frequency }
        #expect(lowHz > 0)
        #expect(highHz > lowHz * 2)
        // Thick drinks glug lower than water at the same fill.
        var thickDice = FeelDice(seed: 7)
        let honey = SoundBook.glug(intensity: 0.5, fill: 0.1, texture: SoundBook.texture(for: .honey), dice: &thickDice)
        var honeyHz: Float = 0
        if case .bubble(let spec)? = honey.first { honeyHz = spec.frequency }
        #expect(honeyHz > 0)
        #expect(honeyHz < lowHz)
    }

    @Test func streakTingClimbsThePentatonic() {
        var previous = 0.0
        for streak in 1...SoundBook.pentatonic.count {
            let hz = SoundBook.tingFrequency(streak: streak)
            #expect(hz > previous)
            previous = hz
        }
        #expect(SoundBook.tingFrequency(streak: 0) == SoundBook.tingFrequency(streak: 1))
        #expect(SoundBook.tingFrequency(streak: 50) == previous)
        #expect(SoundBook.tingFrequency(streak: 1) > 1300)
    }

    @Test func pourBedIsSilentWithoutFlowAndFizzesWithFoam() {
        let still = SoundBook.pourBed(telemetry: PourTelemetry(), foam: 0, texture: SoundBook.texture(for: .water),
                                      master: 1)
        #expect(still.splashGain == Float(0))
        #expect(still.resonanceGain == Float(0))
        #expect(still.fizzGain == Float(0))

        let pouring = SoundBook.pourBed(telemetry: PourTelemetry(flow: 0.6, landingRate: 0.6, activeFill: 0.4),
                                        foam: 0, texture: SoundBook.texture(for: .water), master: 1)
        #expect(pouring.splashGain > 0)
        #expect(pouring.resonanceGain > 0)

        // A soda head keeps fizzing after the pour stops.
        let settling = SoundBook.pourBed(telemetry: PourTelemetry(liquid: .cola), foam: 0.15,
                                         texture: SoundBook.texture(for: .cola), master: 1)
        #expect(settling.fizzRate > 0)
        #expect(settling.fizzGain > 0)

        let sand = SoundBook.pourBed(telemetry: PourTelemetry(flow: 0.5, landingRate: 0.5, liquid: .sand), foam: 0,
                                     texture: SoundBook.texture(for: .sand), master: 1)
        #expect(sand.hissGain > 0)
    }

    @Test func shimmerSwellsInsideThePerfectBand() {
        let band = 0.025
        #expect(SoundBook.shimmerLevel(projectedDistance: 0, band: band) == 1.0)
        #expect(SoundBook.shimmerLevel(projectedDistance: -0.2, band: band) == 0.0)
        #expect(SoundBook.shimmerLevel(projectedDistance: 0.2, band: band) == 0.0)
        #expect(SoundBook.shimmerLevel(projectedDistance: -1.35 * band, band: band) == 0.0)
        // Audible at the band edge, symmetric about the line, and never louder further out.
        let edge = SoundBook.shimmerLevel(projectedDistance: -band, band: band)
        #expect(edge > 0.2)
        #expect(edge < 0.7)
        #expect(SoundBook.shimmerLevel(projectedDistance: band, band: band) == edge)
        var previous = 2.0
        for step in 0...60 {
            let level = SoundBook.shimmerLevel(projectedDistance: -Double(step) * 0.001, band: band)
            #expect(level <= previous)
            #expect(level >= 0)
            previous = level
        }
        #expect(SoundBook.shimmerLevel(projectedDistance: Double.nan, band: band) == 0.0)
        // A nonsense band falls back to the default rather than going silent or NaN.
        #expect(SoundBook.shimmerLevel(projectedDistance: 0, band: Double.nan) == 1.0)
    }

    @Test func pourBedShimmersOnlyWhileTheLevelIsStillLive() {
        let water = SoundBook.texture(for: .water)
        let inBand = SoundBook.pourBed(telemetry: PourTelemetry(flow: 0.2, landingRate: 0.2, activeFill: 0.78,
                                                                distanceToLine: -0.05, projectedDistanceToLine: 0.001),
                                       foam: 0, texture: water, master: 1, band: 0.025, streak: 2)
        #expect(inBand.shimmerGain > 0)
        #expect(inBand.shimmerGain <= SoundBook.shimmerPeak)
        #expect(abs(Double(inBand.shimmerHz) - SoundBook.tingFrequency(streak: 3) / 2) < 0.01)
        let far = SoundBook.pourBed(telemetry: PourTelemetry(flow: 0.6, landingRate: 0.6, activeFill: 0.3,
                                                             distanceToLine: -0.5, projectedDistanceToLine: -0.4),
                                    foam: 0, texture: water, master: 1, band: 0.025, streak: 2)
        #expect(far.shimmerGain == Float(0))
        // Everything has landed: the shimmer hands over to the lock-in tink.
        let settled = SoundBook.pourBed(telemetry: PourTelemetry(flow: 0, landingRate: 0, activeFill: 0.8,
                                                                 distanceToLine: 0, projectedDistanceToLine: 0),
                                        foam: 0, texture: water, master: 1)
        #expect(settled.shimmerGain == Float(0))
        // The shimmer pitch climbs with the streak, like the ting it anticipates.
        #expect(SoundBook.shimmerHz(streak: 4) > SoundBook.shimmerHz(streak: 0))
    }

    @Test func lockInAndFlatClickAreSubtle() {
        var dice = FeelDice(seed: 11)
        let perfectPeak = SoundBook.perfect(streak: 1, dice: &dice).map { $0.gain }.max() ?? 0
        let tink = SoundBook.lockedIn(streak: 0, dice: &dice)
        let click = SoundBook.flatArmed()
        #expect(!tink.isEmpty)
        #expect(!click.isEmpty)
        for command in tink { #expect(command.gain < perfectPeak * 0.25) }
        for command in click { #expect(command.gain <= 0.08) }
        // The tink stays out of the shrill top octave at any streak.
        for streak in 0...12 {
            for command in SoundBook.lockedIn(streak: streak, dice: &dice) {
                if case .ring(let ring) = command { #expect(ring.fundamental <= 4200) }
            }
        }
        let perfectHaptic = HapticBook.perfect.notes.map { $0.intensity }.max() ?? 0
        for note in HapticBook.lockedIn.notes { #expect(note.intensity < perfectHaptic * 0.5) }
        for note in HapticBook.flatArmed.notes { #expect(note.intensity <= 0.45) }
        // The pour-start detent is gentle too.
        for note in HapticBook.pourStart.notes { #expect(note.intensity <= 0.5) }
    }

    @Test func spillCueIsBigAndCarriesThroughTheOverflow() {
        var dice = FeelDice(seed: 5)
        let spill = SoundBook.spill(dice: &dice)
        #expect(spill.count >= 6)
        #expect((spill.map { $0.gain }.max() ?? 0) >= 0.25)
        let longest = HapticBook.spill.notes.map { $0.time + $0.duration }.max() ?? 0
        #expect(longest >= 0.5)
        #expect(HapticBook.spill.wobble.count <= 16)
    }

    @Test func synthRendersTheShimmerCleanly() {
        let synth = PourSynth(sampleRate: 48_000)
        var bed = PourBed()
        bed.master = 1.4
        bed.splashGain = 0.18
        bed.resonance = 1200
        bed.resonanceGain = 1.1
        bed.shimmerGain = SoundBook.shimmerPeak
        bed.shimmerHz = Float(SoundBook.shimmerHz(streak: 7))
        synth.send(.bed(bed))
        let frames = 512
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { buffer.deallocate() }
        var peak: Float = 0
        var energy: Float = 0
        var finite = true
        for _ in 0..<60 {
            synth.render(frames: frames, into: buffer)
            for index in 0..<frames {
                let value = buffer[index]
                if !value.isFinite { finite = false }
                peak = max(peak, abs(value))
                energy += value * value
            }
        }
        #expect(finite)
        #expect(energy > 0)
        #expect(peak < 1)
        // Shimmer alone (no rush) is audible but faint.
        let quiet = PourSynth(sampleRate: 48_000)
        var only = PourBed()
        only.master = 1.4
        only.shimmerGain = SoundBook.shimmerPeak
        only.shimmerHz = 660
        quiet.send(.bed(only))
        var shimmerPeak: Float = 0
        for _ in 0..<40 {
            quiet.render(frames: frames, into: buffer)
            for index in 0..<frames { shimmerPeak = max(shimmerPeak, abs(buffer[index])) }
        }
        #expect(shimmerPeak > 0.01)
        #expect(shimmerPeak < 0.2)
    }

    @Test func hapticFlowMapping() {
        #expect(HapticBook.flowLevel(flow: 0) == Float(0))
        #expect(abs(HapticBook.flowLevel(flow: 1) - 0.7) < 0.0001)
        #expect(abs(HapticBook.flowLevel(flow: 0.02) - 0.161) < 0.001)
        #expect(abs(HapticBook.flowSharpness(fill: 0) - 0.2) < 0.0001)
        #expect(abs(HapticBook.flowSharpness(fill: 1) - 0.8) < 0.0001)
        #expect(HapticBook.perfect.notes.count == 2)
        #expect(HapticBook.spill.notes.filter { $0.kind == .transient }.count == 3)
    }

    @Test func synthRendersWithoutClipping() {
        let synth = PourSynth(sampleRate: 48_000)
        var bed = PourBed()
        bed.master = 1.4
        bed.splashGain = 0.18
        bed.resonance = 700
        bed.resonanceGain = 1.1
        bed.fizzRate = 2000
        bed.fizzGain = 0.22
        synth.send(.bed(bed))
        var dice = FeelDice(seed: 3)
        var cues: [SynthCommand] = SoundBook.perfect(streak: 8, dice: &dice)
        cues.append(contentsOf: SoundBook.spill(dice: &dice))
        cues.append(contentsOf: SoundBook.finished(cleared: true))
        cues.append(contentsOf: SoundBook.short())
        for command in cues { synth.send(command) }
        // A deliberately hot pile-up: still never clips.
        for index in 0..<30 {
            synth.send(.ring(SynthRing(.glass, fundamental: 900 + Float(index) * 37, partials: 6, decay: 0.4, gain: 2)))
        }
        let frames = 512
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { buffer.deallocate() }
        var peak: Float = 0
        var energy: Float = 0
        var finite = true
        for _ in 0..<120 {
            synth.render(frames: frames, into: buffer)
            for index in 0..<frames {
                let value = buffer[index]
                if !value.isFinite { finite = false }
                peak = max(peak, abs(value))
                energy += value * value
            }
        }
        #expect(finite)
        #expect(peak < 1)
        #expect(energy > 0)
        #expect(synth.peak < 1)
        #expect(synth.renderCallbacks == 120)
    }

    @Test func synthIsSilentWithMasterAtZero() {
        let synth = PourSynth(sampleRate: 44_100)
        synth.send(.bed(PourBed()))
        synth.send(.ring(SynthRing(.glass, fundamental: 1500, decay: 0.3, gain: 0.3)))
        let frames = 256
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { buffer.deallocate() }
        var peak: Float = 0
        for _ in 0..<20 {
            synth.render(frames: frames, into: buffer)
            for index in 0..<frames { peak = max(peak, abs(buffer[index])) }
        }
        #expect(peak < 0.0001)
    }

    @Test func commandQueueDropsInsteadOfBlockingWhenFull() {
        let synth = PourSynth(sampleRate: 48_000)
        var accepted = 0
        for _ in 0..<(PourSynth.queueCapacity * 2) {
            let ok = synth.send(.silence)
            if ok { accepted += 1 }
        }
        #expect(accepted == PourSynth.queueCapacity - 1)
    }

    @Test func settingsDefaultAndPersist() throws {
        let suite = "brim.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fresh = FeedbackSettings.load(from: defaults)
        #expect(fresh.soundOn)
        #expect(fresh.hapticsOn)
        #expect(fresh.respectSilentSwitch == false)

        var changed = fresh
        changed.soundOn = false
        changed.respectSilentSwitch = true
        changed.save(to: defaults)
        #expect(FeedbackSettings.load(from: defaults) == changed)
        #expect(defaults.bool(forKey: "brim.silent"))
    }

    @MainActor
    @Test func directorPersistsItsToggles() throws {
        let suite = "brim.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let director = FeedbackDirector(defaults: defaults)
        #expect(director.soundOn)
        director.hapticsOn = false
        director.soundOn = false
        let storedHaptics = (defaults.object(forKey: "brim.haptics") as? Bool) ?? true
        let storedSound = (defaults.object(forKey: "brim.sound") as? Bool) ?? true
        #expect(storedHaptics == false)
        #expect(storedSound == false)
        let again = FeedbackDirector(defaults: defaults)
        #expect(again.soundOn == false)
        #expect(again.hapticsOn == false)
    }
}
