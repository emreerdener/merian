# CPM local allocation diagnostics and shutdown fix: approval scope

> Current October 14: the approved request-boundary campaign completed all 20
> media reads on one worker in 682.342 seconds, but failed runtime shutdown
> qualification after a worker-pool shutdown error (exit 1). External container
> removal is confirmed. See the
> [exact result](client-prepared-media-request-boundary-result-2026-10-14.md).
> The single campaign is consumed; no retry or limit change. Activation
> disabled, AWS unapproved, auto-prompts paused. Earlier preparation/proposal
> states below are historical; product acceptance remains open.

> Current October 14: the user approved local preparation, but independent and
> IC-1 review found an unproven parent-to-worker idle-timer cancellation path.
> Two inert controls are complete; no bundle or verifier campaign ran. See the
> [prelaunch finding and proposed method amendment](client-prepared-media-allocation-diagnostics-preflight-2026-10-14.md).
> Launch remains blocked pending explicit scope resolution and exact-candidate
> review. Activation disabled, AWS unapproved, limits unchanged. Earlier
> approval/status text below is historical.

October 14, 2026. **Proposal and independent/IC-1 review only.** This document
requests approval for a fresh bounded local window; it does not adopt changes or
authorize construction, runtime controls or another verifier campaign.
Activation remains disabled, AWS and the 160 MiB threshold unapproved, and all
existing product, package, storage and experiment limits unchanged.

## Decision requested

Authorize a fresh **two-hour local window**, starting when work resumes after
approval, for the sole history primary to construct a non-deployable diagnostic
harness, perform the bounded controls below, obtain exact-candidate independent
and IC-1 concurrence, then execute **one** local synthetic campaign. Maximum
campaign duration is 900 seconds plus at most 120 seconds cleanup, inside the
two-hour window. Reserve at least 17 minutes before launch. No automatic
extension, second campaign, replacement worker or retry. If preparation or
review cannot close in time, stop with evidence and return the blocker.

Approval of this proposal would authorize that sequence only. Proposal review is
not executable-candidate concurrence. No code has been changed or executed for
this proposal. The previous campaign allowance is consumed and cannot be reused.

## Evidence and questions

The
[reviewed prior result](client-prepared-media-controlled-worker-result-2026-10-14.md)
is preserved at local commit `ad5c8a4c0`. Exact old candidate set:
`fed50e9aade4db3e0cfb716357c1412b143b9d0505bd046d4419bb0e65fdea18`; result set
`d20c45d8dd9e305110a8ce53ab979cf25630ae7a2d0c42c0ecc14a2753dcf66f`.

That campaign stopped at 42.283 seconds: control/control/a/a post-cleanup
samples rose 12.2789 MiB across three positive increments, exceeding the
unchanged 8 MiB stop. Its peak partial V8 proxy was 37.26275 MiB, below 96 MiB.
One worker served four reads, three accepted as verified and the fourth stopped
with matching bytes/digest and positive closure. This does not prove a leak or a
stable warm-memory plateau. A separate unsupported `Deno.exit` call failed after
the terminal result; external container removal succeeded.

Answer three bounded questions:

1. Which allocation/retention paths can be established from source: incremental
   64 KiB fixture chunks, signed GET/response wrappers, hash/reader lifetime,
   timer/listener cleanup, telemetry and instrumentation storage?
2. Do co-timed heap-used, heap-total and external-memory values drop in the
   existing idle interval after successful large reads, or remain elevated?
   Describe observations without attributing GC, a native leak or faithful
   production R2 behavior that the measurements cannot prove.
3. Can the corrected harness finish its main-service lifecycle and retain
   bounded terminal/error evidence while the independent guardian always
   terminates/removes only the owned container?

## Ownership and allowable construction after approval

History primary owns all writes and operation. Independent reviewer and
`Harden main analysis engine` / IC-1 remain read-only; no shared implementation
handoff. Original candidate `9c88cc72d35d925a3e4a7d7890f2ec8728d0e414`, the old
package, manifests, tests and failed logs remain immutable.

Use a new ignored evidence root
`.artifacts/client-prepared-media/allocation-diagnostics/`. Changes are confined
to the local main harness, operator/guardian tests, and explicitly
non-deployable test entry/instrumentation/shim. The entry may instantiate the
unchanged `createWorker` with diagnostic dependency wrappers instead of
importing its normal entrypoint. It must preserve one module instance, one
handler and the same auth, policy, signing, verification, telemetry and
serialization path. Generate and review an exact source-delta manifest; do not
modify copied core handler, verifier, telemetry, policy, signing or shared
helpers. No lockfile, SDK, runtime image, deployable function, schema, iOS or
product changes.

If source review finds a suspected core defect, record it. Fixing it is outside
this scope; stop rather than silently making this a new verifier experiment.

## Minimal diagnostic instrumentation

Keep all original acknowledgements and success/stop semantics unchanged. Use a
separate, fixed-shape diagnostic event channel. The test-only wrapper may retain
only scalar counters and first/last co-timed snapshots per request. Observe the
existing `memoryUsage` dependency calls without changing their return values,
call count, order or the values passed to the original gates. This refers only
to the original gate dependency, not total runtime memory API calls. Do not
retain chunks, responses, requests, hash objects, stacks or unbounded arrays in
a collector. Fixture-byte generation, high-water mark, size, hash and signed URL
shape remain unchanged.

Emit at most **128 diagnostic records**, each at most **1 KiB serialized**,
inside the existing 512 KiB total log and 32 KiB line caps. Fields are limited
to synthetic case/fixture aliases, monotonic time, phase, sample ordinal,
co-timed heapUsed/heapTotal/external and their proxy sum, plus scalar generated
chunk/byte and stream-close/cancel counters. Counters are evidence of activity,
not proof that delivered buffers were freed. No heap snapshots, inspector,
profiling service, body dump, secret, real object identity or user data.

For each successful read, report its first and final original memory snapshot
and one aggregate shim counter record. For successful 32 MiB reads only, propose
two additional same-worker memory observations at approximately **+1 and +30
seconds after acknowledgement**, within the existing 40-second gap. These are
diagnostic only: they must not replace or insert samples into the original
four-point growth history. No idle observations after a failed/stopped read,
after the terminal result, or after the last scheduled read. At most two pending
diagnostic timers; cancel them on stop, next request or completion. Do not delay
the next request, catch up missed samples or wait longer to obtain a desired
observation. Cancellation by the next scheduled dispatch is valid and must be
recorded as skipped; record missing/late observations explicitly. Never force
GC, pre-warm, omit controls, reuse/reset a worker or change fixture order.

The extra idle calls use a separately named diagnostic-only snapshot capability
that directly calls `Deno.memoryUsage()` in this worker with the same co-timed
API/schema as the original dependency. It must neither use a cached snapshot nor
call the original gate dependency/wrapper. Its only permitted call sites are the
two idle timers. First/last original-call snapshots are captured only by the
unchanged gate dependency wrapper.

Idle observations execute inside the same retained worker, without extra handler
requests or new HTTP/control endpoints. Every timer callback must catch errors.
On observer failure, latch a test-entry fault, cancel all observers, veto any
subsequent entry into the original handler and emit one bounded fault record.
The outer operator treats that record as terminal and immediately starts
owned-container cleanup, without the normal two-second drain delay. The
scheduler must cease dispatch on the coordinated stop path. Exact-candidate
review must establish that stop propagation works with the pinned runtime and
that no post-fault original-handler call is possible; log monitoring alone is
not sufficient proof. Any request already racing the fault is recorded and
rejected by the entry veto, never forwarded or retried. If this cannot be
implemented within the existing transport/request bounds, block launch and
return the feasibility finding rather than add a new endpoint or relax stops.

If an additional observed proxy reaches 96 MiB, telemetry is invalid, the
diagnostic bound is exceeded or collection fails, stop the campaign as a
diagnostic failure. The original 8 MiB growth gate remains based only on its
unchanged post-cleanup points, including controls. Instrumentation overhead
stays included; this is an instrumented candidate, not an allocation-free
measurement or an exact quantitative comparison with the prior run.

## Shutdown correction and terminal evidence

Remove the unsupported `Deno.exit` call from the test main service. After its
single terminal result, prohibit further requests, cancel diagnostic timers,
await main-server shutdown and emit a fixed lifecycle acknowledgement. The
external operator/guardian owns process/container termination; do not introduce
a new worker termination API or assume native CLI APIs are available in Edge
Runtime. Establish the actual sequence with the pinned runtime control below.

The independent watchdog deadline starts at campaign launch **before container
creation**, as in the previous operator, and is never renewed at creation,
startup, result or lifecycle acknowledgement. Successful creation supplies the
immutable ID; guardian readiness is required before starting it. The guardian
acts independently of the main service, server-shutdown promise, operator and
log reader: at the 900-second deadline it starts bounded stop/removal even if
all of them hang. Before ownership is established, creation remains bounded and
uncertain creation cannot authorize name-only deletion. Unknown ownership is an
explicit reconciliation obligation. The operator drains from the terminal record
without waiting for a lifecycle acknowledgement; main-server shutdown cannot
block the guardian or extend the deadline.

The operator must not stop reading logs upon the terminal result. Continue a
bounded drain until process EOF or **two seconds**, whichever comes first,
always clipped by the original absolute 900-second deadline. Then trigger the
same immutable-ID guardian cleanup; continue bounded capture during that cleanup
until EOF or its 120-second deadline. No deadline renewal and no extra
read/provider work. Hard log/line caps still trigger cleanup immediately.

Record the cleanup trigger (normal completion versus absolute watchdog timeout),
terminal outcome, lifecycle acknowledgement, process-exit observation,
post-terminal diagnostics disposition and confirmed external removal as separate
facts. Known `Deno.exit`/event-loop/shutdown errors or any unclassified runtime
stderr fail lifecycle qualification even when removal succeeds. Missing
acknowledgement, missing EOF, truncated/capped diagnostics or uncertain status
must be explicit failures/unknowns, never inferred clean from
`operator_failure: null`. Expected operator termination must be distinguished
from graceful worker/process exit; a lifecycle acknowledgement alone proves only
that the main server's shutdown promise completed.

## Unchanged limits and bounded preparation controls

| Control                         | Bound                                                                                                                                                   |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Runtime                         | Cached Linux arm64 Edge Runtime v1.77.0 image `sha256:5f555406dc0705d775323c58e27e856cca7b5b8d0ab726cc6a30b11fcfc7c6b3`; per_worker                     |
| Worker lifetime / external stop | 1,800,000 ms internal / 900 seconds absolute external                                                                                                   |
| CPU                             | One container CPU; worker cumulative soft 5,000 / hard 10,000 ms; retirement stops campaign                                                             |
| Memory                          | Worker 256 MiB; container 512 MiB, no additional swap; 96 MiB proxy and 8 MiB growth stops                                                              |
| Workload                        | At most 21 requests: case 26 denial, controls 1–2, a 3–11, b 12–20; one worker, one active read; original schedule and at least 320-second cohort spans |
| Payload                         | Two 64 KiB controls and eighteen 32 MiB reads: at most 604,110,848 synthetic bytes; exact existing recipes/hashes                                       |
| Request                         | Existing 30-second request deadline and 8 KiB acknowledgement bound                                                                                     |
| Storage                         | At most 24 MiB new retained evidence, 16 MiB tmpfs, 512 MiB aggregate CPM including temporary reservation, 20 GiB free-disk floor                       |
| Logs                            | 512 KiB total, 32 KiB per line; diagnostic sub-cap 128 × 1 KiB                                                                                          |
| Isolation                       | Network none, no exposed port, read-only root/mounts, dummy-only allowlisted environment, no credentials, no image pull                                 |

Within the same two-hour envelope, allow offline type/lint/unit checks using
cached dependencies. Tests use synthetic clocks/counters; no verifier campaign
outside the single allowance. Cover first/last sampling, timer cancellation,
unchanged growth including controls, diagnostic overflow, error disposition,
terminal/EOF races, hung driver and immutable cleanup ownership. Keep the
existing failed case samples as a fixed arithmetic regression fixture.

Allow at most **two offline bundle attempts**, each capped at 30 seconds using
the existing cached bundler and container constraints; retain both attempts.
Allow at most **two inert lifecycle controls**, each at most 15 seconds running
plus 30 seconds cleanup, using the same pinned runtime/image and no verifier,
fixture stream or candidate bundle. One checks nominal server closure plus
external removal; one injects a bounded post-terminal error with a hung driver
to establish detection and independent deadline cleanup. The hung-driver control
uses a **test-only five-second watchdog deadline from control launch**, through
the same guardian code with an explicit control parameter. It proves wiring and
independence, not a 900-second elapsed-time run. Static/unit checks and the
executable manifest must separately prove that the real campaign passes exactly
launch + 900 seconds and cannot use the shortened control value or renew its
deadline. Capture the injected error before deliberately hanging the driver;
separately prove parser failure disposition with a synthetic-log unit test.
Watchdog timeout and positive container absence are required even when the
driver cannot complete its report. These are controls, not warmup or extra
verifier runs. Failure blocks launch; no third control or unbounded iteration.
Pure unit tests may iterate only within the two-hour and storage/log limits.
Check all caps before each operation; never delete old evidence or dependencies
to manufacture headroom.

Current read-only disk inventory is approximately 51 GiB free. Prior CPM
evidence is approximately 459 MiB; adding the full 24 MiB plus 16 MiB temporary
reservation would remain below 512 MiB. This is only planning headroom, not a
future launch preflight. No containers, packages, uploads or tests have been
created or run under this proposal.

## Launch gates, outcome and approval boundary

Before the one campaign, require green focused checks and both independent and
IC-1 concurrence on exact source delta, ESZIP, runtime/control evidence,
parameters, observer budgets, expected lifecycle and manifest hash. A material
correction requires re-review. Any dependency download, unsupported lifecycle,
resource excess or inability to observe intended points blocks launch; return
the finding instead of widening scope. Lock source during bundling/execution.
The launcher consumes the single allowance even if startup fails.

A useful diagnostic result may be another immediate growth stop. Report the
unaltered qualification outcome separately from the diagnostic observations. A
decrease between post-cleanup and idle snapshots supports transient allocation
as a hypothesis; persistence over this short interval does not prove a leak. If
the gate fires before useful idle data, report insufficient data and stop. Do
not continue after the stop, change the sample cohort or request another worker
within this authorization. Full reuse could only be claimed if the unchanged
full schedule passes; even that is local synthetic evidence only.

Deliver source-allocation map, exact instrumented candidate/provenance, bounded
control evidence, ordered scalar samples, unchanged gate calculation, lifecycle
and external cleanup results, retained failures and independent/IC-1 result
review. Retain all previous results unchanged. No hosted affinity/concurrency,
RSS/attributed CPU, product initial-media retention, audio quality, shared-asset
release, recovery, native or integrated acceptance gate closes from this work.
Deletion/export then redesign sequencing and capture-tools ownership remain
unchanged. Auto-prompts stay paused. Push, merge, provisioning, deployments,
secret operations, uploads, hosted tests, device work, activation and AWS remain
outside scope.

The present request authorizes drafting and review only. **Human approval of
this bounded scope is required before construction or controls; exact-candidate
review is additionally required before its single campaign.**
