# CPM controlled-worker reuse: local-only approval proposal

> Current October 14 prelaunch finding: the user approved local preparation and
> execution only after exact-candidate review. The pinned runtime's default
> supervisor retires at half the configured lifetime, so the 900-second setting
> conflicts with the 682-second schedule. No campaign launched; allowance
> unused. See the
> [prelaunch finding and unapproved amendment](client-prepared-media-controlled-worker-preflight-2026-10-14.md).
> Existing limits remain unchanged, activation disabled, AWS unapproved. Earlier
> approval/status notes below are historical.

Status: October 14, 2026. **Proposal and read-only independent/IC-1 review
only.** No harness construction, runtime execution or hosted action is
authorized by this document. The user requested a bounded scope for approval
before execution. Activation remains disabled, AWS unapproved, the 160 MiB
threshold unapproved, and product package/storage limits unchanged.

## Recommendation and evidence boundary

Approve one local campaign that deliberately retains one user-worker handle and
one module instance across separate requests. This addresses the gap in attended
run `qdeec80c5e139e0`: all 26 scheduled checks completed with positive closure,
but its 25 read acknowledgements reported 25 different worker aliases. The
hosted result therefore establishes representative private-R2 transport
evidence, not warm reuse or physical read overlap. Its reviewed outcome remains
in `.artifacts/client-prepared-media/hosted-qdeec80c5e139e0/outcome.md`.

Use executable baseline `9c88cc72d35d925a3e4a7d7890f2ec8728d0e414`, its existing
helpers/dependency pins, and the cached official Linux arm64 Edge Runtime
v1.77.0 image:
`sha256:5f555406dc0705d775323c58e27e856cca7b5b8d0ab726cc6a30b11fcfc7c6b3`. The
existing short harness already observed two controls in the same worker, but its
20-second worker lifetime and control-only synthetic fetch do not support this
campaign. Retain that harness, package and prior evidence unchanged.

A new, explicitly **non-deployable test package** is necessary to generate the
two larger synthetic streams. It is not the production-source ESZIP, and its
future hash must be recorded separately. The representative wrapper, test-key
auth, bounded parser, private-GET signing, incremental verifier, response
serialization, runtime telemetry and growth logic stay unchanged. Only the test
entry shim substitutes the final outbound fetch. Product Auth, real
DNS/TLS/socket/R2 buffering, decoding, derivation, funding, receipts and iOS
paths are absent. Synthetic generation allocations are included in this worker's
measurements; they cannot be subtracted to infer production overhead.

## Proposed authorization envelope

One **two-hour local work window**, including harness preparation, focused
static/unit checks, independent/IC-1 exact-manifest review, corrections, one
runtime campaign, cleanup and reporting. Stop at the timebox; no automatic
extension. The runtime campaign has its own **15-minute absolute deadline**,
followed by at most **two minutes of local cleanup**, all inside the two-hour
window. Reserve those final 17 minutes before starting; insufficient remaining
time blocks launch.

History primary is the sole writer/operator. Independent reviewer and IC-1
remain read-only; ownership does not transfer. Approval of this scope would
permit execution only after the new harness, test-only package, source-delta
manifest and launch parameters have independent/IC-1 concurrence. An unresolved
finding, inability to honor these bounds or a material scope change returns to
the user before execution. No executable candidate exists yet for this proposal.

Preparation stays in a new
`.artifacts/client-prepared-media/controlled-worker-reuse/` directory, with
related proposal/status documentation. Do not overwrite prior stages, bundles or
journals. No product, shared helper, deployment configuration, schema, iOS,
dependency pin or lockfile changes. If reuse requires changing the verifier or
core worker lifecycle, stop and propose that separately. No images/dependencies
are downloaded. No Supabase stack, simulator or managed build is started,
duplicated or cancelled.

No hosted credentials are read or requested; the retained R2 tokens remain
untouched in the user's store. No uploads, secret installation, deployment,
provisioning, hosted calls, external health polling, push, merge or device work.
Hosted cost is zero by construction, not a measured billing assertion.
Auto-prompts remain paused.

## Worker construction and isolation

Use a single dedicated container, no network (`--network none`), no published
ports, read-only root and exact read-only mounts for the new main harness and
test-only ESZIP. No host home, repository-wide mount, credential store, Docker
socket or inherited application environment enters the container. Supply only
explicit public dummy test configuration and a fresh local alias with expiry
fixed at campaign launch plus 900,000 ms; never renew it mid-campaign. Clear
ambient credential variables in the launcher. Never fall back to live fetch.

The main harness serves only container-local loopback and forwards requests
through exactly one cached `EdgeRuntime.userWorkers.create` promise. Creation is
attempted once, before the first request. Keep that resolved handle for the
entire campaign; no per-request worker creation, replacement after failure,
restart or forced affinity. Preserve the candidate's single module-level handler
and generated worker alias. Assert the same alias on every read acknowledgement
and record the main harness's single creation count. Unexpected identity, worker
shutdown or replacement fails the reuse claim and stops new requests.

Proposed isolation limits:

| Control                                  | Bound / interpretation                                                                                                                   |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Container                                | 512 MiB memory, one CPU; existing local isolation values, not a product capacity contract                                                |
| User worker                              | 256 MiB memory; existing local isolation value, not adopted product memory allowance                                                     |
| CPU stop configuration                   | Retain 5,000 ms soft / 10,000 ms hard settings from the short harness; do not raise them to obtain completion                            |
| Worker lifetime                          | Change the short harness's 20,000 ms to 900,000 ms solely for this reviewed local campaign                                               |
| External watchdog                        | At most 900 seconds from campaign launch; cannot be reset by a request or worker                                                         |
| Request                                  | 30 seconds including response validation; active handler sampling remains every 100 ms                                                   |
| Temporary filesystem                     | At most 16 MiB tmpfs; no disk spill or extra fixture files                                                                               |
| New retained package/source/log/evidence | At most 24 MiB combined; includes failed construction/check evidence                                                                     |
| Overall experiment storage               | Existing retained CPM evidence plus new retained files plus temporary writes must remain below 512 MiB; check before each material write |
| Host disk                                | At least 20 GiB free throughout preparation and execution                                                                                |

At proposal preparation, free disk was 51.92 GiB and retained CPM evidence
450.71 MiB. Reserving the full new 24 MiB plus 16 MiB temporary allowance fits
below 512 MiB. Both retained ESZIPs are about 8.03 MiB. This supports reserving
space; it does not prove that construction will fit. Never duplicate the
existing 64 MiB fixture corpus, prune dependencies or delete previous evidence
to make room.

The main harness and worker run in the same limited container. Container memory
includes both and is not attributable worker RSS. Do not introduce CPU profiling
or native-memory acceptance in this checkpoint. Exact CPU-budget
enforcement/accounting semantics and sustained worker-handle lifetime remain
prelaunch gates: record evidence from the pinned runtime API/source that
`workerTimeoutMs: 900000` is accepted, and establish whether its soft/hard CPU
budgets apply per request or cumulatively across the worker lifetime. Unknown
semantics, unsupported configuration or semantics incompatible with this scope
block campaign launch and return for review; do not discover these by silently
spending the measurement run. Successful configuration does not prove sustained
reuse. During the campaign retain observed termination reasons and stop on
either limit. Do not reinterpret a shutdown as a memory failure or increase a
guard without a revised proposal.

## Exact workload

Use real elapsed time, not an accelerated clock, and one serial driver. The
retained policy defines all case identities, fixture sizes, seeds and digests.
Keep separate HTTP requests; do not replace them with a loop inside one handler
invocation.

1. Case 26: the existing wrong test key must receive the genuine handler-marked
   403, expected test-auth mode and exact runtime pair. No media reader may
   open.
2. Cases 1–2: two 64 KiB controls, one second apart, must verify and positively
   close on the same worker. Review the automatic local barrier before larger
   reads; no additional probe request.
3. Cases 3–11: nine 32 MiB reads of fixture a at 40-second spacing (320 seconds
   first-to-last).
4. Cases 12–20: nine 32 MiB reads of fixture b, starting 360 seconds after the
   start of the a sequence, also 40 seconds apart. Same worker throughout both
   sequences.

Use the unchanged policy offsets, anchored after successful local readiness.
Nominal final read is around 682 seconds from the control schedule's origin.
Record actual monotonic send/ack times. Require at least the policy's 320-second
span per nine-read sequence; do not dispatch catch-up bursts. If delay leaves
less than one full request deadline before the campaign deadline, stop. This
campaign has **21 requests maximum**, one active request/reader, **18 large
reads plus two controls**, and at most **604,110,848 synthetic payload bytes**.
Cases 21–25 are excluded by the isolated local driver. The unchanged candidate
handler still recognizes those policy cases: this is a driver-enforced campaign
bound, not a new server admission restriction or hostile-ingress guarantee. Only
this driver can reach the container-local harness, and its fixed schedule
permits `{26, 1..20}` once each. Any unplanned attempt stops and invalidates the
campaign; it does not expand the allowance. There is no concurrent group, retry,
replacement request, extra warm-up or second measurement run.

Install the synthetic fetch shim before importing the unchanged entrypoint. It
accepts only the exact signed R2 GET request shape produced by
`privateGetAdapter`: an explicit dummy HTTPS origin with a 32-hex account
hostname ending in `.r2.cloudflarestorage.com`, bucket
`merian-cpm-verifier-fixtures`, and exact
`/cpm-verifier/<dummy-run>/<fixture-key>` path for one of the three approved
keys. Require GET, `redirect: error`, no port, userinfo, query or fragment;
compare the complete origin/path rather than a suffix. Signing uses dummy keys
through the original adapter; do not log signed headers. Reject every other
outbound request without fallback. Generate deterministic 65,536-byte blocks
incrementally using the existing fixture recipe; retain no whole-file array,
aggregate copy or response cache. Exact a/b/control lengths and independently
expected SHA-256 values come from unchanged `policy.ts`. Any unexpected request
fails rather than reaching the network. Local loopback is only a harness
dispatch path, not an R2 simulation claim.

The wrong-key request and both controls stay in this same worker. Controls also
remain in its quiescent-growth history: do not reset growth state, discard the
initial rise when moving to large fixtures, force garbage collection, prewarm
imports or replace the module. If that transition triggers the existing growth
stop, preserve it as the observed outcome instead of adjusting the test to pass.

## Pass, stop and cleanup criteria

Local controlled-reuse success requires all of the following:

- Exactly one worker-creation attempt and the same worker alias for all 20 read
  acknowledgements, with no runtime restart. The observed runtime pair must
  match v1.77.0 / Deno 2.1.4 / V8 11.6.189.12 on every response.
- All 21 unique attempts journaled before sending; genuine wrong-key denial; all
  20 reads exact-length/exact-digest with opened/closed/cleanup evidence, valid
  bounded responses and no unresolved obligation.
- Both nine-read sequences complete over their measured minimum 320-second spans
  within the absolute campaign deadline. Every request/ack completes before its
  30-second deadline.
- Sampled `P = heapTotal + external` remains below **96 MiB**. No four
  successive same-worker quiescent points have three positive increments
  totaling **8 MiB or more**. Keep original application stop behavior and
  independently recompute this condition from ordered acknowledgements.
- Bounded journals/results and explicit reader/hash/timer cleanup, followed by
  confirmed removal of only this campaign's container and temporary files.

Stop on the first failed/malformed/late response, missing metric, changed
worker/runtime identity, memory/growth stop, CPU/lifetime termination, lost
process, journal/storage failure, exceeded time/disk bound or unexpected network
attempt. No rerun or new worker fills a missing sample. Distinguish integrity
failure, reuse unavailable, resource stop and harness failure. Preserve
incomplete evidence and report the unobserved remainder.

The external watchdog stops only the named campaign container. Confirm its
stopped/absent state through the local container control plane; retain a
pending-cleanup obligation if that cannot be established. Killing a container
establishes local process termination, not a fabricated successful application
acknowledgement. Never delete evidence or infer closed readers from deadline
expiry. A failed short static/unit check may be corrected within the preparation
timebox and re-reviewed; a started measurement campaign consumes the single run
allowance even if it stops immediately.

Record source and test-package hashes, exact shim differences, image digest,
launch limits, creation count, bounded worker aliases, ordered case timing,
digest/closure predicates, sampled memory components, quiescent points, stop
reason and cleanup disposition. Cap streamed runtime logs and sanitized results
within the retained allowance; no unbounded `capture_output`, whole response
bodies, secrets or real user media. No idle-memory sampling or forced-GC plateau
claim is introduced; active samples can miss transient/native peaks.

## Acceptance meaning and next boundary

A pass would close only **local controlled same-module repeated-read evidence**
for this representative verifier and synthetic transport. It would not establish
hosted worker affinity, real-R2 warm reuse, physical concurrency, same-worker
contention, total/native memory, attributed CPU, hostile ingress or complete CPM
acceptance. Existing hosted transport evidence and this future local result must
remain separately labelled; combining them does not prove the unmeasured
combination.

Original retention, audio recipe/quality, package and peak-storage limits,
authoritative shared references, release/late-upload cleanup,
interruption/restart/deletion behavior and all IC-1 lifecycle acceptance stay
open. Fresh initial identification and reanalysis still require actual
photo/audio/video media, optional supporting text, immutable descriptions and
exact already-admitted recovery. Version deletion/export then redesign
sequencing and separate capture UI ownership remain unchanged.

After the result and independent/IC-1 review, recommend the next bounded
decision. Do not repeat hosted tests hoping for affinity, move serial work into
one hosted invocation or adopt larger limits without a separately reviewed
proposal and named approval.

## Approval requested

“Approve the two-hour local preparation/review window and, only after
exact-candidate independent/IC-1 concurrence within this scope, one
controlled-worker campaign of at most 15 minutes plus two minutes cleanup. Use
the cached v1.77.0 runtime, synthetic streams, no network or live credentials,
existing 96 MiB/8 MiB stops and unchanged product limits. No hosted actions,
activation or AWS.”

This approval has **not** been granted. Proposal review records and the exact
documentation commit will be recorded under
`.artifacts/client-prepared-media/controlled-worker-reuse-proposal/`;
implementation and measurement evidence would use the separate directory named
above only after approval.
