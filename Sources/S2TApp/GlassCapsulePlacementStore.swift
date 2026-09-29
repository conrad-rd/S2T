import AppKit
import S2TCore

@MainActor final class GlassCapsulePlacementStore {
    private let read: () -> Data?
    private let write: (Data) -> Void
    private var current: GlassCapsuleAnchor?

    init(read: @escaping () -> Data?, write: @escaping (Data) -> Void) {
        self.read = read
        self.write = write
    }

    convenience init(preview: Bool) {
        let key = "liquidGlassPlacement.v1"
        self.init(read: { preview ? nil : UserDefaults.standard.data(forKey: key) },
                  write: { if !preview { UserDefaults.standard.set($0, forKey: key) } })
    }

    var anchor: GlassCapsuleAnchor? {
        read().flatMap { try? JSONDecoder().decode(GlassCapsuleAnchor.self, from: $0) } ?? current
    }

    func save(_ anchor: GlassCapsuleAnchor) {
        guard let data = try? JSONEncoder().encode(anchor) else { return }
        current = anchor
        write(data)
    }

    static func identifier(for screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return screen.localizedName
        }
        if let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return number.stringValue
    }
}
