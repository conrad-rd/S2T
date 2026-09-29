import SwiftUI

extension View {
    // Settings inherit the platform's sizing, shape, focus and contrast.
    @ViewBuilder func nativeGlassButtons(prominent: Bool = false) -> some View {
        if prominent { self.buttonStyle(.borderedProminent) }
        else { self.buttonStyle(.automatic) }
    }
}
