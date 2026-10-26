# Brim: Press kit

*Everything here is **embargo-free**: anyone may write about Brim from the day they receive it. The public version of the fact sheet is the Press section of `docs/site/index.html`; keep the two in step. The founder sends every email by hand; nothing is automated.*

---

## The pitch (one paragraph)

**Brim turns the iPhone Duo into a jug.** Lay the Duo open on a table and lift the top half like a laptop lid: a jug drawn on that half tips with it, and a stream of lemonade pours across the fold into a glass waiting on the flat half. Lower the lid to stop, but the stream is still falling, so the trick is to stop just before the line. The liquid in the jug stays level, so a full jug pours at a slight lift and an empty one needs a steep one; the glass sings higher as it fills, so experts pour by ear. There are five venues of shifts (foamy sodas, slow milkshakes, glasses on a conveyor, potions measured to the drop), an endless Rush mode, and a seeded Daily Pour that's the same for everyone and shares as a row of emoji. It also plays on every other iPhone: drag up to tip. £1.99 / $1.99, no ads, no in-app purchases, no data collected, rated 4+, and every drink is non-alcoholic.

**One-liner:** *Your iPhone Duo is the jug: lift the top half to pour across the fold, and stop right on the line.*

**Short (for listings, ≤ 140 chars):** *A pouring game for iPhone Duo: lift the top half to tip the jug, pour across the fold, stop on the line. £1.99, no ads.*

---

## Fact sheet

| | |
|---|---|
| **Name** | Brim (App Store: "Brim: Fold to Pour") |
| **Developer** | Brim, an independent studio (GitHub `pravegm`), also making Squish |
| **Founder** | [Founder name] (left off the live page unless the founder chooses) |
| **Release** | **Tue 17 Nov 2026**, worldwide (except China mainland and Vietnam) |
| **Platform** | iPhone. Designed for iPhone Duo in tabletop pose (the hinge is the only control); drag-to-tip on every other iPhone. Requires iOS 18 or later; hinge play uses iOS 27.1, which the Duo ships with |
| **Price** | £1.99 / $1.99 / €1.99 one-off. No ads, no in-app purchases. Family Sharing on |
| **Age rating** | 4+ (every drink is non-alcoholic) |
| **Modes** | Shifts across 5 venues (Lemonade Stand, Soda Fountain, Milkshake Diner, The Conveyor, Potion Shop) plus a secret sixth · Rush (endless) · Daily Pour (seeded, one scored try, shareable) |
| **Features** | Hinge-angle pouring with level-liquid physics · a stream that takes time to fall · foam and thick-liquid behaviour · rising "filling glass" pitch · glug haptics · Perfect streaks and a ×5 multiplier · Game Center leaderboards (Rush, Daily) and 10 achievements |
| **Sound** | Every sound synthesised in the app; no recordings or licensed assets |
| **Accessibility** | Plays fully without folding (drag) on non-Duo iPhones · results always shown as words · Reduce Motion respected · sound and haptics switch off separately |
| **Privacy** | Data Not Collected. No accounts, no tracking, no third-party SDKs |
| **Languages** | English |
| **Size** | ~[XX] MB (fill in from App Store Connect after processing) |
| **Links** | App Store: https://apps.apple.com/app/id6826940959 · Site: https://pravegm.github.io/brim/site/ · Support: https://pravegm.github.io/brim/site/support.html |
| **Press contact** | Reply to the founder's pitch email (sent by hand from the founder's own address). Public channel: https://github.com/pravegm/brim/issues. Never post promo codes in an issue |

---

## Key features (for writers who want bullets)

- **The fold is the jug.** The glass stays still on the table while only the jug half moves. No other phone can do that.
- **Physically true.** The surface in the jug stays level, so how far you lift depends on how full it is. The stream takes 0.35–0.5 s to fall: stop early.
- **Pour by ear.** The pitch rises as the glass fills, like a real glass under a tap.
- **Every liquid has a personality.** Soda foams up then settles; milkshakes and honey lag and keep coming after you stop; potions come in tiny vials with lines that fade.
- **Called to the drop.** Perfect, Great, Good, Short, Over or Spill. A Perfect gets a bright *ting*, a sparkle ring and a climbing streak note.
- **One more go.** Runs last 1–2 minutes. Rush's multiplier climbs to ×5; the Daily Pour is the same ten glasses for everyone.
- **Kind to the hinge.** Play lives in the middle of the hinge's range with slow, held angles. It never asks you to close the phone or fold fast.

## Founder quote (placeholder; founder writes it)

> "[Founder to write in their own words. Suggested angle: the first time the stream crossed the fold on a real Duo; why a pouring game is the most natural thing a hinge can do; why no ads.]"
> — [Founder name], Brim

*Draft to edit or replace:* "Tipping something is the most natural thing a hinge does. The first time the stream left the top screen and landed in a glass on the bottom one, it felt like the phone had always been meant to do it. Then I overfilled it, and had to have another go."

---

## Assets

Put these in one public folder (a shared iCloud Drive or Google Drive folder, or, if the repo goes public, a GitHub Release named `press-kit`), and paste its link wherever `[press folder]` appears.

| File | Spec | Source |
|---|---|---|
| `brim-icon-1024.png` | 1024 × 1024 | CI `screenshots` artifact → `AppIcon-1024.png` (scenario `14-icon`) |
| `brim-duo-01…05.png` | 2007 × 2853, **no captions** | `duo-screens` artifact, the D1–D5 raw frames (D6 dropped at sign-off) (`screenshots.md` §A) |
| `brim-iphone-01…05.png` | 1320 × 2868, no captions | the 6.9" raw frames P1–P5 |
| `brim-teaser-15s.mp4` | 1080 × 1920, with sound | the founder's real-hands clip (`social-launch.md` §3A) |
| `brim-preview.mp4` | 886 × 1920, with sound | the App Preview, if made (`social-launch.md` §3B) |
| `brim-pour-loop.gif` | ≤ 8 MB, 600 px wide | the stream crossing the fold, looped |
| `brim-factsheet.pdf` | 1 page | this fact sheet (print the site's Press section to PDF) |

**Never include:** the secret venue, any frame with alcohol cues, any shot of something real placed on the screen.

**Promo codes:** App Store Connect → the app → Promo Codes, available once 1.0 is approved. Check the current per-version cap and expiry there (historically 100 per version, valid 28 days). Log every code in a sheet: who, when, outlet.

---

## Pitch emails

Plain text, under 150 words, clip link in the first two lines, never attach video, one outlet per email (never CC). Fill in only `[your name]`, `https://apps.apple.com/app/id6826940959` (once the record is live: App Store Connect → App Information → Apple ID → `https://apps.apple.com/app/id6826940959`), `[clip link]`, `[TestFlight link]`, `[promo code]`, `[expiry]`. Check every address on the outlet's own contact page first. The send dates are in `social-launch.md` §4.

### 1. Tip line (MacRumors, 9to5Mac, TechCrunch)

**Subject:** Tip: an iPhone Duo game where the hinge pours the drink (15s clip)

> Hi there,
>
> 15-second clip, sound on: [clip link]
>
> I'm launching Brim on Tue 17 Nov. Lay the iPhone Duo open, lift the top half like a laptop lid, and a jug drawn on that half tips and pours across the fold into a glass on the flat half. Stop right on the line. The liquid stays level in the jug, so a nearly empty jug needs a steeper lift, just like a real one.
>
> - Five venues, an endless Rush mode and a seeded Daily Pour with Game Center leaderboards.
> - Plays on every iPhone (drag up); the Duo is the hero.
> - £1.99/$1.99, no ads, no IAP, no data collected, 4+.
>
> TestFlight, more clips or a promo code on request. No embargo.
>
> [your name], Brim
> https://pravegm.github.io/brim/site/

### 2. Duo directories (FoldHunt, DuoDiscover): listing request

**Subject:** Listing request: Brim, a fold-to-pour game for iPhone Duo

> Hi,
>
> Could you add Brim to your iPhone Duo games list? The hinge is the pour control: in tabletop pose, lifting the top half tips a jug drawn on it, and the stream crosses the fold into a glass on the flat half. Stop on the line.
>
> - Uses the hinge angle continuously (175° to about 95°), never needs closing; a book-pose pause card and a cover-display status card.
> - Game Center leaderboards and a Daily Pour challenge.
> - £1.99/$1.99, no ads, no IAP. Out Tue 17 Nov.
> - Clip: [clip link] · Screenshots and icon: [press folder]
>
> I'll send the App Store link the day it's live.
>
> Thanks,
> [your name], Brim

### 3. Games press (PocketGamer, TouchArcade)

**Subject:** Brim: a premium pour-to-the-line game built on the iPhone Duo's hinge

> Hi,
>
> Pour games on iOS are mostly ad farms. Brim is a £1.99/$1.99 one with no ads, no IAP and no timers, where the iPhone Duo's hinge is the jug: lift the top half to pour across the fold, stop on the line.
>
> - Real-feeling liquids: level surfaces, foam that climbs, shakes that keep coming after you stop.
> - Five venues of shifts, an endless Rush mode with a ×5 streak multiplier, and a Daily Pour that's the same for everyone.
> - Game Center leaderboards and achievements; drag to play on any iPhone.
>
> Out Tue 17 Nov. Clip: [clip link] · TestFlight: [TestFlight link] · promo code on request after approval.
>
> [your name], Brim

*TouchArcade: also start a thread in its forums' upcoming-games section, saying you're the developer.*

### 4. Writers who covered Duo games (Digital Trends' Vikhyaat Vivek; Chonky Corgo blog; Fix Gaming Channel)

**Subject:** For your Duo games list: the hinge as a pouring jug

> Hi [name],
>
> I read your piece on [their article]. I liked [one specific thing they said]. Brim is a game where the hinge is the whole control: lift the Duo's top half and a jug on it tips, pouring across the fold into a glass on the bottom half. It's analogue (the angle sets the flow), so it's a skill game rather than a fold-to-switch toy, with a Daily Pour and leaderboards.
>
> 15 s clip: [clip link] · TestFlight: [TestFlight link]
>
> £1.99/$1.99, no ads, out Tue 17 Nov. Happy to explain how the angle maps to the pour.
>
> [your name], Brim

### 5. Duo creators (TikTok, YouTube Shorts), after approval

**Subject:** A free code for Brim: your Duo becomes a jug

> Hey,
>
> I make Brim: lift the top half of your Duo and the jug on it pours across the fold into a glass. Stop on the line. It reads well on camera from a low side angle, so you see the lid lift and the stream land.
>
> Here's a free code: [promo code] (redeem by [expiry]). No script, no obligation. If you post, a "gifted" tag keeps you right with the platform rules, and caption-free clips are here: [press folder].
>
> Thanks either way!
> [your name], Brim

### 6. Launch-day note (reply in each earlier thread)

> Brim is out today: https://apps.apple.com/app/id6826940959. The iPhone Duo's hinge is the jug; on other iPhones you drag up. £1.99/$1.99, no ads, no IAP, no data collected. Everything in [press folder] is free to use. Promo code on request.
>
> [your name]

Then stop. One more email only if a free update with real new content ships.

## Sources
- `research/01-market.md` (outlets that covered Duo games, Toastie and Orisuji coverage paths, iBeer precedent)
- Squish press kit (structure mirrored): `C:\Users\59527\Squish\docs\appstore\press-kit.md`
