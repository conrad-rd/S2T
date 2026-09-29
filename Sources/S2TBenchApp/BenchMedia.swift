import AppKit
import S2TCore
import S2TBenchCore

extension BenchStore {
    func runMedia() {
        let selected = mediaModels.filter { selectedMedia.contains($0.id) }
        guard !selected.isEmpty else { status = "Select an installed speech model."; return }
        guard selected.allSatisfy({ $0.memoryGB * 1_000_000_000 <= Double(ProcessInfo.processInfo.physicalMemory) }) else { status = "A selected model exceeds this Mac's memory budget."; return }
        let repeatCount = repetitions
        let fixtures = Bundle.main.resourceURL!.appendingPathComponent("BenchmarkFixtures")
        let workload: SpeechFixtureWorkload
        do { workload = try SpeechFixtureWorkload.load(from: fixtures) }
        catch { status = "Speech fixtures are invalid: " + error.localizedDescription; return }
        begin(settings: ["kind": "local speech", "models": selected.map(\.id).joined(separator: ","),
            "repetitions": String(repeatCount), "fixture_version": String(workload.manifest.schema),
            "fixture_manifest_sha256": workload.manifestSHA256, "fixture_audio_sha256": workload.audioSHA256]) { [self] in
            let endpoint = try await startWorker()
            for model in selected {
                for repetition in 0..<repeatCount {
                    try Task.checkCancellation()
                    status = "Testing \(model.name), repeat \(repetition + 1)…"
                    if model.category == "speech" {
                        for fixture in workload.manifest.cases {
                            try Task.checkCancellation()
                            let start = ProcessInfo.processInfo.systemUptime
                            var result = BenchResult(suite: "speech", name: "\(model.name) · \(fixture.name) · \(repetition + 1)", status: .passed, detail: "Synthetic speech. Word-error rate and both negations must pass.")
                            result.input = fixture.text
                            do {
                                let audio = try workload.data(for: fixture)
                                let meter = BenchTransport(maxTokens: 2048, timeout: 180)
                                let transcript = try await DictationAPI(transport: meter).transcribe(audio: audio, apiKey: "", provider: .local, model: model.id, localURL: endpoint + "/audio/transcriptions")
                                result.output = transcript
                                let wer = SpeechScore.wordErrorRate(expected: fixture.text, actual: transcript)
                                result.metrics["word_error_rate"] = wer
                                if wer > fixture.maxWER || SpeechScore.words(transcript).filter({ $0 == "not" }).count != 2 {
                                    result.status = .failed; result.detail = "Word-error limit \(fixture.maxWER) exceeded, or a protected negation was lost."
                                }
                            } catch { if Task.isCancelled { throw CancellationError() }; result.status = .failed; result.detail = error.localizedDescription }
                            let elapsed = ProcessInfo.processInfo.systemUptime - start
                            result.metrics["latency_ms"] = elapsed * 1000
                            result.metrics["real_time_factor"] = elapsed / fixture.seconds
                            result.metrics["audio_seconds"] = fixture.seconds
                            result.metrics["first_request"] = repetition == 0 && fixture.name == "clean" ? 1 : 0
                            if elapsed / fixture.seconds > 1 { result.status = .failed; result.detail += " Processing was slower than real time." }
                            append(result)
                        }
                    }
                }
            }
        }
    }

}
