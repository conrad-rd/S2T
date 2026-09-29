# Model benchmark ranking

The Models overview compares published model results. It does not run recordings or make paid requests.

- Dictation includes Grok Voice Transcribe 2/1, AssemblyAI Universal 3 Pro, OpenRouter Nova 3, Voxtral Small and GPT Transcribe, plus the complete local catalog. Universal 3.5 Pro remains explicitly unranked until a matching comparable result is available. It never inherits Universal 3 Pro's score.
- Processing combines OpenRouter gpt-oss 120B, gpt-oss 20B and GPT-4.1 mini with local models on the same AA Intelligence Index version. Estimates and reasoning settings remain attributed.
- Vision includes Gemini 2.5 Flash and local model-card results on MMMU.
- Each enabled category contributes an equal share of the total. Min/max scaling uses the full task catalog for that category. Lower error/cost and higher quality/speed score better. Equal measurements receive equal points; tied totals share a rank. With every category disabled there is no ranking.
- Models missing an enabled measurement remain visible below the chart with the missing categories named. They receive neither a zero value nor an average over fewer categories.
- Speech quality can switch between AA-WER v2 and FLEURS English. Those results are never mixed. Local Whisper Turbo has an explicitly labeled hosted parent-model quality reference, without claiming measured Mac performance. Local speed remains unknown. Local API cost is zero, excluding hardware and electricity.
- Cloud speed and prices are dated reference API snapshots, not actual OpenRouter routes or S2T billing. Speech speed is AA's 10-minute audio speed factor, not short-dictation latency. Text cost uses the stated 3:1 input/output token blend. Every available measurement links to its source.

Sources checked September 21, 2026:

- https://artificialanalysis.ai/speech-to-text/models/assemblyai
- https://artificialanalysis.ai/models/gpt-oss-120b
- https://artificialanalysis.ai/models/gpt-oss-20b
- https://artificialanalysis.ai/models/gpt-4-1-mini
- https://artificialanalysis.ai/models/gemini-2-5-flash
- https://storage.googleapis.com/deepmind-media/Model-Cards/Gemini-2-5-Flash-Model-Card.pdf
- https://openrouter.ai/api/v1/models?output_modalities=transcription

API keys now uses flat rows. The provider is on the left and the key control is on the right. Idle controls render blurred fixed dots, without rendering secret characters. Editing reveals a plain borderless field. Leaving editing masks the value and retains unsaved drafts. Save continues to validate the key through the existing account-specific code. Get key, Manage limits and Unlock remain available.

Verification:

- `bash scripts/test.sh` includes independent synthetic cases where quality, speed and cost each choose a different winner, a combined winner loses in quality, missing data excludes a model, and ties remain equal.
- `bash scripts/build-app.sh` packages the canonical app.
- `--verify-models-window` checks the default cloud/local coverage, switch bindings, stack geometry and hidden chart layout at widths 420, 600 and 950, plus existing provider/model navigation.
- `--verify-api-keys` checks isolated drafts, validation, stale responses, recording guards and flat row geometry with long fake keys at widths 420 and 600.
- Run `--verify-local-models`, `--verify-settings-sidebar` and `--verify-build` on the package.

These are capture-free checks. They do not claim pixel-level visual verification, physical keyboard testing or live provider benchmarking.

Verified S2T 1.0.1 Build 751 on September 21, 2026. All 433 domain tests passed. The packaged API key, Models window, Local models, settings sidebar and build checks passed. The key check additionally verified an actual native borderless editor and removal of secret characters from the idle view. The Models check exposed a stale header-bounds snapshot; verification now converts the current native bounds instead of retaining coordinates across header resizing. The running app was not restarted.

## Live inspection and layout correction

Computer use on September 21 confirmed that the released page had a nested horizontal chart scrollbar and expanded every Apple Speech language into its own missing-result row. Enabling Speed changed the actual ranking and moved local models with unknown speed out of the ranking. The API keys page exposed masked flat rows and an existing unsaved xAI draft. No saved key was revealed or changed. The computer-use session subsequently became inactive during an attempted check of the empty TypeSafe field, so that live editing check did not complete.

The correction fits the chart to its viewport, groups Apple Speech languages as one benchmark engine and moves source notes and missing measurements into native popovers. The initial page has no selected-model inspector. Model selection opens the score breakdown. The three configured task rows now share one compact native group. Tests cover native-language deduplication and hidden chart widths at 420, 600 and 950 points. Real language/model routing and key drafts remain unchanged. No screen pixels were captured or inspected.

Build 752 validation: all 434 domain tests passed, including the Apple-language regression that failed before the fix. The canonical packaged Models window, API keys, Local models and build-identity checks passed. The revised chart's native bounds equal its available viewport at all three tested widths. The running process was preserved because live inspection found an unsaved xAI key draft. The revised build has hidden interface verification; it has not been reopened over that draft for a live visual review.

## Settings subsections

The Models landing page now uses a native grouped Form. Speech to text, Text cleanup and Vision show their current model in chevron rows. Benchmarks and Local models occupy a second group. Each task keeps its provider visible and opens model choices, hosting/response, extra cleanup and connections on separate pages. Back returns to the parent task, then Models. Native controls remain mounted across navigation, and provider/model behavior is unchanged. The benchmark retains its scoring and cloud/local coverage in its own page. API keys keeps flat inline editing.

The hidden Models probe checks that opening task and benchmark pages does not change model choices, advanced controls stay hidden on parent pages, Model and Codex connection pages isolate their controls, Back restores the parent and existing keyboard/model-routing checks still pass.

Build 753 validation: all 434 tests passed. The canonical packaged Models window, API key, Local models, settings sidebar and build-identity checks passed. The package is S2T 1.0.1, built September 21, 2026 at 18:47:11 UTC. No screen capture or live provider requests were used. The running app was preserved to retain its unsaved xAI key draft.

## Column popovers and stroke boundaries

Score details now attach to a one-point anchor at the selected column's top, using Swift Charts plot positions. This gives the native popover a pointer to the selected model instead of the center of the entire chart. Strokes share a continuous 3.3-point score grid with a consistent gap. Each gets the shade of the category occupying most of that interval. Only the final stroke may be shortened. Exact contributions, totals and rankings are unchanged. Sources explains the visual rounding. Hidden geometry checks cover individual anchors within the chart at 420, 600 and 950 points, distinct anchor ordering and full interior stroke heights across category boundaries.

Build 754 validation: all 434 tests passed. The packaged Models window check passed, including point-anchor bounds at 420/600/950 points and continuous full-height interior strokes. Build identity confirms S2T 1.0.1 Build 754, built September 21, 2026 at 19:03:24 UTC. No visible windows, screen capture, live provider requests or running-app restart were used. Native popover placement was checked structurally, not visually.

## Artificial Analysis integration and top five

Models now opens with the benchmark. Quality is the initial criterion; switches still include/exclude categories from the combined score. Rank the entire candidate set before selecting five distinct models. For each model, retain the highest-scoring measured host under the active criteria. The All models popover contains the complete candidate list. Configuration remains in Model settings. With only Speed enabled, language models are ordered by output TPS and show TPS below the host name. Speech retains its distinct audio speed-factor unit.

The integration follows https://artificialanalysis.ai/data-api/docs and the public OpenAPI specification at https://artificialanalysis.ai/api/v2/openapi. It authenticates with an independently stored `x-api-key`, reads every page, and fetches:

- `/language/models/free` to establish access and obtain Free headline indices.
- `/language/models` for Pro/Commercial model metadata and MMMU-Pro.
- `/language/providers` for Commercial provider-specific median output TPS and matching prices.
- `/media/speech-to-text/models/free` or `/media/speech-to-text/models` for ASR quality and available provider measurements.

Model-level speed aggregates are intentionally not used as host-specific TPS. Nulls remain unknown. Vision uses MMMU-Pro separately from bundled MMMU scores. Static local Intelligence Index references are excluded when the live major/minor index version differs from 4.3. API responses are cached locally without credentials for six hours; a key fingerprint separates accounts. A key change clears old-account results. Redirects from Artificial Analysis are rejected to protect its header. The native key editor uses the existing credentials-v1 Keychain vault, draft/save/validation flow and read-only validation endpoint.

The user has no Artificial Analysis API key yet. No authenticated live pull has been performed. Until a key is saved, the interface explicitly labels reference data. Free/Pro access cannot supply provider TPS; Commercial access is required. No subscription was purchased or account created.

The bundled text reference set was expanded with GPT-5.4, Claude Opus 4.6 and Gemini 2.5 Flash from their AA model pages, plus GPT-OSS 120B measured on Cerebras at 1744.5 output TPS from https://artificialanalysis.ai/models/gpt-oss-120b/providers as read on September 21. These are dated references, not live API responses. Existing cross-provider GPT-OSS averages no longer count as host speed. OpenRouter-compatible models display the actual benchmark host, without claiming that OpenRouter's route was measured.

Offline fixtures cover more than five models across multiple model/provider pages; a later-page Cerebras GPT-OSS result must win Speed, while the Groq endpoint keeps its lower result. They also check null speed, ignored aggregate TPS, stable model deduplication, speech units and pricing, MMMU-Pro isolation, key headers, HTTP failures without secret leakage and snapshot round trips. Hidden app checks cover no API calls without a key, cache reuse, clearing data on account changes, reference labels for unavailable tasks, native key editing and the top-five chart at 420/600/950 points.

Build 755 validation: the full 439-test suite passed. After adding one more reference-catalog regression, all six focused Artificial Analysis tests passed, including five distinct no-key Speed results led by GPT-OSS 120B on Cerebras. The packaged Models window, API keys/feed lifecycle, Local models and build identity probes passed. Identity is S2T 1.0.1 Build 755, built September 21, 2026 at 19:31:37 UTC. The running app was preserved. No authenticated live AA request or visual screen inspection was performed because the user has no key and screen capture is prohibited.

## Free endpoint correction

The user supplied https://artificialanalysis.ai/api-reference and its documented `/api/v2/data/llms/models` endpoint. This is now the primary feed and key-validation endpoint. Its envelope is `status` plus `data`, without required tier/pagination metadata. The decoder uses top-level `median_output_tokens_per_second` and the supplied `price_1m_blended_3_to_1`. Speed ranking works with free data and never uses time to first token as TPS.

Free model-level results are labelled AA reference with no claimed hosting provider. The creator is not treated as the measured host. An optional provider lookup can add named-host results; 403 access denial preserves the free results. Named-provider rows never fall back to model-level TPS when a host measurement is null. The newer paginated API remains a compatibility fallback only if the supplied endpoint returns 404 or 410. Speech uses its existing endpoint independently. Unreported intelligence versions remain unknown and are not silently mixed with dated local intelligence results. The account-scoped response cache uses a new version so previous discarded-TPS results and Commercial-warning text cannot linger for six hours.

New fixtures use the exact documented response shape, including a model with low TTFT but lower TPS than another model. Ranking must follow TPS, preserve fractional values and blended prices, keep stable IDs, and never identify the reference result as Cerebras or OpenAI. Null TPS remains unranked for Speed. Tests also retain the newer-API pagination and provider-isolation checks. The user still has no key; authenticated live responses remain unverified.

Free-feed correction validated in S2T 1.0.1 Build 758, built September 21, 2026 at 20:29:44 UTC. All 442 tests passed, followed by the packaged Models window, API-key/feed lifecycle and build-identity checks. The first package attempt encountered an unrelated sidebar-probe edit during Swift compilation; rebuilding preserved the newer concurrent work. No running-app restart, real-key access or authenticated live data request was performed.

## Whole bars only

Column heights now round to the nearest whole stroke count. Every stroke has the same 2.6-unit height on the existing 3.3-unit grid, including the top stroke. Each stroke keeps one category shade. Exact numeric scores and ordering are unchanged. Popover anchors follow the rendered top rather than the unrounded score. This supersedes the earlier partial-final-stroke behavior.

The hidden Models probe checks all stroke heights and independent rounding fixtures at 0, 1.64, 1.66, 3.3, 4.94, 4.96 and 100 points, with expected counts 0, 0, 1, 1, 1, 2 and 30. The fixtures also assert that scores retain their original precision. All 442 service/domain tests and the debug Models probe passed. No screen capture was used.

Packaged verification passed for S2T 1.0.1 Build 760, built September 21, 2026 at 20:40:16 UTC. The packaged Models probe passed the whole-stroke rounding checks and hidden layout checks, and --verify-build confirmed the executable, metadata and menu identity match. Updated build/S2T.app without restarting the running app.

## Full speech catalog and public refresh

The two-model regression came from newest-family pruning plus matching OpenRouter benchmarks against three Whisper suggestions and mismatched route prefixes. Speech now retains all offered versions, normalizes OpenRouter route prefixes, shares its 21-entry public catalog with the model menu, and appends unmeasured offerings to All models. Direct Mistral is not added; Voxtral routes are labelled OpenRouter and their measured host remains in the source notes. Missing AA-WER scores are never invented for new or streaming models.

The public Artificial Analysis speech page has a server-rendered measurement table. The keyless feed parses its named columns, matches both model and measurement host, rejects incompatible tables, and caches successfully refreshed speech data for six hours. Text/vision remain explicitly dated references when the public source contains only speech. API credentials remain optional and hidden.

A real anonymous request on September 21 returned 21 OpenRouter speech choices, 25 offered hosted models in the focused fixture, 14 measured models and five ranked columns. The fixture uses both xAI versions and AssemblyAI 3/3.5 alongside OpenRouter; the production screen also includes Universal extended languages and local models. The debug public-feed, hidden API-key and Models checks passed, with no credentials, clipboard access, screenshots or visible windows.

Validated in canonical S2T 1.0.1 Build 771, built September 21, 2026 at 21:31:57 UTC. All 447 tests passed. Packaged anonymous public-feed verification again returned 21 OpenRouter choices, 14 measured hosted models and five chart columns. Packaged hidden API-key, Models and build-identity checks passed. The running app was preserved.
