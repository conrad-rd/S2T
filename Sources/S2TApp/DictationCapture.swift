import AppKit
import Foundation
import S2TCore

extension AppState {
    func startRecording(prompt: Bool) {
        guard !isPreservingRecording else { return }
        guard recovery == nil || recoveryIsSaved else {
            errorMessage = "Your previous recording is still in memory. Retry or Save recording before starting another."
            phase = .failed
            return
        }
        dictationSession = DictationSession(configuration: DictationConfiguration(self))
        cancelEarlyTranscription()
        earlyTranscriptionWait = 0
        finishRequestedAt = nil
        sessionIsPrompt = prompt
        promptListener.stop()
        promptSession?.cancel()
        promptSession = prompt && !isPreview ? PromptModeSession() : nil
        promptSession?.onStatus = { [weak self] in self?.promptStatus = $0 }
        if prompt && !isPreview { promptCaptureFeedback.reset(); promptCaptureFeedback.prepare() }
        dictionaryLearner.stop()
        microphone.cancel()
        hideTask?.cancel()
        work?.cancel()
        insertionTarget?.stopTracking()
        recentRecordingID = UUID()
        insertionTarget = isPreview ? nil : TextInsertion.captureTarget(previousApp: focusHistory.previousApp)
        finishTargetTask?.cancel()
        let capturedTarget = insertionTarget
        if !isPreview { bottomWindowTracker.begin(app: capturedTarget?.app, lockToStart: false) }
        finishTargetTask = nil
        pasteHint = nil
        isWaitingToPaste = false
        phase = .preparing
        errorMessage = nil
        notice = nil
        copied = false
        elapsed = 0
        overlayVisible = true
        let session = dictationSession!
        let configuration = session.configuration
        work = Task { [self] in
            let allowed = await requestMicrophoneAccess()
            guard !Task.isCancelled else { return }
            guard allowed else {
                fail(ServiceError.message("Microphone access is off. Allow S2T in System Settings → Privacy & Security → Microphone."))
                return
            }
            do {
                if promptSession != nil {
                    promptSession?.beginRecording()
                    try promptListener.start(microphone: microphone, locale: promptLanguage, onReference: { [weak self] phrase, seconds in
                        guard let self, self.phase == .recording else { return }
                        self.promptStatus = "Reference heard. Recording context for final matching…"
                    }, onFailure: { [weak self] in self?.promptSession?.recordWarning($0); self?.promptStatus = $0; self?.notice = $0 })
                }
                await earlyCancellation?.value
                try Task.checkCancellation()
                let early: EarlyCreditTranscription?
                if configuration.earlyTranscriptionEnabled, let connection = configuration.speechConnection {
                    early = EarlyCreditTranscription(provider: configuration.speechProvider, model: configuration.speechModel,
                        connection: connection, api: creditsAPI, store: recoveryStore, mode: configuration.mode)
                } else { early = nil }
                earlyTranscription = early
                try await microphone.start(deviceUID: configuration.microphoneUID, liveSpeech: promptSession != nil, streamingAudio: early != nil)
                guard !Task.isCancelled else { return }
                if let early { await early.start(microphone: microphone) }
                startedAt = Date()
                phase = .recording
                if promptSession != nil {
                    promptStatus = "⌘ Click to capture · ⌘ Drag to select an area"
                    promptCaptureFeedback.reset()
                    // The event-tap thread draws the live rectangle; the main thread only clears it.
                    promptRegionCapture.onDrag = { [weak self] rect in if rect == nil { self?.promptCaptureFeedback.selection(nil) } }
                    promptRegionCapture.onSelect = { [weak self] rect in self?.captureSelectedRegion(rect) }
                    promptRegionCapture.onClick = { [weak self] point in
                        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
                        self?.captureSelectedRegion(PromptCaptureGeometry.region(pointer: point, display: screen.frame))
                    }
                    promptRegionCapture.onPress = { [weak self] point in
                        self?.promptCaptureFeedback.beginSelection(at: point)
                        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
                        self?.promptSession?.prefetchClick(PromptCaptureGeometry.region(pointer: point, display: screen.frame))
                    }
                    promptSession?.onManualPreview = { [weak self] thumbnail, region in
                        guard let self, let session = self.promptSession else { return }
                        self.promptCaptureFeedback.show(PromptScreenshot(png: Data(), pointer: .zero, region: region, thumbnail: thumbnail),
                            count: session.manualCaptures.count + 1)
                    }
                    promptSession?.onManualCapture = { [weak self] screenshot, previewed in
                        guard let self, let session = self.promptSession else { return }
                        if !previewed { self.promptCaptureFeedback.show(screenshot, count: session.manualCaptures.count) }
                        self.promptStatus = "\(session.manualCaptures.count) screenshots captured for this prompt."
                    }
                    promptSession?.onCaptureTiming = { [weak self] timing in
                        self?.preferences.set(timing, forKey: "lastPromptCaptureTiming")
                    }
                    promptSession?.onSpokenCaptures = { [weak self] captures in
                        guard let self else { return }
                        let manualCount = self.promptSession?.manualCaptures.count ?? 0
                        for (offset, capture) in captures.suffix(3).enumerated() {
                            let region = capture.screenshot.region
                            guard let screen = NSScreen.screens.first(where: { screen in
                                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
                                return CGDisplayBounds(id).intersects(region)
                            }), let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
                            let cocoa = PromptScreenshot.cocoaRect(fromQuartz: region, screenFrame: screen.frame, quartzBounds: CGDisplayBounds(id))
                            self.promptCaptureFeedback.show(capture.screenshot.relocated(to: cocoa),
                                count: manualCount + max(0, captures.count - 3) + offset + 1)
                        }
                    }
                    promptRegionCapture.start()
                }
                connectionTask?.cancel()
                let creditWarm = speechUsesCredits || cleanupUsesCredits ? creditConnection : nil
                let speechWarm = !speechUsesCredits && transcriptionProvider == .assemblyAI && transcriptionMode == .fast
                if creditWarm != nil || speechWarm {
                    let creditsAPI = self.creditsAPI, api = self.api
                    connectionTask = Task {
                        await withTaskGroup(of: Void.self) { group in
                            if let creditWarm { group.addTask { await creditsAPI.warmConnection(creditWarm) } }
                            if speechWarm { group.addTask { await api.warmTranscriptionConnection() } }
                        }
                    }
                }
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.phase == .recording else { return }
                        self.elapsed = Date().timeIntervalSince(self.startedAt)
                        if self.elapsed >= 600 { self.stopRecording() }
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                meterTimer = timer
            } catch {
                guard !Task.isCancelled else { return }
                promptListener.stop(); promptSession?.cancel(); promptSession = nil; fail(error)
            }
        }
    }

    func stopRecording() {
        guard phase == .recording else { return }
        finishRequestedAt = ProcessInfo.processInfo.systemUptime
        if !isPreview { rememberFinishDestination() }
        promptRegionCapture.stop()
        if let promptSession {
            promptSession.stopListening()
        } else { promptListener.stop() }
        meterTimer?.invalidate(); meterTimer = nil
        elapsed = Date().timeIntervalSince(startedAt)
        phase = .transcribing
        guard let session = dictationSession else { return }
        work = Task {
            guard !Task.isCancelled else { return }
            let early = earlyTranscription
            await early?.stop()
            let captured = await session.finishCapture(microphone)
            guard !Task.isCancelled, dictationSession === session else { return }
            promptSession?.setAudioOrigin(microphone.audioStartTime)
            promptSession?.stopListening(words: Task { await promptListener.finish() })
            guard elapsed >= 0.3, captured.count > 44 else {
                promptSession?.cancel()
                finishTargetTask?.cancel()
                insertionTarget?.stopTracking()
                if let early { await early.cancel(); earlyTranscription = nil; microphone.releaseStreamingAudio() }
                phase = .idle
                overlayVisible = false
                return
            }
            if let early {
                let waitStarted = ProcessInfo.processInfo.systemUptime
                do {
                    let prepared = try await early.finish(audio: captured)
                    earlyTranscriptionWait = ProcessInfo.processInfo.systemUptime - waitStarted
                    try Task.checkCancellation()
                    microphone.releaseStreamingAudio()
                    processRecording(captured, prepared: prepared)
                } catch {
                    guard !Task.isCancelled else { return }
                    let prepared = await early.snapshot(audio: captured)
                    microphone.releaseStreamingAudio()
                    processRecording(captured, prepared: prepared)
                }
            } else { processRecording(captured) }
        }
    }

    func handlePromptPointer(type: CGEventType, event: CGEvent) -> Bool {
        if TextInsertion.menuIsOpen { return false }
        return promptRegionCapture.receive(type: type, event: event)
    }

    func rememberFinishDestination() {
        finishTargetTask?.cancel()
        insertionTarget?.stopTracking()
        let target = TextInsertion.captureTarget(previousApp: focusHistory.previousApp)
        insertionTarget = target
        let task = Task { await TextInsertion.rememberFinish(target) }
        finishTargetTask = task
        bottomWindowTracker.pin(to: task)
    }

    func captureSelectedRegion(_ rect: CGRect) {
        guard let promptSession, phase == .recording else { promptCaptureFeedback.selection(nil); return }
        promptStatus = "Capturing selected area…"
        promptSession.captureArea(rect)
        // Turns the drag outline straight into the capture flash, without hiding its window in between.
        promptCaptureFeedback.acknowledge(rect)
    }

    var canCancel: Bool {
        !isPreservingRecording && (isWaitingToPaste || phase.busy || [.recording, .preview, .monitoring, .preparing].contains(phase))
    }

    func cancelEarlyTranscription() {
        guard let early = earlyTranscription else { return }
        earlyTranscription = nil
        let previous = earlyCancellation
        earlyCancellation = Task {
            await previous?.value
            await early.cancel()
        }
    }

    func cancel() {
        guard !isPreservingRecording else { return }
        let session = dictationSession
        let processing = phase.processingAudio || isWaitingToPaste
        stopActivity()
        if processing, let session, session.recovery != nil { Task { await finalizeSession(.cancelled, session: session) } }
    }

    func preserveForInterruption() async -> Bool {
        if let interruptionTask { return await interruptionTask.value }
        let task = Task { await self.preserveInterruptedSession() }
        interruptionTask = task
        let saved = await task.value
        interruptionTask = nil
        return saved
    }

    func preserveInterruptedSession() async -> Bool {
        guard let session = dictationSession else { stopActivity(); return true }
        isPreservingRecording = true
        defer { isPreservingRecording = false }
        let capturing = phase == .recording || phase == .preparing || phase == .transcribing && session.recovery == nil
        let early = earlyTranscription
        earlyTranscription = nil
        work?.cancel()
        meterTimer?.invalidate(); meterTimer = nil
        phase = .processing
        if capturing {
            let captured = await session.finishCapture(microphone)
            if captured.count > 44 {
                do {
                    if let early { session.recovery = try await early.interrupt(audio: captured) }
                    else { session.recovery = RecordingRecovery(audio: captured, requestID: session.requestID, mode: session.configuration.mode) }
                    session.requestID = session.recovery!.requestID
                    rawTranscript = session.recovery?.transcript ?? ""
                } catch {
                    session.recovery = await early?.snapshot(audio: captured) ?? RecordingRecovery(audio: captured, requestID: session.requestID, mode: session.configuration.mode)
                    session.requestID = session.recovery!.requestID
                    rawTranscript = session.recovery?.transcript ?? ""
                }
            } else { await early?.cancel() }
        }
        stopActivity()
        let saved = await finalizeSession(.interrupted, session: session)
        if saved {
            if session.recovery != nil { notice = "Your interrupted recording is saved. Open Recording recovery to retry it." }
            phase = .idle
        } else { phase = .failed }
        return saved
    }

    func stopActivity() {
        finishRequestedAt = nil
        cancelEarlyTranscription()
        localModels.cancelInference()
        promptListener.stop()
        promptSession?.cancel()
        promptSession = nil
        promptRegionCapture.stop()
        promptCaptureFeedback.hide()
        dictionaryLearner.stop()
        isWaitingToPaste = false
        finishTargetTask?.cancel(); finishTargetTask = nil
        insertionTarget?.stopTracking(); insertionTarget = nil
        work?.cancel(); hideTask?.cancel(); connectionTask?.cancel()
        meterTimer?.invalidate(); meterTimer = nil
        microphone.cancel()
        phase = .idle
        overlayVisible = false
    }

}
