# Around Input presets

Presets run before the general composer detector. Switch them individually under Dictation settings → Input presets. All are enabled by default. Disabling one restores automatic detection for that target.

| Preset | Identity and boundary |
| --- | --- |
| Claude AI | claude.ai or Claude desktop. Bounded composer container, including adjacent controls. |
| ChatGPT | chatgpt.com, chat.openai.com or the native ChatGPT app. Compact composer container. |
| X | x.com, twitter.com or the native app. Focused editor bounds. |
| Discord | discord.com, Discord desktop variants or Swiftcord. Compact composer container. |
| WhatsApp | web.whatsapp.com or WhatsApp desktop. Message composer container. |
| Telegram | web.telegram.org or either native Telegram client. Message composer container. |
| Messages | Apple Messages. Padded message field or its local controls container. |
| T3 Code | Installed com.t3tools.t3code desktop app. Composer with room for its control row. |
| Gemini | gemini.google.com. Composer including side controls. |
| Google | Google search domains listed in InputTargetPreset. Search container. |
| Safari | Native toolbar field only. Known websites use their site presets. |
| Codex | com.openai.codex desktop app. Composer with room for its control row. |
| Terminal & Claude Code | Terminal, iTerm2 or Ghostty. Cursor row across the exposed viewport. Requires a collapsed selection and caret bounds. |

Composer presets use app-specific size limits and corners. They select actual Accessibility container rectangles and do not invent outer padding. They bypass ComposerTargeting when successful. Missing, incomplete or unsafe matches fall back to the existing detector. Field discovery still needs macOS Accessibility access.

Website identity comes from AXURL on the nearest AXWebArea in the focused editor's ancestry. No browser automation, page JavaScript, address-field value, window title, field contents or screen image is read. URLs remain transient and local. Only the host participates in matching. Terminal geometry reads AXSelectedTextRange offsets and AXBoundsForRange, never selected text or terminal output. If a terminal does not expose caret geometry, the terminal preset cannot supply a target.

Verification uses the existing measured ChatGPT and Gemini trees at 75%, 100%, 150% and 200% scale. Other targets use synthetic trees. The reader checks routing without calling the automatic resolver, fallback, disabling, changed focus, changed URL, moving geometry, secure fields and forbidden content reads. Native menu checks exercise every switch and reconstruct AppState to check saved values. No live app/site compatibility, terminal-client compatibility or cross-app visual accuracy is claimed.

Commands:

```sh
bash scripts/test.sh
bash scripts/build-app.sh
build/S2T.app/Contents/MacOS/S2T --verify-input-presets
build/S2T.app/Contents/MacOS/S2T --verify-input-outline
build/S2T.app/Contents/MacOS/S2T --verify-menu-highlights
build/S2T.app/Contents/MacOS/S2T --verify-build
```

Build 287, version 1.0.1, passed all 215 service/domain tests and the packaged `--verify-input-presets`, `--verify-input-outline`, `--verify-menu-highlights` and `--verify-build` checks. Compiled identity, bundle metadata and menu identity agree. The packaged hidden-window checks passed; an earlier debug invocation timed out before receiving the input backdrop profile. No live receiving apps were opened or inspected.

## Flush contour correction

The old renderer enlarged every input rectangle by three points and added three points to its corner radius. The correction removes both offsets. Fractional field coordinates survive conversion to panel-local coordinates without rounding the field itself.

Compact ChatGPT and Gemini measured layouts now retain exact semicircular ends at every tested scale. Claude uses 20-point circular corners. Presets carry their corner style through the native blur map, color field, clipping, frequency deformation, palette cycle, processing and geometry cache. Automatic detection and native Safari/Messages retain continuous corners.

The baseline tests reproduced the gap and fixed-radius mismatch with 32 failed assertions. Generated fixtures use an independent expected circular boundary to check inside/outside corner distances and native blur alpha. Hidden production panels verify all four physical edges and switching between circular and continuous contours. These fixtures establish the implementation's geometry, not pixel-perfect live website matching.

Version 1.0.1, Build 291 passed 216 domain/service tests and the packaged input-outline, gradient-cycle, appearance-sliders, appearance-performance, menu-highlights and build-identity checks. Input-outline includes the new preset/flush-edge checks. Generated `build/input-flush-fixtures/flush-chatgpt.png` and `flush-claude.png` were inspected. They show authored fields, not captured app windows. The slider verification now preserves existing preview tuning when checking width/minimum/maximum persistence instead of assuming default tuning.

## Rounded-corner scaling and refresh

Automatic targeting no longer clamps measured padding to 8–16 points. It uses the smallest positive editor inset and fits the radius within both field dimensions. Unknown websites use circular corners rather than native continuous smoothing. Standalone fields without measurable external padding retain the existing eight-point fallback.

Rounded preset radii scale with nearby controls instead of multiline editor height. ChatGPT and Gemini use the 30- and 29-point control metrics in their measured fixtures. Other presets use a nominal 28-point control metric. Compact icons take priority over wide model selectors. These nominal metrics remain estimates, not CSS measurements. A missing control metric retains the preset's unscaled radius. Capsule ends still derive directly from the full field height.

The reader no longer reuses a shape classification solely because editor and container sizes match. It rebuilds the bounded local control snapshot on each read, so controls moving into a footer or an editor moving inside its wrapper can change the corners immediately. Editor identity caching, off-main-thread reads, deadlines, secure-field rejection and final focus checks remain.

Independent scale tests reproduced 200 failed assertions before the correction. They cover 50–300 percent scale and multiline growth. Additional fixtures check that inserting wide model selectors preserves the radius and that moving controls inside unchanged bounds switches out of and back into a capsule. Accessibility does not expose actual CSS corner radius; these checks do not prove exact matching across every live app or website.

Version 1.0.1, Build 298 passed 218 service/domain tests and the packaged input-outline, gradient-cycle, glow-clarity and build-identity checks. The new control-position regression passed through the production reader. A debug input-outline invocation timed out waiting for its initial backdrop profile; the packaged check passed. Packaging retried after concurrent source edits and retained the other work in the canonical app. No receiving apps were opened or inspected, and no screen pixels were captured.

A concurrent package then advanced the canonical app to Build 299 with these changes retained. Its input-outline and build-identity checks also passed.
