import SpriteKit
import SwiftUI

/// The whole app: the SpriteKit scene full-screen underneath, and the SwiftUI screens on top.
///
/// Safe areas (REVIEW-1 P0-6): the content ignores the safe area (the scene is full-bleed), so the insets are read
/// from an outer GeometryReader that does NOT ignore it, and from the key window (whichever is larger), and handed to
/// every screen in `CanvasInfo.insets`.
struct RootView: View {
    @ObservedObject var controller: GameController
    @ObservedObject var store: ProgressStore
    @ObservedObject var settings: SettingsStore

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launched = false
    @State private var dragging = false
    @State private var windowInsets = EdgeInsets()
    @State private var lastCanvasLog = ""
    /// The interface is upside down (the system already put the counter on the phone's natural top half).
    @State private var upsideDown = false
    /// The game is drawn turned round (mirrors `turnsRound` for the play layer's system-gesture edges).
    @State private var turnedRound = false

    private var demo: DemoConfig? { controller.demo }

    var body: some View {
        GeometryReader { safeGeo in
            let safe = safeGeo.safeAreaInsets
            GeometryReader { geo in
                // Founder's real Duo (26 Oct, builds 6–7): as a fold starts from flat, iOS's own fold transition
                // blurs one physical half of the inner display for ~2 s. It does this in every app (Photos too), it
                // stays on the same half when the phone is turned round, and apps can't opt out. In Brim's upright
                // layout that half is the counter, so the glasses blurred on every pour. "Glasses on the sharp half"
                // (on by default) draws the game turned round on a Duo: the player turns the phone round, the glasses
                // sit on the half that stays sharp, and the half they lift (the jug) takes the blur.
                let fold = Self.activeDivision(in: geo)
                let turned = turnsRound(geo.size)
                content(canvas: geo.size, safe: Self.insets(merged(safe, windowInsets), turnedRound: turned))
                    .rotationEffect(turned ? .degrees(180) : .zero)
                    .animation(nil, value: turned)
                    .onChange(of: fold ?? .zero) { _, frame in logFold(frame) }
                    .task(id: turned) {
                        turnedRound = turned
                        logTurned(turned)
                    }
            }
            .ignoresSafeArea()
        }
        .background(BrimTheme.cream.ignoresSafeArea())
        .modifier(HingeReader(onUpdate: { angle, time in
            controller.hingeSample(angle: angle, time: time)
        }, onUnavailable: {
            controller.hingeUnavailable()
        }))
        .onChange(of: scenePhase) { _, phase in
            controller.setAppActive(phase == .active)
            if phase == .active { refreshWindowInsets() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            refreshWindowInsets()
        }
        .onChange(of: reduceMotion) { _, on in controller.setReduceMotion(on) }
        .onChange(of: settings.calmMotion) { _, _ in controller.refreshMotion() }
        .onChange(of: settings.touchOnDuo) { _, _ in controller.refreshInputMode() }
        .onChange(of: settings.sharpSide) { _, on in
            if demo == nil { OrientationLock.setSharpSide(on) }
        }
        .preferredColorScheme(.light)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    @ViewBuilder
    private func content(canvas: CGSize, safe: EdgeInsets) -> some View {
        let pose = self.pose(for: canvas)
        let rect = PoseRule.playRect(in: canvas)
        let column = rect.width < canvas.width - 1
        let info = CanvasInfo(size: rect.size,
                              insets: column ? EdgeInsets(top: safe.top, leading: 0, bottom: safe.bottom, trailing: 0) : safe,
                              hasFold: hasFold(canvas))
        ZStack {
            BrimTheme.cream
            gameLayer(rect, hidden: pose != .play)
            switch pose {
            case .play:
                screenLayer(info)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            case .standUp:
                StandUpCard(insets: safe,
                            onTurnScreen: { OrientationLock.requestPortrait() },
                            onPlayWithTouch: { controller.chooseTouchInBookPose() })
                    .transition(.opacity)
            case .cover:
                CoverView(store: store)
                    .transition(.opacity)
            }
            if demo?.screen == .icon {
                iconLayer(canvas)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .animation(BrimTheme.settle(reduceMotion), value: pose)
        .onAppear {
            refreshWindowInsets()
            handleCanvas(canvas)
            launchOnce()
        }
        .onChange(of: canvas) { _, newSize in
            refreshWindowInsets()
            controller.canvasDidChange(newSize)
            handleCanvas(newSize)
        }
        .onChange(of: pose) { _, _ in handleCanvas(canvas) }
        .onChange(of: controller.hingeSeen) { _, _ in handleCanvas(canvas) }
        .onChange(of: controller.isShut) { _, _ in handleCanvas(canvas) }
        .onChange(of: controller.bookTouchOverride) { _, _ in handleCanvas(canvas) }
    }

    // MARK: - Pose and canvas

    private func pose(for canvas: CGSize) -> DevicePose {
        if let screen = demo?.screen {
            if screen == .standup { return .standUp }
            if screen == .cover { return .cover }
        }
        return PoseRule.pose(canvas: canvas, hingeSeen: controller.hingeSeen, isShut: controller.isShut,
                             bookTouchOverride: controller.bookTouchOverride)
    }

    private func hasFold(_ canvas: CGSize) -> Bool {
        PoseRule.hasFold(canvas: canvas, hingeSeen: controller.hingeSeen)
    }

    private func merged(_ a: EdgeInsets, _ b: EdgeInsets) -> EdgeInsets {
        EdgeInsets(top: max(a.top, b.top), leading: max(a.leading, b.leading),
                   bottom: max(a.bottom, b.bottom), trailing: max(a.trailing, b.trailing))
    }

    private func refreshWindowInsets() {
        let read = OrientationLock.windowSafeArea()
        if read != windowInsets { windowInsets = read }
        let flipped = OrientationLock.interfaceIsUpsideDown()
        if flipped != upsideDown {
            upsideDown = flipped
            logUpsideDown(flipped)
        }
        // The window settles its insets a beat after a rotation or a display handover.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            let later = OrientationLock.windowSafeArea()
            if later != windowInsets { windowInsets = later }
            let laterFlipped = OrientationLock.interfaceIsUpsideDown()
            if laterFlipped != upsideDown {
                upsideDown = laterFlipped
                logUpsideDown(laterFlipped)
            }
        }
    }

    /// Whether to draw the game turned round right now (see the GeometryReader note in `body`).
    private func turnsRound(_ canvas: CGSize) -> Bool {
        let wanted = demo.map { $0.flip } ?? settings.sharpSide
        // Read live (the interface turns before our orientation notification lands); the state only re-renders.
        _ = upsideDown
        return Self.turnsRound(wanted: wanted, pose: pose(for: canvas), hasFold: hasFold(canvas),
                               upsideDown: OrientationLock.interfaceIsUpsideDown())
    }

    /// Pure rule (tested): only the Duo's tabletop canvas turns round, and never when the interface is already upside
    /// down: either way the counter lands on the phone's natural top half, which iOS's fold blur leaves sharp. Brim asks
    /// iOS for upside down (OrientationLock.sharpSide), so system banners turn too; this is the fallback if iOS won't.
    static func turnsRound(wanted: Bool, pose: DevicePose, hasFold: Bool, upsideDown: Bool) -> Bool {
        wanted && pose == .play && hasFold && !upsideDown
    }

    /// The safe-area insets in the drawn layout's terms: turned round, the top inset is at the bottom and so on. Pure.
    static func insets(_ safe: EdgeInsets, turnedRound: Bool) -> EdgeInsets {
        guard turnedRound else { return safe }
        return EdgeInsets(top: safe.bottom, leading: safe.trailing, bottom: safe.top, trailing: safe.leading)
    }

    private func handleCanvas(_ canvas: CGSize) {
        let pose = self.pose(for: canvas)
        let fold = hasFold(canvas)
        logCanvas(canvas, hasFold: fold, pose: pose)
        controller.setPose(pose)
        guard pose == .play else { return }
        if fold { OrientationLock.settleTabletop() }
        if canvas.height >= canvas.width { controller.clearBookTouchOverride() }
        controller.updateCanvas(PoseRule.playRect(in: canvas).size, hasFold: fold)
    }

    /// The active fold (`.division` reserved region, iOS 27.1): present only while the Duo is partly folded.
    private static func activeDivision(in proxy: GeometryProxy) -> CGRect? {
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division).first?.frame
        }
        return nil
    }

    private func logFold(_ frame: CGRect) {
        #if DEBUG
        if frame == .zero {
            print("BRIM-T fold inactive")
        } else {
            print(String(format: "BRIM-T fold active %.0f,%.0f %.0fx%.0f", frame.minX, frame.minY, frame.width, frame.height))
        }
        fflush(stdout)
        #endif
    }

    private func logUpsideDown(_ on: Bool) {
        #if DEBUG
        print("BRIM-T interface upside down \(on ? 1 : 0)")
        fflush(stdout)
        #endif
    }

    private func logTurned(_ on: Bool) {
        #if DEBUG
        print("BRIM-T turned round \(on ? 1 : 0)")
        fflush(stdout)
        #endif
    }

    private func logCanvas(_ canvas: CGSize, hasFold: Bool, pose: DevicePose) {
        #if DEBUG
        guard canvas.width > 1, canvas.height > 1 else { return }
        let line = "BRIM-T canvas \(Int(canvas.width.rounded()))x\(Int(canvas.height.rounded())) hasFold=\(hasFold) pose=\(pose.rawValue)"
        guard line != lastCanvasLog else { return }
        lastCanvasLog = line
        print(line)
        #endif
    }

    private func launchOnce() {
        guard !launched else { return }
        launched = true
        controller.setReduceMotion(reduceMotion)
        OrientationLock.setSharpSide(demo.map { $0.flip } ?? settings.sharpSide)
        controller.launch()
        if demo?.orientPortrait == true { DemoOrientation.requestPortrait() }
    }

    // MARK: - Layers

    /// QA-1 P2-7 (battery): the scene stops rendering while an opaque screen covers it — Venues, Settings, the results
    /// card, the book-pose and cover cards. Real runs only: CI's demo launches wait for the scene's `BRIM-T frame 120`.
    private func sceneIdle(hidden: Bool) -> Bool {
        guard demo == nil else { return false }
        if hidden { return true }
        switch controller.route {
        case .venues, .settings, .results: return true
        case .home, .playing: return false
        }
    }

    @ViewBuilder
    private func gameLayer(_ rect: CGRect, hidden: Bool) -> some View {
        if let scene = controller.scene {
            SpriteView(scene: scene, isPaused: sceneIdle(hidden: hidden), preferredFramesPerSecond: 120)
                .id(controller.sceneGeneration)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func screenLayer(_ info: CanvasInfo) -> some View {
        ZStack {
            switch controller.route {
            case .home:
                HomeView(controller: controller, store: store, info: info)
                    .transition(.opacity)
            case .venues:
                VenuesView(controller: controller, store: store, info: info)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .settings:
                SettingsView(controller: controller, store: store, settings: settings, info: info)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .playing:
                playLayer(info)
                    .transition(.opacity)
            case .results:
                if let summary = controller.summary {
                    ResultsView(controller: controller, summary: summary, info: info)
                        .transition(.opacity)
                }
            }
        }
        .animation(BrimTheme.settle(reduceMotion), value: controller.route)
    }

    @ViewBuilder
    private func playLayer(_ info: CanvasInfo) -> some View {
        ZStack {
            if controller.usesTouch && !controller.isUserPaused && !controller.isClosedPaused {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !dragging {
                                    dragging = true
                                    controller.touch.began(at: value.startLocation.y)
                                }
                                controller.touch.moved(to: value.location.y)
                            }
                            .onEnded { _ in
                                dragging = false
                                controller.touch.ended()
                            }
                    )
                    .accessibilityLabel("Pour")
                    .accessibilityHint("Drag up to tip the jug, let go to stop")
            }
            HintsOverlay(hud: controller.hud, hint: controller.activeHint, touch: controller.usesTouch, info: info)
                .allowsHitTesting(false)
            // Round 6: the one-time venue intro card (only the card takes a tap) and the shift / Rush tier banner.
            VenueIntroOverlay(hud: controller.hud, hint: controller.activeHint, info: info,
                              onDismiss: { controller.dismissHint() })
            PlayBannerView(hud: controller.hud, info: info)
            // Only its card takes touches ("Use touch instead", ROUND-5 decision 1).
            FlatGateOverlay(hud: controller.hud, info: info, onUseTouch: { controller.useTouchForThisRun() })
            HUDView(hud: controller.hud, mode: controller.mode, title: controller.hudTitle,
                    info: info, calm: controller.calmMotion, onPause: { controller.pause() })
            if controller.isUserPaused {
                PauseView(controller: controller, info: info)
                    .transition(.opacity)
            } else if controller.isClosedPaused {
                ClosedPauseView(controller: controller, info: info)
                    .transition(.opacity)
            }
        }
        .animation(BrimTheme.settle(reduceMotion), value: controller.isUserPaused)
        .animation(BrimTheme.settle(reduceMotion), value: controller.isClosedPaused)
        // QA-2 P2-9: a drag that starts in the bottom ~20 pt must pour, not go Home mid-run. iOS then needs a second
        // swipe for Home while a run is live; the pause cards give the edge back.
        .defersSystemGestures(on: RootView.deferredEdges(paused: controller.isUserPaused || controller.isClosedPaused,
                                                         turnedRound: turnedRound))
        .onChange(of: controller.isUserPaused) { _, paused in
            if paused && dragging {
                dragging = false
                controller.touch.ended()
            }
        }
        .onChange(of: controller.isClosedPaused) { _, paused in
            if paused && dragging {
                dragging = false
                controller.touch.ended()
            }
        }
    }

    /// The screen edges whose system gestures wait for a second swipe during play: the bottom (Home) while a run is
    /// live, none while it's paused. Turned round, the Home edge is at the drawn top, so both ends wait. Pure.
    static func deferredEdges(paused: Bool, turnedRound: Bool = false) -> Edge.Set {
        if paused { return [] }
        return turnedRound ? [.top, .bottom] : .bottom
    }

    private func iconLayer(_ canvas: CGSize) -> some View {
        let side = min(canvas.width, canvas.height)
        return ZStack {
            Color.black
            AppIconArt()
                .frame(width: side, height: side)
        }
        .frame(width: canvas.width, height: canvas.height)
        .onAppear { IconExport.render() }
    }
}
