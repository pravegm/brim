// badges.swift: collects Brim's 10 Game Center achievement images for asc.swift.
//
//   xcrun swift tools/appstore/badges.swift --from <dir> [--out <dir>]
//
// Brim draws its badges itself (Brim/UI/AchievementArt.swift, AchievementBadge(id:)). Every CI run (ci.yml) plays
// the scenario `15-badges` (demo key screen=badges, Brim/App/DemoMode.swift), which writes Documents/badges/<id>.png
// at 1024 x 1024; ci/screenshots.sh copies them into the `screenshots` artifact, folder badges/. Point --from at that
// folder. This script does not redraw anything: it
//   1. checks the IDs: the PNG names must equal GameCenterManager.achievementIDs (Brim/App/GameCenterManager.swift),
//      the IDs in docs/appstore/achievements.md and, if it exists, the achievements in docs/appstore/asc-metadata.json;
//   2. checks each image is 1024 x 1024;
//   3. writes it to <out>/<id>.png as an opaque sRGB PNG at 72 ppi. The app's renderer writes RGBA; Game Center asks
//      for RGB without transparency, so the alpha channel is dropped. Any pixel that isn't fully opaque is first
//      composited onto the badge background cream #FFF4E2, and the count is printed (0 expected).
//   4. writes <out>/preview.png, a 5 x 2 contact sheet.
// Default <out> is tools/appstore/badges. Exits 1 on any mismatch or unreadable image.

import CoreGraphics
import Foundation
import ImageIO

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let scriptDir = scriptURL.deletingLastPathComponent()
let repoRoot: URL = {
    if let r = ProcessInfo.processInfo.environment["ASC_REPO_ROOT"], !r.isEmpty { return URL(fileURLWithPath: r) }
    let guess = scriptDir.deletingLastPathComponent().deletingLastPathComponent()
    if FileManager.default.fileExists(atPath: guess.appendingPathComponent("Brim/App/GameCenterManager.swift").path) { return guess }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}()

func fail(_ s: String) -> Never {
    FileHandle.standardError.write("error: \(s)\n".data(using: .utf8)!)
    exit(1)
}

var fromDir: URL? = nil
var outDir = scriptDir.appendingPathComponent("badges")
do {
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "--from":
            guard !args.isEmpty else { fail("--from needs a directory") }
            fromDir = URL(fileURLWithPath: args.removeFirst())
        case "--out":
            guard !args.isEmpty else { fail("--out needs a directory") }
            outDir = URL(fileURLWithPath: args.removeFirst())
        case "-h", "--help":
            print("usage: xcrun swift tools/appstore/badges.swift --from <screenshots artifact>/badges [--out <dir>]")
            exit(0)
        default:
            fail("unknown argument \(a)")
        }
    }
}

// MARK: - The IDs, from three places

func quoted(_ s: Substring) -> [String] {
    var found: [String] = []
    var rest = s
    while let open = rest.firstIndex(of: "\"") {
        let after = rest.index(after: open)
        guard let close = rest[after...].firstIndex(of: "\"") else { break }
        found.append(String(rest[after..<close]))
        rest = rest[rest.index(after: close)...]
    }
    return found
}

func appIDs() -> [String] {
    let url = repoRoot.appendingPathComponent("Brim/App/GameCenterManager.swift")
    guard let text = try? String(contentsOf: url, encoding: .utf8),
          let start = text.range(of: "static let achievementIDs") else { fail("\(url.path): achievementIDs not found") }
    let tail = text[start.upperBound...]
    guard let close = tail.firstIndex(of: "]") else { fail("\(url.path): achievementIDs list not closed") }
    return quoted(tail[..<close])
}

func docIDs() -> [String] {
    let url = repoRoot.appendingPathComponent("docs/appstore/achievements.md")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { fail("\(url.path) not found") }
    // Table rows: | 1 | `brim.first.perfect` | ...
    return text.components(separatedBy: .newlines).compactMap { line in
        guard line.range(of: "^\\| [0-9]+ \\| `", options: .regularExpression) != nil else { return nil }
        let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        return cells.count > 1 ? cells[1].replacingOccurrences(of: "`", with: "") : nil
    }
}

func metadataIDs() -> [String]? {
    let url = repoRoot.appendingPathComponent("docs/appstore/asc-metadata.json")
    guard let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let list = root["achievements"] as? [[String: Any]] else { return nil }
    return list.compactMap { $0["vendorIdentifier"] as? String }
}

let ids = appIDs()
guard ids.count == 10 else { fail("GameCenterManager.achievementIDs has \(ids.count) IDs, expected 10") }
var mismatch = false
func compare(_ name: String, _ other: [String]?) {
    guard let other = other else { print("  \(name): not found, skipped"); return }
    let a = Set(ids), b = Set(other)
    if a == b && other.count == ids.count { print("  \(name): same 10 IDs"); return }
    mismatch = true
    print("  \(name): MISMATCH. Missing: \(a.subtracting(b).sorted().joined(separator: ", ")). Extra: \(b.subtracting(a).sorted().joined(separator: ", "))")
}
print("IDs (GameCenterManager.achievementIDs): \(ids.joined(separator: ", "))")
compare("docs/appstore/achievements.md", docIDs())
compare("docs/appstore/asc-metadata.json", metadataIDs())

guard let from = fromDir else {
    if mismatch { fail("achievement IDs differ") }
    print("No --from given: IDs checked, no images collected.")
    exit(0)
}
let files = ((try? FileManager.default.contentsOfDirectory(atPath: from.path)) ?? []).filter { $0.hasSuffix(".png") }
compare("\(from.path) (rendered by the app)", files.map { String($0.dropLast(4)) })
if mismatch { fail("achievement IDs differ") }

// MARK: - Flatten and write

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func load(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

/// Number of pixels whose alpha is below 255.
func translucentPixels(_ image: CGImage) -> Int {
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var n = 0
    var i = 3
    while i < buf.count { if buf[i] < 255 { n += 1 }; i += 4 }
    return n
}

func opaqueCopy(_ image: CGImage, size: Int) -> CGImage {
    // noneSkipLast: RGB with no alpha channel in the written PNG.
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1.0, green: 0xF4 / 255.0, blue: 0xE2 / 255.0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { fail("can't write \(url.path)") }
    let props: [CFString: Any] = [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72, kCGImagePropertyHasAlpha: false]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fail("can't finalise \(url.path)") }
}

/// Bytes 25 (colour type) of the IHDR chunk: 2 = RGB, 6 = RGBA.
func pngColourType(_ url: URL) -> UInt8? {
    guard let d = try? Data(contentsOf: url), d.count > 25 else { return nil }
    return d[25]
}

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
var flattened: [CGImage] = []
var failed = false
for id in ids {
    let src = from.appendingPathComponent("\(id).png")
    guard let img = load(src) else { print("  \(id): can't read \(src.path)"); failed = true; continue }
    guard img.width == 1024 && img.height == 1024 else { print("  \(id): \(img.width)x\(img.height), Game Center needs 1024x1024"); failed = true; continue }
    let translucent = translucentPixels(img)
    let opaque = opaqueCopy(img, size: 1024)
    let dst = outDir.appendingPathComponent("\(id).png")
    writePNG(opaque, to: dst)
    let bytes = (try? FileManager.default.attributesOfItem(atPath: dst.path)[.size] as? Int) ?? 0
    let ct = pngColourType(dst).map { $0 == 2 ? "RGB" : "colour type \($0)" } ?? "?"
    print("  \(id): 1024x1024, \(translucent) translucent px\(translucent > 0 ? " flattened onto cream" : ""), wrote \(ct) PNG \(bytes / 1024) KB")
    if pngColourType(dst) != 2 { print("  \(id): the written PNG is not plain RGB"); failed = true }
    flattened.append(opaque)
}
if failed { fail("some badges could not be collected") }

// Contact sheet: 5 x 2 at 256 px with 16 px gaps.
let cell = 256, gap = 16, cols = 5, rows = 2
let sheetW = cols * cell + (cols + 1) * gap, sheetH = rows * cell + (rows + 1) * gap
let sheet = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
sheet.setFillColor(CGColor(srgbRed: 0.17, green: 0.13, blue: 0.2, alpha: 1))
sheet.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
sheet.interpolationQuality = .high
for (i, img) in flattened.enumerated() {
    let c = i % cols, r = i / cols
    let x = gap + c * (cell + gap), y = sheetH - (gap + (r + 1) * cell + r * gap)
    sheet.draw(img, in: CGRect(x: x, y: y, width: cell, height: cell))
}
writePNG(sheet.makeImage()!, to: outDir.appendingPathComponent("preview.png"))
print("OK: \(flattened.count) badges in \(outDir.path) (+ preview.png)")
