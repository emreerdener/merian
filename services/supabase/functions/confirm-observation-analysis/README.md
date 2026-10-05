# Confirm observation analysis

Prepared authenticated POST endpoint for confirming an exact private history
result. `confirmation_api_enabled` defaults false, and there is no ordinary
native caller. The
[canonical API contract](../../../../docs/backend-and-data/05-api-contracts.md#prepared-analysis-bound-confirmation)
owns request fields, transitions, outcomes and remaining rollout requirements.

`index.ts` authenticates through the shared handler, validates the exact
request, persists admission before verification, skips external work for a
completed receipt, and returns a private uncached outcome. `db.ts` owns the two
service-only RPC adapters and redacts persistence diagnostics.
`_shared/analysisHistory/confirmation.ts` owns the executable wire contract;
`_shared/identify/speciesVerification.ts` owns the shared name validator and
dictionary-rate admission. Existing GBIF verification owns canonical proof.

Prepare freezes operation identity and query. Complete rechecks both revisions
and deletion before updating only the named child's authority. Applied,
stale-revision and definitive-negative receipts are immutable; infrastructure
failure leaves an intent retryable. A completed retry uses no further lookup
budget; unfinished lookup attempts use the existing dictionary limiter. No AI
provider dispatch or complimentary scan credit is involved. Community authority
and legacy evidence without an explicit primary remain unsupported.

`handler_test.ts` covers orchestration, exact parsing, proof/query binding,
completed recovery, negative outcomes, authentication, rate refusal,
cancellation and sanitized errors. `tests/observation_analysis_confirmation.sql`
checks actual roles, immutable admission, dual revisions, authority isolation
and deletion. `_tests/observationAnalysisConfirmationConcurrencyDb.test.ts` uses
separate database sessions for duplicate/competing completion, selection,
rejection, deletion/account erasure and pending operation rebinding.

The prepared native `ObservationAnalysisReviewRequest`/receipt boundary now
mirrors these exact fields and limits. Its closed typed transport disables
automatic transient replay and 401 recovery and never treats a receipt as
current authority. Durable native delivery and ordinary UI remain separate; this
adds no activation or deployment.
