import CoreGraphics
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

    @Test func pauseWhooshIsSoftShortAndFalling() {
        let whoosh = SoundBook.pauseWhoosh()
        #expect(!whoosh.isEmpty)
        var dice = FeelDice(seed: 3)
        let perfectPeak = SoundBook.perfect(streak: 1, dice: &dice).map { $0.gain }.max() ?? 0
        var noises = 0
        for command in whoosh {
            #expect(command.gain > 0)
            #expect(command.gain <= 0.08)
            #expect(command.gain < perfectPeak * 0.3)
            if case .noise(let noise) = command {
                noises += 1
                // A falling breath of air, gone in well under a second.
                #expect(noise.cutoffEnd < noise.cutoff)
                #expect(noise.delay + noise.attack + 4 * noise.decay < 0.9)
            }
        }
        #expect(noises == whoosh.count)
    }

    @Test func pourStaysQuietUntilTheFlatGateRearms() {
        #expect(SoundBook.pourIsAudible(needsFlat: false))
        #expect(SoundBook.pourIsAudible(needsFlat: true) == false)
        #expect(FeedbackDirector.isPourTexture(.pourStarted))
        #expect(FeedbackDirector.isPourTexture(.glug(intensity: 0.5)))
        #expect(FeedbackDirector.isPourTexture(.splashInGlass(glassID: 1, x: 300, strength: 0.5)))
        #expect(FeedbackDirector.isPourTexture(.splashOnCounter(x: 300, strength: 0.5)))
        // The latch click, judgements and arrivals still speak.
        #expect(FeedbackDirector.isPourTexture(.flatArmed) == false)
        #expect(FeedbackDirector.isPourTexture(.served(glassID: 1, judgement: .perfect, points: 100)) == false)
        #expect(FeedbackDirector.isPourTexture(.glassArrived(glassID: 2)) == false)
    }

    @MainActor
    @Test func idleBedPoursNothingButKeepsOneShotsAudible() {
        let bed = SoundBook.idleBed(master: BrimAudioEngine.masterGain)
        #expect(bed.master == BrimAudioEngine.masterGain)
        #expect(bed.splashGain == Float(0))
        #expect(bed.resonanceGain == Float(0))
        #expect(bed.fizzGain == Float(0))
        #expect(bed.hissGain == Float(0))
        #expect(bed.shimmerGain == Float(0))
        // A pause card's tap or the closing whoosh rings through it (a master of 0 would mute every one-shot).
        let synth = PourSynth(sampleRate: 48_000)
        synth.send(.bed(bed))
        for command in SoundBook.pauseWhoosh() { synth.send(command) }
        let frames = 512
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { buffer.deallocate() }
        var peak: Float = 0
        var finite = true
        for _ in 0..<60 {
            synth.render(frames: frames, into: buffer)
            for index in 0..<frames {
                let value = buffer[index]
                if !value.isFinite { finite = false }
                peak = max(peak, abs(value))
            }
        }
        #expect(finite)
        #expect(peak > 0.002)
        #expect(peak < 1)
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

    /// Round 4 (QA P2-7): the engines idle on menus and wake for a run. The director never starts its engines here
    /// (no `start()`), so this checks the state machine only.
    @MainActor
    @Test func directorIdlesOnMenusAndWakesForARun() throws {
        let suite = "brim.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let director = FeedbackDirector(defaults: defaults)
        #expect(director.isIdle == false)
        director.setIdle(true)
        #expect(director.isIdle)
        director.setIdle(true)
        #expect(director.isIdle)
        director.setIdle(false)
        #expect(director.isIdle == false)
        // A short pause doesn't idle (the long-pause idle arrives after `pausedIdleDelay` seconds).
        director.setPaused(true)
        #expect(director.isIdle == false)
        director.setPaused(false)
        #expect(director.isIdle == false)
        #expect(FeedbackDirector.pausedIdleDelay >= 1)
        #expect(BrimAudioEngine.napAfter >= 1)
    }

    // MARK: Round 5

    @Test func overCueIsSoftAndDistinctFromShortAndSpill() {
        var dice = FeelDice(seed: 21)
        let over = SoundBook.over()
        let short = SoundBook.short()
        let spill = SoundBook.spill(dice: &dice)
        #expect(!over.isEmpty)
        #expect(over != short)
        // Its contour lifts where Short's sinks.
        var overFirst: SynthTone?
        var shortFirst: SynthTone?
        for command in over { if case .tone(let tone) = command, overFirst == nil { overFirst = tone } }
        for command in short { if case .tone(let tone) = command, shortFirst == nil { shortFirst = tone } }
        #expect((overFirst?.end ?? 0) > (overFirst?.start ?? 1))
        #expect((shortFirst?.end ?? 1) < (shortFirst?.start ?? 0))
        // Soft: as quiet as Short, far below the spill, and none of the spill's drips or tones.
        let overPeak = over.map { $0.gain }.max() ?? 1
        let shortPeak = short.map { $0.gain }.max() ?? 0
        let spillPeak = spill.map { $0.gain }.max() ?? 0
        #expect(overPeak <= shortPeak * 1.1)
        #expect(overPeak < spillPeak * 0.5)
        for command in over {
            if case .bubble(_) = command { Issue.record("over has a drip") }
            #expect(!spill.contains(command))
        }
        // Haptics: a soft "uh-uh", neither Short's thud nor the spill's rumble.
        #expect(HapticBook.over != HapticBook.short)
        #expect(HapticBook.over != HapticBook.spill)
        #expect(HapticBook.over.wobble.isEmpty)
        let overHaptic = HapticBook.over.notes.map { $0.intensity }.max() ?? 1
        let spillHaptic = HapticBook.spill.notes.map { $0.intensity }.max() ?? 0
        #expect(overHaptic <= 0.45)
        #expect(overHaptic < spillHaptic * 0.5)
    }

    @Test func glugOutSlowsFallsAndFades() {
        var dice = FeelDice(seed: 9)
        let cue = SoundBook.glugOut(dice: &dice)
        var bubbles: [SynthBubble] = []
        for command in cue { if case .bubble(let bubble) = command { bubbles.append(bubble) } }
        #expect(bubbles.count >= 3)
        for index in 1..<bubbles.count {
            #expect(bubbles[index].frequency < bubbles[index - 1].frequency)
            #expect(bubbles[index].gain < bubbles[index - 1].gain)
            #expect(bubbles[index].delay > bubbles[index - 1].delay)
        }
        // Gaps grow: "glug… glg… g".
        if bubbles.count >= 3 {
            #expect(bubbles[2].delay - bubbles[1].delay > bubbles[1].delay - bubbles[0].delay)
        }
        // Soft: below a Perfect, never an alarm.
        var perfectDice = FeelDice(seed: 9)
        let perfectPeak = SoundBook.perfect(streak: 1, dice: &perfectDice).map { $0.gain }.max() ?? 0
        for command in cue { #expect(command.gain < perfectPeak * 0.6) }
        // The haptic gulps fade and keep time with the sound.
        let taps = HapticBook.glugOut.notes
        #expect(taps.count == bubbles.count)
        for index in 0..<min(taps.count, bubbles.count) {
            #expect(abs(taps[index].time - Double(bubbles[index].delay)) < 1e-6)
            if index > 0 { #expect(taps[index].intensity < taps[index - 1].intensity) }
        }
        for note in taps { #expect(note.intensity <= 0.35) }
    }

    @Test func dryJugWatchFiresOncePerEmptyJug() {
        var watch = DryJugWatch()
        // Never seen a fuller jug (a run that starts empty): nothing.
        #expect(watch.update(fill: 0.0, jugAngle: 80, live: true) == false)
        // A jug in use arms it; tipped and run dry: the cue, once.
        #expect(watch.update(fill: 0.6, jugAngle: 40, live: true) == false)
        #expect(watch.update(fill: 0.2, jugAngle: 70, live: true) == false)
        // The last drops still running out: not yet.
        #expect(watch.update(fill: 0.02, jugAngle: 85, live: true) == false)
        #expect(watch.update(fill: 0.0, jugAngle: 85, live: true))
        #expect(watch.update(fill: 0.0, jugAngle: 90, live: true) == false)
        #expect(watch.update(fill: 0.0, jugAngle: 0, live: true) == false)
        // Swapped for a full one: armed again. Upright and nearly empty is not "dry while tilted".
        #expect(watch.update(fill: 0.7, jugAngle: 0, live: true) == false)
        #expect(watch.update(fill: 0.0, jugAngle: 5, live: true) == false)
        // Not live (paused, gated, Rush): it waits, then speaks once play is live.
        #expect(watch.update(fill: 0.0, jugAngle: 80, live: false) == false)
        #expect(watch.update(fill: 0.0, jugAngle: 80, live: true))
        // NaN never fires.
        #expect(watch.update(fill: 0.9, jugAngle: 0, live: true) == false)
        #expect(watch.update(fill: Double.nan, jugAngle: 80, live: true) == false)
        #expect(watch.update(fill: 0.0, jugAngle: Double.nan, live: true) == false)
    }

    @Test func dryJugWatchReadsTheSnapshot() {
        var watch = DryJugWatch()
        #expect(watch.update(snapshot: feedbackSnapshot(fill: 0.5, angle: 50), events: [], paused: false) == false)
        // Paused or behind the flat gate: not now.
        #expect(watch.update(snapshot: feedbackSnapshot(fill: 0.0, angle: 90), events: [], paused: true) == false)
        #expect(watch.update(snapshot: feedbackSnapshot(fill: 0.0, angle: 90, needsFlat: true), events: [],
                             paused: false) == false)
        // The frame that ends the run on an empty jug has its own cue.
        #expect(watch.update(snapshot: feedbackSnapshot(fill: 0.0, angle: 90), events: [.jugEmpty],
                             paused: false) == false)
        #expect(watch.update(snapshot: feedbackSnapshot(fill: 0.0, angle: 90), events: [], paused: false))
        // Rush: an empty jug ends the run (`jugEmpty`), never a glug-out.
        var rush = DryJugWatch()
        #expect(rush.update(snapshot: feedbackSnapshot(fill: 0.5, angle: 50, mode: .rush), events: [],
                            paused: false) == false)
        #expect(rush.update(snapshot: feedbackSnapshot(fill: 0.0, angle: 90, mode: .rush), events: [],
                            paused: false) == false)
    }

    @Test func overAndGlugOutRenderCleanly() {
        let synth = PourSynth(sampleRate: 48_000)
        var bed = PourBed()
        bed.master = 1.4
        synth.send(.bed(bed))
        var dice = FeelDice(seed: 4)
        for command in SoundBook.over() { synth.send(command) }
        for command in SoundBook.glugOut(dice: &dice) { synth.send(command) }
        let frames = 512
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { buffer.deallocate() }
        var peak: Float = 0
        var finite = true
        for _ in 0..<100 {
            synth.render(frames: frames, into: buffer)
            for index in 0..<frames {
                let value = buffer[index]
                if !value.isFinite { finite = false }
                peak = max(peak, abs(value))
            }
        }
        #expect(finite)
        #expect(peak > 0.002)
        #expect(peak < 1)
    }

    /// REVIEW-5 P1-1: on a glass whose line has faded, the shimmer and the lock-in tink must not tell the player
    /// where the line is.
    @Test func fadedLinesSilenceTheShimmerAndTheLockIn() {
        let water = SoundBook.texture(for: .water)
        let telemetry = PourTelemetry(flow: 0.2, landingRate: 0.2, activeFill: 0.78, distanceToLine: -0.01,
                                      projectedDistanceToLine: 0.0)
        let visible = SoundBook.pourBed(telemetry: telemetry, foam: 0, texture: water, master: 1, band: 0.025,
                                        lineOpacity: 1)
        let fading = SoundBook.pourBed(telemetry: telemetry, foam: 0, texture: water, master: 1, band: 0.025,
                                       lineOpacity: 0.6)
        let faded = SoundBook.pourBed(telemetry: telemetry, foam: 0, texture: water, master: 1, band: 0.025,
                                      lineOpacity: 0.4)
        let gone = SoundBook.pourBed(telemetry: telemetry, foam: 0, texture: water, master: 1, band: 0.025,
                                     lineOpacity: 0)
        #expect(visible.shimmerGain > 0)
        #expect(fading.shimmerGain > 0)
        #expect(faded.shimmerGain == Float(0))
        #expect(gone.shimmerGain == Float(0))
        // The rest of the pour still sounds.
        #expect(faded.splashGain == visible.splashGain)
        #expect(faded.resonanceGain == visible.resonanceGain)
        #expect(SoundBook.lineCuesAudible(lineOpacity: Double.nan) == false)
        // The lock-in tink follows the same rule, per glass.
        #expect(FeedbackDirector.lockInAudible(glassID: 1, snapshot: feedbackSnapshot(fill: 0.5, angle: 0,
                                                                                       lineOpacity: 1)))
        #expect(FeedbackDirector.lockInAudible(glassID: 1, snapshot: feedbackSnapshot(fill: 0.5, angle: 0,
                                                                                       lineOpacity: 0.3)) == false)
        #expect(FeedbackDirector.lockInAudible(glassID: 99, snapshot: feedbackSnapshot(fill: 0.5, angle: 0,
                                                                                        lineOpacity: 0.3)))
    }

    // MARK: Round 6: the late game

    @Test func sandRustleRisesWithReposeAndDucksOnceSandFlows() {
        #expect(SoundBook.rustleLevel(reposeProgress: 0, flow: 0) == 0.0)
        #expect(SoundBook.rustleLevel(reposeProgress: SoundBook.rustleStart, flow: 0) == 0.0)
        #expect(SoundBook.rustleLevel(reposeProgress: 1, flow: 0) == 1.0)
        #expect(SoundBook.rustleLevel(reposeProgress: 3, flow: 0) == 1.0)
        #expect(SoundBook.rustleLevel(reposeProgress: Double.nan, flow: 0) == 0.0)
        var previous = -1.0
        for step in 0...100 {
            let level = SoundBook.rustleLevel(reposeProgress: Double(step) / 100, flow: 0)
            #expect(level >= previous)
            #expect(level >= 0)
            #expect(level <= 1)
            previous = level
        }
        // Once the sand slides, the hiss of the flow takes over.
        #expect(SoundBook.rustleLevel(reposeProgress: 1, flow: 0.5) == 0.0)
        #expect(SoundBook.rustleLevel(reposeProgress: 1, flow: 0.05) < 1)

        let sand = SoundBook.texture(for: .sand)
        let rest = SoundBook.pourBed(telemetry: PourTelemetry(liquid: .sand), foam: 0, texture: sand, master: 1)
        let creeping = SoundBook.pourBed(telemetry: PourTelemetry(liquid: .sand), foam: 0, texture: sand, master: 1,
                                         reposeProgress: 0.7)
        let near = SoundBook.pourBed(telemetry: PourTelemetry(liquid: .sand), foam: 0, texture: sand, master: 1,
                                     reposeProgress: 0.97)
        let flowing = SoundBook.pourBed(telemetry: PourTelemetry(flow: 0.6, landingRate: 0.5, liquid: .sand), foam: 0,
                                        texture: sand, master: 1, reposeProgress: 1)
        #expect(rest.rustleGain == Float(0))
        #expect(creeping.rustleGain > 0)
        #expect(near.rustleGain > creeping.rustleGain)
        #expect(near.rustleGain <= SoundBook.rustlePeak)
        // Denser and brighter as the slide nears.
        #expect(near.rustleDensity > creeping.rustleDensity)
        #expect(near.rustleCenter > creeping.rustleCenter)
        // A whisper under the hiss of sand actually pouring.
        #expect(flowing.rustleGain == Float(0))
        #expect(near.rustleGain < flowing.hissGain)
        // Liquids never rustle.
        let water = SoundBook.pourBed(telemetry: PourTelemetry(flow: 0.5, landingRate: 0.5), foam: 0,
                                      texture: SoundBook.texture(for: .water), master: 1)
        #expect(water.rustleGain == Float(0))
    }

    @Test func sandTicksAccelerateTowardTheSlide() throws {
        #expect(SandTelegraph.tickGap(progress: 0.3) == nil)
        #expect(SandTelegraph.tickGap(progress: SoundBook.rustleStart) == nil)
        #expect(SandTelegraph.tickGap(progress: Double.nan) == nil)
        let early = try #require(SandTelegraph.tickGap(progress: 0.6))
        let late = try #require(SandTelegraph.tickGap(progress: 0.98))
        let last = try #require(SandTelegraph.tickGap(progress: 1))
        #expect(late < early * 0.5)
        #expect(abs(last - SandTelegraph.fastGap) < 1e-9)
        #expect(early <= SandTelegraph.slowGap)
        // Calm: fewer, never busier than the calm floor.
        let calmLate = try #require(SandTelegraph.tickGap(progress: 1, calm: true))
        #expect(calmLate >= SandTelegraph.calmFastGap)
        #expect(calmLate > last)

        // A slow tip from 0.4 to 1 over 4 s at 60 fps: the ticks start past the threshold and close in.
        let telegraph = SandTelegraph()
        var ticks: [Double] = []
        for frame in 0..<240 {
            let t = Double(frame) / 60
            let progress = 0.4 + 0.6 * t / 4
            let tick = telegraph.update(progress: progress, flowing: false, live: true, now: t)
            if tick != nil { ticks.append(t) }
        }
        #expect(ticks.count >= 8)
        if ticks.count >= 4 {
            #expect(ticks[0] > 0.6)
            let firstGap = ticks[1] - ticks[0]
            let lastGap = ticks[ticks.count - 1] - ticks[ticks.count - 2]
            #expect(firstGap > lastGap * 2)
        }

        // Silent while sand flows or the run isn't live; ticks again once it is.
        let quiet = SandTelegraph()
        let whileFlowing = quiet.update(progress: 0.9, flowing: true, live: true, now: 0)
        let whilePaused = quiet.update(progress: 0.9, flowing: false, live: false, now: 1)
        let afterwards = quiet.update(progress: 0.9, flowing: false, live: true, now: 2)
        let tooSoon = quiet.update(progress: 0.9, flowing: false, live: true, now: 2.01)
        #expect(whileFlowing == nil)
        #expect(whilePaused == nil)
        #expect(afterwards != nil)
        #expect(tooSoon == nil)

        // The haptic ticks are light and firm up toward the slide; calm is softer.
        let soft = HapticBook.sandTick(progress: 0.55).notes.map { $0.intensity }.max() ?? 1
        let firm = HapticBook.sandTick(progress: 1).notes.map { $0.intensity }.max() ?? 0
        let calmFirm = HapticBook.sandTick(progress: 1, calm: true).notes.map { $0.intensity }.max() ?? 1
        #expect(firm > soft)
        #expect(firm <= 0.35)
        #expect(calmFirm < firm)
        #expect(HapticBook.sandTick(progress: Double.nan).notes.count == 1)
    }

    @Test func avalancheIsAShortDryFallingWhoosh() {
        var dice = FeelDice(seed: 13)
        let shff = SoundBook.avalanche(dice: &dice)
        var perfectDice = FeelDice(seed: 13)
        let perfectPeak = SoundBook.perfect(streak: 1, dice: &perfectDice).map { $0.gain }.max() ?? 0
        #expect(!shff.isEmpty)
        var falling = 0
        for command in shff {
            #expect(command.gain > 0)
            #expect(command.gain < perfectPeak * 0.6)
            if case .noise(let noise) = command {
                if noise.cutoffEnd < noise.cutoff { falling += 1 }
                #expect(noise.delay + noise.attack + 4 * noise.decay < 0.9)
            } else {
                Issue.record("the avalanche is all grains, no pitched voice")
            }
        }
        #expect(falling >= 1)
        // Felt: a thud and a gritty slide, under the spill.
        let peak = HapticBook.avalanche.notes.map { $0.intensity }.max() ?? 1
        let spillPeak = HapticBook.spill.notes.map { $0.intensity }.max() ?? 0
        #expect(peak <= 0.7)
        #expect(peak < spillPeak)
        #expect(HapticBook.avalanche.wobble.count <= 16)
        // Sand's pour start is the avalanche; a liquid's is the glass knock.
        var sand = feedbackSnapshot(fill: 0.8, angle: 60)
        sand.jug.liquid.id = .sand
        sand.jug.liquid.reposeDegrees = 30
        #expect(FeedbackDirector.isAvalanche(sand))
        #expect(FeedbackDirector.isAvalanche(feedbackSnapshot(fill: 0.8, angle: 60)) == false)
    }

    @Test func rushTierUpChimesOnEveryTierAfterTheFirst() {
        let watch = RushTierWatch()
        let first = watch.update(tier: 1, isRush: true)
        let same = watch.update(tier: 1, isRush: true)
        let second = watch.update(tier: 2, isRush: true)
        let held = watch.update(tier: 2, isRush: true)
        let third = watch.update(tier: 3, isRush: true)
        #expect(first == false)
        #expect(same == false)
        #expect(second)
        #expect(held == false)
        #expect(third)
        // A restarted run drops back to tier 1 silently, then climbs again.
        let restarted = watch.update(tier: 1, isRush: true)
        let climbs = watch.update(tier: 2, isRush: true)
        #expect(restarted == false)
        #expect(climbs)
        // Outside Rush it forgets; a new run's first frames (0, then 1) are not a tier-up.
        let menu = watch.update(tier: 0, isRush: false)
        let intro = watch.update(tier: 0, isRush: true)
        let start = watch.update(tier: 1, isRush: true)
        #expect(menu == false)
        #expect(intro == false)
        #expect(start == false)
        #expect(watch.lastTier == 1)
        // From the snapshot: Rush only.
        let fromSnapshot = RushTierWatch()
        let rush1 = fromSnapshot.update(snapshot: feedbackSnapshot(fill: 1, angle: 0, mode: .rush, rushTier: 1))
        let rush2 = fromSnapshot.update(snapshot: feedbackSnapshot(fill: 1, angle: 0, mode: .rush, rushTier: 2))
        let shift = fromSnapshot.update(snapshot: feedbackSnapshot(fill: 1, angle: 0, rushTier: 3))
        #expect(rush1 == false)
        #expect(rush2)
        #expect(shift == false)

        // The chord: three bells rising through a major triad, arpeggiated, under a Perfect.
        var dice = FeelDice(seed: 17)
        let chord = SoundBook.tierUp(tier: 3, dice: &dice)
        var bells: [SynthRing] = []
        for command in chord { if case .ring(let ring) = command, ring.kind == .bell { bells.append(ring) } }
        #expect(bells.count == 3)
        if bells.count == 3 {
            #expect(bells[1].fundamental > bells[0].fundamental)
            #expect(bells[2].fundamental > bells[1].fundamental)
            #expect(bells[1].delay > bells[0].delay)
            #expect(bells[2].delay > bells[1].delay)
            let fifth = Double(bells[2].fundamental / bells[0].fundamental)
            #expect(abs(fifth - pow(2, 7.0 / 12)) < 0.001)
        }
        var perfectDice = FeelDice(seed: 17)
        let perfectPeak = SoundBook.perfect(streak: 1, dice: &perfectDice).map { $0.gain }.max() ?? 0
        for command in chord { #expect(command.gain < perfectPeak * 0.6) }
        // Each tier starts higher, up to a cap; and it is not the end fanfare.
        #expect(SoundBook.tierRootHz(tier: 4) > SoundBook.tierRootHz(tier: 3))
        #expect(SoundBook.tierRootHz(tier: 30) == SoundBook.tierRootHz(tier: 6))
        #expect(SoundBook.tierRootHz(tier: 6) < 1046.5)
        #expect(chord != SoundBook.finished(cleared: true))
        // Felt: rising taps in time with the bells, confident but under the fanfare.
        let taps = HapticBook.tierUp.notes.filter { $0.kind == .transient }
        #expect(taps.count == 3)
        for index in 1..<taps.count {
            #expect(taps[index].intensity > taps[index - 1].intensity)
            #expect(abs(taps[index].time - Double(SoundBook.tierChordGap) * Double(index)) < 1e-6)
        }
        let tierPeak = HapticBook.tierUp.notes.map { $0.intensity }.max() ?? 1
        let celebratePeak = HapticBook.celebrate.notes.map { $0.intensity }.max() ?? 0
        #expect(tierPeak >= 0.6)
        #expect(tierPeak < celebratePeak)
    }

    @Test func rushLowJugHeartbeatsOncePerDip() {
        let watch = LowJugWatch()
        // Never seen a fuller jug: nothing.
        let unarmed = watch.update(fill: 0.1, live: true)
        #expect(unarmed == false)
        let full = watch.update(fill: 1.0, live: true)
        let quarter = watch.update(fill: 0.25, live: true)
        let dip = watch.update(fill: 0.19, live: true)
        let lower = watch.update(fill: 0.12, live: true)
        #expect(full == false)
        #expect(quarter == false)
        #expect(dip)
        #expect(lower == false)
        // Hovering under 30 % never repeats it.
        let wobbleUp = watch.update(fill: 0.26, live: true)
        let wobbleDown = watch.update(fill: 0.18, live: true)
        #expect(wobbleUp == false)
        #expect(wobbleDown == false)
        // A refill past 30 % re-arms it for the next dip.
        let refilled = watch.update(fill: 0.31, live: true)
        let nextDip = watch.update(fill: 0.19, live: true)
        #expect(refilled == false)
        #expect(nextDip)
        // Not on an empty jug (the run ends with its own cue), and it waits out a pause.
        let rearm = watch.update(fill: 0.5, live: true)
        let empty = watch.update(fill: 0.0, live: true)
        let rearmAgain = watch.update(fill: 0.5, live: true)
        let paused = watch.update(fill: 0.1, live: false)
        let resumed = watch.update(fill: 0.1, live: true)
        let nan = watch.update(fill: Double.nan, live: true)
        #expect(rearm == false)
        #expect(empty == false)
        #expect(rearmAgain == false)
        #expect(paused == false)
        #expect(resumed)
        #expect(nan == false)

        // From the snapshot: Rush only, never on the frame that ends the run.
        let rush = LowJugWatch()
        let rushFull = rush.update(snapshot: feedbackSnapshot(fill: 0.9, angle: 40, mode: .rush), events: [],
                                   paused: false)
        let ending = rush.update(snapshot: feedbackSnapshot(fill: 0.15, angle: 70, mode: .rush), events: [.jugEmpty],
                                 paused: false)
        let gated = rush.update(snapshot: feedbackSnapshot(fill: 0.15, angle: 70, needsFlat: true, mode: .rush),
                                events: [], paused: false)
        let rushDip = rush.update(snapshot: feedbackSnapshot(fill: 0.15, angle: 70, mode: .rush), events: [],
                                  paused: false)
        #expect(rushFull == false)
        #expect(ending == false)
        #expect(gated == false)
        #expect(rushDip)
        let shift = LowJugWatch()
        let shiftFull = shift.update(snapshot: feedbackSnapshot(fill: 0.9, angle: 40), events: [], paused: false)
        let shiftLow = shift.update(snapshot: feedbackSnapshot(fill: 0.15, angle: 70), events: [], paused: false)
        #expect(shiftFull == false)
        #expect(shiftLow == false)

        // Lub-dub: two low glugs, the second lower and softer, soft overall; the haptic keeps time.
        var dice = FeelDice(seed: 23)
        let beat = SoundBook.lowJug(dice: &dice)
        var bubbles: [SynthBubble] = []
        for command in beat { if case .bubble(let bubble) = command { bubbles.append(bubble) } }
        #expect(bubbles.count == 2)
        if bubbles.count == 2 {
            #expect(bubbles[1].frequency < bubbles[0].frequency)
            #expect(bubbles[1].gain < bubbles[0].gain)
            #expect(bubbles[0].frequency < 300)
        }
        var perfectDice = FeelDice(seed: 23)
        let perfectPeak = SoundBook.perfect(streak: 1, dice: &perfectDice).map { $0.gain }.max() ?? 0
        for command in beat { #expect(command.gain < perfectPeak * 0.5) }
        let taps = HapticBook.lowJug.notes
        #expect(taps.count == bubbles.count)
        for index in 0..<min(taps.count, bubbles.count) {
            #expect(abs(taps[index].time - Double(bubbles[index].delay)) < 1e-6)
            #expect(taps[index].intensity <= 0.45)
            #expect(taps[index].sharpness <= 0.3)
        }
    }

    @Test func conveyorBellRingsAsAServedGlassRidesOff() {
        let watch = ConveyorBellWatch()
        let filling = watch.update(glasses: [feedbackGlass(phase: .filling)], conveyor: true)
        let served = watch.update(glasses: [feedbackGlass(phase: .served, result: .perfect)], conveyor: true)
        let leaves = watch.update(glasses: [feedbackGlass(phase: .leaving, result: .perfect)], conveyor: true)
        let stillLeaving = watch.update(glasses: [feedbackGlass(phase: .leaving, result: .perfect)], conveyor: true)
        #expect(filling == nil)
        #expect(served == nil)
        #expect(leaves == .perfect)
        #expect(stillLeaving == nil)
        // Misses ride off quietly.
        let missServed = watch.update(glasses: [feedbackGlass(id: 2, phase: .served, result: .short)], conveyor: true)
        let missLeaves = watch.update(glasses: [feedbackGlass(id: 2, phase: .leaving, result: .short)], conveyor: true)
        #expect(missServed == nil)
        #expect(missLeaves == nil)
        // Any hit rings; the best of a frame wins.
        let pairServed = watch.update(glasses: [feedbackGlass(id: 3, phase: .served, result: .good),
                                                feedbackGlass(id: 4, phase: .served, result: .perfect)],
                                      conveyor: true)
        let pairLeaves = watch.update(glasses: [feedbackGlass(id: 3, phase: .leaving, result: .good),
                                                feedbackGlass(id: 4, phase: .leaving, result: .perfect)],
                                      conveyor: true)
        #expect(pairServed == nil)
        #expect(pairLeaves == .perfect)
        // Other venues, or a glass first seen already leaving: nothing.
        let elsewhere = ConveyorBellWatch()
        let otherServed = elsewhere.update(glasses: [feedbackGlass(phase: .served, result: .great)], conveyor: false)
        let otherLeaves = elsewhere.update(glasses: [feedbackGlass(phase: .leaving, result: .great)], conveyor: false)
        let fresh = ConveyorBellWatch()
        let late = fresh.update(glasses: [feedbackGlass(phase: .leaving, result: .great)], conveyor: true)
        #expect(otherServed == nil)
        #expect(otherLeaves == nil)
        #expect(late == nil)
        // From the snapshot's venue.
        let belt = ConveyorBellWatch()
        let beltServed = belt.update(snapshot: feedbackSnapshot(fill: 0.5, angle: 0, glassPhase: .served,
                                                                result: .great, venue: .conveyor))
        let beltLeaves = belt.update(snapshot: feedbackSnapshot(fill: 0.5, angle: 0, glassPhase: .leaving,
                                                                result: .great, venue: .conveyor))
        #expect(beltServed == nil)
        #expect(beltLeaves == .great)

        // A light bell: under (and lower than) the Perfect ting; a Perfect rings it a touch brighter.
        var dice = FeelDice(seed: 29)
        let ding = SoundBook.serviceBell(perfect: false, dice: &dice)
        let bright = SoundBook.serviceBell(perfect: true, dice: &dice)
        var perfectDice = FeelDice(seed: 29)
        let perfectPeak = SoundBook.perfect(streak: 1, dice: &perfectDice).map { $0.gain }.max() ?? 0
        var bell: SynthRing?
        var brightBell: SynthRing?
        for command in ding { if case .ring(let ring) = command { bell = ring } }
        for command in bright { if case .ring(let ring) = command { brightBell = ring } }
        #expect(bell?.kind == .bell)
        #expect((bell?.fundamental ?? 9999) < Float(SoundBook.tingBaseHz))
        #expect((bell?.gain ?? 1) < perfectPeak * 0.4)
        #expect((brightBell?.gain ?? 0) > (bell?.gain ?? 1))
        for note in HapticBook.serviceBell.notes { #expect(note.intensity <= 0.3) }
    }

    @Test func potionsSparkleWhilePouringAndNeverTellTheLine() {
        let potion = SoundBook.texture(for: .potionBlue)
        #expect(potion.sparkle > 0)
        #expect(SoundBook.texture(for: .potionPink).sparkle > 0)
        #expect(SoundBook.texture(for: .water).sparkle == Float(0))
        #expect(SoundBook.texture(for: .cola).sparkle == Float(0))
        let pouring = SoundBook.pourBed(telemetry: PourTelemetry(flow: 0.5, landingRate: 0.5, activeFill: 0.3,
                                                                 liquid: .potionBlue),
                                        foam: 0, texture: potion, master: 1)
        let resting = SoundBook.pourBed(telemetry: PourTelemetry(liquid: .potionBlue), foam: 0, texture: potion,
                                        master: 1)
        #expect(pouring.sparkleRate > 0)
        #expect(pouring.sparkleGain > 0)
        #expect(pouring.sparkleGain <= SoundBook.sparklePeak)
        #expect(resting.sparkleRate == Float(0))
        // Faint: under the Perfect-band shimmer.
        #expect(SoundBook.sparklePeak < SoundBook.shimmerPeak)
        // The same at the line, past it, or with the line faded: it tells nothing about the level.
        let atLine = SoundBook.pourBed(telemetry: PourTelemetry(flow: 0.5, landingRate: 0.5, activeFill: 0.8,
                                                                distanceToLine: 0, projectedDistanceToLine: 0,
                                                                liquid: .potionBlue),
                                       foam: 0, texture: potion, master: 1, lineOpacity: 0)
        #expect(atLine.sparkleRate == pouring.sparkleRate)
        #expect(atLine.sparkleGain == pouring.sparkleGain)
        let water = SoundBook.pourBed(telemetry: PourTelemetry(flow: 0.5, landingRate: 0.5), foam: 0,
                                      texture: SoundBook.texture(for: .water), master: 1)
        #expect(water.sparkleRate == Float(0))
        #expect(water.sparkleGain == Float(0))
    }

    @Test func lateGameSoundsRenderCleanlyAndStayFaint() {
        // The rustle alone, just before the slide.
        let rustle = PourSynth(sampleRate: 48_000)
        rustle.send(.bed(SoundBook.pourBed(telemetry: PourTelemetry(liquid: .sand), foam: 0,
                                           texture: SoundBook.texture(for: .sand), master: 1.4,
                                           reposeProgress: 0.97)))
        let rustled = renderPeak(rustle, blocks: 60)
        #expect(rustled.finite)
        #expect(rustled.peak > 0.002)
        #expect(rustled.peak < 0.2)
        // The potion sparkle alone, at a full pour.
        let sparkle = PourSynth(sampleRate: 48_000)
        var sparkleBed = PourBed()
        sparkleBed.master = 1.4
        let potionBed = SoundBook.pourBed(telemetry: PourTelemetry(flow: 1, landingRate: 1, liquid: .potionPink),
                                          foam: 0, texture: SoundBook.texture(for: .potionPink), master: 1.4)
        sparkleBed.sparkleRate = potionBed.sparkleRate
        sparkleBed.sparkleGain = potionBed.sparkleGain
        sparkle.send(.bed(sparkleBed))
        let sparkled = renderPeak(sparkle, blocks: 120)
        #expect(sparkled.finite)
        #expect(sparkled.peak > 0.002)
        #expect(sparkled.peak < 0.2)
        // Every new one-shot, piled up over a full potion pour: clean, never clipping.
        let pile = PourSynth(sampleRate: 48_000)
        pile.send(.bed(potionBed))
        var dice = FeelDice(seed: 31)
        var cues: [SynthCommand] = SoundBook.avalanche(dice: &dice)
        cues.append(contentsOf: SoundBook.tierUp(tier: 5, dice: &dice))
        cues.append(contentsOf: SoundBook.lowJug(dice: &dice))
        cues.append(contentsOf: SoundBook.serviceBell(perfect: true, dice: &dice))
        for command in cues { pile.send(command) }
        let piled = renderPeak(pile, blocks: 120)
        #expect(piled.finite)
        #expect(piled.peak > 0.002)
        #expect(piled.peak < 1)
        // `.silence` stops the sparkle's ringing pings too.
        pile.send(.bed(SoundBook.idleBed(master: 1.4)))
        pile.send(.silence)
        _ = renderPeak(pile, blocks: 20)
        let after = renderPeak(pile, blocks: 10)
        #expect(after.peak < 0.01)
    }

    /// Round 7 (QA-3 P2-4): the bell rings only for a glass that really rode a belt (it moved while served), whatever
    /// the venue is that frame: not for the last Soda glass leaving as Rush turns into the Conveyor (tier 2→3), and
    /// still for the last belt glass as the room turns into the Diner (3→4).
    @Test func conveyorBellRingsOnlyForAGlassThatRodeABelt() {
        func glass(_ id: Int, _ phase: GlassPhase, _ result: Judgement?, x: CGFloat) -> GlassState {
            var g = feedbackGlass(id: id, phase: phase, result: result)
            g.x = x
            return g
        }
        // A belt glass: carried on by the belt while served, then rides off.
        let belt = ConveyorBellWatch()
        var rang: [Judgement] = []
        var x: CGFloat = 300
        for _ in 0..<3 {
            if let j = belt.rideOff(glasses: [glass(1, .filling, nil, x: x)]) { rang.append(j) }
            x += 0.6
        }
        for _ in 0..<18 {
            if let j = belt.rideOff(glasses: [glass(1, .served, .perfect, x: x)]) { rang.append(j) }
            x += 0.6
        }
        let off = belt.rideOff(glasses: [glass(1, .leaving, .perfect, x: x)])
        let after = belt.rideOff(glasses: [glass(1, .leaving, .perfect, x: x + 20)])
        #expect(rang.isEmpty)
        #expect(off == .perfect)
        #expect(after == nil)

        // Tier 2→3: a counter glass (standing still while served) leaves as the venue becomes the Conveyor: quiet.
        let counter = ConveyorBellWatch()
        var counterRang: [Judgement] = []
        for _ in 0..<18 {
            var s = feedbackSnapshot(fill: 0.5, angle: 0, mode: .rush, glassPhase: .served, result: .great,
                                     venue: .sodaFountain, rushTier: 2)
            s.glasses[0].x = 335
            if let j = counter.rideOff(snapshot: s) { counterRang.append(j) }
        }
        var leaving = feedbackSnapshot(fill: 0.5, angle: 0, mode: .rush, glassPhase: .leaving, result: .great,
                                       venue: .conveyor, rushTier: 3)
        leaving.glasses[0].x = 360
        if let j = counter.rideOff(snapshot: leaving) { counterRang.append(j) }
        #expect(counterRang.isEmpty)

        // Tier 3→4: the last belt glass rode the belt; the venue is already the Diner when it leaves: it rings.
        let edge = ConveyorBellWatch()
        var ex: CGFloat = 340
        for _ in 0..<18 {
            var s = feedbackSnapshot(fill: 0.5, angle: 0, mode: .rush, glassPhase: .served, result: .good,
                                     venue: .milkshakeDiner, rushTier: 4)
            s.glasses[0].x = ex
            _ = edge.rideOff(snapshot: s)
            ex += 0.5
        }
        var edgeLeaving = feedbackSnapshot(fill: 0.5, angle: 0, mode: .rush, glassPhase: .leaving, result: .good,
                                           venue: .milkshakeDiner, rushTier: 4)
        edgeLeaving.glasses[0].x = ex
        #expect(edge.rideOff(snapshot: edgeLeaving) == .good)

        // A belt miss still rides off quietly; a glass first seen leaving rings nothing.
        let miss = ConveyorBellWatch()
        _ = miss.rideOff(glasses: [glass(5, .served, .short, x: 300)])
        _ = miss.rideOff(glasses: [glass(5, .served, .short, x: 304)])
        #expect(miss.rideOff(glasses: [glass(5, .leaving, .short, x: 310)]) == nil)
        #expect(ConveyorBellWatch().rideOff(glasses: [glass(6, .leaving, .great, x: 310)]) == nil)
        // Ids are only remembered for one frame: a restarted run's glass 1 starts fresh.
        _ = belt.rideOff(glasses: [])
        _ = belt.rideOff(glasses: [glass(1, .served, .great, x: 335)])
        #expect(belt.rideOff(glasses: [glass(1, .leaving, .great, x: 340)]) == nil)
    }
}

private func feedbackLiquid() -> Liquid {
    Liquid(id: .water, name: "Water", top: RGBA(0.6, 0.85, 1), bottom: RGBA(0.4, 0.65, 0.95), foam: nil,
           lagTau: 0.04, foamPerVolume: 0, foamSettle: 1, reposeDegrees: 0, opacity: 0.5, fizzy: false)
}

/// One tumbler of water in `phase` (round 6: the conveyor bell reads phases and results).
private func feedbackGlass(id: Int = 1, phase: GlassPhase = .filling, result: Judgement? = nil,
                           lineOpacity: Double = 1) -> GlassState {
    let shape = GlassShape(id: "tumbler", name: "Tumbler", style: .tumbler,
                           profile: [CGPoint(x: 55, y: 0), CGPoint(x: 62, y: 120)], baseThickness: 8, wall: 3)
    return GlassState(id: id, shape: shape, liquid: feedbackLiquid(), x: 335, phase: phase, liquidHeight: 40,
                      foamHeight: 0, lineHeight: 96, lineOpacity: lineOpacity, inPerfectBand: false,
                      overflowing: false, patienceLeft: nil, patienceTotal: nil, result: result)
}

/// A one-glass snapshot for the director's pure helpers.
private func feedbackSnapshot(fill: Double, angle: Double, needsFlat: Bool = false, mode: GameMode = .shift("1-1"),
                              lineOpacity: Double = 1, glassPhase: GlassPhase = .filling, result: Judgement? = nil,
                              venue: VenueID? = nil, rushTier: Int = 0) -> GameSnapshot {
    let liquid = feedbackLiquid()
    let glass = feedbackGlass(id: 1, phase: glassPhase, result: result, lineOpacity: lineOpacity)
    let jug = JugState(liquid: liquid, angle: angle, fill: fill, outline: [], liquidPolygon: [], lip: .zero,
                       pivot: .zero, flow: 0)
    var snapshot = GameSnapshot(time: 0, phase: .playing, mode: mode, jug: jug, stream: [], droplets: [],
                                glasses: [glass], puddles: [], score: 0, streak: 0, multiplier: 1, strikes: 0,
                                maxStrikes: 3, ordersDone: 0, ordersTotal: nil, perfects: 0,
                                telemetry: PourTelemetry(), needsFlat: needsFlat)
    snapshot.venue = venue
    snapshot.rushTier = rushTier
    return snapshot
}

/// Renders `blocks` × 512 frames; the loudest sample and whether every sample was finite.
private func renderPeak(_ synth: PourSynth, blocks: Int) -> (peak: Float, finite: Bool) {
    let frames = 512
    let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    defer { buffer.deallocate() }
    var peak: Float = 0
    var finite = true
    for _ in 0..<blocks {
        synth.render(frames: frames, into: buffer)
        for index in 0..<frames {
            let value = buffer[index]
            if !value.isFinite { finite = false }
            peak = max(peak, abs(value))
        }
    }
    return (peak, finite)
}
