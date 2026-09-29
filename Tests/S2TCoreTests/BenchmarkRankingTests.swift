import XCTest
@testable import S2TCore

final class BenchmarkRankingTests: XCTestCase {
    private func model(_ id: String, quality: Double?, speed: Double?, cost: Double?) -> BenchmarkModel {
        func measurement(_ value: Double) -> BenchmarkMeasurement { .init(value, source: "https://example.com/fixture", note: "Synthetic test") }
        return BenchmarkModel(id: id, name: id, provider: "Fixture", task: "text",
            quality: quality.map { [.intelligence: measurement($0)] } ?? [:],
            speed: speed.map(measurement), cost: cost.map(measurement))
    }
    func testSpeechEligibilityKeepsLatestOfferedVersion() {
        let offered: [BenchmarkOffering] = [
            .init(id: "xai/grok-voice-transcribe-1.0", name: "Grok Transcribe 1", task: "speech"),
            .init(id: "xai/grok-voice-transcribe-2.0", name: "Grok Transcribe 2", task: "speech"),
            .init(id: "assemblyai/universal-3-5-pro", name: "Universal 3.5 Pro", task: "speech")
        ]
        let candidates = [
            BenchmarkModel(id: "old", name: "Grok Transcribe 1", provider: "xAI", task: "speech", speed: .init(900, source: "fixture", note: "")),
            BenchmarkModel(id: "live-uuid", name: "Grok Transcribe 2", provider: "xAI", task: "speech"),
            BenchmarkModel(id: "assemblyai/universal-3-pro", name: "Universal 3 Pro", provider: "AssemblyAI", task: "speech"),
            BenchmarkModel(id: "assemblyai/universal-3-5-pro", name: "Universal 3.5 Pro", provider: "AssemblyAI", task: "speech"),
            BenchmarkModel(id: "unsupported", name: "Unlisted model", provider: "Other", task: "speech")
        ]
        XCTAssertEqual(BenchmarkAvailability.filter(candidates, offered: offered).map(\.id), ["live-uuid", "assemblyai/universal-3-5-pro"])
    }

    func testCompleteOpenRouterSpeechCatalogProducesFiveRankedModels() {
        let offered = SpeechModelCatalog.reference.map { BenchmarkOffering(id: "openrouter/" + $0.id, name: $0.name, task: "speech") }
        let models = BenchmarkAvailability.filter(BenchmarkCatalog.hosted, offered: offered)
        let obsolete = Set(["openrouter/microsoft/mai-transcribe-1.5", "openrouter/openai/whisper-1"])
        XCTAssertEqual(Set(models.map { $0.modelID ?? $0.id }), Set(offered.map(\.id)).subtracting(obsolete))
        XCTAssertTrue(models.allSatisfy { $0.provider == "OpenRouter" })
        XCTAssertTrue(models.contains { $0.id == "openrouter/meta/muse-voice-transcribe-1.0" && $0.quality.isEmpty })
        let ranked = BenchmarkRanking.rank(models, enabled: [.quality], quality: .speech)
        XCTAssertGreaterThan(ranked.count, 5)
        XCTAssertEqual(BenchmarkRanking.top(ranked).count, 5)
        XCTAssertEqual(ranked.first?.model.name, "MAI-Transcribe 2")
        XCTAssertFalse(models.contains { $0.provider == "Mistral" })
    }

    func testEligibilityPreservesSizesTasksAndLocalIsolation() {
        let offered: [BenchmarkOffering] = [
            .init(id: "openai/gpt-oss-20b", name: "GPT OSS 20B", task: "text"),
            .init(id: "openai/gpt-oss-120b", name: "GPT OSS 120B", task: "text"),
            .init(id: "local/example", name: "Local model", task: "text"),
            .init(id: "google/gemini-2.5-flash", name: "Gemini 2.5 Flash", task: "vision"),
            .init(id: "google/gemini-2.10-flash", name: "Gemini 2.10 Flash", task: "vision")
        ]
        let candidates = offered.map { BenchmarkModel(id: $0.id, name: $0.name, provider: $0.id.hasPrefix("local/") ? "Local" : "Hosted", task: $0.task) } + [
            BenchmarkModel(id: "wrong-task", name: "GPT OSS 20B", provider: "Hosted", task: "vision"),
            BenchmarkModel(id: "wrong-host", name: "Local model", provider: "Hosted", task: "text")
        ]
        XCTAssertEqual(BenchmarkAvailability.filter(candidates, offered: offered).map(\.id),
            ["openai/gpt-oss-20b", "openai/gpt-oss-120b", "local/example", "google/gemini-2.10-flash"])
    }

    func testAppleLanguagesDoNotBecomeDuplicateBenchmarkCompetitors() throws {
        let languages = ["en-US", "en-GB", "de-DE", "fr-FR", "hi-IN", "ja-JP"]
        let models = BenchmarkCatalog.models(local: languages.map(LocalModel.appleSpeech))
        let apple = models.filter { $0.provider == "Local" }
        XCTAssertEqual(apple.count, 1)
        let engine = try XCTUnwrap(apple.first)
        XCTAssertEqual(engine.name, "Apple Speech")
        XCTAssertTrue(engine.quality.isEmpty)
        XCTAssertNil(engine.speed)
        XCTAssertEqual(engine.cost?.value, 0)
        let ranked = BenchmarkRanking.rank(models.filter { $0.task == "speech" }, enabled: [.cost], quality: .speech)
        XCTAssertEqual(ranked.filter { $0.model.provider == "Local" }.count, 1)
        XCTAssertFalse(BenchmarkCatalog.models(local: []).contains { $0.name == "Apple Speech" })
    }

    func testEverySwitchChangesTheActualWinnerAndStack() throws {
        let models = [model("accurate", quality: 90, speed: 20, cost: 5),
                      model("fast", quality: 80, speed: 100, cost: 3),
                      model("cheap", quality: 70, speed: 60, cost: 0)]
        for (category, winner) in [(BenchmarkCategory.quality, "accurate"), (.speed, "fast"), (.cost, "cheap")] {
            let ranked = BenchmarkRanking.rank(models, enabled: [category], quality: .intelligence)
            XCTAssertEqual(ranked.first?.id, winner)
            XCTAssertEqual(ranked.first?.total, 100)
            XCTAssertEqual(ranked.first?.contributions.count, 1)
        }
        let ranked = BenchmarkRanking.rank(models, enabled: [.quality, .speed, .cost], quality: .intelligence)
        XCTAssertEqual(ranked.first?.id, "fast")
        let winner = try XCTUnwrap(ranked.first)
        XCTAssertEqual(winner.total, (50 + 100 + 40) / 3, accuracy: 0.00001)
        XCTAssertLessThan(winner.contributions[.quality]!, ranked.first { $0.id == "accurate" }!.contributions[.quality]!)
        XCTAssertEqual(winner.contributions.count, 3)
        XCTAssertTrue(BenchmarkRanking.rank(models, enabled: [], quality: .intelligence).isEmpty)
    }
    func testUnknownDataNeverReceivesAZeroCostOrAnAverageScore() {
        let models = [model("known", quality: 80, speed: 50, cost: 1), model("missing", quality: 90, speed: nil, cost: nil)]
        XCTAssertEqual(BenchmarkRanking.rank(models, enabled: [.quality], quality: .intelligence).first?.id, "missing")
        XCTAssertEqual(BenchmarkRanking.rank(models, enabled: [.quality, .speed], quality: .intelligence).map(\.id), ["known"])
        XCTAssertEqual(BenchmarkRanking.rank(models, enabled: [.cost], quality: .intelligence).map(\.id), ["known"])
        XCTAssertTrue(BenchmarkRanking.rank(models, enabled: [.quality], quality: .fleurs).isEmpty)
    }
    func testLowerErrorWinsAndTiesRemainEqual() {
        var models = [model("b", quality: nil, speed: nil, cost: 0), model("a", quality: nil, speed: nil, cost: 0)]
        models[0].quality[.speech] = .init(2, source: "fixture", note: "fixture")
        models[1].quality[.speech] = .init(4, source: "fixture", note: "fixture")
        XCTAssertEqual(BenchmarkRanking.rank(models, enabled: [.quality], quality: .speech).first?.id, "b")
        let tied = BenchmarkRanking.rank(models, enabled: [.cost], quality: .speech)
        XCTAssertEqual(tied.map(\.id), ["a", "b"])
        XCTAssertEqual(tied.map(\.rank), [1, 1])
        XCTAssertEqual(tied.map(\.total), [100, 100])
    }
}
