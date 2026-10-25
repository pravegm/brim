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
    /// ROUND-3 decision 3: no text may reach above this world y (the crease band minus 8 pt).
    var keepOutTop: CGFloat
    /// REVIEW-3 P1-1: a glass waiting in the next-glass slot is drawn as *waiting* — this scale (0.82 on the Duo,
    /// 0.75 on phones), this many pt lower on the counter and this opaque. It grows and brightens as it slides to the stop.
    var waitingScale: CGFloat = 0.82
    var waitingDrop: CGFloat = 10
    var waitingAlpha: CGFloat = 0.6
    /// Fade the glass out (a waiting glass that would not fit inside the crop with a clear margin).
    var suppressed: Bool = false
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
    private let plume: SKShapeNode
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
    private var maxHW: CGFloat = 30
    private var hasHandle = false
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
    /// Seconds the glass has been standing still (a glass waiting in the next-glass slot has been still a while).
    private(set) var stillFor: Double = 0
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
    /// 0 = a glass to pour into, 1 = waiting in the slot (linear; eased when drawn). See `GlassFrame.waitingScale`.
    private var waitAmount: CGFloat = 0
    private var waitKnown = false
    /// 1 = shown, 0 = suppressed (eased).
    private var shown: CGFloat = 1
    /// Current drawn scale (about the base) and how far below the counter line the base sits (waiting look).
    private(set) var displayScale: CGFloat = 1
    private(set) var dropY: CGFloat = 0
    /// Seconds a glass takes to go from the waiting look to full size (its slide to the stop is 0.45 s).
    static let waitBlendTime: CGFloat = 0.4

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
        plume = SKShapeNode()
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
        plume.fillColor = UIColor(white: 1, alpha: 0.45)
        plume.strokeColor = UIColor(white: 1, alpha: 0.85)
        plume.lineWidth = 1
        plume.zPosition = 6.2
        plume.isHidden = true
        surfaceFlash.zPosition = 6.5
        surfaceFlash.alpha = 0
        surfaceFlash.isHidden = true
        surfaceFlash.blendMode = .add
        for n in [patienceTrack, patienceArc, shadow, interior, rimBack, liquid, surface, foam, foamBubbles, bubbles, plume] {
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
        // Above the spill sheets (z 5…5.1) so a spill never hides the fill tab (REVIEW-3 P2-10).
        tab.zPosition = 5.3
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

    var rimWorld: CGPoint { CGPoint(x: x, y: counterY - dropY + (base + rimY) * displayScale) }
    var surfaceWorldY: CGFloat { counterY - dropY + (base + level) * displayScale }
    var outerRimHalfWidth: CGFloat { (rimHW + wallW) * displayScale }
    var innerRimHalfWidth: CGFloat { rimHW * displayScale }
    /// 0…1, how much of the waiting look the glass shows (eased).
    var waitingLook: CGFloat {
        let u = min(max(waitAmount, 0), 1)
        return u * u * (3 - 2 * u)
    }
    /// Current drawn opacity of the whole glass (waiting look × suppression).
    var drawnAlpha: CGFloat { back.alpha }
    /// Liquid half-width at the current level (for splashes that must stay inside the mouth).
    var surfaceHalfWidth: CGFloat { ScenePaths.halfWidth(profile, at: level) }
    /// True once the glass has stopped sliding (used to place the coaster under the pour spot).
    var isStill: Bool { velocityValid && abs(lastVX) < 4 }
    /// Half-width of the base in the glass's LOCAL units (multiply by `displayScale` for world).
    var baseOuterHalfWidth: CGFloat { (isStemmed ? footHW : (profile.first?.x ?? 20) + wallW) }
    var velocityX: CGFloat { velocityValid ? lastVX : 0 }
    /// Spilled and still dripping (the wet glass leaving).
    var isWet: Bool { simTime < wetUntil }
    /// World rect of the glass at rest as drawn (walls, foot, mug handle, rim; the waiting glass's smaller size and
    /// lower spot included), for UI keep-outs.
    var worldFrame: CGRect {
        let k = displayScale
        let left = max(maxHW + (hasHandle ? 30 : 0), footHW) * k
        let right = max(maxHW, footHW) * k
        return CGRect(x: x - left, y: counterY - dropY - 6, width: left + right,
                      height: (base + rimY) * k + 12)
    }

    /// How far the glass reaches left of its centre line in LOCAL units (walls, foot, mug handle).
    var localLeftHalfWidth: CGFloat { max(maxHW + (hasHandle ? 30 : 0), footHW) }

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
            liquidColor = SceneLiquidLook.stream(g.liquid).body
            surface.strokeColor = SceneColor.lighter(top, 0.65)
            foam.fillTexture = SceneArt.foamTexture(g.liquid)
            foam.fillColor = .white
            let foamColor = SceneColor.opaque(g.liquid.foam?.skColor ?? SceneColor.foamDefault)
            foam.strokeColor = SceneColor.lighter(foamColor, 0.75)
            foamBubbles.strokeColor = SceneColor.darker(foamColor, 0.18).withAlphaComponent(0.5)
            overflow.fillColor = SceneColor.lighter(liquidColor, 0.08).withAlphaComponent(0.94)
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
                if abs(vx) < 4 { stillFor += Double(dt) } else { stillFor = 0 }
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

        // Waiting look (REVIEW-3 P1-1): a glass born in the slot starts small and dim; it grows and brightens over
        // `waitBlendTime` as it slides to the stop.
        let waitTarget: CGFloat = g.isWaitingInSlot ? 1 : 0
        let showTarget: CGFloat = f.suppressed ? 0 : 1
        if !waitKnown {
            waitKnown = true
            waitAmount = waitTarget
            shown = showTarget
        } else if dt > 0 {
            let step = dt / SceneGlass.waitBlendTime
            waitAmount = waitTarget > waitAmount ? min(waitTarget, waitAmount + step) : max(waitTarget, waitAmount - step)
        }
        if dt > 0 {
            let step = dt * 5
            shown = showTarget > shown ? min(showTarget, shown + step) : max(showTarget, shown - step)
        } else if !f.advanced {
            // First draw / a reset frame: no fade in or out.
            shown = showTarget
        }
        let e = waitingLook
        displayScale = 1 - e * (1 - min(max(f.waitingScale, 0.3), 1))
        dropY = e * f.waitingDrop
        let alpha = (1 - e * (1 - min(max(f.waitingAlpha, 0), 1))) * shown
        back.alpha = alpha
        front.alpha = alpha
        let hide = alpha < 0.005
        back.isHidden = hide
        front.isHidden = hide

        placeRoots(g, f)
        drawLiquid(h: h, foamH: foamH, g: g, dt: dt, time: f.time, reduceMotion: f.reduceMotion)
        drawPlume(h: h, f, thick: SceneStream.isThick(g.liquid.id) || g.liquid.id == .sand)
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
        // The waiting look scales the glass about its base and sets it a little lower (nearer the player).
        let ks = displayScale
        let pos = CGPoint(x: g.x, y: f.counterY - dropY + base * sy * ks + dy)
        back.position = pos
        front.position = pos
        back.xScale = sx * ks
        back.yScale = sy * ks
        front.xScale = sx * ks
        front.yScale = sy * ks
        // The ring/shadow stay on the counter while the glass is in the air.
        shadow.position = CGPoint(x: 0, y: -dy / max(sy * ks, 0.01))
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
        liquid.alpha = SceneLiquidLook.glassAlpha(g.liquid)

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

    /// Where the stream plunges in: a short plume of bubbles under the surface (replaces the ghost "tongue",
    /// REVIEW-2 P1-6). Thick drinks coil on top instead (SceneStream).
    private func drawPlume(h: CGFloat, _ f: GlassFrame, thick: Bool) {
        guard !thick, f.pouring, h > 12, let t = f.tail, abs(t.position.y - surfaceWorldY) < 30,
              let fr = surfaceFraction(worldX: t.position.x) else {
            plume.isHidden = true
            return
        }
        let hwTop = ScenePaths.halfWidth(profile, at: h)
        let cx = -hwTop + 2 * hwTop * fr
        let depth = min(36, h - 8)
        let spread = max(5, min(t.width + 6, hwTop * 0.7))
        let time = CGFloat(f.time)
        let p = CGMutablePath()
        let count = f.reduceMotion ? 4 : 7
        for k in 0..<count {
            let u = (time * 1.7 + CGFloat(k) / CGFloat(count)).truncatingRemainder(dividingBy: 1)
            let y = h - 3 - u * depth
            let r = 1.3 + 1.9 * (1 - u)
            let lim = max(0, ScenePaths.halfWidth(profile, at: y) - r - 2)
            let x = min(max(cx + sin(CGFloat(k) * 2.4 + time * 3) * spread * 0.4 * (0.4 + u), -lim), lim)
            p.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        plume.path = p
        plume.isHidden = false
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
        // REVIEW-3 P2-8: inside the glass the bloom stays ≤ 25 % and hugs the surface (it used to fill the headspace
        // with white, "a glass of milk"); the big glow lives outside, above the rim (SceneFX.perfectBurst).
        let hw = ScenePaths.halfWidth(profile, at: level)
        surfaceFlash.isHidden = false
        surfaceFlash.alpha = a * 0.25
        surfaceFlash.size = CGSize(width: hw * 1.9, height: 14 + 8 * a)
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
            // P2-9: a real 22–26 % strip before and during the pour ("aim here"), brighter once the projection is in.
            band.alpha = a * ((projectedIn ? 0.42 : (f.pouring ? 0.26 : 0.22)) + pulse + lock * 0.3)
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

        // 2. Side sheets running down both walls: thick (≥ 12 pt), opaque, wobbling, with a drip bead at the foot.
        //    (No front curtain: drawn over a full glass it read as a ghost "tongue" inside the drink, REVIEW-2 P1-6.)
        let grow = min(1, max(0, (since - 0.08) / 0.3))
        let len = fullDrop * (g.overflowing ? grow : 1)
        if len > 2 {
            let samples = 10
            for side in [CGFloat(-1), CGFloat(1)] {
                var outer: [CGPoint] = []
                var inner: [CGPoint] = []
                for k in 0...samples {
                    let y = rimY - len * CGFloat(k) / CGFloat(samples)
                    let xw = ScenePaths.halfWidth(profile, at: max(y, 0)) + wallW
                    let taper = 1 - 0.25 * CGFloat(k) / CGFloat(samples)
                    let th = max(2, (13 + 2.5 * sin(t * 7 + CGFloat(k) * 0.9 + side)) * taper * max(strength, 0.35))
                    outer.append(CGPoint(x: side * (xw + 0.4 + th), y: y))
                    inner.append(CGPoint(x: side * (xw - 2), y: y))
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
                // A fat bead gathering at the foot of the sheet.
                if let foot = outer.last {
                    let br = 5.5 * max(strength, 0.4)
                    path.addEllipse(in: CGRect(x: foot.x - side * br * 1.2 - br, y: foot.y - br * 1.6,
                                               width: br * 2, height: br * 2.2))
                }
                // Glint down the sheet.
                let s0 = outer[1], s1 = outer[samples / 2]
                shinePath.move(to: CGPoint(x: s0.x - side * 4, y: s0.y))
                shinePath.addLine(to: CGPoint(x: s1.x - side * 4, y: s1.y))
            }
        }
        overflow.path = path
        overflow.isHidden = false
        overflow.alpha = g.overflowing ? 1 : max(0, min(1, strength * 1.5))
        overflowShine.path = shinePath
        overflowShine.isHidden = shinePath.isEmpty
        overflowShine.alpha = strength

        // Wet walls: a translucent film over the whole outside.
        wetSheen.isHidden = false
        wetSheen.alpha = min(1, strength + 0.4)
    }

    // MARK: Patience ring (attached to the glass: drains around the coaster, P2-2)

    private func drawPatience(_ g: GlassState, time: Double) {
        guard let left = g.patienceLeft, let total = g.patienceTotal, total > 0, g.result == nil,
              !g.isWaitingInSlot else {
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
                stampFullSize = art.size
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
            // Just above the rim, kept inside the crop and BELOW the crease keep-out (ROUND-3 decision 3): tall glasses
            // get the stamp over their upper body instead of on the fold. Computed from the live root (Perfect hop).
            let sy = max(front.yScale, 0.01)
            let limit = (f.keepOutTop - front.position.y) / sy
            let full = stampFullSize == .zero ? stamp.size : stampFullSize       // settled size, not the pop-in scale
            let top = full.height * SceneGlass.labelTopFrac * 1.2                // 1.2: the pop overshoot
            let desired = rimY + 12 + full.height * 0.5
            stamp.position = CGPoint(x: clampedLocalX(halfWidth: full.width * 0.5, f),
                                     y: min(desired, limit - top))
            // The `.streak` event arrives in the same step as `.served`, before the snapshot carrying the result is
            // drawn, so a pop placed then didn't know where the stamp would go and landed on it (round-3 Duo frame
            // store-s2). It waits here until the stamp is in place.
            if let p = pendingStreak {
                pendingStreak = nil
                showStreak(p.n, reduceMotion: p.reduceMotion, safeX: p.safeX, keepOutTop: p.keepOutTop)
            }
        }
    }

    private var pendingStreak: (n: Int, reduceMotion: Bool, safeX: ClosedRange<CGFloat>, keepOutTop: CGFloat)?
    /// The stamp's settled size. `SKSpriteNode.size` includes the node's scale, and the streak is placed while the
    /// stamp is still popping in at 0.3×: measured that way it looked tiny and the pop landed where the full stamp
    /// later covered it (final Duo frame D2).
    private var stampFullSize: CGSize = .zero

    /// Highest world y the stamp's ink reaches (with its pop overshoot); nil when no stamp shows. For tests and UI.
    var stampReachWorld: CGFloat? {
        if stamp.isHidden { return nil }
        let top = stamp.position.y + (stampFullSize == .zero ? stamp.size : stampFullSize).height * SceneGlass.labelTopFrac * 1.2
        return front.position.y + front.yScale * top
    }

    /// Highest world y (glass at rest) the last streak pop reaches, rise and pop overshoot included.
    private(set) var lastStreakReachWorld: CGFloat?

    /// The visible ink of a `SceneArt.label` sprite reaches this fraction of its height above (and below) its centre,
    /// and this fraction of its width either side (the sprite carries padding for the outline and shadow).
    static let labelTopFrac: CGFloat = 0.3
    static let labelSideFrac: CGFloat = 0.46

    /// Where the streak pop goes (glass-local) and how far it may rise: above the stamp if it fits under the crease
    /// keep-out (rising less if it must), else beside the stamp on the flat half, else just under it.
    private func streakPlacement(size: CGSize, safeX: ClosedRange<CGFloat>, keepOutTop: CGFloat)
        -> (position: CGPoint, rise: CGFloat)? {
        // Local limit at rest; allow for the Perfect hop (≤ 13 pt) and its ~2 % stretch while it is running.
        let hop: CGFloat = celebrateAt != nil ? 22 : 2
        let limit = keepOutTop - (counterY + base) - hop
        let popTop = size.height * SceneGlass.labelTopFrac * 1.3
        let halfW = size.width * SceneGlass.labelSideFrac
        let hasStamp = !stamp.isHidden
        let sc = hasStamp ? stamp.position : CGPoint(x: 0, y: rimY + 4)
        // 1.2: the stamp's pop overshoot.
        let sTop = hasStamp ? stampFullSize.height * SceneGlass.labelTopFrac * 1.2 : 0
        let sHalfW = hasStamp ? stampFullSize.width * SceneGlass.labelSideFrac * 1.2 : 0
        func clampX(_ lx: CGFloat) -> CGFloat {
            let lo = safeX.lowerBound + halfW - x, hi = safeX.upperBound - halfW - x
            return lo <= hi ? min(max(lx, lo), hi) : lx
        }
        // A. Above the stamp.
        let aboveY = sc.y + sTop + 4 + size.height * SceneGlass.labelTopFrac
        if aboveY + popTop <= limit {
            return (CGPoint(x: clampX(sc.x), y: aboveY), min(34, max(0, limit - popTop - aboveY)))
        }
        // B. Beside the stamp on the flat half (right first: the next glass waits on the left).
        let sideY = min(sc.y, limit - popTop)
        let wx = x + sc.x
        let rightCentre = wx + sHalfW + 10 + halfW
        if rightCentre + halfW <= safeX.upperBound {
            return (CGPoint(x: rightCentre - x, y: sideY), min(12, max(0, limit - popTop - sideY)))
        }
        let leftCentre = wx - sHalfW - 10 - halfW
        if leftCentre - halfW >= safeX.lowerBound {
            return (CGPoint(x: leftCentre - x, y: sideY), min(12, max(0, limit - popTop - sideY)))
        }
        // C. No clean spot: with a stamp showing, skip the pop. Under the stamp it overprinted PERFECT (final Duo store
        // frame D2); the HUD's streak pill and the climbing ting already carry the streak.
        if hasStamp { return nil }
        let belowY = sc.y - 4 - size.height * SceneGlass.labelTopFrac
        return (CGPoint(x: clampX(sc.x), y: min(belowY, limit - popTop)), 0)
    }

    /// The streak pop — never on the crease band (ROUND-3 decision 3; see `streakPlacement`).
    func showStreak(_ n: Int, reduceMotion: Bool, safeX: ClosedRange<CGFloat>, keepOutTop: CGFloat) {
        if stamp.isHidden {
            pendingStreak = (n: n, reduceMotion: reduceMotion, safeX: safeX, keepOutTop: keepOutTop)
            return
        }
        let art = SceneArt.streak(n)
        guard let place = streakPlacement(size: art.size, safeX: safeX, keepOutTop: keepOutTop) else {
            lastStreakReachWorld = nil
            return
        }
        let node = SKSpriteNode(texture: art.texture, size: art.size)
        node.zPosition = 41
        node.position = place.position
        lastStreakReachWorld = counterY + base + place.position.y + place.rise
            + art.size.height * SceneGlass.labelTopFrac * 1.3
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
            let rise = SKAction.moveBy(x: 0, y: place.rise, duration: 1.1)
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
        var widest: CGFloat = 0
        for p in prof { widest = max(widest, p.x) }
        maxHW = widest + wallW
        hasHandle = s.style == .mug

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
            // Handle on the LEFT, so the fill-line tab on the right never sits on it (REVIEW-2 P2-5).
            let yTop = rimY * 0.8, yBot = rimY * 0.24
            let xTop = -(ScenePaths.halfWidth(prof, at: yTop) + wallW - 1)
            let xBot = -(ScenePaths.halfWidth(prof, at: yBot) + wallW - 1)
            let bulge = -(18 + rimHW * 0.3)
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
