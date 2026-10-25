# Brim: Featuring nomination (App Launch)

*Final copy, 25 Oct 2026, ready to paste. The founder submits it (needs an App Store Connect login: Account Holder, Admin, App Manager or Marketing role).*

## Timing

Apple asks for nominations as early as possible, **at least 3 weeks before** the date. For a **Tue 17 Nov** release that means **submit by Tue 27 Oct 2026**. It needs only the app record (runbook §1), not a build.

Where: App Store Connect → Apps → Brim → **Featuring** → **Nominations** → **Create Nomination**. A saved draft is not a nomination: press **Submit**.

If the launch moves to the fallback date (Tue 1 Dec, runbook timeline), edit the nomination's Publish Date the same day.

## Fields

| Field | Value | Count / limit |
|---|---|---|
| Nomination Name | `Brim - App Launch - iPhone Duo fold-to-pour game` | 48 / 60 |
| Nomination Type | **App Launch** | — |
| Description | the block below | **922 / 1,000** |
| Publish Date | **Specific day: 2026-11-17** | — |
| Related Apps | Brim only (auto-filled). Don't add Squish: it has its own nomination | up to 10 |
| Platforms | iOS | — |
| Countries or Regions | leave the auto-selection (every territory the app is in) | — |
| Localizations | leave the auto-selection (English (U.K.), English (U.S.)) | — |
| In-App Events | none | — |
| Supplemental Materials | 1. `<SITE>` 2. the 15 s teaser post URL (once posted, Fri 6 Nov; add it by editing the nomination) 3. the TestFlight public link (only if you open external testing) | up to 5 URLs |
| Helpful Details | the block below | **381 / 500** |

### Description
```
Brim makes iPhone Duo the jug. Lay the Duo open in tabletop pose and lift the top half like a laptop lid: a jug drawn on that half tips with it, and a stream pours across the fold into a glass on the flat half. Lower it to stop, but the stream is still falling, so the skill is stopping just before the line.

The hinge is an analogue control, not a switch. The liquid in the jug stays level, so a full jug pours at a slight lift and an empty one needs a steep one. The pitch rises as the glass fills, so players learn to pour by ear. Soda foams, milkshakes keep coming, potions demand precision.

Five venues of shifts, an endless Rush mode with a Perfect-streak multiplier, and a seeded Daily Pour that is the same for everyone and shares as a row of emoji, with Game Center leaderboards.

Every iPhone can play by dragging up. One price, no ads, no in-app purchases, no data collected, and every drink is non-alcoholic.
```

### Helpful Details
```
Optimized for iPhone Duo: built for the tabletop pose on the inner display, with a pause card in book pose and a status card on the outer display. Uses the public iOS 27.1 hinge API with slow, held angles between flat and upright; it never asks players to close the phone or fold fast. A small studio: every sound is synthesized in the app. Also from us: Squish (launching 24 Nov).
```

**Why this copy:**
- **New hardware first:** the opening line and "Optimized for iPhone Duo" in Helpful Details (Apple's Duo guidance asks for exactly that phrase).
- **Craft:** level-liquid physics, the falling stream, pitch by ear.
- **Replayability:** Rush, Daily Pour, leaderboards; research found no hinge game with Game Center or a daily mode.
- **Accessibility and reach:** drag on every iPhone. No VoiceOver claim, because the label isn't earned (`accessibility.md`).
- **Kind to the hardware:** answers the wear question before an editor asks it.
- **No ads, 4+:** the last line.

## Later nominations (optional)
- **New Content**, for the first update with a real new venue or drink (for example Bubble Tea, bible §5). Description: what's new, one line restating no ads and free update. Submit 3 weeks ahead.
- An **In-App Event** ("Holiday menu" Daily Pour week, for example) needs a build that implements it first; don't create one for 1.0.

## Sources
- App Store Connect Help, *Nominations template* (name ≤ 60, description ≤ 1,000, helpful details ≤ 500, up to 5 URLs, types): https://developer.apple.com/help/app-store-connect/reference/nominations/nominations-template
- App Store Connect Help, *Nominate your app for featuring* (minimum 3 weeks' lead time; roles): https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring
- Apple Developer, *Prepare for iPhone Duo* ("optimized for iPhone Duo" in Helpful Details), as recorded in Squish's `DECISIONS.md` §3
