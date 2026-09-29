import Foundation
import S2TCore

struct ProviderProbeCodex: CodexServing {
    var fails = false
    func complete(instructions: String, prompt: String, model: String, executable: String, options: CodexOptions) async throws -> String {
        try await Task.sleep(nanoseconds: 100_000_000)
        if fails { throw ServiceError.message("Synthetic Codex failure") }
        return "Processed test"
    }
}
