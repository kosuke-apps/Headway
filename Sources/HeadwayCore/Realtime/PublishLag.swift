import Foundation

/// How long after its own timestamp the city's vehicle feed turns up on the server (about 8 s, measured), learned from the
/// feeds the app has seen. Asking for the next feed that long after its stamp, instead of a second and a half, saves the
/// two-second retries that each downloaded the unchanged feed again.
public struct PublishLag: Sendable, Equatable {
  /// How old each of the last feeds was when it was first fetched on a scheduled attempt.
  private var ages: [TimeInterval] = []
  private let window = 10

  public init() {}

  /// Records the age (seconds since the feed's stamp, by the server's clock) of a new feed fetched on a scheduled attempt.
  /// Ages outside a sane range are ignored.
  public mutating func note(age: TimeInterval) {
    guard age >= 0, age < 60 else { return }
    ages.append(age)
    if ages.count > window { ages.removeFirst() }
  }

  /// The smallest recent age: a feed cannot have been fetched before it existed, so this is as close as the attempts have
  /// come to its publication. Four seconds until something has been seen; never under two and a half or over twenty.
  public var estimate: TimeInterval { min(20, max(2.5, ages.min() ?? 4)) }
}
