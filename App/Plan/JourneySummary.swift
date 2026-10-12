import Foundation
import HeadwayCore

/// A journey as lines of plain text, for sharing and for reminders.
struct JourneySummary {
  let text: TimeText
  let routeName: (String) -> String
  /// A stop's name, with the side of the street when the app knows it.
  var stopName: (PlanPoint) -> String = { $0.name }

  func lines(for journey: Journey, from: String, to: String) -> [String] {
    var lines = [
      "\(from) → \(to)",
      "\(text.clock(journey.departure)) → \(text.clock(journey.arrival)) · \(TimeText.duration(journey.duration))",
    ]
    for (index, leg) in journey.legs.enumerated() {
      defer {
        for stay in journey.stopovers where stay.afterLeg == index {
          lines.append(
            "• " + L10n.string("Stay at \(stay.place.name)") + ": \(text.clock(stay.arrive))–\(text.clock(stay.leave)) · \(TimeText.duration(stay.duration))")
        }
      }
      switch leg {
      case .walk(let walk):
        lines.append("• " + L10n.string("Walk \(TimeText.duration(walk.end.timeIntervalSince(walk.start))) to \(walk.to.name)"))
      case .ride(let ride):
        lines.append(
          "• " + L10n.string("Route \(routeName(ride.routeID)) to \(ride.headsign.prettyHeadsign)") + ": "
            + L10n.string("Board at \(stopName(ride.fromStop)) · \(text.clock(ride.depart))") + ", "
            + L10n.string("Get off at \(stopName(ride.toStop)) · \(text.clock(ride.arrive))"))
      }
    }
    return lines
  }

  /// What the reminder says: when to leave and what to take.
  func reminder(for journey: Journey) -> String {
    guard let first = journey.rides.first else { return L10n.string("Time to start walking.") }
    let route = L10n.string("Route \(routeName(first.routeID)) to \(first.headsign.prettyHeadsign)")
    if case .walk(let walk) = journey.legs.first {
      return String(
        localized: "Leave now: walk \(TimeText.duration(walk.end.timeIntervalSince(walk.start))) to \(first.fromStop.name). \(route) at \(text.clock(first.depart)).")
    }
    return L10n.string("\(route) leaves \(first.fromStop.name) at \(text.clock(first.depart)).")
  }
}
