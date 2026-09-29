import AppKit
import Foundation
import S2TCore

extension AppState {
    func runPipeline() {
        guard let session = dictationSession else { return }
        let configuration = session.configuration
        work?.cancel()
        hideTask?.cancel()
        errorMessage = nil
        notice = nil
        overlayVisible = true
        processingFailureModel = nil
        jevSummary = ""
        let jevMode = configuration.jevMode
        let selectedJevRoute = configuration.jevRoute
        let jevCreditConnection = configuration.jevConnection
        let jevKey = configuration.jevKey
        let clipboardHistory = configuration.clipboard
        let missingCreditKey = configuration.missingCreditKey
        let early = earlyTranscription
        earlyTranscription = nil
        let earlyWait = early == nil ? 0 : earlyTranscriptionWait
        let savedSpeech = session.recovery?.creditSpeechRequest
        let speechConnection = savedSpeech == nil ? early?.connection ?? configuration.speechConnection : configuration.savedCreditConnection
        let cleanupConnection = configuration.cleanupConnection
        let paidRequestID = session.requestID
        let retryingTranscript = !rawTranscript.isEmpty
        let speechProvider = savedSpeech?.provider ?? early?.provider ?? configuration.speechProvider
        let speechKey = speechConnection?.key ?? configuration.speechKey
        let speechModel = savedSpeech?.model ?? early?.model ?? configuration.speechModel
        let speechMode: TranscriptionMode = savedSpeech == nil ? configuration.speechMode : .fast
        var speechURL = configuration.speechURL
        var cleanupURL = configuration.cleanupURL
        let provider = configuration.cleanupProvider
        let processingAPIKey = configuration.cleanupKey
        let selectedMode = configuration.mode
        let model = configuration.cleanupModel
        let endpoint = configuration.cleanupEndpoint
        let visualSession = promptSession
        let codexPath = configuration.codexPath
        let cleanupRouterOptions = configuration.cleanupRouterOptions
        let cleanupOptions = configuration.cleanupOptions
        let trackedTarget = insertionTarget
        let pipelineRequestedAt = ProcessInfo.processInfo.systemUptime
        let deliveryStartedAt = finishRequestedAt ?? pipelineRequestedAt
        finishRequestedAt = nil
        phase = rawTranscript.isEmpty ? .transcribing : .processing
        work = Task {
            var durations: [String: Double] = ["stopToPipeline": pipelineRequestedAt - deliveryStartedAt,
                "earlyTranscriptionWait": earlyWait,
                "cachedSpeechParts": Double(recovery?.completedParts.count ?? 0)]
            var timingOutcome = "incomplete"
            var copiedValuesForHistory: [String] = []
            defer {
                durations["stopToEnd"] = ProcessInfo.processInfo.systemUptime - deliveryStartedAt
                DictationTiming.record(durations, outcome: Task.isCancelled ? "cancelled" : timingOutcome, defaults: preferences)
            }
            var promptDelivery: PromptDeliveryLease?
            var pendingAttachment: PromptImageInsertion.Result?
            defer { promptDelivery?.restore() }
            defer { trackedTarget?.stopTracking(); if speechConnection != nil || cleanupConnection != nil || jevCreditConnection != nil { Task { await self.refreshCredits() } } }
            do {
                try await saveRecovery()
                try Task.checkCancellation()
                if missingCreditKey { throw ServiceError.message("Add your S2T key under API keys before retrying.") }
                if cleanupConnection != nil, recovery?.creditCleanupDraft != nil, recovery?.creditCleanupRequest == nil {
                    throw ServiceError.message("This saved cleanup predates exact request recovery. S2T cannot safely repeat its paid request. Copy the original transcript or save the recording. Select Verbatim to insert the original words, or start a new dictation for a new cleanup request.")
                }
                if rawTranscript.isEmpty, savedSpeech != nil, speechConnection == nil {
                    throw ServiceError.message("Reconnect the S2T key used for this saved speech request before retrying. Its original paid request is preserved.")
                }
                if rawTranscript.isEmpty, let recording {
                    if speechProvider == .local, speechURL == "http://127.0.0.1/s2t-managed", !speechModel.hasPrefix("apple-speech-") {
                        speechURL = try await localModels.url(for: speechModel, path: "/audio/transcriptions")
                    }
                    do {
                        // Cloud providers get 16 kHz PCM, a third of the 48 kHz capture. Local engines read the original.
                        let cloudSpeech = speechConnection != nil || speechProvider != .local
                        let uploadRate = speechConnection == nil ? WaveAudio.speechUploadRate : recovery?.speechUploadRate
                        let uploadAudio = cloudSpeech && uploadRate == WaveAudio.speechUploadRate && recovery?.speechSegmentEnds == nil
                            ? await Task.detached(priority: .userInitiated) { WaveAudio.speechUpload(recording) }.value : recording
                        try Task.checkCancellation()
                        let transcriptionStarted = ProcessInfo.processInfo.systemUptime
                        defer {
                            if durations["transcription"] == nil { durations["transcription"] = ProcessInfo.processInfo.systemUptime - transcriptionStarted }
                            for (name, value) in creditsAPI.timings.take("transcription") ?? [:] { durations["speech." + name] = value }
                        }
                        durations["preTranscription"] = transcriptionStarted - pipelineRequestedAt
                        durations["uploadBytes"] = recovery?.speechSegmentEnds == nil ? Double(uploadAudio.count) : nil
                        preferences.removeObject(forKey: "lastStreamingTiming")
                        let transcription: TimedTranscription
                        if let paidConnection = speechConnection {
                            guard speechMode == .fast else { throw ServiceError.message("S2T credits support Fast recognition. Select Fast under Models.") }
                            guard savedSpeech != nil || recovery?.creditSpeechSnapshotVersion == 1 else {
                                throw ServiceError.message("This saved recording predates exact paid speech recovery. S2T cannot safely repeat its paid request. Save the recording and use a local or personal-key provider, or start a new dictation explicitly.")
                            }
                            let request = try (savedSpeech ?? CreditSpeechRequest(provider: speechProvider, model: speechModel,
                                connection: paidConnection, requestID: paidRequestID + "-speech", segmented: recovery?.speechSegmentEnds != nil))
                                .appending(audio: uploadAudio, segmentEnds: recovery?.speechSegmentEnds, complete: true)
                            recovery?.creditSpeechRequest = request
                            try await saveRecovery()
                            try Task.checkCancellation()
                            transcription = try await creditsAPI.transcribe(request, connection: paidConnection,
                                completedParts: recovery?.completedParts ?? [:], onPartCompleted: { [weak self] key, text in
                                    try await self?.completedSpeechPart(key, text: text, session: session)
                                })
                        } else if speechProvider == .local, speechURL == "http://127.0.0.1/s2t-managed", speechModel.hasPrefix("apple-speech-") {
                            guard #available(macOS 26, *) else { throw ServiceError.message("Apple Speech requires macOS 26 or newer.") }
                            transcription = try await NativeSpeechModels.transcribe(audio: recording, modelID: speechModel)
                        } else {
                            transcription = try await api.transcribeDetailed(audio: uploadAudio, apiKey: speechKey, mode: speechMode, provider: speechProvider, model: speechModel, localURL: speechURL, includeTimestamps: visualSession != nil)
                        }
                        try Task.checkCancellation()
                        preferences.set(ProcessInfo.processInfo.systemUptime - transcriptionStarted, forKey: "lastTranscriptionSeconds")
                        durations["transcription"] = ProcessInfo.processInfo.systemUptime - transcriptionStarted
                        for (name, value) in creditsAPI.timings.take("transcription") ?? [:] { durations["speech." + name] = value }
                        recordKeySuccess(account: speechConnection == nil ? speechProvider.rawValue : "s2t", using: speechKey)
                        rawTranscript = transcription.text
                        output = transcription.text
                        try await saveRecovery()
                        visualSession?.setTranscriptionWords(transcription.words)
                    } catch {
                        try Task.checkCancellation()
                        guard visualSession?.hasManualCaptures == true else { throw error }
                        if !recordKeyFailure(error, using: speechKey) {
                            errorMessage = "Speech transcription failed. Your selected screenshots are preserved. " + error.localizedDescription
                        }
                    }
                }
                let referenceText = visualSession.map { PromptReferenceText(transcript: rawTranscript, session: $0.id) }
                let editingTranscript = referenceText?.text ?? rawTranscript
                let visualWork: Task<PromptModeSession.Result, Error>? = visualSession.map { session in
                    let transcript = rawTranscript
                    let directory = promptStorageDirectory.appendingPathComponent(session.id)
                    return Task {
                        let started = ProcessInfo.processInfo.systemUptime
                        let result = try await session.saveReferences(transcript: transcript, directory: directory)
                        try Task.checkCancellation()
                        preferences.set(ProcessInfo.processInfo.systemUptime - started, forKey: "lastPromptAnalysisSeconds")
                        return result
                    }
                }
                defer { visualWork?.cancel() }
                if selectedMode != .verbatim && !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    phase = .processing
                    do {
                        routeDescription = "Selected model"
                        let processingStarted = ProcessInfo.processInfo.systemUptime
                        defer {
                            durations["cleanup"] = ProcessInfo.processInfo.systemUptime - processingStarted
                            for (name, value) in creditsAPI.timings.take("cleanup") ?? [:] { durations["cleanup." + name] = value }
                        }
                        let context = recovery?.creditCleanupRequest?.clipboardContext ?? (configuration.clipboardEnabled ? clipboardHistory.context(for: rawTranscript) : ClipboardContext())
                        copiedValuesForHistory = context.items.map(\.value)
                        let (prompt, dictionary, instructions) = try configuration.editingPreferences.get()
                        var cleanupInput = editingTranscript
                        var jevResult: JevCleanupResult?
                        let savedCleanup = recovery?.creditCleanupDraft
                        let replayCleanup = cleanupConnection != nil && savedCleanup?.requestID == paidRequestID + "-cleanup" && savedCleanup?.original == rawTranscript
                        if replayCleanup, let savedCleanup {
                            cleanupInput = savedCleanup.text
                            if jevMode != .off { jevSummary = "Reusing the saved cleanup input for this S2T request." }
                        } else if jevMode != .off && !(cleanupConnection != nil && retryingTranscript) {
                            let canFinish = jevMode.permitsFastPath(writingMode: selectedMode, instructions: prompt,
                                                                  clipboardContextEnabled: configuration.clipboardEnabled, hasVisualReferences: visualSession != nil)
                            let source = editingTranscript
                            let plan = await Task.detached(priority: .userInitiated) {
                                JevCleanupPlan(text: source, dictionary: dictionary, allowFastPath: canFinish,
                                               editingPreferences: prompt + "\n" + selectedMode.formattingInstruction)
                            }.value
                            try Task.checkCancellation()
                            if let plan {
                                let started = ProcessInfo.processInfo.systemUptime
                                do {
                                    let result: JevCleanupResult
                                    if selectedJevRoute == .s2t {
                                        guard let connection = jevCreditConnection else { throw ServiceError.message("Add your S2T key in Settings → API keys to use Jev credits.") }
                                        result = try await creditsAPI.cleanWithJev(plan, connection: connection, requestID: paidRequestID)
                                    } else {
                                        result = try await api.cleanWithJev(plan, apiKey: jevKey, route: selectedJevRoute)
                                    }
                                    try Task.checkCancellation()
                                    cleanupInput = result.text
                                    jevResult = result
                                    recordKeySuccess(account: selectedJevRoute == .s2t ? "s2t" : selectedJevRoute.account.rawValue, using: jevKey)
                                    let milliseconds = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                                    jevSummary = "Jev: \(result.editCount) edits · \(milliseconds) ms · " + (result.canSkipRewrite || result.text.isEmpty ? "Normal cleanup skipped" : "Normal cleanup retained")
                                } catch {
                                    try Task.checkCancellation()
                                    _ = recordKeyFailure(error, using: jevKey)
                                    jevSummary = "Jev unavailable. Normal cleanup used. " + error.localizedDescription
                                }
                            } else { jevSummary = "Jev skipped. No eligible edits or transcript exceeds its limits." }
                        }
                        let processed: ProcessedText
                        if let result = jevResult, result.canSkipRewrite || result.text.isEmpty {
                            processed = ProcessedText(text: result.text, model: result.model, host: selectedJevRoute == .s2t ? "S2T · OpenRouter" : selectedJevRoute.account.title)
                            routeDescription = "Jev cleanup"
                        } else {
                            guard cleanupConnection != nil || !provider.requiresAPIKey || !processingAPIKey.isEmpty else { throw ServiceError.message("Add your \(provider.title) API key in Settings, then retry processing.") }
                            if provider == .local, cleanupURL == "http://127.0.0.1/s2t-managed" {
                                cleanupURL = try await localModels.url(for: model, path: "/chat/completions")
                            }
                            if let paidConnection = cleanupConnection {
                                guard provider == .openRouter || provider == .xai else { throw ServiceError.message("This cleanup provider is not supported with S2T.") }
                                let request = try recovery?.creditCleanupRequest ?? CreditCleanupRequest(text: cleanupInput,
                                    mode: selectedMode, model: model, endpoint: endpoint, connection: paidConnection,
                                    clipboardContext: context, instructions: instructions, options: cleanupRouterOptions,
                                    requestID: paidRequestID + "-cleanup", provider: provider)
                                recovery?.creditCleanupRequest = request
                                recovery?.creditCleanupDraft = CreditCleanupDraft(requestID: request.requestID, original: rawTranscript, text: cleanupInput)
                                try await saveRecovery()
                                try Task.checkCancellation()
                                processed = try await creditsAPI.process(request, connection: paidConnection)
                            } else {
                                processed = try await api.process(text: cleanupInput, mode: selectedMode, model: model, apiKey: processingAPIKey, provider: provider, endpoint: endpoint, clipboardContext: context, instructions: instructions, localURL: cleanupURL, codexExecutable: codexPath, codexOptions: cleanupOptions, routerOptions: cleanupRouterOptions)
                            }
                            recordKeySuccess(account: cleanupConnection == nil ? provider.rawValue : "s2t", using: processingAPIKey)
                        }
                        try Task.checkCancellation()
                        preferences.set(ProcessInfo.processInfo.systemUptime - processingStarted, forKey: "lastProcessingSeconds")
                        output = processed.text
                        modelUsed = processed.model + (processed.host.map { " · " + $0 } ?? "")
                        if output.isEmpty && visualSession == nil {
                            isWaitingToPaste = false
                            copied = false
                            pasteHint = nil
                            if await finalizeSession(.empty, session: session) { notice = "Nothing to insert." }
                            phase = .idle
                            hideOverlay(after: 0)
                            return
                        }
                    } catch {
                        try Task.checkCancellation()
                        processingFailureModel = model
                        if error is CreditRequestRejected { creditRequestID = UUID().uuidString; recovery?.creditCleanupRequest = nil; recovery?.creditCleanupDraft = nil }
                        output = editingTranscript
                        modelUsed = speechProvider.title
                        routeDescription = "Original transcription"
                        if !recordKeyFailure(error, using: processingAPIKey) {
                            errorMessage = "\(provider.title) processing failed. Using your original words. \(error.localizedDescription)"
                        }
                    }
                } else {
                    output = editingTranscript
                    modelUsed = speechProvider.title
                    routeDescription = "Original transcription"
                }
                try Task.checkCancellation()
                if let referenceText, let visualWork {
                    phase = .processing
                    promptStatus = "Preparing screenshots…"
                    let visualWaitStarted = ProcessInfo.processInfo.systemUptime
                    let visual = try await withTaskCancellationHandler { try await visualWork.value } onCancel: { visualWork.cancel() }
                    durations["promptWait"] = ProcessInfo.processInfo.systemUptime - visualWaitStarted
                    try Task.checkCancellation()
                    promptImages = visual.images
                    output = referenceText.resolve(output, references: visual.references)
                    promptCaptureFeedback.collapse()
                    promptStatus = visual.images.isEmpty ? "No reference screenshots available." : "\(visual.images.count) screenshots ready to paste with this prompt."
                    if !visual.warnings.isEmpty { errorMessage = ([errorMessage].compactMap { $0 } + visual.warnings).joined(separator: "\n") }
                    if !visual.images.isEmpty { notice = promptStatus }
                } else if recovery?.creditCleanupDraft?.text.contains("__S2T_SCREENSHOT_") == true {
                    output = PromptReferenceText.removingMarkers(from: output)
                }
                try Task.checkCancellation()
                recentRecordings.record(id: recovery?.id ?? recentRecordingID, text: output, appName: insertionTarget?.app.localizedName, bundleID: insertionTarget?.app.bundleIdentifier, copiedValues: copiedValuesForHistory)
                let insertionStarted = ProcessInfo.processInfo.systemUptime
                if TextInsertion.menuIsOpen {
                    isWaitingToPaste = true
                    phase = .complete
                    notice = "Close the menu to deliver to the field selected when dictation ended."
                    hideOverlay(after: 0.35)
                }
                let destinationStarted = ProcessInfo.processInfo.systemUptime
                if let finishTargetTask { insertionTarget = await finishTargetTask.value }
                durations["destinationWait"] = ProcessInfo.processInfo.systemUptime - destinationStarted
                try Task.checkCancellation()
                let target = insertionTarget
                target?.waitsForAttachmentClipboard = !promptImages.isEmpty
                let menuStarted = ProcessInfo.processInfo.systemUptime
                while TextInsertion.menuIsOpen { try await Task.sleep(nanoseconds: 50_000_000) }
                durations["menuWait"] = ProcessInfo.processInfo.systemUptime - menuStarted
                try Task.checkCancellation()
                let focusStarted = ProcessInfo.processInfo.systemUptime
                if let destination = target?.promptDestination {
                    promptDelivery = try await PromptDeliveryLease.prepare(destination)
                }
                durations["focusRestoration"] = ProcessInfo.processInfo.systemUptime - focusStarted
                let missingDestination = !isPreview && (target?.promptDestination == nil || promptDelivery == nil)
                let pasteStarted = ProcessInfo.processInfo.systemUptime
                let outcome: TextInsertion.Outcome = missingDestination ? .destinationUnavailable : try await insertText(output, target, nil)
                durations["paste"] = ProcessInfo.processInfo.systemUptime - pasteStarted
                timingOutcome = outcome.rawValue
                try Task.checkCancellation()
                let imageRecipient = target?.promptDestination != nil ? target?.app.processIdentifier
                    : isPreview ? nil : NSWorkspace.shared.frontmostApplication?.processIdentifier
                if outcome == .textSent, !isPreview {
                    startDictionaryLearning(output: output, recipient: imageRecipient, expectedField: target?.field,
                        insertionSelection: target?.selection, insertionBaseline: target?.dictionaryBaseline)
                }
                durations["insertion"] = ProcessInfo.processInfo.systemUptime - insertionStarted
                durations["stopToInsertionReturn"] = ProcessInfo.processInfo.systemUptime - deliveryStartedAt
                durations["words"] = Double(output.split(whereSeparator: { $0.isWhitespace }).count)
                isWaitingToPaste = false
                preferences.set(outcome.rawValue, forKey: "lastInsertionOutcome")
                preferences.set(Date(), forKey: "lastDeliveryAt")
                copied = false
                if outcome == .textSent {
                    _ = await finalizeSession(.delivered, session: session)
                    if visualSession != nil, !promptImages.isEmpty {
                        let attachmentStarted = ProcessInfo.processInfo.systemUptime
                        promptStatus = "Attaching screenshots…"
                        // Fly the screenshots into the field while they are pasted, without delaying the paste.
                        if let field = target?.field {
                            Task { [weak self] in
                                guard let frame = await Task.detached(priority: .userInitiated, operation: { PromptCaptureDrop.frame(of: field) }).value,
                                      let self, !Task.isCancelled else { return }
                                self.promptCaptureFeedback.deliver(into: frame)
                            }
                        }
                        pendingAttachment = try await insertPromptImages(promptImages, imageRecipient, outputPasteboard, false, target)
                        let attachmentSeconds = ProcessInfo.processInfo.systemUptime - attachmentStarted
                        durations["attachments"] = attachmentSeconds
                        preferences.set(attachmentSeconds, forKey: "lastPromptAttachmentSeconds")
                        try Task.checkCancellation()
                    } else {
                        copyText(output)
                    }
                }
                if outcome != .textSent { _ = await finalizeSession(.undelivered, session: session) }
                pasteHint = outcome.hint
                if notice == "Close the menu to deliver to the field selected when dictation ended." { notice = nil }
                if let hint = outcome.hint { notice = hint }
                try Task.checkCancellation()
                phase = .complete
                durations["stopToComplete"] = ProcessInfo.processInfo.systemUptime - deliveryStartedAt
                preferences.set(durations, forKey: "lastDictationTiming")
                preferences.set(Date().timeIntervalSince1970, forKey: "lastDictationTimingAt")
                if glowAppearance == .bezel || glowAppearance == .liquidGlass { overlayVisible = true }
                hideOverlay(after: pasteHint == nil ? (glowAppearance == .bezel || glowAppearance == .liquidGlass ? 0.85 : 0.35) : 5)
                // The recipient already has the screenshots. Confirming them reads its
                // Accessibility tree, so it runs after the overlay finishes.
                if var attachment = pendingAttachment {
                    if let confirm = attachment.confirm { attachment = try await confirm() }
                    try Task.checkCancellation()
                    durations["attachmentConfirmation"] = ProcessInfo.processInfo.systemUptime - attachment.completedAt
                    if attachment.confirmation == .confirmed {
                        promptStatus = "Screenshots attached."
                        promptCaptureFeedback.hide()
                    } else {
                        promptStatus = attachment.issue ?? "Screenshot paste sent but not confirmed. Images remain on the clipboard; prompt text is in Last dictation."
                        promptCaptureFeedback.hideSoon()
                    }
                    if pasteHint == nil { notice = promptStatus }
                    if attachment.canReleaseClipboard,
                       outputPasteboard.changeCount == attachment.clipboardChange { copyText(output) }
                }
            } catch is CancellationError { _ = await finalizeSession(.cancelled, session: session) }
            catch {
                guard !Task.isCancelled, dictationSession === session else { return }
                timingOutcome = "failed"
                if let rejection = error as? CreditRequestRejected {
                    if let id = rejection.requestID, let renewed = recovery?.creditSpeechRequest?.renewingRejectedPart(requestID: id) {
                        recovery?.creditSpeechRequest = renewed
                    } else { creditRequestID = UUID().uuidString; recovery?.creditCleanupRequest = nil; recovery?.creditCleanupDraft = nil }
                }
                _ = await finalizeSession(.failed, session: session)
                if recordKeyFailure(error, using: speechKey) {
                    phase = .failed
                    hideOverlay(after: 2)
                } else {
                    fail(error)
                }
            }
        }
    }

}
