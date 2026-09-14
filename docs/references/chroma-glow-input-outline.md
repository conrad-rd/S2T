# Chroma Glow input outline reference

The user supplied `chroma-glow-input-outline.json` for S2T's Around Input appearance. Chroma Glow calls this style Box. Preserve every value exactly when discussing or updating the effect. The export includes defaults.

The effect blurs the live desktop when started. `settings.blur` is the background blur multiplier, set to 2. The exported background radius is 76.59375 points. `effectBlur` is 30.040762 points and `sweep.blur` is 0 points. These are separate blur settings.

Sweep height is thickness in points. Sweep width is a fraction of its path length. Speed is a multiplier, with one pass per six seconds at 1. This preset's zero speed holds the sweep at the bottom center of the outline.

`falloffCurve` specifies two Bezier handles with fixed endpoints at zero and one. Position values are fractions of the display dimensions. The reference display is 1800 by 1169 points.

Implemented by ChromaPreset and ChromaAppearance. The bundled resource matches this export. See `../verification/chroma-appearances.md` for the source port, geometry adaptations, native composition and verification limits.
