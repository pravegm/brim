# 01 — Market: hinge-input games on iPhone Duo, and what sells at ~£2

*Research date: 25 Oct 2026 (Duo on sale since 23 Oct). This builds on `Squish/research/06-market.md` (22 Oct) and doesn't repeat its install-base, pricing and go-to-market work. Read that file for those. Items marked **[unverified]** come from one weak source, a directory listing only, or my own judgement. I couldn't reach Reddit (r/iPhoneDuo, r/iPhoneduoapp) through search, and Stuff.tv, PhoneArena and TheStreet blocked fetches. §6–7 (pour concept and name checks) were added at the coordinator's request, which takes the doc past the ~2,500-word target.*

---

## Executive summary

1. **The hinge-game space has filled fast.** FoldHunt lists 106 Duo games, and **23 use the fold as an explicit input**, plus about 12 borderline. Across all categories there are about 45 hinge-as-verb apps in a 701-app directory ([FoldHunt games](https://foldhunt.com/iphone-duo/games/)). Assume any "close the phone to do X" metaphor is taken until we check.
2. **Most of the obvious metaphors are gone:** toaster, waffle iron, press/print, cut, origami, accordion, catapult, swing pump, ramp tilt, door/peek, chomping mouth, angle-matching, cassette deck, film slate, camera and pop-up book. **There's a new Squish overlap: Fold Smasher** (free with IAP), where you "fold your iPhone shut to smash targets between the screens" ([DuoDiscover](https://duodiscover.com/apps/fold-smasher)).
3. **No one has built a score-chasing hinge game.** The titles are toys, puzzles and party games. The FoldHunt sweep found **no hinge game with Game Center or a daily challenge**, and nothing with liquid, water, sand, balance, slingshot or putting. This is our clearest gap.
4. **Most hinge games use the hinge as a switch, not a dial** (open/closed, or fold to change mode). The few analogue-angle games (Duometry, Obtuse, Uphill, Valley Run, Marbles Unhinged, FoldFling) have had little press.
5. **Apple's games collection mixes polish with novelty.** "Great Apps and Games on iPhone Duo" lists **10 games: Toastie first, then PianoFold, Orisuji, Greens, Sneaky Sasquatch, Nitelore, Planet of Lana, Crossy Road Castle, Train Conductor World and Retrocade** ([App Store story](https://apps.apple.com/us/iphone/story/id6820639500)). Only two use the hinge as an input. Apple also says optimised apps carry a **"Made for iPhone Duo" badge**, and its editorial line is "look stunning in any pose" ([Apple Newsroom](https://www.apple.com/newsroom/2026/10/developers-bring-incredible-new-app-experiences-to-iphone-duo/)).
6. **Paid hinge games cluster at $2.99–$4.99.** Toastie, Duometry and Fold Accordion are $2.99. Tiny Computers is $3.99. Orisuji and Deck-Man are $4.99. Free with IAP covers Marbles Unhinged, Fold Smasher and Twofold ([MacRumors](https://www.macrumors.com/2026/10/23/iphone-duo-fun-apps/)). **At £1.99 we'd be the cheapest premium hinge game.** That helps impulse buys, but press may read it as "smaller".
7. **Premium ~£2 hits share a pattern.** One verb, runs from seconds to a few minutes, instant restart, a skill ceiling that resists one dominant strategy (Vollmer's critique of 2048), and heavy juice. Add a reason to come back: daily seed, Game Center, or Zen mode. The risk is clones. Threes was cloned within about 3 weeks, and its daily income doubled once a free version existed ([Game Developer](https://gamedeveloper.com/business/-i-threes-i-devs-double-daily-income-with-free-version)).
8. **The evergreen "satisfying" mechanics are timing-stack, slice, sort/pour, pop and smash.** Helix Jump has 800M+ installs. Soap Cutting and ASMR Slicing each have about 40M+. Sort, block and screw puzzles made about $600M IAP in H1 2026 ([Voodoo/Wikipedia](https://en.wikipedia.org/wiki/Voodoo_(company)), [PocketGamer.biz](https://www.pocketgamer.biz/pgc-digital-crazy-labs-explains-why-asmr-slicing-is-successful-after-launch), [AppMagic](https://appmagic.rocks/research/casual-report-H12026)). Slicing and smashing are already used on the Duo. **Pouring/filling, sand/fluid and balancing/stacking are not.**
   - **Pour check (§6):** I found no Duo or Galaxy-foldable app that pours via the hinge.
   - Pour-to-line is proven: Happy Glass and Water Sort each have 100M+ installs, and iBeer, a $2.99 tilt-to-pour novelty, made up to $20k a day in 2008.
   - **Names (§7):** "Brim" alone, "Top Up", "Pour Decisions" and "Fill Line" are all taken or crowded. **"Brim: Fold to Pour" looks clear.**
9. **The Duo is mostly used half-folded.** Apple tuned hinge torque so it isn't "floppy" in the middle and shuts "like a high-end automobile's car door" ([9to5Mac](https://9to5mac.com/2026/09/18/apple-vp-of-hardware-talks-iphone-duo-durability-crease-hinge-and-more/)). Reviews describe tabletop video, book-style typing and tent/StandBy. Apple's HIG asks games to be "playable in every device pose". **A game played in the middle of the angle range fits how people actually hold it.**
10. **People are watching for wear, but nothing has failed.** Apple publishes no fold rating. Joanna Stern's robot ran 32,640 folds and found the hinge *stiffer*, with no felt change ([MacRumors](https://www.macrumors.com/2026/10/21/iphone-duo-fold-test-hinge/)). "Crackgate" is only a forum prediction ([MacRumors Forums](https://forums.macrumors.com/threads/prediction-pinchgate.2492098/)). **Design for small, deliberate angle changes, not rapid full slams, and say so in the copy.**

### "Taken" hinge mechanics (do not reuse)

| Mechanic | Taken by |
|---|---|
| Close = appliance lid / bake (timed) | **Toastie** (toaster), **WaffleKing** (waffle iron), Duo Grill (BBQ timer) |
| Close = press / crush / smash | **Squish** (ours), **Fold Smasher** (smash targets between the halves) |
| Close = print / mirror-blot | Inkblotter, Foldink, InkBlot Duo, Fold & Squish, FoldSketch, Paint & Fold |
| Close = cut / knife | Exactly Half, Duo Cut |
| Fold = fold paper / origami | kami, Hingami, Paper & Grain, PureOrigami, Orisuji (layer maze) |
| Hinge = bellows / accordion | Fold Accordion, Bellowsby, Foldeon, DuoBox, Foldissimo, Accorduon |
| Hinge = musical tempo | AngleBeat |
| Bend = charge, open = launch (catapult) | FoldFling |
| Fold = pump a swing | Valley Run |
| Angle = floor tilt / ramp / gravity | Marbles Unhinged, Uphill (bowling slope), Fold: Gravity Puzzle (board widens) |
| Match a target angle | Duometry, Obtuse: Degrees of Chaos |
| Close = door; crack open to peek (horror) | Keep It Shut |
| Close = block, open = cast (spellbook) | 転生魔法少女は忙しい |
| Close = mouth chomps | ChompDuo |
| Fold = switch game mode | NEOFOLD (breakout/pinball/duel), Fold Party (each fold starts one of 16 mini-games) |
| Fold = route choice | Foldlight: Cosmic Courier |
| Close = enter a world, open = exit | Porta Nubi; Two Fold (cover world vs inner world) |
| Half-fold = privacy screen; fold = pass turn | Twofold, Fleet Duo/FleetFold, Battlefleet Duo |
| Close = pets move to the cover | Foldlings |
| Fold = squeal or fake crack (prank) | FoldAhhh (screaming chicken), Fold Crack |
| Close = start the cassette / tape | Deck-Man, Duo-Man (concept) |
| Close = film-slate clap | Clap |
| Unfold = print a photo / switch camcorder on | Snapshots, Flipcorder |
| Unfold = pop-up scene or card reveal | Unfold Your City, Papelle, Foldtales, Penta CD Player (jewel case) |
| Open = x-ray reveal | Innards |
| Open = magic-trick reveal | Sleight |
| Closed = focus timer | Fold Focus, Zenitizer |
| Unfold = cast a fishing line | Foldfish |
| Closed = Nintendo DS shell / pause | Delta, Rev Rush |
| Fold = flap (Galaxy foldables, browser) | Foldy Bird |

---

## 1. Foldable-specific games and toys (landscape)

**Directories.** FoldHunt lists 4 launch partners, 211 simulator-verified apps and 486 App Store-confirmed apps, last checked 23 Oct ([FoldHunt](https://foldhunt.com/iphone-duo/)). Its numbers have changed since the 22 Oct Squish read, when it showed 72 verified and 834 claimed. DuoDiscover is a newer hand-reviewed directory with 12 games ([DuoDiscover](https://duodiscover.com/category/games)). A developer-written guide says "Very few games use it yet," and that none of the 261 games on Apple's US top charts mention the Duo ([Chonky Corgo blog](https://www.getchonky.app/blog/best-iphone-duo-games/); the author has a stake in one listed game).

**Hinge-input games and toys with notable traction or detail:**

| Title | Mechanic | Price | Reception / signal |
|---|---|---|---|
| **Toastie** | Close = toaster lid, open to check; timing | $2.99, no IAP | #1 in Apple's Duo games story; TechRadar and podcast love (see Squish 06). MacRumors leads with it |
| **Orisuji** | Fold to overlay paper-maze layers | $4.99, no IAP/ads | In Apple's story; PocketGamer coverage; dev built it without owning a Duo ([Fix Stories](https://www.fixgamingchannel.com/orisuji-iphone-duo-fix-stories-adrien-friggeri/)) |
| **Deck-Man** | Open, insert cassette, close to play | $4.99 | In Apple's newsroom post and apps story |
| **Duometry** | Fold to a target angle, lock in | $2.99 | MacRumors, PhoneArena lists |
| **Marbles Unhinged** | Fold turns floors into ramps, gates, gravity | Free + $9.99 | Several lists **[price from search snippet]** |
| **Twofold: Pass & Play** | Half-fold hides boards; fold to pass | Free trial, $1.99/game or $4.99 all | Found via r/iPhoneDuo by Digital Trends |
| **Fold Party** | Each fold starts one of 16 party games (e.g. Hot Potato, air hockey) | ? | Launched 23 Oct **[mini-game list unverified]** |
| **Fold Smasher** | Close to smash scurrying targets; reopen to splats | Free + IAP | Listed 24 Oct; untested, no press ([DuoDiscover](https://duodiscover.com/apps/fold-smasher)) |
| **WaffleKing** | Pour batter, fold to bake, unfold on time | ? | Directory only; a Toastie clone in effect |

Other $2.99–$3.99 titles: Tiny Computers, Fold Accordion. Free: kami, Foldfish, Fold & Squish. The other titles in the taken table are directory listings only, with no reviews or prices found **[unverified]**.

**Reception overall.** Press treats these as a curiosity; MacRumors commenters say they "feel like early iPhone novelty apps." I found **no ratings volume or chart success for any hinge game**. The best signal is Toastie at #10 in US paid Casual. **The category is crowded with one-joke toys and empty of hinge games built for depth and replay.**

---

## 2. What Apple has featured and seems to want

- **Newsroom (22 Oct)** names Asphalt Legends, Zenless Zone Zero, UnGodly, Sneaky Sasquatch and Retrocade (Arcade; "quick play when closed"), and Deck-Man. It announces Duo editorial collections and a **"Made for iPhone Duo" badge**, which Xcode 27.1 builds get ([Apple Newsroom](https://www.apple.com/newsroom/2026/10/developers-bring-incredible-new-app-experiences-to-iphone-duo/), [9to5Mac](https://9to5mac.com/2026/10/05/apple-invites-developers-to-submit-iphone-duo-ready-apps-to-the-app-store/)).
- **The App Store story "Great Apps and Games on iPhone Duo"** ("A new era of dual-screen experiences enters the fold") lists 10 games: Toastie, PianoFold, Orisuji, Greens, Sneaky Sasquatch, Nitelore, Planet of Lana, Crossy Road Castle, Train Conductor World and Retrocade ([App Store](https://apps.apple.com/us/iphone/story/id6820639500)).
- **What it suggests [inference]:** Apple leads with one witty hinge toy, then **crafted premium indies** and Arcade. The common thread is "stunning in any pose", and hinge input is a bonus. Only Toastie and Orisuji use the hinge as input, so a polished, **replayable** hinge game is underrepresented.
- **Featuring criteria:** uniqueness ("defines a new genre"), innovation, accessibility, localisation and the product page. For games, add controls, sound, replayability and value. Nominate at least 2 weeks ahead, ideally up to 3 months ([Apple](https://developer.apple.com/app-store/getting-featured/)).
- **HIG:** games should be "playable in every device pose" (book, surface, standing).

---

## 3. What makes ~£2 premium casual games sell

| Game | Model and facts | Lesson |
|---|---|---|
| **Threes** (2014) | $1.99; Apple iPhone Game of the Year; cloned in about 3 weeks (1024, 2048); daily income doubled with a free version ([Game Developer](https://gamedeveloper.com/business/-i-threes-i-devs-double-daily-income-with-free-version), [TechCrunch](https://techcrunch.com/2014/03/24/clones-clones-everywhere-1024-2048-and-other-copies-of-popular-paid-game-threes-fill-the-app-stores)) | One swipe verb; depth comes from a system that can't be beaten by one rote strategy ([PocketGamer](https://www.pocketgamer.com/articles/058578/r/)). **Expect clones if the mechanic is simple. Hardware lock-in plus craft is the moat** |
| **Alto's Adventure** (2015) | $2.99 premium on iOS; #1 paid worldwide; sequel also no IAP ([Wikipedia](https://en.wikipedia.org/wiki/Alto%27s_Adventure)) | One-tap jump/flip; mood and audio as product; Zen mode for non-competitive players; goal sets of 3 for short-term aims **[mechanics from general knowledge]** |
| **Mini Metro** (mobile 2016) / **Mini Motorways** | 1M by Jul 2017, about 6–7M+ across platforms; Motorways was an Arcade launch title, 500k+ sold ([PocketGamer.biz](https://www.pocketgamer.biz/how-the-mini-metro-developer-beat-the-odds-to-build-a-premium-mobile-games-studio), [NZGDA](https://www.nzgda.com/blog/news/dinosaur-polo-club-makes-deloittes-fast-50-as-mini-motorways-surpasses-500000-copies-sold)) | Minimal art you can read in one glance; 10–20 minute runs that end in graceful failure; **daily and weekly challenges plus leaderboards** **[challenge detail from general knowledge]** |
| **Downwell** (2015) | Mobile-first; GDC 2016 talk on building everything around one mechanic (gunboots) ([Famitsu](https://www.famitsu.com/news/201603/16101475.html), [Wikipedia](https://en.wikipedia.org/wiki/Downwell_(video_game))) | **Every action does two jobs** (shoot = brake and attack). One input with a deep combo ceiling |
| **Stack** (Ketchapp, 2016) | Free with ads; #1 free chart ([appgefahren](https://www.appgefahren.de/?p=164593)) | Tap to drop; **"perfect" alignment rewards** (the block grows back); colour shifts as you climb; about 30–90 s runs, instant restart **[run length my estimate]** |
| **Wordle** | One puzzle a day, share grid ([Amuse Labs](https://amuselabs.com/resources/author/nishant/page/7)) | Scarcity plus a shareable result makes a ritual without notifications |

**Concrete lessons for us:**
- **Session length:** runs of 30 s to 3 min, restart in under 1 s, "just one more."
- **One input:** the hinge angle is the verb. Make it analogue, not a switch, and give it two jobs (Downwell).
- **Score chasing:** a clear number, an on-screen personal-best line, and Stack-style "perfect" bonuses.
- **Daily challenge:** a shared daily seed plus a copyable result card. Date-keyed Game Center boards mean no server is needed **[implementation assumption]**.
- **Game Center:** daily and all-time leaderboards, plus 10–20 achievements. No Duo hinge game advertises these.
- **Juice:** angle-linked haptics, squash-and-stretch, shake on "perfect", rising pitch on streaks. Apple's game criteria explicitly score controls, sound and animation.
- **Store page:**
  - Screenshot 1 is everything; views drop sharply after the first frame ([Chartboost/Storemaven](https://www.chartboost.com/?p=3084)).
  - In Apple's own PPO case, a video-first page **lost** to screenshots ([Apple PPO](https://developer.apple.com/app-store/product-page-optimization)).
  - Show a real hand folding the phone, A/B test any video, and use a Toastie-style price-joke subtitle.
- **Accessibility and fallback:** a touch-drag "virtual hinge" for non-Duo devices and users who can't fold. It helps featuring and widens the market.

---

## 4. Evergreen "satisfying" mechanics

| Mechanic | Evidence | Status on Duo hinge |
|---|---|---|
| **Timing / stacking** (Stack, Tower, Helix Jump) | Helix Jump has 800M+ downloads, the most-downloaded game of 2018 ([Wikipedia](https://en.wikipedia.org/wiki/Voodoo_(company))) | **Open.** No hinge stacker or balancer found |
| **Slicing / cutting** (soap, fruit, wood) | Crazy Labs Soap Cutting has 44M users; ASMR Slicing 42M installs ([PocketGamer.biz](https://www.pocketgamer.biz/pgc-digital-crazy-labs-explains-why-asmr-slicing-is-successful-after-launch)) | **Taken** (Exactly Half, Duo Cut) |
| **Sort / pour / fill** (water sort, ball sort, screw) | Sort, block and screw puzzles made about $600M IAP in H1 2026; sort reportedly tripled YoY ([AppMagic](https://appmagic.rocks/research/casual-report-H12026), [Udonis](https://www.blog.udonis.co/mobile-marketing/mobile-games/casual-games)) | **Open for the hinge.** WaffleKing "pours" by touch only; no liquid, water or sand entries found |
| **Popping** (bubble wrap, pop-it) | Long-running fidget genre **[no hard data found]** | Bubble Pop Frenzy exists (no hinge) |
| **Smashing / crushing** | Hydraulic-press games (see Squish 06) | **Taken** (Squish, Fold Smasher) |
| **Sand / fluid / physics sandboxes** | Perennial ASMR video favourite **[no download data found]** | **Open** |

The most evergreen mechanics, judged by longevity and how many copies they spawn, are **stacking/timing, slicing, sorting/pouring and popping**. Liquid, sand and balance are the satisfying families that are **still open for hinge control**. A continuous angle naturally maps to *tilt and pour*, *lift and balance*, or *tension and release*.

---

## 5. How real owners hold and use the Duo

- **Half-folded is the signature pose.** Apple's hardware VP cites "a lot of use cases" half-folded, with torque tuned so the middle isn't floppy ([9to5Mac](https://9to5mac.com/2026/09/18/apple-vp-of-hardware-talks-iphone-duo-durability-crease-hinge-and-more/)). Reviews describe "seated" and "tent" poses ([9to5Mac](https://9to5mac.com/2026/10/21/iphone-duo-review/)), tabletop hands-free Netflix ([Consumer Reports](https://www.consumerreports.org/electronics-computers/cell-phones/apple-iphone-duo-review-a5520585020/)), StandBy as a desk clock ([Tom's Guide](https://www.tomsguide.com/phones/iphones/apple-iphone-duo-review)), and split-keyboard typing held "like a book" ([MacDailyNews](https://macdailynews.com/2026/09/11/half-fold-apples-iphone-duo-once-and-youll-start-asking-for-an-ipad-duo/)).
- **Closed is weak.** Daring Fireball calls folded use "the worst iPhone experience ever" ([Daring Fireball](https://daringfireball.net/2026/10/the_iphone_duo)), so the game shouldn't depend on the cover screen.
- **Hinge feel:** "terrific" per review roundups ([MacStories](https://macstories.net/roundups/iphone-duo-review-roundup-great-hinge-messy-apps-and-everybody-misses-face-id/)). It holds at almost any angle, so held angles work as input.
- **Wear:**
  - Apple publishes no fold rating ([Foldify](https://www.foldifycase.com/blogs/news/iphone-duo-hinge-durability-what-apple-did-not-publish-2026)).
  - Stern's robot: 32,640 cycles to about 130°, in a case, never fully closed. The hinge came out slightly stiffer, with no felt change ([MacRumors](https://www.macrumors.com/2026/10/21/iphone-duo-fold-test-hinge/)).
  - Tim Pan: 10.5k folds plus 1k frozen. Still smooth, but **the crease deepened** ([Android Authority](https://www.androidauthority.com/apple-iphone-duo-foldable-display-crease-durability-tests-3726691/)).
  - A Mediastorm reverse-bend flicker is inconclusive ([ZEERA](https://zeerawireless.com/blogs/news/iphone-duo-reverse-bending-test-hinge-oled-flicker)).
  - Forum commenters count folds ("about 5/hour") and note the hinge, unlike the $19 coating, can't be swapped **[unverified comments]**. Samsung rates Z Fold7 displays at 500k folds.
- **Design implication:**
  - Owners are fold-count-aware. A game demanding **hundreds of full slams per session invites "is this wearing out my £2k phone?" reviews** and App Review 2.4.2 scrutiny.
  - Favour small, held, mid-range angle changes (about 60–150°).
  - Never reward closing speed.

---

## 6. Pour concept check: tabletop pose, lift the top half to tip a jug, fill to the line

**Is "fold/tilt to pour" taken on foldables?** *No direct match found.*
- **FoldHunt sweep.** I swept every section of the 701-app list for pour, jug, glass, drink, beer, cocktail, liquid, water, tilt, cup, bartender, coffee, tea, wine and brim. The only near-misses:
  - **WaffleKing** pours batter by *touch*, then you fold to bake.
  - **Duo Coffee** is a pour-over *timer* in tent pose, with no hinge input.
  - **ScrolloDeck** tilts contact cards with the hinge angle (not a game).
  - **Spritz** and the water trackers only use layout.
  - [FoldHunt](https://foldhunt.com/iphone-duo/)
- **DuoDiscover games** and press roundups (MacRumors, Apple story, Chonky) have no pour game.
- **Galaxy foldables.** No Flex-mode pour game turned up. The known hinge games there are **Foldy Bird**, a browser Flappy clone where you fold to flap ([Android Central](https://www.androidcentral.com/gaming/android-games/someone-made-foldy-bird-and-its-a-glorious-way-to-destroy-your-foldable)), and **kami** ([Android Authority](https://www.androidauthority.com/kami-foldable-phone-game-3632416/)). Add Foldy Bird to the taken list as "fold = flap".
- **Caveat.** This is a search-based negative. App Store keyword search on a device for "pour", "jug" and "fold" is still needed **[unverified]**.

**Best-known pour/fill games (the genre is proven, and mostly free with ads):**

| Game | Mechanic | Signal |
|---|---|---|
| **iBeer** (Hottrix, 2008) | Tilt the whole phone to drink/pour beer; shake for foam | $2.99; "$10,000 to $20,000 a day" at peak; #1 download for about a year ([AppleInsider](https://appleinsider.com/articles/22/01/25/original-ibeer-iphone-app-made-creators-20000-a-day), [Cult of Mac](https://www.cultofmac.com/764632/indie-dev-iphone-beer-success/)). **The direct ancestor: a paid tilt-to-pour novelty that sold on new hardware** |
| **Happy Glass** (Lion Studios) | Draw a line so water fills the glass | 100M+ Google Play installs, 1M reviews ([Google Play](https://play.google.com/store/apps/details?id=com.game5mobile.lineandwater&hl=en_US)) |
| **Water Sort Puzzle** (IEC) and clones | Tap to pour coloured liquid between tubes | 100M+ installs ([APKCombo](https://apkcombo.com/water-sort-puzzle/com.gma.water.sort.puzzle/), [App Store](https://apps.apple.com/us/app/water-sort-puzzle/id1514542157)); part of the about $600M H1 2026 sort segment |
| **Magic Pour – Water Match** (2026) | Fill flasks, pour into odd shapes **to dotted target lines**; overflow lowers the score | Small (22 ratings), ad-tracked ([App Store](https://apps.apple.com/us/app/-/id6758132409)). **Closest to "fill to the line", but tap-based** |
| **PourPurr** | Tap to pour; "pro mode" uses device tilt | Listing now 404s **[unverified]** |
| **Where's My Water?** (Disney, 2011) | Dig paths to route water | Classic paid hit **[from general knowledge; no source fetched]** |
| **Bartender: The Right Mix** (HOBO) | Pour ingredients to a recipe, shake, serve | Web/mobile; no data ([TapTap](https://www.taptap.io/kr/app/16707)) |
| **Perfect Pour** | Stop the pour at the line (itch.io), or a beer-pour arcade cabinet | ([itch.io](https://randomvaryable.itch.io/perfect-pour), [All About Beer](https://allaboutbeer.com/perfect-pour-arcade-game/)) |

**Read:**
- Pour-to-line is evergreen and proven. The premium, hardware-novelty version has one famous precedent (iBeer).
- No one has made the *hinge* the pour control.
- Differentiate from iBeer-style whole-phone tilt by making it obvious **the jug is attached to the top half**.
- Pouring drinks risks alcohol themes that push the age rating up. Keep beer to a joke at most, or use water, juice, milk, tea and potions **[judgement]**.

## 7. Name checks (App Store search via web; not checked in App Store Connect)

| Name | Conflicts found | Verdict |
|---|---|---|
| **Brim** | **Brim – Smart Water Tracker** (indie, Apr 2026, active) ([MWM](https://mwm.ai/apps/brim-smart-water-tracker/6761324419)); **Brim Financial** credit-card app ([App Store](https://apps.apple.com/app/id1378431910)); **Blades of Brim** (SYBO, big F2P runner) ([App Store](https://apps.apple.com/app/id891278325)); legacy **Brim!** physics *filling* game (2010) ([TouchArcade](https://toucharcade.com/games/brim-lite)); UK "Brim" TM filed Oct 2025 in Class 9 for business/AI software ([UK IPO](https://www.ipo.gov.uk/t-tmj/tm-journals/2025-043/UK00004272167.html)) | Plain "Brim" is **almost certainly taken** as an App Store name and is crowded. A water-themed same-name app hurts search |
| **Brim: Fold to Pour** | No exact hit. Unique as a compound (18 chars) | **Best option.** "Brim" as the brand, with the subtitle doing the work. Reserve in App Store Connect today. Get a TM check on the "Brim" element (Class 9/41) |
| **Top Up** | Dominated by phone/game credit "top-up" apps (TOPUP Live, Top Up App, Topup Flow) ([App Store](https://apps.apple.com/app/id6446662296)) | **Avoid.** Search intent is mobile recharge, and it reads as IAP currency |
| **Pour Decisions** | **Pour Decisions – Wine Pairing** (exact name, Mar 2026) ([MWM](https://mwm.ai/apps/pour-decisions-wine-pairing/6760296783)); **Pour Decision** ($4.99 alcohol tracker) ([App Store](https://apps.apple.com/app/pour-decision/id6499468185)); a common bar/brewery pun | **Taken.** Alcohol associations too |
| **Fill Line** | **Fill Line** one-stroke puzzle (Mudotek, free with IAP) ([App Store](https://apps.apple.com/us/app/id1370347879)); many "Fill One Line" clones | **Taken.** It would also be buried among line puzzles |

---

## Implications for our game (brief)

- **Open lane:** a premium, replayable, **analogue mid-angle skill game** for book or tabletop pose. Give it a **daily seed, Game Center and a share card**, and build it on an open satisfying family: **pour/fill, sand/fluid or balance/stack**.
- **Avoid:** open/close metaphors, slicing, smashing, angle-matching and pump/bellows motions.
- **Before committing:** re-check FoldHunt, DuoDiscover and an App Store "Duo + mechanic" search on the day we pick. Check r/iPhoneDuo by hand **[not done]**.

---

## Sources

- [FoldHunt — iPhone Duo directory](https://foldhunt.com/iphone-duo/) · [FoldHunt — games](https://foldhunt.com/iphone-duo/games/)
- [DuoDiscover — Games](https://duodiscover.com/category/games) · [Fold Smasher](https://duodiscover.com/apps/fold-smasher) · [Toastie](https://duodiscover.com/apps/toastie)
- [MacRumors — Tiny Mac, Toaster, Nintendo DS (23 Oct)](https://www.macrumors.com/2026/10/23/iphone-duo-fun-apps/)
- [Chonky Corgo — Best iPhone Duo games](https://www.getchonky.app/blog/best-iphone-duo-games/)
- [Apple Newsroom — Developers bring new experiences to iPhone Duo](https://www.apple.com/newsroom/2026/10/developers-bring-incredible-new-app-experiences-to-iphone-duo/)
- [App Store — Great Apps and Games on iPhone Duo](https://apps.apple.com/us/iphone/story/id6820639500)
- [Apple — Getting featured](https://developer.apple.com/app-store/getting-featured/) · [Apple — Product page optimization](https://developer.apple.com/app-store/product-page-optimization)
- [9to5Mac — Duo submissions open](https://9to5mac.com/2026/10/05/apple-invites-developers-to-submit-iphone-duo-ready-apps-to-the-app-store/) · [9to5Mac — Apple VP on durability](https://9to5mac.com/2026/09/18/apple-vp-of-hardware-talks-iphone-duo-durability-crease-hinge-and-more/) · [9to5Mac review](https://9to5mac.com/2026/10/21/iphone-duo-review/)
- [Fix Stories — Orisuji](https://www.fixgamingchannel.com/orisuji-iphone-duo-fix-stories-adrien-friggeri/)
- [MacRumors — 32,000 folds](https://www.macrumors.com/2026/10/21/iphone-duo-fold-test-hinge/) · [Android Authority — durability tests](https://www.androidauthority.com/apple-iphone-duo-foldable-display-crease-durability-tests-3726691/) · [Foldify — no published rating](https://www.foldifycase.com/blogs/news/iphone-duo-hinge-durability-what-apple-did-not-publish-2026) · [ZEERA — reverse bend](https://zeerawireless.com/blogs/news/iphone-duo-reverse-bending-test-hinge-oled-flicker) · [MacRumors Forums — "pinchgate" prediction](https://forums.macrumors.com/threads/prediction-pinchgate.2492098/)
- [Tom's Guide review](https://www.tomsguide.com/phones/iphones/apple-iphone-duo-review) · [Consumer Reports](https://www.consumerreports.org/electronics-computers/cell-phones/apple-iphone-duo-review-a5520585020/) · [Daring Fireball](https://daringfireball.net/2026/10/the_iphone_duo) · [MacDailyNews](https://macdailynews.com/2026/09/11/half-fold-apples-iphone-duo-once-and-youll-start-asking-for-an-ipad-duo/) · [MacStories roundup](https://macstories.net/roundups/iphone-duo-review-roundup-great-hinge-messy-apps-and-everybody-misses-face-id/)
- [Game Developer — Threes free version](https://gamedeveloper.com/business/-i-threes-i-devs-double-daily-income-with-free-version) · [TechCrunch — Threes clones](https://techcrunch.com/2014/03/24/clones-clones-everywhere-1024-2048-and-other-copies-of-popular-paid-game-threes-fill-the-app-stores) · [PocketGamer — Threes dev](https://www.pocketgamer.com/articles/058578/r/)
- [Alto's Adventure — Wikipedia](https://en.wikipedia.org/wiki/Alto%27s_Adventure) · [PocketGamer.biz — Dinosaur Polo Club](https://www.pocketgamer.biz/how-the-mini-metro-developer-beat-the-odds-to-build-a-premium-mobile-games-studio) · [NZGDA — Mini Motorways 500k](https://www.nzgda.com/blog/news/dinosaur-polo-club-makes-deloittes-fast-50-as-mini-motorways-surpasses-500000-copies-sold)
- [Downwell — Wikipedia](https://en.wikipedia.org/wiki/Downwell_(video_game)) · [Famitsu — Downwell GDC 2016](https://www.famitsu.com/news/201603/16101475.html) · [appgefahren — Stack](https://www.appgefahren.de/?p=164593) · [Amuse Labs — Wordle](https://amuselabs.com/resources/author/nishant/page/7)
- [Voodoo — Wikipedia](https://en.wikipedia.org/wiki/Voodoo_(company)) · [PocketGamer.biz — Crazy Labs ASMR slicing](https://www.pocketgamer.biz/pgc-digital-crazy-labs-explains-why-asmr-slicing-is-successful-after-launch) · [AppMagic — Casual H1 2026](https://appmagic.rocks/research/casual-report-H12026) · [Udonis — Casual 2026](https://www.blog.udonis.co/mobile-marketing/mobile-games/casual-games) · [Innovecs — Hyper-casual 2026](https://www.innovecsgames.com/blog/hyper-casual-games/)
- [Chartboost/Storemaven — screenshot view rate](https://www.chartboost.com/?p=3084)
- Pour/names (§6–7): [AppleInsider — iBeer](https://appleinsider.com/articles/22/01/25/original-ibeer-iphone-app-made-creators-20000-a-day) · [Happy Glass — Google Play](https://play.google.com/store/apps/details?id=com.game5mobile.lineandwater&hl=en_US) · [Water Sort Puzzle](https://apps.apple.com/us/app/water-sort-puzzle/id1514542157) · [Magic Pour](https://apps.apple.com/us/app/-/id6758132409) · [Foldy Bird — Android Central](https://www.androidcentral.com/gaming/android-games/someone-made-foldy-bird-and-its-a-glorious-way-to-destroy-your-foldable) · [Brim water tracker](https://mwm.ai/apps/brim-smart-water-tracker/6761324419) · [Brim Financial](https://apps.apple.com/app/id1378431910) · [Blades of Brim](https://apps.apple.com/app/id891278325) · [Brim! Lite](https://toucharcade.com/games/brim-lite) · [Pour Decisions – Wine Pairing](https://mwm.ai/apps/pour-decisions-wine-pairing/6760296783) · [Pour Decision](https://apps.apple.com/app/pour-decision/id6499468185) · [Fill Line](https://apps.apple.com/us/app/id1370347879) · [TOPUP Live](https://apps.apple.com/app/id6446662296)
