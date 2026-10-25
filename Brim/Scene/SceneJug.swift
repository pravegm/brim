import SpriteKit
import UIKit

/// The glass jug on the raised half. Static parts (walls, handle, highlights) are built once per jug shape in
/// jug-local space and rotated as a group; the liquid is redrawn every frame from the snapshot's world polygon.
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

    // front (in front of the liquid)
    private let wallBody: SKShapeNode
    private let wallOuter: SKShapeNode
    private let wallInner: SKShapeNode
    private let rim: SKShapeNode
    private let shine: SKShapeNode
    private let shineDot: SKShapeNode
    private let lipGlint: SKShapeNode

    private var localOutline: [CGPoint] = []
    private var liquidID: LiquidID?
    private let wall: CGFloat = 9

    init() {
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
        wallBody = SKShapeNode()
        wallOuter = SKShapeNode()
        wallInner = SKShapeNode()
        rim = SKShapeNode()
        shine = SKShapeNode()
        shineDot = SKShapeNode()
        lipGlint = SKShapeNode()

        let ink = SceneColor.ink
        shadow.fillColor = ink.withAlphaComponent(0.09)
        shadow.strokeColor = .clear
        shadow.zPosition = 0

        backFrame.zPosition = 1
        liquid.zPosition = 2
        surface.zPosition = 2.5
        frontFrame.zPosition = 3

        handleOutline.strokeColor = ink.withAlphaComponent(0.26)
        handleOutline.lineWidth = 15.5
        handleOutline.lineCap = .round
        handleOutline.fillColor = .clear
        handleOutline.zPosition = 0
        handleBody.strokeColor = SceneColor.jugGlass.withAlphaComponent(0.95)
        handleBody.lineWidth = 12
        handleBody.lineCap = .round
        handleBody.fillColor = .clear
        handleBody.zPosition = 0.1
        handleShine.strokeColor = UIColor(white: 1, alpha: 0.85)
        handleShine.lineWidth = 3
        handleShine.lineCap = .round
        handleShine.fillColor = .clear
        handleShine.zPosition = 0.2
        interior.fillColor = UIColor(white: 1, alpha: 0.34)
        interior.strokeColor = .clear
        interior.zPosition = 0.3
        backFrame.addChild(handleOutline)
        backFrame.addChild(handleBody)
        backFrame.addChild(handleShine)
        backFrame.addChild(interior)

        liquid.fillColor = .white
        liquid.strokeColor = .clear
        surface.fillColor = .clear
        surface.lineWidth = 2.6
        surface.lineCap = .round

        wallBody.strokeColor = SceneColor.jugGlass.withAlphaComponent(0.72)
        wallBody.lineWidth = wall
        wallBody.lineCap = .round
        wallBody.lineJoin = .round
        wallBody.fillColor = .clear
        wallBody.zPosition = 0
        wallOuter.strokeColor = ink.withAlphaComponent(0.30)
        wallOuter.lineWidth = 1.7
        wallOuter.lineCap = .round
        wallOuter.lineJoin = .round
        wallOuter.fillColor = .clear
        wallOuter.zPosition = 0.1
        wallInner.strokeColor = UIColor(white: 1, alpha: 0.6)
        wallInner.lineWidth = 1.3
        wallInner.lineJoin = .round
        wallInner.fillColor = .clear
        wallInner.zPosition = 0.2
        rim.strokeColor = UIColor(white: 1, alpha: 0.85)
        rim.fillColor = UIColor(white: 1, alpha: 0.10)
        rim.lineWidth = 2.2
        rim.zPosition = 0.3
        shine.strokeColor = UIColor(white: 1, alpha: 0.55)
        shine.lineWidth = 5
        shine.lineCap = .round
        shine.fillColor = .clear
        shine.zPosition = 0.4
        shineDot.strokeColor = UIColor(white: 1, alpha: 0.5)
        shineDot.lineWidth = 4
        shineDot.lineCap = .round
        shineDot.fillColor = .clear
        shineDot.zPosition = 0.4
        lipGlint.fillColor = UIColor(white: 1, alpha: 0.9)
        lipGlint.strokeColor = .clear
        lipGlint.zPosition = 0.5
        lipGlint.path = CGPath(ellipseIn: CGRect(x: -2.2, y: -2.2, width: 4.4, height: 4.4), transform: nil)
        frontFrame.addChild(wallBody)
        frontFrame.addChild(wallOuter)
        frontFrame.addChild(wallInner)
        frontFrame.addChild(rim)
        frontFrame.addChild(shine)
        frontFrame.addChild(shineDot)
        frontFrame.addChild(lipGlint)

        root.addChild(shadow)
        root.addChild(backFrame)
        root.addChild(liquid)
        root.addChild(surface)
        root.addChild(frontFrame)
    }

    func update(_ j: JugState) {
        guard j.outline.count >= 3 else {
            root.isHidden = true
            return
        }
        root.isHidden = false
        let rad = CGFloat(j.angle) * .pi / 180
        var local: [CGPoint] = []
        local.reserveCapacity(j.outline.count)
        for p in j.outline { local.append(ScenePaths.toLocal(p, pivot: j.pivot, radians: rad)) }
        let lipLocal = ScenePaths.toLocal(j.lip, pivot: j.pivot, radians: rad)
        if needsRebuild(local) { rebuild(local, lip: lipLocal) }

        backFrame.position = j.pivot
        backFrame.zRotation = -rad
        frontFrame.position = j.pivot
        frontFrame.zRotation = -rad
        shadow.position = CGPoint(x: j.pivot.x + 7, y: j.pivot.y - 9)
        shadow.zRotation = -rad
        lipGlint.position = CGPoint(x: lipLocal.x, y: lipLocal.y + 1)
        lipGlint.alpha = CGFloat(min(1, 0.35 + j.flow * 2))

        // Liquid (world polygon from Core, already level).
        if liquidID != j.liquid.id {
            liquidID = j.liquid.id
            liquid.fillTexture = SceneArt.liquidTexture(j.liquid)
            liquid.fillColor = .white
            surface.strokeColor = SceneColor.lighter(SceneColor.opaque(j.liquid.top.skColor), 0.55)
        }
        if j.liquidPolygon.count >= 3 && j.fill > 0.0005 {
            liquid.isHidden = false
            liquid.alpha = CGFloat(max(0.82, j.liquid.opacity))
            liquid.path = ScenePaths.polygon(j.liquidPolygon)
            // Bright surface line along the level top edge.
            var maxY = -CGFloat.greatestFiniteMagnitude
            for p in j.liquidPolygon { maxY = max(maxY, p.y) }
            var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
            for p in j.liquidPolygon where p.y >= maxY - 0.75 {
                minX = min(minX, p.x)
                maxX = max(maxX, p.x)
            }
            if maxX - minX > 6 {
                let line = CGMutablePath()
                line.move(to: CGPoint(x: minX + 2.5, y: maxY - 1))
                line.addLine(to: CGPoint(x: maxX - 2.5, y: maxY - 1))
                surface.path = line
                surface.isHidden = false
            } else {
                surface.isHidden = true
            }
        } else {
            liquid.isHidden = true
            surface.isHidden = true
        }
    }

    private func needsRebuild(_ local: [CGPoint]) -> Bool {
        if local.count != localOutline.count { return true }
        for i in 0..<local.count {
            if abs(local[i].x - localOutline[i].x) > 0.75 || abs(local[i].y - localOutline[i].y) > 0.75 { return true }
        }
        return false
    }

    /// Builds every static part in jug-local coordinates (pivot at the origin, jug upright).
    private func rebuild(_ local: [CGPoint], lip: CGPoint) {
        localOutline = local
        let n = local.count
        let b = ScenePaths.bounds(local)
        let mid = ScenePaths.offsetPolygon(local, by: wall * 0.5)
        let outer = ScenePaths.offsetPolygon(local, by: wall)

        // The mouth: the highest, roughly horizontal edge. Leave it open so the jug doesn't look lidded.
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
        var order: [Int] = []
        if mouth >= 0 {
            for k in 1...n { order.append((mouth + k) % n) }
        } else {
            for k in 0...n { order.append(k % n) }
        }

        interior.path = ScenePaths.polygon(local)
        wallBody.path = ScenePaths.polyline(mid, order: order)
        wallOuter.path = ScenePaths.polyline(outer, order: order)
        wallInner.path = ScenePaths.polyline(local, order: order)
        shadow.path = ScenePaths.polygon(outer)

        // Rim ellipse across the mouth.
        if mouth >= 0 {
            let a = mid[mouth], c = mid[(mouth + 1) % n]
            let centre = CGPoint(x: (a.x + c.x) * 0.5, y: (a.y + c.y) * 0.5)
            let rx = abs(c.x - a.x) * 0.5
            let ry = min(9, max(4, rx * 0.15))
            rim.path = ScenePaths.polygon(ScenePaths.ellipseArc(center: centre, rx: rx, ry: ry, from: 0, to: 2 * .pi, segments: 28))
            rim.isHidden = false
        } else {
            rim.isHidden = true
        }

        // Handle on the side opposite the lip.
        let side: CGFloat = lip.x >= b.midX ? -1 : 1
        let yTop = b.minY + b.height * 0.76
        let yBot = b.minY + b.height * 0.30
        let xTop = ScenePaths.xOnPolygon(outer, atY: yTop, rightmost: side > 0) ?? (side > 0 ? b.maxX : b.minX)
        let xBot = ScenePaths.xOnPolygon(outer, atY: yBot, rightmost: side > 0) ?? (side > 0 ? b.maxX : b.minX)
        let bulge = max(30, b.width * 0.34)
        let handle = CGMutablePath()
        handle.move(to: CGPoint(x: xTop - side * 4, y: yTop))
        handle.addCurve(to: CGPoint(x: xBot - side * 4, y: yBot),
                        control1: CGPoint(x: xTop + side * bulge, y: yTop + 16),
                        control2: CGPoint(x: xBot + side * bulge * 0.92, y: yBot - 12))
        handleOutline.path = handle
        handleBody.path = handle
        let shinePath = CGMutablePath()
        shinePath.move(to: CGPoint(x: xTop + side * bulge * 0.35, y: yTop + 6))
        shinePath.addQuadCurve(to: CGPoint(x: xTop + side * bulge * 0.62, y: yTop - b.height * 0.12),
                               control: CGPoint(x: xTop + side * bulge * 0.6, y: yTop + 4))
        handleShine.path = shinePath

        // Specular streak down the left wall (light from the top-left).
        var streak: [CGPoint] = []
        for k in 0...6 {
            let y = b.minY + b.height * (0.26 + 0.44 * CGFloat(k) / 6)
            if let x = ScenePaths.xOnPolygon(local, atY: y, rightmost: false) {
                streak.append(CGPoint(x: x + 9, y: y))
            }
        }
        if streak.count >= 2 {
            let sp = CGMutablePath()
            sp.move(to: streak[0])
            ScenePaths.addSmoothCurve(sp, streak)
            shine.path = sp
            shine.isHidden = false
        } else {
            shine.isHidden = true
        }
        let dotY0 = b.minY + b.height * 0.76, dotY1 = b.minY + b.height * 0.82
        if let x0 = ScenePaths.xOnPolygon(local, atY: dotY0, rightmost: false),
           let x1 = ScenePaths.xOnPolygon(local, atY: dotY1, rightmost: false) {
            let dp = CGMutablePath()
            dp.move(to: CGPoint(x: x0 + 9, y: dotY0))
            dp.addLine(to: CGPoint(x: x1 + 9, y: dotY1))
            shineDot.path = dp
            shineDot.isHidden = false
        } else {
            shineDot.isHidden = true
        }
    }
}
