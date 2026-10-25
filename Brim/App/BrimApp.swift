import SwiftUI

@main
struct BrimApp: App {
    @StateObject private var store: ProgressStore
    @StateObject private var settings: SettingsStore
    @StateObject private var controller: GameController

    init() {
        let demo = DemoConfig.current
        if let demo {
            setvbuf(stdout, nil, _IOLBF, 0)
            print("BRIM-T demo '\(demo.raw)' starts")
        }
        // Demo runs never touch the player's saved progress or settings.
        let store = demo == nil ? ProgressStore(defaults: .standard) : ProgressStore(inMemory: ProgressData())
        let settings = SettingsStore(defaults: demo == nil ? UserDefaults.standard : nil)
        _store = StateObject(wrappedValue: store)
        _settings = StateObject(wrappedValue: settings)
        _controller = StateObject(wrappedValue: GameController(store: store, settings: settings, demo: demo))
    }

    var body: some Scene {
        WindowGroup {
            RootView(controller: controller, store: store, settings: settings)
                .onAppear {
                    settings.apply()
                    FeedbackDirector.shared.start()
                    GameCenterManager.shared.authenticate()
                }
        }
    }
}
