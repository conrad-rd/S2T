import AppKit
import CryptoKit
import S2TCore

/// Draws each settings page from a never-shown preview window into PNG files for layout review.
/// Reads only the app's own view drawing, never screen pixels.
@MainActor enum SettingsPageRenderer {
    private struct Artifact: Codable {
        let file: String
        let bytes: Int
        let width: Int
        let height: Int
        let sha256: String
    }

    private struct Manifest: Codable {
        let schema: Int
        let created: Date
        let appVersion: String
        let appBuild: String
        let artifacts: [Artifact]

        init(created: Date, appVersion: String, appBuild: String, artifacts: [Artifact]) {
            schema = 1
            self.created = created
            self.appVersion = appVersion
            self.appBuild = appBuild
            self.artifacts = artifacts
        }
    }

    private enum RenderError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
    }

    static func run(directory: String) throws {
        let controller = AppearanceWindowController(state: AppState(preview: true), presentsWindows: false)
        let window = controller.prepare()
        defer { window.close() }
        let destination = URL(fileURLWithPath: directory).standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            let values = try destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw RenderError.message("Settings page destination must be a real directory.")
            }
        }
        let staging = parent.appendingPathComponent(".\(destination.lastPathComponent).rendering-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        var artifacts: [Artifact] = []
        var names = Set<String>()
        func render(_ name: String, includeTitlebar: Bool = false) throws {
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            guard !window.isVisible else { throw RenderError.message("Preview window became visible while rendering \(name).") }
            guard let content = window.contentView else { throw RenderError.message("Preview window has no content for \(name).") }
            guard names.insert(name).inserted else { throw RenderError.message("Duplicate settings page render: \(name).") }
            let drawing = includeTitlebar ? content.superview ?? content : content
            drawing.layoutSubtreeIfNeeded()
            guard drawing.bounds.width > 0, drawing.bounds.height > 0 else {
                throw RenderError.message("Settings page \(name) has empty bounds.")
            }
            guard let bitmap = drawing.bitmapImageRepForCachingDisplay(in: drawing.bounds) else {
                throw RenderError.message("Could not allocate a bitmap for settings page \(name).")
            }
            drawing.cacheDisplay(in: drawing.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]), !png.isEmpty else {
                throw RenderError.message("Could not encode settings page \(name) as PNG.")
            }
            let file = name + ".png"
            try png.write(to: staging.appendingPathComponent(file), options: .atomic)
            artifacts.append(Artifact(file: file, bytes: png.count, width: bitmap.pixelsWide,
                height: bitmap.pixelsHigh, sha256: SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()))
        }
        controller.showDashboard(); try render("dashboard")
        controller.showDictation(); try render("dictation")
        for page in [DictationNavigation.Page.prompt, .clipboard, .inputDetection, .advanced] {
            controller.dictationNavigation.page = page; try render("dictation-" + page.rawValue)
        }
        controller.dictationNavigation.page = nil
        controller.showModels(); try render("models")
        controller.modelsPane.navigation.showComparison(); try render("models-compare")
        controller.modelsPane.navigation.select(.local); try render("models-local")
        controller.modelsPane.navigation.showOverview()
        controller.showAPIKeys(); try render("keys")
        controller.showWriting(); try render("writing")
        controller.showMeetings(); try render("meetings")
        for (index, text) in ["A short example transcript.", "A longer example transcript wraps onto another line so the recordings list background can be reviewed around its rows and separators."].enumerated() {
            controller.state.recentRecordings.record(id: UUID(), text: text, appName: "Example editor", bundleID: nil,
                date: Date(timeIntervalSince1970: 1_790_400_000 + Double(index * 60)))
        }
        controller.showRecentRecordings(); try render("recent")
        for theme in ["light", "dark"] {
            controller.state.menuAppearance = theme
            controller.refresh()
            controller.showModels(); try render("models-\(theme)", includeTitlebar: true)
            controller.modelsPane.navigation.showComparison(); try render("models-compare-\(theme)", includeTitlebar: true)
            controller.modelsPane.navigation.showOverview()
            controller.showRecentRecordings(); try render("recent-\(theme)", includeTitlebar: true)
        }
        for (name, size) in [("default", AppearanceWindowController.contentSize), ("wide", NSSize(width: 1180, height: 720)), ("tall", NSSize(width: 900, height: 1000))] {
            window.setContentSize(size)
            controller.sidebar.onAppearance?()
            for theme in ["light", "dark"] {
                controller.state.menuAppearance = theme
                for mode in GlowAppearance.allCases {
                    controller.selectPreview(mode)
                    controller.preview.running = true
                    try render("appearance-\(mode.rawValue)-\(name)-\(theme)", includeTitlebar: true)
                }
            }
        }
        guard !artifacts.isEmpty else { throw RenderError.message("No settings pages were rendered.") }
        let manifest = Manifest(created: Date(), appVersion: BuildIdentity.version,
            appBuild: BuildIdentity.number, artifacts: artifacts.sorted { $0.file < $1.file })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        let previous = try ownedArtifacts(in: destination)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        }
        for artifact in artifacts {
            let output = destination.appendingPathComponent(artifact.file)
            if FileManager.default.fileExists(atPath: output.path), previous[artifact.file] == nil {
                throw RenderError.message("Refusing to replace unowned file \(artifact.file); choose a dedicated output directory.")
            }
        }
        for artifact in artifacts {
            let data = try Data(contentsOf: staging.appendingPathComponent(artifact.file), options: .mappedIfSafe)
            try data.write(to: destination.appendingPathComponent(artifact.file), options: .atomic)
        }
        let currentNames = Set(artifacts.map(\.file))
        for file in previous.keys where !currentNames.contains(file) {
            try FileManager.default.removeItem(at: destination.appendingPathComponent(file))
        }
        try manifestData.write(to: destination.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private static func ownedArtifacts(in directory: URL) throws -> [String: Artifact] {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return [:] }
        do {
            let values = try manifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw RenderError.message("Existing settings renderer manifest is not a regular file.")
            }
            let data = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(Manifest.self, from: data)
            guard manifest.schema == 1 else { throw RenderError.message("Existing settings renderer manifest has an unsupported schema.") }
            var owned: [String: Artifact] = [:]
            for artifact in manifest.artifacts {
                guard artifact.file.hasSuffix(".png"), URL(fileURLWithPath: artifact.file).lastPathComponent == artifact.file,
                      !artifact.file.contains("/"), !artifact.file.contains("\\"), artifact.bytes > 0,
                      artifact.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                      owned[artifact.file] == nil else {
                    throw RenderError.message("Existing settings renderer manifest contains an unsafe artifact.")
                }
                let fileURL = directory.appendingPathComponent(artifact.file)
                let fileValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                let bytes = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                guard fileValues.isRegularFile == true, fileValues.isSymbolicLink != true,
                      bytes.count == artifact.bytes, fingerprint(bytes) == artifact.sha256 else {
                    throw RenderError.message("Existing renderer-owned file no longer matches its manifest: \(artifact.file).")
                }
                owned[artifact.file] = artifact
            }
            return owned
        } catch let error as RenderError {
            throw error
        } catch {
            throw RenderError.message("Existing settings renderer manifest is invalid: \(error.localizedDescription)")
        }
    }

    private static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
