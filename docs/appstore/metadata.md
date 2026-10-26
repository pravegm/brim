# Brim: App Store metadata (v1.0)

*Written 25 Oct 2026 by the launch lead; §8 (age rating), §9 and §10 updated 26 Oct against Apple's current rules (`COMPLIANCE.md`). Paste from the code blocks exactly. Counts are Unicode characters, except keywords, which Apple counts in bytes (all ASCII here, so the same). Every choice has a one-line reason in `DECISIONS.md`. Every feature claim is from `design/GAME-DESIGN.md`; the build didn't exist yet when this was written, so the claims marked in §10 must be checked against the release-candidate build before submission.*

Localisations: **English (U.K.)** is the primary language, plus **English (U.S.)**. Every other storefront shows en-GB. Only the description differs between the two (§4); everything else is identical.

---

## 1. App name (limit 30)

```
Brim: Fold to Pour
```
**18 / 30.** Plain "Brim" is taken on the store (a water tracker, a credit-card app, Blades of Brim); the compound had no hit (`research/01-market.md` §7).

If App Store Connect says the name is taken when you create the record, use the first that works, and tell Claude:

| Order | Fallback | Count |
|---|---|---|
| 1 | `Brim: Pour to the Line` | 22 |
| 2 | `Brimful: Fold to Pour` | 21 |
| 3 | `Brim: Fold & Pour` | 17 |

The home-screen name under the icon is **Brim** (`CFBundleDisplayName` in `project.yml`), whichever store name is used.

## 2. Subtitle (limit 30)

```
Fill every glass to the line
```
**28 / 30**, the same in en-GB and en-US. It names the goal in plain words, has no price, superlative or Apple mark (Guideline 2.3.7), and indexes "fill", "glass" and "line" without spending keyword bytes.

## 3. Promotional text (limit 170; can change any time without a new version)

```
On iPhone Duo, lift the top half to pour across the fold. On any other iPhone, drag up. Stop right on the line. No ads, no in-app purchases, no data collected.
```
**159 / 170**, both locales. It leads with the Duo, because if the Duo screenshot slot is missing on upload day, this line and the description are the product page's only Duo signals.

Rotation ideas for later (count before pasting):
- After launch week: `Today's Daily Pour is live: ten glasses, the same for everyone, one scored try. How close to the line can you get?` (114)
- After a press mention: `"[real quote]" ([outlet]). ...` (only with a real quote).

## 4. Description (limit 4,000)

**en-GB 2,740 / 4,000; en-US 2,739 / 4,000** (characters, recounted by script 26 Oct; 2,759 / 2,758 bytes because of the bullets and ×).

### en-GB (English U.K.)

```
Your iPhone Duo is the jug.

Lay your Duo open on the table. The top half holds a jug of lemonade. Lift it like a laptop lid and the jug tips, pouring a stream across the fold into a glass waiting on the flat half. Lower it to stop. But the stream is still falling, so the trick is to stop just before the line.

No ads. No in-app purchases. No accounts. No data collected. Pay once and it's all yours.

MADE FOR THE FOLD. PLAYS ON EVERY iPhone.
On iPhone Duo, the hinge is the only control. The glass stays still on the table while the jug half moves, and you pour by feel with slow, gentle lifts. You never need to close the phone or fold fast. On any other iPhone, drag up anywhere to tip the jug and let go to set it upright. Same glasses, same physics, same leaderboards.

POURING THAT FEELS TRUE
• The drink in the jug stays level, so a full jug pours at a slight tip and a nearly empty one needs a steep one
• The stream takes time to fall: stop early, or watch it sail past the line
• The glass sings as it fills. The pitch rises, so you can pour by ear
• Glugs you can feel, surfaces that wobble, foam that climbs and settles, and a bright ting on every Perfect

FIVE VENUES, ONE SHIFT AT A TIME
• Lemonade Stand: water, lemonade and orange juice, from tumblers to flutes
• Soda Fountain: foam. Pour slowly, then top up
• Milkshake Diner: thick shakes, honey and syrup that keep coming after you stop
• The Conveyor: glasses that won't wait for you
• Potion Shop: tiny vials, millilitre marks and lines that fade
Earn stars to open the next venue. Collect enough to find out what's behind the counter.

RUSH
One big jug and glasses that keep coming. Every Perfect tops the jug up and grows your multiplier, all the way to ×5. Three spills, or an empty jug, and the run is over. Chase your best on the Game Center leaderboard.

DAILY POUR
Ten glasses, the same for everyone today, and one scored try. Then share your row of results without giving the glasses away.

CALLED TO THE DROP
Every glass gets a word: Perfect, Great, Good, Short, Over or Spill. Protect your Perfect streak, collect stars and watch your lifetime stats grow: litres poured, Perfects, best streak.

GAME CENTER
Leaderboards for Rush and the Daily Pour, and ten achievements. It's optional: Brim works fully without signing in.

SOUND AND FEEL
Every sound is synthesised in the app as you pour. There are no recordings. Sound and haptics each switch off in Settings. Reduce Motion turns off screen shake and thins out the particles.

EVERY DRINK IS NON-ALCOHOLIC
Lemonade, juice, sodas, shakes, syrups and potions (the fizzy, colourful, entirely made-up kind).

PRIVATE BY DESIGN
No accounts, no tracking, no data collected. Your progress stays on your iPhone.
```

### en-US (English U.S.)

Identical except four spellings: millilitre → milliliter, litres → liters, synthesised → synthesized, colourful → colorful. Full text, ready to paste:

```
Your iPhone Duo is the jug.

Lay your Duo open on the table. The top half holds a jug of lemonade. Lift it like a laptop lid and the jug tips, pouring a stream across the fold into a glass waiting on the flat half. Lower it to stop. But the stream is still falling, so the trick is to stop just before the line.

No ads. No in-app purchases. No accounts. No data collected. Pay once and it's all yours.

MADE FOR THE FOLD. PLAYS ON EVERY iPhone.
On iPhone Duo, the hinge is the only control. The glass stays still on the table while the jug half moves, and you pour by feel with slow, gentle lifts. You never need to close the phone or fold fast. On any other iPhone, drag up anywhere to tip the jug and let go to set it upright. Same glasses, same physics, same leaderboards.

POURING THAT FEELS TRUE
• The drink in the jug stays level, so a full jug pours at a slight tip and a nearly empty one needs a steep one
• The stream takes time to fall: stop early, or watch it sail past the line
• The glass sings as it fills. The pitch rises, so you can pour by ear
• Glugs you can feel, surfaces that wobble, foam that climbs and settles, and a bright ting on every Perfect

FIVE VENUES, ONE SHIFT AT A TIME
• Lemonade Stand: water, lemonade and orange juice, from tumblers to flutes
• Soda Fountain: foam. Pour slowly, then top up
• Milkshake Diner: thick shakes, honey and syrup that keep coming after you stop
• The Conveyor: glasses that won't wait for you
• Potion Shop: tiny vials, milliliter marks and lines that fade
Earn stars to open the next venue. Collect enough to find out what's behind the counter.

RUSH
One big jug and glasses that keep coming. Every Perfect tops the jug up and grows your multiplier, all the way to ×5. Three spills, or an empty jug, and the run is over. Chase your best on the Game Center leaderboard.

DAILY POUR
Ten glasses, the same for everyone today, and one scored try. Then share your row of results without giving the glasses away.

CALLED TO THE DROP
Every glass gets a word: Perfect, Great, Good, Short, Over or Spill. Protect your Perfect streak, collect stars and watch your lifetime stats grow: liters poured, Perfects, best streak.

GAME CENTER
Leaderboards for Rush and the Daily Pour, and ten achievements. It's optional: Brim works fully without signing in.

SOUND AND FEEL
Every sound is synthesized in the app as you pour. There are no recordings. Sound and haptics each switch off in Settings. Reduce Motion turns off screen shake and thins out the particles.

EVERY DRINK IS NON-ALCOHOLIC
Lemonade, juice, sodas, shakes, syrups and potions (the fizzy, colorful, entirely made-up kind).

PRIVATE BY DESIGN
No accounts, no tracking, no data collected. Your progress stays on your iPhone.
```

Copy rules this text keeps:
- **Duo first, then "works on every iPhone"** in the second section, as the brief asks.
- **"iPhone Duo" is used only referentially**, never in the name, subtitle or keywords, and "iPhone" keeps its exact form even in a capitalised heading (Apple trademark guidelines).
- **The secret venue is only teased** ("what's behind the counter"). Never name the Sand Bar in public copy.
- **No health or hydration claims**, which keeps the "Health or Wellness Topics" age-rating item at No.
- **No alcohol words** in visible copy: no beer, cocktail, booze, pint or shot (§8). "bartender" appears only as a search keyword (§5), for people searching "bartender game".

## 5. Keywords (limit 100 bytes, comma-separated, no spaces)

```
bartender,drink,juice,soda,lemonade,milkshake,potion,physics,tilt,hinge,foldable,jug,splash,fizz,cup
```
**100 / 100 bytes**, both locales.
- Nothing repeats the name or subtitle: brim, fold, pour, fill, every, glass, line are already indexed from them.
- No competitor names (Happy Glass, Water Sort, iBeer, Toastie), no Apple marks ("iPhone", "Duo").
- Apple combines words across fields, so "pour" + "drink", "glass" + "fill", "bartender" + "game"-category and "hinge" + "fold" form the searches people type.
- "water" is left out on purpose: that search is full of water trackers and sort puzzles.

Alternate set to A/B after 4 weeks of Search data (check the bytes first): `bartender,drink,juice,soda,lemonade,milkshake,potion,physics,tilt,hinge,foldable,cafe,diner,daily,skill`

## 6. What's New

App Store Connect has no What's New field for an app's first version. Use the 1.0 line for TestFlight's "What to Test", press and social:
```
First pour. Lay your Duo open, lift the top half like a laptop lid and stop right on the line. On other iPhones, drag up.
```
Template for 1.0.1 (fill in only what actually shipped):
```
Smoother pours on iPhone Duo, [one real change], and small fixes. Thanks for every Perfect.
```

## 7. Category

| Field | Choice | API value |
|---|---|---|
| Primary | **Games** | `GAMES` |
| Game subcategory 1 | **Casual** | `GAMES_CASUAL` |
| Game subcategory 2 | **Arcade** | `GAMES_ARCADE` |
| Secondary category | **Entertainment** | `ENTERTAINMENT` |

**Why:** Casual is where paid one-verb hits chart (Toastie reached #10 in US paid Casual), and its paid chart is shallow enough for a launch spike to show. Arcade matches what Brim is underneath (score chasing, streak multiplier, endless Rush, leaderboards), which a pure toy can't claim, and it separates us from the hinge toys. Entertainment catches people browsing for novelty "look what my phone does" apps. Puzzle was rejected: Brim is a timing and feel game, and puzzle searchers expect sort puzzles.

## 8. Age rating: 4+

Apple's current scheme (since the July 2025 overhaul; answers were due by 31 Jan 2026) has five global ratings, **4+, 9+, 13+, 16+, 18+**, plus regional ones (Australia, Brazil, Korea) that App Store Connect works out from the same answers. Re-checked 26 Oct 2026 against Apple's *Age ratings values and definitions*.

App Store Connect → the app → **App Information** → Age Ratings → **Set Up Age Ratings** (later: **Edit**). Step 1 is a tick-list of in-app controls and capabilities: **tick nothing**. Then answer each section. Yes/No items are marked (Y/N); the rest are a frequency: **None / Infrequent / Frequent**.

| Section | Item | Answer |
|---|---|---|
| In-app controls | Parental Controls | **No** (not ticked) |
| | Age Assurance | **No** (not ticked) |
| Capabilities | Unrestricted Web Access | **No** |
| | User-Generated Content | **No** |
| | Social Media | **No** |
| | Social Media Disabled for Users Under 13 | **No** |
| | Messaging and Chat | **No** |
| | Advertising | **No** |
| Mature themes | Profanity or Crude Humor | **None** |
| | Horror/Fear Themes | **None** |
| | Alcohol, Tobacco, or Drug Use or References | **None** |
| Medical or wellness | Medical or Treatment Information | **None** |
| | Health or Wellness Topics | **None** |
| Sexuality or nudity | Mature or Suggestive Themes | **None** |
| | Sexual Content or Nudity | **None** |
| | Graphic Sexual Content and Nudity | **None** |
| Violence | Cartoon or Fantasy Violence | **None** |
| | Realistic Violence | **None** |
| | Prolonged Graphic or Sadistic Realistic Violence | **None** |
| | Guns or Other Weapons | **None** |
| Chance-based activities | Simulated Gambling | **None** |
| | Contests | **Infrequent** (see below) |
| | Gambling (Y/N) | **No** |
| | Loot Boxes (Y/N) | **No** |
| Age Categories and Override | Made for Kids / Override to Higher Age Rating | **Not Applicable** |
| | Age Suitability URL (optional) | leave empty |

**Expected result: 4+** everywhere (Apple's table puts "Infrequent Contests" at 4+; **Frequent** would make it 13+, so don't pick that). If the form shows an item not listed here, the honest answer is None or No; tell Claude so this table can be updated.

Why each risky item is answered this way:
- **Contests: Infrequent, not None.** Apple now defines Contests as "events that allow users to compete with one another for rankings", which covers Brim's two optional Game Center leaderboards. They are a side feature (no prizes, no entry, the game is complete without them), so Infrequent is the honest level and keeps 4+.
- **Alcohol:** every drink is non-alcoholic (bible §1). Root beer and cream soda are soft drinks; potions are fictional coloured drinks with no effects. *Watch-out:* the glass catalog includes `pint` and `shot` styles. Keep their in-game names neutral (for example "tall glass", "tiny cup"), never show foamy amber in a pint glass on any store frame, and keep root beer out of the screenshots and preview, so nothing reads as beer (`DECISIONS.md` #9).
- **Violence:** spills make a puddle. Nothing is harmed.
- **Simulated gambling / loot boxes:** no chance-based rewards, nothing to buy. The Daily Pour is seeded, not random prizes.
- **Social media / messaging / UGC:** the only sharing is the Daily Pour text handed to the iOS share sheet; Brim has no feed, chat or uploads. Game Center's own friend features are Apple's, not Brim's.
- **Made for Kids: No.** The Kids category adds parental-gate rules and moves the app out of Games; Brim is for everyone, not built for under-11s specifically. Once approved, Made for Kids can't be changed.
- **Korea (GRAC):** no Rating Classification Number needed (it only applies to 17+/19 games or frequent gambling, sex, drugs or realistic violence).

Sources: [Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions) · [Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating) · [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) (31 Jan 2026 deadline) · [App information: Korea](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)

## 9. Other App Store Connect fields

| Field | Value |
|---|---|
| Price | Base country **United Kingdom, £1.99**; Apple equalises every other storefront (check the US shows **$1.99**). No launch discount |
| Availability | Every country or region **except China mainland and Vietnam**: paid games in China mainland need an NPPA (ISBN) approval number, and Vietnam requires games to hold a Vietnamese game licence to stay on its store. Brim has neither (App Information → App Store Regulations and Permits) |
| Apple silicon Mac / Apple Vision Pro | **Untick both** (Pricing and Availability → "iPhone and iPad Apps on Apple Silicon Macs" and "Apple Vision Pro"). They default to on for iPhone apps, and Brim is untested there: no hinge, mouse-drag pouring never checked. iPad keeps running the iPhone app (Guideline 2.4.1) |
| EU Digital Services Act | Account status is already set for Squish, but each new app is asked again: App Information → App Store Regulations and Permits → Digital Services Act. A paid app is normally **trader**; the trader address, phone and email you entered are **shown publicly on EU product pages** (founder's call; never in the repo) |
| Pre-order | **No** |
| Release | **Scheduled: Tue 17 Nov 2026, 08:00 UTC** ("automatically release after approval, no earlier than") |
| Family Sharing | **On** (permanent once on) |
| Small Business Program | Account-level; already enrolled for Squish (just confirm it shows Active) |
| Copyright | `2026 <founder legal name>` (founder-only) |
| Support URL | `https://pravegm.github.io/brim/site/support.html` (support is by GitHub issue: https://github.com/pravegm/brim/issues) |
| Marketing URL | `https://pravegm.github.io/brim/site/` |
| Privacy Policy URL | `https://pravegm.github.io/brim/site/privacy.html` |
| App Privacy | **Data Not Collected** (`privacy.md`) |
| Accessibility Nutrition Labels | **Reduced Motion**, **Sufficient Contrast**, **Differentiate Without Color Alone**, each only after its check passes, published on launch day (`accessibility.md`). Still voluntary (Apple: required "over time") |
| Content Rights | "Does your app contain, show, or access third-party content?" **No** (all art is drawn in code, all sound synthesised, system fonts only) |
| Export compliance | Nothing to answer: `ITSAppUsesNonExemptEncryption` is `false` in `project.yml` |
| Game Center | On; 2 leaderboards and 10 achievements, 700 points (`achievements.md`) |
| Sign-in required | No |
| Version | 1.0 (`MARKETING_VERSION` in `project.yml`) |

The site is live on GitHub Pages (option A, enabled 26 Oct; all three pages returned HTTP 200 on 26 Oct). Support is by GitHub issue, not email: the repo is public, and the support page links straight to https://github.com/pravegm/brim/issues.

## 10. Claims to check against the release-candidate build

The build didn't exist when this was written. Before submission, Claude (or whoever cuts the release candidate) ticks each line or changes the copy.

| Claim (where) | Source today | Check |
|---|---|---|
| Drag up anywhere tips the jug; let go and it eases upright (description, promo, review notes) | Bible §3, `TouchTiltSource` (review-notes table, round 4) | [x] |
| Five venues + a secret one unlocked by stars; stars open the next venue | `LevelCatalog.starsToUnlock`: 0 / 8 / 18 / 30 / 44, Sand Bar 105 of 120 (40 campaign + 4 Sand Bar shifts) | [x] code, 26 Oct |
| Potion Shop has millilitre marks and lines that fade | Bible §6; fading lines `lineFadesAfter` in `LevelCatalog` | [x] fading lines (code); [ ] mL marks on a device frame |
| Rush: Perfect tops up the jug; multiplier to ×5; ends on 3 spills or empty jug | `Rules.multiplier` (×2 at 3, ×3 at 6, ×5 at 10), `GameSession` (Rush strikes only on spills; `rushRefill`; dry jug ends) | [x] code, 26 Oct |
| Daily Pour: 10 glasses, one scored try, share sheet result | `LevelCatalog.dailyOrders` (10), `ResultsView` `ShareLink` | [x] code, 26 Oct |
| Judgement words Perfect / Great / Good / Short / Over / Spill shown as text (Over = too full, nothing spilled; round 5) | `Rules.judge` | [x] code, 26 Oct |
| Lifetime stats screen shows litres poured, Perfects, best streak | Bible §9 | [ ] |
| Sound and haptics each have an off switch in Settings | `UI/SettingsView.swift` ("Sound", "Haptics") | [x] code, 26 Oct |
| Reduce Motion: no screen shake, fewer particles | `SceneFX` (particle counts halve or less), `GameScene.reduceMotion`; Settings shows "Calmer motion: On" | [x] code, 26 Oct |
| All sound synthesised, no audio files in the bundle | Bible §7 | [ ] |
| No network code, no SDKs (privacy) | grep 26 Oct: no `URLSession`, `openURL`, `Link(`, `requestReview`, `UNUserNotification` in `Brim/`; sharing only via `ShareLink` | [x] |
| 2 leaderboards + 10 achievements report from the build | `achievements.md` | [ ] |
| *26 Oct:* nothing in the listing mentions the Duo's upside-down default or Split View; neither needs to (support page and review notes cover them). The Settings › About turn-status line is TestFlight/DEBUG-only: never mention it in store copy | — | [x] |
