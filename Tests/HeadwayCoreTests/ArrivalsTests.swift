import Foundation
import Testing

@testable import HeadwayCore

@Suite struct ArrivalsTests {
  let schedule: Schedule

  init() throws { schedule = try Schedule.load(directory: try makeFeed()) }

  /// Monday 2026-10-05 at the given local time.
  private func monday(_ h: Int, _ m: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = schedule.timeZone
    return calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: h, minute: m))!
  }

  private func vehicle(trip: String) -> VehicleSample {
    VehicleSample(
      entityID: "1", vehicleID: "v1", label: "", tripID: trip, routeID: "A", directionID: nil, startDate: "",
      latitude: 43.07, longitude: -89.40, bearing: nil, speed: nil, timestamp: nil, currentStopSequence: nil,
      stopID: "")
  }

  private func prediction(
    trip: String, stop: String, sequence: Int, at time: Date, skipped: Bool = false, relationship: String = "SCHEDULED"
  ) -> TripPrediction {
    TripPrediction(
      entityID: "1", tripID: trip, routeID: "A", directionID: nil, startDate: "", startTime: "",
      scheduleRelationship: relationship, vehicleID: "v1", timestamp: nil, delay: nil,
      stops: [
        StopPrediction(
          stopID: stop, sequence: sequence, arrival: time, arrivalDelay: nil, departure: nil, departureDelay: nil,
          skipped: skipped)
      ])
  }

  @Test func timetableOnlyWhenNothingIsLive() {
    // t2 leaves at 23:50, so it only shows up with a long window.
    let result = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: monday(7, 50), window: 20 * 3600, predictions: [], vehicles: [])
    #expect(result.map(\.tripID) == ["t1", "t2"])
    #expect(result[0].status == .scheduled)
    #expect(result[0].expected == monday(8, 0))
    #expect(result[0].delay == nil)
  }

  @Test func lastStopOfATripIsNotListed() {
    // s2 is the last stop of both trips, so nobody boards there.
    let result = Arrivals.upcoming(schedule: schedule, stopID: "s2", now: monday(7, 50), predictions: [], vehicles: [])
    #expect(result.isEmpty)
  }

  @Test func liveWhenBusAndPredictionExist() {
    let late = monday(8, 4)
    let result = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: monday(7, 50),
      predictions: [prediction(trip: "t1", stop: "s1", sequence: 1, at: late)], vehicles: [vehicle(trip: "t1")])
    #expect(result[0].status == .live)
    #expect(result[0].expected == late)
    #expect(result[0].delay == 240)
    #expect(result[0].minutes(from: monday(7, 50)) == 14)
  }

  @Test func predictionWithoutBusStaysScheduled() {
    let result = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: monday(7, 50),
      predictions: [prediction(trip: "t1", stop: "s1", sequence: 1, at: monday(8, 4))], vehicles: [])
    #expect(result[0].status == .scheduled)
    #expect(result[0].expected == monday(8, 0))
  }

  @Test func lateBusStillListedAfterItsTimetableTime() {
    // Timetable says 08:00, the bus is 5 minutes late, and it is 08:02 now.
    let result = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: monday(8, 2),
      predictions: [prediction(trip: "t1", stop: "s1", sequence: 1, at: monday(8, 5))], vehicles: [vehicle(trip: "t1")])
    #expect(result.first?.tripID == "t1")
    #expect(result.first?.delay == 300)
  }

  @Test func busThatHasGoneIsDropped() {
    // A bus that is being tracked, and whose time at the stop has passed, has gone.
    let result = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: monday(8, 10), window: 20 * 3600,
      predictions: [prediction(trip: "t1", stop: "s1", sequence: 1, at: monday(8, 1))], vehicles: [vehicle(trip: "t1")])
    #expect(result.map(\.tripID) == ["t2"])
  }

  @Test func aTripNobodyHasSeenABusOnStaysForTwentyMinutes() {
    // 08:00 has passed and no bus reports the trip: it may just be late and not on its route yet.
    let result = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: monday(8, 5), window: 20 * 3600, predictions: [], vehicles: [])
    #expect(result.map(\.tripID) == ["t1", "t2"])
    #expect(result[0].isUnconfirmed(at: monday(8, 5)))
    #expect(!result[1].isUnconfirmed(at: monday(8, 5)))
    // Still there at 08:19, a bus 19 minutes late can turn up.
    let nearly = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: monday(8, 19), window: 20 * 3600, predictions: [], vehicles: [])
    #expect(nearly.map(\.tripID) == ["t1", "t2"])
    // Then it leaves the list of what is coming, so that a trip that never runs does not linger.
    let later = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: monday(8, 21), window: 20 * 3600, predictions: [], vehicles: [])
    #expect(later.map(\.tripID) == ["t2"])
  }

  @Test func earlierDeparturesAreKeptWhenAskedFor() {
    // At 08:30 the 08:00 trip is long gone from the list of what is coming, but the rider can open the earlier ones.
    let now = monday(8, 30)
    let normal = Arrivals.upcoming(schedule: schedule, stopID: "s1", now: now, window: 20 * 3600, predictions: [], vehicles: [])
    #expect(normal.map(\.tripID) == ["t2"])
    let withEarlier = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: now, window: 20 * 3600, predictions: [], vehicles: [], earlier: 3600)
    #expect(withEarlier.map(\.tripID) == ["t1", "t2"])
    #expect(withEarlier[0].hasGone(at: now))
    #expect(!withEarlier[1].hasGone(at: now))
    // Too far back is still left out.
    let tooShort = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: now, window: 20 * 3600, predictions: [], vehicles: [], earlier: 600)
    #expect(tooShort.map(\.tripID) == ["t2"])
  }

  @Test func earlierDeparturesDoNotUseUpTheLimit() {
    let now = monday(8, 30)
    let result = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: now, window: 20 * 3600, predictions: [], vehicles: [], limit: 1, earlier: 3600)
    #expect(result.map(\.tripID) == ["t1", "t2"])
  }

  @Test func aBusThatTurnsUpVeryLateComesBackAsLive() {
    // 08:00 trip, 25 minutes late: it is 08:25, it was in the earlier departures, and now a bus reports it.
    let now = monday(8, 25)
    let result = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: now, window: 20 * 3600,
      predictions: [prediction(trip: "t1", stop: "s1", sequence: 1, at: monday(8, 27))], vehicles: [vehicle(trip: "t1")])
    #expect(result.first?.tripID == "t1")
    #expect(result.first?.status == .live)
    #expect(result.first?.hasGone(at: now) == false)
  }

  @Test func aTripIsNotUnconfirmedBeforeItsTimeOrWhileABusReportsIt() {
    let early = Arrivals.upcoming(schedule: schedule, stopID: "s1", now: monday(7, 50), predictions: [], vehicles: [])
    #expect(!early[0].isUnconfirmed(at: monday(7, 50)))
    let tracked = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: monday(8, 3), predictions: [], vehicles: [vehicle(trip: "t1")])
    // A bus is on the trip but the feed has no time for this stop: it is known to exist, and goes after the short grace.
    #expect(tracked.isEmpty)
  }

  @Test func aCancelledTripIsNotKeptAsUnconfirmed() {
    let result = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: monday(8, 5), window: 20 * 3600,
      predictions: [prediction(trip: "t1", stop: "s1", sequence: 1, at: monday(8, 0), relationship: "CANCELED")], vehicles: [])
    #expect(result.map(\.tripID) == ["t2"])
  }

  @Test func skippedStopIsNotListed() {
    let result = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: monday(7, 50), window: 20 * 3600,
      predictions: [prediction(trip: "t1", stop: "s1", sequence: 1, at: monday(8, 0), skipped: true)],
      vehicles: [vehicle(trip: "t1")])
    #expect(result.map(\.tripID) == ["t2"])
  }

  @Test func windowLimitsHowFarAheadWeLook() {
    let result = Arrivals.upcoming(
      schedule: schedule, stopID: "s1", now: monday(7, 50), window: 600, predictions: [], vehicles: [])
    #expect(result.map(\.tripID) == ["t1"])
  }

  @Test func remainingStopsUseThePredictionWhereThereIsOne() {
    let predicted = monday(8, 12)
    let stops = Arrivals.remainingStops(
      schedule: schedule, tripID: "t1", now: monday(8, 1),
      prediction: prediction(trip: "t1", stop: "s2", sequence: 2, at: predicted))
    // s1 (08:00) has just gone by more than 30 s ago, so only s2 remains.
    #expect(stops.map(\.stopID) == ["s2"])
    #expect(stops[0].scheduled == monday(8, 10))
    #expect(stops[0].expected == predicted)
  }

  @Test func serviceDateOfAPastMidnightTripIsThePreviousDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = schedule.timeZone
    let tuesdayAfterMidnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 0, minute: 10))!
    #expect(schedule.serviceDate(of: "t2", near: tuesdayAfterMidnight) == ServiceDate(20_261_005))
  }
}
