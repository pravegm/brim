import Foundation
import QuartzCore
import SpriteKit
import UIKit

/// The SpriteKit view of a `GameSnapshot` (ARCHITECTURE.md "Scene API").
///
/// Layering (content node, back to front):
///   backdrop (one pre-rendered texture: café back-bar, crease seam, counter)  z −100
///   coaster  −20 · puddles −10
///   glass backs (shadow, interior, liquid, foam, bubbles)                      z 0
///   stream ribbon + droplets                                                   z 10
///   glass fronts (walls, highlights, rim, fill line, overflow, patience, stamp) z 20
///   jug                                                                        z 30
///   FX particles / rings                                                       z 40
/// `world` (parent of `content`) sits at the canvas centre so the Perfect camera bump is a zoom that never
/// reveals an edge.
///
/// The scene only draws snapshots and reacts to events; everything it simulates (surface waves, bubbles,
/// splash particles, stamps) is cosmetic.
@MainActor
final class GameScene: SKScene {
    weak var driver: SceneDriver?

    /// Respect Reduce Motion: no camera bump, fewer particles, fades instead of pops.
    var reduceMotion: Bool = false {
        didSet { fx.reduceMotion = reduceMotion }
    }

    /// Venue look. nil = derive from the session's mode (shift levels), falling back to the Lemonade Stand.
    var venue: VenueID? {
        didSet { if venue != oldValue { paletteChanged() } }
    }

    let layout: WorldLayout

    private var autoVenue: VenueID?
    private var palette: ScenePalette
    private var backdropScale: CGFloat = 0
    private var backdropCache: [String: SKTexture] = [:]

    private let world: SKNode
    private let content: SKNode
    private let backdrop: SKSpriteNode
    private let coaster: SKShapeNode
    private let coasterEdge: SKShapeNode
    private let coasterInner: SKShapeNode
    private let glassBackLayer: SKNode
    private let streamLayer: SKNode
    private let glassFrontLayer: SKNode
    private let jugLayer: SKNode
    private let fxLayer: SKNode

    private let jug: SceneJug
    private let stream: SceneStream
    private let fx: SceneFX
    private var glasses: [Int: SceneGlass] = [:]

    private var lastUpdateTime: TimeInterval?
    private var frameCount = 0
    private var lastSnapshot: GameSnapshot?
    private var lastMode: GameMode?
    private var coasterX: CGFloat = 0
    private var coasterShown = false
    private var spillColor: UIColor = SceneColor.coral
    private var lastCounterSplash: Double = -10
    private var lastServedGlass: Int?
    private var ghostJug: SKNode?

    init(layout: WorldLayout) {
        self.layout = layout
        let pal = ScenePalette.forVenue(nil)
        palette = pal
        world = SKNode()
        content = SKNode()
        backdrop = SKSpriteNode(color: pal.wallBottom, size: layout.size)
        coaster = SKShapeNode()
        coasterEdge = SKShapeNode()
        coasterInner = SKShapeNode()
        glassBackLayer = SKNode()
        streamLayer = SKNode()
        glassFrontLayer = SKNode()
        jugLayer = SKNode()
        fxLayer = SKNode()
        jug = SceneJug()
        stream = SceneStream()
        fx = SceneFX()
        super.init(size: layout.size)
        setUp()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("GameScene is created in code with init(layout:)")
    }

    private func setUp() {
        scaleMode = .aspectFill
        anchorPoint = .zero
        backgroundColor = palette.counterFrontDark

        world.position = CGPoint(x: layout.size.width * 0.5, y: layout.size.height * 0.5)
        content.position = CGPoint(x: -layout.size.width * 0.5, y: -layout.size.height * 0.5)
        addChild(world)
        world.addChild(content)

        backdrop.anchorPoint = .zero
        backdrop.position = .zero
        backdrop.zPosition = -100
        content.addChild(backdrop)

        coaster.path = CGPath(ellipseIn: CGRect(x: -60, y: -12, width: 120, height: 24), transform: nil)
        coaster.lineWidth = 1.2
        coasterEdge.path = CGPath(ellipseIn: CGRect(x: -60, y: -15, width: 120, height: 24), transform: nil)
        coasterEdge.strokeColor = .clear
        coasterEdge.zPosition = -0.5
        coasterInner.path = CGPath(ellipseIn: CGRect(x: -44, y: -8, width: 88, height: 16), transform: nil)
        coasterInner.fillColor = .clear
        coasterInner.lineWidth = 1.5
        coasterInner.zPosition = 0.1
        coaster.addChild(coasterEdge)
        coaster.addChild(coasterInner)
        coaster.zPosition = -20
        coaster.alpha = 0
        coaster.position = CGPoint(x: layout.jugPivot.x, y: layout.counterY + 2)
        content.addChild(coaster)
        applyCoasterColors()

        fx.puddleLayer.zPosition = -10
        content.addChild(fx.puddleLayer)

        glassBackLayer.zPosition = 0
        streamLayer.zPosition = 10
        glassFrontLayer.zPosition = 20
        jugLayer.zPosition = 30
        fxLayer.zPosition = 40
        for n in [glassBackLayer, streamLayer, glassFrontLayer, jugLayer, fxLayer] { content.addChild(n) }
        streamLayer.addChild(stream.root)
        jugLayer.addChild(jug.root)
        fxLayer.addChild(fx.root)
        stream.clear()
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        let s = min(max(view.contentScaleFactor, 2), 3)
        if backdropScale < s - 0.01 { buildBackdrop(scale: s) }
    }

    // MARK: Public API

    /// New session: clear glasses and FX, then draw the first frame of `snapshot`.
    func reset(for snapshot: GameSnapshot) {
        for (_, v) in glasses { v.remove() }
        glasses.removeAll()
        fx.clear()
        stream.clear()
        ghostJug?.removeFromParent()
        ghostJug = nil
        jugLayer.removeAllActions()
        jugLayer.position = .zero
        jugLayer.alpha = 1
        world.removeAllActions()
        world.setScale(1)
        coaster.removeAllActions()
        coaster.alpha = 0
        coasterShown = false
        lastServedGlass = nil
        spillColor = SceneColor.opaque(snapshot.jug.liquid.top.skColor)
        lastSnapshot = snapshot
        lastMode = snapshot.mode
        updateAutoVenue(snapshot.mode)
        render(snapshot, dt: 0, advanced: false)
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        var dt: Double = 1.0 / 120.0
        if let last = lastUpdateTime { dt = min(max(currentTime - last, 0), 1.0 / 30.0) }
        lastUpdateTime = currentTime

        frameCount += 1
        if frameCount == 120 {
            print("BRIM-T frame 120")
            fflush(stdout)
        }
        if backdropScale == 0 { buildBackdrop(scale: 2) }

        var events: [GameEvent] = []
        var advanced = false
        if let d = driver, let out = d.advance(dt: dt, now: CACurrentMediaTime()) {
            lastSnapshot = out.0
            events = out.1
            advanced = true
        }
        let cdt = CGFloat(dt)
        if let s = lastSnapshot {
            if advanced { preRender(events) }
            render(s, dt: cdt, advanced: advanced)
            if advanced { handle(events, s) }
        }
        fx.update(cdt)
    }

    private func render(_ s: GameSnapshot, dt: CGFloat, advanced: Bool) {
        if s.mode != lastMode {
            lastMode = s.mode
            updateAutoVenue(s.mode)
        }
        let cy = layout.counterY

        jug.update(s.jug)
        stream.update(points: s.stream, droplets: s.droplets, liquid: s.jug.liquid)

        let pouring = s.jug.flow > 0.02 || !s.stream.isEmpty
        let tail = s.stream.last
        var seen = Set<Int>()
        for (i, g) in s.glasses.enumerated() {
            seen.insert(g.id)
            let view: SceneGlass
            if let v = glasses[g.id] {
                view = v
            } else {
                view = SceneGlass(id: g.id, darkBackdrop: palette.isDark)
                glassBackLayer.addChild(view.back)
                glassFrontLayer.addChild(view.front)
                glasses[g.id] = view
            }
            view.back.zPosition = CGFloat(i) * 0.25
            view.front.zPosition = CGFloat(i) * 0.25
            view.update(g, counterY: cy, dt: dt, time: s.time, pouring: pouring, tail: tail, advanced: advanced,
                        reduceMotion: reduceMotion)
            if g.overflowing && advanced && s.time - view.lastDripTime > 0.16 {
                view.lastDripTime = s.time
                let side: CGFloat = Int(s.time * 6.25) % 2 == 0 ? -1 : 1
                fx.drip(at: CGPoint(x: g.x + side * (view.outerRimHalfWidth + 2.5), y: view.rimWorld.y - 6),
                        color: view.liquidColor, floorY: cy - 2)
            }
        }
        for (id, v) in glasses where !seen.contains(id) {
            v.remove()
            glasses[id] = nil
        }

        updateCoaster(s, dt: dt)
        fx.syncPuddles(s.puddles, counterY: cy, color: spillColor)
    }

    /// The coaster marks the pour spot: wherever a filling glass stands still. Fades in the first time.
    private func updateCoaster(_ s: GameSnapshot, dt: CGFloat) {
        var target: CGFloat?
        for g in s.glasses where g.phase == .filling {
            if let v = glasses[g.id], v.isStill { target = g.x; break }
        }
        guard let tx = target else { return }
        if !coasterShown {
            coasterShown = true
            coasterX = tx
            coaster.run(SKAction.fadeIn(withDuration: 0.25))
        } else if dt > 0 {
            coasterX += (tx - coasterX) * min(1, dt * 8)
        }
        coaster.position = CGPoint(x: coasterX, y: layout.counterY + 2)
    }

    // MARK: Events

    private func preRender(_ events: [GameEvent]) {
        for e in events {
            if case .jugSwapped = e { swapJug() }
        }
    }

    private func handle(_ events: [GameEvent], _ s: GameSnapshot) {
        for e in events {
            switch e {
            case let .splashInGlass(glassID, x, strength):
                guard let v = glasses[glassID] else { break }
                v.splash(worldX: x, strength: strength)
                if s.time - v.lastCrownTime > 0.07 {
                    v.lastCrownTime = s.time
                    fx.splashCrown(at: CGPoint(x: x, y: v.surfaceWorldY), color: v.liquidColor, strength: strength,
                                   mouthHalfWidth: v.outerRimHalfWidth)
                }
            case let .splashOnCounter(x, strength):
                let c = SceneColor.mix(SceneColor.opaque(s.jug.liquid.bottom.skColor), SceneColor.opaque(s.jug.liquid.top.skColor), 0.6)
                spillColor = c
                if s.time - lastCounterSplash > 0.06 {
                    lastCounterSplash = s.time
                    fx.counterSplash(at: CGPoint(x: x, y: layout.counterY), color: c, strength: strength)
                }
            case let .enteredPerfectBand(glassID):
                glasses[glassID]?.flashLine()
            case let .overflowStarted(glassID):
                if let v = glasses[glassID] {
                    spillColor = v.liquidColor
                    v.slosh(5)
                }
            case let .glassArrived(glassID):
                glasses[glassID]?.slosh(2)
            case let .served(glassID, judgement, _):
                lastServedGlass = glassID
                guard let v = glasses[glassID] else { break }
                if judgement == .perfect {
                    fx.perfectBurst(rim: v.rimWorld, rimHalfWidth: v.outerRimHalfWidth, liquid: v.liquidColor,
                                    floorY: layout.counterY - 4)
                    bump()
                }
            case let .streak(n):
                if n >= 2, let id = lastServedGlass, let v = glasses[id] {
                    v.showStreak(n, reduceMotion: reduceMotion)
                }
            case .jugRefilled:
                fx.refillGlints(at: s.jug.lip)
            default:
                break
            }
        }
    }

    /// Small camera bump on Perfect (a zoom about the canvas centre). Skipped under Reduce Motion.
    private func bump() {
        guard !reduceMotion else { return }
        let a = SKAction.scale(to: 1.022, duration: 0.06)
        a.timingMode = .easeOut
        let b = SKAction.scale(to: 1.0, duration: 0.3)
        b.timingMode = .easeInEaseOut
        world.removeAction(forKey: "bump")
        world.run(SKAction.sequence([a, b]), withKey: "bump")
    }

    /// The empty jug slides up and out; the full one slides down into place.
    private func swapJug() {
        ghostJug?.removeFromParent()
        ghostJug = nil
        if let copy = jug.root.copy() as? SKNode {
            copy.removeAllActions()
            copy.position = jugLayer.position
            copy.zPosition = jugLayer.zPosition - 0.5
            copy.alpha = jugLayer.alpha
            content.addChild(copy)
            ghostJug = copy
            if reduceMotion {
                copy.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.25), SKAction.removeFromParent()]))
            } else {
                let up = SKAction.moveBy(x: 0, y: 320, duration: 0.42)
                up.timingMode = .easeIn
                copy.run(SKAction.sequence([SKAction.group([up, SKAction.fadeOut(withDuration: 0.42)]),
                                            SKAction.removeFromParent()]))
            }
        }
        jugLayer.removeAllActions()
        if reduceMotion {
            jugLayer.position = .zero
            jugLayer.alpha = 0
            jugLayer.run(SKAction.fadeIn(withDuration: 0.3))
        } else {
            jugLayer.alpha = 1
            jugLayer.position = CGPoint(x: 0, y: 340)
            let down = SKAction.move(to: .zero, duration: 0.5)
            down.timingMode = .easeOut
            jugLayer.run(SKAction.sequence([SKAction.wait(forDuration: 0.18), down]))
        }
    }

    // MARK: Palette / backdrop

    private func updateAutoVenue(_ mode: GameMode) {
        var v: VenueID?
        if case let .shift(id) = mode { v = LevelCatalog.level(id)?.venue }
        if v != autoVenue {
            autoVenue = v
            paletteChanged()
        }
    }

    private func paletteChanged() {
        palette = ScenePalette.forVenue(venue ?? autoVenue)
        backgroundColor = palette.counterFrontDark
        applyCoasterColors()
        if backdropScale > 0 { buildBackdrop(scale: backdropScale) }
    }

    private func applyCoasterColors() {
        coaster.fillColor = palette.coaster
        coaster.strokeColor = SceneColor.darker(palette.coasterRing, 0.1).withAlphaComponent(0.6)
        coasterEdge.fillColor = SceneColor.darker(palette.coasterRing, 0.15)
        coasterInner.strokeColor = palette.coasterRing.withAlphaComponent(0.7)
    }

    private func buildBackdrop(scale: CGFloat) {
        let key = "\((venue ?? autoVenue ?? .lemonadeStand).rawValue)@\(Int(scale * 10))"
        let tex: SKTexture
        if let t = backdropCache[key] {
            tex = t
        } else {
            tex = SceneArt.backdrop(layout: layout, palette: palette, scale: scale)
            if backdropCache.count >= 3 { backdropCache.removeAll() }
            backdropCache[key] = tex
        }
        backdropScale = scale
        backdrop.texture = tex
        backdrop.color = .white
        backdrop.colorBlendFactor = 0
        backdrop.size = layout.size
    }
}
