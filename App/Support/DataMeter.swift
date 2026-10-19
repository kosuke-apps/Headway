import Foundation
import HeadwayCore
import Observation

/// What the app downloads, by kind.
enum DataKind: String, Codable, CaseIterable, Identifiable {
  case positions, predictions, alerts, timetable
  var id: String { rawValue }

  init(_ feed: RealtimeFeed) {
    switch feed {
    case .vehicles: self = .positions
    case .trips: self = .predictions
    case .alerts: self = .alerts
    }
  }
}

/// Bytes downloaded since a date, by kind, on Wi-Fi and on mobile data (or in Low Data Mode). Only the bodies of the
/// responses are counted, not the headers or the connection set-up, so iOS Settings shows a little more.
struct DataUsage: Codable, Equatable {
  var since: Date
  private var wifi: [String: Int] = [:]
  private var mobile: [String: Int] = [:]

  init(since: Date = Date()) { self.since = since }

  mutating func add(_ kind: DataKind, bytes: Int, metered: Bool) {
    guard bytes > 0 else { return }
    if metered { mobile[kind.rawValue, default: 0] += bytes } else { wifi[kind.rawValue, default: 0] += bytes }
  }

  func bytes(_ kind: DataKind, metered: Bool) -> Int { (metered ? mobile : wifi)[kind.rawValue] ?? 0 }
  func bytes(metered: Bool) -> Int { DataKind.allCases.reduce(0) { $0 + bytes($1, metered: metered) } }
  func bytes(_ kind: DataKind) -> Int { bytes(kind, metered: false) + bytes(kind, metered: true) }
}

/// The data meter shown in Settings > Mobile data. Kept on the phone only.
@MainActor @Observable
final class DataMeter {
  static let shared = DataMeter()

  private(set) var usage: DataUsage
  @ObservationIgnored private let defaults: UserDefaults
  private static let key = "dataUsage.v1"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(DataUsage.self, from: data) {
      usage = saved
    } else {
      usage = DataUsage()
    }
  }

  func record(_ kind: DataKind, bytes: Int, metered: Bool) {
    usage.add(kind, bytes: bytes, metered: metered)
    if let data = try? JSONEncoder().encode(usage) { defaults.set(data, forKey: Self.key) }
  }

  func reset() {
    usage = DataUsage()
    if let data = try? JSONEncoder().encode(usage) { defaults.set(data, forKey: Self.key) }
  }
}
