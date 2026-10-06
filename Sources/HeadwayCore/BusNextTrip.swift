import Foundation

/// The trip a bus is about to run: at a terminal the next one is often the other way ("Eastbound" becomes "Westbound"),
/// and a bus with no trip in the position feed (out of service, or waiting) may already have one assigned.
public struct NextTrip: Sendable, Hashable {
  public let tripID: String
  public let routeID: String
  public let headsign: String
  public let directionName: String
  public let firstStopID: String
  /// When it leaves its first stop, by the trip updates.
  public let departure: Date
}

public enum BusNextTrip {
  /// The earliest trip the trip updates list for this bus other than the one it is on, that has not left yet.
  public static func of(_ vehicle: VehicleSample, predictions: [TripPrediction], schedule: Schedule, now: Date) -> NextTrip? {
    guard !vehicle.vehicleID.isEmpty else { return nil }
    var best: NextTrip?
    for prediction in predictions where prediction.vehicleID == vehicle.vehicleID && prediction.tripID != vehicle.tripID {
      guard let trip = schedule.trips[prediction.tripID],
        let first = prediction.stops.first(where: { !$0.skipped }),
        let time = first.departure ?? first.arrival, time >= now.addingTimeInterval(-120)
      else { continue }
      if let best, best.departure <= time { continue }
      best = NextTrip(
        tripID: trip.id, routeID: trip.routeID, headsign: trip.headsign, directionName: trip.directionName,
        firstStopID: first.stopID, departure: time)
    }
    return best
  }
}
