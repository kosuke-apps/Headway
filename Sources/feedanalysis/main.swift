import Foundation
import HeadwayCore

// Usage:
//   feedanalysis schedule <mmt_gtfs.zip>
//   feedanalysis sample   <recording-dir>
//   feedanalysis report   <recording-dir>
//   feedanalysis deviation <recording-dir>
//   feedanalysis punctuality <recordings-root> <output.json> [observations.sqlite] [--force]

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
  fail("usage: feedanalysis schedule <zip> | sample <dir> | report <dir>")
}
let directory = URL(fileURLWithPath: arguments[2])

/// The timetable to compare recordings with: the newest one under the recordings root.
func scheduleZip(_ directory: URL) -> URL {
  guard let zip = Recordings.latestSchedule(in: directory) else { fail("no mmt_gtfs.zip under \(directory.path)") }
  return zip
}

switch arguments[1] {
case "schedule":
  let clock = ContinuousClock()
  var schedule: Schedule!
  let elapsed = try clock.measure { schedule = try Schedule.load(zipAt: directory) }
  let stopTimeCount = schedule.stopTimes.values.reduce(0) { $0 + $1.count }
  print("loaded in \(elapsed)")
  print("feed \(schedule.feedVersion), \(schedule.feedStart?.value ?? 0)...\(schedule.feedEnd?.value ?? 0), zone \(schedule.timeZone.identifier)")
  print("routes \(schedule.routes.count), stops \(schedule.stops.count), trips \(schedule.trips.count)")
  print("stop times \(stopTimeCount), shapes \(schedule.shapes.count), services \(schedule.calendars.count)")
  let now = Date()
  let running = schedule.scheduledTrips(at: now)
  print("scheduled trips running now: \(running.count)")

case "sample":
  let recordings = try Recordings(directory: directory)
  for feed in RealtimeFeed.allCases {
    guard let last = recordings.files(of: feed).last else { continue }
    let snapshot = try RealtimeDecoder.decode(try gunzip(Data(contentsOf: last.url)))
    print("== \(feed.rawValue)  \(last.url.lastPathComponent)")
    print("feed timestamp \(snapshot.feedTimestamp.map { "\($0)" } ?? "none"), vehicles \(snapshot.vehicles.count), predictions \(snapshot.predictions.count), alerts \(snapshot.alerts.count)")
    for v in snapshot.vehicles.prefix(3) { print(v) }
    for p in snapshot.predictions.prefix(2) { print(p) }
    for a in snapshot.alerts { print(a.header, "|", a.detail.prefix(80), "|", a.url?.absoluteString ?? "no url", "| effect", a.effect, "| periods", a.activePeriods.map { "\($0.start.map { "\($0)" } ?? "-")..\($0.end.map { "\($0)" } ?? "-")" }, "| active now", a.isActive(at: Date()), "| routes", a.routeIDs, "stops", a.stopIDs.count) }
  }

case "shape":
  // How completely are the optional fields filled in? Uses the latest snapshot of each feed.
  let recordings = try Recordings(directory: directory)
  if let file = recordings.files(of: .vehicles).last {
    let s = try RealtimeDecoder.decode(try gunzip(Data(contentsOf: file.url)))
    let v = s.vehicles
    print("vehicles: \(v.count)  tripID set \(v.filter { !$0.tripID.isEmpty }.count)  routeID set \(v.filter { !$0.routeID.isEmpty }.count)  vehicleID set \(v.filter { !$0.vehicleID.isEmpty }.count)  stopID set \(v.filter { !$0.stopID.isEmpty }.count)  currentStopSequence set \(v.filter { $0.currentStopSequence != nil }.count)")
    let ages = v.compactMap { x in x.timestamp.map { (s.feedTimestamp ?? $0).timeIntervalSince($0) } }
    print("  position age vs feed timestamp (s): min \(ages.min() ?? 0) max \(ages.max() ?? 0)")
  }
  if let file = recordings.files(of: .trips).last {
    let s = try RealtimeDecoder.decode(try gunzip(Data(contentsOf: file.url)))
    let p = s.predictions
    print("predictions: \(p.count)  tripID set \(p.filter { !$0.tripID.isEmpty }.count)  vehicleID set \(p.filter { !$0.vehicleID.isEmpty }.count)  delay set \(p.filter { $0.delay != nil }.count)  startTime set \(p.filter { !$0.startTime.isEmpty }.count)  startDate set \(p.filter { !$0.startDate.isEmpty }.count)  directionID set \(p.filter { $0.directionID != nil }.count)")
    let relationships = Dictionary(grouping: p, by: \.scheduleRelationship).mapValues(\.count)
    print("  schedule relationship: \(relationships)")
    let stopUpdates = p.flatMap(\.stops)
    print("  stop updates: \(stopUpdates.count)  with arrival delay \(stopUpdates.filter { $0.arrivalDelay != nil }.count)  with departure delay \(stopUpdates.filter { $0.departureDelay != nil }.count)  skipped \(stopUpdates.filter(\.skipped).count)")
    let now = s.feedTimestamp ?? Date()
    let started = p.filter { ($0.stops.compactMap { $0.arrival ?? $0.departure }.min() ?? now) < now }
    print("  predictions whose earliest stop time is already past: \(started.count)")
    for q in started.prefix(2) { print("   ", q.routeID, q.stops.prefix(3).map { "\($0.stopID) seq \($0.sequence ?? -1) arr \($0.arrival.map { "\($0)" } ?? "-") dly \($0.arrivalDelay.map(String.init) ?? "-")" }) }
  }

case "fleet":
  // Which routes each fleet number (the vehicle id) runs on, in the latest position snapshot.
  let recordings = try Recordings(directory: directory)
  guard let file = recordings.files(of: .vehicles).last else { fail("no recordings") }
  let snapshot = try RealtimeDecoder.decode(try gunzip(Data(contentsOf: file.url)))
  let bySeries = Dictionary(grouping: snapshot.vehicles) { v -> String in
    guard let number = Int(v.vehicleID) else { return "other" }
    return number >= 1000 ? "\(number / 100)xx" : "\(number / 100)xx (3 digits)"
  }
  for (series, buses) in bySeries.sorted(by: { $0.key < $1.key }) {
    let routes = Dictionary(grouping: buses, by: { $0.routeID.isEmpty ? "(none)" : $0.routeID }).mapValues(\.count).sorted { $0.key < $1.key }
    print("\(series): \(buses.count) buses  routes \(routes.map { "\($0.key)×\($0.value)" }.joined(separator: " "))")
  }

case "layover":
  // Buses with no trip in the position feed: does the trip feed say which trip each will run next? Latest snapshots.
  let recordings = try Recordings(directory: directory)
  guard let vehicleFile = recordings.files(of: .vehicles).last, let tripFile = recordings.files(of: .trips).last else { fail("no recordings") }
  let positions = try RealtimeDecoder.decode(try gunzip(Data(contentsOf: vehicleFile.url)))
  let trips = try RealtimeDecoder.decode(try gunzip(Data(contentsOf: tripFile.url)))
  let idle = positions.vehicles.filter { $0.tripID.isEmpty }
  print("vehicles \(positions.vehicles.count), without a trip \(idle.count); predictions \(trips.predictions.count), with a vehicle \(trips.predictions.filter { !$0.vehicleID.isEmpty }.count)")
  let byVehicle = Dictionary(grouping: trips.predictions.filter { !$0.vehicleID.isEmpty }, by: \.vehicleID)
  for v in idle {
    let next = (byVehicle[v.vehicleID] ?? []).sorted { ($0.stops.compactMap { $0.arrival ?? $0.departure }.min() ?? .distantFuture) < ($1.stops.compactMap { $0.arrival ?? $0.departure }.min() ?? .distantFuture) }
    let first = next.first.map { p in "next trip \(p.tripID) route \(p.routeID) first stop \(p.stops.first?.stopID ?? "-") at \(p.stops.compactMap { $0.arrival ?? $0.departure }.min().map { "\($0)" } ?? "-")" } ?? "no trip assigned"
    print("  bus \(v.vehicleID) label \(v.label) at \(v.latitude),\(v.longitude) speed \(v.speed.map { "\($0)" } ?? "-"): \(first) (\(next.count) predictions)")
  }
  // The same for buses on a trip: is a second trip listed for them (the next one on the same block)?
  let running = positions.vehicles.filter { !$0.tripID.isEmpty }
  let withNext = running.filter { v in (byVehicle[v.vehicleID] ?? []).contains { $0.tripID != v.tripID } }
  print("buses on a trip \(running.count); with another trip listed for the same bus \(withNext.count)")

case "punctuality":
  // feedanalysis punctuality <recordings-root> <output.json> [observations.sqlite]
  guard arguments.count >= 4 else { fail("usage: feedanalysis punctuality <recordings-root> <output.json> [observations.sqlite]") }
  let schedule = try Schedule.load(zipAt: scheduleZip(directory))
  let output = URL(fileURLWithPath: arguments[3])
  let dbPath = arguments.count >= 5 ? arguments[4] : output.deletingLastPathComponent().appendingPathComponent("observations.sqlite").path
  let store = try ObservationStore(path: dbPath)
  let builder = PunctualityBuilder(schedule: schedule, recordings: try Recordings(directory: directory), store: store)
  try builder.ingest(force: arguments.contains("--force"))
  let table = try builder.export(to: output)
  print("wrote \(output.path): \(table.observations) observations over \(table.days) day(s) \(table.firstDay)...\(table.lastDay); \(table.routeCells.count) route cells, \(table.stopCells.count) stop cells")

case "accuracy":
  // feedanalysis accuracy <recordings-root> [observations.sqlite]
  let schedule = try Schedule.load(zipAt: scheduleZip(directory))
  let dbPath = arguments.count >= 4 ? arguments[3] : directory.deletingLastPathComponent().appendingPathComponent("punctuality/observations.sqlite").path
  print(try Accuracy(schedule: schedule, recordings: try Recordings(directory: directory), store: try ObservationStore(path: dbPath)).markdown())

case "early":
  // feedanalysis early <recordings-root> [observations.sqlite]
  let schedule = try Schedule.load(zipAt: scheduleZip(directory))
  let dbPath = arguments.count >= 4 ? arguments[3] : directory.deletingLastPathComponent().appendingPathComponent("punctuality/observations.sqlite").path
  print(try Accuracy(schedule: schedule, recordings: try Recordings(directory: directory), store: try ObservationStore(path: dbPath)).earlyArrivals())

case "notstarted":
  // feedanalysis notstarted <recordings-root> [observations.sqlite]
  let schedule = try Schedule.load(zipAt: scheduleZip(directory))
  let dbPath = arguments.count >= 4 ? arguments[3] : directory.deletingLastPathComponent().appendingPathComponent("punctuality/observations.sqlite").path
  print(try Accuracy(schedule: schedule, recordings: try Recordings(directory: directory), store: try ObservationStore(path: dbPath)).notStarted())

case "variants":
  // feedanalysis variants <recordings-root> <route id>
  guard arguments.count >= 4 else { fail("usage: feedanalysis variants <recordings-root> <route id>") }
  let schedule = try Schedule.load(zipAt: scheduleZip(directory))
  print(try Variants(schedule: schedule, recordings: try Recordings(directory: directory)).markdown(route: arguments[3]))

case "overview":
  // feedanalysis overview <recordings-root or mmt_gtfs.zip> <output.geojson>
  // The network view's lines with their lanes, to look at the layout outside the app (tools/preview/overview.html).
  guard arguments.count >= 4 else { fail("usage: feedanalysis overview <dir or zip> <output.geojson>") }
  let zip = directory.pathExtension == "zip" ? directory : scheduleZip(directory)
  let schedule = try Schedule.load(zipAt: zip)
  var tripOfShape: [String: Trip] = [:]
  for trip in schedule.trips.values where tripOfShape[trip.shapeID] == nil { tripOfShape[trip.shapeID] = trip }
  let inputs = schedule.shapes.compactMap { id, points -> BundleInput? in
    guard let trip = tripOfShape[id], let route = schedule.routes[trip.routeID] else { return nil }
    return BundleInput(route: route.id, order: route.sortOrder, direction: trip.directionID, shapeID: id, points: points)
  }
  let clock = ContinuousClock()
  var lines: [BundledLine] = []
  let elapsed = clock.measure { lines = RouteBundler.overview(inputs) }
  let features: [[String: Any]] = lines.map { line in
    [
      "type": "Feature",
      "properties": ["route": line.route, "lane": line.lane, "color": "#" + (schedule.routes[line.route]?.colorHex ?? "888888")],
      "geometry": ["type": "LineString", "coordinates": line.coordinates.map { [$0.longitude, $0.latitude] }],
    ]
  }
  let stops: [[String: Any]] = schedule.stops.values.map { stop in
    ["type": "Feature", "properties": ["name": stop.name, "facing": stop.facing ?? -1],
     "geometry": ["type": "Point", "coordinates": [stop.longitude, stop.latitude]]]
  }
  let collection: [String: Any] = ["type": "FeatureCollection", "features": features + stops]
  try JSONSerialization.data(withJSONObject: collection).write(to: URL(fileURLWithPath: arguments[3]))
  print("wrote \(lines.count) pieces and \(stops.count) stops in \(elapsed)")

case "offroute":
  // feedanalysis offroute <recordings-root> <routes, comma separated> <from yyyy-MM-ddTHH:mm> <to yyyy-MM-ddTHH:mm> <out.geojson> [min metres]
  // Positions of buses that were farther than `min metres` (default 60) from their trip's line, to see whether a detour
  // can be read from the recordings. Times are in the timetable's time zone.
  guard arguments.count >= 7 else { fail("usage: feedanalysis offroute <dir> <routes> <from> <to> <out.geojson> [metres]") }
  let schedule = try Schedule.load(zipAt: scheduleZip(directory))
  let wanted = Set(arguments[3].split(separator: ",").map(String.init))
  func parse(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = schedule.timeZone
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    guard let date = formatter.date(from: text) else { fail("bad time \(text)") }
    return date
  }
  let from = parse(arguments[4]), to = parse(arguments[5])
  let minimum = arguments.count >= 8 ? Double(arguments[7]) ?? 60 : 60
  let recordings = try Recordings(directory: directory)
  var features: [[String: Any]] = []
  var seen = Set<String>(), onLine = 0, off = 0
  for file in recordings.files(of: .vehicles) where file.recordedAt >= from && file.recordedAt <= to {
    let snapshot = try RealtimeDecoder.decode(try gunzip(Data(contentsOf: file.url)))
    for vehicle in snapshot.vehicles where wanted.contains(vehicle.routeID) && !vehicle.tripID.isEmpty {
      guard let time = vehicle.timestamp, seen.insert("\(vehicle.id)@\(time.timeIntervalSince1970)").inserted else { continue }
      guard let distance = schedule.distanceFromRoute(of: vehicle) else { continue }
      if distance > minimum {
        off += 1
        features.append([
          "type": "Feature",
          "properties": ["route": vehicle.routeID, "distance": Int(distance), "time": "\(time)", "speed": vehicle.speed ?? -1],
          "geometry": ["type": "Point", "coordinates": [vehicle.longitude, vehicle.latitude]],
        ])
      } else {
        onLine += 1
      }
    }
  }
  try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": features] as [String: Any]).write(to: URL(fileURLWithPath: arguments[6]))
  print("reports of routes \(wanted.sorted().joined(separator: ",")) between \(arguments[4]) and \(arguments[5]): \(onLine) on their line, \(off) more than \(Int(minimum)) m away")

case "freshness":
  print(try Freshness(recordings: try Recordings(directory: directory)).markdown())

case "ages":
  // feedanalysis ages <recordings-root>
  var ages = PositionAges(recordings: try Recordings(directory: directory))
  if arguments.count >= 4, let threshold = Double(arguments[3]) { ages.threshold = threshold }
  print(try ages.markdown())

case "deviation":
  let schedule = try Schedule.load(zipAt: scheduleZip(directory))
  print(try Deviation(schedule: schedule, recordings: try Recordings(directory: directory)).markdown())

case "plan":
  // feedanalysis plan <recording-dir> <from stop code or name> <to stop code or name> [HH:mm]
  guard arguments.count >= 5 else { fail("usage: feedanalysis plan <dir> <from> <to> [HH:mm]") }
  let schedule = try Schedule.load(zipAt: scheduleZip(directory))
  func find(_ query: String) -> Stop {
    let matches = schedule.stops.values.filter { $0.code == query || $0.name.localizedCaseInsensitiveContains(query) }
      .sorted { ($0.name, $0.code) < ($1.name, $1.code) }
    guard let stop = matches.first else { fail("no stop matches \(query)") }
    return stop
  }
  let fromStop = find(arguments[3]), toStop = find(arguments[4])
  var departure = Date()
  if arguments.count >= 6 {
    // "HH:mm" today, or "yyyy-MM-ddTHH:mm".
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = schedule.timeZone
    var components = calendar.dateComponents([.year, .month, .day], from: Date())
    var text = arguments[5]
    if let t = text.firstIndex(of: "T") {
      let day = text[..<t].split(separator: "-").compactMap { Int($0) }
      components.year = day[0]
      components.month = day[1]
      components.day = day[2]
      text = String(text[text.index(after: t)...])
    }
    let parts = text.split(separator: ":").compactMap { Int($0) }
    components.hour = parts[0]
    components.minute = parts[1]
    departure = calendar.date(from: components)!
  }
  func point(_ s: Stop) -> PlanPoint { PlanPoint(name: s.name, coordinate: Coordinate(latitude: s.latitude, longitude: s.longitude), stopID: s.id) }
  let formatter = DateFormatter()
  formatter.timeZone = schedule.timeZone
  formatter.dateFormat = "HH:mm"
  let clock = ContinuousClock()
  var journeys: [Journey] = []
  let elapsed = clock.measure {
    journeys = TripPlanner(schedule: schedule).plan(from: point(fromStop), to: point(toStop), departAt: departure)
  }
  print("\(fromStop.name) (\(fromStop.code)) -> \(toStop.name) (\(toStop.code)) at \(formatter.string(from: departure)); planned in \(elapsed)")
  for journey in journeys {
    print("\(formatter.string(from: journey.departure)) -> \(formatter.string(from: journey.arrival)) (\(Int(journey.duration / 60)) min, \(journey.transfers) transfers, walk \(Int(journey.walkingMeters)) m)")
    for leg in journey.legs {
      switch leg {
      case .walk(let w): print("   walk \(Int(w.meters)) m to \(w.to.name)  \(formatter.string(from: w.start))-\(formatter.string(from: w.end))")
      case .ride(let r): print("   route \(schedule.routes[r.routeID]?.shortName ?? r.routeID) to \(r.headsign): \(r.fromStop.name) \(formatter.string(from: r.depart)) -> \(r.toStop.name) \(formatter.string(from: r.arrive)) (\(r.stopCount) stops)")
      }
    }
  }

case "report":
  // `feedanalysis report <recording-dir>`; the schedule is read from <recording-dir>/mmt_gtfs.zip.
  let zip = scheduleZip(directory)
  let schedule = try Schedule.load(zipAt: zip)
  let report = Report(schedule: schedule, recordings: try Recordings(directory: directory))
  print(report.markdown(try report.run()))

default:
  fail("unknown command \(arguments[1])")
}
