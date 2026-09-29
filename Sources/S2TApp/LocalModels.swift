import AppKit
import CryptoKit
import S2TCore

@MainActor final class LocalModels: ObservableObject {
    static let managedEndpoint = "http://127.0.0.1/s2t-managed"
    @Published private(set) var message = "Models run on this Mac after installation."
    @Published private(set) var installing: String?
    @Published private(set) var isRepairing = false
    @Published private(set) var installed = Set<String>()
    @Published private(set) var catalog: [LocalModel]
    /// Bytes on disk for each completed S2T download.
    @Published private(set) var diskUsage: [String: Int64] = [:]
    /// Model folders that exist without a completed installation marker, with their partial size.
    @Published private(set) var partial: [String: Int64] = [:]
    /// Everything under the S2T local-model folder, including the runtime and download caches.
    @Published private(set) var totalBytes: Int64 = 0
    /// Bytes downloaded so far for the model in `installing`; nil while the runtime is being prepared.
    @Published private(set) var downloadedBytes: Int64?
    let root: URL
    private let resources: URL
    private let preview: Bool
    /// Preview instances only touch files when a verification fixture root was supplied.
    private let ownsFiles: Bool
    private var storageScan: Task<Void, Never>?
    /// Removal moves downloads to the Trash; verification substitutes deletion inside its temporary fixture.
    var discard: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    private var worker: Process?
    private var endpoint: String?
    private var startup: Task<String, Error>?
    private var startupGeneration = 0
    private var installation: Process?
    private var task: Task<Void, Never>?
    private var retiringWorker: Task<Void, Never>?

    init(preview: Bool = false, resources: URL? = nil, root: URL? = nil, nativePreviewModels: [LocalModel] = []) {
        self.preview = preview
        ownsFiles = !preview || root != nil
        self.resources = resources ?? Bundle.main.resourceURL!.appendingPathComponent("LocalModels")
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("S2T/LocalModels")
        catalog = ((try? LocalModel.read(from: self.resources.appendingPathComponent("catalog.json"))) ?? []) + (preview ? nativePreviewModels : [])
        if !preview {
            refreshInstalled()
            Task { await refreshNativeModels() }
        }
    }

    var downloadedModels: [LocalModel] { catalog.filter { !$0.isNative && installed.contains($0.id) } }
    var systemModels: [LocalModel] { catalog.filter { $0.isNative && installed.contains($0.id) } }
    var partialModels: [LocalModel] { catalog.filter { partial[$0.id] != nil && $0.id != installing } }

    /// One-line summary for the Models page, separating S2T downloads from languages macOS already has.
    var summary: String {
        if let installing, let model = catalog.first(where: { $0.id == installing }) { return "Downloading " + model.name }
        var parts: [String] = []
        if !downloadedModels.isEmpty { parts.append("\(downloadedModels.count) downloaded") }
        if !systemModels.isEmpty { parts.append("\(systemModels.count) macOS " + (systemModels.count == 1 ? "language" : "languages")) }
        return parts.isEmpty ? "None installed" : parts.joined(separator: " · ")
    }

    nonisolated static func directorySize(_ url: URL) -> Int64 {
        guard let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in items {
            guard let values = try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Measures downloads off the main thread so the settings page can show real sizes and unfinished downloads.
    func refreshStorage() {
        guard ownsFiles else { return }
        storageScan?.cancel()
        let root = root
        let models = catalog.filter { !$0.isNative }.map { ($0.id, $0.revision) }
        storageScan = Task {
            let result = await Task.detached(priority: .utility) { () -> (complete: [String: Int64], partial: [String: Int64], total: Int64) in
                var complete: [String: Int64] = [:], partial: [String: Int64] = [:]
                for (id, revision) in models {
                    let directory = root.appendingPathComponent("models/" + id)
                    let download = root.appendingPathComponent("downloads/" + id)
                    if FileManager.default.fileExists(atPath: download.path) { partial[id] = Self.directorySize(download) }
                    guard FileManager.default.fileExists(atPath: directory.path) else { continue }
                    let size = Self.directorySize(directory)
                    let marker = try? JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("installed.json"))) as? [String: String]
                    if marker?["revision"] == revision { complete[id] = size } else { partial[id] = size }
                }
                return (complete, partial, Self.directorySize(root))
            }.value
            guard !Task.isCancelled else { return }
            diskUsage = result.complete
            partial = result.partial
            totalBytes = result.total
        }
    }

    /// Moves a downloaded model to the Trash. Apple Speech languages stay under macOS management.
    func remove(_ model: LocalModel) throws {
        guard ownsFiles, !isRepairing, !model.isNative, installing != model.id, catalog.contains(model) else { return }
        cancelInference()
        let directory = root.appendingPathComponent("models/" + model.id)
        if FileManager.default.fileExists(atPath: directory.path) {
            try discard(directory)
        }
        let download = root.appendingPathComponent("downloads/" + model.id)
        if FileManager.default.fileExists(atPath: download.path) { try discard(download) }
        refreshInstalled()
        message = model.name + " moved to the Trash."
    }

    func refreshNativeModels() async {
        guard !preview, #available(macOS 26, *) else { return }
        let available = await NativeSpeechModels.catalog()
        catalog = catalog.filter { !$0.isNative } + available.models
        installed = installed.filter { !($0.hasPrefix("apple-speech-")) }.union(available.installed)
    }

    var supported: Bool {
        #if arch(arm64)
        if #available(macOS 26, *) { return true }
        return false
        #else
        return false
        #endif
    }

    func memoryFits(_ model: LocalModel) -> Bool {
        Double(ProcessInfo.processInfo.physicalMemory) >= model.memoryGB * 1_000_000_000
    }

    func refreshInstalled() {
        for model in catalog where ownsFiles && !model.isNative && installing != model.id {
            let directory = root.appendingPathComponent("models/" + model.id)
            let previous = root.appendingPathComponent("models/" + model.id + ".previous")
            if !FileManager.default.fileExists(atPath: directory.path), FileManager.default.fileExists(atPath: previous.path) {
                do { try FileManager.default.moveItem(at: previous, to: directory) }
                catch { message = "A previous model download could not be restored. Retry Repair in Local models." }
            }
        }
        installed = installed.filter { $0.hasPrefix("apple-speech-") }.union(Set(catalog.filter {
            guard !$0.isNative else { return false }
            let marker = root.appendingPathComponent("models/\($0.id)/installed.json")
            guard let data = try? Data(contentsOf: marker),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return false }
            return record["revision"] == $0.revision
        }.map(\.id)))
        refreshStorage()
    }

    func repair(_ model: LocalModel) {
        guard installing == nil, !preview, supported, catalog.contains(model), !model.isNative else { return }
        isRepairing = true
        cancelInference()
        install(model)
    }

    func install(_ model: LocalModel) {
        guard !preview, installing == nil, catalog.contains(model) else { return }
        if model.isNative {
            guard #available(macOS 26, *) else { return }
            installing = model.id
            message = "Downloading Apple’s language model…"
            task = Task {
                defer { installing = nil }
                do {
                    try await NativeSpeechModels.install(model)
                    try Task.checkCancellation()
                    await refreshNativeModels()
                    message = "Apple Speech is ready. Choose Use to enable it."
                } catch { message = Task.isCancelled ? "Download paused. Install again to resume." : error.localizedDescription }
            }
            return
        }
        guard supported else { return }
        installing = model.id
        message = "Preparing download for \(model.name)…"
        task = Task {
            defer { installing = nil; installation = nil; isRepairing = false; downloadedBytes = nil; refreshInstalled() }
            do {
                await retiringWorker?.value
                try Task.checkCancellation()
                try await prepareRuntime()
                try Task.checkCancellation()
                message = "Downloading \(model.name), about \(model.diskGB.formatted()) GB. You can keep using S2T."
                downloadedBytes = 0
                let directory = root.appendingPathComponent("downloads/" + model.id)
                let meter = Task {
                    while !Task.isCancelled {
                        let size = await Task.detached(priority: .utility) { Self.directorySize(directory) }.value
                        if !Task.isCancelled, installing == model.id { downloadedBytes = size }
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
                defer { meter.cancel() }
                try await command(python, [resources.appendingPathComponent("worker.py").path, "install", "--root", root.path, "--model", model.id])
                try Task.checkCancellation()
                refreshInstalled()
                message = "\(model.name) installed. Choose Use to enable it."
            } catch is CancellationError { message = "Download paused. Install again to resume." }
            catch {
                message = Task.isCancelled ? "Download paused. Install again to resume." : "Installation failed. \(error.localizedDescription)"
            }
        }
    }

    func cancelInstall() {
        task?.cancel()
        installation?.terminate()
    }

    private var python: URL { root.appendingPathComponent("runtime/bin/python3") }

    private func prepareRuntime() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let ready = root.appendingPathComponent("runtime/ready-v3")
        if !isRepairing, FileManager.default.fileExists(atPath: ready.path) { return }
        if FileManager.default.fileExists(atPath: ready.path) { try FileManager.default.removeItem(at: ready) }
        message = "Installing the local runtime. This first download includes Python and MLX."
        let uv = root.appendingPathComponent("uv-aarch64-apple-darwin/uv")
        if !FileManager.default.isExecutableFile(atPath: uv.path) {
            let url = URL(string: "https://github.com/astral-sh/uv/releases/download/0.12.15/uv-aarch64-apple-darwin.tar.gz")!
            let (file, response) = try await URLSession.shared.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ServiceError.message("The runtime download failed.") }
            let archive = root.appendingPathComponent("uv.tar.gz")
            try await Task.detached(priority: .utility) {
                let data = try Data(contentsOf: file)
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard hash == "dc304b9ed1b24174572290fba60ac3f6fe63c73a671f0439e62a91375841964d" else {
                    throw ServiceError.message("The runtime download did not pass its integrity check.")
                }
                try data.write(to: archive, options: .atomic)
            }.value
            try await command(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", archive.path, "-C", root.path])
        }
        try await command(uv, ["venv", "--python", "3.12.14", "--managed-python", "--allow-existing", root.appendingPathComponent("runtime").path])
        var packages = ["pip", "install", "--python", python.path, "--requirement", resources.appendingPathComponent("requirements.txt").path]
        if isRepairing { packages.append("--reinstall") }
        try await command(uv, packages)
        try Data("ready".utf8).write(to: ready, options: .atomic)
    }

    private func command(_ executable: URL, _ arguments: [String]) async throws {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.qualityOfService = .utility
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        installation = process
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { process in
                    if process.terminationStatus == 0 { continuation.resume() }
                    else { continuation.resume(throwing: ServiceError.message("The local installer exited with code \(process.terminationStatus). Check internet access and free disk space, then retry.")) }
                }
                do {
                    try Task.checkCancellation()
                    try process.run()
                    if Task.isCancelled, process.isRunning { process.terminate() }
                } catch { continuation.resume(throwing: error) }
            }
            try Task.checkCancellation()
        } onCancel: { if process.isRunning { process.terminate() } }
    }

    private var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["UV_PYTHON_INSTALL_DIR"] = root.appendingPathComponent("python").path
        env["UV_CACHE_DIR"] = root.appendingPathComponent("uv-cache").path
        env["HF_HOME"] = root.appendingPathComponent("cache").path
        env["PYTHONUNBUFFERED"] = "1"
        env["DO_NOT_TRACK"] = "1"
        return env
    }

    func url(for model: String, path: String) async throws -> String {
        guard !isRepairing, installing != model else { throw ServiceError.message("This local model is being installed or repaired. Wait for installation to finish.") }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("runtime/ready-v3").path) else {
            throw ServiceError.message("The local runtime is incomplete. Repair the model in Settings → Models → Local models.")
        }
        guard !preview, installed.contains(model) else { throw ServiceError.message("Install the selected model in Settings → Models → Local models first.") }
        guard let entry = catalog.first(where: { $0.id == model }), memoryFits(entry) else {
            throw ServiceError.message("This model exceeds this Mac's memory budget. Choose a smaller model in Settings → Local.")
        }
        if let startup { return try await startup.value + path }
        startupGeneration += 1
        let generation = startupGeneration
        let task = Task { try await startWorker() }
        startup = task
        defer { if startupGeneration == generation { startup = nil } }
        return try await withTaskCancellationHandler { try await task.value + path } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.startupGeneration == generation else { return }
                self?.cancelInference()
            }
        }
    }

    private func startWorker() async throws -> String {
        await retiringWorker?.value
        try Task.checkCancellation()
        if worker?.isRunning == true, let endpoint { return endpoint }
        endpoint = nil
        let process = Process()
        var ready = false
        defer { if !ready, process.isRunning { process.terminate() } }
        process.executableURL = python
        process.arguments = [resources.appendingPathComponent("worker.py").path, "serve", "--root", root.path]
        process.environment = environment
        process.qualityOfService = .userInitiated
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        worker = process
        message = "Starting local inference…"
        let timeout = Task {
            try? await Task.sleep(for: .seconds(45))
            if !Task.isCancelled, process.isRunning { process.terminate() }
        }
        defer { timeout.cancel() }
        let data = try await Task.detached {
            var line = Data()
            while line.count < 8192 {
                let byte = try output.fileHandleForReading.read(upToCount: 1) ?? Data()
                guard !byte.isEmpty else { throw ServiceError.message("The local runtime stopped during startup. Reinstall the model to repair it.") }
                if byte == Data([10]) { return line }
                line.append(byte)
            }
            throw ServiceError.message("Invalid local runtime response.")
        }.value
        try Task.checkCancellation()
        guard worker === process else { throw CancellationError() }
        guard let info = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let value = info["endpoint"], let url = URL(string: value), url.host == "127.0.0.1" else {
            process.terminate()
            throw ServiceError.message("Invalid local runtime address.")
        }
        endpoint = value
        ready = true
        message = "Local runtime ready. Models unload after two idle minutes."
        return value
    }

    func use(_ model: LocalModel, state: AppState) {
        guard !isRepairing, installing != model.id, catalog.contains(model), installed.contains(model.id), memoryFits(model), !state.phase.busy, state.phase != .recording else { return }
        state.rememberCustomLocalEndpoint(for: model.category)
        state.setUsesCredits(false, for: model.category)
        if model.category == "speech" {
            state.localTranscriptionModel = model.id
            state.localTranscriptionURL = Self.managedEndpoint
            state.transcriptionProvider = .local
        } else if model.category == "text" {
            state.processingProvider = .local
            _ = state.saveProcessingModel(model.id, for: .local)
            state.localProcessingURL = Self.managedEndpoint
        }
        message = "\(model.name) selected for \(model.categoryTitle.lowercased())."
    }

    func cancelInference() {
        startupGeneration += 1
        startup?.cancel()
        startup = nil
        if let process = worker, process.isRunning {
            process.terminate()
            let previous = retiringWorker
            retiringWorker = Task.detached(priority: .utility) {
                await previous?.value
                let deadline = Date().addingTimeInterval(2)
                while process.isRunning && Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
            }
        }
        worker = nil
        endpoint = nil
    }

    func stop() {
        cancelInstall()
        cancelInference()
    }
}
