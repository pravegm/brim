import Combine
import Foundation

/// Player settings, kept apart from progress so "Reset progress" leaves them alone.
/// Sound, haptics and the silent switch live in `FeedbackDirector.shared` (it persists them itself); this store mirrors
/// them for SwiftUI and pushes changes back. "Touch controls on iPhone Duo" is stored here (`brim.settings.touchOnDuo`).
@MainActor
final class SettingsStore: ObservableObject {
    static let touchOnDuoKey = "brim.settings.touchOnDuo"

    @Published var soundOn: Bool { didSet { if FeedbackDirector.shared.soundOn != soundOn { FeedbackDirector.shared.soundOn = soundOn } } }
    @Published var hapticsOn: Bool { didSet { if FeedbackDirector.shared.hapticsOn != hapticsOn { FeedbackDirector.shared.hapticsOn = hapticsOn } } }
    /// Off by default (GAME-DESIGN §7): `.playback` + mixWithOthers; on = `.ambient`, muted by the silent switch.
    @Published var respectSilentSwitch: Bool {
        didSet {
            if FeedbackDirector.shared.respectSilentSwitch != respectSilentSwitch {
                FeedbackDirector.shared.respectSilentSwitch = respectSilentSwitch
            }
        }
    }
    /// iPhone Duo: drag to pour instead of lifting the top half.
    @Published var touchOnDuo: Bool { didSet { defaults?.set(touchOnDuo, forKey: Self.touchOnDuoKey) } }

    private let defaults: UserDefaults?

    /// `defaults` nil = in-memory (demo runs): nothing is written.
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        let feedback = FeedbackDirector.shared
        soundOn = feedback.soundOn
        hapticsOn = feedback.hapticsOn
        respectSilentSwitch = feedback.respectSilentSwitch
        touchOnDuo = defaults?.bool(forKey: Self.touchOnDuoKey) ?? false
    }

    /// Re-reads the feedback engine's values (e.g. at launch).
    func apply() {
        let feedback = FeedbackDirector.shared
        if soundOn != feedback.soundOn { soundOn = feedback.soundOn }
        if hapticsOn != feedback.hapticsOn { hapticsOn = feedback.hapticsOn }
        if respectSilentSwitch != feedback.respectSilentSwitch { respectSilentSwitch = feedback.respectSilentSwitch }
    }
}
