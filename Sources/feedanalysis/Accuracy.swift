import Foundation
import HeadwayCore

/// Are the live predictions better than the timetable? Compares each predicted arrival with the arrival observed
/// afterwards, grouped by how far ahead the prediction was made.
struct Accuracy {
  let schedule: Schedule
  let recordings: Recordings
  let store: ObservationStore

  struct Actual { let actual: Double; let scheduled: Double }

  static let horizons: [(name: String, range: Range<Double>)] = [
    ("0-2 min ahead", 0..<120), ("2-5 min", 120..<300), ("5-10 min", 300..<600), ("10-20 min", 600..<1200), ("20-30 min", 1200..<1800),
  ]

  /// Errors (predicted - observed) of live predictions and of the timetable, per horizon bin.
  func errors() throws -> (prediction: [[Double]], schedule: [[Double]], snapshots: Int) {
    // Observed arrivals: (trip, service day, sequence) -> actual and scheduled instants.
    var actuals: [String: Actual] = [:]
    try store.rows("SELECT day, trip, seq, sched, delay FROM obs") { statement in
      let scheduled = Double(ObservationStore.int(statement, 3))
      actuals["\(ObservationStore.text(statement, 1))|\(ObservationStore.int(statement, 0))|\(ObservationStore.int(statement, 2))"] =
        Actual(actual: scheduled + Double(ObservationStore.int(statement, 4)), scheduled: scheduled)
    }

    let bins = Self.horizons
    var predictionErrors = [[Double]](repeating: [], count: bins.count)
    var scheduleErrors = [[Double]](repeating: [], count: bins.count)
    var snapshots = 0

    for file in recordings.files(of: .trips) {
      let snapshot = try RealtimeDecoder.decode(try gunzip(Data(contentsOf: file.url)))
      snapshots += 1
      let now = file.recordedAt.timeIntervalSince1970
      for prediction in snapshot.predictions where !prediction.tripID.isEmpty && !prediction.vehicleID.isEmpty {
        guard let date = schedule.serviceDate(of: prediction.tripID, near: file.recordedAt) else { continue }
        for stop in prediction.stops where !stop.skipped {
          guard let sequence = stop.sequence, let predicted = (stop.arrival ?? stop.departure)?.timeIntervalSince1970,
            let observed = actuals["\(prediction.tripID)|\(date.value)|\(sequence)"]
          else { continue }
          let horizon = observed.actual - now
          guard let bin = bins.firstIndex(where: { $0.range.contains(horizon) }) else { continue }
          predictionErrors[bin].append(predicted - observed.actual)
          scheduleErrors[bin].append(observed.scheduled - observed.actual)
        }
      }
    }

    return (predictionErrors, scheduleErrors, snapshots)
  }

  /// The summary the app embeds.
  func bins() throws -> [PredictionBin] {
    let (prediction, _, _) = try errors()
    return prediction.enumerated().compactMap { index, list -> PredictionBin? in
      guard list.count >= 30 else { return nil }
      let sorted = list.sorted()
      func q(_ p: Double) -> Int { Int(sorted[min(sorted.count - 1, Int(p * Double(sorted.count)))].rounded()) }
      return PredictionBin(horizon: Int(Self.horizons[index].range.upperBound), n: list.count, q05: q(0.05), q50: q(0.5), q95: q(0.95))
    }
  }

  func markdown() throws -> String {
    let bins = Self.horizons
    let (predictionErrors, scheduleErrors, snapshots) = try errors()
    func stats(_ errors: [Double]) -> (median: Double, medianAbs: Double, p90Abs: Double) {
      guard !errors.isEmpty else { return (0, 0, 0) }
      let sorted = errors.sorted()
      let absolute = errors.map(abs).sorted()
      return (sorted[sorted.count / 2], absolute[absolute.count / 2], absolute[min(absolute.count - 1, Int(0.9 * Double(absolute.count)))])
    }
    var out = "# Are the live predictions better than the timetable?\n\n"
    out += "\(snapshots) trip-update snapshots compared with arrivals observed from bus positions. Error = predicted (or scheduled) time minus observed time, in seconds; positive means the prediction was later than reality.\n\n"
    out += "| horizon | n | live: bias | live: median abs | live: p90 abs | timetable: bias | timetable: median abs | timetable: p90 abs |\n|---|---:|---:|---:|---:|---:|---:|---:|\n"
    for (index, bin) in bins.enumerated() {
      let p = stats(predictionErrors[index]), s = stats(scheduleErrors[index])
      out += "| \(bin.name) | \(predictionErrors[index].count) | \(Int(p.median)) | \(Int(p.medianAbs)) | \(Int(p.p90Abs)) | \(Int(s.median)) | \(Int(s.medianAbs)) | \(Int(s.p90Abs)) |\n"
    }
    return out
  }
}

extension Accuracy {
  /// What the live predictions said about arrivals that were in fact early or late: for each observed arrival, the
  /// delay the prediction implied (predicted minus timetable) against the delay observed, predictions made 0-10
  /// minutes before the arrival. Shows whether the feed's predictions follow a bus that is well ahead of its timetable.
  func earlyArrivals() throws -> String {
    var actuals: [String: Actual] = [:]
    try store.rows("SELECT day, trip, seq, sched, delay FROM obs") { statement in
      let scheduled = Double(ObservationStore.int(statement, 3))
      actuals["\(ObservationStore.text(statement, 1))|\(ObservationStore.int(statement, 0))|\(ObservationStore.int(statement, 2))"] =
        Actual(actual: scheduled + Double(ObservationStore.int(statement, 4)), scheduled: scheduled)
    }
    // Observed delay classes, and for each the delays the predictions implied (seconds, negative = ahead of the timetable).
    let classes: [(name: String, range: Range<Double>)] = [
      ("observed more than 3 min early", -100_000..<(-180)), ("observed 1 to 3 min early", -180..<(-60)),
      ("observed within a minute", -60..<60), ("observed more than 5 min late", 300..<100_000),
    ]
    var implied = [[Double]](repeating: [], count: classes.count)
    for file in recordings.files(of: .trips) {
      let snapshot = try RealtimeDecoder.decode(try gunzip(Data(contentsOf: file.url)))
      let now = file.recordedAt.timeIntervalSince1970
      for prediction in snapshot.predictions where !prediction.tripID.isEmpty && !prediction.vehicleID.isEmpty {
        guard let date = schedule.serviceDate(of: prediction.tripID, near: file.recordedAt) else { continue }
        for stop in prediction.stops where !stop.skipped {
          guard let sequence = stop.sequence, let predicted = (stop.arrival ?? stop.departure)?.timeIntervalSince1970,
            let observed = actuals["\(prediction.tripID)|\(date.value)|\(sequence)"]
          else { continue }
          let horizon = observed.actual - now
          guard horizon >= 0, horizon < 600 else { continue }
          let observedDelay = observed.actual - observed.scheduled
          guard let index = classes.firstIndex(where: { $0.range.contains(observedDelay) }) else { continue }
          implied[index].append(predicted - observed.scheduled)
        }
      }
    }
    var out = "# What do the predictions say about early arrivals?\n\nPredictions made 0-10 minutes ahead, as the delay they imply (predicted minus timetable, seconds; negative is ahead of the timetable).\n\n"
    out += "| arrivals | n | implied delay p10 | median | p90 |\n|---|---:|---:|---:|---:|\n"
    for (index, item) in classes.enumerated() {
      let sorted = implied[index].sorted()
      guard !sorted.isEmpty else { continue }
      func q(_ p: Double) -> Int { Int(sorted[min(sorted.count - 1, Int(p * Double(sorted.count)))].rounded()) }
      out += "| \(item.name) | \(sorted.count) | \(q(0.1)) | \(q(0.5)) | \(q(0.9)) |\n"
    }
    return out
  }
}

extension Accuracy {
  /// How good are the predictions for a trip whose bus has not started it yet (it is still on its previous trip, or idle)?
  /// Compared with the predictions for buses already on the trip, and with the timetable, by the error of the arrival at
  /// each stop 0-30 minutes ahead (seconds, positive = predicted later than observed).
  func notStarted() throws -> String {
    var actuals: [String: Actual] = [:]
    try store.rows("SELECT day, trip, seq, sched, delay FROM obs") { statement in
      let scheduled = Double(ObservationStore.int(statement, 3))
      actuals["\(ObservationStore.text(statement, 1))|\(ObservationStore.int(statement, 0))|\(ObservationStore.int(statement, 2))"] =
        Actual(actual: scheduled + Double(ObservationStore.int(statement, 4)), scheduled: scheduled)
    }
    let vehicleFiles = recordings.files(of: .vehicles)
    guard !vehicleFiles.isEmpty else { return "no vehicle recordings\n" }
    let times = vehicleFiles.map { $0.recordedAt.timeIntervalSince1970 }
    var cachedIndex = -1
    var cachedTrips: [String: String] = [:]  // vehicle id -> trip id in the nearest position snapshot
    let names = ["bus already on this trip", "bus still on its previous trip", "bus with no trip"]
    var predictionErrors = [[Double]](repeating: [], count: 3)
    var scheduleErrors = [[Double]](repeating: [], count: 3)
    var impliedDelays = [[Double]](repeating: [], count: 3)
    var observedDelays = [[Double]](repeating: [], count: 3)
    var predictions = [Int](repeating: 0, count: 3)
    // Per kind, the delays the predictions implied for arrivals that turned out late (more than 5 min) or early (more than 2 min).
    var impliedWhenLate = [[Double]](repeating: [], count: 3)
    var impliedWhenEarly = [[Double]](repeating: [], count: 3)

    for file in recordings.files(of: .trips) {
      let now = file.recordedAt.timeIntervalSince1970
      var low = 0, high = times.count - 1
      while low < high {
        let mid = (low + high) / 2
        if times[mid] < now { low = mid + 1 } else { high = mid }
      }
      if low > 0, abs(times[low - 1] - now) < abs(times[low] - now) { low -= 1 }
      guard abs(times[low] - now) < 120 else { continue }
      if low != cachedIndex {
        let snapshot = try RealtimeDecoder.decode(try gunzip(Data(contentsOf: vehicleFiles[low].url)))
        cachedTrips = Dictionary(snapshot.vehicles.map { ($0.vehicleID, $0.tripID) }, uniquingKeysWith: { first, _ in first })
        cachedIndex = low
      }
      let snapshot = try RealtimeDecoder.decode(try gunzip(Data(contentsOf: file.url)))
      for prediction in snapshot.predictions where !prediction.tripID.isEmpty && !prediction.vehicleID.isEmpty {
        guard let date = schedule.serviceDate(of: prediction.tripID, near: file.recordedAt), let current = cachedTrips[prediction.vehicleID] else { continue }
        let kind = current == prediction.tripID ? 0 : (current.isEmpty ? 2 : 1)
        predictions[kind] += 1
        for stop in prediction.stops where !stop.skipped {
          guard let sequence = stop.sequence, let predicted = (stop.arrival ?? stop.departure)?.timeIntervalSince1970,
            let observed = actuals["\(prediction.tripID)|\(date.value)|\(sequence)"]
          else { continue }
          let horizon = observed.actual - now
          guard horizon >= 0, horizon < 1800 else { continue }
          predictionErrors[kind].append(predicted - observed.actual)
          scheduleErrors[kind].append(observed.scheduled - observed.actual)
          impliedDelays[kind].append(predicted - observed.scheduled)
          observedDelays[kind].append(observed.actual - observed.scheduled)
          if observed.actual - observed.scheduled > 300 { impliedWhenLate[kind].append(predicted - observed.scheduled) }
          if observed.actual - observed.scheduled < -120 { impliedWhenEarly[kind].append(predicted - observed.scheduled) }
        }
      }
    }
    func quantile(_ values: [Double], _ p: Double) -> Int {
      guard !values.isEmpty else { return 0 }
      let sorted = values.sorted()
      return Int(sorted[min(sorted.count - 1, Int(p * Double(sorted.count)))].rounded())
    }
    var out = "# Predictions for trips whose bus has not started them\n\nPredictions with an assigned bus, grouped by what that bus was doing in the position feed at the time; stops 0-30 minutes ahead that were later observed.\n\n"
    out += "| | predictions | stops | median |error| live | median |error| timetable | p90 |error| live | p90 |error| timetable | implied delay median | observed delay median |\n|---|---:|---:|---:|---:|---:|---:|---:|---:|\n"
    for kind in 0..<3 {
      let live = predictionErrors[kind].map(abs), table = scheduleErrors[kind].map(abs)
      out += "| \(names[kind]) | \(predictions[kind]) | \(live.count) | \(quantile(live, 0.5)) | \(quantile(table, 0.5)) | \(quantile(live, 0.9)) | \(quantile(table, 0.9)) | \(quantile(impliedDelays[kind], 0.5)) | \(quantile(observedDelays[kind], 0.5)) |\n"
    }
    out += "\nWhat the predictions implied (predicted minus timetable, seconds) for arrivals that turned out late or early:\n\n| | arrivals >5 min late: n | implied median | p10 | arrivals >2 min early: n | implied median | p90 |\n|---|---:|---:|---:|---:|---:|---:|\n"
    for kind in 0..<3 {
      out += "| \(names[kind]) | \(impliedWhenLate[kind].count) | \(quantile(impliedWhenLate[kind], 0.5)) | \(quantile(impliedWhenLate[kind], 0.1)) | \(impliedWhenEarly[kind].count) | \(quantile(impliedWhenEarly[kind], 0.5)) | \(quantile(impliedWhenEarly[kind], 0.9)) |\n"
    }
    return out
  }
}
