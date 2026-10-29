# Brim: reply to the 4.3 / 4.2.6 rejection (29 Oct 2026)

Apple rejected Brim 1.0 (13) under Guidelines 4.3 (spam) and 4.2.6 (app generation services) and asked nine questions. Advice from developers who have been through this (Tyche Labs, AppSubmitter, ReplyArgus):
- Reply in App Review's thread instead of resubmitting. Resubmitting before the questions are answered gets rejected again.
- Answer every question specifically and truthfully. The reviewer can see every app on the account.
- Put the one-line difference first.
- Show the distinctive feature in a short screen recording.

Founder checks before sending, all marked [check]:
1. That the other games' one-line descriptions in Q5 are right.
2. Whether to keep the AI-assistance sentence in Q9. It is recommended: it's true, and it answers 4.2.6 head on.
3. Attach a 30 to 60 s screen recording of one tabletop pour on the Duo. The Control Centre recording is fine.

Paste the block below into App Store Connect, under App Review, in the rejection thread. It is plain ASCII.

<!-- REPLY:BEGIN -->
```
Hello, and thank you for the review. Brim is an original game designed for iPhone Duo's hinge, and we would like to answer each question in full.

1. WHAT IT DOES
Brim turns iPhone Duo into a jug. The player lays the phone open on a table and lifts the top half like a lid: the jug drawn on the raised half tips, and a simulated stream falls across the fold into a glass on the flat half. The goal is to stop exactly on a fill line, but liquid already in the air keeps falling, so the player must stop early. Soda foams, milkshake pours thick and late, potions need tiny margins, and the pitch rises as the glass fills. It is a short skill game whose control only a foldable can give: the hinge is a continuous analogue input, and the glass stays still while the jug moves. Any other iPhone plays the full game by dragging.

2. INTENDED USERS
iPhone Duo owners looking for a game that uses the hinge as a real control rather than a novelty, and casual players of all ages (rated 4+, every drink non-alcoholic) who like short timing games with score chasing. A run takes 1 to 3 minutes.

3. THE GAP
Before building, we reviewed about 45 App Store apps that use the Duo hinge. Almost all are one-shot toys: toaster, press, origami. None uses the hinge as a precise, held analogue control. None simulates liquid. None offers lasting progression. Brim has 44 levels across six venues, each introducing a mechanic (foam, viscosity, moving glasses, precision), an endless Rush mode, a Daily Pour that is the same for everyone, and 2 Game Center leaderboards and 10 achievements.

4. BETA TESTING
We uploaded 13 TestFlight builds between 25 and 26 October and tested them on a real iPhone Duo. Changes made from that testing:
(a) iOS's fold transition blurs one half of the inner display as a fold starts, which hid the glasses at the critical moment. We added "Glasses on the sharp half" (builds 8-12), which runs the game upside down so the glasses stay sharp.
(b) Notifications came in from the wrong edge in that mode, so build 12 makes iOS itself rotate.
(c) The home screen's demo pour was mistaken for gameplay, so build 13 labels it DEMO.
(d) Closing the phone mid-pour could cost a glass; it now pauses and asks to lay the phone flat.

5. STANDALONE OR SUITE
Brim is a standalone game. Our account publishes other iPhone Duo games, each with a different mechanic, pose and rules. Squish: close the phone slowly to crush objects. Swoop: book pose, the two halves are wings that fold to dive. Hush: open a treasure chest slowly without waking it. Snapjaw: the halves are a flytrap's jaws that snap shut on flies. Brim is the only one about pouring liquid, and the only one built on a liquid simulation, timing against a falling stream and campaign progression.

6. COULD IT BE AN IN-APP PURCHASE OF ANOTHER APP?
Technically yes, but each is a different game with its own controls, physics, art, sound, progression and Game Center items. Someone looking for a pouring game would not find it inside a crushing toy.

7. SHARED CODE OR ASSETS WITH OUR OTHER APPS
No frameworks or assets are shared. Brim's code, art (all drawn in code) and sound (all synthesized at run time) were written for Brim. The only overlap is a small wrapper around Apple's public hinge API (SwiftUI onHingeChange, about 40 lines) and orientation handling, written the same way in each game. Our build and upload scripts are shared, but they are not part of the app.

8. THIRD-PARTY CODE
None. Brim uses only Apple frameworks: SwiftUI, SpriteKit, AVFoundation, Core Haptics and GameKit. There are no third-party SDKs, templates or content libraries.

9. CLIENT OR TEMPLATE
No. Brim is our own concept, content and branding, submitted by us as its owner. It was not made from a commercial template or an app generation service. We wrote it with the help of an AI coding assistant, and the design, testing and every decision are ours.

A screen recording of the hinge play is attached. Thank you for your time.
```
<!-- REPLY:END -->

## If App Review comes back unconvinced

- **Do not resubmit the same build under another name or account.** Apple warns that "repeated submissions of this kind may lead to removal from the Apple Developer Program."
- **Appeal:** if the reply is refused, use one appeal per rejected submission through the App Review Board (developer.apple.com/contact/app-store/?topic=appeal), restating Q1–Q3 and attaching the recording.
- **Consolidation (fallback):** Apple's documented remedy for a 4.3(a) portfolio is one app with the variations inside it. If App Review insists, the cheapest route is a "Duo games" collection app, with Brim as one game and the others added over time. That is a founder business decision, not a fix.

## Sources
- Tyche Labs, Guideline 4.3(a): whether to respond, appeal or rebuild: https://dev.to/tychelabs/guideline-43a-design-spam-whether-to-respond-appeal-or-rebuild-44gn
- AppSubmitter, Guideline 4.3 spam rejection: https://www.appsubmitter.io/app-rejection-guides/app-store-guideline-4-3-spam/
- ReplyArgus, Guideline 4.3 rejections explained, with an appeal template: https://www.replyargus.com/blog/app-store-review-guideline-4-3-rejections
- RuntimeWire, Apple says app-generation services should not submit client apps: https://runtimewire.com/article/apple-guideline-426-app-generation-submission
- Brim's market research, the 45 hinge apps: `research/01-market.md`
