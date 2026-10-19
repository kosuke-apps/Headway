import HeadwayCore
import SwiftUI

/// The board for one stop: what is coming next, live where possible, and a way into the full timetable.
struct StopSheet: View {
  @Environment(AppModel.self) private var model
  let stopID: String

  var body: some View {
    NavigationStack {
      if let stop = model.schedule?.stops[stopID] {
        VStack(spacing: 0) {
          header(stop)
          Divider()
          board
        }
        .navigationBarHidden(true)
        .navigationDestination(for: String.self) { id in TimetableView(stopID: id) }
        .navigationDestination(for: PunctualityTarget.self) { PunctualityDetail(target: $0) }
      } else {
        ContentUnavailableView("Stop not found", systemImage: "mappin.slash")
      }
    }
  }

  // MARK: Header

  private func header(_ stop: Stop) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(stop.name).font(.title3.weight(.semibold)).lineLimit(2)
          HStack(spacing: 6) {
            // The same name is often used for the stops on both sides of a street: say which side this is.
            if let side = Compass.bound(stop.facing) {
              Label(side, systemImage: Compass.symbol(stop.facing)).foregroundStyle(.primary).fontWeight(.semibold)
              Text("·")
            }
            if !stop.code.isEmpty { Text("Stop \(stop.code)") }
            if let distance = distance(to: stop) { Text("· \(distance)") }
          }
          .font(.footnote).foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        Button {
          model.startDirections(to: PlanPoint(name: stop.name, coordinate: Coordinate(latitude: stop.latitude, longitude: stop.longitude), stopID: stop.id))
        } label: {
          Image(systemName: "arrow.triangle.turn.up.right.circle.fill").font(.title2).symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.accentColor).frame(width: 40, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Directions to here"))
        Button { model.settings.toggleFavorite(stop: stop.id) } label: {
          Image(systemName: model.settings.isFavorite(stop: stop.id) ? "star.fill" : "star")
            .font(.title3).foregroundStyle(model.settings.isFavorite(stop: stop.id) ? Color.orange : .secondary)
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel(model.settings.isFavorite(stop: stop.id) ? Text("Remove from favorites") : Text("Add to favorites"))
        Button { model.clearSelection() } label: {
          Image(systemName: "xmark.circle.fill").font(.title3).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary).frame(width: 36, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close"))
      }
      let routes = model.visibleRoutes(atStop: stop.id)
      if !routes.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) { ForEach(routes, id: \.self) { RouteBadge(routeID: $0, compact: true) } }
        }
      }
    }
    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
  }

  private func distance(to stop: Stop) -> String? {
    guard let here = model.location.location else { return nil }
    let meters = here.distance(from: .init(latitude: stop.latitude, longitude: stop.longitude))
    return meters < 20_000 ? TimeText.distance(meters) : nil
  }

  // MARK: Board

  private var board: some View {
    List {
      let alerts = model.alerts(forStop: stopID)
      if !alerts.isEmpty {
        Section {
          ForEach(alerts) { AlertRow(alert: $0) }
        }
      }
      let arrivals = model.boardArrivals
      if arrivals.isEmpty {
        Text(LocalizedStringKey(model.schedule == nil ? "Loading timetable…" : "No buses are scheduled here soon."))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .listRowSeparator(.hidden)
      } else {
        if model.arrivalsAreLater {
          Label("No more buses for a while. Service resumes:", systemImage: "moon.zzz")
            .font(.footnote).foregroundStyle(.secondary).listRowSeparator(.hidden)
        }
        // A stop served in more than one direction (a terminus, a loop) says which way each bus goes.
        let ways = Dictionary(uniqueKeysWithValues: arrivals.map { ($0.id, model.tripDirection($0.tripID)) })
        let mixed = Set(ways.values.compactMap { $0 }).count > 1
        TimelineView(.periodic(from: .now, by: 10)) { context in
          VStack(spacing: 0) {
            ForEach(arrivals) { arrival in
              ArrivalRow(arrival: arrival, now: context.date, direction: mixed ? ways[arrival.id] ?? nil : nil)
              if arrival.id != arrivals.last?.id { Divider() }
            }
          }
        }
        .listRowInsets(EdgeInsets())
      }
      reliabilitySection
      if model.hiddenArrivalCount > 0 || model.showHiddenRoutes, !model.hiddenRoutes.isEmpty {
        Toggle(isOn: Bindable(model).showHiddenRoutes) {
          Text("Show hidden routes").font(.footnote)
        }
        .onChange(of: model.showHiddenRoutes) { _, _ in model.refreshArrivals() }
      }
      NavigationLink(value: stopID) {
        Label("Full timetable", systemImage: "calendar.day.timeline.left")
      }
    }
    .listStyle(.plain)
  }
}

extension StopSheet {
  /// How early, on time and late each route has been here at this time of day.
  @ViewBuilder fileprivate var reliabilitySection: some View {
    let routes = model.visibleRoutes(atStop: stopID)
    let matches = routes.compactMap { route in model.reliability(route: route, stop: stopID).map { (route, $0) } }
    if !matches.isEmpty {
      Section {
        // Touching a graph opens the history behind it.
        ForEach(matches, id: \.0) { route, match in
          NavigationLink(value: PunctualityTarget(route: route, stop: stopID, dayType: match.dayType, wholeRoute: match.scope == .route)) {
            ReliabilityRow(routeID: route, match: match)
          }
        }
      } header: {
        Text("Usually at this stop")
      } footer: {
        VStack(alignment: .leading, spacing: 6) {
          Text("Early means more than a minute before the timetable, late more than five minutes after. Ranges next to live times show where the bus turned up in 9 of 10 past cases for predictions this far ahead.")
          if model.punctuality.days < 7 {
            Text("Only \(model.punctuality.days) days have been recorded so far, so these numbers are rough. They improve as recordings accumulate.")
              .foregroundStyle(.orange)
          }
        }
        .font(.footnote)
      }
    } else if model.punctuality.days > 0, !routes.isEmpty {
      Text("Not enough history for this time yet.").font(.footnote).foregroundStyle(.secondary).listRowSeparator(.hidden)
    }
  }
}

struct ArrivalRow: View {
  @Environment(AppModel.self) private var model
  let arrival: Arrival
  let now: Date
  /// The trip's direction ("Southbound"), shown only where a stop is served in more than one direction.
  var direction: String? = nil

  var body: some View {
    let text = model.timeText()
    // With the timetable's time first, the time at the right is the timetable's, and what is live (the countdown, how late
    // or early) goes under it: a live time never replaces the timetable's.
    let full = model.settings.values.showDelayDetails && model.settings.values.showScheduledTimes
    Button {
      if let vehicle = arrival.vehicle { model.selectBus(vehicle.id) }
    } label: {
      HStack(spacing: 12) {
        RouteBadge(routeID: arrival.routeID)
        VStack(alignment: .leading, spacing: 2) {
          // The way a bus goes (at a terminus, where both directions stop) sits after the destination, so that the line
          // below keeps its room for the live status and the timetable time.
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(arrival.headsign.prettyHeadsign).font(.body).lineLimit(1).layoutPriority(1)
            if let way = direction { Text(way).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
          }
          LiveStatus(arrival: arrival, showDelay: model.settings.values.showDelayDetails, scheduled: nil, untracked: arrival.vehicle == nil)
        }
        Spacer(minLength: 8)
        if full {
          fullTimes(text)
        } else {
        VStack(alignment: .trailing, spacing: 1) {
          Text(text.arrival(arrival, now: now))
            .font(.title3.weight(arrival.status == .live ? .semibold : .regular)).monospacedDigit()
          if let window = model.window(for: arrival, now: now),
            let range = model.settings.values.arrivalStyle == .countdown && arrival.minutes(from: now) < 60
              ? TimeText.minuteRange(earliest: window.earliest, latest: window.latest, now: now)
              : text.clockRange(earliest: window.earliest, latest: window.latest)
          {
            // Where the bus has turned up in 9 of 10 past cases for a prediction this far ahead.
            Text(range).font(.caption).foregroundStyle(.secondary).monospacedDigit()
          } else if model.settings.values.arrivalStyle == .countdown, arrival.minutes(from: now) < 60 {
            Text(text.clock(arrival.expected)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
          }
        }
        }
        // A bus that reports a position opens on the map; a trip without one has nothing to open.
        if arrival.vehicle != nil {
          Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
      }
      .padding(.horizontal, 16).padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // Only buses with a position can be shown on the map; timetable-only rows stay fully legible but do nothing.
    .allowsHitTesting(arrival.vehicle != nil)
    .accessibilityElement(children: .combine)
  }
}

extension ArrivalRow {
  /// The right side of a row that leads with the timetable: its time, then, for a bus that is live (or soon due), the
  /// countdown to when it is expected, coloured by how late or early it is.
  @ViewBuilder fileprivate func fullTimes(_ text: TimeText) -> some View {
    VStack(alignment: .trailing, spacing: 1) {
      Text(text.clock(arrival.scheduled)).font(.title3).monospacedDigit()
      let minutes = arrival.minutes(from: now)
      if arrival.status == .live {
        // Live: when it is expected, as a countdown when near and as a clock time otherwise.
        let expected = model.settings.values.arrivalStyle == .countdown && minutes < 60 ? text.arrival(arrival, now: now) : text.clock(arrival.expected)
        Text(expected).font(.caption.weight(.semibold)).foregroundStyle(liveColor).monospacedDigit()
      } else if model.settings.values.arrivalStyle == .countdown, minutes < 60 {
        Text(text.arrival(arrival, now: now)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
      }
      if let window = model.window(for: arrival, now: now),
        let range = model.settings.values.arrivalStyle == .countdown && minutes < 60
          ? TimeText.minuteRange(earliest: window.earliest, latest: window.latest, now: now)
          : text.clockRange(earliest: window.earliest, latest: window.latest)
      {
        Text(range).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
      }
    }
  }

  private var liveColor: Color {
    guard let delay = arrival.delay else { return .green }
    if delay > 300 { return .red }
    if delay > 90 { return .orange }
    if delay < -90 { return .blue }
    return .green
  }
}

/// A service alert such as a detour. The headline always shows; the details open on tap.
struct AlertRow: View {
  let alert: ServiceAlert
  @State private var expanded = false

  var body: some View {
    Button {
      if !alert.detail.isEmpty { withAnimation(.snappy) { expanded.toggle() } }
    } label: {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 4) {
          Text(alert.header).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
          if expanded, !alert.detail.isEmpty {
            Text(alert.detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            if let url = alert.url {
              Link(destination: url) { Label("Detour details", systemImage: "arrow.up.right.square") }
                .font(.footnote.weight(.medium))
            }
          }
        }
        Spacer(minLength: 0)
        if !alert.detail.isEmpty {
          Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityHint(alert.detail.isEmpty ? Text("") : Text("Shows details"))
  }
}
