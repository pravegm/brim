import SwiftUI

/// Round 8 (REVIEW-6 #6, Glass Cabinet lite): a small sheet from Home that picks the jug Rush and Practice pour from.
/// Venue vessels unlock with Flawless crowns (`GlassCabinet`: 3 → soda dispenser, 6 → shake tin, 10 → potion flask,
/// 14 → copper scoop); the pick is saved in the progress (`ProgressData.vessel`) and drawn by the scene
/// (`GameScene.vesselOverride`). Off the fold: on a Duo the card sits in the flat half under the crease, on a phone at
/// the bottom. A tap outside the card closes it.
struct CabinetSheet: View {
    @ObservedObject var store: ProgressStore
    let info: CanvasInfo
    let onChoose: (VenueID?) -> Void
    let onClose: () -> Void

    /// Pure (tested): where the card's top may start (Duo: below the crease band), and its bottom margin.
    static func margins(info: CanvasInfo) -> (top: CGFloat, bottom: CGFloat) {
        let bottom = max(info.insets.bottom, 12) + 8
        if info.hasFold { return (info.bottomHalfTop + 12, bottom) }
        return (info.hudTop + HUDMetrics.rowHeight + 12, bottom)
    }

    /// The tile's caption: "In use", "Tap to use", or the crowns it still needs. Pure.
    static func caption(for vessel: GlassCabinet.Vessel, crowns: Int, chosen: VenueID?) -> String {
        if !GlassCabinet.isUnlocked(vessel.venue, crowns: crowns) { return "\(vessel.crowns) 👑" }
        return vessel.venue == chosen ? "In use" : "Tap to use"
    }

    private var crowns: Int { store.data.totalCrowns }
    private var chosen: VenueID? { store.data.activeVessel }

    var body: some View {
        let m = Self.margins(info: info)
        return ZStack {
            BrimTheme.ink.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
                .accessibilityLabel("Close the Glass Cabinet")
                .accessibilityAddTraits(.isButton)
            VStack(spacing: 0) {
                if info.hasFold {
                    Color.clear.frame(height: m.top)
                    card
                    Spacer(minLength: m.bottom)
                } else {
                    Spacer(minLength: m.top)
                    card
                    Color.clear.frame(height: m.bottom)
                }
            }
            .padding(.horizontal, info.sidePad)
        }
        .frame(width: info.size.width, height: info.size.height)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Glass Cabinet")
                        .font(BrimTheme.title(24))
                        .foregroundStyle(BrimTheme.ink)
                    Text("Your jug for Rush and Practice")
                        .font(BrimTheme.text(13, .bold))
                        .foregroundStyle(BrimTheme.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill").foregroundStyle(BrimTheme.goldDeep)
                    Text("\(crowns)").font(BrimTheme.number(18))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(BrimTheme.creamDeep))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(crowns) flawless crowns")
                RoundIconButton(systemName: "xmark", size: 40, accessibility: "Close") { onClose() }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(GlassCabinet.vessels) { vessel in
                    tile(vessel)
                }
            }
            if let next = GlassCabinet.nextLine(crowns: crowns) {
                Label("Earn crowns: every glass of a shift Perfect. \(next).", systemImage: "lock.fill")
                    .font(BrimTheme.text(12, .bold))
                    .foregroundStyle(BrimTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: 540)
        .background(
            RoundedRectangle(cornerRadius: BrimTheme.cardRadius, style: .continuous)
                .fill(BrimTheme.card)
                .shadow(color: BrimTheme.ink.opacity(0.22), radius: 18, y: 8)
        )
        .accessibilityElement(children: .contain)
    }

    private func tile(_ vessel: GlassCabinet.Vessel) -> some View {
        let open = GlassCabinet.isUnlocked(vessel.venue, crowns: crowns)
        let inUse = open && vessel.venue == chosen
        let accent = vessel.venue.map { BrimTheme.color(for: $0) } ?? BrimTheme.lemonade
        return Button {
            guard open else { return }
            FeedbackDirector.shared.uiTap()
            onChoose(vessel.venue)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(open ? accent : BrimTheme.creamDeep)
                        .overlay(Circle().stroke(inUse ? BrimTheme.cyan : BrimTheme.ink.opacity(0.12),
                                                 lineWidth: inUse ? 3.5 : 1.5))
                    Image(systemName: open ? Self.symbol(for: vessel.venue) : "lock.fill")
                        .font(.system(size: open ? 20 : 15, weight: .heavy))
                        .foregroundStyle(BrimTheme.ink.opacity(open ? 0.85 : 0.45))
                }
                .frame(width: 52, height: 52)
                Text(vessel.name)
                    .font(BrimTheme.text(12, .heavy))
                    .foregroundStyle(open ? BrimTheme.ink : BrimTheme.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(Self.caption(for: vessel, crowns: crowns, chosen: chosen))
                    .font(BrimTheme.text(11, .bold))
                    .foregroundStyle(inUse ? BrimTheme.ink : BrimTheme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(inUse ? BrimTheme.cyan.opacity(0.14) : BrimTheme.cream)
            )
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!open)
        .accessibilityLabel(open ? "\(vessel.name)\(inUse ? ", in use" : "")"
                                 : "\(vessel.name), locked, needs \(vessel.crowns) crowns")
    }

    /// The tile's symbol: the venue's own (the house jug: a drop).
    static func symbol(for venue: VenueID?) -> String {
        guard let venue else { return "drop.fill" }
        return BrimTheme.symbol(for: venue)
    }
}
