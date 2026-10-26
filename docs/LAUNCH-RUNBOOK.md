# Brim launch runbook (for the founder)

*Written Sun 25 Oct 2026. This is the only document you need to follow. It goes in order, and each step says exactly where to click and what to type. Everything you paste lives in `docs/appstore/`; the reason behind every choice is in `docs/appstore/DECISIONS.md`. Whenever a step says "tell Claude", a one-line message is enough.*

**Launch: Tuesday 17 November 2026, 08:00 UK time** (08:00 UTC; midnight in California). Squish launches a week later, on Tue 24 Nov.

---

## Where things stand (Mon 26 Oct, evening): read this first

Claude pushed the listing into App Store Connect with `tools/appstore/asc.swift` (runs 40343054685, 40345636077, and the screenshots run named in HANDOVER). **Most of §0–§4 below is already done** and stays only as reference.

**Done, nothing for you to do:**
- **Listing:** name, subtitle, description, keywords, promo text, URLs (en-GB and en-US), categories (Games › Casual + Simulation, then Entertainment) and Content Rights.
- **Age rating:** the 2026 questionnaire, answered 4+. Contests is "Infrequent" because of the leaderboards.
- **Release:** version 1.0 is **Scheduled** for 17 Nov 08:00 UTC, with copyright and the App Review contact copied from Squish's record.
- **App Review notes:** 3,946 bytes.
- **Price:** £1.99 with the UK as base, available everywhere except China mainland and Vietnam.
- **Game Center:** on, with 10 achievements (badges in both languages) and both leaderboards (`brim.rush.best`; `brim.daily.score`, recurring daily from 1 Nov).
- **Featuring nomination:** submitted (App Launch, 17 Nov).
- **Website:** support, privacy and home pages are live at https://pravegm.github.io/brim/site/. Support runs through GitHub issues, so you don't need a support email.

**Your remaining steps (about 15 minutes, all in App Store Connect → Brim):**
1. **App Privacy** → Get Started → "No, we do not collect data from this app" → Save → **Publish**.
2. **Pricing and Availability:** under "iPhone and iPad Apps on Apple Silicon Macs", untick *Make this app available*. Under "Apple Vision Pro", untick it too. Save.
3. **App Information:** turn **Family Sharing** on. Then **App Store Regulations and Permits → EU Digital Services Act**: confirm your trader status for Brim. Apple asks again for each app; use the same answer as Squish.
4. **Play the release candidate on your Duo** (§3, including the new "Duo specifics" block), and send Claude your notes.
5. **Release build: 1.0 (13)** (founder-tested 26 Oct). On the 1.0 page, in the Build section, click **+** and pick **13**. Screenshots (6.9", 6.1" and iPhone Duo, en-GB and en-US) are uploaded, and the 12 Game Center items are attached to the draft submission (asc run 40372736601). Then **Add for Review → Submit to App Review**, any day up to Fri 13 Nov.
6. **Launch day:** publish the accessibility labels (§6).

---

## Timeline

| When | Who | What | Section |
|---|---|---|---|
| **Sun 25 – Mon 26 Oct** | You | Decide the 4 things in §0. Register Brim with Apple and create the app record (about 20 minutes) | §0, §1 |
| ~~By Tue 27 Oct~~ | ✅ Claude, 26 Oct | Featuring nomination submitted through the API | §1e |
| Mon 26 – Wed 28 Oct | You | Add the 4 GitHub secrets (10 minutes) | §2 |
| ~Wed 28 Oct (when Claude says the build is ready) | You | Run the TestFlight build (2 clicks) | §2 |
| **Thu 29 Oct – Sun 1 Nov** | You | First play on your Duo: the 10-minute feel check, then send Claude your notes | §3 |
| Mon 2 – Fri 6 Nov | Claude, then you | Claude tunes the feel from your notes; you re-check the new build (10 minutes) | §3 |
| **Fri 6 – Sun 8 Nov** | You | Put the website live; paste the store listing, prices, privacy, age rating and Game Center items | §4 |
| **Mon 9 Nov** | Claude | Code freeze: the final build and the screenshots | — |
| **Tue 10 Nov** | You | Choose the final build, upload screenshots, **submit for review** (hard cut: Fri 13 Nov) | §4.5, §5 |
| Wed 11 Nov | You | (Squish's own submission day: keep Brim work off this day) | — |
| ~Thu 12 Nov | Apple | Approval, usually within 24–48 hours. Brim then waits for its release date by itself | §5 |
| Sat 14 – Mon 16 Nov | You | Promo codes for creators; pre-launch posts | §6 |
| **Tue 17 Nov, 08:00 UK** | Apple, then you | Brim goes live. Launch-day steps | §6 |

**Why 17 November:** it's a different week from Squish (24 Nov), so each game gets its own news, its own featuring slot and your full attention on its day. Going a week *before* Squish rather than after keeps Brim out of US Thanksgiving week and Black Friday noise, and catches new Duo owners while they're still filling their phones with apps (the Duo went on sale 23 Oct). It's 23 days away: enough for 3 weeks' featuring notice, two rounds of real-Duo tuning and a week of review buffer.

**If the build isn't ready by Thu 12 Nov:** move the launch to **Tue 1 Dec**, never to 24 Nov. Change the release date (§4.4) and the nomination's Publish Date (§1e), and tell Claude.

---

## §0. The only things you must personally do or decide

| # | What | Why only you |
|---|---|---|
| 1 | **Your legal name** (or company name) for the line `2026 <your legal name>` | It's your legal identity |
| 2 | **Review contact:** first name, last name, phone number, email | Apple's reviewers call or email a real person. Typed straight into App Store Connect, never into the repo |
| 3 | ~~A support email~~ **Not needed (26 Oct):** the repo is public, so support runs through GitHub issues, as Squish's does | — |
| 4 | **Where the website lives** (support and privacy pages), see the box below | It's your account and your repo |
| 5 | **Apple-login steps:** §1 (register, create the record, nomination), §2 (secrets), §4 (paste the listing), §5 (submit), §6 (accessibility labels on launch day) | They need your Apple Account |

**Already done for Squish, so nothing new (just check they still say Active):** the Paid Apps agreement, tax and banking (App Store Connect → Business), the Small Business Program, and your EU trader (Digital Services Act) status. These cover every app on your account.

> **Decision: where the website lives (pick one, tell Claude which).** The repo `pravegm/brim` is private, and GitHub's free plan only publishes websites from public repos.
> - **Option A (recommended): make the repo public and turn on GitHub Pages.** github.com/pravegm/brim → Settings → General → scroll to "Danger Zone" → Change visibility → Public. Then Settings → Pages → Source "Deploy from a branch" → Branch `main`, folder `/docs` → Save. In about a minute the pages are at `https://pravegm.github.io/brim/site/` (support: `…/site/support.html`, privacy: `…/site/privacy.html`). *Side effects:* anyone can read the code and these launch documents (no personal data is in them), and GitHub's Mac build minutes become free, as with Squish. If you'd like cleaner addresses without `/site/`, tell Claude: it's a small one-time change.
> - **Option B: keep the repo private, use a free static host.** Go to app.netlify.com/drop, sign up, and drag the `docs/site` folder onto the page. Rename the site (Site settings → Change site name, e.g. `brim-pour`), giving `https://brim-pour.netlify.app/support.html` and `/privacy.html`. Re-drag the folder whenever the pages change.
> - **Option C:** keep it private and pay for GitHub Pro (about $4/month), which allows Pages from a private repo; then follow Option A's Pages step without changing visibility.
>
> Whatever you pick, the three addresses are the "Support URL", "Marketing URL" and "Privacy Policy URL" in §4. Wherever the docs say `<SITE>`, use your site's address (Option A: `https://pravegm.github.io/brim/site/`).

---

## §1. Register Brim with Apple and create the app record (about 20 minutes, once)

**1a. Register the bundle ID.** Go to developer.apple.com → Account → **Certificates, IDs & Profiles** → **Identifiers** → the blue **+**.
1. Choose **App IDs** → Continue → **App** → Continue.
2. Description: `Brim`
3. Bundle ID: **Explicit**, `com.pravegm.brim`
4. In the Capabilities list, tick **Game Center** (nothing else).
5. Continue → Register.

**1b. Create the app record.** Go to appstoreconnect.apple.com → **Apps** → the blue **+** → **New App**.

| Field | Type or pick |
|---|---|
| Platforms | **iOS** |
| Name | `Brim: Fold to Pour` (if it says the name is taken, try `Brim: Pour to the Line`, then `Brimful: Fold to Pour`, and tell Claude which one worked) |
| Primary Language | **English (U.K.)** |
| Bundle ID | pick `com.pravegm.brim` from the list (if it's missing, wait 5 minutes and reload) |
| SKU | `brim-ios` |
| User Access | **Full Access** |

Click **Create**.

**1c.** ✅ Done 26 Oct: Apple ID `6826940959`, so the App Store link is `https://apps.apple.com/app/id6826940959` (it works from launch morning).

**1d. Turn on Game Center:** in the app, open **Services** (in some layouts **Features**) → **Game Center** → turn it on. You'll add the leaderboards and achievements in §4.6.

**1e. Featuring nomination (by Tue 27 Oct).** In the app: **Featuring** → **Nominations** → **Create Nomination**. Copy every field from `docs/appstore/featuring-nomination.md`. Press **Submit** (a saved draft doesn't count).

---

## §2. Connect GitHub to Apple, then build for TestFlight

GitHub builds Brim for you on Apple's latest Xcode (your Mac can't run it). It needs four "secrets": the same four values the Squish repo uses. One Apple key works for all your apps.

**2a. Gather the four values.** GitHub never shows a saved secret again, so you can't copy them out of Squish's settings. Get them from the source:

| Secret name | Where to find the value |
|---|---|
| `ASC_KEY_ID` | App Store Connect → Users and Access → **Integrations** → App Store Connect API → **Team Keys**: the "Key ID" column of your Squish key (named `Squish CI`) |
| `ASC_ISSUER_ID` | Same page, the **Issuer ID** shown above the table |
| `ASC_PRIVATE_KEY` | The `.p8` file you downloaded when you made that key. Open it in TextEdit (or Notepad) and copy **all** of it, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |
| `APPLE_TEAM_ID` | developer.apple.com → Account → **Membership details** → Team ID (10 characters) |

*Can't find the `.p8` file?* Apple only lets you download it once. Make a new key on the same Team Keys page: **+**, name `Studio CI`, Access **Admin**, Generate, **Download** the file straight away, and use the new Key ID. Don't revoke the Squish key: Squish keeps working with it.

**2b. Add them to Brim's repo.** github.com/pravegm/brim → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**. Add each of the four: type the name exactly as above, paste the value, **Add secret**.

**2c. Run a build (when Claude tells you the game is ready).** github.com/pravegm/brim → **Actions** → **TestFlight** (left list) → **Run workflow** → keep branch `main` → in "What to test" type anything (e.g. `first Duo test`) → **Run workflow**.
- About 20–30 minutes later the run shows a green tick. A red cross with "Missing repository secrets" means a name in 2b is misspelt; anything else, send Claude the link to the run.
- 10–30 minutes after the green tick, the build appears in App Store Connect → the app → **TestFlight**, first as "Processing". You won't be asked about encryption: that answer is already built in.

---

## §3. Play it on your Duo: the 10-minute feel check

**Set up (once).** App Store Connect → the app → **TestFlight** → **Internal Testing** → **+** → group name `Studio` → add yourself (your Apple Account email) → add the build. On the Duo, install Apple's **TestFlight** app from the App Store, sign in with the same Apple Account, and tap **Install** next to Brim. Later builds appear there automatically.

**Before you start:** ringer on, volume at about half, sitting at a table. Open the Duo flat on the table, inner screen up, fold running left to right.

| Minute | Try this | Notice |
|---|---|---|
| 0–1 | Open Brim for the first time. Follow the hints "Lay it flat to start", then "lift the top half to pour" | Did you get it without thinking? How far did you lift before anything poured? |
| 1–3 | Pour five glasses at the Lemonade Stand | Does the pour start when you expect and stop when you lower the lid? Could you get a Perfect within 5 tries? Did it feel fair when you missed? |
| 3–4 | Keep going until the jug is nearly empty | Did you need to lift further as it emptied, and did that feel natural? |
| 4–5 | Pour with your eyes half closed, listening | Can you hear the pitch rise as the glass fills? Do you feel the glugs in your hand? |
| 5–7 | Play one **Rush** run | Did you want "one more go" at the end? Anything annoying? |
| 7–8 | Play the **Daily Pour**, then tap **Share** and send it to yourself | Does the result row look right? |
| 8–9 | Lay the phone flat and leave it. Then turn it to book pose (fold top to bottom). Then, **in the middle of a pour, close the phone quickly**, look at the outer screen, and reopen. Do the quick close 10 times across the session | No dribble when flat? The "Turn me so the fold runs side to side" card in book pose? Closing mid-pour should never cost you a glass or a strike, and reopening asks you to lay it flat before play carries on. Count any strikes it cost you |
| 9–10 | Flip the silent switch on, then open Settings | Is there still sound? Do the sound, haptics and "Respect silent mode" switches work? |

**Duo specifics (3 minutes, after row 9–10; DUO-AUDIT M4).** Only your Duo can answer these:

1. With the phone turned round as Brim asks, lift from flat 5 times. Which half blurs, the jug or the glasses? Does it happen on every lift, or only the first?
2. Between glasses, rest the lid just off the table (about a finger's width) instead of fully flat. Does the blur still happen?
3. Settings › About: copy the grey "Screen: … · iOS turn: …" line (it only shows in TestFlight builds).
4. Hold the phone sideways (book pose), open Safari, then put Brim beside it in Split View. What does Brim's half show? Can you pour by dragging?
5. Close the phone mid-shift and look at the outer screen. Does it say the shift is paused? Tap **Pour here with touch**, pour one glass, open the phone, lay it flat, carry on.
6. Leave it lying flat and untouched for a minute. Does anything ever dribble?
7. Pour with your ear near each half. Which half is the glug louder on?

**Comfort check (important):** at any point did you have to lift past upright, move fast, or worry about the hinge? Did your hand get tired?

**Send Claude this (copy, fill in, paste in chat):**
```
Brim build [number from TestFlight], iPhone Duo, iOS [version]
Scores 1-5: pour starts when expected [ ] / stopping is controllable [ ] / Perfect feels earned [ ] / sound [ ] / haptics [ ] / comfort [ ] / want one more go [ ]
Lift before the first drop: [tiny / about right / too much]
Quick closes mid-pour that cost a strike: [ ] out of 10
Did the screen ever dim or lock while you were pouring? [yes/no]
Duo specifics: blur on [jug / glasses], [every lift / first only]; off-the-table rest blurs? [yes/no]; Settings line: [ ]; Split View: [ ]; cover after closing: [ ]; dribble when flat? [yes/no]; louder half: [jug / glasses]
Best moment:
Worst moment:
Bugs (what you did, what happened):
Anything confusing:
```
A screen recording (Control Centre → Screen Recording, with the microphone on) or a phone video of you pouring helps a lot: send it if you can. In TestFlight you can also take a screenshot in Brim and tap **Share Beta Feedback**.

Repeat the check on each new build Claude sends (Mon 2 – Fri 6 Nov). The release build is the one where your scores are all 4 or 5 and comfort is 5.

---

## §4. Put the listing into App Store Connect (one evening, Fri 6 – Sun 8 Nov)

Paste everything from `docs/appstore/metadata.md` unless a step says otherwise. Later, Claude can copy Squish's listing tool (`asc.swift` plus a data file) so updates become one click; for 1.0, pasting by hand is quicker.

**4.0 Put the website live** (the option you chose in §0) and open the three pages on your phone. All three must load before Apple will accept them. Make sure the support email shows instead of `SUPPORT_EMAIL_HERE`.

**4.1 App Information** (left sidebar):
- **Subtitle:** `Fill every glass to the line`
- **Category:** Primary **Games**, subcategories **Casual** and **Simulation**. Secondary **Entertainment**.
- **Content Rights:** "Does your app contain, show, or access third-party content?" → **No**.
- **Age Rating:** Edit → answer exactly as the table in `metadata.md` §8 (everything None or No). It should say **4+**.
- **Add English (U.S.):** at the top right, the language menu → **Add Language** → English (U.S.) → fill the same name and subtitle.

**4.2 Pricing and Availability:**
- Price: **Add Pricing** → base country **United Kingdom** → **£1.99**. Leave other countries on Apple's automatic prices; check the US shows **$1.99**.
- Availability: all countries or regions **except China mainland** (untick it).
- Pre-order: **off**. Family Sharing: **on** (permanent once on).

**4.3 App Privacy:** Privacy Policy URL = your privacy page. **Get Started** → "Do you or your third-party partners collect data from this app?" → **No, we do not collect data from this app** → Save → **Publish**. (Details: `privacy.md`.)

**4.4 The 1.0 version page** (left sidebar, under iOS App). For **English (U.K.)**, then switch the language menu to **English (U.S.)** and repeat:
- **Promotional Text**, **Description** (the U.K. or U.S. block), **Keywords**: from `metadata.md` §3–5.
- **Support URL**, **Marketing URL**: your site addresses.
- **Copyright:** `2026 <your legal name>`.
- **App Review Information:** Sign-in required **unticked**; your first name, last name, phone, email; **Notes:** paste the block from `review-notes.md`.
- **Version Release:** "Automatically release this version after App Review approval, no earlier than" → **17 Nov 2026, 08:00** in UK time (the page shows your own time zone).

**4.5 Screenshots** (same page, Previews and Screenshots). Claude sends you a link to the final screenshot download on Mon 9 Nov.
1. **6.9" Display:** drag in P1–P5, in order.
2. **6.1" Display** (or whichever "iPhone with Dynamic Island" slot it asks for): P1–P5.
3. Open the device list. **If you see iPhone Duo**, add D1–D6 there and check them with Apple's iPhone Duo preview. If there's no iPhone Duo entry, skip it (Duo screenshots come with 1.0.1).
4. App Preview video: only if Claude says it's ready.

**4.6 Game Center** (the app → Services → Game Center). Copy from `achievements.md`:
1. **Leaderboards → +**: create `brim.rush.best` (Classic) and `brim.daily.score` (**Recurring**: start 1 Nov 2026 at 00:00 UTC, which is midnight UK time in winter; lasts 1 day; repeats every 1 day). Fill in names and score format for English (U.K.) and English (U.S.).
2. **Achievements → +**: create all ten, IDs exactly as written (they can never be changed), with titles, both descriptions, points, and **Hidden** ticked only for `brim.sandbar`. Each needs its 1024 × 1024 image: Claude sends the ten images.
3. Back on the **1.0 version page**, in the **Game Center** section, switch it on and **+** add both leaderboards and all ten achievements. They only go live with the version.

**4.7 Build** (1.0 version page, Build section): **+** → choose the build Claude names as the release build (Tue 10 Nov).

---

## §5. Submit for review (Tue 10 Nov; last safe day Fri 13 Nov)

1. On the 1.0 page, click **Add for Review**. If App Store Connect lists anything missing, fix it and click again.
2. Click **Submit to App Review**.
3. Usually 24–48 hours. You'll get an email.
   - **Approved:** the status shows it's waiting for 17 Nov. Do nothing: it goes live by itself. **Don't** press "Release This Version" early.
   - **Rejected:** don't panic. Copy Apple's message to Claude. Ready-made replies are in `review-notes.md` ("If rejected under…"). Answer in the Resolution Center the same day.

---

## §6. Launch day: Tue 17 Nov

**Before 08:00 UK (or the days before):**
- Sat 14 – Mon 16 Nov: App Store Connect → the app → **Promo Codes** → generate codes for the creators in `social-launch.md` §4. Keep a list of who got which.

**After 08:00 UK:**
1. Open Brim's App Store page on your phone (UK) and check: price £1.99, **4+**, "Data Not Collected", the screenshots, Game Center. Ask a US friend, or switch storefront, for $1.99.
2. **Accessibility labels:** App Store Connect → the app → **App Accessibility** → Get Started → **iPhone**. Tick only the labels `accessibility.md` marks as passed (planned: **Reduced Motion**, **Sufficient Contrast**, **Differentiate Without Color Alone**). Leave the rest unticked → **Publish**.
3. Post the launch posts from `social-launch.md` §2, and send the launch-day emails from `press-kit.md` #6 (replies in your earlier threads).
4. Tell Claude "Brim is live": Claude swaps "On the App Store 17 November" on the website for the real App Store link.
5. Play the first Daily Pour yourself and check your score appears on the Daily Pour leaderboard.
6. For the next few days: App Store Connect → the app → **Ratings and Reviews**, and TestFlight / Xcode crash reports. Forward anything odd to Claude for 1.0.1.

**Squish's launch is next Tuesday (24 Nov).** Keep that day Brim-free, and move Squish's planned 17 Nov clip to Wed 18 Nov.
