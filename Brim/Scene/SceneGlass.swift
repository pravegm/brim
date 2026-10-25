import SpriteKit
import UIKit

/// One glass on the counter. Two roots so the stream can be drawn *between* them:
/// `back` (shadow, interior, liquid, foam, bubbles) sits under the stream, `front` (walls, highlights, rim,
/// fill line, overflow, patience ring, result stamp) sits over it. Both roots share the glass's local frame:
/// origin = centre of the inner floor, y up (the profile's interior coordinates).
@MainActor
final class SceneGlass {
    let id: Int
    let back: SKNode
    let front: SKNode

    // back
    private let shadow: SKShapeNode
    private let interior: SKShapeNode
    private let rimBack: SKShapeNode
    private let band: SKShapeNode
    private let liquid: SKShapeNode
    private let surface: SKShapeNode
    private let foam: SKShapeNode
    private let bubbles: SKShapeNode

    // front
    private let walls: SKShapeNode
    private let highlight: SKShapeNode
    private let highlight2: SKShapeNode
    private let shade: SKShapeNode
    private let rimFront: SKShapeNode
    private let extraOutline: SKShapeNode
    private let extra: SKShapeNode
    private let lineGlow: SKShapeNode
    private let lineInk: SKShapeNode
    private let lineCore: SKShapeNode
    private let tab: SKShapeNode
    private let overflow: SKShapeNode
    private let patienceTrack: SKShapeNode
    private let patienceArc: SKShapeNode
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
    private var liquidID: LiquidID?
    private var wave = SceneWave()
    private var rng: SceneRNG
    private var bubbleX: [CGFloat] = []
    private var bubbleY: [CGFloat] = []
    private var bubbleSpeed: [CGFloat] = []
    private var bubbleR: [CGFloat] = []
    private var bubblePhase: [CGFloat] = []
    private var lastX: CGFloat?
    private var lastVX: CGFloat = 0
    private var velocityValid = false
    private var shownResult: Judgement?
    private var lastPatience: CGFloat = -1
    private var bandState: Int = -1
    private var flash: CGFloat = 0
    private let darkBackdrop: Bool

    private(set) var liquidColor: UIColor = .white
    private(set) var level: CGFloat = 0
    private(set) var x: CGFloat = 0
    private var counterY: CGFloat = 0
    var lastCrownTime: Double = -10
    var lastDripTime: Double = -10

    static let bubbleCount = 12

    init(id: Int, darkBackdrop: Bool) {
        self.id = id
        self.darkBackdrop = darkBackdrop
        rng = SceneRNG(seed: UInt64(truncatingIfNeeded: id &* 7919 &+ 17))
        back = SKNode()
        front = SKNode()
        shadow = SKShapeNode()
        interior = SKShapeNode()
        rimBack = SKShapeNode()
        band = SKShapeNode()
        liquid = SKShapeNode()
        surface = SKShapeNode()
        foam = SKShapeNode()
        bubbles = SKShapeNode()
        walls = SKShapeNode()
        highlight = SKShapeNode()
        highlight2 = SKShapeNode()
        shade = SKShapeNode()
        rimFront = SKShapeNode()
        extraOutline = SKShapeNode()
        extra = SKShapeNode()
        lineGlow = SKShapeNode()
        lineInk = SKShapeNode()
        lineCore = SKShapeNode()
        tab = SKShapeNode()
        overflow = SKShapeNode()
        patienceTrack = SKShapeNode()
        patienceArc = SKShapeNode()
        stamp = SKSpriteNode()

        let ink = SceneColor.ink
        // back
        shadow.fillColor = ink.withAlphaComponent(darkBackdrop ? 0.35 : 0.17)
        shadow.strokeColor = .clear
        shadow.zPosition = 0
        interior.fillColor = UIColor(white: 1, alpha: darkBackdrop ? 0.10 : 0.16)
        interior.strokeColor = .clear
        interior.zPosition = 1
        rimBack.strokeColor = darkBackdrop ? UIColor(white: 1, alpha: 0.25) : ink.withAlphaComponent(0.2)
        rimBack.lineWidth = 1.4
        rimBack.fillColor = .clear
        rimBack.zPosition = 2
        band.fillColor = SceneColor.perfect.withAlphaComponent(0.16)
        band.strokeColor = .clear
        band.zPosition = 3
        liquid.fillColor = .white
        liquid.strokeColor = .clear
        liquid.zPosition = 4
        surface.fillColor = .clear
        surface.lineWidth = 2.2
        surface.lineCap = .round
        surface.zPosition = 4.5
        foam.fillColor = .white
        foam.lineWidth = 1
        foam.zPosition = 5
        bubbles.fillColor = UIColor(white: 1, alpha: 0.35)
        bubbles.strokeColor = UIColor(white: 1, alpha: 0.85)
        bubbles.lineWidth = 0.8
        bubbles.zPosition = 6
        for n in [shadow, interior, rimBack, band, liquid, surface, foam, bubbles] { back.addChild(n) }

        // front
        walls.fillColor = UIColor(white: 1, alpha: darkBackdrop ? 0.22 : 0.32)
        walls.strokeColor = darkBackdrop ? UIColor(white: 1, alpha: 0.5) : ink.withAlphaComponent(0.32)
        walls.lineWidth = 1.4
        walls.lineJoin = .round
        walls.zPosition = 0
        extraOutline.strokeColor = darkBackdrop ? UIColor(white: 1, alpha: 0.45) : ink.withAlphaComponent(0.3)
        extraOutline.fillColor = .clear
        extraOutline.lineWidth = 10.5
        extraOutline.lineCap = .round
        extraOutline.zPosition = 0.1
        extra.strokeColor = UIColor(white: 1, alpha: 0.65)
        extra.fillColor = .clear
        extra.lineWidth = 7.5
        extra.lineCap = .round
        extra.zPosition = 0.2
        highlight.strokeColor = UIColor(white: 1, alpha: 0.62)
        highlight.fillColor = .clear
        highlight.lineWidth = 3
        highlight.lineCap = .round
        highlight.zPosition = 1
        highlight2.strokeColor = UIColor(white: 1, alpha: 0.4)
        highlight2.fillColor = .clear
        highlight2.lineWidth = 2
        highlight2.lineCap = .round
        highlight2.zPosition = 1
        shade.strokeColor = ink.withAlphaComponent(0.10)
        shade.fillColor = .clear
        shade.lineWidth = 3
        shade.lineCap = .round
        shade.zPosition = 1
        rimFront.strokeColor = UIColor(white: 1, alpha: 0.92)
        rimFront.fillColor = .clear
        rimFront.lineWidth = 2
        rimFront.lineCap = .round
        rimFront.zPosition = 2
        lineGlow.fillColor = .clear
        lineGlow.lineCap = .round
        lineGlow.zPosition = 3
        lineInk.strokeColor = ink.withAlphaComponent(0.45)
        lineInk.fillColor = .clear
        lineInk.lineWidth = 4.4
        lineInk.lineCap = .round
        lineInk.zPosition = 3.1
        lineCore.fillColor = .clear
        lineCore.lineWidth = 2.4
        lineCore.lineCap = .round
        lineCore.zPosition = 3.2
        tab.lineWidth = 1
        tab.strokeColor = ink.withAlphaComponent(0.3)
        tab.zPosition = 3.3
        overflow.strokeColor = .clear
        overflow.zPosition = 5
        patienceTrack.strokeColor = darkBackdrop ? UIColor(white: 1, alpha: 0.2) : ink.withAlphaComponent(0.12)
        patienceTrack.fillColor = UIColor(white: 1, alpha: darkBackdrop ? 0.12 : 0.55)
        patienceTrack.lineWidth = 4
        patienceTrack.zPosition = 6
        patienceArc.fillColor = .clear
        patienceArc.lineWidth = 4
        patienceArc.lineCap = .round
        patienceArc.zPosition = 6.1
        stamp.zPosition = 40
        stamp.isHidden = true
        for n in [walls, extraOutline, extra, highlight, highlight2, shade, rimFront, lineGlow, lineInk, lineCore, tab,
                  overflow, patienceTrack, patienceArc] { front.addChild(n) }
        front.addChild(stamp)

        for _ in 0..<SceneGlass.bubbleCount {
            bubbleX.append(rng.range(-0.8, 0.8))
            bubbleY.append(rng.range(0, 1))
            bubbleSpeed.append(rng.range(26, 70))
            bubbleR.append(rng.range(1.1, 2.6))
            bubblePhase.append(rng.range(0, 6.28))
        }
    }

    func remove() {
        back.removeFromParent()
        front.removeFromParent()
    }

    // MARK: World-space helpers for the scene's FX

    var rimWorld: CGPoint { CGPoint(x: x, y: counterY + base + rimY) }
    var surfaceWorldY: CGFloat { counterY + base + level }
    var outerRimHalfWidth: CGFloat { rimHW + wallW }
    /// True once the glass has stopped sliding (used to place the coaster under the pour spot).
    var isStill: Bool { velocityValid && abs(lastVX) < 4 }
    var baseOuterHalfWidth: CGFloat { (profile.first?.x ?? 20) + wallW }

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

    func flashLine() { flash = 1 }

    // MARK: Per frame

    func update(_ g: GlassState, counterY cy: CGFloat, dt: CGFloat, time: Double, pouring: Bool,
                tail: StreamPoint?, advanced: Bool, reduceMotion: Bool) {
        if g.shape.id != shapeID || profile.isEmpty { rebuild(g.shape) }
        if liquidID != g.liquid.id {
            liquidID = g.liquid.id
            liquid.fillTexture = SceneArt.liquidTexture(g.liquid)
            liquid.fillColor = .white
            let top = SceneColor.opaque(g.liquid.top.skColor)
            liquidColor = SceneColor.mix(SceneColor.opaque(g.liquid.bottom.skColor), top, 0.6)
            surface.strokeColor = SceneColor.lighter(top, 0.6)
            foam.fillTexture = SceneArt.foamTexture(g.liquid)
            foam.fillColor = .white
            let foamColor = SceneColor.opaque(g.liquid.foam?.skColor ?? SceneColor.foamDefault)
            foam.strokeColor = SceneColor.darker(foamColor, 0.12).withAlphaComponent(0.55)
            overflow.fillColor = SceneColor.lighter(liquidColor, 0.1).withAlphaComponent(0.88)
        }

        counterY = cy
        x = g.x
        let pos = CGPoint(x: g.x, y: cy + base)
        back.position = pos
        front.position = pos

        let h = min(max(g.liquidHeight, 0), rimY)
        let foamH = max(0, g.foamHeight)
        level = min(h + foamH, rimY + 2)

        // Slosh from the glass's own acceleration (arrive / leave / conveyor), then the stream's impact.
        if advanced && dt > 0.0001 {
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
            if let t = tail, h > 1, abs(t.position.y - surfaceWorldY) < 28, let f = surfaceFraction(worldX: t.position.x) {
                wave.kick(at: f, impulse: -dt * (14 + t.width * 6))
            }
        }
        wave.step(dt)
        if flash > 0 { flash = max(0, flash - dt * 2.2) }

        drawLiquid(h: h, foamH: foamH, g: g, dt: dt, time: time, reduceMotion: reduceMotion)
        drawLine(g, pouring: pouring, time: time)
        drawOverflow(g.overflowing, time: time)
        drawPatience(g)
        drawStamp(g.result, reduceMotion: reduceMotion)
    }

    // MARK: Liquid, foam, bubbles

    private func surfacePoints(height h: CGFloat, widthAt wh: CGFloat, waveScale: CGFloat, cap: CGFloat) -> [CGPoint] {
        let n = SceneWave.count
        let hw = max(0.5, ScenePaths.halfWidth(profile, at: wh) - 0.3)
        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            let f = CGFloat(i) / CGFloat(n - 1)
            let yy = min(max(h + wave.h[i] * waveScale, 0), cap)
            pts.append(CGPoint(x: -hw + 2 * hw * f, y: yy))
        }
        return pts
    }

    private func drawLiquid(h: CGFloat, foamH: CGFloat, g: GlassState, dt: CGFloat, time: Double, reduceMotion: Bool) {
        guard h > 0.4 else {
            liquid.isHidden = true
            surface.isHidden = true
            foam.isHidden = true
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
        liquid.alpha = CGFloat(0.6 + 0.4 * min(max(g.liquid.opacity, 0), 1))

        let sp = CGMutablePath()
        sp.move(to: surf[0])
        ScenePaths.addSmoothCurve(sp, surf)
        surface.path = sp
        surface.isHidden = false

        // Foam head with a bubbly (scalloped) top.
        if foamH > 0.3 {
            let topH = min(h + foamH, rimY + (g.overflowing ? 4 : 1.5))
            let fs = surfacePoints(height: topH, widthAt: min(topH, rimY), waveScale: waveScale * 0.8, cap: rimY + 5)
            let fp = CGMutablePath()
            fp.move(to: surf[0])
            ScenePaths.addSmoothCurve(fp, surf)
            fp.addLine(to: fs[n - 1])
            var i = n - 1
            let t = CGFloat(time)
            while i > 0 {
                let a = fs[i], b = fs[i - 1]
                let bump = 2.2 + 1.2 * sin(t * 2.3 + CGFloat(i) * 1.7)
                fp.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) * 0.5, y: max(a.y, b.y) + min(bump, foamH * 0.6 + 0.8)))
                i -= 1
            }
            fp.closeSubpath()
            foam.path = fp
            foam.isHidden = false
        } else {
            foam.isHidden = true
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

    // MARK: Fill line

    private func buildLine(_ L: CGFloat) {
        builtLine = L
        let hw = ScenePaths.halfWidth(profile, at: L)
        let x0 = -(hw + wallW + 3), x1 = hw + wallW + 3
        let base = CGMutablePath()
        base.move(to: CGPoint(x: x0, y: L))
        base.addLine(to: CGPoint(x: x1, y: L))
        lineGlow.path = base
        let dashed = base.copy(dashingWithPhase: 0, lengths: [9, 6])
        lineInk.path = dashed
        lineCore.path = dashed
        let tp = CGMutablePath()
        let tx = x1 + 2
        tp.move(to: CGPoint(x: tx, y: L))
        tp.addLine(to: CGPoint(x: tx + 7, y: L + 5))
        tp.addLine(to: CGPoint(x: tx + 7, y: L - 5))
        tp.closeSubpath()
        tp.addRoundedRect(in: CGRect(x: tx + 7, y: L - 6.5, width: 15, height: 13), cornerWidth: 4.5, cornerHeight: 4.5)
        tab.path = tp
        let bandH = max(1.5, rimY * 0.025)
        let bhw = max(1, hw - 0.5)
        band.path = CGPath(rect: CGRect(x: -bhw, y: L - bandH, width: bhw * 2, height: bandH * 2), transform: nil)
        bandState = -1
    }

    private func drawLine(_ g: GlassState, pouring: Bool, time: Double) {
        if abs(g.lineHeight - builtLine) > 0.25 { buildLine(g.lineHeight) }
        var a = CGFloat(min(max(g.lineOpacity, 0), 1))
        if g.result == .short {
            a *= 0.55 + 0.45 * CGFloat(0.5 + 0.5 * sin(time * 9))     // the sad pulse
        }
        let hidden = a < 0.01
        for n in [lineGlow, lineInk, lineCore, tab] {
            n.isHidden = hidden
            n.alpha = a
        }
        let inBand = g.inPerfectBand ? 1 : 0
        if inBand != bandState {
            bandState = inBand
            if g.inPerfectBand {
                lineGlow.strokeColor = SceneColor.perfect.withAlphaComponent(0.6)
                lineCore.strokeColor = SceneColor.lighter(SceneColor.perfect, 0.55)
                tab.fillColor = SceneColor.perfect
            } else {
                lineGlow.strokeColor = SceneColor.gold.withAlphaComponent(0.32)
                lineCore.strokeColor = .white
                tab.fillColor = SceneColor.gold
            }
        }
        lineGlow.lineWidth = (g.inPerfectBand ? 12 : 8) + flash * 10
        let showBand = pouring && g.phase == .filling && !hidden && g.result == nil
        band.isHidden = !showBand
        band.alpha = a * (g.inPerfectBand ? 1.6 : 0.8)
    }

    // MARK: Overflow sheet

    private func drawOverflow(_ on: Bool, time: Double) {
        guard on, profile.count >= 2 else {
            overflow.isHidden = true
            return
        }
        let t = CGFloat(time)
        let path = CGMutablePath()
        let bottom: CGFloat = isStemmed ? 0 : -base
        let samples = 10
        for side in [CGFloat(-1), CGFloat(1)] {
            var outer: [CGPoint] = []
            var inner: [CGPoint] = []
            for k in 0...samples {
                let y = rimY - (rimY - bottom) * CGFloat(k) / CGFloat(samples)
                let xw = ScenePaths.halfWidth(profile, at: max(y, 0)) + wallW
                let th = max(1, 2.4 + 1.3 * sin(t * 7 + CGFloat(k) * 0.9 + side))
                outer.append(CGPoint(x: side * (xw + 0.4 + th), y: y))
                inner.append(CGPoint(x: side * (xw - 0.2), y: y))
            }
            path.move(to: CGPoint(x: side * (rimHW - 1), y: rimY + 1.8))
            for p in outer { path.addLine(to: p) }
            let lastX = outer[outer.count - 1].x
            path.addQuadCurve(to: CGPoint(x: side * (abs(lastX) - 6), y: bottom + 0.5),
                              control: CGPoint(x: lastX + side * 7, y: bottom))
            var i = inner.count - 1
            while i >= 0 {
                path.addLine(to: inner[i])
                i -= 1
            }
            path.closeSubpath()
        }
        overflow.path = path
        overflow.isHidden = false
    }

    // MARK: Patience ring

    private func drawPatience(_ g: GlassState) {
        guard let left = g.patienceLeft, let total = g.patienceTotal, total > 0, g.result == nil else {
            patienceTrack.isHidden = true
            patienceArc.isHidden = true
            lastPatience = -1
            return
        }
        let frac = CGFloat(min(max(left / total, 0), 1))
        let c = CGPoint(x: rimHW + wallW + 22, y: rimY + 18)
        if patienceTrack.isHidden || lastPatience < 0 {
            patienceTrack.path = CGPath(ellipseIn: CGRect(x: c.x - 10.5, y: c.y - 10.5, width: 21, height: 21), transform: nil)
        }
        patienceTrack.isHidden = false
        if abs(frac - lastPatience) > 0.004 {
            lastPatience = frac
            let a0 = CGFloat.pi / 2
            let pts = ScenePaths.ellipseArc(center: c, rx: 10.5, ry: 10.5, from: a0, to: a0 - 2 * .pi * max(frac, 0.001),
                                            segments: max(2, Int(36 * frac)))
            patienceArc.path = ScenePaths.polygon(pts, closed: false)
            patienceArc.strokeColor = frac > 0.5 ? SceneColor.leaf : (frac > 0.25 ? SceneColor.gold : SceneColor.coral)
        }
        patienceArc.isHidden = false
    }

    // MARK: Result stamp + streak

    private func drawStamp(_ r: Judgement?, reduceMotion: Bool) {
        if r == shownResult { return }
        shownResult = r
        stamp.removeAllActions()
        guard let j = r else {
            stamp.isHidden = true
            return
        }
        let art = SceneArt.stamp(j)
        stamp.texture = art.texture
        stamp.size = art.size
        stamp.position = CGPoint(x: 0, y: rimY + 30 + art.size.height * 0.5)
        stamp.zRotation = j == .perfect ? -0.06 : 0.05
        stamp.isHidden = false
        if reduceMotion {
            stamp.setScale(1)
            stamp.alpha = 0
            stamp.run(SKAction.fadeIn(withDuration: 0.15))
        } else {
            stamp.setScale(0.25)
            stamp.alpha = 0
            let up = SKAction.scale(to: 1.18, duration: 0.13)
            up.timingMode = .easeOut
            let down = SKAction.scale(to: 0.95, duration: 0.08)
            down.timingMode = .easeInEaseOut
            let settle = SKAction.scale(to: 1.0, duration: 0.08)
            settle.timingMode = .easeOut
            stamp.run(SKAction.group([SKAction.fadeIn(withDuration: 0.08), SKAction.sequence([up, down, settle])]))
        }
    }

    func showStreak(_ n: Int, reduceMotion: Bool) {
        let art = SceneArt.streak(n)
        let node = SKSpriteNode(texture: art.texture, size: art.size)
        node.zPosition = 41
        let stampTop = rimY + 30 + SceneArt.stamp(.perfect).size.height
        node.position = CGPoint(x: 0, y: stampTop + art.size.height * 0.3)
        front.addChild(node)
        node.alpha = 0
        if reduceMotion {
            node.run(SKAction.sequence([SKAction.fadeIn(withDuration: 0.15), SKAction.wait(forDuration: 0.9),
                                        SKAction.fadeOut(withDuration: 0.3), SKAction.removeFromParent()]))
        } else {
            node.setScale(0.4)
            let pop = SKAction.scale(to: 1.12, duration: 0.14)
            pop.timingMode = .easeOut
            let settle = SKAction.scale(to: 1, duration: 0.1)
            let rise = SKAction.moveBy(x: 0, y: 26, duration: 1.2)
            rise.timingMode = .easeOut
            node.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.12),
                SKAction.group([SKAction.fadeIn(withDuration: 0.08), SKAction.sequence([pop, settle]), rise]),
                SKAction.fadeOut(withDuration: 0.3),
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
        wallW = max(1.5, s.wall)
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
        if isStemmed {
            let stemW = max(5, wallW * 2.2)
            let stemH = base - 4 - bowlBottom
            if stemH > 0 {
                wp.addRect(CGRect(x: -stemW / 2, y: -base + 4, width: stemW, height: stemH))
            }
            wp.addRoundedRect(in: CGRect(x: -footHW, y: -base, width: footHW * 2, height: 4), cornerWidth: 2, cornerHeight: 2)
        }
        walls.path = wp

        shadow.path = CGPath(ellipseIn: CGRect(x: -(footHW + 9), y: -base - 5, width: (footHW + 9) * 2, height: 10), transform: nil)

        // Rim ellipse: far arc behind the liquid, near arc in front.
        let rx = rimHW + wallW * 0.5
        let ry = min(8, max(3, rx * 0.11))
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
        highlight.path = wallPath(0.14, 0.84) { y in -ScenePaths.halfWidth(pr, at: y) + 4 }
        let h2 = wallPath(0.52, 0.72) { y in -ScenePaths.halfWidth(pr, at: y) + 9.5 }
        if !isStemmed && base >= 6 {
            h2.move(to: CGPoint(x: -prof[0].x + 3, y: -base * 0.5))
            h2.addLine(to: CGPoint(x: prof[0].x - 3, y: -base * 0.5))
        }
        highlight2.path = h2
        let wW = wallW
        shade.path = wallPath(0.04, 0.96) { y in ScenePaths.halfWidth(pr, at: y) + wW - 1 }

        // Style extras.
        extra.isHidden = true
        extraOutline.isHidden = true
        switch s.style {
        case .mug:
            let yTop = rimY * 0.8, yBot = rimY * 0.24
            let xTop = ScenePaths.halfWidth(prof, at: yTop) + wallW - 1
            let xBot = ScenePaths.halfWidth(prof, at: yBot) + wallW - 1
            let bulge = 16 + rimHW * 0.28
            let hp = CGMutablePath()
            hp.move(to: CGPoint(x: xTop, y: yTop))
            hp.addCurve(to: CGPoint(x: xBot, y: yBot), control1: CGPoint(x: xTop + bulge, y: yTop + 8),
                        control2: CGPoint(x: xBot + bulge, y: yBot - 8))
            extra.path = hp
            extraOutline.path = hp
            extra.lineWidth = 7.5
            extra.strokeColor = UIColor(white: 1, alpha: 0.65)
            extra.isHidden = false
            extraOutline.isHidden = false
        case .beaker:
            let tp = CGMutablePath()
            for k in 1...4 {
                let y = rimY * CGFloat(k) / 5
                let hw = ScenePaths.halfWidth(prof, at: y)
                tp.move(to: CGPoint(x: -hw + 2, y: y))
                tp.addLine(to: CGPoint(x: -hw + (k % 2 == 0 ? 12 : 8), y: y))
            }
            extra.path = tp
            extra.lineWidth = 1.5
            extra.strokeColor = darkBackdrop ? UIColor(white: 1, alpha: 0.5) : SceneColor.ink.withAlphaComponent(0.35)
            extra.isHidden = false
        default:
            break
        }
    }
}
