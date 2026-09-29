import Darwin
import Foundation

public struct BenchProcessOutput: Sendable {
    public let code: Int32
    public let output: String
    public let timedOut: Bool
}

private final class BenchProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var processFinished = false
    private var readerFinished = false
    private var stopReader = false

    var finished: Bool {
        lock.lock(); defer { lock.unlock() }
        return processFinished && readerFinished
    }
    var shouldStopReader: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopReader
    }
    func markProcessFinished() { lock.lock(); processFinished = true; lock.unlock() }
    func markReaderFinished() { lock.lock(); readerFinished = true; lock.unlock() }
    func abandonReader() { lock.lock(); stopReader = true; lock.unlock() }
}

private final class BenchProcessGroup: @unchecked Sendable {
    let pid: pid_t
    init(pid: pid_t) { self.pid = pid }
    func signal(_ value: Int32) {
        // POSIX_SPAWN_SETPGROUP creates a group whose ID is the child PID. Once
        // the direct child exits, its PID can be reused while descendants still
        // hold the pipe, so only address the supervised process group.
        _ = Darwin.kill(-pid, value)
    }
}

public enum BenchProcess {
    public static func run(executable: URL, arguments: [String], timeout: Double, environment: [String: String]? = nil,
                           onLine: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> BenchProcessOutput {
        try Task.checkCancellation()
        let launched = try spawn(executable: executable, arguments: arguments, environment: environment)
        let group = BenchProcessGroup(pid: launched.pid)
        let state = BenchProcessState()

        let reader = Task.detached(priority: .utility) { () async -> Data in
            defer { Darwin.close(launched.readFD); state.markReaderFinished() }
            var kept = Data(), pending = Data(), bytes = [UInt8](repeating: 0, count: 8192)
            while !state.shouldStopReader {
                let count = Darwin.read(launched.readFD, &bytes, bytes.count)
                if count > 0 {
                    let next = Data(bytes.prefix(count))
                    if kept.count < 2_000_000 { kept.append(next.prefix(2_000_000 - kept.count)) }
                    pending.append(next)
                    while let newline = pending.firstIndex(of: 10) {
                        await onLine(String(decoding: pending[..<newline], as: UTF8.self))
                        pending.removeSubrange(...newline)
                    }
                    if pending.count > 128_000 { pending.removeAll(keepingCapacity: true) }
                } else if count == 0 {
                    break
                } else if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                    try? await Task.sleep(for: .milliseconds(5))
                } else {
                    break
                }
            }
            if !pending.isEmpty { await onLine(String(decoding: pending, as: UTF8.self)) }
            return kept
        }
        let waiter = Task.detached(priority: .utility) { () -> Int32 in
            defer { state.markProcessFinished() }
            var status: Int32 = 0
            while Darwin.waitpid(launched.pid, &status, 0) == -1 {
                if errno != EINTR { return 127 }
            }
            return exitCode(status)
        }

        let started = ProcessInfo.processInfo.systemUptime
        var timedOut = false
        await withTaskCancellationHandler {
            while !state.finished {
                if Task.isCancelled { break }
                if ProcessInfo.processInfo.systemUptime - started >= max(0, timeout) {
                    timedOut = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
        } onCancel: {
            group.signal(SIGTERM)
        }

        if timedOut || Task.isCancelled {
            group.signal(SIGTERM)
            let grace = ProcessInfo.processInfo.systemUptime + 0.25
            while !state.finished, ProcessInfo.processInfo.systemUptime < grace {
                try? await Task.sleep(for: .milliseconds(10))
            }
            if !state.finished { group.signal(SIGKILL) }
            let killWait = ProcessInfo.processInfo.systemUptime + 0.25
            while !state.finished, ProcessInfo.processInfo.systemUptime < killWait {
                try? await Task.sleep(for: .milliseconds(10))
            }
            // A descendant that deliberately escaped the process group must not
            // turn output draining into an unbounded second wait.
            if !state.finished { state.abandonReader() }
        }

        let status = await waiter.value
        let output = await reader.value
        try Task.checkCancellation()
        return BenchProcessOutput(code: status, output: String(decoding: output, as: UTF8.self), timedOut: timedOut)
    }

    private static func spawn(executable: URL, arguments: [String], environment: [String: String]?) throws -> (pid: pid_t, readFD: Int32) {
        var descriptors: [Int32] = [0, 0]
        guard Darwin.pipe(&descriptors) == 0 else { throw launchError(errno) }
        let readFD = descriptors[0], writeFD = descriptors[1]
        let flags = Darwin.fcntl(readFD, F_GETFL)
        guard flags >= 0, Darwin.fcntl(readFD, F_SETFL, flags | O_NONBLOCK) == 0 else {
            let code = errno
            Darwin.close(readFD); Darwin.close(writeFD)
            throw launchError(code)
        }

        var actions: posix_spawn_file_actions_t?
        let actionsResult = posix_spawn_file_actions_init(&actions)
        guard actionsResult == 0 else {
            Darwin.close(readFD); Darwin.close(writeFD)
            throw launchError(actionsResult)
        }
        defer { posix_spawn_file_actions_destroy(&actions) }
        var attributes: posix_spawnattr_t?
        let attributesResult = posix_spawnattr_init(&attributes)
        guard attributesResult == 0 else {
            Darwin.close(readFD); Darwin.close(writeFD)
            throw launchError(attributesResult)
        }
        defer { posix_spawnattr_destroy(&attributes) }
        let actionResults = [
            posix_spawn_file_actions_adddup2(&actions, writeFD, STDOUT_FILENO),
            posix_spawn_file_actions_adddup2(&actions, writeFD, STDERR_FILENO),
            posix_spawn_file_actions_addclose(&actions, readFD),
            posix_spawn_file_actions_addclose(&actions, writeFD),
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)),
            posix_spawnattr_setpgroup(&attributes, 0)
        ]
        if let failure = actionResults.first(where: { $0 != 0 }) {
            Darwin.close(readFD); Darwin.close(writeFD)
            throw launchError(failure)
        }

        let argumentStorage = ([executable.path] + arguments).map { strdup($0) }
        let values = (environment ?? ProcessInfo.processInfo.environment).map { "\($0.key)=\($0.value)" }.sorted()
        let environmentStorage = values.map { strdup($0) }
        defer {
            argumentStorage.forEach { free($0) }
            environmentStorage.forEach { free($0) }
        }
        guard !argumentStorage.contains(where: { $0 == nil }), !environmentStorage.contains(where: { $0 == nil }) else {
            Darwin.close(readFD); Darwin.close(writeFD)
            throw launchError(ENOMEM)
        }
        var argv = argumentStorage + [nil]
        var envp = environmentStorage + [nil]
        var pid: pid_t = 0
        let result = executable.path.withCString { path in
            argv.withUnsafeMutableBufferPointer { arguments in
                envp.withUnsafeMutableBufferPointer { environment in
                    posix_spawn(&pid, path, &actions, &attributes, arguments.baseAddress!, environment.baseAddress!)
                }
            }
        }
        Darwin.close(writeFD)
        guard result == 0 else {
            Darwin.close(readFD)
            throw launchError(result)
        }
        return (pid, readFD)
    }

    private static func exitCode(_ status: Int32) -> Int32 {
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }

    private static func launchError(_ code: Int32) -> BenchError {
        .message("Could not start benchmark process: " + String(cString: strerror(code)))
    }
}
