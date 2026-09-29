import XCTest
@testable import S2TCore

final class CreditSpeechRecoveryTests: XCTestCase {
    func testSegmentedRestartKeepsCompletedPrefixAndExactUncertainTail() async throws {
        let connection = try CreditConnection(address: "http://localhost:4317", key: "s2t_demo_" + String(repeating: "a", count: 64))
        let samples = (0..<44100).map { Int16(($0 % 31) * 100) }
        let prefixAudio = WaveAudio.encode(samples: Array(samples.prefix(22050)), sampleRate: 22050)
        let audio = WaveAudio.encode(samples: samples, sampleRate: 22050)
        let prefix = try CreditSpeechRequest(provider: .assemblyAI, model: "universal-3-5-pro", connection: connection,
            requestID: "saved-speech", segmented: true).appending(audio: prefixAudio, segmentEnds: [22050], complete: false)
        let transport = SpeechSnapshotTransport(failAt: 2)
        let api = CreditsAPI(transport: transport)
        let first = try await api.transcribe(prefix, connection: connection)
        var record = RecordingRecovery(audio: audio, requestID: "saved", mode: .verbatim,
            completedParts: [prefix.parts[0].cacheKey: first.text])
        record.speechSegmentEnds = [22050]
        record.creditSpeechRequest = try prefix.appending(audio: audio, segmentEnds: [22050], complete: true)
        do { _ = try await api.transcribe(record.creditSpeechRequest!, connection: connection, completedParts: record.completedParts); XCTFail("Fixture must lose the tail response") } catch is URLError { }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("speech-snapshot-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RecordingRecoveryStore(directory: folder, key: { Data(repeating: 52, count: 32) })
        try await store.save(record)
        let restarted = RecordingRecoveryStore(directory: folder, key: { Data(repeating: 52, count: 32) })
        let recovered = try await restarted.pending()[0]
        _ = try await api.transcribe(XCTUnwrap(recovered.creditSpeechRequest), connection: connection, completedParts: recovered.completedParts)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[1].httpBody, requests[2].httpBody)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Idempotency-Key"), requests[2].value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertNotEqual(requests[0].httpBody, requests[1].httpBody)
        XCTAssertEqual(recovered.creditSpeechRequest?.parts.first, prefix.parts.first)
        let other = try CreditConnection(address: "http://localhost:4317", key: "s2t_demo_" + String(repeating: "b", count: 64))
        do { _ = try await api.transcribe(recovered.creditSpeechRequest!, connection: other); XCTFail("Wrong account must not send") } catch { }
        let afterWrongAccount = await transport.requests.count
        XCTAssertEqual(afterWrongAccount, 3)
        let changed = WaveAudio.encode(samples: Array(repeating: Int16(0), count: 44100), sampleRate: 22050)
        XCTAssertThrowsError(try prefix.appending(audio: changed, segmentEnds: [22050], complete: true))
    }

    func testLegacyDecodeHasNoProofThatSpeechWasNeverSubmittedAndCompletionDropsAudioSnapshot() async throws {
        let connection = try CreditConnection(address: "http://localhost:4317", key: "s2t_demo_" + String(repeating: "a", count: 64))
        let audio = WaveAudio.encode(samples: Array(repeating: 500, count: 16000), sampleRate: 16000)
        var record = RecordingRecovery(audio: audio, requestID: "saved", mode: .verbatim)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        legacy.removeValue(forKey: "creditSpeechSnapshotVersion")
        let restored = try JSONDecoder().decode(RecordingRecovery.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.creditSpeechSnapshotVersion)
        record.creditSpeechRequest = try CreditSpeechRequest(provider: .assemblyAI, model: "universal-3-5-pro", connection: connection,
            requestID: "saved-speech", segmented: false).appending(audio: audio, segmentEnds: nil, complete: true)
        record.streamingReceipt = .init(authorizationID: "historical", sessionID: "session", sessionDurationSeconds: 1, audioDurationSeconds: 1)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("speech-complete-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RecordingRecoveryStore(directory: folder, key: { Data(repeating: 52, count: 32) })
        try await store.save(record)
        try await store.complete(record)
        let receipt = try await store.pendingStreamingReports()[0]
        XCTAssertTrue(receipt.audio.isEmpty)
        XCTAssertNil(receipt.creditSpeechRequest)
        XCTAssertEqual(receipt.streamingReceipt?.authorizationID, "historical")
    }
}

private actor SpeechSnapshotTransport: HTTPTransport {
    let failAt: Int
    var requests: [URLRequest] = []
    init(failAt: Int) { self.failAt = failAt }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if requests.count == failAt { throw URLError(.badServerResponse) }
        let data = try JSONSerialization.data(withJSONObject: ["state": "settled", "result": ["text": "Part \(requests.count)", "model": "fixture"]])
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
