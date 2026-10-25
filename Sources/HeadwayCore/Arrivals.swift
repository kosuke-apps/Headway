import Foundation

/// One upcoming bus at a stop, combining the timetable with what the realtime feeds say.
public struct Arrival: Sendable, Identifiable, Hashable {
  public enum Status: Sendable, Hashable {
    /// A bus is reporting its position for this trip and the feed predicts a time at this stop.
    case live
    /// Only the timetable is known. Either no bus has been seen for this trip, or the feed has no prediction.
    case scheduled
  }

  public var id: String { "\(tripID)@\(serviceDate.value)#\(sequence)" }
  public let tripID: String
  public let routeID: String
  public let headsign: String
  public let serviceDate: ServiceDate
  public let sequence: Int
  public let scheduled: Date
  public let predicted: Date?
  public let status: Status
  public let vehicle: VehicleSample?
  /// True when the trip updates say the trip is cancelled.
  public let cancelled: Bool

  /// The best estimate: the prediction when the bus is live, otherwise the timetable.
  public var expected: Date { status == .live ? (predicted ?? scheduled) : scheduled }

  /// Seconds later (positive) or earlier (negative) than the timetable. `nil` when only the timetable is known.
  public var delay: Int? {
    guard status == .live, let predicted else { return nil }
    return Int(predicted.timeIntervalSince(scheduled).rounded())
  }

  public func minutes(from now: Date) -> Int {
    Int((expected.timeIntervalSince(now) / 60).rounded(.down))
  }

  /// True when the timetable time has passed and no bus has been seen on the trip: it may be running late and not on its
  /// route yet (a bus has no position until it starts the trip), or it may not run at all. After `unconfirmedGrace` it
  /// counts as gone and moves to the earlier departures, which the rider can open.
  public func isUnconfirmed(at now: Date) -> Bool {
    status == .scheduled && vehicle == nil && !cancelled && scheduled < now.addingTimeInterval(-Arrivals.dueGrace)
      && scheduled >= now.addingTimeInterval(-Arrivals.unconfirmedGrace)
  }

  /// True when the bus has passed this stop, as far as the timetable and the feed say, and the trip is not one that may
  /// still turn up (`isUnconfirmed`): such rows belong under "Earlier departures", not in the list of what is coming.
  public func hasGone(at now: Date) -> Bool {
    expected < now.addingTimeInterval(-Arrivals.dueGrace) && !isUnconfirmed(at: now)
  }
}

public enum Arrivals {
  /// How long a bus that has gone stays listed as "Due".
  public static let dueGrace: TimeInterval = 20
  /// How long a trip that no bus has been seen on stays in the list of what is coming, after its timetable time. Measured:
  /// 7% of trips start more than 5 minutes late, 1% more than 10 and 0.3% more than 15, and until the bus starts the trip
  /// the feed has no position for it. Later it moves to the earlier departures; it is never deleted, and a bus that does
  /// turn up makes it a live row again.
  public static let unconfirmedGrace: TimeInterval = 20 * 60

  /// Upcoming departures from `stopID`, soonest first.
  ///
  /// The timetable is searched from 30 minutes before `now`, so a late bus whose timetable time has passed is still
  /// listed. A departure is `live` only when a bus reports a position for that trip and the trip updates predict a
  /// time at this stop; predictions for trips without a bus are just the timetable again. A trip with no bus at all stays
  /// for `unconfirmedGrace` after its time (see `Arrival.isUnconfirmed`), unless the feed says it is cancelled, instead
  /// of vanishing the moment its time passes.
  ///
  /// With `earlier` above zero the list also holds the departures of the last `earlier` seconds that have gone (they
  /// answer `hasGone`), oldest first and not counted in `limit`; they carry only what is known now, which for a bus that
  /// has passed is usually just the timetable.
  public static func upcoming(
    schedule: Schedule,
    stopID: String,
    now: Date,
    window: TimeInterval = 3 * 3600,
    predictions: [TripPrediction],
    vehicles: [VehicleSample],
    limit: Int = 40,
    earlier: TimeInterval = 0
  ) -> [Arrival] {
    var predictionByTrip: [String: TripPrediction] = [:]
    for prediction in predictions where !prediction.tripID.isEmpty { predictionByTrip[prediction.tripID] = prediction }
    var vehicleByTrip: [String: VehicleSample] = [:]
    for vehicle in vehicles where !vehicle.tripID.isEmpty { vehicleByTrip[vehicle.tripID] = vehicle }

    var arrivals: [Arrival] = []
    for departure in schedule.scheduledDepartures(from: stopID, from: now.addingTimeInterval(-max(earlier, 30 * 60)), until: now.addingTimeInterval(window)) {
      var predicted: Date?
      var skipped = false
      if let prediction = predictionByTrip[departure.tripID] {
        let stop = prediction.stops.first { $0.stopID == stopID && $0.sequence == departure.sequence }
          ?? prediction.stops.first { $0.stopID == stopID && $0.sequence == nil }
        if let stop {
          predicted = stop.arrival ?? stop.departure
          skipped = stop.skipped
        }
      }
      if skipped { continue }
      let cancelled = predictionByTrip[departure.tripID].map { ["CANCELED", "CANCELLED"].contains($0.scheduleRelationship) } ?? false
      let vehicle = vehicleByTrip[departure.tripID]
      let live = vehicle != nil && predicted != nil
      let arrival = Arrival(
        tripID: departure.tripID, routeID: departure.routeID, headsign: departure.headsign,
        serviceDate: departure.serviceDate, sequence: departure.sequence, scheduled: departure.time,
        predicted: predicted, status: live ? .live : .scheduled, vehicle: vehicle, cancelled: cancelled)
      // Buses that have gone are dropped (a short grace keeps "Due" visible) unless the rider asked for the earlier ones; a
      // trip nobody has seen a bus on stays for a while, because its bus may simply not have started it yet.
      if arrival.hasGone(at: now), arrival.expected < now.addingTimeInterval(-earlier) { continue }
      arrivals.append(arrival)
    }
    arrivals.sort { $0.expected < $1.expected }
    let gone = arrivals.filter { $0.hasGone(at: now) }
    return gone + arrivals.filter { !$0.hasGone(at: now) }.prefix(limit)
  }
}

/// One stop of a trip, for the "where is this bus going" list and for the timetable of a trip no bus is on yet.
public struct TripStopEta: Sendable, Identifiable, Hashable {
  public var id: Int { sequence }
  public let sequence: Int
  public let stopID: String
  public let scheduled: Date
  public let predicted: Date?
  /// True when the bus is past this stop (or, with no bus to ask, when its time has passed): the list greys it out.
  public let passed: Bool

  public var expected: Date { predicted ?? scheduled }
}

extension Arrivals {
  /// Every stop of `tripID` from first to last, with predicted times where the feed gives them. `currentSequence` is the stop
  /// the bus reports it is at or heading for: the stops before it are `passed`. Without it (no bus, or one that does not say)
  /// a stop has been passed once its expected time is more than 30 seconds ago.
  ///
  /// `serviceDate` is the day the trip runs on, when the caller knows it (a stop board row does); otherwise it is the one
  /// nearest to `now`.
  public static func tripStops(
    schedule: Schedule, tripID: String, now: Date, prediction: TripPrediction?, currentSequence: Int? = nil,
    serviceDate: ServiceDate? = nil
  ) -> [TripStopEta] {
    guard let times = schedule.stopTimes[tripID], let date = serviceDate ?? schedule.serviceDate(of: tripID, near: now) else { return [] }
    let midnight = date.midnight(in: schedule.timeZone)
    var predictedBySequence: [Int: Date] = [:]
    var predictedByStop: [String: Date] = [:]
    for stop in prediction?.stops ?? [] where !stop.skipped {
      guard let time = stop.arrival ?? stop.departure else { continue }
      if let sequence = stop.sequence { predictedBySequence[sequence] = time } else { predictedByStop[stop.stopID] = time }
    }
    return times.map { time in
      let scheduled = midnight.addingTimeInterval(TimeInterval(time.arrival))
      let predicted = predictedBySequence[time.sequence] ?? predictedByStop[time.stopID]
      let passed = currentSequence.map { time.sequence < $0 } ?? ((predicted ?? scheduled) < now.addingTimeInterval(-30))
      return TripStopEta(sequence: time.sequence, stopID: time.stopID, scheduled: scheduled, predicted: predicted, passed: passed)
    }
  }

  /// The stops `tripID` has yet to serve, with predicted times when the feed provides them.
  public static func remainingStops(
    schedule: Schedule, tripID: String, now: Date, prediction: TripPrediction?
  ) -> [TripStopEta] {
    tripStops(schedule: schedule, tripID: tripID, now: now, prediction: prediction).filter { !$0.passed }
  }
}
