import Foundation

public enum RealtimeFeed: String, CaseIterable, Sendable {
  case vehicles
  case trips
  case alerts
}

public enum RealtimeError: Error {
  case badStatus(Int)
}

/// Fetches and decodes the Madison Metro GTFS-Realtime feeds. No API key is needed.
public struct RealtimeClient: Sendable {
  public static let madisonBaseURL = URL(string: "https://metromap.cityofmadison.com/gtfsrt")!

  private let baseURL: URL
  private let session: URLSession
  private let onTransfer: (@Sendable (RealtimeFeed, Int) -> Void)?

  /// `onTransfer` is told how many bytes of body each successful request downloaded (the app's data meter).
  public init(
    baseURL: URL = RealtimeClient.madisonBaseURL, session: URLSession = .shared, onTransfer: (@Sendable (RealtimeFeed, Int) -> Void)? = nil
  ) {
    self.baseURL = baseURL
    self.session = session
    self.onTransfer = onTransfer
  }

  static func parseHTTPDate(_ text: String?) -> Date? {
    guard let text else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.date(from: text)
  }

  public func fetch(_ feed: RealtimeFeed) async throws -> RealtimeSnapshot {
    var request = URLRequest(url: baseURL.appendingPathComponent(feed.rawValue))
    request.timeoutInterval = 10
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let (data, response) = try await session.data(for: request)
    onTransfer?(feed, data.count)
    var serverDate: Date?
    if let http = response as? HTTPURLResponse {
      if !(200..<300).contains(http.statusCode) { throw RealtimeError.badStatus(http.statusCode) }
      serverDate = Self.parseHTTPDate(http.value(forHTTPHeaderField: "Date"))
    }
    var snapshot = try RealtimeDecoder.decode(data)
    snapshot.serverDate = serverDate
    return snapshot
  }
}
