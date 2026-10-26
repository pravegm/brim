import CoreGraphics
import SwiftUI

// MARK: - World ↔ screen

/// Maps world points (SpriteKit, origin bottom-left, y up) to SwiftUI points of the play canvas (origin top-left), for
/// the one 670 × 952 world aspect-FILLED into the canvas (GameScene.scaleMode = .aspectFill: the scene is centred and
/// the overflowing sides are cropped). Pure; tested.
struct WorldMapper: Equatable {
    var canvas: CGSize
    var world: CGSize

    init(canvas: CGSize, world: CGSize = CGSize(width: WorldLayout.worldWidth, height: WorldLayout.worldHeight)) {
        self.canvas = canvas
        self.world = world
    }

    var scale: CGFloat {
        guard world.width > 0, world.height > 0 else { return 1 }
        return max(canvas.width / world.width, canvas.height / world.height)
    }

    private var origin: CGPoint {
        let s = scale
        return CGPoint(x: (canvas.width - world.width * s) / 2, y: (canvas.height - world.height * s) / 2)
    }

    /// Screen point (canvas, from the top-left) of a world point.
    func point(_ p: CGPoint) -> CGPoint {
        let s = scale, o = origin
        return CGPoint(x: o.x + p.x * s, y: o.y + (world.height - p.y) * s)
    }

    /// Screen y (from the top) of a world height.
    func y(_ worldY: CGFloat) -> CGFloat { point(CGPoint(x: 0, y: worldY)).y }

    /// Screen x of a world x.
    func x(_ worldX: CGFloat) -> CGFloat { point(CGPoint(x: worldX, y: 0)).x }

    /// Screen rect of a world rect.
    func rect(_ r: CGRect) -> CGRect {
        let a = point(CGPoint(x: r.minX, y: r.maxY))
        let b = point(CGPoint(x: r.maxX, y: r.minY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Screen length of a world length.
    func length(_ worldLength: CGFloat) -> CGFloat { worldLength * scale }
}

// MARK: - Pose

/// What the display should show, from the canvas shape and the hinge.
enum DevicePose: String, Equatable {
    /// Tabletop on a Duo (portrait canvas, fold across), or any portrait phone: the game and its screens.
    case play
    /// Duo with a landscape canvas (book pose): "Turn me so the fold runs side to side, then lay me flat".
    case standUp = "book"
    /// Duo shut (hinge ≤ 15°, released at ≥ 20°) or the small cover display: "Open me to pour".
    case cover
}

/// The pose rules (ROUND-2 App P0 b). Pure; tested.
enum PoseRule {
    /// The Duo cover display is 466 × 678 pt; its inner canvas 669 × 951 / 951 × 669. Anything whose long side is
    /// under this, on a device with a hinge, is the cover.
    static let coverMaxSide: CGFloat = 760

    /// Both Duo displays are ~0.7 wide-to-tall; other iPhones ~0.46. The inner display is ≥ 600 pt on its short side.
    static func looksLikeDuoInner(_ size: CGSize) -> Bool {
        let short = min(size.width, size.height)
        let long = max(size.width, size.height)
        guard long > 0 else { return false }
        return short / long > 0.62 && short >= 600
    }

    /// QA-5 P1-1: a multitasking window (Split View, Slide Over, a resized window on the Duo's inner display, possible
    /// since Release dropped UIRequiresFullScreen) is smaller than its screen. Sorted sides, so rotation order doesn't
    /// matter. Pure.
    static func isWindowed(canvas: CGSize, screen: CGSize?) -> Bool {
        guard let screen, screen.width > 10, screen.height > 10, canvas.width > 10, canvas.height > 10 else { return false }
        let c = (min(canvas.width, canvas.height), max(canvas.width, canvas.height))
        let s = (min(screen.width, screen.height), max(screen.width, screen.height))
        return c.0 < s.0 - 2 || c.1 < s.1 - 2
    }

    /// `screen`: the window scene's screen. The cover is a screen size, not a window size: a Split View half of the
    /// inner display (≈475 × 669) is nearly the cover display's 466 × 678, so the canvas alone can't tell them apart.
    /// A window on the inner display plays like any iPhone (touch, no fold: hinge play makes no sense in a shared
    /// window).
    static func pose(canvas: CGSize, hingeSeen: Bool, isShut: Bool, bookTouchOverride: Bool,
                     screen: CGSize? = nil) -> DevicePose {
        if hingeSeen && isShut { return .cover }
        let display = screen ?? canvas
        if hingeSeen && display.width > 10 && display.height > 10 && max(display.width, display.height) < coverMaxSide {
            return .cover
        }
        if isWindowed(canvas: canvas, screen: screen) { return .play }
        if canvas.width > canvas.height && !bookTouchOverride && (hingeSeen || looksLikeDuoInner(canvas)) {
            return .standUp
        }
        return .play
    }

    /// A horizontal fold runs across the middle of a portrait Duo inner display (never in a multitasking window).
    static func hasFold(canvas: CGSize, hingeSeen: Bool, screen: CGSize? = nil) -> Bool {
        if isWindowed(canvas: canvas, screen: screen) { return false }
        guard canvas.height > canvas.width else { return false }
        if hingeSeen { return max(canvas.width, canvas.height) >= coverMaxSide }
        return looksLikeDuoInner(canvas)
    }

    /// The game canvas: the whole screen when it's no wider than the world (0.704 wide-to-tall: every phone, the Duo's
    /// tabletop); otherwise a centred world-shaped column (book pose with "Play with touch instead", a wide Split View
    /// window, which would otherwise crop the counter and the HUD).
    static func playRect(in canvas: CGSize) -> CGRect {
        let worldWide = (canvas.height * WorldLayout.worldWidth / WorldLayout.worldHeight).rounded(.up)
        guard canvas.width > worldWide else { return CGRect(origin: .zero, size: canvas) }
        let width = min(canvas.width, (canvas.height * 0.70).rounded())
        return CGRect(x: ((canvas.width - width) / 2).rounded(), y: 0, width: width, height: canvas.height)
    }
}

// MARK: - Live anchors (where the jug and the active glass are, for hints and callouts)

/// World-space anchors published with the HUD (≤ 15 Hz).
struct PlayAnchors: Equatable {
    /// Bounding box of the jug's outline (world), padded for the walls and handle the art adds.
    var jug: CGRect
    /// The glass under the spout, if any.
    var glass: GlassAnchor?
    /// REVIEW-3 P1-1: the next glass waiting on the counter (world, glass and coaster), if any. Callouts and hints
    /// treat it as occupied. From `GameScene.waitingGlassWorldFrame` when the scene has one, else the snapshot.
    var waiting: CGRect? = nil
}

struct GlassAnchor: Equatable {
    var id: Int
    /// Centre line x (world).
    var x: CGFloat
    /// The fill line's world y and the outer half-width of the glass there.
    var lineY: CGFloat
    var halfWidthAtLine: CGFloat
    /// World y of the rim and of the counter (base).
    var rimY: CGFloat
    var baseY: CGFloat
    var filling: Bool
}

enum AnchorMath {
    /// Half-width of a glass profile at a height above the inner floor (linear between profile points).
    static func halfWidth(_ shape: GlassShape, at height: CGFloat) -> CGFloat {
        let p = shape.profile
        guard let first = p.first else { return 0 }
        if height <= first.y { return first.x }
        if p.count > 1 {
            for i in 1..<p.count {
                let a = p[i - 1], b = p[i]
                if height <= b.y {
                    let span = max(b.y - a.y, 0.0001)
                    return a.x + (b.x - a.x) * (height - a.y) / span
                }
            }
        }
        return p.last?.x ?? first.x
    }

    static func anchors(_ s: GameSnapshot, layout: WorldLayout) -> PlayAnchors {
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in s.jug.outline {
            minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let jug: CGRect
        if minX <= maxX && minY <= maxY {
            // Walls + handle the art draws around the interior outline.
            jug = CGRect(x: minX - 34, y: minY - 14, width: maxX - minX + 68, height: maxY - minY + 28)
        } else {
            jug = CGRect(x: layout.jugPivot.x - 110, y: layout.jugPivot.y - 130, width: 220, height: 250)
        }
        var glass: GlassAnchor?
        if let g = s.glasses.first(where: { $0.phase == .filling })
            ?? s.glasses.first(where: { $0.phase == .arriving && !$0.isWaitingInSlot }) {
            let floor = layout.counterY + g.shape.baseThickness
            glass = GlassAnchor(id: g.id, x: g.x, lineY: floor + g.lineHeight,
                                halfWidthAtLine: halfWidth(g.shape, at: g.lineHeight) + g.shape.wall,
                                rimY: floor + g.shape.interiorHeight, baseY: layout.counterY,
                                filling: g.phase == .filling)
        }
        var waiting: CGRect?
        if let w = s.glasses.first(where: { $0.isWaitingInSlot }) {
            waiting = waitingFrame(w, layout: layout)
        }
        return PlayAnchors(jug: jug, glass: glass, waiting: waiting)
    }

    /// The waiting glass's world frame at full size (conservative: the scene may draw it smaller), with its coaster.
    static func waitingFrame(_ g: GlassState, layout: WorldLayout) -> CGRect {
        let half = (g.shape.profile.map { $0.x }.max() ?? 40) + g.shape.wall
        let height = g.shape.baseThickness + g.shape.interiorHeight
        // The coaster is ~120 pt wide and reaches ~16 pt under the counter line.
        let width = max(2 * half, 120)
        return CGRect(x: g.x - width / 2, y: layout.counterY - 16, width: width, height: height + 16)
    }

    /// Rounds world values to 2 pt so the HUD only republishes on visible changes.
    static func quantized(_ a: PlayAnchors) -> PlayAnchors {
        func q(_ v: CGFloat) -> CGFloat { (v / 2).rounded() * 2 }
        func qr(_ r: CGRect) -> CGRect { CGRect(x: q(r.minX), y: q(r.minY), width: q(r.width), height: q(r.height)) }
        var out = a
        out.jug = qr(a.jug)
        if var g = a.glass {
            g.x = q(g.x); g.lineY = q(g.lineY); g.halfWidthAtLine = q(g.halfWidthAtLine); g.rimY = q(g.rimY)
            out.glass = g
        }
        out.waiting = a.waiting.map { qr($0) }
        return out
    }
}

// MARK: - "Fill to here" placement (REVIEW-3 P1-1)

/// Where the "Fill to here" pill goes: beside the glass at its line (right first: on the Duo that's the free counter
/// to the right of the tab), else above the rim, never over the waiting glass, never off screen, never on the fold.
/// Pure; tested.
enum CalloutPlacement {
    enum Side: Equatable { case right, left, above }

    static let pillSize = CGSize(width: 128, height: 30)
    /// Clear room past the glass wall on the right, for the scene's fill-line tab.
    static let tabRoom: CGFloat = 22

    static func place(glass: GlassAnchor, waiting: CGRect?, info: CanvasInfo) -> (center: CGPoint, side: Side) {
        let m = info.mapper
        let size = pillSize
        let minY = info.hasFold ? info.bottomHalfTop + 8 + size.height / 2 : info.hudTop + HUDMetrics.rowHeight + 8
        let lineY = max(m.y(glass.lineY), minY)
        let left = m.x(glass.x - glass.halfWidthAtLine)
        let right = m.x(glass.x + glass.halfWidthAtLine)
        let blocked = waiting.map { m.rect($0).insetBy(dx: -6, dy: -6) }
        let minX = info.sidePad, maxX = info.size.width - info.sidePad
        func fits(_ c: CGPoint) -> Bool {
            let r = CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
            if r.minX < minX - 0.5 || r.maxX > maxX + 0.5 { return false }
            if c.y < minY - 0.5 { return false }
            if let blocked, r.intersects(blocked) { return false }
            return true
        }
        let onRight = CGPoint(x: right + tabRoom + size.width / 2, y: lineY)
        if fits(onRight) { return (onRight, .right) }
        let onLeft = CGPoint(x: left - 10 - size.width / 2, y: lineY)
        if fits(onLeft) { return (onLeft, .left) }
        // Above the rim, centred on the glass (pulled inside the screen edges).
        let rimY = m.y(glass.rimY)
        let x = min(max(m.x(glass.x), minX + size.width / 2), maxX - size.width / 2)
        let above = CGPoint(x: x, y: max(rimY - 14 - size.height / 2, minY))
        return (above, .above)
    }
}

// MARK: - HUD metrics

enum HUDMetrics {
    /// The one HUD row's height (≤ 56 pt, REVIEW-1 P0-2).
    static let rowHeight: CGFloat = 52
}

// MARK: - Placing a card beside something without covering it

enum CardPlacement {
    /// Where a card of `size` goes beside `avoid` (screen rect) within `bounds`: the side with more room if it fits,
    /// vertically centred on `avoid` (clamped into `bounds`). nil = neither side fits.
    static func beside(_ avoid: CGRect, size: CGSize, in bounds: CGRect, gap: CGFloat = 14) -> CGPoint? {
        let leftRoom = avoid.minX - gap - bounds.minX
        let rightRoom = bounds.maxX - (avoid.maxX + gap)
        let y = min(max(avoid.midY, bounds.minY + size.height / 2), bounds.maxY - size.height / 2)
        guard bounds.height >= size.height else { return nil }
        if leftRoom >= size.width && leftRoom >= rightRoom {
            return CGPoint(x: avoid.minX - gap - size.width / 2, y: y)
        }
        if rightRoom >= size.width {
            return CGPoint(x: avoid.maxX + gap + size.width / 2, y: y)
        }
        if leftRoom >= size.width {
            return CGPoint(x: avoid.minX - gap - size.width / 2, y: y)
        }
        return nil
    }
}
