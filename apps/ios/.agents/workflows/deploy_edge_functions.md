---
description: Enter the reviewed Supabase production deployment workflow
---

# Deploy Supabase Edge Functions

Use the repository's canonical
[Supabase deployment runbook](../../../../docs/backend-and-data/06-supabase-deployment-runbook.md).
This file is an agent entry point, not a second deployment procedure.

Production deployment authority is the reviewed GitHub `Production` workflow on
an exact source SHA. Do not replace it with a local `supabase functions deploy`,
dashboard deployment, ad-hoc database push, or manual secret mutation. The
workflow enforces the exact Supabase CLI pin, complete migration history,
Function fleet planning, secret synchronization, pre/post-deploy verification,
and evidence artifacts.

Use **Supabase Candidate Validation** first when the objective is evidence. It
replays the exact candidate against a disposable database and runs the complete
Edge/database suite without receiving production secrets or mutating
production. A green candidate run does not authorize deployment.

## Consent release hold

`CONSENT-001` through `CONSENT-010` are closed in source. Do not enter the
Production job or run strict consent cutover until the same immutable SHA passes
both hosted gates and the external production controls in the
[production consent readiness record](../../../../docs/legal/production-consent-readiness-2026-08-03.md).
The bounded rollout is:

1. Prove **iOS Build and Test** and **Supabase Candidate Validation** on the same
   SHA. The latter is validation-only and must report no production mutation.
2. After separate production authorization, deploy the additive schema and
   consent-gated Edge code while
   `internal.ai_consent_rollout_config` remains `legacy_compatible`.
3. Distribute and verify the corrected replacement TestFlight build.
4. Expire old consent-incapable builds.
5. Only then run the owner-only forward strict-cutover script and verify
   deployed rejection fixtures.

Never backfill or infer adult, Terms, Gemini, or analytics evidence.

## Required local preflight

Run the complete repository tooling and migration contracts; tests are not
optional. If a response DTO or schema changes, update and compile the matching
Swift DTO before deployment. Do not use real personal data in local or unpaid
provider tests.

```bash
bash services/supabase/scripts/require_supabase_cli_version.sh
bash services/supabase/scripts/test_supabase_tooling.sh
make validate-supabase-migrations
```

The exact production secret is `GEMINI_PAID_API_KEY`; no unpaid-key fallback is
permitted. Do not treat its name or presence as billing/DPA evidence. A Google
Cloud owner must archive active paid billing and DPA confirmation, rotate the
key, let the production workflow synchronize it, smoke-test it, and revoke the
superseded key. Never put a secret value in source, logs, tickets, or command
output.

After deployment, use the runbook's bounded positive and negative smokes and
structured monitoring. Verify the fixed handler marker, caller-safe status/code,
database state, and provider/analytics admission without printing credentials or
operational response bodies.
