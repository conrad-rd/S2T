import XCTest
@testable import S2TCore

final class APIKeyTests: XCTestCase {
    func testValidationUsesAuthenticatedReadOnlyEndpointForEachProvider() async throws {
        let fixtures: [(APIAccount, String, String, String, String)] = [
            (.assemblyAI, "/v2/transcript", "api.assemblyai.com", "assembly-key", #"{"transcripts":[]}"#),
            (.openRouter, "/api/v1/key", "openrouter.ai", "Bearer router-key", #"{"data":{"label":"test"}}"#),
            (.typeSafe, "/v1/models", "api.typesafe.ai", "Bearer typesafe-key", #"{"models":[]}"#)
        ]
        for (account, path, host, authorization, json) in fixtures {
            let transport = ScriptedTransport([.init(path: path, status: 200, json: json)])
            let key = authorization.replacingOccurrences(of: "Bearer ", with: "")
            try await DictationAPI(transport: transport).validateKey(key, account: account)
            let requests = await transport.requests
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.url?.host, host)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), authorization)
            XCTAssertNil(request.httpBody)
        }
    }

    func testAuthenticationAndCreditFailuresIdentifyAccountWithoutLeakingResponse() async {
        for status in [401, 402, 403] {
            let transport = ScriptedTransport([.init(path: "/api/v1/chat/completions", status: status, json: #"{"error":"private-key-and-response"}"#)])
            do {
                _ = try await DictationAPI(transport: transport).process(text: "hello", mode: .clean, model: "openrouter/auto", apiKey: "private-key")
                XCTFail("Expected account failure")
            } catch {
                XCTAssertEqual(error as? ServiceError, .account(.openRouter, status: status))
                XCTAssertFalse(error.localizedDescription.contains("private-key"))
            }
        }
    }

    func testModelAttestationFailureDoesNotRejectAValidOpenRouterKey() async throws {
        let json = #"{"error":{"message":"private-provider-response","code":403,"metadata":{"missing_attestation_types":["age_18plus"]}}}"#
        for path in ["/api/v1/chat/completions", "/api/v1/audio/transcriptions"] {
            let transport = ScriptedTransport([.init(path: path, status: 403, json: json)])
            do {
                let api = DictationAPI(transport: transport)
                if path.hasSuffix("chat/completions") {
                    _ = try await api.process(text: "hello", mode: .clean, model: "meta/muse-spark-1.3-contributor", apiKey: "fixture", routerOptions: OpenRouterOptions(allowDataCollection: true))
                } else {
                    _ = try await api.transcribe(audio: Data(), apiKey: "fixture", provider: .openRouter)
                }
                XCTFail("Expected model access failure")
            } catch {
                guard case .message = error as? ServiceError else { return XCTFail("Model requirements must not mark the key invalid") }
                XCTAssertTrue(error.localizedDescription.contains("age confirmation"))
                XCTAssertTrue(error.localizedDescription.contains("https://openrouter.ai/settings/preferences"))
                XCTAssertTrue(error.localizedDescription.contains(path.hasSuffix("chat/completions") ? "Models → Selected model" : "Speech-to-text model"))
                XCTAssertFalse(error.localizedDescription.contains("private-provider-response"))
            }
        }
    }

    func testServerErrorsAreNotReportedAsBrokenProviderKeys() async {
        for status in [429, 500] {
            let transport = ScriptedTransport([.init(path: "/api/v1/key", status: status, json: "{}")])
            do {
                try await DictationAPI(transport: transport).validateKey("test", account: .openRouter)
                XCTFail("Expected failure")
            } catch {
                guard case .message = error as? ServiceError else { return XCTFail("Must not mark key rejected") }
            }
        }
    }
}
