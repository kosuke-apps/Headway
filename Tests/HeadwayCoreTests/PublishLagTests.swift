import Testing

@testable import HeadwayCore

@Suite struct PublishLagTests {
  @Test func startsAtFourSeconds() {
    #expect(PublishLag().estimate == 4)
  }

  @Test func followsTheSmallestRecentAge() {
    var lag = PublishLag()
    for age in [9.2, 8.1, 10.4, 8.6] { lag.note(age: age) }
    #expect(lag.estimate == 8.1)
  }

  @Test func forgetsOldFeeds() {
    var lag = PublishLag()
    lag.note(age: 5)
    for _ in 0..<10 { lag.note(age: 9) }
    #expect(lag.estimate == 9)
  }

  @Test func ignoresAgesThatCannotBeRight() {
    var lag = PublishLag()
    lag.note(age: -3)
    lag.note(age: 400)
    #expect(lag.estimate == 4)
  }

  @Test func staysWithinLimits() {
    var low = PublishLag()
    low.note(age: 0.4)
    #expect(low.estimate == 2.5)
    var high = PublishLag()
    high.note(age: 50)
    #expect(high.estimate == 20)
  }
}
