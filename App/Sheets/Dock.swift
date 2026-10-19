import HeadwayCore
import SwiftUI

/// What the rider put away, waiting at the bottom right of the map: the stop, the bus and the journey they were looking
/// at. A tap (or a swipe up) brings its sheet back and the cross lets go of it. They are stacked instead of laid in a
/// row, so even all three leave the map free, and each stays marked on the map while it waits.
struct Dock: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .trailing, spacing: 8) {
      if let vehicle = model.dockedVehicle { busChip(vehicle) }
      if let id = model.dockedStopID, let stop = model.schedule?.stops[id] { stopChip(stop) }
      if let journey = model.mapJourney { journeyChip(journey) }
    }
  }

  private func busChip(_ vehicle: VehicleSample) -> some View {
    let title = vehicle.tripID.isEmpty ? L10n.string("Not on a trip") : model.headsign(of: vehicle.tripID).prettyHeadsign
    var details = [L10n.string("Bus \(vehicle.vehicleID)")]
    if let seconds = model.vehicleDelays[vehicle.id], let delay = TimeText.delay(Int(seconds.rounded())) { details.append(delay) }
    return DockChip(
      title: title, subtitle: details.joined(separator: " · "), open: { model.reopenDockedBus() }, close: { model.closeDockedBus() }
    ) {
      if vehicle.routeID.isEmpty {
        Image(systemName: "bus.fill").foregroundStyle(.secondary).frame(minWidth: 30)
      } else {
        RouteBadge(routeID: vehicle.routeID, compact: true)
      }
    }
  }

  private func stopChip(_ stop: Stop) -> some View {
    var details: [String] = []
    if let side = Compass.bound(stop.facing) { details.append(side) }
    if !stop.code.isEmpty { details.append(L10n.string("Stop \(stop.code)")) }
    return DockChip(
      title: stop.name, subtitle: details.joined(separator: " · "), open: { model.reopenDockedStop() }, close: { model.closeDockedStop() }
    ) {
      Image(systemName: "mappin.circle.fill").font(.title3).foregroundStyle(.blue).frame(minWidth: 30)
    }
  }

  private func journeyChip(_ journey: Journey) -> some View {
    let text = model.timeText()
    return DockChip(
      title: "\(text.clock(journey.departure)) → \(text.clock(journey.arrival))", subtitle: L10n.string("Show journey steps"),
      open: { model.sheet = .journey }, close: { model.clearJourney() }
    ) {
      Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").font(.title3).foregroundStyle(.blue).frame(minWidth: 30)
    }
  }
}

/// One item of the dock: what it is (an icon or badge), a title and a line under it.
private struct DockChip<Icon: View>: View {
  let title: String
  let subtitle: String
  let open: () -> Void
  let close: () -> Void
  @ViewBuilder let icon: () -> Icon

  var body: some View {
    HStack(spacing: 0) {
      Button(action: open) {
        HStack(spacing: 10) {
          icon()
          VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1)
            if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
          }
          Image(systemName: "chevron.up").font(.caption.weight(.bold)).foregroundStyle(.secondary)
        }
        .padding(.leading, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)
      .accessibilityHint(Text("Shows the details again"))
      Button(action: close) {
        Image(systemName: "xmark.circle.fill").font(.title3).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
          .frame(width: 38, height: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text("Close"))
    }
    .frame(maxWidth: 290)
    .fixedSize(horizontal: true, vertical: false)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    // Swiping a chip up brings its sheet back, like pulling up a sheet.
    .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height < -30 { open() } })
  }
}
