import SpriteKit
import UIKit

/// The pour: a smooth ribbon (Catmull–Rom through the stream particles, offset ± width/2 along the normals) with a
/// lighter core highlight, plus free droplets. Three shape nodes total; paths are rebuilt each frame.
@MainActor
final class SceneStream {
    let root: SKNode
    private let body: SKShapeNode
    private let core: SKShapeNode
    private let drops: SKShapeNode
    private var liquidID: LiquidID?
    private var baseAlpha: CGFloat = 1

    init() {
        root = SKNode()
        body = SKShapeNode()
        core = SKShapeNode()
        drops = SKShapeNode()
        body.zPosition = 0
        core.zPosition = 1
        drops.zPosition = 0.5
        body.lineWidth = 1
        core.strokeColor = .clear
        core.lineWidth = 0
        drops.lineWidth = 0
        drops.strokeColor = .clear
        root.addChild(body)
        root.addChild(drops)
        root.addChild(core)
    }

    func clear() {
        body.path = nil
        core.path = nil
        drops.path = nil
        root.isHidden = true
    }

    func update(points: [StreamPoint], droplets: [Droplet], liquid: Liquid) {
        if liquidID != liquid.id {
            liquidID = liquid.id
            let top = SceneColor.opaque(liquid.top.skColor)
            let bottom = SceneColor.opaque(liquid.bottom.skColor)
            let mid = SceneColor.mix(bottom, top, 0.6)
            body.fillColor = mid
            body.strokeColor = SceneColor.darker(mid, 0.3).withAlphaComponent(0.35)
            core.fillColor = SceneColor.lighter(top, 0.55).withAlphaComponent(0.8)
            drops.fillColor = mid
            baseAlpha = CGFloat(min(1, max(0.45, liquid.opacity)))
        }
        if points.isEmpty && droplets.isEmpty {
            if !root.isHidden { clear() }
            return
        }
        root.isHidden = false
        body.alpha = baseAlpha
        drops.alpha = baseAlpha
        core.alpha = min(1, baseAlpha + 0.2)

        let bodyPath = CGMutablePath()
        let corePath = CGMutablePath()
        let dropPath = CGMutablePath()

        if !points.isEmpty {
            var pts: [CGPoint] = []
            var ws: [CGFloat] = []
            pts.reserveCapacity(points.count)
            ws.reserveCapacity(points.count)
            for p in points {
                pts.append(p.position)
                ws.append(max(1.2, p.width))
            }
            for run in ScenePaths.runs(pts, gap: 54) {
                let rp = Array(pts[run])
                let rw = Array(ws[run])
                if rp.count == 1 {
                    let r = rw[0] * 0.5
                    dropPath.addEllipse(in: CGRect(x: rp[0].x - r, y: rp[0].y - r, width: r * 2, height: r * 2))
                    continue
                }
                let s = ScenePaths.smooth(rp, widths: rw, maxStep: 6)
                ScenePaths.addRibbon(bodyPath, points: s.points, widths: s.widths)
                ScenePaths.addRibbon(corePath, points: s.points, widths: s.widths, widthScale: 0.3, shift: -0.17,
                                     minHalfWidth: 0.35)
            }
        }
        for d in droplets {
            let r = max(0.8, d.radius)
            // Stretch slightly along the velocity so fast drops read as falling.
            let speed = hypot(d.velocity.dx, d.velocity.dy)
            if speed > 260 {
                let stretch = min(2.2, 1 + speed / 1400)
                let ang = atan2(d.velocity.dy, d.velocity.dx)
                let t = CGAffineTransform(translationX: d.position.x, y: d.position.y).rotated(by: ang).scaledBy(x: stretch, y: 1)
                dropPath.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: t)
            } else {
                dropPath.addEllipse(in: CGRect(x: d.position.x - r, y: d.position.y - r, width: r * 2, height: r * 2))
            }
        }
        body.path = bodyPath.isEmpty ? nil : bodyPath
        core.path = corePath.isEmpty ? nil : corePath
        drops.path = dropPath.isEmpty ? nil : dropPath
    }
}
