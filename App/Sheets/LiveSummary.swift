import SwiftUI

/// The card that opens from the live-status bar over the map: how old the positions are, how many buses are on the road
/// and how many of them are late, on time and early, with a way to refresh and to the service board.
struct LiveSummary: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let age = model.positionAge(at: context.date)
      let fleet = model.fleetAll()
      let idle = model.idleBusCount
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text("\(model.vehicles.count)").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
          Text("buses on the road").foregroundStyle(.secondary)
        }
        if idle > 0 {
          Label("\(idle) not on a trip (out of service or waiting)", systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.orange)
        }
        HStack(spacing: 8) {
          tile(fleet.late, "Late", .red)
          tile(fleet.onTime, "On time", .green)
          tile(fleet.early, "Early", .blue)
          tile(fleet.total - fleet.measured, "No prediction", .gray)
        }
        if let age {
          Text("Positions are \(Int(age.rounded())) s old. Each bus reports about every 30 seconds (usually 25 to 35, sometimes up to a minute), and the city's feed is rebuilt about as often.")
            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if model.settings.values.estimateBusPositions {
          // The dashes are the only sign that a marker has been moved on from the last report.
          Label("A dashed ring: the bus is drawn where it probably is now, moved ahead of its last report.", systemImage: "circle.dashed")
            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        HStack {
          Button { model.refreshNow() } label: { Label("Refresh now", systemImage: "arrow.clockwise") }
          Spacer()
          Button {
            model.liveSummaryOpen = false
            model.mode = .info
          } label: { Label("Service info", systemImage: "chevron.right").labelStyle(.titleAndIcon) }
        }
        .font(.subheadline.weight(.medium))
      }
      .padding(16)
      .frame(width: 320)
    }
  }

  private func tile(_ number: Int, _ title: LocalizedStringKey, _ color: Color) -> some View {
    VStack(spacing: 2) {
      Text("\(number)").font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(color)
      Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}
