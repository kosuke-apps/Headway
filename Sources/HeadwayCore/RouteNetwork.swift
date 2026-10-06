import Foundation

/// One way a route runs: a direction with the destinations shown on its buses.
///
/// Madison has many one-way streets, so the two directions of a route often use different streets and stops. A route
/// can also have several destinations in one direction (for example a branch that runs only on weekdays).
public struct RouteVariant: Sendable, Codable, Hashable {
  public let route: String
  public let direction: Int
  /// "Westbound", "Eastbound", ... from the feed; empty when the feed has none.
  public let directionName: String
  /// The most common destinations in this direction, most trips first.
  public let headsigns: [String]
  public let trips: Int

  public init(route: String, direction: Int, directionName: String, headsigns: [String], trips: Int) {
    self.route = route
    self.direction = direction
    self.directionName = directionName
    self.headsigns = headsigns
    self.trips = trips
  }
}

/// One destination of a route in one direction ("2-EPIC CAMPUS" going west) and the stops its trips serve.
public struct RoutePattern: Sendable, Codable, Hashable, Identifiable {
  public let route: String
  public let direction: Int
  /// The headsign as the feed writes it, which is also what a bus's trip carries.
  public let headsign: String
  public let trips: Int
  public let stops: [String]

  public var id: String { "\(route)|\(direction)|\(headsign)" }

  public init(route: String, direction: Int, headsign: String, trips: Int, stops: [String]) {
    self.route = route
    self.direction = direction
    self.headsign = headsign
    self.trips = trips
    self.stops = stops
  }

  /// "2" for "2-EPIC CAMPUS": the number the city puts in front of a destination to tell the patterns of a route apart.
  public var number: String? {
    guard let dash = headsign.firstIndex(of: "-"), dash != headsign.startIndex else { return nil }
    let head = headsign[..<dash]
    return head.allSatisfy(\.isNumber) ? String(head) : nil
  }

  /// The destination without its number ("EPIC CAMPUS").
  public var destination: String {
    guard number != nil, let dash = headsign.firstIndex(of: "-") else { return headsign }
    return String(headsign[headsign.index(after: dash)...])
  }
}

/// Which routes serve which stops, and which stops each direction of each route serves.
public struct RouteNetwork: Sendable, Codable, Equatable {
  /// Route ids serving each stop, ordered like the route list.
  public let routesByStop: [String: [String]]
  public let variants: [RouteVariant]
  /// Stop ids served by a route in one direction, keyed by `key(route:direction:)`.
  public let stopsByDirection: [String: [String]]
  /// Each destination of each route in each direction, most trips first.
  public let patterns: [RoutePattern]

  public static func key(route: String, direction: Int) -> String { "\(route)|\(direction)" }

  public init(routesByStop: [String: [String]], variants: [RouteVariant], stopsByDirection: [String: [String]], patterns: [RoutePattern] = []) {
    self.routesByStop = routesByStop
    self.variants = variants
    self.stopsByDirection = stopsByDirection
    self.patterns = patterns
  }

  // A copy saved by an older version has no patterns: it still decodes, and is drawn until a new one is computed.
  private enum CodingKeys: String, CodingKey { case routesByStop, variants, stopsByDirection, patterns }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    routesByStop = try c.decode([String: [String]].self, forKey: .routesByStop)
    variants = try c.decode([RouteVariant].self, forKey: .variants)
    stopsByDirection = try c.decode([String: [String]].self, forKey: .stopsByDirection)
    patterns = try c.decodeIfPresent([RoutePattern].self, forKey: .patterns) ?? []
  }

  public init(schedule: Schedule) {
    func order(_ id: String) -> (Int, String) { (schedule.routes[id]?.sortOrder ?? .max, id) }

    var byStop: [String: [String]] = [:]
    for (stopID, visits) in schedule.visitsByStop {
      var routes: Set<String> = []
      for visit in visits { if let trip = schedule.trips[visit.tripID] { routes.insert(trip.routeID) } }
      byStop[stopID] = routes.sorted { order($0) < order($1) }
    }

    struct Group {
      var trips = 0
      var headsigns: [String: Int] = [:]
      var names: [String: Int] = [:]
      var stops: Set<String> = []
    }
    var groups: [String: Group] = [:]
    var patternGroups: [String: Group] = [:]
    for trip in schedule.trips.values {
      let key = Self.key(route: trip.routeID, direction: trip.directionID)
      var group = groups[key] ?? Group()
      group.trips += 1
      if !trip.headsign.isEmpty { group.headsigns[trip.headsign, default: 0] += 1 }
      if !trip.directionName.isEmpty { group.names[trip.directionName, default: 0] += 1 }
      for time in schedule.stopTimes[trip.id] ?? [] { group.stops.insert(time.stopID) }
      groups[key] = group
      if !trip.headsign.isEmpty {
        let patternKey = "\(key)|\(trip.headsign)"
        var pattern = patternGroups[patternKey] ?? Group()
        pattern.trips += 1
        for time in schedule.stopTimes[trip.id] ?? [] { pattern.stops.insert(time.stopID) }
        patternGroups[patternKey] = pattern
      }
    }

    var variants: [RouteVariant] = []
    var stops: [String: [String]] = [:]
    for (key, group) in groups {
      let parts = key.split(separator: "|")
      guard parts.count == 2, let direction = Int(parts[1]) else { continue }
      let route = String(parts[0])
      variants.append(
        RouteVariant(
          route: route, direction: direction,
          directionName: group.names.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? "",
          headsigns: group.headsigns.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(4).map(\.key),
          trips: group.trips))
      stops[key] = group.stops.sorted()
    }
    variants.sort {
      let a = order($0.route), b = order($1.route)
      return a != b ? a < b : $0.direction < $1.direction
    }
    var patterns: [RoutePattern] = []
    for (key, group) in patternGroups {
      let parts = key.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
      guard parts.count == 3, let direction = Int(parts[1]) else { continue }
      patterns.append(RoutePattern(route: String(parts[0]), direction: direction, headsign: String(parts[2]), trips: group.trips, stops: group.stops.sorted()))
    }
    patterns.sort {
      let a = order($0.route), b = order($1.route)
      if a != b { return a < b }
      return ($0.direction, -$0.trips, $0.headsign) < ($1.direction, -$1.trips, $1.headsign)
    }
    self.init(routesByStop: byStop, variants: variants, stopsByDirection: stops, patterns: patterns)
  }

  public func variants(of route: String) -> [RouteVariant] { variants.filter { $0.route == route } }

  /// The destinations of a route (in one direction, or both), most trips first.
  public func patterns(of route: String, direction: Int? = nil) -> [RoutePattern] {
    patterns.filter { $0.route == route && (direction == nil || $0.direction == direction) }
  }

  public func stops(route: String, direction: Int?) -> Set<String> {
    if let direction { return Set(stopsByDirection[Self.key(route: route, direction: direction)] ?? []) }
    return Set(variants(of: route).flatMap { stopsByDirection[Self.key(route: route, direction: $0.direction)] ?? [] })
  }
}
