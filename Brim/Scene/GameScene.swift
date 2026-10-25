import Foundation
import QuartzCore
import SpriteKit
import UIKit

/// The SpriteKit view of a `GameSnapshot` (ARCHITECTURE.md "Scene API").
///
/// Composition (round 2, one 670 × 952 world for every device): the raised half (y 496…952) is the back bar with the
/// jug, the fold is y 456…496, the flat half (y 0…456) is the counter top seen from above with the glass in the
/// middle. The HUD band (y ≥ 842) is kept calm. Phones see x ≈ 116…554 of the same world (aspect fill), so anything
/// that matters stays inside x 130…540 (`safeX`).
///
/// Layering (content node, back to front):
///   backdrop (one pre-rendered texture)          z −100
///   lift shadow under the crease (Duo)           z −90
///   belt slats (Conveyor) −30 · puddles −25 (under the coasters) · coaster + next-glass slot coaster −20
///   glass backs (ring, shadow, interior, liquid, foam, bubbles, flash)   z 0
///   splash droplets inside the glasses                                   z 8
///   stream ribbon + droplets                                              z 10
///   glass fronts (walls, outline, band, line, overflow, stamp)           z 20
///   jug                                                                   z 30
///   FX particles / rings                                                  z 40
/// `world` (parent of `shaker`, parent of `content`) sits at the canvas centre so the Perfect camera bump is a zoom
/// that never reveals an edge; `shaker` carries the spill shake.
///
/// Cosmetic simulation runs on the session's clock (snapshot time), so when the session is paused or frozen
/// (DemoMode `freezeOn`) the frame holds still — a Perfect captured 0.15 s after the verdict shows the burst.
@MainActor
final class GameScene: SKScene {
    weak var driver: SceneDriver?

    /// Respect Reduce Motion: no camera bump, no shake, no hop, fewer particles, fades instead of pops.
    var reduceMotion: Bool = false {
        didSet { fx.reduceMotion = reduceMotion }
    }

    /// Venue look. nil = derive from the session's mode (shift levels), falling back to the Lemonade Stand.
    var venue: VenueID? {
        didSet { if venue != oldValue { paletteChanged() } }
    }

    /// Rush's dusk look (string lights, indigo-to-peach wall). Also switched on automatically in `.rush` mode.
    var rushLook: Bool = false {
        didSet { if rushLook != oldValue { paletteChanged() } }
    }

    /// The Daily's tear-off calendar number ("#297" on the wall). nil = derive from `.daily(day)` mode; set it to
    /// override (e.g. a Daily backdrop on Home). The calendar shows only when a number is known.
    var dailyNumber: Int? {
        didSet { if dailyNumber != oldValue { paletteChanged() } }
    }

    let layout: WorldLayout

    /// World bounds of the jug this frame (for placing hints beside it, never over it). `.null` before the first frame.
    private(set) var jugWorldBounds: CGRect = .null
    /// World point at the right end of the active glass's fill line (for a "Fill to here" callout). nil if none.
    private(set) var activeLineWorld: CGPoint?
    /// World rect of the glass under the spout (the last glass that stood there filling; kept between glasses so UI
    /// keep-outs don't flicker). nil before the first one. Use it for Home's button keep-out (REVIEW-2 P1-2).
    private(set) var activeGlassWorldFrame: CGRect?
    /// World rect of the next glass waiting on the counter (ROUND-3 decision 2), nil when none is waiting.
    private(set) var waitingGlassWorldFrame: CGRect?
    /// ROUND-3 decision 3: no scene text (stamps, streak pops) reaches above this world y (crease bottom − 8).
    var foldKeepOutTop: CGFloat { layout.creaseMinY - 8 }
    /// The x range (world) that is on screen on every supported device: visibleRect inset by 14, ≥ 130…540 on phones.
    let safeX: ClosedRange<CGFloat>

    private var autoVenue: VenueID?
    private var autoRush = false
    private var autoDaily: Int?
    private var palette: ScenePalette
    private var backdropScale: CGFloat = 0
    private var backdropCache: [String: SKTexture] = [:]

    private let world: SKNode
    private let shaker: SKNode
    private let content: SKNode
    private let backdrop: SKSpriteNode
    private let beltSlats: SKShapeNode
    private let coaster: SKShapeNode
    private let coasterEdge: SKShapeNode
    private let coasterInner: SKShapeNode
    /// The next-glass slot's own coaster (ROUND-3 decision 2).
    private let slotCoaster: SKShapeNode
    private let slotCoasterEdge: SKShapeNode
    private let slotCoasterInner: SKShapeNode
    /// A soft shadow under the crease that deepens as the top half is lifted (REVIEW-2 P2-3, Duo only).
    private let liftShadow: SKSpriteNode
    private let glassBackLayer: SKNode
    private let streamLayer: SKNode
    private let glassFrontLayer: SKNode
    private let jugLayer: SKNode
    private let fxLayer: SKNode

    private let jug: SceneJug
    private let stream: SceneStream
    private let fx: SceneFX
    private var glasses: [Int: SceneGlass] = [:]
    private var bandEstimate: [Int: Double] = [:]
    private var wasInBand: [Int: Bool] = [:]
    private var spilled: Set<Int> = []
    /// How many spill bursts (sheet + droplets + shake) have played since the last reset. Only real overflow
    /// (`.overflowStarted` or a `.spill` verdict) starts one — never `.over` (ROUND-5 decision 4). For tests.
    private(set) var spillFXCount = 0

    private var lastUpdateTime: TimeInterval?
    private var lastSimTime: Double?
    private var frameCount = 0
    private var lastSnapshot: GameSnapshot?
    private var lastMode: GameMode?
    private var coasterX: CGFloat = 0
    private var coasterScale: CGFloat = 1
    private var coasterShown = false
    private var slotX: CGFloat?
    private var slotScale: CGFloat = 1
    private var slotAlpha: CGFloat = 0
    private var slotDrop: CGFloat = 0
    private var lastPhase: [Int: GlassPhase] = [:]
    private var spillColor: UIColor = SceneColor.coral
    private var lastCounterSplash: Double = -10
    private var lastServedGlass: Int?
    private var ghostJug: SKNode?
    private var beltOffset: CGFloat = 0
    private var frozen = false

    static let beltPitch: CGFloat = 26
    /// REVIEW-3 P1-1 / P1-4: the next glass is drawn as *waiting*: smaller (0.82 Duo, 0.75 phones), set this much
    /// lower on the counter, at this opacity, on a plain coaster. It grows and brightens as it slides to the stop.
    /// Core places the slot for exactly these scales (`NextGlassSlot`), so they come from `CoreTuning`.
    static let waitingScaleFold = CGFloat(CoreTuning.nextGlassScaleFold)
    static let waitingScalePhone = CGFloat(CoreTuning.nextGlassScalePhone)
    static let waitingDropFold: CGFloat = 10
    static let waitingDropPhone: CGFloat = 8
    static let waitingAlpha: CGFloat = 0.6
    /// The waiting look's scale on this canvas.
    var waitingScale: CGFloat { layout.hasFold ? GameScene.waitingScaleFold : GameScene.waitingScalePhone }

    init(layout: WorldLayout) {
        self.layout = layout
        let vr = layout.visibleRect
        let lo = max(0, vr.minX + 14), hi = min(layout.size.width, vr.maxX - 14)
        safeX = lo < hi ? lo...hi : 0...max(1, layout.size.width)
        let pal = ScenePalette.forVenue(nil)
        palette = pal
        world = SKNode()
        shaker = SKNode()
        content = SKNode()
        backdrop = SKSpriteNode(color: pal.wallBottom, size: layout.size)
        beltSlats = SKShapeNode()
        coaster = SKShapeNode()
        coasterEdge = SKShapeNode()
        coasterInner = SKShapeNode()
        slotCoaster = SKShapeNode()
        slotCoasterEdge = SKShapeNode()
        slotCoasterInner = SKShapeNode()
        liftShadow = SKSpriteNode(texture: SceneArt.verticalGradient(
            key: "lift-shadow", colors: [SceneColor.ink.withAlphaComponent(0.55), SceneColor.ink.withAlphaComponent(0.18),
                                         SceneColor.ink.withAlphaComponent(0)], locations: [0, 0.35, 1]))
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
        world.addChild(shaker)
        shaker.addChild(content)

        backdrop.anchorPoint = .zero
        backdrop.position = .zero
        backdrop.zPosition = -100
        content.addChild(backdrop)

        // Conveyor belt slats (moved by the glasses' speed; hidden in other venues).
        let sp = CGMutablePath()
        let cy = layout.counterY
        var x: CGFloat = -GameScene.beltPitch
        while x < layout.size.width + GameScene.beltPitch * 2 {
            sp.move(to: CGPoint(x: x, y: cy - 44))
            sp.addLine(to: CGPoint(x: x, y: cy + 44))
            x += GameScene.beltPitch
        }
        beltSlats.path = sp
        beltSlats.strokeColor = UIColor(white: 1, alpha: 0.13)
        beltSlats.lineWidth = 2.5
        beltSlats.zPosition = -30
        beltSlats.isHidden = true
        content.addChild(beltSlats)

        for (c, e, i) in [(coaster, coasterEdge, coasterInner), (slotCoaster, slotCoasterEdge, slotCoasterInner)] {
            c.path = CGPath(ellipseIn: CGRect(x: -60, y: -12, width: 120, height: 24), transform: nil)
            c.lineWidth = 1.4
            e.path = CGPath(ellipseIn: CGRect(x: -60, y: -15.5, width: 120, height: 24), transform: nil)
            e.strokeColor = .clear
            e.zPosition = -0.5
            i.path = CGPath(ellipseIn: CGRect(x: -44, y: -8, width: 88, height: 16), transform: nil)
            i.fillColor = .clear
            i.lineWidth = 1.6
            i.zPosition = 0.1
            c.addChild(e)
            c.addChild(i)
            c.zPosition = -20
            c.alpha = 0
            c.position = CGPoint(x: layout.jugPivot.x, y: layout.counterY + 2)
            content.addChild(c)
        }
        // The next-glass slot's coaster is plain: no inner ring (REVIEW-3 P1-1, "waiting", not "pour here").
        slotCoasterInner.isHidden = true

        // Puddles lie UNDER the coasters (REVIEW-2 P1-4): a spill spreads around the coaster, never over it.
        fx.puddleLayer.zPosition = -25
        content.addChild(fx.puddleLayer)

        liftShadow.anchorPoint = CGPoint(x: 0.5, y: 1)
        liftShadow.size = CGSize(width: layout.size.width + 40, height: 90)
        liftShadow.position = CGPoint(x: layout.size.width * 0.5, y: layout.creaseMinY)
        liftShadow.zPosition = -90
        liftShadow.alpha = 0
        liftShadow.isHidden = !layout.hasFold
        content.addChild(liftShadow)

        glassBackLayer.zPosition = 0
        fx.innerRoot.zPosition = 8
        streamLayer.zPosition = 10
        glassFrontLayer.zPosition = 20
        jugLayer.zPosition = 30
        fxLayer.zPosition = 40
        for n in [glassBackLayer, fx.innerRoot, streamLayer, glassFrontLayer, jugLayer, fxLayer] { content.addChild(n) }
        streamLayer.addChild(stream.root)
        jugLayer.addChild(jug.root)
        fxLayer.addChild(fx.root)
        stream.clear()
        applyPaletteToNodes()
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
        bandEstimate.removeAll()
        wasInBand.removeAll()
        spilled.removeAll()
        spillFXCount = 0
        fx.clear()
        stream.clear()
        ghostJug?.removeFromParent()
        ghostJug = nil
        jugLayer.removeAllActions()
        jugLayer.position = .zero
        jugLayer.alpha = 1
        world.removeAllActions()
        world.setScale(1)
        shaker.removeAllActions()
        shaker.position = .zero
        coaster.removeAllActions()
        coaster.alpha = 0
        coasterShown = false
        slotCoaster.alpha = 0
        slotAlpha = 0
        slotX = nil
        slotDrop = 0
        lastPhase.removeAll()
        activeGlassWorldFrame = nil
        waitingGlassWorldFrame = nil
        content.isPaused = false
        frozen = false
        lastServedGlass = nil
        lastSimTime = nil
        spillColor = SceneColor.opaque(snapshot.jug.liquid.top.skColor)
        lastSnapshot = snapshot
        lastMode = snapshot.mode
        updateAutoLook(snapshot.mode)
        render(snapshot, dt: 0, advanced: false)
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        var dt: Double = 1.0 / 120.0
        if let last = lastUpdateTime { dt = min(max(currentTime - last, 0), 1.0 / 30.0) }
        lastUpdateTime = currentTime

        frameCount += 1
        #if DEBUG
        if frameCount == 120 {
            print("BRIM-T frame 120")
            fflush(stdout)
        }
        #endif
        if backdropScale == 0 { buildBackdrop(scale: 2) }

        var events: [GameEvent] = []
        var advanced = false
        if let d = driver, let out = d.advance(dt: dt, now: CACurrentMediaTime()) {
            lastSnapshot = out.0
            events = out.1
            advanced = true
        }
        guard let s = lastSnapshot else { return }
        // Simulation dt: how far the session's clock moved (0 while paused / frozen).
        var simDt: Double = 0
        if advanced {
            if let prev = lastSimTime { simDt = min(max(s.time - prev, 0), 1.0 / 30.0) } else { simDt = dt }
            lastSimTime = s.time
        }
        let holding = advanced && simDt <= 0 && events.isEmpty
        if holding != frozen {
            frozen = holding
            content.isPaused = holding
        }
        let cdt = CGFloat(simDt)
        if advanced { preRender(events) }
        render(s, dt: cdt, advanced: advanced)
        if advanced { handle(events, s) }
        fx.update(cdt)
    }

    private func render(_ s: GameSnapshot, dt: CGFloat, advanced: Bool) {
        if s.mode != lastMode {
            lastMode = s.mode
            updateAutoLook(s.mode)
        }
        let cy = layout.counterY

        // Where does the stream land? (thick drinks coil there)
        var landing: CGPoint?
        if let tail = s.stream.last {
            for (_, v) in glasses where v.surfaceFraction(worldX: tail.position.x) != nil {
                landing = CGPoint(x: tail.position.x, y: v.surfaceWorldY)
                break
            }
        }
        stream.update(points: s.stream, droplets: s.droplets, liquid: s.jug.liquid, time: s.time, landing: landing,
                      lip: s.jug.flow > 0.004 ? s.jug.lip : nil)
        jug.update(s.jug, streamWidth: stream.displayWidth(s.stream.first?.width ?? 0), time: s.time, dt: dt)
        updateLiftShadow(s, dt: dt)
        if s.jug.outline.count >= 3 {
            // Everything drawn (lid, knob, handle included), so hints beside the jug never overlap it.
            var drawn = jug.worldBounds
            if drawn.isNull { drawn = ScenePaths.bounds(s.jug.outline).insetBy(dx: -10, dy: -10) }
            jugWorldBounds = drawn.insetBy(dx: -4, dy: -4).offsetBy(dx: jugLayer.position.x, dy: jugLayer.position.y)
        }

        let pouring = s.jug.flow > 0.02 || !s.stream.isEmpty
        let tail = s.stream.last
        let baseBand = defaultBand(s.mode)
        var activeID: Int?
        for g in s.glasses where g.phase == .filling { activeID = g.id; break }
        activeLineWorld = nil
        var waitingID: Int?
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
            measureBand(g)
            // REVIEW-3 P1-4 safety net: a waiting glass PARKED within 4 pt of the crop's edge fades out (Core parks it
            // ≥ 16 pt clear of the coaster; this only bites on an unexpected canvas or glass). Sliding in from off
            // screen is not "parked".
            var suppress = false
            if g.isWaitingInSlot && view.isStill {
                let left = g.x - view.localLeftHalfWidth * waitingScale
                suppress = left < layout.visibleRect.minX + 4
            }
            var gf = GlassFrame(counterY: cy, dt: dt, time: s.time, pouring: pouring, tail: tail, advanced: advanced,
                                reduceMotion: reduceMotion, band: bandEstimate[g.id] ?? baseBand,
                                projected: g.id == activeID ? s.telemetry.projectedDistanceToLine : nil,
                                safeX: safeX, keepOutTop: foldKeepOutTop)
            gf.waitingScale = waitingScale
            gf.waitingDrop = layout.hasFold ? GameScene.waitingDropFold : GameScene.waitingDropPhone
            gf.waitingAlpha = GameScene.waitingAlpha
            gf.suppressed = suppress
            view.update(g, gf)
            if g.id == activeID {
                activeLineWorld = CGPoint(x: g.x + view.outerRimHalfWidth + 12, y: cy + view.base + g.lineHeight)
                if view.isStill { activeGlassWorldFrame = view.worldFrame }
            } else if g.isWaitingInSlot && !suppress && view.isStill && view.stillFor > 0.1 {
                waitingID = g.id
                waitingGlassWorldFrame = view.worldFrame
            }
            // Decision 4: when a glass starts to leave, the puddle under it starts drying.
            if let prev = lastPhase[g.id], prev != g.phase, g.phase == .leaving {
                fx.dryPuddles(nearX: g.x, halfWidth: view.baseOuterHalfWidth + 40)
            }
            lastPhase[g.id] = g.phase
            // Overflow / wet drips.
            if advanced && dt > 0 {
                let rate: Double = g.overflowing ? 0.07 : 0.22
                if (g.overflowing || view.isWet) && s.time - view.lastDripTime > rate {
                    view.lastDripTime = s.time
                    let side: CGFloat = Int(s.time * 9.1) % 2 == 0 ? -1 : 1
                    let y = g.overflowing ? view.rimWorld.y - 6 : cy + view.base * 0.5
                    fx.drip(at: CGPoint(x: g.x + side * (view.outerRimHalfWidth + 4), y: y),
                            color: view.liquidColor, floorY: cy - 3, big: g.overflowing)
                }
            }
        }
        for (id, v) in glasses where !seen.contains(id) {
            v.remove()
            glasses[id] = nil
            bandEstimate[id] = nil
            wasInBand[id] = nil
            lastPhase[id] = nil
            spilled.remove(id)
        }
        if waitingID == nil { waitingGlassWorldFrame = nil }

        updateCoaster(s, dt: dt)
        updateSlotCoaster(s, waitingID: waitingID, dt: dt)
        updateBelt(s, dt: dt)
        fx.syncPuddles(s.puddles, counterY: cy, color: spillColor)
    }

    /// The Perfect band isn't in the snapshot: use the level's band, refined by watching `inPerfectBand` switch on.
    private func defaultBand(_ mode: GameMode) -> Double {
        switch mode {
        case let .shift(id): return LevelCatalog.level(id)?.perfectBand ?? 0.025
        case .rush: return 0.026
        case .daily: return 0.03
        case .practice: return 0.03
        }
    }

    private func measureBand(_ g: GlassState) {
        let was = wasInBand[g.id] ?? false
        if g.inPerfectBand && !was && g.phase == .filling && g.lineOpacity > 0.01 {
            let interior = g.shape.interiorHeight
            if interior > 1 {
                let top = g.liquidHeight + g.foamHeight
                let m = Double(abs(top - g.lineHeight) / interior)
                if m > 0.008 && m < 0.06 { bandEstimate[g.id] = m }
            }
        }
        wasInBand[g.id] = g.inPerfectBand
    }

    /// The coaster marks the pour spot: wherever a filling glass stands still. Sized to the glass. Fades in once.
    private func updateCoaster(_ s: GameSnapshot, dt: CGFloat) {
        if palette.venue == .conveyor {
            coaster.isHidden = true
            return
        }
        coaster.isHidden = false
        var target: CGFloat?
        var targetScale: CGFloat = coasterScale
        for g in s.glasses where g.phase == .filling {
            if let v = glasses[g.id], v.isStill {
                target = g.x
                targetScale = min(1.7, max(0.8, (v.baseOuterHalfWidth * 2 + 48) / 120 * v.displayScale))
                break
            }
        }
        guard let tx = target else { return }
        if !coasterShown {
            coasterShown = true
            coasterX = tx
            coasterScale = targetScale
            coaster.run(SKAction.fadeIn(withDuration: 0.25))
        } else if dt > 0 {
            coasterX += (tx - coasterX) * min(1, dt * 8)
            coasterScale += (targetScale - coasterScale) * min(1, dt * 8)
        }
        coaster.position = CGPoint(x: coasterX, y: layout.counterY + 2)
        coaster.xScale = coasterScale
        coaster.yScale = coasterScale
    }

    /// The next-glass slot (ROUND-3 decision 2): a coaster of its own under the waiting glass. It learns the slot from
    /// where Core parks the waiting glass, stays while a glass is in or near the slot, and fades when the slot empties.
    private func updateSlotCoaster(_ s: GameSnapshot, waitingID: Int?, dt: CGFloat) {
        if palette.venue == .conveyor {
            slotCoaster.isHidden = true
            return
        }
        slotCoaster.isHidden = false
        if let id = waitingID, let v = glasses[id] {
            let target = slotCoasterScale(for: v)
            if slotX == nil { slotScale = target }
            slotX = v.x
            slotDrop = v.dropY
            if dt > 0 { slotScale += (target - slotScale) * min(1, dt * 8) }
        }
        guard let sx = slotX else {
            slotCoaster.alpha = 0
            return
        }
        // Occupied: a glass queued for the slot (Core: `.arriving` with its line hidden) stands in or near it.
        var occupied = false
        for g in s.glasses where g.isWaitingInSlot && abs(g.x - sx) < 60 { occupied = true; break }
        let target: CGFloat = occupied ? 1 : 0
        if dt > 0 {
            let rate: CGFloat = occupied ? 6 : 2.5
            slotAlpha += (target - slotAlpha) * min(1, dt * rate)
        } else if waitingID != nil && slotAlpha < 0.01 {
            slotAlpha = 1
        }
        slotCoaster.alpha = slotAlpha * GameScene.slotCoasterAlpha
        slotCoaster.position = CGPoint(x: sx, y: layout.counterY + 2 - slotDrop)
        slotCoaster.setScale(slotScale)
    }

    /// The waiting glass's plain coaster is about 0.9× the glass's own coaster, scaled with the glass, and never runs
    /// off the crop's left edge (it shrinks to keep ≥ 6 pt clear, but stays ≥ 6 pt wider than the glass's base).
    static let slotCoasterAlpha: CGFloat = 0.85

    private func slotCoasterScale(for v: SceneGlass) -> CGFloat {
        let k = v.displayScale
        var target = (v.baseOuterHalfWidth * 2 + 36) / 120 * k
        let room = (v.x - (layout.visibleRect.minX + 6)) / 60
        let minFit = (v.baseOuterHalfWidth * k + 6) / 60
        target = min(target, room)
        target = max(target, minFit)
        return min(1.4, max(0.5, target))
    }

    /// Duo: the raised half casts a soft shadow onto the counter that deepens as the lid lifts (REVIEW-2 P2-3).
    private func updateLiftShadow(_ s: GameSnapshot, dt: CGFloat) {
        guard layout.hasFold else { return }
        // Round 4 (REVIEW-3 P2-9: "still doesn't react"): a deeper, longer shadow, so the lift reads in a still.
        let lift = CGFloat(min(max(s.jug.angle / 70, 0), 1))
        let target = 0.12 + 0.62 * lift
        if dt > 0 {
            liftShadow.alpha += (target - liftShadow.alpha) * min(1, dt * 6)
        } else if liftShadow.alpha <= 0.001 {
            liftShadow.alpha = target
        }
        liftShadow.yScale = 0.7 + 0.75 * lift
    }

    /// Conveyor: the belt slats move with whatever glass is riding it.
    private func updateBelt(_ s: GameSnapshot, dt: CGFloat) {
        guard palette.venue == .conveyor else {
            beltSlats.isHidden = true
            return
        }
        beltSlats.isHidden = false
        var speed: CGFloat = 0
        for g in s.glasses {
            if let v = glasses[g.id], abs(v.velocityX) > abs(speed) { speed = v.velocityX }
        }
        speed = min(max(speed, -600), 600)
        beltOffset += speed * dt
        beltOffset = beltOffset.truncatingRemainder(dividingBy: GameScene.beltPitch)
        beltSlats.position = CGPoint(x: beltOffset, y: 0)
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
                    fx.splashCrown(at: CGPoint(x: x, y: v.surfaceWorldY), glassX: v.x,
                                   mouthHalfWidth: max(4, min(v.surfaceHalfWidth, v.innerRimHalfWidth)),
                                   color: v.liquidColor, strength: strength, granular: v.isGranular)
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
            case let .lockedIn(glassID):
                glasses[glassID]?.lockIn()
            case let .overflowStarted(glassID):
                spill(glassID)
            case let .glassArrived(glassID):
                glasses[glassID]?.slosh(2)
            case let .served(glassID, judgement, _):
                lastServedGlass = glassID
                guard let v = glasses[glassID] else { break }
                if judgement == .perfect {
                    v.celebrate()
                    fx.perfectBurst(rim: v.rimWorld, rimHalfWidth: v.outerRimHalfWidth, liquid: v.liquidColor,
                                    floorY: layout.counterY - 4)
                    bump()
                } else if judgement == .spill {
                    // ROUND-5 decision 4: `.spill` now only ever means liquid really crossed the rim (usually already
                    // shown by `.overflowStarted`; `spill` runs once per glass).
                    spill(glassID)
                }
                // `.over` (past the Good band, nothing over the rim) and `.short`: the stamp only — no sheet, no
                // burst, no shake, no wet glass.
            case let .streak(n):
                if n >= 2, let id = lastServedGlass, let v = glasses[id] {
                    v.showStreak(n, reduceMotion: reduceMotion, safeX: safeX, keepOutTop: foldKeepOutTop)
                }
            case .jugRefilled:
                fx.refillGlints(at: s.jug.lip)
            case .flatArmed:
                // The start gate opened: a little "ready" twinkle at the spout.
                fx.refillGlints(at: s.jug.lip)
            default:
                break
            }
        }
    }

    /// Spill (once per glass): the sheet breaks, droplets rain, the screen shakes, the glass stays wet.
    private func spill(_ glassID: Int) {
        guard let v = glasses[glassID] else { return }
        spillColor = v.liquidColor
        if spilled.contains(glassID) { return }
        spilled.insert(glassID)
        spillFXCount += 1
        v.startOverflow()
        v.markWet(seconds: 2.2)
        fx.spillBurst(rim: v.rimWorld, rimHalfWidth: v.outerRimHalfWidth, color: v.liquidColor, floorY: layout.counterY - 3)
        shake()
    }

    /// Small camera bump on Perfect (a zoom about the canvas centre). Skipped under Reduce Motion.
    private func bump() {
        guard !reduceMotion else { return }
        let a = SKAction.scale(to: 1.03, duration: 0.06)
        a.timingMode = .easeOut
        let b = SKAction.scale(to: 1.0, duration: 0.32)
        b.timingMode = .easeInEaseOut
        world.removeAction(forKey: "bump")
        world.run(SKAction.sequence([a, b]), withKey: "bump")
    }

    /// 0.25 s screen shake on Spill. Skipped under Reduce Motion.
    private func shake() {
        guard !reduceMotion else { return }
        var steps: [SKAction] = []
        let offsets: [(CGFloat, CGFloat)] = [(-9, 3), (8, -4), (-6, 2), (5, -2), (-3, 1), (0, 0)]
        for o in offsets {
            let m = SKAction.move(to: CGPoint(x: o.0, y: o.1), duration: 0.042)
            m.timingMode = .easeInEaseOut
            steps.append(m)
        }
        shaker.removeAction(forKey: "shake")
        shaker.run(SKAction.sequence(steps), withKey: "shake")
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
                let up = SKAction.moveBy(x: 0, y: 340, duration: 0.42)
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
            jugLayer.position = CGPoint(x: 0, y: 360)
            let down = SKAction.move(to: .zero, duration: 0.5)
            down.timingMode = .easeOut
            jugLayer.run(SKAction.sequence([SKAction.wait(forDuration: 0.18), down]))
        }
    }

    // MARK: Palette / backdrop

    private func updateAutoLook(_ mode: GameMode) {
        var v: VenueID?
        var rush = false
        var daily: Int?
        switch mode {
        case let .shift(id): v = LevelCatalog.level(id)?.venue
        case .rush: rush = true
        case let .daily(day): daily = day
        case .practice: break
        }
        if v != autoVenue || rush != autoRush || daily != autoDaily {
            autoVenue = v
            autoRush = rush
            autoDaily = daily
            paletteChanged()
        }
    }

    private var effectiveVenue: VenueID { venue ?? autoVenue ?? .lemonadeStand }
    private var effectiveRush: Bool { rushLook || autoRush }
    private var effectiveDaily: Int? { dailyNumber ?? autoDaily }

    private func paletteChanged() {
        var p = ScenePalette.forVenue(effectiveVenue)
        if effectiveRush { p = p.duskified() }
        palette = p
        applyPaletteToNodes()
        if backdropScale > 0 { buildBackdrop(scale: backdropScale) }
    }

    private func applyPaletteToNodes() {
        backgroundColor = palette.counterFrontDark
        coaster.fillColor = palette.coaster
        coaster.strokeColor = SceneColor.darker(palette.coasterRing, 0.1).withAlphaComponent(0.7)
        coasterEdge.fillColor = SceneColor.darker(palette.coasterRing, 0.15)
        coasterInner.strokeColor = palette.coasterRing.withAlphaComponent(0.75)
        slotCoaster.fillColor = palette.coaster
        slotCoaster.strokeColor = coaster.strokeColor
        slotCoasterEdge.fillColor = coasterEdge.fillColor
        slotCoasterInner.strokeColor = coasterInner.strokeColor
        jug.setStyle(palette.vessel)
    }

    private func buildBackdrop(scale: CGFloat) {
        let dailyKey = effectiveDaily.map { String($0) } ?? "-"
        let key = "\(effectiveVenue.rawValue)-\(effectiveRush ? "dusk" : "day")-\(dailyKey)@\(Int(scale * 10))"
        let tex: SKTexture
        if let t = backdropCache[key] {
            tex = t
        } else {
            tex = SceneArt.backdrop(layout: layout, palette: palette, dailyNumber: effectiveDaily, scale: scale)
            // ~23 MB per full-canvas texture at 3×: keep at most two looks (QA-1 P2-13).
            if backdropCache.count >= 2 { backdropCache.removeAll() }
            backdropCache[key] = tex
        }
        backdropScale = scale
        backdrop.texture = tex
        backdrop.color = .white
        backdrop.colorBlendFactor = 0
        backdrop.size = layout.size
    }
}
