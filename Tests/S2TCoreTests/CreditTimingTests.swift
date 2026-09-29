import XCTest
@testable import S2TCore

private struct TimedCreditTransport: HTTPTransport {
    let serverTiming: String?
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(nanoseconds: 30_000_000)
        let body = #"{"id":"6f1c2a52-5d51-4c34-9a0b-2f7a0e3c9b11","state":"settled","result":{"text":"Hello there.","model":"universal-3-5-pro"}}"#
        let headers = serverTiming.map { ["Server-Timing": $0, "Content-Type": "application/json"] } ?? ["Content-Type": "application/json"]
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
    }
}

final class CreditTimingTests: XCTestCase {
    private let connection = try! CreditConnection(address: "https://credits.example.com", key: "s2t_test_" + String(repeating: "a", count: 64))
    private let audio = WaveAudio.encode(samples: [Int16](repeating: 100, count: 16_000), sampleRate: 16_000)

    func testServerTimingSplitsProviderServiceAndNetworkTime() async throws {
        let api = CreditsAPI(transport: TimedCreditTransport(serverTiming: "upload;dur=12.5, reserve;dur=3.0, durability;dur=8.0, provider;dur=410.0, settle;dur=2.5, edge;dur=440.0"))
        _ = try await api.transcribe(audio: audio, provider: .assemblyAI, model: "universal-3-5-pro", endpoint: nil, connection: connection)
        let timing = try XCTUnwrap(api.timings.take("transcription"))
        XCTAssertEqual(timing["provider"] ?? -1, 0.41, accuracy: 0.0001)
        XCTAssertEqual(timing["durability"] ?? -1, 0.008, accuracy: 0.0001)
        XCTAssertEqual(timing["edge"] ?? -1, 0.44, accuracy: 0.0001)
        let roundTrip = try XCTUnwrap(timing["roundTrip"])
        XCTAssertGreaterThanOrEqual(roundTrip, 0.03)
        XCTAssertEqual(timing["network"] ?? -1, max(0, roundTrip - 0.44), accuracy: 0.0001)
        XCTAssertNil(api.timings.take("transcription"), "Timings are consumed once per dictation")
    }

    func testMissingOrMalformedServerTimingKeepsRoundTripOnly() async throws {
        let api = CreditsAPI(transport: TimedCreditTransport(serverTiming: "provider;desc=x, ;dur=4, edge;dur=-3, huge;dur=inf"))
        _ = try await api.transcribe(audio: audio, provider: .assemblyAI, model: "universal-3-5-pro", endpoint: nil, connection: connection)
        let timing = try XCTUnwrap(api.timings.take("transcription"))
        XCTAssertEqual(Set(timing.keys), ["roundTrip"])
    }
}
