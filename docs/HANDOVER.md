# Brim: handover (read this first, founder)

*Sun 25 Oct 2026. Built unsupervised in one long day by Claude running an agent studio: research, design, four
engineers, a design critic, QA, store and launch leads.*

## Status, Mon 26 Oct (evening): ready to submit

**Release build: TestFlight 1.0 (13)**, tested by the founder on a real Duo ("all good").

**Since build 7:**
- **Glasses on the sharp half.** On the Duo, iOS blurs one fixed half for about 2 s as a fold starts. Brim runs upside down so the glasses stay sharp, and iOS's own banners turn with it.
- **Every Duo pose plays:**
  - book-pose touch play on one page;
  - touch play on the outer display, with a paused-run card;
  - Split View plays by touch, and small windows say "make me full screen".
- **Clearer Home:** a DEMO tag on the attract pour, and a one-time "upside down on purpose" card.
- **Reviews:** QA-5 and DUO-AUDIT are both clear.

**App Store Connect is filled in through the API** (`tools/appstore/`):
- listing, categories, the 4+ age rating, £1.99 and availability;
- scheduled release on 17 Nov 08:00 UTC;
- review notes and contact, copyright;
- Game Center, with 10 achievements and 2 leaderboards attached;
- screenshots for 6.9", 6.1" and iPhone Duo;
- the featuring nomination, **submitted**.

The founder has done App Privacy, Mac/Vision Pro availability, Family Sharing and EU DSA status.

**Left:**
- **Founder:** pick build 13 on the 1.0 page, then Add for Review → Submit (`docs/LAUNCH-RUNBOOK.md`, "Where things stand", step 5).
- **In progress, optional:** the new iOS 27 product-page header and search-results images (`docs/appstore/header-search.md`).

## What it is

**Brim: Fold to Pour.** £1.99 once, no ads, no in-app purchases, no data collected, rated 4+.

- **How it plays:** lay your iPhone Duo open and flat, fold running side to side. Lift the top half off the table
  and the jug drawn on it tips. The stream crosses the fold into a glass on the flat half. Stop exactly on the line:
  the stream keeps falling, so you have to stop *before* it.
- **Feedback:**
  - the pour's pitch rises as the glass fills (real filling-vessel acoustics, synthesized live);
  - glugs in your hand;
  - a *ting* and fireworks on a Perfect, with streak notes climbing a scale;
  - a proper mess on a spill.
- **Modes:**
  - **Shifts:** 44 levels across Lemonade Stand, Soda Fountain (foam), Milkshake Diner (thick, slow drinks), The
    Conveyor (moving glasses), Potion Shop (precision) and a secret Sand Bar.
  - **Rush:** endless; Perfects refill the jug.
  - **Daily Pour:** one scored attempt a day for everyone, with a shareable emoji result.
- **Game Center:** 2 leaderboards and 10 achievements, with badge art.
- **Other iPhones:** drag up to pour.

## Why this game

Market research found about 45 apps that already use the hinge as an action. The obvious metaphors are taken: toaster,
press, cut, origami, accordion, catapult, ramp, mouth. Nothing **pours**, and no hinge game has score-chasing,
Game Center or a daily mode.

Tipping a container is the most natural thing a hinge does, and only a foldable can keep the glass still while the
jug moves. My own shortlist and an independent concept agent both picked this idea (61/70). Details are in
`research/`.

## Quality bar reached

| Round | Critic score | Launch call |
|---|---|---|
| R1 | 5.0 | not yet |
| R2 | 7.5 | close |
| R3 | 8.4 | **yes, if** the P1s are fixed (done in R4), a real-Duo TestFlight session passes, and the store kit is built from the new frames |

- **Tests:** 156 unit tests pass on CI.
- **Duo simulator CI:** real iPhone Duo simulator runs drive the hinge, and a CI check proves that **closing the phone
  mid-pour never costs a glass**.
- **QA:** a code audit found no crash-level bugs; its four P1s are fixed.
- **Reviews:** `design/REVIEW-1…3.md` and `design/QA-1.md`.

## Overnight (25–26 Oct): what changed while you slept

**Install TestFlight 1.0 (6)**: it contains everything below. Builds 2, 3 and 5 are older, and 5 has no Game Center.

| Round | What it fixed or added |
|---|---|
| 5 | Real-Duo fixes from the QA audit. The "lay it flat" gate opens at 168°, with a "Use touch instead" escape. Lifting quickly never re-locks the gate. The jug refills between glasses, not mid-pour. A new **OVER** verdict, so "SPILL" only appears when it really overflows. Venue achievements unlock on clearing a venue, not on opening it. |
| 6 | The late game. A one-time intro card for each new mechanic. Shift and Rush tier banners. **Rush travels** to a new venue every 12 glasses. **Flawless crowns** for an all-Perfect shift. The Daily shows your streak and the week. Conveyor pour zone and belt queue. A ghost line in the Potion Shop. A desert Sand Bar with a slide warning and an hourglass glass. |
| 7 | Intro cards pause the belt. Stamps leave with their glass. Rush hand-offs smoothed. |
| 8 | Fairer Rush. An autopilot that can pour foam. The crown chase. The **Glass Cabinet**, where crowns unlock jugs for Rush and Practice. Ghost glasses on the failed-shift card. |
| 9 | Stamps never cover the next glass. Star wording ("Clean / Great / Flawless shift"). The secret Sand Bar now unlocks at **105★** instead of 3★ on every shift. |
| Balance | A simulated-player harness (novice, casual and expert) plays every level, Rush and the Daily on CI. Stars are now 3★ = no misses, 2★ = one miss, 1★ = cleared. Casual players clear about 80–97 % of each venue, Rush lasts about 4 minutes for a casual player, and the Sand Bar is reachable. |

The critic's latest score is **9.0/10** (REVIEW-7). A QA lead read the code end to end three more times and found
no crashes. There are 268 automated tests, all passing.

**Signing problem found and fixed overnight (it affects Squish too).** The build at 04:00 failed with "maximum number
of certificates": CI was creating a new Apple Development certificate on every run. Squish's TestFlight workflow
does the same thing on the same Apple account, so **Squish's next TestFlight build will probably fail the same way.**
Brim's workflow no longer creates certificates. It signs only with Apple's cloud-managed distribution certificate.
You can tidy up by revoking the old "Created via API" *development* certificates at developer.apple.com →
Certificates (optional; nothing in Brim needs them). Ask me to port the fix to Squish if you want it.

## What only you can do (about 1 hour total, click-by-click in `docs/LAUNCH-RUNBOOK.md`)

0. ~~Unblock CI~~ **Done 26 Oct:** the repo is public.
   - CI is green again: 156/156 tests.
   - An unsigned **Release** archive builds cleanly (`testflight.yml` with `check_only`, run 40234316753). It is a
     2.5 MB app, `com.pravegm.brim` 1.0, with a valid privacy manifest and no demo code in Release.
   - So TestFlight now needs only items 1 and 2.
1. **Create the app record** (bundle ID `com.pravegm.brim`, name `Brim: Fold to Pour`). Submit the featuring
   nomination **by Tue 27 Oct**: Apple wants 3 weeks' notice for the proposed **Tue 17 Nov** launch.
2. **Add the 4 GitHub secrets** to `pravegm/brim`. They are the same Apple key values Squish uses. Then press
   **Actions → TestFlight → Run workflow**.
3. **Play it on your Duo for 10 minutes** with the checklist in runbook §3 and send me the scores. Hinge feel,
   sound, haptics and the stream crossing a real fold can only be judged on the device. Tuning from your notes is
   quick.
4. **Turn on the support and privacy pages.** The repo is public now, so runbook §0 Option A applies:
   Settings → Pages → Deploy from a branch → `main`, folder `/docs`. Then give me a support email: the pages say
   `SUPPORT_EMAIL_HERE` until then.
5. **Paste the listing** (`docs/appstore/`) and press Submit.

## The store screenshots

They're ready, captioned and at the exact slot sizes, in the artifacts of the **App Store screenshots** run
https://github.com/pravegm/brim/actions/runs/40270623298 (final, 26 Oct, morning: round-9 build):

- `store-69` (6.9-inch);
- `store-61` (6.1-inch);
- `store-duo` (iPhone Duo inner display).

Each set has a `MANIFEST.txt` (0 flagged). GitHub keeps artifacts for 90 days.

The critic's final sign-off (`design/REVIEW-4-SIGNOFF.md`) is **launch "yes", 8.7/10**, with these upload rules:

- **P2 re-shot and checked (26 Oct):** PERFECT is clean, with no streak pop over it, and the 6.1-inch score shows
  in full with the streak pill under it.
- **Drop D6** (Venues on the Duo: shown flat, the gap left around the fold looks broken).
- **Upload order:** phones P1 → P2 → P3 → P4 → P5; Duo D1 → D2 → D4 → D5 → D3.
- **Submit with manual release.** The real-Duo TestFlight session (runbook §3) decides the release day.

## Where everything is

| Folder | What's there |
|---|---|
| Repo | `pravegm/brim` (private), local copy `C:\Users\59527\Fold` |
| `CLAUDE.md` | How to work on it (for any Claude account) |
| `design/` | The game design bible, architecture, round briefs, critic reviews, QA |
| `docs/appstore/` | Store copy, review notes, privacy, accessibility, screenshots plan, achievements, press kit, social posts, featuring nomination, decisions |
| `docs/site/` | The support, privacy and home pages |
| CI | **CI** (every push), **Duo** (iPhone Duo sim + hinge), **App Store screenshots** (captioned 6.9" / 6.1" / Duo sets with a MANIFEST), **TestFlight** |
