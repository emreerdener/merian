# CPM allocation source review: no supported correction identified

October 15, 2026. Read-only source review and report only. No implementation,
compilation, tests, runtime invocation or hosted access. Activation disabled;
AWS and 160 MiB unapproved; all limits unchanged; auto-prompts paused.

## Disposition

**No concrete correction for the demonstrated memory growth is supported by this
bounded review. Do not schedule another campaign or substitute a speculative
rewrite for a fix.** This satisfies the stop condition in the
[lifecycle design review](client-prepared-media-lifecycle-design-review-2026-10-15.md).
It does not establish that the code is leak-free or that the runtime is faulty.

The retained four-read failure remains binding: 10.278900 MiB growth exceeds the
unchanged 8 MiB stop, despite a peak below 96 MiB and positive owned-body
closure. Three verified paths localize measured increases to reading/hashing;
the stopped fourth path remains unclassified. See the
[reviewed result](client-prepared-media-memory-bins-result-2026-10-15.md).

## Reviewed ownership paths

| Source and symbol                                                          | Finding                                                                                                                                                                                        | Consequence for a proposed correction                                                                                                                                                                                    |
| -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `services/supabase/tests/cpm_verifier_characterization/verifier.ts:verify` | One hash context; sequential `reader.read()` passes each view directly to `hash.update`. No application-level full-file buffer, chunk array, concatenation or chunk copy appears.              | No removable collection/copy has been identified. Merely assigning the current read result to null does not establish reclamation or explain a multi-MiB accumulated rise.                                               |
| Same function, `finally`                                                   | Cancels sampling/deadline and removes caller listener; cancels incomplete readers, awaits closure, releases the lock, destroys and clears the hash. Unknown closure does not release the slot. | Adding the same cleanup again is not a correction. Closure is not proof of GC or native backing-store release.                                                                                                           |
| `handler.ts:createHandler`                                                 | Module owns bounded schedule IDs, four scalar growth points, busy/halted state and a live-request map. Each invocation removes its live entry in `finally`.                                    | No retained media collection identified. The live map tracks concurrent invocations; it is not a platform-wide concurrency bound. Sequential retained results do not justify changing concurrent admission here.         |
| `telemetry.ts:Samples` / `Growth`                                          | Scalar maxima and a rolling four-number window; no buffer references.                                                                                                                          | Recreating the handler or resetting history would evade the failure rather than fix it.                                                                                                                                  |
| `private_get.ts:privateGetAdapter`                                         | Signs a fixed GET and returns the single transport Response; no body aggregation.                                                                                                              | Signing metadata is distinct from payload storage. No demonstrated media buffering fix in this adapter.                                                                                                                  |
| Retained `memory-bins/.../shim.ts:syntheticFetch`                          | A fresh 64 KiB allocation per pull, zero stream high-water mark; 512 chunks per 32 MiB fixture.                                                                                                | This is real transient allocation in the synthetic workload, not proof of a leak or actual R2 allocation behavior. Reusing one synthetic buffer would change the workload and cannot qualify unchanged product behavior. |
| Retained `diagnostics.ts:observer` and `bins.ts`                           | First/last scalar observations and a fixed 2,384-byte numeric backing; report serialization occurs after handling.                                                                             | Observer overhead can affect allocation timing, but contains no retained media payload list. Removing it alone would not identify a product correction.                                                                  |

The inspected repository verifier is qualification code, not a newly deployed
production route. These conclusions are confined to the traced paths; they are
not an exhaustive proof about all platform allocations or all error paths.

## Runtime hashing cross-check and provenance limits

Read-only public source inspection supplemented the retained local evidence. The
runtime reports Deno 2.1.4, but that version alone is not a sufficient source
identity; the Supabase runtime includes a local Node implementation.

- The
  [Supabase v1.77.0 hash wrapper](https://github.com/supabase/edge-runtime/blob/v1.77.0/ext/node/polyfills/internal/crypto/hash.ts#L121-L154)
  forwards updates through `toBuf` to a native operation, and hex digest uses
  the dedicated digest operation. No chunk list appears in that wrapper.
- The
  [native update operation](https://github.com/supabase/edge-runtime/blob/v1.77.0/ext/node/ops/crypto/mod.rs#L96-L125)
  is synchronous and receives a borrowed byte slice.
- The
  [native digest owner](https://github.com/supabase/edge-runtime/blob/v1.77.0/ext/node/ops/crypto/digest.rs#L9-L38)
  holds an optional hash state; update feeds that state and digest takes it for
  finalization. The SHA-256 path uses the fixed-size digest implementation,
  rather than a visible vector of submitted chunks.
- As a secondary comparison only,
  [upstream Deno 2.1.4 `toBuf`](https://github.com/denoland/deno/blob/v2.1.4/ext/node/polyfills/internal/crypto/util.ts#L177-L187)
  returns non-string input unchanged. The corresponding Supabase utility fetch
  failed, so this is not asserted as verified fork/binary behavior.

The prior runtime-source review resolved v1.77.0 to
`e847536d7b276428415d7cf9877803d99a16fde5`. This turn's successful additional
reads used the public tag URLs; commit-specific retrieval was unavailable. No
new Git blob attestation or binary-to-source correspondence was established.
These source observations weaken the rationale for a speculative hash rewrite;
they do not exclude engine accounting, stream internals, native retention or GC
effects. No claim is made that `hash.destroy()` synchronously frees every native
allocation, especially on incomplete/error paths.

## Candidate changes rejected as unsupported

- Replacing incremental hashing: no demonstrated growing hash-owned input store,
  and new CPU/compatibility risks without a source-supported memory prediction.
- Copying or explicitly clearing each input view: adds work or changes
  references without proving external-memory release. Detaching transferred
  buffers would additionally require a justified ownership contract.
- BYOB/reusable-buffer transport: requires byte-stream/ownership support not
  established by the current generic stream contract and frozen synthetic
  source. It is a design experiment, not the demonstrated correction sought.
- Forced GC, idle delays, shorter lifetime, fresh workers, smaller inputs or
  growth-state resets: change the agreed method, architecture or limits; none is
  adopted. An unchanged rerun supplies no missing causal evidence.

## What would change this decision

A future fix needs evidence linking a specific allocation owner to avoidable
retention/copying, a bounded source change that preserves byte identity and
cleanup/recovery semantics, and a predicted observable improvement. An upstream
issue or patch could provide that evidence only if its path/version applies to
the intended runtime. This report identifies neither such a patch nor a proven
external cause. Do not blame R2 transport for a failure reproduced with a
synthetic source.

The alternative would be an explicitly reviewed change to the acceptance
contract. The present 8 MiB stop is a policy, not a proven leak classifier, but
its failure cannot be waived on that basis. Neither further investigation nor an
amendment is authorized by this finding. Return the blocker for a decision; no
automatic follow-up run, infrastructure change or threshold increase.

History primary retains sole write ownership; independent and IC-1 review cover
this finding, not a nonexistent executable fix. Existing admission, accounting,
media retention, recovery and later feature gates remain open. Unknown AI
execution still permits only original-operation recovery/reconciliation, never
another invocation or refund. Prior source/result manifests and unrelated work
remain untouched.
