import XCTest
@testable import S2TCore

final class LocalModelTests: XCTestCase {
    func testNativeSpeechIdentityAndUnmeasuredResources() {
        let model = LocalModel.appleSpeech(locale: "de-DE")
        XCTAssertEqual(model.id, "apple-speech-de-DE")
        XCTAssertEqual(LocalModel.appleSpeech(locale: "de_DE").id, model.id)
        XCTAssertEqual(model.nativeLocale, "de-DE")
        XCTAssertEqual(model.category, "speech")
        XCTAssertTrue(model.isNative)
        XCTAssertEqual(model.memoryGB, 0)
        XCTAssertEqual(model.qualityPerGB, 0)
        XCTAssertTrue(TranscriptionProvider.local.validModelID(model.id))
    }

    func testCatalogHasSeparateTasksAndPinnedRevisions() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let models = try LocalModel.read(from: source.appendingPathComponent("Resources/LocalModels/catalog.json"))
        XCTAssertEqual(Set(models.map(\.category)), ["speech", "text"])
        XCTAssertGreaterThanOrEqual(models.filter { $0.category == "speech" }.count, 2)
        XCTAssertGreaterThanOrEqual(models.filter { $0.category == "text" }.count, 2)
        XCTAssertTrue(models.allSatisfy { !$0.revision.isEmpty && $0.diskGB <= $0.memoryGB })
    }
}
