import CoreGraphics
import Foundation

// Pure geometry used by the scene. No SpriteKit / UIKit, no actor isolation, so it is unit-testable
// (BrimTests/SceneTests.swift).

/// A puddle on the counter: where, and how many spill marks fed it (it spreads with the count).
struct PuddleBlob: Equatable {
    var center: CGPoint
    var count: Int
}

enum ScenePaths {

    // MARK: Glass profile

    /// Linear interpolation of a glass profile (x = half-width, y = height). Clamped to the first/last point.
    static func halfWidth(_ profile: [CGPoint], at h: CGFloat) -> CGFloat {
        guard let first = profile.first, let last = profile.last else { return 0 }
        if h <= first.y { return first.x }
        if h >= last.y { return last.x }
        if profile.count < 2 { return last.x }
        for i in 1..<profile.count {
            let a = profile[i - 1], b = profile[i]
            if h <= b.y {
                let span = b.y - a.y
                if span <= 0.0001 { return b.x }
                let t = (h - a.y) / span
                return a.x + (b.x - a.x) * t
            }
        }
        return last.x
    }

    // MARK: Polylines and ribbons

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    /// Uniform Catmull–Rom point on the segment p1→p2.
    static func catmull(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let t2 = t * t
        let t3 = t2 * t
        let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                       + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
        let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                       + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
        return CGPoint(x: x, y: y)
    }

    /// Catmull–Rom smoothing of a polyline with per-point widths. Segments longer than `maxStep` get subdivided
    /// (at most 6 sub-points per segment). The first and last points are kept exactly.
    static func smooth(_ pts: [CGPoint], widths ws: [CGFloat], maxStep: CGFloat = 7) -> (points: [CGPoint], widths: [CGFloat]) {
        let n = min(pts.count, ws.count)
        if n < 3 { return (Array(pts.prefix(n)), Array(ws.prefix(n))) }
        var outP: [CGPoint] = []
        var outW: [CGFloat] = []
        outP.reserveCapacity(n * 3)
        outW.reserveCapacity(n * 3)
        for i in 0..<(n - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, n - 1)]
            let w1 = ws[i], w2 = ws[i + 1]
            let len = ScenePaths.distance(p1, p2)
            let steps = max(1, min(6, Int(ceil(len / max(maxStep, 0.5)))))
            for s in 0..<steps {
                let t = CGFloat(s) / CGFloat(steps)
                outP.append(s == 0 ? p1 : catmull(p0, p1, p2, p3, t))
                outW.append(w1 + (w2 - w1) * t)
            }
        }
        outP.append(pts[n - 1])
        outW.append(ws[n - 1])
        return (outP, outW)
    }

    /// Appends a closed ribbon outline (centre line ± width/2 along the normals) to `path`.
    /// `widthScale` scales the half-widths; `shift` moves the centre line sideways by `shift × width`.
    /// The far end (the stream's falling tail) gets a rounded cap.
    static func addRibbon(_ path: CGMutablePath, points p: [CGPoint], widths w: [CGFloat],
                          widthScale: CGFloat = 1, shift: CGFloat = 0, minHalfWidth: CGFloat = 0.6) {
        let n = min(p.count, w.count)
        guard n >= 2 else { return }
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        left.reserveCapacity(n)
        right.reserveCapacity(n)
        var tx: CGFloat = 0, ty: CGFloat = -1
        var lastHalf: CGFloat = minHalfWidth
        var lastCentre = p[n - 1]
        for i in 0..<n {
            let a = p[max(i - 1, 0)], b = p[min(i + 1, n - 1)]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = hypot(dx, dy)
            if len > 0.0001 { tx = dx / len; ty = dy / len }
            let nx = -ty, ny = tx
            let half = max(minHalfWidth, w[i] * 0.5 * widthScale)
            let cx = p[i].x + nx * w[i] * shift
            let cy = p[i].y + ny * w[i] * shift
            left.append(CGPoint(x: cx + nx * half, y: cy + ny * half))
            right.append(CGPoint(x: cx - nx * half, y: cy - ny * half))
            lastHalf = half
            lastCentre = CGPoint(x: cx, y: cy)
        }
        path.move(to: left[0])
        for i in 1..<n { path.addLine(to: left[i]) }
        let tip = CGPoint(x: lastCentre.x + tx * lastHalf * 2, y: lastCentre.y + ty * lastHalf * 2)
        path.addQuadCurve(to: right[n - 1], control: tip)
        var i = n - 2
        while i >= 0 {
            path.addLine(to: right[i])
            i -= 1
        }
        path.closeSubpath()
    }

    /// Lateral wobble of a ribbon's centre line: a travelling sine along the arc length, zero at the spout and
    /// growing over the first ~120 pt, amplitude `amplitude × width`.
    static func wobble(_ p: inout [CGPoint], widths w: [CGFloat], amplitude: CGFloat, time: CGFloat) {
        let n = min(p.count, w.count)
        guard n >= 3, amplitude > 0 else { return }
        let src = p
        var s: CGFloat = 0
        for i in 0..<n {
            if i > 0 { s += distance(src[i - 1], src[i]) }
            let a = src[max(i - 1, 0)], b = src[min(i + 1, n - 1)]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = hypot(dx, dy)
            if len < 0.0001 { continue }
            let nx = -dy / len, ny = dx / len
            let ramp = min(1, s / 120)
            let off = amplitude * w[i] * ramp * sin(time * 5.5 - s * 0.05)
            p[i] = CGPoint(x: src[i].x + nx * off, y: src[i].y + ny * off)
        }
    }

    /// Groups puddle marks (Core may repeat points to say "this puddle grew") into blobs: centre + how many marks.
    static func puddleBlobs(_ pts: [CGPoint], radius: CGFloat) -> [PuddleBlob] {
        var blobs: [PuddleBlob] = []
        for q in pts {
            var merged = false
            for i in 0..<blobs.count where abs(blobs[i].center.x - q.x) <= radius {
                let k = CGFloat(blobs[i].count)
                blobs[i].center = CGPoint(x: (blobs[i].center.x * k + q.x) / (k + 1), y: (blobs[i].center.y * k + q.y) / (k + 1))
                blobs[i].count += 1
                merged = true
                break
            }
            if !merged { blobs.append(PuddleBlob(center: q, count: 1)) }
        }
        return blobs
    }

    /// Splits an ordered polyline into runs wherever two consecutive points are further apart than `gap`
    /// (a stream that stopped and restarted). Returns index ranges.
    static func runs(_ pts: [CGPoint], gap: CGFloat) -> [Range<Int>] {
        guard !pts.isEmpty else { return [] }
        var result: [Range<Int>] = []
        var start = 0
        if pts.count > 1 {
            for i in 1..<pts.count where ScenePaths.distance(pts[i - 1], pts[i]) > gap {
                result.append(start..<i)
                start = i
            }
        }
        result.append(start..<pts.count)
        return result
    }

    /// Adds `pts` as a smooth open curve (quadratic through the midpoints). The path must already be at `pts[0]`.
    static func addSmoothCurve(_ path: CGMutablePath, _ pts: [CGPoint]) {
        let n = pts.count
        guard n >= 2 else { return }
        if n == 2 { path.addLine(to: pts[1]); return }
        for i in 1..<(n - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) * 0.5, y: (pts[i].y + pts[i + 1].y) * 0.5)
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.addLine(to: pts[n - 1])
    }

    // MARK: Polygons

    static func polygon(_ pts: [CGPoint], closed: Bool = true) -> CGMutablePath {
        let path = CGMutablePath()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count > 1 {
            for i in 1..<pts.count { path.addLine(to: pts[i]) }
        }
        if closed { path.closeSubpath() }
        return path
    }

    /// Open polyline visiting `pts` in the given index order.
    static func polyline(_ pts: [CGPoint], order: [Int]) -> CGMutablePath {
        let path = CGMutablePath()
        var started = false
        for idx in order where idx >= 0 && idx < pts.count {
            if started { path.addLine(to: pts[idx]) } else { path.move(to: pts[idx]); started = true }
        }
        return path
    }

    /// Positive for counter-clockwise polygons (y up).
    static func signedArea(_ pts: [CGPoint]) -> CGFloat {
        let n = pts.count
        guard n >= 3 else { return 0 }
        var s: CGFloat = 0
        for i in 0..<n {
            let a = pts[i], b = pts[(i + 1) % n]
            s += a.x * b.y - b.x * a.y
        }
        return s * 0.5
    }

    static func bounds(_ pts: [CGPoint]) -> CGRect {
        guard let f = pts.first else { return .zero }
        var minX = f.x, maxX = f.x, minY = f.y, maxY = f.y
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func centroid(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        var x: CGFloat = 0, y: CGFloat = 0
        for p in pts { x += p.x; y += p.y }
        return CGPoint(x: x / CGFloat(pts.count), y: y / CGFloat(pts.count))
    }

    /// Offsets a simple polygon outward by `d` (mitered, miter clamped). Works for either winding.
    static func offsetPolygon(_ pts: [CGPoint], by d: CGFloat) -> [CGPoint] {
        let n = pts.count
        guard n >= 3 else { return pts }
        let ccw: CGFloat = signedArea(pts) >= 0 ? 1 : -1
        var out: [CGPoint] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n]
            let n1 = edgeNormal(prev, cur, ccw)
            let n2 = edgeNormal(cur, next, ccw)
            var mx = n1.dx + n2.dx, my = n1.dy + n2.dy
            let ml = hypot(mx, my)
            if ml < 0.0001 { mx = n2.dx; my = n2.dy } else { mx /= ml; my /= ml }
            let cosHalf = max(0.45, mx * n2.dx + my * n2.dy)
            let k = d / cosHalf
            out.append(CGPoint(x: cur.x + mx * k, y: cur.y + my * k))
        }
        return out
    }

    private static func edgeNormal(_ a: CGPoint, _ b: CGPoint, _ ccw: CGFloat) -> CGVector {
        let dx = b.x - a.x, dy = b.y - a.y
        let l = hypot(dx, dy)
        if l < 0.0001 { return CGVector(dx: 0, dy: 0) }
        // Outward normal of a CCW polygon edge is (dy, -dx).
        return CGVector(dx: dy / l * ccw, dy: -dx / l * ccw)
    }

    /// x where the horizontal line at `y` crosses the polygon: the right-most crossing if `rightmost`, else the
    /// left-most. nil if the line misses.
    static func xOnPolygon(_ pts: [CGPoint], atY y: CGFloat, rightmost: Bool) -> CGFloat? {
        let n = pts.count
        guard n >= 2 else { return nil }
        var best: CGFloat?
        for i in 0..<n {
            let a = pts[i], b = pts[(i + 1) % n]
            let lo = min(a.y, b.y), hi = max(a.y, b.y)
            if y < lo || y > hi || hi - lo < 0.0001 { continue }
            let t = (y - a.y) / (b.y - a.y)
            let x = a.x + (b.x - a.x) * t
            if let cur = best {
                best = rightmost ? max(cur, x) : min(cur, x)
            } else {
                best = x
            }
        }
        return best
    }

    /// The part of polygon `pts` at or below y = `level` (`below` true) or at or above it (`below` false).
    /// Sutherland–Hodgman against one horizontal half-plane. Empty if fewer than 3 points survive.
    static func clip(_ pts: [CGPoint], level: CGFloat, below: Bool) -> [CGPoint] {
        let n = pts.count
        guard n >= 3 else { return [] }
        var out: [CGPoint] = []
        out.reserveCapacity(n + 4)
        for i in 0..<n {
            let a = pts[i], b = pts[(i + 1) % n]
            let aIn = below ? a.y <= level : a.y >= level
            let bIn = below ? b.y <= level : b.y >= level
            if aIn { out.append(a) }
            if aIn != bIn {
                let dy = b.y - a.y
                let t = abs(dy) > 1e-9 ? (level - a.y) / dy : 0
                out.append(CGPoint(x: a.x + t * (b.x - a.x), y: level))
            }
        }
        return out.count >= 3 ? out : []
    }

    /// An open polyline visiting `pts` in `order`, keeping only the parts at or above y = `level` (each run becomes
    /// its own subpath; crossings are interpolated).
    static func polylineAbove(_ pts: [CGPoint], order: [Int], level: CGFloat) -> CGMutablePath {
        let path = CGMutablePath()
        var prev: CGPoint?
        var drawing = false
        for idx in order where idx >= 0 && idx < pts.count {
            let p = pts[idx]
            let inside = p.y >= level
            if let q = prev {
                let qIn = q.y >= level
                if qIn != inside {
                    let dy = p.y - q.y
                    let t = abs(dy) > 1e-9 ? (level - q.y) / dy : 0
                    let c = CGPoint(x: q.x + t * (p.x - q.x), y: level)
                    if inside {
                        path.move(to: c)
                        path.addLine(to: p)
                        drawing = true
                    } else {
                        if drawing { path.addLine(to: c) }
                        drawing = false
                    }
                } else if inside {
                    if drawing { path.addLine(to: p) } else { path.move(to: p); drawing = true }
                }
            } else if inside {
                path.move(to: p)
                drawing = true
            }
            prev = p
        }
        return path
    }

    /// Index of the polygon vertex nearest to `p` (-1 for an empty polygon).
    static func nearestIndex(_ pts: [CGPoint], to p: CGPoint) -> Int {
        var best = -1
        var bestD = CGFloat.greatestFiniteMagnitude
        for (i, q) in pts.enumerated() {
            let d = (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    /// World point → jug-local point (relative to `pivot`, rotation `radians` undone).
    /// The jug's world pose is `world = pivot + R(−angle)·local` (positive angle = clockwise on screen), so
    /// `local = R(+angle)·(world − pivot)`.
    static func toLocal(_ p: CGPoint, pivot: CGPoint, radians r: CGFloat) -> CGPoint {
        let dx = p.x - pivot.x, dy = p.y - pivot.y
        let c = cos(r), s = sin(r)
        return CGPoint(x: dx * c - dy * s, y: dx * s + dy * c)
    }

    /// Inverse of `toLocal`.
    static func toWorld(_ p: CGPoint, pivot: CGPoint, radians r: CGFloat) -> CGPoint {
        let c = cos(-r), s = sin(-r)
        return CGPoint(x: pivot.x + p.x * c - p.y * s, y: pivot.y + p.x * s + p.y * c)
    }

    /// Points on an ellipse arc (angles in radians, counter-clockwise, y up).
    static func ellipseArc(center: CGPoint, rx: CGFloat, ry: CGFloat, from a0: CGFloat, to a1: CGFloat, segments: Int) -> [CGPoint] {
        let n = max(2, segments)
        var pts: [CGPoint] = []
        pts.reserveCapacity(n + 1)
        for i in 0...n {
            let a = a0 + (a1 - a0) * CGFloat(i) / CGFloat(n)
            pts.append(CGPoint(x: center.x + cos(a) * rx, y: center.y + sin(a) * ry))
        }
        return pts
    }
}

// MARK: - Liquid surface waves

/// A 1D chain of damped springs across a glass's liquid surface (GAME-DESIGN §5: "spring-mass wave").
/// Heights are offsets in points from the true level; the mean is removed each step so the visible level never lies.
struct SceneWave {
    static let count = 16
    var h: [CGFloat] = Array(repeating: 0, count: SceneWave.count)
    var v: [CGFloat] = Array(repeating: 0, count: SceneWave.count)
    var stiffness: CGFloat = 55
    var damping: CGFloat = 2.8
    var spread: CGFloat = 240
    var limit: CGFloat = 14
    private var acc: [CGFloat] = Array(repeating: 0, count: SceneWave.count)

    init() {}

    mutating func step(_ dt: CGFloat) {
        guard dt > 0 else { return }
        let maxStep: CGFloat = 1.0 / 240.0
        let steps = max(1, min(16, Int(ceil(dt / maxStep))))
        let sdt = dt / CGFloat(steps)
        let n = SceneWave.count
        for _ in 0..<steps {
            for i in 0..<n {
                let l = h[max(i - 1, 0)], r = h[min(i + 1, n - 1)]
                acc[i] = -stiffness * h[i] - damping * v[i] + spread * (l + r - 2 * h[i])
            }
            var mean: CGFloat = 0
            for i in 0..<n {
                v[i] += acc[i] * sdt
                h[i] += v[i] * sdt
                if h[i] > limit { h[i] = limit; v[i] = min(v[i], 0) }
                if h[i] < -limit { h[i] = -limit; v[i] = max(v[i], 0) }
                mean += h[i]
            }
            mean /= CGFloat(n)
            for i in 0..<n { h[i] -= mean }
        }
    }

    /// Vertical velocity impulse centred at `fraction` (0 = left wall, 1 = right wall). Negative pushes down.
    mutating func kick(at fraction: CGFloat, impulse: CGFloat) {
        let n = SceneWave.count
        let c = min(max(fraction, 0), 1) * CGFloat(n - 1)
        for i in 0..<n {
            let d = CGFloat(i) - c
            let k = exp(-d * d / 3.0)
            if k > 0.01 { v[i] += impulse * k }
        }
    }

    /// Tilting impulse (sloshing): positive raises the right side.
    mutating func slosh(_ impulse: CGFloat) {
        let n = SceneWave.count
        for i in 0..<n {
            let f = CGFloat(i) / CGFloat(n - 1) * 2 - 1
            v[i] += impulse * f
        }
    }

    var energy: CGFloat {
        var e: CGFloat = 0
        for i in 0..<SceneWave.count { e += abs(h[i]) + abs(v[i]) * 0.05 }
        return e
    }

    var mean: CGFloat {
        var m: CGFloat = 0
        for x in h { m += x }
        return m / CGFloat(SceneWave.count)
    }

    mutating func reset() {
        for i in 0..<SceneWave.count { h[i] = 0; v[i] = 0 }
    }
}

// MARK: - Deterministic cosmetic randomness

/// xorshift64. Cosmetic only (never touches game state), seeded so CI frames are stable.
struct SceneRNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// 0 ..< 1
    mutating func unit() -> CGFloat {
        CGFloat(Double(next() >> 11) / 9_007_199_254_740_992.0)
    }

    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * unit() }

    mutating func sign() -> CGFloat { unit() < 0.5 ? -1 : 1 }
}
