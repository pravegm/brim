# Brim: Accessibility Nutrition Labels (v1.0)

*Decided 25 Oct 2026 from the design and the expected build (the brief's working assumptions). The rule, same as Squish: **claim a label only when the build earns it across every common task**, and verify on the release build first. Labels are voluntary, per device, and can only be published once a version is live, so this happens on **launch day, Tue 17 Nov** (runbook §6).*

Common tasks for Brim:
1. start a shift, Rush or the Daily Pour from the menu;
2. pour a glass (hinge on Duo, drag elsewhere) and read the result;
3. read the results card and share the Daily result;
4. open Venues and pick a shift;
5. change Settings (sound, haptics, silent mode).

## The answer, at a glance

| Label | 1.0 answer | Status | Why |
|---|---|---|---|
| VoiceOver | **No** | Decided | Menus are labelled, but pouring (task 2) can't be done with VoiceOver: the result depends on seeing the stream approach the line. Apple's bar is all common tasks |
| Voice Control | **No** | Decided | Pouring needs the hinge or a drag; there's no spoken alternative |
| Larger Text | **No** | Decided | Partial only (menus scale, the in-game HUD and result stamps don't reach 200%) |
| Dark Interface | **No** | Decided | Light only by design (`UIUserInterfaceStyle: Light` in `project.yml`; cream wall palette) |
| Differentiate Without Color Alone | **Yes**, if check A passes | **Verify** | Results are words (PERFECT / GREAT / GOOD / SHORT / OVER / SPILL), not colours; recap coasters add a glyph (✓, ↓ short, ↑ over, drop for spill) |
| Sufficient Contrast | **Yes**, if check B passes | **Verify** | Ink `#2B2233` on cream `#FFF4E2` is about 14:1 (13.99:1) |
| Reduced Motion | **Yes**, if check C passes | **Verify** | Bible §8: no screen shake, fewer particles |
| Captions | **No** (not applicable) | Decided | No dialogue, video or audio-only content |
| Audio Descriptions | **No** (not applicable) | Decided | No time-based video content |

**Publish for iPhone: Reduced Motion, Sufficient Contrast, Differentiate Without Color Alone**, each only if its check below passes on the release build. Leave every other box unticked. If a check fails, leave that box unticked: an honest "not indicated" beats a false claim.

## Checks (on the release build, on a Duo and on a non-Duo iPhone)

### A. Differentiate Without Color Alone
- [ ] Every judgement shows its **word** (stamp or label), not just a colour flash. Spill also shows a puddle; Short pulses the level line; Over is its own word ("OVER"), with no puddle.
- [ ] The fill line is a **dashed line with a tick tab**, readable without its colour; the Perfect-band glow is extra, not the only cue.
- [ ] Stars are filled vs outlined **shapes**, not colour-only.
- [ ] Locked venues show a **lock glyph or "?"**, not just greyed colour.
- [ ] Selected options in Settings have a check mark, toggle position or outline, not only a tint.
- [ ] The in-app Daily result row uses **shapes or letters** alongside colour (for example ⭐ for Perfect). The shared emoji text is outside the app, but keep its mapping readable too (`social-launch.md` §2).
- [ ] Run through tasks 1–5 with **Settings > Accessibility > Display & Text Size > Color Filters > Grayscale** on.

### B. Sufficient Contrast
Apple's bar: about 4.5:1 for text, 3:1 for large text, controls and state indicators.

| Pair (bible §8 palette) | Ratio (computed) | Use |
|---|---|---|
| Ink `#2B2233` on cream `#FFF4E2` | 13.99:1 | body text, menus |
| Ink `#2B2233` on mint `#BFE8D8` | 11.42:1 | text on tiles |
| Ink `#2B2233` on gold `#FFC23D` | 9.45:1 | buttons |
| Ink `#2B2233` on terracotta `#D9825B` | 5.29:1 | text on the counter: use ink, not white |
| White on terracotta `#D9825B` | 2.88:1 | **fails for text**: don't put white text on the counter colour |
| Cyan `#3FD0FF` on cream | 1.65:1 | **fails**: the cyan PERFECT stamp needs an ink outline or ink text (ink on cyan is 8.47:1) |
| Gold `#FFC23D` on cream | 1.48:1 | **fails** as a line or text colour on its own |

- [ ] No text uses the three failing pairs, or each has an ink outline/shadow.
- [ ] The fill line reaches 3:1 against every glass and liquid colour (a dark outline around the dash solves it).
- [ ] Check with Increase Contrast and Bold Text on.

### C. Reduced Motion
- [ ] With **Settings > Accessibility > Motion > Reduce Motion** on: no screen shake on spills, fewer particles (splash, sparkle ring, confetti), no parallax.
- [ ] Menu and glass transitions become fades or short moves, not springs and slides.
- [ ] The liquid, stream and jug still move: that motion is the game's content, which Apple's criteria allow.

## What we can say in copy today

The description says only: "Reduce Motion turns off screen shake and thins out the particles", and that sound and haptics switch off separately. It makes no VoiceOver or Larger Text claim. If check C fails, cut that sentence too.

## 1.0.1 list to earn more labels honestly

| Fix | Size | Earns |
|---|---|---|
| "Pour by dragging" on Duo (a setting), plus VoiceOver announcements of the level ("40 percent, line at 75") and an adjustable "pour a little" action | M | VoiceOver (maybe), and helps motor access on Duo |
| Named custom actions "Pour" / "Stop" on the play area, input labels | S | Voice Control (with the above) |
| HUD, result stamps and results card scale to AX3 with reflow | M | Larger Text |

Re-check the labels with every update; add one only after the fix is on device and tested.

## Sources
- App Store Connect Help, *Overview of Accessibility Nutrition Labels*: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels
- App Store Connect Help, *Manage Accessibility Nutrition Labels* (publish only for devices with a live version): https://developer.apple.com/help/app-store-connect/manage-app-accessibility/manage-accessibility-nutrition-labels
- Squish's label decisions (method mirrored): `C:\Users\59527\Squish\docs\appstore\accessibility.md`
