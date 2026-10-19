import Foundation
import Network

/// Whether the phone is on a connection that costs the rider data: mobile data or a personal hotspot (`isExpensive`), or
/// any connection while Low Data Mode is on (`isConstrained`). Read by the code that decides how often to fetch.
final class NetworkStatus: @unchecked Sendable {
  static let shared = NetworkStatus()

  private let monitor = NWPathMonitor()
  private let lock = NSLock()
  private var expensive = false
  private var constrained = false
  private var started = false

  var isExpensive: Bool { lock.withLock { expensive } }
  var isConstrained: Bool { lock.withLock { constrained } }

  /// Starts watching the connection; harmless to call again.
  func start() {
    let already = lock.withLock { () -> Bool in
      defer { started = true }
      return started
    }
    guard !already else { return }
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      self.lock.withLock {
        self.expensive = path.isExpensive
        self.constrained = path.isConstrained
      }
    }
    monitor.start(queue: DispatchQueue(label: "dev.kosuke.headway.network"))
  }

  /// How much longer than usual to wait between large downloads: 1 on Wi-Fi, 2 on mobile data, 4 in Low Data Mode.
  /// `saving` is the rider's "Save mobile data" choice; without it the connection is treated as free.
  func slowdown(saving: Bool) -> Double {
    guard saving else { return 1 }
    if isConstrained { return 4 }
    return isExpensive ? 2 : 1
  }
}
