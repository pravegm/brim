# Brim: App Store metadata (v1.0)

*Written 25 Oct 2026 by the launch lead. Paste from the code blocks exactly. Counts are Unicode characters, except keywords, which Apple counts in bytes (all ASCII here, so the same). Every choice has a one-line reason in `DECISIONS.md`. Every feature claim is from `design/GAME-DESIGN.md`; the build didn't exist yet when this was written, so the claims marked in §10 must be checked against the release-candidate build before submission.*

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

**en-GB 2,763 / 4,000; en-US 2,762 / 4,000.**

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
Earn up to three stars a shift to open the next venue. Three-star everything to find out what's behind the counter.

RUSH
One big jug and glasses that keep coming. Every Perfect tops the jug up and grows your multiplier, all the way to ×5. Three spills, or an empty jug, and the shift is over. Chase your best on the Game Center leaderboard.

DAILY POUR
Ten glasses, the same for everyone today, and one scored try. Then share your row of results without giving the glasses away.

CALLED TO THE DROP
Every glass gets a word: Perfect, Great, Good, Short or Spill. Protect your Perfect streak, collect stars and watch your lifetime stats grow: litres poured, Perfects, best streak.

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
Earn up to three stars a shift to open the next venue. Three-star everything to find out what's behind the counter.

RUSH
One big jug and glasses that keep coming. Every Perfect tops the jug up and grows your multiplier, all the way to ×5. Three spills, or an empty jug, and the shift is over. Chase your best on the Game Center leaderboard.

DAILY POUR
Ten glasses, the same for everyone today, and one scored try. Then share your row of results without giving the glasses away.

CALLED TO THE DROP
Every glass gets a word: Perfect, Great, Good, Short or Spill. Protect your Perfect streak, collect stars and watch your lifetime stats grow: liters poured, Perfects, best streak.

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

Answer the questionnaire exactly like this (App Store Connect → the app → App Information → Age Rating → Edit):

| Section | Item | Answer |
|---|---|---|
| In-app controls | Parental Controls | **No** |
| | Age Assurance | **No** |
| Capabilities | Unrestricted Web Access | **No** |
| | User-Generated Content | **No** |
| | Messaging and Chat | **No** |
| | Advertising | **No** |
| Mature themes | Profanity or Crude Humor | **None** |
| | Horror/Fear Themes | **None** |
| | Alcohol, Tobacco, or Drug Use or References | **None** |
| | Mature or Suggestive Themes | **None** |
| Medical or wellness | Medical or Treatment Information | **None** |
| | Health or Wellness Topics | **No** |
| Sexuality or nudity | Sexual Content or Nudity | **None** |
| | Graphic Sexual Content and Nudity | **None** |
| Violence | Cartoon or Fantasy Violence | **None** |
| | Realistic Violence | **None** |
| | Prolonged Graphic or Sadistic Realistic Violence | **None** |
| | Guns or Other Weapons | **None** |
| Chance-based activities | Simulated Gambling | **None** |
| | Contests | **None** |
| | Gambling | **No** |
| | Loot Boxes | **No** |
| Kids | Made for Kids | **No** |

**Expected result: 4+.** If the form you see has extra or renamed items, the honest answer to each is None or No.

Why each risky item is None:
- **Alcohol:** every drink is non-alcoholic (bible §1). Root beer and cream soda are soft drinks; potions are fictional coloured drinks with no effects. *Watch-out:* the glass catalog includes `pint` and `shot` styles. Keep their in-game names neutral (for example "tall glass", "tiny cup"), never show foamy amber in a pint glass on any store frame, and keep root beer out of the screenshots and preview, so nothing reads as beer (`DECISIONS.md` #9).
- **Violence:** spills make a puddle. Nothing is harmed.
- **Simulated gambling / loot boxes:** no chance-based rewards, nothing to buy. The Daily Pour is seeded, not random prizes.
- **Contests:** Game Center leaderboards are not prize contests.
- **Made for Kids: No.** The Kids category adds parental-gate rules and moves the app out of Games; Brim is for everyone, not built for under-11s specifically.

## 9. Other App Store Connect fields

| Field | Value |
|---|---|
| Price | Base country **United Kingdom, £1.99**; Apple equalises every other storefront (check the US shows **$1.99**). No launch discount |
| Availability | Every country or region **except China mainland** (paid games there need a government ISBN licence) |
| Pre-order | **No** |
| Release | **Scheduled: Tue 17 Nov 2026, 08:00 UTC** ("automatically release after approval, no earlier than") |
| Family Sharing | **On** (permanent once on) |
| Small Business Program | Account-level; already enrolled for Squish (just confirm it shows Active) |
| Copyright | `2026 <founder legal name>` (founder-only) |
| Support URL | `<SITE>support.html` (see runbook §4.0 for `<SITE>`) |
| Marketing URL | `<SITE>` |
| Privacy Policy URL | `<SITE>privacy.html` |
| App Privacy | **Data Not Collected** (`privacy.md`) |
| Accessibility Nutrition Labels | **Reduced Motion**, **Sufficient Contrast**, **Differentiate Without Color Alone**, each only after its check passes, published on launch day (`accessibility.md`) |
| Content Rights | "Does your app contain, show, or access third-party content?" **No** (all art is drawn in code, all sound synthesised, system fonts only) |
| Export compliance | Nothing to answer: `ITSAppUsesNonExemptEncryption` is `false` in `project.yml` |
| Game Center | On; 2 leaderboards and 10 achievements, 700 points (`achievements.md`) |
| Sign-in required | No |
| Version | 1.0 (`MARKETING_VERSION` in `project.yml`) |

`<SITE>` if the founder picks hosting option A (public repo, GitHub Pages from `/docs`): `https://pravegm.github.io/brim/site/`, so:
- Support URL: `https://pravegm.github.io/brim/site/support.html`
- Marketing URL: `https://pravegm.github.io/brim/site/`
- Privacy Policy URL: `https://pravegm.github.io/brim/site/privacy.html`

## 10. Claims to check against the release-candidate build

The build didn't exist when this was written. Before submission, Claude (or whoever cuts the release candidate) ticks each line or changes the copy.

| Claim (where) | Source today | Check |
|---|---|---|
| Drag up anywhere tips the jug; let go and it eases upright (description, promo, review notes) | Bible §3, `TouchTiltSource` | [ ] |
| Five venues + a secret one unlocked by 3-starring everything; stars open the next venue | Bible §6 | [ ] |
| Potion Shop has millilitre marks and lines that fade | Bible §6 | [ ] |
| Rush: Perfect tops up the jug; multiplier to ×5; ends on 3 spills or empty jug | Bible §6, `Rules.multiplier` | [ ] |
| Daily Pour: 10 glasses, one scored try, share sheet result | Bible §6 | [ ] |
| Judgement words Perfect / Great / Good / Short / Spill shown as text | Bible §5, `Judgement` | [ ] |
| Lifetime stats screen shows litres poured, Perfects, best streak | Bible §9 | [ ] |
| Sound and haptics each have an off switch in Settings | `FeedbackDirector.soundOn/hapticsOn` | [ ] |
| Reduce Motion: no screen shake, fewer particles | Bible §8, `GameScene.reduceMotion` | [ ] |
| All sound synthesised, no audio files in the bundle | Bible §7 | [ ] |
| No network code, no SDKs (privacy) | `privacy.md` grep | [ ] |
| 2 leaderboards + 10 achievements report from the build | `achievements.md` | [ ] |
