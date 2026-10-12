import Charts
import HeadwayCore
import SwiftUI

/// What a punctuality graph is about: a route, and a stop when the graph was for one.
struct PunctualityTarget: Hashable {
  let route: String
  let stop: String?
  /// What the graph that was touched showed: the kind of day, and whether it was the whole route.
  let dayType: DayType
  let wholeRoute: Bool
}

/// The history behind "75% on time": hour by hour for one kind of day, how many buses were early, on time and late, and
/// how far from the timetable most of them were. Opens from the bar under "Usually at this stop".
struct PunctualityDetail: View {
  @Environment(AppModel.self) private var model
  let target: PunctualityTarget

  @State private var dayType: DayType
  @State private var wholeRoute: Bool
  @State private var selectedHour: Double?

  init(target: PunctualityTarget) {
    self.target = target
    _dayType = State(initialValue: target.dayType)
    _wholeRoute = State(initialValue: target.wholeRoute || target.stop == nil)
  }

  private var stop: String? { wholeRoute ? nil : target.stop }
  private var table: PunctualityTable { model.punctuality }

  private let early = Color.blue, onTime = Color.green, late = Color.orange

  var body: some View {
    let slices = table.hourly(route: target.route, stop: stop, dayType: dayType)
    let totals = table.totals(route: target.route, stop: stop, dayType: dayType)
    List {
      Section {
        HStack(spacing: 10) {
          RouteBadge(routeID: target.route)
          VStack(alignment: .leading, spacing: 2) {
            Text(model.route(target.route)?.longName ?? "").font(.subheadline).lineLimit(2)
            if let stopID = stop, let name = model.schedule?.stops[stopID]?.name {
              Text(name).font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
        Picker("Day", selection: $dayType) {
          Text("Weekdays").tag(DayType.weekday)
          Text("Saturdays").tag(DayType.saturday)
          Text("Sundays").tag(DayType.sunday)
        }
        .pickerStyle(.segmented)
        if target.stop != nil {
          Picker("Where", selection: $wholeRoute) {
            Text("This stop").tag(false)
            Text("Whole route").tag(true)
          }
          .pickerStyle(.segmented)
        }
      }

      if slices.isEmpty {
        Section {
          Text("Not enough history for this yet. Headway keeps recording, so it fills in as days go by.")
            .foregroundStyle(.secondary)
        }
      } else {
        if let totals { overall(totals) }
        Section {
          sharesChart(slices)
          legend
          selectionLine(slices)
        } header: {
          Text("By hour of the day")
        } footer: {
          if stop != nil { Text("Figures for a stop come in two-hour blocks, so the bars of a block are equal.") }
        }
        Section {
          spreadChart(slices)
        } header: {
          Text("How far from the timetable")
        } footer: {
          Text("The bar spans where 8 of 10 buses were (from the 10th to the 90th percentile); the dot is the middle bus. Below the line the bus was early, above it late.")
        }
      }

      Section {
        Text("Early means more than a minute before the timetable (a rider who arrives on time misses the bus), late more than five minutes after it. The numbers come from recorded bus positions compared with the timetable.")
          .font(.footnote).foregroundStyle(.secondary)
        Text("\(table.days) days recorded (\(table.firstDay) to \(table.lastDay)). \(table.observations) arrivals in all. Only hours with enough arrivals are drawn.")
          .font(.footnote).foregroundStyle(.secondary)
        if table.days < 7 {
          Text("Only \(table.days) days have been recorded so far, so these numbers are rough.").font(.footnote).foregroundStyle(.orange)
        }
      } header: {
        Text("About these numbers")
      }
    }
    .navigationTitle(L10n.string("Punctuality"))
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: dayType) { _, _ in selectedHour = nil }
    .onChange(of: wholeRoute) { _, _ in selectedHour = nil }
  }

  // MARK: Pieces

  private func overall(_ totals: PunctualityTable.Totals) -> some View {
    Section {
      HStack(spacing: 0) {
        figure(totals.earlyShare, "Early", early)
        figure(totals.onTimeShare, "On time", onTime)
        figure(totals.lateShare, "Late", late)
      }
      Text("\(totals.n) arrivals over the whole day").font(.footnote).foregroundStyle(.secondary)
    } header: {
      Text("All day")
    }
  }

  private func figure(_ share: Double, _ title: LocalizedStringKey, _ color: Color) -> some View {
    VStack(spacing: 2) {
      Text("\(Int((share * 100).rounded()))%").font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(color)
      Text(title).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  /// One coloured part of an hour's bar: from `low` to `high` per cent.
  private struct Share: Identifiable {
    let hour: Int
    let kind: String
    let low: Double
    let high: Double
    var id: String { "\(hour)-\(kind)" }
    let tint: Color
    var left: Double { Double(hour) - 0.4 }
    var right: Double { Double(hour) + 0.4 }
  }

  /// True for the bars of the hours that are not the one being touched.
  private func dimmed(_ hour: Int) -> Bool {
    guard let selected = selectedHour else { return false }
    return Int(selected.rounded()) != hour
  }

  private func shares(_ slices: [PunctualityTable.HourSlice]) -> [Share] {
    slices.flatMap { slice -> [Share] in
      let early = slice.cell.earlyShare * 100, late = slice.cell.lateShare * 100
      let onTime = max(0, 100 - early - late)
      return [
        Share(hour: slice.hour, kind: L10n.string("Early"), low: 0, high: early, tint: self.early),
        Share(hour: slice.hour, kind: L10n.string("On time"), low: early, high: early + onTime, tint: self.onTime),
        Share(hour: slice.hour, kind: L10n.string("Late"), low: early + onTime, high: 100, tint: self.late),
      ]
    }
  }

  private func sharesChart(_ slices: [PunctualityTable.HourSlice]) -> some View {
    let parts = shares(slices)
    return Chart {
      ForEach(parts) { item in
        // Bars are drawn from their edges as rectangles: a bar's width in "ratio" only exists on a category axis, and a
        // BarMark cannot be given both ends on both axes.
        RectangleMark(
          xStart: .value("Hour", item.left), xEnd: .value("Hour", item.right),
          yStart: .value("From", item.low), yEnd: .value("To", item.high)
        )
        .foregroundStyle(item.tint)
        .opacity(dimmed(item.hour) ? 0.4 : 1.0)
      }
      if let now = currentHour {
        RuleMark(x: .value("Now", Double(now) + 0.5)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
      }
    }
    .chartXScale(domain: hourDomain(slices))
    .chartXAxis { hourAxis() }
    .chartYScale(domain: 0.0...100.0)
    .chartYAxis { percentAxis() }
    .chartXSelection(value: $selectedHour)
    .chartLegend(.hidden)
    .frame(height: 200)
    .padding(.vertical, 4)
  }

  /// The marks of one hour of the spread chart: the bar from the 10th to the 90th percentile and the dot of the median.
  @ChartContentBuilder private func spreadMarks(_ slice: PunctualityTable.HourSlice) -> some ChartContent {
    let hour = Double(slice.hour)
    let low = Double(slice.cell.p10) / 60, high = Double(slice.cell.p90) / 60, middle = Double(slice.cell.p50) / 60
    let tint = colour(median: slice.cell.p50)
    RectangleMark(
      xStart: .value("Hour", hour - 0.3), xEnd: .value("Hour", hour + 0.3),
      yStart: .value("10th", low), yEnd: .value("90th", high)
    )
    .foregroundStyle(tint.opacity(0.35))
    PointMark(x: .value("Hour", hour), y: .value("Median", middle))
      .foregroundStyle(tint)
      .symbolSize(40)
  }

  private func spreadChart(_ slices: [PunctualityTable.HourSlice]) -> some View {
    let now = currentHour.map { Double($0) + 0.5 }
    return Chart {
      RuleMark(y: .value("Timetable", 0.0)).foregroundStyle(.secondary)
      ForEach(slices) { slice in spreadMarks(slice) }
      if let now {
        RuleMark(x: .value("Now", now)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
      }
    }
    .chartXScale(domain: hourDomain(slices))
    .chartXAxis { hourAxis() }
    .chartYAxis { minutesAxis() }
    .chartYAxisLabel("min", position: .top, alignment: .trailing)
    .frame(height: 200)
    .padding(.vertical, 4)
  }

  private func percentAxis() -> some AxisContent {
    AxisMarks(values: [0.0, 50.0, 100.0]) { value in
      AxisGridLine()
      AxisValueLabel { Text(percentText(value)) }
    }
  }

  private func minutesAxis() -> some AxisContent {
    AxisMarks { value in
      AxisGridLine()
      AxisValueLabel { Text(minutesText(value)) }
    }
  }

  private func percentText(_ value: AxisValue) -> String {
    let number: Double = value.as(Double.self) ?? 0
    return "\(Int(number))%"
  }

  private func minutesText(_ value: AxisValue) -> String {
    signedMinutes(value.as(Double.self) ?? 0)
  }

  private func signedMinutes(_ value: Double) -> String {
    let rounded = Int(value.rounded())
    return rounded > 0 ? "+\(rounded)" : "\(rounded)"
  }

  private func colour(median seconds: Int) -> Color {
    if seconds > 300 { return late }
    if seconds < -60 { return early }
    return onTime
  }

  private var legend: some View {
    HStack(spacing: 14) {
      key(early, "Early")
      key(onTime, "On time")
      key(late, "Late")
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private func key(_ color: Color, _ title: LocalizedStringKey) -> some View {
    HStack(spacing: 5) {
      RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
      Text(title)
    }
  }

  /// The words under the chart for the bar being touched.
  @ViewBuilder private func selectionLine(_ slices: [PunctualityTable.HourSlice]) -> some View {
    if let selected = selectedHour, case let hour = Int(selected.rounded()), let slice = slices.first(where: { $0.hour == hour }) {
      let cell = slice.cell
      VStack(alignment: .leading, spacing: 2) {
        Text(hourRange(hour)).font(.subheadline.weight(.semibold))
        Text("\(Int((cell.earlyShare * 100).rounded()))% early · \(Int((cell.onTimeShare * 100).rounded()))% on time · \(Int((cell.lateShare * 100).rounded()))% late")
          .font(.footnote)
        Text("Middle bus \(signed(cell.p50)); 8 of 10 between \(signed(cell.p10)) and \(signed(cell.p90)) · \(cell.n) arrivals")
          .font(.footnote).foregroundStyle(.secondary)
      }
    } else {
      Text("Touch a bar for the details of that hour.").font(.footnote).foregroundStyle(.secondary)
    }
  }

  // MARK: Helpers

  /// "+3 min" or "−2 min" for a delay in seconds.
  private func signed(_ seconds: Int) -> String {
    let minutes = Int((Double(seconds) / 60).rounded())
    if minutes == 0 { return L10n.string("on time") }
    return minutes > 0 ? L10n.string("+\(minutes) min") : L10n.string("\u{2212}\(-minutes) min")
  }

  private func date(atHour hour: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = model.schedule?.timeZone ?? .current
    return calendar.date(bySettingHour: min(23, hour), minute: 0, second: 0, of: Date()) ?? Date()
  }

  private func hourRange(_ hour: Int) -> String {
    let text = model.timeText()
    return "\(text.hourLabel(date(atHour: hour))) – \(text.hourLabel(date(atHour: hour + 1)))"
  }

  /// The hour of day it is now, when the graph is for today's kind of day.
  private var currentHour: Int? {
    var calendar = Calendar(identifier: .gregorian)
    let zone = model.schedule?.timeZone ?? .current
    calendar.timeZone = zone
    guard DayType(ServiceDate(Date(), in: zone), in: zone) == dayType else { return nil }
    return calendar.component(.hour, from: Date())
  }

  private func hourDomain(_ slices: [PunctualityTable.HourSlice]) -> ClosedRange<Double> {
    let first = Double(slices.first?.hour ?? 5), last = Double(slices.last?.hour ?? 23)
    return (first - 0.6)...(last + 0.6)
  }

  private func hourAxis() -> some AxisContent {
    AxisMarks(values: .stride(by: 3)) { value in
      AxisGridLine()
      AxisValueLabel { Text(hourText(value)) }
    }
  }

  private func hourText(_ value: AxisValue) -> String {
    let hour: Double = value.as(Double.self) ?? 0
    return model.timeText().hourLabel(date(atHour: Int(hour)))
  }
}
