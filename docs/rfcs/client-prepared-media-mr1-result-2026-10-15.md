# MR-1 result: hosted resource method remains unavailable

October 15, 2026. The user approved MR-1's two-hour read-only scope at
`147021f2d`. This report records its semantics-first stopping decision. No
tests, invocations, account queries, R2 operations, uploads, secrets, deployment
or configuration changes occurred. Activation disabled; AWS and 160 MiB
unapproved; all limits unchanged; auto-prompts paused.

## Decision

**Stop hosted qualification under HAM-1 for now.** Gate M remains
`hosted_resource_method_unavailable`; Gate R remains
`resource_target_decision_pending`. No credible qualifying native-inclusive
whole-worker peak measurement was established within the reviewed sources.
Request-attributed CPU and timely target correlation also remain unestablished.
These are measurement gaps, not observed verifier resource violations.

MR-1 explicitly requires stopping before account retrieval when an essential
measurement cannot be established. Therefore Stage 2 was skipped: zero queries,
zero records and no query plan submitted. Independent/IC-1 query concurrence was
a prerequisite to retrieval, not permission to retrieve inadequate metrics.
Independent and IC-1 review of this result is recorded separately in the result
evidence directory; pending review must not be represented as concurrence.

This finding does not prove Supabase has no internal metric or that every
possible runtime version lacks one. It establishes that the approved bounded
review found no supported, target-applicable mechanism meeting HAM-1. Existing
samples cannot repair missing measurement semantics. Another identical inventory
or campaign would not resolve this gap.

## Evidence and acceptance matrix

The official sources were read on October 15. Runtime source is pinned to
`e847536d7b276428415d7cf9877803d99a16fde5` (retained v1.77.0 evidence). Neither
that revision nor the previously tested image proves the live hosted build or
hosting policy. Three cached source hashes match the retained manifest; the
fourth file was read at its immutable official revision. No runtime ran.

| Required property           | Evidence and status                                                                                                                                                                                                                         | Limitation and HAM-1 disposition                                                                                                                                                                                                                                   |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Native-inclusive high-water | Documented shutdown memory is a snapshot. Pinned `create_supervisor` constructs `total` as `used_heap_size + external_memory` after receiving isolate statistics.                                                                           | Neither is a complete native-allocation high-water over initialization, TLS/fetch, hashing, response and cleanup. Gate M unavailable.                                                                                                                              |
| Request CPU                 | Platform documentation states a two-second per-request CPU limit. In the pinned per-worker strategy, `CPUUsage.accumulated` is divided by 1,000,000 and returned on retirement; the user driver attaches runtime CPU to termination events. | Enforcement is not an exposed measurement contract. This worker-lifecycle path does not establish complete request attribution. Other supervisor policies exist; the live policy is unknown. No assumption that all hosted CPU fields are cumulative. Unqualified. |
| Scope/reset                 | Source distinguishes per-worker and per-request supervisors; memory data is assembled during termination.                                                                                                                                   | No documented measurement covering exactly one invocation with required baseline and cleanup ownership. No conversion or division across requests. Unqualified.                                                                                                    |
| Correlation                 | Documentation names `execution_id`; retained HQ-1A report established minute/function aggregation only.                                                                                                                                     | A field name does not prove invocation-to-actual-worker linkage or live build identity. No target selectors or event rows retrieved. Unqualified.                                                                                                                  |
| Precision                   | CPU documentation uses milliseconds; pinned per-worker arithmetic discards fractional milliseconds. Memory fields are numeric sizes.                                                                                                        | Neither numeric representation nor that conversion establishes a complete-domain error bound. A displayed 1,000 ms cannot establish an upper bound of at most 1,000 ms. Unqualified.                                                                               |
| Retention                   | No account metadata retrieved; current field documentation warns that fields may be absent.                                                                                                                                                 | Retention and completeness for this deleted route remain unknown. No inference from absent data. Unqualified.                                                                                                                                                      |
| Delivery                    | Shutdown events are documented, and the platform permits a worker to serve multiple requests.                                                                                                                                               | No guarantee found for complete qualifying measurements within each HAM-1 60-second slot. Shutdown timing is not request completion timing. Unqualified.                                                                                                           |

Sources:

- [Shutdown event semantics](https://supabase.com/docs/guides/troubleshooting/edge-function-shutdown-reasons-explained):
  CPU milliseconds, shutdown memory snapshot and execution identifier. This is
  documentation, not a fresh observation of target events.
- [Log field reference](https://supabase.com/docs/guides/observability/log-field-reference):
  structured fields are not necessarily populated. The retrieved static page
  displayed the gateway field tab; it was not treated as a complete runtime
  event schema or used to invent query fields.
- [Hosted limits](https://supabase.com/docs/guides/functions/limits): 256 MB
  platform memory limit, two-second per-request CPU limit and up to 400 seconds
  for paid-plan workers. These platform bounds do not substitute for application
  acceptance targets or prove resource consumption below them.
- [Pinned supervisor](https://github.com/supabase/edge-runtime/blob/e847536d7b276428415d7cf9877803d99a16fde5/crates/base/src/worker/supervisor/mod.rs#L310-L350):
  shutdown `total` composition and captured memory-checker state. The latter was
  not established as a native-inclusive, interval-wide maximum; no such claim
  follows from its name. Failed isolate collection can produce zero-valued
  fields, so zero is not independent proof of low usage.
- [Pinned per-worker strategy](https://github.com/supabase/edge-runtime/blob/e847536d7b276428415d7cf9877803d99a16fde5/crates/base/src/worker/supervisor/strategy_per_worker.rs#L319-L368),
  [user driver](https://github.com/supabase/edge-runtime/blob/e847536d7b276428415d7cf9877803d99a16fde5/crates/base/src/worker/driver/user.rs#L73-L123)
  and
  [worker event handling](https://github.com/supabase/edge-runtime/blob/e847536d7b276428415d7cf9877803d99a16fde5/crates/base/src/worker/worker_inner.rs#L362-L376):
  source-level CPU accounting and forwarding, not proof of hosted telemetry
  availability or the deployed policy.

## Resource-target decision

No limits change. Provenance hashes are in
`.artifacts/client-prepared-media/mr1-result/provenance.json`.

| Quantity                        | Preserved meaning                                                                        | Decision                                                                                            |
| ------------------------------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Stored package and asset limits | Approved CPM-1 storage contract, including 96 MiB package; separate from runtime memory. | Unchanged.                                                                                          |
| TM-1 sampled proxy              | `heapTotal + external`; stop at or above 100,663,296 bytes.                              | Still active in its approved measurement scope, not native peak.                                    |
| Growth                          | Existing 8 MiB criteria; local GAC-1 and legacy hosted method remain distinct.           | No pooling, shortened substitute or additional campaign. Retained GAC-1 pass and warning unchanged. |
| Native whole-worker memory      | Historical IVI-1 comparison of 96 MiB, not adopted hosted acceptance.                    | Do not adopt a new predicate without measurable domain and uncertainty. Gate R pending.             |
| Request CPU                     | Historical IVI-1 one-second comparison, not adopted hosted acceptance.                   | Same; do not substitute the platform's larger limit or elapsed duration.                            |
| Deadline                        | Existing 30-second request bound; HAM-1 observation slot is 60 seconds.                  | Neither extended.                                                                                   |

If an applicable measurement later becomes established, MR-1's proposed
comparisons remain native-memory upper bound strictly below 100,663,296 bytes
and CPU upper bound at most 1,000 ms, including uncertainty. They are not
adopted by this report. A nominal target choice cannot close Gate M.

## Stop and handoff

This completes the bounded investigation, not hosted or product acceptance. Keep
local GAC-1 evidence closed within its stated scope. Warm reuse, concurrency,
complete-verifier, ingress, media retention, audio quality, recovery/deletion
and integrated product acceptance remain open.

The next decision is contractual: retain HAM-1's prerequisites and remain
blocked, or separately authorize review of a different acceptance method that
explicitly states which resource guarantees it can and cannot establish. No
alternative method, higher resource limit, new infrastructure or further test is
proposed or adopted here. New evidence identifying a qualifying existing
measurement could also justify reconsideration. No automatic investigation,
provider contact, implementation or campaign follows.

Scope ledger and review bindings are under
`.artifacts/client-prepared-media/mr1-result/`. The approved outer window began
at 21:35:53 UTC, ending no later than 23:35:53 UTC. Stage 1 ended before its
35-minute ceiling; account inspection time was zero. Prior evidence remains
historical and recoverable.
