// Brim App Store frame compositor (macOS host side; ci/store-set.sh runs it, compiled with `xcrun swiftc` or as a
// script with `xcrun swift`). Puts one store caption above one raw simulator screenshot, in the caption system of
// docs/appstore/screenshots.md:
//
//   store-frame --in raw.png --out frame.png --size 1320x2868 \
//               --caption "Tip the jug. Stop on the *line*. / Drag up to pour, on any iPhone." [--radius 0.11]
//
//  • Background: the brand sweep, cream #FFF4E2 at the top to peach at the bottom, with a soft gold glow.
//  • Caption: centred in the top band (3 %–26 % of the height). Headline in SF Pro Rounded Heavy (the system font
//    with the rounded design; plain system Heavy if that design is missing), ink #2B2233, cap height 4.6 % of the
//    image height, shrinking in 5 % steps (floor 3.0 %) until it fits the band in at most three lines. `*word*` is the
//    ONE highlighted word: ink letters on a brim-gold #FFC23D marker swash (never gold letters: 1.48:1 on cream).
//    " / " starts the sub-line (SF Pro Rounded Semibold, ~46 % of the headline, shrinking to stay on one line).
//    Lines are balanced (even widths, no orphan) and prefer to break after a sentence.
//  • Screenshot: the capture itself, unaltered, scaled to fit the box under the band, with rounded corners, a hairline
//    edge and a soft shadow. No device frame is drawn, so a non-folding iPhone is never shown folded and a Duo frame
//    stays a flat picture of its inner display (Brim's truthfulness rule: nothing on a frame the app doesn't do).
//  • Output: exactly --size pixels (default: the input's size), opaque sRGB PNG with no alpha channel.
// Prints one line: `store-frame: <out> <W>x<H> cap=<% of H> lines=<n> font=<PostScript name> rounded=<yes|no>`.
import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("store-frame: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

var options: [String: String] = [:]
var argv = Array(CommandLine.arguments.dropFirst())
while !argv.isEmpty {
    let key = argv.removeFirst()
    guard key.hasPrefix("--"), !argv.isEmpty else { fail("bad argument \(key)") }
    options[String(key.dropFirst(2))] = argv.removeFirst()
}
guard let input = options["in"], let output = options["out"] else { fail("needs --in and --out") }
let rawCaption = options["caption"] ?? ""
let cornerFraction = CGFloat(Double(options["radius"] ?? "") ?? 0.08)

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
      let shot = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(input)") }

var width = shot.width, height = shot.height
if let size = options["size"], !size.isEmpty, size != "raw" {
    let parts = size.lowercased().split(separator: "x").compactMap { Int($0) }
    guard parts.count == 2, parts[0] > 64, parts[1] > 64 else { fail("bad --size \(size)") }
    width = parts[0]
    height = parts[1]
}
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

// Brand palette (docs/appstore/screenshots.md, Brim/UI palette).
let cream: UInt32 = 0xFFF4E2
let creamPeach: UInt32 = 0xFFE9CF
let peach: UInt32 = 0xFFD3B2
let ink: UInt32 = 0x2B2233
let subInk: UInt32 = 0x544760
let gold: UInt32 = 0xFFC23D

/// A top-left-origin rect → Core Graphics' bottom-left origin.
func cg(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height) }

// MARK: Background

ctx.setFillColor(srgb(cream))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
if let sweep = CGGradient(colorsSpace: space, colors: [srgb(cream), srgb(creamPeach), srgb(peach)] as CFArray,
                          locations: [0, 0.55, 1]) {
    ctx.drawLinearGradient(sweep, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
}
if let glow = CGGradient(colorsSpace: space, colors: [srgb(gold, 0.20), srgb(gold, 0)] as CFArray, locations: [0, 1]) {
    let centre = CGPoint(x: W / 2, y: H * 0.40)
    ctx.drawRadialGradient(glow, startCenter: centre, startRadius: 0, endCenter: centre,
                           endRadius: max(W, H) * 0.55, options: [])
}

// MARK: Screenshot (unaltered, scaled to fit the box under the caption band)

let boxTop = H * 0.28
let boxBottom = H * 0.97
let boxWidth = W * 0.86
let fit = min(boxWidth / CGFloat(shot.width), (boxBottom - boxTop) / CGFloat(shot.height))
let shotW = (CGFloat(shot.width) * fit).rounded()
let shotH = (CGFloat(shot.height) * fit).rounded()
let shotRect = CGRect(x: ((W - shotW) / 2).rounded(), y: boxTop.rounded(), width: shotW, height: shotH)  // top-left
let radius = max(0, min(shotW * cornerFraction, shotW * 0.49, shotH * 0.49))
let shotPath = CGPath(roundedRect: cg(shotRect), cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -H * 0.007), blur: H * 0.030, color: srgb(ink, 0.32))
ctx.addPath(shotPath)
ctx.setFillColor(srgb(ink))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shotPath)
ctx.clip()
ctx.draw(shot, in: cg(shotRect))
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shotPath)
ctx.setStrokeColor(srgb(ink, 0.16))
ctx.setLineWidth(max(1, W * 0.0015))
ctx.strokePath()
ctx.restoreGState()

// MARK: Caption (Core Text, laid out top-down, drawn in Core Graphics coordinates)

struct Seg { var text: String; var hi: Bool }
typealias Token = [Seg]          // one unbreakable word (a `*highlighted phrase*` stays in one token)
typealias Words = [Token]

/// Splits on spaces outside `*…*`; `*` toggles the highlight and is never drawn.
func tokenize(_ text: String) -> Words {
    var tokens: Words = []
    var current: Token = []
    var buffer = ""
    var hi = false
    func flushSeg() {
        if !buffer.isEmpty { current.append(Seg(text: buffer, hi: hi)); buffer = "" }
    }
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

/// One line's attributed string and its highlighted UTF-16 ranges.
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
        if current.isEmpty || measure(current + [token], style) <= limit {
            current.append(token)
        } else {
            lines.append(current)
            current = [token]
        }
    }
    if !current.isEmpty { lines.append(current) }
    return lines
}

/// As many lines as a greedy wrap needs, at the narrowest width that keeps that count (even lines, no orphan).
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

/// Balanced lines, preferring a break after a sentence (". ", "! ", "? ", ": ") when that costs no extra line.
func wrap(_ words: Words, _ width: CGFloat, _ style: Style, sentenceBreaks: Bool) -> [Words] {
    let plain = balanced(words, width, style)
    guard sentenceBreaks, plain.count > 1, words.count > 1 else { return plain }
    func widest(_ lines: [Words]) -> CGFloat { lines.map { measure($0, style) }.max() ?? 0 }
    var chosen = plain
    var chosenIsSentence = false
    for i in 0..<(words.count - 1) {
        guard let last = words[i].last?.text.last, ".!?:".contains(last) else { continue }
        let option = balanced(Array(words[...i]), width, style) + balanced(Array(words[(i + 1)...]), width, style)
        guard option.count <= plain.count else { continue }
        if !chosenIsSentence || widest(option) < widest(chosen) {
            chosen = option
            chosenIsSentence = true
        }
    }
    return chosen
}

struct Laid {
    var lines: [CTLine] = []
    var highlights: [[NSRange]] = []
    var widths: [CGFloat] = []
    var lineHeight: CGFloat = 0
    var ascentShare: CGFloat = 0.8
    var size: CGFloat = 0
    var capHeight: CGFloat = 0
    var height: CGFloat { lineHeight * CGFloat(lines.count) }
}

func lay(_ words: Words, _ style: Style, width: CGFloat, sentenceBreaks: Bool, leading: CGFloat) -> Laid {
    var laid = Laid()
    let ascent = CTFontGetAscent(style.font), descent = CTFontGetDescent(style.font)
    laid.lineHeight = (ascent + descent) * leading
    laid.ascentShare = ascent / max(ascent + descent, 1)
    laid.size = CTFontGetSize(style.font)
    laid.capHeight = CTFontGetCapHeight(style.font)
    for lineWords in wrap(words, width, style, sentenceBreaks: sentenceBreaks) {
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
    if let descriptor = base.fontDescriptor.withDesign(.rounded),
       let font = NSFont(descriptor: descriptor, size: size) {
        return font as CTFont
    }
    usedRounded = false
    return base as CTFont
}

let inkColor = srgb(ink)
let subColor = srgb(subInk)
let band = CGRect(x: W * 0.05, y: H * 0.03, width: W * 0.90, height: H * 0.23)   // top-left origin
let capStart = H * 0.046
let capFloor = H * 0.030

var reportCap: CGFloat = 0
var reportLines = 0
var reportFont = ""

func drawLaid(_ laid: Laid, top: CGFloat) {
    for (i, line) in laid.lines.enumerated() {
        let lineTop = top + CGFloat(i) * laid.lineHeight
        let baseline = lineTop + laid.lineHeight * laid.ascentShare     // top-left origin
        let x = band.midX - laid.widths[i] / 2
        let baseCG = H - baseline
        for range in laid.highlights[i] {
            // The marker swash: ink letters on gold, slightly tilted like a highlighter stroke.
            let x0 = CTLineGetOffsetForStringIndex(line, range.location, nil)
            let x1 = CTLineGetOffsetForStringIndex(line, range.location + range.length, nil)
            let pad = laid.size * 0.10
            let swash = CGRect(x: x + x0 - pad, y: baseCG - laid.size * 0.15,
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
        }
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: x, y: baseCG)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

if !rawCaption.trimmingCharacters(in: .whitespaces).isEmpty {
    let parts = rawCaption.components(separatedBy: " / ")
    let headWords = tokenize(parts[0])
    let subText: String? = parts.count > 1 ? parts.dropFirst().joined(separator: " / ") : nil
    let subWords = subText.map { tokenize($0.replacingOccurrences(of: "*", with: "")) } ?? []

    let probe = roundedFont(100, .heavy)
    let capRatio = max(CTFontGetCapHeight(probe) / 100, 0.5)

    var cap = capStart
    var head = Laid()
    var sub: Laid? = nil
    var gap: CGFloat = 0
    while true {
        let size = cap / capRatio
        let headStyle = Style(font: roundedFont(size, .heavy), color: inkColor, kern: -0.008 * size)
        head = lay(headWords, headStyle, width: band.width, sentenceBreaks: true, leading: 0.88)
        sub = nil
        if !subWords.isEmpty {
            var subSize = size * 0.46
            let natural = measure(subWords, Style(font: roundedFont(subSize, .semibold), color: subColor, kern: 0))
            let room = band.width * 0.97
            if natural > room { subSize = max(size * 0.36, subSize * room / max(natural, 1)) }
            let subStyle = Style(font: roundedFont(subSize, .semibold), color: subColor, kern: 0)
            sub = lay(subWords, subStyle, width: band.width, sentenceBreaks: false, leading: 1.0)
        }
        gap = sub == nil ? 0 : size * 0.30
        let total = head.height + gap + (sub?.height ?? 0)
        if (head.lines.count <= 3 && total <= band.height) || cap <= capFloor { break }
        cap = max(capFloor, cap * 0.95)
    }

    let total = head.height + gap + (sub?.height ?? 0)
    let top = max(band.minY, band.midY - total / 2)
    drawLaid(head, top: top)
    if let sub { drawLaid(sub, top: top + head.height + gap) }

    reportCap = cap
    reportLines = head.lines.count
    reportFont = CTFontCopyPostScriptName(roundedFont(10, .heavy)) as String
}

// MARK: Output (opaque sRGB PNG, no alpha)

guard let flat = ctx.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.png" as CFString,
                                                        1, nil) else { fail("cannot create \(output)") }
CGImageDestinationAddImage(destination, flat, nil)
guard CGImageDestinationFinalize(destination) else { fail("cannot write \(output)") }
let capPercent = String(format: "%.1f", Double(reportCap / H * 100))
print("store-frame: \(output) \(width)x\(height) cap=\(capPercent)% lines=\(reportLines) "
      + "font=\(reportFont.isEmpty ? "-" : reportFont) rounded=\(usedRounded ? "yes" : "no")")
