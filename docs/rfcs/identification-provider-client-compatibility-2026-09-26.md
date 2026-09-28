# Identification client compatibility — 26 September 2026

Status: implemented and verified locally. Every production assignment remains
Gemini. No deployment or paid evaluation is included.

**Follow-up — 27 September 2026:** The
[photo integration record](./identification-openai-photo-integration-2026-09-27.md)
owns the subsequent recipient, reader, dormant binding and deployment work. The
[matched comparison](./identification-gemini-openai-matched-results-2026-09-27.md)
and
[current optimization plan](./identification-optimization-preserving-results-2026-09-27.md)
supply later development evidence and priorities. The protocol, benchmark and
remaining-work statements below are the 26 September checkpoint, not a request
to repeat completed work or reopen the concise screen. Production remains
Gemini.

## Decision and scope

The app owns provider assignment. Each exact backend input/model binding can
require a minimum client protocol before new identification work begins. This
lets a later provider release exclude apps that cannot interpret its consent,
confidence or result contracts without blocking stored-result recovery.

Migration `20260926200227_add_identification_client_compatibility.sql` adds a
minimum to the private binding catalog and snapshots it with the recognized
original-client protocol on each admitted attempt. Every current Gemini minimum
is zero, preserving schema-first legacy access and the separate global
entitlement rollout. Historical attempt fields remain null. This capability
claim is not binary attestation, account authorization or permission to choose a
provider.

The gate runs inside the existing quota transaction. Rejection returns
`426 client_update_required` and rolls back reservation, counters, attempt and
complimentary-credit effects. Both identification RPC overloads retain their
signatures and return fields. No Swift, public Identify DTO, active model,
prompt, confidence or pricing changes are included.

## Retry and recovery behavior

A background worker cannot assert that an old app understands a new provider.
For fresh internal replay, compatibility comes from the original reservation for
the same owner, operation and observation, joined to its current immutable
attempt with the same complete-input profile. A worker header, another
observation, an older attempt or the reservation's legacy protocol column cannot
supply missing proof. Unknown proof passes only a zero-minimum binding.

Active or committed quota duplicates remain non-dispatchable replays and retain
their original snapshots. A newly metered attempt must satisfy the current
binding. Stored-result lookup precedes provider admission, and scan-status
recovery does not enter this gate.

Compatibility endpoints currently reconstruct a multimodal recovery request. All
current Gemini bindings preserve that behavior because their minimum is zero.
This slice deliberately does not qualify a changed profile or operation for a
future gated binding. Any such recovery path needs a separately reviewed,
durable origin mapping and provider qualification before activation; a worker
header cannot supply it.

## What remains before OpenAI production assignment

The current iOS app continues to advertise protocol 3. Complete recipient-aware
preflight, deliberate permission collection, confidence interpretation and
versioned result provenance for the exact qualified OpenAI photo/text profile.
Then coordinate a new accepted maximum in Edge, SQL and snapshot constraints
before shipping a client that advertises it. Keep the global required minimum
compatible with older-client recovery and apply the new minimum to the exact
qualified provider binding. Model/adapter allowlists and production composition
remain separate prerequisites. Follow
[Adding a provider](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md)
and the canonical release procedure for activation.

## Benchmark checkpoint

The existing benchmarks have produced a Gemini app baseline and demonstrated a
working OpenAI photo/text adapter. They have not established a provider winner.

| Evidence                                                                            | Completed measurement                                                                                                  | What it supports                                                                               |
| ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| [Gemini source photos](./identification-source-photo-app-benchmark-2026-09-22.md)   | Six app results: five provisional species agreements and one non-biological control                                    | Small operational baseline; app-pipeline median 17.190 s                                       |
| [Gemini audio V2](./identification-audio-confidence-v2-app-benchmark-2026-09-24.md) | Six complete windows: two provisional animal agreements, two source disagreements, two correct non-biological controls | Regression evidence; “Strong” labels on both disagreements show confidence needs qualification |
| [OpenAI photo/text pilot](./identification-openai-photo-text-pilot-2026-09-25.md)   | Eight planned cases: seven normalized, one unknown execution; six assessable agreements and one unassessable result    | Alternative adapter works; successful provider-boundary median 6.914 s                         |
| [OpenAI concise screen](./identification-openai-concise-screen-2026-09-26.md)       | One control completed, zero candidate calls, 15 unattempted                                                            | Closed as inconclusive because explanation reference coverage was insufficient                 |

Gemini and OpenAI used different input crops/context and measurement boundaries;
the timing numbers do not establish that either provider is faster. Biological
references remain provisional, with no independent biological validation. The
concise screen is optional optimization and is not a prerequisite for reviewing
this infrastructure. Do not repeat it merely because it was inconclusive.

Before a production selection, use a prospective matched comparison of the
specific candidate and Gemini on the same frozen inputs and measurement
boundary, with reviewed reference coverage, complete scheduled denominators,
confidence/error assessment and independent held-out qualification. The
[optimization plan](./identification-provider-optimization-plan.md) owns those
requirements. This slice adds no model calls or benchmark spending.

## Verification

The final local candidate passed:

| Gate                                          | Evidence                                                                                                                |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Clean migration replay and database catalogs  | 58 catalog files, 394 assertions                                                                                        |
| Complete Edge suite with database concurrency | 2,109 tests and 257 steps                                                                                               |
| Migration contracts                           | 351 tests across 63 discovered files                                                                                    |
| Supabase tooling                              | 438 standard tests plus 32 steps; 58 isolated evaluator tests plus 29 steps; 19 and 20 DTO tests; all 10 shell suites   |
| Runtime type/dependency checks                | 101 entrypoints, isolated dependency graphs and generated Deno configs                                                  |
| Privileged routine audit                      | 261 public definer routines; zero violations                                                                            |
| Database lint and advisors                    | No lint warnings/errors; zero advisor errors, with the same 105 security and 80 performance warnings as the prior slice |
| Formatting                                    | Complete functions/scripts formatting and lint; every changed Markdown file formatted and checked                       |

Regressions cover both RPC overloads, schema-first requests, recognized and
unsupported protocols, immutable snapshots, upgraded-client retries despite
stale reservation metadata, exact owner/operation/observation/current-attempt
proof for internal replay, missing historical evidence, unchanged zero-minimum
compatibility recovery and rejection of unqualified transformed recovery, atomic
credit rollback, and stored-result recovery before admission. Read-only review
found no remaining blocker within that scope; benchmark claims were checked
separately against the sanitized records.

A catalog rerun after the complete Edge concurrency suite encountered its
existing Field Chat cutover fixture state. Replaying all migrations in the
task-owned disposable database restored the clean baseline; all final catalogs,
lint and advisors then passed. No application fix or weakened assertion was
used. Keep clean catalog validation before state-changing concurrency tests, or
rebuild the disposable database between those gates.

No iOS build was needed or run: Swift sources and public DTOs are unchanged. The
task-owned database and volumes were removed after verification. No paid
provider calls, hosted mutation, push or deployment were performed. Local tests
establish compatibility behavior, not alternative-provider quality or latency.
