# CPM-1 complete-verifier measurement proposal

> October 14: this unapproved scope is superseded by the
> [smaller measurement proposal](client-prepared-media-measurement-revised-scope-2026-10-14.md).
> Target/metric feasibility now precedes construction; a representative path,
> simpler bounded driver and separately approved characterization stop threshold
> replace the proposed complete-verifier build as the next experiment. The text
> below and its reviews remain historical, not current approval instructions.

Status: October 13, 2026. **For approval; no implementation or experiment
started.** Baseline: `ff7962099eb1f4c5d6728fc3002e630ce8d29cda`. This responds
to the human's request for a bounded proposal following the
[buffer-lifetime investigation](client-prepared-media-buffer-lifetime-budget-review-2026-10-13.md).
It changes no adopted resource limit, receipt semantics or release permission.

## Recommendation and approval stages

Measure an isolated, inactive candidate on the **intended hosted Supabase Edge
runtime**, using TLS reads from the intended private R2 storage and real
nonproduction Supabase Auth/Postgres boundaries. A macOS Deno process or local
Edge container can help prepare it, but cannot replace that measurement.

The complete CPM verifier is not implemented. The existing buffered
`initialAnalysis/mediaHandoffStorage.ts` path calls `readInitialStream` and
`initialMediaHash`; increasing its limit or relabelling the standalone hash
probe would not produce the proposed complete incremental verifier. The fresh
CPM claim/receipt/clock/reference agreement also remains open. These are
explicit preparation tasks, not a reason to claim missing work has zero memory
cost.

Recommend two separate approvals:

- **A — local candidate preparation:** at most two engineering days to close the
  narrow measurement interface, assemble a qualification-only full verifier
  candidate, instrument it, and run its local correctness/cleanup checks.
  Produce an exact source/dependency manifest and independent/IC-1 review. No
  deployment, hosted access or runtime feature integration. Local new
  fixtures/evidence stay within 512 MiB and workstation free space above 20 GiB.
  This stage requires approval; nothing in this proposal starts it.
- **B — named-target execution:** approve the exact reviewed candidate, named
  existing nonproduction targets, permitted setup/read/write/cleanup operations
  and finite matrix below. Target identifiers and runtime details are not yet
  available, so stage B cannot be an executable approval today. Return the
  completed target sheet and exact candidate for approval after A. Do not create
  a project/bucket, install a function or change credentials as implied setup.

Within A, agree the minimal measurement slice before writing it: actual caller,
immutable object/manifest identity, reference/finality proof, claim/attempt and
receipt/status operations, retirement fence, physical-reader occupancy and
cleanup ownership. No invented production schema expansion to support unproved
claims. Use existing applicable owners and narrowly reviewed qualification
bindings. If a needed owner or agreement cannot be supplied within the timebox,
return that concrete gap. Stubs may support local tests but must be listed as
partial evidence and cannot earn the label **complete verifier**. Full product
acceptance follows implementation; it is not a prerequisite to writing the
approved test candidate.

History primary owns all writes. IC-1 reviews original authority/receipt/funding
boundaries and independent review checks measurement, concurrency and shutdown.
The production integration hold remains active locally and unpublished. Feature
activation stays disabled, ordinary app access nil, AWS unapproved and automatic
prompts paused. No push/merge, production deployment, device work, provider
calls, funding, scheduling, distribution or later redesign is included.

## Required target sheet before B

Record identifiers in private execution evidence, never credentials in the repo:

| Item            | Required selection/proof                                                                                                                                                                                                 |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Supabase        | Existing isolated nonproduction project reference, region, plan, test-only function name and database namespace; affirmative production exclusion                                                                        |
| Runtime         | Actual hosted Edge/runtime/build identity where exposed, exact code bundle/dependency hashes, configured worker memory and lifetime limits with exact units; document anything the platform does not expose              |
| Storage         | Existing private R2 account/bucket and allowlisted TLS endpoint, dedicated opaque run prefix and fixed fixture inventory; private policy, lifecycle exclusions and credential/writer inventory                           |
| Access          | At most two synthetic test owners; operator-only authenticated allowlist; least-privilege fixture storage and test-ledger access, no provider or production credentials                                                  |
| Operations      | Exact function installation/update, narrowly scoped test-schema setup if required, fixture PUT/HEAD/GET, test-ledger writes, status reads, and named fixture/function teardown; each explicitly authorized               |
| Measurement     | Worker identity/reuse correlation, total-worker memory semantics, peak visibility and request CPU attribution; driver abort and independent run-disable path                                                             |
| Costs/retention | Existing-target charges estimated from the bounded workload before launch; no new paid resource provisioning. Fixed fixtures removed after safe closure; content-free cleanup obligations retained if closure is unknown |

Supabase publishes 256 MB memory, two seconds CPU per request and worker
lifetimes of 150 seconds on Free / 400 seconds on paid plans. These are
documented ceilings, not confirmation of the chosen target's byte accounting or
usable application budget. Pin observed target details rather than assuming
local Deno 2.9.4 equals the hosted build.
[Official limits](https://supabase.com/docs/guides/functions/limits).

## What “complete” includes

The timed invocation must include the actual request wrapper and imports,
authentication and owner checks, bounded manifest parsing (including the largest
legal metadata shape), reference/capacity and finality reads, durable claim and
attempt accounting, signed private TLS GET, incremental full-length/hash checks,
serialized receipt commit or exact status recovery, response serialization,
reader/hash release and cancellation handling. Measure errors too. No media
decoding, provider request or scan-token settlement is part of this verifier.

Freeze the complete dependency graph and effective test callers. Ordinary
feature gates remain false. A distinct test entrypoint exposes only this
qualification composition to the two synthetic owners; it cannot call admission,
dispatch, refund or completion owners. Its installation is a hosted deployment
requiring B approval even with all product flags disabled. No in-memory mock
ledger, synthetic stream replacing TLS, hash-result cache, shortened manifest or
removed middleware may substitute for omitted full-path overhead.

Fixture data is synthetic and nonpersonal. Success cases use supported valid
representations and frozen manifests; negative cases use intentional mismatches.
At most 48 fixed media objects, each within the existing per-role/per-asset cap,
and 1.5 GiB media total in the dedicated private prefix. Each legal package
remains within 96 MiB, with at most two originals and the existing role counts.
Do not issue outstanding client upload tickets: fixtures are operator-seeded
before the run, hashes verified independently, and write authority closed by the
reviewed fixture procedure. This isolates verifier measurement; it does not
qualify the fresh-upload ingress protocol or general late-writer closure.

Use distinct legitimate object/manifest bindings when a case needs a fresh full
read. A known successful receipt must recover without another full verification;
do not defeat replay semantics to create benchmark work. Failed read retries
remain limited to three durable attempts under the original nonrenewable
30-minute intent. Unknown receipt outcomes require recovery/fencing first. Stage
A must allocate the exact case identities within existing reservations: no more
than two simultaneous pending intents per owner or the existing global limit.
Preseeded source bytes need their own authoritative retained references; they
are not unaccounted staging objects. No limit is enlarged by this proposal.

## Finite execution matrix

One execution packet, no automatic rerun or tuning. Maximum **48
verifier/control invocations** in this matrix, **64 additional status/metric
polls**, **30 minutes for measurement**, then a **15-minute bounded
shutdown/cleanup window**. Setup and teardown inventories allow at most 48 PUTs,
48 setup HEADs, 96 DELETEs and 96 cleanup HEADs. Maximum 1,000
application-issued target HTTP calls including Auth/RPC and retries, and 4 GiB
aggregate application media transfer. Count calls/bytes in the driver and
outbound instrumentation; disable uncounted SDK retries. These are experiment
caps, not exact bounds on provider-internal buffers or billing. At an exhausted
cap stop new work and record unfinished obligations; do not silently extend the
packet. Explicit operator recovery may still be needed if cleanup remains
unknown.

| Group                              | Maximum invocations | Purpose and evidence                                                                                                                                                                                                                                                                                        |
| ---------------------------------- | ------------------: | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Observability and denial preflight |                   6 | Loaded-worker baseline; one 64 KiB positive control; invalid/foreign-owner and oversized metadata denials before storage read; establish metric correlation and verify flags/allowlists. If peak/CPU visibility is inadequate, stop the resource run as unobservable.                                       |
| Cold full path                     |                   3 | Three 32 MiB fresh verifications on observed new workers; record imports/startup separately and whole-worker peak without subtracting baseline. If routing does not supply three cold workers, record incomplete coverage; do not redeploy merely to force it.                                              |
| Warm sequential reuse              |                  24 | Two cohorts of 12 fresh 32 MiB verifications each, one outstanding request at a time, targeting a window of 80% of the confirmed worker lifetime, capped at 360 seconds per cohort. Bind every observation to actual worker identity and invocation ordinal.                                                |
| Concurrent arrivals                |                   6 | Three pairs: different objects, same object, and competing owner/authorization. Two simultaneous client requests maximum. Verify the existing proposed **one physical body reader per worker** policy and denial/status behavior before another GET; do not silently permit two hash streams in one worker. |
| Recovery and retirement            |                   9 | Three schedules, at most three invocations each: interrupted read/cancellation with a competing retry; lost receipt acknowledgement and exact status recovery; retirement during a delayed read and late receipt denial. Observe physical closure and stale authority fencing, not just client timeouts.    |
| **Total**                          |              **48** | Stops earlier on a failed guard, resource target or missing essential measurement.                                                                                                                                                                                                                          |

For warm cohorts, schedule starts across the fixed window, but never overlap
sequential requests to catch up. If a request lasts too long, the cohort timebox
wins and remaining reads stay unrun. Worker replacement is recorded as a break
in the cohort. Twelve unrelated worker IDs do not prove warm reuse; no keepalive
loop, single giant batched invocation, redeploy or routing-affinity trick is
added. If twelve requests on one worker cannot be observed, return incomplete
warm coverage. Even successful 80%-lifetime coverage leaves the final tail and
longer lifetime configurations explicitly unqualified.

Concurrent arrivals measure both admitted work and busy/duplicate/denied request
overhead. Two parallel requests landing on separate workers do not measure
same-worker contention; mark that row unobserved. Across workers, no same-object
replacement reader starts while the old reader's physical closure is unknown. If
the existing design cannot enforce or observe this, stop and report the
ownership gap. A lease expiry never proves termination. This packet does not
approve intentional double-reader overlap or a larger production concurrency
limit. It measures whether the proposed single-reader policy withstands
concurrent arrival and recovery; a design allowing overlap needs a different
explicitly bounded packet.

Fault hooks must be confined to the test entrypoint and preserve real clocks,
limits and transaction semantics. Delay/cancel within the original deadline;
never shorten lease TTLs or reset authority to make a race occur. If a desired
race cannot occur under the fixed candidate's timing, mark it inapplicable with
proof or unobserved, rather than change the candidate mid-run. Lost receipt
acknowledgement must not cause another body read or AI execution.

## Reserved stop and recovery capacity

Do not allow measurement work to exhaust the operations needed to stop it. Split
this packet's caps before any work starts:

| Pool                                              |            Target HTTP-call allowance | Application media allowance |
| ------------------------------------------------- | ------------------------------------: | --------------------------: |
| Setup                                             |                                   120 |                     1.5 GiB |
| Normal measurement                                | 480, at most 10 per matrix invocation |                     1.5 GiB |
| Disable, cancellation, reconciliation and cleanup |                      **400 reserved** |          **1 GiB reserved** |
| Total                                             |                                 1,000 |                       4 GiB |

The recovery pool covers the 64 polls, at most 96 DELETEs and 96 cleanup HEADs,
up to two late recovery callbacks for each of the 48 invocations, and 48 calls
for run-disable/auth/other closure work. These maxima sum to 400. Setup's 48
PUTs and 48 HEADs leave 24 calls for configuration/auth/schema-control
operations. Any candidate needing more calls must return a revised packet before
launch; there is no silent transfer out of the recovery pool. The 15-minute
cleanup window is reserved after the 30-minute measurement window, not consumed
by it.

A must bind a non-reassignable allowance to each invocation and reserve its full
worst-case body/callback liability **before** dispatch. Admission and allowance
allocation must serialize run-wide; concurrent handlers check/debit their bound
allowance before each outbound call. An idempotent replay or unknown termination
cannot obtain another normal-work allowance. Driver counters after completion
are observations, not enforcement. Specify the actual test-controller grant and
atomic allocation mechanism in A; no new production resource ledger is implied.
If the mechanism cannot bound parallel or delayed callbacks, B is blocked.
Unused grants are not recycled until their owners are positively terminal.

Stop new admission before any normal-work slot or byte reservation is exhausted,
or before the last request could exceed the measurement window. In-flight calls
keep their reserved worst-case liability; cancellation does not release it.
Recovery calls share the already reserved pool rather than racing to use its
last slot. A reserved emergency disable action has priority over optional status
polls. At exhausted recovery capacity or unknown closure, keep the run disabled,
retain references/fences/reservations and the unresolved inventory, and request
separate operator recovery. Never exceed the approved cap to report green
cleanup.

## Instrumentation and decision rules

Record bounded phase timings and synthetic case/worker aliases only—no tokens,
private storage URLs, raw user identifiers, request bodies or original media in
logs. At most 128 MiB retained metric/log artifacts within the 512 MiB local
allowance. Collect loaded baseline, after-auth/claim, read start/end,
receipt/response and cleanup samples; aggregate additional samples locally in
the worker rather than emitting a log for each chunk. Calibrate instrumentation
cost in A and report it. Do not force GC or omit that overhead from total
memory.

Required memory evidence is a target-defined **whole-worker peak**, including
native TLS/fetch and hash buffers and overlapping request handlers. Record heap
and external samples for diagnosis, but never label sampled maxima or shutdown
snapshots as proof of the true peak. Supabase documents shutdown memory as a
snapshot. A must document a credible high-water and request-CPU attribution
mechanism from available documentation and permitted read-only configuration,
including what remains unverified. A does not prove live target telemetry. B's
first six observability calls, only after named-target installation/preflight
approval, are the confirmation point. Permit at most one 64 KiB media fixture at
that point; defer bulk fixture creation and every full-media case until the
metric gate passes. If no credible mechanism can be identified in A, or live
visibility/CPU attribution fails in B, return a concrete instrumentation or
acceptance amendment instead of pretending to close the gate.
[Official shutdown metrics](https://supabase.com/docs/guides/troubleshooting/edge-function-shutdown-reasons-explained).
A host/container RSS value cannot silently replace isolate memory accounting.

Per-request CPU needs target attribution. Under concurrency, cumulative worker
CPU must not be divided by request count. Capture worker totals too; unresolved
attribution leaves the one-second request target unqualified. Wall timing covers
request entry through response and cleanup, with the irreversible receipt
eligibility deadline fixed at 30 seconds. Cleanup may finish after that
deadline, but cannot publish a late receipt or start another read while closure
is unknown. Record those durations separately; a driver timeout does not
terminate hosted work. Pin a bounded drain/disable procedure and receipt fence
before launch.

Keep the **96 MiB experimental target**, one-second CPU target and 30-second
receipt deadline unchanged for this packet. At the first observed resource
exceedance stop issuing work, cancel where supported, recover original state and
report the failed case; do not switch to 128 MiB, 75% of platform memory or an
unapproved higher cap mid-run. If measurement lacks sufficient resolution to
detect the exceedance promptly, disclose that limitation. JS guards are not a
hard memory or synchronous CPU limiter. A platform memory kill, wrong hash,
unauthorized GET, stale receipt, uncontrolled reader or unknown shutdown is a
failure/stop, never a retry credit. Known capped cancellation in the fault cases
is expected only if all specified authority/closure outcomes hold.

Classify each row separately as passed, failed, unobserved or not run. For warm
memory report per-invocation peaks and quiescent values, all worker restarts and
the whole cohort high-water. A rising envelope is unresolved growth, even if it
stays below 96 MiB. Absence of observed growth over this finite window supports
only that window; it is not a leak-proof claim. Do not average away a failed
cohort or subtract startup to obtain a pass.

The deliverable is an evidence-based recommendation: measured full-worker peak
`P`, run variation and explicitly justified allowance `A`, actual platform
envelope `L`, and resulting margin. The prior proposed 25% platform reserve is
still a policy suggestion, not adopted acceptance. Missing peak visibility,
coverage or allowance evidence means **no new numeric budget justified**. All
previous 172.59/122.81 MiB failures and 89.75 MiB local fetch evidence retain
their original meanings. No result automatically adopts a higher budget or
qualifies the entire feature.

## Exit and approval request

A delivers the reviewed executable packet or a precise blocker within two days.
B, if separately approved with named targets, ends after its one finite run and
bounded cleanup. Revoke test invocation access first on stop; reconcile receipts
and readers, then remove only proven unreferenced run-owned fixtures/test
records under the approved cleanup authority. Do not delete fences or release
capacity on unknown closure. Keep a private unresolved-obligation inventory,
bounded alerts and an identified operator if the 15-minute cleanup window
expires. No recurring cleanup schedule is created by this proposal.

Approve **A only** to prepare a concrete reviewable candidate and target sheet.
Hosted installation/execution/cleanup B returns for explicit exact-target
approval. This prevents a generic “proceed” from being interpreted as deployment
permission. The current request authorizes this document only; no test has run.
