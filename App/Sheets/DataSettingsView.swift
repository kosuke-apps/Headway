import HeadwayCore
import SwiftUI

/// Settings > Live buses > the icon next to "Save mobile data": how much data the app uses, and how to use less. Bus
/// positions are not on the list of things that can be slowed: they are always live.
struct DataSettingsView: View {
  @Environment(AppModel.self) private var model
  @State private var confirmReset = false

  var body: some View {
    @Bindable var settings = model.settings
    Form {
      Section {
        Toggle("Save mobile data", isOn: $settings.values.saveMobileData)
      } footer: {
        Text("With the refresh set to Automatic, arrival predictions are fetched half as often on mobile data and a quarter as often in Low Data Mode. Mobile data here includes a personal hotspot.")
      }

      Section {
        Label("Always live", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.green)
      } header: {
        Text("Bus positions")
      } footer: {
        Text("7 KB per update, about 2 MB an hour. No data setting slows them down: they follow the city's feed (Refresh, under Live buses).")
      }

      Section {
        Picker("On Wi-Fi", selection: $settings.values.predictionsOnWiFi) { options }
        Picker("On mobile data", selection: $settings.values.predictionsOnMobile) { options }
      } header: {
        Text("Arrival predictions")
      } footer: {
        Text("160 KB each time, most of what the app downloads. Automatic: every minute while a stop, a bus or the planner is open or a route is watched, every two minutes for lists and a focused route. Manual: only when a stop or bus opens or you pull the stop's list down; watched routes are still checked every five minutes.")
      }

      Section {
        Toggle("Only on Wi-Fi", isOn: $settings.values.timetableOnlyOnWiFi)
      } header: {
        Text("Timetable")
      } footer: {
        Text("7 MB, a few times a year. It is allowed on any connection when the phone's copy has expired.")
      }

      usageSection
    }
    .navigationTitle(L10n.string("Mobile data"))
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(Text(L10n.string("Reset the data meter?")), isPresented: $confirmReset, titleVisibility: .visible) {
      Button("Reset", role: .destructive) { DataMeter.shared.reset() }
    }
  }

  @ViewBuilder private var options: some View {
    Text("Automatic").tag(PredictionRefresh.automatic)
    Text("Every 30 seconds").tag(PredictionRefresh.every30Seconds)
    Text("Every minute").tag(PredictionRefresh.everyMinute)
    Text("Every 2 minutes").tag(PredictionRefresh.everyTwoMinutes)
    Text("Every 5 minutes").tag(PredictionRefresh.everyFiveMinutes)
    Text("Manual").tag(PredictionRefresh.manual)
  }

  // MARK: Meter

  private var usageSection: some View {
    let usage = DataMeter.shared.usage
    return Section {
      ForEach(DataKind.allCases) { kind in row(title(kind), wifi: usage.bytes(kind, metered: false), mobile: usage.bytes(kind, metered: true)) }
      row(L10n.string("Total"), wifi: usage.bytes(metered: false), mobile: usage.bytes(metered: true), bold: true)
      Button("Reset the meter", role: .destructive) { confirmReset = true }
    } header: {
      Text("Data used since \(usage.since.formatted(date: .abbreviated, time: .shortened))")
    } footer: {
      Text("What Headway downloaded, counted by the app: the data itself, without the headers of each request, so iOS Settings (Cellular) shows a little more.")
    }
  }

  private func title(_ kind: DataKind) -> String {
    switch kind {
    case .positions: L10n.string("Bus positions")
    case .predictions: L10n.string("Arrival predictions")
    case .alerts: L10n.string("Service alerts")
    case .timetable: L10n.string("Timetable")
    }
  }

  private func row(_ title: String, wifi: Int, mobile: Int, bold: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(title).fontWeight(bold ? .semibold : .regular)
        Spacer()
        Text(Self.size(wifi + mobile)).monospacedDigit().fontWeight(bold ? .semibold : .regular)
      }
      Text("Wi-Fi \(Self.size(wifi)) · Mobile \(Self.size(mobile))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
    }
    .accessibilityElement(children: .combine)
  }

  static func size(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .decimal)
  }
}
