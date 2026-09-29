import AppKit

// Figma artwork positions are relative to the 780 × 720 window. The content begins at x = 105.
enum AppearanceDesignArtwork {
    static let size = CGSize(width: 675, height: 720)
    static let bottomEdge: CGFloat = -157 + 1.0283411741256714 + 445.2892761230469
    static let notchTop: CGFloat = -7 + 99.91655731201172
    static let notchImageFrame = CGRect(x: -195 + 540.8333740234375 - 105,
        y: -7 + 80.6667709350586, width: 220.00001525878906, height: 52.250003814697266)
    // The 240 × 57 PNG includes asymmetric transparent padding around its black housing.
    static let notchLeft = notchImageFrame.minX + 6 / 240 * notchImageFrame.width
    static let notchWidth = 200 / 240 * notchImageFrame.width
    static let notchDepth = notchImageFrame.minY + 56 / 57 * notchImageFrame.height - notchTop

    static func compose(notch: Bool, leadingWidth: CGFloat = 0, load: (String) -> NSImage?) -> NSImage? {
        let names = notch ? ["Figma-Notch-Background", "Figma-Notch-Display", "Figma-Notch-Housing"]
            : ["Figma-Bottom-Background", "Figma-Bottom-Display"]
        let images = names.compactMap(load)
        guard images.count == names.count else { return nil }
        let rects: [CGRect] = notch ? [
            CGRect(x: -195, y: -7, width: 1276, height: 828.6666870117188),
            CGRect(x: -195 - 234.66665649414062, y: notchTop, width: 1833.3333740234375, height: 1031.25),
            notchImageFrame.offsetBy(dx: 105, dy: 0)
        ] : [
            CGRect(x: -60 - 238.28500366210938, y: -157 - 36.35308837890625, width: 1524.5701904296875, height: 1452.7974853515625),
            CGRect(x: -60 - 235.2944793701172, y: -157 + 1.0283411741256714, width: 1496.159912109375, height: 445.2892761230469)
        ]
        return NSImage(size: CGSize(width: size.width + leadingWidth, height: size.height), flipped: true) { _ in
            for (index, image) in images.enumerated() {
                let rect = rects[index].offsetBy(dx: leadingWidth - 105, dy: 0)
                if !notch && index == 1 {
                    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                } else {
                    let scale = max(rect.width / image.size.width, rect.height / image.size.height)
                    let source = CGRect(x: (image.size.width - rect.width / scale) / 2,
                        y: (image.size.height - rect.height / scale) / 2,
                        width: rect.width / scale, height: rect.height / scale)
                    image.draw(in: rect, from: source, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
            if notch {
                NSGradient(colorsAndLocations: (.clear, 0), (.clear, 0.19782), (.black.withAlphaComponent(0.2), 1))?
                    .draw(in: CGRect(x: 0, y: 0, width: 796 + leadingWidth, height: 733), angle: 90)
            } else {
                NSGradient(starting: .clear, ending: .black.withAlphaComponent(0.3))?
                    .draw(in: CGRect(x: -60 - 328.31634521484375 - 105 + leadingWidth, y: -157 - 129.5087890625,
                        width: 1763.1392822265625, height: 969.0449829101562), angle: 90)
            }
            return true
        }
    }
}
