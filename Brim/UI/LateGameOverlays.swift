import SwiftUI

// Round 6 (ROUND-6 decisions 1 and 2, REVIEW-5 §1 and §5): teach every venue's idea once, announce each shift, and
// make the Rush tiers visible. Everything here sits OFF the fold: on a Duo in the raised half, on a phone under the HUD
// (the banner) or in the open air between the jug and the glass (the intro card).

// MARK: - Venue intro card (one per venue, stored in hintsSeen)

/// Copy and placement of the one-time venue intro cards. Pure; tested.
enum VenueIntroCard {
    /// The card's estimated height (art, venue name, up to three lines, footer), for placement.
    static let estimatedHeight: CGFloat = 206
    /// Room kept free under the HUD row for the shift banner.
    static let bannerLane: CGFloat = 52

    /// One line, a verb first (REVIEW-5 §1).
    static func line(for hint: HintKind) -> String {
        switch hint {
        case .foam: return "Foam rises after you stop. Pour slow, let it settle, top up."
        case .thick: return "Thick drinks keep coming. Stop well before the line."
        case .belt: return "Glasses ride past. Start pouring before they reach the spout."
        case .fade: return "The line vanishes. Remember where it was."
        case .sand: return "Sand sticks, then slides all at once. Tip slowly, stop early."
        case .lift, .stop, .anticipate: return ""
        }
    }

    /// QA-3 P2-10: the card waits while the Duo's flat gate is closed, not only while the gate's card shows (that card
    /// is delayed 0.35 s, so the intro card used to pop in and then vanish under it). Pure.
    static func isVisible(hint: HintKind?, gateClosed: Bool, showFlatGate: Bool) -> Bool {
        guard let hint, hint.isVenueIntro else { return false }
        return !gateClosed && !showFlatGate
    }

    static func title(for hint: HintKind) -> String {
        guard let venue = hint.introVenue else { return "" }
        return LevelCatalog.title(of: venue)
    }

    /// Where the card goes and how wide it is. Duo: the raised half, beside the jug (the hint rules), else centred in the
    /// raised half under the banner lane; never on the crease. Phone: the open air in the middle of the screen (between
    /// the jug and the glass), under the banner lane.
    static func spot(height: CGFloat = estimatedHeight, anchors: PlayAnchors?, info: CanvasInfo)
        -> (center: CGPoint, width: CGFloat) {
        let laneTop = info.hudTop + HUDMetrics.rowHeight + bannerLane
        if info.hasFold {
            let width = min(max(info.size.width * 0.36, 210), 250)
            let s = HintSpot.place(size: CGSize(width: width, height: height), anchors: anchors, info: info,
                                   topGap: bannerLane)
            if !s.compact { return (s.center, s.width) }
            let bottom = info.topHalfHeight - 8
            let y = max(min((laneTop + bottom) / 2, bottom - height / 2), laneTop + height / 2)
            return (CGPoint(x: info.size.width / 2, y: y), width)
        }
        let width = min(info.size.width - 2 * info.sidePad, 320)
        let bottom = info.size.height - max(info.insets.bottom, 12)
        let y = max(min(info.topHalfHeight, bottom - height / 2), laneTop + height / 2)
        return (CGPoint(x: info.size.width / 2, y: y), width)
    }
}

/// The intro card over the play scene. Only the card takes touches (a tap dismisses it); a drag anywhere else pours,
/// and the first pour dismisses it too (GameController). Hidden while the Duo's flat gate is closed (QA-3 P2-10). While
/// it is up the run holds (`GameSession.setStartHold`, QA-3 P1-3): no belt, patience or line fade under the card.
struct VenueIntroOverlay: View {
    @ObservedObject var hud: HUDState
    let hint: HintKind?
    let info: CanvasInfo
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.clear
                .allowsHitTesting(false)
            if let hint, VenueIntroCard.isVisible(hint: hint, gateClosed: hud.gateClosed, showFlatGate: hud.showFlatGate) {
                let spot = VenueIntroCard.spot(anchors: hud.anchors, info: info)
                Button {
                    FeedbackDirector.shared.uiTap()
                    onDismiss()
                } label: {
                    VenueIntroCardView(hint: hint)
                }
                .buttonStyle(PressScaleStyle())
                .frame(width: spot.width)
                .position(spot.center)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .accessibilityHint("Pour, or double-tap to close")
            }
        }
        .frame(width: info.size.width, height: info.size.height)
        .animation(BrimTheme.pop(reduceMotion), value: hint)
        .animation(BrimTheme.pop(reduceMotion), value: hud.showFlatGate)
        .animation(BrimTheme.pop(reduceMotion), value: hud.gateClosed)
    }
}

struct VenueIntroCardView: View {
    let hint: HintKind

    private var accent: Color { hint.introVenue.map { BrimTheme.color(for: $0) } ?? BrimTheme.gold }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(spacing: 7) {
            VenueIntroArt(hint: hint)
                .frame(width: 150, height: 64)
            Text(VenueIntroCard.title(for: hint).uppercased())
                .font(BrimTheme.text(12, .heavy))
                .kerning(1)
                .foregroundStyle(BrimTheme.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(VenueIntroCard.line(for: hint))
                .font(BrimTheme.text(16, .heavy))
                .foregroundStyle(BrimTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Pour to start, or tap to close")
                .font(BrimTheme.text(11, .bold))
                .foregroundStyle(BrimTheme.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity)
        .background(
            shape.fill(BrimTheme.card)
                .shadow(color: BrimTheme.ink.opacity(0.2), radius: 12, y: 6)
        )
        .overlay(shape.stroke(accent, lineWidth: 3))
        .accessibilityElement(children: .combine)
    }
}

/// The card's tiny two-frame diagram (REVIEW-5 §1: "a 2-frame mini diagram"): frame 0 is the moment to act, frame 1
/// what happens next. Alternates every 1.1 s; Reduce Motion holds frame 1.
struct VenueIntroArt: View {
    let hint: HintKind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.1)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / 1.1)
            let frame = reduceMotion ? 1 : (tick % 2)
            Canvas { ctx, size in
                VenueIntroArt.draw(hint, frame: frame, in: &ctx, size: size)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    private static let ink = BrimTheme.ink
    private static let glassFill = Color.white.opacity(0.75)

    /// A tumbler standing on `baseY`, centred on `cx`: `fill`/`line` are fractions of its height. Returns its outline.
    @discardableResult
    private static func glass(_ ctx: inout GraphicsContext, cx: CGFloat, baseY: CGFloat, width: CGFloat, height: CGFloat,
                              fill: CGFloat, liquid: Color, foam: CGFloat = 0, foamColor: Color = .white,
                              line: CGFloat?, lineColor: Color = BrimTheme.cyan, lineOpacity: Double = 1,
                              ghostLine: Bool = false) -> Path {
        let top = baseY - height
        let inset = width * 0.12
        var outline = Path()
        outline.move(to: CGPoint(x: cx - width / 2, y: top))
        outline.addLine(to: CGPoint(x: cx + width / 2, y: top))
        outline.addLine(to: CGPoint(x: cx + width / 2 - inset, y: baseY))
        outline.addLine(to: CGPoint(x: cx - width / 2 + inset, y: baseY))
        outline.closeSubpath()
        ctx.fill(outline, with: .color(glassFill))
        var inner = ctx
        inner.clip(to: outline)
        let level = baseY - height * min(max(fill, 0), 1)
        inner.fill(Path(CGRect(x: cx - width, y: level, width: 2 * width, height: baseY - level)), with: .color(liquid))
        if foam > 0 {
            let foamTop = level - height * foam
            inner.fill(Path(CGRect(x: cx - width, y: foamTop, width: 2 * width, height: level - foamTop)),
                       with: .color(foamColor))
        }
        ctx.stroke(outline, with: .color(ink.opacity(0.8)), lineWidth: 1.6)
        if let line {
            let y = baseY - height * line
            var mark = Path()
            mark.move(to: CGPoint(x: cx - width / 2 - 3, y: y))
            mark.addLine(to: CGPoint(x: cx + width / 2 + 3, y: y))
            if ghostLine {
                ctx.stroke(mark, with: .color(lineColor.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [2, 3]))
            } else {
                ctx.stroke(mark, with: .color(lineColor.opacity(lineOpacity)),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
        }
        return outline
    }

    private static func stream(_ ctx: inout GraphicsContext, x: CGFloat, from y0: CGFloat, to y1: CGFloat, width: CGFloat,
                               color: Color) {
        var p = Path()
        p.move(to: CGPoint(x: x, y: y0))
        p.addLine(to: CGPoint(x: x, y: y1))
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private static func arrow(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, color: Color) {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        let angle = atan2(b.y - a.y, b.x - a.x)
        let head: CGFloat = 5
        p.move(to: b)
        p.addLine(to: CGPoint(x: b.x - head * cos(angle - 0.5), y: b.y - head * sin(angle - 0.5)))
        p.move(to: b)
        p.addLine(to: CGPoint(x: b.x - head * cos(angle + 0.5), y: b.y - head * sin(angle + 0.5)))
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    static func draw(_ hint: HintKind, frame: Int, in ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let baseY = h - 3
        let cx = w / 2
        switch hint {
        case .foam:
            // 0: pouring, the head climbs past the line. 1: settled under the line, ready to top up.
            let cola = Color(brimHex: 0x8A4A22)
            let cream = Color(brimHex: 0xFFF6E6)
            if frame == 0 {
                stream(&ctx, x: cx, from: 0, to: baseY - 30, width: 4, color: cola)
                glass(&ctx, cx: cx, baseY: baseY, width: 34, height: 46, fill: 0.38, liquid: cola, foam: 0.42,
                      foamColor: cream, line: 0.7)
                arrow(&ctx, from: CGPoint(x: cx + 30, y: baseY - 14), to: CGPoint(x: cx + 30, y: baseY - 40),
                      color: BrimTheme.goldDeep)
            } else {
                glass(&ctx, cx: cx, baseY: baseY, width: 34, height: 46, fill: 0.6, liquid: cola, foam: 0.08,
                      foamColor: cream, line: 0.7)
                arrow(&ctx, from: CGPoint(x: cx + 30, y: baseY - 40), to: CGPoint(x: cx + 30, y: baseY - 18),
                      color: BrimTheme.mintDeep)
            }
        case .thick:
            // 0: the player stopped, the thick ribbon is still falling. 1: it landed right on the line.
            let shake = Color(brimHex: 0xEE8FB0)
            if frame == 0 {
                stream(&ctx, x: cx, from: 4, to: baseY - 22, width: 7, color: shake)
                glass(&ctx, cx: cx, baseY: baseY, width: 36, height: 46, fill: 0.45, liquid: shake, line: 0.72)
                // "Stop here": a short mark at the stop height, left of the glass.
                let stopY = baseY - 46 * 0.45
                var tick = Path()
                tick.move(to: CGPoint(x: cx - 34, y: stopY))
                tick.addLine(to: CGPoint(x: cx - 24, y: stopY))
                ctx.stroke(tick, with: .color(BrimTheme.spill), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            } else {
                glass(&ctx, cx: cx, baseY: baseY, width: 36, height: 46, fill: 0.72, liquid: shake, line: 0.72)
            }
        case .belt:
            // The belt, the stream at the spout; 0: the glass is still coming and the pour has started. 1: under it.
            let water = Color(brimHex: 0x7CC8F2)
            var belt = Path(roundedRect: CGRect(x: 4, y: baseY, width: w - 8, height: 4), cornerRadius: 2)
            ctx.fill(belt, with: .color(Color(brimHex: 0x4A4F5C)))
            belt = Path()
            for i in 0..<3 {
                let x = 18 + CGFloat(i) * 12
                belt.move(to: CGPoint(x: x, y: baseY - 9))
                belt.addLine(to: CGPoint(x: x + 4, y: baseY - 6))
                belt.addLine(to: CGPoint(x: x, y: baseY - 3))
            }
            ctx.stroke(belt, with: .color(BrimTheme.goldDeep), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            let spoutX = cx + 18
            if frame == 0 {
                stream(&ctx, x: spoutX, from: 0, to: baseY - 40, width: 4, color: water)
                glass(&ctx, cx: spoutX - 34, baseY: baseY, width: 28, height: 36, fill: 0.15, liquid: water, line: 0.75)
            } else {
                stream(&ctx, x: spoutX, from: 0, to: baseY - 24, width: 4, color: water)
                glass(&ctx, cx: spoutX, baseY: baseY, width: 28, height: 36, fill: 0.6, liquid: water, line: 0.75)
            }
        case .fade:
            // A potion beaker; 0: read the line. 1: the line is gone (a ghost of where it was), pour to the memory.
            let potion = Color(brimHex: 0x8B6CF0)
            if frame == 0 {
                glass(&ctx, cx: cx, baseY: baseY, width: 30, height: 50, fill: 0.25, liquid: potion, line: 0.62)
                // A spark: "remember this".
                var spark = Path()
                spark.addEllipse(in: CGRect(x: cx + 22, y: baseY - 50 * 0.62 - 3, width: 6, height: 6))
                ctx.fill(spark, with: .color(BrimTheme.gold))
            } else {
                glass(&ctx, cx: cx, baseY: baseY, width: 30, height: 50, fill: 0.6, liquid: potion, line: 0.62,
                      ghostLine: true)
            }
        case .sand:
            // 0: the scoop tips slowly, a few grains at the lip. 1: it slides all at once into a heap.
            let sand = Color(brimHex: 0xE4C08A)
            let sandDeep = Color(brimHex: 0xC79A5B)
            let tilt: Double = frame == 0 ? 18 : 34
            var scoop = ctx
            scoop.translateBy(x: cx - 18, y: 18)
            scoop.rotate(by: .degrees(tilt))
            let body = Path(roundedRect: CGRect(x: -22, y: -10, width: 40, height: 20), cornerRadius: 6)
            scoop.fill(body, with: .color(Color(brimHex: 0xC77B4A)))
            scoop.fill(Path(roundedRect: CGRect(x: -18, y: -6, width: 30, height: 9), cornerRadius: 3),
                       with: .color(sand))
            scoop.stroke(body, with: .color(ink.opacity(0.7)), lineWidth: 1.4)
            let glassX = cx + 14
            if frame == 0 {
                for i in 0..<3 {
                    let g = CGRect(x: cx + 2 + CGFloat(i) * 2, y: 30 + CGFloat(i) * 6, width: 2.5, height: 2.5)
                    ctx.fill(Path(ellipseIn: g), with: .color(sandDeep))
                }
                glass(&ctx, cx: glassX, baseY: baseY, width: 32, height: 30, fill: 0.15, liquid: sand, line: 0.7,
                      lineColor: BrimTheme.cyan)
            } else {
                stream(&ctx, x: cx + 4, from: 26, to: baseY - 18, width: 7, color: sandDeep)
                let outline = glass(&ctx, cx: glassX, baseY: baseY, width: 32, height: 30, fill: 0.45, liquid: sand,
                                    line: 0.7, lineColor: BrimTheme.cyan)
                // The heap: a cone over the level, not a flat surface.
                var heap = Path()
                let level = baseY - 30 * 0.45
                heap.move(to: CGPoint(x: glassX - 14, y: level))
                heap.addQuadCurve(to: CGPoint(x: glassX + 14, y: level), control: CGPoint(x: glassX - 6, y: level - 16))
                heap.closeSubpath()
                var inner = ctx
                inner.clip(to: outline)
                inner.fill(heap, with: .color(sand))
            }
        case .lift, .stop, .anticipate:
            break
        }
    }
}

// MARK: - Shift and Rush tier banners

/// The banner under the HUD row: "Shift 6 · Slow Pour, Fast Belt" during the intro phase, "TIER 3 · BELTS!" when a
/// Rush tier changes. In the raised half on a Duo (well clear of the crease), under the HUD on a phone. Never takes
/// touches.
struct PlayBannerView: View {
    @ObservedObject var hud: HUDState
    let info: CanvasInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 40

    /// The banner's lane on the canvas (from the top). Pure; tested (never on the fold).
    static func lane(info: CanvasInfo) -> CGRect {
        let top = info.hudTop + HUDMetrics.rowHeight + 6
        return CGRect(x: info.sidePad, y: top, width: max(info.size.width - 2 * info.sidePad, 0), height: height)
    }

    var body: some View {
        let lane = Self.lane(info: info)
        return ZStack(alignment: .top) {
            Color.clear
            if let banner = hud.banner {
                label(banner)
                    .frame(maxWidth: min(lane.width, 460))
                    .frame(height: lane.height)
                    .id(banner.serial)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .padding(.top, lane.minY)
            }
        }
        .frame(width: info.size.width, height: info.size.height, alignment: .top)
        .animation(BrimTheme.pop(reduceMotion), value: hud.banner)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func label(_ banner: PlayBanner) -> some View {
        switch banner.kind {
        case .shift:
            Text(banner.text)
                .font(BrimTheme.text(17, .heavy))
                .foregroundStyle(BrimTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(BrimTheme.card).shadow(color: BrimTheme.ink.opacity(0.18), radius: 8, y: 3))
                .accessibilityLabel(banner.text)
        case .tier:
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16, weight: .black))
                Text(banner.text)
                    .font(BrimTheme.title(21))
                    .kerning(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(BrimTheme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(Capsule().fill(BrimTheme.gold).shadow(color: BrimTheme.ink.opacity(0.25), radius: 8, y: 3))
            .overlay(Capsule().stroke(BrimTheme.cyan.opacity(0.9), lineWidth: 2.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(banner.text)
        }
    }
}

// MARK: - Flawless crown mark (Venues bubbles, results)

/// A small gold crown on a cyan disc: the shift was cleared with every glass Perfect.
struct CrownMark: View {
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: size * 0.55, weight: .black))
            .foregroundStyle(BrimTheme.gold)
            .frame(width: size, height: size)
            .background(Circle().fill(BrimTheme.ink))
            .overlay(Circle().stroke(BrimTheme.cyan, lineWidth: max(1.5, size * 0.09)))
            .accessibilityLabel("Flawless crown")
    }
}
