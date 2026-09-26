# Independent OpenAI consent infrastructure

Date: 26 September 2026\
Scope: Second production-integration sub-slice, processor permission\
Status: Implemented and verified locally. OpenAI collection and production
routing remain disabled.

This follows
[provider-bound admission](./identification-provider-production-admission-2026-09-26.md).
It gives OpenAI its own permission history and prepares the app to ask for it
when a reviewed rollout is ready. Gemini remains the only production assignment
and the required onboarding/inference provider. No deployment, consent
collection, secret mutation or paid identification was performed for this slice.

## Implemented behavior

- The existing append-only AI evidence table accepts `google_gemini` and
  `openai`, preserving historical Gemini rows. OpenAI has a fixed-recipient
  authenticated RPC with the same causal append contract. Direct inserts and
  client-selected recipient parameters remain prohibited.
- Both AI RPCs serialize on one account-level advisory lock and verify provider
  during event-ID replay. Each selects its own all-version head. Stale grants
  cannot undo a revocation; revoked events can rebase to their provider's head.
- The internal OpenAI proof requires its own current `2026-09-26` grant and
  adult/Terms receipts for `2026-08-03`. Old/future versions, missing evidence
  and any-version head revocation deny. Gemini grants and legacy compatibility
  never authorize OpenAI. Policy versions are the server authority identifiers;
  exact supplied text is immutable client evidence, not verified UI rendering.
- iOS persists independent actions in the existing ledger, routes uploads to the
  fixed RPC and fetches a separate OpenAI head. Rebinding and server merge keep
  event IDs, recipient, text, versions and causal ancestry. Account deletion
  uses the existing cascading evidence cleanup.
- Optional Settings presentation requires an explicit displayed action and
  captures its account before opening the disclosure. Cancellation, stale owner,
  SDK mismatch or account transition cannot record a grant. Verified persistence
  precedes publication and synchronization. Failed saves report an unsaved
  change; failed withdrawal is closed and retryable for the current process,
  without claiming durable revocation after restart. Successfully saved offline
  withdrawal remains pending in the durable ledger until synchronization.
- `openAIConsentCollectionEnabled = false` hides new collection. Existing
  current or older-version grants stay visible for withdrawal with that gate
  closed. The optional choice does not satisfy Gemini required consent or
  authorize model dispatch. The PostHog Keychain withdrawal journal is
  unchanged.

`ConsentRemoteMapping` now owns the pure mapping helpers extracted from the
remote service. `AIProcessingConsentCoordinator` owns optional choices and uses
the existing runtime/session synchronization wiring. All consent owners and the
facade retain the 600-line boundary.

## Disclosure draft and activation boundary

The source draft is scoped to photos, written descriptions and related
observation context. It makes no zero-retention promise. OpenAI's
[API data guide](https://developers.openai.com/api/docs/guides/your-data)
distinguishes storage controls from abuse-monitoring retention; request
`store: false` alone does not prove zero retention. The draft points to API data
policies without hard-coding a retention guarantee.

The collection flag is a source constant, not a remote traffic switch. Review
and publish the intended disclosure, legal terms and privacy materials before
enabling collection; revise the version and server gate together if the material
purpose or copy changes. Public production policies still describe the active
Gemini service. Do not add audio, native video or new purposes under this draft.
Five-second captured video supplies ordered image snapshots to identification;
any included audio still requires a complete qualified task binding.

Apply migration `20260926150509_add_independent_openai_consent_stream.sql`
before enabling an app that collects this evidence. Existing Gemini callers
remain compatible. The source-disabled app can read an absent OpenAI head on the
old schema without collecting new choices. A client with existing OpenAI history
still needs the new RPC to synchronize pending events and withdrawals. Preserve
consent history through rollback; disabling collection must not erase evidence
or remove the withdrawal path. Use the existing exact-SHA release controls only
after explicit deployment authorization.

## Verification

Validation used XcodeGen 2.45.4, the iOS 27 simulator, Deno 2.9.4 and Supabase
CLI 2.109.1. Final checks passed:

| Check                                         | Result                                                                                                         |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Complete iOS unit target                      | 4,328 tests passed, zero failures or skips                                                                     |
| iOS source/project gates                      | XcodeGen regeneration, project membership, privacy manifest, typed event routing and transport security passed |
| Clean migration replay                        | All migrations replayed in a task-owned disposable database                                                    |
| Database security catalogs                    | 55 files, 391 assertions passed                                                                                |
| Complete Edge suite with database integration | 2,098 tests and 245 steps passed                                                                               |
| Migration contracts                           | 349 tests across 61 discovered files passed                                                                    |
| Complete Supabase tooling                     | 438 standard tests, 58 isolated evaluator tests, both DTO suites and all 10 shell suites passed                |
| Recursive Edge type/config/dependency checks  | 101 entrypoints, configurations and isolated dependency graphs passed                                          |
| Privileged routine audit                      | 260 definer routines, zero violations                                                                          |
| Database lint                                 | No schema errors or warnings                                                                                   |
| Security/performance advisors                 | No errors; 105 security and 80 performance warnings on unrelated existing objects, none on the consent objects |
| Formatting and lint                           | Recursive functions/scripts format and lint passed                                                             |
| Generated contracts and identities            | Identify and captured-media Swift DTOs plus both generated deployment identities validated unchanged           |

The complete iOS result is retained privately at
`.artifacts/local-ios/23b81f8638b445208bd48f23808c1125.xcresult` in the task
worktree. It includes 1,366 XCTest cases and 2,962 Swift Testing cases. The
focused consent run also passed. Changed Markdown and diff whitespace passed;
the generated Xcode project changes contain only the new Swift file membership.
The task-owned disposable database and its test volume were removed after
validation; other local database environments were untouched.

Review found and corrected the concurrent same-ID cross-provider collision and
the older-disclosure withdrawal path. A final independent read-only review found
no remaining actionable blockers. Deterministic fixtures contain no production
identities, credentials or provider responses. The local database catalog
exercises the real merge orchestrator, including its handler-before-reparent
preconditions. User-level Supabase skill links still have the previously noted
drift; validation used the reviewed checked-in skills without changing those
links. No physical-device or live OpenAI rollout test was performed.

## Next integration slice

Carry the qualified provider and complete generation/confidence identity through
durable scan results and recovery. Then complete recipient-aware quota admission
and iOS inference/reapproval behavior, usage and confidence compatibility,
held-out quality/safety qualification, published disclosure and controlled
activation. The legacy quota delegate and current client inference gate remain
Gemini-only; adding an OpenAI receipt or catalog row is insufficient. The
optional concise-prompt experiment stays deferred and need not be rerun for this
work.
