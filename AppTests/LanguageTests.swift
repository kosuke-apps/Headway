import Foundation
import Testing

@testable import Headway

@Suite struct LanguageTests {
  /// The app bundle that holds the translation folders (the tests run inside the app).
  private let host = Bundle(for: AppModel.self)

  private func state(_ choice: AppLanguage, preferred: [String] = ["en-US"], region: String? = "US") -> LanguageState {
    LanguageState(choice: choice, preferred: preferred, region: region, host: host)
  }

  // MARK: Which language

  @Test func theTwoFixedChoicesIgnoreThePhonesLanguage() {
    #expect(LanguageState.resolve(.english, preferred: ["ja-JP"]) == "en")
    #expect(LanguageState.resolve(.japanese, preferred: ["en-US"]) == "ja")
  }

  @Test func systemDefaultFollowsTheFirstPreferredLanguageTheAppKnows() {
    #expect(LanguageState.resolve(.system, preferred: ["ja-JP", "en-US"]) == "ja")
    #expect(LanguageState.resolve(.system, preferred: ["en-US", "ja-JP"]) == "en")
    #expect(LanguageState.resolve(.system, preferred: ["fr-FR", "ja"]) == "ja")
    #expect(LanguageState.resolve(.system, preferred: ["zh-Hans-CN"]) == "en")
    #expect(LanguageState.resolve(.system, preferred: []) == "en")
  }

  @Test func theLocalePairsTheLanguageWithThePhonesRegion() {
    let ja = state(.japanese, region: "US")
    #expect(ja.locale.language.languageCode?.identifier == "ja")
    #expect(ja.locale.region?.identifier == "US")
    #expect(state(.english, region: "JP").locale.region?.identifier == "JP")
    #expect(state(.english, region: nil).locale.language.languageCode?.identifier == "en")
  }

  @Test func changingTheLanguageUpdatesEverythingDerivedFromIt() {
    let language = state(.english)
    #expect(language.code == "en")
    language.apply(.japanese)
    #expect(language.code == "ja")
    #expect(language.locale.language.languageCode?.identifier == "ja")
    language.apply(.system, preferred: ["en-GB"])
    #expect(language.code == "en")
  }

  // MARK: Text

  @Test func aStringComesBackInTheChosenLanguageWhateverTheHostSpeaks() {
    #expect(L10n.string("Close", in: state(.english)) == "Close")
    #expect(L10n.string("Close", in: state(.japanese)) == "閉じる")
  }

  @Test func interpolatedStringsKeepTheirNumbersInBothLanguages() {
    let minutes = 5
    #expect(L10n.string("\(minutes) min", in: state(.english)) == "5 min")
    #expect(L10n.string("\(minutes) min", in: state(.japanese)) == "5分")
  }

  @Test func theDirectionWordsAreTranslated() {
    #expect(L10n.string("Eastbound", in: state(.japanese)) == "東行き")
    #expect(L10n.string("Eastbound", in: state(.english)) == "Eastbound")
  }

  // MARK: The setting

  @Test func theChoiceIsStoredWithTheOtherSettingsAndSurvivesEncoding() throws {
    var prefs = Preferences()
    #expect(prefs.language == .system)
    prefs.language = .japanese
    let back = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs))
    #expect(back.language == .japanese)
  }

  @Test func settingsSavedBeforeTheChoiceExistedLoadAsSystemDefault() throws {
    let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"markerSize": "large"}"#.utf8))
    #expect(old.language == .system)
    #expect(old.markerSize == .large)
    // A value this version does not know falls back instead of failing the whole load.
    let odd = try JSONDecoder().decode(Preferences.self, from: Data(#"{"language": "klingon", "markerSize": "large"}"#.utf8))
    #expect(odd.language == .system && odd.markerSize == .large)
  }

  // MARK: Rules that keep the choice working

  /// The root of the repository, found from this file.
  private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }

  @Test func everyStringHasAJapaneseTranslationWithTheSameFormatSpecifiers() throws {
    let data = try Data(contentsOf: root.appendingPathComponent("App/Resources/Localizable.xcstrings"))
    let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(catalog["strings"] as? [String: [String: Any]])
    #expect(strings.count > 400)
    func specifiers(_ text: String) -> [String] {
      let pattern = #"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:l{1,2}|h{1,2}|q|z)?([dDuUfFeEgGsS@])"#
      let expression = try! NSRegularExpression(pattern: pattern)
      // One string for the match and for the ranges: a range of the longer text applied to the shorter one raises.
      let cleaned = text.replacingOccurrences(of: "%%", with: "")
      let range = NSRange(cleaned.startIndex..., in: cleaned)
      return expression.matches(in: cleaned, range: range).map { (cleaned as NSString).substring(with: $0.range(at: 1)) }.sorted()
    }
    var problems: [String] = []
    for (key, entry) in strings.sorted(by: { $0.key < $1.key }) {
      let ja = (entry["localizations"] as? [String: Any])?["ja"] as? [String: Any]
      guard let unit = ja?["stringUnit"] as? [String: Any], let value = unit["value"] as? String, !value.isEmpty else {
        problems.append("no Japanese: \(key)")
        continue
      }
      if specifiers(key) != specifiers(value) { problems.append("specifiers differ: \(key)") }
    }
    #expect(problems.isEmpty, Comment(rawValue: problems.joined(separator: "\n")))
  }

  @Test func japaneseTextUsesTheFullWidthCommaAndPeriod() throws {
    // The author writes Japanese with "，" and "．", never "、" and "。": the app's Japanese follows.
    let catalog = try Data(contentsOf: root.appendingPathComponent("App/Resources/Localizable.xcstrings"))
    let plist = try Data(contentsOf: root.appendingPathComponent("App/Resources/ja.lproj/InfoPlist.strings"))
    for (name, data) in [("Localizable.xcstrings", catalog), ("ja InfoPlist.strings", plist)] {
      let text = String(decoding: data, as: UTF8.self)
      #expect(!text.contains("、") && !text.contains("。"), Comment(rawValue: "\(name) uses 、 or 。"))
    }
  }

  @Test func noCodeAsksTheSystemForTextBehindTheLanguageChoicesBack() throws {
    // `String(localized:)` follows the phone's language, so a string built with it ignores Settings > Language.
    let app = root.appendingPathComponent("App")
    let files = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
    var offenders: [String] = []
    for case let url as URL in files where url.pathExtension == "swift" && url.lastPathComponent != "Language.swift" {
      let text = try String(contentsOf: url, encoding: .utf8)
      if text.contains("String(localized:") || text.contains("NSLocalizedString") { offenders.append(url.lastPathComponent) }
    }
    #expect(offenders.isEmpty, Comment(rawValue: "use L10n.string instead in: \(offenders.joined(separator: ", "))"))
  }
}
