// Usage (repo root): node tools/appstore/build-metadata.js
// Regenerates docs/appstore/asc-metadata.json and tools/appstore/fixtures/asc-metadata.sample.json from the docs.
const fs = require('fs'), path = require('path');
const root = process.argv[2] || path.join(__dirname, '..', '..');
const outFile = process.argv[3] || path.join(root, 'docs/appstore/asc-metadata.json');
const fixtureFile = process.argv[4] || path.join(root, 'tools/appstore/fixtures/asc-metadata.sample.json');
const rd = f => fs.readFileSync(path.join(root, 'docs/appstore', f), 'utf8').replace(/\r\n/g, '\n');
function blockAfter(text, marker) {
  const i = text.indexOf(marker); if (i < 0) throw new Error('marker ' + marker);
  const s = text.indexOf('```\n', i) + 4;
  const e = text.indexOf('\n```', s);
  return text.slice(s, e);
}
const md = rd('metadata.md');
const name = blockAfter(md, '## 1. App name');
const subtitle = blockAfter(md, '## 2. Subtitle');
const promo = blockAfter(md, '## 3. Promotional text');
const descGB = blockAfter(md, '### en-GB (English U.K.)');
const descUS = blockAfter(md, '### en-US (English U.S.)');
const keywords = blockAfter(md, '## 5. Keywords');
const rn = rd('review-notes.md');
const notes = blockAfter(rn, '<!-- REVIEW-NOTES:BEGIN -->');
const fn = rd('featuring-nomination.md');
const nomDesc = blockAfter(fn, '### Description');
const nomNotes = blockAfter(fn, '### Helpful Details');
const nomName = (fn.match(/\| Nomination Name \| `([^`]+)`/) || [])[1];
const ach = rd('achievements.md');
const rows = ach.split('\n').filter(l => /^\| \d+ \| `brim\./.test(l)).map(l => l.split('|').slice(1, -1).map(c => c.trim()));
function split2(c) { const p = c.split(' / '); return [p[0], p[1] || p[0]]; }
const achievements = rows.map(r => {
  const id = r[1].replace(/`/g, '');
  const [tGB, tUS] = split2(r[2]), [bGB, bUS] = split2(r[3]), [aGB, aUS] = split2(r[4]);
  const hidden = /yes/i.test(r[6]);
  const loc = (n, b, a) => ({ name: n, beforeEarnedDescription: b, afterEarnedDescription: a });
  return { vendorIdentifier: id, referenceName: tGB, points: parseInt(r[5], 10), showBeforeEarned: !hidden, repeatable: false,
    localizations: { 'en-GB': loc(tGB, bGB, aGB), 'en-US': loc(tUS, bUS, aUS) }, image: `tools/appstore/badges/${id}.png` };
});
const site = 'https://pravegm.github.io/brim/site/';
const loc = (desc) => ({ name, subtitle, privacyPolicyUrl: site + 'privacy.html', description: desc, keywords, promotionalText: promo,
  supportUrl: site + 'support.html', marketingUrl: site });
const lbLoc = (n) => ({ name: n, formatterSuffix: ' points', formatterSuffixSingular: ' point' });
const phones = ['P1-hero-pour', 'P2-perfect-streak', 'P3-soda-foam', 'P4-rush', 'P5-venues'];
const meta = {
  _comment: 'Generated 26 Oct 2026 from docs/appstore/metadata.md, review-notes.md, achievements.md and featuring-nomination.md; asc.swift pushes it (tools/appstore/README.md). No personal data: the copyright and the App Review contact are read at run time from Squish (--inherit-from com.pravegm.squish).',
  bundleId: 'com.pravegm.brim',
  primaryLocale: 'en-GB',
  copyrightHolder: null,
  contentRights: 'DOES_NOT_USE_THIRD_PARTY_CONTENT',
  categories: { primary: 'GAMES', primarySubcategories: ['GAMES_CASUAL', 'GAMES_SIMULATION'], secondary: 'ENTERTAINMENT' },
  localizations: { 'en-GB': loc(descGB), 'en-US': loc(descUS) },
  ageRating: {
    _comment: 'metadata.md section 8 (re-checked 26 Oct 2026): 4+; every item None or No except Contests = Infrequent (the two optional Game Center leaderboards); not Made for Kids. Names from AgeRatingDeclarationUpdateRequest (API docs read 26 Oct 2026).',
    parentalControls: false, ageAssurance: false, unrestrictedWebAccess: false, userGeneratedContent: false, messagingAndChat: false,
    advertising: false, socialMedia: false, socialMediaAgeRestricted: false,
    profanityOrCrudeHumor: 'NONE', horrorOrFearThemes: 'NONE', alcoholTobaccoOrDrugUseOrReferences: 'NONE', matureOrSuggestiveThemes: 'NONE',
    medicalOrTreatmentInformation: 'NONE', healthOrWellnessTopics: false, sexualContentOrNudity: 'NONE', sexualContentGraphicAndNudity: 'NONE',
    violenceCartoonOrFantasy: 'NONE', violenceRealistic: 'NONE', violenceRealisticProlongedGraphicOrSadistic: 'NONE', gunsOrOtherWeapons: 'NONE',
    gamblingSimulated: 'NONE', contests: 'INFREQUENT', gambling: false, lootBox: false, kidsAgeBand: null,
    ageRatingOverrideV2: 'NONE', koreaAgeRatingOverride: 'NONE'
  },
  review: { notes, demoAccountRequired: false, contact: { firstName: null, lastName: null, phone: null, email: null } },
  release: { type: 'SCHEDULED', earliestReleaseDate: '2026-11-17T08:00:00Z' },
  price: { baseTerritory: 'GBR', customerPrice: '1.99' },
  availability: { _comment: 'COMPLIANCE.md #15: no NPPA (China mainland) or Vietnam game licence. #16 (Mac and Vision Pro off) has no public API: the tool prints the clicks.', excludedTerritories: ['CHN', 'VNM'], availableInNewTerritories: true },
  achievements,
  leaderboards: [
    { vendorIdentifier: 'brim.rush.best', referenceName: 'Rush best', defaultFormatter: 'INTEGER', scoreSortType: 'DESC', submissionType: 'BEST_SCORE',
      scoreRangeStart: 0, scoreRangeEnd: 10000000, recurrence: null, localizations: { 'en-GB': lbLoc('Rush'), 'en-US': lbLoc('Rush') } },
    { vendorIdentifier: 'brim.daily.score', referenceName: 'Daily Pour', defaultFormatter: 'INTEGER', scoreSortType: 'DESC', submissionType: 'BEST_SCORE',
      scoreRangeStart: 0, scoreRangeEnd: 1000000,
      recurrence: { startDate: '2026-11-01T00:00:00Z', duration: 'P1D', rule: 'FREQ=DAILY;INTERVAL=1' },
      localizations: { 'en-GB': lbLoc('Daily Pour'), 'en-US': lbLoc('Daily Pour') } }
  ],
  screenshots: {
    _comment: 'Paths inside a downloaded App Store screenshots run (store.yml; final run 40270623298). HANDOVER upload order: phones P1-P5; Duo D1, D2, D4, D5, D3 (D6 dropped).',
    APP_IPHONE_67: phones.map(n => `store-69/store/${n}.png`),
    APP_IPHONE_61: phones.map(n => `store-61/store/${n}.png`),
    duoInner: ['D1-hero-pour', 'D2-perfect-streak', 'D4-soda-foam', 'D5-shake', 'D3-rush'].map(n => `store-duo/duo-screens/store/${n}.png`)
  },
  nomination: {
    _comment: 'docs/appstore/featuring-nomination.md. notes = Helpful Details. submit: true presses Submit (a saved draft is not a nomination). Deadline Tue 27 Oct 2026.',
    name: nomName, type: 'APP_LAUNCH', description: nomDesc, notes: nomNotes, publishStartDate: '2026-11-17T08:00:00Z',
    deviceFamilies: ['IPHONE'], locales: ['en-GB', 'en-US'], supplementalMaterialsUris: [site],
    hasInAppEvents: false, launchInSelectMarketsFirst: false, preOrderEnabled: false, submit: true
  }
};
fs.writeFileSync(outFile, JSON.stringify(meta, null, 2) + '\n');
const c = s => [...s].length, b = s => Buffer.byteLength(s);
console.log({ name: c(name), subtitle: c(subtitle), promo: c(promo), descGB: c(descGB), descUS: c(descUS), kwBytes: b(keywords), notesBytes: b(notes), nomName: c(nomName), nomDesc: c(nomDesc), nomNotes: c(nomNotes), ach: achievements.length, pts: achievements.reduce((a, x) => a + x.points, 0) });
console.log(achievements.map(a => `${a.vendorIdentifier} ${a.points} show=${a.showBeforeEarned} | ${a.localizations['en-US'].name} | ${a.localizations['en-US'].beforeEarnedDescription} | ${a.localizations['en-US'].afterEarnedDescription}`).join('\n'));
const fx = JSON.parse(JSON.stringify(meta));
fx._comment = 'CI fixture for asc.swift validate (a placeholder URL, a partial en-US, missing images). The real data is docs/appstore/asc-metadata.json.';
fx.localizations['en-GB'].supportUrl = 'https://[SITE]/support.html';
fx.localizations['en-US'] = { description: descUS };
fx.achievements = fx.achievements.map(a => ({ ...a, localizations: { 'en-GB': a.localizations['en-GB'] }, image: 'tools/appstore/fixtures/missing.png' }));
delete fx.screenshots;
fs.writeFileSync(fixtureFile, JSON.stringify(fx, null, 2) + '\n');
