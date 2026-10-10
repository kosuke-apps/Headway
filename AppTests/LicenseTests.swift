import Foundation
import Testing

@testable import Headway

@Suite struct LicenseTests {
  /// The app bundle that holds the licence files (the tests run inside the app).
  private let bundle = Bundle(for: AppModel.self)

  @Test func everyEntryHasItsLicenceTextInTheApp() throws {
    for entry in LicenseEntry.all {
      let text = try #require(entry.text(in: bundle), "\(entry.name) has no licence text")
      #expect(text.count > 500, "\(entry.name) text is too short to be a licence")
    }
  }

  @Test func theTextsAreTheLicencesTheyAreListedWith() throws {
    func text(_ id: String) throws -> String { try #require(LicenseEntry.all.first { $0.id == id }?.text(in: bundle)) }
    #expect(try text("protobuf").contains("Apache License"))
    #expect(try text("gtfs-realtime").contains("Version 2.0"))
    #expect(try text("zipfoundation").contains("MIT License"))
    #expect(try text("maplibre").contains("BSD 2-Clause"))
    #expect(try text("noto").contains("SIL OPEN FONT LICENSE"))
    #expect(try text("protomaps").contains("BSD 3-Clause"))
  }

  @Test func theEntriesCoverEveryThirdPartyPackage() {
    // Package.resolved lists the Swift packages; each one needs an entry. This list is what THIRD_PARTY.md names.
    let names = Set(LicenseEntry.all.map(\.name))
    for required in ["MapLibre Native", "SwiftProtobuf", "ZIPFoundation", "Noto Sans", "GTFS Realtime", "Protomaps basemaps"] {
      #expect(names.contains(required), "\(required) is missing from the licences screen")
    }
    #expect(Set(LicenseEntry.all.map(\.id)).count == LicenseEntry.all.count)
  }
}
