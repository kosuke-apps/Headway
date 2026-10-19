import Testing

@testable import Headway

@Suite struct NetworkStatusTests {
  @Test func nothingIsSlowedWhenTheRiderDoesNotSaveData() {
    // On Wi-Fi (the test machine's connection) the factor is 1; with saving off it is 1 whatever the connection.
    #expect(NetworkStatus.shared.slowdown(saving: false) == 1)
  }

  @Test func theFactorIsOneTwoOrFour() {
    #expect([1.0, 2.0, 4.0].contains(NetworkStatus.shared.slowdown(saving: true)))
  }
}
