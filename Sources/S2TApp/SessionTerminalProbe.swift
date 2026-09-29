import AppKit
import S2TCore

@MainActor enum SessionTerminalProbe {
    static func run() async throws {
        for deliveredFirst in [true, false] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-terminal-" + UUID().uuidString)
            let suite = "com.s2t.terminal." + UUID().uuidString
            let preferences = UserDefaults(suiteName: suite)!
            let gate = TerminalStoreGate()
            defer { gate.release(); preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
            let key = Data(repeating: 91, count: 32)
            let record = RecordingRecovery(audio: Data([1, 2]), requestID: "terminal-race", mode: .verbatim, transcript: "Saved words")
            let writer = RecordingRecoveryStore(directory: folder, key: { key })
            try await writer.save(record)
            let blocked = RecordingRecoveryStore(directory: folder, key: { try gate.wait(); return key })
            let read = Task { try await blocked.pending() }
            try await PaidSpeechRecoveryProbe.wait { gate.entered }
            let state = AppState(preview: true, previewPreferences: preferences)
            let session = DictationSession(configuration: DictationConfiguration(state), audio: record.audio, recovery: record)
            let first: DictationSession.Outcome = deliveredFirst ? .delivered : .interrupted
            let second: DictationSession.Outcome = deliveredFirst ? .interrupted : .delivered
            let transition1 = Task { try await session.finish(first, transcript: record.transcript, store: blocked) }
            try await Task.sleep(for: .milliseconds(10))
            let transition2 = Task { try await session.finish(second, transcript: record.transcript, store: blocked) }
            let cancellation = Task { try await session.finish(.cancelled, transcript: record.transcript, store: blocked) }
            try await Task.sleep(for: .milliseconds(10))
            gate.release()
            _ = try await read.value
            _ = try await transition1.value
            _ = try await transition2.value
            _ = try await cancellation.value
            guard try await blocked.pending().isEmpty, session.recovery == nil else {
                throw ServiceError.message("A concurrent interruption/cancellation resurrected delivered recovery audio")
            }
            _ = try await session.save(transcript: "Late checkpoint", to: blocked)
            guard try await blocked.pending().isEmpty else { throw ServiceError.message("A late checkpoint resurrected completed recovery") }
        }
        print("Session terminal transitions: delivery wins concurrent interruption/cancel/checkpoint in either ordering PASS")
    }
}

private final class TerminalStoreGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var hasEntered = false
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return hasEntered }
    func wait() throws {
        lock.lock(); hasEntered = true; lock.unlock()
        guard semaphore.wait(timeout: .now() + 5) == .success else { throw CocoaError(.userCancelled) }
    }
    func release() { semaphore.signal() }
}
