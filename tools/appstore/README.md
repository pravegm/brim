# App Store Connect from GitHub Actions

`asc.swift` puts the whole Brim 1.0 listing into App Store Connect from `docs/appstore/asc-metadata.json`. It's a port of Squish's tool (same Apple account) plus leaderboards, the review-submission attach step, the featuring nomination and `--inherit-from`. It is idempotent: it changes only what differs, and `push` resumes after a failure.

Nobody pastes anything. The founder only runs the workflow.

## Run it

GitHub → **Actions** → **App Store Connect tool** → **Run workflow**:

| Input | Meaning |
|---|---|
| `asc` | Tick to contact App Store Connect. Unticked, the run only typechecks and validates |
| `mode` | `check`: read-only status. `plan`: check plus a dry run, still read-only. `push`: check, plan, then write |
| `only` | Optional step list, e.g. `nomination` or `gamecenter,attach` |
| `store_run` | A green **App Store screenshots** run. Empty = `DEFAULT_STORE_RUN` in the workflow (40270623298, the final frames) |
| `ci_run` | A green **CI** run whose `screenshots` artifact holds `badges/`. Empty = the latest green run on `main` |
| `inherit_from` | Default `com.pravegm.squish`. See "Personal data" |

Every run uploads `asc-output` (check.txt, plan.txt, push.txt). Read `plan.txt` before running `push`.

```bash
gh workflow run asc.yml -R pravegm/brim -f asc=true -f mode=plan
gh workflow run asc.yml -R pravegm/brim -f asc=true -f mode=push -f only=nomination
```

The secrets are the shared Admin team key: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`. The key is written to a temp file for the job and deleted at the end.

## Personal data (the repo is public)

The metadata file has no name, phone, email or legal name: `copyrightHolder` and `review.contact` are `null`. With `--inherit-from com.pravegm.squish` (or `ASC_INHERIT_FROM`), the tool reads Squish's newest version at run time: its `copyright` line and its `appStoreReviewDetail` contact. It uses them in memory for Brim. Every value is masked in all output (`‹hidden›`, plus GitHub's `::add-mask::`), and `asc-output` gets only masked lines. Never put these values in a file.

## What `push` does, in order

| Step | What |
|---|---|
| `appinfo` | Name, subtitle and privacy URL for en-GB and en-US. Primary language en-GB. Content Rights: no third-party content |
| `categories` | Games: Casual and Arcade, then Entertainment. Subcategories are checked against Apple's live list first. **On 26 Oct the live list had no Arcade** (run 40340641267), so this step fails until `metadata.md` §7 picks another second subcategory or none |
| `agerating` | The questionnaire from `metadata.md` §8: everything None or No except Contests = Infrequent. Result 4+ |
| `version` | 1.0: copyright (inherited), release **Scheduled**, no earlier than 17 Nov 2026 08:00 UTC |
| `localizations` | Description (UK and US spellings), keywords, promotional text, support and marketing URLs |
| `review` | Review notes (≤ 4,000 bytes, or validate fails), "no sign-in", and the contact (inherited) |
| `gamecenter` | Enables Game Center for the app and version 1.0. Creates 10 achievements (700 points, only `brim.sandbar` hidden) with en-GB and en-US text and a badge each. Creates 2 leaderboards: `brim.rush.best` (classic) and `brim.daily.score` (recurring daily from 1 Nov 2026 00:00 UTC), both Integer, High to Low, best score, with " point"/" points" suffixes |
| `attach` | Adds every achievement and leaderboard version to the draft iOS review submission. It never adds the build and never submits |
| `screenshots` | 6.9": P1–P5. 6.1" class (1179 × 2556): P1–P5. iPhone Duo inner: D1, D2, D4, D5, D3 (D6 dropped), only if the API offers a Duo placement group (`check` says) |
| `price` | £1.99, base territory United Kingdom; Apple equalises the rest. Available everywhere except China mainland and Vietnam |
| `accessibility` | Nothing for 1.0: labels go on by hand on launch day |
| `nomination` | The App Launch featuring nomination from `featuring-nomination.md`, publish date 17 Nov. It's **submitted** (`"submit": true`), not left as a draft |

Badges: the app draws them (`Brim/UI/AchievementArt.swift`). CI scenario `15-badges` renders them into the `screenshots` artifact. `badges.swift --from <that>/badges` checks the IDs against `GameCenterManager.achievementIDs`, `achievements.md` and the metadata, and writes opaque RGB copies to `tools/appstore/badges/`, the `badges` artifact. Leaderboard images are optional and not pushed.

## Still by hand (no public API)

- **App Privacy**: Get Started → "Data Not Collected" → Publish.
- **Mac and Vision Pro**: Pricing and Availability → untick "iPhone and iPad Apps on Apple Silicon Macs" and "… on Apple Vision Pro".
- **Family Sharing**: on (permanent once on).
- **EU DSA trader status** for Brim: App Information → App Store Regulations and Permits.
- **Accessibility Nutrition Labels**: on launch day.
- **The build**: pick it on the 1.0 page, **Add for Review** (it joins the draft that holds the Game Center items), then **Submit to App Review**.
- **iPhone Duo screenshots**: by hand if the API offers no Duo group.

## Files

- `asc.swift`: the tool (Foundation and CryptoKit only). Commands: `validate`, `check`, `plan`, `push`, `upload-screenshots`. Run `xcrun swift tools/appstore/asc.swift help`.
- `badges.swift`: collects and flattens the app-rendered badges.
- `fixtures/asc-metadata.sample.json`: the validator's CI fixture.
- `docs/appstore/asc-metadata.json`: generated from `metadata.md`, `review-notes.md`, `achievements.md` and `featuring-nomination.md`. Regenerate it when they change.
