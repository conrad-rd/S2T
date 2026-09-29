# Provider cost pause recovery

September 19, 2026. Live health showed a single invalid_cost incident for OpenRouter request 9dd69a47-5945-4ab1-a5f8-6ce5790719f6. Its 250-microdollar reservation remained uncertain and the entire service was paused. No cost or provider receipt had been stored. The exact rejected response is unavailable; its format cannot be established from the incident alone.

The cost parser rejected scientific notation and decimals longer than 12 fractional digits. Both failures were reproduced independently. It now accepts bounded decimal and scientific notation, uses exact integer arithmetic to round positive fractions upward to one microdollar, and retains the existing maximum charge. Negative, missing, nonnumeric and oversized inputs remain invalid.

An invalid_cost failure now retains only the affected request hold and records the unknown outcome without a global pause. Duplicate requests do not reissue provider calls. Other accounts and subsequent requests can continue. Receipt identity conflicts, over-reservation charges, model mismatches and other ledger integrity checks retain their existing behavior.

Three new regressions cover numeric conversion, invalid values, and the provider adapter through gateway and ledger. Tests first reproduced the old parser rejection and global pause, then passed with the repair. All 125 billing tests passed. cost-pause-deployment-check.mjs runs the same request-isolation assertions against the exact scoped Worker in an isolated Cloudflare runtime. No real provider inference, payments, recordings or screenshots were used.

Worker version 65270a59-74c3-42a7-9322-e0a9a552c3bb was published with live configuration, secrets, assets and unrelated code preserved. Exact source readback SHA-256 is 6545e5880ab738286cade8ef501be6bb57ed57a418e976059467798cb7b346b4. Artifacts are in build/cost-pause-repair.

After deployment, the existing audited writeoff absorbed the unknown charge at S2T expense and released the customer hold. Normal resume checks succeeded. Live health confirmed paused=false, no pending requests and no open incidents. This is a server repair; no native app changes or restart are required. The precise original provider charge remains unknown rather than being replaced with an invented receipt.
