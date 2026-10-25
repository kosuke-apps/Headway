import Foundation

/// What a rider can ask to be told about a route they watch.
public enum WatchKind: String, Sendable, Codable, CaseIterable {
  /// A bus is more than five minutes behind its timetable.
  case late
  /// A bus is more than two minutes ahead of its timetable.
  case early
  /// The city published an alert (a detour, a closed stop, ...) for the route.
  case alert
}

/// One destination of a route, watched on its own: "D2 to Epic Campus" without "D1 to the hospital". The headsign is the
/// feed's ("2-EPIC CAMPUS"), which is also what tells the two directions of a route apart.
public struct WatchLine: Sendable, Codable, Hashable {
  public let routeID: String
  public let headsign: String

  public init(routeID: String, headsign: String) {
    self.routeID = routeID
    self.headsign = headsign
  }
}

/// Something worth a notification.
public struct WatchEvent: Sendable, Hashable, Identifiable {
  public let kind: WatchKind
  public let routeID: String
  /// Late and early: how many buses are affected.
  public let buses: Int
  /// Late: the worst delay; early: how far ahead the earliest bus is. Seconds, always positive.
  public let seconds: Int
  /// Alerts: the alert's id, title and (shortened) text.
  public let alertID: String
  public let headline: String
  public let detail: String
  /// Late and early: which destination ("2-EPIC CAMPUS") and way ("Eastbound") of the route the buses are on, so that a
  /// late D2 and an early D1 are two messages that say which is which. Empty when the feed does not say.
  public let headsign: String
  public let directionName: String

  public init(
    kind: WatchKind, routeID: String, buses: Int, seconds: Int, alertID: String, headline: String, detail: String,
    headsign: String = "", directionName: String = ""
  ) {
    self.kind = kind
    self.routeID = routeID
    self.buses = buses
    self.seconds = seconds
    self.alertID = alertID
    self.headline = headline
    self.detail = detail
    self.headsign = headsign
    self.directionName = directionName
  }

  /// Late and early are told once per destination and cooldown; an alert once, however long it lasts.
  public var id: String {
    kind == .alert ? "alert|\(alertID)|\(routeID)" : "\(kind.rawValue)|\(routeID)|\(headsign)|\(directionName)"
  }

  /// "2" for "2-EPIC CAMPUS": the number that tells the destinations of a route apart.
  public var patternNumber: String {
    guard let dash = headsign.firstIndex(of: "-"), dash != headsign.startIndex, headsign[..<dash].allSatisfy(\.isNumber) else { return "" }
    return String(headsign[..<dash])
  }

  /// The destination without its number ("EPIC CAMPUS").
  public var destination: String {
    guard !patternNumber.isEmpty, let dash = headsign.firstIndex(of: "-") else { return headsign }
    return String(headsign[headsign.index(after: dash)...])
  }
}

public enum WatchEvaluator {
  /// How far ahead an alert that has not started yet is announced.
  public static let alertLookAhead: TimeInterval = 24 * 3600

  /// Events for what the rider watches: every destination of the whole `routes`, and the single destinations in `lines`.
  /// Buses are judged per destination and way (D2 eastbound on its own), limited to the `kinds` the rider asked for;
  /// `lateAfter` and `earlyAfter` are how far from the timetable a bus has to be, in seconds, to count.
  public static func evaluate(
    status: ServiceStatus?, alerts: [ServiceAlert], now: Date, routes: Set<String>, lines: Set<WatchLine> = [],
    kinds: Set<WatchKind>, lateAfter: TimeInterval = ServiceStatusBuilder.lateThreshold,
    earlyAfter: TimeInterval = -ServiceStatusBuilder.earlyThreshold
  ) -> [WatchEvent] {
    guard !routes.isEmpty || !lines.isEmpty, !kinds.isEmpty else { return [] }
    let linesOfRoute = Dictionary(grouping: lines, by: \.routeID)
    var events: [WatchEvent] = []

    if let status {
      struct Group: Hashable { let headsign: String; let direction: String }
      for row in status.routes {
        let whole = routes.contains(row.routeID)
        let chosen = Set((linesOfRoute[row.routeID] ?? []).map(\.headsign))
        guard whole || !chosen.isEmpty else { continue }
        var groups: [Group: [Double]] = [:]
        for bus in row.busDelays where whole || chosen.contains(bus.headsign) {
          groups[Group(headsign: bus.headsign, direction: bus.directionName), default: []].append(bus.seconds)
        }
        for (group, seconds) in groups {
          let late = seconds.filter { $0 > lateAfter }
          if kinds.contains(.late), let worst = late.max() {
            events.append(
              WatchEvent(
                kind: .late, routeID: row.routeID, buses: late.count, seconds: Int(worst.rounded()), alertID: "", headline: "", detail: "",
                headsign: group.headsign, directionName: group.direction))
          }
          let early = seconds.filter { $0 < -earlyAfter }
          if kinds.contains(.early), let earliest = early.min() {
            events.append(
              WatchEvent(
                kind: .early, routeID: row.routeID, buses: early.count, seconds: Int((-earliest).rounded()), alertID: "", headline: "",
                detail: "", headsign: group.headsign, directionName: group.direction))
          }
        }
      }
    }

    if kinds.contains(.alert) {
      for alert in alerts where isWorthTelling(alert, at: now) {
        // An alert belongs to a route, not to a destination: a rider watching one destination of it hears it too.
        for route in alert.routeIDs where routes.contains(route) || linesOfRoute[route] != nil {
          events.append(
            WatchEvent(kind: .alert, routeID: route, buses: 0, seconds: 0, alertID: alert.entityID, headline: alert.header, detail: alert.detail))
        }
      }
    }
    return events.sorted { ($0.routeID, $0.kind.rawValue, $0.headsign, $0.directionName, $0.alertID) < ($1.routeID, $1.kind.rawValue, $1.headsign, $1.directionName, $1.alertID) }
  }

  private static func isWorthTelling(_ alert: ServiceAlert, at now: Date) -> Bool {
    if alert.isActive(at: now) { return true }
    return alert.activePeriods.contains { period in
      guard let start = period.start else { return false }
      return start > now && start.timeIntervalSince(now) <= alertLookAhead
    }
  }
}

/// Remembers what the rider has already been told, so that a bus that stays late is not announced every minute.
public struct WatchLedger: Sendable, Codable, Equatable {
  /// When each event was last announced.
  public private(set) var told: [String: Date] = [:]

  public init() {}

  /// Minutes before a late or early route is announced again.
  public static let repeatAfter: TimeInterval = 45 * 60
  /// Entries older than this are forgotten (an alert is then announced again if it is still around).
  public static let forgetAfter: TimeInterval = 7 * 24 * 3600

  /// The events that have not been announced recently. They count as announced from now on.
  public mutating func fresh(_ events: [WatchEvent], now: Date) -> [WatchEvent] {
    told = told.filter { now.timeIntervalSince($0.value) < Self.forgetAfter }
    var result: [WatchEvent] = []
    for event in events {
      if let last = told[event.id] {
        // Alerts are announced once; late and early again after a while.
        if event.kind == .alert || now.timeIntervalSince(last) < Self.repeatAfter { continue }
      }
      told[event.id] = now
      result.append(event)
    }
    return result
  }
}
