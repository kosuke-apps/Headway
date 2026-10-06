import HeadwayCore
import SwiftUI

/// The route's name on its colour, like the sign on the front of the bus.
struct RouteBadge: View {
  @Environment(AppModel.self) private var model
  let routeID: String
  var compact = false

  var body: some View {
    let look = style()
    Text(model.route(routeID)?.shortName ?? routeID)
      .font((compact ? Font.caption : Font.subheadline).weight(.bold))
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .foregroundStyle(look.text)
      .padding(.horizontal, compact ? 6 : 9)
      .frame(minWidth: compact ? 24 : 34, minHeight: compact ? 20 : 28)
      .background(look.fill, in: RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous))
      .accessibilityLabel(Text("Route \(model.route(routeID)?.shortName ?? routeID)"))
  }

  private func style() -> (fill: Color, text: Color) {
    guard let route = model.route(routeID) else { return (.gray, .white) }
    let routes = model.orderedRoutes
    let palette = model.settings.values.routePalette
    // The quiet palette greys map lines; badges keep the agency colour so that routes stay recognisable.
    let fill = RouteColors.fill(for: route, palette: palette == .quiet ? .agency : palette, among: routes)
    return (Color(fill), Color(RouteColors.text(on: fill)))
  }
}

/// A small dot-and-label that says whether a time is live or only from the timetable. With `scheduled` (the timetable's
/// own time, already formatted) a live bus also says what the timetable promised, so the live time never hides it.
struct LiveStatus: View {
  let arrival: Arrival
  let showDelay: Bool
  var scheduled: String? = nil

  var body: some View {
    HStack(spacing: 4) {
      if arrival.status == .live {
        Image(systemName: "dot.radiowaves.left.and.right")
          .foregroundStyle(.green)
          .symbolRenderingMode(.hierarchical)
        Text(liveText).foregroundStyle(delayColor).lineLimit(1)
        if let scheduled, showDelay {
          Text("· Scheduled \(scheduled)").foregroundStyle(.secondary).lineLimit(1)
        }
      } else {
        Image(systemName: "clock").foregroundStyle(.secondary)
        Text("Scheduled").foregroundStyle(.secondary)
      }
    }
    .font(.caption)
    .accessibilityElement(children: .combine)
  }

  private var liveText: String {
    if showDelay, let text = TimeText.delay(arrival.delay) { return text }
    return String(localized: "Live")
  }

  private var delayColor: Color {
    guard showDelay, let delay = arrival.delay else { return .secondary }
    if delay > 300 { return .red }
    if delay > 90 { return .orange }
    if delay < -90 { return .blue }  // ahead of the timetable: the bus may be gone before its time
    return .secondary
  }
}

/// Lays views out in rows, moving to the next row when one does not fit: a few chips that would otherwise be cut off.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > 0, x + size.width > width {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
      widest = max(widest, x - spacing)
    }
    return CGSize(width: widest, height: y + rowHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width > bounds.maxX {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }
      view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}

struct CircleButton: View {
  let systemName: String
  let label: LocalizedStringKey
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 17, weight: .medium))
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .background(.regularMaterial, in: Circle())
    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    .accessibilityLabel(label)
  }
}

/// Early, on time and late as one bar: blue for buses that left before the timetable, green for on time, orange for late.
struct ReliabilityBar: View {
  let cell: PunctualityCell

  var body: some View {
    GeometryReader { geometry in
      let total = max(1, cell.n)
      HStack(spacing: 2) {
        segment(cell.early, total: total, width: geometry.size.width, color: .blue)
        segment(cell.onTime, total: total, width: geometry.size.width, color: .green)
        segment(cell.late, total: total, width: geometry.size.width, color: .orange)
      }
    }
    .frame(height: 8)
    .clipShape(Capsule())
    .accessibilityHidden(true)
  }

  @ViewBuilder private func segment(_ count: Int, total: Int, width: CGFloat, color: Color) -> some View {
    if count > 0 {
      color.frame(width: max(3, width * CGFloat(count) / CGFloat(total)))
    }
  }
}

/// How punctual a route has been at this time of day, with the bar and the numbers.
struct ReliabilityRow: View {
  @Environment(AppModel.self) private var model
  let routeID: String
  let match: PunctualityTable.Match

  var body: some View {
    let cell = match.cell
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 10) {
        RouteBadge(routeID: routeID, compact: true)
        ReliabilityBar(cell: cell)
      }
      HStack(spacing: 10) {
        Text("\(percent(cell.earlyShare))% early").foregroundStyle(.blue)
        Text("\(percent(cell.onTimeShare))% on time").foregroundStyle(.green)
        Text("\(percent(cell.lateShare))% late").foregroundStyle(.orange)
      }
      .font(.caption.weight(.medium))
      Text(description).font(.caption2).foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }

  private func percent(_ share: Double) -> Int { Int((share * 100).rounded()) }

  private var description: String {
    let name: String
    switch match.dayType {
    case .weekday: name = String(localized: "Weekdays")
    case .saturday: name = String(localized: "Saturdays")
    case .sunday: name = String(localized: "Sundays")
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = model.schedule?.timeZone ?? .current
    let time = calendar.date(bySettingHour: match.hour, minute: 0, second: 0, of: Date()) ?? Date()
    let hour = model.timeText().hourLabel(time)
    let scope = match.scope == .stop ? String(localized: "this stop") : String(localized: "whole route")
    let arrivals = String(localized: "\(match.cell.n) arrivals")
    let days = String(localized: "\(model.punctuality.days) days recorded")
    return "\(name) \(String(localized: "around \(hour)")) · \(scope) · \(arrivals) · \(days)"
  }
}
