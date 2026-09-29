# Privacy and policies verification

September 17, 2026. Canonical package: S2T 1.0.1, Build 580.

Added six static policy drafts: privacy, terms, refunds/withdrawal, cookies/storage, legal notice and security reporting. The confirmed operator is Conrad Baulig and the confirmed public email is info@conrad-baulig.com. The postal business address remains unconfirmed. The pages remain marked as drafts and no website or Worker deployment was performed.

Verified changes include opt-in clipboard history for new installations with existing choices preserved, disabled optional Clerk SDK telemetry, OpenRouter cleanup/image routing that excludes data-collecting endpoints, window-scoped HMAC rate identifiers, active-database expiry and last-use-only device attribution.

- 52 billing tests passed, including expiry boundaries, restart-stable rate limits, legacy schema migration, replay identity, money preservation, device minimisation and account isolation.
- Cloudflare dry-run and local runtime integration passed with mocked external calls. A test-only Durable Object subclass invoked the actual alarm, checked expired ciphertext and rate-row removal, verified alarm rescheduling and compared unchanged account summaries. The fixture subclass is not in production source.
- Existing dashboard browser verification passed. Policy browser verification passed at 320, 768 and 1280 pixel viewport widths, with six working links, checkout links, no third-party requests on policy pages, no scripts on policy pages, and telemetry disabled in the actual Clerk load options through an intercepted fixture SDK.
- Website production build passed. Generated public pages, frontend staging files, website build output and final app resources match.
- 295 S2T core tests passed. The required full scripts/test.sh run stalled in the separate benchmark suite. Sampling its own fixture process showed BenchProcess.run waiting in NSConcreteTask.waitUntilExit. The stalled test process was stopped; no benchmark code was changed. The full suite is not reported as passing.
- Packaged --verify-clipboard passed using preview preferences and an isolated pasteboard. It includes fresh-install opt-in and preserved saved-choice checks.
- Packaged --verify-menu-highlights passed without opening menus.
- Final --verify-build passed for Build 580, including six enabled offline policy actions, bundled text and matching compiled/bundle/menu identities. Code signing and package private-state checks passed.

No real payments, provider credentials, account content, user clipboard, microphone capture, screen capture or Raycast were used. Live provider compatibility and hosted provider settings were not tested. The service maintenance code has not been deployed or run against the real ledger. Remaining publication and operational requirements are recorded in docs/legal/OPERATIONS.md.

## Small app link correction

Build 581 removes the policies root menu command and all six submenu actions. One understated, underlined 11-point Policies link now sits at the bottom of the existing settings sidebar and opens the bundled privacy page. Its page navigation reaches the other policies. Website footer links are unchanged.

Packaged --verify-build, --verify-settings-sidebar and --verify-menu-highlights passed. The hidden sidebar check verifies the link's font, accessible name, contained bounds, separation from navigation, and actual button dispatch through an injected URL handler. No browser, menu or visible diagnostic window was opened. No screen capture was used.
