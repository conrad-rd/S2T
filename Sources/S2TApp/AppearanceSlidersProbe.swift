import AppKit
import SwiftUI
import S2TCore

@MainActor enum AppearanceSlidersProbe {
    static func run() throws {
        let state = AppState(preview: true)
        let saved = (state.glowWidth, state.glowMinimum, state.glowMaximum, state.glowAppearance)
        defer { state.glowWidth = saved.0; state.glowMinimum = saved.1; state.glowMaximum = saved.2; state.glowAppearance = saved.3 }
        let controller = MenuBarController(state: state)
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        controller.menuNeedsUpdate(controller.menu)
        try AppearanceWindowProbe.verifyModeControls(state: state, menu: controller)
        let window = controller.appearanceWindow
        window.prepare()
        defer { window.window?.close() }
        let originalTuning = state.glowTuning
        func slide(_ id: String, _ value: Double) throws {
            guard let control = AppearanceControl.allCases.first(where: { $0.id == id }),
                  let slider = window.sliders[control] else { throw failure("Missing native slider") }
            slider.doubleValue = value
            slider.sendAction(slider.action, to: slider.target)
        }
        try slide("glow.maximum", 5)
        guard state.glowMaximum == 5, AppState(preview: true).glowMaximum == 5,
              window.sliders[.maximum]?.maxValue == 5 else { throw failure("Maximum did not reach and persist 500 percent") }
        let root = ProgressiveBackdropView(frame: CGRect(x: 0, y: 0, width: 800, height: GlowProfile.extent * 2.5))
        var loud = GlowProfile(energy: 1, heights: [3], sweepStrength: 1.3)
        loud.response = .init(maximum: 5)
        root.profile = loud
        guard let filter = root.layer?.sublayers?.first?.filters?.first as? NSObject,
              abs((filter.value(forKey: "inputRadius") as? Double ?? 0) - 22.5) < 0.000001 else { throw failure("The 500 percent setting did not reach the bounded blur maximum") }
        let originalField = CGRect(x: 700, y: 500, width: 400, height: 64)
        let expanded = InputOutlineGeometry(field: originalField, paddingScale: 2.5,
            displayFrame: CGRect(x: 0, y: 0, width: 1800, height: 1169))
        guard expanded.windowFrame == CGRect(x: 0, y: 0, width: 1800, height: 1169),
              expanded.outlineRect == CGRect(x: 700, y: 605, width: 400, height: 64) else { throw failure("500 percent padding moved the input or exceeded the display") }
        try slide("glow.width", 0.5)
        try slide("glow.maximum", 1.2)
        try slide("glow.minimum", 0.8)
        guard AppState(preview: true).glowResponseSettings == GlowResponseSettings(width: 0.5, minimum: 0.8, maximum: 1.2, tuning: originalTuning) else { throw failure("Slider values did not persist") }
        try slide("glow.minimum", 1.5)
        guard state.glowMaximum == 1.5 else { throw failure("Minimum passed maximum") }
        try slide("glow.maximum", 0.4)
        guard state.glowMinimum == 0.4 else { throw failure("Maximum passed minimum") }
        let size = CGSize(width: 800, height: GlowProfile.extent)
        var profile = GlowProfile(energy: 1, heights: [3], sweepStrength: 1.3)
        profile.response.width = 0.5
        guard let map = GlowBackdrop.mask(profile: profile, size: size),
              let bitmap = map.representations.first as? NSBitmapImageRep,
              bitmap.colorAt(x: 80, y: bitmap.pixelsHigh - 10)?.alphaComponent == 0,
              (bitmap.colorAt(x: 400, y: bitmap.pixelsHigh - 10)?.alphaComponent ?? 0) > 0 else { throw failure("Width did not narrow the native field") }
        let renderer = ImageRenderer(content: BottomGlow(level: 1, strength: 1.3, phase: .recording,
            timeOverride: 1, reduceMotionOverride: true, reduceTransparencyOverride: true,
            response: .init(width: 0.5, minimum: 0.3, maximum: 2)).frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let color = renderer.cgImage else { throw failure("Width color fixture failed") }
        let rendered = NSBitmapImageRep(cgImage: color)
        guard rendered.colorAt(x: 80, y: rendered.pixelsHigh - 10)?.alphaComponent == 0,
              (rendered.colorAt(x: 400, y: rendered.pixelsHigh - 10)?.alphaComponent ?? 0) > 0 else { throw failure("Canvas width differs from blur width") }
        let display = GlowDisplay(frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), safeTop: 38,
            topLeft: CGRect(x: 0, y: 1131, width: 790, height: 38), topRight: CGRect(x: 1010, y: 1131, width: 790, height: 38))
        let notch = TopGlowLayout(display: display)
        guard ChromaAppearance.widthCoverage(notch.notch!.minX, geometry: .notch(notch), size: notch.frame.size, width: 0.25) == 1,
              ChromaAppearance.widthCoverage(0, geometry: .notch(notch), size: notch.frame.size, width: 0.25) == 0,
              ChromaAppearance.widthCoverage(0, geometry: .input(.zero, 0), size: size, width: 0.25) == 1 else { throw failure("Width changed housing or input geometry") }
        print("PASS: native Appearance sliders, mode visibility, saved values, ordered minimum/maximum, narrowed native blur, fixed notch housing, and unchanged input width.")
    }
    private static func failure(_ text: String) -> NSError { NSError(domain: "AppearanceSlidersProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
