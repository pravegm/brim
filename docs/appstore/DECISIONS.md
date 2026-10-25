# Brim 1.0: launch decisions

*Made 25 Oct 2026 by the launch lead, mirroring Squish's reviewed launch kit (`C:\Users\59527\Squish\docs\appstore\`). Each line is the decision and the one reason that settled it. The clicks are in `docs/LAUNCH-RUNBOOK.md`. Only the founder's legal identity, contact details, hosting choice and Apple-login actions are left to the founder (runbook §0).*

## 1. The decisions

| # | Topic | Decision | Reason |
|---|---|---|---|
| 1 | **App name** | `Brim: Fold to Pour` (18/30) | Plain "Brim" is taken and crowded; the compound had no hit, and "Fold" + "Pour" index the two searches that matter |
| 2 | **Fallback names** | `Brim: Pour to the Line` → `Brimful: Fold to Pour` → `Brim: Fold & Pour` | Keep the "Brim" brand and the home-screen name; avoid the taken "Pour Decisions", "Fill Line", "Top Up" |
| 3 | **Subtitle** | `Fill every glass to the line` (28/30), both locales | States the goal in plain words and indexes fill/glass/line; no price, superlative or Apple mark (2.3.7), the lesson from Squish's subtitle change |
| 4 | **Promotional text** | Duo first, then "drag up" on other iPhones, then no ads/IAP/data (159/170) | If the Duo screenshot slot is missing, this and the description are the only Duo signals; it's editable any time |
| 5 | **Description** | Opens "Your iPhone Duo is the jug.", then the hook, then "works on every iPhone"; 2,763/4,000; en-US differs in 4 spellings | The brief's order; scannable headings; claims taken from the bible with a check table (`metadata.md` §10) because the build didn't exist yet |
| 6 | **Keywords** | `bartender,drink,juice,soda,lemonade,milkshake,potion,physics,tilt,hinge,foldable,jug,splash,fizz,cup` (100/100 bytes) | No repeats of name/subtitle words, no competitor or Apple marks; "water" dropped (water trackers and sort puzzles own it) |
| 7 | **Categories** | Games → **Casual** + **Arcade**; secondary **Entertainment** | Casual is where paid one-verb hits chart (Toastie); Arcade fits the score chasing and separates Brim from hinge toys; Entertainment catches novelty browsers. Puzzle rejected: wrong intent |
| 8 | **Age rating** | **4+**: every content item None, every capability No, not Made for Kids | All drinks are non-alcoholic, nothing is harmed, nothing is random or bought |
| 9 | **Alcohol guard** | No beer/cocktail/shot/pint words in visible copy; keep root beer and foamy amber in pint-style glasses off every store frame; rename the `pint`/`shot` glass styles neutrally in-game | A 4+ rating rests on nothing *looking* like alcohol; root beer reads as beer to UK eyes and to reviewers |
| 10 | **Price** | Base **UK £1.99**, Apple equalises the rest ($1.99). No launch discount | The brief's price; at £1.99 Brim is the cheapest premium hinge game (rivals $2.99–4.99), good for impulse buys |
| 11 | **Territories** | All **except China mainland** | Paid games there need an ISBN licence we don't have; account-level EU trader status is already handled for Squish |
| 12 | **Pre-order** | **No** | A pre-order needs an approved final build ~3 weeks out, and the real-Duo feel tuning is the biggest quality lever left |
| 13 | **Duo screenshots** | Upload D1–D6 by hand **if** App Store Connect shows an iPhone Duo slot; otherwise ship 1.0 with the iPhone sets and add the Duo set in 1.0.1 | The API has no Duo type (Squish research, Oct 2026); screenshots lock at approval |
| 14 | **Screenshot sets** | 6 Duo inner + 5 at 6.9" + 5 at 6.1", order and captions in `screenshots.md`; frame 1 is the stream crossing the fold | The first 3 frames show in search; the crossing stream is the one image no other phone can make |
| 15 | **App Preview** | Optional; ships in 1.0 only if recorded and checked by code freeze (Mon 9 Nov) | Previews lock with the version; Brim has no preview recorder yet, and a late one costs a version |
| 16 | **Daily Pour day boundary** | Recommend **00:00 UTC** for everyone (engineering change from the local-date design) | Game Center's recurring leaderboard resets at one UTC moment; local dates would mix two days' glasses on one board |
| 17 | **Leaderboards** | `brim.rush.best` Classic, best score; `brim.daily.score` Recurring daily from 1 Nov 2026 00:00 UTC | All-time chase for Rush; a fresh board each day for the Daily; starting 1 Nov lets TestFlight testers see it |
| 18 | **Achievements** | 10, **700 points**, 300 held back; only `brim.sandbar` hidden; none repeatable; none rewards speed or fold count | Room for future content under the 1,000 cap; the secret venue stays secret; App Review 2.4.2 |
| 19 | **App Privacy** | **Data Not Collected** (confirm with the grep in `privacy.md` §3 on the release build) | No network, SDKs or accounts by design; Game Center data is Apple's to disclose |
| 20 | **Accessibility labels** | Claim **Reduced Motion**, **Sufficient Contrast**, **Differentiate Without Color Alone**, each only if its check passes; not VoiceOver, Voice Control, Larger Text, Dark | Pouring can't be done with VoiceOver and text doesn't reach 200%; light-only by design. Labels go live on launch day |
| 21 | **Content Rights** | **No** third-party content | All art drawn in code, all sound synthesised, system fonts only |
| 22 | **Export compliance** | Nothing to answer (`ITSAppUsesNonExemptEncryption = false` in `project.yml`) | No encryption of our own, no networking |
| 23 | **Review notes** | Lead with "testing without a Duo", then the hinge, then the wear answer (2.4.2/1.4.5); 3,609 bytes, ASCII | Reviewers may not have a Duo; the wear question is the likeliest objection |
| 24 | **Launch date** | **Tue 17 Nov 2026, 08:00 UTC**, scheduled release; submit Tue 10 Nov (hard cut Fri 13 Nov) | A different week from Squish (24 Nov) gives each its own news cycle and nomination; before rather than after avoids US Thanksgiving week and catches new Duo owners; 23 days fits 3 weeks' featuring notice and two tuning rounds |
| 25 | **Fallback date** | **Tue 1 Dec** if the release build isn't ready by Thu 12 Nov; never 24 Nov | Keeps the one-launch-per-week rule |
| 26 | **Featuring** | App Launch nomination, publish date 17 Nov, **submitted by Tue 27 Oct**; "Optimized for iPhone Duo" in Helpful Details | Apple asks for 3 weeks' notice and asks Duo apps to say that phrase |
| 27 | **Localisation** | en-GB primary, en-US added; English only | The founder is UK-based; US spelling is the only difference that matters for 1.0 |
| 28 | **Website hosting** | Recommend **Option A**: make the repo public and serve `docs/` with GitHub Pages (`docs/.nojekyll` is in place); pages at `…/brim/site/` | No code or workflow change needed, and it also makes GitHub's Mac build minutes free, as for Squish. Founder's call (private-repo alternatives in runbook §0) |
| 29 | **Support contact** | A **dedicated support email**, shown on the support and privacy pages | Guideline 1.5 needs an easy contact; a private repo can't take public GitHub issues as Squish does |
| 30 | **Build and upload** | GitHub Actions → TestFlight with the **same App Store Connect API key** as Squish | A Team key with Admin works across apps; the founder's Intel Mac can't run Xcode 27 |
| 31 | **Family Sharing** | **On** | Standard for a one-off paid game; costs nothing |
| 32 | **What's New** | None for 1.0 (App Store Connect has no field); the 1.0 line goes into TestFlight's "What to Test" | Apple's rule |
| 33 | **Social and press timing** | Brim posts on the days between Squish's posts; Squish's 17 Nov clip moves to 18 Nov; no Brim posts on 24 Nov | Two launches from one founder must never compete on the same day |
| 34 | **Daily share emoji** | ⭐ Perfect · 🟩 Great · 🟨 Good · ⬜ Short · 🟥 Spill (confirm against the build) | Star shape for the best result, so the row reads without colour; matches the bible's example |

## 2. Requests to engineering (not mine to edit; must land before the release build)

| # | Priority | Owner | Request |
|---|---|---|---|
| 1 | **High** | App | **Daily Pour on the UTC date** (`LevelCatalog.dayNumber(for:)` currently uses the user's calendar), so it matches the recurring leaderboard (#16). If kept local, tell the launch lead so the support page and achievements note change |
| 2 | **High** | App + CI | **Achievement images**: ten 1024 × 1024 PNGs, no alpha (`achievements.md` "Images"). App Store Connect won't save an achievement without one |
| 3 | **High** | CI | **6.9" capture**: a run of `ci/screenshots.sh` with `DEVICE="iPhone 18 Pro Max"` and a size check (1320 × 2868; 1206 × 2622; Duo 2007 × 2853, no alpha). `ci.yml` only captures on the iPhone 18 Pro |
| 4 | Medium | CI | **Caption renderer** for store frames (port Squish's `ci/store-frame.swift`); fallback is uncaptioned frames |
| 5 | Medium | App | **Litres scale** for the lifetime stat and `brim.litres.10` (suggested: a tumbler at its line = 250 mL, so 10 L ≈ 40 glasses) |
| 6 | Medium | Scene/App | **Alcohol guard (#9):** neutral names for the `pint`/`shot` glass styles; no root beer in pint glasses; no foamy amber in the store scenarios |
| 7 | Medium | App | **"Pour by dragging" setting on Duo**: helps players who can't or won't fold, and reviewers; add the review-notes line if it ships |
| 8 | Low | App | Achievement banners queued until a glass is served; never mid-pour |
| 9 | Low | CI | **App Preview recorder** (Squish's `preview.yml` approach), only if the preview is wanted for 1.0 |
| 10 | Low | Design | Consider numbering the Daily from launch day (Daily #1 on 17 Nov) rather than days since 1 Jan 2026 (#320 on launch day) |

## 3. Five decisions for the founder to sanity-check

1. **Launch Tue 17 Nov** (a week *before* Squish), nomination by **Tue 27 Oct**, fallback Tue 1 Dec.
2. **Make the repo public** for free website hosting (and free Mac build minutes), or keep it private and use Netlify or GitHub Pro. Plus the **support email** you'll create.
3. **Daily Pour resets at 00:00 UTC** for everyone (midnight UK in winter, 4 pm California), to match Game Center's daily board.
4. **Store words:** subtitle `Fill every glass to the line`, keywords led by "bartender", Casual + Arcade.
5. **4+ guard:** keep root beer, pint and shot glasses away from anything that looks like beer or spirits, and out of the store frames.

## Sources
- Squish's reviewed decisions, research and sources (Apple specs, Duo slots, age-rating values, featuring lead time): `C:\Users\59527\Squish\docs\appstore\DECISIONS.md`
- `research/01-market.md` (competitors, prices, Apple's Duo editorial, name checks); `design/GAME-DESIGN.md`; `design/ARCHITECTURE.md`; `CLAUDE.md`
