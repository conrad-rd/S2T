# Bottom glow sweep

Implemented from the supplied `glow-sweep-macos-complete.md` on September 13, 2026.

Bottom uses the captured four color stops, horizontal reference endpoints, vertical midpoint, cubic brightness transfer, and native radial attenuation approximation. Canvas composites the white lift beneath the color. The blur map uses the same spatial field. The curve lookup is computed once and interpolated when sampling.

S2T fits the field to its existing speech-responsive height plus 26 points, inside its 240-point panel. It retains the existing audio-dependent 8-point blur ceiling and bounded square-root transfer rather than the demo's 19-point setting. Color opacity 0.70 and white lift 0.12 are native adaptation defaults, not authored AE values. Speech changes height and brightness; the horizontal palette does not travel. Busy phases keep the loading line.

Around Notch and Around Input retain their existing renderers. WindowServer hosting, focus behavior, reduced-transparency handling, phase persistence, and display placement use the existing implementation.

Verification uses domain tests, generated Canvas output, and hidden-window structural checks. No desktop pixels are captured. These checks do not establish cross-app visual blur quality or AE pixel parity.

Build 68 verification: 106 service/domain tests passed. Packaged --verify-glow passed at 0.3 and 0.55 meter levels, including generated color continuity and filter output, plus hidden-window checks on both connected displays at 2x and 1x. --verify-build confirmed S2T 1.0.1, Build 68, and matching menu metadata. No provider calls were needed for this appearance change.

The edge-only correction restores Build 68 height and radial geometry. The middle half has an edge multiplier of exactly 1. The outer quarters use a smooth taper to 0.35 at either side. Both Canvas and the native blur map use this multiplier. The center-matching regression first failed against Build 69 and then passed after the correction, alongside all 108 tests.

The later center and edge refinements were rejected. Restored the full Build 68 sweep, removing the extra edge mask from Canvas and native blur. The regression now compares the original field across the full width and preserves the original height.

The light-sweep revision adds a separate pale colored highlight across the bottom 14 points. Its strongest light is at the bottom center; a squared-sine horizontal fade reaches zero with a flat slope at both screen edges. The full-width base field, its brightness, height, and native blur stay unchanged. The loading line is unaffected. This restores a distinct bottom light band that the initial sweep replacement removed.

The side drop-off correction applies a smooth zero-to-one fade across each outer 20% to both base color and blur. The central 60% retains its original base field. The center light now spans 18 points with increased opacity at the bottom and through its falloff. This addresses the residual full-width base band that remained visible beneath the previous highlight-only fade.

The intensity correction separates the appearance slider from microphone gain. Maximum intensity now supplies a 200–240-point spatial field and brightness 0.8–1.0, rather than requiring loud speech for a visible body. Speech continues to vary height and brightness. The native blur map receives the same intensity, while its radius remains audio-driven and zero in silence. The generated filter fixture checks sharp content above the expanded field.

Around Notch and Around Input now share the sweep palette, transfer, intensity response, and bright edge through ContourGlow. The field fits their existing exterior geometry; notch wings fade laterally and input interiors stay clear. Native radius maps use the same transfer and intensity-dependent extent. The previous additive notch tint is disabled. Target detection and window placement are unchanged.

Build 79 adds two tapered processing light trails around the input outline. The trails repeat every 2.8 seconds, wrap without losing length, and stay fixed with Reduce Motion. Around Notch now uses a 2-point blur ceiling, quadratic falloff, and 0.24 haze opacity. The native notch check asserts the submitted 2-point radius at both 0.3 and 0.55 meter levels and zero during busy phases. All 109 domain/service tests passed; generated rendering and hidden notch checks passed on both displays. No screen capture or live visual matching was performed.
