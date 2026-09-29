import Foundation
import CryptoKit
import S2TCore

@MainActor final class BenchmarkFeed: ObservableObject {
    @Published private(set) var snapshot: ArtificialAnalysisSnapshot?
    @Published private(set) var loading = false
    @Published private(set) var message = "Reference data · " + BenchmarkCatalog.checkedAt
    private var fingerprint = ""
    private var revision = UUID()
    private var lastAttempt: Date?
    private let publicClient: ArtificialAnalysisPublicClient
    private let client: ArtificialAnalysisClient
    private let cacheURL: URL?
    private struct Cache: Codable { let fingerprint: String; let snapshot: ArtificialAnalysisSnapshot }

    init(preview: Bool, client: ArtificialAnalysisClient = .init(), publicClient: ArtificialAnalysisPublicClient = .init()) {
        self.client = client
        self.publicClient = publicClient
        cacheURL = preview ? nil : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("S2T/benchmarks-v3.json")
    }
    func refresh(key: String, force: Bool = false) async {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = key.isEmpty ? "public" : SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        if hash != fingerprint {
            revision = UUID(); fingerprint = hash; loading = false; lastAttempt = nil; snapshot = nil
            if !hash.isEmpty, let cacheURL, let data = try? Data(contentsOf: cacheURL), data.count < 30_000_000,
               let cache = try? JSONDecoder().decode(Cache.self, from: data), cache.fingerprint == hash {
                snapshot = cache.snapshot
            }
        }
        guard !loading else { return }
        if !force, let date = snapshot?.fetchedAt, Date().timeIntervalSince(date) < 6 * 3600 {
            message = status; return
        }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < 60 { return }
        loading = true; lastAttempt = Date()
        let current = revision
        defer { if revision == current { loading = false } }
        do {
            let result = try await (key.isEmpty ? publicClient.fetch() : client.fetch(key: key))
            guard !Task.isCancelled, current == revision else { return }
            snapshot = result; message = status
            if let cacheURL, let data = try? JSONEncoder().encode(Cache(fingerprint: hash, snapshot: result)) {
                try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cacheURL, options: [.atomic])
            }
        } catch {
            guard !Task.isCancelled, current == revision else { return }
            message = (snapshot == nil ? "Reference data · " : "Saved data · ") +
                ((error as? ArtificialAnalysisError)?.localizedDescription ?? "Couldn't refresh Artificial Analysis.")
        }
    }
    private var status: String {
        guard let snapshot else { return message }
        let time = snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)
        return "Updated \(time)" + (snapshot.tier == "public" ? " · Public benchmark table" : snapshot.tier == "commercial" ? "" : " · Model-level TPS; host not identified.")
    }
    func status(for task: String) -> String {
        if let snapshot, !snapshot.models.contains(where: { $0.task == task }) {
            return "Reference data · " + BenchmarkCatalog.checkedAt + " · No live data for this task."
        }
        return message
    }
    func models(local: [LocalModel]) -> [BenchmarkModel] {
        let reference = BenchmarkCatalog.models(local: local)
        guard let snapshot else { return reference }
        let liveTasks = Set(snapshot.models.map(\.task))
        return snapshot.models + reference.filter { model in
            if model.provider == "Local" {
                return !liveTasks.contains(model.task) || model.task != "text" || snapshot.indexVersion == 4.3
            }
            return !liveTasks.contains(model.task)
        }
    }
}
