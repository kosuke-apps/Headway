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

/// How old were the bus positions inside each recorded vehicle feed, by local hour? Answers "why do the positions sometimes
/// say 3 minutes old": is it the city's feed (its buses' reports arrive late) or the phone?
struct PositionAges {
  let recordings: Recordings
  var timeZone = TimeZone(identifier: "America/Chicago")!
  /// Snapshots whose median position is older than this are listed.
  var threshold: Double = 100

  func markdown() throws -> String {
    struct Row { var medians: [Double] = [] }
    var byHour: [Int: Row] = [:]
    var unreadable = 0
    var all: [(Date, Double)] = []
    var worst: [(Date, Double, Double, Int)] = []  // when, median age, feed age at fetch, buses
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    for file in recordings.files(of: .vehicles) {
      // A few recordings are empty or cut off (the city sent 15 bytes, or nothing): they are counted, not fatal.
      guard let data = try? gunzip(Data(contentsOf: file.url)), let snapshot = try? RealtimeDecoder.decode(data) else { unreadable += 1; continue }
      guard let header = snapshot.feedTimestamp else { continue }
      let ages = snapshot.vehicles.compactMap { $0.timestamp.map { header.timeIntervalSince($0) } }.sorted()
      guard ages.count >= 10 else { continue }
      let median = ages[ages.count / 2]
      let weekday = calendar.component(.weekday, from: file.recordedAt)
      _ = weekday
      byHour[calendar.component(.hour, from: file.recordedAt), default: Row()].medians.append(median)
      all.append((file.recordedAt, median))
      if median > threshold { worst.append((file.recordedAt, median, file.recordedAt.timeIntervalSince(header), ages.count)) }
    }
    func q(_ values: [Double], _ p: Double) -> Int {
      let sorted = values.sorted()
      return Int(sorted[min(sorted.count - 1, Int(p * Double(sorted.count)))].rounded())
    }
    var byDayHour: [String: [Double]] = [:]
    let dayFormatter = DateFormatter()
    dayFormatter.timeZone = timeZone
    dayFormatter.dateFormat = "MM-dd HH"
    for item in all { byDayHour[dayFormatter.string(from: item.0), default: []].append(item.1) }
    var perDay = "\n## Per day and hour (7 to 9 o'clock)\n\n| day hour | snapshots | median of medians s | max s |\n|---|---:|---:|---:|\n"
    for key in byDayHour.keys.sorted() where ["07", "08", "09"].contains(String(key.suffix(2))) {
      let m = byDayHour[key]!.sorted()
      perDay += "| \(key) | \(m.count) | \(Int(m[m.count / 2])) | \(Int(m.last!)) |\n"
    }
    var out = "# Age of the bus positions inside the city's feed\n\n\(unreadable) recordings could not be read.\n\nMedian over the buses of a snapshot (feed timestamp minus the position's own timestamp), by local hour.\n\n"
    out += "| hour | snapshots | median s | p90 s | share over 60 s | share over 120 s |\n|---|---:|---:|---:|---:|---:|\n"
    for hour in byHour.keys.sorted() {
      let m = byHour[hour]!.medians
      let over60 = Double(m.filter { $0 > 60 }.count) / Double(m.count) * 100, over120 = Double(m.filter { $0 > 120 }.count) / Double(m.count) * 100
      out += "| \(hour) | \(m.count) | \(q(m, 0.5)) | \(q(m, 0.9)) | \(String(format: "%.1f", over60))% | \(String(format: "%.1f", over120))% |\n"
    }
    out += "\nSnapshots whose median position was over \(Int(threshold)) s old: \(worst.count)\n\n| time | median age s | feed age at fetch s | buses |\n|---|---:|---:|---:|\n"
    let formatter = DateFormatter()
    formatter.timeZone = timeZone
    formatter.dateFormat = "MM-dd HH:mm:ss"
    for item in worst.prefix(400) { out += "| \(formatter.string(from: item.0)) | \(Int(item.1)) | \(Int(item.2)) | \(item.3) |\n" }
    return out + perDay
  }
}
