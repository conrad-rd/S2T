import XCTest
@testable import S2TCore

final class LocalBenchmarkTests: XCTestCase {
    func testScoresBelongToTheCatalogTaskAndRetainSources() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try LocalModel.read(from: root.appendingPathComponent("Resources/LocalModels/catalog.json"))
        for (id, score) in LocalModelBenchmark.scores {
            let model = try XCTUnwrap(catalog.first { $0.id == id })
            XCTAssertEqual(score.metric, .forCategory(model.category))
            XCTAssertTrue(score.value.isFinite && score.value >= 0 && score.value <= score.metric.chartMaximum)
            XCTAssertEqual(URL(string: score.sourceURL)?.scheme, "https")
            XCTAssertFalse(score.configuration.isEmpty)
        }
        XCTAssertNil(LocalModelBenchmark.scores["apple-speech-en-US"])
        XCTAssertNil(LocalModelBenchmark.scores["whisper-turbo"])
        XCTAssertNil(LocalModelBenchmark.scores["future-unrated-model"])
    }

    func testBarsPreservePublishedValueRatios() throws {
        let smallSpeech = try XCTUnwrap(LocalModelBenchmark.scores["qwen-asr"])
        let largeSpeech = try XCTUnwrap(LocalModelBenchmark.scores["qwen-asr-large"])
        XCTAssertEqual(smallSpeech.fraction / largeSpeech.fraction, 4.39 / 3.35, accuracy: 0.000001)
        XCTAssertTrue(smallSpeech.metric.title.contains("Lower is better"))
    }

    func testEstimatedScoresAndDifferentReasoningAreExplicit() throws {
        for id in ["qwen-small", "qwen-medium", "qwen-cleanup-4b", "qwen-cleanup-8b"] {
            let score = try XCTUnwrap(LocalModelBenchmark.scores[id])
            XCTAssertTrue(score.estimated)
            XCTAssertTrue(score.formattedValue.hasPrefix("~"))
            XCTAssertTrue(score.configuration.contains("AA estimate"))
        }
        let gpt = try XCTUnwrap(LocalModelBenchmark.scores["openai-gpt-oss-20b"])
        XCTAssertTrue(gpt.configuration.contains("High reasoning"))
        XCTAssertFalse(gpt.estimated)
    }
}
