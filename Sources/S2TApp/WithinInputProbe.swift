import AppKit
import SwiftUI
import S2TCore

@MainActor enum WithinInputProbe {
    static func run() throws {
        try verifySavedProcessingPalette()
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "WithinInput", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw NSError(domain: "WithinInput", code: 2)
            }
            return NSBitmapImageRep(cgImage: cg)
        }
        func alpha(_ image: NSBitmapImageRep, _ x: Double, _ y: Double) -> Double {
            Double(image.colorAt(x: Int(x), y: Int(y))?.alphaComponent ?? 0)
        }
        func matchingPixels(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Bool {
            guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return false }
            // GPU filter rounding can vary below one 8-bit level. Compare the
            // visible premultiplied pixels rather than encoded TIFF bytes.
            for y in 0..<a.pixelsHigh { for x in 0..<a.pixelsWide {
                guard let p = a.colorAt(x: x, y: y), let q = b.colorAt(x: x, y: y) else { return false }
                let difference = max(abs(p.alphaComponent - q.alphaComponent),
                    abs(p.redComponent * p.alphaComponent - q.redComponent * q.alphaComponent),
                    abs(p.greenComponent * p.alphaComponent - q.greenComponent * q.alphaComponent),
                    abs(p.blueComponent * p.alphaComponent - q.blueComponent * q.alphaComponent))
                if difference > 1.0 / 255 + 0.00001 { return false }
            } }
            return true
        }
        func savedRGB(_ image: NSBitmapImageRep, x: Int, y: Int) -> SIMD3<Double> {
            // colorAt labels floating-point linear components as Generic RGB.
            // Convert using the bitmap's actual profile before comparing saved sRGB.
            let raw = image.colorAt(x: x, y: y)!
            let color = CGColor(colorSpace: image.colorSpace.cgColorSpace!,
                components: [raw.redComponent, raw.greenComponent, raw.blueComponent, raw.alphaComponent])!
                .converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)!
            let values = color.components!
            return SIMD3(Double(values[0]), Double(values[1]), Double(values[2]))
        }
        let state = AppState(preview: true)
        let saved = state.glowAppearance
        defer { state.glowAppearance = saved }
        state.glowAppearance = .withinInput
        try check(GlowAppearance.allCases.firstIndex(of: .withinInput) == 4,
            "Within Input must be the fifth appearance")
        try check(AppState(preview: true).glowAppearance == .withinInput, "Appearance did not persist")
        let originalTuning = state.glowTuning
        defer { state.glowTuning = originalTuning }
        if !ProcessInfo.processInfo.arguments.contains("--processing-only") {
        let settings = AppearanceWindowController(state: state, presentsWindows: false)
        _ = settings.prepare()
        settings.setModelsVisible(false)
        state.glowAppearance = .withinInput
        settings.selectPreview(.withinInput)
        settings.selectSection(.glow)
        settings.window?.contentView?.layoutSubtreeIfNeeded()
        let sizeRow = settings.inputSizeRow
        let sizeLabel = sizeRow.arrangedSubviews.compactMap { $0 as? NSTextField }.first!
        let adjacent = settings.sliders[.inputMinimumSize]!.superview!
        let adjacentLabel = adjacent.subviews.compactMap { $0 as? NSTextField }.first!
        try check(sizeRow.bounds.height == 38 && !sizeRow.isHiddenOrHasHiddenAncestor,
            "Adaptive size row must match the visible slider row height")
        try check(abs(sizeLabel.convert(.zero, to: settings.controlsPanel).x - adjacentLabel.convert(.zero, to: settings.controlsPanel).x) < 0.5
            && sizeLabel.font?.pointSize == 13,
            "Adaptive size label must align with adjacent setting labels")
        try check(sizeRow.bounds.contains(settings.inputSizeToggle.frame)
            && settings.inputSizeToggle.frame.minX > sizeLabel.frame.maxX,
            "Adaptive size switch must fit to the right of its label")
        settings.inputSizeToggle.state = .on
        _ = settings.inputSizeToggle.sendAction(settings.inputSizeToggle.action!, to: settings.inputSizeToggle.target)
        try check(state.glowTuning.inputSizeEnabled, "Size option did not enable")
        AppearanceControl.inputMinimumSize.set(0.7, in: state)
        AppearanceControl.inputMaximumSize.set(1.6, in: state)
        let previewRequest = AppearancePreviewScene.request(state: state, phase: 0, time: 0, reducedMotion: true, backdrop: true)
        try check(abs(previewRequest.profile.response.tuning.falloff - state.glowTuning.falloff / 1.6) < 0.000001,
            "Preview must use maximum glow size: mode \(state.glowAppearance), enabled \(state.glowTuning.inputSizeEnabled), maximum \(state.glowTuning.inputMaximumSize), base \(state.glowTuning.falloff), preview \(previewRequest.profile.response.tuning.falloff)")
        try check(AppState(preview: true).glowTuning.inputMaximumSize == 1.6, "Size settings did not persist")
        let fixtureContour = InputContour(rect: CGRect(x: 30, y: 30, width: 300, height: 180), radius: 20)
        let fixtureSize = CGSize(width: 360, height: 240)
        let smallTuning = state.glowTuning.forInput(size: CGSize(width: 600, height: 24))
        let largeTuning = state.glowTuning.forInput(size: CGSize(width: 600, height: 300))
        let smallAssets = ChromaAppearance.assets(geometry: .withinInput(fixtureContour), size: fixtureSize, falloff: smallTuning.falloff)!
        let largeAssets = ChromaAppearance.assets(geometry: .withinInput(fixtureContour), size: fixtureSize, falloff: largeTuning.falloff)!
        for (smallImage, largeImage) in [(smallAssets.color, largeAssets.color), (smallAssets.radius, largeAssets.radius)] {
            let small = try bitmap(smallImage), large = try bitmap(largeImage)
            var smallTotal = 0.0, largeTotal = 0.0
            for y in 100..<205 { for x in 120..<240 {
                smallTotal += alpha(small, Double(x), Double(y))
                largeTotal += alpha(large, Double(x), Double(y))
            } }
            try check(smallTotal > 1 && largeTotal > smallTotal, "Generated color/blur falloff did not scale or small glow vanished")
        }
        }
        state.glowTuning = originalTuning
        let size = CGSize(width: 440, height: 280)
        if !ProcessInfo.processInfo.arguments.contains("--processing-only") {
        for (height, radius, style) in [(120.0, 24.0, InputCornerStyle.circular), (60.0, 30.0, .circular), (120.0, 24.0, .continuous)] {
            let rect = CGRect(x: 60, y: 60, width: 320, height: height)
            let contour = InputContour(rect: rect, radius: radius, style: style)
            let field = WithinInputField(contour: contour)
            try check(field.lowerEdge(at: rect.minX + 6) < rect.maxY - 2, "Lower band did not wrap the corner")
            for amount in [0.3, 1.0, 2.0, 5.0] {
                var profile = GlowProfile(energy: 0.55, heights: [3], reducedMotion: false,
                    response: .init(minimum: amount, maximum: amount))
                profile.inputOutline = InputOutlineBackdrop(contour: contour, strength: 1.3, withinInput: true)
                let request = ChromaFrameRequest(geometry: .withinInput(contour), size: size,
                    profile: profile, brightness: profile.speechGain, backdrop: true)
                guard let frame = ChromaFrame.render(request), let map = frame.radiusMap else {
                    throw NSError(domain: "WithinInput", code: 3)
                }
                let renderer = ImageRenderer(content: ChromaFrameCanvas(frame: frame).frame(width: size.width, height: size.height))
                renderer.scale = 1
                guard let color = renderer.cgImage else { throw NSError(domain: "WithinInput", code: 4) }
                let pixels = NSBitmapImageRep(cgImage: color)
                let blur = try bitmap(map)
                for image in [pixels, blur] {
                    if height == 60 && amount >= 1 {
                        try check(alpha(image, rect.midX, rect.midY - 3) > 0.001, "Glow still stops at the editor midpoint")
                    }
                    if amount >= 2 {
                        try check(alpha(image, rect.midX, rect.minY - 3) > 0.001, "Glow still stops at the editor top")
                    }
                    if amount >= 2 {
                        for x in [rect.minX - 8, rect.maxX + 8] {
                            try check(alpha(image, x, rect.midY) == 0, "Side spill reached the main bar")
                        }
                    }
                    try check(alpha(image, rect.minX - 12, rect.maxY) == 0, "Effect escaped the input horizontally")
                    try check(alpha(image, rect.midX, rect.maxY + 12) == 0, "Exterior spill exceeded its bound")
                    try check(alpha(image, rect.midX, rect.maxY - 3) > 0.01, "Missing glow inside the lower edge")
                    try check(alpha(image, rect.midX, rect.maxY + 1) == 0, "Glow leaked below the anchored edge")
                    for offset in [6.0, 12.0, 24.0] {
                        let x = rect.minX + offset
                        try check(alpha(image, x, ceil(field.lowerEdge(at: x + 1)) + 1) == 0, "Glow leaked below a rounded corner at \(x),\(ceil(field.lowerEdge(at: x + 1)) + 1), alpha \(alpha(image, x, ceil(field.lowerEdge(at: x + 1)) + 1)), color \(image === pixels), height \(height), amount \(amount)")
                    }
                }
            }
        }
        let edgeContour = InputContour(rect: CGRect(x: 60, y: 100, width: 320, height: 60), radius: 30, style: .circular)
        var edgeTuning = GlowTuning()
        edgeTuning.bodyOpacity = 0
        edgeTuning.edgeGlow = 2
        edgeTuning.edgeBlur = 12
        let edgeView = Canvas { context, dimensions in
            ChromaAppearance.draw(context: &context, geometry: .withinInput(edgeContour), size: dimensions,
                brightness: 5, distortion: .identity, expansion: 1.6, tuning: edgeTuning)
        }.frame(width: size.width, height: size.height)
        let edgeRenderer = ImageRenderer(content: edgeView)
        edgeRenderer.scale = 1
        guard let edgeImage = edgeRenderer.cgImage else { throw NSError(domain: "WithinInput", code: 4) }
        let edgePixels = NSBitmapImageRep(cgImage: edgeImage)
        for y in 0..<Int(size.height) { for x in 0..<Int(size.width) {
            if !edgeContour.bounds.insetBy(dx: -1, dy: -1).contains(CGPoint(x: x, y: y)) {
                try check(alpha(edgePixels, Double(x), Double(y)) == 0, "Listening edge escaped the bar")
            }
        } }
        for amount in [0.3, 1.0, 2.0, 5.0] {
            let contour = InputContour(rect: CGRect(x: 60, y: 60, width: 320, height: 120), radius: 24, style: .circular)
            var within = GlowProfile(energy: 1, heights: [3], response: .init(minimum: 0, maximum: amount))
            within.inputOutline = InputOutlineBackdrop(contour: contour, strength: 1.3, withinInput: true)
            var around = within
            around.inputOutline = InputOutlineBackdrop(contour: contour, strength: 1.3)
            try check(abs(within.blurGain - around.blurGain) < 0.0001,
                "Shared blur settings must have equal gain inside and around inputs")
            try check(within.speechExpansion == around.speechExpansion,
                "Intensity balancing must preserve speech expansion and the upper spill")
        }
        }
        let messageContour = InputContour(rect: CGRect(x: 60, y: 60, width: 320, height: 120), radius: 30, style: .circular)
        func processingImage(_ time: Double, reduced: Bool = false, gradient: GlowGradient = .init()) throws -> NSBitmapImageRep {
            let view = Canvas(opaque: false, colorMode: .extendedLinear) { context, dimensions in
                WithinInputProcessing.draw(context: &context, contour: messageContour, time: time, reducedMotion: reduced, gradient: gradient)
            }.frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.cgImage else { throw NSError(domain: "WithinInput", code: 5) }
            return NSBitmapImageRep(cgImage: image)
        }
        let green = GlowGradient(stops: [.init(position: 0, color: SIMD3(0, 1, 0))])
        let greenImage = try processingImage(0, gradient: green)
        let greenPixel = greenImage.colorAt(x: 220, y: 120)!.usingColorSpace(.deviceRGB)!
        try check(greenPixel.greenComponent > greenPixel.redComponent + 0.1
            && greenPixel.greenComponent > greenPixel.blueComponent + 0.1,
            "Processing ignored the user-selected gradient")
        let storedDefault = GlowGradient()
        let shifted = GlowGradient(stops: storedDefault.stops.map {
            .init(position: ($0.position + 0.125).truncatingRemainder(dividingBy: 1), color: $0.color)
        })
        let ordinary = try processingImage(0, gradient: storedDefault)
        let equivalent = GlowGradient(stops: storedDefault.stops + [
            .init(position: storedDefault.stops[0].position, color: storedDefault.stops[0].color)
        ])
        let equivalentImage = try processingImage(0, gradient: equivalent)
        try check(matchingPixels(ordinary, equivalentImage),
            "The standard saved gradient must not use a separate reference-color renderer")
        let shiftedImage = try processingImage(0, gradient: shifted)
        try check(ordinary.tiffRepresentation != shiftedImage.tiffRepresentation,
            "Processing must use the saved gradient's stop positions")
        for y in [90, 110, 130, 150] {
            try check(abs(alpha(ordinary, 220, Double(y)) - alpha(shiftedImage, 220, Double(y))) < 1.0 / 1024,
                "Palette changes must preserve the approved soft opacity envelope")
        }
        let neutral = GlowGradient(stops: [.init(position: 0, color: SIMD3(repeating: 0.5))])
        let neutralImage = try processingImage(0, gradient: neutral)
        for (x, y) in [(220, 110), (220, 155), (61, 120)] {
            let color = neutralImage.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            try check(abs(color.redComponent - color.greenComponent) < 0.005
                && abs(color.greenComponent - color.blueComponent) < 0.005,
                "The wave or glass rim introduced colors outside the saved neutral palette")
        }
        let exactColors = [SIMD3(0.12, 0.24, 0.78), SIMD3(0.85, 0.32, 0.08), SIMD3(repeating: 0.18)]
        let colorSize = CGSize(width: 320, height: 120)
        let colorContour = InputContour(rect: CGRect(origin: .zero, size: colorSize), radius: 30, style: .circular)
        for expected in exactColors {
            let gradient = GlowGradient(stops: [.init(position: 0, color: expected)])
            for time in [0.0, 0.6, 1.2] {
                guard let image = WithinInputProcessing.loadingImage(size: colorSize, time: time,
                    gradient: gradient, contour: colorContour) else { throw NSError(domain: "WithinInput", code: 5) }
                let pixels = try bitmap(image)
                for (x, y) in [(160, 35), (160, 70)] {
                    let actual = OKLab.fromSRGB(savedRGB(pixels, x: x, y: y))
                    let source = OKLab.fromSRGB(expected)
                    let sourceChroma = hypot(source.y, source.z), actualChroma = hypot(actual.y, actual.z)
                    if sourceChroma < 0.0001 {
                        try check(actualChroma < 0.003, "Neutral saved colors must remain neutral under the reference lighting")
                    } else {
                        let hueAgreement = (source.y * actual.y + source.z * actual.z) / (sourceChroma * actualChroma)
                        try check(hueAgreement > 0.96, "Reference lighting changed the selected gradient hue")
                    }
                }
            }
        }
        let spacedColors = GlowGradient(stops: [
            .init(position: 40.5 / 320, color: SIMD3(0.85, 0.32, 0.08)),
            .init(position: 100.5 / 320, color: SIMD3(0.04, 0.65, 0.5)),
            .init(position: 190.5 / 320, color: SIMD3(0.38, 0.12, 0.72)),
            .init(position: 270.5 / 320, color: SIMD3(0.76, 0.64, 0.08))
        ])
        for stop in spacedColors.stops {
            // Find when this saved stop passes the sampled point in the rolling
            // multicolor band, rather than assuming a single hue per frame.
            let sampleHeight = 60.5 / 120.0
            let time = (0...3600).map { Double($0) / 1000 }.min { a, b in
                func error(_ time: Double) -> Double {
                    let position = ReferenceLoadingField.Frame(time: time, gradient: spacedColors)
                        .lightPalettePosition(heightFraction: sampleHeight)
                    let delta = abs((position - floor(position)) - stop.position)
                    return min(delta, 1 - delta)
                }
                return error(a) < error(b)
            }!
            guard let image = WithinInputProcessing.loadingImage(size: colorSize,
                time: time, gradient: spacedColors) else {
                throw NSError(domain: "WithinInput", code: 5)
            }
            let actual = OKLab.fromSRGB(savedRGB(try bitmap(image), x: 160, y: 60))
            let expected = OKLab.fromSRGB(stop.color)
            let hueAgreement = (actual.y * expected.y + actual.z * expected.z)
                / (hypot(actual.y, actual.z) * hypot(expected.y, expected.z))
            try check(hueAgreement > 0.96, "Every saved gradient stop must reach the actual loading light during its color cycle")
        }
        for time in [0.0, 1.8] {
            let frame = ReferenceLoadingField.Frame(time: time, gradient: spacedColors)
            for stop in spacedColors.stops {
                let position = (stop.position - time / ReferenceLoadingField.paletteDuration + 1).truncatingRemainder(dividingBy: 1)
                let expected = stop.color
                let actual = frame.paletteColor(at: position)
                try check(abs(actual.x - expected.x) < 0.004
                    && abs(actual.y - expected.y) < 0.004
                    && abs(actual.z - expected.z) < 0.004,
                    "The light source must preserve saved colors and stop spacing before reference lighting shades them")
            }
        }
        for gradient in [storedDefault, spacedColors] {
            let frame = ReferenceLoadingField.Frame(time: 0, gradient: gradient)
            for stop in gradient.stops {
                let step = 0.0001
                let center = OKLab.fromSRGB(frame.paletteColor(at: stop.position))
                let left = (center - OKLab.fromSRGB(frame.paletteColor(at: stop.position - step))) / step
                let right = (OKLab.fromSRGB(frame.paletteColor(at: stop.position + step)) - center) / step
                let jump = abs(left.x - right.x) + abs(left.y - right.y) + abs(left.z - right.z)
                try check(jump < 0.02, "Gradient stops must not create sharp vertical color seams")
            }
        }
        func fluidFrame(_ time: Double) throws -> NSBitmapImageRep {
            guard let image = WithinInputProcessing.loadingImage(size: CGSize(width: 320, height: 240), time: time, gradient: .init()) else {
                throw NSError(domain: "WithinInput", code: 5)
            }
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            try check(cg?.bitsPerComponent == 32 && cg?.bitmapInfo.contains(.floatComponents) == true,
                "Processing must keep floating-point color and alpha")
            return try bitmap(image)
        }
        let flowStart = try fluidFrame(0), flowLater = try fluidFrame(1.2)
        let flowLoop = try fluidFrame(WithinInputProcessing.cycleDuration)
        try check(matchingPixels(flowStart, flowLoop), "Processing must loop seamlessly")
        try check(flowStart.tiffRepresentation != flowLater.tiffRepresentation, "Processing must visibly change")
        let moved = try fluidFrame(0.2)
        for x in [80.0, 160.0, 240.0] {
            var bestShift = 0, bestError = Double.infinity
            for shift in -30...35 {
                let error = (40..<170).reduce(0.0) {
                    $0 + abs(alpha(flowStart, x, Double($1 + shift)) - alpha(moved, x, Double($1)))
                }
                if error < bestError { bestError = error; bestShift = shift }
            }
            try check((16...30).contains(bestShift) && bestError / 130 < 0.02,
                "The restored light and its translucent opening must travel upward at the reference speed")
        }
        for (height, measured) in [(0.4, SIMD3<Double>(81, 53, 145)), (0.8, SIMD3<Double>(242, 198, 231))] {
            let actual = OKLab.fromSRGB(savedRGB(flowStart, x: 160, y: Int(height * 240)))
            let reference = OKLab.fromSRGB(measured / 255)
            try check(abs(actual.x - reference.x) < 0.045,
                "Changing the palette must retain the supplied reference's light and shadow depth")
        }
        let before = try fluidFrame(WithinInputProcessing.cycleDuration - 0.001)
        let after = try fluidFrame(WithinInputProcessing.cycleDuration + 0.001)
        var jump = 0.0, brightest = 0.0, faintest = 1.0, spatialStep = 0.0
        var levels = Set<Int>()
        for y in 1..<239 {
            let a = alpha(flowLater, 160, Double(y))
            levels.insert(Int((a * 65535).rounded()))
            brightest = max(brightest, a)
            faintest = min(faintest, a)
            spatialStep = max(spatialStep, abs(a - alpha(flowLater, 160, Double(y - 1))))
        }
        for y in stride(from: 0, to: 240, by: 8) { for x in stride(from: 0, to: 320, by: 8) {
            jump = max(jump, abs(alpha(before, Double(x), Double(y)) - alpha(after, Double(x), Double(y))))
        } }
        try check(jump < 0.01, "Processing has a visible cycle reset")
        // The clear treatment uses a smaller alpha range. Require more than
        // twice the levels an 8-bit image could represent within that range.
        let eightBitLevels = Int(ceil((brightest - faintest) * 255)) + 1
        try check(levels.count > eightBitLevels * 2, "Low-opacity glow has visible quantization steps")
        try check(brightest > 0.04 && brightest < 0.10 && faintest > 0.005 && faintest < 0.015 && spatialStep < 0.025,
            "The moving sheen must leave the message bar visible between soft highlights")
        let lensSize = CGSize(width: 320, height: 120)
        let lensContour = InputContour(rect: CGRect(origin: .zero, size: lensSize), radius: 30, style: .circular)
        guard let plain = WithinInputProcessing.loadingImage(size: lensSize, time: 1.1, gradient: .init()),
              let refracted = WithinInputProcessing.loadingImage(size: lensSize, time: 1.1, gradient: .init(), contour: lensContour) else {
            throw NSError(domain: "WithinInput", code: 5)
        }
        let plainPixels = try bitmap(plain), refractedPixels = try bitmap(refracted)
        try check(alpha(refractedPixels, 160, 117) > 0.05 && alpha(refractedPixels, 160, 117) < 0.25,
            "The curled perimeter must read as a translucent gradient detail")
        var edgeChange = 0.0
        for y in 1..<119 { for x in 1..<319 {
            let point = CGPoint(x: x, y: y)
            let difference = abs(alpha(plainPixels, Double(x), Double(y)) - alpha(refractedPixels, Double(x), Double(y)))
            if x > 96 && x < 224 && y > 38 && y < 82 {
                try check(difference < 0.006, "Finishing diffusion changed the central glow excessively")
            } else if lensContour.path.contains(point) {
                edgeChange += difference
            }
        } }
        try check(edgeChange > 15, "Glass lens must visibly refract the existing blurred wave near the edge")
        if ProcessInfo.processInfo.arguments.contains("--export-processing-fixture") {
            let image = try ProcessingBlurProbe.fixture()
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw NSError(domain: "WithinInput", code: 5)
            }
            try png.write(to: URL(fileURLWithPath: "/tmp/s2t-loading-fixture.png"))
            let compound = try ProcessingBlurProbe.compoundFixture()
            try NSBitmapImageRep(cgImage: compound).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "/tmp/s2t-loading-compound-fixture.png"))
            print("Generated fixture: /tmp/s2t-loading-fixture.png. Authored text, production native progressive blur and color; no screen content sampled.")
        }
        try ProcessingBlurProbe.run()
        if ProcessInfo.processInfo.arguments.contains("--export-loading-reference") {
            let destination = URL(fileURLWithPath: "/tmp/s2t-loading-coded", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for frame in 0..<27 {
                let view = Canvas(opaque: true, colorMode: .extendedLinear) { context, _ in
                    for y in 0..<68 { for x in 0..<68 {
                        let color = Color(white: (x + y).isMultiple(of: 2) ? 0.92 : 0.78)
                        context.fill(Path(CGRect(x: x * 8, y: y * 8, width: 8, height: 8)), with: .color(color))
                    } }
                    let contour = InputContour(rect: CGRect(x: 60, y: 190, width: 418, height: 160), radius: 42, style: .circular)
                    context.fill(contour.path, with: .color(Color(white: 0.95)))
                    context.drawLayer { background in
                        background.addFilter(.blur(radius: 1.2))
                        background.draw(Text("Ask Chatgpt anything").font(.system(size: 12)).foregroundColor(.black.opacity(0.42)),
                            at: CGPoint(x: 90, y: 238), anchor: .leading)
                    }
                    context.drawLayer { effect in
                        WithinInputProcessing.draw(context: &effect, contour: contour, time: Double(frame) / 15, reducedMotion: false)
                    }
                }.frame(width: 540, height: 540)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                guard let image = renderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "WithinInput", code: 5)
                }
                try png.write(to: destination.appendingPathComponent(String(format: "%03d.png", frame)))
            }
            print("Generated coded animation: /tmp/s2t-loading-coded. No reference media or screen content loaded.")
        }
        let first = try processingImage(0), later = try processingImage(3)
        let translucentFrame = try processingImage(0.9)
        let interiorAlphas = (70..<170).map { alpha(translucentFrame, 220, Double($0)) }
        try check(interiorAlphas.min()! > 0.005 && interiorAlphas.min()! < 0.02
            && interiorAlphas.max()! > 0.035 && interiorAlphas.max()! < 0.16,
            "The composed wave must reveal the input with stronger light confined to its edges")
        try check(alpha(first, 220, 185) > 0.003 && alpha(first, 220, 185) < 0.05,
            "A faint outer glow must extend beyond the bar without becoming another filled surface")
        let borderView = Canvas(opaque: false, colorMode: .extendedLinear) { context, dimensions in
            WithinInputProcessing.drawBorder(context: &context, boundary: messageContour.path,
                size: size, time: 0, gradient: .init())
        }.frame(width: size.width, height: size.height)
        let borderRenderer = ImageRenderer(content: borderView)
        borderRenderer.scale = 1
        guard let borderImage = borderRenderer.cgImage else { throw NSError(domain: "WithinInput", code: 5) }
        let borderPixels = NSBitmapImageRep(cgImage: borderImage)
        try check(alpha(borderPixels, 220, 120) == 0, "Border reflection must leave the approved interior glow unchanged")
        var glint = 0.0
        for y in 60..<180 { for x in 60..<380 {
            glint = max(glint, alpha(borderPixels, Double(x), Double(y)))
        } }
        try check(glint > 0.025 && glint < 0.15, "The softened glass highlight must remain visible without a hard white outline")
        try check(alpha(borderPixels, 220, 179) > 2 * alpha(borderPixels, 220, 60),
            "The gradient accent must stay at the lower edge instead of framing the whole input")
        for y in [90.0, 120.0, 150.0] {
            for x in [100.0, 220.0, 340.0] {
                try check(alpha(first, x, y) > 0.005, "Processing glow does not cover the message bar")
            }
        }
        var change = 0.0
        for y in stride(from: 20, to: 260, by: 4) { for x in stride(from: 20, to: 420, by: 4) {
            let nearBar = messageContour.bounds.insetBy(dx: -WithinInputProcessing.haloPadding,
                dy: -WithinInputProcessing.haloPadding).contains(CGPoint(x: x, y: y))
            if !nearBar {
                try check(alpha(first, Double(x), Double(y)) == 0, "Processing glow escapes the message bar at \(x),\(y), alpha \(alpha(first, Double(x), Double(y)))")
            }
            if let a = first.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
               let b = later.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                change += abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
            }
            try check(alpha(first, Double(x), Double(y)) <= 1, "Processing obscures the message bar")
        } }
        try check(change > 3, "Processing wave does not move across the message bar")
        let stillA = try processingImage(0, reduced: true), stillB = try processingImage(3, reduced: true)
        try check(matchingPixels(stillA, stillB), "Reduce Motion must freeze the wave")
        for phase in [DictationPhase.idle, .recording, .complete, .failed] {
            try check(!WithinInputProcessing.isActive(phase), "Message-bar effect survives outside processing")
        }
        try check(WithinInputProcessing.isActive(.transcribing) && WithinInputProcessing.isActive(.processing),
            "Message-bar effect must cover transcription and cleanup")
        let processingController = InputProcessingController()
        let windowTarget = InputOutlineTarget(frame: CGRect(x: 100, y: 100, width: 800, height: 600), cornerRadius: 12, kind: .focusedWindow)
        try check(!WithinInputProcessing.accepts(windowTarget) && !WithinInputProcessing.accepts(nil)
            && processingController.prepare(target: windowTarget) == nil && processingController.panel == nil,
            "Whole-window detection must use Bottom instead of a processing panel")
        let target = InputOutlineTarget(frame: CGRect(x: 100, y: 100, width: 320, height: 120), cornerRadius: 30, cornerStyle: .circular)
        guard let processingPanel = processingController.prepare(target: target) else { throw NSError(domain: "WithinInput", code: 6) }
        let padded = target.frame.insetBy(dx: -WithinInputProcessing.haloPadding, dy: -WithinInputProcessing.haloPadding)
        try check(processingPanel.frame == padded && !processingPanel.isVisible && !processingPanel.canBecomeKey
            && processingPanel.ignoresMouseEvents, "Processing must fit the message bar without activation")
        guard let root = processingPanel.contentView as? ProgressiveBackdropView else { throw NSError(domain: "WithinInput", code: 6) }
        try check(root.profile?.processingInput?.contour == target.contour.offsetBy(dx: WithinInputProcessing.haloPadding,
            dy: WithinInputProcessing.haloPadding), "Reserving outer-glow space must not move the input or its native blur")
        let laterProfile = InputProcessingGlow.profile(contour: messageContour, time: 2.1)
        try check(abs((laterProfile.processingInput?.time ?? -1) - 2.1) < 0.00001,
            "Native blur must retain the slow light deformation after the first upward pulse")
        let initialProcessing = InputProcessingGlow.profile(contour: messageContour)
        root.prepareGeometry(initialProcessing.chromaGeometry)
        root.apply(profile: initialProcessing, radiusMap: GlowBackdrop.mask(profile: initialProcessing, size: root.bounds.size))
        root.layoutSubtreeIfNeeded()
        let filter = root.layer?.sublayers?.first?.filters?.first as? NSObject
        try check(abs((filter?.value(forKey: "inputRadius") as? Double ?? -1) - 1.25) < 0.001,
            "Processing must use a subtle 1.25-point variable-radius native blur ceiling")
        guard let nativeMap = GlowBackdrop.mask(profile: InputProcessingGlow.profile(contour: messageContour, time: 0.9), size: size) else {
            throw NSError(domain: "WithinInput", code: 7)
        }
        let map = try bitmap(nativeMap)
        try check(alpha(map, 220, 140) > 0.05 && alpha(map, 220, 140) < 0.45 && alpha(map, 0, 0) == 0,
            "Processing blur must cover the interior and respect the message-bar corners")
        for y in stride(from: 0, to: 280, by: 4) { for x in stride(from: 0, to: 440, by: 4) {
            if !messageContour.bounds.insetBy(dx: -1, dy: -1).contains(CGPoint(x: x, y: y)) {
                try check(alpha(map, Double(x), Double(y)) == 0, "Native blur escapes the selected bar")
            }
        } }
        let openRow = (75..<165).min { alpha(translucentFrame, 220, Double($0)) < alpha(translucentFrame, 220, Double($1)) }!
        let denseRow = (75..<165).max { alpha(translucentFrame, 220, Double($0)) < alpha(translucentFrame, 220, Double($1)) }!
        let clearBlur = alpha(map, 220, Double(openRow)), denseBlur = alpha(map, 220, Double(denseRow))
        try check(clearBlur > 0.06 && clearBlur < 0.12 && denseBlur > 0.3 && denseBlur < 0.42,
            "The passing sheen must gently blur the text while the clear area retains detail")
        guard let movingMap = GlowBackdrop.mask(profile: InputProcessingGlow.profile(contour: messageContour, time: 0.45), size: size) else {
            throw NSError(domain: "WithinInput", code: 7)
        }
        try check(nativeMap.tiffRepresentation != movingMap.tiffRepresentation,
            "The native blur field must move with the color wave")
        try check(InputProcessingGlow.profile(contour: messageContour, time: 0, reducedMotion: true)
            == InputProcessingGlow.profile(contour: messageContour, time: 1, reducedMotion: true),
            "Reduce Motion must freeze the native blur and color together")
        let movingProcessing = InputProcessingGlow.profile(contour: messageContour, time: 0.45)
        root.apply(profile: movingProcessing, radiusMap: GlowBackdrop.mask(profile: movingProcessing, size: root.bounds.size))
        try check(root.isBackdropAttached, "Animating blur detached the native sampler")
        root.profile = nil
        try check(root.profile == nil, "Reduce Transparency did not clear processing blur")
        processingController.hide()
        print("PASS: saved-gradient hues, restored reference light and rim, upward motion, spatial translucency, native blur, masks and Reduce Motion.")
        let controller = InputOutlineWindowController(state: state)
        let panel = controller.prepare(field: CGRect(x: 200, y: 200, width: 400, height: 100), cornerRadius: 24)
        try check(!panel.isVisible && panel.ignoresMouseEvents && !panel.canBecomeKey,
            "Within Input panel must remain hidden and click-through during verification")
        try check((panel.contentView as? ProgressiveBackdropView)?.profile?.chromaGeometry.appearance == .withinInput,
            "Native panel lost the selected geometry")
        let request = AppearancePreviewScene.request(state: state, phase: 0, time: 0, reducedMotion: true, backdrop: true)
        try check(request.geometry.appearance == .withinInput && request.profile.chromaGeometry == request.geometry,
            "Preview color and blur geometry differ")
        let processingRequest = AppearancePreviewScene.request(state: state, phase: 2, time: 0, reducedMotion: true, backdrop: true)
        try check(processingRequest.profile.processingInput != nil && ChromaFrame.render(processingRequest)?.radiusMap != nil,
            "Processing preview lost the message-bar blur")
        let movingPreview = AppearancePreviewScene.request(state: state, phase: 2, time: 0.45, reducedMotion: false, backdrop: true)
        let startingPreview = AppearancePreviewScene.request(state: state, phase: 2, time: 0, reducedMotion: false, backdrop: true)
        try check(movingPreview.profile.processingInput != startingPreview.profile.processingInput,
            "Settings preview must animate the same native blur field")
        let sampleField = AppearanceSampleTextField(frame: CGRect(x: 0, y: 0, width: 320, height: 30))
        sampleField.processing = InputProcessingBackdrop(contour: messageContour.offsetBy(dx: -60, dy: -90), time: 0.45)
        try check(sampleField.layer?.filters?.isEmpty == false, "Preview sample text must receive progressive native blur")
        sampleField.processing = nil
        try check(sampleField.layer?.filters == nil, "Preview text must become sharp when processing stops")
        if ProcessInfo.processInfo.arguments.contains("--processing-only") {
            print("PASS: saved appearance, hidden click-through panels and processing-preview geometry.")
        } else {
            print("PASS: saved appearance, listening color/blur maps, lower boundary, hidden panels and preview geometry.")
        }
    }

    static func verifySavedProcessingPalette() throws {
        func expect(_ actual: SIMD3<Double>, _ expected: SIMD3<Double>, _ message: String) throws {
            guard (0..<3).allSatisfy({ actual[$0].isFinite && abs(actual[$0] - expected[$0]) < 0.00001 }) else {
                throw NSError(domain: "WithinInput", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        let gradient = GlowGradient(stops: [
            .init(position: 0, color: SIMD3(1, 0.2, 0.1)),
            .init(position: 0.1, color: SIMD3(0.1, 1, 0.3)),
            .init(position: 0.7, color: SIMD3(0.2, 0.3, 1)),
            .init(position: 1, color: SIMD3(1, 0.7, 0.1))
        ])
        let frame = ReferenceLoadingField.Frame(time: 0, gradient: gradient)
        let waveHeight = 1 / ReferenceLoadingField.verticalCycles
        for time in [0.0, 0.4, 1.4, 2.5] {
            let field = ReferenceLoadingField.Frame(time: time, gradient: gradient)
            let start = field.lightPalettePosition(heightFraction: 0.1)
            let end = field.lightPalettePosition(heightFraction: 0.1 + waveHeight)
            try expect(SIMD3(repeating: end - start), SIMD3(repeating: 0.5),
                "One wave must carry half the saved gradient, leaving room for every color across two waves")
            let following = ReferenceLoadingField.Frame(time: time + ReferenceLoadingField.duration, gradient: gradient)
            let advance = following.lightPalettePosition(heightFraction: 0.1) - start
            try expect(SIMD3(repeating: advance - floor(advance)), SIMD3(repeating: 0.5),
                "The following wave must reveal the other half of the saved gradient")
        }
        for stop in gradient.stops {
            let position = stop.position == 1 ? 1 - 1e-7 : stop.position
            try expect(frame.paletteColor(at: position), stop.color,
                "Processing must retain both endpoint colors at their saved positions")
            let moving = ReferenceLoadingField.Frame(time: position * ReferenceLoadingField.paletteDuration, gradient: gradient)
            try expect(moving.paletteColor(at: 0), stop.color,
                "The color cycle must honor the saved stop spacing")
        }
        // Unequal gaps must keep their own midpoint, including the final gap to 100%.
        for (left, right) in zip(gradient.stops, gradient.stops.dropFirst()) {
            let middle = (left.position + right.position) / 2
            try expect(frame.paletteColor(at: middle), gradient.sampler.color(at: middle),
                "Processing must not redistribute unevenly spaced gradient stops")
        }
        let duplicate = GlowGradient(stops: [gradient.stops[0],
            .init(position: 0.1, color: SIMD3(0.3, 0.1, 1)),
            gradient.stops[1], gradient.stops[2], gradient.stops[3]])
        let duplicateFrame = ReferenceLoadingField.Frame(time: 0, gradient: duplicate)
        try expect(duplicateFrame.paletteColor(at: 0.1 - 1e-7), duplicate.stops[1].color,
            "Overlapping stops must retain the color entering the stop")
        try expect(duplicateFrame.paletteColor(at: 0.1), duplicate.stops[2].color,
            "Overlapping stops must retain the color leaving the stop")
        let same = SIMD3(0.21, 0.47, 0.68)
        for stops in [[GlowGradient.Stop(position: 1, color: same)],
                      [.init(position: 0, color: same), .init(position: 1, color: same)]] {
            let constant = ReferenceLoadingField.Frame(time: 0, gradient: GlowGradient(stops: stops))
            for position in [-0.2, 0, 0.45, 1, 1.3] {
                try expect(constant.paletteColor(at: position), same,
                    "Single-color and equal-endpoint gradients must remain constant")
            }
        }
        print("PASS: saved processing colors, uneven spacing, separate 0/100% endpoints and overlapping stops.")
    }
}
