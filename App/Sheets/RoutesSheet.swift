import HeadwayCore
import SwiftUI

/// All routes: look at one on its own, hide the ones you never use, and keep favourites at the top.
struct RoutesSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        let favorites = model.orderedRoutes.filter { model.settings.isFavorite(route: $0.id) }
        if !favorites.isEmpty {
          Section("Favorites") { ForEach(favorites) { row($0) } }
        }
        Section {
          ForEach(model.orderedRoutes) { row($0) }
        } header: {
          Text("All routes")
        } footer: {
          Text("Tap a route, or one of its directions, to see only that and its stops. Use the switch to hide a route from the map. Swipe left on a route to be notified about it. Next to the bus: red is late (over 5 minutes), green on time, blue early (over 2 minutes). A triangle marks a route with an alert.")
        }
      }
      .navigationTitle("Routes")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear {
        model.refreshOutlooks()
        model.ensurePredictions()
      }
      .notificationsDeniedAlert()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Menu {
            Button("Show all routes") { model.settings.values.hiddenRoutes = [] }
            Button("Hide all routes") { model.settings.values.hiddenRoutes = Set(model.orderedRoutes.map(\.id)) }
          } label: { Label("More", systemImage: "ellipsis.circle") }
        }
        ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
      }
    }
  }

  /// How many buses are running, with how many of them are late, on time and early, to the right of the name; nothing
  /// when there are none (the reason goes under the name instead).
  @ViewBuilder private func count(route: String, direction: Int?) -> some View {
    FleetCounts(route: route, direction: direction)
  }

  /// Why there are no buses (not running today, between trips, ...): nothing is wrong, but it is worth a line.
  @ViewBuilder private func reason(route: String, direction: Int?) -> some View {
    let status = model.liveStatus(route: route, direction: direction)
    if !status.isRunning {
      Text(status.text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }

  /// One route: a header that shows both directions, and one line per direction (they often use different streets).
  /// The number of buses sits at the right of each line, so that a row takes two or three lines, not six.
  private func row(_ route: Route) -> some View {
    let hidden = model.settings.values.hiddenRoutes.contains(route.id)
    let variants = model.variants(of: route.id)
    let focused = model.focus.routes == [route.id]
    return HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Button {
          model.settings.setRoute(route.id, hidden: false)
          model.focusRoute(route.id)
          dismiss()
        } label: {
          HStack(alignment: .top, spacing: 12) {
            RouteBadge(routeID: route.id)
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(route.longName.isEmpty ? String(localized: "Both directions") : route.longName).font(.subheadline).lineLimit(2)
                  .foregroundStyle(focused && model.focus.direction == nil ? Color.blue : Color.primary)
                if model.alertRouteIDs.contains(route.id) {
                  Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).accessibilityLabel(Text("Alert"))
                }
                if model.isWatching(route: route.id) { Image(systemName: "bell.fill").font(.caption2).foregroundStyle(.orange) }
                Spacer(minLength: 4)
                count(route: route.id, direction: nil)
              }
              reason(route: route.id, direction: nil)
              if model.liveStatus(route: route.id, direction: nil).isRunning, let match = model.reliability(route: route.id, stop: nil) {
                Text("Usually \(Int((match.cell.onTimeShare * 100).rounded()))% on time right now").font(.caption).foregroundStyle(.secondary)
              }
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        ForEach(variants, id: \.direction) { variant in
          Button {
            model.settings.setRoute(route.id, hidden: false)
            model.focusRoute(route.id, direction: variant.direction)
            dismiss()
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(model.directionTitle(route: route.id, direction: variant.direction), systemImage: model.directionSymbol(route: route.id, direction: variant.direction))
                  .font(.footnote)
                  .lineLimit(1)
                  .multilineTextAlignment(.leading)
                  .foregroundStyle(focused && model.focus.direction == variant.direction ? Color.blue : Color.primary)
                Spacer(minLength: 4)
                count(route: route.id, direction: variant.direction)
              }
              reason(route: route.id, direction: variant.direction).padding(.leading, 26)
            }
            .padding(.leading, 46)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .opacity(hidden ? 0.4 : 1)
      Toggle("Show \(route.shortName) on the map", isOn: Binding(
        get: { !hidden }, set: { model.settings.setRoute(route.id, hidden: !$0) }))
        .labelsHidden()
    }
    .swipeActions(edge: .trailing) {
      Button {
        Task { await model.setWatching(route: route.id, !model.isWatching(route: route.id)) }
      } label: {
        model.isWatching(route: route.id) ? Label("Stop watching", systemImage: "bell.slash") : Label("Watch", systemImage: "bell")
      }
      .tint(.blue)
    }
    .swipeActions(edge: .leading) {
      Button {
        model.settings.toggleFavorite(route: route.id)
      } label: {
        model.settings.isFavorite(route: route.id) ? Label("Unfavorite", systemImage: "star.slash") : Label("Favorite", systemImage: "star")
      }
      .tint(.orange)
    }
  }
}
