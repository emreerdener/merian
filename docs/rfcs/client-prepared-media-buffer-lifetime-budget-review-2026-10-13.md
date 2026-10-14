# CPM-1 buffer lifetime investigation and memory-budget recommendation

Status: October 13, 2026. Completed bounded local investigation; budget proposal
only. Baseline: `3443f9dbe13a624c25da13a07d6e5d2db47b22ed`. The history primary
verified the human's approval in advisory chat
`01a137d1-0cca-77f0-b570-614c40abdecb`, turn
`01a138ab-d43c-76f2-9d7d-f56b12145fe1`, and budget-reassessment instruction in
turn `01a138af-22d9-7643-a1c8-a8ca226788ce`. This follow-up supersedes only the
prior stop's requirement for separately agreed investigation. That investigation
is now finished; it does not authorize another experiment or runtime adapters.

Activation remains disabled, AWS unapproved, and the auto-prompt paused. All
per-asset, package, local/server storage and retention limits remain unchanged.
Push, merge, provisioning, deployment, hosted/device tests and provider calls
remain separately restricted. History primary is sole writer; reviewers are
read-only. PR116 integration and feature acceptance remain open.

## Recommendation

**Do not adopt a higher numeric worker-memory limit from these results. Retain
96 MiB as the recorded experimental comparison target, while treating the final
worker acceptance budget as unresolved.** This is a recommendation, not an
adopted change to the current target. Streaming remains a plausible direction;
neither the previous failure nor these local passes decide hosted suitability.
Do not choose 128 MiB merely to clear the earlier 122.81 MiB measurement.

The 96 MiB worker target first appeared in the limits proposal at `3e1405447` as
an engineering allowance. The subsequent
[IVI feasibility review](client-prepared-media-ivi-feasibility-review-2026-10-13.md)
explicitly calls it provisional headroom, without a derivation of 96
specifically. The **separate 96 MiB stored-package ceiling** has a media-cohort
rationale and is unchanged. Streamed verification memory need not equal package
size.

## Exact experiment and results

Evidence: `.artifacts/client-prepared-media/buffer-lifetime-probe/`.
`launch-v2.json` SHA-256:
`2cf4d7128fb4634c5182628074a15c1708e2c69b1483d720e207197ae6b00acc`. It binds
`probe.ts`, `run.py` and the preflight record. Independent and IC-1 source
review cleared the corrected launch before execution. A v1 timeout blocker was
fixed before any probe ran: the driver now owns a process group, uses bounded
TERM/KILL and closure observations, limits socket writes, and bounds server
shutdown/join. Unknown closure records failure. This source review and a normal
successful shutdown do not prove the timeout branch through fault injection; no
extra cases were run.

Runtime: local arm64 macOS, Deno 2.9.4 / V8 15.0.245.2-rusty. Each mode ran in a
fresh Deno process and made three sequential 32 MiB reads within that process.
Each input uses varying deterministic content (adjacent 64 KiB chunks differ),
with an independent Python hash. The consumer synchronously hashes each chunk
before a 2 ms timer and before requesting more bytes. No forced GC, full-body
concatenation, dependency change, production adapter or app build was used.

| Mode                                                         |       Process high-water RSS | End-of-round sampled RSS, MiB | Largest per-round CPU / wall | Result                                                  |
| ------------------------------------------------------------ | ---------------------------: | ----------------------------- | ---------------------------- | ------------------------------------------------------- |
| Controlled stream, reused 64 KiB slab, queue high-water zero | 63,586,304 B / **60.64 MiB** | 58.92 → 59.75 → 59.77         | 111.653 ms / 1,845.702 ms    | All three lengths/hashes correct; below original target |
| Native file reads into reused 64 KiB slab                    | 57,360,384 B / **54.70 MiB** | 52.88 → 53.70 → 53.77         | 127.167 ms / 1,966.696 ms    | All three lengths/hashes correct; below original target |
| Real loopback HTTP response through `fetch`                  | 94,109,696 B / **89.75 MiB** | 83.86 → 83.42 → 88.28         | 156.145 ms / 2,024.172 ms    | All three lengths/hashes correct; below original target |

All three planned modes and nine reads completed once. The fixture server closed
normally. Darwin `time -l` reports whole-client-process high-water RSS,
including startup and native client allocations; the separate Python fixture
server is excluded. Deno samples provide additional RSS, heap and external
allocation observations, not an independent complete allocation census.
Per-round CPU/wall includes local event-loop work and intentional pacing, but
excludes startup and `finally` cleanup. It is not a complete handler or complete
attempt-lifecycle timing. The maximum observed fetch chunk was 64 KiB; that does
not promise the same chunking for R2, TLS or another runtime.

The earlier fresh-allocation prototype's **122.81 MiB failure remains a failure
against 96 MiB**. Its raw evidence and all 60 evidence hashes remain unchanged.
This comparison changes chunk size, pacing, source and allocation strategy;
there is no one-variable experiment establishing why the earlier process grew.
The new results must not be presented as a repaired runtime implementation or a
reclassification of the earlier result.

## What memory behavior is observable

- Initial local RSS was 50.59 MiB for the controlled stream, 47.44 MiB for file
  reads and 48.05 MiB for fetch. These are this harness's loaded-process
  samples, not the baseline of a hosted worker or the full backend handler. They
  are included in the reported peaks, never subtracted to manufacture a pass.
- Controlled sources retain a single explicit 64 KiB byte slab and consume it
  before reuse. Their end-of-round external allocations stayed at approximately
  2.12 MiB and 1.88 MiB respectively. The final RSS increments became small over
  three reads, but three reads do not prove a long-run plateau.
- Fetch owns its buffers. End-of-round external allocations were 22.75, 14.13
  and 25.63 MiB, with a sampled maximum of 26.25 MiB. End heap-used values were
  6.82, 6.24 and 7.04 MiB. RSS dipped and then rose; **stable warm reuse has not
  been established**, nor has monotonic unbounded growth. Samples cannot
  separate live references, garbage awaiting collection, allocator reservations
  and every native buffer. No leak or specific GC explanation is established.
- The local fetch peak leaves **6.25 MiB** below the experimental 96 MiB target.
  Auth, routing, manifest parsing, ledger/receipt work, TLS, backend libraries
  and overlapping readers are absent. No evidence shows those omissions fit this
  gap. Copying received chunks into a reusable slab would not by itself
  eliminate fetch-owned allocation.
- Each mode has one physical reader at a time. There is no concurrent or
  expired-reader-overlap evidence. The approved three verification attempts are
  sequential authority, not permission for three parallel readers. Lease expiry
  still does not prove termination. Unknown AI execution still permits only
  original-operation recovery, never another invocation or inferred refund.

## Evidence-based budget method and missing measurement

Supabase currently documents a hosted maximum of **256 MB** and two seconds CPU
per request, and describes worker reuse across requests. This is a platform
ceiling, not an application budget or a translation of Darwin RSS into hosted
worker memory. The documentation labels units MB; confirm exact configured bytes
and metric accounting on the intended target instead of assuming 256 MiB.
[Official runtime limits](https://supabase.com/docs/guides/functions/limits).
Shutdown memory is described as a snapshot, so it cannot alone prove a lifetime
peak. Qualification must identify a usable peak metric or acknowledge the
measurement gap.
[Official shutdown metrics](https://supabase.com/docs/guides/troubleshooting/edge-function-shutdown-reasons-explained).

Recommend this **proposed method**, rather than an invented replacement number:

1. Establish the actual target's memory envelope `L` in bytes and the meaning of
   its worker/isolate memory metric. Measure loaded handler baseline, then total
   peak `P` through warm reuse with the agreed maximum number of physically
   overlapping readers. The full measurement must include fetch/TLS, hash,
   auth/manifest/ledger/receipt and cleanup. Do not add an isolated peak for
   each reader because their shared baseline would be double-counted.
2. Account explicitly for observed run-to-run variation and any known excluded
   work as allowance `A`. Unknown handler/overlap allocation is a missing
   measurement, not a guessed 16 or 32 MiB allowance. Breakdown samples can
   explain the peak but cannot replace the total.
3. Propose at least **25% of `L` left unallocated** as an initial safety-margin
   policy for review; it is not an empirically proven universal margin. A
   candidate budget `B = P + A` must fit within `0.75 × L` and have evidence
   that warm reuse does not keep accumulating within the worker's allowed
   lifetime. The 75% boundary is a planning ceiling, not the new application
   limit or a pass criterion adopted by this report. Increase the reserve if
   measured variation or platform accounting requires it; do not silently shrink
   it to accommodate a failing candidate.

We cannot fill in `P` or `A` for the complete hosted worker from these local
measurements. Therefore **no evidence-based numeric replacement is available
now**. Keeping 96 as an experiment label while leaving final acceptance open is
more accurate than declaring it mandatory for reliable history or raising it to
an attractive round number. No new schema field or resource ledger is proposed.

The smallest missing measurement is one separately agreed resource packet for
the intended runtime and inactive full verifier composition: cold/loaded
baseline, warm sequential reads over a finite agreed worker-lifetime window, and
the permitted physical-reader overlap bound with cleanup. The packet must
specify number/duration of cases and peak/CPU instrumentation before approval;
it must distinguish failure to measure from passing. If reliable hosted peak
instrumentation is unavailable, revise the acceptance measurement with explicit
review. This report does not authorize that packet, build the handler, start
more local tests, or provision a hosted target. The current three-read local
scope is exhausted.

## Evidence, limitations and remaining sequence

The single synthetic file is 32 MiB; retained new artifacts occupy about 32.05
MiB, within the previous 512 MiB local allowance. Free disk remains above 41
GiB, exceeding the 20 GiB floor. The 115 unrelated working-tree paths are
unchanged. The initial Python bytecode-cache permission failure is recorded; AST
parsing then checked syntax without cache writes. Deno type checking and source
reviews preceded the probe. No full backend/native regression suite was rerun
for this artifact-only investigation; no deployed source changed.

All CPM original-retention, audio signal/quality, full-lifecycle recovery,
shared-reference cleanup, ingress enforcement and marker accounting acceptance
remain open. Source integration is still protected by the local unpublished
whole-backend hold, not feature flags alone. Current IC-1/alpha acceptance still
precedes individual-version deletion and source export, then the approved
Identification/History/menu redesign. Separate capture visual ownership does not
transfer. Further work waits for the next explicit bounded decision; the paused
automation stays paused.
