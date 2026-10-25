import SpriteKit
import UIKit

/// The pour (REVIEW-2 P1-5): a FAT, OPAQUE ribbon in the icon's style — Catmull–Rom through Core's stream particles,
/// offset ± width/2 along the normals, with a darker keyline, a rich saturated body, a bright core and a hot specular
/// thread. Widths come from `ScenePaths.streamDisplayWidth` (a typical pour ≥ 20 pt, full flow 26 pt, thick drinks
/// 1.6×). The ribbon necks in at the lip so it leaves the spout channel cleanly.
///
/// Round 4 (REVIEW-3 P1-2): a tail that has left the spout is NOT a chain of identical beads. When the pour stops the
/// column breaks up from the top down (Plateau–Rayleigh): the part still falling as a column stays a ribbon with a
/// pinched top, the part above it is 3–6 drops of varied size (60–100 %) whose spacing grows as they fall, starting at
/// the spout lip. The drops fade out within ~0.4 s of the stop. Lone drips get the same varied sizes.
///
/// Per-liquid personality: thick drinks fall as a straight, slowly pulsing rope (lateral wobble ≤ 3 pt, REVIEW-3 P2-1)
/// and coil lazily where they land; fizzy drinks carry rising bubbles.
/// Five shape nodes total; their paths are rebuilt each frame (scratch buffers are reused).
@MainActor
final class SceneStream {
    let root: SKNode
    private let body: SKShapeNode
    private let core: SKShapeNode
    private let spec: SKShapeNode
    private let drops: SKShapeNode
    /// Drops of a detached tail (they fade after the pour stops; spill spray in `drops` does not).
    private let tail: SKShapeNode
    private var liquidID: LiquidID?
    private var baseAlpha: CGFloat = 1
    private var wobble: CGFloat = 0.04
    private var thick = false
    private var fizzy = false
    private var pts: [CGPoint] = []
    private var ws: [CGFloat] = []
    /// Scratch: cumulative arc length along the run being drawn.
    private var arc: [CGFloat] = []
    /// Session time the outflow stopped (nil while the jug pours).
    private var stopTime: Double?

    /// Drop sizes of a breaking tail, 60–100 % (cycled; deterministic so CI frames are stable).
    static let dropSizes: [CGFloat] = [0.64, 0.92, 0.74, 1.0, 0.6, 0.84]
    /// The break-up front runs down a stopped column this fast (pt/s), from `breakStart` pt below its top.
    static let breakSpeed: CGFloat = 780
    static let breakStart: CGFloat = 36
    /// Tail drops start fading this long after the stop and are gone `tailFade` later (≈ 0.4 s in all).
    static let tailFadeDelay: CGFloat = 0.2
    static let tailFade: CGFloat = 0.2
    /// Thick drinks: the rope's centre line never strays more than this from Core's path.
    static let thickMaxWobble: CGFloat = 3

    static func isThick(_ id: LiquidID) -> Bool {
        id == .milkshake || id == .honey || id == .mapleSyrup || id == .berrySmoothie
    }

    /// How many drops a broken length of `length` pt shows (1 for a pinch, 3…6 for a real tail).
    static func dropCount(forLength length: CGFloat) -> Int {
        if length < 24 { return 1 }
        return min(6, max(3, Int(length / 45) + 2))
    }

    /// Arc-length position (from the top) of drop `k` of `count` in a broken length `length`: spacing grows down the
    /// fall (ballistic: lower drops have fallen longer).
    static func dropOffset(_ k: Int, of count: Int, length: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        let u = CGFloat(k) / CGFloat(count - 1)
        return length * 0.94 * CGFloat(pow(Double(u), 1.5))
    }

    init() {
        root = SKNode()
        body = SKShapeNode()
        core = SKShapeNode()
        spec = SKShapeNode()
        drops = SKShapeNode()
        tail = SKShapeNode()
        body.zPosition = 0
        drops.zPosition = 0.5
        tail.zPosition = 0.6
        core.zPosition = 1
        spec.zPosition = 1.5
        body.lineWidth = 2.4
        body.lineJoin = .round
        core.strokeColor = .clear
        core.lineWidth = 0
        spec.strokeColor = .clear
        spec.lineWidth = 0
        spec.fillColor = UIColor(white: 1, alpha: 0.9)
        drops.lineWidth = 1.6
        tail.lineWidth = 1.6
        root.addChild(body)
        root.addChild(drops)
        root.addChild(tail)
        root.addChild(core)
        root.addChild(spec)
    }

    func clear() {
        body.path = nil
        core.path = nil
        spec.path = nil
        drops.path = nil
        tail.path = nil
        stopTime = nil
        root.isHidden = true
    }

    /// Ribbon width the scene draws for a Core width (the jug's spout sheet uses it too).
    func displayWidth(_ coreWidth: CGFloat) -> CGFloat {
        ScenePaths.streamDisplayWidth(coreWidth, coreMax: CGFloat(CoreTuning.streamWidthMax), thick: thick)
    }

    /// `landing`: where the stream's tail meets a liquid surface (world), if it does — thick drinks coil there.
    /// `lip`: the spout lip while the jug is still pouring (nil once outflow stopped) — the run that starts there is
    /// the attached stream; every other run is a falling tail.
    func update(points: [StreamPoint], droplets: [Droplet], liquid: Liquid, time: Double, landing: CGPoint?,
                lip: CGPoint?) {
        if liquidID != liquid.id {
            liquidID = liquid.id
            let look = SceneLiquidLook.stream(liquid)
            body.fillColor = look.body
            body.strokeColor = look.edge
            core.fillColor = look.core.withAlphaComponent(0.8)
            drops.fillColor = look.body
            drops.strokeColor = look.edge
            tail.fillColor = look.body
            tail.strokeColor = look.edge
            baseAlpha = look.alpha
            thick = SceneStream.isThick(liquid.id)
            fizzy = liquid.fizzy
            wobble = thick ? 0.14 : (liquid.id == .sand ? 0.02 : 0.045)
        }
        if lip == nil {
            if stopTime == nil { stopTime = time }
        } else {
            stopTime = nil
        }
        if points.isEmpty && droplets.isEmpty {
            if !root.isHidden { clear() }
            return
        }
        root.isHidden = false
        body.alpha = baseAlpha
        drops.alpha = baseAlpha
        core.alpha = 1
        spec.alpha = 1
        // Seconds since the outflow stopped (0 while pouring).
        var age: CGFloat = 0
        if let st = stopTime { age = CGFloat(max(0, time - st)) }
        let tailFade: CGFloat = stopTime == nil ? 1
            : min(1, max(0, 1 - (age - SceneStream.tailFadeDelay) / SceneStream.tailFade))
        tail.alpha = baseAlpha * tailFade

        let bodyPath = CGMutablePath()
        let corePath = CGMutablePath()
        let specPath = CGMutablePath()
        let dropPath = CGMutablePath()
        let tailPath = CGMutablePath()
        let t = CGFloat(time)

        if !points.isEmpty {
            pts.removeAll(keepingCapacity: true)
            ws.removeAll(keepingCapacity: true)
            for p in points {
                pts.append(p.position)
                ws.append(displayWidth(p.width))
            }
            var runIndex = 0
            for run in ScenePaths.runs(pts, gap: 54) {
                runIndex += 1
                let first = pts[run.lowerBound]
                let attached = lip.map { ScenePaths.distance($0, first) < 14 } ?? false
                if run.count == 1 {
                    // A lone drip: varied sizes, so a dribble never reads as a dotted line.
                    let size = SceneStream.dropSizes[runIndex % SceneStream.dropSizes.count]
                    let r = max(2.6, ws[run.lowerBound] * 0.45) * size
                    tailPath.addEllipse(in: CGRect(x: first.x - r, y: first.y - r * 1.15, width: r * 2, height: r * 2.3))
                    continue
                }
                if !attached {
                    // Stopped: the break-up front runs down the column. A gap mid-pour: all drops.
                    let breakLength: CGFloat = stopTime == nil ? CGFloat.greatestFiniteMagnitude
                        : SceneStream.breakStart + age * SceneStream.breakSpeed
                    addDetached(run: run, breakLength: breakLength, body: bodyPath, core: corePath, drops: tailPath)
                    continue
                }
                var rp = Array(pts[run])
                var rw = Array(ws[run])
                // Neck at the lip: ~60 % of the width at the spout, full width ~18 pt below it.
                var s: CGFloat = 0
                for i in 0..<rp.count {
                    if i > 0 { s += ScenePaths.distance(rp[i - 1], rp[i]) }
                    if s >= 18 { break }
                    rw[i] *= 0.6 + 0.4 * (s / 18)
                }
                let smoothed = ScenePaths.smooth(rp, widths: rw, maxStep: 6)
                rp = smoothed.points
                rw = smoothed.widths
                if thick {
                    // A rope, not a ribbon: barely any sideways travel, viscosity shows as a slow swell of the
                    // width running down it and a gentle taper toward the landing.
                    ScenePaths.wobble(&rp, widths: rw, amplitude: wobble, time: t * 0.6,
                                      maxOffset: SceneStream.thickMaxWobble)
                    var acc: CGFloat = 0
                    for i in 0..<rw.count {
                        if i > 0 { acc += ScenePaths.distance(rp[i - 1], rp[i]) }
                        let swell = 1 + 0.08 * sin(t * 3.1 - acc * 0.045)
                        let taper = 1 - 0.12 * min(1, acc / 320)
                        rw[i] *= swell * taper
                    }
                } else {
                    ScenePaths.wobble(&rp, widths: rw, amplitude: wobble, time: t)
                }
                ScenePaths.addRibbon(bodyPath, points: rp, widths: rw)
                ScenePaths.addRibbon(corePath, points: rp, widths: rw, widthScale: 0.42, shift: -0.12, minHalfWidth: 0.6)
                ScenePaths.addRibbon(specPath, points: rp, widths: rw, widthScale: 0.1, shift: -0.25, minHalfWidth: 0.5)
                if fizzy && rp.count >= 6 {
                    // A few bubbles riding up the stream.
                    let m = rp.count
                    for k in 0..<4 {
                        var u = (t * 0.9 + CGFloat(k) * 0.25).truncatingRemainder(dividingBy: 1)
                        u = 1 - u
                        let idx = min(m - 1, max(0, Int(u * CGFloat(m - 1))))
                        let c = rp[idx]
                        let r = max(1.2, rw[idx] * 0.11)
                        corePath.addEllipse(in: CGRect(x: c.x + rw[idx] * 0.14 - r, y: c.y - r, width: r * 2, height: r * 2))
                    }
                }
            }
            // Thick drinks fold over themselves where they land: slow, lumpy coils.
            if thick, let land = landing, let last = pts.last, let lw = ws.last, abs(last.y - land.y) < 40 {
                let w = max(8, lw)
                for k in 0..<3 {
                    let ph = t * 2.8 + CGFloat(k) * 2.1
                    let dx = sin(ph) * w * 0.34 + CGFloat(k - 1) * w * 0.3
                    let rw = w * (0.56 + 0.14 * sin(ph * 0.7 + CGFloat(k)))
                    let rh = w * (0.32 + 0.05 * sin(ph * 1.3))
                    let cy = land.y + 1.5 + CGFloat(k) * w * 0.1
                    let rect = CGRect(x: land.x + dx - rw, y: cy - rh, width: rw * 2, height: rh * 2)
                    bodyPath.addEllipse(in: rect)
                    corePath.addEllipse(in: rect.insetBy(dx: rw * 0.45, dy: rh * 0.35).offsetBy(dx: -rw * 0.2, dy: rh * 0.25))
                }
            }
        }
        for d in droplets {
            let r = max(1.4, d.radius * 1.35)
            let speed = hypot(d.velocity.dx, d.velocity.dy)
            if speed > 260 {
                let stretch = min(2.2, 1 + speed / 1400)
                let ang = atan2(d.velocity.dy, d.velocity.dx)
                let tr = CGAffineTransform(translationX: d.position.x, y: d.position.y).rotated(by: ang).scaledBy(x: stretch, y: 1)
                dropPath.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: tr)
            } else {
                dropPath.addEllipse(in: CGRect(x: d.position.x - r, y: d.position.y - r, width: r * 2, height: r * 2))
            }
        }
        body.path = bodyPath.isEmpty ? nil : bodyPath
        core.path = corePath.isEmpty ? nil : corePath
        spec.path = specPath.isEmpty ? nil : specPath
        drops.path = dropPath.isEmpty ? nil : dropPath
        tail.path = tailPath.isEmpty || tailFade <= 0.001 ? nil : tailPath
    }

    /// A run that has left the spout. Its top `breakLength` pt has broken into a few drops (sized 60–100 %, spacing
    /// growing down the fall); whatever is below that still falls as a column with a pinched top.
    private func addDetached(run: Range<Int>, breakLength: CGFloat, body: CGMutablePath, core: CGMutablePath,
                             drops: CGMutablePath) {
        arc.removeAll(keepingCapacity: true)
        var total: CGFloat = 0
        for i in run {
            if i > run.lowerBound { total += ScenePaths.distance(pts[i - 1], pts[i]) }
            arc.append(total)
        }
        let broken = min(max(breakLength, 0), total)

        // 1. The column still falling below the break.
        var firstKept = -1
        for (j, s) in arc.enumerated() where s >= broken {
            firstKept = j
            break
        }
        if firstKept >= 0 && arc.count - firstKept >= 2 {
            let lo = run.lowerBound + firstKept
            var rp = Array(pts[lo..<run.upperBound])
            var rw = Array(ws[lo..<run.upperBound])
            // Pinched top: the neck where the last drop is pulling away.
            let s0 = arc[firstKept]
            for j in 0..<rp.count {
                let s = arc[firstKept + j] - s0
                if s >= 26 { break }
                rw[j] *= 0.35 + 0.65 * (s / 26)
            }
            let smoothed = ScenePaths.smooth(rp, widths: rw, maxStep: 6)
            rp = smoothed.points
            rw = smoothed.widths
            ScenePaths.addRibbon(body, points: rp, widths: rw)
            ScenePaths.addRibbon(core, points: rp, widths: rw, widthScale: 0.42, shift: -0.12, minHalfWidth: 0.6)
        }

        // 2. Drops in the broken part, from the top of the run (the spout lip right after the stop).
        guard broken > 2 else { return }
        let length = broken
        let count = SceneStream.dropCount(forLength: length)
        var j = 0
        for k in 0..<count {
            let target = SceneStream.dropOffset(k, of: count, length: length)
            while j < arc.count - 1 && arc[j + 1] < target { j += 1 }
            let i0 = run.lowerBound + j
            let i1 = min(i0 + 1, run.upperBound - 1)
            let segLen = max(0.0001, (j + 1 < arc.count ? arc[j + 1] : arc[j]) - arc[j])
            let u: CGFloat = i1 == i0 ? 0 : min(max((target - arc[j]) / segLen, 0), 1)
            let a = pts[i0], b = pts[i1]
            let p = CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
            let w = ws[i0] + (ws[i1] - ws[i0]) * u
            let size = SceneStream.dropSizes[k % SceneStream.dropSizes.count]
            let r = max(2.2, w * 0.42) * size
            // Stretched a little along the fall.
            let ang: CGFloat = (i1 == i0) ? -CGFloat.pi / 2 : atan2(b.y - a.y, b.x - a.x)
            let tr = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: ang).scaledBy(x: 1.2 + 0.15 * size, y: 1)
            drops.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: tr)
        }
    }
}
