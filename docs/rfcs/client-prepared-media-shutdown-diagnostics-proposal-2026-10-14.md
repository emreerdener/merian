# CPM local shutdown diagnostics and fix: approval proposal

October 14, 2026; revised October 15. **Draft/review only; execution awaits
human approval.** Activation remains disabled, AWS and 160 MiB unapproved, all
existing limits unchanged. Auto-prompts stay paused. This proposal does not
authorize a runtime run, construction, upload, secret access, deployment or
hosted action.

## Decision requested

Recommend a fresh **two-hour local window** after approval for a narrowly scoped
main-service shutdown correction, at most **two short lifecycle controls**, and
**one conditional local synthetic verifier campaign**. Both independent and IC-1
review must concur on exact control source/operator before controls and on the
exact final campaign candidate before launch. Proposal concurrence does not
substitute for either executable review.

The controls establish or fail to establish the proposed observed receipt-order
envelope; they cannot prove runtime-internal causal order or signal delivery.
Keep the one-campaign allowance unspent unless that envelope is observed, all
focused checks pass, both reviewers concur and at least 17 minutes remain.
Campaign maximum remains 900 seconds plus 120 seconds cleanup, all inside the
two-hour window. Failed startup consumes that campaign; no retry, replacement
worker, third control or window extension. All previous control and campaign
allowances are consumed and remain separate. This is a request for a new bounded
allowance, not reuse of the old one.

## Evidence and hypothesis

The
[reviewed request-boundary result](client-prepared-media-request-boundary-result-2026-10-14.md)
at local commit `c458b4ee1` remains **workload passed, lifecycle failed**. Its
candidate set is
`82f1c3a6e4bf3911f5924b4ff0504aec8894a15b4b9c649ec5e086951dcce333`; result set
is `59703c1c84692398dbc6fd3f9197004189d5c0eab96a435f8bbf518d3bd69449`. Twenty
exact synthetic reads closed on one worker; runtime shutdown then emitted
main-worker destruction and a worker-pool shutdown-send error, followed by exit
code `1`. External removal succeeded. None of those failures is reclassified
here.

Local main source `allocation-diagnostics/boundary/main/index.ts` sets its
terminal veto before the result, then calls `server.shutdown()` in `finally` and
reports `server_shutdown`. The operator drains for up to two seconds before
asking the independent guardian to terminate the owned container. Its runtime
command uses `--graceful-exit-timeout 0`; guardian stop uses `docker stop -t 1`,
followed by forced removal and an absence check. Those durations/options stay
unchanged.

The pinned
[v1.77.0 server source](https://raw.githubusercontent.com/supabase/edge-runtime/v1.77.0/crates/base/src/server.rs)
handles main-worker cancellation as a failure path (lines 638–666), separately
from its termination-signal path. This is source support for a hypothesis:
closing the main service before external termination may destroy a runtime owner
too early. It does not prove the complete causal chain or the cause of the
subsequent pool error. The final error lines have no emission timestamps, so the
existing log cannot reliably order their origin against external stop. Collector
timestamps in the proposed diagnostic will be receipt times, not runtime
emission times. The earlier nominal control had no real user worker; it did not
establish shutdown behavior with a populated worker pool.

## Smallest proposed change after approval

Keep the main server alive after a single terminal result, with the existing
terminal veto blocking every further forwarding attempt. Emit a fixed
`dispatch_closed` acknowledgement only after scheduling has ended and the
harness has accounted for in-flight requests and response/body obligations. Do
not label it `server_shutdown`: the listener remains open, confined to the
network-disabled container with no published port. It is the live server, not an
artificial timer, polling loop or invented worker API, that retains the main
service until external termination.

The external operator/guardian remains the sole termination owner. Retain its
two-second terminal drain, independent absolute deadline, one-second Docker stop
grace, immutable-ID deletion and bounded log capture through EOF/cleanup. Do not
change `--graceful-exit-timeout`, runtime binaries, worker lifetime or add a
second shutdown mechanism. Do not call `Deno.exit`, force GC, send a final
probe, invoke a new worker API or add background observers.

On a failure with unresolved request/body obligations, emit an explicit failed
or unknown disposition; never assert clean dispatch closure. Cleanup still runs
independently. A dispatch-closed marker is not proof of user-worker destruction,
internal pool draining, a graceful process exit or product operation completion.

Record bounded operator events for terminal receipt, dispatch-closed receipt,
raw error-line receipt, stop intent, guardian stop invocation/return, process
exit/EOF and confirmed removal, using the host monotonic clock in operator and
guardian. Add only scalar guardian journal markers bracketing its existing stop
command; preserve its behavior, ownership and deadline. Main markers also carry
their own runtime monotonic time, which must not be subtracted from the host
clock. Preserve raw runtime lines. Intent does not prove signal delivery; a
signal line, matching exit and confirmed cleanup are separate required evidence.
Missing chronology remains unknown. Keep host journals separate from the
existing user-worker `CPM_DIAG` stream and its unchanged parser/128-record cap.
Host journals have at most 16 records total across operator and guardian, each
at most 1 KiB, containing only fixed event, ordinal, host monotonic time and
bounded status/code fields. Each process owns its own append-only file. Merge
for offline analysis without inventing order for equal or missing timestamps.
Raw runtime log plus both journals share the existing 512 KiB total log cap and
retained-evidence cap. Record overflow or journal failure blocks qualification;
cleanup must still proceed. No user-worker instrumentation change is needed.

## Two comparison controls, then a conditional campaign

Construct both controls in a new ignored evidence root under
`.artifacts/client-prepared-media/shutdown-diagnostics/`. Each uses the same
pinned runtime/options and exactly one real user worker loaded from the existing
immutable verifier ESZIP, whose path/hash are given below. Each sends only the
existing case-26 denied request with its well-formed all-zero incorrect bearer,
using dummy-only configuration. Require the actual handler's 403 response and
existing handler/auth markers, at most 8 KiB response, and completely consumed
body with reader closure before the terminal record. No media GET, fixture
stream, signing or AI invocation is permitted; no auth code changes. These are
two lifecycle controls, not extra verifier/media campaigns.

Load bytes from the read-only `/candidate.eszip` mount using the same
`maybeEszip` and `/candidate/synthetic` servicePath as the executed candidate.
The exact local file is
`.artifacts/client-prepared-media/allocation-diagnostics/boundary/bundle-1/candidate.eszip`;
verify SHA-256
`3f28f9b7ac99d6d55d87cd1b47be19d4b6a2bebffcd0eb3531a340ade752fbf6` before each
run. No alternate source-loading assumption, new worker stub or bundle is
needed. The two controls differ only in terminal main-server behavior and its
truthful markers; enumerate any supporting difference for exact review. Both use
sequence: one fully consumed denied response, terminal veto latched, terminal
record, then baseline shutdown or proposed `dispatch_closed` marker. The latter
requires zero in-flight dispatch and no unresolved response reader; otherwise
record failure and clean up without claiming dispatch closure.

1. **Baseline:** reproduce terminal result followed by main-server shutdown with
   a populated worker pool. Expected diagnostic outcome is the recorded failure
   path, complete logs and successful external cleanup. That is a successful
   reproduction, never a lifecycle pass. If it does not reproduce, stop and
   return the inconclusive comparison; no automatic campaign.
2. **Proposed ordering:** retain the terminal-vetoed main server, acknowledge
   dispatch closure, and let the same operator/guardian terminate it. Require
   one request/worker, no post-terminal forwarding, complete response closure,
   bounded operator termination evidence, no unexpected runtime error, complete
   EOF and confirmed container/attachment cleanup. Any failure blocks the
   verifier campaign; no third control or variant retry.

Each control has at most 15 seconds from launch, with at most 30 seconds
cleanup. Its independent deadline begins before container creation, readiness
precedes start, and cleanup/attachment work shares one nonrenewable deadline.
Reserve the full 45 seconds before each launch. A short control does not prove
the full 900-second campaign watchdog; reuse the exact prior guardian evidence
only if hashes and reviewers confirm applicability. Do not rerun the consumed
hung-driver control; use synthetic clocks for deadline/error-path regressions.

After successful controls and exact final concurrence, run the unchanged
21-request request-boundary workload once. Reuse the existing verifier ESZIP
byte-for-byte (SHA-256
`3f28f9b7ac99d6d55d87cd1b47be19d4b6a2bebffcd0eb3531a340ade752fbf6`); **zero new
verifier bundle attempts** are requested. Only the test main/operator and
lifecycle evidence interpretation can change. Keep denial 26, controls 1–2, a
cohort 3–11 and b cohort 12–20, including original spacing, memory sampling,
stream generation, byte identities and all original stop gates. No new memory
calls or observer timers. A failed growth gate remains a failed workload.

## Unchanged limits

| Boundary                                     | Limit                                                                                                                                                      |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Runtime                                      | Cached Linux arm64 Edge Runtime v1.77.0 image `sha256:5f555406dc0705d775323c58e27e856cca7b5b8d0ab726cc6a30b11fcfc7c6b3`, `per_worker`; no image pull/build |
| Worker lifetime / campaign external deadline | 1,800,000 ms / 900 seconds absolute from before creation; neither renewed                                                                                  |
| CPU                                          | One container CPU; worker soft 5,000 / hard 10,000 ms; retirement stops                                                                                    |
| Memory                                       | Worker 256 MiB, container 512 MiB, no extra swap; 96 MiB partial proxy / original 8 MiB growth gate                                                        |
| Workload                                     | One worker, one active read, at most 21 requests, both cohort spans at least 320 seconds                                                                   |
| Payload                                      | Two 64 KiB and eighteen 32 MiB reads; at most 604,110,848 synthetic bytes                                                                                  |
| Request / response                           | Original 30-second request deadline / 8 KiB acknowledgement                                                                                                |
| Logs                                         | 512 KiB total, 32 KiB per line; user-worker diagnostic maximum 128 × 1 KiB; separate host journal maximum 16 × 1 KiB within that same 512 KiB total        |
| Storage                                      | 24 MiB maximum new retained evidence, 16 MiB tmpfs reservation, 512 MiB aggregate CPM including temporary reservation; 20 GiB free-disk floor              |
| Isolation                                    | Network none, no exposed port, read-only root/source mounts, dummy-only allowlisted environment, no credentials/dependency download                        |
| Cleanup                                      | Existing immutable-ID owner; campaign 120 seconds / control 30 seconds shared budget, no renewed per-operation deadline                                    |

Product per-asset/package/storage contracts are unchanged. Current planning
headroom is about 50 GiB free and 467 MiB retained CPM evidence; reserving the
full 24 MiB new evidence plus 16 MiB temporary space remains below 512 MiB.
Recompute before every construction/launch operation; do not delete old evidence
or dependencies to fit. A cap or deadline breach stops further work and leaves
explicit cleanup obligations, never silent success.

## Ownership, verification and decision criteria

History primary is the sole writer/operator. Independent reviewer and IC-1
(`Harden main analysis engine`, thread `01a112ae-2c97-77a1-bd53-5a4434510d4c`)
remain read-only. Allowed source changes are only copied local main harness,
operator lifecycle collection/classification, scalar guardian journal markers,
denied-request lifecycle controls and their focused regression tests. The
guardian's termination behavior, verifier bundle, user worker
instrumentation/shim, core, policy, signing/auth, telemetry, shared helpers,
dependencies and lockfiles remain unchanged. No schema, deployable function,
iOS, redesign or broader engine changes.

Before either control, review exact source/command/diff and ESZIP manifests and
run cached offline type/lint plus pure synthetic tests of terminal veto, single
terminal record, false dispatch-closure prevention, marker order, late errors,
bounded records, EOF, deadline clipping, guardian ownership and attachment
cleanup. Replay the previous failed log and require it still fail; test missing
and duplicated markers, early/unknown signals, exit 1/137, missing EOF,
incomplete logs and failed/unknown cleanup as failures. No blanket stderr
allowlist and no suppression of either recorded error. Pure tests may iterate
inside the window; no hidden runtime probes count as unit tests.

Freeze candidate sources during controls and campaign. Changes affecting a
completed control invalidate its applicability; no rerun allowance is implied.
Final campaign concurrence binds exact source delta, reused ESZIP hash, runtime,
operator/guardian, parameters, both control outcomes and the updated parser.
Record reviews before launch; material corrections require re-review. Green
proposal review is not permission to execute.

Keep three outcomes separate: workload gates, orderly observed runtime
termination, and external cleanup. For the proposed sequence, normal bounded
operator termination requires a valid terminal/dispatch-closed sequence,
observed operator stop followed by the exact expected SIGTERM line and exit 15,
complete EOF without partial/capped lines, no other runtime errors and confirmed
owned-container/attachment cleanup. This is **expected operator termination**,
not graceful in-runtime pool shutdown. Do not adopt a new exit code or signal
classification from a failed run. If actual behavior differs, preserve it and
return for review. Existing zero-exit observations may be recorded, but cannot
replace the proposed control's ordered signal evidence.

The previous failed lifecycle remains failed. A new passing campaign can qualify
only this local workload with the explicitly reviewed operator-managed
lifecycle; it cannot establish a graceful internal worker-pool shutdown, hosted
affinity, concurrency, total RSS/CPU, product recovery, media retention/audio
quality, shared-asset release, native journeys or integrated acceptance. Those
gates and the approved deletion/export then redesign sequence remain unchanged.

Deliver a causal evidence map (observed versus inferred), control comparison,
exact candidate/provenance, unaltered gate outcomes, lifecycle/cleanup results,
retained failures and independent/IC-1 result review. If comparison or packaging
feasibility fails, return the bounded finding without spending the full
campaign. No push, merge, provisioning, uploads, secrets, deployment, hosted
test, device operation, activation or AWS action is included. Human approval of
this packet is required before construction or execution.
