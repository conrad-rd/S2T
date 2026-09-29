import XCTest
@testable import S2TCore

final class RecordingRecoveryTests: XCTestCase {
    func testFiveMinuteAudioSurvivesPartitioningWithoutMissingOrRepeatedSamples() throws {
        for rate: UInt32 in [16000, 24000, 44100, 48000] {
            let samples = (0..<Int(rate) * 300).map { Int16(truncatingIfNeeded: $0) }
            let audio = WaveAudio.encode(samples: samples, sampleRate: rate)
            let parts = try WaveAudio.creditParts(audio)
            XCTAssertGreaterThan(parts.count, 1)
            var joined = Data()
            for part in parts {
                XCTAssertTrue(WaveAudio.supportsImmediateTranscription(part))
                let body = try JSONEncoder().encode(["audio": part.base64EncodedString(), "provider": "assemblyai", "operation": "transcription", "model": "universal-3-5-pro"])
                XCTAssertLessThan(body.count, 12_000_000)
                XCTAssertLessThan(part.base64EncodedString().count, 11_000_000)
                joined.append(part.dropFirst(44))
            }
            XCTAssertEqual(joined, audio.dropFirst(44))
        }
    }

    func testShortAudioRetainsOriginalBytesAndMalformedAudioIsRejected() throws {
        let audio = WaveAudio.encode(samples: Array(repeating: 17, count: 16000), sampleRate: 16000)
        XCTAssertEqual(try WaveAudio.creditParts(audio), [audio])
        var corrupt = audio
        corrupt[40] ^= 1
        XCTAssertThrowsError(try WaveAudio.creditParts(corrupt))
        XCTAssertThrowsError(try WaveAudio.creditParts(Data()))
    }

    func testEncryptedRecoverySurvivesRestartAndPreservesOtherFailures() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-recovery-test-" + UUID().uuidString)
        let key = Data(repeating: 42, count: 32)
        let first = RecordingRecovery(audio: Data("private recorded words".utf8), requestID: "payment-id", mode: .clean, completedParts: ["part-1": "First sentence."], transcript: "Original transcript")
        let second = RecordingRecovery(audio: Data([1, 2, 3]), requestID: "other-payment", mode: .verbatim)
        let store = RecordingRecoveryStore(directory: directory, key: { key })
        try await store.save(first)
        try await store.save(second)
        let disk = try Data(contentsOf: directory.appendingPathComponent(first.id.uuidString + ".enc"))
        XCTAssertNil(disk.range(of: first.audio))
        XCTAssertNil(disk.range(of: Data(first.transcript.utf8)))
        let restarted = RecordingRecoveryStore(directory: directory, key: { key })
        let pending = try await restarted.pending()
        let loaded = try XCTUnwrap(pending.first { $0.id == first.id })
        XCTAssertEqual(loaded.audio, first.audio)
        XCTAssertEqual(loaded.requestID, first.requestID)
        XCTAssertEqual(loaded.completedParts, first.completedParts)
        XCTAssertEqual(loaded.transcript, first.transcript)
        try await restarted.complete(first)
        let remaining = try await restarted.pending()
        XCTAssertEqual(remaining.map(\.id), [second.id])
        let wrongKey = RecordingRecoveryStore(directory: directory, key: { Data(repeating: 7, count: 32) })
        do { _ = try await wrongKey.pending(); XCTFail("Wrong keys must not erase or replace recovery files") } catch { }
        let preserved = try await restarted.pending()
        XCTAssertEqual(preserved.first?.audio, second.audio)
    }
}

extension CreditsTests {
    func testUploadEncodingStaysUnderGatewayLimitEvenForSlashHeavyAudio() async throws {
        let transport = UploadSizeTransport()
        let audio = WaveAudio.encode(samples: Array(repeating: -1, count: 48000 * 95), sampleRate: 48000)
        _ = try await CreditsAPI(transport: transport).transcribe(audio: audio, provider: .assemblyAI, model: "universal-3-5-pro", endpoint: nil, connection: CreditConnection(address: "http://localhost:4317", key: "s2t_demo_" + String(repeating: "a", count: 64)))
        let sizes = await transport.sizes
        XCTAssertGreaterThan(sizes.count, 1)
        XCTAssertTrue(sizes.allSatisfy { $0 < 12_000_000 })
    }
    func testLongRecordingRetrySkipsCompletedPartsAndKeepsUncertainPaymentIdentity() async throws {
        let transport = PartFailureTransport()
        let api = CreditsAPI(transport: transport)
        let connection = try CreditConnection(address: "http://localhost:4317", key: "s2t_demo_" + String(repeating: "a", count: 64))
        let audio = WaveAudio.encode(samples: Array(repeating: 11, count: 48000 * 150), sampleRate: 48000)
        let progress = PartProgress()
        do {
            _ = try await api.transcribe(audio: audio, provider: .assemblyAI, model: "universal-3-5-pro", endpoint: nil, connection: connection, requestID: "retry-fixture", onPartCompleted: { key, text in await progress.save(key, text) })
            XCTFail("The second part must fail")
        } catch { }
        let saved = await progress.values
        XCTAssertEqual(saved.count, 1)
        let result = try await api.transcribe(audio: audio, provider: .assemblyAI, model: "universal-3-5-pro", endpoint: nil, connection: connection, requestID: "retry-fixture", completedParts: saved, onPartCompleted: { key, text in await progress.save(key, text) })
        XCTAssertEqual(result.text, "First Second Third")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Idempotency-Key"), requests[2].value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertEqual(requests[1].httpBody, requests[2].httpBody)
        XCTAssertNotEqual(requests[0].value(forHTTPHeaderField: "Idempotency-Key"), requests[2].value(forHTTPHeaderField: "Idempotency-Key"))
    }
}

private actor PartProgress {
    var values: [String: String] = [:]
    func save(_ key: String, _ text: String) { values[key] = text }
}

private actor PartFailureTransport: HTTPTransport {
    var requests: [URLRequest] = []
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let count = requests.count
        let text = count == 1 ? "First" : count == 3 ? "Second" : "Third"
        let body = count == 2 ? #"{"error":"Temporary outage"}"# : "{\"state\":\"settled\",\"result\":{\"text\":\"\(text)\",\"model\":\"universal-3-5-pro\"}}"
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: count == 2 ? 503 : 200, httpVersion: nil, headerFields: nil)!)
    }
}

private actor UploadSizeTransport: HTTPTransport {
    var sizes: [Int] = []
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sizes.append(request.httpBody?.count ?? 0)
        return (Data(#"{"state":"settled","result":{"text":"Words","model":"universal-3-5-pro"}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
