import XCTest
@testable import S2TCore

final class LocalUsageResilienceTests: XCTestCase {
    func testDirectTypeSafeRequestIsRecordedWithUnknownCost() throws {
        var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!)
        request.httpMethod = "POST"
        let record = try XCTUnwrap(LocalUsageRecord.read(request: request, data: Data(#"{"decisions":[]}"#.utf8), status: 200, credits: false))
        XCTAssertEqual(record.source.rawValue, "typeSafe")
        XCTAssertNil(record.amount)
    }

    func testDamagedArchiveIsPreservedAndNewEventsSurviveRestart() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("usage.json")
        let bad = Data("broken history".utf8)
        try bad.write(to: file)
        let ledger = LocalUsageLedger(file: file)
        await ledger.record(record("new"))
        let restored = await LocalUsageLedger(file: file).snapshot()
        XCTAssertEqual(restored.records.map(\.id), ["new"])
        let preserved = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("usage.json.unreadable-") }
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(preserved.first)), bad)
    }

    func testOversizedCollectionIsCompactedBeforeNextSave() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        var records = (0..<10_010).map { record("item-\($0)") }
        records.append(.init(id: "invalid", date: Date(), source: .local, amount: -2, tokens: nil, seconds: nil, estimated: false, pending: false))
        try JSONEncoder().encode(LocalUsageSnapshot(records: records, startedAt: Date(), error: "")).write(to: file)
        let ledger = LocalUsageLedger(file: file)
        await ledger.record(record("latest"))
        let restored = await LocalUsageLedger(file: file).snapshot()
        XCTAssertLessThanOrEqual(restored.records.count, 10_000)
        XCTAssertTrue(restored.records.contains { $0.id == "latest" })
        XCTAssertFalse(restored.records.contains { $0.id == "invalid" })
        XCTAssertLessThan(try Data(contentsOf: file).count, 8_000_000)
    }

    private func record(_ id: String) -> LocalUsageRecord {
        .init(id: id, date: Date(), source: .openRouter, amount: 1, tokens: 2, seconds: nil, estimated: false, pending: false)
    }
}
