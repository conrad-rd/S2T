import XCTest
@testable import S2TCore

final class CreditsTests: XCTestCase {
    private let key = "s2t_demo_" + String(repeating: "a", count: 64)
    func testSignInOnlyOpensMatchingOriginAndConnectionCode() async throws {
        let origin = "https://credits.example.com"
        let code = "ABCDEF123456"
        for url in [origin + "/?connect=" + code, "https://other.example.com/?connect=" + code, origin + "/?connect=000000000000", origin + "/?connect=" + code + "#fragment"] {
            let response: [String: Any] = ["deviceCode": String(repeating: "a", count: 64), "userCode": code, "verificationURL": url, "expiresIn": 600]
            let transport = CreditFixture(response: String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self))
            do {
                let result = try await CreditsAPI(transport: transport).startSignIn(address: origin)
                XCTAssertEqual(url, origin + "/?connect=" + code)
                XCTAssertEqual(result.userCode, code)
            } catch {
                XCTAssertNotEqual(url, origin + "/?connect=" + code)
            }
            let requests = await transport.requests
            XCTAssertEqual(requests.first?.url?.path, "/api/device/start")
            XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
        }
    }
    func testConnectionsRejectProviderKeysAndUnsafeDestinations() throws {
        XCTAssertNoThrow(try CreditConnection(address: "http://localhost:4317", key: key))
        for address in ["http://example.com", "https://user@example.com", "https://example.com/?key=x", "https://example.com/api", "https://example.com"] {
            XCTAssertThrowsError(try CreditConnection(address: address, key: key))
        }
        XCTAssertThrowsError(try CreditConnection(address: "https://example.com", key: "sk-or-v1-fake"))
        XCTAssertThrowsError(try CreditConnection(address: "http://localhost:4317", key: "s2t_live_" + String(repeating: "a", count: 64)))
    }
    func testWarmUsesAuthenticatedLedgerRoute() async throws {
        let transport = CreditFixture(response: #"{"ready":true}"#)
        let connection = try CreditConnection(address: "http://localhost:4317", key: key)
        await CreditsAPI(transport: transport).warmConnection(connection)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.path, "/api/v1/warm")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer " + key)
    }
    func testCleanupPreservesEditingContractAndMetersOneRequest() async throws {
        let transport = CreditFixture()
        let api = CreditsAPI(transport: transport)
        let connection = try CreditConnection(address: "http://localhost:4317", key: key)
        let result = try await api.process(text: "Can you fix this?", mode: .verbatim, model: "openai/gpt-oss-120b", endpoint: "cerebras/fp16", connection: connection, clipboardContext: ClipboardContext(), instructions: "Preserve technical terms.")
        XCTAssertEqual(result.text, "Can you fix this?")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.path, "/api/v1/requests")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer " + key)
        XCTAssertNotNil(UUID(uuidString: requests[0].value(forHTTPHeaderField: "Idempotency-Key") ?? ""))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: String])
        XCTAssertTrue(body["instructions"]!.contains("never that recipient"))
        XCTAssertTrue(body["instructions"]!.contains("Preserve technical terms."))
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: Data(body["text"]!.utf8))["dictated_text"], "Can you fix this?")
    }
    func testExplicitRetryRetainsThePaymentIdentifier() async throws {
        let transport = CreditFixture()
        let api = CreditsAPI(transport: transport)
        let connection = try CreditConnection(address: "http://localhost:4317", key: key)
        for _ in 0..<2 {
            _ = try await api.process(text: "Can you fix this?", mode: .clean, model: "openai/gpt-oss-120b", endpoint: "cerebras/fp16", connection: connection, clipboardContext: ClipboardContext(), instructions: nil, requestID: "recording-fixture-cleanup")
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Idempotency-Key") }, ["recording-fixture-cleanup", "recording-fixture-cleanup"])
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: String])
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: String])
        XCTAssertEqual(first, second)
    }
    func testDeviceAttributionUsesOnlyExplicitMetadataOnUsageRequests() async throws {
        let transport = CreditFixture()
        let id = UUID(uuidString: "a42fb61a-8053-4336-9482-b3e5f27ec7a1")!
        let api = CreditsAPI(transport: transport, device: CreditDevice(id: id, name: "MacBook Pro"))
        _ = try await api.process(text: "test", mode: .verbatim, model: "openai/gpt-oss-120b", endpoint: "cerebras/fp16", connection: CreditConnection(address: "http://localhost:4317", key: key), clipboardContext: ClipboardContext(), instructions: nil)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-S2T-Device-Id"), id.uuidString.lowercased())
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-S2T-Device-Name"), "MacBook Pro")
        XCTAssertEqual(CreditDevice(id: id, name: "Private hostname").name, "Mac")
    }
    func testUnknownOutcomeDoesNotRetryOrReturnSyntheticSuccess() async throws {
        let transport = CreditFixture(response: #"{"state":"uncertain"}"#)
        do {
            _ = try await CreditsAPI(transport: transport).process(text: "test", mode: .verbatim, model: "openai/gpt-oss-120b", endpoint: "cerebras/fp16", connection: CreditConnection(address: "http://localhost:4317", key: key), clipboardContext: ClipboardContext(), instructions: nil)
            XCTFail("An uncertain response must not be delivered")
        } catch { XCTAssertTrue(error.localizedDescription.contains("reserved")) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }
    func testCompletedSilenceReportsNoSpeechWithoutClaimingPendingFunds() async throws {
        let transport = CreditFixture(response: #"{"state":"settled","result":{"text":"","model":"universal-3-5-pro","host":"assemblyai"}}"#)
        do {
            _ = try await CreditsAPI(transport: transport).transcribe(audio: WaveAudio.encode(samples: Array(repeating: 0, count: 16000), sampleRate: 16000), provider: .assemblyAI, model: "universal-3-5-pro", endpoint: nil, connection: CreditConnection(address: "http://localhost:4317", key: key))
            XCTFail("Silence must not produce a delivered transcript")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("No speech"))
            XCTAssertFalse(error.localizedDescription.contains("reserved"))
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }
}
private actor CreditFixture: HTTPTransport {
    var requests: [URLRequest] = []
    let response: String
    let status: Int
    init(status: Int = 200, response: String = #"{"state":"settled","result":{"text":"Can you fix this?","model":"openai/gpt-oss-120b","host":"Cerebras"}}"#) { self.response = response; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (Data(response.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

extension CreditsTests {
    func testChosenReasoningReachesTheCreditGatewayUnchanged() async throws {
        for (model, saved) in [("openai/gpt-4.1-mini", OpenRouterOptions.Effort.high), ("unknown/model", .max), ("openai/gpt-oss-120b", .none)] {
            let transport = CreditFixture()
            _ = try await CreditsAPI(transport: transport).process(text: "test", mode: .clean,
                model: model, endpoint: nil, connection: CreditConnection(address: "http://localhost:4317", key: key),
                clipboardContext: ClipboardContext(), instructions: nil, options: .init(reasoning: saved))
            let requests = await transport.requests
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: String])
            XCTAssertEqual(body["reasoning"], saved.rawValue)
            XCTAssertEqual(body["model"], model)
        }
    }
    func testSelectedModelAndOptionsAreSentWithoutPersonalProviderKey() async throws {
        let transport = CreditFixture()
        let connection = try CreditConnection(address: "http://localhost:4317", key: key)
        _ = try await CreditsAPI(transport: transport).process(text: "test", mode: .clean,
            model: "openai/gpt-oss-20b", endpoint: nil, connection: connection,
            clipboardContext: ClipboardContext(), instructions: nil,
            options: OpenRouterOptions(reasoning: .low, fast: true))
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String])
        XCTAssertEqual(body["model"], "openai/gpt-oss-20b")
        XCTAssertEqual(body["host"], "")
        XCTAssertEqual(body["reasoning"], "low")
        XCTAssertEqual(body["fast"], "true")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + key)
    }
    func testBalanceLoadsConfiguredModelChoicesAndSupportsOlderServices() throws {
        let legacy = Data(#"{"available":9.5,"reserved":0.5,"frozen":false,"paused":false,"mode":"test"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(CreditBalance.self, from: legacy).models)
        let current = Data(#"{"available":9.5,"reserved":0.5,"frozen":false,"paused":false,"mode":"test","models":[{"provider":"openrouter","operation":"cleanup","model":"openai/gpt-oss-20b","host":"","title":"GPT-OSS 20B"}]}"#.utf8)
        let balance = try JSONDecoder().decode(CreditBalance.self, from: current)
        XCTAssertEqual(balance.available, 9.5)
        XCTAssertEqual(balance.reserved, 0.5)
        XCTAssertEqual(balance.models?.first?.model, "openai/gpt-oss-20b")
    }
}

extension CreditsTests {
    func testContributorRequiresOptInBeforeAnyNetworkRequest() async throws {
        let transport = CreditFixture()
        let connection = try CreditConnection(address: "http://localhost:4317", key: key)
        do {
            _ = try await CreditsAPI(transport: transport).process(text: "private fixture", mode: .clean,
                model: OpenRouterOptions.contributorModel, endpoint: nil, connection: connection,
                clipboardContext: ClipboardContext(), instructions: nil)
            XCTFail("Contributor needs opt-in")
        } catch { XCTAssertTrue(error.localizedDescription.contains("opt-in")) }
        var requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
        _ = try await CreditsAPI(transport: transport).process(text: "consented fixture", mode: .clean,
            model: OpenRouterOptions.contributorModel, endpoint: nil, connection: connection,
            clipboardContext: ClipboardContext(), instructions: nil, options: OpenRouterOptions(allowDataCollection: true))
        requests = await transport.requests
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: String])
        XCTAssertEqual(body["allowDataCollection"], "true")
    }
}

extension CreditsTests {
    func testKeyAllowanceDecodesWithoutReplacingWalletBalance() throws {
        let response = Data(#"{"available":100,"reserved":2,"frozen":false,"paused":false,"mode":"live","keyLimit":{"limitCredits":5,"remainingCredits":0,"resetDays":3,"resetsAt":1800316800000,"expiresAt":null}}"#.utf8)
        let balance = try JSONDecoder().decode(CreditBalance.self, from: response)
        XCTAssertEqual(balance.available, 100)
        XCTAssertEqual(balance.keyLimit?.remainingCredits, 0)
        XCTAssertEqual(balance.keyLimit?.resetDays, 3)
        XCTAssertNil(balance.keyLimit?.expiresAt)
    }
    func testKeyLimitErrorsCanRefreshAfterResetWithoutTreatingInvalidKeysAsRecoverable() async throws {
        for code in ["key_limit", "key", "credits"] {
            let transport = CreditFixture(status: 402, response: "{\"error\":\"Fixture failure\",\"code\":\"\(code)\"}")
            do {
                _ = try await CreditsAPI(transport: transport).balance(CreditConnection(address: "http://localhost:4317", key: key))
                XCTFail("An HTTP failure must throw")
            } catch let error as CreditAccountError {
                XCTAssertEqual(error.automaticallyRefreshable, code == "key_limit")
            }
        }
    }
}

extension CreditsTests {
    func testLostResponseRetriesIdenticalRequestAndRecoversCompletedText() async throws {
        let transport = RecoveryCreditFixture()
        let connection = try CreditConnection(address: "http://localhost:4317", key: key)
        let api = CreditsAPI(transport: transport)
        let audio = WaveAudio.encode(samples: Array(repeating: 0, count: 1600), sampleRate: 16000)
        let result = try await api.transcribe(audio: audio, provider: .openRouter, model: "openai/whisper-large-v3-turbo", endpoint: nil, connection: connection, requestID: "same-payment-request-speech")
        XCTAssertEqual(result.text, "Recovered words")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpBody, requests[1].httpBody)
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Idempotency-Key") }, Array(repeating: "same-payment-request-speech", count: 2))
        XCTAssertEqual(requests[0].url?.host, "localhost")
    }
    func testDefinitiveRejectionReportsUsefulErrorWithoutAutomaticNewCharge() async throws {
        let transport = CreditFixture(response: #"{"state":"released","error":"The selected host has no available route."}"#)
        let connection = try CreditConnection(address: "http://localhost:4317", key: key)
        do {
            _ = try await CreditsAPI(transport: transport).process(text: "Retain these words", mode: .clean, model: "openai/gpt-oss-120b", endpoint: nil, connection: connection, clipboardContext: .init(), instructions: nil)
            XCTFail("Expected routing rejection")
        } catch let error as CreditRequestRejected {
            XCTAssertTrue(error.localizedDescription.contains("no available route"))
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }
}
private actor RecoveryCreditFixture: HTTPTransport {
    var requests: [URLRequest] = []
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if requests.count == 1 { throw URLError(.networkConnectionLost) }
        return (Data(#"{"state":"settled","result":{"text":"Recovered words","model":"openai/whisper-large-v3-turbo"}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
