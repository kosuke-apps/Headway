import Foundation
import HeadwayCore
import Testing

@testable import Headway

@Suite struct WatchNotifierTests {
  private func event(_ kind: WatchKind, seconds: Int = 0, buses: Int = 0, headline: String = "", detail: String = "") -> WatchEvent {
    WatchEvent(kind: kind, routeID: "A", buses: buses, seconds: seconds, alertID: "x", headline: headline, detail: detail)
  }

  @Test func lateAndEarlyMessagesMentionTheRouteAndMinutes() {
    let late = WatchNotifier.text(for: event(.late, seconds: 600, buses: 2), routeName: "B")
    #expect(late.title.contains("B"))
    #expect(late.body.contains("10"))
    let early = WatchNotifier.text(for: event(.early, seconds: 200, buses: 1), routeName: "B")
    #expect(early.title.contains("B"))
    #expect(early.body.contains("3"))
  }

  @Test func aLateOrEarlyBusSaysWhichDestinationAndWay() {
    let late = WatchEvent(
      kind: .late, routeID: "D", buses: 1, seconds: 600, alertID: "", headline: "", detail: "", headsign: "2-EPIC CAMPUS", directionName: "Eastbound")
    let text = WatchNotifier.text(for: late, routeName: "D")
    #expect(text.title.contains("D2") && text.title.contains("Epic Campus"))
    #expect(text.body.contains("Eastbound") && text.body.contains("10"))
    let early = WatchEvent(
      kind: .early, routeID: "D", buses: 1, seconds: 200, alertID: "", headline: "", detail: "", headsign: "1-UW HOSPITAL", directionName: "Westbound")
    let other = WatchNotifier.text(for: early, routeName: "D")
    #expect(other.title.contains("D1") && other.title.contains("UW Hospital"))
    #expect(text.title != other.title)
  }

  @MainActor @Test func watchedDestinationsAndTheirThresholdsSurviveAReset() {
    let defaults = UserDefaults(suiteName: "watch-tests-\(UUID().uuidString)")!
    let settings = AppSettings(defaults: defaults)
    settings.values.watchedLines = [WatchLine(routeID: "D", headsign: "2-EPIC CAMPUS")]
    settings.values.watchLateMinutes = 10
    settings.reset()
    #expect(settings.values.watchedLines == [WatchLine(routeID: "D", headsign: "2-EPIC CAMPUS")])
    #expect(settings.values.isWatchingAnything)
  }

  @Test func aThresholdOutsideTheChoicesFallsBackToTheDefault() throws {
    let json = Data(#"{"watchLateMinutes": 7, "watchEarlyMinutes": 3}"#.utf8)
    let prefs = try JSONDecoder().decode(Preferences.self, from: json)
    #expect(prefs.watchLateMinutes == 5)
    #expect(prefs.watchEarlyMinutes == 3)
  }

  @Test func alertsUseTheirOwnHeadlineAndAShortenedText() {
    let long = String(repeating: "detour ", count: 60)
    let text = WatchNotifier.text(for: event(.alert, headline: "A - State detour", detail: long), routeName: "A")
    #expect(text.title == "A - State detour")
    #expect(text.body.count <= 160)
  }

  @Test func anAlertWithoutTextStillSaysWhichRoute() {
    let text = WatchNotifier.text(for: event(.alert), routeName: "J")
    #expect(text.title.contains("J"))
    #expect(text.body.contains("J"))
  }

  @MainActor @Test func watchedRoutesSurviveResettingSettings() {
    let defaults = UserDefaults(suiteName: "watch-tests-\(UUID().uuidString)")!
    let settings = AppSettings(defaults: defaults)
    settings.values.watchedRoutes = ["A", "J"]
    settings.values.watchEnabled = true
    settings.reset()
    #expect(settings.values.watchedRoutes == ["A", "J"])
    #expect(!settings.values.watchEnabled)
  }
}
