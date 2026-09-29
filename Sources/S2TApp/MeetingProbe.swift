import AppKit
import PDFKit
import SwiftUI
import S2TCore

@MainActor enum MeetingProbe {
    static func run() async throws {
        let previewDefaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = previewDefaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { previewDefaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        previewDefaults.setPersistentDomain([:], forName: "com.s2t.preview")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("S2T-meeting-verification-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try verifySourceAnchors(folder: folder.appendingPathComponent("anchors"))
        let writer = MeetingAudioWriter(folder: folder, source: "room", rate: 16000, offset: 0)
        var signal: [Int16] = []
        for index in 0..<11_536_017 { signal.append(Int16(index % 32000 - 16000)) }
        var chunks: [UUID: MeetingChunk] = [:]
        for position in stride(from: 0, to: signal.count, by: 16000 * 7) {
            let updates = try await writer.append(Array(signal[position..<min(signal.count, position + 16000 * 7)]))
            for value in updates { chunks[value.id] = value }
        }
        try await writer.close()
        let ordered = chunks.values.sorted { $0.index < $1.index }
        guard ordered.count == 7, ordered.prefix(6).allSatisfy({ $0.ready && $0.duration == 120 }), ordered.last?.ready == false else { throw failure("Two-minute processing boundaries or final partial chunk failed") }
        var reconstructed: [Int16] = []
        for chunk in ordered { reconstructed += try MeetingPCM.decode(Data(contentsOf: folder.appendingPathComponent(chunk.filename))).samples }
        guard reconstructed == signal else { throw failure("Meeting audio was lost, repeated or truncated after ten minutes") }

        let recoveryStore = MeetingStore(directory: folder.appendingPathComponent("recovery"))
        let interrupted = MeetingRecord(title: "Interrupted", model: .universal2)
        try recoveryStore.save(interrupted)
        let recoveredFile = recoveryStore.folder(interrupted.id).appendingPathComponent("room-0.wav")
        var unfinished = WaveAudio.encode(samples: [1, 2, 3, 4], sampleRate: 16000)
        for byte in 0..<4 { unfinished[40 + byte] = 0 }
        try unfinished.write(to: recoveredFile)
        let repaired = try MeetingRecovery.recover(interrupted, store: recoveryStore)
        guard repaired.chunks.count == 1, repaired.chunks[0].ready,
              repaired.chunks[0].duration == 4.0 / 16000,
              try MeetingPCM.decode(Data(contentsOf: recoveredFile)).samples == [1, 2, 3, 4] else {
            throw failure("Crash recovery lost audio written before its manifest")
        }
        var record = MeetingRecord(title: "Meeting export verification", model: .universal35)
        for index in 0..<100 {
            let speaker = index % 2 == 0 ? "You" : "Alex"
            let text = "Transcript line \(index). Grüße, 日本語, and decisions remain readable in the export."
            record.utterances.append(MeetingUtterance(speaker: speaker, start: Double(index * 10), end: Double(index * 10 + 8), text: text))
        }
        for format in MeetingExport.Format.allCases {
            let data = try MeetingExport.data(record, format: format)
            guard !data.isEmpty else { throw failure("Empty \(format.title) export") }
            try data.write(to: folder.appendingPathComponent("export." + format.rawValue))
            switch format {
            case .pdf:
                guard let pdf = PDFDocument(data: data), pdf.pageCount > 1, pdf.string?.contains("Transcript line 99") == true else { throw failure("PDF pagination lost the final transcript") }
            case .word:
                guard data.prefix(2) == Data("PK".utf8) else { throw failure("Word export is not DOCX") }
                let decoded = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
                guard decoded.string.contains("Transcript line 99"), decoded.string.contains("Grüße") else { throw failure("Word export lost transcript text") }
            case .rtf:
                let decoded = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
                guard decoded.string.contains("Transcript line 99") else { throw failure("RTF export lost transcript text") }
            default: guard String(data: data, encoding: .utf8)?.contains("Transcript line 99") == true else { throw failure("Text export lost transcript text") }
            }
        }
        let suite = "S2T.meeting.verify." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try verifyHistoryIsolation(folder: folder.appendingPathComponent("damaged-history"), defaults: defaults)
        let state = AppState(preview: true)
        let window = AppearanceWindowController(state: state, presentsWindows: false)
        window.showMeetings()
        guard window.showingMeetings, !window.meetingsPane.view.isHidden, window.sidebar.table.selectedRow == window.sidebar.meetingsRow else { throw failure("Meetings navigation failed") }
        window.showModels()
        guard !window.showingMeetings, window.meetingsPane.view.isHidden else { throw failure("Meetings did not yield to Models") }
        window.showMeetings()
        guard !window.meetingsPane.view.isHidden else { throw failure("Meetings did not restore") }
        let isolated = MeetingRecorder(directory: folder.appendingPathComponent("library"), defaults: defaults)
        isolated.model = .universal2
        guard defaults.string(forKey: "meetings.model") == "universal-2", state.transcriptionModel == state.transcriptionProvider.defaultModel else { throw failure("Meeting model selection leaked into dictation") }
        try state.reserveMeetingRecording()
        state.toggleRecording()
        guard state.phase != .recording else { throw failure("Dictation started during a meeting") }
        do { try state.reserveWritingPromptDictation(); throw failure("Writing microphone was not reserved") }
        catch let error as NSError where error.domain == "MeetingProbe" { throw error }
        catch { }
        state.releaseMeetingRecording()
        let modelsFixture = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 780), styleMask: [.borderless], backing: .buffered, defer: true)
        let modelsView = NSHostingView(rootView: MeetingModelsView(state: state, meetings: state.meetings, back: {}))
        modelsFixture.contentView = modelsView
        modelsView.frame = NSRect(x: 0, y: 0, width: 700, height: 780)
        modelsView.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let popups = descendants(modelsView).compactMap { $0 as? NSPopUpButton }
        let choices = popups.flatMap(\.itemTitles)
        guard choices.contains("Universal 3.5 Pro"), choices.contains("Universal 2"), choices.contains("GPT-OSS 120B"),
              popups.contains(where: { $0.identifier?.rawValue == "meetings.processing.provider" && $0.numberOfItems == 4 }),
              !modelsFixture.isVisible else { throw failure("Meeting model pickers are not populated: " + choices.joined(separator: ", ")) }
        guard let providerPicker = popups.first(where: { $0.identifier?.rawValue == "meetings.speech.provider" }) else {
            throw failure("Missing meeting speech provider selector")
        }
        providerPicker.selectItem(at: 1)
        providerPicker.sendAction(providerPicker.action, to: providerPicker.target)
        try await Task.sleep(nanoseconds: 60_000_000)
        modelsView.layoutSubtreeIfNeeded()
        guard state.meetings.model == .grok2,
              descendants(modelsView).compactMap({ $0 as? NSPopUpButton }).contains(where: {
                  $0.identifier?.rawValue == "meetings.speech.model" && $0.itemTitles == ["Grok Voice Transcribe 2", "Grok Voice Transcribe 1"] && $0.isEnabled
              }) else { throw failure("Selecting xAI did not expose working voice-model choices") }
        state.meetings.model = .grok1
        state.meetings.selectSpeechProvider("assemblyai")
        state.meetings.selectSpeechProvider("xai")
        guard state.meetings.model == .grok1 else { throw failure("Provider switching lost the saved voice model") }
        state.meetings.selectSpeechProvider("assemblyai")
        state.assemblyKey = "verification-key"
        let overflowCapture = OverflowMeetingCapture()
        let overflowRecorder = MeetingRecorder(directory: folder.appendingPathComponent("overflow"), defaults: defaults,
            transcriber: MeetingTranscriber(transport: MeetingProbeTransport(), pollNanoseconds: 0),
            microphone: Microphone(simulatedAudio: Array(repeating: 0.1, count: 48_000), startDelay: 0),
            requestMicrophoneAccess: { true }, systemAudioFactory: { overflowCapture })
        overflowRecorder.includeMacAudio = true
        overflowRecorder.start(state: state)
        for _ in 0..<150 {
            if !overflowRecorder.isActive { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let overflowRecord = overflowRecorder.records.first, !overflowRecorder.isActive,
              overflowRecord.endedAt != nil, overflowCapture.stopped,
              overflowRecord.chunks.count == 2, overflowRecord.chunks.allSatisfy(\.ready),
              let call = overflowRecord.chunks.first(where: { $0.source == "call" }),
              try MeetingPCM.decode(Data(contentsOf: overflowRecorder.store.folder(overflowRecord.id).appendingPathComponent(call.filename))).samples == [11, 22, 33],
              try overflowRecorder.store.load().first?.endedAt != nil else {
            throw failure("Overflow prevented buffered audio, writer closure or terminal manifest from being saved: " + overflowRecorder.error)
        }
        state.routerKey = "verification-processing-key"
        let fakeAudio = Array(repeating: Float(0.1), count: 48_000 * 121)
        let speechTransport = MeetingProbeTransport()
        let simulated = MeetingRecorder(directory: folder.appendingPathComponent("pipeline"), defaults: defaults,
            transcriber: MeetingTranscriber(transport: speechTransport, pollNanoseconds: 0),
            microphone: Microphone(simulatedAudio: fakeAudio, startDelay: 0), requestMicrophoneAccess: { true }, processingAPI: DictationAPI(transport: MeetingProcessingProbeTransport()))
        simulated.textSettings.enabled = true
        simulated.textSettings.model = "openai/gpt-oss-120b"
        simulated.includeMacAudio = false
        simulated.start(state: state)
        for _ in 0..<100 {
            if simulated.records.first?.chunks.contains(where: { $0.completed }) == true { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard simulated.recording, simulated.records.first?.chunks.contains(where: { $0.completed && $0.duration == 120 }) == true else { throw failure("A two-minute part was not transcribed while recording: " + simulated.error) }
        await simulated.stopAndWait()
        for _ in 0..<100 {
            if !simulated.processing { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard simulated.records.first?.chunks.contains(where: { $0.processingError != nil }) == true,
              simulated.records.first?.utterances.contains(where: { $0.processedText == nil && $0.text == "Meeting words" }) == true else {
            throw failure("Failed meeting processing did not retain original text")
        }
        let uploadsBeforeRetry = await speechTransport.uploads
        simulated.textSettings.model = "unrelated/model"
        simulated.retry(state: state)
        for _ in 0..<100 {
            if !simulated.processing { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard await speechTransport.uploads == uploadsBeforeRetry else { throw failure("Processing retry uploaded audio again") }
        guard let completed = simulated.records.first, completed.endedAt != nil, completed.chunks.count == 2,
              completed.chunks.allSatisfy({ $0.completed && $0.processingCompleted == true }), !state.meetingRecordingActive, !completed.utterances.isEmpty else {
            throw failure("Stopping did not finish and persist the remaining meeting audio: " + simulated.error)
        }
        guard completed.utterances.allSatisfy({ $0.text == "Meeting words" && $0.processedText == "Meeting words." }),
              completed.processingSettings?.model == "openai/gpt-oss-120b" else { throw failure("Meeting processing did not preserve originals and model snapshot") }
        let restored = MeetingRecorder(directory: folder.appendingPathComponent("pipeline"), defaults: defaults)
        guard restored.records.first?.utterances.count == completed.utterances.count else { throw failure("Meeting history failed to survive reload") }
        state.xaiKey = "verification-xai-key"
        let grokTransport = GrokMeetingProbeTransport()
        let grok = MeetingRecorder(directory: folder.appendingPathComponent("grok-pipeline"), defaults: defaults,
            transcriber: MeetingTranscriber(transport: grokTransport),
            microphone: Microphone(simulatedAudio: Array(repeating: 0.1, count: 48_000), startDelay: 0),
            requestMicrophoneAccess: { true })
        grok.textSettings.enabled = false
        grok.model = .grok2
        grok.includeMacAudio = false
        grok.start(state: state)
        for _ in 0..<100 where !grok.recording { try await Task.sleep(nanoseconds: 10_000_000) }
        await grok.stopAndWait()
        for _ in 0..<100 where grok.processing { try await Task.sleep(nanoseconds: 10_000_000) }
        guard let grokRecord = grok.records.first, grokRecord.model == .grok2,
              grokRecord.chunks.allSatisfy(\.completed), grokRecord.speakers.count == 2,
              await grokTransport.correctKey else { throw failure("Grok meeting pipeline lost speakers, failed routing or used another provider's key: " + grok.error) }
        let restoredGrok = MeetingRecorder(directory: folder.appendingPathComponent("grok-pipeline"), defaults: defaults)
        guard restoredGrok.records.first?.model == .grok2, restoredGrok.records.first?.speakers.count == 2 else {
            throw failure("Grok meeting model and speaker labels did not survive reload")
        }
        print("Meetings verified: 12-minute lossless audio, two-minute chunks, partial tail, five export formats, PDF pagination, Word round trip, hidden navigation and microphone exclusion. No real audio, credentials or screen capture. Artifacts: \(folder.path)")
    }
    private static func verifyHistoryIsolation(folder: URL, defaults: UserDefaults) throws {
        let store = MeetingStore(directory: folder)
        var damaged = MeetingRecord(title: "Damaged audio", model: .universal35)
        damaged.createdAt = Date().addingTimeInterval(60)
        try store.save(damaged)
        try Data("broken".utf8).write(to: store.folder(damaged.id).appendingPathComponent("room-0.wav"))
        let healthy = MeetingRecord(title: "Healthy interrupted meeting", model: .universal35)
        try store.save(healthy)
        try WaveAudio.encode(samples: [11, 22, 33], sampleRate: 16000).write(to: store.folder(healthy.id).appendingPathComponent("room-0.wav"))
        let unreadable = UUID()
        try FileManager.default.createDirectory(at: store.folder(unreadable), withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: store.folder(unreadable).appendingPathComponent("meeting.json"))
        let recorder = MeetingRecorder(directory: folder, defaults: defaults)
        guard recorder.records.count == 2,
              recorder.records.first(where: { $0.id == healthy.id })?.endedAt != nil,
              recorder.records.first(where: { $0.id == healthy.id })?.chunks.first?.ready == true,
              recorder.records.first(where: { $0.id == damaged.id })?.endedAt == nil,
              recorder.error.contains(unreadable.uuidString), recorder.error.contains("Damaged audio") else {
            throw failure("A damaged meeting manifest or audio part hid healthy history or blocked its recovery")
        }
        let reloaded = try store.load()
        guard reloaded.first(where: { $0.id == healthy.id })?.chunks.count == 1 else {
            throw failure("Healthy meeting recovery did not persist alongside damaged history")
        }
    }

    private static func verifySourceAnchors(folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = WaveAudio.encode(samples: Array(repeating: 100, count: 16000 * 12), sampleRate: 16000)
        try audio.write(to: folder.appendingPathComponent("call-0.wav"))
        try audio.write(to: folder.appendingPathComponent("call-1.wav"))
        let local = MeetingUtterance(speaker: "You", start: 2, end: 10, text: "Local microphone")
        let remote = MeetingUtterance(speaker: "Remote", start: 3, end: 4, text: "Remote speaker")
        var prior = MeetingChunk(index: 0, start: 0, duration: 12, filename: "call-0.wav")
        prior.source = "call"; prior.sampleRate = 16000; prior.completed = true; prior.utteranceIDs = [remote.id]
        var next = MeetingChunk(index: 1, start: 12, duration: 12, filename: "call-1.wav")
        next.source = "call"; next.sampleRate = 16000
        var record = MeetingRecord(title: "Overlapping sources", model: .universal35)
        record.chunks = [prior, next]; record.utterances = [local, remote]
        let prepared = try MeetingSpeakerAudio.prepare(record: record, chunk: next, folder: folder)
        guard prepared.anchors.map(\.speaker) == ["Remote"] else { throw failure("Microphone speech contaminated call-audio speaker anchors") }
        var cached = next
        cached.requestFilename = prepared.filename; cached.prefixDuration = prepared.prefix
        cached.anchors = prepared.anchors + [.init(speaker: "You", start: 0, end: 1)]
        let restored = try MeetingSpeakerAudio.prepare(record: record, chunk: cached, folder: folder)
        guard restored.anchors.map(\.speaker) == ["Remote"], restored.audio == prepared.audio,
              restored.prefix == prepared.prefix else { throw failure("A saved request reused a cross-source anchor or changed its submitted audio") }
        record.chunks[0].utteranceIDs = nil
        guard try MeetingSpeakerAudio.prepare(record: record, chunk: next, folder: folder).anchors.isEmpty else {
            throw failure("Legacy chunks guessed speaker ownership from overlapping time ranges")
        }
    }
    private static func failure(_ text: String) -> NSError { NSError(domain: "MeetingProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}

private final class OverflowMeetingCapture: MeetingSystemCapturing, @unchecked Sendable {
    let audioStartTime: Double? = nil
    private(set) var stopped = false
    func start() async throws { }
    func stop() async { stopped = true }
    func drain() throws -> (samples: [Int16], sampleRate: Int) { throw ServiceError.message("Synthetic overflow") }
    func drainFinal() -> (samples: [Int16], sampleRate: Int, overflowed: Bool) { ([11, 22, 33], 48000, true) }
}

private actor MeetingProbeTransport: HTTPTransport {
    var uploads = 0
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let value: String
        if request.url!.path.hasSuffix("upload") { uploads += 1; value = #"{"upload_url":"https://cdn.assemblyai.com/fixture"}"# }
        else if request.httpMethod == "POST" { value = #"{"id":"fixture-job","status":"queued"}"# }
        else { value = #"{"id":"fixture-job","status":"completed","utterances":[{"speaker":"A","start":100,"end":700,"text":"Meeting words"}]}"# }
        return (Data(value.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private actor MeetingProcessingProbeTransport: HTTPTransport {
    private var shouldFail = true
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.host == "openrouter.ai", request.value(forHTTPHeaderField: "Authorization") == "Bearer verification-processing-key" else {
            throw ServiceError.message("Meeting processing used the wrong provider or key")
        }
        if shouldFail { shouldFail = false; return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!) }
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        guard body["model"] as? String == "openai/gpt-oss-120b" else { throw ServiceError.message("Retry changed the snapshotted meeting model") }
        let messages = body["messages"] as! [[String: String]]
        var entries = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [[String: String]]
        for index in entries.indices { entries[index]["text"] = "Meeting words." }
        let content = String(decoding: try JSONSerialization.data(withJSONObject: entries), as: UTF8.self)
        let reply: [String: Any] = ["model": "openai/gpt-oss-120b", "provider": "fixture-host", "choices": [["finish_reason": "stop", "message": ["content": content]]]]
        return (try JSONSerialization.data(withJSONObject: reply), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private actor GrokMeetingProbeTransport: HTTPTransport {
    private(set) var correctKey = false
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        correctKey = request.url?.host == "api.x.ai" && request.value(forHTTPHeaderField: "Authorization") == "Bearer verification-xai-key"
        let value = #"{"text":"Hello there","words":[{"text":"Hello","start":0.1,"end":0.4,"speaker":0},{"text":"there","start":0.5,"end":0.9,"speaker":1}]}"#
        return (Data(value.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
