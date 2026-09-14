import AppKit
import SwiftUI
import S2TCore

@MainActor enum SpeechGlowProbe {
    static func run() throws {
        func bands(_ frequency: Double) -> [Double] {
            var spectrum = AudioSpectrum(sampleRate: 48000)
            for index in 0..<14400 {
                spectrum.consume(0.04 * sin(2 * .pi * frequency * Double(index) / 48000))
            }
            return spectrum.levels
        }
        let low = bands(140), high = bands(2200)
        let state = AppState(preview: true)
        state.phase = .recording
        let input = InputOutlineLayout()
        input.outlineRect = CGRect(x: 32, y: 32, width: 400, height: 64)
        input.cornerRadius = 32
        let display = GlowDisplay(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 32,
            topLeft: CGRect(x: 0, y: 950, width: 660, height: 32),
            topRight: CGRect(x: 852, y: 950, width: 660, height: 32))
        let top = TopGlowLayout(display: display)
        for mode in [GlowAppearance.bottom, .aroundNotch, .aroundInput] {
            let size: CGSize = mode == .bottom ? CGSize(width: 800, height: 240)
                : mode == .aroundNotch ? top.frame.size : CGSize(width: 464, height: 128)
            func view(_ bands: [Double], reduced: Bool) -> AnyView {
                switch mode {
                case .bottom:
                    return AnyView(BottomGlow(level: 0.3, strength: 1, phase: .recording,
                        timeOverride: 1, spectrumProvider: { bands }, reduceMotionOverride: reduced,
                        reduceTransparencyOverride: true))
                case .aroundNotch:
                    return AnyView(TopGlow(layout: top, strength: 1, phase: .recording,
                        levelProvider: { 0.3 }, spectrumProvider: { bands }, timeOverride: 1,
                        reduceTransparencyOverride: true, reduceMotionOverride: reduced))
                default:
                    return AnyView(InputOutline(state: state, layout: input, reduceMotionOverride: reduced,
                        levelProvider: { 0.3 }, spectrumProvider: { bands }, timeOverride: 1,
                        reduceTransparencyOverride: true))
                }
            }
            func pixels(_ bands: [Double], reduced: Bool = false) throws -> Data {
                let renderer = ImageRenderer(content: view(bands, reduced: reduced).frame(width: size.width, height: size.height))
                renderer.scale = 1
                guard let image = renderer.cgImage, let data = image.dataProvider?.data else {
                    throw failure("Could not render the synthetic \(mode.title) speech fixture.")
                }
                return data as Data
            }
            let bass = try pixels(low), treble = try pixels(high)
            guard bass.count == treble.count, zip(bass, treble).filter({ $0 != $1 }).count > 80,
                  try pixels(low, reduced: true) == pixels(high, reduced: true) else {
                throw failure("\(mode.title) does not distinguish equal-volume pitches or suppress motion when requested.")
            }
            func profile(_ bands: [Double]) -> GlowProfile {
                var profile = GlowHistory().frame(level: 0.3, time: 1, reducedMotion: false, bands: bands)
                if mode == .aroundNotch { profile.topLayout = top }
                if mode == .aroundInput {
                    profile.inputOutline = InputOutlineBackdrop(rect: input.outlineRect, cornerRadius: input.cornerRadius)
                }
                return profile
            }
            func map(_ bands: [Double]) throws -> Data {
                guard let image = GlowBackdrop.mask(profile: profile(bands), size: size),
                      let bitmap = image.representations.first as? NSBitmapImageRep,
                      let pixels = bitmap.bitmapData else { throw failure("Missing speech blur map.") }
                return Data(bytes: pixels, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
            }
            guard try map(low) != map(high) else { throw failure("\(mode.title) blur field does not respond to frequency balance.") }
            print("PASS: \(mode.title) actual Canvas and native map distinguish equal-RMS synthetic pitches; Reduce Motion freezes geometry; no separate speech trace is drawn.")
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "S2TSpeechGlow", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
