# Brim: handover (read this first, founder)

*Sun 25 Oct 2026. Built unsupervised in one long day by Claude running an agent studio: research, design, four
engineers, a design critic, QA, store and launch leads.*

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
https://github.com/pravegm/brim/actions/runs/40234263161 (final, 26 Oct):

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
