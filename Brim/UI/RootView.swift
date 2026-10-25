import SpriteKit
import SwiftUI

/// What the inner (or cover) display should show, from the canvas shape and the hinge.
enum DevicePose: Equatable {
    /// Tabletop on a Duo, or any portrait phone: the game and its screens.
    case play
    /// Duo in book pose (landscape canvas): "Stand me up like a little laptop". The game is paused.
    case standUp
    /// Duo shut (hinge ≤ 15°) or the small cover display: "Open me to pour".
    case cover
}

/// The whole app: the SpriteKit scene full-screen underneath, and the SwiftUI screens on top.
struct RootView: View {
    @ObservedObject var controller: GameController
    @ObservedObject var store: ProgressStore
    @ObservedObject var settings: SettingsStore

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launched = false
    @State private var dragging = false

    private var demo: DemoConfig? { controller.demo }

    var body: some View {
        GeometryReader { geo in
            let canvas = geo.size
            let pose = self.pose(for: canvas)
            let rect = playRect(in: canvas)
            let info = CanvasInfo(size: rect.size,
                                  insets: insets(geo.safeAreaInsets, column: rect.width < canvas.width - 1),
                                  crease: hasFold(canvas) ? (rect.height / 2 - 20)...(rect.height / 2 + 20) : nil)
            ZStack {
                BrimTheme.cream
                gameLayer(rect)
                switch pose {
                case .play:
                    screenLayer(info)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                case .standUp:
                    StandUpCard(onPlayWithTouch: { controller.chooseTouchInBookPose() })
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
                handleCanvas(canvas)
                launchOnce()
            }
            .onChange(of: canvas) { _, newSize in handleCanvas(newSize) }
            .onChange(of: pose) { _, _ in handleCanvas(canvas) }
            .onChange(of: controller.hingeSeen) { _, _ in handleCanvas(canvas) }
            .onChange(of: controller.bookTouchOverride) { _, _ in handleCanvas(canvas) }
        }
        .ignoresSafeArea()
        .background(BrimTheme.cream.ignoresSafeArea())
        .modifier(HingeReader(onUpdate: { angle, time in
            controller.hingeSample(angle: angle, time: time)
        }, onUnavailable: {
            controller.hingeUnavailable()
        }))
        .onChange(of: scenePhase) { _, phase in controller.setAppActive(phase == .active) }
        .onChange(of: reduceMotion) { _, on in controller.setReduceMotion(on) }
        .onChange(of: settings.touchOnDuo) { _, _ in controller.refreshInputMode() }
        .preferredColorScheme(.light)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Pose and canvas

    /// Both Duo displays are ~0.7 wide-to-tall; other iPhones ~0.46. The inner display is ≥ 600 pt on its short side.
    private func looksLikeDuoInner(_ size: CGSize) -> Bool {
        let short = min(size.width, size.height)
        let long = max(size.width, size.height)
        guard long > 0 else { return false }
        return short / long > 0.62 && short >= 600
    }

    private func pose(for canvas: CGSize) -> DevicePose {
        if let screen = demo?.screen {
            if screen == .standup { return .standUp }
            if screen == .cover { return .cover }
        }
        let duo = controller.hingeSeen
        if duo && controller.isShut { return .cover }
        if duo && max(canvas.width, canvas.height) < 800 { return .cover }
        if canvas.width > canvas.height && !controller.bookTouchOverride && (duo || looksLikeDuoInner(canvas)) {
            return .standUp
        }
        return .play
    }

    /// The game canvas: the whole screen in portrait; a centred portrait column on a landscape canvas (book pose
    /// with "Play with touch instead").
    private func playRect(in canvas: CGSize) -> CGRect {
        guard canvas.width > canvas.height else { return CGRect(origin: .zero, size: canvas) }
        let width = min(canvas.width, (canvas.height * 0.70).rounded())
        return CGRect(x: ((canvas.width - width) / 2).rounded(), y: 0, width: width, height: canvas.height)
    }

    /// A horizontal fold runs across the middle of a portrait Duo inner display.
    private func hasFold(_ canvas: CGSize) -> Bool {
        guard canvas.height > canvas.width else { return false }
        return controller.hingeSeen || looksLikeDuoInner(canvas)
    }

    private func insets(_ safe: EdgeInsets, column: Bool) -> EdgeInsets {
        column ? EdgeInsets(top: safe.top, leading: 0, bottom: safe.bottom, trailing: 0) : safe
    }

    private func handleCanvas(_ canvas: CGSize) {
        let pose = self.pose(for: canvas)
        controller.setPosePaused(pose != .play)
        guard pose == .play else { return }
        if canvas.height >= canvas.width { controller.clearBookTouchOverride() }
        controller.updateCanvas(playRect(in: canvas).size, hasFold: hasFold(canvas))
    }

    private func launchOnce() {
        guard !launched else { return }
        launched = true
        controller.setReduceMotion(reduceMotion)
        controller.launch()
        if demo?.orientPortrait == true { DemoOrientation.requestPortrait() }
    }

    // MARK: - Layers

    @ViewBuilder
    private func gameLayer(_ rect: CGRect) -> some View {
        if let scene = controller.scene {
            SpriteView(scene: scene, preferredFramesPerSecond: 120)
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
            if controller.usesTouch && !controller.isUserPaused {
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
            HintsOverlay(hint: controller.activeHint, touch: controller.usesTouch, info: info)
                .allowsHitTesting(false)
            HUDView(hud: controller.hud, mode: controller.mode, info: info, onPause: { controller.pause() })
            if controller.isUserPaused {
                PauseView(controller: controller, info: info)
                    .transition(.opacity)
            }
        }
        .animation(BrimTheme.settle(reduceMotion), value: controller.isUserPaused)
        .onChange(of: controller.isUserPaused) { _, paused in
            if paused && dragging {
                dragging = false
                controller.touch.ended()
            }
        }
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
