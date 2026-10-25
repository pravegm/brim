import SpriteKit
import UIKit

/// The pour (REVIEW-2 P1-5): a FAT, OPAQUE ribbon in the icon's style — Catmull–Rom through Core's stream particles,
/// offset ± width/2 along the normals, with a darker keyline, a rich saturated body, a bright core and a hot specular
/// thread. Widths come from `ScenePaths.streamDisplayWidth` (a typical pour ≥ 20 pt, full flow 26 pt, thick drinks
/// 1.6×). The ribbon necks in at the lip so it leaves the spout channel cleanly; a tail that has left the spout breaks
/// into falling beads instead of a rigid stick (P2-8).
/// Per-liquid personality: thick drinks wobble slowly and coil where they land; fizzy drinks carry rising bubbles.
/// Four shape nodes total; their paths are rebuilt each frame.
@MainActor
final class SceneStream {
    let root: SKNode
    private let body: SKShapeNode
    private let core: SKShapeNode
    private let spec: SKShapeNode
    private let drops: SKShapeNode
    private var liquidID: LiquidID?
    private var baseAlpha: CGFloat = 1
    private var wobble: CGFloat = 0.04
    private var thick = false
    private var fizzy = false
    private var pts: [CGPoint] = []
    private var ws: [CGFloat] = []

    static func isThick(_ id: LiquidID) -> Bool {
        id == .milkshake || id == .honey || id == .mapleSyrup || id == .berrySmoothie
    }

    init() {
        root = SKNode()
        body = SKShapeNode()
        core = SKShapeNode()
        spec = SKShapeNode()
        drops = SKShapeNode()
        body.zPosition = 0
        drops.zPosition = 0.5
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
        root.addChild(body)
        root.addChild(drops)
        root.addChild(core)
        root.addChild(spec)
    }

    func clear() {
        body.path = nil
        core.path = nil
        spec.path = nil
        drops.path = nil
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
            baseAlpha = look.alpha
            thick = SceneStream.isThick(liquid.id)
            fizzy = liquid.fizzy
            wobble = thick ? 0.14 : (liquid.id == .sand ? 0.02 : 0.045)
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

        let bodyPath = CGMutablePath()
        let corePath = CGMutablePath()
        let specPath = CGMutablePath()
        let dropPath = CGMutablePath()
        let t = CGFloat(time)

        if !points.isEmpty {
            pts.removeAll(keepingCapacity: true)
            ws.removeAll(keepingCapacity: true)
            for p in points {
                pts.append(p.position)
                ws.append(displayWidth(p.width))
            }
            for run in ScenePaths.runs(pts, gap: 54) {
                let first = pts[run.lowerBound]
                let attached = lip.map { ScenePaths.distance($0, first) < 14 } ?? false
                if run.count == 1 {
                    let r = max(2, ws[run.lowerBound] * 0.45)
                    dropPath.addEllipse(in: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2))
                    continue
                }
                if !attached {
                    addBeads(dropPath, run: run)
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
                ScenePaths.wobble(&rp, widths: rw, amplitude: wobble, time: t)
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
            // Thick drinks fold over themselves where they land.
            if thick, let land = landing, let last = pts.last, let lw = ws.last, abs(last.y - land.y) < 40 {
                let w = max(8, lw)
                for k in 0..<3 {
                    let ph = t * 5 + CGFloat(k) * 2.1
                    let dx = sin(ph) * w * 0.4 + CGFloat(k - 1) * w * 0.32
                    let rw = w * (0.58 + 0.1 * sin(ph * 0.7))
                    let rh = w * 0.34
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
    }

    /// A tail that has left the spout: falling beads along the run, slightly stretched along the fall.
    private func addBeads(_ path: CGMutablePath, run: Range<Int>) {
        var acc: CGFloat = 0
        var lastIdx = run.lowerBound
        var placed = 0
        for i in run {
            if i > run.lowerBound { acc += ScenePaths.distance(pts[i - 1], pts[i]) }
            let w = max(3, ws[i] * 0.8)
            let spacing = max(7, w * 1.7)
            if i == run.lowerBound || acc >= spacing || i == run.upperBound - 1 {
                if i != run.lowerBound && acc < spacing * 0.5 { continue }
                acc = 0
                let p = pts[i]
                let q = pts[max(lastIdx, run.lowerBound)]
                let ang = atan2(p.y - q.y, p.x - q.x)
                let r = w * 0.5
                let rot: CGFloat = i == lastIdx ? -CGFloat.pi / 2 : ang
                let tr = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: rot).scaledBy(x: 1.25, y: 1)
                path.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: tr)
                lastIdx = i
                placed += 1
                if placed > 24 { break }
            }
        }
    }
}
