import SwiftUI

/// One piece of other people's work that Headway ships or draws on, and where its licence text is.
struct LicenseEntry: Identifiable, Hashable {
  let id: String
  let name: String
  /// What it is used for.
  let purpose: LocalizedStringResource
  /// "Apache License 2.0".
  let licence: String
  let copyright: String
  /// The licence text, a `.txt` file in the app bundle.
  let file: String

  /// Every package, font and style the app contains. The licence of each requires its text to come with the app.
  static let all: [LicenseEntry] = [
    LicenseEntry(
      id: "maplibre", name: "MapLibre Native", purpose: "Draws the map", licence: "BSD 2-Clause",
      copyright: "Copyright (c) 2021 MapLibre contributors, 2018-2021 MapTiler.com, 2014-2020 Mapbox", file: "maplibre-native"),
    LicenseEntry(
      id: "protobuf", name: "SwiftProtobuf", purpose: "Reads the city's live feeds", licence: "Apache License 2.0",
      copyright: "Copyright Apple Inc. and the Swift Project authors", file: "apache-2.0"),
    LicenseEntry(
      id: "gtfs-realtime", name: "GTFS Realtime", purpose: "The definition of the live feeds", licence: "Apache License 2.0",
      copyright: "Copyright 2015 The GTFS Specifications Authors", file: "apache-2.0"),
    LicenseEntry(
      id: "zipfoundation", name: "ZIPFoundation", purpose: "Opens the timetable archive", licence: "MIT",
      copyright: "Copyright (c) 2017-2025 Thomas Zoechling", file: "zipfoundation"),
    LicenseEntry(
      id: "noto", name: "Noto Sans", purpose: "Map labels", licence: "SIL Open Font License 1.1",
      copyright: "Copyright 2022 The Noto Project Authors", file: "noto-sans"),
    LicenseEntry(
      id: "protomaps", name: "Protomaps basemaps", purpose: "Colours and layers of the map", licence: "BSD 3-Clause, with CC0 and MIT parts",
      copyright: "Copyright 2019-2023 Protomaps LLC, Kelso Cartography", file: "protomaps-basemaps"),
  ]

  static func == (a: LicenseEntry, b: LicenseEntry) -> Bool { a.id == b.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }

  /// The licence text, or nil when the file is missing from the app.
  func text(in bundle: Bundle = .main) -> String? {
    guard let url = bundle.url(forResource: file, withExtension: "txt") else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
  }
}

/// Settings > Licences: the data credits and the licence of everything the app contains.
struct LicensesView: View {
  var body: some View {
    List {
      Section {
        Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
          VStack(alignment: .leading, spacing: 2) {
            Text("OpenStreetMap").foregroundStyle(.primary)
            Text("Map data © OpenStreetMap contributors, Open Database Licence 1.0. The map tiles are a Protomaps build.")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
        VStack(alignment: .leading, spacing: 2) {
          Text("City of Madison, Metro Transit")
          Text("Timetables and live positions: Data provided under license granted by City of Madison, WI, Metro Transit. Headway is independent of the City and Metro Transit.")
            .font(.footnote).foregroundStyle(.secondary)
        }
      } header: {
        Text("Data")
      }
      Section {
        ForEach(LicenseEntry.all) { entry in
          NavigationLink(value: entry) {
            VStack(alignment: .leading, spacing: 2) {
              Text(entry.name)
              Text("\(Text(entry.purpose)) · \(entry.licence)").font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
      } header: {
        Text("Software and fonts")
      } footer: {
        Text("Headway itself is under the MIT licence, Copyright (c) 2026 Kosuke Satake.")
      }
    }
    .navigationTitle("Licences")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: LicenseEntry.self) { LicenseText(entry: $0) }
  }
}

/// The full licence text of one entry.
private struct LicenseText: View {
  let entry: LicenseEntry

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text(entry.copyright).font(.footnote.weight(.semibold))
        Text(entry.text() ?? String(localized: "The licence text is missing from this copy of the app."))
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle(entry.name)
    .navigationBarTitleDisplayMode(.inline)
  }
}
