# Identification recipient preflight — 26 September 2026

Status: backend implementation verified locally. Native integration is the next
slice. All current assignments remain Gemini.

## Decision

The app should check which recipient the backend assigns before sending an
observation for identification. If that recipient changes before admission, stop
and check again. End users can grant or refuse processing permission; they do
not choose the provider. Confidence scoring is unchanged.

This backend slice adds a read-only authenticated preflight RPC and an atomic
recipient expectation on fresh admission. It prepares the contract needed by the
native app without changing existing callers or activating OpenAI.

## Backend contract

`get_my_identification_preflight` accepts the prospective complete-input
profile, operation, Flash eligibility, original client scan UUID and client
protocol. Identity is derived from `auth.uid()`. It returns the assigned
recipient and one of `ready`, `permission_required`, `client_update_required` or
`recovery_only`. There is no model or provider selector and no observation
content in this call.

The existing global protocol fence runs first. Recovery-only describes an
already live or committed reservation and returns no inferred recipient. Fresh
work resolves the prospective plan, including credit already held or consumed by
that same scan, then checks the exact binding, its compatibility minimum and its
current consent stream. The existing Capture allowance preview remains separate.
Recipient readiness is not a promise of available quota.

Preflight neither changes a consent record nor reserves a credit, quota or model
call. Its profile and eligibility inputs are hints. The actual Edge handler
continues to derive these from validated evidence. A client that implements this
flow will echo the assigned recipient, or `recovery_only`, in
`X-Merian-Identification-Recipient`.

The header selects a new service-only ten-argument
`reserve_identification_quota` overload. It is an untrusted expectation that can
only deny an independently selected assignment; it is not an authorization
token. Fresh recipient mismatch returns
`409 ai_identification_preflight_changed` and rolls back quota, attempt and
complimentary-credit effects. It does not cause a retry, fallback or a call to
another service. A same-recipient model change still uses the existing
admission, capability and qualification rules.

The old eight- and nine-argument RPCs remain compatible. Headerless clients keep
the nine-argument path; a guarded call never falls back to it after failure.
Both paths retain current Gemini-only bindings and model allowlists. Completed
result lookup and non-dispatchable reservation replay keep their current paths.
Expired, failed and refunded requests must satisfy fresh admission.

The migration creates the ten-argument overload from the reviewed nine-argument
implementation using exact source-fragment checks. A later admission change must
review all three overloads. No historical migration, saved attempt or consent
receipt is rewritten.

## Next native slice

Use the final outgoing evidence shape for preflight, including sampled video
frames and companion audio. Validate the closed response without treating it as
permission to select another provider. Preserve the expectation across live
request reconstruction, authentication/transport retries and durable background
request preparation. Background recovery should look for existing results first.

Recheck local recipient permission and the current account/generation
immediately before dispatch; the backend expectation cannot detect a local
withdrawal that has not synchronized yet. On policy drift or missing permission,
retain the observation and use the existing pause/retry path. Offline storage
may continue, but inference must wait for a valid current check. Add no provider
chooser and do not automatically collect or enable OpenAI consent.

Later activation still requires deliberate disclosure/permission collection,
qualified client capability and coordinated protocol expansion, model admission,
confidence interpretation and versioned result provenance. Native protocol 3 and
the global rollout setting are unchanged in this slice. Follow
[Adding a provider](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md).

## Benchmark status

No model evaluations or paid calls are part of this slice. The existing Gemini
baseline and OpenAI photo/text pilot remain useful operational evidence, but
they do not establish a quality or speed winner because their inputs and timing
boundaries differed. The concise optimization screen remains closed as
inconclusive. See the existing
[benchmark checkpoint](./identification-provider-client-compatibility-2026-09-26.md#benchmark-checkpoint).
A matched comparison of qualified candidates remains the selection milestone.

## Verification

The final local candidate passed:

| Gate                                          | Evidence                                                                                                              |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Clean migration replay and database catalogs  | 59 catalog files, 395 assertions                                                                                      |
| Complete Edge suite with database concurrency | 2,113 tests and 265 steps                                                                                             |
| Migration contracts                           | 352 tests across 64 discovered files                                                                                  |
| Supabase tooling                              | 438 standard tests plus 32 steps; 58 isolated evaluator tests plus 29 steps; 19 and 20 DTO tests; all 10 shell suites |
| Runtime type and dependency checks            | 101 entrypoints, isolated dependency graphs and generated Deno configurations                                         |
| Privileged routine audit                      | 263 public definer routines; zero violations                                                                          |
| Database lint and advisors                    | No lint warnings/errors; zero advisor errors; unchanged 105 security and 80 performance warnings                      |
| Formatting                                    | Complete functions/scripts formatting and lint; changed Markdown formatted and checked                                |

Tests cover caller isolation, read-only behavior, each accepted input profile,
protocol ordering, scan-specific complimentary funding, denied recipient
changes, atomic rollback, legacy callers and live/committed versus fresh retry
states. The temporary OpenAI-recipient test fixture runs only inside a
rolled-back local transaction; no production binding constraint is widened.

Independent read-only review identified a global-gate ordering mismatch and a
missing error-matrix entry; both were corrected. The final implementation had no
remaining review blocker. The task-owned database and volumes were removed after
the gates. The preexisting user-level Supabase skill links still differ from the
reviewed checkout; checked-in skill packages were used without changing global
links.

This slice changes no Swift source or Identify response DTO. No iOS build was
needed or run. It includes no hosted mutation, push, deployment, provider
activation or benchmark spending.

## Subsequent native slice — 26 September 2026

The
[native integration](./identification-native-recipient-preflight-2026-09-26.md)
implements the next-slice contract described above. Its local verification and
release ordering are recorded separately; the backend verification above remains
historical evidence for its own candidate. Gemini remains the only active
assignment, with no deployment or provider activation in either local slice.
