import SwiftUI
import UIKit

/// Settings: sound, haptics, silent switch, touch on Duo, reduce motion (system), reset progress, about.
struct SettingsView: View {
    @ObservedObject var controller: GameController
    @ObservedObject var store: ProgressStore
    @ObservedObject var settings: SettingsStore
    let info: CanvasInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmReset = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        ZStack(alignment: .top) {
            BrimTheme.cream
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    section("Sound & feel") {
                        toggleRow("Sound", icon: "speaker.wave.2.fill", isOn: $settings.soundOn)
                        divider
                        toggleRow("Haptics", icon: "hand.tap.fill", isOn: $settings.hapticsOn)
                        divider
                        toggleRow("Respect silent mode", icon: "bell.slash.fill", isOn: $settings.respectSilentSwitch,
                                  footnote: "Off: Brim plays sound even in Silent Mode.")
                    }
                    section("Controls") {
                        // QA-2 P2-12: only where there is a hinge to swap for touch.
                        if controller.hingeSeen {
                            toggleRow("Touch controls on iPhone Duo", icon: "hand.draw.fill", isOn: $settings.touchOnDuo,
                                      footnote: "Drag up to pour instead of lifting the top half.")
                            divider
                            toggleRow("Glasses on the sharp half", icon: "drop.fill", isOn: $settings.sharpSide,
                                      footnote: "iPhone Duo blurs one half of its screen for a moment as you start to fold. This keeps the glasses on the other half: lay your Duo so the screen reads the right way up. If the glasses still blur, switch this off.")
                            divider
                        }
                        if reduceMotion {
                            infoRow("Calmer motion", icon: "figure.walk.motion", value: "On",
                                    footnote: "On because Reduce Motion is on in iOS Settings.")
                        } else {
                            toggleRow("Calmer motion", icon: "figure.walk.motion", isOn: $settings.calmMotion,
                                      footnote: "No screen shake, camera bumps or score pops.")
                        }
                    }
                    section("Progress") {
                        Button {
                            FeedbackDirector.shared.uiTap()
                            confirmReset = true
                        } label: {
                            HStack(spacing: 12) {
                                rowIcon("arrow.counterclockwise", tint: BrimTheme.spill)
                                Text("Reset progress")
                                    .font(BrimTheme.text(17, .bold))
                                    .foregroundStyle(BrimTheme.spill)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    section("About") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "iphone.gen3")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(BrimTheme.terracotta)
                                Text("Made for iPhone Duo — on a Duo, the fold is the jug.")
                                    .font(BrimTheme.text(16, .heavy))
                                    .foregroundStyle(BrimTheme.ink)
                            }
                            Text("Turn your Duo so the fold runs side to side. Lay it flat, then lift the top half to pour. On other iPhones, drag up to tip the jug.")
                                .font(BrimTheme.text(14))
                                .foregroundStyle(BrimTheme.inkSoft)
                            Text("Every sound is synthesised live. No ads, no in-app purchases, no tracking, no accounts. Every drink is non-alcoholic.")
                                .font(BrimTheme.text(14))
                                .foregroundStyle(BrimTheme.inkSoft)
                            Text("Brim \(version) · made by a tiny studio")
                                .font(BrimTheme.text(13, .bold))
                                .foregroundStyle(BrimTheme.inkFaint)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, info.insets.top + 8)
                .padding(.bottom, info.insets.bottom + 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .alert("Reset all progress?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                // Round 9 (QA-4 P2-1): through the controller, so the Home loop drops the chosen vessel at once.
                controller.resetProgress()
                FeedbackDirector.shared.uiConfirm()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stars, unlocked venues, bests and lifetime stats will be erased. Daily Pour results are kept. This can't be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundIconButton(systemName: "chevron.left", size: 46, accessibility: "Back") {
                controller.showHome()
            }
            Text("Settings")
                .font(BrimTheme.title(32))
                .foregroundStyle(BrimTheme.ink)
            Spacer()
        }
        .padding(.top, 6)
    }

    private var divider: some View {
        Rectangle().fill(BrimTheme.ink.opacity(0.07)).frame(height: 1)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(BrimTheme.text(12, .heavy))
                .kerning(0.8)
                .foregroundStyle(BrimTheme.inkSoft)
                .padding(.leading, 6)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .brimCard(padding: 16, radius: 22)
        }
    }

    private func rowIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint))
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { isOn.wrappedValue }, set: { newValue in
                FeedbackDirector.shared.uiTap()
                isOn.wrappedValue = newValue
            })) {
                HStack(spacing: 12) {
                    rowIcon(icon, tint: BrimTheme.mintDeep)
                    Text(title)
                        .font(BrimTheme.text(17, .bold))
                        .foregroundStyle(BrimTheme.ink)
                }
            }
            .tint(BrimTheme.goldDeep)
            if let footnote {
                Text(footnote)
                    .font(BrimTheme.text(13))
                    .foregroundStyle(BrimTheme.inkSoft)
                    .padding(.leading, 44)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func infoRow(_ title: String, icon: String, value: String, footnote: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                rowIcon(icon, tint: BrimTheme.terracotta)
                Text(title)
                    .font(BrimTheme.text(17, .bold))
                    .foregroundStyle(BrimTheme.ink)
                Spacer()
                Text(value)
                    .font(BrimTheme.text(16, .heavy))
                    .foregroundStyle(BrimTheme.inkSoft)
            }
            Text(footnote)
                .font(BrimTheme.text(13))
                .foregroundStyle(BrimTheme.inkSoft)
                .padding(.leading, 44)
        }
    }
}
