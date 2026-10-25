import Testing

@testable import Headway

@Suite struct BusAnimatorTests {
  @Test func aReportOfNormalAgeKeepsTheOldLimit() {
    #expect(BusAnimator.extrapolationLimit(reportAge: 0) == 50)
    #expect(BusAnimator.extrapolationLimit(reportAge: 25) == 50)
  }

  @Test func anOldReportKeepsRoomToMoveAfterItArrives() {
    // The city's feed 70 s behind: the marker may be moved on for 25 more seconds, not frozen at the 50 s mark at once.
    #expect(BusAnimator.extrapolationLimit(reportAge: 70) == 95)
    #expect(BusAnimator.extrapolationLimit(reportAge: 95) > 95)
  }
}
