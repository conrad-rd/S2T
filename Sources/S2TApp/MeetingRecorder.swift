import AppKit
import AVFoundation
import Combine
import S2TCore

@MainActor final class MeetingRecorder: ObservableObject {
    @Published private(set) var records: [MeetingRecord] = []
    @Published var selectedID: UUID?
    @Published var model: MeetingModel { didSet { defaults.set(model.rawValue, forKey: "meetings.model"); defaults.set(model.rawValue, forKey: "meetings.model." + model.provider.rawValue) } }
    @Published var textSettings: MeetingProcessingSettings { didSet {
        if let data = try? JSONEncoder().encode(textSettings) { defaults.set(data, forKey: "meetings.processing") }
    } }
    @Published var includeMacAudio: Bool { didSet { defaults.set(includeMacAudio, forKey: "meetings.macAudio") } }
    @Published private(set) var recording = false
    @Published private(set) var starting = false
    @Published private(set) var processing = false
    @Published private(set) var textModels: [OpenRouterTextModel] = []
    @Published private(set) var modelCatalogError = ""
    @Published private(set) var loadingModels = false
    private var requestedModels = false
    func loadTextModels(preview: Bool, refresh: Bool = false) {
        guard !preview, !loadingModels, refresh || !requestedModels else { return }
        requestedModels = true; loadingModels = true
        Task {
            defer { loadingModels = false }
            do { textModels = try await OpenRouterTextModel.load(); modelCatalogError = "" }
            catch { modelCatalogError = "Could not refresh models. Saved choices and manual model IDs remain available." }
        }
    }
    @Published private(set) var elapsed: Double = 0
    @Published var error = ""
    private let defaults: UserDefaults
    let store: MeetingStore
    private let microphone: Microphone
    private let requestMicrophoneAccess: (() async -> Bool)?
    private var systemAudio: (any MeetingSystemCapturing)?
    private let systemAudioFactory: (() -> any MeetingSystemCapturing)?
    private var captureTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var activeID: UUID?
    private weak var state: AppState?
    private var writers: [String: MeetingAudioWriter] = [:]
    private var stopped = false
    private var microphoneChanges: AnyCancellable?
    private let transcriber: MeetingTranscriber
    private let processingAPI: DictationAPI
    var selected: MeetingRecord? { records.first { $0.id == selectedID } }
    var isActive: Bool { recording || starting }

    init(directory: URL? = nil, defaults: UserDefaults = .standard, transcriber: MeetingTranscriber = .init(), microphone: Microphone = Microphone(), requestMicrophoneAccess: (() async -> Bool)? = nil, processingAPI: DictationAPI = .init(), systemAudioFactory: (() -> any MeetingSystemCapturing)? = nil) {
        self.systemAudioFactory = systemAudioFactory
        self.processingAPI = processingAPI
        self.microphone = microphone; self.requestMicrophoneAccess = requestMicrophoneAccess
        self.defaults = defaults; self.transcriber = transcriber
        store = MeetingStore(directory: directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("S2T/Meetings", isDirectory: true))
        textSettings = defaults.data(forKey: "meetings.processing").flatMap { try? JSONDecoder().decode(MeetingProcessingSettings.self, from: $0) } ?? .init()
        model = MeetingModel(rawValue: defaults.string(forKey: "meetings.model") ?? "") ?? .universal35
        includeMacAudio = defaults.object(forKey: "meetings.macAudio") as? Bool ?? true
        do {
            let loaded = try store.loadWithIssues()
            records = loaded.records
            var failures = loaded.unreadableFolders.map { "Unreadable meeting: " + $0 }
            for index in records.indices where records[index].endedAt == nil {
                do {
                    records[index] = try MeetingRecovery.recover(records[index], store: store)
                    try store.save(records[index])
                } catch { failures.append("Could not recover \(records[index].title): " + error.localizedDescription) }
            }
            selectedID = records.first?.id
            if !failures.isEmpty { error = failures.joined(separator: "\n") }
        } catch { self.error = "Meeting history could not be loaded: " + error.localizedDescription }
        microphoneChanges = NotificationCenter.default.publisher(for: Microphone.configurationChanged, object: microphone)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self, self.isActive else { return }
                self.error = "The microphone changed or disconnected. The meeting has stopped; recorded audio is saved."
                self.stop()
            }
    }

    func selectSpeechProvider(_ value: String) {
        guard !isActive, ["assemblyai", "xai"].contains(value) else { return }
        defaults.set(model.rawValue, forKey: "meetings.model." + model.provider.rawValue)
        let saved = defaults.string(forKey: "meetings.model." + value).flatMap(MeetingModel.init(rawValue:))
        model = saved?.provider.rawValue == value ? saved! : value == "xai" ? .grok2 : .universal35
    }

    func start(state: AppState) {
        guard !isActive else { return }
        guard !speechKey(for: model, state: state).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "Add your " + model.provider.title + " API key under API keys. Meetings use your personal key."; return
        }
        do { try state.reserveMeetingRecording() } catch { self.error = error.localizedDescription; return }
        self.state = state; starting = true; stopped = false; error = ""; elapsed = 0
        let withMac = includeMacAudio
        captureTask = Task {
            do {
                let granted: Bool
                if let requestMicrophoneAccess { granted = await requestMicrophoneAccess() }
                else if state.isPreview { granted = false }
                else { granted = await AVCaptureDevice.requestAccess(for: .audio) }
                guard granted else { throw ServiceError.message("Allow microphone access in System Settings to record a meeting.") }
                guard !stopped else { throw CancellationError() }
                if withMac {
                    if let systemAudioFactory {
                        let audio = systemAudioFactory(); systemAudio = audio; try await audio.start()
                    } else if #available(macOS 14.2, *) {
                        let audio = MeetingSystemAudio(); systemAudio = audio; try await audio.start()
                    } else { throw ServiceError.message("Mac call audio requires macOS 14.2 or later. Choose Microphone only on this Mac.") }
                }
                guard !stopped else { throw CancellationError() }
                try await microphone.start(deviceUID: state.microphoneUID)
                guard !stopped else { throw CancellationError() }
                var record = MeetingRecord(title: "Meeting " + Date().formatted(date: .abbreviated, time: .shortened), model: model)
                record.processingSettings = textSettings
                if withMac { record.speakerNames["You"] = "You" }
                try store.save(record)
                records.insert(record, at: 0); selectedID = record.id; activeID = record.id
                starting = false; recording = true
                while !stopped {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    try await collect(withMac: withMac)
                    processPending()
                }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
            await finishCapture(withMac: withMac)
            state.releaseMeetingRecording()
            starting = false; recording = false; activeID = nil
            processPending()
        }
    }

    func stop() { guard isActive else { return }; stopped = true }
    func stopAndWait() async { stop(); await captureTask?.value }

    private func collect(withMac: Bool) async throws {
        guard let id = activeID else { return }
        let mic = microphone.drainMeetingAudio()
        let micTime = microphone.audioStartTime ?? ProcessInfo.processInfo.systemUptime
        var origin = micTime
        if let start = systemAudio?.audioStartTime { origin = min(origin, start) }
        try await append(mic.samples, rate: mic.sampleRate, source: withMac ? "You" : "room", offset: max(0, micTime - origin), id: id)
        if let system = systemAudio {
            let chunk = try system.drain()
            let offset = max(0, (system.audioStartTime ?? origin) - origin)
            try await append(chunk.samples, rate: chunk.sampleRate, source: "call", offset: offset, id: id)
        }
        elapsed = records.first { $0.id == id }?.duration ?? 0
    }

    private func append(_ samples: [Int16], rate: Int, source: String, offset: Double, id: UUID) async throws {
        guard !samples.isEmpty, let index = records.firstIndex(where: { $0.id == id }) else { return }
        let writer: MeetingAudioWriter
        if let existing = writers[source] { writer = existing }
        else { writer = MeetingAudioWriter(folder: store.folder(id), source: source, rate: rate, offset: offset); writers[source] = writer }
        let chunks = try await writer.append(samples)
        for chunk in chunks {
            if let existing = records[index].chunks.firstIndex(where: { $0.id == chunk.id }) {
                let old = records[index].chunks[existing]
                if !old.ready { records[index].chunks[existing] = chunk }
            } else { records[index].chunks.append(chunk) }
        }
        try store.save(records[index])
    }

    private func finishCapture(withMac: Bool) async {
        await systemAudio?.stop()
        let final = await microphone.finish()
        var failures: [String] = []
        if let id = activeID {
            do {
                let pcm = try MeetingPCM.decode(final)
                try await append(pcm.samples, rate: pcm.rate, source: withMac ? "You" : "room", offset: 0, id: id)
            } catch { failures.append(error.localizedDescription) }
            if let system = systemAudio {
                let audio = system.drainFinal()
                if audio.overflowed { error = "Mac audio filled its buffer. The meeting stopped; audio captured before the overflow is saved." }
                do {
                    try await append(audio.samples, rate: audio.sampleRate, source: "call", offset: 0, id: id)
                } catch { failures.append(error.localizedDescription) }
            }
            var closed = Set<String>()
            for (source, writer) in writers {
                do { try await writer.close(); closed.insert(source) }
                catch { failures.append(error.localizedDescription) }
            }
            if let index = records.firstIndex(where: { $0.id == id }) {
                for part in records[index].chunks.indices where closed.contains(records[index].chunks[part].source) {
                    records[index].chunks[part].ready = true
                }
                // A failed write keeps crash recovery eligible on the next launch.
                if failures.isEmpty { records[index].endedAt = Date() }
                do { try store.save(records[index]) }
                catch { failures.append(error.localizedDescription) }
            }
        }
        if !failures.isEmpty { error = "The meeting stopped, but saving needs attention: " + failures.joined(separator: "; ") }
        systemAudio = nil; writers = [:]
    }

    func retry(state: AppState) {
        guard !processing else { return }
        self.state = state
        guard let index = records.firstIndex(where: { $0.id == selectedID }) else { return }
        for part in records[index].chunks.indices {
            records[index].chunks[part].error = nil
            records[index].chunks[part].processingError = nil
        }
        error = ""; processPending()
    }

    static func needsWork(_ chunk: MeetingChunk, in record: MeetingRecord) -> Bool {
        chunk.ready && chunk.error == nil && (!chunk.completed ||
            (record.processingSettings?.enabled == true && chunk.processingCompleted != true && chunk.processingError == nil))
    }
    private func speechKey(for model: MeetingModel, state: AppState) -> String {
        model.provider == .xai ? state.xaiKey : state.assemblyKey
    }
    private func processPending() {
        guard !processing, let state else { return }
        guard records.contains(where: { record in record.chunks.contains { Self.needsWork($0, in: record) } }) else { return }
        processing = true
        processingTask = Task {
            defer { processing = false }
            while let record = records.first(where: { record in record.chunks.contains { Self.needsWork($0, in: record) } }),
                  let chunk = record.chunks.first(where: { Self.needsWork($0, in: record) }) {
                if !chunk.completed {
                    do { try await transcribeChunk(chunk, record: record, key: speechKey(for: record.model, state: state)) }
                    catch {
                        let message = error is MeetingJobFailure ? "Meeting transcription failed. Retry will submit the saved audio again." : error.localizedDescription
                        try? updateChunk(record.id, chunk.id) {
                            $0.error = message
                            if error is MeetingJobFailure { $0.jobID = nil }
                        }
                        self.error = message
                        continue
                    }
                }
                if record.processingSettings?.enabled == true {
                    do { try await processText(recordID: record.id, chunkID: chunk.id) }
                    catch {
                        let message = "Text processing failed. Original transcript kept. " + error.localizedDescription
                        try? updateChunk(record.id, chunk.id) { $0.processingError = message }
                        self.error = message
                    }
                }
            }
        }
    }
    private func transcribeChunk(_ chunk: MeetingChunk, record: MeetingRecord, key: String) async throws {
        let folder = store.folder(record.id)
        let prepared = try await Task.detached { try MeetingSpeakerAudio.prepare(record: record, chunk: chunk, folder: folder) }.value
        try updateChunk(record.id, chunk.id) {
            $0.anchors = prepared.anchors; $0.prefixDuration = prepared.prefix; $0.requestFilename = prepared.filename
        }
        let result: [MeetingUtterance]
        if record.model.provider == .xai {
            result = try await transcriber.transcribeGrok(audio: prepared.audio, key: key, model: record.model)
        } else {
            let job: String
            if let existing = chunk.jobID { job = existing }
            else {
                job = try await transcriber.submit(audio: prepared.audio, key: key, model: record.model)
                try updateChunk(record.id, chunk.id) { $0.jobID = job }
            }
            result = try await transcriber.result(id: job, key: key)
        }
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        var translated = MeetingSpeakers.resolve(result, anchors: prepared.anchors, prefix: prepared.prefix, offset: chunk.start,
            namespace: "\(chunk.source == "call" ? "Call" : "Room") \(chunk.index + 1)")
        if chunk.source == "You" { for index in translated.indices { translated[index].speaker = "You" } }
        for value in translated where records[index].speakerNames[value.speaker] == nil {
            let count = records[index].speakerNames.keys.filter { $0 != "You" }.count
            records[index].speakerNames[value.speaker] = value.speaker == "You" ? "You" : "Speaker \(count + 1)"
        }
        records[index].utterances += translated
        try updateChunk(record.id, chunk.id) { $0.completed = true; $0.error = nil; $0.utteranceIDs = translated.map(\.id) }
    }
    private func processText(recordID: UUID, chunkID: UUID) async throws {
        guard let record = records.first(where: { $0.id == recordID }),
              let chunk = record.chunks.first(where: { $0.id == chunkID }),
              let settings = record.processingSettings, settings.enabled, let state else { return }
        let ids = Set(chunk.utteranceIDs ?? [])
        let original = record.utterances.filter { ids.contains($0.id) }
        if original.isEmpty { try updateChunk(recordID, chunkID) { $0.processingCompleted = true }; return }
        let provider = settings.selectedProvider
        let key = provider == .openRouter ? state.routerKey : provider == .xai ? state.xaiKey : ""
        let codexModel = provider == .codex && !state.isPreview ? (try? CodexModelCatalog.read())?.first { $0.slug == settings.model } : nil
        let result = try await processingAPI.processMeeting(original, settings: settings, apiKey: key, codexExecutable: state.codexExecutable,
            codexOptions: codexModel?.normalized(settings.codex) ?? .init())
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        let updates = Dictionary(uniqueKeysWithValues: result.utterances.map { ($0.id, $0.processedText) })
        for position in records[index].utterances.indices where ids.contains(records[index].utterances[position].id) {
            records[index].utterances[position].processedText = updates[records[index].utterances[position].id] ?? nil
        }
        try updateChunk(recordID, chunkID) {
            $0.processingCompleted = true; $0.processingError = nil; $0.processingModel = result.model; $0.processingHost = result.host
        }
    }
    private func updateChunk(_ id: UUID, _ chunk: UUID, edit: (inout MeetingChunk) -> Void) throws {
        guard let index = records.firstIndex(where: { $0.id == id }), let part = records[index].chunks.firstIndex(where: { $0.id == chunk }) else { return }
        edit(&records[index].chunks[part]); try store.save(records[index])
    }
    func renameSpeaker(_ speaker: String, name: String) {
        guard let index = records.firstIndex(where: { $0.id == selectedID }) else { return }
        records[index].speakerNames[speaker] = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? speaker : name
        do { try store.save(records[index]) } catch { self.error = error.localizedDescription }
    }
    func renameMeeting(_ title: String) {
        guard let index = records.firstIndex(where: { $0.id == selectedID }), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        records[index].title = title
        do { try store.save(records[index]) } catch { self.error = error.localizedDescription }
    }
}

actor MeetingAudioWriter {
    private let folder: URL
    private let source: String
    private let rate: Int
    private let offset: Double
    private var frameCount = 0
    private var partFrames = 0
    private var index = 0
    private var handle: FileHandle?
    private var current: MeetingChunk?
    init(folder: URL, source: String, rate: Int, offset: Double) { self.folder = folder; self.source = source; self.rate = rate; self.offset = offset }
    func append(_ samples: [Int16]) throws -> [MeetingChunk] {
        var position = 0
        var updates: [MeetingChunk] = []
        while position < samples.count {
            if handle == nil {
                let name = "\(source)-\(index).wav"
                let url = folder.appendingPathComponent(name)
                try WaveAudio.encode(samples: [], sampleRate: UInt32(rate)).write(to: url, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                handle = try FileHandle(forUpdating: url); try handle?.seekToEnd()
                var chunk = MeetingChunk(index: index, start: offset + Double(frameCount) / Double(rate), duration: 0, filename: name)
                chunk.source = source; chunk.sampleRate = rate; current = chunk; partFrames = 0
            }
            let count = min(samples.count - position, rate * 120 - partFrames)
            let data = samples[position..<(position + count)].withUnsafeBytes { Data($0) }
            try handle?.write(contentsOf: data)
            position += count; frameCount += count; partFrames += count
            current?.duration = Double(partFrames) / Double(rate)
            try rewriteHeader()
            if partFrames == rate * 120 { current?.ready = true; try handle?.synchronize(); try handle?.close(); handle = nil; index += 1 }
            if let current { updates.append(current) }
        }
        return updates
    }
    private func rewriteHeader() throws {
        var header = WaveAudio.encode(samples: [], sampleRate: UInt32(rate))
        for (offset, value) in [(4, partFrames * 2 + 36), (40, partFrames * 2)] {
            for byte in 0..<4 { header[offset + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8)) }
        }
        try handle?.seek(toOffset: 0); try handle?.write(contentsOf: header); try handle?.seekToEnd()
    }
    func close() throws {
        let file = handle
        handle = nil
        defer { try? file?.close() }
        try file?.synchronize()
        try file?.close()
    }
}

enum MeetingPCM {
    static func decode(_ audio: Data) throws -> (samples: [Int16], rate: Int) {
        guard audio.count >= 44, audio.count % 2 == 0, String(data: audio.prefix(4), encoding: .ascii) == "RIFF" else { throw ServiceError.message("The saved meeting audio is unreadable.") }
        let rate = (0..<4).reduce(0) { $0 | Int(audio[24 + $1]) << ($1 * 8) }
        let samples = stride(from: 44, to: audio.count, by: 2).map { Int16(bitPattern: UInt16(audio[$0]) | UInt16(audio[$0 + 1]) << 8) }
        return (samples, rate)
    }
}

struct MeetingSpeakerAudio {
    var audio: Data
    var anchors: [MeetingSpeakerAnchor]
    var prefix: Double
    var filename: String?
    static func prepare(record: MeetingRecord, chunk: MeetingChunk, folder: URL) throws -> Self {
        if let filename = chunk.requestFilename {
            let owned = Set(record.chunks.filter { $0.completed && $0.source == chunk.source }.flatMap { $0.utteranceIDs ?? [] })
            let speakers = Set(record.utterances.filter { owned.contains($0.id) }.map(\.speaker))
            // Old saved requests may already contain cross-source context. Keep
            // their exact audio/job identity, but never reuse an unowned label.
            return Self(audio: try Data(contentsOf: folder.appendingPathComponent(filename)), anchors: chunk.anchors.filter { speakers.contains($0.speaker) }, prefix: chunk.prefixDuration, filename: filename)
        }
        let raw = try Data(contentsOf: folder.appendingPathComponent(chunk.filename))
        guard chunk.source != "You", chunk.index > 0 else { return Self(audio: raw, anchors: [], prefix: 0, filename: nil) }
        let current = try MeetingPCM.decode(raw)
        var prefix: [Int16] = []
        var anchors: [MeetingSpeakerAnchor] = []
        let prior = record.chunks.filter { $0.completed && $0.source == chunk.source && $0.sampleRate == current.rate }
        var seen = Set<String>()
        for utterance in record.utterances.sorted(by: { ($0.end - $0.start) > ($1.end - $1.start) }) {
            guard anchors.count < 20, !seen.contains(utterance.speaker), utterance.end - utterance.start >= 1,
                  let part = prior.first(where: { $0.utteranceIDs?.contains(utterance.id) == true && utterance.start >= $0.start && utterance.end <= $0.start + $0.duration + 0.1 }) else { continue }
            let pcm = try MeetingPCM.decode(Data(contentsOf: folder.appendingPathComponent(part.filename)))
            let start = max(0, Int((utterance.start - part.start) * Double(current.rate)))
            let end = min(pcm.samples.count, Int((min(utterance.end, utterance.start + 8) - part.start) * Double(current.rate)))
            guard end > start else { continue }
            let anchorStart = Double(prefix.count) / Double(current.rate)
            prefix += pcm.samples[start..<end]
            anchors.append(.init(speaker: utterance.speaker, start: anchorStart, end: Double(prefix.count) / Double(current.rate)))
            prefix += Array(repeating: 0, count: current.rate)
            seen.insert(utterance.speaker)
        }
        guard !anchors.isEmpty else { return Self(audio: raw, anchors: [], prefix: 0, filename: nil) }
        let duration = Double(prefix.count) / Double(current.rate)
        prefix += current.samples
        let audio = WaveAudio.encode(samples: prefix, sampleRate: UInt32(current.rate))
        let filename = "context-\(chunk.id.uuidString).wav"
        let url = folder.appendingPathComponent(filename)
        try audio.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return Self(audio: audio, anchors: anchors, prefix: duration, filename: filename)
    }
}

enum MeetingRecovery {
    static func recover(_ saved: MeetingRecord, store: MeetingStore) throws -> MeetingRecord {
        var record = saved
        let folder = store.folder(record.id)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        for url in files where url.pathExtension == "wav" {
            let pieces = url.deletingPathExtension().lastPathComponent.split(separator: "-")
            guard pieces.count == 2, ["You", "room", "call"].contains(String(pieces[0])), let number = Int(pieces[1]), number >= 0 else { continue }
            let existing = record.chunks.firstIndex { $0.filename == url.lastPathComponent }
            if let existing, record.chunks[existing].completed { continue }
            let handle = try FileHandle(forUpdating: url)
            defer { try? handle.close() }
            guard var header = try handle.read(upToCount: 44), header.count == 44,
                  String(data: header.prefix(4), encoding: .ascii) == "RIFF",
                  String(data: header[36..<40], encoding: .ascii) == "data" else { throw ServiceError.message("A saved meeting part has an invalid WAV header.") }
            let rate = (0..<4).reduce(0) { $0 | Int(header[24 + $1]) << ($1 * 8) }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let bytes = size - 44
            guard rate >= 8000, rate <= 192000, bytes >= 0, bytes % 2 == 0, bytes <= rate * 240 else { throw ServiceError.message("A saved meeting part has an invalid length.") }
            for (offset, value) in [(4, bytes + 36), (40, bytes)] {
                for byte in 0..<4 { header[offset + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8)) }
            }
            try handle.seek(toOffset: 0); try handle.write(contentsOf: header); try handle.synchronize()
            let source = String(pieces[0])
            let sourceOffset = record.chunks.first { $0.source == source && $0.index == 0 }?.start ?? 0
            var chunk = existing.map { record.chunks[$0] } ?? MeetingChunk(index: number, start: sourceOffset + Double(number * 120), duration: 0, filename: url.lastPathComponent)
            chunk.source = source; chunk.sampleRate = rate; chunk.duration = Double(bytes) / Double(rate * 2); chunk.ready = true
            if let existing { record.chunks[existing] = chunk } else { record.chunks.append(chunk) }
        }
        record.chunks.sort { $0.start < $1.start }
        record.endedAt = record.createdAt.addingTimeInterval(record.duration)
        return record
    }
}
