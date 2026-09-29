import XCTest
@testable import S2TCore

private actor StreamingSocketFixture: AssemblyStreamingSocket {
    var messages: [URLSessionWebSocketTask.Message] = []
    var sent: [URLSessionWebSocketTask.Message] = []
    var request: URLRequest?
    var closed = false
    let stallConnect: Bool
    let stallSend: Bool
    let begin: Bool
    let finishMessages: [String]
    init(begin: Bool = true, finishMessages: [String] = [], stallConnect: Bool = false, stallSend: Bool = false) { self.begin = begin; self.finishMessages = finishMessages; self.stallConnect = stallConnect; self.stallSend = stallSend }
    func connect(_ request: URLRequest) async throws {
        self.request = request
        while stallConnect && !closed { try await Task.sleep(nanoseconds:1_000_000) }
        if begin { messages.append(.string("{\"type\":\"Begin\",\"id\":\"session-1\"}")) }
    }
    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        while stallSend && !closed { try await Task.sleep(nanoseconds:1_000_000) }
        if closed { throw AssemblyStreamingError.disconnected }
        sent.append(message)
        if case .string(let text) = message, text.contains("Terminate") {
            messages += finishMessages.map { .string($0) }
        }
    }
    func receive() async throws -> URLSessionWebSocketTask.Message {
        while messages.isEmpty {
            if closed { throw AssemblyStreamingError.disconnected }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return messages.removeFirst()
    }
    func close() async { closed = true }
    func feed(_ text: String) { messages.append(.string(text)) }
    func audio() -> [Data] { sent.compactMap { if case .data(let data) = $0 { return data }; return nil } }
}

final class AssemblyStreamingTests: XCTestCase {
    private let termination = "{\"type\":\"Termination\",\"session_duration_seconds\":2.4,\"audio_duration_seconds\":0.1}"
    private func turn(_ order: Int, _ text: String, final: Bool = true, formatted: Bool = false) -> String {
        "{\"type\":\"Turn\",\"turn_order\":\(order),\"transcript\":\"\(text)\",\"end_of_turn\":\(final),\"turn_is_formatted\":\(formatted)}"
    }
    func testNativeRateChunksAndFinalTurnReplacement() async throws {
        let socket = StreamingSocketFixture(finishMessages: [turn(1,"world"), turn(0,"hel",final:false), turn(0,"Hello.",formatted:true), turn(0,"stale",final:false), termination])
        let client = AssemblyStreamingClient(socket: socket)
        let id = try await client.start(token:"fake-token", sampleRate:48000)
        XCTAssertEqual(id,"session-1")
        let pcm = Data((0..<11000).map { UInt8(truncatingIfNeeded:$0) })
        try await client.append(pcm: pcm)
        let result = try await client.finish()
        XCTAssertEqual(result.text,"Hello. world")
        XCTAssertEqual(result.sessionDurationSeconds,2.4)
        let audio = await socket.audio()
        XCTAssertEqual(audio.map(\.count),[9600,4800])
        XCTAssertEqual(Data(audio.joined()).prefix(pcm.count),pcm)
        let request = await socket.request
        XCTAssertEqual(request?.url?.host,"streaming.assemblyai.com")
        XCTAssertNil(request?.value(forHTTPHeaderField:"Authorization"))
        XCTAssertTrue(request!.url!.query!.contains("sample_rate=48000"))
    }
    func testEmptyAndMalformedFinalResponsesFail() async throws {
        for ending in [termination,"{\"type\":\"Turn\",\"transcript\":\"bad\"}"] {
            let client = AssemblyStreamingClient(socket:StreamingSocketFixture(finishMessages:[ending]),timeoutSeconds:0.1)
            _ = try await client.start(token:"fake",sampleRate:16000)
            do { _ = try await client.finish(); XCTFail("Expected response failure") } catch { XCTAssertTrue(error is AssemblyStreamingError) }
        }
    }
    func testTimeoutAndCancellationCloseTransport() async throws {
        let socket = StreamingSocketFixture(begin:false)
        let client = AssemblyStreamingClient(socket:socket,timeoutSeconds:0.02)
        do { _ = try await client.start(token:"fake",sampleRate:16000); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? AssemblyStreamingError,.timedOut) }
        let closed = await socket.closed
        XCTAssertTrue(closed)
        let socket2 = StreamingSocketFixture()
        let second = AssemblyStreamingClient(socket:socket2)
        _ = try await second.start(token:"fake",sampleRate:16000)
        await second.cancel()
        do { try await second.append(pcm:Data(repeating:0,count:3200)); XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testDisconnectDoesNotReturnPartialTranscript() async throws {
        let socket = StreamingSocketFixture()
        let client = AssemblyStreamingClient(socket:socket,timeoutSeconds:0.05)
        _ = try await client.start(token:"fake",sampleRate:44100)
        await socket.feed(turn(0,"partial",final:false))
        await socket.close()
        do { _ = try await client.finish(); XCTFail("Expected disconnect") } catch { XCTAssertTrue(error is AssemblyStreamingError) }
    }
    func testFinishingTimeoutAndOddPCMRejection() async throws {
        let socket = StreamingSocketFixture()
        let client = AssemblyStreamingClient(socket:socket,timeoutSeconds:0.02)
        _ = try await client.start(token:"never-echo-this-secret",sampleRate:16000)
        do { try await client.append(pcm:Data([1])); XCTFail("Expected invalid PCM") }
        catch { XCTAssertEqual(error as? AssemblyStreamingError,.invalidAudio) }
        do { _ = try await client.finish(); XCTFail("Expected final timeout") }
        catch {
            XCTAssertEqual(error as? AssemblyStreamingError,.timedOut)
            XCTAssertFalse(error.localizedDescription.contains("never-echo-this-secret"))
        }
        let closed = await socket.closed
        XCTAssertTrue(closed)
    }
    func testSequentialChunksPreserveSampleOrderAcrossAppends() async throws {
        let socket = StreamingSocketFixture(finishMessages:[turn(0,"Ready."),termination])
        let client = AssemblyStreamingClient(socket:socket)
        _ = try await client.start(token:"fake",sampleRate:16000)
        var expected = Data()
        for index in 0..<12 {
            let part = Data(repeating:UInt8(index),count:800)
            expected.append(part)
            try await client.append(pcm:part)
        }
        _ = try await client.finish()
        let sent = await socket.audio()
        XCTAssertEqual(sent.count,3)
        XCTAssertEqual(Data(sent.joined()),expected)
    }

    func testStalledConnectionAndSendAreBounded() async throws {
        let connecting = AssemblyStreamingClient(socket:StreamingSocketFixture(stallConnect:true),timeoutSeconds:0.02)
        do { _ = try await connecting.start(token:"fake",sampleRate:16000); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? AssemblyStreamingError,.timedOut) }
        let client = AssemblyStreamingClient(socket:StreamingSocketFixture(stallSend:true),timeoutSeconds:0.02)
        _ = try await client.start(token:"fake",sampleRate:16000)
        do { try await client.append(pcm:Data(repeating:0,count:3200)); XCTFail("Expected send timeout") }
        catch { XCTAssertEqual(error as? AssemblyStreamingError,.timedOut) }
    }
    func testDuplicateBeginUnsolicitedTerminationAndIncompleteTurnFail() async throws {
        for message in ["{\"type\":\"Begin\",\"id\":\"duplicate\"}",termination] {
            let socket = StreamingSocketFixture()
            let client = AssemblyStreamingClient(socket:socket)
            _ = try await client.start(token:"fake",sampleRate:16000)
            await socket.feed(message)
            try await Task.sleep(nanoseconds:20_000_000)
            do { _ = try await client.finish(); XCTFail("Expected invalid sequence") }
            catch { XCTAssertEqual(error as? AssemblyStreamingError,.malformedResponse) }
        }
        let client = AssemblyStreamingClient(socket:StreamingSocketFixture(finishMessages:[turn(0,"unfinished",final:false),termination]))
        _ = try await client.start(token:"fake",sampleRate:16000)
        do { _ = try await client.finish(); XCTFail("Expected incomplete turn failure") }
        catch { XCTAssertEqual(error as? AssemblyStreamingError,.malformedResponse) }
    }
    func testCancellingStalledAppendClosesSocket() async throws {
        let socket = StreamingSocketFixture(stallSend:true)
        let client = AssemblyStreamingClient(socket:socket)
        _ = try await client.start(token:"fake",sampleRate:16000)
        let append = Task { try await client.append(pcm:Data(repeating:0,count:3200)) }
        try await Task.sleep(nanoseconds:10_000_000)
        append.cancel()
        do { try await append.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        let closed = await socket.closed
        XCTAssertTrue(closed)
    }

}
