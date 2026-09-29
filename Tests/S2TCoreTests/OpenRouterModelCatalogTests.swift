import XCTest
@testable import S2TCore

final class OpenRouterModelCatalogTests: XCTestCase {
    func testTextCatalogIncludesFutureAndMultimodalModelsButNotImageOnly() throws {
        let data = Data(#"{"data":[{"id":"fixture/fable-5.1","name":"Fable 5.1","architecture":{"input_modalities":["text"],"output_modalities":["text"]}},{"id":"fixture/multimodal","name":"Multimodal","architecture":{"input_modalities":["text","image"],"output_modalities":["text"]}},{"id":"fixture/image","name":"Image","architecture":{"input_modalities":["text"],"output_modalities":["image"]}}]}"#.utf8)
        let models = try OpenRouterTextModel.decode(data)
        XCTAssertEqual(models.map(\.id), ["fixture/fable-5.1", "fixture/multimodal"])
        XCTAssertEqual(models.filter(\.acceptsImages).map(\.id), ["fixture/multimodal"])
    }
    func testProviderTagsMetricsAndMissingMeasurements() async throws {
        let json = #"{"data":{"endpoints":[{"tag":"host/fp16","provider_name":"Host","quantization":"fp16","status":0,"pricing":{"prompt":"0.000002","completion":"0.000004"},"throughput_last_30m":{"p50":123.4}},{"tag":"other","provider_name":"Other","status":0,"pricing":{},"throughput_last_30m":null},{"tag":"offline","provider_name":"Offline","status":1,"pricing":{}}]}}"#
        let transport = ScriptedTransport([.init(path: "/api/v1/models/fixture/model/endpoints", status: 200, json: json)])
        let hosts = try await OpenRouterHost.load(model: "fixture/model", transport: transport)
        XCTAssertEqual(hosts.map(\.tag), ["host/fp16", "other"])
        XCTAssertTrue(hosts[0].menuTitle(cheapest: 0.000003).contains("+100%"))
        XCTAssertTrue(hosts[0].menuTitle(cheapest: nil).contains("123 tok/s"))
        XCTAssertTrue(hosts[0].menuTitle(cheapest: nil).contains("$2 in / $4 out per 1M"))
        XCTAssertTrue(hosts[1].menuTitle(cheapest: nil).contains("Speed unavailable"))
        let requests = await transport.requests
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
    }
}
