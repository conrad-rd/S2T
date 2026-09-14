public enum ActivationAction: Equatable, Sendable {
    case none, start, stop, toggle, cancel
}

public struct ActivationGesture {
    public static let tapThreshold = 0.24
    private struct Press {
        let time: Double
        let listening: Bool
        let hold: Bool
        let tap: Bool
        var started: Bool { hold && !listening }
    }
    private var current: Press?
    public init() {}
    public mutating func press(at time: Double, listening: Bool, hold: Bool, tap: Bool) -> ActivationAction {
        guard current == nil, hold || tap else { return .none }
        current = Press(time: time, listening: listening, hold: hold, tap: tap)
        return hold && !listening ? .start : .none
    }
    public mutating func release(at time: Double) -> ActivationAction {
        guard let press = current else { return .none }
        current = nil
        let short = time - press.time < Self.tapThreshold
        if press.started { return short && press.tap ? .none : .stop }
        if press.listening { return (short && press.tap) || press.hold ? .stop : .none }
        return short && press.tap ? .toggle : .none
    }
    public mutating func interrupt() -> ActivationAction {
        let result: ActivationAction = current?.started == true ? .cancel : .none
        current = nil
        return result
    }
}

public struct ShortcutKey: Codable, Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: UInt64
    public let name: String
    public init(keyCode: UInt16, modifiers: UInt64, name: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.name = name
    }
    public static let rightCommand = ShortcutKey(keyCode: 54, modifiers: 0, name: "Right Command")
    public func matchesBinding(_ other: ShortcutKey) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
    public static let function = ShortcutKey(keyCode: 63, modifiers: 0, name: "Fn")
    public var displayName: String {
        var prefix = ""
        for (mask, symbol): (UInt64, String) in [(1 << 18, "⌃"), (1 << 19, "⌥"), (1 << 17, "⇧"), (1 << 20, "⌘"), (1 << 23, "Fn ")] {
            if modifiers & mask != 0 { prefix += symbol }
        }
        return prefix + name
    }
}
