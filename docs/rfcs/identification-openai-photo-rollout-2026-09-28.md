# OpenAI photo rollout

Date: 28 September 2026\
Status: optional permission collection and saved-scan recovery implemented in
source and ready for review. Distribution and activation remain pending;
production remains Gemini.

## Adapter enablement follow-up — 28 September 2026

PR 95 merged the optional permission UI and saved-scan recovery. The owner then
requested enabling OpenAI still-photo identification during beta, deferring the
new opt-in step. Adapter deployment and traffic assignment must be separate:
Supabase applies migrations before deploying Functions, so an assignment-first
release would select OpenAI through an older disabled adapter.

This first change enables the production photo adapter without changing routing
rows, prompts, quotas, native moderation, permission records or client checks.
The routing catalog still selects Gemini. Deploy and verify this Function bundle
before the follow-up photo-only catalog activation. Keep the historical
benchmark results; source enablement is not a new benchmark or a claim that the
production binding has completed live qualification. The beta permission-policy
change is separate from this adapter preparation and must preserve explicit
withdrawals without manufacturing affirmative consent.

## Decision and current position

Finish still-photo rollout before further prompt optimization or OpenAI audio.
Keep the original OpenAI prompt and full explanation format. The provider
infrastructure and credential synchronization closed in
[PR 87](https://github.com/emreerdener/merian/pull/87); the
[integration record](./identification-openai-photo-integration-2026-09-27.md)
contains the deployment evidence. No new key setup is needed for that milestone.

The completed six-photo Gemini/OpenAI comparison remains valid development
evidence. The explicit-null prompt experiment is closed inconclusive without a
candidate call. Neither substitutes for qualification of `openai_photo_v1`,
which adds native input/output moderation to the measured baseline.

## Permission and recovery implementation (PR 95)

- Enable optional OpenAI collection in Settings using disclosure `2026-09-26`
  and its existing statement. Gemini onboarding stays required.
- Explain that Naturebook chooses the AI service. A person's permission allows
  disclosure to OpenAI when assigned; it does not change the assignment.
- For `ai_openai_consent_required`, retain the same saved scan, media and
  funding and offer **Review permission** inside the app. Review is available
  offline for the matching stable account. Cancel or withdrawal leaves the scan
  paused.
- After a successful local grant, expose **Retry now** only when the saved scan
  is retryable and online. Saving permission never automatically resumes a scan.
  Explicit retry synchronizes evidence and runs fresh recipient preflight; local
  UI state is not cloud authority.
- Close stale disclosure presentation when the account or presented scan
  changes. Match the scan job's retained funding owner and scan identity before
  exposing recovery and again before any retry mutation; visibility in a local
  library does not authorize resubmission by another account. Mutation and
  transport retain their independent account checks. Failed writes do not
  publish permission; failed withdrawal stays locally blocked and retryable
  without claiming durable revocation across restart.

PR 95 made no database migration, wire/schema change, assignment update,
model/prompt change or production request. Its source dispatch gate remained
false. The adapter follow-up above now enables that composition; every catalog
assignment still selects Gemini until the separate activation migration. The UI
and ledger tests use synthetic local evidence without provider keys. The Release
archive rejects the new fixture marker, and the workflow contract checks markers
from every Swift fixture file in `App/UITesting/`.

## Remaining release sequence

1. **Review and distribute the compatible iOS reader and permission flow.**
   Require current CI, archive/upload through the existing release procedure,
   then verify an actual upgrade from the previously distributed build preserves
   saved observations and launches correctly. Simulator/development installation
   does not close the distribution or upgrade requirement.
2. **Qualify the exact production photo binding once.** Freeze a bounded,
   separately budgeted packet and acceptance criteria before paid execution.
   Reuse existing development measurements; use held-out still photos for
   quality and the full app path for permission, optional-note preservation,
   native moderation/refusal, uncertain execution, save/retry and account-change
   behavior. Report full-path latency and cost separately from provider timing.
   A reviewed failure ends the packet; no automatic replacement or parameter
   sweep. This is production qualification, not another prompt comparison.
3. **Activate by the existing exact-SHA release process.** Prepare the concrete
   photo binding/assignment change and rollback evidence for explicit operation
   and target approval. No reviewed percentage-routing control exists. Audio,
   five ordered video snapshots, description-only and combined observations stay
   Gemini until their own complete-input profiles are qualified. Never fall back
   to another provider to bypass permission or retry a billable attempt.

The [deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md)
and
[provider onboarding contract](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md)
remain authoritative for admission, evidence, activation and rollback. Preserve
new-result readers and existing provenance during a provider rollback.

## Verification evidence

Local preparation verified:

- Focused permission, ownership and presentation suites plus the deterministic
  permission UI smoke: 19 tests passed. This exposed and corrected the system
  dialog's missing explicit Cancel action. Independent review also identified
  the cross-account retry gap, now covered by owned-funding checks and tests.
- Complete offline Edge suite: 2,151 passed, 9 database-dependent tests ignored;
  no live provider calls. All 102 function entrypoints type-checked with their
  deployment configs; 102 dependency graphs across 391 runtime files validated.
- Complete Supabase tooling passed: 455 standard tests, 66 isolated evaluator
  tests, both generated DTO suites and all 12 shell test files.
- Project generation, project/privacy/event-routing/transport guardrails, iOS CI
  tooling, Deno format/lint and changed-Markdown/link checks passed. The full
  iOS pass exposed the queue owner's line ceiling; the ownership query now lives
  in the existing queue-state owner without weakening the guard.

The final complete iOS unit target, five relevant UI smokes and required
current-SHA CI/Release archive gate the reviewed change. Retain their exact
outcomes in the pull request and XCResult/Actions evidence; a source record is
not a substitute for those gates. No live provider request, production mutation
or iOS distribution is claimed by this implementation. The real released-build
upgrade remains outstanding.
