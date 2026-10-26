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
///   backdrop (one pre-rendered texture)          z −100 (the previous one cross-fades out over it at −99.5)
///   Conveyor service bell + its ring             z −95 / −94
///   lift shadow under the crease (Duo)           z −90
///   belt slats (Conveyor) −30 · pour zone −28 · puddles −25 (under the coasters) · coaster + slot coaster −20
///   upcoming belt glasses (stand-ins)            z −1 inside the glass layers
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
        didSet {
            fx.reduceMotion = reduceMotion
            jug.reduceMotion = reduceMotion
        }
    }

    /// Venue look. nil = derive from the session's mode (shift levels), falling back to the Lemonade Stand.
    var venue: VenueID? {
        didSet { if venue != oldValue { paletteChanged() } }
    }

    /// Round 8 (Glass Cabinet lite, REVIEW-6 #6): the vessel the player picked for Rush / Practice. When set, the jug
    /// is drawn as that venue's signature vessel (pitcher, soda dispenser, shake tin, potion flask, copper scoop)
    /// around the same interior outline, whatever venue the backdrop shows (Rush keeps it through its tier travel).
    /// nil = each venue's own vessel. Core's jug geometry and physics are unchanged.
    var vesselOverride: VenueID? {
        didSet { if vesselOverride != oldValue { paletteChanged() } }
    }

    /// The vessel on screen (the override's, else the shown venue's). Tests.
    var shownVesselForm: VesselForm { jug.form }
    var shownVesselDecal: VesselDecal { jug.decalKind }
    /// Which signature parts the drawn vessel shows (lid, handle, opaque skin); nil until it has been built. Tests.
    var shownVesselParts: (lid: Bool, handle: Bool, skin: Bool)? {
        guard jug.isBuilt else { return nil }
        return (jug.drawsLid, jug.drawsHandle, jug.drawsSkin)
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

    /// Round 6 (REVIEW-5 §2): the next orders on a conveyor, nearest first, drawn as empty glasses riding in on the
    /// belt behind the one being poured. Shifts derive them from the level (which wins). Round 7 (QA-3 P2-1): Rush has
    /// no list and `GameSnapshot` carries none, so the App sets this to what Core knows of the orders after every glass
    /// on the counter (`[session.upcomingOrder]`, nil/empty when unknown); set it only when it changes. In Rush only
    /// belt orders (no patience) are drawn.
    var upcomingOrders: [GlassOrder]?

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
    /// Tests (QA-4 P1-1): the settled ink of glass `id`'s verdict stamp (world), nil when it shows none.
    func stampInkWorldRect(glassID id: Int) -> CGRect? { glasses[id]?.stampInkWorldRect }
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

    // Round 6
    /// The venue the snapshot asks for (Rush travels one venue per tier). Wins over `venue`.
    private var snapshotVenue: VenueID?
    /// The previous backdrop, fading out over the new one when the venue changes mid-run.
    private let backdropFade: SKSpriteNode
    /// Conveyor: the service bell on the shelf (hops and rings when a glass leaves) and its ring.
    private let bell: SKSpriteNode
    private let bellRing: SKShapeNode
    /// Conveyor: the lit pour zone on the belt under the stream.
    private let pourZone: SKSpriteNode
    /// World x where the stream meets the belt glasses' rims (estimated from where Core parks each belt glass).
    private var zoneX: CGFloat?
    private var zoneAlpha: CGFloat = 0
    private var measuredBeltSpeed: CGFloat = 0
    private var fillStartX: [Int: CGFloat] = [:]
    private var ghosts: [BeltGhost] = []
    private var shiftBeltSpeed: CGFloat?
    private var shiftOrders: [GlassOrder] = []
    private var lastRepose: Double = 0
    private var reposeArmed = true
    /// Tests: how often the bell rang / the sand puffed / the look cross-faded since the last reset.
    private(set) var bellRingCount = 0
    private(set) var reposePuffCount = 0
    private(set) var lookCrossFadeCount = 0
    /// Tests: the pour zone is showing; the order indices of the upcoming glasses riding the belt.
    var pourZoneVisible: Bool { !pourZone.isHidden && pourZone.alpha > 0.05 }
    var pourZoneWorldX: CGFloat? { zoneX }
    var beltQueueKeys: [Int] {
        var out: [Int] = []
        for g in ghosts where !g.retiring { out.append(g.key) }
        return out
    }
    /// The venue whose look is on screen.
    var shownVenue: VenueID { palette.venue }

    /// Where the bell stands: x 510 on the Conveyor's ledge (`SceneBackdropPainter.ledgeY` 766 + 8), 48 pt lower on
    /// phones (`phonePropDrop`), like the painted props around it.
    static let bellX: CGFloat = 510
    static let ledgeTop: CGFloat = 774
    static let phonePropDrop: CGFloat = 48
    /// Upcoming belt glasses: drawn at this scale and opacity, in the waiting look's language.
    static let beltGhostScale: CGFloat = 0.9
    static let beltGhostAlpha: CGFloat = 0.72
    static let beltQueueLength = 2

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
        backdropFade = SKSpriteNode(color: .clear, size: layout.size)
        bell = SKSpriteNode(texture: SceneArt.bell, size: SceneArt.bellSize)
        bellRing = SKShapeNode(ellipseOf: CGSize(width: 30, height: 12))
        pourZone = SKSpriteNode(texture: SceneArt.pourZone, size: SceneArt.pourZoneSize)
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
        backdropFade.anchorPoint = .zero
        backdropFade.position = .zero
        backdropFade.zPosition = -99.5
        backdropFade.isHidden = true
        content.addChild(backdropFade)

        bell.anchorPoint = CGPoint(x: 0.5, y: SceneArt.bellAnchorY)
        bell.position = bellRest
        bell.zPosition = -95
        bell.isHidden = true
        content.addChild(bell)
        bellRing.fillColor = .clear
        bellRing.strokeColor = SceneColor.hex(0xFFE7A0)
        bellRing.lineWidth = 2
        bellRing.zPosition = -94
        bellRing.isHidden = true
        content.addChild(bellRing)

        pourZone.zPosition = -28
        pourZone.alpha = 0
        pourZone.isHidden = true
        content.addChild(pourZone)

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
        // Round 6.
        for g in ghosts { g.view.remove() }
        ghosts.removeAll()
        fillStartX.removeAll()
        zoneX = nil
        zoneAlpha = 0
        pourZone.alpha = 0
        pourZone.isHidden = true
        measuredBeltSpeed = 0
        lastRepose = 0
        reposeArmed = true
        bellRingCount = 0
        reposePuffCount = 0
        lookCrossFadeCount = 0
        bell.removeAllActions()
        bell.position = bellRest
        bell.zRotation = 0
        bellRing.removeAllActions()
        bellRing.isHidden = true
        backdropFade.removeAllActions()
        backdropFade.isHidden = true
        prewarmedTier = 0
        jug.root.removeAction(forKey: "vesselFade")
        jug.root.alpha = 1
        spillColor = SceneColor.opaque(snapshot.jug.liquid.top.skColor)
        lastSnapshot = snapshot
        lastMode = snapshot.mode
        if snapshot.venue != snapshotVenue {
            snapshotVenue = snapshot.venue
            paletteChanged()
        }
        updateAutoLook(snapshot.mode)
        render(snapshot, dt: 0, advanced: false)
    }

    private var bellRest: CGPoint {
        CGPoint(x: GameScene.bellX, y: GameScene.ledgeTop - (layout.hasFold ? 0 : GameScene.phonePropDrop))
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
        // Round 6 (decision 2): Rush travels — the snapshot names the venue per tier; cross-fade to it mid-run.
        if s.venue != snapshotVenue {
            snapshotVenue = s.venue
            paletteChanged(animated: advanced)
        }
        if advanced && dt > 0 { watchRepose(s) }
        let cy = layout.counterY
        let lead = updateBeltEstimate(s, dt: dt)

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
        // Round 9 (QA-4 P1-1): where the glass waiting in the slot stands (its look as last drawn, at this frame's x),
        // so the judged glass's stamp never sits over it.
        var slotGlassID: Int?
        var slotGlassRect: CGRect?
        for g in s.glasses where g.isWaitingInSlot {
            if let v = glasses[g.id], v.drawnAlpha > 0.05 {
                slotGlassID = g.id
                slotGlassRect = v.occupiedWorldRect(centreX: g.x)
            }
            break
        }
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
            gf.beltWindow = beltWindow(g)
            if g.id != slotGlassID { gf.waitingGlassRect = slotGlassRect }
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
                // Conveyor: a glass that rode the belt rides off — the bell on the shelf flicks and rings. Only one
                // that really rode it (moved while served), whatever the room is now: not the last Soda glass as Rush
                // turns into the Conveyor, and still the last belt glass as it turns into the Diner (QA-3 P2-4).
                if prev == .served, view.rodeBelt, let j = g.result { ringBell(judgement: j) }
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
            fillStartX[id] = nil
        }
        if waitingID == nil { waitingGlassWorldFrame = nil }

        // The bell and the belt slats belong to the Conveyor's room: they fade in and out with the backdrop's
        // cross-fade, so the last belt glass of Rush's Conveyor tier still rides out on moving slats and flicks the
        // bell as it goes, while the room turns into the Diner (QA-3 P2-2 / P2-4).
        let lookTarget: CGFloat = palette.venue == .conveyor ? 1 : 0
        if dt > 0 {
            let step = dt / GameScene.bellFade
            bellAlpha = lookTarget > bellAlpha ? min(lookTarget, bellAlpha + step) : max(lookTarget, bellAlpha - step)
        } else if !advanced {
            bellAlpha = lookTarget
        }

        updateCoaster(s, dt: dt)
        updateSlotCoaster(s, waitingID: waitingID, dt: dt)
        updateBelt(s, dt: dt)
        updateBeltQueue(s, lead: lead, dt: dt, advanced: advanced)
        updatePourZone(s, lead: lead, dt: dt, advanced: advanced)
        bell.alpha = bellAlpha
        bell.isHidden = bellAlpha < 0.01
        if bell.isHidden { bellRing.isHidden = true }
        fx.syncPuddles(s.puddles, counterY: cy, color: spillColor)
        if advanced { prewarmNextRushLook(s) }
    }

    /// The Conveyor props' (bell, belt slats) fade with a venue change (the backdrop's cross-fade is 0.8 s).
    static let bellFade: CGFloat = 0.8
    /// 0…1: how much of the Conveyor's props show (1 in the Conveyor, 0 elsewhere, between while the room changes).
    private var bellAlpha: CGFloat = 0

    // MARK: Conveyor (round 6, REVIEW-5 §2)

    /// Glasses ride a belt: Conveyor shifts (every order), and Rush's Conveyor tier (orders without patience).
    private var beltMode: Bool {
        guard palette.venue == .conveyor, let mode = lastMode else { return false }
        switch mode {
        case .shift: return shiftBeltSpeed != nil
        case .rush: return true
        case .daily, .practice: return false
        }
    }

    private func isBelt(_ g: GlassState) -> Bool {
        return beltMode && g.patienceTotal == nil && !g.isWaitingInSlot
    }

    /// Belt speed (pt/s): the shift's own, else what the riding glasses show.
    private var beltSpeed: CGFloat {
        if let v = shiftBeltSpeed { return v }
        return measuredBeltSpeed > 4 ? measuredBeltSpeed : 30
    }

    /// Finds the belt glass being served (the "lead") and keeps the pour-zone estimate: Core parks each belt glass
    /// `rimHalf + leadIn` left of where the stream crosses its rim (`GameSession.sendToStop`), so that landing x is
    /// where the glass stood when it started filling, plus those two.
    private func updateBeltEstimate(_ s: GameSnapshot, dt: CGFloat) -> GlassState? {
        guard beltMode else { return nil }
        var lead: GlassState?
        for g in s.glasses where isBelt(g) {
            if lead == nil && g.result == nil && (g.phase == .filling || g.phase == .arriving) { lead = g }
            if g.phase == .filling && fillStartX[g.id] == nil && lastPhase[g.id] == .arriving { fillStartX[g.id] = g.x }
            if dt > 0, g.phase == .filling || g.phase == .served, let v = glasses[g.id], abs(v.velocityX) > 4 {
                measuredBeltSpeed += (v.velocityX - measuredBeltSpeed) * min(1, dt * 4)
            }
        }
        if let g = lead, let x0 = fillStartX[g.id] {
            let leadIn = min(max(beltSpeed * 0.9, 10), CGFloat(CoreTuning.conveyorLeadIn))
            zoneX = x0 + g.shape.rimHalfWidth + leadIn
        }
        return lead
    }

    /// How much of a belt glass's pour window is left: 1 until its mouth reaches the stream, 0 once it has passed.
    private func beltWindow(_ g: GlassState) -> CGFloat? {
        guard isBelt(g), let zx = zoneX else { return nil }
        if g.phase == .arriving { return 1 }
        guard g.phase == .filling else { return nil }
        let r = max(1, g.shape.rimHalfWidth)
        return min(max((zx - g.x + r) / (2 * r), 0), 1)
    }

    /// The lit pour zone on the belt: fades in once the landing x is known, brightens while a mouth is under it.
    private func updatePourZone(_ s: GameSnapshot, lead: GlassState?, dt: CGFloat, advanced: Bool) {
        let show = beltMode && zoneX != nil && lead != nil && s.phase != .finished
        let target: CGFloat = show ? 1 : 0
        if dt > 0 {
            zoneAlpha += (target - zoneAlpha) * min(1, dt * 5)
        } else if !advanced {
            zoneAlpha = target
        }
        guard zoneAlpha > 0.01, let zx = zoneX else {
            pourZone.isHidden = true
            return
        }
        pourZone.position = CGPoint(x: zx, y: layout.counterY)
        var live = false
        if let g = lead, g.phase == .filling {
            let r = g.shape.rimHalfWidth
            live = g.x + r > zx && g.x - r < zx
        }
        let pulse: CGFloat = live ? 0.2 + 0.08 * CGFloat(sin(s.time * 12)) : 0
        pourZone.alpha = zoneAlpha * min(1, 0.72 + pulse)
        pourZone.isHidden = false
    }

    /// Index of the first order not yet on the counter (orders served + glasses still waiting for a verdict).
    private func upcomingBase(_ s: GameSnapshot) -> Int {
        var unserved = 0
        for g in s.glasses where g.result == nil && g.phase != .leaving { unserved += 1 }
        return s.ordersDone + unserved
    }

    /// The `offset`-th upcoming order (0 = next) that rides the belt: the shift's own list (complete, so it wins), else
    /// `upcomingOrders` (Rush: the App publishes what Core knows of the next glasses; the snapshot carries none). In
    /// Rush only the Conveyor tier's orders ride (Core gives them a belt and no patience; every other tier's glass has
    /// patience), so the queue ends at the tier's last belt glass instead of showing a Diner glass on the belt.
    private func upcomingOrder(base: Int, offset: Int) -> GlassOrder? {
        var order: GlassOrder?
        if !shiftOrders.isEmpty {
            let k = base + offset
            order = k >= 0 && k < shiftOrders.count ? shiftOrders[k] : nil
        } else if let given = upcomingOrders {
            order = offset >= 0 && offset < given.count ? given[offset] : nil
        }
        guard let o = order else { return nil }
        if case .rush? = lastMode, o.patience != nil { return nil }
        return o
    }

    /// Spacing between a belt glass and the one riding in behind it: where Core will park the next one when this one
    /// is served (rims + exit margin + lead-in), and never closer than their bodies allow.
    private func beltGap(_ a: GlassShape, _ b: GlassShape) -> CGFloat {
        let leadIn = min(max(beltSpeed * 0.9, 10), CGFloat(CoreTuning.conveyorLeadIn))
        let park = a.rimHalfWidth + b.rimHalfWidth + CGFloat(CoreTuning.conveyorExitMargin) + leadIn
        let bodies = CGFloat(NextGlassSlot.bodyHalfWidth(a) + NextGlassSlot.handleReach(a))
            + CGFloat(NextGlassSlot.bodyHalfWidth(b)) * GameScene.beltGhostScale + 14
        return max(park, bodies)
    }

    /// The next glasses ride in on the belt behind the lead (empty, slightly smaller and dimmer, prefills showing).
    /// When the lead is served, the nearest becomes the real next glass (Core slides it in to about the same spot) and
    /// its stand-in fades; a new one appears at the back.
    private func updateBeltQueue(_ s: GameSnapshot, lead: GlassState?, dt: CGFloat, advanced: Bool) {
        if !beltMode || lead == nil {
            for g in ghosts where !g.retiring { g.retire(at: s.time) }
        }
        var base = Int.max
        var joining = false
        if beltMode, let l = lead {
            base = upcomingBase(s)
            // New stand-ins join only once the lead has stopped sliding in.
            joining = l.phase == .filling
        }
        for g in ghosts where !g.retiring && g.key < base { g.retire(at: s.time) }
        // Join the queue at the back.
        if joining {
            var added = false
            for offset in 0..<GameScene.beltQueueLength {
                guard let order = upcomingOrder(base: base, offset: offset) else { break }
                let key = base + offset
                if ghosts.contains(where: { $0.key == key && !$0.retiring }) { continue }
                let shape = GlassCatalog.shape(order.glass)
                var anchorX = lead?.x ?? layout.visibleRect.minX
                var anchorShape = lead?.shape ?? shape
                for g in ghosts where !g.retiring && g.key < key {
                    anchorX = g.x
                    anchorShape = g.shape
                }
                let ghost = BeltGhost(key: key, order: order, shape: shape, x: anchorX - beltGap(anchorShape, shape),
                                      dark: palette.isDark)
                glassBackLayer.addChild(ghost.view.back)
                glassFrontLayer.addChild(ghost.view.front)
                ghost.view.back.zPosition = -1
                ghost.view.front.zPosition = -1
                ghosts.append(ghost)
                added = true
            }
            if added { ghosts.sort { $0.key < $1.key } }
        }

        // Ride the belt: move with it while it runs; the active ones keep their spacing behind the lead.
        var running = false
        for g in s.glasses where isBelt(g) && (g.phase == .filling || g.phase == .served) {
            if let v = glasses[g.id], abs(v.velocityX) > 4 { running = true; break }
        }
        let move = running ? beltSpeed * dt : 0
        var anchor: (x: CGFloat, shape: GlassShape)? = nil
        if let l = lead, l.phase == .filling { anchor = (l.x, l.shape) }
        let baseBand = defaultBand(s.mode)
        var i = 0
        while i < ghosts.count {
            let g = ghosts[i]
            g.x += move
            if !g.retiring {
                if let a = anchor {
                    let target = a.x - beltGap(a.shape, g.shape)
                    if dt > 0 { g.x += (target - g.x) * min(1, dt * 5) }
                }
                anchor = (g.x, g.shape)
            }
            var suppressed = g.fresh
            if g.retiring {
                let near = lead.map { abs($0.x - g.x) < 70 } ?? true
                suppressed = near || s.time - g.retiredAt > 0.5 || !beltMode
            }
            g.state.x = g.x
            var f = GlassFrame(counterY: layout.counterY, dt: dt, time: s.time, pouring: false, tail: nil,
                               advanced: advanced, reduceMotion: reduceMotion, band: baseBand, projected: nil,
                               safeX: 0...layout.size.width, keepOutTop: foldKeepOutTop)
            f.waitingScale = GameScene.beltGhostScale
            f.waitingDrop = 0
            f.waitingAlpha = GameScene.beltGhostAlpha
            f.suppressed = suppressed
            g.view.update(g.state, f)
            g.fresh = false
            if g.retiring && suppressed && g.view.drawnAlpha < 0.01 && s.time - g.retiredAt > 0.05 {
                g.view.remove()
                ghosts.remove(at: i)
                continue
            }
            i += 1
        }
    }

    /// The bell on the shelf: a little hop (bigger on Perfect), a ring at the knob and a glint.
    private func ringBell(judgement: Judgement) {
        guard !bell.isHidden else { return }
        bellRingCount += 1
        let rest = bellRest
        let knob = CGPoint(x: rest.x, y: rest.y + SceneArt.bellKnobHeight)
        bellRing.removeAllActions()
        bellRing.position = knob
        bellRing.setScale(0.4)
        bellRing.alpha = judgement.isHit ? 0.95 : 0.5
        bellRing.isHidden = false
        let grow = SKAction.scale(to: judgement == .perfect ? 1.8 : 1.4, duration: 0.45)
        grow.timingMode = .easeOut
        bellRing.run(SKAction.sequence([SKAction.group([grow, SKAction.fadeOut(withDuration: 0.45)]), SKAction.hide()]))
        if judgement.isHit { fx.ding(at: knob, big: judgement == .perfect) }
        guard !reduceMotion else { return }
        bell.removeAction(forKey: "flick")
        bell.position = rest
        bell.zRotation = 0
        let hop: CGFloat = judgement == .perfect ? 8 : (judgement.isHit ? 5 : 2)
        let up = SKAction.group([SKAction.moveBy(x: 0, y: hop, duration: 0.07), SKAction.rotate(toAngle: 0.1, duration: 0.07)])
        up.timingMode = .easeOut
        let down = SKAction.group([SKAction.move(to: rest, duration: 0.12), SKAction.rotate(toAngle: -0.06, duration: 0.12)])
        down.timingMode = .easeIn
        let settle = SKAction.rotate(toAngle: 0, duration: 0.12)
        settle.timingMode = .easeOut
        bell.run(SKAction.sequence([up, down, settle]), withKey: "flick")
    }

    // MARK: Sand repose (round 6, REVIEW-5 §4)

    /// A tiny puff of dust at the lip as the scoop reaches its angle of repose (re-arms once it eases back).
    private func watchRepose(_ s: GameSnapshot) {
        guard s.jug.liquid.id == .sand else {
            lastRepose = 0
            reposeArmed = true
            return
        }
        let rp = s.jug.reposeProgress
        if reposeArmed && rp >= 0.97 && lastRepose < 0.97 {
            reposeArmed = false
            reposePuffCount += 1
            fx.dustPuff(at: s.jug.lip, color: SceneLiquidLook.stream(s.jug.liquid).body)
        }
        if rp < 0.6 { reposeArmed = true }
        lastRepose = rp
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
        // Belt glasses have the pour zone instead (round 6: Rush's Conveyor tier mixes in glasses that stop).
        var onBelt = false
        for g in s.glasses where g.phase == .filling {
            onBelt = isBelt(g)
            break
        }
        if onBelt {
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
        // No slot on a belt (Core never queues a waiting glass while a belt glass is on the counter).
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
        // `bellAlpha`: the Conveyor look's share (fades with a venue change, see `render`).
        guard bellAlpha > 0.01 else {
            beltSlats.isHidden = true
            return
        }
        beltSlats.isHidden = false
        beltSlats.alpha = bellAlpha
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
                // Conveyor: the bell flicks as a belt glass rides off (`render`, on `.served` → `.leaving`), the same
                // moment and rule as Feel's ring (QA-3 P2-4).
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
        shiftBeltSpeed = nil
        shiftOrders = []
        switch mode {
        case let .shift(id):
            let level = LevelCatalog.level(id)
            v = level?.venue
            shiftBeltSpeed = level?.conveyorSpeed.map { CGFloat($0 * CoreTuning.beltScale) }
            shiftOrders = level?.orders ?? []
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

    /// Round 6: the snapshot's venue first (Rush travels per tier; shifts report their own), then the App's `venue`,
    /// then the shift's, then the Lemonade Stand.
    private var effectiveVenue: VenueID { snapshotVenue ?? venue ?? autoVenue ?? .lemonadeStand }
    private var effectiveRush: Bool { rushLook || autoRush }
    private var effectiveDaily: Int? { dailyNumber ?? autoDaily }

    /// `animated` (a venue change mid-run): the old backdrop and vessel cross-fade into the new ones.
    private func paletteChanged(animated: Bool = false) {
        var p = ScenePalette.forVenue(effectiveVenue)
        if effectiveRush { p = p.duskified() }
        if let v = vesselOverride { p.vessel = ScenePalette.forVenue(v).vessel }
        let oldVessel = palette.vessel
        let oldTexture = backdrop.texture
        let changedVenue = p.venue != palette.venue
        let vesselChanged = oldVessel.form != p.vessel.form || oldVessel.decal != p.vessel.decal
        if animated && changedVenue && vesselChanged && !jug.root.isHidden, let copy = jug.root.copy() as? SKNode {
            // The old vessel fades out where it stands while the new one fades in.
            copy.removeAllActions()
            copy.position = jugLayer.position
            copy.zPosition = jugLayer.zPosition - 0.4
            content.addChild(copy)
            copy.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.45), SKAction.removeFromParent()]))
            jug.root.removeAction(forKey: "vesselFade")
            jug.root.alpha = 0
            jug.root.run(SKAction.fadeIn(withDuration: 0.45), withKey: "vesselFade")
        }
        palette = p
        if !animated {
            // A look set from outside a run (the App's venue, a reset): the bell is there or not at once.
            bellAlpha = p.venue == .conveyor ? 1 : 0
            bell.alpha = bellAlpha
            bell.isHidden = bellAlpha < 0.01
        }
        applyPaletteToNodes()
        if backdropScale > 0 { buildBackdrop(scale: backdropScale) }
        if animated && changedVenue, let old = oldTexture, old !== backdrop.texture {
            lookCrossFadeCount += 1
            backdropFade.removeAllActions()
            backdropFade.texture = old
            backdropFade.size = layout.size
            backdropFade.alpha = 1
            backdropFade.isHidden = false
            let fade = SKAction.fadeOut(withDuration: 0.8)
            fade.timingMode = .easeInEaseOut
            backdropFade.run(SKAction.sequence([fade, SKAction.hide()]))
        }
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
        let tex = backdropTexture(venue: effectiveVenue, palette: palette, scale: scale)
        backdropScale = scale
        backdrop.texture = tex
        backdrop.color = .white
        backdrop.colorBlendFactor = 0
        backdrop.size = layout.size
    }

    // MARK: Backdrop cache (round 7, QA-3 P2-5)
    //
    // One look per venue (+ dusk/day + Daily number + scale), least recently used dropped first. Rush travels through
    // a venue per tier, so a Rush tier change used to repaint a full-canvas texture (~23 MB at 3×) on the main thread
    // at the very moment the next glass slides in. Now Rush looks are painted at 2× (~10 MB; soft painted art, and the
    // glasses, jug and stream are drawn live at full resolution over it), the next tier's look is painted ahead, at a
    // quiet moment late in the current tier (`prewarmNextRushLook`), and the cache keeps three Rush looks (previous,
    // current, next): the tier change itself is a cache hit. Outside Rush it keeps two (QA-1 P2-13).

    /// Rush backdrops are painted at most at this scale.
    static let rushBackdropScale: CGFloat = 2
    /// Paint the next Rush tier's look once this many glasses of the current tier are done and nothing is pouring…
    static let prewarmFromGlass = CoreTuning.rushTierEvery - 4
    /// …or at this many at any moment between glasses, even with the jug tipped (round 9, QA-4 P2-3)…
    static let prewarmForcedFromGlass = CoreTuning.rushTierEvery - 2
    /// …or, on the tier's last glass, regardless (the cache-miss at the change stays the last fallback).
    static let prewarmLastFromGlass = CoreTuning.rushTierEvery - 1
    /// Tests: full-canvas backdrops painted since the scene was made.
    private(set) var backdropRenderCount = 0
    /// Tests: how many looks the cache holds.
    var cachedLookCount: Int { backdropCache.count }
    /// Least recently used first.
    private var backdropOrder: [String] = []
    /// The Rush tier whose successor's look has been painted (0 = none yet).
    private var prewarmedTier = 0

    private var backdropCacheCapacity: Int { effectiveRush ? 3 : 2 }

    private func lookKey(_ venue: VenueID, rush: Bool, daily: Int?, scale: CGFloat) -> String {
        let dailyKey = daily.map { String($0) } ?? "-"
        return "\(venue.rawValue)-\(rush ? "dusk" : "day")-\(dailyKey)@\(Int(scale * 10))"
    }

    /// The look for `venue` in `palette` (cached), painted at `scale` (capped for Rush).
    private func backdropTexture(venue: VenueID, palette pal: ScenePalette, scale: CGFloat) -> SKTexture {
        let rush = effectiveRush
        let s = rush ? min(scale, GameScene.rushBackdropScale) : scale
        let key = lookKey(venue, rush: rush, daily: effectiveDaily, scale: s)
        if let t = backdropCache[key] {
            if backdropOrder.last != key, let i = backdropOrder.firstIndex(of: key) {
                backdropOrder.remove(at: i)
                backdropOrder.append(key)
            }
            return t
        }
        let tex = SceneArt.backdrop(layout: layout, palette: pal, dailyNumber: effectiveDaily, scale: s)
        backdropRenderCount += 1
        while backdropOrder.count >= backdropCacheCapacity && !backdropOrder.isEmpty {
            let oldest = backdropOrder.removeFirst()
            backdropCache[oldest] = nil
        }
        backdropCache[key] = tex
        backdropOrder.append(key)
        return tex
    }

    /// Rush: paint the next tier's look ahead of the change (once per tier), so the change is a cache hit.
    /// Round 9 (QA-4 P2-3): the paint (~10 MB, main thread) never lands while the stream fills a glass. From
    /// `prewarmFromGlass` it waits for the jug to rest; from `prewarmForcedFromGlass` for any moment between glasses
    /// (no glass filling, the stamp up, the next one sliding in), even with the jug still tipped; only on the tier's
    /// last glass, if the player never once stopped filling, does it paint regardless.
    private func prewarmNextRushLook(_ s: GameSnapshot) {
        guard case .rush = s.mode, s.rushTier >= 1, s.rushTier != prewarmedTier, backdropScale > 0,
              s.phase == .playing else { return }
        let into = s.ordersDone - (s.rushTier - 1) * CoreTuning.rushTierEvery
        guard into >= GameScene.prewarmFromGlass else { return }
        let pouring = !s.stream.isEmpty || s.jug.flow >= 0.01
        var filling = false
        if pouring {
            for g in s.glasses where g.phase == .filling {
                filling = true
                break
            }
        }
        let ready: Bool
        if into >= GameScene.prewarmLastFromGlass {
            ready = true
        } else if into >= GameScene.prewarmForcedFromGlass {
            ready = !filling
        } else {
            ready = !pouring
        }
        guard ready else { return }
        prewarmedTier = s.rushTier
        let next = Rules.rushVenue(tier: s.rushTier + 1)
        var p = ScenePalette.forVenue(next)
        if effectiveRush { p = p.duskified() }
        _ = backdropTexture(venue: next, palette: p, scale: backdropScale)
    }
}

/// Round 6 (REVIEW-5 §2): a stand-in for an order still to come, riding the Conveyor's belt behind the glass being
/// poured — an empty glass (its prefill showing) in the waiting look. Purely cosmetic; Core never sees it.
@MainActor
private final class BeltGhost {
    let key: Int
    let shape: GlassShape
    let view: SceneGlass
    var state: GlassState
    var x: CGFloat
    var retiring = false
    var retiredAt: Double = 0
    /// True until its first draw (it fades in from nothing).
    var fresh = true

    init(key: Int, order: GlassOrder, shape: GlassShape, x: CGFloat, dark: Bool) {
        self.key = key
        self.shape = shape
        self.x = x
        let id = -1000 - key
        view = SceneGlass(id: id, darkBackdrop: dark)
        let interior = shape.interiorHeight
        let prefill = CGFloat(min(max(order.prefill, 0), 0.95))
        // `.arriving` with the line hidden: SceneGlass draws it in the waiting look (scale/opacity from GlassFrame).
        state = GlassState(id: id, shape: shape, liquid: LiquidCatalog.liquid(order.liquid), x: x, phase: .arriving,
                           liquidHeight: interior * prefill, foamHeight: 0, lineHeight: interior * CGFloat(order.line),
                           lineOpacity: 0, inPerfectBand: false, overflowing: false, patienceLeft: nil,
                           patienceTotal: nil, result: nil)
    }

    func retire(at time: Double) {
        retiring = true
        retiredAt = time
    }
}
