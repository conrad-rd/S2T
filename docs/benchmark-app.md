# S2T Bench

Build the separate native macOS app with `bash scripts/build-bench.sh`. Open `build/S2T Bench.app`. Packaging also updates the canonical `build/S2T.app` and embeds that exact production engine in the companion. S2T Bench has its own bundle identity, window and local data directory.

## Stress tests

Harsh is the default. Endurance increases run duration and repetitions without relaxing thresholds. Every result retains failures, timeouts and skips. The seed reproduces fixture order and generated metadata. Hardware load can still change timings.

- Animations exercise Bottom, Around Notch, Around Input and Within Input with changing frequency balance and full padded native fields. A second workload changes input geometry, notch tuning or display width. Eight workloads measure cold preparation, completion throughput, frame-gap percentiles, worst gaps and main-loop stalls. Separate 2× offscreen Canvas samples measure drawing cost.
- The animation gate requires at least 57 prepared frames per second, p99 gaps at most 33.334 ms and no gap over 100 ms. Cold preparation is reported separately. Canvas drawing over 100 ms also fails. These are deliberately demanding limits, not claims about previous S2T performance.
- Input checks exercise production Accessibility readers with generated geometry, secure fields, competing focus, stale bounds, attachments, negative display coordinates and fractional positions. Each repeat includes 400 seeded hostile metadata cases. Existing capture-free production checks also cover both input appearances, registered hidden panels and fallback recovery.
- Reliability uses production fixtures for provider-key isolation, stale responses, clipboard persistence, model routing, permissions, shortcuts and Liquid Glass lifecycle.

No screen or microphone capture is performed. Generated image rendering reads only authored offscreen content. Prepared frames per second are not screen-presented FPS. Synthetic Accessibility coverage does not establish compatibility with every live app. Heavy workloads are bounded and cancellable.

## Prompt and model comparisons

Prompt A starts with S2T's default prompt. Load S2T prompt into A reads the user's existing file without changing it. Prompt B starts with a deliberately compact candidate. Both pass through S2T's actual dictation request builder and formatting contract.

The 24 built-in cases cover role injection, fake system delimiters, recipient requests, negation, corrections, exact identifiers, mixed languages, Unicode, quantities, long context and opaque markers. Add one custom input with an expected exact output. Case order is seeded, and the first variant alternates between A and B to reduce ordering bias. Requests run sequentially to avoid contention between models.

Choose a loopback endpoint for Ollama or another compatible server, installed S2T text models, OpenRouter or Cerebras. Enter model IDs separated by commas. Model IDs and OpenRouter hosting endpoints remain separate. Installed models run in a separate offline worker, with one model loaded at a time and physical-memory checks. S2T continues to own installation and repair.

Paid requests start only with Run paid API comparison. The selected key remains in memory and clears when changing providers. It is never read from S2T's Keychain or written into benchmark preferences, reports or process arguments. Redirects are rejected. Requests have deadlines, bounded responses, a maximum output-token parameter and an overall request count. Providers may enforce their own parameter limits. The request cap is not a dollar spending limit.

Token counts, cached and reasoning tokens, and cost are recorded only when the provider returns them. Missing values are unknown, never estimated or zero-filled. See the [OpenRouter response schema](https://openrouter.ai/docs/api_reference/overview) and [Ollama compatibility documentation](https://docs.ollama.com/api/openai-compatibility). Local workers may not report token usage.

The comparison summary reports failures in A and B, new candidate failures, p95 latency and input-token savings on matched passing pairs. Assertions check explicit invariants and exact outputs, not general semantic quality. Inspect outputs before adopting a candidate. Failed requests and incomplete answers remain failures. A run reaching its request cap records the unrun count as skipped.

## Reports and automation

Speech tests installed MLX speech models. Speech fixtures are synthesized during packaging, with clean, fast, quiet and 10 dB noise variants. The score measures word errors, preserves both explicit negations and requires faster-than-real-time processing. First requests include model loading. Apple-managed speech models are outside this MLX worker suite.

Runs save atomically under `~/Library/Application Support/S2T Bench/Runs`. Default saved reports omit prompt inputs and outputs. Export can include them when its checkbox is enabled. API keys are never part of the report schema. Prompt drafts save separately in the same benchmark directory; they do not replace S2T's prompt.

Load a prior JSON report with Compare baseline. Matching result rows show metric changes only for matching workload settings. Retain machine metadata when interpreting results. No report is automatically deleted.

Run a packaged suite without opening a window:

```sh
"build/S2T Bench.app/Contents/MacOS/S2TBench" --run-suite animations --seconds 30 --seed 42
"build/S2T Bench.app/Contents/MacOS/S2TBench" --run-suite inputs --repeats 10 --seed 42
"build/S2T Bench.app/Contents/MacOS/S2TBench" --run-suite reliability
```

Each result is a JSON line prefixed `S2TBENCH`. The CLI exits nonzero if the engine crashes, times out or reports a failed check. Use `--verify-bench` for hidden UI, provider isolation and persistence checks. `bash scripts/test.sh` includes independent benchmark statistics, corpus, request, token, timeout and cancellation tests.

`python3 scripts/run-bench-report.py --save-to-history` runs all synthetic suites sequentially and saves a JSON report in `build/bench-verification-report.json` and the app's Saved runs. The script exits nonzero when a benchmark fails. `python3 scripts/verify-bench-network.py 'build/S2T Bench.app/Contents/MacOS/S2TBench'` verifies the complete comparison flow against an independent local HTTP fixture, without real model requests or credentials.
