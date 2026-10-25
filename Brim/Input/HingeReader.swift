import Foundation
import QuartzCore
import SwiftUI

/// Reads the iPhone Duo hinge (iOS 27.1+) and reports `(angleDegrees, time)`: 180 = flat, time = `CACurrentMediaTime()`
/// on receipt (samples carry no timestamp of their own). On devices without a hinge (or below iOS 27.1) it calls
/// `onUnavailable` instead. Never use the hinge's `status` for play (it reads `.closed` at ~85° on hardware).
///
/// Lifecycle trap (Squish, real Duo): back from the background with the phone open and still, iOS may send no hinge
/// change at all. On every scene activation the subscription is switched off and on again, which delivers the current
/// state. Note: after a hinge has been seen, a transient nil (display handover) should not demote the app to touch;
/// that policy belongs to the caller (`HingeTiltSource.hasHinge` stays true).
///
/// Usage: `view.modifier(HingeReader(onUpdate: { angle, time in … }, onUnavailable: { … }))`
struct HingeReader: ViewModifier {
    let onUpdate: (Double, TimeInterval) -> Void
    let onUnavailable: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var enabled = true
    @State private var refresh = 0

    init(onUpdate: @escaping (Double, TimeInterval) -> Void, onUnavailable: @escaping () -> Void = {}) {
        self.onUpdate = onUpdate
        self.onUnavailable = onUnavailable
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content
                .onHingeChange(isEnabled: enabled) { _, newContext in
                    if let hinge = newContext.hinge {
                        let time = CACurrentMediaTime()
                        let degrees = hinge.angle.degrees
                        HingeLog.record(angle: degrees, at: time)
                        onUpdate(degrees, time)
                    } else {
                        onUnavailable()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    refresh &+= 1
                    let ticket = refresh
                    enabled = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(30))
                        guard ticket == refresh else { return }
                        enabled = true
                    }
                }
        } else {
            content.onAppear(perform: onUnavailable)
        }
    }
}

/// `BRIM-H <t> <angle>` stdout lines for CI (`ci/duo.sh` greps them), only with the `-brimDemo` launch argument,
/// at most 10 per second. Don't rename the prefix. Called on the main thread only (hinge callbacks).
enum HingeLog {
    static let isEnabled: Bool = ProcessInfo.processInfo.arguments.contains("-brimDemo")
    nonisolated(unsafe) private static var lastLine: TimeInterval = -.infinity

    static func record(angle: Double, at time: TimeInterval) {
        guard isEnabled, time - lastLine >= 0.1 else { return }
        lastLine = time
        print(String(format: "BRIM-H %.3f %.1f", time, angle))
        fflush(stdout)
    }
}
