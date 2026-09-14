# Chroma Glow Bottom maximum reference

The user supplied `chroma-glow-bottom-maximum.json` as the appearance reference for Bottom at maximum intensity. Preserve every value exactly when discussing or updating the effect. The export includes defaults.

The effect blurs the live desktop when started. `settings.blur` is a background blur multiplier. The exported background radius is 25.36087 points. `effectBlur` and `sweep.blur` are separate amounts in points, not background blur multipliers.

Sweep height is thickness in points. Sweep width is a fraction of its path length. Speed is a multiplier, with one pass per six seconds at 1. Zero speed holds the sweep at the bottom center of the outline.

`falloffCurve` specifies two Bezier handles with fixed endpoints at zero and one. Position values are fractions of the display dimensions. The reference display is 1800 by 1169 points.

Implemented by ChromaPreset and ChromaAppearance. The bundled resource matches this export. See `../verification/chroma-appearances.md` for the source port, geometry adaptations, native composition and verification limits.
