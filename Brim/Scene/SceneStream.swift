import SpriteKit
import UIKit

/// The pour (REVIEW-1 P1-4/P1-5): a fat, glossy ribbon (Catmull–Rom through the stream particles, offset ± width/2
/// along the normals) with a lighter core, a hot specular thread and a darker keyline, plus free droplets.
/// Per-liquid personality: thick drinks (shake, honey, syrup, smoothie) are 1.6× wider, wobble slowly and coil where
/// they land; fizzy drinks carry a few rising bubbles. Four shape nodes total; paths are rebuilt each frame.
@MainActor
final class SceneStream {
    let root: SKNode
    private let body: SKShapeNode
    private let core: SKShapeNode
    private let spec: SKShapeNode
    private let drops: SKShapeNode
    private var liquidID: LiquidID?
    private var baseAlpha: CGFloat = 1
    private var widthScale: CGFloat = 1
    private var wobble: CGFloat = 0.04
    private var thick = false
    private var fizzy = false

    /// Width multiplier that brings Core's ribbon up to the round-2 target (~26 pt at full flow).
    static var baseWidthScale: CGFloat {
        let coreMax = CGFloat(CoreTuning.streamWidthMax)
        guard coreMax > 1 else { return 1 }
        return min(1.6, max(1, 26 / coreMax))
    }

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
        body.lineWidth = 1.3
        core.strokeColor = .clear
        core.lineWidth = 0
        spec.strokeColor = .clear
        spec.lineWidth = 0
        spec.fillColor = UIColor(white: 1, alpha: 0.85)
        drops.lineWidth = 0
        drops.strokeColor = .clear
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
        min(36, max(1.6, coreWidth * widthScale))
    }

    /// `landing`: where the stream's tail meets a liquid surface (world), if it does — thick drinks coil there.
    func update(points: [StreamPoint], droplets: [Droplet], liquid: Liquid, time: Double, landing: CGPoint?) {
        if liquidID != liquid.id {
            liquidID = liquid.id
            let top = SceneColor.opaque(liquid.top.skColor)
            let bottom = SceneColor.opaque(liquid.bottom.skColor)
            let mid = SceneColor.mix(bottom, top, 0.62)
            body.fillColor = mid
            body.strokeColor = SceneColor.darker(mid, 0.38).withAlphaComponent(0.55)
            core.fillColor = SceneColor.lighter(top, 0.5).withAlphaComponent(0.85)
            drops.fillColor = mid
            baseAlpha = CGFloat(min(1, max(0.62, liquid.opacity + 0.12)))
            thick = SceneStream.isThick(liquid.id)
            fizzy = liquid.fizzy
            widthScale = SceneStream.baseWidthScale * (thick ? 1.6 : 1)
            wobble = thick ? 0.16 : (liquid.id == .sand ? 0.02 : 0.05)
        }
        if points.isEmpty && droplets.isEmpty {
            if !root.isHidden { clear() }
            return
        }
        root.isHidden = false
        body.alpha = baseAlpha
        drops.alpha = baseAlpha
        core.alpha = min(1, baseAlpha + 0.15)
        spec.alpha = min(1, baseAlpha + 0.1)

        let bodyPath = CGMutablePath()
        let corePath = CGMutablePath()
        let specPath = CGMutablePath()
        let dropPath = CGMutablePath()
        let t = CGFloat(time)

        if !points.isEmpty {
            var pts: [CGPoint] = []
            var ws: [CGFloat] = []
            pts.reserveCapacity(points.count)
            ws.reserveCapacity(points.count)
            for p in points {
                pts.append(p.position)
                ws.append(displayWidth(p.width))
            }
            for run in ScenePaths.runs(pts, gap: 54) {
                let rp = Array(pts[run])
                let rw = Array(ws[run])
                if rp.count == 1 {
                    let r = rw[0] * 0.5
                    dropPath.addEllipse(in: CGRect(x: rp[0].x - r, y: rp[0].y - r, width: r * 2, height: r * 2))
                    continue
                }
                let smoothed = ScenePaths.smooth(rp, widths: rw, maxStep: 6)
                var sPts = smoothed.points
                let sWs = smoothed.widths
                ScenePaths.wobble(&sPts, widths: sWs, amplitude: wobble, time: t)
                let s = (points: sPts, widths: sWs)
                ScenePaths.addRibbon(bodyPath, points: s.points, widths: s.widths)
                ScenePaths.addRibbon(corePath, points: s.points, widths: s.widths, widthScale: 0.36, shift: -0.15,
                                     minHalfWidth: 0.4)
                ScenePaths.addRibbon(specPath, points: s.points, widths: s.widths, widthScale: 0.09, shift: -0.27,
                                     minHalfWidth: 0.35)
                if fizzy && s.points.count >= 6 {
                    // A few bubbles riding up the stream.
                    let m = s.points.count
                    for k in 0..<4 {
                        var u = (t * 0.9 + CGFloat(k) * 0.25).truncatingRemainder(dividingBy: 1)
                        u = 1 - u
                        let idx = min(m - 1, max(0, Int(u * CGFloat(m - 1))))
                        let c = s.points[idx]
                        let r = max(1, s.widths[idx] * 0.12)
                        corePath.addEllipse(in: CGRect(x: c.x + s.widths[idx] * 0.12 - r, y: c.y - r, width: r * 2, height: r * 2))
                    }
                }
            }
            // Thick drinks fold over themselves where they land.
            if thick, let land = landing, let last = pts.last, let lw = ws.last, abs(last.y - land.y) < 40 {
                let w = max(6, lw)
                for k in 0..<3 {
                    let ph = t * 5 + CGFloat(k) * 2.1
                    let dx = sin(ph) * w * 0.45 + CGFloat(k - 1) * w * 0.35
                    let rw = w * (0.62 + 0.12 * sin(ph * 0.7))
                    let rh = w * 0.38
                    let cy = land.y + 1.5 + CGFloat(k) * w * 0.12
                    let rect = CGRect(x: land.x + dx - rw, y: cy - rh, width: rw * 2, height: rh * 2)
                    bodyPath.addEllipse(in: rect)
                    corePath.addEllipse(in: rect.insetBy(dx: rw * 0.45, dy: rh * 0.35).offsetBy(dx: -rw * 0.2, dy: rh * 0.25))
                }
            }
        }
        for d in droplets {
            let r = max(0.9, d.radius * min(1.4, widthScale))
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
}
