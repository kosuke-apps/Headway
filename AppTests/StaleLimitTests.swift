import Testing

@testable import Headway

@Suite struct StaleLimitTests {
  @Test func aNormalFleetKeepsTheOldLimit() {
    #expect(MapLayers.staleLimit(ages: [10, 20, 25, 30, 35]) == MapLayers.staleAfter)
    #expect(MapLayers.staleLimit(ages: []) == MapLayers.staleAfter)
  }

  @Test func aFeedThatIsBehindDoesNotVeilEveryBus() {
    // The whole feed is 70 to 90 s old: the limit moves with it, so only a bus that is older than the rest is veiled.
    let ages: [Double] = [70, 75, 80, 85, 90]
    let limit = MapLayers.staleLimit(ages: ages)
    #expect(limit == 125)
    #expect(ages.allSatisfy { $0 < limit })
    #expect(200 > limit)
  }
}
