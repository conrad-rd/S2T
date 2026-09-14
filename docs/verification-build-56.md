# Build 56 verification

S2T 1.0.1, Build 56.

Around Input previously used capsule rounding only for accessibility search fields or search landmarks. Ordinary chat inputs received a smaller content-spacing radius even when their layout matched a capsule.

The shared geometry rule now recognizes compact centered editor/control rows, checks that their contents fit inside circular end caps, and recognizes generously padded single-line fields. All distances scale with field and control dimensions. Tall editors, footer composers and ambiguous plain fields retain the prior content-spacing radius. Boundary selection is unchanged. No application names, website selectors, text reads or pixels enter the detector.

The renderer uses a circular Capsule path when the radius reaches half the outline height. Other outlines retain continuous corners. Cached shape is re-evaluated when the selected container changes size.

Domain verification passed with 103 tests. The new cases cover capsule rows at three scales, padded single-line fields, ordinary rectangular fields, multiline editors and separate footer rows. Recorded ChatGPT and Gemini geometry now selects capsule shape while the measured footer composer retains its existing radius. The production reader probe also checks non-search capsule detection and cached reads.

Packaged verification results are recorded in build/capsule-verify-build.log, build/capsule-verify-outline.log and build/capsule-verify-menu.log. These checks use metadata and hidden windows. They do not establish a pixel-level match to third-party border styling. No screenshots, screen pixels or Raycast inspection were used.

All three packaged probes and codesign verification passed for Build 56, compiled 2026-09-13T11:09:20Z. Packaging overlapped another build in the shared workspace; verification used that completed package after it finished. The package includes the capsule reader checks and renderer changes.
