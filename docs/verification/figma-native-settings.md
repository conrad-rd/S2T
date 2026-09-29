# Figma settings implementation

Reference: https://www.figma.com/design/2EIk9uNHoq3bXncYlpgr1y/S2T

September 21 changes use native controls rather than reproducing the drawn control artwork. The later benchmark and flat API-key row changes are documented in model-benchmark-ranking.md and supersede the initial designs below.

- API keys uses a SwiftUI grouped Form with DisclosureGroup rows. Each row retains its draft editor, explicit Save, key validation, error state and provider link. TypeSafe remains available alongside the four providers in the design. Unlock remains actionable when the credential store is locked.
- Models opens with three compact native menus for Dictation, Processing and Vision. Their actions reuse the existing model selection/validation code. The displayed value is the actual saved model. Configure and Advanced Settings open the existing task pages, including local models, hosting, custom IDs and reasoning. Back to Models returns to the overview.
- The benchmark card uses Swift Charts, native source/task pickers and three switches. It uses the existing source-attributed local parent-model quality data. No cloud benchmark integration or new speed/cost measurements are implied. Speed and Cost explicitly report unavailable comparable measurements. The duplicated Cost switch in Figma is omitted at the user's request.
- Appearance uses the standard NSSegmentedCell, preserving native drawing and interaction. The mode and adjustment bars are 228 and 195 points wide with 9-point outer insets. Custom hover/selection painting is removed.
- Bottom and Notch preview artwork uses the original Figma image layers, bundled locally. AppearanceDesignArtwork records their source geometry and composes them with AppKit. The live preview uses the same display edge/notch coordinates. Input and Classic artwork remains unchanged.

Verification uses the canonical packaged app, synthetic credentials and hidden windows. Never capture the screen or restart the running app. Run the domain suite with scripts/test.sh and package with scripts/build-app.sh. Check --verify-api-keys, --verify-models-window, --verify-local-models, --verify-appearance-selection, --verify-appearance-window, --verify-settings-sidebar and --verify-build sequentially. Additional routing checks use --verify-models and --verify-credits.

These checks establish control actions, geometry, source data and packaging. They do not establish pixel parity or physical interaction with the running app.
