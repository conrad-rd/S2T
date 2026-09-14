import Foundation
import S2TCore

struct ProviderProbeCodex: CodexServing {
    var fails = false
    func complete(instructions: String, prompt: String, model: String, images: [Data], executable: String, options: CodexOptions) async throws -> String {
        try await Task.sleep(nanoseconds: 100_000_000)
        if fails { throw ServiceError.message("Synthetic Codex failure") }
        if images.isEmpty { return "Processed test" }
        let data = try JSONSerialization.data(withJSONObject: ["descriptions": Array(repeating: "A blue button beside a gray button.", count: images.count)])
        return String(decoding: data, as: UTF8.self)
    }
}
