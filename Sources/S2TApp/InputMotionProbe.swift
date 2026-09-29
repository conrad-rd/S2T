import AppKit
import ApplicationServices
import S2TCore

@MainActor enum InputMotionProbe {
    static func run() async throws {
        setbuf(stdout, nil)
        for alwaysMoving in [false, true] {
            let pid: pid_t = 2_970_001
            let app = AXUIElementCreateApplication(pid)
            let field = AXUIElementCreateApplication(pid + 1)
            var sizeReads = 0
            var height: CGFloat = 80
            var calls = 0
            let reader = FocusedInputReader(attribute: { node, name in
                calls += 1
                Thread.sleep(forTimeInterval: 0.0002)
                if CFEqual(node, app) {
                    return name == kAXFocusedUIElementAttribute ? field : nil
                }
                guard CFEqual(node, field) else { return nil }
                switch name {
                case kAXRoleAttribute: return "AXTextArea" as CFString
                case kAXFocusedAttribute: return kCFBooleanTrue
                case kAXPositionAttribute:
                    var point = CGPoint(x: 100, y: 200)
                    return AXValueCreate(.cgPoint, &point)
                case kAXSizeAttribute:
                    sizeReads += 1
                    if sizeReads == 2 || alwaysMoving && sizeReads.isMultiple(of: 2) { height += 20 }
                    var size = CGSize(width: 600, height: height)
                    return AXValueCreate(.cgSize, &size)
                default: return nil
                }
            }, children: { _ in [] }, fallbackFocus: { _ in nil }, hitTest: { _, _ in nil },
                applicationBundleID: { _ in "test.input-motion" }, enableAccessibility: { _ in })
            let service = FocusedInputService(reader: reader, measuresPixels: false)
            let start = CACurrentMediaTime()
            let result = await service.read(pid: pid, anchor: nil)
            let elapsed = (CACurrentMediaTime() - start) * 1000
            print(String(format: "%@: %.2f ms, %d metadata calls, %d geometry samples",
                alwaysMoving ? "Continuously changing geometry" : "One resize during sampling", elapsed, calls, sizeReads))
            if alwaysMoving {
                guard case .geometryChanging = result else { throw failure("Motion was treated as a missing field") }
            } else {
                guard result.target?.frame == CGRect(x: 100, y: 200, width: 600, height: 100) else {
                    throw failure("Motion retry accepted stale geometry or lost the current input")
                }
            }
            guard elapsed < 40 else { throw failure("Geometry changes entered the unavailable-input retry delay") }
            guard sizeReads == 4 else { throw failure("Motion recovery exceeded its two-read budget") }
        }
        print("PASS: changing input geometry retries promptly, remains bounded, and never publishes stale bounds.")
    }

    private static func failure(_ text: String) -> NSError {
        NSError(domain: "InputMotion", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
