# CPM memory-growth evidence and next diagnostic proposal

October 15, 2026. **Read-only analysis and proposal; no new runtime run or
implementation authorized by this document.** Activation remains disabled, AWS
and 160 MiB remain unapproved, all existing limits unchanged, auto-prompts
paused. History primary owns writes and execution; independent and IC-1
reviewers remain read-only. Prior approvals and unused execution time do not
authorize another run.

## Recommendation

Approve a fresh two-hour **local diagnostic construction and review window**,
with one denial control and one conditional, shortened diagnostic campaign only
after exact-candidate independent and IC-1 concurrence. Expose a bounded
selection of **already occurring memory samples** to locate the rise within
reading, cleanup or handler work. Add no memory calls, timer, idle probe, forced
GC or new provider/storage operation. Do not repeat the full sustained workload
yet.

This is an explicitly changed diagnostic observer and a shortened workload, not
qualification of the unchanged executable. It can narrow where reported memory
changes, but cannot establish a leak, idle reclamation or safe sustained reuse.
If that narrower question is not answered, stop and return evidence; do not
escalate to another measurement method or retry within the window.

## Retained observations

The offline arithmetic is reproducible with
`.artifacts/client-prepared-media/memory-growth-review/analyze.py`. It reads
only the two retained `outcome.json` files; `inputs.json` records their hashes
and `comparison.json` preserves per-request components and four-point windows.
It executes no verifier or runtime. Raw evidence remains unchanged.

| Observation                             | Historical boundary campaign                 | Latest pool-retirement campaign                   |
| --------------------------------------- | -------------------------------------------- | ------------------------------------------------- |
| Workload                                | 20 reads, 604,110,848 bytes; passed workload | 4 reads, 67,239,936 bytes; stopped at growth gate |
| Same-worker post-request growth windows | 17 windows; none triggered                   | First window triggered                            |
| Reported maximum proxy                  | 40,678,197 bytes                             | 36,713,785 bytes                                  |
| Prior-last to next-first decreases      | 6 of 19 pairs                                | 1 of 3 pairs                                      |
| Lifecycle                               | Failed shutdown                              | Scoped teardown passed; expected external exit 15 |
| End-to-end qualification                | Failed                                       | Failed                                            |

Both used retained ESZIP SHA-256
`3f28f9b7ac99d6d55d87cd1b47be19d4b6a2bebffcd0eb3531a340ade752fbf6` and runtime
image `sha256:5f555406dc0705d775323c58e27e856cca7b5b8d0ab726cc6a30b11fcfc7c6b3`
(v1.77.0). Main harness/clock/shutdown code differed; these are not randomized
or otherwise controlled repetitions of an identical complete candidate. A prior
workload pass cannot be combined with later teardown success into a pass.

The latest four quiescent proxies were 17,644,757, 17,845,063, 19,903,285 and
31,961,909 bytes. All rose; the difference was 14,317,152 bytes (13.653900 MiB),
so the unchanged 8 MiB rule correctly stopped the run. The 96 MiB ceiling was
not reached. Between cases 3 and 4, the last-to-next-first proxy fell from
19,903,285 to 16,036,629 bytes. During case 4, first-to-last `external` rose
from 3,031,829 to 18,957,109 bytes while `heapTotal` stayed 13,004,800. This
locates most of that request's observed rise in the reported external component,
but does not identify its allocator or reachability.

In the historical campaign, case 3 last proxy was 32,224,053 and case 4 first
was the same 16,036,629 bytes, about 39.885 seconds later. The observed
variation is compatible with delayed reclamation or runtime accounting effects,
among other causes. It proves neither mechanism, nor the absence of a smaller
retained allocation. The growth rule is a stop rule over four selected points,
not a validated leak classifier. Both failure and earlier passing observations
stand.

## What the existing measurements mean

The frozen source owner is
`.artifacts/client-prepared-media/allocation-diagnostics/boundary/stage/functions/cpm-verifier-characterization/`:

- `shim.ts:syntheticFetch` allocates a fresh 64 KiB `Uint8Array` per pull with
  high-water mark zero. A 32 MiB read has 512 chunks. This allocation is part of
  the local synthetic workload; it is not a measured R2 transport allocation.
- `candidate/verifier.ts:verify` synchronously feeds each chunk into
  `node:crypto` hashing. Its finally block closes/cancels the reader, releases
  the lock and destroys/clears the hash before the `quiescent` sample. This
  establishes owned cleanup, not garbage collection or native-buffer release.
- `candidate/handler.ts` takes a final capture after verification and growth
  evaluation. `diagnostics.ts:observer` copies scalars from existing calls;
  `index.ts` emits first/last points after `worker.handle` returns, before the
  outer response returns. Neither point is an idle or post-response observation.
- `candidate/telemetry.ts` defines the proxy as `heapTotal + external`. This is
  partial V8 telemetry, not RSS. It retains scalar maxima, not chunk payloads.
  Source tracing found no intentional JavaScript collection of all chunks; this
  is not a proof about native hash, stream, fetch or runtime internals.

Remaining hypotheses include delayed reclamation of transient synthetic chunks,
retention in native/hash/stream internals, and heap/accounting variability.
Current evidence cannot distinguish them. A pool inventory read is also not a
replacement V8 sample. Forced GC, weak-reference finalizers and idle timers are
outside this proposal.

## Proposed diagnostic method

Keep verifier, handler, policy, fixture bytes/digests, synthetic fetch and
original memory port call sites byte-identical. Only the offline entry/observer,
bounded report parser and prefix main driver may change. Reuse the reviewed pool
retirement and qualified clock/watchdog sources unchanged after exact review.

Preallocate a fixed typed-array backing store of at most 4 KiB per worker and
reset it in place per request; a scalar-payload estimate for ordinary objects or
growable arrays is insufficient. Bind byteLength and slot layout in the exact
candidate. Wrapper objects and output serialization are additional overhead, not
covered by that backing-store allowance, and remain subject to all existing
resource gates. Never retain a chunk, response, hash, memory-result object or
unbounded list. Return the identical object from each original memory call; no
diagnostic value changes `Samples`, growth input, acknowledgment or cleanup.
Observer allocation/CPU is real overhead and remains included in existing gates.
No claim of identical allocation behavior to the old bundle is allowed.

For a complete 32 MiB synthetic verification, the expected original-call order
is: handler entry/auth/body at 1–3; verifier initial at 4; chunk samples at
5–516; verifier cleanup sample at 517; final handler sample at 518. A complete
64 KiB control has one chunk at 5, cleanup at 6 and final handler at 7.
Aggregate the chunk calls into 16 fixed bins (32 chunks per large-read bin);
control uses one bin. Retain first/last scalar components, maximum actual proxy
and count per bin, plus the six non-chunk points. Do not create synthetic sums
of independent component maxima.

The source still has its original periodic capture. Counts alone do not justify
labels on arbitrary paths: phase interpretation is permitted only for an
acknowledgment with outcome `verified`, the exact frozen successful path,
expected chunk/byte/digest totals, closure, no deadline/abort or diagnostic
fault, and expected original-call counts. A timer callback adds an observation;
unexpected counts invalidate phase interpretation and end the diagnostic
campaign after normal cleanup. Never suppress a timer to fit the mapping.

**All stopped requests remain unclassified**, including a terminal
`growth_stop`. The main validator can produce that reason before validating the
acknowledgment's outcome/byte/digest fields, and the handler's stop aborts its
controller. No internal verifier reason or cancellation provenance is exposed.
Do not infer that growth was the sole cause. Fixed samples/bins on stopped or
denied paths may be retained only as raw numeric ordinals/counts, explicitly
unclassified, without read/cleanup/handler labels. Never reinterpret them as
completed verification. The same fixed record and storage bounds apply. This
means finer phase localization may be available only for preceding verified
reads, not the terminal failing read; a new provenance mechanism is outside this
scope.

Emit only after handling, outside the measured calls, using the existing maximum
128 diagnostic records (one reserved for a fault), 1024 bytes per record and 512
KiB aggregate logs. The prefix has 15 legacy first/last/activity records, 24
non-chunk point records and 34 populated-bin records: 73 normal records plus one
fault slot. The denial control adds three normal records and one fault slot,
totaling at most 78 across both processes. Empty control bins are absent by
fixed schema, not emitted. Every record must fit 1024 encoded bytes; the exact
candidate must bind the field/number/string bounds, include the log prefix in
its byte accounting, and validate this worst-case calculation before execution.
Preserve existing first/last/activity records. With only four reads the fixed
bins fit this envelope; the full 20-read campaign would not. Reporting faults
veto diagnostic acceptance while preserving the original response. No additional
request or delayed sample is introduced to discover whether memory falls later.

## Proposed execution boundary, pending approval

1. Within a fresh two-hour local window, construct one frozen candidate and
   validate observer/parser bounds with local pure-data tests and type checks.
   Prove original code hashes, original-call forwarding/identity, bounded
   storage, count mismatch handling and unchanged gate inputs. No experiment
   before independent and IC-1 exact executable concurrence.
2. One denial-only control, no media reads, with the reviewed retirement path;
   15 seconds plus 30 seconds cleanup maximum. Require expected denial, no
   diagnostic/runtime fault, complete shutdown receipts and confirmed removal.
3. After that control passes and separate exact independent/IC-1 concurrence,
   one prefix campaign: cases **26, 1, 2, 3, 4**, in the same order and timing
   as the earlier full campaign. One reused worker; two 64 KiB controls and two
   32 MiB reads, at most 67,239,936 bytes. Cases 5–20 are deliberately absent.
   No retries, substitute fixture, additional control or second campaign.
4. Stop immediately on the original gate, diagnostic invalidity, runtime error,
   resource bound, cleanup failure or window expiry. The original 900-second
   external campaign deadline and 120-second cleanup cap are ceilings, not a
   reason to keep a completed prefix alive. Require at least 17 minutes remain
   before launch. Retire on normal prefix completion or any terminal stop.

Keep 30-minute internal lifetime, 96 MiB proxy, 8 MiB four-point growth, 256 MiB
worker/512 MiB container, one CPU, 5000/10000 ms CPU bounds, 30-second request/8
KiB response, original 100 ms sampling, one active media read, zero runtime
grace, one-second Docker grace, two-second terminal host drain, 1500 ms
retirement phase and 16 aggregate journal records. No concurrency expansion.
Control and campaign use separate sequential containers; all networking is
disabled, no published ports, dummy configuration only. No secrets, R2,
Supabase, provider, device, image/package downloads or external operations.

A useful result localizes observed increases/decreases to chunk bins, cleanup or
final handler capture with valid provenance, regardless of whether the original
growth gate stops. A gate stop still fails workload qualification. No
reproduction is inconclusive about the earlier failure, not a fix. No result
closes sustained reuse, hosted, product, native or integrated acceptance.
Initial media-required scope, video reanalysis, historical/admitted-operation
recovery and later deletion/export/redesign sequencing remain unchanged.

## Evidence and packaging feasibility

Read-only inventory before this proposal found 511,435,469 retained CPM bytes;
including the unchanged 16 MiB temporary reservation leaves **8,658,227 bytes**
below the 512 MiB aggregate cap. Preserving six current status documents as
lossless gzip adds 1,199,310 bytes. Current headroom must be recomputed before
construction and every runtime launch; the 20 GiB disk floor also remains.

Do not copy a new 8,435,444-byte uncompressed bundle into retained evidence. The
existing bundle compresses offline to 1,818,414 bytes; this is an estimate for
storage planning, not proof of a new bundle's size or successful packaging. The
1,199,310-byte preserved snapshots are a separate, already-counted reservation;
they are not part of the proposed future construction budget. After the current
proposal/verification files, retained bytes plus the temporary reservation leave
approximately 7.4 MB; this is inventory-time evidence, not a permanent
allowance. Propose **at most 4 MiB of additional persistent evidence** measured
from the finalized proposal checkpoint, inside the existing 24 MiB per-scope and
512 MiB aggregate caps, including new source, compressed executable, manifests
and logs. No existing evidence/cache may be removed, recompressed in place or
discarded to fit.

Construction must demonstrate a bounded packaging plan: produce the new bundle
only within the existing 16 MiB temporary reservation, retain its lossless
compressed form and hash of the uncompressed executable, and load that exact
executable within the same temporary cap for the subsequent container. Account
for all concurrent temporary/cache/output bytes and the entire compressed
artifact before committing to the run. Never count an uncompressed staging copy
as free storage outside the evidence tree. No new dependency or duplicated
managed build is allowed. Whether this packaging fits is **unproven**; if it
cannot be established within the caps, stop construction and return the blocker
without any control/campaign. No storage-limit increase is proposed.

## Review and adoption

This is a proposal review, not executable concurrence. Exact independent and
IC-1 review must bind this document, the comparison inputs/results, source
references and synchronized status summaries. User approval is required before
construction/execution under the proposed scope. Review of a later exact
candidate and control result remains mandatory even after approval. No adoption
of a different threshold, measurement definition or retained-growth criterion is
implied.

The prior reviewed result remains bound to set
`ac820dc99dce54b5d75419c635aa73f97857eb4c015151e7ded876cf664135ee`.
`memory-growth-review/prior-status-snapshots.json` maps its six mutable status
paths to lossless gzip snapshots; validation hashes their decompressed bytes.
This preserves that exact historical result while current summaries advance.
