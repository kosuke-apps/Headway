import HeadwayCore
import SwiftUI

/// How a delay (seconds from the timetable) is coloured in the sheets of a bus and of a trip.
func tripDelayColor(_ delay: Int?) -> Color {
  guard let delay else { return .secondary }
  if delay > 300 { return .red }
  if delay > 90 { return .orange }
  if delay < -90 { return .blue }
  return .secondary
}

/// One stop of a trip: its name, the timetable's time and, for a bus that reports, how far it is from that. A stop the bus
/// has passed is greyed out and says nothing about delay.
struct TripStopRow: View {
  @Environment(AppModel.self) private var model
  let eta: TripStopEta

  var body: some View {
    let text = model.timeText()
    let stop = model.schedule?.stops[eta.stopID]
    let delay = eta.predicted.map { Int($0.timeIntervalSince(eta.scheduled).rounded()) }
    // With timetable times on, the time at the right is the timetable's; how far the bus is from it, and when it now
    // expects to arrive, are written under the stop's name instead of replacing it.
    let detailed = model.settings.values.showDelayDetails && model.settings.values.showScheduledTimes
    Button {
      model.selectStop(eta.stopID)
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(stop?.name ?? eta.stopID).font(.body).lineLimit(1)
          if !eta.passed, model.settings.values.showDelayDetails, let label = TimeText.delay(delay) {
            HStack(spacing: 4) {
              Text(label).foregroundStyle(detailed ? tripDelayColor(delay) : .secondary)
              if detailed, eta.predicted != nil, abs(delay ?? 0) >= 60 {
                Text("· Expected \(text.clock(eta.expected))").foregroundStyle(.secondary)
              }
            }
            .font(.caption)
          }
        }
        Spacer(minLength: 8)
        Text(text.clock(detailed || eta.passed ? eta.scheduled : eta.expected)).font(.body.weight(.medium)).monospacedDigit()
      }
      .padding(.horizontal, 16).padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(eta.passed ? Color.secondary : Color.primary)
    .opacity(eta.passed ? 0.55 : 1)
    .accessibilityElement(children: .combine)
    .accessibilityHint(eta.passed ? Text("The bus has passed this stop") : Text(""))
  }
}

/// All the stops of a trip, first to last, inside a `List`. The list starts on the last stop passed, so that the next one is
/// near the top and the rest of the way is below; scroll up for where the bus has been.
struct TripStopRows: View {
  let stops: [TripStopEta]

  /// The row to put at the top: the last stop passed, so that the rider sees it grey above the next one.
  var anchorID: Int? {
    guard let next = stops.firstIndex(where: { !$0.passed }) else { return stops.last?.id }
    return stops[max(0, next - 1)].id
  }

  var body: some View {
    ForEach(stops) { eta in
      TripStopRow(eta: eta)
        .id(eta.id)
        .listRowInsets(EdgeInsets())
    }
  }
}
