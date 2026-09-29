import XCTest
@testable import S2TCore

final class ReasoningCatalogTests: XCTestCase {
    func testPickerUsesOnlyAdvertisedLevelsAndNeverInventsSupport() throws {
        let entries = try OpenRouterReasoningCatalog.decode(Data(#"{"data":[{"id":"fixture/required","reasoning":{"mandatory":true,"supported_efforts":["high","low","none","future-level","low"]}},{"id":"fixture/optional","reasoning":{"mandatory":false,"supported_efforts":["high","minimal","none"]}},{"id":"fixture/plain"},{"id":"fixture/budget-only","reasoning":{"mandatory":false}}]}"#.utf8))
        let catalog = OpenRouterReasoningCatalog(entries: entries)
        XCTAssertEqual(catalog.efforts(for: "fixture/required"), [.automatic, .low, .high])
        XCTAssertEqual(catalog.efforts(for: "fixture/optional"), [.automatic, .none, .minimal, .high])
        for model in ["fixture/plain", "fixture/budget-only", "fixture/missing"] {
            XCTAssertEqual(catalog.efforts(for: model), [.automatic])
        }
    }

    func testSavedChoicesRemainExplicitAcrossModels() {
        for model in ["openai/gpt-4.1-mini", "unknown/model"] {
            let options = OpenRouterOptions(reasoning: .max, fast: true, allowDataCollection: true).normalized(for: model)
            XCTAssertEqual(options.reasoning, .max)
            XCTAssertTrue(options.fast)
            XCTAssertTrue(options.allowDataCollection)
            var body: [String: Any] = ["model": model, "reasoning": ["effort": "max"]]
            OpenRouterOptions(reasoning: .max).apply(to: &body)
            XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], "max")
        }
        XCTAssertTrue(OpenRouterOptions.supportedEfforts(for: "meta/muse-spark-1.3-contributor").contains(.none))
        XCTAssertTrue(OpenRouterOptions.supportedEfforts(for: "openai/gpt-5.6-luna").contains(.minimal))
        XCTAssertTrue(OpenRouterOptions.supportedEfforts(for: "openai/gpt-5.6-luna").contains(.none))
    }

    func testRefreshReplacesCapabilitiesAndUnknownFailuresStayAtDefault() async throws {
        let catalog = OpenRouterReasoningCatalog(entries: [:])
        let transport = ScriptedTransport([
            .init(path: "/api/v1/model/fixture/model", status: 200, json: #"{"data":{"id":"fixture/model","reasoning":{"mandatory":true,"supported_efforts":["high","low"]}}}"#),
            .init(path: "/api/v1/model/fixture/missing", status: 404, json: "{}")
        ])
        XCTAssertEqual(catalog.efforts(for: "fixture/model"), [.automatic])
        await catalog.refresh(model: "fixture/model", transport: transport)
        XCTAssertEqual(catalog.efforts(for: "fixture/model"), [.automatic, .low, .high])
        await catalog.refresh(model: "fixture/model", transport: transport)
        await catalog.refresh(model: "fixture/missing", transport: transport)
        XCTAssertEqual(catalog.efforts(for: "fixture/missing"), [.automatic])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && $0.httpBody == nil })
    }
}
