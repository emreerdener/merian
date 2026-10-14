# CPM-1 approved local feasibility: stopped at verifier memory target

Status: October 13, 2026. The human approved the accounting/retry decisions and
bounded local exercise in `Scan ID History (2)`, turn
`01a1389b-98ec-7620-a4a1-855456cecd46`. The primary verified that human message
directly before executing. Baseline: `50d0e6df4c4cc57843600ccd0d3405558b8c9c5e`.
Approval is not runtime implementation, hosted/device qualification,
provisioning, push, merge, deployment or activation authority. AWS remains
unapproved.

## Approved decisions and sequence

The existing application byte limits cover **committed application media and
application-owned copies**. Provider-internal buffers and request costs need
separate abuse controls and observation, not an exact-byte guarantee. The
approved per-asset, 96 MiB package, 192 MiB temporary, 288 MiB incremental and
server capacity limits do not change. Original, AI-input and preview identities,
private retention and surviving-version references remain distinct.

Read-only verification may use at most **three durably counted full-read
attempts** per unchanged immutable object/manifest under the original
nonrenewable 30-minute intent, with a **30-second deadline per attempt**. Retain
96 MiB total-worker memory including concurrency and one-second CPU per attempt
as qualification targets. There is no cross-request aggregate CPU-accounting
requirement. This supersedes the unadopted single aggregate budget in the prior
[feasibility review](client-prepared-media-ivi-feasibility-review-2026-10-13.md).
One current receipt-writing claim, stale-commit fencing and recovery of unknown
receipt commits remain required. Lease expiry is not reader termination; bounded
physical overlap still needs qualification. Unknown AI execution remains
original-operation recovery only, never another invocation or inferred refund.

The sequence is now explicit:

1. Agree identities, privacy, ownership/references, byte budgets, accounting and
   recovery semantics; agree the audio recipe and quality evaluation method.
2. Resolve the decisive ingress, marker, verifier and native-storage feasibility
   questions through bounded probes. Local models do not qualify a hosted
   target. Do not expand the schema around unestablished guarantees.
3. Implement reviewed inactive increments after the narrow contract and decisive
   feasibility questions close. Complete restart/missing-file/deletion and
   shared-reference races, audio signal/identification-quality evaluation, full
   affected gates and required hosted/device evidence against that
   implementation before acceptance. Complete end-to-end proof is not a
   prerequisite to writing the implementation being tested.

The local exercise was limited to two engineering days, 512 MiB additional
synthetic files and the 20 GiB free-space floor. No production adapter,
migration, new capture UI, provider invocation or managed-cache duplication was
authorized. History primary remains sole writer; independent and IC-1 owners
review only.

## Results and exact scope

Evidence directory: `.artifacts/client-prepared-media/local-feasibility/`.
`preflight.json` binds approval, baseline, runtime and the 115 unrelated paths.
Harnesses, raw outputs, failed commands, native extraction hashes and the final
candidate manifest are retained. Local runtime: Deno 2.9.4, V8 15.0.245.2-rusty;
native host harness: Apple Swift 6.4 targeting arm64 macOS 26. No iOS app build
or installation occurred.

| Question                        | Local finding                                                                                                                                                                                                                                                                                                                 | Remaining qualification                                                                                                                                                                     |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Upload bounds/create-only       | **Partial pass.** Cached `aws4fetch` signer inspection shows the existing helper signs length/type but not `If-None-Match`; the candidate request signs all three. Eight fixtures match the explicitly assumed size/create-only model.                                                                                        | R2 enforcement, malformed HTTP framing, expiry behavior and real client requests remain unobservable locally. The old helper's known gap is not a newly qualified CPM ingress.              |
| Retirement and capacity release | **Model pass.** Six modeled orders cover data-first, marker-first, in-flight data, lost marker acknowledgement, lost ledger acknowledgement and outage/recovery. The existing `markInitialMediaErased` primitive runs against injected storage; each modeled retirement converges to a marker and one modeled ledger release. | Atomic-at-commit conditional creation and ledger idempotency are model assumptions, not target or SQL proof. All-writer/credential/lifecycle exclusion still needs named-target inspection. |
| Incremental verifier            | **Failed local memory target; exercise stopped.** All 12 fresh-process length/hash cases passed. Three sequential 32 MiB reads in one warm process produced correct hashes but reached **128,778,240 bytes / 122.81 MiB** process high-water RSS, above 96 MiB.                                                               | Concurrent-read, stalled-read and oversized-chunk cases were not executed after the stop. Actual fetch buffering, full Edge route, target metrics and hosted runtime remain unqualified.    |
| Native files/preparation        | **Partial primitive pass.** Two 32 MiB opaque source files copy and reopen byte-exactly; missing-source cleanup preserves originals. Actual audio-preparation method bodies turn a 2,646,044-byte synthetic stereo WAV into a valid 1,327,096-byte mono WAV without changing the source. Invalid-audio output cleanup passes. | No PhotoKit/camera acquisition, iOS process restart, complete package transaction, image/video processing or audio quality equivalence is proved.                                           |

The verifier probe uses `node:crypto` incremental SHA-256 over freshly allocated
synthetic chunks no larger than 1 MiB. It does not retain or concatenate prior
chunks, force garbage collection, fetch an object, authenticate, read a ledger
or publish a receipt. High-water process RSS includes startup; Deno's sampled
RSS is separately retained. Neither is a hosted isolate measurement. The 12
single cases peaked at 87,195,648 bytes / 83.16 MiB; their largest hash/control
CPU and wall measurements were 23.986 ms and 23.357 ms. Those timings exclude a
real route and cannot qualify its CPU/deadline budget. Warm-process CPU for all
three reads was 59.376 ms; it is not a per-request measurement.

The warm-process result shows that **incremental hashing alone does not
establish bounded total process memory**. Temporary allocation and collection
timing are possible explanations, not a proven leak diagnosis. No limits were
increased and no alternate implementation was tried after the failure. Thirteen
of 16 planned verifier cases ran; the three remaining cases stay unrun.

## Native and storage gaps exposed without implementing CPM

The native executable contains source-hashed, verbatim selected bodies from
`OfflineCaptureFileStore.persistFiles/persistFile`,
`InferenceAudioPreparer.prepareLocalFile` and its local conversion/validation
dependencies, plus `ObservationAudioContainer`. App-only acquisition and remote
download paths are excluded; the harness uses the existing 2,700,000-byte audio
constant. It is a standalone macOS primitive exercise, not compilation or
qualification of the iOS target.

An interrupted metadata handoff followed by another `persistFiles` call produces
another uniquely named copy. The draft source survives, but the primitive has no
stable package identity. This confirms the already planned need for durable
package ownership and retry reuse; it is not authority to implement that owner.
The harness's saved mapping and reopen simulate metadata recovery only, not
process termination or power-loss durability. Opaque 32 MiB files test copy
identity, not valid image eligibility. A strict free-space refusal fixture uses
the approved 288 MiB incremental plus 256 MiB reserve; it is an explicit model,
not the existing application's low-disk implementation. The copy scenario has a
192 MiB logical media high-water count, below the 288 MiB envelope; complete
preparation/transfer peak accounting remains open.

Source inventory confirms existing generic PUT/COPY/DELETE paths and the old
presigned helper. The history signer/target composition is not installed or
qualified. These paths must be excluded from any proposed private CPM namespace;
the local source list is not an inventory of hosted credentials, lifecycle rules
or outstanding upload authority.

A representative opaque marker record serializes to 156 bytes; 1,000 such model
records would occupy 156,000 serialized bytes. This is arithmetic over a model,
not measured Postgres/index/WAL or R2 metadata footprint. At 24 objects per
package, 1,000 fully retired packages could leave 24,000 permanent keys and
3,744,000 bytes in that illustrative representation. No sustainable allocation
rate or metadata cap is established. Keep marker/ledger footprint measurement
and a reviewed allocation budget open, and keep cleanup runnable when admission
capacity is exhausted. Never delete the fence to reclaim its metadata without
proving old write authority cannot recreate media.

## Stop disposition and smallest next alternative

**Stop further experiments at this failed prototype.** The smallest proposed
follow-up is to investigate bounded read-buffer allocation/lifetime and real
stream backpressure in an isolated verifier, including warm reuse, before any
runtime adapter. A reusable byte buffer or smaller bounded reads are candidates
for a separately agreed probe, not demonstrated fixes; actual fetch chunking and
native allocation must be measured. Do not force GC to manufacture a pass, raise
the memory target, add a server or infer AWS authority.

Retained setup failures are not product results: one unsupported Deno check
option, one literal-type annotation error, sandbox denial of the existing Swift
module cache, and sandbox denial of `time -l` process metrics. The type check
was corrected; native compilation reused the existing cache with approved local
access; the identical verifier driver reran with metric access and Deno
network/environment access denied. All earlier logs remain retained. The
measurement failure, not a setup error, stopped the exercise.

Acceptance remains open. Hosted tests require a separately named nonproduction
Supabase/private R2 target and authorized operations, including permanent test
marker disposition; device work remains user-owned. PR116 source integration,
its locally active whole-backend hold, feature activation and later version
deletion/export/redesign remain separate. Ordinary access stays nil. Nothing in
this report authorizes push, merge, deployment, hosted scheduling, device work
or distribution.
