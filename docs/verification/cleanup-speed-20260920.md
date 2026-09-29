# Same-model cleanup speed check

The user authorized up to 10 S2T credits for generated-text comparison, while retaining the current cleanup quality. No app settings, provider keys, model, prompt, or production service configuration were changed.

The runner uses the compiled production CreditsAPI and its default editing instructions. It compares GPT-OSS 120B with Low reasoning on the existing Cerebras FP16 host against DeepInfra Turbo BF16. The planned three paired fixtures cover spoken corrections, numbers, negation and recipient requests. The alternative uses the same model, but equivalence across hosts would still require checking its actual output.

The first Cerebras request completed in 0.826 seconds. Server timing attributed 0.610 seconds to the provider call, 0.012 seconds to durable confirmation, 0.622 seconds to the ledger request and 0.791 seconds to the edge round trip. The generated output correctly changed Thursday to Friday, retained 240 euros, preserved the instruction not to invite the supplier, and kept the requests addressed to the recipient.

The alternative-host request returned HTTP 400 in 0.070 seconds. It produced no successful inference result and must not be counted as a fast result. The comparison stopped. A subsequent authenticated read reported openRouterCatalog=false, only the Cerebras host for GPT-OSS 120B, zero pending credits and no spending pause. The rejection body was not retained, so its precise error code is unavailable. Public OpenRouter endpoint availability does not establish availability through this deployed S2T service.

Confirmed charge was 0.1434 credits for the successful request. The local budget retains a conservative 3.6258-credit commitment, including the unrefunded maximum assigned to the rejected attempt. It was not reset, and there were no automatic paid retries. The test did not read user dictation, microphone audio, clipboard text, screen pixels or custom writing instructions. Credentials were accessed noninteractively and remained in memory.

This is one successful baseline sample, not a demonstrated speed improvement or completed host comparison. No app rebuild was warranted because no app implementation changed. Testing another host requires that route to be supported by the live S2T service first. No route or allowlist was broadened as part of this check.

Runner, generated fixture output, request timings and persistent budget are in build/cleanup-speed-20260920. The existing budget prevents a fresh paid run from resetting the authorization.
