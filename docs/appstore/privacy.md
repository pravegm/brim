# Brim: App Privacy answers and privacy policy (v1.0)

**Answer: Data Not Collected.** Based on the design (`design/GAME-DESIGN.md` §9: "no data collection, no accounts") and the privacy manifest `Brim/PrivacyInfo.xcprivacy` (no tracking, no collected data types). The app code was still being written on 25 Oct 2026, so the grep in §3 must pass on the release-candidate build **before** you publish this answer.

The live policy page is `docs/site/privacy.html` (the text in §4 is the same; keep the two in step).

---

## 1. What to click (App Store Connect → the app → App Privacy)

1. **Privacy Policy URL:** `<SITE>privacy.html` (for hosting option A: `https://pravegm.github.io/brim/site/privacy.html`). The page must load before you save.
2. Click **Get Started**. "Do you or your third-party partners collect data from this app?" → **No, we do not collect data from this app.**
3. **Save**, then **Publish**. The product page shows **"Data Not Collected"**.

There's no tracking question once you choose "No". For the record, Brim doesn't track: no advertising identifier, no `AppTrackingTransparency`, no data brokers.

## 2. Why Apple services don't change the answer

| Thing | Declare? | Why |
|---|---|---|
| **Game Center** (sign-in, leaderboard scores, achievements) | No | Apple collects it under Apple's privacy policy. Apple: "You are not responsible for disclosing data collected by Apple." Brim never sends it anywhere itself. The player's Game Center name may be shown on the device only |
| **Daily Pour share** (emoji result text) | No | Made on the phone and handed to the iOS share sheet only when the player taps Share. Where it goes is the player's choice; nothing comes to us |
| **Crash reports** via iOS "Share With App Developers" | No | Apple-collected and opt-in. We add no crash SDK. *If one is ever added, the label must declare Crash Data first* |
| **Rating prompt** (if added) | No | Apple's `requestReview` |
| **Support email** | No | Happens outside the app; covered by the policy |
| **Progress, stars, stats, settings** | No | Stored only on the device (`ProgressStore`, UserDefaults). Never transmitted |

**The limit to watch:** if a future version ever sends anything to our own server (Game Center IDs, analytics, a remote daily seed), this answer and the privacy manifest change **before** that build ships.

## 3. Evidence to collect on the release-candidate build (Claude runs this; paste the result here)

| Look for, in `Brim/` | Expect | Result |
|---|---|---|
| Networking: `URLSession`, `URLRequest`, `NWConnection`, `import Network`, sockets | none | [ ] |
| Web/links: `WKWebView`, `SFSafariViewController`, `openURL`, SwiftUI `Link(` | none, or only a link to the support/privacy page (opening Safari is not collection) | [ ] |
| SDKs: Firebase, Crashlytics, Sentry, Mixpanel, Amplitude, AdSupport, `ASIdentifierManager` | none | [ ] |
| Tracking: `AppTrackingTransparency`, `ATTrackingManager` | none | [ ] |
| Cloud: `CloudKit`, `NSUbiquitousKeyValueStore` | none | [ ] |
| Notifications: `UNUserNotificationCenter` | none | [ ] |
| Packages in `project.yml` | none (true on 25 Oct) | [ ] |
| `NS*UsageDescription` keys in `project.yml` | none (true on 25 Oct) | [ ] |
| `Brim/PrivacyInfo.xcprivacy` in the built app | present (the TestFlight workflow already checks this) | [ ] |
| Required-reason APIs | UserDefaults `CA92.1`, system boot time `35F9.1` (declared). If the code uses file timestamps or disk space, add those reasons | [ ] |

One-line grep: `URLSession|URLRequest|NWConnection|WKWebView|SFSafari|openURL|Link\(|ATTrackingManager|ASIdentifier|CloudKit|NSUbiquitous|Firebase|Sentry|UNUserNotification`

---

## 4. Privacy policy (public text)

*Effective: 17 November 2026. Live at `<SITE>privacy.html`. Replace `SUPPORT_EMAIL_HERE` with the dedicated support address before publishing (runbook §0).*

> # Brim Privacy Policy
>
> **The short version: Brim doesn't collect any data about you.** There are no accounts, no ads, no analytics and no tracking, and the app makes no network requests of its own. Your progress stays on your iPhone.
>
> ## What Brim collects
> Nothing. Brim has no sign-up and no login. It contains no advertising, analytics, crash-reporting or tracking code from anyone, and it doesn't ask for your camera, microphone, photos, contacts or location.
>
> ## What stays on your device
> Your stars, unlocked venues, best scores, lifetime stats and settings are saved only on your iPhone. We can't see them. If you delete the app, they're deleted too.
>
> ## Sharing your Daily Pour
> When you tap Share, Brim makes a short text result (a row of emoji and your score) and hands it to the iOS share sheet. Where it goes next is up to you. Nothing is sent to us.
>
> ## Game Center (optional)
> If you're signed in to Game Center, your scores and achievements are handled by Apple under Apple's Privacy Policy (apple.com/legal/privacy). We don't receive your Game Center profile.
>
> ## Crash reports
> If you've chosen in iOS Settings to share analytics with app developers, Apple may pass us anonymous crash reports. We use them only to fix bugs. You can turn this off at any time in Settings > Privacy & Security > Analytics & Improvements.
>
> ## Tracking
> Brim doesn't track you across apps or websites, and it never asks for tracking permission.
>
> ## Children
> Brim is rated 4+ and collects no personal information from anyone, including children.
>
> ## This website
> These pages have no cookies, analytics, trackers, embedded media, external fonts or scripts. Our web host may keep standard server logs (such as IP addresses) for security, under its own privacy policy.
>
> ## If you email us
> If you write to SUPPORT_EMAIL_HERE, we use your email address and message only to reply and to fix the problem. We never add you to a mailing list or share your message. Ask us to delete the thread at any time and we will.
>
> ## Changes
> If this policy ever changes, we'll update this page and its date before the change reaches the app.
>
> ## Contact
> Brim, an independent game. Privacy questions: SUPPORT_EMAIL_HERE.

*(Founder to decide: if a legal or trading name or a postal address is ever required, for example for EU trader status, add it to the Contact section and the live page. It is deliberately left off.)*

## Sources
- Apple, *App privacy details on the App Store* ("collect" means transmitting off the device beyond real-time servicing; "You are not responsible for disclosing data collected by Apple"): https://developer.apple.com/app-store/app-privacy-details/
- Apple, *Privacy manifest files* and required-reason APIs: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
- Squish's reviewed answers (structure mirrored): `C:\Users\59527\Squish\docs\appstore\privacy-labels.md`, `privacy-policy.md`
