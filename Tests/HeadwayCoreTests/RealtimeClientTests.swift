import Foundation
import SwiftProtobuf
import Testing

@testable import HeadwayCore

@Suite(.serialized) struct RealtimeClientTests {
  @Test func parsesHTTPDates() {
    let date = RealtimeClient.parseHTTPDate("Sun, 04 Oct 2026 01:07:21 GMT")
    #expect(date == Date(timeIntervalSince1970: 1_791_076_041))
    #expect(RealtimeClient.parseHTTPDate(nil) == nil)
    #expect(RealtimeClient.parseHTTPDate("yesterday") == nil)
  }

  /// Answers every request with `body` (status 200), so that the client can be tried without the network.
  final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Date": "Sat, 24 Oct 2026 20:15:04 GMT"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Self.body)
      client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
  }

  private func stubbedClient(answering body: Data) -> RealtimeClient {
    StubProtocol.body = body
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return RealtimeClient(baseURL: URL(string: "https://feeds.example.invalid/gtfsrt")!, session: URLSession(configuration: configuration))
  }

  @Test func aFifteenByteAnswerIsAnErrorTheCallerCanHandle() async throws {
    // What the poll relies on: a too-short body from the city is thrown (the live status says so and the next poll tries
    // again), never a crash.
    let client = stubbedClient(answering: Data(repeating: 0x0A, count: 15))
    await #expect(throws: (any Error).self) { _ = try await client.fetch(.vehicles) }
  }

  @Test func aWholeAnswerIsDecodedWithTheServersClock() async throws {
    var message = TransitRealtime_FeedMessage()
    message.header.gtfsRealtimeVersion = "2.0"
    message.header.timestamp = 1_792_500_000
    let client = stubbedClient(answering: try message.serializedData())
    let snapshot = try await client.fetch(.vehicles)
    #expect(snapshot.feedTimestamp == Date(timeIntervalSince1970: 1_792_500_000))
    #expect(snapshot.serverDate != nil)
  }
}
