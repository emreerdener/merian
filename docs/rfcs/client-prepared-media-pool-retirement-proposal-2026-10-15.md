# CPM pool shutdown: source review and bounded retirement proposal

October 15, 2026. **Proposal only; no implementation or execution authorized by
this document.** Activation disabled, AWS and 160 MiB unapproved, all existing
limits unchanged. Auto-prompts remain paused. No product acceptance closes.

## Recommendation

Test one narrowly scoped harness correction: after the single workload result
and terminal veto, request retirement of the sole idle user worker through the
pinned runtime's existing API, then require an empty pool-registry observation
before accepting normal external termination. Keep the main listener alive,
`--graceful-exit-timeout 0`, Docker stop grace one second, and all deadlines and
resource limits unchanged.

This is a source-supported **hypothesis**, not a proven fix or a guarantee of
process quiescence. A cleanup acknowledgment alone is insufficient. If bounded
retirement cannot produce the required evidence, stop with a failed lifecycle;
do not lengthen a timeout, retry the campaign or suppress the pool error.

Request a fresh two-hour local construction/review window after approval, at
most two short comparison controls, then one conditional unchanged synthetic
campaign only after successful controls and separate exact independent/IC-1
concurrence. No new verifier bundle, image, dependency or interpreter is needed.
This scope replaces no prior evidence and does not reuse an unspent campaign
allowance without explicit new approval.

## What the source establishes

The public v1.77.0 tag resolved to commit
`e847536d7b276428415d7cf9877803d99a16fde5`. Eleven cached source files were
checked against that commit's Git blob identities; SHA-256s are recorded in
`.artifacts/client-prepared-media/pool-shutdown-review/source-manifest.json`.
The tested image remains
`sha256:5f555406dc0705d775323c58e27e856cca7b5b8d0ab726cc6a30b11fcfc7c6b3`. The
image reported v1.77.0 in prior evidence; this review does not independently
prove binary-to-source build correspondence.

1. The exact pool error comes from a user-worker completion scope guard. It
   sends `UserWorkerMsgs::Shutdown(key)` and logs the error when the receiver
   has already closed. Runtime drop and supervisor completion precede that send
   on the ordinary completion path. This is a runtime pool-channel notification
   failure, not a provider request failure.
   [worker_inner.rs, lines 310–353](https://github.com/supabase/edge-runtime/blob/e847536d7b276428415d7cf9877803d99a16fde5/crates/base/src/worker/worker_inner.rs#L310-L353).
2. The pool receiver belongs to a detached task. Processing `Shutdown` removes
   the worker profile. Ordered cancellation waits for the registry to become
   empty before acknowledging pool termination. Abrupt executor teardown can
   instead drop that receiver.
   [pool.rs, lines 690–705 and 813–911](https://github.com/supabase/edge-runtime/blob/e847536d7b276428415d7cf9877803d99a16fde5/crates/base/src/worker/pool.rs#L690-L911).
3. SIGTERM with zero graceful-exit timeout bypasses the ordered termination
   branch; the positive-timeout branch drains transport and terminates the pool
   before the main worker. This supports a teardown-order explanation for the
   retained log, but does not prove the precise scheduler interleaving.
   [server.rs, lines 134–143 and 693–810](https://github.com/supabase/edge-runtime/blob/e847536d7b276428415d7cf9877803d99a16fde5/crates/base/src/server.rs#L693-L810).
4. The CLI explicitly documents zero as disabling graceful exit and maps a
   returned termination signal to the exit code. Exit 15 therefore does not
   prove an orderly pool shutdown.
   [flags.rs, lines 153–162](https://github.com/supabase/edge-runtime/blob/e847536d7b276428415d7cf9877803d99a16fde5/cli/src/flags.rs#L153-L162),
   [cli/main.rs, lines 321–326](https://github.com/supabase/edge-runtime/blob/e847536d7b276428415d7cf9877803d99a16fde5/cli/src/main.rs#L321-L326).

The
[retained control result](client-prepared-media-clock-qualification-result-2026-10-15.md)
shows a complete terminal/stop/signal/error/EOF receipt sequence and confirmed
cleanup, with the pool error still present. Receipt order is not internal
emission order. Earlier successful workload evidence and failed lifecycle
classification remain unchanged.

## Existing API and proof boundary

The runtime exposes `EdgeRuntime.userWorkers.tryCleanupIdleWorkers(timeoutMs)`
and `memStats()`.
[user_workers.js, lines 176–182](https://github.com/supabase/edge-runtime/blob/e847536d7b276428415d7cf9877803d99a16fde5/ext/workers/user_workers.js#L176-L182).

Cleanup waits for bounded early-drop acknowledgments. The supervisor
acknowledges only after pending requests and promises are resolved and it
dispatches the before-unload hook; actual early termination follows later. Thus
a return value of one proves exactly one true early-drop acknowledgment: the
request was delivered and the supervisor reported pending tasks resolved and
before-unload dispatched. It does not prove registry removal or process
destruction. Zero can also mean a closed pool channel.
[strategy_per_worker.rs, lines 107–116 and 472–500](https://github.com/supabase/edge-runtime/blob/e847536d7b276428415d7cf9877803d99a16fde5/crates/base/src/worker/supervisor/strategy_per_worker.rs#L472-L500),
[workers/lib.rs, lines 698–718](https://github.com/supabase/edge-runtime/blob/e847536d7b276428415d7cf9877803d99a16fde5/ext/workers/lib.rs#L698-L718).

`memStats()` routes a request through the same pool channel. The pool snapshots
its registered profiles and reads their cached `mem_check.current` values; this
is not a new V8 memory sampling call. Only an empty successful map is used here.
For the isolated one-worker harness, after an authentic completed request proves
registration and the terminal veto forbids further creation/forwarding, an empty
registry supports that worker's `Shutdown` message having been processed. A
nonempty map may simply precede that message from another sender. Do not infer
global FIFO across senders or process destruction from the empty snapshot.
[pool.rs, lines 707–724 and 776–799](https://github.com/supabase/edge-runtime/blob/e847536d7b276428415d7cf9877803d99a16fde5/crates/base/src/worker/pool.rs#L707-L799).

No memory values, service paths or pool keys from these inventories should be
persisted. Record only bounded call count and empty/nonempty status. These new
post-terminal inventory calls are teardown evidence, excluded from all workload
memory/growth measurements. They require explicit approval as part of this
method amendment, despite leaving numeric limits unchanged.

## Exact proposed change after approval

Only copied local test main harnesses and their lifecycle parser/tests may
change. Preserve the verifier ESZIP, worker shim, workload, policies, runtime
binary/options, clock basis, independent guardian and cleanup ownership.

After the final fully consumed response:

1. Latch the existing terminal veto and emit the single workload result. Require
   the existing zero-pending-dispatch/readers predicate and exactly one created
   worker. Keep the listener alive. A failed workload remains failed regardless
   of later cleanup.
2. Emit `dispatch_closed`, then a bounded `pool_cleanup_started` marker. Start
   one **1,500-ms total teardown budget**, contained within the unchanged
   two-second host drain from terminal receipt. The main cannot know that host
   receipt time: containment must be established by the host parser requiring
   `pool_empty` receipt before `stop_intent`. No deadline is renewed.
3. Call `tryCleanupIdleWorkers(250)` exactly once, with a host-main promise
   deadline of at most 500 ms clipped to the phase budget. Require exactly one
   true early-drop acknowledgment. Missing API, rejection, timeout, zero or
   unexpected count records failure; no second retirement request.
4. Make at most three sequential registry inventory calls, each with at most 250
   ms clipped to the same phase budget, separated by at most 50 ms only when the
   preceding result is nonempty. Stop at the first valid empty map. Validate
   native map shape; null, malformed, unavailable, rejected or timed-out results
   fail. No memory statistics are used to qualify or relax a gate.
5. Emit `pool_empty` only after that positive result. No more worker requests,
   creates, cleanup requests or inventory calls follow. Pending operations from
   a promise timeout are unresolved obligations, not canceled merely by racing a
   timer; they prohibit a success marker. Clear owned teardown timers.
6. The existing host drain, stop, EOF collection and immutable-ID cleanup still
   run on their original schedule. If evidence is late or absent, fail rather
   than postponing termination. The host parser must reject `pool_empty`
   received at or after `stop_intent`; source emission order is insufficient.
   The independent absolute watchdog always wins.

The runtime emits an early-termination info line on its `EarlyDrop` path. The
parser may recognize exactly one such line only after the cleanup-start marker
and for the exact created worker key, with UUID comparison kept in bounded test
state. It must remain unexpected during workload execution, before cleanup or
for another worker. All pool-send errors, resource alerts, unknown lines,
missing markers, timeouts, wrong exits and incomplete cleanup remain failures.
This is an explicit expected teardown event, never a blanket stderr allowlist.
Preserve raw local test logs under the existing cap.

The new markers fit the existing 16-record total host-journal allowance and
512-KiB combined logs; exact implementation must account for this before review.
They must distinguish request acceptance, registry-empty observation and actual
process exit rather than naming any of them graceful destruction.

## Bounded validation and review gates

Before any execution, prepare focused synthetic checks for accepted-but-not-yet
removed workers, nonempty/empty inventory ordering, closed-channel zero,
malformed data, clipped deadlines, timeout without cancellation, no forwarding
or creation after terminal, exact early-drop-line gating, and every existing
failure parser. Prove all frozen source/ESZIP hashes unchanged. Reuse the exact
qualified clock/watchdog evidence only after reviewers confirm those sources and
interpreter are unchanged; no new clock or watchdog control is requested.

Independent and IC-1 concurrence must bind the exact control sources, parser,
commands, evidence manifest and unchanged limits before these two controls:

- **A, baseline:** copy the most recent retained-listener control without idle
  cleanup. One case-26 denied request; expect the retained pool-send error,
  signal/exit 15, full EOF and cleanup. It is a failure reproduction, not a
  pass.
- **B, proposed:** same single denied request and source except the bounded
  post-terminal retirement procedure. Require one acknowledgment, valid empty
  registry observation, the expected early-drop event, then unchanged external
  signal/exit 15, no pool/error/alert lines, complete receipt order/EOF and
  confirmed cleanup. Any failure ends the scope without another control.

Each control remains at most 15 seconds plus 30 seconds cleanup. No media read,
provider invocation or extra user worker is allowed in either control. Failed
startup consumes its control; no third control or variant retry.

Only after successful controls and separate exact campaign concurrence, one
unchanged 21-request, 604,110,848-byte synthetic campaign may run if at least 17
minutes remain. It retains the 900-second absolute deadline plus 120-second
cleanup, 1,800,000-ms worker lifetime, one active read, original cohort spacing,
96-MiB proxy/8-MiB growth stops, 256-MiB worker/512-MiB container, one CPU,
5,000/10,000-ms worker CPU limits, 30-second request deadline and 8-KiB response
cap. No extra workload memory calls or observer timers. Post-terminal teardown
cannot repair a workload failure. No retry or window extension.

Keep network disabled, no published port, read-only mounts, dummy-only
configuration, zero new bundles, 24-MiB new evidence, 16-MiB tmpfs reservation,
512-MiB aggregate CPM evidence and 20-GiB free-disk floor. Preserve old evidence
and all unrelated work. No hosted or credential actions, push, merge,
deployment, provisioning, device operations or distribution.

## Alternatives and unresolved risk

Nonzero runtime graceful exit uses the source's intended ordered cancellation
path, but changes a frozen option and may require coordinating Docker's
one-second stop grace. It is outside this unchanged-limit proposal. Runtime
upgrades, patching the binary, adding an event worker, forcing GC, shrinking
worker lifetime or ignoring the error are also excluded.

The proposed API sequence is specific to an isolated, single-worker local
harness. It cannot prevent arbitrary external termination, guarantee OS-level
quiescence, or establish hosted lifecycle behavior. If it fails, preserve the
failure and return the remaining constraint conflict; do not automatically adopt
another shutdown policy. Approval would authorize testing this hypothesis, not
adopting it as a qualified runtime fix or closing product acceptance.
