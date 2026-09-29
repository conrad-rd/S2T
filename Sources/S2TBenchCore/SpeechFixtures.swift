import Foundation

public struct SpeechFixture: Codable, Sendable {
    public let name: String
    public let text: String
    public let seconds: Double
    public let file: String
    public let maxWER: Double
    public let bytes: Int
    public let sha256: String

    public init(name: String, text: String, seconds: Double, file: String, maxWER: Double, bytes: Int, sha256: String) {
        self.name = name
        self.text = text
        self.seconds = seconds
        self.file = file
        self.maxWER = maxWER
        self.bytes = bytes
        self.sha256 = sha256
    }
}

public struct SpeechFixtureManifest: Codable, Sendable {
    public let schema: Int
    public let generator: [String: String]
    public let cases: [SpeechFixture]

    public init(schema: Int = 2, generator: [String: String], cases: [SpeechFixture]) {
        self.schema = schema
        self.generator = generator
        self.cases = cases
    }
}

public struct SpeechFixtureWorkload: Sendable {
    public let manifest: SpeechFixtureManifest
    public let manifestSHA256: String
    public let audioSHA256: String
    private let audio: [String: Data]

    public static func load(from directory: URL) throws -> Self {
        let manifestURL = directory.appendingPathComponent("speech.json")
        let manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        guard manifestData.count <= 1_000_000 else { throw BenchError.message("Speech fixture manifest exceeds 1 MB.") }
        let manifest = try JSONDecoder().decode(SpeechFixtureManifest.self, from: manifestData)
        guard manifest.schema == 2, !manifest.cases.isEmpty else { throw BenchError.message("Unsupported or empty speech fixture manifest.") }
        guard Set(manifest.cases.map(\.name)).count == manifest.cases.count,
              Set(manifest.cases.map(\.file)).count == manifest.cases.count else {
            throw BenchError.message("Speech fixture names and files must be unique.")
        }
        var audio: [String: Data] = [:]
        for fixture in manifest.cases {
            guard !fixture.name.isEmpty, !fixture.text.isEmpty, fixture.seconds.isFinite, fixture.seconds > 0,
                  fixture.maxWER.isFinite, (0...1).contains(fixture.maxWER), fixture.bytes > 0,
                  fixture.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                  URL(fileURLWithPath: fixture.file).lastPathComponent == fixture.file,
                  !fixture.file.contains("/"), !fixture.file.contains("\\") else {
                throw BenchError.message("Invalid speech fixture metadata for \(fixture.name).")
            }
            let data = try Data(contentsOf: directory.appendingPathComponent(fixture.file), options: .mappedIfSafe)
            guard data.count == fixture.bytes, BenchEndpoint.fingerprint(data) == fixture.sha256 else {
                throw BenchError.message("Speech fixture bytes do not match the manifest: \(fixture.file).")
            }
            audio[fixture.file] = data
        }
        let audioIdentity = manifest.cases.sorted { $0.file < $1.file }
            .map { "\($0.file)\u{0}\($0.bytes)\u{0}\($0.sha256)\n" }.joined()
        return Self(manifest: manifest, manifestSHA256: BenchEndpoint.fingerprint(manifestData),
            audioSHA256: BenchEndpoint.fingerprint(audioIdentity), audio: audio)
    }

    public func data(for fixture: SpeechFixture) throws -> Data {
        guard let data = audio[fixture.file] else { throw BenchError.message("Missing speech fixture: \(fixture.file).") }
        return data
    }

    private init(manifest: SpeechFixtureManifest, manifestSHA256: String, audioSHA256: String, audio: [String: Data]) {
        self.manifest = manifest
        self.manifestSHA256 = manifestSHA256
        self.audioSHA256 = audioSHA256
        self.audio = audio
    }
}
