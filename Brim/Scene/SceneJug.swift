import SpriteKit
import UIKit

/// The pouring vessel on the raised half, in the app icon's art language (REVIEW-1 P1-9): a clear glass body so the
/// player can read the level, a thick ink outline, a ceramic (or chrome / steel) accent on the rim, handle and foot,
/// a glossy specular streak and a decal on the belly. One dressing per venue (`VesselStyle`, P1-6).
///
/// Static parts are built once per jug shape in jug-local space and rotated as a group; the liquid is redrawn every
/// frame from the snapshot's world polygon, plus a short "spout sheet" that joins the liquid to the stream at the lip
/// (P0-4: the stream visibly comes out of the body).
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
    private let rimBand: SKShapeNode
    private let rimBandShine: SKShapeNode
    private let rim: SKShapeNode
    private let shine: SKShapeNode
    private let shineDot: SKShapeNode
    private let metalLines: SKShapeNode
    private let decal: SKSpriteNode
    private let lipGlint: SKShapeNode

    private var localOutline: [CGPoint] = []
    /// Angle of the outline's first edge in the cached local frame (lets us follow outlines Core rotates further,
    /// e.g. the sand pile, without rebuilding every frame).
    private var baseEdgeAngle: CGFloat = 0
    private var liquidID: LiquidID?
    private var styleKey = ""
    private var style: VesselStyle
    private let wall: CGFloat = 9

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
        rimBand = SKShapeNode()
        rimBandShine = SKShapeNode()
        rim = SKShapeNode()
        shine = SKShapeNode()
        shineDot = SKShapeNode()
        metalLines = SKShapeNode()
        decal = SKSpriteNode()
        lipGlint = SKShapeNode()

        let ink = SceneColor.ink
        shadow.fillColor = ink.withAlphaComponent(0.10)
        shadow.strokeColor = .clear
        shadow.zPosition = 0

        backFrame.zPosition = 1
        liquid.zPosition = 2
        surface.zPosition = 2.5
        spoutSheet.zPosition = 2.4
        frontFrame.zPosition = 3

        handleOutline.strokeColor = ink.withAlphaComponent(0.8)
        handleOutline.lineWidth = 19
        handleOutline.lineCap = .round
        handleOutline.fillColor = .clear
        handleOutline.zPosition = 0
        handleBody.lineWidth = 13
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
        backFrame.addChild(handleOutline)
        backFrame.addChild(handleBody)
        backFrame.addChild(handleShine)
        backFrame.addChild(interior)

        liquid.fillColor = .white
        liquid.strokeColor = .clear
        surface.fillColor = .clear
        surface.lineWidth = 3
        surface.lineCap = .round
        spoutSheet.strokeColor = .clear
        spoutSheet.isHidden = true

        footBand.strokeColor = .clear
        footBand.zPosition = -0.1
        wallBody.lineWidth = wall
        wallBody.lineCap = .round
        wallBody.lineJoin = .round
        wallBody.fillColor = .clear
        wallBody.zPosition = 0
        wallOuter.strokeColor = ink.withAlphaComponent(0.78)
        wallOuter.lineWidth = 3
        wallOuter.lineCap = .round
        wallOuter.lineJoin = .round
        wallOuter.fillColor = .clear
        wallOuter.zPosition = 0.15
        wallInner.strokeColor = UIColor(white: 1, alpha: 0.75)
        wallInner.lineWidth = 1.5
        wallInner.lineJoin = .round
        wallInner.fillColor = .clear
        wallInner.zPosition = 0.1
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
        rim.strokeColor = UIColor(white: 1, alpha: 0.9)
        rim.fillColor = UIColor(white: 1, alpha: 0.08)
        rim.lineWidth = 2.4
        rim.zPosition = 0.3
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
        metalLines.zPosition = 0.35
        decal.zPosition = 0.45
        lipGlint.fillColor = UIColor(white: 1, alpha: 0.95)
        lipGlint.strokeColor = .clear
        lipGlint.zPosition = 0.5
        lipGlint.path = CGPath(ellipseIn: CGRect(x: -2.6, y: -2.6, width: 5.2, height: 5.2), transform: nil)
        for n in [footBand, wallBody, wallInner, wallOuter, rimBand, rimBandShine, rim, metalLines, shine, shineDot] {
            frontFrame.addChild(n)
        }
        frontFrame.addChild(decal)
        frontFrame.addChild(lipGlint)

        root.addChild(shadow)
        root.addChild(backFrame)
        root.addChild(liquid)
        root.addChild(spoutSheet)
        root.addChild(surface)
        root.addChild(frontFrame)
        applyStyleColors()
    }

    /// Venue dressing. Cheap to call repeatedly; rebuilds only when it changes.
    func setStyle(_ s: VesselStyle) {
        let key = "\(s.decal.rawValue)-\(s.accent.hashValue)-\(s.metallic)-\(s.glassTint.hashValue)"
        if key == styleKey { return }
        styleKey = key
        style = s
        applyStyleColors()
        localOutline = []          // force a rebuild (decal, metal lines)
    }

    private func applyStyleColors() {
        handleBody.strokeColor = style.accent
        interior.fillColor = style.glassTint
        footBand.fillColor = style.accent
        wallBody.strokeColor = style.wall
        rimBand.strokeColor = style.accent
        metalLines.isHidden = !style.metallic
    }

    func update(_ j: JugState, streamWidth: CGFloat) {
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

        backFrame.position = j.pivot
        backFrame.zRotation = -rad
        frontFrame.position = j.pivot
        frontFrame.zRotation = -rad
        shadow.position = CGPoint(x: j.pivot.x + 8, y: j.pivot.y - 10)
        shadow.zRotation = -rad
        lipGlint.position = CGPoint(x: lipLocal.x, y: lipLocal.y + 1)
        lipGlint.alpha = CGFloat(min(1, 0.4 + j.flow * 2))

        // Liquid (world polygon from Core, already level).
        if liquidID != j.liquid.id {
            liquidID = j.liquid.id
            liquid.fillTexture = SceneArt.liquidTexture(j.liquid)
            liquid.fillColor = .white
            let top = SceneColor.opaque(j.liquid.top.skColor)
            surface.strokeColor = SceneColor.lighter(top, 0.6)
            spoutSheet.fillColor = SceneColor.mix(SceneColor.opaque(j.liquid.bottom.skColor), top, 0.65)
        }
        if j.liquidPolygon.count >= 3 && j.fill > 0.0005 {
            liquid.isHidden = false
            liquid.alpha = CGFloat(max(0.86, j.liquid.opacity))
            liquid.path = ScenePaths.polygon(j.liquidPolygon)
            var maxY = -CGFloat.greatestFiniteMagnitude
            for p in j.liquidPolygon { maxY = max(maxY, p.y) }
            var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
            for p in j.liquidPolygon where p.y >= maxY - 0.75 {
                minX = min(minX, p.x)
                maxX = max(maxX, p.x)
            }
            if maxX - minX > 6 {
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

    /// While pouring, a tapered sheet of liquid runs from the body's nearest liquid edge to the lip, so the stream
    /// is visibly fed by the jug (REVIEW-1 P0-4).
    private func updateSpoutSheet(_ j: JugState, streamWidth: CGFloat) {
        guard j.flow > 0.015, streamWidth > 0.5 else {
            spoutSheet.isHidden = true
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
        let w = max(3, streamWidth)
        let path = CGMutablePath()
        ScenePaths.addRibbon(path, points: [q, mid, j.lip], widths: [w * 1.6, w * 1.25, w])
        spoutSheet.path = path
        spoutSheet.isHidden = false
        spoutSheet.alpha = CGFloat(max(0.86, j.liquid.opacity))
    }

    private func needsRebuild(_ local: [CGPoint]) -> Bool {
        if local.count != localOutline.count { return true }
        for i in 0..<local.count {
            if abs(local[i].x - localOutline[i].x) > 0.75 || abs(local[i].y - localOutline[i].y) > 0.75 { return true }
        }
        return false
    }

    /// Builds every static part in jug-local coordinates (pivot at the origin).
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

        // Ceramic rim band around the top ~14 % (mouth + spout), and a foot band at the bottom ~9 %.
        let bandLevel = b.maxY - b.height * 0.14
        rimBand.path = ScenePaths.polylineAbove(mid, order: order, level: bandLevel)
        rimBandShine.path = ScenePaths.polylineAbove(ScenePaths.offsetPolygon(local, by: wall * 0.3), order: order,
                                                     level: bandLevel + 4)
        let foot = ScenePaths.clip(outer, level: b.minY + b.height * 0.09, below: true)
        if foot.count >= 3 {
            footBand.path = ScenePaths.polygon(foot)
            footBand.isHidden = false
        } else {
            footBand.isHidden = true
        }

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

        // Handle on the side opposite the lip: a chunky ceramic loop with an ink keyline.
        let side: CGFloat = lip.x >= b.midX ? -1 : 1
        let yTop = b.minY + b.height * 0.78
        let yBot = b.minY + b.height * 0.30
        let xTop = ScenePaths.xOnPolygon(outer, atY: yTop, rightmost: side > 0) ?? (side > 0 ? b.maxX : b.minX)
        let xBot = ScenePaths.xOnPolygon(outer, atY: yBot, rightmost: side > 0) ?? (side > 0 ? b.maxX : b.minX)
        let bulge = max(32, b.width * 0.36)
        let handle = CGMutablePath()
        handle.move(to: CGPoint(x: xTop - side * 5, y: yTop))
        handle.addCurve(to: CGPoint(x: xBot - side * 5, y: yBot),
                        control1: CGPoint(x: xTop + side * bulge, y: yTop + 18),
                        control2: CGPoint(x: xBot + side * bulge * 0.92, y: yBot - 14))
        handleOutline.path = handle
        handleBody.path = handle
        let shinePath = CGMutablePath()
        shinePath.move(to: CGPoint(x: xTop + side * bulge * 0.32, y: yTop + 7))
        shinePath.addQuadCurve(to: CGPoint(x: xTop + side * bulge * 0.62, y: yTop - b.height * 0.13),
                               control: CGPoint(x: xTop + side * bulge * 0.6, y: yTop + 5))
        handleShine.path = shinePath

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

        // Brushed-metal hairlines (chrome soda jug, steel shake tin).
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

        // The belly decal (the icon's lemon roundel on the Lemonade Stand jug).
        let dia = min(70, max(30, b.width * 0.36))
        let art = SceneArt.decal(style.decal, accent: style.accent, diameter: dia)
        decal.texture = art.texture
        decal.size = art.size
        let decalY = b.minY + b.height * 0.42
        let leftX = ScenePaths.xOnPolygon(local, atY: decalY, rightmost: false) ?? b.minX
        let rightX = ScenePaths.xOnPolygon(local, atY: decalY, rightmost: true) ?? b.maxX
        let cx = leftX + (rightX - leftX) * (side < 0 ? 0.56 : 0.44)
        decal.position = CGPoint(x: cx, y: decalY)
        decal.zRotation = -0.08
    }
}
