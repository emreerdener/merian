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

## Target contract prerequisite inventory — October 13, 2026

The local owner composition is committed at
`b3864361dd5c8b4d921650891ca1926a798d9bb0`, after independent and IC-1 final
review of candidate
`45df8399e08b88ec9475a0f46eb074e51f1da331d70ab5acf1e69d1865e76bf8`. Its
checkpoint and final decisions are in
`.artifacts/initial-media-structure/owner-local-checkpoint.json` and
`owner-final-reviews.json`. The following inventory prepares the next target
contract; it does not choose, install or qualify a target runtime.

### Reuse the current state and receipt owners

| Boundary                          | Existing concrete owner                                                                                                                                                                 | Target contract obligation                                                                                                                                                                  |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Frozen original input             | `initial_analysis_preparation_intents` in `20261011192000_prepare_initial_saved_assignment.sql`; source mapping/registry in `20261011194522_prepare_initial_media_source_lifecycle.sql` | Resolve only the saved assignment, backend generation and original object IDs. Keep the original 300-second lifetime and immutable source mapping.                                          |
| Fixed service calls               | Five service-role-only wrappers in `20261011205141_prepare_initial_preparation_execution.sql`; `createPreparationExecutionTransport` in `preparationExecutionTransport.ts`              | Use only original status, source settlement, sole issue, known-output registration and outcome settlement. The fixed transport supplies no runtime installation or new execution authority. |
| Serialized state and write guards | `internal.initial_preparation_execution_action` and `internal.guard_initial_preparation_execution_private` as revised in `20261012000419_qualify_initial_preparation_owners.sql`        | Preserve original scope, phase/deadline, eligibility and private-erasure checks. No parallel operation owner or service bypass.                                                             |
| Fresh execution and recovery      | `runInitialPreparation` and `reconcileInitialPreparationOutput` in `preparationExecution.ts`                                                                                            | Bind the concrete adapter only at the existing fresh-grant callback. Issued/lost-reply/unknown states recover the original operation; known output reconciles without another transform.    |
| Eligibility                       | `internal.lock_initial_preparation_eligibility` and `internal.resolve_initial_media_preparation_assignment` in `20261012000419_qualify_initial_preparation_owners.sql`                  | Require the saved qualified profile/backend installations and handoff eligibility under the existing gate. A shape-valid profile or local executable receipt is insufficient.               |
| Byte transport                    | `mediaStorage.ts` supplies exact-key conditional PUT and bounded direct GET/hash verification; `mediaHandoffStorage.ts` supplies private source/destination primitives for M1/handoff   | Reuse compatible byte primitives only after defining the original-preparation signer/object/erasure contract. Do not call an M1 owner as a substitute for preparation ownership.            |
| Receipts                          | `preparationExecutionContract.ts`, its closed schemas and the existing private source/grant/output/outcome tables                                                                       | Reuse the saved identity and ordered byte chain. Extend a schema only for concrete target facts that the existing schema cannot represent.                                                  |

The service operations are exactly `get_initial_preparation_execution_status`,
`settle_initial_preparation_sources`, `issue_initial_preparation_execution`,
`register_initial_preparation_output` and `settle_initial_preparation_outcome`.
Their wrappers require service role; ordinary client roles have no execution
grant. No route installs the new local fixture. This source inventory describes
relevant owners, not a newly qualified effective SQL lock graph. Any later
lock/caller/schema change needs its own complete effective inventory and
concurrency acceptance.

Existing source receipts already bind scan, assignment, profile, backend,
validator identity, every ordered original object tuple and declared facts.
Grants bind original source/profile/artifact digests and deadlines. Output
manifests bind grant/source, prepared bytes, transform/options and source
identity; resolved manifests bind allocated output IDs. The immutable outcome
nests those records with the profile and retained tuples. Adding another generic
attestation field or table would not establish that a target executed anything.
**No schema delta is justified by target selection alone.**

The missing implementation is a concrete target composition of the existing
`readSource`, `inspectSource`, `runtime`, identity-output verification and fresh
output/readback dependencies. The contract must establish how the trusted
adapter obtains saved object metadata and signing authority, proves bytes are
private and unchanged, resolves the immutable executable, enforces the complete
cohort budget, and records/reconciles only the original output. No SQL lock may
span process or storage I/O. No caller-selected URL, artifact, profile or object
path may enter that composition.

### Facts required before choosing that composition

- Name the intended execution environment, platform/ABI and exact runtime
  version/identity. The existing Darwin tuple is a local experiment and cannot
  be selected as an Edge installation. The intended backend product alone does
  not supply executable or isolation evidence.
- Identify the compatible pinned decoder/transform closure and retained
  toolchain provenance for each consumed modality. WAV has a bounded parser and
  executable. Photo/MP4 signatures establish neither successful decoding nor
  expansion safety; they cannot fill this row.
- Define the full accepted ingress and aggregate cohort envelope, output
  expansion bounds, phase deadlines, hard CPU/native-memory owner, cancellation
  and supervisor-death behavior. Declared profile limits, sampled RSS and the
  local 9/14/15-second observations do not establish target guarantees.
- For derived video frames/audio, define the trusted raw-clip relationship,
  track/timebase/timestamp selection, orientation/color/crop policy, frame order
  and audio extraction/resampling policy. Review compatibility with existing
  saved `video_frame_v1` and `video_audio` records before proposing any new
  version. Existing integer lineage is not a decode/extraction executable.
- Identify the separately authorized qualification environment and operation
  before installed/hosted use, with the original signer/backend generation and
  exact artifact/configuration evidence. Local contract drafting needs no such
  operation; runtime use does. Preserve pending device environment answers.

A concrete decoder may require new durable photo dimensions/format/expansion
facts or MP4 track/timebase/derivation facts; a target may require a durable
process-provenance receipt. Those are examples of unresolved requirements, not
approved schema additions. Choose neither field names nor a new receipt version
until the consuming target contract proves the need and receives independent and
IC-1 agreement. Do not relabel the synthetic profile, register an unqualified
bundle, or implement another placeholder runtime to move a checkpoint forward.

The next review must distinguish decisions that can be resolved in the local
contract from missing target evidence or separately named runtime-use authority.
No named environment variable is currently documented as blocking this local
inventory. Missing target evidence must be recorded concretely; it must not
become a reason to repeat the accepted WAV or SQL suites. Provider dispatch,
result/completion and native/integrated acceptance remain in their existing
dependency order, followed by approved deletion/export/redesign.

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
and IC-1 final evidence reviews are complete and checkpoint
`b3864361dd5c8b4d921650891ca1926a798d9bb0` is committed; broader
target-runtime/media integration remains open. The
[target composition proposal](initial-preparation-target-composition-2026-10-13.md)
resolves the proposed trust and crash-recovery boundaries for review without
claiming a qualified target. Reuse existing artifact qualification and execution
owners. Retain failed evidence and qualify new adapter/receipt bindings with
copied-view mutation, changed identity/options, malformed/truncated/expanding
inputs, complete cohort ordering, original deadlines, lost
grant/output/settlement, erasure/cancellation and no-repeat execution cases.
Full affected gates belong to coherent implementation milestones; unchanged
completed SQL or artifact qualification must not be rerun merely because this
document changes.

No target-runtime implementation acceptance is claimed by this revision. The
local owner acceptance above is separate. The redundant helper was removed, and
the prior full Edge failures remain evidence of that withdrawn candidate rather
than failures of the restored committed runtime. Restoration must be checked
against the exact baseline, not described as a new successful suite. Initial
dispatch, durable result capture, successful completion, native media-backed
journeys and integrated acceptance remain open. Approved version deletion,
source export and Identification/History redesign follow them.

Activation stays disabled and ordinary production access nil. Exact-push
approval remains required; PR115 is not updated. No deployment, hosted
scheduling, device installation/testing, TestFlight or distribution is
introduced. The capture visual refactor, broader engine hardening and Field Trip
retain their separate ownership boundaries; existing schedules and pending
environment answers are unchanged.
