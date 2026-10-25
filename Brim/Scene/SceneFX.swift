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

/// Pooled FX: a fixed set of sprites sharing two textures (so SpriteKit batches them), a few rings, and puddles.
/// Nothing is allocated per frame.
@MainActor
final class SceneFX {
    let root: SKNode
    let puddleLayer: SKNode
    var reduceMotion = false

    private var sprites: [SKSpriteNode] = []
    private var parts: [SceneParticle] = []
    private var cursor = 0
    private var rings: [SKShapeNode] = []
    private var ringCursor = 0
    private var puddles: [SKShapeNode] = []
    private var rng = SceneRNG(seed: 0xB21_B0B)
    private let dotTexture: SKTexture
    private let sparkleTexture: SKTexture

    init(capacity: Int = 260) {
        root = SKNode()
        puddleLayer = SKNode()
        dotTexture = SceneArt.dot
        sparkleTexture = SceneArt.sparkle
        for _ in 0..<capacity {
            let s = SKSpriteNode(texture: dotTexture, size: CGSize(width: 6, height: 6))
            s.colorBlendFactor = 1
            s.isHidden = true
            root.addChild(s)
            sprites.append(s)
            parts.append(SceneParticle())
        }
        for _ in 0..<4 {
            // Drawn at full size (radius 100) and scaled down, so the stroke thickens as it grows instead of
            // turning into a fat band.
            let r = SKShapeNode(ellipseOf: CGSize(width: 200, height: 64))
            r.fillColor = .clear
            r.lineWidth = 3.5
            r.isHidden = true
            r.zPosition = -1
            root.addChild(r)
            rings.append(r)
        }
    }

    func clear() {
        for i in 0..<parts.count {
            parts[i].active = false
            sprites[i].isHidden = true
        }
        for r in rings {
            r.removeAllActions()
            r.isHidden = true
        }
        for p in puddles { p.removeFromParent() }
        puddles.removeAll()
    }

    // MARK: Simulation

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

    private func spawn(_ p: SceneParticle, size: CGFloat, color: UIColor, texture: SKTexture) {
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

    private func droplet(at pos: CGPoint, vel: CGVector, size: CGFloat, color: UIColor, life: CGFloat,
                         gravity: CGFloat = 1500, floorY: CGFloat = -10_000) {
        var p = SceneParticle()
        p.position = pos
        p.velocity = vel
        p.life = life
        p.gravity = gravity
        p.floorY = floorY
        p.stretch = true
        p.shrink = true
        spawn(p, size: size, color: color, texture: dotTexture)
    }

    // MARK: Effects

    /// Splash crown where the stream hits a glass's surface: droplets leap up and fall back in.
    func splashCrown(at pos: CGPoint, color: UIColor, strength: Double, mouthHalfWidth: CGFloat) {
        let s = CGFloat(min(max(strength, 0.1), 1.5))
        let count = Int((reduceMotion ? 2 : 4) + s * (reduceMotion ? 2 : 5))
        for _ in 0..<count {
            let side = rng.sign()
            let vx = side * rng.range(30, 110 + 60 * s)
            let vy = rng.range(110, 220 + 160 * s)
            let x = pos.x + side * rng.range(1, 5)
            droplet(at: CGPoint(x: x, y: pos.y + 1), vel: CGVector(dx: vx, dy: vy), size: rng.range(3.2, 5.8),
                    color: color, life: rng.range(0.32, 0.55), gravity: 1500, floorY: pos.y - 2)
        }
        _ = mouthHalfWidth
    }

    /// Spray where stream particles miss the glass and hit the counter.
    func counterSplash(at pos: CGPoint, color: UIColor, strength: Double) {
        let s = CGFloat(min(max(strength, 0.1), 1.5))
        let count = Int((reduceMotion ? 2 : 3) + s * (reduceMotion ? 2 : 5))
        for _ in 0..<count {
            let vx = rng.sign() * rng.range(40, 170)
            let vy = rng.range(80, 200 + 120 * s)
            droplet(at: CGPoint(x: pos.x, y: pos.y + 2), vel: CGVector(dx: vx, dy: vy), size: rng.range(2.8, 5),
                    color: color, life: rng.range(0.3, 0.5), gravity: 1500, floorY: pos.y - 3)
        }
    }

    /// A single drip running off an overflowing glass.
    func drip(at pos: CGPoint, color: UIColor, floorY: CGFloat) {
        droplet(at: pos, vel: CGVector(dx: rng.range(-10, 10), dy: rng.range(-40, -10)), size: rng.range(3.5, 5),
                color: color, life: 0.9, gravity: 900, floorY: floorY)
    }

    /// Perfect: a cyan sparkle ring on the rim plane, twinkles and a confetti of droplets.
    func perfectBurst(rim: CGPoint, rimHalfWidth: CGFloat, liquid: UIColor, floorY: CGFloat) {
        // Rings.
        for (k, color) in [SceneColor.perfect, UIColor.white].enumerated() {
            let r = rings[ringCursor % rings.count]
            ringCursor += 1
            r.removeAllActions()
            r.strokeColor = color
            r.position = rim
            r.setScale(max(0.12, rimHalfWidth / 100))
            r.alpha = 0
            r.isHidden = false
            let target = max(0.5, (rimHalfWidth + 75) / 100)
            let grow = SKAction.scale(to: target, duration: 0.55)
            grow.timingMode = .easeOut
            r.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.07 * Double(k)),
                SKAction.group([SKAction.fadeAlpha(to: 1, duration: 0.05), grow,
                                SKAction.sequence([SKAction.wait(forDuration: 0.2), SKAction.fadeOut(withDuration: 0.35)])]),
                SKAction.hide(),
            ]))
        }
        // Twinkles around the rim.
        let twinkles = reduceMotion ? 5 : 11
        let colors: [UIColor] = [SceneColor.perfect, .white, SceneColor.gold]
        for i in 0..<twinkles {
            let a = CGFloat(i) / CGFloat(twinkles) * 2 * .pi + rng.range(-0.2, 0.2)
            let speed = rng.range(90, 170)
            var p = SceneParticle()
            p.position = CGPoint(x: rim.x + cos(a) * rimHalfWidth * 0.9, y: rim.y + sin(a) * 6)
            p.velocity = CGVector(dx: cos(a) * speed, dy: sin(a) * speed * 0.45 + 50)
            p.life = rng.range(0.55, 0.8)
            p.drag = 2.4
            p.spin = rng.range(-5, 5)
            p.shrink = true
            spawn(p, size: rng.range(16, 26), color: colors[i % colors.count], texture: sparkleTexture)
        }
        // Droplet confetti.
        let confetti = reduceMotion ? 6 : 18
        let palette: [UIColor] = [SceneColor.perfect, SceneColor.gold, liquid, .white, SceneColor.hex(0xFF8FB1)]
        for i in 0..<confetti {
            let vx = rng.range(-180, 180)
            let vy = rng.range(260, 520)
            droplet(at: CGPoint(x: rim.x + rng.range(-rimHalfWidth, rimHalfWidth) * 0.6, y: rim.y + 4),
                    vel: CGVector(dx: vx, dy: vy), size: rng.range(5, 9), color: palette[i % palette.count],
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
            spawn(p, size: rng.range(12, 18), color: SceneColor.gold, texture: sparkleTexture)
        }
    }

    // MARK: Puddles

    func syncPuddles(_ pts: [CGPoint], counterY: CGFloat, color: UIColor) {
        while puddles.count > pts.count {
            puddles.removeLast().removeFromParent()
        }
        while puddles.count < pts.count {
            let w = rng.range(58, 86), h = rng.range(10, 13)
            let p = SKShapeNode(ellipseOf: CGSize(width: w, height: h))
            p.fillColor = SceneColor.opaque(color).withAlphaComponent(0.78)
            p.strokeColor = SceneColor.darker(SceneColor.opaque(color), 0.25).withAlphaComponent(0.35)
            p.lineWidth = 1
            let shine = SKShapeNode(ellipseOf: CGSize(width: w * 0.42, height: h * 0.3))
            shine.fillColor = UIColor(white: 1, alpha: 0.45)
            shine.strokeColor = .clear
            shine.position = CGPoint(x: -w * 0.12, y: h * 0.12)
            shine.zPosition = 0.1
            p.addChild(shine)
            puddleLayer.addChild(p)
            puddles.append(p)
            if reduceMotion {
                p.setScale(1)
            } else {
                p.xScale = 0.15
                p.yScale = 0.3
                let grow = SKAction.scaleX(to: 1, y: 1, duration: 0.45)
                grow.timingMode = .easeOut
                p.run(grow)
            }
        }
        for (i, pt) in pts.enumerated() where i < puddles.count {
            puddles[i].position = CGPoint(x: pt.x, y: counterY + 1)
        }
    }
}
