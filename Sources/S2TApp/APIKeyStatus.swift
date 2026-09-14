import Foundation

enum APIKeyStatus: Equatable {
    case checking, accepted, issue(String)

    var message: String {
        switch self {
        case .checking: return "Saved in Keychain. Checking key…"
        case .accepted: return "Saved in Keychain. Key accepted."
        case .issue(let message): return message
        }
    }

    var needsAttention: Bool {
        if case .issue = self { return true }
        return false
    }
}
