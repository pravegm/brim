import SpriteKit
import UIKit

/// The pouring vessel on the raised half, in the app icon's art language: a thick ink outline, glossy specular
/// streaks, a belly decal, and one SIGNATURE VESSEL per venue (REVIEW-2 P1-9), all drawn as different exteriors around
/// Core's one interior outline (`JugGeometry`, physics unchanged):
///   pitcher    clear glass, ceramic rim + foot ring, a domed lid with a knob, loop handle   (Lemonade, Conveyor)
///   dispenser  clear glass, red handle, two chrome hoops, a flat chrome lid with a red button (Soda Fountain)
///   shakeTin   opaque brushed steel with a sight window, rolled lip, no handle                (Milkshake Diner)
///   flask      thick glass, a cork stopper and twine, no handle                              (Potion Shop)
///   scoop      copper measuring scoop: open top, graduated sight glass, wooden stick handle    (Sand Bar)
///
/// Core's outline is closed on top: `JugGeometry.lidIndices` (15…18) is the lid, so every lidded form draws a real lid
/// there (no open white oval, REVIEW-2 P1-3/item 4). Static parts are built once per shape/style in jug-local space
/// and rotated as a group; the liquid is redrawn every frame from the snapshot's world polygon, and while pouring a
/// sheet of liquid fills the spout channel from the neck right to the lip (P1-5), so the stream is visibly fed.
@MainActor
final class SceneJug {
    let root: SKNode

    private let shadow: SKShapeNode
    private let backFrame: SKNode
    private let frontFrame: SKNode

    // back (behind the liquid)
    private let handleOutline: SKShapeNode
    private let handleBody: SKShapeNode
    private let handleShine: SKShapeNode
    private let interior: SKShapeNode

    // liquid (world space)
    private let liquid: SKShapeNode
    private let surface: SKShapeNode
    private let spoutSheet: SKShapeNode

    // front (in front of the liquid)
    private let footBand: SKShapeNode
    private let wallBody: SKShapeNode
    private let wallOuter: SKShapeNode
    private let wallInner: SKShapeNode
    private let skin: SKShapeNode
    private let windowFrame: SKShapeNode
    private let windowGlare: SKShapeNode
    private let ticks: SKShapeNode
    private let hoops: SKShapeNode
    private let rimBand: SKShapeNode
    private let rimBandShine: SKShapeNode
    private let opening: SKShapeNode
    private let lid: SKShapeNode
    private let lidShine: SKShapeNode
    private let knob: SKShapeNode
    private let knobShine: SKShapeNode
    private let twine: SKShapeNode
    private let shine: SKShapeNode
    private let shineDot: SKShapeNode
    private let metalLines: SKShapeNode
    private let decal: SKSpriteNode
    private let lipGlint: SKShapeNode
    /// Dry jug (ROUND-5 decision 3): beads of residue clinging to the inner walls (jug-local, behind the front glass)
    /// and a last drop hanging from the lip that swells and falls now and then (world space).
    private let residue: SKShapeNode
    private let lastDrop: SKShapeNode
    /// Sand Bar (round 6, REVIEW-5 §4): grains creeping over the lip and trickling down as the scoop nears its angle
    /// of repose (`JugState.reposeProgress` 0.7 → 1). Cosmetic: no volume. World space.
    /// Round 9 (REVIEW-7 P1-1, frame 30): a pool of outlined grain sprites (2.2–3 pt, darker than the sand, so they
    /// read against a sand-coloured wall), made once and only moved per frame.
    private let trickle: SKNode
    private var grains: [SKSpriteNode] = []
    private var grainTint: LiquidID?
    /// How many trickle grains are drawn this frame (tests).
    private(set) var trickleGrains = 0
    /// The largest trickle grain's radius this frame (world pt; 0 when none). Tests.
    private(set) var trickleGrainRadius: CGFloat = 0
    /// Repose progress where the trickle starts.
    static let trickleStart: Double = 0.7
    /// Pool size: at most `2 + 4` grains on the lip and `2 + 9` falling.
    static let maxSittingGrains = 6
    static let maxFallingGrains = 11
    /// Round 9 (REVIEW-7 P1-1): over the last half of the telegraph the scoop shivers, up to this much (radians,
    /// ±1.2°) at `shiverHz`, growing as the slide nears. Never under Reduce Motion.
    static let shiverMax: CGFloat = 1.2 * .pi / 180
    static let shiverHz: Double = 14
    /// The shiver's current angle (radians, added to the tip; 0 = still). Tests.
    private(set) var shiverAngle: CGFloat = 0
    /// Set by the scene (Reduce Motion): no shiver.
    var reduceMotion = false
    /// Round 9 (REVIEW-7 P1-1): the scoop's sight-glass slot pulses amber-red as the slide nears (an overlay on its
    /// frame, so the colour is never re-made per frame).
    private let windowWarn: SKShapeNode
    static let warnColor = SceneColor.hex(0xE8553A)
    /// The sight-slot warning's strength this frame (0 = none). Tests.
    var sightWarning: CGFloat { windowWarn.isHidden ? 0 : windowWarn.alpha }

    /// 0 = has liquid, 1 = dry (eased). See `dryFill`.
    private(set) var dryAmount: CGFloat = 0
    private var dryKnown = false
    /// True once the jug reads as empty: under `dryFill` and not pouring.
    var isDry: Bool { dryAmount > 0.5 }
    /// At or below this fill (and with no outflow) the jug is drawn empty. Core stops the stream at 2.5 %.
    static let dryFill: Double = 0.03
    /// The hanging drop's cycle (s): swell, fall, gone.
    static let dripPeriod: Double = 1.6

    private var localOutline: [CGPoint] = []
    private var localDrawnBounds: CGRect = .null

    /// World bounds of everything drawn (body, lid + knob, handle) at the current pose. `.null` before a frame.
    var worldBounds: CGRect {
        guard !root.isHidden, !localDrawnBounds.isNull else { return .null }
        let r = localDrawnBounds
        let c = cos(frontFrame.zRotation), s = sin(frontFrame.zRotation)
        let o = frontFrame.position
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                  CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)] {
            let wx = o.x + p.x * c - p.y * s, wy = o.y + p.x * s + p.y * c
            minX = min(minX, wx); maxX = max(maxX, wx)
            minY = min(minY, wy); maxY = max(maxY, wy)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    /// Angle of the outline's first edge in the cached local frame (lets us follow outlines Core rotates further,
    /// e.g. the sand pile, without rebuilding every frame).
    private var baseEdgeAngle: CGFloat = 0
    private var liquidID: LiquidID?
    private var styleKey = ""
    private var style: VesselStyle
    private var openingFull: Bool?
    private var sheetFloor: [CGPoint] = []
    private var sheetTop: [CGPoint] = []
    private var sheetRoof: [CGPoint] = []
    private let wall: CGFloat = 9

    static let wood = SceneColor.hex(0xB98552)
    static let cork = SceneColor.hex(0xCFA06A)
    static let copperInside = SceneColor.hex(0x7A4524)

    init() {
        style = ScenePalette.forVenue(nil).vessel
        root = SKNode()
        shadow = SKShapeNode()
        backFrame = SKNode()
        frontFrame = SKNode()
        handleOutline = SKShapeNode()
        handleBody = SKShapeNode()
        handleShine = SKShapeNode()
        interior = SKShapeNode()
        liquid = SKShapeNode()
        surface = SKShapeNode()
        spoutSheet = SKShapeNode()
        footBand = SKShapeNode()
        wallBody = SKShapeNode()
        wallOuter = SKShapeNode()
        wallInner = SKShapeNode()
        skin = SKShapeNode()
        windowFrame = SKShapeNode()
        windowGlare = SKShapeNode()
        ticks = SKShapeNode()
        hoops = SKShapeNode()
        rimBand = SKShapeNode()
        rimBandShine = SKShapeNode()
        opening = SKShapeNode()
        lid = SKShapeNode()
        lidShine = SKShapeNode()
        knob = SKShapeNode()
        knobShine = SKShapeNode()
        twine = SKShapeNode()
        shine = SKShapeNode()
        shineDot = SKShapeNode()
        metalLines = SKShapeNode()
        decal = SKSpriteNode()
        lipGlint = SKShapeNode()
        residue = SKShapeNode()
        lastDrop = SKShapeNode()
        trickle = SKNode()
        windowWarn = SKShapeNode()

        let ink = SceneColor.ink
        shadow.fillColor = ink.withAlphaComponent(0.10)
        shadow.strokeColor = .clear
        shadow.zPosition = 0

        backFrame.zPosition = 1
        spoutSheet.zPosition = 1.95       // under the liquid polygon: where Core's liquid already fills the channel, it wins
        liquid.zPosition = 2
        surface.zPosition = 2.5
        frontFrame.zPosition = 3

        handleOutline.strokeColor = ink.withAlphaComponent(0.8)
        handleOutline.lineCap = .round
        handleOutline.fillColor = .clear
        handleOutline.zPosition = 0
        handleBody.lineCap = .round
        handleBody.fillColor = .clear
        handleBody.zPosition = 0.1
        handleShine.strokeColor = UIColor(white: 1, alpha: 0.6)
        handleShine.lineWidth = 3.5
        handleShine.lineCap = .round
        handleShine.fillColor = .clear
        handleShine.zPosition = 0.2
        interior.strokeColor = .clear
        interior.zPosition = 0.3
        residue.strokeColor = UIColor(white: 1, alpha: 0.7)
        residue.lineWidth = 1
        residue.zPosition = 0.31
        residue.alpha = 0
        residue.isHidden = true
        lastDrop.lineWidth = 1.4
        lastDrop.zPosition = 3.5
        lastDrop.isHidden = true
        trickle.zPosition = 3.6
        trickle.isHidden = true
        for _ in 0..<(SceneJug.maxSittingGrains + SceneJug.maxFallingGrains) {
            let g = SKSpriteNode()
            g.isHidden = true
            grains.append(g)
            trickle.addChild(g)
        }
        windowWarn.fillColor = .clear
        windowWarn.strokeColor = SceneJug.warnColor
        windowWarn.lineWidth = 3.5
        windowWarn.glowWidth = 0
        windowWarn.zPosition = 0.134
        windowWarn.isHidden = true
        backFrame.addChild(handleOutline)
        backFrame.addChild(handleBody)
        backFrame.addChild(handleShine)
        backFrame.addChild(interior)
        backFrame.addChild(residue)

        liquid.fillColor = .white
        liquid.strokeColor = .clear
        surface.fillColor = .clear
        surface.lineWidth = 3
        surface.lineCap = .round
        spoutSheet.strokeColor = .clear
        spoutSheet.isHidden = true

        footBand.fillColor = .clear
        footBand.lineCap = .round
        footBand.lineJoin = .round
        footBand.zPosition = 0.17
        wallBody.lineWidth = wall
        wallBody.lineCap = .round
        wallBody.lineJoin = .round
        wallBody.fillColor = .clear
        wallBody.zPosition = 0
        wallInner.strokeColor = UIColor(white: 1, alpha: 0.75)
        wallInner.lineWidth = 1.5
        wallInner.lineJoin = .round
        wallInner.fillColor = .clear
        wallInner.zPosition = 0.1
        skin.lineWidth = 0
        skin.strokeColor = .clear
        skin.zPosition = 0.12
        windowFrame.fillColor = .clear
        windowFrame.lineWidth = 3
        windowFrame.zPosition = 0.13
        windowGlare.fillColor = .clear
        windowGlare.strokeColor = UIColor(white: 1, alpha: 0.5)
        windowGlare.lineWidth = 3
        windowGlare.lineCap = .round
        windowGlare.zPosition = 0.135
        ticks.fillColor = .clear
        ticks.lineWidth = 1.8
        ticks.lineCap = .round
        ticks.zPosition = 0.14
        wallOuter.strokeColor = ink.withAlphaComponent(0.78)
        wallOuter.lineWidth = 3
        wallOuter.lineCap = .round
        wallOuter.lineJoin = .round
        wallOuter.fillColor = .clear
        wallOuter.zPosition = 0.15
        hoops.lineWidth = 1.2
        hoops.strokeColor = ink.withAlphaComponent(0.55)
        hoops.zPosition = 0.18
        rimBand.lineWidth = wall + 3
        rimBand.lineCap = .round
        rimBand.lineJoin = .round
        rimBand.fillColor = .clear
        rimBand.zPosition = 0.2
        rimBandShine.strokeColor = UIColor(white: 1, alpha: 0.45)
        rimBandShine.lineWidth = 2.5
        rimBandShine.lineCap = .round
        rimBandShine.fillColor = .clear
        rimBandShine.zPosition = 0.25
        opening.strokeColor = ink.withAlphaComponent(0.7)
        opening.lineWidth = 2.2
        opening.zPosition = 0.3
        lid.strokeColor = ink.withAlphaComponent(0.82)
        lid.lineWidth = 2.6
        lid.lineJoin = .round
        lid.zPosition = 0.32
        lidShine.fillColor = .clear
        lidShine.strokeColor = UIColor(white: 1, alpha: 0.6)
        lidShine.lineWidth = 3
        lidShine.lineCap = .round
        lidShine.zPosition = 0.33
        knob.strokeColor = ink.withAlphaComponent(0.82)
        knob.lineWidth = 2.2
        knob.zPosition = 0.34
        knobShine.fillColor = UIColor(white: 1, alpha: 0.75)
        knobShine.strokeColor = .clear
        knobShine.zPosition = 0.35
        twine.fillColor = .clear
        twine.strokeColor = SceneColor.hex(0xD8B98A)
        twine.lineWidth = 3
        twine.lineCap = .round
        twine.zPosition = 0.36
        shine.strokeColor = UIColor(white: 1, alpha: 0.78)
        shine.lineWidth = 7
        shine.lineCap = .round
        shine.fillColor = .clear
        shine.zPosition = 0.4
        shineDot.strokeColor = UIColor(white: 1, alpha: 0.7)
        shineDot.lineWidth = 5
        shineDot.lineCap = .round
        shineDot.fillColor = .clear
        shineDot.zPosition = 0.4
        metalLines.strokeColor = UIColor(white: 1, alpha: 0.45)
        metalLines.lineWidth = 1.2
        metalLines.lineCap = .round
        metalLines.fillColor = .clear
        metalLines.zPosition = 0.38
        decal.zPosition = 0.45
        lipGlint.fillColor = UIColor(white: 1, alpha: 0.95)
        lipGlint.strokeColor = .clear
        lipGlint.zPosition = 0.5
        lipGlint.path = CGPath(ellipseIn: CGRect(x: -2.6, y: -2.6, width: 5.2, height: 5.2), transform: nil)
        for n in [wallBody, wallInner, skin, windowFrame, windowWarn, windowGlare, ticks, wallOuter, footBand, hoops,
                  rimBand, rimBandShine, opening, lid, lidShine, knob, knobShine, twine, metalLines, shine, shineDot] {
            frontFrame.addChild(n)
        }
        frontFrame.addChild(decal)
        frontFrame.addChild(lipGlint)

        root.addChild(shadow)
        root.addChild(backFrame)
        root.addChild(spoutSheet)
        root.addChild(liquid)
        root.addChild(surface)
        root.addChild(frontFrame)
        root.addChild(lastDrop)
        root.addChild(trickle)
        applyStyleColors()
    }

    /// Venue dressing. Cheap to call repeatedly; rebuilds only when it changes.
    func setStyle(_ s: VesselStyle) {
        let key = "\(s.form.rawValue)-\(s.decal.rawValue)-\(s.accent.hashValue)-\(s.metallic)-\(s.glassTint.hashValue)"
        if key == styleKey { return }
        styleKey = key
        style = s
        applyStyleColors()
        localOutline = []          // force a rebuild (lid, handle, decal, metal lines)
    }

    private var hasSkin: Bool { style.form == .shakeTin || style.form == .scoop }

    /// The dressing in use (tests, and `GameScene.vesselOverride`).
    var form: VesselForm { style.form }
    var decalKind: VesselDecal { style.decal }
    /// The belly decal's rotation on screen (radians; nil when none is drawn). Tests.
    var decalWorldRotation: CGFloat? { decal.isHidden ? nil : frontFrame.zRotation + decal.zRotation }
    /// The jug body's rotation on screen (radians). Tests.
    var bodyWorldRotation: CGFloat { frontFrame.zRotation }
    /// The decals' slight jaunty tilt (radians); the Conveyor's badge keeps it on screen whatever the tip.
    static let decalTilt: CGFloat = -0.08
    /// Whether the static parts have been built for the current dressing (false until the next frame after a change).
    var isBuilt: Bool { !localOutline.isEmpty }
    /// Whether a lid / a handle is drawn (tests: the scoop is open; the tin and flask have no handle).
    var drawsLid: Bool { !lid.isHidden }
    var drawsHandle: Bool { !handleOutline.isHidden }
    var drawsSkin: Bool { !skin.isHidden }

    private func applyStyleColors() {
        let ink = SceneColor.ink
        interior.fillColor = style.glassTint
        wallBody.strokeColor = style.wall
        rimBand.strokeColor = style.accent
        footBand.strokeColor = style.accent
        metalLines.isHidden = !style.metallic
        handleBody.strokeColor = style.form == .scoop ? SceneJug.wood : style.accent
        windowFrame.strokeColor = SceneColor.darker(style.accent, 0.35)
        ticks.strokeColor = ink.withAlphaComponent(0.55)
        ticks.fillColor = .clear
        switch style.form {
        case .shakeTin:
            skin.fillTexture = SceneArt.sheenTexture(key: "jug-steel", base: SceneColor.hex(0xBCC7D0))
            skin.fillColor = .white
        case .scoop:
            skin.fillTexture = SceneArt.sheenTexture(key: "jug-copper", base: SceneColor.hex(0xD08A55))
            skin.fillColor = .white
        default:
            skin.fillTexture = nil
            skin.fillColor = .clear
        }
        switch style.form {
        case .dispenser, .shakeTin:
            lid.fillTexture = SceneArt.sheenTexture(key: "jug-chrome", base: SceneColor.chrome)
            lid.fillColor = .white
        case .flask:
            lid.fillTexture = nil
            lid.fillColor = SceneJug.cork
        default:
            lid.fillTexture = nil
            lid.fillColor = style.accent
        }
        hoops.fillTexture = SceneArt.sheenTexture(key: "jug-chrome", base: SceneColor.chrome)
        hoops.fillColor = .white
        knob.fillColor = style.form == .dispenser ? SceneColor.hex(0xE8505B) : style.accentDark
        // The flask is thicker glass; everything else uses the standard wall.
        wallBody.lineWidth = style.form == .flask ? wall + 4 : wall
        openingFull = nil
    }

    /// `time`: the session clock (the dry jug's last drop runs on it); `dt`: simulation step (0 = paused / first draw).
    func update(_ j: JugState, streamWidth: CGFloat, time: Double = 0, dt: CGFloat = 0) {
        guard j.outline.count >= 3 else {
            root.isHidden = true
            return
        }
        root.isHidden = false
        // Rotation: follow the outline itself (Core may rotate it beyond `angle`, e.g. sand).
        let o0 = j.outline[0], o1 = j.outline[1]
        let worldEdge = atan2(o1.y - o0.y, o1.x - o0.x)
        var rad = CGFloat(j.angle) * .pi / 180
        if !localOutline.isEmpty { rad = baseEdgeAngle - worldEdge }
        var local: [CGPoint] = []
        local.reserveCapacity(j.outline.count)
        for p in j.outline { local.append(ScenePaths.toLocal(p, pivot: j.pivot, radians: rad)) }
        if needsRebuild(local) {
            rad = CGFloat(j.angle) * .pi / 180
            local.removeAll(keepingCapacity: true)
            for p in j.outline { local.append(ScenePaths.toLocal(p, pivot: j.pivot, radians: rad)) }
            let lipLocal0 = ScenePaths.toLocal(j.lip, pivot: j.pivot, radians: rad)
            rebuild(local, lip: lipLocal0)
            if local.count >= 2 {
                baseEdgeAngle = atan2(local[1].y - local[0].y, local[1].x - local[0].x)
            }
        }
        let lipLocal = ScenePaths.toLocal(j.lip, pivot: j.pivot, radians: rad)

        // Round 9 (REVIEW-7 P1-1): the sand-slide telegraph's strength (nil = none): grains, shiver, sight-slot pulse.
        let tele = telegraphStrength(j)
        shiverAngle = 0
        if let u = tele, u > 0.5, !reduceMotion {
            // On the session clock, so a paused frame holds still. The liquid polygon is Core's and stays put: the
            // sand seems to sit still while the copper trembles around it.
            let k = min(1, (u - 0.5) / 0.5)
            shiverAngle = SceneJug.shiverMax * k * CGFloat(sin(2 * Double.pi * SceneJug.shiverHz * time))
        }
        let tip = -rad - shiverAngle
        backFrame.position = j.pivot
        backFrame.zRotation = tip
        frontFrame.position = j.pivot
        frontFrame.zRotation = tip
        shadow.position = CGPoint(x: j.pivot.x + 8, y: j.pivot.y - 10)
        shadow.zRotation = tip
        // Round 9 (REVIEW-7 P2-8, N11): the Conveyor's chevron badge stays level as the jug tips; turning with it, its
        // two chevrons in a ring read as clock hands.
        if style.decal == .ticket && !decal.isHidden { decal.zRotation = SceneJug.decalTilt - tip }
        lipGlint.position = CGPoint(x: lipLocal.x, y: lipLocal.y + 1)
        lipGlint.alpha = CGFloat(min(1, 0.4 + j.flow * 2))

        // Liquid (world polygon from Core, already level).
        if liquidID != j.liquid.id {
            liquidID = j.liquid.id
            liquid.fillTexture = SceneArt.liquidTexture(j.liquid)
            liquid.fillColor = .white
            let g = SceneLiquidLook.gradient(j.liquid)
            surface.strokeColor = SceneColor.lighter(g.top, 0.6)
            let look = SceneLiquidLook.stream(j.liquid)
            spoutSheet.fillColor = look.body
            residue.fillColor = look.body.withAlphaComponent(0.75)
            lastDrop.fillColor = look.body
            lastDrop.strokeColor = look.edge
            openingFull = nil
        }
        updateDry(j, time: time, dt: dt)
        updateTrickle(j, u: tele, time: time)
        updateSightWarning(u: tele, time: time)
        if style.form == .scoop {
            // Open top: sand shows in the mouth once the scoop is well filled.
            let full = j.fill > 0.55
            if full != openingFull {
                openingFull = full
                opening.fillColor = full ? SceneLiquidLook.gradient(j.liquid).top : SceneJug.copperInside
            }
        }
        if j.liquidPolygon.count >= 3 && j.fill > 0.0005 {
            liquid.isHidden = false
            // Dry: what's left is a thin residue, not "a bit more to pour".
            liquid.alpha = max(0.9, CGFloat(j.liquid.opacity)) * (1 - 0.6 * dryAmount)
            liquid.path = ScenePaths.polygon(j.liquidPolygon)
            var maxY = -CGFloat.greatestFiniteMagnitude
            for p in j.liquidPolygon { maxY = max(maxY, p.y) }
            var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
            for p in j.liquidPolygon where p.y >= maxY - 0.75 {
                minX = min(minX, p.x)
                maxX = max(maxX, p.x)
            }
            if maxX - minX > 6 && dryAmount < 0.5 {
                let line = CGMutablePath()
                line.move(to: CGPoint(x: minX + 3, y: maxY - 1.2))
                line.addLine(to: CGPoint(x: maxX - 3, y: maxY - 1.2))
                surface.path = line
                surface.isHidden = false
            } else {
                surface.isHidden = true
            }
            updateSpoutSheet(j, streamWidth: streamWidth)
        } else {
            liquid.isHidden = true
            surface.isHidden = true
            spoutSheet.isHidden = true
        }
    }

    // MARK: Dry jug

    /// ROUND-5 decision 3: when the jug runs dry mid-glass Core stops the stream and the refill waits for the next
    /// glass, so the jug must READ empty: the leftover sliver fades to a residue, beads cling to the inner walls, the
    /// surface line goes, and while it is tipped a last drop swells at the lip and falls every `dripPeriod`.
    private func updateDry(_ j: JugState, time: Double, dt: CGFloat) {
        let dry = j.fill < SceneJug.dryFill && j.flow < 0.02
        let target: CGFloat = dry ? 1 : 0
        if !dryKnown || (!dry && j.fill > 0.1) {
            // First draw, or a fresh jug arrived (swap / refill): no fade.
            dryKnown = true
            dryAmount = target
        } else if dt > 0 {
            let step = dt * (dry ? 3.5 : 6)
            dryAmount = target > dryAmount ? min(target, dryAmount + step) : max(target, dryAmount - step)
        }
        residue.isHidden = dryAmount < 0.01 || residue.path == nil
        residue.alpha = dryAmount

        // The last drop: only while the spout points down (tipped), on the session clock (still when paused). Sand
        // doesn't drip.
        guard dryAmount > 0.01, j.angle > 25, j.liquid.id != .sand else {
            lastDrop.isHidden = true
            return
        }
        let period = SceneJug.dripPeriod
        let u = CGFloat((time.truncatingRemainder(dividingBy: period) + period).truncatingRemainder(dividingBy: period)
            / period)
        var r: CGFloat
        var fall: CGFloat = 0
        var a: CGFloat = 1
        if u < 0.72 {
            r = 1.6 + 2.2 * (u / 0.72)                       // swelling on the lip
        } else {
            let k = (u - 0.72) / 0.28                        // let go: falls and fades
            r = 3.8 * (1 - 0.25 * k)
            fall = 46 * k * k
            a = 1 - k
        }
        r = max(1.2, r)
        let p = CGMutablePath()
        let cx = j.lip.x, top = j.lip.y - 1 - fall
        // A teardrop: a round bottom pulled into a point toward the lip.
        p.move(to: CGPoint(x: cx, y: top + (fall > 0 ? r * 0.6 : 1.5)))
        p.addQuadCurve(to: CGPoint(x: cx + r, y: top - r * 1.4), control: CGPoint(x: cx + r * 0.9, y: top - r * 0.2))
        p.addArc(center: CGPoint(x: cx, y: top - r * 1.4), radius: r, startAngle: 0, endAngle: .pi, clockwise: true)
        p.addQuadCurve(to: CGPoint(x: cx, y: top + (fall > 0 ? r * 0.6 : 1.5)),
                       control: CGPoint(x: cx - r * 0.9, y: top - r * 0.2))
        p.closeSubpath()
        lastDrop.path = p
        lastDrop.isHidden = false
        lastDrop.alpha = a * dryAmount
    }

    // MARK: Sand trickle

    /// 0…1 over the telegraph (`reposeProgress` `trickleStart` → 1) while sand sits tipped in the jug and nothing
    /// flows; nil otherwise.
    private func telegraphStrength(_ j: JugState) -> CGFloat? {
        let rp = min(max(j.reposeProgress, 0), 1)
        guard j.liquid.id == .sand, rp > SceneJug.trickleStart, j.flow < 0.02, j.fill > SceneJug.dryFill else {
            return nil
        }
        return CGFloat((rp - SceneJug.trickleStart) / (1 - SceneJug.trickleStart))
    }

    /// Telegraphs the avalanche: from `trickleStart` to 1 a few grains sit on the lip and more and more of them
    /// trickle off it (deterministic on the session clock, so a paused frame holds still). Gone once sand flows.
    /// Round 9 (REVIEW-7 P1-1): grains 2.2–3 pt with an ink outline in a darker sand (was 1–1.5 pt, the stream's own
    /// colour), 2–6 on the lip and 2–11 falling (was 2–5 and 1–7), fully opaque from u ≈ 0.4.
    private func updateTrickle(_ j: JugState, u tele: CGFloat?, time: Double) {
        guard let u = tele else {
            if !trickle.isHidden {
                trickle.isHidden = true
                for g in grains { g.isHidden = true }
            }
            trickleGrains = 0
            trickleGrainRadius = 0
            return
        }
        if grainTint != j.liquid.id {
            grainTint = j.liquid.id
            let tex = SceneArt.grain(fill: SceneColor.darker(SceneLiquidLook.stream(j.liquid).body, 0.25))
            for g in grains { g.texture = tex }
        }
        let lip = j.lip
        var used = 0
        var biggest: CGFloat = 0
        // Grains gathered on the lip (they creep outward as u grows).
        let sitting = min(SceneJug.maxSittingGrains, 2 + Int(u * 4))
        for k in 0..<sitting {
            let dx = (CGFloat(k) - CGFloat(sitting - 1) * 0.5) * 4.6 + u * 3
            let r: CGFloat = k % 2 == 0 ? 3.0 : 2.4
            placeGrain(used, x: lip.x + dx, y: lip.y + r * 0.5, r: r)
            used += 1
            biggest = max(biggest, r)
        }
        // Falling grains: each loops a short fall from the lip, staggered; more of them (and faster) near 1.
        let falling = min(SceneJug.maxFallingGrains, 2 + Int(u * 9))
        let period = 0.42 - 0.12 * Double(u)
        let fallTime: CGFloat = 0.3
        for k in 0..<falling {
            let ph = (time / period + Double(k) * 0.618).truncatingRemainder(dividingBy: 1)
            let t = CGFloat(ph < 0 ? ph + 1 : ph) * fallTime
            let jitter = CGFloat((k * 37) % 7) - 3
            let x = lip.x + 2 + jitter * 1.1 + t * 12
            let y = lip.y - 2 - 0.5 * 1500 * t * t
            let r: CGFloat = 2.2 + CGFloat((k * 13) % 3) * 0.4
            placeGrain(used, x: x, y: y, r: r)
            used += 1
            biggest = max(biggest, r)
        }
        if used < grains.count {
            for i in used..<grains.count where !grains[i].isHidden { grains[i].isHidden = true }
        }
        trickleGrains = used
        trickleGrainRadius = biggest
        trickle.isHidden = false
        trickle.alpha = min(1, 0.6 + u)
    }

    /// Moves pooled grain `i` (world centre, radius `r`) and shows it.
    private func placeGrain(_ i: Int, x: CGFloat, y: CGFloat, r: CGFloat) {
        guard i >= 0 && i < grains.count else { return }
        let g = grains[i]
        g.position = CGPoint(x: x, y: y)
        // The texture's padding: size the sprite so its outlined disc is 2r across.
        let side = r * 2 * SceneArt.grainTexturePad
        g.size = CGSize(width: side, height: side)
        g.isHidden = false
    }

    /// Round 9 (REVIEW-7 P1-1): the scoop's sight-glass slot glows amber-red from a quarter of the way through the
    /// telegraph, pulsing (steady under Reduce Motion) and strongest as the slide nears.
    private func updateSightWarning(u tele: CGFloat?, time: Double) {
        guard style.form == .scoop, windowWarn.path != nil, let u = tele, u > 0.25 else {
            if !windowWarn.isHidden { windowWarn.isHidden = true }
            return
        }
        let k = min(1, (u - 0.25) / 0.75)
        let beat: CGFloat = reduceMotion ? 1 : 0.6 + 0.4 * CGFloat(sin(2 * Double.pi * (3 + 3 * Double(u)) * time))
        windowWarn.alpha = k * beat
        windowWarn.isHidden = false
    }

    /// Residue beads on the inner walls (jug-local), built with the static parts.
    private func buildResidue(local: [CGPoint], b: CGRect) {
        let poly = ScenePaths.polygon(local)
        let path = CGMutablePath()
        let spots: [(CGFloat, CGFloat, CGFloat)] = [(0.2, -1, 3.2), (0.34, 1, 2.6), (0.47, -1, 2.2), (0.28, 1, 3.4),
                                                    (0.58, 1, 2.0), (0.4, -1, 1.8)]
        for (fy, side, r) in spots {
            let y = b.minY + b.height * fy
            guard let xl = ScenePaths.xOnPolygon(local, atY: y, rightmost: false),
                  let xr = ScenePaths.xOnPolygon(local, atY: y, rightmost: true), xr - xl > 30 else { continue }
            let x = side < 0 ? xl + 7 + r : xr - 7 - r
            let c = CGPoint(x: x, y: y)
            guard poly.contains(c) else { continue }
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r * 1.3, width: r * 2, height: r * 2.6))
        }
        residue.path = path.isEmpty ? nil : path
    }

    // MARK: Spout channel

    /// While pouring, liquid runs along the spout channel's floor from the neck to the lip (REVIEW-2 P1-5), thinning
    /// to the lip where the stream leaves. Uses Core's vertex map (`JugGeometry.spoutChannelIndices`); falls back to a
    /// short tapered sheet from the nearest liquid vertex for any other outline.
    private func updateSpoutSheet(_ j: JugState, streamWidth: CGFloat) {
        guard j.flow > 0.012, streamWidth > 0.5 else {
            spoutSheet.isHidden = true
            return
        }
        let o = j.outline
        let ch = JugGeometry.spoutChannelIndices
        let lipI = JugGeometry.lipIndex
        if o.count == JugGeometry.standard.outline.count && ch.lowerBound < lipI && lipI < ch.upperBound
            && ch.upperBound < o.count {
            sheetFloor.removeAll(keepingCapacity: true)
            sheetRoof.removeAll(keepingCapacity: true)
            sheetTop.removeAll(keepingCapacity: true)
            for i in ch.lowerBound...lipI { sheetFloor.append(o[i]) }
            for i in lipI...ch.upperBound { sheetRoof.append(o[i]) }
            let want = min(16, max(5, streamWidth * 0.62))
            let m = sheetFloor.count
            for k in 0..<m {
                let p = sheetFloor[k]
                let a = sheetFloor[max(k - 1, 0)], b = sheetFloor[min(k + 1, m - 1)]
                let dx = b.x - a.x, dy = b.y - a.y
                let len = max(0.0001, hypot(dx, dy))
                // Interior is to the left of a counter-clockwise outline's edges.
                let nx = -dy / len, ny = dx / len
                let room = ScenePaths.distanceToPolyline(p, sheetRoof) * 0.9
                let t = k == m - 1 ? 0 : min(want, room)
                sheetTop.append(CGPoint(x: p.x + nx * t, y: p.y + ny * t))
            }
            let path = CGMutablePath()
            path.move(to: sheetFloor[0])
            for k in 1..<m { path.addLine(to: sheetFloor[k]) }
            var k = m - 2
            while k >= 0 {
                path.addLine(to: sheetTop[k])
                k -= 1
            }
            path.closeSubpath()
            spoutSheet.path = path
            spoutSheet.isHidden = false
            spoutSheet.alpha = 1
            return
        }
        let qi = ScenePaths.nearestIndex(j.liquidPolygon, to: j.lip)
        guard qi >= 0 else {
            spoutSheet.isHidden = true
            return
        }
        let q = j.liquidPolygon[qi]
        let d = ScenePaths.distance(q, j.lip)
        if d < 1.5 || d > 90 {
            spoutSheet.isHidden = true
            return
        }
        let mid = CGPoint(x: (q.x + j.lip.x) * 0.5, y: max(q.y, j.lip.y) + 1)
        let w = max(3, streamWidth * 0.7)
        let path = CGMutablePath()
        ScenePaths.addRibbon(path, points: [q, mid, j.lip], widths: [w * 1.5, w * 1.2, w])
        spoutSheet.path = path
        spoutSheet.isHidden = false
        spoutSheet.alpha = 1
    }

    private func needsRebuild(_ local: [CGPoint]) -> Bool {
        if local.count != localOutline.count { return true }
        for i in 0..<local.count {
            if abs(local[i].x - localOutline[i].x) > 0.75 || abs(local[i].y - localOutline[i].y) > 0.75 { return true }
        }
        return false
    }

    // MARK: Static parts

    /// Builds every static part in jug-local coordinates (pivot at the origin).
    private func rebuild(_ local: [CGPoint], lip: CGPoint) {
        localOutline = local
        let n = local.count
        let b = ScenePaths.bounds(local)
        let mid = ScenePaths.offsetPolygon(local, by: wall * 0.5)
        let outer = ScenePaths.offsetPolygon(local, by: wall)
        let form = style.form
        let mapped = n == JugGeometry.standard.outline.count && JugGeometry.lidIndices.upperBound < n
        let lidLo = JugGeometry.lidIndices.lowerBound, lidHi = JugGeometry.lidIndices.upperBound

        // Wall order. Lidded forms: a closed loop (the lid sits on top). The scoop: open across the lid edges.
        // Unknown outlines: leave the highest horizontal edge open (round-1 behaviour).
        var order: [Int] = []
        var openMouth: (CGPoint, CGPoint)?
        if mapped {
            if form == .scoop {
                for k in 0...(n - (lidHi - lidLo)) { order.append((lidHi + k) % n) }
                openMouth = (mid[lidLo], mid[lidHi])
            } else {
                for k in 0...n { order.append(k % n) }
            }
        } else {
            var mouth = -1
            var mouthY = -CGFloat.greatestFiniteMagnitude
            for i in 0..<n {
                let a = local[i], c = local[(i + 1) % n]
                let dx = abs(c.x - a.x), dy = abs(c.y - a.y)
                let my = (a.y + c.y) * 0.5
                if dx > 8 && dy < dx * 0.4 && my > mouthY {
                    mouth = i
                    mouthY = my
                }
            }
            if mouth >= 0 && mouthY < b.maxY - b.height * 0.2 { mouth = -1 }
            if mouth >= 0 {
                for k in 1...n { order.append((mouth + k) % n) }
                openMouth = (mid[mouth], mid[(mouth + 1) % n])
            } else {
                for k in 0...n { order.append(k % n) }
            }
        }

        interior.path = ScenePaths.polygon(local)
        wallBody.path = ScenePaths.polyline(mid, order: order)
        wallOuter.path = ScenePaths.polyline(outer, order: order)
        wallInner.path = ScenePaths.polyline(local, order: order)
        shadow.path = ScenePaths.polygon(outer)

        // Accent band around the top ~14 % (rim + spout).
        let bandLevel = b.maxY - b.height * 0.14
        rimBand.path = ScenePaths.polylineAbove(mid, order: order, level: bandLevel)
        rimBand.lineWidth = form == .shakeTin ? wall + 6 : wall + 3
        rimBandShine.path = ScenePaths.polylineAbove(ScenePaths.offsetPolygon(local, by: wall * 0.3), order: order,
                                                     level: bandLevel + 4)
        // P2-1: the foot is a ceramic RING on the outside wall, not a filled band that reads as a second liquid.
        footBand.path = ScenePaths.polylineBelow(mid, order: order, level: b.minY + b.height * 0.08)
        footBand.lineWidth = wall + 2
        footBand.isHidden = hasSkin

        let side: CGFloat = lip.x >= b.midX ? -1 : 1       // handle side (opposite the spout)
        let bodyY = b.minY + b.height * 0.45
        let bodyL = ScenePaths.xOnPolygon(local, atY: bodyY, rightmost: false) ?? b.minX
        let bodyR = ScenePaths.xOnPolygon(local, atY: bodyY, rightmost: true) ?? b.maxX

        buildSkin(outer: outer, b: b, bodyL: bodyL, bodyR: bodyR)
        buildHoops(outer: outer, b: b)
        buildLid(mid: mid, mapped: mapped, openMouth: openMouth)
        buildHandle(outer: outer, b: b, side: side)
        buildTwine(outer: outer, b: b)
        buildHighlights(local: local, mid: mid, b: b)
        buildResidue(local: local, b: b)

        // Everything drawn, in jug-local space (for `worldBounds`: hints must sit beside the lid and handle too).
        var lb = ScenePaths.bounds(outer)
        for nd in [lid, knob, handleOutline] where !nd.isHidden {
            if let p = nd.path {
                let r = p.boundingBoxOfPath
                if !r.isNull && !r.isEmpty { lb = lb.union(r.insetBy(dx: -nd.lineWidth * 0.5, dy: -nd.lineWidth * 0.5)) }
            }
        }
        localDrawnBounds = lb.insetBy(dx: -3, dy: -3)

        // The belly decal (none on the steel tin; none on the scoop since round 6 — with the sight glass it made a face).
        if form == .shakeTin || form == .scoop {
            decal.isHidden = true
        } else {
            decal.isHidden = false
            let dia = form == .scoop ? min(40, max(26, b.width * 0.22)) : min(70, max(30, b.width * 0.36))
            let art = SceneArt.decal(style.decal, accent: style.accent, diameter: dia)
            decal.texture = art.texture
            decal.size = art.size
            let decalY = form == .scoop ? b.minY + b.height * 0.5 : b.minY + b.height * 0.42
            let leftX = ScenePaths.xOnPolygon(local, atY: decalY, rightmost: false) ?? b.minX
            let rightX = ScenePaths.xOnPolygon(local, atY: decalY, rightmost: true) ?? b.maxX
            let frac: CGFloat = form == .scoop ? (side < 0 ? 0.25 : 0.75) : (side < 0 ? 0.56 : 0.44)
            decal.position = CGPoint(x: leftX + (rightX - leftX) * frac, y: decalY)
            decal.zRotation = SceneJug.decalTilt
        }
    }

    /// Steel tin / copper scoop: an opaque skin over the outer silhouette with a sight window cut through it, so the
    /// player still reads the level (REVIEW-2 P1-9).
    private func buildSkin(outer: [CGPoint], b: CGRect, bodyL: CGFloat, bodyR: CGFloat) {
        guard hasSkin else {
            for nd in [skin, windowFrame, windowGlare, ticks, windowWarn] { nd.isHidden = true }
            windowWarn.path = nil
            return
        }
        var sil = outer
        if ScenePaths.signedArea(sil) < 0 { sil.reverse() }
        let bw = max(20, bodyR - bodyL)
        let scoop = style.form == .scoop
        let cx = bodyL + bw * (scoop ? 0.64 : 0.5)
        // Round 6 (REVIEW-5 §4): the scoop's wide oval window with ticks inside it read as a grinning mouth with
        // teeth (and the sun decal above it as an eye). It is now a slim gauge slot with the graduations engraved on
        // the copper beside it, and no belly decal.
        let hw = scoop ? max(7, bw * 0.07) : max(14, bw * 0.15)
        let y0 = b.minY + b.height * (scoop ? 0.16 : 0.1), y1 = b.minY + b.height * (scoop ? 0.78 : 0.8)
        let win = ScenePaths.pillClockwise(centerX: cx, minY: y0, maxY: y1, halfWidth: hw)
        let path = ScenePaths.polygon(sil)
        path.addPath(ScenePaths.polygon(win))
        skin.path = path
        skin.isHidden = false
        windowFrame.path = ScenePaths.polygon(win)
        windowFrame.isHidden = false
        // The scoop's slot carries the slide warning (an amber-red ring over its frame; shown by `updateSightWarning`).
        windowWarn.path = scoop ? windowFrame.path : nil
        windowWarn.isHidden = true
        let glare = CGMutablePath()
        let gx = cx - hw + (scoop ? 3 : 5)
        glare.move(to: CGPoint(x: gx, y: y1 - hw - 4))
        glare.addLine(to: CGPoint(x: gx, y: y0 + hw + 10))
        windowGlare.path = glare
        windowGlare.lineWidth = scoop ? 2 : 3
        windowGlare.isHidden = false
        if scoop {
            // Engraved graduations on the copper, left of the slot (a ruler, not teeth), plus two rivets that pin the
            // slot's frame top and bottom.
            let tp = CGMutablePath()
            for k in 1...5 {
                let y = y0 + (y1 - y0) * CGFloat(k) / 6
                tp.move(to: CGPoint(x: cx - hw - 4, y: y))
                tp.addLine(to: CGPoint(x: cx - hw - (k == 3 ? 15 : 9), y: y))
            }
            tp.addEllipse(in: CGRect(x: cx - 2, y: y1 + 3, width: 4, height: 4))
            tp.addEllipse(in: CGRect(x: cx - 2, y: y0 - 7, width: 4, height: 4))
            ticks.path = tp
            ticks.strokeColor = SceneColor.hex(0x6A3418, 0.75)
            ticks.isHidden = false
        } else {
            ticks.isHidden = true
        }
    }

    /// Soda dispenser: two chrome hoops around the body.
    private func buildHoops(outer: [CGPoint], b: CGRect) {
        guard style.form == .dispenser else {
            hoops.isHidden = true
            return
        }
        let path = CGMutablePath()
        for frac in [CGFloat(0.2), CGFloat(0.66)] {
            let y0 = b.minY + b.height * frac
            let above = ScenePaths.clip(outer, level: y0, below: false)
            let strip = ScenePaths.clip(above, level: y0 + 10, below: true)
            if strip.count >= 3 { path.addPath(ScenePaths.polygon(strip)) }
        }
        hoops.path = path
        hoops.isHidden = path.isEmpty
    }

    /// The lid over `JugGeometry.lidIndices`: domed with a knob (pitcher), flat chrome with a red button (dispenser),
    /// a flat steel cap (tin), a cork (flask); the scoop is open (a dark copper mouth that shows sand when full).
    private func buildLid(mid: [CGPoint], mapped: Bool, openMouth: (CGPoint, CGPoint)?) {
        lid.isHidden = true
        lidShine.isHidden = true
        knob.isHidden = true
        knobShine.isHidden = true
        opening.isHidden = true
        if let m = openMouth, style.form == .scoop || !mapped {
            let centre = CGPoint(x: (m.0.x + m.1.x) * 0.5, y: (m.0.y + m.1.y) * 0.5)
            let rx = abs(m.0.x - m.1.x) * 0.5
            let ry = min(10, max(4, rx * 0.15))
            opening.path = ScenePaths.polygon(ScenePaths.ellipseArc(center: centre, rx: rx, ry: ry, from: 0, to: 2 * .pi,
                                                                    segments: 28))
            opening.isHidden = false
            if style.form != .scoop { opening.fillColor = UIColor(white: 1, alpha: 0.08) }
            return
        }
        guard mapped else { return }
        let lo = JugGeometry.lidIndices.lowerBound, hi = JugGeometry.lidIndices.upperBound
        var pts: [CGPoint] = []
        for i in lo...hi { pts.append(mid[i]) }
        let a = pts[0], d = pts[pts.count - 1]          // a = spout side, d = handle side
        var top = -CGFloat.greatestFiniteMagnitude
        for p in pts { top = max(top, p.y) }
        let cx = (a.x + d.x) * 0.5
        let dir: CGFloat = a.x >= d.x ? 1 : -1
        let width = abs(a.x - d.x)

        switch style.form {
        case .pitcher, .scoop:
            let dome: CGFloat = 10
            let p = CGMutablePath()
            p.move(to: CGPoint(x: a.x + dir * 3, y: a.y - 3))
            for q in pts.dropFirst().dropLast() { p.addLine(to: CGPoint(x: q.x, y: q.y - 3)) }
            p.addLine(to: CGPoint(x: d.x - dir * 3, y: d.y - 3))
            p.addLine(to: CGPoint(x: d.x - dir * 2, y: d.y + 5))
            p.addQuadCurve(to: CGPoint(x: a.x + dir * 2, y: a.y + 5), control: CGPoint(x: cx, y: top + 5 + dome * 2))
            p.closeSubpath()
            lid.path = p
            lid.isHidden = false
            let sp = CGMutablePath()
            sp.move(to: CGPoint(x: d.x + dir * width * 0.16, y: top + 7))
            sp.addQuadCurve(to: CGPoint(x: cx - dir * 10, y: top + 5 + dome * 0.95),
                            control: CGPoint(x: d.x + dir * width * 0.3, y: top + 5 + dome * 0.95))
            lidShine.path = sp
            lidShine.isHidden = false
            // Knob on a short neck at the crown.
            let crown = top + 5 + dome
            let kp = CGMutablePath()
            kp.addRoundedRect(in: CGRect(x: cx - 4, y: crown - 3, width: 8, height: 9), cornerWidth: 2, cornerHeight: 2)
            kp.addEllipse(in: CGRect(x: cx - 9, y: crown + 4, width: 18, height: 14))
            knob.path = kp
            knob.isHidden = false
            knobShine.path = CGPath(ellipseIn: CGRect(x: cx - 5.5, y: crown + 11, width: 5, height: 3.5), transform: nil)
            knobShine.isHidden = false
        case .dispenser, .shakeTin:
            let h: CGFloat = style.form == .dispenser ? 11 : 8
            let minX = min(a.x, d.x) - 5, maxX = max(a.x, d.x) + 5
            var low = CGFloat.greatestFiniteMagnitude
            for q in pts { low = min(low, q.y) }
            let rect = CGRect(x: minX, y: low - 3, width: maxX - minX, height: top - low + 3 + h)
            lid.path = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            lid.isHidden = false
            let sp = CGMutablePath()
            sp.move(to: CGPoint(x: rect.minX + 8, y: rect.maxY - 3))
            sp.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.maxY - 3))
            lidShine.path = sp
            lidShine.isHidden = false
            if style.form == .dispenser {
                knob.path = CGPath(roundedRect: CGRect(x: cx - 13, y: rect.maxY - 1, width: 26, height: 8),
                                   cornerWidth: 3, cornerHeight: 3, transform: nil)
                knob.isHidden = false
                knobShine.path = CGPath(ellipseIn: CGRect(x: cx - 9, y: rect.maxY + 3, width: 7, height: 2.5), transform: nil)
                knobShine.isHidden = false
            }
        case .flask:
            // Glass shoulder + cork: the cork is ~45 % of the mouth, tapering wider at the top.
            let cw = max(26, width * 0.42)
            let base = top - 4
            let p = CGMutablePath()
            p.move(to: CGPoint(x: cx - cw * 0.44, y: base))
            p.addLine(to: CGPoint(x: cx + cw * 0.44, y: base))
            p.addLine(to: CGPoint(x: cx + cw * 0.5, y: base + 26))
            p.addQuadCurve(to: CGPoint(x: cx - cw * 0.5, y: base + 26), control: CGPoint(x: cx, y: base + 31))
            p.closeSubpath()
            lid.path = p
            lid.isHidden = false
            // Cork grain rings.
            let sp = CGMutablePath()
            for k in 1...2 {
                let y = base + CGFloat(k) * 8
                sp.move(to: CGPoint(x: cx - cw * 0.36, y: y))
                sp.addLine(to: CGPoint(x: cx + cw * 0.36, y: y))
            }
            lidShine.path = sp
            lidShine.strokeColor = SceneColor.darker(SceneJug.cork, 0.25).withAlphaComponent(0.7)
            lidShine.lineWidth = 1.6
            lidShine.isHidden = false
        }
        if style.form != .flask {
            lidShine.strokeColor = UIColor(white: 1, alpha: 0.6)
            lidShine.lineWidth = 3
        }
    }

    /// Loop handle (pitcher, dispenser), a wooden stick (scoop), nothing (tin, flask).
    private func buildHandle(outer: [CGPoint], b: CGRect, side: CGFloat) {
        switch style.form {
        case .shakeTin, .flask:
            for nd in [handleOutline, handleBody, handleShine] { nd.isHidden = true }
        case .scoop:
            let y = b.minY + b.height * 0.62
            let x0 = ScenePaths.xOnPolygon(outer, atY: y, rightmost: side > 0) ?? (side > 0 ? b.maxX : b.minX)
            let len = max(40, b.width * 0.32)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x0 - side * 4, y: y))
            p.addLine(to: CGPoint(x: x0 + side * len, y: y + 8))
            handleOutline.path = p
            handleOutline.lineWidth = 17
            handleBody.path = p
            handleBody.lineWidth = 11
            let sp = CGMutablePath()
            sp.move(to: CGPoint(x: x0 + side * 12, y: y + 3.5))
            sp.addLine(to: CGPoint(x: x0 + side * (len - 6), y: y + 10))
            handleShine.path = sp
            for nd in [handleOutline, handleBody, handleShine] { nd.isHidden = false }
        case .pitcher, .dispenser:
            let yTop = b.minY + b.height * 0.78
            let yBot = b.minY + b.height * 0.30
            let xTop = ScenePaths.xOnPolygon(outer, atY: yTop, rightmost: side > 0) ?? (side > 0 ? b.maxX : b.minX)
            let xBot = ScenePaths.xOnPolygon(outer, atY: yBot, rightmost: side > 0) ?? (side > 0 ? b.maxX : b.minX)
            // Round 3 moved the jug left: a slightly tighter loop keeps the tipped handle inside the phone crop.
            let bulge = max(30, b.width * 0.3)
            let square: CGFloat = style.form == .dispenser ? 0.8 : 1
            let handle = CGMutablePath()
            handle.move(to: CGPoint(x: xTop - side * 5, y: yTop))
            handle.addCurve(to: CGPoint(x: xBot - side * 5, y: yBot),
                            control1: CGPoint(x: xTop + side * bulge, y: yTop + 18 * square),
                            control2: CGPoint(x: xBot + side * bulge * 0.92, y: yBot - 14 * square))
            handleOutline.path = handle
            handleOutline.lineWidth = 19
            handleBody.path = handle
            handleBody.lineWidth = 13
            let shinePath = CGMutablePath()
            shinePath.move(to: CGPoint(x: xTop + side * bulge * 0.32, y: yTop + 7))
            shinePath.addQuadCurve(to: CGPoint(x: xTop + side * bulge * 0.62, y: yTop - b.height * 0.13),
                                   control: CGPoint(x: xTop + side * bulge * 0.6, y: yTop + 5))
            handleShine.path = shinePath
            for nd in [handleOutline, handleBody, handleShine] { nd.isHidden = false }
        }
    }

    /// Potion flask: twine wrapped twice around the neck.
    private func buildTwine(outer: [CGPoint], b: CGRect) {
        guard style.form == .flask else {
            twine.isHidden = true
            return
        }
        let p = CGMutablePath()
        for (k, frac) in [CGFloat(0.8), CGFloat(0.76)].enumerated() {
            let y = b.minY + b.height * frac
            if let xl = ScenePaths.xOnPolygon(outer, atY: y, rightmost: false),
               let xr = ScenePaths.xOnPolygon(outer, atY: y, rightmost: true) {
                p.move(to: CGPoint(x: xl - 1, y: y + (k == 0 ? 2 : -2)))
                p.addLine(to: CGPoint(x: xr + 1, y: y + (k == 0 ? -2 : 2)))
            }
        }
        twine.path = p
        twine.isHidden = p.isEmpty
    }

    private func buildHighlights(local: [CGPoint], mid: [CGPoint], b: CGRect) {
        // Specular streak down the light side (top-left), fat and bright like the icon's.
        var streak: [CGPoint] = []
        for k in 0...6 {
            let y = b.minY + b.height * (0.24 + 0.42 * CGFloat(k) / 6)
            if let x = ScenePaths.xOnPolygon(local, atY: y, rightmost: false) {
                streak.append(CGPoint(x: x + 12, y: y))
            }
        }
        if streak.count >= 2 {
            let sp = CGMutablePath()
            sp.move(to: streak[0])
            ScenePaths.addSmoothCurve(sp, streak)
            shine.path = sp
            shine.isHidden = false
            shine.alpha = hasSkin ? 0.7 : 1
        } else {
            shine.isHidden = true
        }
        let dotY0 = b.minY + b.height * 0.72, dotY1 = b.minY + b.height * 0.78
        if let x0 = ScenePaths.xOnPolygon(local, atY: dotY0, rightmost: false),
           let x1 = ScenePaths.xOnPolygon(local, atY: dotY1, rightmost: false) {
            let dp = CGMutablePath()
            dp.move(to: CGPoint(x: x0 + 12, y: dotY0))
            dp.addLine(to: CGPoint(x: x1 + 12, y: dotY1))
            shineDot.path = dp
            shineDot.isHidden = false
        } else {
            shineDot.isHidden = true
        }

        // Brushed-metal hairlines (steel tin, copper scoop).
        if style.metallic {
            let mp = CGMutablePath()
            for (k, frac) in [CGFloat(0.22), CGFloat(0.5), CGFloat(0.78)].enumerated() {
                let y = b.minY + b.height * frac
                if let xl = ScenePaths.xOnPolygon(mid, atY: y, rightmost: false),
                   let xr = ScenePaths.xOnPolygon(mid, atY: y, rightmost: true) {
                    let inset: CGFloat = k == 1 ? 3 : 1
                    mp.move(to: CGPoint(x: xl - inset, y: y - 6))
                    mp.addLine(to: CGPoint(x: xl - inset, y: y + 6))
                    mp.move(to: CGPoint(x: xr + inset, y: y - 4))
                    mp.addLine(to: CGPoint(x: xr + inset, y: y + 4))
                }
            }
            metalLines.path = mp
        }
    }
}
