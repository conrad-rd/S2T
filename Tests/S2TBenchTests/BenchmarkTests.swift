import XCTest
@testable import S2TBenchCore

final class BenchmarkTests: XCTestCase {
    func testProcessDeadlineIncludesDescendantPipeDrain() async throws {
        let started = ProcessInfo.processInfo.systemUptime
        let output = try await BenchProcess.run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 2 & exit 0"], timeout: 0.1)
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        XCTAssertTrue(output.timedOut)
        XCTAssertLessThan(elapsed, 1)
    }

    func testProcessCapturesOutputAndFinalUnterminatedLine() async throws {
        let lines = LineCollector()
        let output = try await BenchProcess.run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'first\\nlast'"], timeout: 2) { await lines.append($0) }
        XCTAssertFalse(output.timedOut)
        XCTAssertEqual(output.code, 0)
        XCTAssertEqual(output.output, "first\nlast")
        let received = await lines.values
        XCTAssertEqual(received, ["first", "last"])
    }

    func testProcessCancellationStopsDescendantsAndPipeDrain() async throws {
        let started = ProcessInfo.processInfo.systemUptime
        let task = Task {
            try await BenchProcess.run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "sleep 2 & wait"], timeout: 10)
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled benchmark process returned normally")
        } catch is CancellationError {
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 1)
    }

    func testWordErrorRateCountsInsertionsDeletionsAndSubstitutions() {
        XCTAssertEqual(SpeechScore.wordErrorRate(expected: "Do not ship.", actual: "do not ship"), 0)
        XCTAssertEqual(SpeechScore.wordErrorRate(expected: "do not ship", actual: "do ship"), 1.0 / 3, accuracy: 0.00001)
        XCTAssertEqual(SpeechScore.wordErrorRate(expected: "one two", actual: "one three four"), 1)
    }
    func testTailStatisticsAndMissedDeadlines() {
        let stats = BenchStatistics([1, 2, 3, 4, 100])
        XCTAssertEqual(stats.median, 3)
        XCTAssertEqual(stats.p95, 100)
        XCTAssertEqual(stats.p99, 100)
        XCTAssertEqual(stats.maximum, 100)
        XCTAssertEqual(stats.over(16.667), 1)
        XCTAssertNil(BenchStatistics([]).median)
    }

    func testCorpusRejectsAnswersLeaksAndLostDetails() {
        let question = PromptCorpus.cases.first { $0.id == "question" }!
        XCTAssertTrue(question.failures(output: "What is two plus two?").isEmpty)
        XCTAssertFalse(question.failures(output: "4").isEmpty)
        let negation = PromptCorpus.cases.first { $0.id == "negation" }!
        XCTAssertFalse(negation.failures(output: "Deploy on Friday.").isEmpty)
        let exact = PromptCorpus.cases.first { $0.id == "exact-values" }!
        XCTAssertFalse(exact.failures(output: "Use the supplied API key.").isEmpty)
        XCTAssertFalse(question.failures(output: "Here is the edited text: What is two plus two?").isEmpty)
    }

    func testExactCasesPreserveWhitespaceUnlessNormalizationIsExplicit() {
        let expected = "if ready:\n    deploy()\nnotify()"
        let changed = "if ready:\n    deploy()\n    notify()"
        XCTAssertFalse(PromptCase(id: "bytes", name: "bytes", input: expected, exact: expected).failures(output: changed).isEmpty)
        XCTAssertTrue(PromptCase(id: "normalized", name: "normalized", input: expected, exact: expected,
            exactComparison: .normalizedWhitespace).failures(output: changed).isEmpty)
        XCTAssertFalse(PromptCase(id: "unicode-bytes", name: "unicode bytes", input: "e\u{301}", exact: "e\u{301}")
            .failures(output: "é").isEmpty)
    }

    func testPromptCorpusIdentityCoversEveryEvaluatedField() throws {
        let original = [PromptCase(id: "custom", name: "Custom", input: "input", exact: "output")]
        XCTAssertEqual(try PromptCorpus.identity(original), try PromptCorpus.identity(original))
        XCTAssertNotEqual(try PromptCorpus.identity(original),
            try PromptCorpus.identity([PromptCase(id: "custom", name: "Custom", input: "input", exact: "different")]))
        XCTAssertNotEqual(try PromptCorpus.identity(original),
            try PromptCorpus.identity([PromptCase(id: "custom", name: "Renamed", input: "input", exact: "output")]))
    }

    func testSpeechFixtureWorkloadVerifiesEveryAudioByte() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-speech-fixtures-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audio = Data("synthetic audio bytes".utf8)
        try audio.write(to: directory.appendingPathComponent("clean.wav"))
        let fixture = SpeechFixture(name: "clean", text: "Do not ship.", seconds: 1, file: "clean.wav",
            maxWER: 0.05, bytes: audio.count, sha256: BenchEndpoint.fingerprint(audio))
        let manifest = SpeechFixtureManifest(generator: ["voice": "Fixture Voice"], cases: [fixture])
        let encoded = try JSONEncoder().encode(manifest)
        try encoded.write(to: directory.appendingPathComponent("speech.json"))
        let workload = try SpeechFixtureWorkload.load(from: directory)
        XCTAssertEqual(try workload.data(for: fixture), audio)
        XCTAssertEqual(workload.manifestSHA256, BenchEndpoint.fingerprint(encoded))
        XCTAssertEqual(workload.manifest.generator["voice"], "Fixture Voice")

        try Data("changed".utf8).write(to: directory.appendingPathComponent("clean.wav"))
        XCTAssertThrowsError(try SpeechFixtureWorkload.load(from: directory))
    }

    func testSpeechFixtureWorkloadRejectsPathsOutsideFixtureDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-speech-path-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = SpeechFixture(name: "escape", text: "text", seconds: 1, file: "../escape.wav",
            maxWER: 0.1, bytes: 1, sha256: String(repeating: "0", count: 64))
        try JSONEncoder().encode(SpeechFixtureManifest(generator: [:], cases: [fixture]))
            .write(to: directory.appendingPathComponent("speech.json"))
        XCTAssertThrowsError(try SpeechFixtureWorkload.load(from: directory))
    }

    func testHistoryKeepsNewestHundredValidReportsByReportDate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-bench-history-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for index in 0..<120 {
            var report = BenchReport(results: [], settings: ["index": String(index)])
            report.created = Date(timeIntervalSince1970: Double(index))
            try report.encoded(includeText: false).write(to: directory.appendingPathComponent(String(format: "%03d.json", 119 - index)))
        }
        try Data("invalid".utf8).write(to: directory.appendingPathComponent("newest-looking.json"))
        let loaded = BenchReportHistory.load(from: directory)
        XCTAssertEqual(loaded.count, 100)
        XCTAssertEqual(loaded.first?.settings["index"], "119")
        XCTAssertEqual(loaded.last?.settings["index"], "20")
    }

    func testSeedIsReproducibleAndChangesOrdering() {
        XCTAssertEqual(BenchRandom.shuffled(Array(0..<100), seed: 42), BenchRandom.shuffled(Array(0..<100), seed: 42))
        XCTAssertNotEqual(BenchRandom.shuffled(Array(0..<100), seed: 42), BenchRandom.shuffled(Array(0..<100), seed: 43))
    }

    func testRejectsCredentialBearingOrRemoteLocalAddresses() throws {
        for address in ["https://example.com/v1/chat/completions", "http://127.0.0.1.evil.test/v1", "http://user:key@localhost/v1", "file:///tmp/a", "http://localhost/v1?key=secret"] {
            XCTAssertThrowsError(try BenchEndpoint.local(address))
        }
        XCTAssertEqual(try BenchEndpoint.local("http://127.0.0.1:11434/v1/chat/completions").host, "127.0.0.1")
    }

    func testReportsNeverPersistCredentialsOrTextByDefault() throws {
        var result = BenchResult(suite: "prompts", name: "case", status: .failed, detail: "Failure", metrics: [:])
        result.input = "private input"; result.output = "private output"
        let report = BenchReport(results: [result], settings: ["seed": "42"])
        let data = try report.encoded(includeText: false)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("private input"))
        XCTAssertFalse(text.contains("private output"))
        XCTAssertTrue(String(decoding: try report.encoded(includeText: true), as: UTF8.self).contains("private output"))
    }

    func testEveryCaseHasAnIndependentAssertionAndStableID() {
        XCTAssertGreaterThanOrEqual(PromptCorpus.cases.count, 20)
        XCTAssertEqual(Set(PromptCorpus.cases.map(\.id)).count, PromptCorpus.cases.count)
        for test in PromptCorpus.cases {
            XCTAssertTrue(test.exact != nil || !test.required.isEmpty)
            XCTAssertEqual(test.failures(output: "").isEmpty, test.exact == "")
        }
    }

    func testCorrectionCasesRejectAbandonedWordsAndPreserveMeaning() {
        let replacement = PromptCorpus.cases.first { $0.id == "hesitation-correction" }!
        XCTAssertTrue(replacement.failures(output: "I want yellow.").isEmpty)
        XCTAssertFalse(replacement.failures(output: "I want orange, yellow.").isEmpty)
        let selective = PromptCorpus.cases.first { $0.id == "selective-retraction" }!
        XCTAssertTrue(selective.failures(output: "Keep the meeting. Repair the old laptop.").isEmpty)
        XCTAssertFalse(selective.failures(output: "Repair the old laptop.").isEmpty)
        let discarded = PromptCorpus.cases.first { $0.id == "whole-retraction" }!
        XCTAssertTrue(discarded.failures(output: "").isEmpty)
        XCTAssertFalse(discarded.failures(output: discarded.input).isEmpty)
    }
}

private actor LineCollector {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}
