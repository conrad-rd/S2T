import AppKit
import AVFoundation
import S2TCore

@MainActor enum NativeSpeechProbe {
    static func run() async throws {
        guard #available(macOS 26, *) else { throw ServiceError.message("Requires macOS 26.") }
        let samples: [Int16] = [-32768, -1234, 0, 1234, 32767]
        let pcm = try NativeSpeechModels.pcmBuffer(WaveAudio.encode(samples: samples, sampleRate: 44100))
        guard pcm.frameLength == 5, pcm.format.sampleRate == 44100,
              samples.enumerated().allSatisfy({ pcm.floatChannelData![0][$0.offset] == Float($0.element) / 32768 }) else {
            throw ServiceError.message("Native speech changed recorded samples.")
        }
        do {
            _ = try NativeSpeechModels.pcmBuffer(Data([0, 1]))
            throw ServiceError.message("Malformed audio was accepted.")
        } catch let error as ServiceError {
            guard error.localizedDescription.contains("unsupported recording") else { throw error }
        }
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        let state = AppState(preview: true)
        let model = LocalModel.appleSpeech(locale: "en-US")
        state.localModels = LocalModels(preview: true, nativePreviewModels: [model])
        let pane = LocalModelsPane(state: state)
        _ = pane.view
        pane.refresh()
        guard pane.rows.contains(model), pane.tableRow(for: model.id) == nil,
              pane.appleLanguagePicker.itemArray.contains(where: { $0.representedObject as? String == model.id }) else {
            throw ServiceError.message("Apple Speech languages must have a separate picker.")
        }
        pane.selectCategory(1)
        guard pane.appleLanguagePicker.isHiddenOrHasHiddenAncestor, pane.rows.allSatisfy({ $0.category == "text" }) else { throw ServiceError.message("Apple languages affected text models.") }
        pane.selectCategory(0)
        guard let index = pane.appleLanguagePicker.itemArray.firstIndex(where: { $0.representedObject as? String == model.id }) else { throw ServiceError.message("Native speech missing from language picker.") }
        pane.appleLanguagePicker.selectItem(at: index)
        pane.appleLanguagePicker.sendAction(pane.appleLanguagePicker.action, to: pane.appleLanguagePicker.target)
        guard pane.isShowingDetail, pane.detailModelID == model.id, pane.comparison?.rootView.models.contains(model) == true, pane.comparison?.rootView.nativeSelection == model,
              let actions = pane.detail.stack.arrangedSubviews.compactMap({ $0 as? NSStackView }).first,
              let install = actions.arrangedSubviews.compactMap({ $0 as? NSButton }).first(where: { $0.identifier?.rawValue == model.id && $0.title == "Download" }),
              install.isEnabled else { throw ServiceError.message("Native speech picker actions or chart exclusion failed.") }
        pane.comparison?.rootView.select(model.id)
        guard pane.detailModelID == model.id, pane.appleLanguagePicker.selectedItem?.representedObject as? String == model.id else {
            throw ServiceError.message("Apple chart selection did not select its language.")
        }
        install.performClick(nil)
        guard state.localModels.installing == nil else { throw ServiceError.message("Preview started a download.") }
        let catalog = await NativeSpeechModels.catalog()
        print("PASS: native speech PCM integrity, malformed input, hidden picker, native actions, unrated chart entry and preview isolation. Supported languages: \(catalog.models.count); installed: \(catalog.installed.sorted()).")
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--native-speech-fixture"), args.indices.contains(index + 1) {
            guard catalog.installed.contains(model.id) else { throw ServiceError.message("English US language assets are not installed. No automatic download in verification.") }
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[index + 1]))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw ServiceError.message("Invalid generated fixture.") }
            try file.read(into: buffer)
            let samples = (0..<Int(buffer.frameLength)).map { Int16(max(-32768, min(32767, Double(buffer.floatChannelData![0][$0]) * 32767))) }
            let audio = WaveAudio.encode(samples: samples, sampleRate: UInt32(file.processingFormat.sampleRate))
            let result = try await NativeSpeechModels.transcribe(audio: audio, modelID: model.id)
            guard result.text.lowercased().contains("blue square"), !result.words.isEmpty else { throw ServiceError.message("Generated speech recognition or timestamps failed: " + result.text) }
            let cancelled = Task { try await NativeSpeechModels.transcribe(audio: audio, modelID: model.id) }
            cancelled.cancel()
            do { _ = try await cancelled.value; throw ServiceError.message("Cancelled speech returned a result.") }
            catch is CancellationError { }
            print("PASS: real on-device Apple Speech recognized generated audio with timestamps; cancellation rejected results. No microphone, clipboard or screen access.")
        }
    }
}
