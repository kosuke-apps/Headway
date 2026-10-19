import Foundation
import Testing

@testable import Headway

@Suite struct DataUseTests {
  // MARK: How often predictions are fetched

  @Test func automaticIsAMinuteForWhatNeedsThemFreshAndTwoOtherwise() {
    #expect(AppModel.predictionInterval(.automatic, urgent: true, slowdown: 1, watching: false) == 55)
    #expect(AppModel.predictionInterval(.automatic, urgent: false, slowdown: 1, watching: false) == 115)
  }

  @Test func automaticWaitsLongerOnMobileDataAndInLowDataMode() {
    #expect(AppModel.predictionInterval(.automatic, urgent: true, slowdown: 2, watching: false) == 115)
    #expect(AppModel.predictionInterval(.automatic, urgent: true, slowdown: 4, watching: false) == 235)
  }

  @Test func aChosenGapIsKeptWhateverIsOnScreen() {
    #expect(AppModel.predictionInterval(.every30Seconds, urgent: false, slowdown: 4, watching: false) == 25)
    #expect(AppModel.predictionInterval(.everyFiveMinutes, urgent: true, slowdown: 1, watching: true) == 295)
  }

  @Test func manualFetchesNothingByItselfExceptForWatchedRoutes() {
    #expect(AppModel.predictionInterval(.manual, urgent: true, slowdown: 1, watching: false) == .infinity)
    #expect(AppModel.predictionInterval(.manual, urgent: true, slowdown: 1, watching: true) == 295)
  }

  // MARK: The meter

  @Test func theMeterCountsByKindAndConnection() {
    var usage = DataUsage(since: Date(timeIntervalSince1970: 0))
    usage.add(.positions, bytes: 7_000, metered: false)
    usage.add(.positions, bytes: 7_000, metered: true)
    usage.add(.predictions, bytes: 160_000, metered: false)
    usage.add(.timetable, bytes: 0, metered: true)  // nothing to count
    #expect(usage.bytes(.positions, metered: true) == 7_000)
    #expect(usage.bytes(.positions) == 14_000)
    #expect(usage.bytes(.predictions, metered: true) == 0)
    #expect(usage.bytes(metered: false) == 167_000)
    #expect(usage.bytes(metered: true) == 7_000)
  }

  @Test func theMeterSurvivesBeingSaved() throws {
    var usage = DataUsage(since: Date(timeIntervalSince1970: 1_000))
    usage.add(.alerts, bytes: 1_300, metered: true)
    let back = try JSONDecoder().decode(DataUsage.self, from: JSONEncoder().encode(usage))
    #expect(back == usage)
    #expect(back.bytes(.alerts, metered: true) == 1_300)
  }

  @MainActor @Test func theMeterKeepsItsCountsBetweenLaunchesAndCanBeReset() {
    let suite = UserDefaults(suiteName: "dev.kosuke.headway.tests.meter")!
    suite.removePersistentDomain(forName: "dev.kosuke.headway.tests.meter")
    let first = DataMeter(defaults: suite)
    first.record(.predictions, bytes: 160_000, metered: false)
    #expect(DataMeter(defaults: suite).usage.bytes(.predictions) == 160_000)
    first.reset()
    #expect(DataMeter(defaults: suite).usage.bytes(.predictions) == 0)
    suite.removePersistentDomain(forName: "dev.kosuke.headway.tests.meter")
  }
}
