import Foundation
import HeadwayCore

/// How "live" is the vehicle feed, really? Looks at three delays between a bus and the screen:
/// the bus's own report interval, the server's refresh interval, and how old a position already is when we fetch it.
struct Freshness {
  let recordings: Recordings

  func markdown() throws -> String {
    var feedStamps: [Date] = []          // distinct feed header timestamps, in order
    var ageAtFetch: [Double] = []        // fetch time - feed header timestamp
    var positionAge: [Double] = []       // feed header timestamp - vehicle position timestamp
    var lastStamp: [String: Date] = [:]  // vehicle -> last distinct position timestamp
    var reportIntervals: [Double] = []
    var intervalsByBus: [String: [Double]] = [:]
    var stale = 0, moving = 0
    var previousPosition: [String: (Double, Double)] = [:]
    var fetches = 0

    for file in recordings.files(of: .vehicles) {
      let snapshot = try RealtimeDecoder.decode(try gunzip(Data(contentsOf: file.url)))
      guard let header = snapshot.feedTimestamp else { continue }
      fetches += 1
      if feedStamps.last != header { feedStamps.append(header) }
      ageAtFetch.append(file.recordedAt.timeIntervalSince(header))
      for vehicle in snapshot.vehicles {
        guard let stamp = vehicle.timestamp else { continue }
        positionAge.append(header.timeIntervalSince(stamp))
        if let last = lastStamp[vehicle.id], stamp > last {
          reportIntervals.append(stamp.timeIntervalSince(last))
          intervalsByBus[vehicle.id, default: []].append(stamp.timeIntervalSince(last))
        }
        if lastStamp[vehicle.id] == nil || stamp > lastStamp[vehicle.id]! { lastStamp[vehicle.id] = stamp }
        // A bus that is moving but whose coordinates did not change since the last fetch is a stale position.
        if let speed = vehicle.speed, speed > 2 {
          moving += 1
          if let previous = previousPosition[vehicle.id], previous == (vehicle.latitude, vehicle.longitude) { stale += 1 }
        }
        previousPosition[vehicle.id] = (vehicle.latitude, vehicle.longitude)
      }
    }
    func pct(_ values: [Double], _ p: Double) -> String {
      guard !values.isEmpty else { return "-" }
      let sorted = values.sorted()
      return String(format: "%.0f", sorted[min(sorted.count - 1, Int(p * Double(sorted.count)))])
    }
    let feedIntervals = zip(feedStamps.dropFirst(), feedStamps).map { $0.timeIntervalSince($1) }
    var out = "# How live is the vehicle feed?\n\n\(fetches) fetches.\n\n"
    out += "| measure | median s | p90 s | max s |\n|---|---:|---:|---:|\n"
    out += "| server refresh interval (feed timestamp changes every) | \(pct(feedIntervals, 0.5)) | \(pct(feedIntervals, 0.9)) | \(pct(feedIntervals, 1)) |\n"
    out += "| age of the feed when fetched (fetch time - feed timestamp) | \(pct(ageAtFetch, 0.5)) | \(pct(ageAtFetch, 0.9)) | \(pct(ageAtFetch, 1)) |\n"
    out += "| age of a bus position inside the feed (feed timestamp - position timestamp) | \(pct(positionAge, 0.5)) | \(pct(positionAge, 0.9)) | \(pct(positionAge, 1)) |\n"
    out += "| time between two new reports from the same bus | \(pct(reportIntervals, 0.5)) | \(pct(reportIntervals, 0.9)) | \(pct(reportIntervals, 1)) |\n\n"
    let total = zip(ageAtFetch, positionAge.isEmpty ? [] : positionAge).map { $0 + $1 }
    _ = total
    // Is the interval the same for every bus, and is it steady? Shares of intervals by length, and the spread of the
    // typical (median) interval from bus to bus.
    let bands: [(String, Range<Double>)] = [("under 25 s", 0..<25), ("25-35 s", 25..<35), ("35-50 s", 35..<50), ("50-90 s", 50..<90), ("90 s or more", 90..<1e9)]
    out += "| time between two reports of one bus | share of all intervals |\n|---|---:|\n"
    for (name, range) in bands {
      let share = Double(reportIntervals.filter { range.contains($0) }.count) / Double(max(1, reportIntervals.count))
      out += "| \(name) | \(String(format: "%.1f", share * 100))% |\n"
    }
    let busMedians = intervalsByBus.filter { $0.value.count >= 20 }.map { $0.value.sorted()[$0.value.count / 2] }
    out += "\nMedian interval of each bus (\(busMedians.count) buses with at least 20 reports): lowest \(pct(busMedians, 0)) s, 10th percentile \(pct(busMedians, 0.1)) s, median \(pct(busMedians, 0.5)) s, 90th percentile \(pct(busMedians, 0.9)) s, highest \(pct(busMedians, 1)) s. Buses whose median is outside 28-33 s: \(busMedians.filter { $0 < 28 || $0 > 33 }.count).\n\n"
    out += "Moving buses (speed over 2 m/s) whose coordinates were identical to the previous fetch: \(stale) of \(moving).\n"
    return out
  }
}
