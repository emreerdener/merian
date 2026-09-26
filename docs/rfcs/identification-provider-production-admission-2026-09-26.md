# Provider-bound identification admission

Date: 26 September 2026\
Scope: First production-integration sub-slice, admission provenance\
Status: Implemented and verified locally. No deployment or provider activation.

This follows the
[implementation review](./identification-provider-flexibility-review-2026-09-26.md).
It makes the provider recipient explicit in authoritative identification
admission. Gemini remains the only enabled production provider. The local OpenAI
evaluator and the closed concise-prompt experiment keep their separate evidence
boundaries.

## Implemented boundary

The four identification routes now use the service-only
`reserve_identification_quota` wrapper through
`reserveIdentificationProviderCall`. The wrapper retains existing quota,
entitlement, consent, locking, and lease semantics. It selects an exact database
binding for the admitted operation, effective plan, model and policy version,
then records provider, binding and processor permission in the same transaction.

The private catalog contains only currently enabled Gemini assignments. Missing
bindings roll back reservation and counter/hold changes. Edge validates the
returned assignment before fresh work, and the AI registry independently checks
it before preparation. Each handler uses the admitted recipient permission. No
client field or environment setting selects a provider.

Each metered generation gets a separate snapshot. A duplicate uses its existing
record; a newly admitted retry preserves previous generations. Older workers
retain their original RPC and can coexist with the additive migration. A live or
committed legacy reservation without a snapshot stays a non-dispatchable replay;
no historical evidence is fabricated. Completed scans replay before admission as
before.

The recipient-aware consent helper delegates `google_gemini` to its existing
causal stream-head gate and rejects every other recipient. No historical consent
is relabeled and no OpenAI disclosure is collected in this sub-slice. Content,
chat and other paid-model operations retain their existing quota path.

The
[API contract](../backend-and-data/05-api-contracts.md#provider-bound-identification-reservations)
and
[database schema](../backend-and-data/04-database-schema.md#internalai_quota_policies-counters-and-reservations)
are the current authorities. The attempt records inherit quota-reservation
retention, including its existing recovery exceptions and cascading account
cleanup. They are not permanent scan provenance or a full prompt/generation
fingerprint.

## Verification

Verification used Deno 2.9.4, Supabase CLI 2.109.1 and a task-owned disposable
local database. Final checks passed:

| Check                                                       | Result                                                                                                                          |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Clean migration replay                                      | All migrations replayed successfully                                                                                            |
| Database catalogs                                           | 54 files, 390 assertions passed                                                                                                 |
| Complete Edge suite, with the disposable database available | 2,095 tests and 245 steps passed                                                                                                |
| Static migration contracts                                  | 348 tests across 60 discovered files passed                                                                                     |
| Complete Supabase tooling gate                              | 438 standard tests, 58 isolated evaluator tests, DTO suites, wire validation and all 10 shell suites passed                     |
| Edge type/config/dependency checks                          | All 101 entrypoints/configurations/isolated graphs passed                                                                       |
| Privileged routine ACL audit                                | 259 definer routines, zero violations                                                                                           |
| Database lint                                               | No schema errors or warnings                                                                                                    |
| Security and performance advisors                           | No errors; 105 security and 80 performance warnings on unrelated existing objects                                               |
| Formatting, lint and generated identities                   | Recursive functions/scripts format and lint, changed Markdown, diff whitespace and both generated bundle identity checks passed |

Coverage includes unknown/missing recipient metadata, exact policy binding,
atomic rollback, revocation, legacy replay, independently metered retry,
service-only access, cleanup, and overlapping duplicate requests. Two read-only
reviews found no remaining actionable contract blockers after corrections.

The generated Identify and captured-media Swift contracts validate unchanged. No
iOS build or simulator run was needed because this slice changes neither Swift
nor the public wire contract. The user-level skill-link check reported
pre-existing link drift; the reviewed checked-in packages were used without
changing the user's skill installation.

All provider responses in these checks are deterministic fixtures. No paid
inference, hosted mutation, deployment or provider activation was performed.

## Deployment compatibility

Migration `20260926142824_bind_identification_quota_to_provider.sql` must
precede the new Edge callers. Missing RPCs fail closed without falling back to
legacy admission. Use the existing
[exact-SHA release procedure](../backend-and-data/06-supabase-deployment-runbook.md)
only after separately authorized deployment. A backend rollback can use the old
Gemini callers while the additive tables remain; do not delete migration history
or snapshot records as a rollback shortcut.

## Remaining integration slices

1. Add the OpenAI-specific disclosure and independently scoped consent stream,
   app permission/revocation, account-switch, cancellation and replay behavior.
   Extend underlying database admission together; the legacy delegate in this
   slice is deliberately still Gemini-only.
2. Propagate qualified provider and complete generation/confidence identity into
   durable scan results and recovery. Verify usage/accounting, confidence, saved
   results and older-client compatibility before adding an OpenAI binding.
3. Qualify the complete accepted photo/text input set, then prepare controlled
   activation and rollback through the existing release controls. Audio and
   video-origin observations keep Gemini until their complete evidence is
   supported and qualified; sampled frames are not native video input.

The optional concise-prompt optimization stays deferred. Completing this
admission sub-slice is progress toward production integration, not a claim that
OpenAI production assignment or provider-specific user consent is complete.
