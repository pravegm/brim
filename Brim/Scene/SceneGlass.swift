import SpriteKit
import UIKit

/// Per-frame inputs a glass needs from the scene besides its `GlassState`.
struct GlassFrame {
    var counterY: CGFloat
    /// Simulation dt (0 while the session is paused or frozen, so the frame holds still).
    var dt: CGFloat
    var time: Double
    var pouring: Bool
    var tail: StreamPoint?
    var advanced: Bool
    var reduceMotion: Bool
    /// Perfect band half-width as a fraction of interior height.
    var band: Double
    /// The projected (everything-in-the-air-has-landed) distance to the line, if this is the active glass.
    var projected: Double?
    /// World x range stamps and pops must stay inside (the iPhone crop).
    var safeX: ClosedRange<CGFloat>
}

/// One glass on the counter. Two roots so the stream can be drawn *between* them:
/// `back` (patience ring, shadow, interior, liquid, foam, bubbles, surface flash) sits under the stream, `front`
/// (walls, ink outline, highlights, rim, Perfect band, fill line, overflow sheet, stamp) sits over it. Both roots
/// share the glass's local frame: origin = centre of the inner floor, y up (the profile's interior coordinates).
@MainActor
final class SceneGlass {
    let id: Int
    let back: SKNode
    let front: SKNode

    // back
    private let patienceTrack: SKShapeNode
    private let patienceArc: SKShapeNode
    private let shadow: SKShapeNode
    private let interior: SKShapeNode
    private let rimBack: SKShapeNode
    private let liquid: SKShapeNode
    private let surface: SKShapeNode
    private let foam: SKShapeNode
    private let foamBubbles: SKShapeNode
    private let bubbles: SKShapeNode
    private let surfaceFlash: SKSpriteNode

    // front
    private let walls: SKShapeNode
    private let outline: SKShapeNode
    private let highlight: SKShapeNode
    private let highlight2: SKShapeNode
    private let shade: SKShapeNode
    private let rimFront: SKShapeNode
    private let extraOutline: SKShapeNode
    private let extra: SKShapeNode
    private let band: SKShapeNode
    private let bandEdges: SKShapeNode
    private let lineGlow: SKShapeNode
    private let lineHalo: SKShapeNode
    private let lineInk: SKShapeNode
    private let tab: SKShapeNode
    private let overflow: SKShapeNode
    private let overflowShine: SKShapeNode
    private let wetSheen: SKShapeNode
    private let stamp: SKSpriteNode

    private(set) var shapeID = ""
    private var profile: [CGPoint] = []
    private(set) var rimY: CGFloat = 0
    private(set) var rimHW: CGFloat = 0
    private var wallW: CGFloat = 3
    private(set) var base: CGFloat = 6
    private var footHW: CGFloat = 20
    private var isStemmed = false
    private var builtLine: CGFloat = -1
    private var builtBand: CGFloat = -1
    private var liquidID: LiquidID?
    private var wave = SceneWave()
    private var rng: SceneRNG
    private var bubbleX: [CGFloat] = []
    private var bubbleY: [CGFloat] = []
    private var bubbleSpeed: [CGFloat] = []
    private var bubbleR: [CGFloat] = []
    private var bubblePhase: [CGFloat] = []
    private var foamBumps: [CGFloat] = []
    private var lastX: CGFloat?
    private var lastVX: CGFloat = 0
    private var velocityValid = false
    private var shownResult: Judgement?
    private var lastPatience: CGFloat = -1
    private var lineState: Int = -1
    private var flash: CGFloat = 0
    private var lockFlash: CGFloat = 0
    private var celebrateAt: Double?
    private var overflowAt: Double?
    private var wetUntil: Double = -1
    private var lastOverflowing = false
    private var simTime: Double = 0
    private let darkBackdrop: Bool

    private(set) var liquidColor: UIColor = .white
    private(set) var level: CGFloat = 0
    private(set) var x: CGFloat = 0
    private var counterY: CGFloat = 0
    var lastCrownTime: Double = -10
    var lastDripTime: Double = -10

    static let bubbleCount = 12
    static let foamBubbleCount = 9

    init(id: Int, darkBackdrop: Bool) {
        self.id = id
        self.darkBackdrop = darkBackdrop
        rng = SceneRNG(seed: UInt64(truncatingIfNeeded: id &* 7919 &+ 17))
        back = SKNode()
        front = SKNode()
        patienceTrack = SKShapeNode()
        patienceArc = SKShapeNode()
        shadow = SKShapeNode()
        interior = SKShapeNode()
        rimBack = SKShapeNode()
        liquid = SKShapeNode()
        surface = SKShapeNode()
        foam = SKShapeNode()
        foamBubbles = SKShapeNode()
        bubbles = SKShapeNode()
        surfaceFlash = SKSpriteNode(texture: SceneArt.glow)
        walls = SKShapeNode()
        outline = SKShapeNode()
        highlight = SKShapeNode()
        highlight2 = SKShapeNode()
        shade = SKShapeNode()
        rimFront = SKShapeNode()
        extraOutline = SKShapeNode()
        extra = SKShapeNode()
        band = SKShapeNode()
        bandEdges = SKShapeNode()
        lineGlow = SKShapeNode()
        lineHalo = SKShapeNode()
        lineInk = SKShapeNode()
        tab = SKShapeNode()
        overflow = SKShapeNode()
        overflowShine = SKShapeNode()
        wetSheen = SKShapeNode()
        stamp = SKSpriteNode()

        let ink = SceneColor.ink
        // back
        patienceTrack.strokeColor = darkBackdrop ? UIColor(white: 1, alpha: 0.22) : ink.withAlphaComponent(0.16)
        patienceTrack.fillColor = .clear
        patienceTrack.lineWidth = 6
        patienceTrack.zPosition = -1
        patienceArc.fillColor = .clear
        patienceArc.lineWidth = 6
        patienceArc.lineCap = .round
        patienceArc.zPosition = -0.9
        shadow.fillColor = ink.withAlphaComponent(darkBackdrop ? 0.38 : 0.2)
        shadow.strokeColor = .clear
        shadow.zPosition = 0
        interior.fillColor = UIColor(white: 1, alpha: darkBackdrop ? 0.12 : 0.2)
        interior.strokeColor = .clear
        interior.zPosition = 1
        rimBack.strokeColor = darkBackdrop ? UIColor(white: 1, alpha: 0.35) : ink.withAlphaComponent(0.3)
        rimBack.lineWidth = 1.8
        rimBack.fillColor = .clear
        rimBack.zPosition = 2
        liquid.fillColor = .white
        liquid.strokeColor = .clear
        liquid.zPosition = 4
        surface.fillColor = .clear
        surface.lineWidth = 2.6
        surface.lineCap = .round
        surface.zPosition = 4.5
        foam.fillColor = .white
        foam.lineWidth = 1.6
        foam.zPosition = 5
        foamBubbles.fillColor = .clear
        foamBubbles.lineWidth = 0.9
        foamBubbles.zPosition = 5.2
        bubbles.fillColor = UIColor(white: 1, alpha: 0.35)
        bubbles.strokeColor = UIColor(white: 1, alpha: 0.85)
        bubbles.lineWidth = 0.8
        bubbles.zPosition = 6
        surfaceFlash.zPosition = 6.5
        surfaceFlash.alpha = 0
        surfaceFlash.isHidden = true
        surfaceFlash.blendMode = .add
        for n in [patienceTrack, patienceArc, shadow, interior, rimBack, liquid, surface, foam, foamBubbles, bubbles] {
            back.addChild(n)
        }
        back.addChild(surfaceFlash)

        // front
        walls.fillColor = UIColor(white: 1, alpha: darkBackdrop ? 0.2 : 0.3)
        walls.strokeColor = .clear
        walls.zPosition = 0
        outline.strokeColor = darkBackdrop ? UIColor(white: 1, alpha: 0.7) : ink.withAlphaComponent(0.66)
        outline.fillColor = .clear
        outline.lineWidth = 2.4
        outline.lineJoin = .round
        outline.zPosition = 0.05
        extraOutline.strokeColor = darkBackdrop ? UIColor(white: 1, alpha: 0.6) : ink.withAlphaComponent(0.66)
        extraOutline.fillColor = .clear
        extraOutline.lineWidth = 12
        extraOutline.lineCap = .round
        extraOutline.zPosition = 0.1
        extra.strokeColor = UIColor(white: 1, alpha: 0.75)
        extra.fillColor = .clear
        extra.lineWidth = 8
        extra.lineCap = .round
        extra.zPosition = 0.2
        highlight.strokeColor = UIColor(white: 1, alpha: 0.88)
        highlight.fillColor = .clear
        highlight.lineWidth = 4.5
        highlight.lineCap = .round
        highlight.zPosition = 1
        highlight2.strokeColor = UIColor(white: 1, alpha: 0.55)
        highlight2.fillColor = .clear
        highlight2.lineWidth = 2.5
        highlight2.lineCap = .round
        highlight2.zPosition = 1
        shade.strokeColor = ink.withAlphaComponent(0.13)
        shade.fillColor = .clear
        shade.lineWidth = 3.5
        shade.lineCap = .round
        shade.zPosition = 1
        rimFront.strokeColor = UIColor(white: 1, alpha: 0.97)
        rimFront.fillColor = .clear
        rimFront.lineWidth = 3
        rimFront.lineCap = .round
        rimFront.zPosition = 2
        band.fillColor = SceneColor.perfect
        band.strokeColor = .clear
        band.zPosition = 2.6
        bandEdges.strokeColor = SceneColor.perfect.withAlphaComponent(0.75)
        bandEdges.fillColor = .clear
        bandEdges.lineWidth = 1
        bandEdges.zPosition = 2.65
        lineGlow.fillColor = .clear
        lineGlow.lineCap = .round
        lineGlow.zPosition = 3
        lineHalo.strokeColor = UIColor(white: 1, alpha: 0.95)
        lineHalo.fillColor = .clear
        lineHalo.lineWidth = 6
        lineHalo.lineCap = .round
        lineHalo.zPosition = 3.1
        lineInk.strokeColor = ink.withAlphaComponent(0.85)
        lineInk.fillColor = .clear
        lineInk.lineWidth = 3
        lineInk.lineCap = .round
        lineInk.zPosition = 3.2
        tab.lineWidth = 1.6
        tab.strokeColor = ink.withAlphaComponent(0.7)
        tab.zPosition = 3.3
        overflow.strokeColor = .clear
        overflow.zPosition = 5
        overflowShine.fillColor = .clear
        overflowShine.strokeColor = UIColor(white: 1, alpha: 0.55)
        overflowShine.lineWidth = 2.5
        overflowShine.lineCap = .round
        overflowShine.zPosition = 5.1
        wetSheen.strokeColor = .clear
        wetSheen.zPosition = 4.9
        stamp.zPosition = 40
        stamp.isHidden = true
        for n in [walls, outline, extraOutline, extra, highlight, highlight2, shade, rimFront, band, bandEdges, lineGlow,
                  lineHalo, lineInk, tab, wetSheen, overflow, overflowShine] {
            front.addChild(n)
        }
        front.addChild(stamp)

        for _ in 0..<SceneGlass.bubbleCount {
            bubbleX.append(rng.range(-0.8, 0.8))
            bubbleY.append(rng.range(0, 1))
            bubbleSpeed.append(rng.range(26, 70))
            bubbleR.append(rng.range(1.1, 2.6))
            bubblePhase.append(rng.range(0, 6.28))
        }
        for _ in 0..<SceneWave.count { foamBumps.append(rng.range(2.4, 5.2)) }
    }

    func remove() {
        back.removeFromParent()
        front.removeFromParent()
    }

    // MARK: World-space helpers for the scene's FX

    var rimWorld: CGPoint { CGPoint(x: x, y: counterY + base + rimY) }
    var surfaceWorldY: CGFloat { counterY + base + level }
    var outerRimHalfWidth: CGFloat { rimHW + wallW }
    var innerRimHalfWidth: CGFloat { rimHW }
    /// Liquid half-width at the current level (for splashes that must stay inside the mouth).
    var surfaceHalfWidth: CGFloat { ScenePaths.halfWidth(profile, at: level) }
    /// True once the glass has stopped sliding (used to place the coaster under the pour spot).
    var isStill: Bool { velocityValid && abs(lastVX) < 4 }
    var baseOuterHalfWidth: CGFloat { (isStemmed ? footHW : (profile.first?.x ?? 20) + wallW) }
    var velocityX: CGFloat { velocityValid ? lastVX : 0 }
    /// Spilled and still dripping (the wet glass leaving).
    var isWet: Bool { simTime < wetUntil }

    /// 0…1 across the liquid surface if `worldX` is inside the mouth, else nil.
    func surfaceFraction(worldX: CGFloat) -> CGFloat? {
        let hw = max(1, ScenePaths.halfWidth(profile, at: level))
        let dx = worldX - x
        if abs(dx) > hw + 3 { return nil }
        return min(max((dx + hw) / (2 * hw), 0), 1)
    }

    func splash(worldX: CGFloat, strength: Double) {
        guard let f = surfaceFraction(worldX: worldX) else { return }
        let s = CGFloat(min(max(strength, 0), 2))
        wave.kick(at: f, impulse: -(6 + s * 30))
    }

    func slosh(_ amount: CGFloat) { wave.slosh(amount) }

    /// The level just entered the Perfect band: a soft glow pulse.
    func flashLine() { flash = max(flash, 0.7) }

    /// `.lockedIn`: the stream finished landing inside the band — a bright cyan flash of the whole line.
    func lockIn() {
        lockFlash = 1
        flash = 1
    }

    /// Perfect: surface flash, the line turns solid cyan, the glass hops (P0-5).
    func celebrate() {
        celebrateAt = simTime
        flash = 1
        wave.slosh(3)
    }

    /// Spill: the lip bulges, then a thick sheet breaks over the front (P1-2).
    func startOverflow() {
        if overflowAt == nil { overflowAt = simTime }
        wave.slosh(6)
    }

    /// The spilled glass stays wet and drips for a while as it leaves.
    func markWet(seconds: Double) {
        wetUntil = max(wetUntil, simTime + seconds)
    }

    // MARK: Per frame

    func update(_ g: GlassState, _ f: GlassFrame) {
        simTime = f.time
        if g.shape.id != shapeID || profile.isEmpty { rebuild(g.shape) }
        if liquidID != g.liquid.id {
            liquidID = g.liquid.id
            liquid.fillTexture = SceneArt.liquidTexture(g.liquid)
            liquid.fillColor = .white
            let top = SceneColor.opaque(g.liquid.top.skColor)
            liquidColor = SceneColor.mix(SceneColor.opaque(g.liquid.bottom.skColor), top, 0.6)
            surface.strokeColor = SceneColor.lighter(top, 0.65)
            foam.fillTexture = SceneArt.foamTexture(g.liquid)
            foam.fillColor = .white
            let foamColor = SceneColor.opaque(g.liquid.foam?.skColor ?? SceneColor.foamDefault)
            foam.strokeColor = SceneColor.lighter(foamColor, 0.75)
            foamBubbles.strokeColor = SceneColor.darker(foamColor, 0.18).withAlphaComponent(0.5)
            overflow.fillColor = SceneColor.lighter(liquidColor, 0.08).withAlphaComponent(0.82)
            wetSheen.fillColor = SceneColor.lighter(liquidColor, 0.15).withAlphaComponent(0.28)
            surfaceFlash.color = SceneColor.lighter(top, 0.8)
            surfaceFlash.colorBlendFactor = 0.3
        }

        counterY = f.counterY
        x = g.x

        let h = min(max(g.liquidHeight, 0), rimY)
        let foamH = max(0, g.foamHeight)
        level = min(h + foamH, rimY + 2)

        // Slosh from the glass's own acceleration (arrive / leave / conveyor), then the stream's impact.
        let dt = f.dt
        if f.advanced && dt > 0.0001 {
            if let lx = lastX {
                let vx = (g.x - lx) / dt
                if velocityValid {
                    let ax = min(max((vx - lastVX) / dt, -12000), 12000)
                    wave.slosh(-ax * dt * 0.028)
                }
                lastVX = vx
                velocityValid = true
            }
            lastX = g.x
            if let t = f.tail, h > 1, abs(t.position.y - surfaceWorldY) < 30, let fr = surfaceFraction(worldX: t.position.x) {
                wave.kick(at: fr, impulse: -dt * (14 + t.width * 6))
            }
        }
        wave.step(dt)
        if flash > 0 { flash = max(0, flash - dt * 2.4) }
        if lockFlash > 0 { lockFlash = max(0, lockFlash - dt * 3) }
        if g.overflowing && !lastOverflowing { startOverflow() }
        if g.overflowing { markWet(seconds: 1.6) }
        lastOverflowing = g.overflowing

        placeRoots(g, f)
        drawLiquid(h: h, foamH: foamH, g: g, dt: dt, time: f.time, reduceMotion: f.reduceMotion)
        drawSurfaceFlash(h: h)
        drawLine(g, f)
        drawOverflow(g, time: f.time)
        drawPatience(g, time: f.time)
        drawStamp(g, f)
    }

    /// Position + the Perfect hop (squash, stretch, a little jump), scaled about the base so it stays on the counter.
    private func placeRoots(_ g: GlassState, _ f: GlassFrame) {
        var sx: CGFloat = 1, sy: CGFloat = 1, dy: CGFloat = 0
        if let t0 = celebrateAt, !f.reduceMotion {
            let t = CGFloat(f.time - t0)
            if t >= 0 && t < 0.6 {
                let s = -0.06 * cos(t * 2 * .pi / 0.32) * exp(-t * 6.5)
                sy = 1 + s
                sx = 1 - s * 0.8
                let k = min(max((t - 0.05) / 0.3, 0), 1)
                dy = 13 * sin(k * .pi)
            } else if t >= 0.6 {
                celebrateAt = nil
            }
        }
        let pos = CGPoint(x: g.x, y: f.counterY + base * sy + dy)
        back.position = pos
        front.position = pos
        back.xScale = sx
        back.yScale = sy
        front.xScale = sx
        front.yScale = sy
        // The ring/shadow stay on the counter while the glass is in the air.
        shadow.position = CGPoint(x: 0, y: -dy / max(sy, 0.01))
        shadow.alpha = max(0.45, 1 - dy / 26)
    }

    // MARK: Liquid, foam, bubbles

    private func surfacePoints(height h: CGFloat, widthAt wh: CGFloat, waveScale: CGFloat, cap: CGFloat) -> [CGPoint] {
        let n = SceneWave.count
        let hw = max(0.5, ScenePaths.halfWidth(profile, at: wh) - 0.3)
        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            let fr = CGFloat(i) / CGFloat(n - 1)
            let yy = min(max(h + wave.h[i] * waveScale, 0), cap)
            pts.append(CGPoint(x: -hw + 2 * hw * fr, y: yy))
        }
        return pts
    }

    private func drawLiquid(h: CGFloat, foamH: CGFloat, g: GlassState, dt: CGFloat, time: Double, reduceMotion: Bool) {
        guard h > 0.4 else {
            liquid.isHidden = true
            surface.isHidden = true
            foam.isHidden = true
            foamBubbles.isHidden = true
            bubbles.isHidden = true
            return
        }
        let n = SceneWave.count
        let waveScale = min(1, h / 18)
        let surf = surfacePoints(height: h, widthAt: h, waveScale: waveScale, cap: rimY + 2)

        let lp = CGMutablePath()
        lp.move(to: surf[n - 1])
        for p in profile.reversed() where p.y < h - 0.3 { lp.addLine(to: CGPoint(x: p.x, y: p.y)) }
        for p in profile where p.y < h - 0.3 { lp.addLine(to: CGPoint(x: -p.x, y: p.y)) }
        lp.addLine(to: surf[0])
        ScenePaths.addSmoothCurve(lp, surf)
        lp.closeSubpath()
        liquid.path = lp
        liquid.isHidden = false
        liquid.alpha = CGFloat(0.62 + 0.38 * min(max(g.liquid.opacity, 0), 1))

        let sp = CGMutablePath()
        sp.move(to: surf[0])
        ScenePaths.addSmoothCurve(sp, surf)
        surface.path = sp
        surface.isHidden = false

        // Foam head: a bumpy dome that rises in the middle, with micro-bubbles; the top edge sinks as it settles.
        if foamH > 0.3 {
            let topH = min(h + foamH, rimY + (g.overflowing ? 5 : 1.5))
            let fs = surfacePoints(height: topH, widthAt: min(topH, rimY), waveScale: waveScale * 0.8, cap: rimY + 6)
            let dome = min(7, foamH * 0.4)
            let fp = CGMutablePath()
            fp.move(to: surf[0])
            ScenePaths.addSmoothCurve(fp, surf)
            fp.addLine(to: fs[n - 1])
            var i = n - 1
            let t = CGFloat(time)
            let hw = max(1, abs(fs[n - 1].x))
            while i > 0 {
                let a = fs[i], b = fs[i - 1]
                let mx = (a.x + b.x) * 0.5
                let u = mx / hw
                let domeY = dome * max(0, 1 - u * u)
                let bump = min(foamBumps[i] + 0.8 * sin(t * 1.7 + CGFloat(i) * 1.3), foamH * 0.7 + 1)
                let by = b.y + dome * max(0, 1 - (b.x / hw) * (b.x / hw))
                fp.addQuadCurve(to: CGPoint(x: b.x, y: by), control: CGPoint(x: mx, y: max(a.y, b.y) + domeY + bump))
                i -= 1
            }
            fp.closeSubpath()
            foam.path = fp
            foam.isHidden = false

            // Micro-bubbles in the head.
            let bp = CGMutablePath()
            let count = reduceMotion ? 4 : SceneGlass.foamBubbleCount
            for k in 0..<count {
                let fx = CGFloat(k) / CGFloat(max(count - 1, 1)) * 1.6 - 0.8 + 0.06 * sin(CGFloat(k) * 3.1)
                let fyFrac = 0.25 + 0.5 * (0.5 + 0.5 * sin(CGFloat(k) * 2.3))
                let by = h + (topH - h) * fyFrac
                let bx = fx * max(0, ScenePaths.halfWidth(profile, at: min(by, rimY)) - 4)
                let r = 0.9 + 0.8 * (0.5 + 0.5 * sin(CGFloat(k) * 1.7))
                if topH - h > r * 2 + 1 {
                    bp.addEllipse(in: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2))
                }
            }
            foamBubbles.path = bp
            foamBubbles.isHidden = false
        } else {
            foam.isHidden = true
            foamBubbles.isHidden = true
        }

        // Rising bubbles (fizzy drinks).
        if g.liquid.fizzy && h > 8 {
            let bp = CGMutablePath()
            let t = CGFloat(time)
            let count = reduceMotion ? SceneGlass.bubbleCount / 2 : SceneGlass.bubbleCount
            for i in 0..<count {
                bubbleY[i] += bubbleSpeed[i] * dt / max(h, 1)
                if bubbleY[i] >= 1 {
                    bubbleY[i] = rng.range(0, 0.25)
                    bubbleX[i] = rng.range(-0.8, 0.8)
                    bubbleSpeed[i] = rng.range(26, 70)
                }
                let by = 2 + bubbleY[i] * (h - 5)
                let hw = ScenePaths.halfWidth(profile, at: by)
                let r = bubbleR[i] * (0.7 + 0.3 * bubbleY[i])
                let bx = bubbleX[i] * max(0, hw - r - 2) + sin(t * 3 + bubblePhase[i]) * 1.4
                bp.addEllipse(in: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2))
            }
            bubbles.path = bp
            bubbles.isHidden = false
        } else {
            bubbles.isHidden = true
        }
    }

    /// Perfect: a white flash across the surface (0.25 s).
    private func drawSurfaceFlash(h: CGFloat) {
        guard let t0 = celebrateAt, h > 0.4 else {
            surfaceFlash.isHidden = true
            return
        }
        let t = CGFloat(simTime - t0)
        let a = t < 0.04 ? t / 0.04 : max(0, 1 - (t - 0.04) / 0.22)
        if a <= 0.001 {
            surfaceFlash.isHidden = true
            return
        }
        let hw = ScenePaths.halfWidth(profile, at: level)
        surfaceFlash.isHidden = false
        surfaceFlash.alpha = a
        surfaceFlash.size = CGSize(width: hw * 2.6, height: 34 + 20 * a)
        surfaceFlash.position = CGPoint(x: 0, y: level)
    }

    // MARK: Fill line + Perfect band

    private func buildLine(_ L: CGFloat, bandFrac: CGFloat) {
        builtLine = L
        builtBand = bandFrac
        let hw = ScenePaths.halfWidth(profile, at: L)
        let x0 = -(hw + wallW + 8), x1 = hw + wallW + 8
        let base = CGMutablePath()
        base.move(to: CGPoint(x: x0, y: L))
        base.addLine(to: CGPoint(x: x1, y: L))
        lineGlow.path = base
        lineHalo.path = base
        lineInk.path = base
        // The tab: a pointer + rounded flag, 1.5× round 1.
        let tp = CGMutablePath()
        let tx = x1 + 2
        tp.move(to: CGPoint(x: tx, y: L))
        tp.addLine(to: CGPoint(x: tx + 10, y: L + 7.5))
        tp.addLine(to: CGPoint(x: tx + 10, y: L - 7.5))
        tp.closeSubpath()
        tp.addRoundedRect(in: CGRect(x: tx + 9, y: L - 9.5, width: 22, height: 19), cornerWidth: 6, cornerHeight: 6)
        tab.path = tp
        // Band: ± band × interior height, across the inside of the glass.
        let bandH = max(1.5, rimY * bandFrac)
        let y0 = max(0, L - bandH), y1 = min(rimY, L + bandH)
        let hw0 = max(1, ScenePaths.halfWidth(profile, at: y0) - 0.5)
        let hw1 = max(1, ScenePaths.halfWidth(profile, at: y1) - 0.5)
        let bp = CGMutablePath()
        bp.move(to: CGPoint(x: -hw0, y: y0))
        bp.addLine(to: CGPoint(x: hw0, y: y0))
        bp.addLine(to: CGPoint(x: hw1, y: y1))
        bp.addLine(to: CGPoint(x: -hw1, y: y1))
        bp.closeSubpath()
        band.path = bp
        let ep = CGMutablePath()
        ep.move(to: CGPoint(x: -hw0, y: y0))
        ep.addLine(to: CGPoint(x: hw0, y: y0))
        ep.move(to: CGPoint(x: -hw1, y: y1))
        ep.addLine(to: CGPoint(x: hw1, y: y1))
        bandEdges.path = ep
        lineState = -1
    }

    private func drawLine(_ g: GlassState, _ f: GlassFrame) {
        let bandFrac = CGFloat(min(max(f.band, 0.008), 0.08))
        if abs(g.lineHeight - builtLine) > 0.25 || abs(bandFrac - builtBand) > 0.0005 { buildLine(g.lineHeight, bandFrac: bandFrac) }
        var a = CGFloat(min(max(g.lineOpacity, 0), 1))
        if g.result == .short {
            a *= 0.55 + 0.45 * CGFloat(0.5 + 0.5 * sin(f.time * 9))     // the sad pulse
        }
        let hidden = a < 0.01
        for n in [lineGlow, lineHalo, lineInk, tab] {
            n.isHidden = hidden
            n.alpha = a
        }
        // 0 normal, 1 in band, 2 perfect (solid cyan), 3 missed.
        var state = 0
        if g.result == .perfect { state = 2 } else if g.result != nil { state = 3 } else if g.inPerfectBand { state = 1 }
        if state != lineState {
            lineState = state
            switch state {
            case 2:
                lineInk.strokeColor = SceneColor.perfect
                lineGlow.strokeColor = SceneColor.perfect.withAlphaComponent(0.7)
                tab.fillColor = SceneColor.perfect
            case 1:
                lineInk.strokeColor = SceneColor.ink.withAlphaComponent(0.9)
                lineGlow.strokeColor = SceneColor.perfect.withAlphaComponent(0.65)
                tab.fillColor = SceneColor.perfect
            default:
                lineInk.strokeColor = SceneColor.ink.withAlphaComponent(0.85)
                lineGlow.strokeColor = SceneColor.gold.withAlphaComponent(0.4)
                tab.fillColor = SceneColor.gold
            }
        }
        let lock = lockFlash
        lineInk.lineWidth = state == 2 ? 4 : 3
        lineHalo.lineWidth = 6 + lock * 4
        lineHalo.strokeColor = lock > 0.02 ? SceneColor.mix(UIColor.white, SceneColor.perfect, lock * 0.8) : UIColor(white: 1, alpha: 0.95)
        lineGlow.lineWidth = (state >= 1 && state <= 2 ? 14 : 9) + flash * 14 + lock * 10
        lineGlow.isHidden = hidden

        // Perfect band: visible all the while the glass is being filled; brighter when the projected level is in it.
        let showBand = g.phase == .filling && !hidden && g.result == nil
        band.isHidden = !showBand
        bandEdges.isHidden = !showBand
        if showBand {
            var projectedIn = g.inPerfectBand
            if let pr = f.projected { projectedIn = projectedIn || abs(pr) <= f.band }
            let pulse: CGFloat = projectedIn ? 0.06 * CGFloat(0.5 + 0.5 * sin(f.time * 10)) : 0
            band.alpha = a * ((projectedIn ? 0.4 : (f.pouring ? 0.2 : 0.14)) + pulse + lock * 0.3)
            bandEdges.alpha = a * (projectedIn ? 0.95 : 0.55)
        }
    }

    // MARK: Overflow sheet (spill)

    private func drawOverflow(_ g: GlassState, time: Double) {
        let wet = isWet
        guard (g.overflowing || wet), profile.count >= 2 else {
            overflow.isHidden = true
            overflowShine.isHidden = true
            wetSheen.isHidden = true
            if !g.overflowing && !wet { overflowAt = nil }
            return
        }
        let t = CGFloat(time)
        let since = CGFloat(time - (overflowAt ?? time))
        let bottom: CGFloat = isStemmed ? 0 : -base
        let fullDrop = rimY - bottom
        // Fade the sheet once the pour has stopped (the glass leaves wet).
        let strength: CGFloat = g.overflowing ? 1 : max(0, CGFloat(wetUntil - time) / 1.6)
        let path = CGMutablePath()
        let shinePath = CGMutablePath()

        // 1. The lip bulge (meniscus over the rim) — big at first, then it breaks into the sheet.
        let bulgeK = g.overflowing ? (since < 0.16 ? since / 0.16 : max(0.35, 1 - (since - 0.16) * 2)) : 0
        if bulgeK > 0.01 {
            let ry = 3 + 7 * bulgeK
            let bulge = CGMutablePath()
            bulge.move(to: CGPoint(x: -rimHW - wallW * 0.5, y: rimY))
            bulge.addQuadCurve(to: CGPoint(x: rimHW + wallW * 0.5, y: rimY), control: CGPoint(x: 0, y: rimY + ry * 2))
            bulge.closeSubpath()
            path.addPath(bulge)
        }

        // 2. Side sheets running down both walls, thick and wobbling.
        let grow = min(1, max(0, (since - 0.08) / 0.35))
        let len = fullDrop * (g.overflowing ? grow : 1)
        if len > 2 {
            let samples = 10
            for side in [CGFloat(-1), CGFloat(1)] {
                var outer: [CGPoint] = []
                var inner: [CGPoint] = []
                for k in 0...samples {
                    let y = rimY - len * CGFloat(k) / CGFloat(samples)
                    let xw = ScenePaths.halfWidth(profile, at: max(y, 0)) + wallW
                    let th = max(1.5, (4.5 + 2 * sin(t * 7 + CGFloat(k) * 0.9 + side)) * strength)
                    outer.append(CGPoint(x: side * (xw + 0.4 + th), y: y))
                    inner.append(CGPoint(x: side * (xw - 0.4), y: y))
                }
                path.move(to: CGPoint(x: side * (rimHW - 1), y: rimY + 2))
                for p in outer { path.addLine(to: p) }
                let lastX = outer[outer.count - 1].x
                let lastY = outer[outer.count - 1].y
                path.addQuadCurve(to: CGPoint(x: side * (abs(lastX) - 7), y: lastY - 2),
                                  control: CGPoint(x: lastX + side * 6, y: lastY - 5))
                var i = inner.count - 1
                while i >= 0 {
                    path.addLine(to: inner[i])
                    i -= 1
                }
                path.closeSubpath()
            }

            // 3. The front curtain: ≥ 40 % of the rim width, sheeting down the face of the glass.
            let cx = -rimHW * 0.12 + 2 * sin(t * 2.3)
            let topHW = rimHW * 0.46 * max(0.35, strength)
            let curtain = CGMutablePath()
            var left: [CGPoint] = []
            var right: [CGPoint] = []
            let steps = 8
            for k in 0...steps {
                let fk = CGFloat(k) / CGFloat(steps)
                let y = rimY + 1 - len * fk
                let w = topHW * (1 - 0.4 * fk) + 2.5 * sin(t * 6 + fk * 7)
                let sway = 3 * sin(t * 4 + fk * 5)
                left.append(CGPoint(x: cx - w + sway, y: y))
                right.append(CGPoint(x: cx + w + sway, y: y))
            }
            curtain.move(to: left[0])
            for p in left.dropFirst() { curtain.addLine(to: p) }
            let lb = left[left.count - 1], rb = right[right.count - 1]
            curtain.addQuadCurve(to: rb, control: CGPoint(x: (lb.x + rb.x) * 0.5, y: lb.y - 10))
            var j = right.count - 1
            while j >= 0 {
                curtain.addLine(to: right[j])
                j -= 1
            }
            curtain.closeSubpath()
            path.addPath(curtain)
            shinePath.move(to: CGPoint(x: left[0].x + topHW * 0.35, y: rimY - 4))
            shinePath.addLine(to: CGPoint(x: left[steps / 2].x + topHW * 0.3, y: rimY - len * 0.5))
        }
        overflow.path = path
        overflow.isHidden = false
        overflow.alpha = max(0.15, strength)
        overflowShine.path = shinePath
        overflowShine.isHidden = shinePath.isEmpty
        overflowShine.alpha = strength

        // Wet walls: a translucent film over the whole outside.
        wetSheen.isHidden = false
        wetSheen.alpha = min(1, strength + 0.4)
    }

    // MARK: Patience ring (attached to the glass: drains around the coaster, P2-2)

    private func drawPatience(_ g: GlassState, time: Double) {
        guard let left = g.patienceLeft, let total = g.patienceTotal, total > 0, g.result == nil else {
            patienceTrack.isHidden = true
            patienceArc.isHidden = true
            lastPatience = -1
            return
        }
        let frac = CGFloat(min(max(left / total, 0), 1))
        let rx = baseOuterHalfWidth + 24
        let ry = max(7, rx * 0.2)
        let c = CGPoint(x: 0, y: -base + 1)
        if patienceTrack.isHidden || lastPatience < 0 {
            patienceTrack.path = CGPath(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2), transform: nil)
        }
        patienceTrack.isHidden = false
        if abs(frac - lastPatience) > 0.004 {
            lastPatience = frac
            // Starts at the front (nearest the player) and drains clockwise.
            let a0 = -CGFloat.pi / 2
            let pts = ScenePaths.ellipseArc(center: c, rx: rx, ry: ry, from: a0, to: a0 - 2 * .pi * max(frac, 0.001),
                                            segments: max(2, Int(48 * frac)))
            patienceArc.path = ScenePaths.polygon(pts, closed: false)
            patienceArc.strokeColor = frac > 0.5 ? SceneColor.leaf : (frac > 0.25 ? SceneColor.gold : SceneColor.coral)
        }
        patienceArc.isHidden = false
        patienceArc.alpha = frac < 0.25 ? 0.6 + 0.4 * CGFloat(0.5 + 0.5 * sin(time * 12)) : 1
    }

    // MARK: Result stamp + streak

    /// Local x that keeps a sprite of half-width `hw` inside the safe world range.
    private func clampedLocalX(halfWidth hw: CGFloat, _ f: GlassFrame) -> CGFloat {
        let lo = f.safeX.lowerBound + hw, hi = f.safeX.upperBound - hw
        let wx = lo <= hi ? min(max(x, lo), hi) : (f.safeX.lowerBound + f.safeX.upperBound) * 0.5
        return wx - x
    }

    private func drawStamp(_ g: GlassState, _ f: GlassFrame) {
        let r = g.result
        if r != shownResult {
            shownResult = r
            stamp.removeAllActions()
            if let j = r {
                let art = SceneArt.stamp(j)
                stamp.texture = art.texture
                stamp.size = art.size
                stamp.zRotation = j == .perfect ? -0.05 : 0.05
                stamp.isHidden = false
                if f.reduceMotion {
                    stamp.setScale(1)
                    stamp.alpha = 0
                    stamp.run(SKAction.fadeIn(withDuration: 0.12))
                } else {
                    stamp.setScale(0.3)
                    stamp.alpha = 0
                    let up = SKAction.scale(to: 1.2, duration: 0.11)
                    up.timingMode = .easeOut
                    let down = SKAction.scale(to: 0.94, duration: 0.08)
                    down.timingMode = .easeInEaseOut
                    let settle = SKAction.scale(to: 1.0, duration: 0.08)
                    settle.timingMode = .easeOut
                    stamp.run(SKAction.group([SKAction.fadeIn(withDuration: 0.06), SKAction.sequence([up, down, settle])]))
                }
            } else {
                stamp.isHidden = true
            }
        }
        if !stamp.isHidden {
            // Just above the rim, kept inside the crop.
            stamp.position = CGPoint(x: clampedLocalX(halfWidth: stamp.size.width * 0.5, f),
                                     y: rimY + 12 + stamp.size.height * 0.5)
        }
    }

    func showStreak(_ n: Int, reduceMotion: Bool, safeX: ClosedRange<CGFloat>) {
        let art = SceneArt.streak(n)
        let node = SKSpriteNode(texture: art.texture, size: art.size)
        node.zPosition = 41
        let stampH = SceneArt.stamp(.perfect).size.height
        let hw = art.size.width * 0.5
        let lo = safeX.lowerBound + hw, hi = safeX.upperBound - hw
        let wx = lo <= hi ? min(max(x, lo), hi) : x
        node.position = CGPoint(x: wx - x, y: rimY + 12 + stampH + art.size.height * 0.35)
        front.addChild(node)
        node.alpha = 0
        if reduceMotion {
            node.run(SKAction.sequence([SKAction.fadeIn(withDuration: 0.12), SKAction.wait(forDuration: 0.9),
                                        SKAction.fadeOut(withDuration: 0.3), SKAction.removeFromParent()]))
        } else {
            node.setScale(0.3)
            let pop = SKAction.scale(to: 1.3, duration: 0.12)
            pop.timingMode = .easeOut
            let settle = SKAction.scale(to: 1, duration: 0.12)
            settle.timingMode = .easeInEaseOut
            let rise = SKAction.moveBy(x: 0, y: 34, duration: 1.1)
            rise.timingMode = .easeOut
            node.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.08),
                SKAction.group([SKAction.fadeIn(withDuration: 0.06), SKAction.sequence([pop, settle]), rise]),
                SKAction.fadeOut(withDuration: 0.28),
                SKAction.removeFromParent(),
            ]))
        }
    }

    // MARK: Static parts (once per glass shape)

    private func rebuild(_ s: GlassShape) {
        shapeID = s.id
        var prof = s.profile
        if prof.count < 2 { prof = [CGPoint(x: 30, y: 0), CGPoint(x: 33, y: 110)] }
        profile = prof
        rimY = prof[prof.count - 1].y
        rimHW = prof[prof.count - 1].x
        wallW = max(2, s.wall)
        base = max(0, s.baseThickness)
        builtLine = -1
        isStemmed = (s.style == .flute || s.style == .sundae || s.style == .bowl) && base >= 20
        let bowlBottom: CGFloat = isStemmed ? min(base, 7) : base
        let f0 = prof[0].x + wallW
        footHW = isStemmed ? max(f0 + 4, rimHW * 0.62) : f0

        // Interior (the far wall of the glass, seen through).
        var inner: [CGPoint] = []
        for p in prof.reversed() { inner.append(CGPoint(x: -p.x, y: p.y)) }
        for p in prof { inner.append(CGPoint(x: p.x, y: p.y)) }
        interior.path = ScenePaths.polygon(inner)

        // Solid glass: a U of walls + base (+ stem and foot).
        var u: [CGPoint] = []
        u.append(CGPoint(x: -f0, y: -bowlBottom))
        for p in prof { u.append(CGPoint(x: -(p.x + wallW), y: p.y)) }
        for p in prof.reversed() { u.append(CGPoint(x: -p.x, y: p.y)) }
        for p in prof { u.append(CGPoint(x: p.x, y: p.y)) }
        for p in prof.reversed() { u.append(CGPoint(x: p.x + wallW, y: p.y)) }
        u.append(CGPoint(x: f0, y: -bowlBottom))
        let wp = ScenePaths.polygon(u)
        // Ink keyline: the outer silhouette only (left wall, base, right wall), like the icon.
        let op = CGMutablePath()
        op.move(to: CGPoint(x: -(prof[prof.count - 1].x + wallW), y: rimY))
        for p in prof.reversed() { op.addLine(to: CGPoint(x: -(p.x + wallW), y: p.y)) }
        op.addLine(to: CGPoint(x: -f0, y: -bowlBottom))
        op.addLine(to: CGPoint(x: f0, y: -bowlBottom))
        for p in prof { op.addLine(to: CGPoint(x: p.x + wallW, y: p.y)) }
        if isStemmed {
            let stemW = max(5, wallW * 2.2)
            let stemH = base - 4 - bowlBottom
            if stemH > 0 {
                wp.addRect(CGRect(x: -stemW / 2, y: -base + 4, width: stemW, height: stemH))
                op.addRect(CGRect(x: -stemW / 2, y: -base + 4, width: stemW, height: stemH))
            }
            let footRect = CGRect(x: -footHW, y: -base, width: footHW * 2, height: 4.5)
            wp.addRoundedRect(in: footRect, cornerWidth: 2, cornerHeight: 2)
            op.addRoundedRect(in: footRect, cornerWidth: 2, cornerHeight: 2)
        }
        walls.path = wp
        outline.path = op

        // Wet film over the glass walls.
        wetSheen.path = wp

        shadow.path = CGPath(ellipseIn: CGRect(x: -(footHW + 12), y: -base - 6, width: (footHW + 12) * 2, height: 12), transform: nil)

        // Rim ellipse: far arc behind the liquid, near arc in front.
        let rx = rimHW + wallW * 0.5
        let ry = min(9, max(3.5, rx * 0.12))
        let rc = CGPoint(x: 0, y: rimY)
        rimBack.path = ScenePaths.polygon(ScenePaths.ellipseArc(center: rc, rx: rx, ry: ry, from: 0, to: .pi, segments: 20), closed: false)
        rimFront.path = ScenePaths.polygon(ScenePaths.ellipseArc(center: rc, rx: rx, ry: ry, from: .pi, to: 2 * .pi, segments: 20), closed: false)

        // Highlights: a long streak down the left inner wall, a short second one, a darker refraction edge right.
        func wallPath(_ from: CGFloat, _ to: CGFloat, _ xAt: (CGFloat) -> CGFloat) -> CGMutablePath {
            var pts: [CGPoint] = []
            for k in 0...6 {
                let y = rimY * (from + (to - from) * CGFloat(k) / 6)
                pts.append(CGPoint(x: xAt(y), y: y))
            }
            let p = CGMutablePath()
            p.move(to: pts[0])
            ScenePaths.addSmoothCurve(p, pts)
            return p
        }
        let pr = prof
        highlight.path = wallPath(0.12, 0.86) { y in -ScenePaths.halfWidth(pr, at: y) + 5 }
        let h2 = wallPath(0.5, 0.74) { y in -ScenePaths.halfWidth(pr, at: y) + 12 }
        if !isStemmed && base >= 6 {
            h2.move(to: CGPoint(x: -prof[0].x + 3, y: -base * 0.5))
            h2.addLine(to: CGPoint(x: prof[0].x - 3, y: -base * 0.5))
        }
        highlight2.path = h2
        let wW = wallW
        shade.path = wallPath(0.04, 0.96) { y in ScenePaths.halfWidth(pr, at: y) + wW - 1.2 }

        // Style extras.
        extra.isHidden = true
        extraOutline.isHidden = true
        switch s.style {
        case .mug:
            let yTop = rimY * 0.8, yBot = rimY * 0.24
            let xTop = ScenePaths.halfWidth(prof, at: yTop) + wallW - 1
            let xBot = ScenePaths.halfWidth(prof, at: yBot) + wallW - 1
            let bulge = 18 + rimHW * 0.3
            let hp = CGMutablePath()
            hp.move(to: CGPoint(x: xTop, y: yTop))
            hp.addCurve(to: CGPoint(x: xBot, y: yBot), control1: CGPoint(x: xTop + bulge, y: yTop + 8),
                        control2: CGPoint(x: xBot + bulge, y: yBot - 8))
            extra.path = hp
            extraOutline.path = hp
            extra.lineWidth = 8
            extra.strokeColor = UIColor(white: 1, alpha: 0.75)
            extra.isHidden = false
            extraOutline.isHidden = false
        case .beaker:
            let tp = CGMutablePath()
            for k in 1...4 {
                let y = rimY * CGFloat(k) / 5
                let hw = ScenePaths.halfWidth(prof, at: y)
                tp.move(to: CGPoint(x: -hw + 2, y: y))
                tp.addLine(to: CGPoint(x: -hw + (k % 2 == 0 ? 14 : 9), y: y))
            }
            extra.path = tp
            extra.lineWidth = 1.6
            extra.strokeColor = darkBackdrop ? UIColor(white: 1, alpha: 0.55) : SceneColor.ink.withAlphaComponent(0.4)
            extra.isHidden = false
        default:
            break
        }
    }
}
