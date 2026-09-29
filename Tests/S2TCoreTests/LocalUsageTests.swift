import XCTest
@testable import S2TCore

final class LocalUsageTests: XCTestCase {
    private func event(_ url: String, _ json: String, credits: Bool = false) -> LocalUsageRecord? {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        return LocalUsageRecord.read(request: request, data: Data(json.utf8), status: 200, credits: credits)
    }

    func testFundingRoutesAndMissingCost() throws {
        let direct = try XCTUnwrap(event("https://openrouter.ai/api/v1/chat/completions", #"{"id":"gen-1","usage":{"cost":0.00125,"total_tokens":321},"choices":[]}"#))
        XCTAssertEqual(direct.source, .openRouter)
        XCTAssertEqual(direct.amount, Decimal(string: "0.00125"))
        XCTAssertEqual(direct.tokens, 321)
        let unknown = try XCTUnwrap(event("https://openrouter.ai/api/v1/chat/completions", #"{"id":"gen-2","usage":{"total_tokens":100}}"#))
        XCTAssertNil(unknown.amount)
        let paid = try XCTUnwrap(event("https://credits.example/api/v1/requests", #"{"id":"receipt","state":"settled","provider":"openrouter","chargedCredits":1.25}"#, credits: true))
        XCTAssertEqual(paid.source, .s2t)
        XCTAssertEqual(paid.amount, Decimal(string: "1.25"))
        XCTAssertNil(event("https://openrouter.ai/api/v1/auth/key", #"{"data":{"usage":40}}"#))
        XCTAssertNil(event("https://example.com/api/v1/chat/completions", #"{"id":"x","usage":{"cost":12}}"#))
    }

    func testAssemblyEstimateAndUnrecognizedModel() throws {
        let record = try XCTUnwrap(event("https://api.assemblyai.com/v2/transcript/job", #"{"id":"job","status":"completed","audio_duration":3600,"speech_model_used":"universal-3-5-pro","speaker_labels":true}"#))
        XCTAssertTrue(record.estimated)
        XCTAssertEqual(record.amount, Decimal(string: "0.23"))
        let unknown = try XCTUnwrap(event("https://api.assemblyai.com/v2/transcript/other", #"{"id":"other","status":"completed","audio_duration":3600,"speech_model_used":"future-model"}"#))
        XCTAssertNil(unknown.amount)
        XCTAssertNil(event("https://api.assemblyai.com/v2/transcript/job", #"{"id":"job","status":"processing"}"#))
    }

    func testReceiptReplayPersistenceAndContentExclusion() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let ledger = LocalUsageLedger(file: file)
        let pending = try XCTUnwrap(event("https://credits.example/api/v1/requests", #"{"id":"receipt","state":"reserved","reservedCredits":10,"text":"PRIVATE","account":"ACCOUNT"}"#, credits: true))
        let settled = try XCTUnwrap(event("https://credits.example/api/v1/requests", #"{"id":"receipt","state":"settled","chargedCredits":2,"result":{"text":"PRIVATE"}}"#, credits: true))
        await ledger.record(pending)
        await ledger.record(settled)
        await ledger.record(settled)
        let saved = await LocalUsageLedger(file: file).snapshot()
        XCTAssertEqual(saved.records.count, 1)
        XCTAssertEqual(saved.records.first?.amount, 2)
        XCTAssertEqual(saved.records.first?.pending, false)
        let bytes = try String(contentsOf: file)
        XCTAssertFalse(bytes.contains("PRIVATE"))
        XCTAssertFalse(bytes.contains("ACCOUNT"))
        XCTAssertFalse(bytes.contains("receipt"))
    }

    func testCorruptHistoryIsPreserved() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data("broken history".utf8).write(to: file)
        let ledger = LocalUsageLedger(file: file)
        await ledger.record(try XCTUnwrap(event("https://openrouter.ai/api/v1/chat/completions", #"{"id":"gen","usage":{"cost":1}}"#)))
        let snapshot = await ledger.snapshot()
        XCTAssertFalse(snapshot.error.isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(file.lastPathComponent + ".unreadable-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(backups.first)), "broken history")
        XCTAssertEqual(snapshot.records.count, 1)
    }
}
