// Brim App Store creative-asset renderer (macOS host side; ci/store-placements.sh runs it, compiled with
// `xcrun swiftc` or as a script with `xcrun swift`). Draws the two optional placements Apple added on 5 Oct 2026
// (docs/appstore/header-search.md) from REAL upright iPhone Duo inner-display captures (2007 x 2853, ci/duo.sh):
//
//   store-banner --kind search --hero D1.png --out search-3840x2560.png [--extras D2.png,D4.png] [--layout hero|trio]
//   store-banner --kind header --hero D1.png --out header-3840x1646.png
//                [--guides guides.png] [--yaw 9] [--elev 27] [--tilt 17] [--headline "Lift to *pour.*"] [--sub "…"]
//
//  • The hero is an iPhone Duo in tabletop pose, drawn as a clean device silhouette (no logo, no buttons, no badge):
//    the capture's top half (rows above the fold, the jug) is mapped onto the raised half and its bottom half (the
//    glass) onto the flat half, with a real perspective camera, so the stream visibly crosses the fold. The capture's
//    pixels are only resampled (Lanczos, then a perspective warp); nothing is painted into the game picture. It is
//    always the upright capture: the top of the picture is the top of the raised half (founder's rule: nothing upside
//    down, ever).
//  • Type is the house style of ci/store-frame.swift: SF Pro Rounded (Black for the wordmark, Heavy for headlines,
//    Semibold for sub-lines), ink #2B2233 on the cream → peach brand sweep, ONE `*word*` on a brim-gold swash. The
//    wordmark is the app's BrimWordmark (Brim/UI/BrimTheme.swift): "Brim", a glowing gold fill line, a cyan drip.
//  • Composition keeps the fold and the text block on the image's vertical centre line, inside the safe areas of
//    Apple's templates (header x 1097–2743 / y 493–1154, search x 836–3004 / y 765–1795, as measured from the
//    templates; Apple publishes no numbers) as far as the art allows. --guides writes a review copy with those
//    rectangles and the iPhone-portrait side crop (8 % per side) drawn on.
//  • Output: exactly 3840 x 2560 (search) or 3840 x 1646 (header), opaque sRGB PNG, no alpha channel.
// Prints one line: `store-banner: <out> <W>x<H> kind=… layout=… fold=<y> device=<rect> text=<rect> text-iphone=<yes|no>
// overlap=<yes|no> text-in-template-safe=… fold-in-template-safe=… rounded=<yes|no>` (rects in top-left pixels).
import AppKit
import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("store-banner: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

var options: [String: String] = [:]
var argv = Array(CommandLine.arguments.dropFirst())
while !argv.isEmpty {
    let key = argv.removeFirst()
    guard key.hasPrefix("--"), !argv.isEmpty else { fail("bad argument \(key)") }
    options[String(key.dropFirst(2))] = argv.removeFirst()
}
let kind = options["kind"] ?? "search"
guard kind == "search" || kind == "header" else { fail("--kind is search or header") }
guard let heroPath = options["hero"], let output = options["out"] else { fail("needs --hero and --out") }
let layout = options["layout"] ?? "hero"
func num(_ key: String, _ fallback: CGFloat) -> CGFloat {
    guard let s = options[key], let d = Double(s) else { return fallback }
    return CGFloat(d)
}

func loadImage(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(path)") }
    return image
}
let hero = loadImage(heroPath)
guard hero.width == 2007, hero.height == 2853 else {
    fail("\(heroPath) is \(hero.width)x\(hero.height); the hero must be an upright Duo inner capture, 2007x2853")
}
let extras: [CGImage] = (options["extras"] ?? "").split(separator: ",").map { loadImage(String($0)) }

let width = kind == "search" ? 3840 : 3840
let height = kind == "search" ? 2560 : 1646
let W = CGFloat(width), H = CGFloat(height)

guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { fail("no sRGB colour space") }
// noneSkipLast: an opaque RGB bitmap, so the PNG has no alpha channel (App Store Connect rejects alpha).
guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fail("no context") }
let ctx: CGContext = context
ctx.interpolationQuality = .high
ctx.setShouldAntialias(true)

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Brand palette (Brim/UI/BrimTheme.swift, ci/store-frame.swift).
let cream: UInt32 = 0xFFF4E2
let creamPeach: UInt32 = 0xFFE9CF
let peach: UInt32 = 0xFFD3B2
let ink: UInt32 = 0x2B2233
let subInk: UInt32 = 0x544760
let gold: UInt32 = 0xFFC23D
let cyan: UInt32 = 0x3FD0FF
let cyanDeep: UInt32 = 0x1FA3D6
let card: UInt32 = 0xFFFBF4
let frameHex = UInt32(options["frame"] ?? "", radix: 16) ?? 0x4A4350       // device frame: warm graphite
let glassHex: UInt32 = 0x121016                                             // the black glass round the display

/// Top-left-origin rect / point → Core Graphics' bottom-left origin.
func cg(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height) }
func cgp(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: H - p.y) }
func tl(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height) }   // CG → top-left

// MARK: Layout (top-left pixel coordinates)

struct Plan {
    var foldY: CGFloat            // where the hinge line sits (image y, top-left origin)
    var hingeX: CGFloat           // the hinge's midpoint x
    var deviceHeight: CGFloat     // projected device height in px
    var textBox: CGRect           // the text column
    var align: NSTextAlignment
    var glow: CGPoint
}

let safeArea: CGRect = kind == "header"
    ? CGRect(x: 1097, y: 493, width: 2743 - 1097, height: 1154 - 493)
    : CGRect(x: 836, y: 765, width: 3004 - 836, height: 1795 - 765)

var plan: Plan
if kind == "search" {
    if layout == "trio" {
        plan = Plan(foldY: H * 0.555, hingeX: W * 0.535, deviceHeight: H * 0.66,
                    textBox: CGRect(x: W * 0.085, y: 0, width: W * 0.30, height: H), align: .left,
                    glow: CGPoint(x: W * 0.58, y: H * 0.45))
    } else {
        plan = Plan(foldY: H * 0.55, hingeX: W * 0.672, deviceHeight: H * 0.76,
                    textBox: CGRect(x: W * 0.105, y: 0, width: W * 0.30, height: H), align: .left,
                    glow: CGPoint(x: W * 0.64, y: H * 0.45))
    }
} else {
    plan = Plan(foldY: H * 0.58, hingeX: W * 0.635, deviceHeight: H * 0.82,
                textBox: CGRect(x: W * 0.155, y: 0, width: W * 0.30, height: H), align: .left,
                glow: CGPoint(x: W * 0.60, y: H * 0.45))
}
plan.foldY = num("fold", plan.foldY / H) * H
plan.hingeX = num("hinge", plan.hingeX / W) * W
plan.deviceHeight = num("device", plan.deviceHeight / H) * H

/// Debug (--snaps <dir>): the canvas after each stage, to find which stage changed what.
var snapCount = 0
func snap(_ name: String) {
    guard let dir = options["snaps"], !dir.isEmpty, let image = ctx.makeImage() else { return }
    snapCount += 1
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "%02d-%@.png", snapCount, name))
    if let d = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
        CGImageDestinationAddImage(d, image, nil)
        _ = CGImageDestinationFinalize(d)
    }
}

// MARK: Background: the brand sweep, a gold glow behind the hero, a soft cream bloom

ctx.setFillColor(srgb(cream))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
if let sweep = CGGradient(colorsSpace: space, colors: [srgb(cream), srgb(creamPeach), srgb(peach)] as CFArray,
                          locations: [0, 0.55, 1]) {
    ctx.drawLinearGradient(sweep, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
}
if let glow = CGGradient(colorsSpace: space, colors: [srgb(gold, 0.26), srgb(gold, 0)] as CFArray, locations: [0, 1]) {
    let centre = cgp(plan.glow)
    ctx.drawRadialGradient(glow, startCenter: centre, startRadius: 0, endCenter: centre,
                           endRadius: max(W, H) * 0.42, options: [])
}
if let bloom = CGGradient(colorsSpace: space, colors: [srgb(0xFFFFFF, 0.55), srgb(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1]) {
    let centre = cgp(CGPoint(x: plan.hingeX, y: plan.foldY - plan.deviceHeight * 0.18))
    ctx.drawRadialGradient(bloom, startCenter: centre, startRadius: 0, endCenter: centre,
                           endRadius: plan.deviceHeight * 0.75, options: [])
}

snap("background")

// MARK: 3D: the Duo in tabletop pose

struct V3 {
    var x: CGFloat, y: CGFloat, z: CGFloat
    static func + (a: V3, b: V3) -> V3 { V3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    static func - (a: V3, b: V3) -> V3 { V3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    static func * (a: V3, s: CGFloat) -> V3 { V3(x: a.x * s, y: a.y * s, z: a.z * s) }
    func dot(_ b: V3) -> CGFloat { x * b.x + y * b.y + z * b.z }
    func cross(_ b: V3) -> V3 { V3(x: y * b.z - z * b.y, y: z * b.x - x * b.z, z: x * b.y - y * b.x) }
    var normalized: V3 { let l = max(sqrt(dot(self)), 1e-9); return V3(x: x / l, y: y / l, z: z / l) }
}

/// A look-at pinhole camera. World: x right, y up, z toward the viewer; the hinge line runs along x through the origin.
struct Camera {
    let c: V3, r: V3, u: V3, f: V3
    init(target: V3, distance: CGFloat, elevation: CGFloat, yaw: CGFloat) {
        let dir = V3(x: cos(elevation) * sin(yaw), y: sin(elevation), z: cos(elevation) * cos(yaw))
        c = target + dir * distance
        f = (target - c).normalized
        r = f.cross(V3(x: 0, y: 1, z: 0)).normalized
        u = r.cross(f)
    }
    func project(_ p: V3) -> CGPoint {
        let d = p - c
        let zc = max(d.dot(f), 1e-6)
        return CGPoint(x: d.dot(r) / zc, y: d.dot(u) / zc)
    }
}

let degrees = CGFloat.pi / 180
let tilt = num("tilt", kind == "header" ? 16 : 15) * degrees      // the raised half leans back this far from vertical
let elevation = num("elev", kind == "header" ? 26 : 34) * degrees
let yaw = num("yaw", kind == "header" ? 10 : 6) * degrees          // + = camera to the device's right
let camera = Camera(target: V3(x: 0, y: 150, z: 120), distance: num("distance", 2900),
                    elevation: elevation, yaw: yaw)

// Inner display, in points: 669 x 951 at 3x; the fold sits at capture row 1427 (WorldLayout crease centre, 476 pt).
let foldRow = 1427
let halfW: CGFloat = 669 / 2
let lidLen = CGFloat(foldRow) / 3
let baseLen = CGFloat(hero.height - foldRow) / 3
let bezel: CGFloat = 9
let rim: CGFloat = 2.4
let thick: CGFloat = 5.2
let bodyRadius: CGFloat = 38
let screenRadius: CGFloat = 29

/// A point on the raised half: `w` along it from the hinge, `off` along its front normal.
func lidPoint(_ u: CGFloat, _ w: CGFloat, _ off: CGFloat) -> V3 {
    V3(x: u, y: w * cos(tilt) + off * sin(tilt), z: -w * sin(tilt) + off * cos(tilt))
}
/// A point on the flat half: `w` toward the viewer from the hinge, `off` up.
func basePoint(_ u: CGFloat, _ w: CGFloat, _ off: CGFloat) -> V3 { V3(x: u, y: off, z: w) }

/// A half's outline in (u, w): square at the hinge (the body runs on round the fold), rounded at the free end.
func halfOutline(halfWidth hw: CGFloat, length: CGFloat, radius: CGFloat, steps: Int = 14) -> [CGPoint] {
    let r = min(radius, hw, length)
    var pts = [CGPoint(x: -hw, y: 0), CGPoint(x: hw, y: 0)]
    for i in 0...steps {
        let a = CGFloat(i) / CGFloat(steps) * .pi / 2
        pts.append(CGPoint(x: hw - r + r * cos(a), y: length - r + r * sin(a)))
    }
    for i in 0...steps {
        let a = .pi / 2 + CGFloat(i) / CGFloat(steps) * .pi / 2
        pts.append(CGPoint(x: -hw + r + r * cos(a), y: length - r + r * sin(a)))
    }
    return pts
}

let lidBody = halfOutline(halfWidth: halfW + bezel, length: lidLen + bezel, radius: bodyRadius)
let baseBody = halfOutline(halfWidth: halfW + bezel, length: baseLen + bezel, radius: bodyRadius)
let lidGlass = halfOutline(halfWidth: halfW + bezel - rim, length: lidLen + bezel - rim, radius: bodyRadius - rim)
let baseGlass = halfOutline(halfWidth: halfW + bezel - rim, length: baseLen + bezel - rim, radius: bodyRadius - rim)
let lidScreen = halfOutline(halfWidth: halfW, length: lidLen, radius: screenRadius)
let baseScreen = halfOutline(halfWidth: halfW, length: baseLen, radius: screenRadius)

// Fit: scale the projection so the device is plan.deviceHeight tall, with the hinge midpoint at (hingeX, foldY).
var bounds = CGRect.null
for q in lidBody { for off in [0, -thick] { let p = camera.project(lidPoint(q.x, q.y, off)); bounds = bounds.union(CGRect(origin: p, size: .zero)) } }
for q in baseBody { for off in [0, -thick] { let p = camera.project(basePoint(q.x, q.y, off)); bounds = bounds.union(CGRect(origin: p, size: .zero)) } }
let projScale = plan.deviceHeight / max(bounds.height, 1e-6)
let hingeProj = camera.project(V3(x: 0, y: 0, z: 0))
let hingeCG = cgp(CGPoint(x: plan.hingeX, y: plan.foldY))
func toImage(_ p: V3) -> CGPoint {
    let q = camera.project(p)
    return CGPoint(x: hingeCG.x + (q.x - hingeProj.x) * projScale, y: hingeCG.y + (q.y - hingeProj.y) * projScale)
}
func path(_ pts: [CGPoint], _ map: (CGPoint) -> V3) -> CGPath {
    let p = CGMutablePath()
    for (i, q) in pts.enumerated() {
        let s = toImage(map(q))
        if i == 0 { p.move(to: s) } else { p.addLine(to: s) }
    }
    p.closeSubpath()
    return p
}

/// Pixels per display point at the hinge (for line widths).
let pxPerPt = hypot(toImage(basePoint(halfW, 0, 0)).x - toImage(basePoint(-halfW, 0, 0)).x,
                    toImage(basePoint(halfW, 0, 0)).y - toImage(basePoint(-halfW, 0, 0)).y) / (2 * halfW)
var deviceRectCG = CGRect.null
for q in lidBody { for off in [0, -thick] { deviceRectCG = deviceRectCG.union(CGRect(origin: toImage(lidPoint(q.x, q.y, off)), size: .zero)) } }
for q in baseBody { for off in [0, -thick] { deviceRectCG = deviceRectCG.union(CGRect(origin: toImage(basePoint(q.x, q.y, off)), size: .zero)) } }

// MARK: Perspective warp of a capture half (Core Image: Lanczos down to about the drawn size, then the quad)

// No colour management inside Core Image: the capture is first drawn into an sRGB bitmap by Core Graphics (as
// ci/store-frame.swift draws it), then resampled number for number, so the screen keeps the capture's colours.
let ciContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .useSoftwareRenderer: true])

func srgbCopy(_ image: CGImage) -> CGImage {
    guard let c = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fail("no context") }
    c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let out = c.makeImage() else { fail("cannot copy the capture") }
    return out
}

func warp(_ image: CGImage, quad: (tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint)) -> (CGImage, CGRect)? {
    var ci = CIImage(cgImage: image, options: [.colorSpace: NSNull()])
    let drawnW = max(hypot(quad.tr.x - quad.tl.x, quad.tr.y - quad.tl.y), hypot(quad.br.x - quad.bl.x, quad.br.y - quad.bl.y))
    let drawnH = max(hypot(quad.bl.x - quad.tl.x, quad.bl.y - quad.tl.y), hypot(quad.br.x - quad.tr.x, quad.br.y - quad.tr.y))
    let kx = min(1, drawnW * 1.15 / CGFloat(image.width))
    let ky = min(1, drawnH * 1.15 / CGFloat(image.height))
    if kx < 0.999 || ky < 0.999, let f = CIFilter(name: "CILanczosScaleTransform") {
        f.setValue(ci, forKey: kCIInputImageKey)
        f.setValue(NSNumber(value: Double(ky)), forKey: kCIInputScaleKey)
        f.setValue(NSNumber(value: Double(kx / ky)), forKey: kCIInputAspectRatioKey)
        if let o = f.outputImage { ci = o }
    }
    guard let p = CIFilter(name: "CIPerspectiveTransform") else { return nil }
    p.setValue(ci, forKey: kCIInputImageKey)
    p.setValue(CIVector(cgPoint: quad.tl), forKey: "inputTopLeft")
    p.setValue(CIVector(cgPoint: quad.tr), forKey: "inputTopRight")
    p.setValue(CIVector(cgPoint: quad.br), forKey: "inputBottomRight")
    p.setValue(CIVector(cgPoint: quad.bl), forKey: "inputBottomLeft")
    guard let o = p.outputImage else { return nil }
    let rect = o.extent.integral
    guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0,
          let out = ciContext.createCGImage(o, from: rect, format: .RGBA8, colorSpace: space) else { return nil }
    // (createCGImage tags the untouched numbers as sRGB, which is what they are.)
    return (out, rect)
}

let heroRGB = srgbCopy(hero)
guard let lidHalf = heroRGB.cropping(to: CGRect(x: 0, y: 0, width: hero.width, height: foldRow)),
      let baseHalf = heroRGB.cropping(to: CGRect(x: 0, y: foldRow, width: hero.width, height: hero.height - foldRow)) else {
    fail("cannot split the capture at the fold")
}

func shade(_ hex: UInt32, _ k: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255, g = CGFloat((hex >> 8) & 0xFF) / 255, b = CGFloat(hex & 0xFF) / 255
    return CGColor(srgbRed: min(1, r * k), green: min(1, g * k), blue: min(1, b * k), alpha: alpha)
}

/// One half: back face, side walls (shaded by how much they face a light up and to the front-left), frame, black
/// glass, the capture, a faint glass sheen.
func drawHalf(body: [CGPoint], glass: [CGPoint], screen: [CGPoint], map: @escaping (CGFloat, CGFloat, CGFloat) -> V3,
              image: CGImage, lid: Bool) {
    let light = V3(x: -0.35, y: 0.85, z: 0.55).normalized
    let back = path(body) { map($0.x, $0.y, -thick) }
    ctx.addPath(back)
    ctx.setFillColor(shade(frameHex, 0.62))
    ctx.fillPath()
    for i in 0..<body.count {
        let a = body[i], b = body[(i + 1) % body.count]
        if a.y == 0 && b.y == 0 { continue }   // the hinge edge: the body runs on round the fold
        let p0 = map(a.x, a.y, 0), p1 = map(b.x, b.y, 0), p2 = map(b.x, b.y, -thick)
        let normal = (p1 - p0).cross(p2 - p1).normalized
        let lit = max(0, min(1, abs(normal.dot(light))))
        let quad = CGMutablePath()
        quad.move(to: toImage(p0)); quad.addLine(to: toImage(p1)); quad.addLine(to: toImage(p2))
        quad.addLine(to: toImage(map(a.x, a.y, -thick))); quad.closeSubpath()
        let colour = shade(frameHex, 0.70 + 0.55 * lit)
        ctx.addPath(quad); ctx.setFillColor(colour); ctx.fillPath()
        ctx.addPath(quad); ctx.setStrokeColor(colour); ctx.setLineWidth(1.2); ctx.strokePath()
    }
    let front = path(body) { map($0.x, $0.y, 0) }
    ctx.addPath(front)
    ctx.setFillColor(shade(frameHex, 1.18))
    ctx.fillPath()
    ctx.addPath(path(glass) { map($0.x, $0.y, 0) })
    ctx.setFillColor(srgb(glassHex))
    ctx.fillPath()

    // The capture. Lid: picture top = the raised half's free edge. Base: picture top = the hinge, bottom = near edge.
    let len = lid ? lidLen : baseLen
    let quad: (tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint) = lid
        ? (toImage(map(-halfW, len, 0)), toImage(map(halfW, len, 0)), toImage(map(halfW, 0, 0)), toImage(map(-halfW, 0, 0)))
        : (toImage(map(-halfW, 0, 0)), toImage(map(halfW, 0, 0)), toImage(map(halfW, len, 0)), toImage(map(-halfW, len, 0)))
    let screenPath = path(screen) { map($0.x, $0.y, 0) }
    if let result = warp(image, quad: quad) {
        let (warped, rect) = result
        ctx.saveGState()
        ctx.addPath(screenPath)
        ctx.clip()
        ctx.draw(warped, in: rect)
        // Sheen: glass, not paint. A faint diagonal light on the raised half, an even fainter one on the flat half.
        if let sheen = CGGradient(colorsSpace: space, colors: [srgb(0xFFFFFF, lid ? 0.10 : 0.05), srgb(0xFFFFFF, 0),
                                                              srgb(0xFFFFFF, 0)] as CFArray, locations: [0, 0.45, 1]) {
            ctx.drawLinearGradient(sheen, start: quad.tl, end: quad.br, options: [])
        }
        ctx.restoreGState()
    } else {
        fail("perspective warp failed")
    }
    // Crease: a whisper of shade where the display bends at the hinge.
    let crease = halfOutline(halfWidth: halfW, length: 9, radius: 0, steps: 1)
    ctx.saveGState()
    ctx.addPath(screenPath)
    ctx.clip()
    if let g = CGGradient(colorsSpace: space, colors: [srgb(0x000000, lid ? 0.16 : 0.10), srgb(0x000000, 0)] as CFArray,
                          locations: [0, 1]) {
        let a = toImage(map(0, 0, 0)), b = toImage(map(0, 9, 0))
        ctx.addPath(path(crease) { map($0.x, $0.y, 0) })
        ctx.clip()
        ctx.drawLinearGradient(g, start: a, end: b, options: [])
    }
    ctx.restoreGState()
    // Edge light on the frame.
    ctx.addPath(front)
    ctx.setStrokeColor(srgb(0xFFFFFF, 0.22))
    ctx.setLineWidth(max(1.5, pxPerPt * 0.8))   // (projScale is per projected unit, not per point: never a width)
    ctx.strokePath()
}

// MARK: Extra frames (flat cards of other real captures, layout "trio" only)

func drawCard(_ image: CGImage, centre: CGPoint, height h: CGFloat, angle: CGFloat) {
    let w = h * CGFloat(image.width) / CGFloat(image.height)
    let c = cgp(centre)
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angle)
    let r = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    let corner = w * 0.075
    let p = CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -h * 0.012), blur: h * 0.05, color: srgb(ink, 0.30))
    ctx.addPath(p); ctx.setFillColor(srgb(card)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(p); ctx.clip()
    ctx.draw(image, in: r)
    ctx.restoreGState()
    ctx.addPath(p); ctx.setStrokeColor(srgb(ink, 0.16)); ctx.setLineWidth(max(1, w * 0.004)); ctx.strokePath()
    ctx.restoreGState()
}

if layout == "trio", extras.count >= 1 {
    let ch = H * 0.44
    let x = W * 0.835
    drawCard(extras[0], centre: CGPoint(x: x, y: H * 0.285), height: ch, angle: -4 * degrees)
    if extras.count >= 2 { drawCard(extras[1], centre: CGPoint(x: x + W * 0.012, y: H * 0.725), height: ch, angle: 3.5 * degrees) }
}

snap("cards")

// MARK: Draw the Duo: contact shadow, raised half, flat half

let footprint = path(baseBody) { basePoint($0.x, $0.y, -thick) }
let lidFoot = path(lidBody) { lidPoint($0.x, $0.y, -thick) }
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: -plan.deviceHeight * 0.012, height: -plan.deviceHeight * 0.030),
              blur: plan.deviceHeight * 0.11, color: srgb(0x7A4A2A, 0.34))
ctx.addPath(footprint); ctx.addPath(lidFoot)
ctx.setFillColor(shade(frameHex, 0.62))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -plan.deviceHeight * 0.006), blur: plan.deviceHeight * 0.018,
              color: srgb(0x3A2418, 0.45))
ctx.addPath(footprint)
ctx.setFillColor(shade(frameHex, 0.62))
ctx.fillPath()
ctx.restoreGState()

snap("shadow")
drawHalf(body: lidBody, glass: lidGlass, screen: lidScreen, map: lidPoint, image: lidHalf, lid: true)
snap("lid")
drawHalf(body: baseBody, glass: baseGlass, screen: baseScreen, map: basePoint, image: baseHalf, lid: false)

snap("base")

// MARK: Type (the caption system of ci/store-frame.swift: tokenize `*word*`, balanced lines, gold swash)

struct Seg { var text: String; var hi: Bool }
typealias Token = [Seg]
typealias Words = [Token]

func tokenize(_ text: String) -> Words {
    var tokens: Words = []
    var current: Token = []
    var buffer = ""
    var hi = false
    func flushSeg() { if !buffer.isEmpty { current.append(Seg(text: buffer, hi: hi)); buffer = "" } }
    for ch in text {
        if ch == "*" { flushSeg(); hi.toggle(); continue }
        if ch == " " && !hi {
            flushSeg()
            if !current.isEmpty { tokens.append(current); current = [] }
            continue
        }
        buffer.append(ch)
    }
    flushSeg()
    if !current.isEmpty { tokens.append(current) }
    return tokens
}

let fontKey = NSAttributedString.Key(rawValue: kCTFontAttributeName as String)
let colorKey = NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String)
let kernKey = NSAttributedString.Key(rawValue: kCTKernAttributeName as String)

struct Style { var font: CTFont; var color: CGColor; var kern: CGFloat }

func attributed(_ words: Words, _ style: Style) -> (text: NSAttributedString, highlights: [NSRange]) {
    let result = NSMutableAttributedString()
    var highlights: [NSRange] = []
    let attrs: [NSAttributedString.Key: Any] = [fontKey: style.font, colorKey: style.color,
                                                kernKey: NSNumber(value: Double(style.kern))]
    for (i, token) in words.enumerated() {
        if i > 0 { result.append(NSAttributedString(string: " ", attributes: attrs)) }
        for seg in token {
            if seg.hi { highlights.append(NSRange(location: result.length, length: (seg.text as NSString).length)) }
            result.append(NSAttributedString(string: seg.text, attributes: attrs))
        }
    }
    return (result, highlights)
}

func measure(_ words: Words, _ style: Style) -> CGFloat {
    let line = CTLineCreateWithAttributedString(attributed(words, style).text as CFAttributedString)
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

func greedy(_ words: Words, _ limit: CGFloat, _ style: Style) -> [Words] {
    var lines: [Words] = []
    var current: Words = []
    for token in words {
        if current.isEmpty || measure(current + [token], style) <= limit { current.append(token) }
        else { lines.append(current); current = [token] }
    }
    if !current.isEmpty { lines.append(current) }
    return lines
}

func balanced(_ words: Words, _ width: CGFloat, _ style: Style) -> [Words] {
    guard words.count > 1, measure(words, style) > width else { return [words] }
    let count = greedy(words, width, style).count
    var lo: CGFloat = 0
    var hi = width
    for _ in 0..<18 {
        let mid = (lo + hi) / 2
        if greedy(words, mid, style).count <= count { hi = mid } else { lo = mid }
    }
    return greedy(words, hi, style)
}

struct Laid {
    var lines: [CTLine] = []
    var highlights: [[NSRange]] = []
    var widths: [CGFloat] = []
    var lineHeight: CGFloat = 0
    var ascentShare: CGFloat = 0.8
    var size: CGFloat = 0
    var capHeight: CGFloat = 0
    var ascent: CGFloat = 0
    var height: CGFloat { lineHeight * CGFloat(lines.count) }
    var maxWidth: CGFloat { widths.max() ?? 0 }
}

func lay(_ words: Words, _ style: Style, width: CGFloat, leading: CGFloat) -> Laid {
    var laid = Laid()
    let ascent = CTFontGetAscent(style.font), descent = CTFontGetDescent(style.font)
    laid.lineHeight = (ascent + descent) * leading
    laid.ascentShare = ascent / max(ascent + descent, 1)
    laid.size = CTFontGetSize(style.font)
    laid.capHeight = CTFontGetCapHeight(style.font)
    laid.ascent = ascent
    for lineWords in balanced(words, width, style) {
        let (text, highlights) = attributed(lineWords, style)
        let line = CTLineCreateWithAttributedString(text as CFAttributedString)
        laid.lines.append(line)
        laid.highlights.append(highlights)
        laid.widths.append(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
    }
    return laid
}

var usedRounded = true
func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> CTFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let descriptor = base.fontDescriptor.withDesign(.rounded), let font = NSFont(descriptor: descriptor, size: size) {
        return font as CTFont
    }
    usedRounded = false
    return base as CTFont
}

var textRect = CGRect.null   // top-left coordinates, ink extents
var textPieces: [CGRect] = []  // each line, swash, fill line and drip (for the overlap check)
func addText(_ r: CGRect) { textRect = textRect.union(r); textPieces.append(r) }

/// Draws laid lines from `top`, left-aligned at `x` or centred on `x` (top-left coordinates).
func drawLaid(_ laid: Laid, top: CGFloat, x: CGFloat, centred: Bool) {
    for (i, line) in laid.lines.enumerated() {
        let lineTop = top + CGFloat(i) * laid.lineHeight
        let baseline = lineTop + laid.lineHeight * laid.ascentShare
        let lx = centred ? x - laid.widths[i] / 2 : x
        let baseCG = H - baseline
        for range in laid.highlights[i] {
            let x0 = CTLineGetOffsetForStringIndex(line, range.location, nil)
            let x1 = CTLineGetOffsetForStringIndex(line, range.location + range.length, nil)
            let pad = laid.size * 0.10
            let swash = CGRect(x: lx + x0 - pad, y: baseCG - laid.size * 0.15,
                               width: (x1 - x0) + pad * 2, height: laid.capHeight + laid.size * 0.30)
            ctx.saveGState()
            ctx.translateBy(x: swash.midX, y: swash.midY)
            ctx.rotate(by: 0.018)
            let local = CGRect(x: -swash.width / 2, y: -swash.height / 2, width: swash.width, height: swash.height)
            let corner = max(0, min(swash.height * 0.28, swash.width * 0.49, swash.height * 0.49))
            ctx.addPath(CGPath(roundedRect: local, cornerWidth: corner, cornerHeight: corner, transform: nil))
            ctx.setFillColor(srgb(gold))
            ctx.fillPath()
            ctx.restoreGState()
            addText(tl(swash))
        }
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: lx, y: baseCG)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        addText(CGRect(x: lx + ink.minX, y: baseline - ink.maxY, width: ink.width, height: ink.height))
    }
}

/// The app's BrimWordmark: "Brim" (Rounded Black, kern -2 %), a glowing gold fill line 1.9 x size wide, and the cyan
/// drip hanging off the m. Returns its height. `x` is the left edge (or the centre when `centred`).
func wordmarkHeight(_ size: CGFloat) -> CGFloat {
    let font = roundedFont(size, .black)
    return CTFontGetAscent(font) + CTFontGetDescent(font) + size * 0.02 + max(4, size * 0.07) + size * 0.16
}
func drawWordmark(size: CGFloat, top: CGFloat, x: CGFloat, centred: Bool) {
    let font = roundedFont(size, .black)
    let style = Style(font: font, color: srgb(ink), kern: -size * 0.02)
    let words = tokenize("Brim")
    let textW = measure(words, style)
    let lineH = CTFontGetAscent(font) + CTFontGetDescent(font)
    let capsuleW = size * 1.9, capsuleH = max(4, size * 0.07)
    let stackW = max(textW, capsuleW)
    let left = centred ? x - stackW / 2 : x
    let laid = lay(words, style, width: 10_000, leading: 1.0)
    drawLaid(laid, top: top, x: left + (stackW - textW) / 2, centred: false)
    let capsule = CGRect(x: left + (stackW - capsuleW) / 2, y: top + lineH + size * 0.02, width: capsuleW, height: capsuleH)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: size * 0.2, color: srgb(gold, 0.8))
    ctx.addPath(CGPath(roundedRect: cg(capsule), cornerWidth: capsuleH / 2, cornerHeight: capsuleH / 2, transform: nil))
    ctx.setFillColor(srgb(gold))
    ctx.fillPath()
    ctx.restoreGState()
    addText(capsule)
    // DropShape, bottom-trailing in the stack, offset (-0.12, +0.16) x size.
    let dw = size * 0.16, dh = size * 0.24
    let drop = CGRect(x: left + stackW - size * 0.12 - dw, y: capsule.maxY + size * 0.16 - dh, width: dw, height: dh)
    let r = dw / 2, cy = drop.maxY - r
    let p = CGMutablePath()
    p.move(to: cgp(CGPoint(x: drop.midX, y: drop.minY)))
    p.addCurve(to: cgp(CGPoint(x: drop.maxX, y: cy)), control1: cgp(CGPoint(x: drop.midX + dw * 0.12, y: drop.minY + dh * 0.25)),
               control2: cgp(CGPoint(x: drop.maxX, y: cy - r * 0.9)))
    p.addArc(center: cgp(CGPoint(x: drop.midX, y: cy)), radius: r, startAngle: 0, endAngle: -.pi, clockwise: true)
    p.addCurve(to: cgp(CGPoint(x: drop.midX, y: drop.minY)), control1: cgp(CGPoint(x: drop.minX, y: cy - r * 0.9)),
               control2: cgp(CGPoint(x: drop.midX - dw * 0.12, y: drop.minY + dh * 0.25)))
    p.closeSubpath()
    ctx.saveGState()
    ctx.addPath(p)
    ctx.clip()
    if let g = CGGradient(colorsSpace: space, colors: [srgb(cyan), srgb(cyanDeep)] as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: cgp(CGPoint(x: 0, y: drop.minY)), end: cgp(CGPoint(x: 0, y: drop.maxY)), options: [])
    }
    ctx.restoreGState()
    addText(drop)
}

let tb = plan.textBox
let textCentreY = num("texty", (kind == "header" ? 0.50 : 0.50)) * H
if kind == "search" {
    // Wordmark (small), headline (big, two lines, one gold word), sub-line.
    let headline = options["headline"] ?? "Lift to *pour.*"
    let sub = options["sub"] ?? "Stop on the line."
    let headWords = tokenize(headline)
    let probe = roundedFont(100, .heavy)
    let capRatio = max(CTFontGetCapHeight(probe) / 100, 0.5)
    var cap = H * num("cap", 0.105)
    var head = Laid()
    while true {
        let size = cap / capRatio
        head = lay(headWords, Style(font: roundedFont(size, .heavy), color: srgb(ink), kern: -0.008 * size),
                   width: tb.width, leading: 0.90)
        if (head.lines.count <= 2 && head.maxWidth <= tb.width) || cap <= H * 0.05 { break }
        cap *= 0.95
    }
    let size = head.size
    let subSize = size * 0.40
    let subLaid = lay(tokenize(sub.replacingOccurrences(of: "*", with: "")),
                      Style(font: roundedFont(subSize, .semibold), color: srgb(subInk), kern: 0), width: tb.width, leading: 1.0)
    let markSize = size * 0.50
    let markH = wordmarkHeight(markSize)
    let gap1 = size * 0.22, gap2 = size * 0.20
    let total = markH + gap1 + head.height + gap2 + subLaid.height
    let top = textCentreY - total / 2
    drawWordmark(size: markSize, top: top, x: tb.minX + size * 0.02, centred: false)
    drawLaid(head, top: top + markH + gap1, x: tb.minX, centred: false)
    drawLaid(subLaid, top: top + markH + gap1 + head.height + gap2, x: tb.minX + size * 0.02, centred: false)
} else {
    // Header: the wordmark, big, and "Fold to Pour" under it. The icon and the app name sit below on the page.
    let tagline = options["headline"] ?? "Fold to Pour"
    let markSize = H * num("mark", 0.235)
    let markH = wordmarkHeight(markSize)
    let tagSize = markSize * 0.34
    let tagLaid = lay(tokenize(tagline), Style(font: roundedFont(tagSize, .heavy), color: srgb(subInk), kern: 0),
                      width: tb.width * 1.4, leading: 1.0)
    let gap = markSize * 0.10
    let total = markH + gap + tagLaid.height
    let top = textCentreY - total / 2
    let font = roundedFont(markSize, .black)
    let textW = measure(tokenize("Brim"), Style(font: font, color: srgb(ink), kern: -markSize * 0.02))
    let stackW = max(textW, markSize * 1.9)
    let centreX = tb.minX + stackW / 2
    drawWordmark(size: markSize, top: top, x: centreX, centred: true)
    drawLaid(tagLaid, top: top + markH + gap, x: centreX, centred: true)
}

snap("text")

// MARK: Output (opaque sRGB PNG, no alpha), plus the optional review copy with guides

func writePNG(_ image: CGImage, _ path: String) {
    guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString,
                                                            1, nil) else { fail("cannot create \(path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(path)") }
}

guard let flat = ctx.makeImage() else { fail("cannot flatten") }
writePNG(flat, output)

// Where the art is seen. Brim is iPhone-only (TARGETED_DEVICE_FAMILY 1). On an iPhone in portrait the search art is
// shown whole (~365 pt wide) and the header keeps its full height but loses about 8 % per side, with the back and
// share buttons over its top corners (measured in App Store Connect's preview by others; Apple publishes no crop
// rule). Text must sit inside that iPhone area and never touch the device; the smaller template safe area (other
// devices, e.g. the Mac App Store listing of an iPhone app) is reported, not enforced.
let iphoneArea: CGRect = kind == "header"
    ? CGRect(x: W * 0.09, y: H * 0.05, width: W * 0.82, height: H * 0.90)
    : CGRect(x: W * 0.03, y: H * 0.03, width: W * 0.94, height: H * 0.94)

if let guides = options["guides"], !guides.isEmpty {
    ctx.saveGState()
    ctx.setLineWidth(6)
    ctx.setStrokeColor(srgb(0xE5484D, 0.9))
    ctx.setLineDash(phase: 0, lengths: [28, 18])
    ctx.stroke(cg(safeArea))
    ctx.setStrokeColor(srgb(0x1FA3D6, 0.9))
    ctx.stroke(cg(iphoneArea))
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setStrokeColor(srgb(0x2B2233, 0.6))
    ctx.setLineWidth(3)
    ctx.move(to: CGPoint(x: 0, y: H / 2)); ctx.addLine(to: CGPoint(x: W, y: H / 2)); ctx.strokePath()
    ctx.restoreGState()
    if let g = ctx.makeImage() { writePNG(g, guides) }
}

// Does any piece of text come within 1.2 % of the image height of the device?
var overlap = false
let devicePath = CGMutablePath()
devicePath.addPath(path(lidBody) { lidPoint($0.x, $0.y, 0) })
devicePath.addPath(path(baseBody) { basePoint($0.x, $0.y, 0) })
devicePath.addPath(path(baseBody) { basePoint($0.x, $0.y, -thick) })
for piece in textPieces {
    let probe = CGPath(rect: cg(piece.insetBy(dx: -H * 0.012, dy: -H * 0.012)), transform: nil)
    if #available(macOS 13.0, *) {
        if probe.intersects(devicePath) { overlap = true }
    } else if piece.intersects(tl(deviceRectCG)) {
        overlap = true
    }
}

let deviceTL = tl(deviceRectCG)
func r(_ v: CGRect) -> String { "\(Int(v.minX)),\(Int(v.minY)),\(Int(v.width))x\(Int(v.height))" }
let textIPhone = iphoneArea.contains(textRect)
let textTemplate = safeArea.contains(textRect)
let foldInTemplate = plan.foldY >= safeArea.minY && plan.foldY <= safeArea.maxY
print("store-banner: \(output) \(width)x\(height) kind=\(kind) layout=\(layout) fold=\(Int(plan.foldY)) "
      + "device=\(r(deviceTL)) text=\(r(textRect)) text-iphone=\(textIPhone ? "yes" : "no") "
      + "overlap=\(overlap ? "yes" : "no") text-in-template-safe=\(textTemplate ? "yes" : "no") "
      + "fold-in-template-safe=\(foldInTemplate ? "yes" : "no") rounded=\(usedRounded ? "yes" : "no")")
