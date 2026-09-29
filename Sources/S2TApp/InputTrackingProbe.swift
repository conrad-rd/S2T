import AppKit
import ApplicationServices
import S2TCore

@MainActor enum InputTrackingProbe {
    static func run() throws {
        let pid: pid_t = 2_930_000
        let app = AXUIElementCreateApplication(pid)
        let elements = (0..<7).map { AXUIElementCreateApplication(pid + 1 + pid_t($0)) }
        var growth: CGFloat = 0
        var calls = 0
        var search = false
        var movingBoundary = false
        var boundaryReads = 0
        let roles = ["AXTextArea", "AXGroup", "AXGroup", "AXGroup", "AXButton", "AXButton", "AXWindow"]
        let parents = [1, 2, 3, 6, 3, 3, -1]
        let children = [[], [0], [1], [2, 4, 5], [], [], [3]]
        func bounds(_ id: Int) -> CGRect {
            switch id {
            case 0, 1, 2: return CGRect(x: 120, y: 416, width: 560, height: 28 + growth)
            case 3: return CGRect(x: 100, y: 400, width: 600, height: 60 + growth)
            case 4: return CGRect(x: 105, y: 415 + growth, width: 30, height: 30)
            case 5: return CGRect(x: 665, y: 415 + growth, width: 30, height: 30)
            default: return CGRect(x: 0, y: 0, width: 1200, height: 1000)
            }
        }
        let reader = FocusedInputReader(attribute: { element, name in
            calls += 1
            Thread.sleep(forTimeInterval: 0.0002)
            if CFEqual(element, app) {
                if name == kAXFocusedUIElementAttribute { return elements[0] }
                if name == kAXFocusedWindowAttribute { return elements[6] }
                return nil
            }
            guard let id = elements.firstIndex(where: { CFEqual(element, $0) }) else { return nil }
            switch name {
            case kAXRoleAttribute: return roles[id] as CFString
            case kAXSubroleAttribute: return (id == 3 && search ? "AXLandmarkSearch" : "") as CFString
            case kAXParentAttribute: return parents[id] >= 0 ? elements[parents[id]] : nil
            case kAXPositionAttribute:
                var point = bounds(id).origin
                return AXValueCreate(.cgPoint, &point)
            case kAXSizeAttribute:
                var size = bounds(id).size
                if id == 3 {
                    boundaryReads += 1
                    if movingBoundary && boundaryReads > 1 { size.height += 24 }
                }
                return AXValueCreate(.cgSize, &size)
            default: return nil
            }
        }, children: { element in
            calls += 1
            Thread.sleep(forTimeInterval: 0.0002)
            return elements.firstIndex(where: { CFEqual(element, $0) }).map { children[$0].map { elements[$0] } }
        }, fallbackFocus: { _ in nil }, hitTest: { _, _ in nil }, applicationBundleID: { _ in "test.input-tracking" },
            enableAccessibility: { _ in })
        var elapsed = [Double]()
        var requestCounts = [Int]()
        for amount in [CGFloat(0), 24, 72, 160, 0] {
            growth = amount; calls = 0
            let started = CACurrentMediaTime()
            let target = reader.read(pid: pid)
            elapsed.append((CACurrentMediaTime() - started) * 1000)
            requestCounts.append(calls)
            try check(target == bounds(3), "Growing composer lost its full height: \(String(describing: target)), expected \(bounds(3))")
        }
        print(String(format: "Tracking fixture, five growth/shrink reads, 0.2 ms per metadata call: mean %.2f ms, max %.2f ms, mean %.1f calls",
            elapsed.reduce(0, +) / Double(elapsed.count), elapsed.max() ?? 0,
            Double(requestCounts.reduce(0, +)) / Double(requestCounts.count)))
        search = true
        for amount in [CGFloat(0), 24, 72, 160, 0] {
            growth = amount
            try check(reader.read(pid: pid) == bounds(3), "Search composer did not follow height changes")
            let radius: CGFloat = amount == 0 ? 30 : 16
            try check(reader.cornerRadius == radius, "Search composer radius \(reader.cornerRadius), expected \(radius) at growth \(amount)")
        }
        movingBoundary = true; boundaryReads = 0
        try check(reader.read(pid: pid) == nil, "A container resized during sampling but its obsolete height was accepted")
        print("PASS: growing and shrinking search composers keep measured rounded corners, restore capsule ends and reject mid-read container changes. Injected geometry only.")
    }

    private static func check(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "InputTracking", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
