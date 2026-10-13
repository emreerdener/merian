# S0 media validation: original preparation evidence and retained bytes

Status: revised dependency contract after runtime checkpoint
`41823294d5a9a919ab4a339dc8564ec4a6ae12c4`; dependency boundary accepted by
independent and IC-1 review at SHA
`65f3decca3c50b501e96186f9665cbcfc9a4d490e0a58fdf34833600302f95cb`. History
primary remains sole writer. No runtime launch, installation, service
permission, new grant or production composition follows from this document.

The first draft proposed another unconsumed WAV comparison helper. Further
source tracing found that the accepted finite validated-WAV artifact already
performs private-copy structural validation and transformation. That redundant
candidate and its typed-error/archive-test changes were withdrawn before commit.
Its exact sources, reviews and failed test evidence remain under
`.artifacts/initial-media-structure/withdrawn-local-wrapper/`. They are
historical and confer no acceptance on this revised contract. The committed
runtime checkpoint remains the implementation baseline.

## Existing implementation to reuse

The [validated WAV artifact profile](initial-wav-artifact-profile-2026-10-11.md)
and `scripts/initial-preparation/registry.json` already name a concrete local
validator/transform executable:

- Profile `validated-wav-darwin-arm64-v1`, adapter and validator source anchor
  `e4fc83d27329b1133eab3fbfe8368d58c96ff4fc`.
- Emitted eight-module artifact, 16,647 bytes, SHA256
  `cf2df93f4bdcdea853ae7d9c0e1432149cec470270880ca87dcb3b43f51a2f64`.
- Historical transform archive and exact Deno/esbuild/provenance identities,
  separately pinned adapter/validator regular Git blobs, and two reproducible
  offline builds. `artifact.py` verifies these before executable qualification.
- `wav-validation-bootstrap.ts` snapshots one exact nonshared source view,
  invokes `inspectInitialWavStructure` on that private copy and passes that same
  copy to the pinned `processWavBuffer`. The v2 closed protocol binds explicit
  fallback, source and output byte counts/digests, canonical prepared bytes and
  complete status. Known structural and transform rejection stages remain
  distinct from unexpected failure.

These are executable synthetic results, not merely profile metadata. Preserve
both registry entries, source blobs, artifact bytes and accepted receipts. Do
not add a parallel WAV algorithm, replace archived code with current checkout
source, or change `configuration-assets-v1.json` or its saved digest. The
historical minimum-duration Error classification belongs to that pinned
artifact; a new typed error is unnecessary for reusing it.

The local profile is explicitly `local_synthetic_only`, Darwin ARM64, always
Edge-ineligible. Its stdin ceiling is 262,144 bytes and base64 ceiling 256,000
characters; these are smaller than the 2,700,000-byte ingress limit. Existing
permission denial, network sandbox, fixed environment, private cache, deadline,
I/O limits, cancellation and process-group reaping remain useful local controls.
The 64 MiB V8 old-space limit and sampled 256 MiB process-group RSS ceiling are
not a hard native-memory cap or a complete saved CPU/heap budget. No local
receipt upgrades this tuple into an installed or hosted profile.

## Required ordering: no post-M2 transform

The
[durable pre-admission agreement](initial-pre-admission-preparation-2026-10-11.md)
supersedes the historical post-M2 retransformation proposal in the
[earlier binding interface](initial-preparation-binding-interface-2026-10-11.md).
Its required order remains:

1. Freeze the unfunded original candidate/assignment/profile, allocate and
   durably verify the original sources.
2. Only the fresh positively received original preparation grant may invoke the
   qualified transform once, outside SQL locks and under the original deadline.
   Lost acknowledgement or process outcome permits original recovery, never
   regrant, retransform or another artifact/profile.
3. Preserve the known original output, register destinations before storage,
   verify exact output bytes and record the immutable preparation outcome.
4. Final admission binds that outcome and original funding. M1/M2 v2 and the
   accepted handoff copy those exact bytes; they never execute the transform.
5. Before provider dispatch, verify original executable preparation evidence
   through that complete outcome/admission/handoff chain and the retained
   prepared bytes actually consumed. Missing proof holds; it does not cause a
   new run for an existing operation.

This contract therefore does not authorize reading an admitted source and
running the local artifact to reconstruct its result. Historical admitted
operations retain exact status/outcome recovery with their original identities.
The same conservative rule applies after an uncertain preparation execution.

## Concrete missing integration

`_shared/initialAnalysis/preparationExecution.ts` already owns the inactive
synthetic sequence in `runInitialPreparation`. `verifySources` copies, hashes
and compares each saved source, then passes a defensive copy to the injected
`inspectSource`. The injected `runtime` reads defensive copies of the verified
snapshots only after a validated fresh grant. Known output retention and
settlement-only reconciliation are separate. Reuse those phase and recovery
owners; do not create a second operation or runner lifecycle.

Pre-grant `inspectSource` is structural inspection only. The combined WAV
validate-and-transform executable must not run as a source preflight and again
after grant. The consuming protocol must give structural-only inspection and
actual transformation distinguishable authority and evidence; revalidation of
bytes inside the one authorized transform is not a second transform.

At checkpoint `41823294`, the trusted synthetic `inspectSource` and `runtime`
dependencies did not resolve or run the pinned executable. The subsequent
[local owner fixture](initial-preparation-local-owner-integration-2026-10-13.md)
closes that narrow WAV composition gap with actual local execution; it still
cannot attest an installed decoder. `preparationExecutionContract.ts` validates
shape and binding of declared source facts, grant artifact digest and output
bytes. Equality with profile metadata is not proof that the named executable
consumed those bytes. The handoff family likewise cannot manufacture missing
preparation execution proof from byte retention.

Before target-runtime integration, close one consuming protocol across these
existing owners:

| Boundary                       | Required binding and rejection                                                                                                                                                                                                                                                                                                                                                |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Original scope                 | Exact saved candidate, ordered source mapping, assignment/profile digest, original preparation source receipt and fresh grant. Snapshot validated own-data scalar fields before asynchronous work; reject changed options, role/order or caller-selected artifact.                                                                                                            |
| Source bytes                   | Direct bounded reads from original object IDs and saved backend generation; verify complete expected length/digest, reject erasure markers, own exact private copies before awaits, and never refetch or replace the transform input.                                                                                                                                         |
| Executing tuple                | Resolve the exact saved qualified runtime/validator/transform bundle and transitive source/toolchain identity before a fresh invocation. Check target eligibility and complete ingress/cohort/resource limits before granting or executing; local Darwin evidence cannot satisfy Edge eligibility.                                                                            |
| Process input/output           | Bind each ordered ordinal and fixed options to the exact source bytes passed into the existing executable protocol; compare returned source digest/count, output bytes/digest, protocol and fallback against the original invocation. Unexpected exit, malformed/extra output, timeout or unknown execution never becomes a successful negative result or an execution retry. |
| Durable preparation evidence   | Bind original grant, executing tuple and complete ordered input/output evidence to the original immutable outcome under existing erasure and cancellation ownership. Justify any schema extension and its SQL parity before implementation; no ad hoc boolean, caller report or process-local brand supplies durable authority.                                               |
| Admission and retained handoff | Preserve existing admitted receipt, M1/M2 v2 and transfer semantics. Prove byte-preserving correspondence to the original outcome; no later transformation, profile selection or replacement funding.                                                                                                                                                                         |
| Consuming prepared bytes       | Verify the complete retained prepared cohort and exclusive byte ownership through provider construction. A scalar digest report alone cannot prove what a later reader consumes. No provider grant before all S0 dependencies close together.                                                                                                                                 |

The next bounded work after local-owner acceptance is the concrete target
runtime/receipt and resource contract for that original preparation boundary,
including any justified schema delta and current owner/caller inventory.
Existing codecs and the actual local WAV composition are inputs to it, not
completed target integration. Do not implement another identity-only helper or
speculative grant schema while that consuming agreement is open. Pure draft
preparation and read-only tracing are authorized; installed runtime use still
requires separately named authorization.

## Other formats and current media scope

Standalone WAV has a concrete bounded parser and local executable proof. Photo
signature checks are not decoders; raw-MP4 box checks do not decode compressed
payloads. Concrete bounded validators/decoders and expansion limits remain
internal S0 prerequisites for all formats actually consumed.

Current `video_frame_v1` records supplied frame lineage and integer indices; its
null transform parameters do not specify timestamps/timebase, sampling,
orientation/color/crop or a raw-clip conversion executable. Video audio is a
separately supplied WAV associated by `clip_index`; its short-context fallback
is trimming policy, not extraction proof. Close the complete trusted derivation
and saved-version compatibility before claiming raw-clip provenance. Do not
silently reinterpret or rewrite existing receipts. Video remains in the approved
product scope, including reanalysis using original media.

Every fresh initial identification and reanalysis requires physical media, with
optional immutable supporting descriptions. Missing/removed media requires
replacement or blocked submission. Historical text-only records and exact
already-admitted recovery remain; unadmitted queued drafts require explicit
remediation, never a silent rewrite or text-only fallback.

## Acceptance and remaining boundaries

The revised dependency boundary has independent and IC-1 concurrence. The
[concrete local owner agreement](initial-preparation-local-owner-integration-2026-10-13.md)
also has both reviews and authorizes the bounded synthetic implementation. Its
exact source/vector launch reviews are clear, and the fixed synthetic owner
execution and both existing standalone artifact regressions pass. Independent
and IC-1 final evidence review is required before the local checkpoint commit;
broader target-runtime/media integration remains open. Reuse existing artifact
qualification and execution owners. Retain failed evidence and qualify new
adapter/receipt bindings with copied-view mutation, changed identity/options,
malformed/truncated/expanding inputs, complete cohort ordering, original
deadlines, lost grant/output/settlement, erasure/cancellation and no-repeat
execution cases. Full affected gates belong to coherent implementation
milestones; unchanged completed SQL or artifact qualification must not be rerun
merely because this document changes.

No implementation acceptance is claimed by this revision. The redundant helper
was removed, and the prior full Edge failures remain evidence of that withdrawn
candidate rather than failures of the restored committed runtime. Restoration
must be checked against the exact baseline, not described as a new successful
suite. Initial dispatch, durable result capture, successful completion, native
media-backed journeys and integrated acceptance remain open. Approved version
deletion, source export and Identification/History redesign follow them.

Activation stays disabled and ordinary production access nil. Exact-push
approval remains required; PR115 is not updated. No deployment, hosted
scheduling, device installation/testing, TestFlight or distribution is
introduced. The capture visual refactor, broader engine hardening and Field Trip
retain their separate ownership boundaries; existing schedules and pending
environment answers are unchanged.
