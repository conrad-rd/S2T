# Publishing source safely

Keep provider and payment secrets in macOS Keychain, your host's secret store, or ignored local environment files. Never include recordings, customer data, recovery codes, database exports, browser sessions, or audit captures in a source commit. Public legal notices and service URLs are intentional application content.

`billing-local/wrangler.jsonc` is a portable demo configuration. For a deployment, copy it to `billing-local/wrangler.local.jsonc` and configure your own account, identity provider, approved pricing, and independently reviewed funding controls. The local override is ignored. `npm run deploy:cloudflare` requires that override; secrets belong in the Worker's secret store. Do not deploy the current billing candidate to production until the prerequisites in the dated billing security report have been handled.

The frontend deploy helper uses its local Vercel project link; `VERCEL_SCOPE` can select a team explicitly. Hosted identity verification requires `S2T_TEST_ORIGIN`, `CLERK_TEST_APP_ID`, `CLERK_TEST_USER_ID`, and `CLERK_FAPI` for a dedicated test instance. Keep those account settings outside Git.

Before pushing, inspect the exact staged paths and diff, then scan with Gitleaks:

```sh
git diff --cached --name-status
git diff --cached --check
gitleaks git . --log-opts=HEAD --redact=100
```

The history command scans committed changes, so run it again after committing. Also scan an isolated copy of the staged tree with `gitleaks dir` before committing; a working-directory scan can include private ignored files and is not the same as checking the publication candidate. Keep reports local and use redaction.

The repository scanner configuration extends all default rules. Its narrow exceptions cover an environment-variable expression, two synthetic idempotency identifiers, and historical Clerk publishable browser keys. They do not allow provider keys, Clerk secret keys, or arbitrary test credentials.

Before changing repository visibility, scan every GitHub branch and tag, plus release attachments and any uploaded artifacts. Ignoring or deleting a secret from the current tree does not remove it from history. If a real credential has been published, revoke or rotate it and handle historical copies before making the repository public.
