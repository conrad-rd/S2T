import XCTest
@testable import S2TCore

final class ArtificialAnalysisPublicTests: XCTestCase {
    func testPublicTableUsesNamedHostsAndKeepsMissingValuesUnknown() throws {
        let html = """
        <table><tr><th>Model</th><th>Provider</th><th>Whisper Version</th><th>Word Error Rate <span>%</span></th><th>Median Speed Factor</th><th>Price USD per 1,000 minutes</th></tr>
        <tr><td>Grok Voice Transcribe 2.0</td><td>SpaceXAI</td><td></td><td>2.3%</td><td>153.8</td><td>1.67</td></tr>
        <tr><td>Whisper Large v3</td><td>Replicate</td><td>v3</td><td>10.1%</td><td>2.6</td><td>4.23</td></tr>
        <tr><td>Whisper Large v3</td><td>fal.ai</td><td>v3</td><td>4.1%</td><td>—</td><td>1.15</td></tr>
        </table>
        """
        let result = try ArtificialAnalysisPublicClient.decode(html)
        XCTAssertEqual(result.tier, "public")
        XCTAssertEqual(result.models.count, 2)
        XCTAssertEqual(result.models[0].speed?.value, 153.8)
        XCTAssertEqual(result.models[1].quality[.speech]?.value, 4.1)
        XCTAssertNil(result.models[1].speed)
        XCTAssertEqual(result.models[1].provider, "OpenRouter")
        XCTAssertTrue(result.models[1].cost!.note.contains("fal.ai"))
    }

    func testMissingOrChangedTableFailsInsteadOfClaimingFreshData() {
        XCTAssertThrowsError(try ArtificialAnalysisPublicClient.decode("<html>Unavailable</html>"))
        XCTAssertThrowsError(try ArtificialAnalysisPublicClient.decode("<table><tr><th>Model</th><th>Latency</th></tr></table>"))
    }
}
