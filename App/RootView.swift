import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase

  /// Height of the stop and bus sheets in their resting position.
  private static let detailHeight: CGFloat = 320

  var body: some View {
    ZStack(alignment: .top) {
      MapContainer(bottomInset: model.sheet?.isDetail == true ? Self.detailHeight : 0)
        .ignoresSafeArea()
        .accessibilityHidden(model.mode != .map)
      if model.mode == .map {
        VStack(spacing: 8) {
          StatusPill()
          if model.focus.isActive { FocusChip() }
          if !model.routeChoices.isEmpty { RouteChooser() }
          if case .failed(let message) = model.phase { FailureBanner(message: message) }
        }
        .padding(.top, 8)
        .padding(.horizontal, 60)

        MenuButton()
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 2)
          .padding(.leading, 12)

        Controls()
          .frame(maxWidth: .infinity, alignment: .trailing)
          .padding(.top, 54)
          .padding(.trailing, 12)

        // A stop, a bus or a journey that was put away stays on the map; this is the way back to it.
        if model.sheet == nil, model.hasDock {
          Dock()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 12)
            .padding(.bottom, 30)
        }
      }
      if model.mode == .info {
        InfoView().background(Color(.systemGroupedBackground).ignoresSafeArea())
      }
      if model.mode == .plan {
        PlanView().background(Color(.systemGroupedBackground).ignoresSafeArea())
      }
      if !model.menuOpen, model.mode == .map || !model.planPushed {
        EdgeSwipeArea()
      }
      MenuDrawer()
    }
    // Swiping a stop or bus sheet down puts it into the dock instead of losing it.
    .sheet(item: Binding(get: { model.sheet }, set: { if $0 == nil { model.minimizeSheet() } else { model.sheet = $0 } })) { sheet in
      switch sheet {
      case .stop(let id):
        StopSheet(stopID: id).modifier(DetailSheetStyle(height: Self.detailHeight))
      case .bus(let id):
        BusSheet(vehicleID: id).modifier(DetailSheetStyle(height: Self.detailHeight))
      case .trip(let id, let date):
        TripSheet(tripID: id, date: date).modifier(DetailSheetStyle(height: Self.detailHeight))
      case .journey:
        // Swiped down, the journey goes into the dock at the bottom of the map.
        JourneySheet().modifier(DetailSheetStyle(height: Self.detailHeight))
      case .settings:
        // Half height with the map still usable, so a change (colours, marker size) can be watched on the map.
        SettingsView()
          .presentationDetents([.medium, .large])
          .presentationBackgroundInteraction(.enabled(upThrough: .medium))
          .presentationBackground(Color(.systemGroupedBackground))
      case .routes:
        RoutesSheet().presentationDetents([.medium, .large])
      case .search:
        SearchSheet().presentationDetents([.medium, .large])
      }
    }
    .confirmationDialog(
      model.droppedPin?.name ?? "", isPresented: Binding(get: { model.droppedPin != nil }, set: { if !$0 { model.droppedPin = nil } }),
      titleVisibility: .visible
    ) {
      Button("Directions to here") {
        if let pin = model.droppedPin { model.startDirections(to: pin) }
      }
      Button("Directions from here") {
        if let pin = model.droppedPin { model.startDirections(from: pin) }
      }
      Button("Cancel", role: .cancel) {}
    }
    .preferredColorScheme(colorScheme)
    .onChange(of: model.settings.values.language) { _, language in LanguageState.shared.apply(language) }
    .onChange(of: scenePhase) { _, phase in
      model.setActive(phase != .background)
      if phase == .background { WatchBackground.schedule(enabled: model.settings.values.watchEnabled && model.settings.values.isWatchingAnything) }
    }
  }

  private var colorScheme: ColorScheme? {
    switch model.settings.values.appearance {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

/// A bottom sheet that leaves the map usable above it.
private struct DetailSheetStyle: ViewModifier {
  let height: CGFloat

  func body(content: Content) -> some View {
    content
      .presentationDetents([.height(height), .large])
      .presentationBackgroundInteraction(.enabled(upThrough: .height(height)))
      .presentationDragIndicator(.visible)
      .presentationContentInteraction(.scrolls)
      .presentationBackground(Color(.systemBackground))
  }
}

private struct Controls: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(spacing: 10) {
      CircleButton(systemName: "magnifyingglass", label: "Find a stop") { model.sheet = .search }
      CircleButton(systemName: "line.3.horizontal.decrease", label: "Routes") { model.sheet = .routes }
      CircleButton(systemName: model.location.isAuthorized ? "location.fill" : "location", label: "My location") {
        model.locateMe()
      }
    }
  }
}

/// One line that says how current the buses on the map are. "Live" is only true to a point: positions are about
/// half a minute old when they arrive, so the line reports their age, not the time of the last request.
private struct StatusPill: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    // Tapping it opens the details of the live feed (how old, how many buses, how many late) and a way to refresh.
    Button { model.liveSummaryOpen.toggle() } label: {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let age = model.positionAge(at: context.date)
        let late = model.liveFailing || (age ?? 0) > 90
        HStack(spacing: 8) {
          Circle().fill(model.lastLiveUpdate == nil ? Color.gray : (late ? Color.orange : Color.green)).frame(width: 8, height: 8)
          // One line whatever the numbers are: the text shrinks a little rather than wrapping.
          Text(text(age: age, late: late)).font(.footnote.weight(.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
      }
    }
    .buttonStyle(.plain)
    .accessibilityHint(Text("Shows details of the live buses"))
    .popover(isPresented: $model.liveSummaryOpen, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
      LiveSummary().presentationCompactAdaptation(.popover)
    }
    .onChange(of: model.liveSummaryOpen) { _, open in if open { model.ensurePredictions() } }
  }

  private func text(age: TimeInterval?, late: Bool) -> String {
    guard let age else { return L10n.string("Connecting…") }
    let seconds = Int(age.rounded())
    if model.liveFailing {
      return L10n.string("No connection · positions \(seconds) s old")
    }
    if late { return L10n.string("Delayed · positions \(seconds) s old") }
    return L10n.string("Live · \(model.vehicles.count) buses · positions \(seconds) s old")
  }
}

/// Says what the map is limited to, and lets the rider change the direction or go back to all routes.
/// A thin strip along the left edge: swiping right from it opens the menu, like the hamburger button.
private struct EdgeSwipeArea: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Color.clear
      .frame(width: 22)
      .frame(maxHeight: .infinity)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 8)
          .onEnded { value in
            if value.translation.width > 40, abs(value.translation.height) < value.translation.width {
              withAnimation(.snappy(duration: 0.28)) { model.menuOpen = true }
            }
          }
      )
      .frame(maxWidth: .infinity, alignment: .leading)
      .ignoresSafeArea()
      .accessibilityHidden(true)
  }
}

/// Which route did you mean? Shown when a tap lands on lines of several routes.
private struct RouteChooser: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Which route?").font(.footnote.weight(.semibold))
        Spacer()
        Button { model.routeChoices = [] } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
          .accessibilityLabel(Text("Close"))
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(model.routeChoices, id: \.self) { id in
            Button { model.focusRoute(id, direction: nil, fit: false) } label: {
              HStack(spacing: 6) {
                RouteBadge(routeID: id)
                if model.fleet(route: id).total > 0 {
                  FleetCounts(route: id)
                } else {
                  Text("0").font(.footnote.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
                    .accessibilityLabel(Text("0 buses now"))
                }
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .padding(12)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

private struct FocusChip: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let focus = model.focus
    let single = focus.routes.count == 1 ? focus.routes.first : nil
    // A route with two directions or several destinations can be narrowed from the chip.
    let choices = single != nil && focus.label == nil && model.variants(of: single!).count > 1
    HStack(spacing: 8) {
      if model.focusReturn != nil {
        Button { model.returnFromFocus() } label: {
          Image(systemName: "chevron.backward.circle.fill").font(.title3).symbolRenderingMode(.hierarchical).foregroundStyle(.blue)
            .frame(width: 30, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Back"))
      }
      if choices, let single {
        // The whole chip opens the choices, not only the small arrows.
        Menu { choiceMenu(route: single, focus: focus) } label: {
          HStack(spacing: 8) {
            label(focus, single: single)
            Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.blue)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Choose a direction or destination"))
      } else {
        label(focus, single: single)
      }
      Button { model.clearFocus() } label: {
        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 30, height: 36).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text("Show all routes"))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 2)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private func label(_ focus: MapFocus, single: String?) -> some View {
    HStack(spacing: 8) {
      if let single { RouteBadge(routeID: single, compact: true) }
      VStack(alignment: .leading, spacing: 3) {
        Text(title(focus, single: single)).font(.footnote.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
        if let single, focus.label == nil {
          // Which way, how many buses, and how many of them are late (red), on time (green) and early (blue).
          ForEach(model.variants(of: single).map(\.direction).filter { focus.direction == nil || focus.direction == $0 }, id: \.self) { direction in
            directionLine(route: single, direction: direction, headsign: focus.headsign)
          }
          legend
        }
        if focus.isAlert {
          // The dashes are the only sign of a detour on the map: say what they mean, and what is not known.
          Text("Dashed line: the route has an alert. The city does not publish which streets a detour uses; see the details link.")
            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func directionLine(route: String, direction: Int, headsign: String?) -> some View {
    HStack(spacing: 5) {
      Image(systemName: model.directionSymbol(route: route, direction: direction)).font(.caption2)
      Text(model.directionName(route: route, direction: direction)).font(.caption2).lineLimit(1)
      if model.fleet(route: route, direction: direction, headsign: headsign).total > 0 {
        FleetCounts(route: route, direction: direction, headsign: headsign)
      } else {
        Text(model.liveStatus(route: route, direction: direction).text).font(.caption2).lineLimit(1)
      }
    }
    .foregroundStyle(.secondary)
  }

  /// What the rings on the map mean.
  private var legend: some View {
    HStack(spacing: 10) {
      HStack(spacing: 4) {
        Circle().strokeBorder(Color.purple, lineWidth: 2).frame(width: 9, height: 9)
        Text("First stop")
      }
      HStack(spacing: 4) {
        Circle().strokeBorder(Color.primary, lineWidth: 2).frame(width: 9, height: 9)
        Text("Last stop")
      }
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
  }

  /// Both directions, then each direction with its destinations underneath (D1, D2, ...).
  @ViewBuilder private func choiceMenu(route: String, focus: MapFocus) -> some View {
    Button { model.setFocusDirection(nil) } label: {
      Label("Both directions", systemImage: focus.direction == nil ? "checkmark" : "arrow.left.arrow.right")
    }
    ForEach(model.variants(of: route), id: \.direction) { variant in
      let patterns = model.patterns(of: route, direction: variant.direction)
      let wholeDirection = focus.direction == variant.direction && focus.headsign == nil
      Section(model.directionName(route: route, direction: variant.direction)) {
        Button { model.setFocusDirection(variant.direction) } label: {
          Label(
            patterns.isEmpty ? model.directionTitle(route: route, direction: variant.direction) : L10n.string("All destinations"),
            systemImage: wholeDirection ? "checkmark" : model.directionSymbol(route: route, direction: variant.direction))
        }
        ForEach(patterns) { pattern in
          Button { model.setFocusPattern(pattern) } label: {
            if focus.direction == pattern.direction, focus.headsign == pattern.headsign {
              Label(model.patternTitle(pattern), systemImage: "checkmark")
            } else {
              Text(model.patternTitle(pattern))
            }
          }
        }
      }
    }
  }

  private func title(_ focus: MapFocus, single: String?) -> String {
    if let label = focus.label { return label }
    guard let single else { return L10n.string("Showing only these routes") }
    if let direction = focus.direction {
      if let headsign = focus.headsign, let pattern = model.patterns(of: single, direction: direction).first(where: { $0.headsign == headsign }) {
        return model.patternTitle(pattern)
      }
      return model.directionTitle(route: single, direction: direction)
    }
    return L10n.string("Both directions")
  }
}

private struct FailureBanner: View {
  @Environment(AppModel.self) private var model
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("The timetable could not be loaded").font(.footnote.weight(.semibold))
      Text(message).font(.caption).foregroundStyle(.secondary)
      Button("Try again") { Task { await model.retry() } }.font(.footnote.weight(.semibold))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
  }
}
