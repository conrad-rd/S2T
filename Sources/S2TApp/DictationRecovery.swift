import AppKit
import Foundation
import S2TCore

extension AppState {
    func processRecording(_ captured: Data, prepared: RecordingRecovery? = nil) {
        if dictationSession == nil || recovery != nil || phase != .transcribing {
            dictationSession = DictationSession(configuration: DictationConfiguration(self))
        }
        creditRequestID = prepared?.requestID ?? UUID().uuidString
        recording = captured
        recovery = prepared ?? RecordingRecovery(audio: captured, requestID: creditRequestID, mode: sessionMode)
        recovery?.speechUploadRate = WaveAudio.speechUploadRate
        recoveryIsSaved = false
        promptImages = []
        rawTranscript = ""
        output = ""
        modelUsed = ""
        showOriginal = false
        runPipeline()
    }

    func retry() {
        guard canRetry else { return }
        guard cleanupUsesCredits || processingProvider != nil || mode == .verbatim else { page = .connections; notice = "Choose a text cleanup provider first."; return }
        if finishTargetTask == nil, !isPreview { rememberFinishDestination() }
        let previous = dictationSession
        dictationSession = DictationSession(configuration: DictationConfiguration(self), audio: previous?.audio, recovery: previous?.recovery)
        dictationSession?.isSaved = previous?.isSaved ?? true
        runPipeline()
    }

    var canRetry: Bool { !phase.busy && phase != .recording && (phase == .failed || recovery != nil) && (recording != nil || recovery != nil || isPreview && dictationSession == nil && !rawTranscript.isEmpty) }

    func refreshRecoveredRecordings() async {
        guard let recoveryStore else { return }
        do {
            recoveredRecordings = try await recoveryStore.pending()
            let unreadable = await recoveryStore.unreadableFiles
            await refreshHistoricalStreamingReceipts()
            if !unreadable.isEmpty { notice = "Some saved recordings could not be read. Healthy recordings are available; the unreadable files have been preserved." }
            else if !recoveredRecordings.isEmpty && recovery == nil {
                notice = "An unfinished recording is saved. Open Dictation → Recording recovery → Recordings to recover it."
            }
        } catch { notice = "Saved recordings could not be opened. Existing files are preserved. " + error.localizedDescription }
    }

    func refreshHistoricalStreamingReceipts() async {
        guard let recoveryStore, let pending = try? await recoveryStore.pendingStreamingReports() else { return }
        historicalStreamingReceiptCount = pending.count
    }

    func recoverRecording(_ saved: RecordingRecovery) {
        guard !phase.busy, phase != .recording else { return }
        guard recovery == nil || recoveryIsSaved || recovery?.id == saved.id else {
            errorMessage = "Save the current recording before opening another. Its only copy is still in memory."
            return
        }
        dictationSession = DictationSession(configuration: DictationConfiguration(self), audio: saved.audio, recovery: saved)
        recording = saved.audio
        recovery = saved
        recoveryIsSaved = true
        creditRequestID = saved.requestID
        rawTranscript = saved.transcript
        output = saved.transcript
        promptSession = nil
        promptImages = []
        insertionTarget = nil
        finishTargetTask = nil
        phase = .failed
        errorMessage = "Recording recovered. Choose Retry to transcribe it, or Save recording to keep a WAV copy."
        if saved.streamingReceipt != nil { errorMessage! += " " + (historicalReceiptNotice ?? "This legacy streaming receipt needs service confirmation; its metadata is preserved.") }
    }

    func saveRecording() {
        guard canSaveRecording, let recording, !isPreview else { return }
        let savedID = recovery?.id
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "S2T recording.wav"
        panel.allowedContentTypes = [.wav]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try recording.write(to: url, options: .atomic)
                self?.notice = "Recording saved."
                if self?.recovery?.id == savedID { self?.recoveryIsSaved = true }
            } catch { self?.errorMessage = "Could not save the recording. " + error.localizedDescription }
        }
    }

    func publishRecovery(_ saved: RecordingRecovery) {
        recoveredRecordings.removeAll { $0.id == saved.id }
        if !saved.audio.isEmpty { recoveredRecordings.append(saved) }
        recoveredRecordings.sort { $0.createdAt > $1.createdAt }
    }

    func saveRecovery() async throws {
        guard let session = dictationSession else { return }
        let saved = try await session.save(transcript: rawTranscript, to: recoveryStore)
        if dictationSession === session, let saved, recoveryStore != nil { publishRecovery(saved) }
    }

    @discardableResult func finalizeSession(_ outcome: DictationSession.Outcome, session: DictationSession) async -> Bool {
        let transcript = dictationSession === session ? rawTranscript : session.recovery?.transcript ?? ""
        let id = session.recovery?.id
        do {
            let saved = try await session.finish(outcome, transcript: transcript, store: recoveryStore)
            if let saved, recoveryStore != nil { publishRecovery(saved) }
            else if let id { recoveredRecordings.removeAll { $0.id == id } }
            return true
        } catch {
            if dictationSession === session {
                notice = "The recording could not be saved. Its only copy may still be in memory. Use Save recording before quitting. " + error.localizedDescription
            }
            return false
        }
    }

    func completedSpeechPart(_ key: String, text: String, session: DictationSession) async throws {
        try Task.checkCancellation()
        guard dictationSession === session else { throw CancellationError() }
        recovery?.completedParts[key] = text
        try await saveRecovery()
    }


}
