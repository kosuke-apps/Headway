import Foundation
import Observation
import SwiftUI

/// What the rider chose in Settings > Language.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
  /// Whatever iOS gives this app: its per-app language when one is set, otherwise the phone's language.
  case system
  case english = "en"
  case japanese = "ja"
  var id: String { rawValue }
}

/// The language the app speaks right now, and everything derived from it: the translation bundle, and the locale for
/// formatting.
///
/// Reading any property inside a SwiftUI body registers the body for redraw, so a change of language redraws what shows
/// text without restarting the app or losing the map's position or an open sheet. The language is separate from the
/// region: the locale built here pairs the chosen language with the phone's region, so 12 or 24 hours and the units of
/// distance still follow the phone.
final class LanguageState: Observable, @unchecked Sendable {
  /// What the app uses; tests build their own instances instead of changing this one.
  static let shared = LanguageState()

  /// The languages the app has translations for.
  static let supported = ["en", "ja"]

  private struct Resolved {
    let code: String
    let locale: Locale
    let bundle: Bundle
  }

  private let registrar = ObservationRegistrar()
  private let lock = NSLock()
  private let host: Bundle
  private let region: String?
  private var resolved: Resolved

  init(
    choice: AppLanguage = .system, preferred: [String] = Locale.preferredLanguages,
    region: String? = Locale.autoupdatingCurrent.region?.identifier, host: Bundle = .main
  ) {
    self.host = host
    self.region = region
    resolved = Self.resolve(choice: choice, preferred: preferred, region: region, host: host)
  }

  /// "en" or "ja".
  var code: String { read { $0.code } }
  /// The chosen language with the phone's region ("ja_US"): for dates, numbers and the lookup of SwiftUI text.
  var locale: Locale { read { $0.locale } }
  /// The folder of translations for the chosen language (`ja.lproj`), or the app's own bundle without one.
  var bundle: Bundle { read { $0.bundle } }

  /// Switches the language; views that read it redraw.
  func apply(_ choice: AppLanguage, preferred: [String] = Locale.preferredLanguages) {
    let next = Self.resolve(choice: choice, preferred: preferred, region: region, host: host)
    guard next.code != code else { return }
    registrar.withMutation(of: self, keyPath: \.code) {
      lock.lock()
      resolved = next
      lock.unlock()
    }
  }

  private func read<Value>(_ get: (Resolved) -> Value) -> Value {
    registrar.access(self, keyPath: \.code)
    lock.lock()
    defer { lock.unlock() }
    return get(resolved)
  }

  /// The language for a choice: the two fixed ones as they are, "system" as the first of the phone's preferred languages
  /// that the app is translated into (English when none is).
  static func resolve(_ choice: AppLanguage, preferred: [String]) -> String {
    switch choice {
    case .english: return "en"
    case .japanese: return "ja"
    case .system:
      for language in preferred {
        if let code = Locale(identifier: language).language.languageCode?.identifier, supported.contains(code) { return code }
      }
      return "en"
    }
  }

  private static func resolve(choice: AppLanguage, preferred: [String], region: String?, host: Bundle) -> Resolved {
    let code = resolve(choice, preferred: preferred)
    let locale = Locale(identifier: region.map { "\(code)_\($0)" } ?? code)
    let bundle = host.path(forResource: code, ofType: "lproj").flatMap { Bundle(path: $0) } ?? host
    return Resolved(code: code, locale: locale, bundle: bundle)
  }
}

/// Text in the language the rider chose. Every string the app builds in code goes through here (or through a SwiftUI
/// `Text`, which follows the locale of the environment): `String(localized:)` would follow the phone's language and ignore
/// Settings > Language. `LanguageTests` fails when it finds one in the app's sources.
enum L10n {
  static func string(_ value: String.LocalizationValue, in language: LanguageState = .shared) -> String {
    String(localized: value, bundle: language.bundle, locale: language.locale)
  }
}

/// Puts the chosen language into the environment, so that SwiftUI text, dates and numbers use it.
struct LanguageRoot<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    content.environment(\.locale, LanguageState.shared.locale)
  }
}
