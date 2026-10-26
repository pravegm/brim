import SwiftUI
import UIKit

/// Orientation policy (Duo run 40203342285, ROUND-2 App P0 a).
///
/// Info.plist declares portrait + both landscapes, so iOS never runs Brim as a letterboxed compatibility column on the
/// Duo's landscape (book-pose) inner display. The app itself decides what it supports:
/// - phones without a hinge: portrait only (the one world is composed for a tall canvas);
/// - an iPhone Duo (a hinge has reported on this device, one reports now, or the screen already looks foldable: both
///   Duo displays are ~0.7 wide to tall, other iPhones ~0.46): every orientation but upside down, so the inner display
///   follows the way the phone is held. A landscape canvas shows the "turn me" card (PoseCards). With "Glasses on the
///   sharp half" (on by default) the inner display swaps upright portrait for upside down (`sharpSide`).
/// Brim asks for portrait at launch on a Duo and whenever the player taps "Turn the screen" on the card (the phone may
/// be lying flat, where the orientation sensor says face-up and never rotates on its own).
@MainActor
enum OrientationLock {
    static let hingeKey = "brim.hasHinge"

    /// A hinge reported in this run, before `brim.hasHinge` was ever saved.
    private(set) static var hingeSeen = false

    /// "Glasses on the sharp half" (`SettingsStore.sharpSide`, demo `flip`). The founder's Duo blurs one fixed
    /// physical half as a fold starts (iOS's fold transition, every app, no opt-out), and in upright portrait that half
    /// is the counter. With this on, the inner display runs upside down instead of upright, so the glasses sit on the
    /// half that stays sharp, and iOS's own banners, notifications and Game Center turn round with the game. If iOS
    /// ever keeps the interface upright, RootView draws the game turned round itself (`RootView.turnsRound`).
    private(set) static var sharpSide = false

    static func mask(screen: CGSize) -> UIInterfaceOrientationMask {
        let stored = trustsStoredHinge(UserDefaults.standard.bool(forKey: hingeKey), screen: screen)
        guard allowsLandscape(hasHinge: stored || hingeSeen, screen: screen) else { return .portrait }
        return duoMask(sharpSide: sharpSide, screen: screen)
    }

    /// Pure rule (tested): a Duo's mask. Upright portrait gives way to upside down on the inner display only (the
    /// cover display, under `PoseRule.coverMaxSide`, keeps its usual orientations).
    nonisolated static func duoMask(sharpSide: Bool, screen: CGSize) -> UIInterfaceOrientationMask {
        let inner = max(screen.width, screen.height) >= PoseRule.coverMaxSide
        return sharpSide && inner ? [.portraitUpsideDown, .landscapeLeft, .landscapeRight] : .allButUpsideDown
    }

    /// The tabletop orientation Brim asks for: upside down with "Glasses on the sharp half", else upright.
    static var tabletop: UIInterfaceOrientationMask { sharpSide ? .portraitUpsideDown : .portrait }

    static func setSharpSide(_ on: Bool) {
        guard on != sharpSide else { return }
        sharpSide = on
        refreshSupportedOrientations()
        requestTabletopIfSupported()
    }

    /// On the inner display in portrait, the interface isn't yet the way "Glasses on the sharp half" wants it (e.g.
    /// just reopened from the cover display, or launched lying flat, where iOS never rotates on its own): ask once.
    static func settleTabletop() {
        guard sharpSide, !interfaceIsUpsideDown() else { return }
        requestTabletopIfSupported()
    }

    /// Only where the mask allows it (never on a phone without a hinge, nor on the cover display).
    private static func requestTabletopIfSupported() {
        let screen = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.size
        guard let screen, mask(screen: screen).contains(tabletop) else { return }
        requestPortrait()
    }

    /// Pure rule (tested): landscape only on a device with a hinge, or one whose screen looks like a Duo's.
    nonisolated static func allowsLandscape(hasHinge: Bool, screen: CGSize) -> Bool {
        if hasHinge { return true }
        guard screen.width > 0, screen.height > 0 else { return false }
        return min(screen.width, screen.height) / max(screen.width, screen.height) > 0.6
    }

    /// QA-1 P1-1 (pure, tested): `brim.hasHinge` travels in backups and Quick Start transfers, so a saved "this device
    /// has a hinge" is only believed on a screen shaped like a Duo's (both Duo displays are ~0.7 wide-to-tall, every
    /// other iPhone ~0.46). Restored onto any other iPhone, the flag is ignored and the phone plays with touch.
    nonisolated static func trustsStoredHinge(_ stored: Bool, screen: CGSize) -> Bool {
        stored && allowsLandscape(hasHinge: false, screen: screen)
    }

    /// A hinge just reported: let the windows rotate if they were held in portrait.
    static func hingeArrived() {
        guard !hingeSeen else { return }
        hingeSeen = true
        refreshSupportedOrientations()
        settleTabletop()
    }

    static func refreshSupportedOrientations() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }

    /// Asks the window scene for the tabletop portrait once (669 × 951 pt, fold across at y 455…495): upside down with
    /// "Glasses on the sharp half", else upright.
    static func requestPortrait() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
            window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: tabletop)) { error in
                #if DEBUG
                print("BRIM-T orient request error: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// The key window's scene is in portrait upside down.
    static func interfaceIsUpsideDown() -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.windows.contains(where: \.isKeyWindow) }) ?? scenes.first
        return scene?.effectiveGeometry.interfaceOrientation == .portraitUpsideDown
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
