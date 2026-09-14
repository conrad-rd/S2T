import AppKit
import S2TCore

@MainActor enum ContourFrameProbe {
    static func run() throws {
        let display = GlowDisplay(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 32,
            topLeft: CGRect(x: 0, y: 950, width: 660, height: 32),
            topRight: CGRect(x: 852, y: 950, width: 660, height: 32))
        let notch = TopGlowLayout(display: display)
        let input = InputOutlineBackdrop(rect: CGRect(x: 116, y: 116, width: 560, height: 72), cornerRadius: 36)
        let bands = (0..<30).map { frame in
            (0..<7).map { band in 0.2 + 0.5 * abs(sin(Double(frame) * 0.12 + Double(band))) }
        }
        for name in ["notch", "input"] {
          for animated in [false, true] {
            _ = name == "notch"
                ? TopGlow.radiusMap(layout: notch, energy: 0.4, size: notch.frame.size, expansion: 0.3)
                : input.mask(size: CGSize(width: 792, height: 304), expansion: 0.3)
            let start = ProcessInfo.processInfo.systemUptime
            for (index, spectrum) in bands.enumerated() {
                let expansion = animated ? 0.3 + 1.7 * Double(index) / 29 : 1
                let distortion = GlowDistortion(bands: spectrum)
                let image = name == "notch"
                    ? TopGlow.radiusMap(layout: notch, energy: 0.4, size: notch.frame.size, distortion: distortion, expansion: expansion)
                    : input.mask(size: CGSize(width: 792, height: 304), distortion: distortion, expansion: expansion)
                guard image != nil else { throw NSError(domain: "ContourFrameProbe", code: 1) }
            }
            let duration = (ProcessInfo.processInfo.systemUptime - start) * 1000 / Double(bands.count)
            print("\(name) \(animated ? "speech expansion" : "baseline") native mask, 30 changing synthetic frames: \(String(format: "%.2f", duration)) ms/frame")
          }
        }
    }
}
