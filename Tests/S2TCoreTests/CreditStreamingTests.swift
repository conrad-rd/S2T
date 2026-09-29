import XCTest
@testable import S2TCore

final class CreditStreamingTests: XCTestCase {
    func testStreamingMarkerAndReceiptSurviveRestartAndDelivery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("streaming-recovery-" + UUID().uuidString)
        let store = RecordingRecoveryStore(directory: directory, key: { Data(repeating: 12, count: 32) })
        var recording = RecordingRecovery(audio: Data([1, 2]), requestID: "recording", mode: .verbatim)
        recording.directAssemblyStreaming = true
        recording.streamingReceipt = CreditStreamingReceipt(authorizationID: "auth", sessionID: "session", sessionDurationSeconds: 4, audioDurationSeconds: 3)
        try await store.save(recording)
        let restored = try await store.pending()
        XCTAssertEqual(restored.first?.directAssemblyStreaming, true)
        try await store.complete(recording)
        let pendingAudio = try await store.pending()
        XCTAssertTrue(pendingAudio.isEmpty)
        let receipts = try await store.pendingStreamingReports()
        XCTAssertEqual(receipts.first?.streamingReceipt?.authorizationID, "auth")
        try await store.clearStreamingReport(id: recording.id, authorizationID: "wrong-auth")
        let stillPending = try await store.pendingStreamingReports()
        XCTAssertEqual(stillPending.count, 1)
        try await store.clearStreamingReport(id: recording.id, authorizationID: "auth")
        let finished = try await store.pendingStreamingReports()
        XCTAssertTrue(finished.isEmpty)
    }
}
