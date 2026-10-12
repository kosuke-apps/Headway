import HeadwayCore
import SwiftUI

/// The full day's timetable for a stop: hours down the side, minutes across, one block per route and direction.
struct TimetableView: View {
  @Environment(AppModel.self) private var model
  let stopID: String

  @State private var dayOffset = 0
  @State private var routeFilter: String?

  var body: some View {
    let text = model.timeText()
    let departures = loadDepartures()
    let routeIDs = Array(Set(departures.map(\.routeID))).sorted { (model.route($0)?.sortOrder ?? .max, $0) < (model.route($1)?.sortOrder ?? .max, $1) }
    let stop = model.schedule?.stops[stopID]
    let delays = liveDelays()
    List {
      Section {
        if let side = Compass.bound(stop?.facing) {
          Label("\(side) · Stop \(stop?.code ?? "")", systemImage: Compass.symbol(stop?.facing)).font(.subheadline.weight(.semibold))
        }
        Picker("Day", selection: $dayOffset) {
          ForEach(0..<7, id: \.self) { Text(dayTitle($0)).tag($0) }
        }
        .pickerStyle(.menu)
        if routeIDs.count > 1 {
          Picker("Route", selection: $routeFilter) {
            Text("All routes").tag(String?.none)
            ForEach(routeIDs, id: \.self) { Text("Route \(model.route($0)?.shortName ?? $0)").tag(String?.some($0)) }
          }
          .pickerStyle(.menu)
        }
      } footer: {
        if !delays.isEmpty {
          Text("Times are the timetable's. Next to a bus that is being tracked, orange +3 means 3 minutes behind and blue −2 means 2 minutes ahead of its time right now.")
        }
      }
      if departures.isEmpty {
        Text("No service on this day.").foregroundStyle(.secondary)
      }
      ForEach(groups(departures), id: \.key) { group in
        Section {
          ForEach(hours(group.departures, text: text), id: \.hour) { row in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Text(row.hour).font(.subheadline.weight(.semibold)).monospacedDigit().frame(width: 54, alignment: .trailing)
              Text(minutesText(row.minutes, delays: delays)).font(.body).monospacedDigit()
              Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
          }
        } header: {
          HStack(spacing: 8) {
            RouteBadge(routeID: group.routeID, compact: true)
            Text(group.headsign.prettyHeadsign).textCase(nil).font(.subheadline.weight(.semibold))
            if let way = model.tripDirection(group.departures[0].tripID) { Text(way).textCase(nil).font(.caption).foregroundStyle(.secondary) }
          }
        }
      }
    }
    .navigationTitle(model.schedule?.stops[stopID]?.name ?? "")
    .navigationBarTitleDisplayMode(.inline)
  }

  // MARK: Data

  private func dayStart() -> Date {
    let zone = model.schedule?.timeZone ?? .current
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date()))!
  }

  private func dayTitle(_ offset: Int) -> String {
    let zone = model.schedule?.timeZone ?? .current
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date()))!
    if offset == 0 { return L10n.string("Today") }
    if offset == 1 { return L10n.string("Tomorrow") }
    let formatter = DateFormatter()
    formatter.timeZone = zone
    formatter.locale = LanguageState.shared.locale
    formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
    return formatter.string(from: date)
  }

  private func loadDepartures() -> [ScheduledDeparture] {
    guard let schedule = model.schedule else { return [] }
    let start = dayStart()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = schedule.timeZone
    let end = calendar.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-1)
    var all = schedule.scheduledDepartures(from: stopID, from: start, until: end)
    if !model.showHiddenRoutes { all = all.filter { !model.hiddenRoutes.contains($0.routeID) } }
    guard let routeFilter else { return all }
    return all.filter { $0.routeID == routeFilter }
  }

  private struct Group {
    let key: String
    let routeID: String
    let headsign: String
    let departures: [ScheduledDeparture]
  }

  private func groups(_ departures: [ScheduledDeparture]) -> [Group] {
    let grouped = Dictionary(grouping: departures) { "\($0.routeID)|\($0.headsign)" }
    return grouped.map { key, items in Group(key: key, routeID: items[0].routeID, headsign: items[0].headsign, departures: items) }
      .sorted { (model.route($0.routeID)?.sortOrder ?? .max, $0.key) < (model.route($1.routeID)?.sortOrder ?? .max, $1.key) }
  }

  private typealias Minute = (label: String, tripID: String)

  private func hours(_ departures: [ScheduledDeparture], text: TimeText) -> [(hour: String, minutes: [Minute])] {
    var rows: [(hour: String, minutes: [Minute])] = []
    for departure in departures.sorted(by: { $0.time < $1.time }) {
      let hour = text.hourLabel(departure.time)
      let minute: Minute = (text.minuteLabel(departure.time), departure.tripID)
      if let last = rows.last, last.hour == hour {
        rows[rows.count - 1].minutes.append(minute)
      } else {
        rows.append((hour, [minute]))
      }
    }
    return rows
  }

  /// How far each tracked bus of today is from its timetable time at this stop (seconds, late is positive), by trip.
  private func liveDelays() -> [String: Int] {
    guard dayOffset == 0, model.settings.values.showDelayDetails, model.settings.values.showScheduledTimes, let schedule = model.schedule else { return [:] }
    let found = Arrivals.upcoming(
      schedule: schedule, stopID: stopID, now: Date(), window: 8 * 3600, predictions: model.predictions, vehicles: model.vehicles, limit: 500)
    return found.reduce(into: [:]) { result, arrival in if let delay = arrival.delay { result[arrival.tripID] = delay } }
  }

  /// The minutes of an hour as the timetable has them; a bus that is being tracked has its delay beside its minute, in
  /// colour and small, so that the timetable's own time is never replaced.
  private func minutesText(_ minutes: [Minute], delays: [String: Int]) -> AttributedString {
    var result = AttributedString()
    for (index, minute) in minutes.enumerated() {
      if index > 0 { result += AttributedString("  ") }
      result += AttributedString(minute.label)
      guard let seconds = delays[minute.tripID] else { continue }
      guard let delay = TimeText.delayMark(seconds: seconds) else { continue }
      var mark = AttributedString(delay.text)
      mark.font = .caption.weight(.semibold)
      mark.foregroundColor = delay.minutes >= 5 ? .red : (delay.minutes > 0 ? .orange : .blue)
      result += AttributedString(" ") + mark
    }
    return result
  }
}
