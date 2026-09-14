import XCTest
@testable import S2TCore

final class CodexCLITests: XCTestCase {
    private func fixture(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-cli-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("codex fixture")
        try ("#!/usr/bin/python3\n" + body).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }

    func testRealSubprocessPassesInputWithoutShellAndCleansPrivateFiles() async throws {
        let executable = try fixture("""
        import sys, json, pathlib, os
        args = sys.argv[1:]
        assert args[0] == 'exec'
        assert '--ignore-user-config' in args and '--ephemeral' in args
        assert args[args.index('--sandbox') + 1] == 'read-only'
        assert 'features.shell_tool=false' in args
        assert 'features.plugins=false' in args
        assert '--model' not in args
        assert 'OPENAI_API_KEY' not in os.environ
        assert args[-2:] == ['--', '-']
        image = pathlib.Path(args[args.index('--image') + 1]).read_bytes()
        assert image == bytes([1, 2, 3])
        output = pathlib.Path(args[args.index('--output-last-message') + 1])
        output.write_text(json.dumps({'input': sys.stdin.read(), 'directory': str(output.parent)}))
        """)
        let source = "Dictated text: $(touch NEVER) `whoami` \"quotes\"\n第二行"
        let result = try await CodexCLI().complete(instructions: "Edit only.", prompt: source, model: "default", images: [Data([1, 2, 3])], executable: executable.path)
        let decoded = try JSONDecoder().decode([String: String].self, from: Data(result.utf8))
        XCTAssertEqual(decoded["input"], source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(decoded["directory"])))
    }

    func testModelReasoningAndFastReachTheExecutable() async throws {
        let executable = try fixture("""
        import sys, pathlib
        args = sys.argv[1:]
        assert args[args.index('--model') + 1] == 'fixture-model'
        assert 'model_reasoning_effort="high"' in args
        assert 'service_tier="fast"' in args
        assert 'features.fast_mode=true' in args
        pathlib.Path(args[args.index('--output-last-message') + 1]).write_text('Configured result')
        """)
        let result = try await CodexCLI().complete(instructions: "Edit.", prompt: "Source", model: "fixture-model", executable: executable.path, options: CodexOptions(reasoning: "high", fast: true))
        XCTAssertEqual(result, "Configured result")
    }

    func testCatalogCapabilitiesDoNotInventReasoningOrFastSupport() throws {
        let data = Data(#"{"models":[{"slug":"fixture-model","display_name":"Fixture","supported_reasoning_levels":[{"effort":"low","description":"Quick"},{"effort":"high","description":"Deep"}],"service_tiers":[{"id":"priority","name":"Fast"}],"input_modalities":["text","image"]},{"slug":"plain","display_name":"Plain","supported_reasoning_levels":[],"input_modalities":["text"]}]}"#.utf8)
        let models = try CodexModelCatalog.decode(data)
        XCTAssertTrue(models[0].supportsFast)
        XCTAssertEqual(models[0].normalized(CodexOptions(reasoning: "ultra", fast: true)), CodexOptions(fast: true))
        XCTAssertEqual(models[1].normalized(CodexOptions(reasoning: "high", fast: true)), CodexOptions())
        XCTAssertFalse(CodexOptions(reasoning: "high\";bad").isValid)
        XCTAssertTrue(CodexOptions().arguments.isEmpty)
    }

    func testCancellationAndTimeoutStopSubprocesses() async throws {
        let executable = try fixture("import time\ntime.sleep(30)\n")
        let task = Task { try await CodexCLI().complete(instructions: "", prompt: "fixture", model: "default", executable: executable.path) }
        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation returned a result") }
        catch is CancellationError {} catch { XCTFail("Wrong cancellation: \(error)") }
        let started = Date()
        do {
            _ = try await CodexCLI(timeout: 0.15).complete(instructions: "", prompt: "fixture", model: "default", executable: executable.path)
            XCTFail("Timeout returned a result")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testFailedAndEmptyRunsAreNotSuccessfulResults() async throws {
        for body in ["import sys\nsys.exit(7)\n", "pass\n"] {
            let executable = try fixture(body)
            do {
                _ = try await CodexCLI().complete(instructions: "", prompt: "fixture", model: "test-model", executable: executable.path)
                XCTFail("Failed run returned a result")
            } catch { XCTAssertTrue(error.localizedDescription.contains("Codex")) }
        }
    }
}
