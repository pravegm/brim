import SwiftUI
import UIKit

/// Orientation policy (Duo run 40203342285, ROUND-2 App P0 a).
///
/// Info.plist declares portrait + both landscapes, so iOS never runs Brim as a letterboxed compatibility column on the
/// Duo's landscape (book-pose) inner display. The app itself decides what it supports:
/// - phones without a hinge: portrait only (the one world is composed for a tall canvas);
/// - an iPhone Duo (a hinge has reported on this device, one reports now, or the screen already looks foldable: both
///   Duo displays are ~0.7 wide to tall, other iPhones ~0.46): every orientation but upside down, so the inner display
///   follows the way the phone is held. A landscape canvas shows the "turn me" card (PoseCards).
/// Brim asks for portrait at launch on a Duo and whenever the player taps "Turn the screen" on the card (the phone may
/// be lying flat, where the orientation sensor says face-up and never rotates on its own).
@MainActor
enum OrientationLock {
    static let hingeKey = "brim.hasHinge"

    /// A hinge reported in this run, before `brim.hasHinge` was ever saved.
    private(set) static var hingeSeen = false

    static func mask(screen: CGSize) -> UIInterfaceOrientationMask {
        allowsLandscape(hasHinge: UserDefaults.standard.bool(forKey: hingeKey) || hingeSeen, screen: screen)
            ? .allButUpsideDown : .portrait
    }

    /// Pure rule (tested): landscape only on a device with a hinge, or one whose screen looks like a Duo's.
    nonisolated static func allowsLandscape(hasHinge: Bool, screen: CGSize) -> Bool {
        if hasHinge { return true }
        guard screen.width > 0, screen.height > 0 else { return false }
        return min(screen.width, screen.height) / max(screen.width, screen.height) > 0.6
    }

    /// A hinge just reported: let the windows rotate if they were held in portrait.
    static func hingeArrived() {
        guard !hingeSeen else { return }
        hingeSeen = true
        refreshSupportedOrientations()
    }

    static func refreshSupportedOrientations() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }

    /// Asks the window scene for portrait once (the tabletop canvas: 669 × 951 pt, fold across at y 455…495).
    static func requestPortrait() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
            window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                #if DEBUG
                print("BRIM-T orient request error: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// The key window's real safe-area insets (Dynamic Island, rounded corners, the Duo's inner camera cut-out).
    static func windowSafeArea() -> EdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first else {
            return EdgeInsets()
        }
        let i = window.safeAreaInsets
        return EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
    }
}

/// Supplies the orientation policy (`OrientationLock`) to UIKit.
@MainActor
final class BrimAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask(screen: window?.windowScene?.screen.bounds.size ?? .zero)
    }
}
