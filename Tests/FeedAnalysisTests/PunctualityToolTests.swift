import Foundation
import HeadwayCore
import SwiftProtobuf
import Testing
import ZIPFoundation

private final class BundleToken {}

/// The nightly job runs `feedanalysis punctuality` over the recordings. The city sometimes answers with a few bytes (15 in
/// October 2026), the recorder stores them like any snapshot, and the tool crashed on the first one (exit 133, no new
/// statistics for three nights). These tests run the real tool on a recordings folder that holds such a file.
@Suite struct PunctualityToolTests {
  /// The built tool: next to the test bundle (the test target depends on it, so SwiftPM builds it).
  private var tool: URL {
    Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent().appendingPathComponent("feedanalysis")
  }

  /// Like the recorder's files (Python `gzip.compress`): a 10-byte header, a raw deflate stream, 8 bytes of trailer.
  private func gzip(_ data: Data) throws -> Data {
    let raw = try (data as NSData).compressed(using: .zlib) as Data
    return Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3]) + raw + Data(repeating: 0, count: 8)
  }

  private func vehicleFeed() throws -> Data {
    var message = TransitRealtime_FeedMessage()
    message.header.gtfsRealtimeVersion = "2.0"
    message.header.timestamp = 1_792_500_000
    var entity = TransitRealtime_FeedEntity()
    entity.id = "v1"
    entity.vehicle.trip.tripID = "t"
    entity.vehicle.vehicle.id = "2353"
    entity.vehicle.position.latitude = 43.0
    entity.vehicle.position.longitude = -89.4
    entity.vehicle.timestamp = 1_792_499_990
    message.entity.append(entity)
    return try message.serializedData()
  }

  /// A recordings root with one day: the timetable, one good vehicle snapshot and one that is only 15 bytes long.
  private func recordings(in root: URL) throws {
    let day = root.appendingPathComponent("2026-10-20")
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    let step = 1_000 / (111_320 * cos(43.0 * .pi / 180))
    let files: [String: String] = [
      "agency.txt": "agency_id,agency_name,agency_timezone\n1,Test,America/Chicago\n",
      "routes.txt": "route_id,route_short_name,route_long_name,route_color,route_text_color,route_sort_order\nR,R,Line,FF0000,FFFFFF,1\n",
      "stops.txt": "stop_id,stop_code,stop_name,stop_lat,stop_lon\n"
        + (0..<4).map { "s\($0),\($0),Stop \($0),43.0,\(-89.40 + Double($0) * step)" }.joined(separator: "\n") + "\n",
      "trips.txt": "trip_id,route_id,service_id,trip_headsign,direction_id,shape_id,block_id\nt,R,wk,East,0,sh,b\n",
      "stop_times.txt": "trip_id,arrival_time,departure_time,stop_id,stop_sequence\nt,08:00:00,08:00:00,s0,1\nt,08:05:00,08:05:00,s1,2\nt,08:10:00,08:10:00,s2,3\nt,08:15:00,08:15:00,s3,4\n",
      "shapes.txt": "shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence\n"
        + (0..<7).map { "sh,43.0,\(-89.40 + Double($0) * 0.5 * step),\($0 + 1)" }.joined(separator: "\n") + "\n",
      "calendar.txt": "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\nwk,1,1,1,1,1,0,0,20261001,20261231\n",
    ]
    let zip = try Archive(url: day.appendingPathComponent("mmt_gtfs.zip"), accessMode: .create)
    for (name, text) in files {
      let data = Data(text.utf8)
      try zip.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count)) { position, size in
        data.subdata(in: Data.Index(position)..<(Data.Index(position) + size))
      }
    }
    let good = try vehicleFeed()
    try gzip(good).write(to: day.appendingPathComponent("20261020T080000-0500_vehicles.pb.gz"))
    let short = good.prefix(15)  // what the city sent: too short to be a feed
    try gzip(Data(short)).write(to: day.appendingPathComponent("20261020T080040-0500_vehicles.pb.gz"))
  }

  @Test func aFifteenByteSnapshotIsReadAsAnError() throws {
    let short = Data(try vehicleFeed().prefix(15))
    #expect(short.count == 15)
    #expect(throws: (any Error).self) { try RealtimeDecoder.decode(short) }
  }

  @Test func theNightlyToolSkipsAnUnreadableSnapshotAndExitsCleanly() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("headway-tool-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try recordings(in: root)
    let output = root.appendingPathComponent("punctuality.json")

    let process = Process()
    process.executableURL = tool
    process.arguments = ["punctuality", root.path, output.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()

    #expect(process.terminationStatus == 0, "the tool stopped: \(text)")
    #expect(text.contains("1 unreadable snapshot(s) skipped"), "output was: \(text)")
    #expect(text.contains("wrote "), "output was: \(text)")
    #expect(FileManager.default.fileExists(atPath: output.path))
  }
}
