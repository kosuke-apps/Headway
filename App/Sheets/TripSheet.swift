import HeadwayCore
import SwiftUI

/// One trip that no bus is reporting on (yet): all its stops with the timetable's times, first to last. It opens from a row
/// of the stop board that has no bus; a bus that turns up makes it the bus's sheet.
struct TripSheet: View {
  @Environment(AppModel.self) private var model
  let tripID: String
  let date: ServiceDate

  var body: some View {
    NavigationStack {
      if let trip = model.schedule?.trips[tripID] {
        ScrollViewReader { proxy in
          VStack(spacing: 0) {
            header(trip)
            Divider()
            TimelineView(.periodic(from: .now, by: 30)) { _ in
              let stops = model.tripStops(tripID: tripID, on: date)
              let rows = TripStopRows(stops: stops)
              List {
                if stops.isEmpty {
                  Text("No stops are known for this trip.").foregroundStyle(.secondary)
                } else {
                  Section("Stops") { rows }
                }
              }
              .listStyle(.plain)
              .task(id: tripID) {
                await Task.yield()
                if let id = rows.anchorID { proxy.scrollTo(id, anchor: .top) }
              }
            }
          }
          .navigationBarHidden(true)
        }
      } else {
        ContentUnavailableView {
          Label("This trip is not in the timetable", systemImage: "bus")
        } actions: {
          Button("Close") { model.clearSelection() }
        }
      }
    }
  }

  private func header(_ trip: Trip) -> some View {
    let text = model.timeText()
    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 12) {
        RouteBadge(routeID: trip.routeID)
        VStack(alignment: .leading, spacing: 2) {
          Text(trip.headsign.prettyHeadsign).font(.title3.weight(.semibold)).lineLimit(2)
          HStack(spacing: 6) {
            Image(systemName: "clock")
            Text(status(trip, text: text))
          }
          .font(.footnote).foregroundStyle(.secondary)
          if let way = model.tripDirection(tripID) {
            Text(way).font(.footnote).foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 8)
        Button { model.clearSelection() } label: {
          Image(systemName: "xmark.circle.fill").font(.title3).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary).frame(width: 36, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close"))
      }
      if let stopID = model.returnStopID, let stop = model.schedule?.stops[stopID] {
        Button {
          model.selectStop(stopID)
        } label: {
          Label("Back to \(stop.name)", systemImage: "chevron.backward").font(.footnote.weight(.medium))
        }
      }
    }
    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
  }

  /// "Timetable · no position yet", with how long ago the first stop's time was when it has passed.
  private func status(_ trip: Trip, text: TimeText) -> String {
    guard let first = model.tripStops(tripID: tripID, on: date).first else { return L10n.string("Timetable only") }
    let minutes = Int(Date().timeIntervalSince(first.scheduled) / 60)
    if minutes >= 1 { return L10n.string("No bus seen yet · due \(minutes) min ago") }
    return L10n.string("Timetable only · no position yet")
  }
}
