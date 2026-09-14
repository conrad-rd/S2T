# Reference-matched menu bar backdrop

Matched the supplied 1010×658 screenshot's backdrop and mark. The backdrop reference is 625×370 pixels. The logo viewport is 490×203 pixels, with 77 pixels of left padding and 84 pixels of bottom padding.

The status item remains 32 points wide. Its 28-point-wide artwork scales the reference geometry directly. The backdrop uses SwiftUI RoundedRectangle with continuous corners. Fitting this native shape against the screenshot's left silhouette gave a 101-pixel reference radius, or 4.5248 points in the menu bar. Boundary RMS difference was 1.41 reference pixels. Opacity is 25/245 to match the screenshot's 220 gray on a 245 background.

The packaged build passed without compiler warnings. Rendered native button previews were inspected in light and dark appearances under build/verification/menu-squircle. No menu interaction, provider, audio, or paste logic changed.
