// asc.swift: pushes Brim's App Store Connect listing from docs/appstore/asc-metadata.json.
// Ported from Squish's tool (pravegm/squish, tools/appstore/asc.swift, 25 Oct 2026) and extended with Game Center
// leaderboards (classic and recurring), the review-submission attach step, the featuring nomination and
// --inherit-from (personal fields read from another app's record at run time, never written to a file).
//
//   xcrun swift tools/appstore/asc.swift <command> [options]
//
// Commands
//   validate                  offline: checks asc-metadata.json, the badge PNGs and the screenshots (no key needed)
//   check                     auth works, the app is found by bundle ID, lists app infos, versions, Game Center,
//                             the asset library, categories, review submissions, nominations, the price schedule and
//                             (with --inherit-from) whether the inherited fields exist. Changes nothing.
//   plan                      dry run of `push`: prints every change it would make. Changes nothing.
//   push                      idempotent create-or-update of everything below. Safe to re-run.
//   upload-screenshots [dir]  only the screenshots. With <dir>, uses the PNGs found under a `store/` folder in a
//                             downloaded store.yml artifact (classified by pixel size) instead of the JSON's list.
//   upload-placements [dir]   only the product page header and search results art (the `placements` step) from
//                             <dir> (a downloaded store-placements artifact; default ASC_PLACEMENTS_DIR).
//
// Options
//   --only a,b    run only these steps     --skip a,b    skip these steps
//   --metadata <path>                      default docs/appstore/asc-metadata.json
//   --inherit-from <bundle ID>             read the copyright and the App Review contact (name, phone, email) from
//                                          that app's newest version, in memory only (env ASC_INHERIT_FROM). They are
//                                          masked in every line this tool prints.
//   Steps: appinfo categories agerating version localizations review gamecenter attach screenshots placements
//          price accessibility nomination
//
// Configuration (environment; the key never leaves your Mac and is never printed)
//   ASC_KEY_ID       the API key's Key ID
//   ASC_ISSUER_ID    the Issuer ID (Users and Access > Integrations > App Store Connect API); empty for an
//                    individual key
//   ASC_KEY_PATH     path to AuthKey_<KEYID>.p8 (default ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8)
//   ASC_VERSION      the App Store version to edit (default 1.0)
//   ASC_SCREENSHOTS_DIR    base folder for the JSON's screenshot paths (a `gh run download` of a store.yml run);
//                          default the repo root
//   ASC_SCREENSHOT_API     library (default: App Asset Library, API 4.5.1+) | legacy (deprecated screenshot sets)
//   ASC_PLACEMENTS_DIR     folder with header-3840x1646.png and search-3840x2560.png (a `gh run download` of a
//                          store.yml run's store-placements artifact); default <ASC_SCREENSHOTS_DIR>/store-placements.
//                          Without it the placements step changes nothing (a gap, not an error).
//   ASC_DUO_SCREENSHOTS    auto (default: upload the Duo sets only if the API's reference data offers an IPHONE_DUO
//                          screenshot group of that pixel size) | skip
//   ASC_LEGACY_DUO_INNER_DISPLAY_TYPE / ASC_LEGACY_DUO_OUTER_DISPLAY_TYPE
//                          legacy mode only: the screenshotDisplayType to use for the Duo sets. Default empty = skip,
//                          because the ScreenshotDisplayType enum has no Duo case (checked 23 Oct 2026).
//
// Only Foundation and CryptoKit. API references (developer.apple.com/documentation/appstoreconnectapi, read
// 23 Oct 2026 for Squish and 26 Oct 2026 for the Brim additions: GameCenterLeaderboardV2*, ReviewSubmission*,
// Nomination*). Anything not confirmed in those pages is marked UNCONFIRMED below.

import CryptoKit
import Foundation

// MARK: - Output (every line goes through mask(): inherited personal fields never reach a log)

let env = ProcessInfo.processInfo.environment

/// Values read with --inherit-from (copyright, contact name, phone, email). Replaced in all output.
var secretValues: [String] = []

func mask(_ s: String) -> String {
    var r = s
    for v in secretValues { r = r.replacingOccurrences(of: v, with: "‹hidden›") }
    return r
}

/// Registers a value to hide. In GitHub Actions it is also handed to the runner's own masker (the `::add-mask::`
/// command line is consumed by the runner and never shown in the log).
func addSecret(_ raw: String) {
    let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard v.count >= 3, !secretValues.contains(v) else { return }
    secretValues.append(v)
    secretValues.sort { $0.count > $1.count }   // longest first, so "first last" goes before "first"
    if env["GITHUB_ACTIONS"] == "true" { print("::add-mask::\(v)") }
}

/// ASC_OUTPUT_FILE: a copy of every masked output line (for a CI artifact). The `::add-mask::` lines never go there.
let outputLog: FileHandle? = {
    guard let p = env["ASC_OUTPUT_FILE"], !p.isEmpty else { return nil }
    if !FileManager.default.fileExists(atPath: p) { FileManager.default.createFile(atPath: p, contents: nil) }
    let h = FileHandle(forWritingAtPath: p)
    h?.seekToEndOfFile()
    return h
}()

func out(_ s: String = "") {
    let line = mask(s)
    print(line)
    outputLog?.write((line + "\n").data(using: .utf8)!)
}
func warn(_ s: String) { FileHandle.standardError.write("warning: \(mask(s))\n".data(using: .utf8)!) }
func die(_ s: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write("error: \(mask(s))\n".data(using: .utf8)!)
    exit(code)
}

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ s: String) { description = s }
}

typealias JSON = [String: Any]

/// IDs handed out by `plan` for things it would create; their children are never fetched.
let plannedPrefix = "PLANNED-"

// MARK: - Arguments

var argv = Array(CommandLine.arguments.dropFirst())
let command = argv.isEmpty ? "help" : argv.removeFirst()
var onlySteps: Set<String>? = nil
var skipSteps: Set<String> = []
var metadataPathArg: String? = nil
var inheritFromArg: String? = env["ASC_INHERIT_FROM"].flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) }
var positional: [String] = []
while !argv.isEmpty {
    let a = argv.removeFirst()
    switch a {
    case "--only":
        guard !argv.isEmpty else { die("--only needs a list of steps") }
        onlySteps = Set(argv.removeFirst().split(separator: ",").map { String($0) })
    case "--skip":
        guard !argv.isEmpty else { die("--skip needs a list of steps") }
        skipSteps = Set(argv.removeFirst().split(separator: ",").map { String($0) })
    case "--metadata":
        guard !argv.isEmpty else { die("--metadata needs a path") }
        metadataPathArg = argv.removeFirst()
    case "--inherit-from":
        guard !argv.isEmpty else { die("--inherit-from needs a bundle ID, e.g. com.pravegm.squish") }
        let b = argv.removeFirst().trimmingCharacters(in: .whitespaces)
        inheritFromArg = b.isEmpty ? nil : b
    default:
        if a.hasPrefix("-") { die("unknown option \(a)") }
        positional.append(a)
    }
}

/// Read-only after parsing (a top-level `let`, so async code may read it).
let inheritFrom: String? = inheritFromArg

let allSteps = ["appinfo", "categories", "agerating", "version", "localizations", "review", "gamecenter", "attach",
                "screenshots", "placements", "price", "accessibility", "nomination"]
for s in (onlySteps ?? []).union(skipSteps) where !allSteps.contains(s) {
    die("unknown step '\(s)'. Steps: \(allSteps.joined(separator: " "))")
}

let usage = """
usage: xcrun swift tools/appstore/asc.swift <command> [--only a,b] [--skip a,b] [--metadata path]
                                           [--inherit-from bundle.id]

  validate                  offline checks of asc-metadata.json, badges and screenshots
  check                     read-only: auth, app lookup, editable version, Game Center, categories, asset library,
                            review submissions, nominations, price, inherited fields
  plan                      dry run: every change push would make
  push                      create or update everything (idempotent)
  upload-screenshots [dir]  screenshots only; <dir> = a downloaded store.yml artifact
  upload-placements [dir]   header and search results art only; <dir> = a downloaded store-placements artifact

steps: \(allSteps.joined(separator: " "))
env:   ASC_KEY_ID  ASC_ISSUER_ID  ASC_KEY_PATH  [ASC_VERSION=1.0]  [ASC_SCREENSHOT_API=library|legacy]
       [ASC_DUO_SCREENSHOTS=auto|skip]  [ASC_INHERIT_FROM=bundle.id]  [ASC_SCREENSHOTS_DIR=dir]
       [ASC_PLACEMENTS_DIR=dir]
"""

// MARK: - Paths

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let repoRoot: URL = {
    if let r = env["ASC_REPO_ROOT"], !r.isEmpty { return URL(fileURLWithPath: r) }
    let guess = scriptURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    if FileManager.default.fileExists(atPath: guess.appendingPathComponent("docs").path) { return guess }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}()

func repoPath(_ p: String) -> URL {
    p.hasPrefix("/") ? URL(fileURLWithPath: p) : repoRoot.appendingPathComponent(p)
}

let metadataURL = repoPath(metadataPathArg ?? "docs/appstore/asc-metadata.json")

// MARK: - Small helpers

func isBool(_ v: Any?) -> Bool {
    guard let n = v as? NSNumber else { return false }
    return CFGetTypeID(n) == CFBooleanGetTypeID()
}

func isInt(_ v: Any?) -> Bool {
    guard let n = v as? NSNumber, !isBool(n) else { return false }
    return n.doubleValue == n.doubleValue.rounded()
}

func isNull(_ v: Any?) -> Bool { v == nil || v is NSNull }

func short(_ v: Any?) -> String {
    if isNull(v) { return "∅" }
    if isBool(v) { return (v as! NSNumber).boolValue ? "true" : "false" }
    if let s = v as? String {
        let one = s.replacingOccurrences(of: "\n", with: "⏎")
        return one.count > 70 ? "\"\(one.prefix(64))…\" (\(s.count) chars)" : "\"\(one)\""
    }
    return "\(v!)"
}

func sha256Hex(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
func md5Hex(_ d: Data) -> String { Insecure.MD5.hash(data: d).map { String(format: "%02x", $0) }.joined() }

let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func parseDate(_ s: String?) -> Date? {
    guard let s = s else { return nil }
    return isoFormatter.date(from: s) ?? isoFractional.date(from: s)
}

/// Equality for "is this already what we want?". Nil, NSNull and "" are the same; dates compare as instants.
func isSameValue(_ current: Any?, _ desired: Any?) -> Bool {
    let cNull = isNull(current) || (current as? String) == ""
    let dNull = isNull(desired) || (desired as? String) == ""
    if cNull || dNull { return cNull && dNull }
    if isBool(current) || isBool(desired) {
        return (current as? NSNumber)?.boolValue == (desired as? NSNumber)?.boolValue
    }
    if let c = current as? String, let d = desired as? String {
        if let cd = parseDate(c), let dd = parseDate(d) { return abs(cd.timeIntervalSince(dd)) < 1 }
        return c == d
    }
    if let c = current as? NSNumber, let d = desired as? NSNumber { return c == d }
    if let c = current as? [Any], let d = desired as? [Any] {
        // Lists (nomination locales, device families, URLs) compare as sets of their string forms.
        return Set(c.map { "\($0)" }) == Set(d.map { "\($0)" })
    }
    if let c = current as? NSNumber, let d = desired as? String { return Double(d) == c.doubleValue }
    if let c = current as? String, let d = desired as? NSNumber { return Double(c) == d.doubleValue }
    return "\(current!)" == "\(desired!)"
}

/// Dates where App Store Connect may keep only the day (nomination publish dates): equal if the same UTC day.
func isSameDay(_ a: Any?, _ b: Any?) -> Bool {
    guard let x = parseDate(a as? String), let y = parseDate(b as? String) else { return isSameValue(a, b) }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.isDate(x, inSameDayAs: y)
}

// MARK: - Image headers (PNG and JPEG, no ImageIO: Foundation only)

struct ImageInfo { let width: Int; let height: Int; let hasAlpha: Bool; let format: String }

func imageInfo(_ data: Data) -> ImageInfo? {
    let b = [UInt8](data)
    func be32(_ i: Int) -> Int { Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3]) }
    if b.count > 33, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 {
        var w = 0, h = 0, colourType: UInt8 = 0, alpha = false
        var i = 8
        while i + 8 <= b.count {
            let len = be32(i)
            let type = String(bytes: b[(i + 4)..<(i + 8)], encoding: .ascii) ?? ""
            if type == "IHDR", i + 21 <= b.count {
                w = be32(i + 8); h = be32(i + 12); colourType = b[i + 17]
            } else if type == "tRNS" {
                alpha = true
            } else if type == "IDAT" || type == "IEND" {
                break
            }
            i += 12 + len
        }
        if colourType == 4 || colourType == 6 { alpha = true }
        return ImageInfo(width: w, height: h, hasAlpha: alpha, format: "png")
    }
    if b.count > 4, b[0] == 0xFF, b[1] == 0xD8 {
        var i = 2
        while i + 9 < b.count {
            guard b[i] == 0xFF else { i += 1; continue }
            let marker = b[i + 1]
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            if (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC {
                let h = Int(b[i + 5]) << 8 | Int(b[i + 6])
                let w = Int(b[i + 7]) << 8 | Int(b[i + 8])
                return ImageInfo(width: w, height: h, hasAlpha: false, format: "jpeg")
            }
            i += 2 + len
        }
    }
    return nil
}

struct ImageFile {
    let path: String      // as written in the JSON (repo-relative)
    let url: URL
    let data: Data
    let info: ImageInfo
    var size: Int { data.count }
    var sha12: String { String(sha256Hex(data).prefix(12)) }
    var ext: String { info.format == "png" ? "png" : "jpg" }
}

/// Screenshot paths in the JSON are relative to ASC_SCREENSHOTS_DIR (where you ran `gh run download` for a store.yml
/// run, so `store-69/store/P1-….png` resolves), or to the repo root when it isn't set.
let screenshotsBase: URL? = env["ASC_SCREENSHOTS_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }

func loadImage(_ path: String, base: URL? = nil) -> Result<ImageFile, ToolError> {
    let url = path.hasPrefix("/") || base == nil ? repoPath(path) : base!.appendingPathComponent(path)
    guard let data = try? Data(contentsOf: url) else { return .failure(ToolError("\(path): file not found")) }
    guard let info = imageInfo(data) else { return .failure(ToolError("\(path): not a PNG or JPEG")) }
    return .success(ImageFile(path: path, url: url, data: data, info: info))
}

// MARK: - Metadata model

struct LocaleText {
    var fields: [String: String] = [:]     // only set (non-empty, non-placeholder) fields
    var inherited: Set<String> = []        // fields copied from the primary locale
}

struct AchievementLoc { let name: String; let before: String; let after: String; let inherited: Bool }

struct AchievementSpec {
    let vendorIdentifier: String
    let referenceName: String
    let points: Int
    let showBeforeEarned: Bool
    let repeatable: Bool
    var localizations: [(String, AchievementLoc)]
    let image: ImageFile?
}

struct ScreenshotSet { let key: String; let files: [ImageFile] }

/// A Game Center leaderboard (v2). `recurrence` nil = classic (all-time).
struct LeaderboardSpec {
    let vendorIdentifier: String
    var attributes: JSON          // GameCenterLeaderboardV2 attributes except vendorIdentifier
    var localizations: [(String, JSON)]
    var inheritedLocales: Set<String>
    var recurring: Bool { attributes["recurrenceRule"] != nil }
}

struct NominationSpec {
    var attributes: JSON          // NominationCreateRequest attributes except `submitted`
    let submit: Bool
}

struct Metadata {
    var bundleId = ""
    var primaryLocale = ""
    var copyrightHolder: String? = nil
    /// The whole copyright line read with --inherit-from (used as is); never from a file.
    var inheritedCopyright: String? = nil
    var inheritedContact = false
    var contentRights: String? = nil
    var leaderboards: [LeaderboardSpec] = []
    var nomination: NominationSpec? = nil
    var primaryCategory: String? = nil
    var primarySubcategories: [String] = []
    var secondaryCategory: String? = nil
    var categoriesGiven = false
    var locales: [String] = []                  // primary first
    var text: [String: LocaleText] = [:]
    var ageRating: JSON = [:]
    var reviewNotes: String? = nil
    var demoAccountRequired: Bool? = nil
    var contact: [String: String] = [:]          // ASC attribute name → value, only the ones given
    var releaseType: String? = nil
    var earliestReleaseDate: String? = nil
    var priceTerritory: String? = nil
    var customerPrice: String? = nil
    var achievements: [AchievementSpec] = []
    var screenshots: [ScreenshotSet] = []
    var accessibility: JSON? = nil
    var excludedTerritories: Set<String> = ["CHN"]
    var availableInNewTerritories = true
}

/// Errors are tagged with the step they belong to ("core" blocks everything). Blockers are gaps (founder-only data, or data held back):
/// the step still runs, without those fields.
final class Validation {
    var errors: [(step: String, msg: String)] = []
    var warnings: [String] = []
    var blockers: [(step: String, msg: String)] = []
    func error(_ step: String, _ m: String) { errors.append((step, m)) }
    func block(_ step: String, _ m: String) { blockers.append((step, m)) }
    func blockingErrors(for steps: Set<String>) -> [String] {
        errors.filter { $0.step == "core" || steps.contains($0.step) }.map { $0.msg }
    }
}

let screenshotKeys = ["APP_IPHONE_67", "APP_IPHONE_61", "duoInner", "duoOuter"]

/// Accepted pixel sizes per set (App Store Connect Help > Screenshot specifications, 23 Oct 2026), portrait and
/// landscape. APP_IPHONE_67 is the "Dynamic Island (large)" 6.9"/6.7" class; APP_IPHONE_61 is "Dynamic Island
/// (medium)", which includes 1206 x 2622 and is currently the required iPhone class.
let screenshotSizes: [String: [(Int, Int)]] = [
    "APP_IPHONE_67": [(1320, 2868), (1290, 2796), (1260, 2736)],
    "APP_IPHONE_61": [(1206, 2622), (1179, 2556)],
    "duoInner": [(2007, 2853)],
    "duoOuter": [(1398, 2034)],
]

func sizeMatches(_ key: String, _ i: ImageInfo) -> Bool {
    (screenshotSizes[key] ?? []).contains { ($0.0 == i.width && $0.1 == i.height) || ($0.1 == i.width && $0.0 == i.height) }
}

// Age rating: ASC attribute names (AgeRatingDeclarationUpdateRequest.Data.Attributes, API 4.5.1).
let ageLevelAttrs: Set<String> = [
    "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
    "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity", "sexualContentOrNudity",
    "horrorOrFearThemes", "matureOrSuggestiveThemes", "violenceCartoonOrFantasy",
    "violenceRealisticProlongedGraphicOrSadistic", "violenceRealistic",
]
let ageLevelValues: Set<String> = ["NONE", "INFREQUENT_OR_MILD", "FREQUENT_OR_INTENSE", "INFREQUENT", "FREQUENT"]
let ageBoolAttrs: Set<String> = [
    "advertising", "gambling", "healthOrWellnessTopics", "lootBox", "messagingAndChat", "parentalControls",
    "ageAssurance", "socialMedia", "socialMediaAgeRestricted", "unrestrictedWebAccess", "userGeneratedContent",
]
let ageEnumAttrs: [String: Set<String>] = [
    "kidsAgeBand": ["FIVE_AND_UNDER", "SIX_TO_EIGHT", "NINE_TO_ELEVEN"],   // UNCONFIRMED values (KidsAgeBand page not read)
    "ageRatingOverrideV2": ["NONE", "NINE_PLUS", "THIRTEEN_PLUS", "SIXTEEN_PLUS", "EIGHTEEN_PLUS", "UNRATED"],
    "koreaAgeRatingOverride": ["NONE", "ALL", "TWELVE_PLUS", "FIFTEEN_PLUS", "NINETEEN_PLUS"],
]
let ageStringAttrs: Set<String> = ["developerAgeRatingInfoUrl", "gracRatingClassificationNumber"]
/// Questionnaire wording → ASC names, for keys written the way the App Store Connect form words them.
let ageAliases: [String: String] = [
    "cartoonorfantasyviolence": "violenceCartoonOrFantasy",
    "realisticviolence": "violenceRealistic",
    "prolongedgraphicorsadisticrealisticviolence": "violenceRealisticProlongedGraphicOrSadistic",
    "profanityorcrudehumour": "profanityOrCrudeHumor",
    "horrorfearthemes": "horrorOrFearThemes",
    "matureorsuggestive": "matureOrSuggestiveThemes",
    "simulatedgambling": "gamblingSimulated",
    "lootboxes": "lootBox",
    "messagingchat": "messagingAndChat",
    "usergeneratedcontentugc": "userGeneratedContent",
    "webaccess": "unrestrictedWebAccess",
    "medicalortreatmentinfo": "medicalOrTreatmentInformation",
    "alcoholtobaccoordruguse": "alcoholTobaccoOrDrugUseOrReferences",
    "sexualcontentnudity": "sexualContentOrNudity",
    "graphicsexualcontentandnudity": "sexualContentGraphicAndNudity",
    "gunsorweapons": "gunsOrOtherWeapons",
]

func normKey(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

let ageLookup: [String: String] = {
    var m: [String: String] = [:]
    for a in ageLevelAttrs.union(ageBoolAttrs).union(Set(ageEnumAttrs.keys)).union(ageStringAttrs) { m[normKey(a)] = a }
    for (k, v) in ageAliases { m[k] = v }
    return m
}()

// The tool's offline list; `check` and the categories step use Apple's live list (GET /v1/appCategories/GAMES/
// subcategories). GAMES_ARCADE is here because metadata.md §7 picks Arcade; the live list decides.
let gamesSubcategories: Set<String> = [
    "GAMES_ACTION", "GAMES_ADVENTURE", "GAMES_ARCADE", "GAMES_BOARD", "GAMES_CARD", "GAMES_CASINO", "GAMES_CASUAL", "GAMES_DICE",
    "GAMES_EDUCATIONAL", "GAMES_FAMILY", "GAMES_MUSIC", "GAMES_PUZZLE", "GAMES_RACING", "GAMES_ROLE_PLAYING",
    "GAMES_SIMULATION", "GAMES_SPORTS", "GAMES_STRATEGY", "GAMES_TRIVIA", "GAMES_WORD",
]
let knownCategories: Set<String> = [
    "BOOKS", "BUSINESS", "DEVELOPER_TOOLS", "EDUCATION", "ENTERTAINMENT", "FINANCE", "FOOD_AND_DRINK", "GAMES",
    "GRAPHICS_AND_DESIGN", "HEALTH_AND_FITNESS", "LIFESTYLE", "MAGAZINES_AND_NEWSPAPERS", "MEDICAL", "MUSIC",
    "NAVIGATION", "NEWS", "PHOTO_AND_VIDEO", "PRODUCTIVITY", "REFERENCE", "SHOPPING", "SOCIAL_NETWORKING", "SPORTS",
    "STICKERS", "TRAVEL", "UTILITIES", "WEATHER",
]

let localeFieldLimits: [(key: String, step: String, limit: Int, bytes: Bool)] = [
    ("name", "appinfo", 30, false),
    ("subtitle", "appinfo", 30, false),
    ("privacyPolicyUrl", "appinfo", 255, false),
    ("description", "localizations", 4000, false),
    ("keywords", "localizations", 100, true),
    ("promotionalText", "localizations", 170, false),
    ("supportUrl", "localizations", 255, false),
    ("marketingUrl", "localizations", 255, false),
]
let urlFields: Set<String> = ["privacyPolicyUrl", "supportUrl", "marketingUrl"]
let requiredLocaleFields = ["name", "description", "keywords", "supportUrl", "privacyPolicyUrl"]

func isPlaceholder(_ s: String) -> Bool {
    let l = s.lowercased()
    return s.contains("[") && s.contains("]") || l.contains("todo") || l.contains("tbd") || l.contains("placeholder")
        || l.contains("example.com") || l.contains("{domain}") || l.contains("<domain>")
}

let gameCenterSource = "Brim/App/GameCenterManager.swift"

func quotedStrings(_ s: String) -> [String] {
    var found: [String] = []
    var rest = Substring(s)
    while let open = rest.firstIndex(of: "\"") {
        let after = rest.index(after: open)
        guard let close = rest[after...].firstIndex(of: "\"") else { break }
        found.append(String(rest[after..<close]))
        rest = rest[rest.index(after: close)...]
    }
    return found
}

/// The app's own achievement IDs: `GameCenterManager.achievementIDs` in Brim/App/GameCenterManager.swift.
func contractAchievementIDs() -> [String]? {
    guard let text = try? String(contentsOf: repoRoot.appendingPathComponent(gameCenterSource), encoding: .utf8),
          let start = text.range(of: "static let achievementIDs") else { return nil }
    // `static let achievementIDs: [String] = [ ... ]`: the list starts after "= [".
    guard let open = text[start.upperBound...].range(of: "= [") else { return nil }
    let tail = text[open.upperBound...]
    guard let close = tail.firstIndex(of: "]") else { return nil }
    let ids = quotedStrings(String(tail[..<close]))
    return ids.isEmpty ? nil : ids
}

/// The app's leaderboard IDs: the `static let` strings inside `enum Leaderboard` in GameCenterManager.swift.
func contractLeaderboardIDs() -> [String]? {
    guard let text = try? String(contentsOf: repoRoot.appendingPathComponent(gameCenterSource), encoding: .utf8) else { return nil }
    var inEnum = false
    var ids: [String] = []
    for line in text.components(separatedBy: .newlines) {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("enum Leaderboard") { inEnum = true; continue }
        if inEnum {
            if t.hasPrefix("}") { break }
            if t.hasPrefix("static let") { ids += quotedStrings(t) }
        }
    }
    return ids.isEmpty ? nil : ids
}

func loadMetadata(_ v: Validation) -> Metadata? {
    guard let data = try? Data(contentsOf: metadataURL) else {
        v.error("core", "\(metadataURL.path) not found (the listing writer owns it; see tools/appstore/README.md)")
        return nil
    }
    let rootAny: Any
    do { rootAny = try JSONSerialization.jsonObject(with: data) } catch {
        v.error("core", "asc-metadata.json is not valid JSON: \(error.localizedDescription)")
        return nil
    }
    guard let root = rootAny as? JSON else { v.error("core", "asc-metadata.json: top level must be an object"); return nil }
    var m = Metadata()

    func unknownKeys(_ obj: JSON, _ allowed: [String], _ path: String, _ step: String) {
        for k in obj.keys where !allowed.contains(k) && !k.hasPrefix("_") && !k.hasPrefix("$") {
            v.error(step, "\(path).\(k): unknown key (allowed: \(allowed.joined(separator: ", ")); prefix a key with _ for a comment)")
        }
    }
    func str(_ obj: JSON, _ k: String, _ path: String, _ step: String, nullable: Bool = false) -> String? {
        let val = obj[k]
        if val == nil { if !nullable { v.error(step, "\(path).\(k): missing") }; return nil }
        if val is NSNull { if !nullable { v.error(step, "\(path).\(k): must be a string, not null") }; return nil }
        guard let s = val as? String else { v.error(step, "\(path).\(k): must be a string"); return nil }
        return s
    }
    func bool(_ obj: JSON, _ k: String, _ path: String, _ step: String) -> Bool? {
        guard let val = obj[k] else { v.error(step, "\(path).\(k): missing"); return nil }
        guard isBool(val) else { v.error(step, "\(path).\(k): must be true or false"); return nil }
        return (val as! NSNumber).boolValue
    }

    unknownKeys(root, ["bundleId", "primaryLocale", "copyrightHolder", "contentRights", "categories", "localizations", "ageRating",
                       "review", "release", "price", "availability", "achievements", "leaderboards", "screenshots", "accessibility",
                       "nomination"], "$", "core")

    // bundleId, primaryLocale
    m.bundleId = str(root, "bundleId", "$", "core") ?? ""
    if !m.bundleId.isEmpty, m.bundleId.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) == nil {
        v.error("core", "$.bundleId: '\(m.bundleId)' is not a bundle ID")
    }
    if !m.bundleId.isEmpty && m.bundleId != "com.pravegm.brim" { v.warnings.append("bundleId is \(m.bundleId), not com.pravegm.brim") }
    if let from = inheritFrom, from == m.bundleId { v.error("core", "--inherit-from \(from) is this app itself") }
    m.primaryLocale = str(root, "primaryLocale", "$", "core") ?? ""

    // copyrightHolder (null + --inherit-from: the whole copyright line comes from the other app at run time)
    if let c = root["copyrightHolder"], !(c is NSNull) {
        if let s = c as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty, !isPlaceholder(s) {
            m.copyrightHolder = s.trimmingCharacters(in: .whitespaces)
            v.warnings.append("copyrightHolder is set in a file; the repo is public. Prefer null with --inherit-from.")
        } else if c is String {
            v.block("version", "copyrightHolder is empty or a placeholder (founder-only: the studio's legal name). Copyright is not pushed.")
        } else {
            v.error("version", "$.copyrightHolder: must be a string or null")
        }
    } else if inheritFrom == nil {
        v.block("version", "copyrightHolder is null and no --inherit-from: copyright is not pushed.")
    }

    // contentRights (App Information > Content Rights; the apps resource's contentRightsDeclaration)
    if let cr = root["contentRights"], !(cr is NSNull) {
        if let s = cr as? String, ["DOES_NOT_USE_THIRD_PARTY_CONTENT", "USES_THIRD_PARTY_CONTENT"].contains(s) { m.contentRights = s }
        else { v.error("appinfo", "$.contentRights: DOES_NOT_USE_THIRD_PARTY_CONTENT or USES_THIRD_PARTY_CONTENT") }
    }

    // categories
    if let cats = root["categories"] as? JSON {
        m.categoriesGiven = true
        unknownKeys(cats, ["primary", "primarySubcategories", "secondary"], "$.categories", "categories")
        m.primaryCategory = str(cats, "primary", "$.categories", "categories")
        if let p = m.primaryCategory, !knownCategories.contains(p) {
            v.warnings.append("categories.primary '\(p)' isn't a category ID this tool knows; App Store Connect decides")
        }
        if let subs = cats["primarySubcategories"] {
            if let arr = subs as? [String] {
                if arr.count > 2 { v.error("categories", "$.categories.primarySubcategories: at most 2") }
                for s in arr where !gamesSubcategories.contains(s) {
                    v.error("categories", "$.categories.primarySubcategories: '\(s)' is not a Games subcategory (\(gamesSubcategories.sorted().joined(separator: ", ")))")
                }
                if !arr.isEmpty && m.primaryCategory != "GAMES" { v.error("categories", "$.categories.primarySubcategories: only the GAMES category has subcategories") }
                if Set(arr).count != arr.count { v.error("categories", "$.categories.primarySubcategories: duplicate") }
                m.primarySubcategories = arr
            } else if !(subs is NSNull) {
                v.error("categories", "$.categories.primarySubcategories: must be an array of strings")
            }
        }
        if let s = cats["secondary"], !(s is NSNull) {
            if let sec = s as? String {
                if sec == m.primaryCategory { v.error("categories", "$.categories.secondary: same as primary") }
                if !knownCategories.contains(sec) { v.warnings.append("categories.secondary '\(sec)' isn't a category ID this tool knows") }
                m.secondaryCategory = sec
            } else { v.error("categories", "$.categories.secondary: must be a string or null") }
        }
    } else if root["categories"] != nil {
        v.error("categories", "$.categories: must be an object")
    }

    // localizations
    if let locs = root["localizations"] as? JSON, !locs.isEmpty {
        let fieldKeys = localeFieldLimits.map { $0.key }
        guard let primary = locs[m.primaryLocale] as? JSON else {
            v.error("core", "$.localizations has no entry for primaryLocale '\(m.primaryLocale)'")
            return m
        }
        let order = [m.primaryLocale] + locs.keys.filter { $0 != m.primaryLocale && !$0.hasPrefix("_") }.sorted()
        for locale in order {
            if locale.range(of: "^[a-z]{2,3}(-[A-Za-z]{2,4})?$", options: .regularExpression) == nil {
                v.error("core", "$.localizations: '\(locale)' is not a locale code like en-GB")
                continue
            }
            guard let obj = locs[locale] as? JSON else { v.error("core", "$.localizations.\(locale): must be an object"); continue }
            unknownKeys(obj, fieldKeys, "$.localizations.\(locale)", "core")
            var lt = LocaleText()
            var placeholders: Set<String> = []
            for f in localeFieldLimits {
                let path = "$.localizations.\(locale).\(f.key)"
                var value: String? = nil
                if let raw = obj[f.key], !(raw is NSNull) {
                    guard let s = raw as? String else { v.error(f.step, "\(path): must be a string"); continue }
                    value = s
                }
                if (value ?? "").isEmpty, locale != m.primaryLocale, let pv = primary[f.key] as? String, !pv.isEmpty {
                    value = pv
                    lt.inherited.insert(f.key)
                }
                guard let s = value, !s.isEmpty else { continue }
                if isPlaceholder(s) {
                    v.block(f.step, "\(path) is still a placeholder (\(short(s))); not pushed")
                    placeholders.insert(f.key)
                    continue
                }
                let count = f.bytes ? s.utf8.count : s.count
                if count > f.limit { v.error(f.step, "\(path): \(count) \(f.bytes ? "bytes" : "characters"), limit \(f.limit)") }
                if f.key == "name" && count < 2 { v.error(f.step, "\(path): at least 2 characters") }
                if urlFields.contains(f.key) {
                    if let u = URL(string: s), let scheme = u.scheme?.lowercased(), scheme == "https" || scheme == "http", u.host != nil {
                        if scheme == "http" { v.warnings.append("\(path) is http, not https") }
                    } else {
                        v.error(f.step, "\(path): '\(s)' is not an http(s) URL")
                    }
                }
                if f.key == "keywords" {
                    if s.contains(", ") { v.warnings.append("\(path): spaces after commas waste keyword bytes") }
                }
                lt.fields[f.key] = s
            }
            if locale == m.primaryLocale {
                for k in requiredLocaleFields where lt.fields[k] == nil && !placeholders.contains(k) {
                    v.block(k == "name" || k == "privacyPolicyUrl" ? "appinfo" : "localizations",
                            "$.localizations.\(locale).\(k) is empty: App Store Connect needs it before submission")
                }
            }
            m.locales.append(locale)
            m.text[locale] = lt
        }
    } else {
        v.error("core", "$.localizations: must be a non-empty object keyed by locale")
    }

    // ageRating
    if let ar = root["ageRating"] as? JSON {
        for (rawKey, rawValue) in ar where !rawKey.hasPrefix("_") {
            guard let key = ageLookup[normKey(rawKey)] else {
                if normKey(rawKey) == "seventeenplus" {
                    v.error("agerating", "$.ageRating.\(rawKey): deprecated in ASC; use ageRatingOverrideV2")
                } else if normKey(rawKey) == "madeforkids" {
                    if isBool(rawValue) && !(rawValue as! NSNumber).boolValue {
                        m.ageRating["kidsAgeBand"] = NSNull()
                    } else {
                        v.error("agerating", "$.ageRating.\(rawKey): Made for Kids = yes needs kidsAgeBand instead")
                    }
                } else {
                    v.error("agerating", "$.ageRating.\(rawKey): not an ageRatingDeclaration attribute")
                }
                continue
            }
            if key != rawKey { v.warnings.append("ageRating.\(rawKey) is pushed as \(key)") }
            if ageLevelAttrs.contains(key) {
                guard let s = rawValue as? String else { v.error("agerating", "$.ageRating.\(rawKey): must be one of \(ageLevelValues.sorted().joined(separator: ", "))"); continue }
                let n = s.uppercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "_OR_")
                guard ageLevelValues.contains(n) else { v.error("agerating", "$.ageRating.\(rawKey): '\(s)' is not one of \(ageLevelValues.sorted().joined(separator: ", "))"); continue }
                m.ageRating[key] = n
            } else if ageBoolAttrs.contains(key) {
                if isBool(rawValue) { m.ageRating[key] = rawValue }
                else if let s = rawValue as? String, ["yes", "no", "true", "false"].contains(s.lowercased()) {
                    m.ageRating[key] = NSNumber(value: s.lowercased() == "yes" || s.lowercased() == "true")
                    v.warnings.append("ageRating.\(rawKey): '\(s)' read as a boolean; write true/false")
                } else { v.error("agerating", "$.ageRating.\(rawKey): must be true or false") }
            } else if let allowed = ageEnumAttrs[key] {
                if rawValue is NSNull { m.ageRating[key] = NSNull() }
                else if let s = rawValue as? String, allowed.contains(s) { m.ageRating[key] = s }
                else { v.error("agerating", "$.ageRating.\(rawKey): must be null or one of \(allowed.sorted().joined(separator: ", "))") }
            } else if ageStringAttrs.contains(key) {
                if rawValue is NSNull || rawValue is String { m.ageRating[key] = rawValue } else { v.error("agerating", "$.ageRating.\(rawKey): must be a string") }
            }
        }
        let answered = Set(m.ageRating.keys)
        let unanswered = ageLevelAttrs.union(ageBoolAttrs).subtracting(answered).sorted()
        if !unanswered.isEmpty {
            v.warnings.append("ageRating leaves \(unanswered.count) questionnaire items unanswered (App Store Connect needs every one): \(unanswered.joined(separator: ", "))")
        }
    } else if root["ageRating"] != nil {
        v.error("agerating", "$.ageRating: must be an object")
    }

    // review
    if let r = root["review"] as? JSON {
        unknownKeys(r, ["notes", "demoAccountRequired", "contact"], "$.review", "review")
        if let n = str(r, "notes", "$.review", "review", nullable: true), !n.isEmpty {
            // App Store Connect limits App Review notes to 4,000 bytes. Over the limit, the notes are held back (a
            // The limit is in bytes, not characters; over it, validate fails.
            if n.utf8.count > 4000 { v.error("review", "$.review.notes: \(n.utf8.count) bytes, App Store Connect takes 4,000") }
            m.reviewNotes = n
            if isPlaceholder(n) { v.warnings.append("review.notes contains a placeholder-looking [..]/TODO; check it") }
        }
        m.demoAccountRequired = bool(r, "demoAccountRequired", "$.review", "review")
        if m.demoAccountRequired == true {
            v.error("review", "$.review.demoAccountRequired: Brim has no accounts; a demo account can't be supplied by this tool")
        }
        if let c = r["contact"] as? JSON {
            unknownKeys(c, ["firstName", "lastName", "phone", "email"], "$.review.contact", "review")
            let map = ["firstName": "contactFirstName", "lastName": "contactLastName", "phone": "contactPhone", "email": "contactEmail"]
            for k in ["firstName", "lastName", "phone", "email"] {
                guard let s = str(c, k, "$.review.contact", "review", nullable: true), !s.isEmpty, !isPlaceholder(s) else {
                    if inheritFrom == nil {
                        v.block("review", "review.contact.\(k) is not set and no --inherit-from. Review contact \(k) is not pushed; App Review needs it.")
                    }
                    continue
                }
                v.warnings.append("review.contact.\(k) is set in a file; the repo is public. Prefer null with --inherit-from.")
                if k == "email", s.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) == nil {
                    v.error("review", "$.review.contact.email: '\(s)' is not an email address")
                }
                if k == "phone", s.range(of: "^\\+?[0-9 ()\\-]{7,}$", options: .regularExpression) == nil {
                    v.error("review", "$.review.contact.phone: use international format, e.g. +44 20 7946 0000")
                }
                m.contact[map[k]!] = s
            }
        } else {
            v.error("review", "$.review.contact: missing (an object with firstName, lastName, phone, email; null allowed)")
        }
    } else if root["review"] != nil {
        v.error("review", "$.review: must be an object")
    }

    // release
    if let r = root["release"] as? JSON {
        unknownKeys(r, ["type", "earliestReleaseDate"], "$.release", "version")
        if let t = str(r, "type", "$.release", "version") {
            if ["MANUAL", "AFTER_APPROVAL", "SCHEDULED"].contains(t) { m.releaseType = t }
            else { v.error("version", "$.release.type: must be MANUAL, AFTER_APPROVAL or SCHEDULED") }
        }
        if let d = str(r, "earliestReleaseDate", "$.release", "version", nullable: true), !d.isEmpty {
            if let date = parseDate(d) {
                m.earliestReleaseDate = isoFormatter.string(from: date)
                if date < Date() { v.warnings.append("release.earliestReleaseDate \(d) is in the past") }
                let comps = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
                if comps.minute != 0 || comps.second != 0 { v.warnings.append("release.earliestReleaseDate: App Store Connect schedules on the hour") }
            } else { v.error("version", "$.release.earliestReleaseDate: '\(d)' is not ISO 8601, e.g. 2026-11-24T08:00:00Z") }
        }
        if m.releaseType == "SCHEDULED" && m.earliestReleaseDate == nil { v.error("version", "$.release: SCHEDULED needs earliestReleaseDate") }
        if m.releaseType != "SCHEDULED" && m.earliestReleaseDate != nil { v.warnings.append("release.earliestReleaseDate is ignored unless type is SCHEDULED") }
    } else if root["release"] != nil {
        v.error("version", "$.release: must be an object")
    }

    // price
    if let p = root["price"] as? JSON {
        unknownKeys(p, ["baseTerritory", "customerPrice"], "$.price", "price")
        if let t = str(p, "baseTerritory", "$.price", "price") {
            if t.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil { m.priceTerritory = t }
            else { v.error("price", "$.price.baseTerritory: a 3-letter territory code such as GBR") }
        }
        if let cp = str(p, "customerPrice", "$.price", "price") {
            if cp.range(of: "^[0-9]+(\\.[0-9]{1,2})?$", options: .regularExpression) != nil { m.customerPrice = cp }
            else { v.error("price", "$.price.customerPrice: a decimal string such as \"2.99\"") }
        }
    } else if root["price"] != nil {
        v.error("price", "$.price: must be an object")
    }

    // availability (pushed by the price step): every territory except these
    if let a = root["availability"] as? JSON {
        unknownKeys(a, ["excludedTerritories", "availableInNewTerritories"], "$.availability", "price")
        if let ex = a["excludedTerritories"] {
            if let arr = ex as? [String], arr.allSatisfy({ $0.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil }) { m.excludedTerritories = Set(arr) }
            else { v.error("price", "$.availability.excludedTerritories: 3-letter territory codes such as CHN") }
        }
        if let n = a["availableInNewTerritories"], !(n is NSNull) {
            if isBool(n) { m.availableInNewTerritories = (n as! NSNumber).boolValue } else { v.error("price", "$.availability.availableInNewTerritories: true or false") }
        }
    } else if let a = root["availability"], !(a is NSNull) {
        v.error("price", "$.availability: must be an object")
    }

    // achievements
    if let list = root["achievements"] as? [Any] {
        var seen = Set<String>()
        var total = 0
        if list.count > 100 { v.error("gamecenter", "$.achievements: at most 100") }
        for (i, item) in list.enumerated() {
            let path = "$.achievements[\(i)]"
            guard let a = item as? JSON else { v.error("gamecenter", "\(path): must be an object"); continue }
            unknownKeys(a, ["vendorIdentifier", "referenceName", "points", "showBeforeEarned", "repeatable", "localizations", "image"], path, "gamecenter")
            let vid = str(a, "vendorIdentifier", path, "gamecenter") ?? ""
            if vid.range(of: "^[A-Za-z0-9._]{1,100}$", options: .regularExpression) == nil {
                v.error("gamecenter", "\(path).vendorIdentifier: '\(vid)' must be 1-100 characters of A-Z a-z 0-9 . _")
            }
            if !seen.insert(vid).inserted { v.error("gamecenter", "\(path).vendorIdentifier: duplicate \(vid)") }
            let ref = str(a, "referenceName", path, "gamecenter") ?? ""
            if ref.isEmpty { v.error("gamecenter", "\(path).referenceName: empty") }
            if ref.count > 64 { v.warnings.append("\(path).referenceName is \(ref.count) characters; App Store Connect may cap it") }
            var points = 0
            if isInt(a["points"]) {
                points = (a["points"] as! NSNumber).intValue
                if points < 0 || points > 100 { v.error("gamecenter", "\(path).points: 0-100 per achievement") }
                if points == 0 { v.warnings.append("\(path).points is 0") }
            } else { v.error("gamecenter", "\(path).points: must be an integer") }
            total += points
            let show = bool(a, "showBeforeEarned", path, "gamecenter") ?? true
            let rep = bool(a, "repeatable", path, "gamecenter") ?? false
            var locs: [(String, AchievementLoc)] = []
            if let l = a["localizations"] as? JSON, !l.isEmpty {
                for (locale, lv) in l.sorted(by: { $0.key < $1.key }) where !locale.hasPrefix("_") {
                    guard let lo = lv as? JSON else { v.error("gamecenter", "\(path).localizations.\(locale): must be an object"); continue }
                    unknownKeys(lo, ["name", "beforeEarnedDescription", "afterEarnedDescription"], "\(path).localizations.\(locale)", "gamecenter")
                    let n = str(lo, "name", "\(path).localizations.\(locale)", "gamecenter") ?? ""
                    let b = str(lo, "beforeEarnedDescription", "\(path).localizations.\(locale)", "gamecenter") ?? ""
                    let af = str(lo, "afterEarnedDescription", "\(path).localizations.\(locale)", "gamecenter") ?? ""
                    if n.isEmpty || b.isEmpty || af.isEmpty { v.error("gamecenter", "\(path).localizations.\(locale): name and both descriptions must be non-empty") }
                    locs.append((locale, AchievementLoc(name: n, before: b, after: af, inherited: false)))
                }
            } else { v.error("gamecenter", "\(path).localizations: must be a non-empty object keyed by locale") }
            // Every store locale gets the achievement text; missing ones copy the primary locale's (achievements.md:
            // en-GB and en-US are identical for 1.0).
            if let base = locs.first(where: { $0.0 == m.primaryLocale })?.1 ?? locs.first?.1 {
                for locale in m.locales where !locs.contains(where: { $0.0 == locale }) {
                    locs.append((locale, AchievementLoc(name: base.name, before: base.before, after: base.after, inherited: true)))
                }
            }
            var image: ImageFile? = nil
            if let ip = str(a, "image", path, "gamecenter", nullable: true), !ip.isEmpty {
                switch loadImage(ip) {
                case .failure(let e):
                    v.block("gamecenter", "\(vid): badge image \(e.description) (run badges.swift); the image is not pushed")
                case .success(let f):
                    if f.info.width != 1024 || f.info.height != 1024 { v.error("gamecenter", "\(path).image: \(f.info.width)x\(f.info.height), Game Center needs 1024x1024") }
                    if f.info.hasAlpha { v.warnings.append("\(ip) has an alpha channel; Game Center asks for RGB") }
                    image = f
                }
            } else {
                v.block("gamecenter", "\(vid): no image; Game Center needs one per localization")
            }
            m.achievements.append(AchievementSpec(vendorIdentifier: vid, referenceName: ref, points: points,
                                                  showBeforeEarned: show, repeatable: rep, localizations: locs, image: image))
        }
        if total > 1000 { v.error("gamecenter", "$.achievements: \(total) points in total, limit 1000") }
        if let appIDs = contractAchievementIDs() {
            let mine = Set(m.achievements.map { $0.vendorIdentifier })
            let missing = Set(appIDs).subtracting(mine).sorted()
            let extra = mine.subtracting(appIDs).sorted()
            if !missing.isEmpty { v.error("gamecenter", "$.achievements lacks the app's IDs (GameCenterManager.achievementIDs): \(missing.joined(separator: ", "))") }
            if !extra.isEmpty { v.error("gamecenter", "$.achievements has IDs the app never reports: \(extra.joined(separator: ", "))") }
        } else {
            v.warnings.append("\(gameCenterSource) not found: achievement IDs not checked against the app")
        }
    } else if root["achievements"] != nil {
        v.error("gamecenter", "$.achievements: must be an array")
    }

    // leaderboards (GameCenterLeaderboardV2: classic, or recurring with start date, duration and rule)
    if let list = root["leaderboards"] as? [Any] {
        var seen = Set<String>()
        let formatters: Set<String> = ["INTEGER", "DECIMAL_POINT_1_PLACE", "DECIMAL_POINT_2_PLACE", "DECIMAL_POINT_3_PLACE",
                                       "ELAPSED_TIME_CENTISECOND", "ELAPSED_TIME_MINUTE", "ELAPSED_TIME_SECOND", "MONEY_POUND_DECIMAL",
                                       "MONEY_POUND", "MONEY_DOLLAR_DECIMAL", "MONEY_DOLLAR", "MONEY_EURO_DECIMAL", "MONEY_EURO",
                                       "MONEY_FRANC_DECIMAL", "MONEY_FRANC", "MONEY_KRONER_DECIMAL", "MONEY_KRONER", "MONEY_YEN"]
        for (i, item) in list.enumerated() {
            let path = "$.leaderboards[\(i)]"
            guard let l = item as? JSON else { v.error("gamecenter", "\(path): must be an object"); continue }
            unknownKeys(l, ["vendorIdentifier", "referenceName", "defaultFormatter", "scoreSortType", "submissionType", "scoreRangeStart",
                            "scoreRangeEnd", "recurrence", "visibility", "localizations"], path, "gamecenter")
            let vid = str(l, "vendorIdentifier", path, "gamecenter") ?? ""
            if vid.range(of: "^[A-Za-z0-9._]{1,100}$", options: .regularExpression) == nil {
                v.error("gamecenter", "\(path).vendorIdentifier: '\(vid)' must be 1-100 characters of A-Z a-z 0-9 . _")
            }
            if !seen.insert(vid).inserted { v.error("gamecenter", "\(path).vendorIdentifier: duplicate \(vid)") }
            var a: JSON = [:]
            if let ref = str(l, "referenceName", path, "gamecenter"), !ref.isEmpty { a["referenceName"] = ref } else { v.error("gamecenter", "\(path).referenceName: empty") }
            if let f = str(l, "defaultFormatter", path, "gamecenter") {
                if formatters.contains(f) { a["defaultFormatter"] = f } else { v.error("gamecenter", "\(path).defaultFormatter: '\(f)' is not a GameCenterLeaderboardFormatter") }
            }
            if let s = str(l, "scoreSortType", path, "gamecenter") {
                if ["ASC", "DESC"].contains(s) { a["scoreSortType"] = s } else { v.error("gamecenter", "\(path).scoreSortType: ASC or DESC") }
            }
            if let s = str(l, "submissionType", path, "gamecenter") {
                if ["BEST_SCORE", "MOST_RECENT_SCORE"].contains(s) { a["submissionType"] = s } else { v.error("gamecenter", "\(path).submissionType: BEST_SCORE or MOST_RECENT_SCORE") }
            }
            if let vis = str(l, "visibility", path, "gamecenter", nullable: true) {
                if ["SHOW_FOR_ALL", "HIDE_FOR_ALL"].contains(vis) { a["visibility"] = vis } else { v.error("gamecenter", "\(path).visibility: SHOW_FOR_ALL or HIDE_FOR_ALL") }
            }
            // The API takes the range as STRINGS (push run 40343054685: "Expected a STRING but got INTEGER").
            var range: [String: Double] = [:]
            for k in ["scoreRangeStart", "scoreRangeEnd"] {
                guard let raw = l[k], !(raw is NSNull) else { continue }
                if let n = raw as? NSNumber, !isBool(n) { a[k] = n.stringValue; range[k] = n.doubleValue }
                else { v.error("gamecenter", "\(path).\(k): must be a number") }
            }
            if let s = range["scoreRangeStart"], let e = range["scoreRangeEnd"], s >= e {
                v.error("gamecenter", "\(path): scoreRangeStart must be below scoreRangeEnd")
            }
            if let r = l["recurrence"] as? JSON {
                unknownKeys(r, ["startDate", "duration", "rule"], "\(path).recurrence", "gamecenter")
                if let sd = str(r, "startDate", "\(path).recurrence", "gamecenter") {
                    if let d = parseDate(sd) { a["recurrenceStartDate"] = isoFormatter.string(from: d) }
                    else { v.error("gamecenter", "\(path).recurrence.startDate: '\(sd)' is not ISO 8601") }
                }
                // The duration must carry time components (push run 40344348013 refused "P1D": "Expected an ISO
                // 8601 duration with time components"), so a day is PT24H. The rule is an RFC 5545 RRULE such as
                // FREQ=DAILY;INTERVAL=1.
                if let du = str(r, "duration", "\(path).recurrence", "gamecenter") {
                    if du.range(of: "^P(\\d+D)?T\\d+H(\\d+M)?$", options: .regularExpression) != nil { a["recurrenceDuration"] = du }
                    else { v.error("gamecenter", "\(path).recurrence.duration: an ISO 8601 duration with time components, such as PT24H") }
                }
                if let ru = str(r, "rule", "\(path).recurrence", "gamecenter") {
                    if ru.hasPrefix("FREQ=") { a["recurrenceRule"] = ru } else { v.error("gamecenter", "\(path).recurrence.rule: an RRULE such as FREQ=DAILY;INTERVAL=1") }
                }
            } else if let r = l["recurrence"], !(r is NSNull) {
                v.error("gamecenter", "\(path).recurrence: an object or null (null = classic)")
            }
            var locs: [(String, JSON)] = []
            if let lo = l["localizations"] as? JSON, !lo.isEmpty {
                for (locale, lv) in lo.sorted(by: { $0.key < $1.key }) where !locale.hasPrefix("_") {
                    let lp = "\(path).localizations.\(locale)"
                    guard let o = lv as? JSON else { v.error("gamecenter", "\(lp): must be an object"); continue }
                    unknownKeys(o, ["name", "description", "formatterSuffix", "formatterSuffixSingular", "formatterOverride"], lp, "gamecenter")
                    var d: JSON = [:]
                    if let n = str(o, "name", lp, "gamecenter"), !n.isEmpty { d["name"] = n } else { v.error("gamecenter", "\(lp).name: empty") }
                    for k in ["description", "formatterSuffix", "formatterSuffixSingular", "formatterOverride"] {
                        if let s = str(o, k, lp, "gamecenter", nullable: true), !s.isEmpty { d[k] = s }
                    }
                    if let fo = d["formatterOverride"] as? String, !formatters.contains(fo) { v.error("gamecenter", "\(lp).formatterOverride: not a formatter") }
                    locs.append((locale, d))
                }
            } else { v.error("gamecenter", "\(path).localizations: must be a non-empty object keyed by locale") }
            var inherited = Set<String>()
            if let base = locs.first(where: { $0.0 == m.primaryLocale })?.1 ?? locs.first?.1 {
                for locale in m.locales where !locs.contains(where: { $0.0 == locale }) { locs.append((locale, base)); inherited.insert(locale) }
            }
            m.leaderboards.append(LeaderboardSpec(vendorIdentifier: vid, attributes: a, localizations: locs, inheritedLocales: inherited))
        }
        if let appIDs = contractLeaderboardIDs() {
            let mine = Set(m.leaderboards.map { $0.vendorIdentifier })
            let missing = Set(appIDs).subtracting(mine).sorted()
            let extra = mine.subtracting(appIDs).sorted()
            if !missing.isEmpty { v.error("gamecenter", "$.leaderboards lacks the app's IDs (GameCenterManager.Leaderboard): \(missing.joined(separator: ", "))") }
            if !extra.isEmpty { v.error("gamecenter", "$.leaderboards has IDs the app never submits to: \(extra.joined(separator: ", "))") }
        } else {
            v.warnings.append("\(gameCenterSource) not found: leaderboard IDs not checked against the app")
        }
    } else if root["leaderboards"] != nil {
        v.error("gamecenter", "$.leaderboards: must be an array")
    }

    // nomination (App Store featuring nomination, NominationCreateRequest; `notes` is the form's Helpful Details)
    if let n = root["nomination"] as? JSON {
        let p = "$.nomination"
        unknownKeys(n, ["name", "type", "description", "notes", "publishStartDate", "publishEndDate", "deviceFamilies", "locales",
                        "supplementalMaterialsUris", "hasInAppEvents", "launchInSelectMarketsFirst", "preOrderEnabled", "submit"], p, "nomination")
        var a: JSON = [:]
        for (k, limit) in [("name", 60), ("description", 1000), ("notes", 500)] {
            if let s = str(n, k, p, "nomination", nullable: k == "notes"), !s.isEmpty {
                if s.count > limit { v.error("nomination", "\(p).\(k): \(s.count) characters, limit \(limit)") }
                if isPlaceholder(s) { v.error("nomination", "\(p).\(k): contains a placeholder") }
                a[k] = s
            } else if k != "notes" { v.error("nomination", "\(p).\(k): empty") }
        }
        if let t = str(n, "type", p, "nomination") {
            if ["APP_LAUNCH", "APP_ENHANCEMENTS", "NEW_CONTENT"].contains(t) { a["type"] = t } else { v.error("nomination", "\(p).type: APP_LAUNCH, APP_ENHANCEMENTS or NEW_CONTENT") }
        }
        for k in ["publishStartDate", "publishEndDate"] {
            guard let s = str(n, k, p, "nomination", nullable: k == "publishEndDate"), !s.isEmpty else { continue }
            if let d = parseDate(s) {
                a[k] = isoFormatter.string(from: d)
                if k == "publishStartDate" && d.timeIntervalSinceNow < 21 * 86400 {
                    v.warnings.append("nomination.publishStartDate is less than 3 weeks away; Apple asks for 3 weeks' notice")
                }
            } else { v.error("nomination", "\(p).\(k): '\(s)' is not ISO 8601") }
        }
        for k in ["deviceFamilies", "locales", "supplementalMaterialsUris"] {
            guard let raw = n[k], !(raw is NSNull) else { continue }
            guard let arr = raw as? [String] else { v.error("nomination", "\(p).\(k): must be an array of strings"); continue }
            if k == "deviceFamilies", let bad = arr.first(where: { !["IPHONE", "IPAD", "APPLE_TV", "APPLE_WATCH", "MAC", "VISION"].contains($0) }) {
                v.error("nomination", "\(p).deviceFamilies: '\(bad)' is not a DeviceFamily")
            }
            if k == "supplementalMaterialsUris" {
                if arr.count > 5 { v.error("nomination", "\(p).supplementalMaterialsUris: at most 5") }
                for u in arr where URL(string: u)?.scheme?.hasPrefix("http") != true || isPlaceholder(u) { v.error("nomination", "\(p).supplementalMaterialsUris: '\(u)' is not a URL") }
            }
            a[k] = arr
        }
        for k in ["hasInAppEvents", "launchInSelectMarketsFirst", "preOrderEnabled"] {
            guard let raw = n[k], !(raw is NSNull) else { continue }
            if isBool(raw) { a[k] = raw } else { v.error("nomination", "\(p).\(k): must be true or false") }
        }
        let submit = n["submit"].map { isBool($0) && ($0 as! NSNumber).boolValue } ?? false
        m.nomination = NominationSpec(attributes: a, submit: submit)
    } else if let n = root["nomination"], !(n is NSNull) {
        v.error("nomination", "$.nomination: must be an object")
    }

    // screenshots
    if let s = root["screenshots"] as? JSON {
        unknownKeys(s, screenshotKeys, "$.screenshots", "screenshots")
        for key in screenshotKeys {
            guard let raw = s[key], !(raw is NSNull) else { continue }
            guard let paths = raw as? [String] else { v.error("screenshots", "$.screenshots.\(key): must be an array of paths"); continue }
            if paths.isEmpty { continue }
            if paths.count > 10 { v.error("screenshots", "$.screenshots.\(key): at most 10 per display") }
            var files: [ImageFile] = []
            var missing = false
            for p in paths {
                let lower = p.lowercased()
                if lower.contains("/verify/") || lower.contains("-eye") || lower.contains("book-storeshot") {
                    v.error("screenshots", "$.screenshots.\(key): \(p) is a review-only frame (never upload verify/, -eye, book store shots)")
                }
                switch loadImage(p, base: screenshotsBase) {
                case .failure(let e): missing = true; v.block("screenshots", "\(key): \(e.description)")
                case .success(let f):
                    if !sizeMatches(key, f.info) {
                        v.error("screenshots", "$.screenshots.\(key): \(p) is \(f.info.width)x\(f.info.height); \(key) takes \((screenshotSizes[key] ?? []).map { "\($0.0)x\($0.1)" }.joined(separator: ", "))")
                    }
                    if f.info.hasAlpha { v.error("screenshots", "$.screenshots.\(key): \(p) has an alpha channel (App Store screenshots must be opaque)") }
                    files.append(f)
                }
            }
            if missing {
                v.block("screenshots", "\(key): set skipped until every file exists (gh run download a green store.yml run, then set ASC_SCREENSHOTS_DIR to that folder, or use upload-screenshots <dir>)")
            } else {
                m.screenshots.append(ScreenshotSet(key: key, files: files))
            }
        }
    } else if root["screenshots"] != nil {
        v.error("screenshots", "$.screenshots: must be an object")
    }

    // accessibility (optional extension: Accessibility Nutrition Labels, AccessibilityDeclaration, API 4.x)
    if let a = root["accessibility"] {
        if let obj = a as? JSON {
            let flags = ["supportsAudioDescriptions", "supportsCaptions", "supportsDarkInterface",
                         "supportsDifferentiateWithoutColorAlone", "supportsLargerText", "supportsReducedMotion",
                         "supportsSufficientContrast", "supportsVoiceControl", "supportsVoiceover"]
            unknownKeys(obj, ["deviceFamily", "publish"] + flags, "$.accessibility", "accessibility")
            var clean: JSON = [:]
            for f in flags + ["publish"] {
                if let val = obj[f] { if isBool(val) { clean[f] = val } else { v.error("accessibility", "$.accessibility.\(f): must be true or false") } }
            }
            clean["deviceFamily"] = (obj["deviceFamily"] as? String) ?? "IPHONE"
            m.accessibility = clean
        } else if !(a is NSNull) {
            v.error("accessibility", "$.accessibility: must be an object")
        }
    }
    return m
}

// MARK: - Screenshots from a downloaded store.yml artifact

func screenshotsFromDirectory(_ dir: URL) throws -> [ScreenshotSet] {
    guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else {
        throw ToolError("\(dir.path): not a directory")
    }
    var byKey: [String: [ImageFile]] = [:]
    var manifests: [URL] = []
    for case let url as URL in walker {
        let rel = url.path.replacingOccurrences(of: dir.path + "/", with: "")
        let parts = rel.split(separator: "/").map { String($0) }
        if parts.contains("store-placements") { continue }   // header/search art: the placements step's, not a screenshot set
        if url.lastPathComponent == "MANIFEST.txt" { manifests.append(url) }
        let ext = url.pathExtension.lowercased()
        guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
        // Upload set only: files inside a `store` folder, never verify/ or -eye composites.
        guard parts.dropLast().contains("store") || parts.dropLast().contains(where: { $0.hasPrefix("duo-inner") || $0.hasPrefix("duo-outer") }) else { continue }
        if parts.contains("verify") || url.lastPathComponent.contains("-eye") { continue }
        guard let data = try? Data(contentsOf: url), let info = imageInfo(data) else { continue }
        guard let key = screenshotKeys.first(where: { sizeMatches($0, info) }) else {
            warn("\(rel): \(info.width)x\(info.height) matches no screenshot set; ignored")
            continue
        }
        if info.hasAlpha { throw ToolError("\(rel) has an alpha channel") }
        byKey[key, default: []].append(ImageFile(path: rel, url: url, data: data, info: info))
    }
    for m in manifests {
        let text = (try? String(contentsOf: m, encoding: .utf8)) ?? ""
        // The Duo manifest reports "missing: 0  flagged: 0"; the Pinch Press ones (ci/screenshots.sh) only
        // "flagged: 0  (content 0, …)". Accept either, never a non-zero count.
        let clean = text.range(of: "(^|\\n)\\s*(missing: 0\\s+)?flagged: 0\\b", options: .regularExpression) != nil
        let refused = text.range(of: "(missing|flagged): [1-9]", options: .regularExpression) != nil
        if !clean || refused {
            throw ToolError("\(m.path) does not report 'flagged: 0' (and 'missing: 0' where counted); refusing to upload a set with refused frames")
        }
    }
    return screenshotKeys.compactMap { key in
        guard let files = byKey[key], !files.isEmpty else { return nil }
        let sorted = files.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        if sorted.count > 10 { warn("\(key): \(sorted.count) frames found, only the first 10 are used") }
        return ScreenshotSet(key: key, files: Array(sorted.prefix(10)))
    }
}

// MARK: - Creative assets: product page header and search results art (iOS 27 App Store, 5 Oct 2026)

/// One optional creative asset (docs/appstore/header-search.md). Placement type IDs are read from the asset library
/// reference data at run time. PRODUCT_PAGE_HEADER_ASSET is named in Apple's API docs; APP_STORE_SEARCH_RESULTS_ASSET
/// is what developers report (UNCONFIRMED in Apple's pages, 26 Oct 2026). If an ID is absent from the reference data,
/// the one placement type whose ID contains `typeWord` is used instead.
struct PlacementSpec { let key: String; let label: String; let typeID: String; let typeWord: String; let fileNames: [String] }
let placementSpecs = [
    PlacementSpec(key: "header", label: "product page header", typeID: "PRODUCT_PAGE_HEADER_ASSET", typeWord: "HEADER",
                  fileNames: ["header-3840x1646.png", "header-3840x1646.jpg", "universal-5244x2950.png"]),
    PlacementSpec(key: "search", label: "search results art", typeID: "APP_STORE_SEARCH_RESULTS_ASSET", typeWord: "SEARCH",
                  fileNames: ["search-3840x2560.png", "search-3840x2560.jpg", "universal-5244x2950.png"]),
]
struct PlacementFile { let spec: PlacementSpec; let file: ImageFile }

/// App Store Connect Help, Creative assets specifications (read 26 Oct 2026): header 21:9 3840 x 1646 (PNG or JPEG) or
/// the universal 16:9 5244 x 2950 PNG; search results 3:2 from 1920 x 1280 to 3840 x 2560, or the universal PNG.
/// No alpha channel in either.
func placementSizeOK(_ key: String, _ i: ImageInfo) -> Bool {
    if i.width == 5244 && i.height == 2950 { return i.format == "png" }
    if key == "header" { return i.width == 3840 && i.height == 1646 }
    return i.width >= 1920 && i.width <= 3840 && i.width * 2 == i.height * 3
}

func placementsDirectory(_ explicit: String?) -> URL? {
    if let e = explicit ?? env["ASC_PLACEMENTS_DIR"], !e.trimmingCharacters(in: .whitespaces).isEmpty {
        return URL(fileURLWithPath: (e as NSString).expandingTildeInPath)
    }
    if let b = screenshotsBase {
        let u = b.appendingPathComponent("store-placements")
        if FileManager.default.fileExists(atPath: u.path) { return u }
    }
    return nil
}

/// The header and search files in `dir` (ci/store-placements.sh output), checked offline: exact size, no alpha, and the
/// folder's MANIFEST (when present) reporting no problems. A missing folder or file is a gap, never an error.
func loadPlacements(_ dir: URL?, _ v: Validation) -> [PlacementFile] {
    guard let dir = dir else {
        v.block("placements", "no header/search art folder (ASC_PLACEMENTS_DIR = a downloaded store-placements artifact): App Store Connect's are left as they are")
        return []
    }
    let manifest = dir.appendingPathComponent("MANIFEST.txt")
    if let text = try? String(contentsOf: manifest, encoding: .utf8),
       text.range(of: "problems [1-9]", options: .regularExpression) != nil || text.contains(" FLAGGED ") || text.contains(" FAILED ") {
        v.error("placements", "\(manifest.path) reports problems; refusing to place that art (fix it and re-run store.yml)")
        return []
    }
    var result: [PlacementFile] = []
    for spec in placementSpecs {
        guard let name = spec.fileNames.first(where: { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }) else {
            v.block("placements", "\(spec.label): no \(spec.fileNames[0]) in \(dir.path); not placed")
            continue
        }
        switch loadImage(dir.appendingPathComponent(name).path) {
        case .failure(let e): v.error("placements", "\(spec.label): \(e.description)")
        case .success(let f):
            if !placementSizeOK(spec.key, f.info) {
                let want = spec.key == "header" ? "3840x1646" : "3:2 from 1920x1280 to 3840x2560"
                v.error("placements", "\(spec.label): \(name) is \(f.info.width)x\(f.info.height); Apple takes \(want) or the universal 5244x2950 PNG")
            } else if f.info.hasAlpha {
                v.error("placements", "\(spec.label): \(name) has an alpha channel (creative assets must be opaque)")
            } else {
                result.append(PlacementFile(spec: spec, file: f))
            }
        }
    }
    return result
}

// MARK: - App Store Connect client (ES256 JWT, JSON:API)

final class ASC {
    let keyID: String
    let issuerID: String
    let key: P256.Signing.PrivateKey
    let base = "https://api.appstoreconnect.apple.com"
    let session = URLSession(configuration: .ephemeral)
    private var token = ""
    private var tokenExpiry = Date.distantPast

    init() throws {
        guard let kid = env["ASC_KEY_ID"], !kid.isEmpty else {
            throw ToolError("ASC_KEY_ID is not set. See tools/appstore/README.md (create an App Store Connect API key).")
        }
        keyID = kid
        issuerID = env["ASC_ISSUER_ID"] ?? ""
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [env["ASC_KEY_PATH"] ?? "", "\(home)/.appstoreconnect/private_keys/AuthKey_\(kid).p8",
                          "\(home)/private_keys/AuthKey_\(kid).p8", "./private_keys/AuthKey_\(kid).p8"].filter { !$0.isEmpty }
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw ToolError("no .p8 key found. Set ASC_KEY_PATH, or put AuthKey_\(kid).p8 in ~/.appstoreconnect/private_keys/")
        }
        guard let pem = try? String(contentsOfFile: path, encoding: .utf8) else { throw ToolError("cannot read \(path)") }
        do { key = try P256.Signing.PrivateKey(pemRepresentation: pem) } catch {
            throw ToolError("\(path) is not an App Store Connect .p8 private key (PEM, PKCS#8, P-256)")
        }
    }

    private func b64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// ES256 token, 15 minutes (Apple's limit is 20). Team keys carry iss; individual keys carry sub "user".
    func bearer() throws -> String {
        if Date() < tokenExpiry { return token }
        let now = Int(Date().timeIntervalSince1970)
        let header: JSON = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
        var payload: JSON = ["iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"]
        if issuerID.isEmpty { payload["sub"] = "user" } else { payload["iss"] = issuerID }
        let h = b64url(try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]))
        let p = b64url(try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
        let signingInput = "\(h).\(p)"
        let sig = try key.signature(for: Data(signingInput.utf8))
        token = "\(signingInput).\(b64url(sig.rawRepresentation))"
        tokenExpiry = Date().addingTimeInterval(840)
        return token
    }

    struct Response { let status: Int; let json: JSON? }

    static func describeErrors(_ status: Int, _ json: JSON?) -> String {
        guard let errs = json?["errors"] as? [JSON], !errs.isEmpty else { return "HTTP \(status)" }
        return errs.map { e in
            var s = "HTTP \(e["status"] as? String ?? "\(status)") \(e["code"] as? String ?? ""): \(e["title"] as? String ?? "")"
            if let d = e["detail"] as? String { s += ". \(d)" }
            if let src = e["source"] as? JSON, let ptr = src["pointer"] as? String ?? src["parameter"] as? String { s += " (\(ptr))" }
            return s
        }.joined(separator: "; ")
    }

    func send(_ method: String, _ pathOrURL: String, query: [(String, String)] = [], body: JSON? = nil) async throws -> Response {
        var comps = URLComponents(string: pathOrURL.hasPrefix("http") ? pathOrURL : base + pathOrURL)!
        if !query.isEmpty { comps.queryItems = (comps.queryItems ?? []) + query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        guard let url = comps.url else { throw ToolError("bad URL \(pathOrURL)") }
        var attempt = 0
        while true {
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.timeoutInterval = 120
            req.setValue("Bearer \(try bearer())", forHTTPHeaderField: "Authorization")
            if let body = body {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            do {
                let (data, resp) = try await session.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let json = data.isEmpty ? nil : (try? JSONSerialization.jsonObject(with: data)) as? JSON
                if (status == 429 || status >= 500) && attempt < 5 {
                    attempt += 1
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
                    continue
                }
                return Response(status: status, json: json)
            } catch let e as URLError where attempt < 3 {
                attempt += 1
                warn("network: \(e.localizedDescription); retrying")
                try await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    /// GET that must succeed. Planned (dry-run) IDs never hit the network: they have no children yet.
    func get(_ path: String, _ query: [(String, String)] = []) async throws -> JSON {
        if path.contains(plannedPrefix) { return ["data": [Any]()] }
        let r = try await send("GET", path, query: query)
        guard (200..<300).contains(r.status) else { throw ToolError("GET \(path): \(ASC.describeErrors(r.status, r.json))") }
        return r.json ?? [:]
    }

    /// GET where 404 means "not there yet".
    func getOptional(_ path: String, _ query: [(String, String)] = []) async throws -> JSON? {
        if path.contains(plannedPrefix) { return nil }
        let r = try await send("GET", path, query: query)
        if r.status == 404 { return nil }
        guard (200..<300).contains(r.status) else { throw ToolError("GET \(path): \(ASC.describeErrors(r.status, r.json))") }
        return r.json
    }

    /// Every page of a collection. Returns (data, included).
    func getAll(_ path: String, _ query: [(String, String)] = []) async throws -> ([JSON], [JSON]) {
        if path.contains(plannedPrefix) { return ([], []) }
        var items: [JSON] = []
        var included: [JSON] = []
        var page: JSON = try await get(path, query)
        while true {
            items += (page["data"] as? [JSON]) ?? []
            included += (page["included"] as? [JSON]) ?? []
            guard let links = page["links"] as? JSON, let next = links["next"] as? String, !next.isEmpty else { break }
            let r = try await send("GET", next)
            guard (200..<300).contains(r.status), let j = r.json else { throw ToolError("GET \(next): \(ASC.describeErrors(r.status, r.json))") }
            page = j
        }
        return (items, included)
    }

    func write(_ method: String, _ path: String, _ body: JSON?) async throws -> JSON? {
        let r = try await send(method, path, body: body)
        guard (200..<300).contains(r.status) else { throw ToolError("\(method) \(path): \(ASC.describeErrors(r.status, r.json))") }
        return r.json
    }

    /// Asset upload: follow each reservation operation (method, url, offset, length, requestHeaders). The URLs are
    /// pre-signed; no JWT is sent to them.
    func runUploadOperations(_ ops: [JSON], data: Data) async throws {
        guard !ops.isEmpty else { throw ToolError("the reservation returned no upload operations") }
        for op in ops {
            guard let urlString = op["url"] as? String, let url = URL(string: urlString) else { throw ToolError("upload operation without a URL") }
            let offset = (op["offset"] as? NSNumber)?.intValue ?? 0
            let length = (op["length"] as? NSNumber)?.intValue ?? data.count
            guard offset >= 0, offset + length <= data.count else { throw ToolError("upload operation outside the file") }
            var req = URLRequest(url: url)
            req.httpMethod = (op["method"] as? String) ?? "PUT"
            req.timeoutInterval = 300
            for h in (op["requestHeaders"] as? [JSON]) ?? [] {
                if let n = h["name"] as? String, let v = h["value"] as? String { req.setValue(v, forHTTPHeaderField: n) }
            }
            let part = data.subdata(in: offset..<(offset + length))
            var attempt = 0
            while true {
                let (_, resp) = try await session.upload(for: req, from: part)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status) { break }
                attempt += 1
                if attempt > 3 { throw ToolError("upload part at offset \(offset) failed: HTTP \(status)") }
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}

// JSON:API helpers
func ref(_ type: String, _ id: String) -> JSON { ["data": ["type": type, "id": id]] }
func refs(_ type: String, _ ids: [String]) -> JSON { ["data": ids.map { ["type": type, "id": $0] }] }
func dataList(_ j: JSON?) -> [JSON] { (j?["data"] as? [JSON]) ?? [] }
func dataOne(_ j: JSON?) -> JSON? { j?["data"] as? JSON }
func attrs(_ r: JSON?) -> JSON { (r?["attributes"] as? JSON) ?? [:] }
func idOf(_ r: JSON?) -> String { (r?["id"] as? String) ?? "" }
func relID(_ r: JSON, _ name: String) -> String? {
    ((r["relationships"] as? JSON)?[name] as? JSON).flatMap { ($0["data"] as? JSON)?["id"] as? String }
}

// MARK: - The sync engine (plan = dry run of push)

final class Engine {
    let api: ASC
    let meta: Metadata
    let dryRun: Bool
    let steps: Set<String>
    var changes = 0
    var unchanged = 0
    var failures: [String] = []
    var manual: [String] = []
    private var plannedCounter = 0

    var appID = ""
    var appInfoID = ""
    var appInfo: JSON = [:]
    var versionID = ""
    var versionLocIDs: [String: String] = [:]

    init(api: ASC, meta: Metadata, dryRun: Bool, steps: Set<String>) {
        self.api = api; self.meta = meta; self.dryRun = dryRun; self.steps = steps
    }

    func head(_ s: String) { out(""); out("── \(s)") }
    func same(_ what: String) { unchanged += 1; out("   = \(what)") }
    func note(_ s: String) { out("   · \(s)") }

    func diffLines(_ current: JSON, _ desired: JSON) -> (JSON, [String]) {
        var patch: JSON = [:]
        var lines: [String] = []
        for k in desired.keys.sorted() {
            let d = desired[k]
            if !isSameValue(current[k], d) {
                patch[k] = d ?? NSNull()
                lines.append("\(k): \(short(current[k])) → \(short(d))")
            }
        }
        return (patch, lines)
    }

    func create(_ what: String, _ path: String, type: String, attributes: JSON? = nil, relationships: JSON? = nil,
                included: [JSON]? = nil, detail: [String] = []) async throws -> JSON {
        changes += 1
        out("   + \(dryRun ? "would create" : "create") \(what)")
        for d in detail { out("       \(d)") }
        if dryRun {
            plannedCounter += 1
            return ["type": type, "id": "\(plannedPrefix)\(plannedCounter)", "attributes": attributes ?? [:]]
        }
        var data: JSON = ["type": type]
        if let a = attributes, !a.isEmpty { data["attributes"] = a }
        if let r = relationships, !r.isEmpty { data["relationships"] = r }
        var body: JSON = ["data": data]
        if let inc = included { body["included"] = inc }
        guard let res = try await api.write("POST", path, body), let obj = dataOne(res) else {
            throw ToolError("POST \(path) returned no resource")
        }
        return obj
    }

    func update(_ what: String, _ path: String, type: String, id: String, attributes: JSON? = nil,
                relationships: JSON? = nil, lines: [String]) async throws {
        changes += 1
        out("   ~ \(dryRun ? "would update" : "update") \(what)")
        for l in lines { out("       \(l)") }
        if dryRun || id.hasPrefix(plannedPrefix) { return }
        var data: JSON = ["type": type, "id": id]
        if let a = attributes, !a.isEmpty { data["attributes"] = a }
        if let r = relationships, !r.isEmpty { data["relationships"] = r }
        _ = try await api.write("PATCH", path, ["data": data])
    }

    /// PATCH of a to-many relationship (the body is a plain linkage list).
    func relink(_ what: String, _ path: String, _ linkage: JSON, lines: [String]) async throws {
        changes += 1
        out("   ~ \(dryRun ? "would set" : "set") \(what)")
        for l in lines { out("       \(l)") }
        if dryRun || path.contains(plannedPrefix) { return }
        _ = try await api.write("PATCH", path, linkage)
    }

    func delete(_ what: String, _ path: String) async throws {
        changes += 1
        out("   - \(dryRun ? "would delete" : "delete") \(what)")
        if dryRun || path.contains(plannedPrefix) { return }
        _ = try await api.write("DELETE", path, nil)
    }

    /// Runs one step; a failure is recorded and the next step still runs.
    func step(_ name: String, _ title: String, _ body: () async throws -> Void) async {
        guard steps.contains(name) else { return }
        head("\(title) [\(name)]")
        do { try await body() } catch {
            failures.append("\(name): \(error)")
            out("   ! \(error)")
        }
    }

    // MARK: Lookups

    func resolveApp() async throws {
        let res = try await api.get("/v1/apps", [("filter[bundleId]", meta.bundleId),
                                                 ("fields[apps]", "name,bundleId,primaryLocale,sku,contentRightsDeclaration")])
        guard let app = dataList(res).first(where: { attrs($0)["bundleId"] as? String == meta.bundleId }) else {
            throw ToolError("""
            no app with bundle ID \(meta.bundleId) is visible to this key.
              Create the app record first (App Store Connect > Apps > + > New App, bundle ID \(meta.bundleId));
              Apple's API can't create apps. Also check the key's role (App Manager or Admin) and app access.
            """)
        }
        appID = idOf(app)
        let a = attrs(app)
        out("app: \(a["name"] as? String ?? "?") (id \(appID), bundle \(meta.bundleId), primary locale \(a["primaryLocale"] as? String ?? "?"))")
        guard steps.contains("appinfo") else { return }
        // App-level fields: the primary language and Content Rights (App Information > Content Rights).
        var desired: JSON = [:]
        if let pl = a["primaryLocale"] as? String, pl != meta.primaryLocale { desired["primaryLocale"] = meta.primaryLocale }
        if let cr = meta.contentRights { desired["contentRightsDeclaration"] = cr }
        let (patch, lines) = diffLines(a, desired)
        head("App: primary language, content rights [appinfo]")
        if patch.isEmpty { same("primary language \(short(a["primaryLocale"])), content rights \(short(a["contentRightsDeclaration"]))") }
        else { try await update("app", "/v1/apps/\(appID)", type: "apps", id: appID, attributes: patch, lines: lines) }
    }

    static let editableInfoStates: Set<String> = ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW"]
    static let editableVersionStates: Set<String> = ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"]

    func resolveAppInfo() async throws {
        let (infos, _) = try await api.getAll("/v1/apps/\(appID)/appInfos",
                                              [("include", "primaryCategory,primarySubcategoryOne,primarySubcategoryTwo,secondaryCategory,ageRatingDeclaration")])
        let editable = infos.filter { Engine.editableInfoStates.contains((attrs($0)["state"] as? String) ?? (attrs($0)["appStoreState"] as? String) ?? "") }
        guard let info = editable.first(where: { attrs($0)["state"] as? String == "PREPARE_FOR_SUBMISSION" }) ?? editable.first ?? (infos.count == 1 ? infos.first : nil) else {
            throw ToolError("no editable app info (states: \(infos.map { attrs($0)["state"] as? String ?? "?" }.joined(separator: ", "))). App info is only editable while a version is being prepared.")
        }
        appInfoID = idOf(info)
        appInfo = info
    }

    func resolveVersion(create: Bool) async throws {
        let target = env["ASC_VERSION"] ?? "1.0"
        let (versions, _) = try await api.getAll("/v1/apps/\(appID)/appStoreVersions",
                                                 [("filter[platform]", "IOS"), ("limit", "50"),
                                                  ("fields[appStoreVersions]", "versionString,appVersionState,appStoreState,copyright,releaseType,earliestReleaseDate,platform")])
        let editable = versions.filter { Engine.editableVersionStates.contains((attrs($0)["appVersionState"] as? String) ?? (attrs($0)["appStoreState"] as? String) ?? "") }
        if let v = editable.first {
            let vs = attrs(v)["versionString"] as? String ?? "?"
            guard vs == target else {
                throw ToolError("the editable iOS version is \(vs), not \(target). Run with ASC_VERSION=\(vs) to edit it.")
            }
            versionID = idOf(v)
            versionAttrs = attrs(v)
            return
        }
        if versions.contains(where: { attrs($0)["versionString"] as? String == target }) {
            throw ToolError("version \(target) exists but is no longer editable (\(versions.map { "\(attrs($0)["versionString"] as? String ?? "?") \(attrs($0)["appVersionState"] as? String ?? "?")" }.joined(separator: ", ")))")
        }
        guard create else { throw ToolError("no editable iOS version; `push` would create \(target)") }
        let created = try await self.create("App Store version \(target) (iOS)", "/v1/appStoreVersions", type: "appStoreVersions",
                                            attributes: ["platform": "IOS", "versionString": target],
                                            relationships: ["app": ref("apps", appID)])
        versionID = idOf(created)
        versionAttrs = attrs(created)
    }
    var versionAttrs: JSON = [:]

    // MARK: Steps

    func syncAppInfoLocalizations() async throws {
        let (existing, _) = try await api.getAll("/v1/appInfos/\(appInfoID)/appInfoLocalizations", [("limit", "50")])
        for locale in meta.locales {
            guard let t = meta.text[locale] else { continue }
            var desired: JSON = [:]
            for k in ["name", "subtitle", "privacyPolicyUrl"] { if let v = t.fields[k] { desired[k] = v } }
            let inherited = t.inherited.intersection(["name", "subtitle", "privacyPolicyUrl"]).sorted()
            let tag = inherited.isEmpty ? "" : " (\(inherited.joined(separator: ", ")) inherited from \(meta.primaryLocale))"
            if let cur = existing.first(where: { attrs($0)["locale"] as? String == locale }) {
                let (patch, lines) = diffLines(attrs(cur), desired)
                if patch.isEmpty { same("\(locale) name/subtitle/privacy URL") }
                else { try await update("\(locale) app info localization\(tag)", "/v1/appInfoLocalizations/\(idOf(cur))", type: "appInfoLocalizations", id: idOf(cur), attributes: patch, lines: lines) }
            } else {
                guard desired["name"] != nil else { note("\(locale): no name yet, localization not created"); continue }
                var a = desired; a["locale"] = locale
                _ = try await create("\(locale) app info localization\(tag)", "/v1/appInfoLocalizations", type: "appInfoLocalizations",
                                     attributes: a, relationships: ["appInfo": ref("appInfos", appInfoID)],
                                     detail: desired.keys.sorted().map { "\($0): \(short(desired[$0]))" })
            }
        }
    }

    func syncCategories() async throws {
        guard meta.categoriesGiven else { note("no categories in the metadata"); return }
        // The subcategory IDs are checked against Apple's live list first (GET /v1/appCategories/{id}/subcategories).
        if let primary = meta.primaryCategory, !meta.primarySubcategories.isEmpty {
            let (subs, _) = try await api.getAll("/v1/appCategories/\(primary)/subcategories", [("limit", "200")])
            let live = Set(subs.map { idOf($0) })
            let unknown = meta.primarySubcategories.filter { !live.contains($0) }
            if !unknown.isEmpty {
                throw ToolError("\(unknown.joined(separator: ", ")) is not a \(primary) subcategory on the App Store. Live list: \(live.sorted().joined(separator: ", "))")
            }
        }
        let names = ["primaryCategory", "primarySubcategoryOne", "primarySubcategoryTwo", "secondaryCategory"]
        let desired: [String: String?] = [
            "primaryCategory": meta.primaryCategory,
            "primarySubcategoryOne": meta.primarySubcategories.first,
            "primarySubcategoryTwo": meta.primarySubcategories.count > 1 ? meta.primarySubcategories[1] : nil,
            "secondaryCategory": meta.secondaryCategory,
        ]
        var rels: JSON = [:]
        var lines: [String] = []
        for n in names {
            let cur = relID(appInfo, n)
            let want = desired[n] ?? nil
            if cur != want {
                rels[n] = want.map { ref("appCategories", $0) } ?? ["data": NSNull()]
                lines.append("\(n): \(cur ?? "∅") → \(want ?? "∅")")
            }
        }
        if rels.isEmpty { same("categories \(meta.primaryCategory ?? "∅") (\(meta.primarySubcategories.joined(separator: ", "))) / \(meta.secondaryCategory ?? "∅")") }
        else { try await update("categories", "/v1/appInfos/\(appInfoID)", type: "appInfos", id: appInfoID, relationships: rels, lines: lines) }
    }

    func syncAgeRating() async throws {
        guard !meta.ageRating.isEmpty else { note("no ageRating answers in the metadata"); return }
        guard let res = try await api.getOptional("/v1/appInfos/\(appInfoID)/ageRatingDeclaration"), let decl = dataOne(res) else {
            throw ToolError("the app info has no age rating declaration to edit (UNCONFIRMED: Apple creates it with the app record)")
        }
        let (patch, lines) = diffLines(attrs(decl), meta.ageRating)
        if patch.isEmpty { same("age rating declaration (\(meta.ageRating.count) answers)") }
        else { try await update("age rating declaration", "/v1/ageRatingDeclarations/\(idOf(decl))", type: "ageRatingDeclarations", id: idOf(decl), attributes: patch, lines: lines) }
    }

    func syncVersionAttributes() async throws {
        var desired: JSON = [:]
        if let holder = meta.copyrightHolder {
            let year = meta.earliestReleaseDate.flatMap { parseDate($0) }.map { Calendar(identifier: .gregorian).component(.year, from: $0) }
                ?? Calendar(identifier: .gregorian).component(.year, from: Date())
            desired["copyright"] = holder.range(of: "^(©\\s*)?[0-9]{4}", options: .regularExpression) != nil ? holder : "\(year) \(holder)"
        } else if let inherited = meta.inheritedCopyright {
            desired["copyright"] = inherited
            note("copyright: inherited from \(inheritFrom ?? "?") (value hidden)")
        } else { note("copyright skipped: copyrightHolder not set and nothing inherited") }
        if let t = meta.releaseType {
            desired["releaseType"] = t
            if t == "SCHEDULED", let d = meta.earliestReleaseDate { desired["earliestReleaseDate"] = d }
        }
        guard !desired.isEmpty else { note("nothing to set"); return }
        let (patch, lines) = diffLines(versionAttrs, desired)
        if patch.isEmpty { same("version copyright/release (\(short(desired["releaseType"])) \(short(desired["earliestReleaseDate"])))") }
        else { try await update("version \(versionAttrs["versionString"] as? String ?? "") attributes", "/v1/appStoreVersions/\(versionID)", type: "appStoreVersions", id: versionID, attributes: patch, lines: lines) }
    }

    func loadVersionLocalizations() async throws {
        let (existing, _) = try await api.getAll("/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations", [("limit", "50")])
        for e in existing { if let l = attrs(e)["locale"] as? String { versionLocIDs[l] = idOf(e) } }
        versionLocCache = existing
    }
    var versionLocCache: [JSON] = []

    func syncVersionLocalizations() async throws {
        // Re-read first: creating an app-info localization earlier in the same push can make App Store Connect create
        // the matching version localization too, and a stale cache then POSTs a duplicate (HTTP 409).
        try await loadVersionLocalizations()
        let keys = ["description", "keywords", "promotionalText", "supportUrl", "marketingUrl"]
        for locale in meta.locales {
            guard let t = meta.text[locale] else { continue }
            var desired: JSON = [:]
            for k in keys { if let v = t.fields[k] { desired[k] = v } }
            let inherited = t.inherited.intersection(keys).sorted()
            let tag = inherited.isEmpty ? "" : " (\(inherited.joined(separator: ", ")) inherited from \(meta.primaryLocale))"
            if let cur = versionLocCache.first(where: { attrs($0)["locale"] as? String == locale }) {
                let (patch, lines) = diffLines(attrs(cur), desired)
                if patch.isEmpty { same("\(locale) description/keywords/promo/URLs") }
                else { try await update("\(locale) version localization\(tag)", "/v1/appStoreVersionLocalizations/\(idOf(cur))", type: "appStoreVersionLocalizations", id: idOf(cur), attributes: patch, lines: lines) }
            } else {
                var a = desired; a["locale"] = locale
                let created = try await create("\(locale) version localization\(tag)", "/v1/appStoreVersionLocalizations", type: "appStoreVersionLocalizations",
                                               attributes: a, relationships: ["appStoreVersion": ref("appStoreVersions", versionID)],
                                               detail: desired.keys.sorted().map { "\($0): \(short(desired[$0]))" })
                versionLocIDs[locale] = idOf(created)
            }
        }
    }

    func syncReview() async throws {
        var desired: JSON = [:]
        if let n = meta.reviewNotes { desired["notes"] = n }
        if let d = meta.demoAccountRequired { desired["demoAccountRequired"] = d }
        for (k, v) in meta.contact { desired[k] = v }
        guard !desired.isEmpty else { note("no review details in the metadata"); return }
        let missing = ["contactFirstName", "contactLastName", "contactPhone", "contactEmail"].filter { meta.contact[$0] == nil }
        if !missing.isEmpty { note("not pushed (null in the metadata and not inherited): \(missing.joined(separator: ", "))") }
        if meta.inheritedContact { note("contact name, phone and email: inherited from \(inheritFrom ?? "?") (values hidden)") }
        if meta.reviewNotes == nil { note("notes: not pushed (see the gaps at the end)") }
        let res = try await api.getOptional("/v1/appStoreVersions/\(versionID)/appStoreReviewDetail")
        if let cur = dataOne(res) {
            let (patch, lines) = diffLines(attrs(cur), desired)
            if patch.isEmpty { same("review details") }
            else { try await update("review details", "/v1/appStoreReviewDetails/\(idOf(cur))", type: "appStoreReviewDetails", id: idOf(cur), attributes: patch, lines: lines) }
        } else {
            _ = try await create("review details", "/v1/appStoreReviewDetails", type: "appStoreReviewDetails", attributes: desired,
                                 relationships: ["appStoreVersion": ref("appStoreVersions", versionID)],
                                 detail: desired.keys.sorted().map { "\($0): \(short(desired[$0]))" })
        }
    }

    // MARK: Game Center (v2 achievements: achievement → versions → localizations → image)

    static let editableGCStates: Set<String> = ["PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "REJECTED", "DEVELOPER_REJECTED"]

    func syncGameCenter() async throws {
        // 1. Game Center for the app (POST /v1/gameCenterDetails, "Enable game center for an app").
        var detailID: String
        if let res = try await api.getOptional("/v1/apps/\(appID)/gameCenterDetail"), let d = dataOne(res) {
            detailID = idOf(d)
            same("Game Center enabled for the app (detail \(detailID))")
        } else {
            detailID = idOf(try await create("Game Center detail (enables Game Center for the app)", "/v1/gameCenterDetails",
                                             type: "gameCenterDetails", relationships: ["app": ref("apps", appID)]))
        }
        // 2. Game Center on this App Store version (gameCenterAppVersions; attribute `enabled`).
        // UNCONFIRMED: that creating the gameCenterAppVersion is what ticks "Game Center" on the version page, and
        // that PATCH accepts `enabled` (it is a readable field; the create request takes only appStoreVersion).
        if !versionID.isEmpty {
            if let res = try await api.getOptional("/v1/appStoreVersions/\(versionID)/gameCenterAppVersion"), let gv = dataOne(res) {
                if (attrs(gv)["enabled"] as? NSNumber)?.boolValue == false {
                    try await update("Game Center on version", "/v1/gameCenterAppVersions/\(idOf(gv))", type: "gameCenterAppVersions", id: idOf(gv),
                                     attributes: ["enabled": true], lines: ["enabled: false → true"])
                } else { same("Game Center on the version") }
            } else {
                _ = try await create("Game Center app version (Game Center on the App Store version)", "/v1/gameCenterAppVersions",
                                     type: "gameCenterAppVersions", relationships: ["appStoreVersion": ref("appStoreVersions", versionID)])
            }
        }
        if meta.achievements.isEmpty { note("no achievements in the metadata") }
        try await syncAchievements(detailID: detailID)
        if meta.leaderboards.isEmpty { note("no leaderboards in the metadata") }
        try await syncLeaderboards(detailID: detailID)
        manual.append("Game Center: achievements and leaderboards go live with the 1.0 review submission that also holds the app version (the attach step adds them; check App Store Connect > the version > Game Center lists all \(meta.achievements.count) achievements and \(meta.leaderboards.count) leaderboards).")
    }

    func syncAchievements(detailID: String) async throws {
        guard !meta.achievements.isEmpty else { return }
        // 3. Achievements.
        let (existing, _) = try await api.getAll("/v1/gameCenterDetails/\(detailID)/gameCenterAchievementsV2", [("limit", "200")])
        var byVendor: [String: JSON] = [:]
        for e in existing { if let v = attrs(e)["vendorIdentifier"] as? String { byVendor[v] = e } }
        let wanted = Set(meta.achievements.map { $0.vendorIdentifier })
        for (vid, _) in byVendor where !wanted.contains(vid) {
            note("App Store Connect has an achievement the metadata doesn't: \(vid) (left alone)")
        }

        for a in meta.achievements {
            out("   \(a.vendorIdentifier)")
            let desired: JSON = ["referenceName": a.referenceName, "points": a.points,
                                 "showBeforeEarned": a.showBeforeEarned, "repeatable": a.repeatable]
            var achievementID: String
            var versions: [JSON] = []
            if let cur = byVendor[a.vendorIdentifier] {
                achievementID = idOf(cur)
                let (patch, lines) = diffLines(attrs(cur), desired)
                if patch.isEmpty { same("achievement attributes (\(a.points) pts)") }
                else { try await update("achievement \(a.vendorIdentifier)", "/v2/gameCenterAchievements/\(achievementID)", type: "gameCenterAchievements", id: achievementID, attributes: patch, lines: lines) }
                versions = try await api.getAll("/v2/gameCenterAchievements/\(achievementID)/versions", [("limit", "50")]).0
            } else {
                // Create with its first version inline (GameCenterAchievementV2CreateRequest: relationships.versions is
                // required; included takes GameCenterAchievementVersionV2InlineCreate). The "${…}" local ID follows
                // Apple's inline-create convention (UNCONFIRMED for this resource).
                var attrsWithID = desired
                attrsWithID["vendorIdentifier"] = a.vendorIdentifier
                let created = try await create("achievement \(a.vendorIdentifier) (\(a.points) pts, \(a.showBeforeEarned ? "visible" : "hidden") before earned)",
                                               "/v2/gameCenterAchievements", type: "gameCenterAchievements",
                                               attributes: attrsWithID,
                                               relationships: ["gameCenterDetail": ref("gameCenterDetails", detailID),
                                                               "versions": refs("gameCenterAchievementVersions", ["${version-1}"])],
                                               included: [["type": "gameCenterAchievementVersions", "id": "${version-1}"]])
                achievementID = idOf(created)
                versions = try await api.getAll("/v2/gameCenterAchievements/\(achievementID)/versions", [("limit", "50")]).0
            }

            // 4. The version to edit: the newest one, if it's still editable; otherwise a new version.
            let latest = versions.max { ((attrs($0)["version"] as? NSNumber)?.intValue ?? 0) < ((attrs($1)["version"] as? NSNumber)?.intValue ?? 0) }
            var versionIDGC: String
            var locs: [JSON] = []
            if let l = latest, Engine.editableGCStates.contains(attrs(l)["state"] as? String ?? "") {
                versionIDGC = idOf(l)
                locs = try await api.getAll("/v2/gameCenterAchievementVersions/\(versionIDGC)/localizations", [("limit", "50")]).0
            } else if let l = latest {
                // Live (or in review): only make a new version if something differs.
                let liveLocs = try await api.getAll("/v2/gameCenterAchievementVersions/\(idOf(l))/localizations", [("limit", "50")]).0
                let differs = a.localizations.contains { (locale, want) in
                    guard let cur = liveLocs.first(where: { attrs($0)["locale"] as? String == locale }) else { return true }
                    let c = attrs(cur)
                    return !isSameValue(c["name"], want.name) || !isSameValue(c["beforeEarnedDescription"], want.before)
                        || !isSameValue(c["afterEarnedDescription"], want.after)
                }
                if !differs { same("localizations (version \(attrs(l)["version"] ?? "?") is \(attrs(l)["state"] ?? "?"))"); continue }
                versionIDGC = idOf(try await create("new achievement version (v\(attrs(l)["version"] ?? "?") is \(attrs(l)["state"] ?? "?"))",
                                                    "/v2/gameCenterAchievementVersions", type: "gameCenterAchievementVersions",
                                                    relationships: ["achievement": ref("gameCenterAchievements", achievementID)]))
            } else if achievementID.hasPrefix(plannedPrefix) {
                versionIDGC = "\(plannedPrefix)v"
            } else {
                versionIDGC = idOf(try await create("achievement version", "/v2/gameCenterAchievementVersions", type: "gameCenterAchievementVersions",
                                                    relationships: ["achievement": ref("gameCenterAchievements", achievementID)]))
            }

            // 5. Localizations and their images.
            for (locale, want) in a.localizations {
                let desiredLoc: JSON = ["name": want.name, "beforeEarnedDescription": want.before, "afterEarnedDescription": want.after]
                var locID: String
                if let cur = locs.first(where: { attrs($0)["locale"] as? String == locale }) {
                    locID = idOf(cur)
                    let (patch, lines) = diffLines(attrs(cur), desiredLoc)
                    if patch.isEmpty { same("\(locale) text") }
                    else { try await update("\(locale) achievement text", "/v2/gameCenterAchievementLocalizations/\(locID)", type: "gameCenterAchievementLocalizations", id: locID, attributes: patch, lines: lines) }
                } else {
                    var a2 = desiredLoc; a2["locale"] = locale
                    locID = idOf(try await create("\(locale) achievement text\(want.inherited ? " (copied from \(meta.primaryLocale))" : "")",
                                                  "/v2/gameCenterAchievementLocalizations", type: "gameCenterAchievementLocalizations",
                                                  attributes: a2, relationships: ["version": ref("gameCenterAchievementVersions", versionIDGC)],
                                                  detail: ["name: \(short(want.name))", "before: \(short(want.before))", "after: \(short(want.after))"]))
                }
                guard let img = a.image else { note("\(locale): no badge image (run badges.swift)"); continue }
                try await syncAchievementImage(locID: locID, locale: locale, image: img, vendor: a.vendorIdentifier)
            }
        }
    }

    func syncAchievementImage(locID: String, locale: String, image: ImageFile, vendor: String) async throws {
        // File name carries a content hash, so "same name and size" means "same picture".
        let stem = vendor.replacingOccurrences(of: ".", with: "_")
        let fileName = "\(stem)-\(image.sha12).\(image.ext)"
        if let res = try await api.getOptional("/v2/gameCenterAchievementLocalizations/\(locID)/image"), let cur = dataOne(res) {
            let ca = attrs(cur)
            let state = ((ca["assetDeliveryState"] as? JSON)?["state"] as? String) ?? ""
            if ca["fileName"] as? String == fileName && (ca["fileSize"] as? NSNumber)?.intValue == image.size && state != "FAILED" {
                same("\(locale) badge \(fileName)")
                return
            }
            try await delete("\(locale) badge \(ca["fileName"] as? String ?? "?") (\(state.isEmpty ? "replaced" : state))", "/v2/gameCenterAchievementImages/\(idOf(cur))")
        }
        let reserved = try await create("\(locale) badge \(fileName) (\(image.size / 1024) KB)", "/v2/gameCenterAchievementImages",
                                        type: "gameCenterAchievementImages",
                                        attributes: ["fileName": fileName, "fileSize": image.size],
                                        relationships: ["localization": ref("gameCenterAchievementLocalizations", locID)])
        if dryRun { return }
        try await api.runUploadOperations((attrs(reserved)["uploadOperations"] as? [JSON]) ?? [], data: image.data)
        // GameCenterAchievementImageV2UpdateRequest takes `uploaded` only (no checksum).
        _ = try await api.write("PATCH", "/v2/gameCenterAchievementImages/\(idOf(reserved))",
                                ["data": ["type": "gameCenterAchievementImages", "id": idOf(reserved), "attributes": ["uploaded": true]]])
        out("       uploaded and committed")
    }

    // MARK: Game Center leaderboards (v2: leaderboard → versions → localizations; same shape as achievements)

    func syncLeaderboards(detailID: String) async throws {
        guard !meta.leaderboards.isEmpty else { return }
        let (existing, _) = try await api.getAll("/v1/gameCenterDetails/\(detailID)/gameCenterLeaderboardsV2", [("limit", "200")])
        var byVendor: [String: JSON] = [:]
        for e in existing { if let v = attrs(e)["vendorIdentifier"] as? String { byVendor[v] = e } }
        let wanted = Set(meta.leaderboards.map { $0.vendorIdentifier })
        for (vid, _) in byVendor where !wanted.contains(vid) {
            note("App Store Connect has a leaderboard the metadata doesn't: \(vid) (left alone)")
        }

        for lb in meta.leaderboards {
            let kind = lb.recurring
                ? "recurring from \(lb.attributes["recurrenceStartDate"] as? String ?? "?"), \(lb.attributes["recurrenceDuration"] as? String ?? "?"), \(lb.attributes["recurrenceRule"] as? String ?? "?")"
                : "classic"
            out("   \(lb.vendorIdentifier) (leaderboard, \(kind))")
            var leaderboardID: String
            var versions: [JSON] = []
            if let cur = byVendor[lb.vendorIdentifier] {
                leaderboardID = idOf(cur)
                let c = attrs(cur)
                if (c["recurrenceRule"] != nil && !(c["recurrenceRule"] is NSNull)) != lb.recurring {
                    note("App Store Connect has it as \(lb.recurring ? "classic" : "recurring"); the metadata says \(lb.recurring ? "recurring" : "classic"). Changing the type is tried as an update.")
                }
                let (patch, lines) = diffLines(c, lb.attributes)
                if patch.isEmpty { same("leaderboard attributes (\(lb.attributes["defaultFormatter"] ?? "?"), \(lb.attributes["scoreSortType"] ?? "?"), \(lb.attributes["submissionType"] ?? "?"))") }
                else { try await update("leaderboard \(lb.vendorIdentifier)", "/v2/gameCenterLeaderboards/\(leaderboardID)", type: "gameCenterLeaderboards", id: leaderboardID, attributes: patch, lines: lines) }
                versions = try await api.getAll("/v2/gameCenterLeaderboards/\(leaderboardID)/versions", [("limit", "50")]).0
            } else {
                // GameCenterLeaderboardV2CreateRequest: relationships.versions is required; included takes
                // GameCenterLeaderboardVersionV2InlineCreate (the same inline pattern that created Squish's achievements).
                var a = lb.attributes
                a["vendorIdentifier"] = lb.vendorIdentifier
                let created = try await create("leaderboard \(lb.vendorIdentifier) (\(kind))", "/v2/gameCenterLeaderboards", type: "gameCenterLeaderboards",
                                               attributes: a,
                                               relationships: ["gameCenterDetail": ref("gameCenterDetails", detailID),
                                                               "versions": refs("gameCenterLeaderboardVersions", ["${version-1}"])],
                                               included: [["type": "gameCenterLeaderboardVersions", "id": "${version-1}"]],
                                               detail: lb.attributes.keys.sorted().map { "\($0): \(short(lb.attributes[$0]))" })
                leaderboardID = idOf(created)
                versions = try await api.getAll("/v2/gameCenterLeaderboards/\(leaderboardID)/versions", [("limit", "50")]).0
            }

            let latest = versions.max { ((attrs($0)["version"] as? NSNumber)?.intValue ?? 0) < ((attrs($1)["version"] as? NSNumber)?.intValue ?? 0) }
            var versionIDGC: String
            var locs: [JSON] = []
            if let l = latest, Engine.editableGCStates.contains(attrs(l)["state"] as? String ?? "") {
                versionIDGC = idOf(l)
                locs = try await api.getAll("/v2/gameCenterLeaderboardVersions/\(versionIDGC)/localizations", [("limit", "50")]).0
            } else if let l = latest {
                let liveLocs = try await api.getAll("/v2/gameCenterLeaderboardVersions/\(idOf(l))/localizations", [("limit", "50")]).0
                let differs = lb.localizations.contains { (locale, want) in
                    guard let cur = liveLocs.first(where: { attrs($0)["locale"] as? String == locale }) else { return true }
                    return !diffLines(attrs(cur), want).0.isEmpty
                }
                if !differs { same("localizations (version \(attrs(l)["version"] ?? "?") is \(attrs(l)["state"] ?? "?"))"); continue }
                versionIDGC = idOf(try await create("new leaderboard version (v\(attrs(l)["version"] ?? "?") is \(attrs(l)["state"] ?? "?"))",
                                                    "/v2/gameCenterLeaderboardVersions", type: "gameCenterLeaderboardVersions",
                                                    relationships: ["leaderboard": ref("gameCenterLeaderboards", leaderboardID)]))
            } else if leaderboardID.hasPrefix(plannedPrefix) {
                versionIDGC = "\(plannedPrefix)lv"
            } else {
                versionIDGC = idOf(try await create("leaderboard version", "/v2/gameCenterLeaderboardVersions", type: "gameCenterLeaderboardVersions",
                                                    relationships: ["leaderboard": ref("gameCenterLeaderboards", leaderboardID)]))
            }

            for (locale, want) in lb.localizations {
                let copied = lb.inheritedLocales.contains(locale) ? " (copied from \(meta.primaryLocale))" : ""
                if let cur = locs.first(where: { attrs($0)["locale"] as? String == locale }) {
                    let (patch, lines) = diffLines(attrs(cur), want)
                    if patch.isEmpty { same("\(locale) name and score format") }
                    else { try await update("\(locale) leaderboard text", "/v2/gameCenterLeaderboardLocalizations/\(idOf(cur))", type: "gameCenterLeaderboardLocalizations", id: idOf(cur), attributes: patch, lines: lines) }
                } else {
                    var a2 = want; a2["locale"] = locale
                    _ = try await create("\(locale) leaderboard text\(copied)", "/v2/gameCenterLeaderboardLocalizations", type: "gameCenterLeaderboardLocalizations",
                                         attributes: a2, relationships: ["version": ref("gameCenterLeaderboardVersions", versionIDGC)],
                                         detail: want.keys.sorted().map { "\($0): \(short(want[$0]))" })
                }
            }
        }
        note("leaderboard images are optional and not pushed")
    }

    // MARK: Attach Game Center items to the 1.0 review submission
    //
    // In the versioned Game Center model (API 4.x) a first achievement or leaderboard can only be reviewed together
    // with an app version, and it is attached by adding its version to the app's review submission
    // (ReviewSubmissionItemCreateRequest: gameCenterAchievementVersion / gameCenterLeaderboardVersion). This step
    // adds them to the draft iOS submission (state READY_FOR_REVIEW, created if missing). It never adds the app
    // version and never submits: the founder picks the build, clicks Add for Review (the version joins the same
    // draft) and then Submit to App Review. UNCONFIRMED: that App Store Connect accepts Game Center items in a draft
    // before the app version is in it; if it refuses, the error is printed and the version page's Game Center
    // section does the same by hand.

    static let attachableGCStates: Set<String> = ["PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "REJECTED", "DEVELOPER_REJECTED"]

    func syncAttach() async throws {
        guard let res = try await api.getOptional("/v1/apps/\(appID)/gameCenterDetail"), let d = dataOne(res) else {
            note("Game Center isn't enabled for the app yet, so there's nothing to attach. The gamecenter step creates it; run push again afterwards.")
            if dryRun { note("after a real gamecenter step this would add \(meta.achievements.count) achievement versions and \(meta.leaderboards.count) leaderboard versions to the draft iOS review submission") }
            return
        }
        let detailID = idOf(d)
        var wanted: [(label: String, rel: String, type: String, id: String)] = []
        var notYet: [String] = []
        func collect(_ label: String, list: String, versionsPath: (String) -> String, ids: [String], rel: String, type: String) async throws {
            let (items, _) = try await api.getAll("/v1/gameCenterDetails/\(detailID)/\(list)", [("limit", "200")])
            for vid in ids {
                guard let item = items.first(where: { attrs($0)["vendorIdentifier"] as? String == vid }) else { notYet.append(vid); continue }
                let versions = try await api.getAll(versionsPath(idOf(item)), [("limit", "50")]).0
                guard let latest = versions.max(by: { ((attrs($0)["version"] as? NSNumber)?.intValue ?? 0) < ((attrs($1)["version"] as? NSNumber)?.intValue ?? 0) }) else {
                    notYet.append(vid); continue
                }
                let state = attrs(latest)["state"] as? String ?? "?"
                if Engine.attachableGCStates.contains(state) {
                    wanted.append(("\(label) \(vid) v\(attrs(latest)["version"] ?? "?")", rel, type, idOf(latest)))
                } else {
                    same("\(label) \(vid): version \(attrs(latest)["version"] ?? "?") is \(state)")
                }
            }
        }
        try await collect("achievement", list: "gameCenterAchievementsV2", versionsPath: { "/v2/gameCenterAchievements/\($0)/versions" },
                          ids: meta.achievements.map { $0.vendorIdentifier }, rel: "gameCenterAchievementVersion", type: "gameCenterAchievementVersions")
        try await collect("leaderboard", list: "gameCenterLeaderboardsV2", versionsPath: { "/v2/gameCenterLeaderboards/\($0)/versions" },
                          ids: meta.leaderboards.map { $0.vendorIdentifier }, rel: "gameCenterLeaderboardVersion", type: "gameCenterLeaderboardVersions")
        if !notYet.isEmpty {
            note("not created yet, so not attached\(dryRun ? " (a real push creates them in the gamecenter step first)" : ""): \(notYet.joined(separator: ", "))")
        }
        guard !wanted.isEmpty else { return }

        let (subs, _) = try await api.getAll("/v1/reviewSubmissions", [("filter[app]", appID), ("filter[platform]", "IOS"),
                                                                        ("filter[state]", "READY_FOR_REVIEW"), ("limit", "20")])
        var subID: String
        var have = Set<String>()
        if let s = subs.first {
            subID = idOf(s)
            let (items, _) = try await api.getAll("/v1/reviewSubmissions/\(subID)/items",
                                                  [("include", "appStoreVersion,gameCenterAchievementVersion,gameCenterLeaderboardVersion"), ("limit", "200")])
            for it in items {
                for r in ["appStoreVersion", "gameCenterAchievementVersion", "gameCenterLeaderboardVersion"] { if let id = relID(it, r) { have.insert(id) } }
            }
            note("draft iOS review submission \(subID): \(items.count) item(s)\(have.contains(versionID) ? ", including version 1.0" : "")")
        } else {
            subID = idOf(try await create("draft iOS review submission (not submitted)", "/v1/reviewSubmissions", type: "reviewSubmissions",
                                          attributes: ["platform": "IOS"], relationships: ["app": ref("apps", appID)]))
        }
        for w in wanted {
            if have.contains(w.id) { same("\(w.label) is in the review submission"); continue }
            _ = try await create("attach \(w.label) to the review submission", "/v1/reviewSubmissionItems", type: "reviewSubmissionItems",
                                 relationships: ["reviewSubmission": ref("reviewSubmissions", subID), w.rel: ref(w.type, w.id)])
        }
        manual.append("Submission: on the 1.0 page pick the build and click Add for Review (the version joins the draft that holds the Game Center items), then Submit to App Review. This tool never submits.")
    }

    // MARK: Featuring nomination (Nominations API: GET/POST /v1/nominations, PATCH /v1/nominations/{id})

    func syncNomination() async throws {
        guard let n = meta.nomination else { note("no nomination block in the metadata"); return }
        let name = n.attributes["name"] as? String ?? ""
        let found = try await nominations(api, appID: appID)
        let mine = found.first { attrs($0)["name"] as? String == name }
            ?? found.first { attrs($0)["type"] as? String == n.attributes["type"] as? String }
        for o in found where idOf(o) != idOf(mine) {
            note("other nomination for this app: \(short(attrs(o)["name"])) (\(attrs(o)["state"] as? String ?? "?"), left alone)")
        }
        if let cur = mine {
            let c = attrs(cur)
            let state = c["state"] as? String ?? "?"
            var patch: JSON = [:]
            var lines: [String] = []
            for k in n.attributes.keys.sorted() {
                let d = n.attributes[k]
                let equal = k.hasPrefix("publish") ? isSameDay(c[k], d) : isSameValue(c[k], d)
                if !equal { patch[k] = d ?? NSNull(); lines.append("\(k): \(short(c[k])) → \(short(d))") }
            }
            if n.submit && state == "DRAFT" { patch["submitted"] = true; lines.append("submitted: false → true (presses Submit)") }
            if patch.isEmpty { same("nomination \(short(name)) (\(state))"); return }
            try await update("nomination \(short(name)) (\(state))", "/v1/nominations/\(idOf(cur))", type: "nominations", id: idOf(cur), attributes: patch, lines: lines)
        } else {
            var a = n.attributes
            a["submitted"] = n.submit
            _ = try await create("nomination \(short(name)) (\(n.submit ? "submitted" : "saved as a draft"))", "/v1/nominations", type: "nominations",
                                 attributes: a, relationships: ["relatedApps": refs("apps", [appID])],
                                 detail: n.attributes.keys.sorted().map { "\($0): \(short(n.attributes[$0]))" } + ["submitted: \(n.submit)"])
        }
        if !n.submit { manual.append("Nomination: saved as a draft; App Store Connect > Featuring > Nominations > Submit (a draft isn't a nomination).") }
    }

    // MARK: Screenshots

    func syncScreenshots(_ sets: [ScreenshotSet]) async throws {
        guard !sets.isEmpty else { note("no screenshot sets with every file present"); return }
        if versionLocIDs.isEmpty { try await loadVersionLocalizations() }
        let locales = meta.locales.filter { versionLocIDs[$0] != nil }
        let missingLocales = meta.locales.filter { versionLocIDs[$0] == nil }
        if !missingLocales.isEmpty { note("no version localization yet for \(missingLocales.joined(separator: ", ")) (run the localizations step first)") }
        guard !locales.isEmpty else { return }
        let mode = (env["ASC_SCREENSHOT_API"] ?? "library").lowercased()
        if mode == "legacy" {
            try await legacyScreenshots(sets, locales: locales)
        } else {
            try await libraryScreenshots(sets, locales: locales)
        }
    }

    /// App Asset Library (API 4.5.1): upload each file once, place it on every locale, then order the group.
    func libraryScreenshots(_ sets: [ScreenshotSet], locales: [String]) async throws {
        guard let libRes = try await api.getOptional("/v1/apps/\(appID)/assetLibrary"), let lib = dataOne(libRes) else {
            throw ToolError("the app has no asset library (GET /v1/apps/{id}/assetLibrary). Retry with ASC_SCREENSHOT_API=legacy.")
        }
        let libID = idOf(lib)
        let catalog = try await RefCatalog.load(api)
        note("asset library \(libID); reference data: \(catalog.groups.count) placement groups, \(catalog.screenshotGroups.count) take APP_SCREENSHOT")
        var assetCache: [String: String] = [:]   // referenceName → image ID

        // Resolve every set to its placement group first. Sets that land in the same group (the Duo inner and outer
        // frames both go to IPHONE_DUO) must be placed as ONE ordered list: syncing them one after the other made the
        // second set delete the first set's placements.
        var groupOrder: [String] = []
        var byGroup: [String: (label: String, wanted: [(name: String, file: ImageFile)])] = [:]
        for set in sets {
            let duo = set.key.hasPrefix("duo")
            if duo && (env["ASC_DUO_SCREENSHOTS"] ?? "auto").lowercased() == "skip" {
                note("\(set.key): skipped (ASC_DUO_SCREENSHOTS=skip)")
                continue
            }
            let first = set.files[0].info
            guard let group = catalog.group(for: set.key, width: first.width, height: first.height) else {
                let msg = "\(set.key): the API's reference data has no APP_SCREENSHOT placement group for \(first.width)x\(first.height)"
                if duo {
                    note("\(msg); skipped. Upload the Duo frames by hand when App Store Connect shows the iPhone Duo slot.")
                    manual.append("Duo screenshots (\(set.key)): not offered by the API for this app yet; upload in App Store Connect when the slot appears.")
                    continue
                }
                throw ToolError("\(msg). Groups seen: \(catalog.describe())")
            }
            note("\(set.key) → placement group \(group) (\(catalog.groups[group] ?? "?"))")
            for f in set.files.dropFirst() where f.info.width != first.width || f.info.height != first.height {
                throw ToolError("\(set.key): \(f.path) is \(f.info.width)x\(f.info.height), the set's first frame is \(first.width)x\(first.height)")
            }
            let names: [(name: String, file: ImageFile)] = set.files.enumerated().map { (i, f) in
                (String(format: "brim %@ %02d %@", set.key, i + 1, f.sha12), f)
            }
            if var existing = byGroup[group] {
                existing.label += "+\(set.key)"
                existing.wanted += names
                byGroup[group] = existing
            } else {
                groupOrder.append(group)
                byGroup[group] = (set.key, names)
            }
        }

        for group in groupOrder {
            guard let entry = byGroup[group] else { continue }
            if entry.wanted.count > 10 {
                throw ToolError("\(entry.label): \(entry.wanted.count) screenshots share placement group \(group); App Store Connect allows 10")
            }
            let set = (key: entry.label, files: entry.wanted.map { $0.file })
            let wanted = entry.wanted

            for locale in locales {
                guard let locID = versionLocIDs[locale] else { continue }
                let (placements, included) = try await api.getAll("/v1/appStoreVersionLocalizations/\(locID)/placements",
                    [("filter[placementType]", "APP_SCREENSHOT"), ("filter[placementGroup]", group), ("sort", "placementGroupPosition"),
                     ("include", "image"), ("fields[appAssetLibraryImages]", "referenceName,state"), ("limit", "50")])
                var imageNames: [String: String] = [:]
                for inc in included where inc["type"] as? String == "appAssetLibraryImages" {
                    imageNames[idOf(inc)] = attrs(inc)["referenceName"] as? String ?? ""
                }
                let current: [(placement: String, name: String)] = placements.map { p in
                    (idOf(p), relID(p, "image").flatMap { imageNames[$0] } ?? "")
                }
                if current.map({ $0.name }) == wanted.map({ $0.name }) {
                    same("\(locale) \(set.key): \(wanted.count) screenshots in order")
                    continue
                }
                // Keep placements whose asset is wanted (first occurrence), delete the rest.
                var keep: [String: String] = [:]   // name → placement ID
                for c in current {
                    if wanted.contains(where: { $0.name == c.name }) && keep[c.name] == nil { keep[c.name] = c.placement }
                    else { try await delete("\(locale) \(set.key) placement \(c.name.isEmpty ? c.placement : c.name)", "/v1/appAssetLibraryPlacements/\(c.placement)") }
                }
                var ordered: [String] = []
                for w in wanted {
                    if let p = keep[w.name] { ordered.append(p); continue }
                    let imageID = try await ensureLibraryImage(libID: libID, name: w.name, file: w.file, cache: &assetCache)
                    let placement = try await create("\(locale) \(set.key) #\(ordered.count + 1) ← \(w.file.path)", "/v1/appAssetLibraryPlacements",
                                                     type: "appAssetLibraryPlacements",
                                                     attributes: ["placementType": "APP_SCREENSHOT", "placementGroup": group],
                                                     relationships: ["image": ref("appAssetLibraryImages", imageID),
                                                                     "appStoreVersionLocalization": ref("appStoreVersionLocalizations", locID)])
                    ordered.append(idOf(placement))
                }
                _ = try await create("\(locale) \(set.key) order (\(ordered.count))", "/v1/appAssetLibraryPlacementOrderingRequests",
                                     type: "appAssetLibraryPlacementOrderingRequests", attributes: ["placementGroup": group],
                                     relationships: ["orderedPlacements": refs("appAssetLibraryPlacements", ordered),
                                                     "appStoreVersionLocalization": ref("appStoreVersionLocalizations", locID)])
            }
        }
    }

    func ensureLibraryImage(libID: String, name: String, file: ImageFile, category: String = "APP_SCREENSHOTS_AND_PREVIEWS",
                            cache: inout [String: String]) async throws -> String {
        if let id = cache[name] { return id }
        let (found, _) = try await api.getAll("/v1/appAssetLibraries/\(libID)/images", [("filter[referenceName]", name), ("limit", "20")])
        let usable = found.first { ["UPLOAD_COMPLETE", "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW",
                                    "IN_REVIEW", "ACCEPTED", "APPROVED"].contains(attrs($0)["state"] as? String ?? "") }
        if let u = usable {
            note("reusing library image \(name) (\(attrs(u)["state"] as? String ?? "?"))")
            cache[name] = idOf(u)
            if !dryRun { try await waitForLibraryImage(idOf(u), name: name) }
            return idOf(u)
        }
        let reserved = try await create("library image \(name) ← \(file.path) (\(file.size / 1024) KB)", "/v1/appAssetLibraryImages",
                                        type: "appAssetLibraryImages",
                                        attributes: ["fileName": file.url.lastPathComponent, "fileSize": file.size,
                                                     "category": category, "referenceName": name],
                                        relationships: ["assetLibrary": ref("appAssetLibraries", libID)])
        cache[name] = idOf(reserved)
        if dryRun { return idOf(reserved) }
        try await api.runUploadOperations((attrs(reserved)["uploadOperations"] as? [JSON]) ?? [], data: file.data)
        // Asset library commits take `uploaded` alone (no sourceFileChecksum; size is checked against fileSize).
        _ = try await api.write("PATCH", "/v1/appAssetLibraryImages/\(idOf(reserved))",
                                ["data": ["type": "appAssetLibraryImages", "id": idOf(reserved), "attributes": ["uploaded": true]]])
        try await waitForLibraryImage(idOf(reserved), name: name)
        return idOf(reserved)
    }

    func waitForLibraryImage(_ id: String, name: String) async throws {
        for _ in 0..<60 {
            let res = try await api.get("/v1/appAssetLibraryImages/\(id)")
            let a = attrs(dataOne(res))
            let state = a["state"] as? String ?? ""
            if state == "FAILED" { throw ToolError("library image \(name) failed processing: \(short(a["stateDetails"]))") }
            if !["AWAITING_UPLOAD", "UPLOAD_COMPLETE"].contains(state) {
                out("       processed (\(state), spec \(a["specId"] as? String ?? "?"))")
                return
            }
            try await Task.sleep(nanoseconds: 4_000_000_000)
        }
        throw ToolError("library image \(name) still processing after 4 minutes; re-run push later (it resumes)")
    }

    /// Deprecated set-based flow (appScreenshotSets / appScreenshots): reserve, PUT the parts, commit with an MD5
    /// sourceFileChecksum, then order the set. Kept as a fallback (ASC_SCREENSHOT_API=legacy).
    func legacyScreenshots(_ sets: [ScreenshotSet], locales: [String]) async throws {
        for set in sets {
            var displayType = set.key
            if set.key == "duoInner" || set.key == "duoOuter" {
                let envName = set.key == "duoInner" ? "ASC_LEGACY_DUO_INNER_DISPLAY_TYPE" : "ASC_LEGACY_DUO_OUTER_DISPLAY_TYPE"
                guard let t = env[envName], !t.isEmpty else {
                    note("\(set.key): skipped. ScreenshotDisplayType has no iPhone Duo case; set \(envName) if Apple adds one.")
                    continue
                }
                displayType = t
            }
            let wanted = set.files.enumerated().map { (i, f) in (name: String(format: "brim-%@-%02d-%@.%@", set.key, i + 1, f.sha12, f.ext), file: f) }
            for locale in locales {
                guard let locID = versionLocIDs[locale] else { continue }
                let (existingSets, _) = try await api.getAll("/v1/appStoreVersionLocalizations/\(locID)/appScreenshotSets",
                                                             [("filter[screenshotDisplayType]", displayType)])
                var setID: String
                var shots: [JSON] = []
                if let s = existingSets.first {
                    setID = idOf(s)
                    shots = try await api.getAll("/v1/appScreenshotSets/\(setID)/appScreenshots", [("limit", "50")]).0
                } else {
                    setID = idOf(try await create("\(locale) screenshot set \(displayType)", "/v1/appScreenshotSets", type: "appScreenshotSets",
                                                  attributes: ["screenshotDisplayType": displayType],
                                                  relationships: ["appStoreVersionLocalization": ref("appStoreVersionLocalizations", locID)]))
                }
                let current = shots.map { (id: idOf($0), name: attrs($0)["fileName"] as? String ?? "",
                                           state: ((attrs($0)["assetDeliveryState"] as? JSON)?["state"] as? String) ?? "") }
                if current.map({ $0.name }) == wanted.map({ $0.name }) && !current.contains(where: { $0.state == "FAILED" }) {
                    same("\(locale) \(displayType): \(wanted.count) screenshots in order")
                    continue
                }
                var keep: [String: String] = [:]
                for c in current {
                    if wanted.contains(where: { $0.name == c.name }) && keep[c.name] == nil && c.state != "FAILED" { keep[c.name] = c.id }
                    else { try await delete("\(locale) \(displayType) screenshot \(c.name)", "/v1/appScreenshots/\(c.id)") }
                }
                var ordered: [String] = []
                for w in wanted {
                    if let id = keep[w.name] { ordered.append(id); continue }
                    let r = try await create("\(locale) \(displayType) #\(ordered.count + 1) \(w.name) ← \(w.file.path)", "/v1/appScreenshots",
                                             type: "appScreenshots", attributes: ["fileName": w.name, "fileSize": w.file.size],
                                             relationships: ["appScreenshotSet": ref("appScreenshotSets", setID)])
                    ordered.append(idOf(r))
                    if dryRun { continue }
                    try await api.runUploadOperations((attrs(r)["uploadOperations"] as? [JSON]) ?? [], data: w.file.data)
                    _ = try await api.write("PATCH", "/v1/appScreenshots/\(idOf(r))",
                                            ["data": ["type": "appScreenshots", "id": idOf(r),
                                                      "attributes": ["uploaded": true, "sourceFileChecksum": md5Hex(w.file.data)]]])
                }
                try await relink("\(locale) \(displayType) order", "/v1/appScreenshotSets/\(setID)/relationships/appScreenshots",
                                 refs("appScreenshots", ordered), lines: ordered.enumerated().map { "#\($0.offset + 1) \($0.element)" })
            }
        }
    }

    // MARK: Price

    func syncPrice() async throws {
        guard let territory = meta.priceTerritory, let price = meta.customerPrice else { note("no price in the metadata"); return }
        let manualSteps = """
        Set the price by hand: App Store Connect > your app > Pricing and Availability > Price Schedule > Add Pricing:
               base country \(territory), price \(price), start Today, no end date; let Apple set the other countries
               (equalised). Then Availability: all countries or regions, and pre-orders if you want them.
        """
        do {
            // The price point for this territory and amount (customerPrice is a string, e.g. "2.99").
            var pointID: String? = nil
            var next: String? = "/v1/apps/\(appID)/appPricePoints"
            var query: [(String, String)] = [("filter[territory]", territory), ("limit", "200"), ("fields[appPricePoints]", "customerPrice,proceeds,territory")]
            while let path = next, pointID == nil {
                let page = try await api.get(path, query)
                query = []
                for p in dataList(page) {
                    if let cp = attrs(p)["customerPrice"] as? String, Double(cp) == Double(price) { pointID = idOf(p); break }
                }
                next = (page["links"] as? JSON)?["next"] as? String
            }
            guard let point = pointID else { throw ToolError("no \(territory) price point at \(price)") }

            // Current schedule, if any.
            if let res = try await api.getOptional("/v1/apps/\(appID)/appPriceSchedule"), let sched = dataOne(res) {
                let sid = idOf(sched)
                let base = idOf(dataOne(try await api.getOptional("/v1/appPriceSchedules/\(sid)/baseTerritory")))
                // A new app reports a schedule whose manualPrices 404 until a first price is set: treat that as none.
                let (prices, included): ([JSON], [JSON])
                if base.isEmpty {
                    (prices, included) = ([], [])
                } else {
                    (prices, included) = (try? await api.getAll("/v1/appPriceSchedules/\(sid)/manualPrices",
                                                                [("include", "appPricePoint"), ("filter[territory]", territory), ("limit", "50")])) ?? ([], [])
                }
                let now = Date()
                let currentPoint = prices.first { p in
                    let a = attrs(p)
                    let start = parseDate(a["startDate"] as? String) ?? .distantPast
                    let end = parseDate(a["endDate"] as? String) ?? .distantFuture
                    return start <= now && now < end
                }.flatMap { relID($0, "appPricePoint") }
                let currentPrice = included.first { idOf($0) == currentPoint }.flatMap { attrs($0)["customerPrice"] as? String }
                if base == territory && (currentPoint == point || (currentPrice.map { Double($0) == Double(price) } ?? false)) {
                    same("price \(territory) \(price) (base territory \(base))")
                    return
                }
                note("current: base \(base.isEmpty ? "∅" : base), price \(currentPrice ?? "∅")")
            }
            _ = try await create("price schedule: base \(territory), \(price) from today, other territories equalised by Apple",
                                 "/v1/appPriceSchedules", type: "appPriceSchedules",
                                 relationships: ["app": ref("apps", appID),
                                                 "baseTerritory": ref("territories", territory),
                                                 "manualPrices": refs("appPrices", ["${price-1}"])],
                                 included: [["type": "appPrices", "id": "${price-1}", "attributes": ["startDate": NSNull()],
                                             "relationships": ["appPricePoint": ref("appPricePoints", point)]]])
        } catch {
            out("   ! price not set automatically: \(error)")
            manual.append(manualSteps)
        }
        do {
            try await syncAvailability()
        } catch {
            out("   ! availability not set automatically: \(error)")
            manual.append("Availability: App Store Connect > Pricing and Availability > Availability: every country or region except "
                          + "\(excludedTerritories.sorted().joined(separator: ", ")), and 'make available in new countries' \(meta.availableInNewTerritories ? "on" : "off").")
        }
        // COMPLIANCE.md #16. The public API has no attribute for these two app-level switches (checked 26 Oct 2026:
        // App, AppAvailabilityV2 and AppStoreVersion attributes), so they stay manual.
        manual.append("Mac and Vision Pro: App Store Connect > the app > Pricing and Availability > 'iPhone and iPad Apps on Apple Silicon Macs': untick 'Make this app available'; then 'iPhone and iPad Apps on Apple Vision Pro': untick 'Make this app available on Apple Vision Pro'. Save. Not in the API.")
    }

    /// Every territory except `availability.excludedTerritories` in the metadata (Brim: CHN and VNM, COMPLIANCE.md
    /// #15: no regional game licence). ASC_EXCLUDED_TERRITORIES="CHN,…" overrides it.
    var excludedTerritories: Set<String> {
        guard let raw = ProcessInfo.processInfo.environment["ASC_EXCLUDED_TERRITORIES"], !raw.isEmpty else { return meta.excludedTerritories }
        return Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty })
    }

    func syncAvailability() async throws {
        let excluded = excludedTerritories
        let unknown = excluded.subtracting(try await api.getAll("/v1/territories", [("limit", "200")]).0.map { idOf($0) })
        if !unknown.isEmpty { throw ToolError("excluded territories not in GET /v1/territories: \(unknown.sorted().joined(separator: ", "))") }
        let (territories, _) = try await api.getAll("/v1/territories", [("limit", "200")])
        let codes = territories.map { idOf($0) }.filter { !$0.isEmpty }.sorted()
        guard !codes.isEmpty else { throw ToolError("GET /v1/territories returned none") }
        if let res = try await api.getOptional("/v1/apps/\(appID)/appAvailabilityV2"), let av = dataOne(res) {
            let avID = idOf(av)
            let (current, _) = try await api.getAll("/v2/appAvailabilities/\(avID)/territoryAvailabilities",
                                                    [("include", "territory"), ("limit", "200")])
            var changed = 0
            for ta in current {
                guard let code = relID(ta, "territory") else { continue }
                let want = !excluded.contains(code)
                if (attrs(ta)["available"] as? Bool) != want {
                    try await update("availability \(code) → \(want ? "available" : "not available")",
                                     "/v1/territoryAvailabilities/\(idOf(ta))", type: "territoryAvailabilities", id: idOf(ta),
                                     attributes: ["available": want], lines: [])
                    changed += 1
                }
            }
            if changed == 0 { same("availability: \(current.count) territories, all but \(excluded.sorted().joined(separator: ", "))") }
            if (attrs(av)["availableInNewTerritories"] as? Bool) != meta.availableInNewTerritories {
                manual.append("Availability: \(meta.availableInNewTerritories ? "tick" : "untick") 'make available in new countries or regions' in Pricing and Availability.")
            }
            return
        }
        let included: [JSON] = codes.map { code in
            ["type": "territoryAvailabilities", "id": "${ta-\(code)}",
             "attributes": ["available": !excluded.contains(code)],
             "relationships": ["territory": ref("territories", code)]]
        }
        _ = try await create("availability: \(codes.count - codes.filter { excluded.contains($0) }.count) of \(codes.count) territories "
                             + "(all but \(excluded.sorted().joined(separator: ", "))), new territories \(meta.availableInNewTerritories ? "on" : "off")",
                             "/v2/appAvailabilities", type: "appAvailabilities",
                             attributes: ["availableInNewTerritories": meta.availableInNewTerritories],
                             relationships: ["app": ref("apps", appID),
                                             "territoryAvailabilities": refs("territoryAvailabilities", codes.map { "${ta-\($0)}" })],
                             included: included)
    }

    // MARK: Accessibility Nutrition Labels (optional "accessibility" block)

    func syncAccessibility() async throws {
        guard var desired = meta.accessibility else {
            note("no accessibility block in the metadata; the labels go on by hand on launch day (see README)")
            return
        }
        let family = desired.removeValue(forKey: "deviceFamily") as? String ?? "IPHONE"
        let publish = (desired.removeValue(forKey: "publish") as? NSNumber)?.boolValue ?? false
        let (decls, _) = try await api.getAll("/v1/apps/\(appID)/accessibilityDeclarations", [("limit", "50")])
        if let cur = decls.first(where: { attrs($0)["deviceFamily"] as? String == family }) {
            var (patch, lines) = diffLines(attrs(cur), desired)
            if publish && (attrs(cur)["state"] as? String) != "PUBLISHED" { patch["publish"] = true; lines.append("publish: → true") }
            if patch.isEmpty { same("accessibility declaration \(family)") }
            else { try await update("accessibility declaration \(family)", "/v1/accessibilityDeclarations/\(idOf(cur))", type: "accessibilityDeclarations", id: idOf(cur), attributes: patch, lines: lines) }
        } else {
            var a = desired; a["deviceFamily"] = family
            let created = try await create("accessibility declaration \(family)", "/v1/accessibilityDeclarations", type: "accessibilityDeclarations",
                                           attributes: a, relationships: ["app": ref("apps", appID)],
                                           detail: desired.keys.sorted().map { "\($0): \(short(desired[$0]))" })
            if publish {
                try await update("publish accessibility declaration \(family)", "/v1/accessibilityDeclarations/\(idOf(created))", type: "accessibilityDeclarations",
                                 id: idOf(created), attributes: ["publish": true], lines: ["publish: → true"])
            }
        }
    }
}

// MARK: - Creative assets (the placements step)

extension Engine {
    /// Product page header and search results art (App Asset Library, API 4.5): upload each file once as a
    /// CREATIVE_ASSETS image, then give every version localization one placement of each type per placement group
    /// that takes its size. Placements can't be edited, so a changed file means delete + create. Idempotent: a
    /// placement whose image has the same content-addressed reference name is left alone. The art then goes to App
    /// Review with the version (placements follow their parent's review state).
    func syncPlacements(_ files: [PlacementFile]) async throws {
        guard !files.isEmpty else { note("no header or search art to place (see the gaps below); App Store Connect's are left as they are"); return }
        if versionLocIDs.isEmpty { try await loadVersionLocalizations() }
        let locales = meta.locales.filter { versionLocIDs[$0] != nil }
        guard !locales.isEmpty else { note("no version localizations yet (run the localizations step first)"); return }
        guard let libRes = try await api.getOptional("/v1/apps/\(appID)/assetLibrary"), let lib = dataOne(libRes) else {
            throw ToolError("the app has no asset library (GET /v1/apps/{id}/assetLibrary); upload the art by hand (docs/appstore/header-search.md)")
        }
        let libID = idOf(lib)
        let catalog = try await RefCatalog.load(api)
        var assetCache: [String: String] = [:]
        for pf in files {
            let info = pf.file.info
            let fileName = pf.file.url.lastPathComponent
            guard let type = catalog.placementType(pf.spec.typeID, containing: pf.spec.typeWord) else {
                note("\(pf.spec.label): the API's reference data offers no \(pf.spec.typeID) placement type; skipped")
                manual.append("\(pf.spec.label): not offered by the API for this app yet; upload \(fileName) in App Store Connect (docs/appstore/header-search.md).")
                continue
            }
            if !catalog.versionTypes.isEmpty && !catalog.versionTypes.contains(type) {
                note("\(type) is not listed under APP_STORE_VERSIONS in the reference data; trying anyway")
            }
            let category = catalog.category(for: type)
            let groups = catalog.groups(forType: type, width: info.width, height: info.height)
            if catalog.hasGroups(type) && groups.isEmpty {
                throw ToolError("\(pf.spec.label): no \(type) placement group takes \(info.width)x\(info.height). Groups: \(catalog.describe(type))")
            }
            let targets: [String?] = groups.isEmpty ? [nil] : groups.map { Optional($0) }
            note("\(pf.spec.label) → \(type), \(groups.isEmpty ? "no placement group in the reference data" : "group(s) \(groups.joined(separator: ", "))"), category \(category)")
            let name = "brim \(pf.spec.key) \(pf.file.sha12)"
            for locale in locales {
                guard let locID = versionLocIDs[locale] else { continue }
                for group in targets {
                    var query: [(String, String)] = [("filter[placementType]", type), ("include", "image"),
                                                     ("fields[appAssetLibraryImages]", "referenceName,state"), ("limit", "50")]
                    if let g = group { query.append(("filter[placementGroup]", g)) }
                    let label = "\(locale) \(pf.spec.key)\(group.map { " [\($0)]" } ?? "")"
                    var current: [(placement: String, name: String)] = []
                    if !locID.hasPrefix(plannedPrefix) {
                        let (placements, included) = try await api.getAll("/v1/appStoreVersionLocalizations/\(locID)/placements", query)
                        var imageNames: [String: String] = [:]
                        for inc in included where inc["type"] as? String == "appAssetLibraryImages" {
                            imageNames[idOf(inc)] = attrs(inc)["referenceName"] as? String ?? ""
                        }
                        current = placements.map { p in (idOf(p), relID(p, "image").flatMap { imageNames[$0] } ?? "") }
                    }
                    if current.count == 1 && current[0].name == name {
                        same("\(label): \(fileName)")
                        continue
                    }
                    for c in current {
                        try await delete("\(label) placement \(c.name.isEmpty ? c.placement : c.name)", "/v1/appAssetLibraryPlacements/\(c.placement)")
                    }
                    let imageID = try await ensureLibraryImage(libID: libID, name: name, file: pf.file, category: category, cache: &assetCache)
                    var attributes: JSON = ["placementType": type]
                    if let g = group { attributes["placementGroup"] = g }
                    _ = try await create("\(label) ← \(fileName) (\(info.width)x\(info.height), \(pf.file.size / 1024) KB)",
                                         "/v1/appAssetLibraryPlacements", type: "appAssetLibraryPlacements", attributes: attributes,
                                         relationships: ["image": ref("appAssetLibraryImages", imageID),
                                                         "appStoreVersionLocalization": ref("appStoreVersionLocalizations", locID)])
                }
            }
        }
        manual.append("Header and search art: check both in App Store Connect's product page preview (the iPhone header loses ~8 % per side); they go to App Review with the version.")
    }
}

// MARK: - Asset library reference data

struct RefCatalog {
    var groups: [String: String] = [:]                 // placementProfileGroupId → displayClassId
    var specs: [String: (Int, Int, Int, Int)] = [:]    // specId → minW, maxW, minH, maxH
    var screenshotGroups: [String: [String]] = [:]     // placementGroupId → spec IDs, for APP_SCREENSHOT
    var typeGroups: [String: [String: [String]]] = [:]  // placementTypeId → placementGroupId → spec IDs (every type)
    var typeCategories: [String: [String]] = [:]       // placementTypeId → acceptsAssetCategories
    var versionTypes: Set<String> = []                 // types APP_STORE_VERSIONS lists (field names UNCONFIRMED)

    static func load(_ api: ASC) async throws -> RefCatalog {
        let res = try await api.get("/v1/appAssetLibraryRefData", [("fields[appAssetLibraryRefData]", "features,placementProfileGroups,placementTypes,imageSpecs")])
        var c = RefCatalog()
        for datum in dataList(res) {
            let a = attrs(datum)
            for g in (a["placementProfileGroups"] as? [JSON]) ?? [] {
                if let id = g["placementProfileGroupId"] as? String { c.groups[id] = g["displayClassId"] as? String ?? "" }
            }
            for s in (a["imageSpecs"] as? [JSON]) ?? [] {
                guard let id = s["specId"] as? String, let d = s["dimensions"] as? JSON else { continue }
                func n(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? -1 }
                c.specs[id] = (n("minWidth"), n("maxWidth"), n("minHeight"), n("maxHeight"))
            }
            for t in (a["placementTypes"] as? [JSON]) ?? [] {
                guard let tid = t["placementTypeId"] as? String else { continue }
                c.typeCategories[tid] = (t["acceptsAssetCategories"] as? [String]) ?? []
                var groups = c.typeGroups[tid] ?? [:]
                for m in (t["specMappings"] as? [JSON]) ?? [] {
                    guard let g = m["placementGroupId"] as? String else { continue }
                    let specs = (m["specs"] as? [String]) ?? []
                    groups[g, default: []] += specs
                    if tid == "APP_SCREENSHOT" { c.screenshotGroups[g, default: []] += specs }
                }
                c.typeGroups[tid] = groups
            }
            for f in (a["features"] as? [JSON]) ?? [] {
                let fid = (f["featureId"] ?? f["feature"] ?? f["id"]) as? String ?? ""
                guard fid == "APP_STORE_VERSIONS" else { continue }
                for pol in (f["placementPolicies"] as? [JSON]) ?? [] {
                    if let t = (pol["placementTypeId"] ?? pol["placementType"]) as? String { c.versionTypes.insert(t) }
                }
            }
        }
        guard !c.screenshotGroups.isEmpty else { throw ToolError("the asset library reference data lists no APP_SCREENSHOT groups") }
        return c
    }

    /// The APP_SCREENSHOT group whose specs accept this exact size, preferring the display class for the key:
    /// APP_IPHONE_67 → IPHONE_DYNAMIC_ISLAND_LARGE_DISPLAY, APP_IPHONE_61 → IPHONE_DYNAMIC_ISLAND_MEDIUM_DISPLAY,
    /// duoInner/duoOuter → IPHONE_DUO (AppAssetLibraryDisplayClass, added in API 4.5.1). Group IDs are read at run
    /// time, as Apple asks; none are hard-coded.
    func group(for key: String, width: Int, height: Int) -> String? {
        let preferred: [String]
        switch key {
        case "APP_IPHONE_67": preferred = ["IPHONE_DYNAMIC_ISLAND_LARGE_DISPLAY", "IPHONE_FACE_ID_LARGE_DISPLAY"]
        case "APP_IPHONE_61": preferred = ["IPHONE_DYNAMIC_ISLAND_MEDIUM_DISPLAY", "IPHONE_FACE_ID_MEDIUM_DISPLAY"]
        default: preferred = ["IPHONE_DUO"]
        }
        func fits(_ g: String) -> Bool {
            (screenshotGroups[g] ?? []).contains { id in
                guard let s = specs[id] else { return false }
                return s.0 <= width && width <= s.1 && s.2 <= height && height <= s.3
            }
        }
        let candidates = screenshotGroups.keys.filter(fits).sorted()
        // iMessage and other non-app-screenshot groups never appear under APP_SCREENSHOT, but stay on iPhone classes.
        for cls in preferred {
            if let g = candidates.first(where: { groups[$0] == cls }) { return g }
        }
        if key.hasPrefix("duo") { return nil }
        return candidates.first { (groups[$0] ?? "").hasPrefix("IPHONE") && groups[$0] != "IPHONE_DUO" }
    }

    func describe() -> String {
        screenshotGroups.keys.sorted().map { "\($0) (\(groups[$0] ?? "?"))" }.joined(separator: ", ")
    }

    /// The placement type for a creative asset: `preferred` if the reference data has it, else the only type whose ID
    /// contains `word` (e.g. HEADER, SEARCH).
    func placementType(_ preferred: String, containing word: String) -> String? {
        let all = Set(typeGroups.keys).union(typeCategories.keys)
        if all.contains(preferred) { return preferred }
        let matches = all.filter { $0.contains(word) && !$0.contains("EVENT") }.sorted()
        return matches.count == 1 ? matches[0] : nil
    }

    func hasGroups(_ type: String) -> Bool { !(typeGroups[type] ?? [:]).isEmpty }

    /// The groups of `type` with a spec that takes this exact size (sorted; all of them get a placement).
    func groups(forType type: String, width: Int, height: Int) -> [String] {
        (typeGroups[type] ?? [:]).filter { _, ids in
            ids.contains { id in
                guard let s = specs[id] else { return false }
                return s.0 <= width && width <= s.1 && s.2 <= height && height <= s.3
            }
        }.keys.sorted()
    }

    /// The asset category a type accepts (CREATIVE_ASSETS for the creative placements, per Apple's docs).
    func category(for type: String) -> String {
        let accepted = typeCategories[type] ?? []
        return accepted.contains("CREATIVE_ASSETS") || accepted.isEmpty ? "CREATIVE_ASSETS" : accepted[0]
    }

    func describe(_ type: String) -> String {
        (typeGroups[type] ?? [:]).keys.sorted().map { "\($0) (\(groups[$0] ?? "?"))" }.joined(separator: ", ")
    }
}

// MARK: - Commands

func printValidation(_ v: Validation, steps: Set<String>) {
    for w in v.warnings { out("  warning: \(w)") }
    for b in v.blockers where b.step == "core" || steps.contains(b.step) { out("  blocked [\(b.step)]: \(b.msg)") }
    for e in v.errors where e.step == "core" || steps.contains(e.step) { out("  ERROR [\(e.step)]: \(e.msg)") }
}

let manualAlways = [
    "App Privacy: App Store Connect > your app > App Privacy > Get Started > \"Data Not Collected\" > Publish (no public API).",
    "Agreements, tax and banking: Business > Paid Apps agreement, tax forms and bank account must be Active before a paid app can sell (already Active for Squish; check).",
    "Small Business Program: account-level, already enrolled for Squish; check it shows Active. Not an API.",
    "Family Sharing: App Information > Family Sharing on (permanent once enabled). Not in the API.",
    "Accessibility Nutrition Labels: on launch day, only the labels accessibility.md marks as passed (runbook §6).",
    "The build: TestFlight workflow, then pick it on the 1.0 version page, Add for Review, Submit to App Review.",
]

// MARK: - Inherited personal fields (--inherit-from)

/// Reads the copyright line and the App Review contact from another app on the same account (Squish) into memory.
/// Every value is registered with addSecret() before anything else can print it. Nothing is written to disk.
func inheritPersonalFields(_ api: ASC, into m: inout Metadata, _ v: Validation) async throws -> String {
    guard let from = inheritFrom else { return "" }
    let res = try await api.get("/v1/apps", [("filter[bundleId]", from), ("fields[apps]", "name,bundleId")])
    guard let app = dataList(res).first(where: { attrs($0)["bundleId"] as? String == from }) else {
        throw ToolError("--inherit-from \(from): no app with that bundle ID is visible to this key")
    }
    let (versions, _) = try await api.getAll("/v1/apps/\(idOf(app))/appStoreVersions",
                                             [("filter[platform]", "IOS"), ("limit", "20"),
                                              ("fields[appStoreVersions]", "versionString,copyright,createdDate,appVersionState")])
    // Newest first.
    let sorted = versions.sorted { (attrs($0)["createdDate"] as? String ?? "") > (attrs($1)["createdDate"] as? String ?? "") }
    var parts: [String] = []
    if m.copyrightHolder == nil {
        if let ver = sorted.first(where: { !((attrs($0)["copyright"] as? String) ?? "").trimmingCharacters(in: .whitespaces).isEmpty }) {
            let c = (attrs(ver)["copyright"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            addSecret(c)
            addSecret(c.replacingOccurrences(of: "^(©\\s*)?[0-9]{4}\\s*", with: "", options: .regularExpression))
            m.inheritedCopyright = c
            parts.append("copyright from version \(attrs(ver)["versionString"] as? String ?? "?")")
        } else {
            v.block("version", "--inherit-from \(from): no version of it has a copyright yet. Copyright is not pushed.")
            parts.append("no copyright found")
        }
    }
    let keys = ["contactFirstName", "contactLastName", "contactPhone", "contactEmail"]
    if keys.contains(where: { m.contact[$0] == nil }) {
        var got = 0
        for ver in sorted {
            guard let r = try await api.getOptional("/v1/appStoreVersions/\(idOf(ver))/appStoreReviewDetail"), let d = dataOne(r) else { continue }
            let a = attrs(d)
            let values = keys.compactMap { k -> (String, String)? in
                guard m.contact[k] == nil, let s = (a[k] as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
                return (k, s)
            }
            guard !values.isEmpty else { continue }
            for (k, s) in values {
                addSecret(s)
                if k == "contactPhone" { addSecret(s.replacingOccurrences(of: " ", with: "")) }
                m.contact[k] = s
                got += 1
            }
            if let f = m.contact["contactFirstName"], let l = m.contact["contactLastName"] { addSecret("\(f) \(l)") }
            m.inheritedContact = true
            parts.append("\(got) of 4 contact fields from version \(attrs(ver)["versionString"] as? String ?? "?")")
            break
        }
        for k in keys where m.contact[k] == nil {
            v.block("review", "--inherit-from \(from): \(k) not found on any of its versions. Not pushed; App Review needs it.")
        }
        if got == 0 { parts.append("no contact found") }
    }
    return "\(from) (app \(idOf(app))): \(parts.joined(separator: "; ")); values hidden"
}

/// The app's draft and submitted nominations. `filter[state]` takes one state per request (HTTP 400 for a list, run
/// 40340641267), so each is read on its own.
func nominations(_ api: ASC, appID: String) async throws -> [JSON] {
    var all: [JSON] = []
    for state in ["DRAFT", "SUBMITTED"] {
        all += try await api.getAll("/v1/nominations", [("filter[state]", state), ("filter[relatedApps]", appID), ("limit", "50")]).0
    }
    return all
}

/// Status of a public URL (check only): HTTP code and whether the page still shows a placeholder.
func probeURL(_ s: String) async -> String {
    guard let u = URL(string: s) else { return "not a URL" }
    var req = URLRequest(url: u)
    req.timeoutInterval = 20
    do {
        let (data, resp) = try await URLSession(configuration: .ephemeral).data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""
        let placeholders = ["SUPPORT_EMAIL_HERE", "TODO", "[domain]", "<SITE>"].filter { body.contains($0) }
        return "HTTP \(code)\(placeholders.isEmpty ? "" : "; page still contains \(placeholders.joined(separator: ", "))")"
    } catch {
        return "unreachable (\(error.localizedDescription))"
    }
}

func runValidate() -> Int32 {
    let v = Validation()
    out("Validating \(metadataURL.path)")
    guard let m = loadMetadata(v) else { printValidation(v, steps: Set(allSteps)); return 1 }
    out("  \(m.locales.count) locales (\(m.locales.joined(separator: ", "))), \(m.achievements.count) achievements (\(m.achievements.map { $0.points }.reduce(0, +)) pts, \(m.achievements.filter { $0.image != nil }.count) badges), \(m.leaderboards.count) leaderboards (\(m.leaderboards.map { "\($0.vendorIdentifier) \($0.recurring ? "recurring" : "classic")" }.joined(separator: ", "))), screenshot sets: \(m.screenshots.map { "\($0.key)×\($0.files.count)" }.joined(separator: ", ")), nomination: \(m.nomination.map { $0.submit ? "submit" : "draft" } ?? "none")")
    if let from = inheritFrom { out("  copyright and App Review contact: inherited from \(from) at push time") }
    let art = loadPlacements(placementsDirectory(nil), v)
    out("  header/search art: \(art.isEmpty ? "none" : art.map { "\($0.spec.key) \($0.file.info.width)x\($0.file.info.height) (\($0.file.size / 1024) KB)" }.joined(separator: ", "))")
    printValidation(v, steps: Set(allSteps))
    if v.errors.isEmpty { out("OK: no errors (\(v.blockers.count) gaps, \(v.warnings.count) warnings)"); return 0 }
    out("\(v.errors.count) error(s)")
    return 1
}

func selectedSteps() -> Set<String> {
    var s = onlySteps ?? Set(allSteps)
    s.subtract(skipSteps)
    return s
}

func runCheck() async -> Int32 {
    let v = Validation()
    let meta = loadMetadata(v)
    let bundle = meta?.bundleId.isEmpty == false ? meta!.bundleId : "com.pravegm.brim"
    do {
        let api = try ASC()
        out("key \(api.keyID) (\(api.issuerID.isEmpty ? "individual" : "team") key)")
        let apps = try await api.get("/v1/apps", [("filter[bundleId]", bundle), ("fields[apps]", "name,bundleId,primaryLocale,sku")])
        out("auth: OK")
        guard let app = dataList(apps).first(where: { attrs($0)["bundleId"] as? String == bundle }) else {
            out("app: NOT FOUND for bundle ID \(bundle). Create the app record in App Store Connect (the API can't).")
            return 1
        }
        let appID = idOf(app)
        out("app: \(attrs(app)["name"] as? String ?? "?")  id \(appID)  primary locale \(attrs(app)["primaryLocale"] as? String ?? "?")  sku \(attrs(app)["sku"] as? String ?? "?")")
        let (infos, _) = try await api.getAll("/v1/apps/\(appID)/appInfos")
        for i in infos { out("app info: \(idOf(i))  state \(attrs(i)["state"] as? String ?? attrs(i)["appStoreState"] as? String ?? "?")  age rating \(attrs(i)["appStoreAgeRating"] as? String ?? "?")") }
        let (versions, _) = try await api.getAll("/v1/apps/\(appID)/appStoreVersions",
                                                 [("filter[platform]", "IOS"), ("fields[appStoreVersions]", "versionString,appVersionState,appStoreState,releaseType,earliestReleaseDate")])
        let target = env["ASC_VERSION"] ?? "1.0"
        var editable: JSON? = nil
        for ver in versions {
            let a = attrs(ver)
            let state = a["appVersionState"] as? String ?? a["appStoreState"] as? String ?? "?"
            let isEditable = Engine.editableVersionStates.contains(state)
            if isEditable && editable == nil { editable = ver }
            out("version: \(a["versionString"] as? String ?? "?")  \(state)\(isEditable ? "  ← editable" : "")  release \(a["releaseType"] as? String ?? "?") \(a["earliestReleaseDate"] as? String ?? "")")
        }
        if let e = editable {
            let vs = attrs(e)["versionString"] as? String ?? "?"
            out(vs == target ? "editable version: \(vs) (push edits this one)" : "editable version: \(vs), but ASC_VERSION is \(target): push will refuse")
        } else {
            out("editable version: none (push creates \(target))")
        }
        let gc = try await api.getOptional("/v1/apps/\(appID)/gameCenterDetail")
        out("Game Center: \(dataOne(gc) != nil ? "enabled (detail \(idOf(dataOne(gc))))" : "not enabled yet (push enables it)")")
        if let d = dataOne(gc) {
            let (achs, _) = try await api.getAll("/v1/gameCenterDetails/\(idOf(d))/gameCenterAchievementsV2", [("limit", "200")])
            let (lbs, _) = try await api.getAll("/v1/gameCenterDetails/\(idOf(d))/gameCenterLeaderboardsV2", [("limit", "200")])
            out("  achievements in App Store Connect: \(achs.count) (\(achs.compactMap { attrs($0)["vendorIdentifier"] as? String }.sorted().joined(separator: ", ")))")
            out("  leaderboards in App Store Connect: \(lbs.count) (\(lbs.compactMap { attrs($0)["vendorIdentifier"] as? String }.sorted().joined(separator: ", ")))")
        }
        if let m = meta, let primary = m.primaryCategory {
            let (subs, _) = try await api.getAll("/v1/appCategories/\(primary)/subcategories", [("limit", "200")])
            let live = Set(subs.map { idOf($0) })
            let verdict = m.primarySubcategories.map { "\($0) \(live.contains($0) ? "ok" : "NOT ON THE STORE")" }.joined(separator: ", ")
            out("categories: \(primary) subcategories on the store: \(live.sorted().joined(separator: ", "))")
            out("  metadata asks for: \(verdict)")
        }
        let (subsR, _) = try await api.getAll("/v1/reviewSubmissions", [("filter[app]", appID), ("filter[platform]", "IOS"), ("limit", "20")])
        out("review submissions: \(subsR.isEmpty ? "none" : subsR.map { "\(idOf($0)) \(attrs($0)["state"] as? String ?? "?")" }.joined(separator: ", "))")
        do {
            let noms = try await nominations(api, appID: appID)
            out("nominations:\(noms.isEmpty ? "none yet" : noms.map { "\(short(attrs($0)["name"])) \(attrs($0)["state"] as? String ?? "?")" }.joined(separator: ", "))")
        } catch {
            out("nominations: can't read (\(error)); the nomination step needs the Admin, App Manager or Marketing role")
        }
        if let lib = try await api.getOptional("/v1/apps/\(appID)/assetLibrary"), let l = dataOne(lib) {
            out("asset library: \(idOf(l))")
            if let cat = try? await RefCatalog.load(api) {
                let duo = cat.screenshotGroups.keys.filter { cat.groups[$0] == "IPHONE_DUO" }.sorted()
                out("screenshot groups: \(cat.screenshotGroups.count); iPhone Duo: \(duo.isEmpty ? "none offered" : duo.joined(separator: ", "))")
                for (key, size) in [("APP_IPHONE_67", (1320, 2868)), ("APP_IPHONE_61", (1179, 2556)), ("APP_IPHONE_61", (1206, 2622)), ("duoInner", (2007, 2853))] {
                    out("  \(key) \(size.0)x\(size.1) → \(cat.group(for: key, width: size.0, height: size.1) ?? "no group (skipped)")")
                }
                for (spec, size) in zip(placementSpecs, [(3840, 1646), (3840, 2560)]) {
                    if let t = cat.placementType(spec.typeID, containing: spec.typeWord) {
                        let g = cat.groups(forType: t, width: size.0, height: size.1)
                        out("  \(spec.label): \(t), category \(cat.category(for: t)), \(size.0)x\(size.1) → \(g.isEmpty ? (cat.hasGroups(t) ? "no group takes that size" : "no placement group") : g.joined(separator: ", "))\(cat.versionTypes.isEmpty ? "" : (cat.versionTypes.contains(t) ? "; listed for App Store versions" : "; NOT listed for App Store versions"))")
                    } else {
                        out("  \(spec.label): no \(spec.typeID) placement type offered (upload by hand)")
                    }
                }
            }
        } else {
            out("asset library: not available (screenshots would need ASC_SCREENSHOT_API=legacy)")
        }
        let ps = try await api.getOptional("/v1/apps/\(appID)/appPriceSchedule")
        out("price schedule: \(dataOne(ps) != nil ? "exists" : "none yet")")
        let av = try await api.getOptional("/v1/apps/\(appID)/appAvailabilityV2")
        out("availability: \(dataOne(av) != nil ? "set" : "not set yet (the price step sets it)")")
        if var m = meta, inheritFrom != nil {
            do { out("inherit: \(try await inheritPersonalFields(api, into: &m, v))") } catch { out("inherit: FAILED: \(error)") }
        }
        if let m = meta, let t = m.text[m.primaryLocale] {
            for k in ["supportUrl", "marketingUrl", "privacyPolicyUrl"] {
                if let u = t.fields[k] { out("\(k): \(u) → \(await probeURL(u))") }
            }
        }
    } catch {
        out("check failed: \(error)")
        return 1
    }
    out("")
    out("metadata: \(v.errors.isEmpty ? "valid" : "\(v.errors.count) error(s); run `validate`") (\(v.blockers.count) gaps)")
    for b in v.blockers { out("  gap [\(b.step)]: \(b.msg)") }
    return 0
}

func runSync(dryRun: Bool, screenshotsOnly: Bool, screenshotDir: String?, placementsOnly: Bool = false,
             placementsDir: String? = nil) async -> Int32 {
    let v = Validation()
    guard var meta = loadMetadata(v) else { printValidation(v, steps: Set(allSteps)); return 1 }
    let steps: Set<String> = placementsOnly ? ["placements"] : screenshotsOnly ? ["screenshots"] : selectedSteps()
    let art = steps.contains("placements") ? loadPlacements(placementsDirectory(placementsDir), v) : []
    var sets = meta.screenshots
    if let dir = screenshotDir {
        do {
            sets = try screenshotsFromDirectory(URL(fileURLWithPath: dir))
            out("screenshots from \(dir): \(sets.map { "\($0.key)×\($0.files.count)" }.joined(separator: ", "))")
            v.errors.removeAll { $0.step == "screenshots" }
            v.blockers.removeAll { $0.step == "screenshots" }
        } catch { die("\(error)") }
    }
    out("\(dryRun ? "PLAN (dry run, nothing is changed)" : "PUSH") from \(metadataURL.path)")
    out("steps: \(allSteps.filter { steps.contains($0) }.joined(separator: " "))")
    printValidation(v, steps: steps)
    let blocking = v.blockingErrors(for: steps)
    if !blocking.isEmpty {
        out("")
        out("Stopped: \(blocking.count) validation error(s) in the selected steps. Fix asc-metadata.json, or narrow with --only/--skip.")
        return 1
    }
    let api: ASC
    do { api = try ASC() } catch { die("\(error)") }
    if inheritFrom != nil && !steps.isDisjoint(with: ["version", "review"]) {
        do { out("inherit: \(try await inheritPersonalFields(api, into: &meta, v))") } catch {
            out("inherit: FAILED: \(error)")
            v.block("version", "inheriting from \(inheritFrom ?? "?") failed; copyright is not pushed")
            v.block("review", "inheriting from \(inheritFrom ?? "?") failed; the App Review contact is not pushed")
        }
    }
    let e = Engine(api: api, meta: meta, dryRun: dryRun, steps: steps)
    do {
        try await e.resolveApp()
        let needsInfo = !steps.isDisjoint(with: ["appinfo", "categories", "agerating"])
        if needsInfo { try await e.resolveAppInfo() }
        let needsVersion = !steps.isDisjoint(with: ["version", "localizations", "review", "gamecenter", "attach", "screenshots", "placements"])
        if needsVersion {
            try await e.resolveVersion(create: true)
            try await e.loadVersionLocalizations()
        }
    } catch {
        out("error: \(error)")
        return 1
    }
    await e.step("appinfo", "App information: name, subtitle, privacy policy URL") { try await e.syncAppInfoLocalizations() }
    await e.step("categories", "Categories") { try await e.syncCategories() }
    await e.step("agerating", "Age rating declaration") { try await e.syncAgeRating() }
    await e.step("version", "Version: copyright, release type and date") { try await e.syncVersionAttributes() }
    await e.step("localizations", "Version localizations: description, keywords, promo text, URLs") { try await e.syncVersionLocalizations() }
    await e.step("review", "App Review details") { try await e.syncReview() }
    await e.step("gamecenter", "Game Center: enable, achievements, leaderboards, localizations, badges") { try await e.syncGameCenter() }
    await e.step("attach", "Game Center items into the 1.0 review submission (draft, never submitted)") { try await e.syncAttach() }
    await e.step("screenshots", "Screenshots") { try await e.syncScreenshots(sets) }
    await e.step("placements", "Product page header and search results art") { try await e.syncPlacements(art) }
    await e.step("price", "Price and availability") { try await e.syncPrice() }
    await e.step("accessibility", "Accessibility Nutrition Labels") { try await e.syncAccessibility() }
    await e.step("nomination", "Featuring nomination") { try await e.syncNomination() }

    out("")
    out("══ \(dryRun ? "Plan" : "Push"): \(e.changes) change(s) \(dryRun ? "planned" : "made"), \(e.unchanged) already up to date, \(e.failures.count) step failure(s)")
    for f in e.failures { out("  failed: \(f)") }
    let founderGaps = v.blockers.filter { steps.contains($0.step) }
    if !founderGaps.isEmpty {
        out("Gaps (not pushed; fix the source and run push again):")
        for b in founderGaps { out("  • \(b.msg)") }
    }
    if !screenshotsOnly && !placementsOnly {
        out("Still by hand in App Store Connect:")
        for m in e.manual + manualAlways { out("  • \(m)") }
    }
    return e.failures.isEmpty ? 0 : 1
}

// MARK: - Main

let status: Int32
switch command {
case "validate": status = runValidate()
case "check": status = await runCheck()
case "plan": status = await runSync(dryRun: true, screenshotsOnly: false, screenshotDir: nil)
case "push": status = await runSync(dryRun: false, screenshotsOnly: false, screenshotDir: nil)
case "upload-screenshots":
    status = await runSync(dryRun: env["ASC_DRY_RUN"] == "1", screenshotsOnly: true, screenshotDir: positional.first)
case "upload-placements":
    status = await runSync(dryRun: env["ASC_DRY_RUN"] == "1", screenshotsOnly: false, screenshotDir: nil,
                           placementsOnly: true, placementsDir: positional.first)
case "help", "-h", "--help": out(usage); status = 0
default: out(usage); status = 2
}
exit(status)
