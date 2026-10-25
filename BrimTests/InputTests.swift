import CoreGraphics
import Foundation
import Testing
@testable import Brim

// MARK: - Fixtures (memberwise initialisers of the Contracts types)

private func inputTestLiquid() -> Liquid {
    Liquid(id: .water, name: "Water", top: RGBA(0.6, 0.85, 1), bottom: RGBA(0.4, 0.65, 0.95), foam: nil,
           lagTau: 0.04, foamPerVolume: 0, foamSettle: 1, reposeDegrees: 0, opacity: 0.5, fizzy: false)
}

private func inputTestGlass(phase: GlassPhase, overflowing: Bool = false) -> GlassState {
    let shape = GlassShape(id: "tumbler", name: "Tumbler", style: .tumbler,
                           profile: [CGPoint(x: 40, y: 0), CGPoint(x: 46, y: 120)], baseThickness: 8, wall: 3)
    return GlassState(id: 1, shape: shape, liquid: inputTestLiquid(), x: 375, phase: phase, liquidHeight: 0,
                      foamHeight: 0, lineHeight: 96, lineOpacity: 1, inPerfectBand: false, overflowing: overflowing,
                      patienceLeft: nil, patienceTotal: nil, result: nil)
}

private func inputTestSnapshot(glasses: [GlassState], flow: Double = 0, projected: Double = -0.8,
                               phase: SessionPhase = .playing) -> GameSnapshot {
    let liquid = inputTestLiquid()
    let jug = JugState(liquid: liquid, angle: 0, fill: 1, outline: [], liquidPolygon: [], lip: .zero, pivot: .zero,
                       flow: flow)
    let telemetry = PourTelemetry(flow: flow, landingRate: flow, activeFill: 0.1, distanceToLine: projected,
                                  projectedDistanceToLine: projected, liquid: .water)
    return GameSnapshot(time: 0, phase: phase, mode: .practice, jug: jug, stream: [], droplets: [], glasses: glasses,
                        puddles: [], score: 0, streak: 0, multiplier: 1, strikes: 0, maxStrikes: 3, ordersDone: 0,
                        ordersTotal: nil, perfects: 0, telemetry: telemetry)
}

// MARK: - Tests

@MainActor
struct InputTests {
    @Test func oneEuroSmoothsJitter() {
        var filter = OneEuroSmoother(minCutoff: 2.0, beta: 0.12, dCutoff: 1.5)
        var worst = 0.0
        for index in 0..<240 {
            let time = Double(index) / 120
            let noisy = 120.0 + (index % 2 == 0 ? 2.0 : -2.0)
            let out = filter.filter(noisy, at: time)
            if index > 60 { worst = max(worst, abs(out - 120)) }
        }
        #expect(worst < 1.0)
    }

    @Test func oneEuroConvergesAfterAStep() {
        var filter = OneEuroSmoother(minCutoff: 2.0, beta: 0.12, dCutoff: 1.5)
        var time = 0.0
        for _ in 0..<60 {
            _ = filter.filter(100, at: time)
            time += 1.0 / 120
        }
        var out = 0.0
        for _ in 0..<120 {
            out = filter.filter(150, at: time)
            time += 1.0 / 120
        }
        #expect(abs(out - 150) < 0.5)
    }

    @Test func tiltMappingClamps() {
        #expect(HingeTiltSource.lidTilt(forHingeAngle: 190) == 0.0)
        #expect(HingeTiltSource.lidTilt(forHingeAngle: 180) == 0.0)
        #expect(HingeTiltSource.lidTilt(forHingeAngle: 120) == 60.0)
        #expect(HingeTiltSource.lidTilt(forHingeAngle: 90) == 90.0)
        #expect(HingeTiltSource.lidTilt(forHingeAngle: 20) == 90.0)
        #expect(HingeTiltSource.lidTilt(forHingeAngle: Double.nan) == 0.0)
        #expect(HingeTiltSource.hingeAngle(forLidTilt: 30) == 150.0)
    }

    @Test func hingeSourceFollowsSamples() {
        let source = HingeTiltSource()
        #expect(source.hasHinge == false)
        #expect(source.tilt(at: 0) == 0.0)
        var time = 0.0
        var tilt = 0.0
        for frame in 0..<240 {
            time = Double(frame) / 120
            if frame % 4 == 0 { source.ingest(angleDegrees: 120, at: time) }
            tilt = source.tilt(at: time)
        }
        #expect(source.hasHinge)
        #expect(abs(tilt - 60) < 0.5)
        let angle = source.lastAngle ?? -1
        #expect(abs(angle - 120) < 0.5)
    }

    @Test func hingeSourceMovesSmoothlyBetweenSamples() {
        // A steady close from 170° at 40°/s, reported at 30 Hz, read at 120 Hz: no frame-to-frame jump bigger than a
        // couple of degrees (the picture never holds and then steps).
        let source = HingeTiltSource()
        var previous: Double?
        var biggestStep = 0.0
        for frame in 0..<180 {
            let time = Double(frame) / 120
            if frame % 4 == 0 { source.ingest(angleDegrees: 170 - 40 * time, at: time) }
            let tilt = source.tilt(at: time)
            if let previous, frame > 30 { biggestStep = max(biggestStep, abs(tilt - previous)) }
            previous = tilt
        }
        #expect(biggestStep < 2)
    }

    @Test func touchTipsAndEasesBackToZero() {
        let touch = TouchTiltSource(viewHeight: 1000)
        var time = 0.0
        _ = touch.tilt(at: time)
        touch.began(at: 800)
        touch.moved(to: 800 - 225)
        for _ in 0..<120 {
            time += 1.0 / 120
            _ = touch.tilt(at: time)
        }
        #expect(abs(touch.currentTilt - 45) < 1)
        touch.moved(to: 800 - 450)
        for _ in 0..<120 {
            time += 1.0 / 120
            _ = touch.tilt(at: time)
        }
        #expect(touch.currentTilt > 88)
        touch.ended()
        var tilt = touch.currentTilt
        for _ in 0..<36 {
            time += 1.0 / 120
            tilt = touch.tilt(at: time)
        }
        #expect(tilt < 2)
        #expect(tilt >= 0)
    }

    @Test func touchNeverLeavesRange() {
        let touch = TouchTiltSource(viewHeight: 800)
        var time = 0.0
        touch.began(at: 700)
        touch.moved(to: -2000)
        for _ in 0..<60 {
            time += 1.0 / 60
            #expect(touch.tilt(at: time) <= 90)
        }
        touch.moved(to: 5000)
        for _ in 0..<60 {
            time += 1.0 / 60
            #expect(touch.tilt(at: time) >= 0)
        }
    }

    @Test func demoInterpolatesKeyframes() {
        let demo = DemoTiltSource(keyframes: [(t: 0, tilt: 0), (t: 1, tilt: 40), (t: 2, tilt: 40), (t: 3, tilt: 0)],
                                  start: 10)
        #expect(abs(demo.tilt(at: 10.5) - 20) < 1e-9)
        #expect(demo.tilt(at: 9) == 0.0)
        #expect(abs(demo.tilt(at: 11.5) - 40) < 1e-9)
        #expect(abs(demo.tilt(at: 12.5) - 20) < 1e-9)
        #expect(demo.tilt(at: 30) == 0.0)
        let empty = DemoTiltSource(keyframes: [], start: 0)
        #expect(empty.tilt(at: 5) == 0.0)
    }

    @Test func autopilotRestsWithoutAGlass() {
        let noGlass = inputTestSnapshot(glasses: [])
        let pilot = AutopilotTiltSource(style: .perfect) { noGlass }
        var tilt = 1.0
        for frame in 0..<120 { tilt = pilot.tilt(at: Double(frame) / 60) }
        #expect(abs(tilt) < 0.01)

        let arriving = inputTestSnapshot(glasses: [inputTestGlass(phase: .arriving)])
        let waiting = AutopilotTiltSource(style: .perfect) { arriving }
        for frame in 0..<120 { tilt = waiting.tilt(at: Double(frame) / 60) }
        #expect(abs(tilt) < 0.01)

        let nothing = AutopilotTiltSource(style: .spill) { nil }
        for frame in 0..<60 { tilt = nothing.tilt(at: Double(frame) / 60) }
        #expect(abs(tilt) < 0.01)
    }

    @Test func autopilotTipsInWhenFarFromTheLine() {
        let far = inputTestSnapshot(glasses: [inputTestGlass(phase: .filling)], flow: 0, projected: -0.8)
        let pilot = AutopilotTiltSource(style: .perfect) { far }
        var tilt = 0.0
        var previous = 0.0
        var biggestStep = 0.0
        for frame in 0..<90 {
            tilt = pilot.tilt(at: Double(frame) / 60)
            biggestStep = max(biggestStep, abs(tilt - previous))
            previous = tilt
        }
        #expect(tilt > 6)
        #expect(tilt <= 90)
        // Human-like: no jumps (≤ 160°/s at 60 Hz).
        #expect(biggestStep <= 160.0 / 60 + 1e-9)
    }

    @Test func autopilotLaysBackAtTheLine() {
        var snapshot = inputTestSnapshot(glasses: [inputTestGlass(phase: .filling)], flow: 0.5, projected: -0.6)
        let pilot = AutopilotTiltSource(style: .perfect) { snapshot }
        var time = 0.0
        var tilt = 0.0
        for _ in 0..<90 {
            tilt = pilot.tilt(at: time)
            time += 1.0 / 60
        }
        #expect(tilt > 6)
        // The projection reaches the line: the jug goes back upright within half a second.
        snapshot = inputTestSnapshot(glasses: [inputTestGlass(phase: .filling)], flow: 0.2, projected: 0.0)
        for _ in 0..<30 {
            tilt = pilot.tilt(at: time)
            time += 1.0 / 60
        }
        #expect(tilt < 6)
    }

    @Test func autopilotDesiredFlowEasesNearTheLine() {
        #expect(AutopilotTiltSource.desiredFlow(remaining: 0.8) > AutopilotTiltSource.desiredFlow(remaining: 0.1))
        #expect(AutopilotTiltSource.desiredFlow(remaining: 0.1) > AutopilotTiltSource.desiredFlow(remaining: 0.01))
        #expect(AutopilotStyle.great.stopDistance > AutopilotStyle.perfect.stopDistance)
        #expect(AutopilotStyle.short.stopDistance < AutopilotStyle.perfect.stopDistance)
    }
}
