import AppKit
import ApplicationServices
import S2TCore

/// Diagnoses Around Input targeting against a running app without focusing it.
/// `S2T --diagnose-input <pid>` prints the boundary chosen for every visible editor.
@MainActor enum InputLiveProbe {
    static func run(pid: pid_t, windowTitle: String? = nil, annotate: URL? = nil) async {
        let app = AXUIElementCreateApplication(pid)
        FocusedInputReader.enableApplicationAccessibility(app)
        try? await Task.sleep(nanoseconds: 400_000_000)
        let windows = FocusedInputReader.systemAttribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard let window = windows.first(where: { window in
            windowTitle.map { (FocusedInputReader.systemAttribute(window, kAXTitleAttribute) as? String ?? "").hasPrefix($0) } ?? true
        }) else {
            print("No window for \(pid)."); return
        }
        var queue = [window], editors = [AXUIElement](), scanned = 0
        while !queue.isEmpty, scanned < 20_000 {
            let node = queue.removeFirst(); scanned += 1
            let role = FocusedInputReader.systemAttribute(node, kAXRoleAttribute) as? String ?? ""
            let subrole = FocusedInputReader.systemAttribute(node, kAXSubroleAttribute) as? String ?? ""
            let editable = FocusedInputReader.systemAttribute(node, "AXEditable") as? Bool == true
            if InputOutlineGeometry.isInput(role: role, subrole: subrole, editable: editable) {
                let parent = FocusedInputReader.systemAttribute(node, kAXParentAttribute)
                let nested = parent.map { FocusedInputReader.systemAttribute($0 as! AXUIElement, "AXEditable") as? Bool == true } ?? false
                if !nested { editors.append(node); continue }
            }
            queue += FocusedInputReader.systemChildren(node) ?? []
        }
        InputSurfaceDetector.trace = { print("    · \($0)") }
        let estimates = FocusedInputService(measuresPixels: false), measured = FocusedInputService()
        var marks = [(InputOutlineTarget, NSColor)]()
        for editor in editors {
            let role = FocusedInputReader.systemAttribute(editor, kAXRoleAttribute) as? String ?? ""
            let destination = PromptDestination(pid: pid, window: window, field: editor, document: nil, tab: nil, selection: nil)
            print("\(role) \(describe(frame(editor)))")
            for (label, service) in [("accessibility", estimates), ("pixels", measured)] {
                let started = ProcessInfo.processInfo.systemUptime
                let result = await service.read(pid: pid, anchor: nil, pinned: destination)
                let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                guard let target = result.target else { print("  \(label): \(result)"); continue }
                let parts = target.contour.parts.map { part in
                    "\(describe(part.rect.offsetBy(dx: target.frame.minX, dy: target.frame.minY))) r\(Int(part.radius)) \(part.corners)"
                }
                let pixels = await service.usedPixels
                let fallback = label == "pixels" && !pixels ? " (fallback)" : ""
                print("  \(label)\(fallback) → \(parts.joined(separator: " | ")) \(target.cornerStyle) \(elapsed)ms")
                marks.append((target, label == "pixels" ? .systemGreen : .systemRed))
            }
        }
        if let annotate { await save(pid: pid, window: window, marks: marks, to: annotate) }
    }

    /// Writes the window with accessibility (red) and measured (green) boundaries drawn on top.
    private static func save(pid: pid_t, window: AXUIElement, marks: [(InputOutlineTarget, NSColor)], to url: URL) async {
        let bounds = frame(window)
        guard let shot = await InputSurfaceCapture().capture(pid: pid, window: bounds, region: bounds) else { print("Capture failed."); return }
        let b = shot.bitmap, scale = shot.scale
        var pixels = b.pixels
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: b.width, height: b.height, bitsPerComponent: 8,
                bytesPerRow: b.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            for (target, color) in marks {
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(color == .systemGreen ? 2 : 4)
                for part in target.contour.offsetBy(dx: target.frame.minX, dy: target.frame.minY).parts {
                    let rect = part.rect
                    let local = CGRect(x: (rect.minX - bounds.minX) * scale, y: CGFloat(b.height) - (rect.maxY - bounds.minY) * scale,
                                       width: rect.width * scale, height: rect.height * scale)
                    let radius = min(part.radius * scale, local.width / 2, local.height / 2)
                    context.addPath(CGPath(roundedRect: local, cornerWidth: radius, cornerHeight: radius, transform: nil))
                    context.strokePath()
                }
            }
            guard let image = context.makeImage(),
                  let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }

    private static func frame(_ node: AXUIElement) -> CGRect {
        var origin = CGPoint.zero, size = CGSize.zero
        if let value = FocusedInputReader.systemAttribute(node, kAXPositionAttribute) { AXValueGetValue(value as! AXValue, .cgPoint, &origin) }
        if let value = FocusedInputReader.systemAttribute(node, kAXSizeAttribute) { AXValueGetValue(value as! AXValue, .cgSize, &size) }
        return CGRect(origin: origin, size: size)
    }

    private static func describe(_ rect: CGRect) -> String {
        String(format: "(%.0f,%.0f %.0f×%.0f)", rect.minX, rect.minY, rect.width, rect.height)
    }
}
