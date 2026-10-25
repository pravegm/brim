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
}

/// A one-glass snapshot for the director's pure helpers.
private func feedbackSnapshot(fill: Double, angle: Double, needsFlat: Bool = false, mode: GameMode = .shift("1-1"),
                              lineOpacity: Double = 1) -> GameSnapshot {
    let liquid = Liquid(id: .water, name: "Water", top: RGBA(0.6, 0.85, 1), bottom: RGBA(0.4, 0.65, 0.95), foam: nil,
                        lagTau: 0.04, foamPerVolume: 0, foamSettle: 1, reposeDegrees: 0, opacity: 0.5, fizzy: false)
    let shape = GlassShape(id: "tumbler", name: "Tumbler", style: .tumbler,
                           profile: [CGPoint(x: 55, y: 0), CGPoint(x: 62, y: 120)], baseThickness: 8, wall: 3)
    let glass = GlassState(id: 1, shape: shape, liquid: liquid, x: 335, phase: .filling, liquidHeight: 40,
                           foamHeight: 0, lineHeight: 96, lineOpacity: lineOpacity, inPerfectBand: false,
                           overflowing: false, patienceLeft: nil, patienceTotal: nil, result: nil)
    let jug = JugState(liquid: liquid, angle: angle, fill: fill, outline: [], liquidPolygon: [], lip: .zero,
                       pivot: .zero, flow: 0)
    return GameSnapshot(time: 0, phase: .playing, mode: mode, jug: jug, stream: [], droplets: [], glasses: [glass],
                        puddles: [], score: 0, streak: 0, multiplier: 1, strikes: 0, maxStrikes: 3, ordersDone: 0,
                        ordersTotal: nil, perfects: 0, telemetry: PourTelemetry(), needsFlat: needsFlat)
}
