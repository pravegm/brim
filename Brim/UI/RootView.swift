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

    private var demo: DemoConfig? { controller.demo }

    var body: some View {
        GeometryReader { safeGeo in
            let safe = safeGeo.safeAreaInsets
            GeometryReader { geo in
                // Founder's real-Duo recording (26 Oct): lifting the top half from flat blurred the flat half for
                // ~2 s. That is the moment iOS switches the fold's `.division` reserved region on. Apple's guidance
                // is to read reserved regions in the GeometryReader body so the view updates when they arrive; Brim
                // never read them, so nothing in our layout answered the change. The body now depends on the active
                // division (and commits a change when it flips), and the flip is logged for CI.
                let fold = Self.activeDivision(in: geo)
                content(canvas: geo.size, safe: merged(safe, windowInsets))
                    .background(Color.clear.frame(width: 1, height: fold == nil ? 1 : 2))
                    .onChange(of: fold ?? .zero) { _, frame in logFold(frame) }
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
        .onChange(of: reduceMotion) { _, on in controller.setReduceMotion(on) }
        .onChange(of: settings.calmMotion) { _, _ in controller.refreshMotion() }
        .onChange(of: settings.touchOnDuo) { _, _ in controller.refreshInputMode() }
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
        // The window settles its insets a beat after a rotation or a display handover.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            let later = OrientationLock.windowSafeArea()
            if later != windowInsets { windowInsets = later }
        }
    }

    private func handleCanvas(_ canvas: CGSize) {
        let pose = self.pose(for: canvas)
        let fold = hasFold(canvas)
        logCanvas(canvas, hasFold: fold, pose: pose)
        controller.setPose(pose)
        guard pose == .play else { return }
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
        .defersSystemGestures(on: RootView.deferredEdges(paused: controller.isUserPaused || controller.isClosedPaused))
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
    /// live, none while it's paused. Pure.
    static func deferredEdges(paused: Bool) -> Edge.Set {
        paused ? [] : .bottom
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
