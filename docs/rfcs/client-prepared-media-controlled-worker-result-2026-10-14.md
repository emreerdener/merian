# CPM controlled-worker local result: growth stop

October 14, 2026. The single approved local campaign stopped at its unchanged 8
MiB growth gate. It did not qualify sustained warm reuse. The container was
removed with positive absence confirmation; no rerun followed. Activation
remains disabled, AWS and the 160 MiB threshold unapproved, and all product
package/storage limits unchanged.

## Exact scope and review

The user approved a fresh two-hour window, 18:29:30–20:29:30 UTC, with an
internal worker lifetime of 1,800,000 ms and external deadline of 900 seconds.
All other limits remained unchanged. Independent reviewer
`diagnostics_review_fallback` and IC-1 both concurred before execution with set
`fed50e9aade4db3e0cfb716357c1412b143b9d0505bd046d4419bb0e65fdea18`. IC-1
concurrence turn: `01a13bbb-c1ce-7f62-a010-0daf5c73e580`.

The non-deployable synthetic ESZIP hash is
`d9eead1bf797b3a171dd23e10a151cba075e0fd3276d29382aa8c2814d008bac`. Original
candidate/shared code and dependency locks from
`9c88cc72d35d925a3e4a7d7890f2ec8728d0e414` were unchanged. Only the test entry
shim substituted final outbound fetch with incrementally generated fixture
bytes. Cached Linux arm64 Edge Runtime v1.77.0 image:
`sha256:5f555406dc0705d775323c58e27e856cca7b5b8d0ab726cc6a30b11fcfc7c6b3`. No
network, credentials, hosted service, AI provider or product path was used.

Launch was 18:48:16.356405 UTC. Harness terminal result arrived after 42.283
seconds; operator execution plus cleanup took 43.054 seconds. One worker was
created and retained; no replacement or retry occurred. The local
single-campaign allowance is consumed.

## Observed result

Five requests were dispatched: one genuine authentication rejection (403), two
64 KiB controls and two 32 MiB fixture-a reads. Four reads acknowledged positive
body closure and cleanup with identical worker aliases. Three acknowledgements
were `verified`; the fourth was `stopped` by growth despite an exact byte count
and digest. It must not be counted as a fourth accepted verification. Total
synthetic bytes read: 67,239,936. Cases 5–20, including the entire fixture-b
sequence, were not attempted.

The unchanged handler growth gate and the outer harness's independent four-point
calculation agreed. The recorded post-cleanup samples were:

| Case | Fixture | Quiescent proxy bytes | Approximate MiB |
| ---- | ------- | --------------------: | --------------: |
| 1    | control |            17,906,901 |           17.08 |
| 2    | control |            18,106,549 |           17.27 |
| 3    | a       |            26,325,813 |           25.11 |
| 4    | a       |            30,782,261 |           29.36 |

All three increments were positive; total increase was **12,875,360 bytes
(12.2789 MiB)**, above the unchanged 8 MiB stop. Controls are included by the
approved rule; this crosses the transition from small controls to large reads.
The maximum sampled partial V8 proxy was **39,072,825 bytes (37.26275 MiB)**,
below the unchanged 96 MiB absolute stop. The second large request was sent
40.004 seconds after the first, preserving the requested spacing.

This is an observed safety-stop condition, **not proof of a memory leak**.
Quiescent means sampled after owned body work settled, timers/listeners were
removed and the hash was destroyed; it does not mean GC-complete or idle-memory
settled. These values combine V8 heap capacity and external memory. Synthetic
fixture allocations, allocator/GC behavior and any retained references are not
separately attributed. The evidence neither proves a leak nor clears one.
Separate component maxima are not added to reconstruct a co-timed sample. RSS,
native memory and attributed CPU remain unavailable.

## Cleanup and preparation evidence

The detached watchdog was ready before startup. On the terminal stop, the
operator signalled completion and the watchdog stopped/removed only the
immutable ID returned by successful creation. Both cleanup commands succeeded
and a subsequent local container listing positively confirmed absence. The
external deadline did not need to fire. No fixture file or hosted object was
created. No credential was read, installed, changed or revoked.

Independent review identified a separate post-terminal harness error in the
retained runtime log: `TypeError: Deno.exit is not a function`, followed by
worker-pool shutdown send errors. The main service calls unsupported
`Deno.exit(0)` after emitting its terminal result and awaiting server shutdown.
This does not change the preceding read/hash/closure acknowledgements or
independent container-removal evidence, but **in-runtime graceful shutdown did
not pass**. `operator_failure: null` only describes the outer driver; it does
not mean there were no runtime errors. The current driver stops collecting on
the terminal record and does not classify subsequent stderr; the errors were
retained because they arrived in the captured chunk. Future harness work must
use a runtime-supported termination lifecycle and bounded post-terminal error
collection/disposition. Neither correction nor a rerun is performed here.

Before execution, five offline Deno harness tests and four Python control tests
passed, including signing through the strict stream shim, telemetry consistency,
growth, immutable cleanup ownership, log bounds and detached deadline cleanup.
An inert network-isolated cached-image Docker control demonstrated actual
watchdog removal without executing the verifier. Offline recursive type-check,
Deno lint and Markdown formatting also passed. Earlier preparation failures
remain in the evidence directory; no unchanged product suites were rerun.

After execution, candidate hashes still matched. New retained evidence was
approximately 8.22 MiB; aggregate CPM evidence approximately 458.94 MiB, plus a
reserved 16 MiB temporary allowance below the 512 MiB cap. Free disk was
approximately 50.99 GiB, above the 20 GiB floor. Runtime log: 4,140 bytes. No
outstanding cleanup obligation was reported by the operator.

Evidence root: `.artifacts/client-prepared-media/controlled-worker-reuse/`.
`candidate-manifest.json`, `execution-concurrence.json`, `package-evidence.json`
and `campaign/{launch,created,cleanup,outcome}.json` bind the candidate,
authorization, execution and cleanup. `campaign/runtime.log` preserves ordered
attempts, dispatches and acknowledgements. The result manifest and post-run
review receipts are recorded beside them.

## Acceptance and recommended next decision

This provides short local same-worker reuse evidence and a functioning growth
stop. Neither nine-read, 320-second cohort completed. It closes no sustained
reuse, hosted affinity, physical concurrency, total-memory, CPU or product
acceptance gate. Prior hosted transport/cleanup results remain separately valid.
Original-media retention, audio behavior/quality, recovery, shared-asset
release, native journeys and integrated IC-1 acceptance remain open. Version
deletion and source export, then the approved redesign, retain their existing
dependency order; capture-tools visual ownership remains separate.

Recommend a separately approved **local diagnostic proposal**, starting with
source-level allocation/retention and harness-shutdown review, specifying the
smallest additional telemetry needed to distinguish post-read transient
allocations from retained objects. Any diagnostic execution requires a new exact
reviewed scope; this result does not authorize another campaign. Preserve these
failed samples and the current gates. Excluding controls, warming before
measurement, forcing GC, changing the memory metric or increasing thresholds
would change the experiment and must be explicitly proposed and approved, never
used to relabel this run. No hosted action, deployment, push, activation or AWS
work follows this result.

Post-run independent re-review and IC-1 concur with this corrected report,
including the teardown defect. IC-1 result-review turn:
`01a13bc1-5062-70e1-9e21-f9b27c0168d8`. Evidence set:
`d20c45d8dd9e305110a8ce53ab979cf25630ae7a2d0c42c0ecc14a2753dcf66f`. The original
reporting blocker and its correction are retained in `result-review.json`. This
accepts the evidence and interpretation, not qualification or another campaign.
