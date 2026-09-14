public struct MicrophoneCandidate: Equatable, Sendable {
    public enum Transport: Sendable { case builtIn, bluetooth, other }
    public let id: String
    public let transport: Transport

    public init(id: String, transport: Transport) {
        self.id = id
        self.transport = transport
    }
}

public enum MicrophoneSelection {
    public static func resolve(selection: String, defaultID: String?, devices: [MicrophoneCandidate]) -> String? {
        if !selection.isEmpty {
            return devices.first { $0.id == selection }?.id
        }
        if let builtIn = devices.first(where: { $0.transport == .builtIn }) {
            return builtIn.id
        }
        if let preferred = devices.first(where: { $0.id == defaultID && $0.transport != .bluetooth }) {
            return preferred.id
        }
        return devices.first { $0.transport != .bluetooth }?.id
    }
}
