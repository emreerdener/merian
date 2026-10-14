# CPM-1 measurement: smaller revised scope

Status: October 14, 2026. **Scope and R2-F1/TM-1 design accepted; construction
and testing remain unapproved.** The latest verified human decision is advisory
turn `01a138f7-a38d-75a0-b0c8-31f2d0eb9665`: private fixture design, partial V8
measurement/safety amendment and Emre as operator are approved. The
[next boundary is the bounded local construction request](client-prepared-media-local-construction-request-2026-10-14.md).
No actual R2 setup or hosted metric qualification is needed before requesting
that local work; those operational proofs remain for separately approved stages.

The approved
[R2-F1/TM-1 design](client-prepared-media-private-fixtures-telemetry-proposal-2026-10-14.md)
supersedes the earlier target/metric decisions and proposed native-inclusive 160
MiB guard below. Its 96 MiB partial V8 proxy is not the historical process
memory target or a total-memory guarantee. The previously accepted 26-case
bounds, reader-closure semantics, omissions and evidence limitations still
apply. No production resource budget or feature acceptance is established.
Activation disabled, AWS unapproved, auto-prompts paused; external-operation
restrictions remain. All package/per-asset/storage limits and failed evidence
are unchanged.

The following inventory and pre-amendment rationale are historical for target
selection and the memory-guard decision. They do not require another approval of
the design or a native-inclusive metric before local construction can be
requested. They remain evidence of what has and has not been observed.

## October 14 read-only inventory: production alpha target selected

The human explicitly selected the existing production alpha environment and
rejected a separate Supabase project requirement. This supersedes the earlier
nonproduction target-selection prerequisite. Existing configured access was used
for read-only CLI metadata and dashboard inspection. It does **not** authorize
construction, fixture uploads, invocations, tests, provisioning or configuration
changes. The 160 MiB threshold remains unapproved.

| Surface                    | Observed evidence                                                                                                                                                                                   | What remains unestablished                                                                                                                                                            |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Supabase target            | Existing `merian` project, `us-east-1`, CLI status `ACTIVE_HEALTHY`; dashboard shows Pro organization and main production branch. CLI 2.109.1 matches the repository pin.                           | Exact deployed Edge runtime build and target memory accounting. No separate Supabase project is needed.                                                                               |
| Existing backend access    | Existing login can list project metadata, 107 deployed functions and secret names. Current R2 write/read credential names exist; no `R2_HISTORY_*` secret names are present.                        | Secret names do not establish credential permissions, bucket binding, test identity or authority to change anything. No secret values or digests were retained.                       |
| R2 inventory               | The visible Cloudflare account lists `merian` and unrelated `portfolio`. Only `merian` settings were inspected. Its `media.merian.app` custom-domain access and public development URL are enabled. | No private history/fixture bucket was visible in this account. This is not a claim about all accounts. The current app bucket does not meet the accepted private-fixture requirement. |
| R2 lifecycle and telemetry | `merian` has enabled seven-day incomplete multipart abort, one-day `staging/` and `quarantine/` deletion rules; no bucket-lock or CORS rules; Data Access Logs disabled.                            | Lifecycle expiry is not writer-closure proof. No fixture namespace, object permissions, writer closure, cleanup capability or private GET behavior was tested.                        |
| Edge observability         | Existing report offers invocation counts, status codes, average execution time in milliseconds and invocations by region.                                                                           | These are not request CPU attribution, per-worker native-inclusive memory samples or lifetime peak. No compatible in-run total-memory guard was identified.                           |

Sanitized inventory is retained locally at
`.artifacts/client-prepared-media/measurement-revised-scope/live-target-inventory-2026-10-14.json`.
No customer object contents, credentials, auth state or production response
bodies were saved. No object or runtime test was performed. Inventory is a
point-in-time observation, not qualification of storage or telemetry guarantees.

Public upstream source inspected October 14 narrows the telemetry uncertainty:
the user-worker
[bootstrap override](https://github.com/supabase/edge-runtime/blob/main/ext/runtime/js/bootstrap.js)
routes `Deno.memoryUsage()` to
[`op_runtime_memory_usage`](https://github.com/supabase/edge-runtime/blob/main/ext/runtime/lib.rs),
which returns `rss: 0` and V8 heap-total, heap-used and external-memory
statistics. These are upstream `main` observations, not proof of the unnamed
hosted build. Zero RSS must not be treated as measured zero memory. This
operation does not establish total native TLS/fetch allocation coverage or
lifetime peak.

The credible partial method is therefore separately labelled V8 heap/external
trend samples, monotonic wall timings and boot-correlated runtime events; CPU
totals remain diagnostic without request attribution. It cannot by itself supply
the accepted scope's native-inclusive abort metric. An operator-accessible
compatible metric must be identified, or a specific measurement/safety amendment
returned for approval. Do not silently use heap plus external as total memory,
substitute the platform kill for the proposed guard, or infer approval of a
different experiment. Live metric behavior and closure still belong to the later
separately approved two-call preflight, not a new preconstruction test.

**Pre-amendment disposition (superseded by R2-F1/TM-1):** Supabase selection is
resolved. Private fixture placement and native-inclusive measurement remain
unresolved. Keep the same Supabase project. Do not provision a bucket or change
the existing public bucket as part of this inventory. A later proposal can name
an existing private bucket if available, request narrowly scoped R2
provisioning, or explicitly amend fixture privacy for synthetic benchmark bytes
only. None of those choices is adopted here; public benchmark fixtures would not
qualify private-history access controls. Likewise, partial V8 trend telemetry
needs an explicit measurement/safety amendment if no compatible native-inclusive
metric can be established. Do not request construction until the remaining
target/metric decisions are resolved.

## Pre-amendment recommendation (design decisions now resolved)

1. **Finish storage and measurement decisions on the selected production alpha
   project.** Preserve the accepted bounds and account for shared production
   runtime impact in any later execution packet. Name the fixture location,
   operator/test access, lifecycle/cleanup owner and metric definition. Existing
   read access does not establish least-privilege test or cleanup access. No
   additional Supabase project or production-exclusion evidence is required.
2. **Approve a small local preparation separately:** at most four engineering
   hours after target selection and agreement on the measurement definition
   below. Prepare the representative candidate, fixed driver and exact
   dependency manifest; local correctness checks and independent/IC-1 review
   only. Return a concrete blocker when this timebox cannot suffice; do not
   expand it into the production schema/receipt implementation. Local
   fixtures/evidence at most 512 MiB, with workstation free space above 20 GiB.
3. **Return the exact candidate and named-target packet for hosted approval.**
   Specify installation, fixture operations, read-only Auth use, telemetry and
   teardown individually. Run observability preflight before bulk fixtures. No
   part of this revision starts steps 2 or 3, adopts a higher memory limit, or
   transfers writing ownership from History primary.

## Accepted measurement scope; storage and metric confirmation pending

Official
[Supabase telemetry](https://supabase.com/docs/guides/troubleshooting/edge-function-shutdown-reasons-explained)
provides shutdown reasons, memory snapshots and CPU totals; it does not
establish a lifetime peak or concurrent request attribution. The documented
[Deno memory API](https://docs.deno.com/api/deno/runtime/#Deno.memoryUsage)
describes process/V8 memory. Its availability and accounting in hosted Edge must
be confirmed, not equated to an isolate limit from the API name alone.

Recommend **observed-trend characterization**, not resource acceptance: collect
phase samples and a bounded 100 ms sampling timer during active requests only,
quiescent samples, monotonic wall timings, and available runtime shutdown/CPU
events. Aggregate samples locally; retain only bounded synthetic case/worker
aliases and summaries, never auth state, URLs or bodies. Keep instrumentation
cost included. Confirm metric domain/native coverage and worker correlation in
the two-call preflight. No timer may keep a worker alive between requests.

Report observed maxima, sampling gaps, fields omitted and worker changes. A
sampled maximum is a lower bound on the actual peak, not proof it stayed below a
ceiling. Do not add heap/external/RSS blindly. If reliable request CPU is
unavailable, report its absence and runtime CPU-limit events; never divide a
worker total among concurrent requests or call wall time CPU time. The existing
one-second CPU and complete-worker peak acceptance remain **unqualified**.
Shutdown-only observations may describe terminal state but cannot establish a
warm trend; if no usable in-run metric exists, stop before full-media work and
return a measurement amendment. Scope acceptance does not establish target
feasibility or resource acceptance.

## Historical comparison threshold and superseded proposed stop rules

Keep **96 MiB as the historical comparison threshold**, preserving the
122.81/172.59 MiB failures and all original measurement domains. A future
crossing is recorded as an exceedance, never rewritten as a pass. Cross-runtime
values are compared only with their accounting differences disclosed.

For separate approval, propose **160 MiB as an observed-memory abort threshold**
for this small experiment, conditional on a compatible, native-inclusive metric
and a confirmed platform hard limit of at least 256,000,000 bytes. This leaves
about 84 MiB of nominal room below that limit and permits characterization above
96 MiB, including the prior 122.81 MiB range. It is a conservative experiment
choice, not an empirically established safe budget or a new production limit.
[Published platform limits](https://supabase.com/docs/guides/functions/limits)
state 256 MB memory and two seconds CPU per request; exact target accounting
still needs confirmation.

**160 MiB cannot be promised as a hard ceiling:** sampling and cancellation can
lag, and native allocation can overshoot. The platform limit is the hard
backstop. The named-target approval must explicitly accept this limitation; if a
hard 160 MiB bound is required, no suitable enforcement is established and the
run stays blocked. Heap-only or unrelated process measurements cannot silently
serve as this guard. Above 96 but below the approved abort threshold,
characterization may continue only while every other safety condition holds; no
higher threshold is adopted or used now.

Stop new work and attempt cancellation on the first observed 160 MiB breach,
runtime memory/CPU kill, hash mismatch, unauthorized read, uncontrolled reader,
missing required telemetry, unknown in-flight termination or run-bound breach.
Keep the existing 30-second per-read deadline; no automatic retry or replacement
after uncertainty. Normal busy denials are expected. CPU safety relies on the
confirmed platform cap when request attribution is unavailable; it does not
prove the historical one-second target. Do not average away failures.

## Smallest representative candidate and finite bounds

Use an isolated test-only wrapper with the actual selected imports/auth helper,
bounded manifest parsing, private TLS GET, incremental length/hash verification,
response serialization and awaited reader cleanup. The code manifest must list
omissions: production claims, SQL receipts, funding, admission, deletion races,
decoding and AI execution. **This is not a complete verifier.** Repeated reads
of fixed synthetic fixtures are benchmark operations without production
operation IDs or receipts; they do not change accepted replay semantics.

| Bound             | Proposed maximum                                                                                                                               |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Fixtures          | Three immutable synthetic objects: two 32 MiB and one 64 KiB; under 65 MiB total, existing per-role limits preserved; no client upload tickets |
| Invocations       | 26 total: two observability controls, two nine-request warm cohorts, three pairs of concurrent arrivals                                        |
| Concurrency       | Two client requests; one physical body reader per worker; same-worker busy/denial overhead measured, no intentional double-reader overlap      |
| Duration          | 30-minute measurement window plus 15 minutes reserved for disable/reconciliation/cleanup                                                       |
| Calls             | 256 application-issued target HTTP calls total: 192 setup/test/observation, 64 reserved exclusively for recovery/cleanup                       |
| Transfer/evidence | 2 GiB application media transfer; local evidence included in the 512 MiB allowance                                                             |

A single operator driver sends the fixed list once, counts each attempt before
sending and stops on an uncertain response. Disable automatic SDK/HTTP retries,
redirect following, background tasks, callbacks and recursive dispatch. Each
handler has at most four outbound calls, one bounded object GET and no loops
over variable fixture sets. The non-cleanup ceiling fits 16 setup calls, 26
driver calls plus at most 104 handler calls, and 32 metric reads, with 14 unused
calls. Each response body is capped; media GETs at the fixture size. These
static bounds cover the two possible in-flight requests without a new
distributed allowance ledger. They are application bounds, not exact platform
internal traffic or billing guarantees.

Fixed inventory and finite calls suffice for this controlled, single-driver,
read-only benchmark only with operator-only access, a fixed expiry and a
separately authorized disable path. The fixed driver never overlaps reads of the
same immutable fixture, even on different workers. Positive physical reader
closure precedes every reuse of that fixture; unknown closure stops the entire
packet, never a replacement GET. No automatic driver restart or resumption after
uncertain delivery. If the reviewed composition introduces detached work,
retries, extra callers or unbounded outbound paths, shrink/revise the packet
before execution; do not add a general accounting subsystem by default. Reserve
the 64 calls and 15 minutes for disable first, then closure and fixture cleanup.
Cleanup may remove only run-owned objects after writers/readers close;
unresolved obligations remain recorded for the named operator, with no automatic
extra run or capacity release.

### Positive reader-closure acknowledgement

For a successful read, the handler must observe full body EOF, verify exact
length/hash, and await all request-owned fetch/read/hash work. Before returning,
its awaited cleanup must observe the reader's terminal `closed` state, release
the reader lock, drop request-owned buffers/hash state, stop the sampling timer
and release that request's worker reader slot. Only then may it send a bounded,
non-streaming terminal acknowledgement identifying the synthetic run,
invocation, fixture and worker, verified length/hash and completed cleanup. The
driver must receive and validate that complete server response against its
outstanding case before reusing the fixture or starting the next serial case. A
busy/denied response may acknowledge that it opened no reader; it cannot
acknowledge closure of the paired active reader. Both members of a pair must
finish before advancing.

On early exit, abort the fetch, await settlement of any outstanding acquisition
or read, and await body cancellation/reader cleanup wherever a body was
acquired, including a late fetch response. A cancellation request, rejected
promise or released lock alone is not a positive closure acknowledgement. This
benchmark does not resume after a failed/cancelled read even if cleanup is
acknowledged. Lost/truncated acknowledgements, client timeout, mere request
cancellation or unknown handler termination stop the packet: no replacement read
or blind resend. Use the reserved disable/cleanup allowance; retain unresolved
reader and fixture obligations for the named operator rather than deleting on
timeout. No durable recovery ledger or extra polling loop is introduced.

This acknowledgement proves the reviewed handler's request-owned reader
lifecycle completed, not native buffer reclamation, socket destruction or memory
returning to baseline. The exact runtime must support and demonstrate this
EOF/settlement/cleanup predicate in the reviewed candidate and approved
preflight; if it cannot, positive closure remains unproved and full-media work
is blocked. No driver-visible success may precede awaited cleanup.

## Warm routing fallback and useful conclusions

Spread each nine-request cohort over 80% of the confirmed worker lifetime,
capped at 320 seconds; no catch-up overlap, affinity tricks, forced redeployment
or keepalive. Record actual instance identity (test-generated boot alias plus
available platform correlation), request ordinal and first-use status.
Concurrent pairs comprise two different-object arrival pairs and one reader
paired with a denied caller. Same-object duplicate/replacement races are
excluded and remain for later complete-verifier qualification; this benchmark
neither needs nor qualifies a distributed claim fence. First-use is not proof of
a platform cold start without boot evidence.

If routing yields only shorter same-worker sequences, report those exact lengths
and their observed trends. If every request lands elsewhere, report per-request
TLS/hash behavior, observed memory distributions and wall time only; warm reuse
remains unobserved. Pairs on separate workers establish only that observed
topology, not same-worker contention. Missing coverage does not trigger extra
calls. A separately proposed local same-worker test could diagnose retention but
could not replace hosted evidence. Even full coverage supports only this finite
representative path: complete-verifier memory, request CPU, lifetime peak,
longer-term growth and production lifecycle acceptance remain open.

### Outcomes and next decisions

| Observation                                                                                                                                                                                              | Next step                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Correct bytes and closure acknowledgements; both warm cohorts and same-worker arrival coverage observed; comparable quiescent samples and observed maxima show no sustained upward trend; no safety stop | Propose a bounded **inactive implementation** checkpoint for review, listing omitted SQL claims/receipts and lifecycle work plus the complete-verifier qualification still needed. Stable observed memory is directional evidence only. It supplies neither a final full-verifier budget nor permission to implement.                                                                        |
| Rising quiescent/peak-sample envelope, resource stop, deadline failure or uncertain cleanup                                                                                                              | Preserve the failing case and stop where the existing safety rules require. Propose a focused investigation of retention, native buffers, CPU or cleanup before expanding implementation; no automatic rerun, higher threshold or budget adoption. A crossing of 96 MiB alone remains a historical-target exceedance and may continue only under separately approved characterization rules. |
| Inadequate metric domain/resolution, missing CPU attribution or insufficient same-worker coverage                                                                                                        | Report exactly what was observed and propose a measurement/coverage amendment. Do not infer stability from unrelated workers or use shutdown snapshots as peak proof. Missing CPU attribution leaves that acceptance open even when memory trends are useful; absent usable in-run memory stops full-media work.                                                                             |

Compare each cohort's ordered samples and tail with its earlier warm values;
disclose measurement noise and ambiguous trends rather than declaring a plateau
from a flat average. Mixed outcomes take the more restrictive next step. None of
these outcomes closes production acceptance or automatically authorizes
construction, another experiment or a budget change.

**Historical next decision (now satisfied as design only):** resolve private
fixture placement and propose a compatible measurement/safety method using the
selected production alpha Supabase project. The read-only inventory is complete.
The characterization scope is accepted; local construction awaits a later
approval request after the remaining gaps close. Hosted execution, the proposed
abort threshold and its overshoot limitation still require separate explicit
approval. No test, construction, provisioning or configuration change ran as
part of this update. Activation remains disabled and AWS unapproved.
