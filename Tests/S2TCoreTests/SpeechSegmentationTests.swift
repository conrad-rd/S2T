import XCTest
@testable import S2TCore

final class SpeechSegmentationTests: XCTestCase {
    func testContinuousSpeechIsNeverCutAndPausesKeepEveryFrame() throws {
        let rate = 16000
        var detector = SpeechSegmentation()
        for _ in 0..<95 {
            XCTAssertNil(detector.append(Array(repeating: 1000, count: rate), sampleRate: rate))
        }
        XCTAssertNil(detector.append(Array(repeating: 0, count: rate / 4), sampleRate: rate))
        XCTAssertEqual(detector.append(Array(repeating: 0, count: rate / 4), sampleRate: rate), rate * 95 + rate / 4)
        XCTAssertNil(detector.append(Array(repeating: 0, count: rate * 20), sampleRate: rate))
    }

    func testShortUtteranceWaitsForFinish() {
        var detector = SpeechSegmentation()
        XCTAssertNil(detector.append(Array(repeating: 1000, count: 16000 * 3), sampleRate: 16000))
        XCTAssertNil(detector.append(Array(repeating: 0, count: 16000), sampleRate: 16000))
    }

    func testSavedBoundariesPreserveAudioAndEarlierUploadsExactly() throws {
        let rate = 16000
        let samples = (0..<rate * 25).map { Int16(truncatingIfNeeded: $0) }
        let audio = WaveAudio.encode(samples: samples, sampleRate: UInt32(rate))
        let ends = [rate * 9, rate * 18]
        let parts = try WaveAudio.segmentedSpeechParts(audio, ends: ends)
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts.reduce(into: Data()) { $0.append($1.dropFirst(44)) }, audio.dropFirst(44))
        for inputRate in [16000, 24000, 44100, 48000] {
            let source = (0..<inputRate * 20).map { Int16(truncatingIfNeeded: $0 * 7) }
            let end = inputRate * 9
            let before = WaveAudio.encode(samples: Array(source.prefix(end)), sampleRate: UInt32(inputRate))
            let after = WaveAudio.encode(samples: source, sampleRate: UInt32(inputRate))
            XCTAssertEqual(try WaveAudio.segmentedSpeechParts(before, ends: [end]).first,
                           try WaveAudio.segmentedSpeechParts(after, ends: [end]).first)
        }
        for invalid in [[0], [-1], [rate * 30], [100, 90], [100, 100]] {
            XCTAssertThrowsError(try WaveAudio.segmentedSpeechParts(audio, ends: invalid))
        }
    }

    func testGrowingRecordingReusesPaidPrefixAndRetriesUncertainTail() async throws {
        let transport = SegmentedSpeechTransport()
        let api = CreditsAPI(transport: transport)
        let connection = try CreditConnection(address: "http://localhost:4317", key: "s2t_demo_" + String(repeating: "a", count: 64))
        let samples = Array(repeating: Int16(300), count: 16000 * 18)
        let prefix = WaveAudio.encode(samples: Array(samples.prefix(16000 * 9)), sampleRate: 16000)
        let full = WaveAudio.encode(samples: samples, sampleRate: 16000)
        let cache = SegmentedSpeechCache()
        _ = try await api.transcribe(audio: prefix, provider: .assemblyAI, model: "universal-3-5-pro", endpoint: nil,
            connection: connection, requestID: "growing", segmentEnds: [16000 * 9],
            onPartCompleted: { key, text in await cache.save(key, text) })
        do {
            _ = try await api.transcribe(audio: full, provider: .assemblyAI, model: "universal-3-5-pro", endpoint: nil,
                connection: connection, requestID: "growing", completedParts: await cache.values, segmentEnds: [16000 * 9])
            XCTFail("The first tail request must fail")
        } catch { }
        let result = try await api.transcribe(audio: full, provider: .assemblyAI, model: "universal-3-5-pro", endpoint: nil,
            connection: connection, requestID: "growing", completedParts: await cache.values, segmentEnds: [16000 * 9])
        XCTAssertEqual(result.text, "First section Last section")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[1].httpBody, requests[2].httpBody)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Idempotency-Key"), requests[2].value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertNotEqual(requests[0].value(forHTTPHeaderField: "Idempotency-Key"), requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
    }
}

private actor SegmentedSpeechCache {
    var values: [String: String] = [:]
    func save(_ key: String, _ text: String) { values[key] = text }
}

private actor SegmentedSpeechTransport: HTTPTransport {
    var requests: [URLRequest] = []
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let count = requests.count
        if count == 2 { throw URLError(.badServerResponse) }
        let text = count == 1 ? "First section" : "Last section"
        return (Data("{\"state\":\"settled\",\"result\":{\"text\":\"\(text)\",\"model\":\"universal-3-5-pro\"}}".utf8),
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
