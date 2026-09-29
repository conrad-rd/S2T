import XCTest
@testable import S2TCore

final class RecoveryResilienceTests: XCTestCase {
    func testCorruptSiblingDoesNotHideAudioOrPreventNewSaves() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RecordingRecoveryStore(directory: folder, key: { Data(repeating: 7, count: 32) })
        let good = RecordingRecovery(audio: Data([1, 2]), requestID: "fixture", mode: .clean)
        try await store.save(good)
        let bad = folder.appendingPathComponent(UUID().uuidString + ".enc")
        try Data([0]).write(to: bad)
        let pending = try await store.pending()
        XCTAssertEqual(pending.map(\.id), [good.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: bad.path))
        try await store.complete(good)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(good.id.uuidString + ".enc").path))
    }

    func testCorruptMeetingManifestDoesNotHideHealthyMeeting() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = MeetingStore(directory: folder)
        let good = MeetingRecord(title: "Kept", model: .universal2)
        try store.save(good)
        try FileManager.default.createDirectory(at: store.folder(UUID()), withIntermediateDirectories: true)
        XCTAssertEqual(try store.load().map(\.id), [good.id])
    }

    func testEarlySpeechResamplesNativeRatesAndKeepsRetryBytes() throws {
        for rate in [22050, 32000, 96000] {
            let samples = Array(repeating: Int16(300), count: rate * 2)
            let audio = WaveAudio.encode(samples: samples, sampleRate: UInt32(rate))
            XCTAssertEqual(try WaveAudio.segmentedSpeechParts(audio, ends: []), try WaveAudio.creditParts(WaveAudio.speechUpload(audio)))
            let prefix = WaveAudio.encode(samples: Array(samples.prefix(rate)), sampleRate: UInt32(rate))
            XCTAssertEqual(try WaveAudio.segmentedSpeechParts(prefix, ends: [rate]).first,
                           try WaveAudio.segmentedSpeechParts(audio, ends: [rate]).first)
        }
    }
}
