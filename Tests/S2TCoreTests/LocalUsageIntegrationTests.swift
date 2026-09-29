import XCTest
@testable import S2TCore

final class LocalUsageIntegrationTests: XCTestCase {
    func testSyncTranscriptionRecordsDurationWithoutAnotherRequest() async throws {
        let ledger = LocalUsageLedger()
        let base = UsageResponseFixture(json: #"{"text":"A private fixture transcript."}"#)
        let api = DictationAPI(transport: LocalUsageTransport(base: base, ledger: ledger))
        let result = try await api.transcribe(audio: WaveAudio.encode(samples: Array(repeating: 1, count: 16_000), sampleRate: 16_000), apiKey: "fake")
        XCTAssertEqual(result, "A private fixture transcript.")
        let records = await ledger.snapshot().records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.seconds, 1)
        XCTAssertEqual(records.first?.amount, Decimal(string: "0.000125"))
        let calls = await base.calls
        XCTAssertEqual(calls, 1)
    }

    func testChargedFailedCleanupRemainsInUsage() async throws {
        let ledger = LocalUsageLedger()
        let base = UsageResponseFixture(json: #"{"id":"charged-receipt","model":"openai/gpt-oss-120b","usage":{"cost":0.002,"total_tokens":19},"choices":[{"finish_reason":"length","message":{"content":"unfinished"}}]}"#)
        let api = DictationAPI(transport: LocalUsageTransport(base: base, ledger: ledger))
        do {
            _ = try await api.process(text: "private input", mode: .clean, model: "openai/gpt-oss-120b", apiKey: "fake")
            XCTFail("Incomplete cleanup must fail")
        } catch { }
        let records = await ledger.snapshot().records
        XCTAssertEqual(records.first?.amount, Decimal(string: "0.002"))
        XCTAssertEqual(records.first?.tokens, 19)
        let calls = await base.calls
        XCTAssertEqual(calls, 1)
    }

    func testCreditRetryCountsOneChargeThroughProductionAPI() async throws {
        let ledger = LocalUsageLedger()
        let base = UsageResponseFixture(json: #"{"id":"same-charge","state":"settled","provider":"assemblyai","chargedCredits":0.8,"result":{"text":"A private transcript.","model":"universal-3-5-pro"}}"#)
        let api = CreditsAPI(transport: LocalUsageTransport(base: base, ledger: ledger, credits: true))
        let connection = try CreditConnection(address: "http://localhost:4317", key: "s2t_test_" + String(repeating: "a", count: 64))
        for _ in 0..<2 {
            let result = try await api.transcribe(audio: WaveAudio.encode(samples: Array(repeating: 1, count: 16_000), sampleRate: 16_000), provider: .assemblyAI, model: "universal-3-5-pro", endpoint: nil, connection: connection, requestID: "same-local-recording")
            XCTAssertEqual(result.text, "A private transcript.")
        }
        let records = await ledger.snapshot().records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.source, .s2t)
        XCTAssertEqual(records.first?.amount, Decimal(string: "0.8"))
        let calls = await base.calls
        XCTAssertEqual(calls, 2)
    }
}

private actor UsageResponseFixture: HTTPTransport {
    let json: String
    var calls = 0
    init(json: String) { self.json = json }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
