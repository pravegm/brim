import SpriteKit
import UIKit

/// One cosmetic particle (splash droplet, sparkle, confetti). Simulated by the scene, never by Core.
struct SceneParticle {
    var position: CGPoint = .zero
    var velocity: CGVector = CGVector(dx: 0, dy: 0)
    var life: CGFloat = 0
    var maxLife: CGFloat = 1
    var gravity: CGFloat = 0
    var drag: CGFloat = 0
    /// Dies when falling below this world y.
    var floorY: CGFloat = -10_000
    var spin: CGFloat = 0
    var stretch: Bool = false
    var shrink: Bool = true
    var active: Bool = false
}

/// A fixed pool of sprites sharing a couple of textures (so SpriteKit batches them). Nothing is allocated per frame.
@MainActor
final class ParticlePool {
    let root: SKNode
    private var sprites: [SKSpriteNode] = []
    private var parts: [SceneParticle] = []
    private var cursor = 0

    init(capacity: Int, texture: SKTexture) {
        root = SKNode()
        for _ in 0..<capacity {
            let s = SKSpriteNode(texture: texture, size: CGSize(width: 6, height: 6))
            s.colorBlendFactor = 1
            s.isHidden = true
            root.addChild(s)
            sprites.append(s)
            parts.append(SceneParticle())
        }
    }

    func clear() {
        for i in 0..<parts.count {
            parts[i].active = false
            sprites[i].isHidden = true
        }
    }

    func update(_ dt: CGFloat) {
        guard dt > 0 else { return }
        for i in 0..<parts.count where parts[i].active {
            var p = parts[i]
            p.life -= dt
            p.velocity.dy -= p.gravity * dt
            if p.drag > 0 {
                let k = max(0, 1 - p.drag * dt)
                p.velocity.dx *= k
                p.velocity.dy *= k
            }
            p.position.x += p.velocity.dx * dt
            p.position.y += p.velocity.dy * dt
            let s = sprites[i]
            if p.life <= 0 || (p.velocity.dy < 0 && p.position.y < p.floorY) {
                p.active = false
                s.isHidden = true
                parts[i] = p
                continue
            }
            let k = max(0, min(1, p.life / max(p.maxLife, 0.001)))
            s.position = p.position
            s.alpha = min(1, k * 3)
            let scale: CGFloat = p.shrink ? (0.35 + 0.65 * k) : 1
            if p.stretch {
                let speed = hypot(p.velocity.dx, p.velocity.dy)
                s.zRotation = atan2(p.velocity.dy, p.velocity.dx)
                s.xScale = scale * (1 + min(speed / 900, 0.9))
                s.yScale = scale
            } else {
                s.zRotation += p.spin * dt
                s.setScale(scale)
            }
            parts[i] = p
        }
    }

    func spawn(_ p: SceneParticle, size: CGFloat, color: UIColor, texture: SKTexture) {
        let n = parts.count
        guard n > 0 else { return }
        var slot = -1
        for k in 0..<n {
            let idx = (cursor + k) % n
            if !parts[idx].active { slot = idx; break }
        }
        if slot < 0 { slot = cursor }
        cursor = (slot + 1) % n
        var q = p
        q.active = true
        q.maxLife = max(q.life, 0.01)
        parts[slot] = q
        let s = sprites[slot]
        if s.texture !== texture { s.texture = texture }
        s.size = CGSize(width: size, height: size)
        s.color = color
        s.colorBlendFactor = 1
        s.position = q.position
        s.zRotation = 0
        s.setScale(1)
        s.alpha = 1
        s.isHidden = false
    }
}

/// Pooled FX: particles over everything (`root`), particles inside glasses drawn behind their front walls
/// (`innerRoot`, REVIEW-1 P1-4), a few rings and glows, and the puddles.
@MainActor
final class SceneFX {
    let root: SKNode
    let innerRoot: SKNode
    let puddleLayer: SKNode
    var reduceMotion = false

    private let pool: ParticlePool
    private let inner: ParticlePool
    private var rings: [SKShapeNode] = []
    private var ringCursor = 0
    private let glow: SKSpriteNode
    private var puddles: [PuddleView] = []
    private var puddleSignature: Int = -1
    private var rng = SceneRNG(seed: 0xB21_B0B)
    private let dotTexture: SKTexture
    private let sparkleTexture: SKTexture

    init(capacity: Int = 300) {
        root = SKNode()
        innerRoot = SKNode()
        puddleLayer = SKNode()
        dotTexture = SceneArt.dot
        sparkleTexture = SceneArt.sparkle
        pool = ParticlePool(capacity: capacity, texture: dotTexture)
        inner = ParticlePool(capacity: 96, texture: dotTexture)
        root.addChild(pool.root)
        innerRoot.addChild(inner.root)
        glow = SKSpriteNode(texture: SceneArt.glow)
        glow.blendMode = .add
        // The Perfect glow blooms ABOVE the rim, not down into the headspace (REVIEW-3 P2-8).
        glow.anchorPoint = CGPoint(x: 0.5, y: 0.16)
        glow.isHidden = true
        glow.zPosition = -2
        root.addChild(glow)
        for _ in 0..<4 {
            // Drawn at full size (radius 100) and scaled, so the stroke thickens as it grows.
            let r = SKShapeNode(ellipseOf: CGSize(width: 200, height: 58))
            r.fillColor = .clear
            r.lineWidth = 4.5
            r.isHidden = true
            r.zPosition = -1
            root.addChild(r)
            rings.append(r)
        }
    }

    func clear() {
        pool.clear()
        inner.clear()
        for r in rings {
            r.removeAllActions()
            r.isHidden = true
        }
        glow.removeAllActions()
        glow.isHidden = true
        for p in puddles { p.node.removeFromParent() }
        puddles.removeAll()
        puddleSignature = -1
    }

    // MARK: Simulation

    func update(_ dt: CGFloat) {
        pool.update(dt)
        inner.update(dt)
    }

    private func droplet(_ target: ParticlePool, at pos: CGPoint, vel: CGVector, size: CGFloat, color: UIColor,
                         life: CGFloat, gravity: CGFloat = 1500, floorY: CGFloat = -10_000) {
        var p = SceneParticle()
        p.position = pos
        p.velocity = vel
        p.life = life
        p.gravity = gravity
        p.floorY = floorY
        p.stretch = true
        p.shrink = true
        target.spawn(p, size: size, color: color, texture: dotTexture)
    }

    // MARK: Effects

    /// Splash crown where the stream hits a glass's surface: droplets leap up and fall back in, staying inside the
    /// mouth (|x − centre| < half-width − 3) and drawn behind the glass's front wall.
    /// `granular` (sand): no liquid crown — a low puff of fine grains that drops straight back onto the heap.
    func splashCrown(at pos: CGPoint, glassX: CGFloat, mouthHalfWidth: CGFloat, color: UIColor, strength: Double,
                     granular: Bool = false) {
        let s = CGFloat(min(max(strength, 0.1), 1.5))
        if granular {
            let count = reduceMotion ? 2 : 4
            let limit = max(2, mouthHalfWidth - 3)
            let grain = SceneColor.darker(color, 0.12)
            for _ in 0..<count {
                let x0 = min(max(pos.x + rng.range(-5, 5), glassX - limit), glassX + limit)
                let room = max(0, min(glassX + limit - x0, x0 - (glassX - limit)))
                let vx = rng.sign() * min(rng.range(10, 45), max(6, room / 0.25))
                let vy = rng.range(40, 90 + 40 * s)
                droplet(inner, at: CGPoint(x: x0, y: pos.y + 1), vel: CGVector(dx: vx, dy: vy), size: rng.range(1.8, 3),
                        color: grain, life: rng.range(0.18, 0.26), gravity: 1800, floorY: pos.y - 1)
            }
            return
        }
        let count = Int((reduceMotion ? 2 : 4) + s * (reduceMotion ? 2 : 6))
        let limit = max(2, mouthHalfWidth - 3)
        let life: CGFloat = 0.42
        for _ in 0..<count {
            let side = rng.sign()
            let x0 = min(max(pos.x + side * rng.range(1, 6), glassX - limit), glassX + limit)
            // Horizontal speed capped so the drop lands back inside the mouth.
            let room = side > 0 ? (glassX + limit - x0) : (x0 - (glassX - limit))
            let vmax = max(10, room / (life * 0.9))
            let vx = side * min(rng.range(30, 120 + 60 * s), vmax)
            let vy = rng.range(120, 230 + 170 * s)
            droplet(inner, at: CGPoint(x: x0, y: pos.y + 1), vel: CGVector(dx: vx, dy: vy), size: rng.range(3.6, 6.8),
                    color: color, life: rng.range(0.32, life), gravity: 1500, floorY: pos.y - 2)
        }
    }

    /// Spray where stream particles miss the glass and hit the counter.
    func counterSplash(at pos: CGPoint, color: UIColor, strength: Double) {
        let s = CGFloat(min(max(strength, 0.1), 1.5))
        let count = Int((reduceMotion ? 2 : 4) + s * (reduceMotion ? 2 : 6))
        for _ in 0..<count {
            let vx = rng.sign() * rng.range(40, 190)
            let vy = rng.range(90, 220 + 140 * s)
            droplet(pool, at: CGPoint(x: pos.x, y: pos.y + 2), vel: CGVector(dx: vx, dy: vy), size: rng.range(3.2, 6),
                    color: color, life: rng.range(0.3, 0.5), gravity: 1500, floorY: pos.y - 4)
        }
    }

    /// A single drip running off an overflowing / wet glass.
    func drip(at pos: CGPoint, color: UIColor, floorY: CGFloat, big: Bool = false) {
        droplet(pool, at: pos, vel: CGVector(dx: rng.range(-12, 12), dy: rng.range(-50, -10)),
                size: big ? rng.range(5, 7.5) : rng.range(3.8, 5.5), color: color, life: 1.0, gravity: 900, floorY: floorY)
    }

    /// Spill: liquid bursts over the lip and rains onto the counter (P1-2).
    func spillBurst(rim: CGPoint, rimHalfWidth: CGFloat, color: UIColor, floorY: CGFloat) {
        let n = reduceMotion ? 8 : 22
        for i in 0..<n {
            let side: CGFloat = i % 2 == 0 ? -1 : 1
            let x = rim.x + side * rimHalfWidth * rng.range(0.6, 1.05)
            let vx = side * rng.range(40, 160)
            let vy = rng.range(60, 260)
            droplet(pool, at: CGPoint(x: x, y: rim.y + rng.range(0, 6)), vel: CGVector(dx: vx, dy: vy),
                    size: rng.range(4.5, 9), color: color, life: rng.range(0.7, 1.1), gravity: 1300, floorY: floorY)
        }
        counterSplash(at: CGPoint(x: rim.x - rimHalfWidth, y: floorY + 4), color: color, strength: 1.2)
        counterSplash(at: CGPoint(x: rim.x + rimHalfWidth, y: floorY + 4), color: color, strength: 1.2)
    }

    /// Perfect (P0-5): two big rings on the rim plane (≥ 2.5× the rim width), a cyan glow, twinkles and confetti.
    /// Everything is visible from the first frame so a capture 0.15 s after the verdict shows the burst at full tilt.
    func perfectBurst(rim: CGPoint, rimHalfWidth: CGFloat, liquid: UIColor, floorY: CGFloat) {
        let rimW = max(40, rimHalfWidth * 2)
        let specs: [(UIColor, CGFloat, Double)] = [(SceneColor.perfect, 2.7, 0), (UIColor.white, 3.4, 0.06)]
        for (color, mult, delay) in specs {
            let r = rings[ringCursor % rings.count]
            ringCursor += 1
            r.removeAllActions()
            r.strokeColor = color
            r.glowWidth = reduceMotion ? 0 : 2
            r.position = rim
            r.setScale(rimW / 200)
            r.alpha = delay > 0 ? 0 : 1
            r.isHidden = false
            let grow = SKAction.scale(to: rimW * mult / 200, duration: 0.5)
            grow.timingMode = .easeOut
            r.run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.group([SKAction.fadeAlpha(to: 1, duration: 0.03), grow,
                                SKAction.sequence([SKAction.wait(forDuration: 0.24), SKAction.fadeOut(withDuration: 0.3)])]),
                SKAction.hide(),
            ]))
        }
        glow.removeAllActions()
        glow.isHidden = false
        glow.color = SceneColor.perfect
        glow.colorBlendFactor = 0.85
        glow.position = rim
        glow.size = CGSize(width: rimW * 3, height: rimW * 1.3)
        glow.alpha = 0.8
        glow.run(SKAction.sequence([SKAction.wait(forDuration: 0.12), SKAction.fadeOut(withDuration: 0.4), SKAction.hide()]))

        let twinkles = reduceMotion ? 6 : 14
        let colors: [UIColor] = [SceneColor.perfect, .white, SceneColor.gold]
        for i in 0..<twinkles {
            let a = CGFloat(i) / CGFloat(twinkles) * 2 * .pi + rng.range(-0.2, 0.2)
            let speed = rng.range(140, 260)
            var p = SceneParticle()
            p.position = CGPoint(x: rim.x + cos(a) * rimHalfWidth * 0.9, y: rim.y + sin(a) * 8)
            p.velocity = CGVector(dx: cos(a) * speed, dy: sin(a) * speed * 0.5 + 70)
            p.life = rng.range(0.6, 0.9)
            p.drag = 2.6
            p.spin = rng.range(-5, 5)
            p.shrink = true
            pool.spawn(p, size: rng.range(20, 34), color: colors[i % colors.count], texture: sparkleTexture)
        }
        let confetti = reduceMotion ? 8 : 26
        let palette: [UIColor] = [SceneColor.perfect, SceneColor.gold, liquid, .white, SceneColor.hex(0xFF8FB1)]
        for i in 0..<confetti {
            let vx = rng.range(-220, 220)
            let vy = rng.range(300, 600)
            droplet(pool, at: CGPoint(x: rim.x + rng.range(-rimHalfWidth, rimHalfWidth) * 0.6, y: rim.y + 4),
                    vel: CGVector(dx: vx, dy: vy), size: rng.range(6, 11), color: palette[i % palette.count],
                    life: rng.range(0.9, 1.3), gravity: 1100, floorY: floorY)
        }
    }

    /// Small glints at the jug mouth when it is refilled.
    func refillGlints(at pos: CGPoint) {
        let n = reduceMotion ? 3 : 6
        for _ in 0..<n {
            var p = SceneParticle()
            p.position = CGPoint(x: pos.x + rng.range(-30, 30), y: pos.y + rng.range(-6, 10))
            p.velocity = CGVector(dx: rng.range(-20, 20), dy: rng.range(40, 90))
            p.life = rng.range(0.5, 0.8)
            p.drag = 1.5
            p.spin = rng.range(-4, 4)
            pool.spawn(p, size: rng.range(12, 18), color: SceneColor.gold, texture: sparkleTexture)
        }
    }

    // MARK: Puddles (spread 2–3× across the coaster and counter)

    /// Mirrors Core's puddles (decision 4: a puddle belongs to the glass that spilled it). A puddle grows to 2–3× the
    /// coaster over 0.4 s while its glass spills; when its glass leaves it starts to dry (`dryPuddles`); when Core drops
    /// its points it fades away instead of vanishing.
    func syncPuddles(_ pts: [CGPoint], counterY: CGFloat, color: UIColor) {
        // Cheap signature so the decode pass only runs when Core's puddle list changes.
        var sig = pts.count &* 7919
        for q in pts { sig = sig &* 31 &+ Int(q.x.rounded()) }
        if sig == puddleSignature { return }
        puddleSignature = sig
        let runs = ScenePaths.puddleRuns(pts, spacing: CGFloat(CoreTuning.puddlePointSpacing))
        let inset = CGFloat(CoreTuning.puddlePointInset)
        var keep = Array(repeating: false, count: puddles.count)
        for r in runs {
            let radius = r.halfSpan + inset
            var match = -1
            var bestD = CGFloat.greatestFiniteMagnitude
            for (i, pv) in puddles.enumerated() where !keep[i] && !pv.dying {
                let d = abs(pv.x - r.center.x)
                if d < max(40, radius * 0.8) && d < bestD {
                    match = i
                    bestD = d
                }
            }
            if match >= 0 {
                keep[match] = true
                puddles[match].x = r.center.x
                puddles[match].node.position = CGPoint(x: r.center.x, y: counterY + 1)
                puddles[match].setRadius(radius, reduceMotion: reduceMotion)
            } else {
                let pv = PuddleView(color: color, seed: UInt64(truncatingIfNeeded: Int(r.center.x * 13) &+ pts.count))
                pv.x = r.center.x
                pv.node.position = CGPoint(x: r.center.x, y: counterY + 1)
                puddleLayer.addChild(pv.node)
                pv.setRadius(radius, reduceMotion: reduceMotion)
                puddles.append(pv)
                keep.append(true)
            }
        }
        var i = puddles.count - 1
        while i >= 0 {
            if i < keep.count && !keep[i] {
                if puddles[i].dying {
                    // Already fading; drop the bookkeeping once its node is gone.
                    if puddles[i].node.parent == nil { puddles.remove(at: i) }
                } else {
                    puddles[i].fadeAway(reduceMotion: reduceMotion)
                }
            }
            i -= 1
        }
    }

    /// The glass standing over these puddles has left: they start drying (the shine goes, the pool pales).
    func dryPuddles(nearX x: CGFloat, halfWidth: CGFloat) {
        for pv in puddles where !pv.dying && abs(pv.x - x) < halfWidth + 30 {
            pv.startDrying(reduceMotion: reduceMotion)
        }
    }
}

/// One puddle: a glossy pool with a darker rim, a highlight and a few satellite drops; it spreads when it grows.
@MainActor
final class PuddleView {
    let node: SKNode
    var x: CGFloat = 0
    private let pool: SKShapeNode

    static let width: CGFloat = 170
    static let height: CGFloat = 28

    init(color: UIColor, seed: UInt64) {
        node = SKNode()
        var rng = SceneRNG(seed: seed == 0 ? 7 : seed)
        let w = PuddleView.width, h = PuddleView.height
        let c = SceneColor.opaque(color)
        // Irregular blob: an ellipse with wobbly radius.
        let path = CGMutablePath()
        let n = 18
        for i in 0...n {
            let a = CGFloat(i % n) / CGFloat(n) * 2 * .pi
            let k = 1 + 0.08 * sin(a * 3 + rng.range(0, 1)) + rng.range(-0.04, 0.04)
            let p = CGPoint(x: cos(a) * w * 0.5 * k, y: sin(a) * h * 0.5 * k)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        pool = SKShapeNode(path: path)
        pool.fillColor = c.withAlphaComponent(0.86)
        pool.strokeColor = SceneColor.darker(c, 0.3).withAlphaComponent(0.6)
        pool.lineWidth = 2
        node.addChild(pool)
        let shine = SKShapeNode(ellipseOf: CGSize(width: w * 0.36, height: h * 0.24))
        shine.fillColor = UIColor(white: 1, alpha: 0.5)
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -w * 0.14, y: h * 0.14)
        shine.zPosition = 0.1
        node.addChild(shine)
        for _ in 0..<4 {
            let r = rng.range(3, 7)
            let d = SKShapeNode(ellipseOf: CGSize(width: r * 2, height: r * 1.1))
            d.fillColor = c.withAlphaComponent(0.85)
            d.strokeColor = .clear
            d.position = CGPoint(x: rng.sign() * rng.range(w * 0.5 + 6, w * 0.5 + 26), y: rng.range(-h * 0.4, h * 0.3))
            node.addChild(d)
        }
        // Glossy rim: a bright arc along the far edge.
        let rim = CGMutablePath()
        let arc = ScenePaths.ellipseArc(center: .zero, rx: w * 0.47, ry: h * 0.4, from: 0.35, to: CGFloat.pi - 0.5,
                                        segments: 14)
        rim.move(to: arc[0])
        for p in arc.dropFirst() { rim.addLine(to: p) }
        let rimNode = SKShapeNode(path: rim)
        rimNode.strokeColor = UIColor(white: 1, alpha: 0.55)
        rimNode.lineWidth = 2
        rimNode.lineCap = .round
        rimNode.zPosition = 0.12
        node.addChild(rimNode)
        gloss = [shine, rimNode]
        node.setScale(0.15)
    }

    private(set) var dying = false
    private var drying = false
    private var gloss: [SKNode] = []
    private var radius: CGFloat = 0

    /// Display width for Core's puddle radius `r`. The puddle lies under the coaster (~140–200 pt wide), so it starts
    /// at about the coaster's width and spreads past it as the spill grows (REVIEW-3: the grown puddle must read in a
    /// spill frame): r 30 → ~170 pt, r 60 → ~240 pt, r 105 → ~350 pt (≈ 2–2.3× the coaster).
    static func displayWidth(radius r: CGFloat) -> CGFloat {
        return 96 + 2.4 * max(0, r)
    }

    /// Grows to `displayWidth(radius:)` in 0.4 s.
    func setRadius(_ r: CGFloat, reduceMotion: Bool) {
        guard abs(r - radius) > 0.5 else { return }
        if drying && r > radius + 1 {
            // Fed again (a new spill joined it): wet and glossy again.
            drying = false
            node.removeAction(forKey: "dry")
            node.alpha = 1
            for g in gloss {
                g.removeAllActions()
                g.alpha = 1
            }
        }
        radius = r
        let target = min(2.2, max(0.18, PuddleView.displayWidth(radius: r) / PuddleView.width))
        node.removeAction(forKey: "grow")
        if reduceMotion {
            node.setScale(target)
        } else {
            let grow = SKAction.scale(to: target, duration: 0.4)
            grow.timingMode = .easeOut
            node.run(grow, withKey: "grow")
        }
    }

    /// Its glass has left: the gloss goes and the stain pales (Core removes it ~1.5 s later).
    func startDrying(reduceMotion: Bool) {
        guard !drying else { return }
        drying = true
        for g in gloss { g.run(SKAction.fadeOut(withDuration: reduceMotion ? 0.3 : 0.9)) }
        node.run(SKAction.fadeAlpha(to: 0.6, duration: reduceMotion ? 0.3 : 1.2), withKey: "dry")
    }

    /// Core dropped it: fade (and shrink a touch), then leave the tree.
    func fadeAway(reduceMotion: Bool) {
        guard !dying else { return }
        dying = true
        node.removeAllActions()
        let d: Double = reduceMotion ? 0.3 : 0.6
        let fade = SKAction.fadeOut(withDuration: d)
        fade.timingMode = .easeIn
        let shrink = SKAction.scale(by: 0.9, duration: d)
        node.run(SKAction.sequence([SKAction.group([fade, shrink]), SKAction.removeFromParent()]))
    }
}
