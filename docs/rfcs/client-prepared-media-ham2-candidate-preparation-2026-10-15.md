# CP-1: candidate delta and bounded preparation proposal

October 15, 2026. **HAM-2 adopted as method only; CP-1 proposed for approval.**
The user adopted the reviewed method at `4598debc1`, document hash
`654c98fba017a30b4a05e3a244596fdf853f0f2caefabb9b8824c6def12c5e49`, reviewed set
`b1ed0c631548d9bbc183cbb487a418c2bdaf22113323e44093f040bda1a094e5`. That
adoption authorizes no construction or tests. This document records a read-only
source comparison and proposes the next preparation boundary. Activation
disabled, AWS and 160 MiB unapproved, limits unchanged, auto-prompts paused. No
tests, builds, dependency resolution or hosted actions occurred.

## Recommendation

**No new representative hosted test is justified by the current delta.** Do not
repackage or deploy the existing transport merely to label it HAM-2. Its hosted
evidence remains bound to `9c88cc72d`; the finite local GAC-1 result remains
separate. Neither result is promoted to a pass for current HEAD or a complete
verifier.

The objective is still user-facing identification history: reanalysis creates a
new version while retaining earlier results, original media and exact recovery.
Recommend **CP-1: one two-hour local candidate-contract preparation** aimed at
that integration, with independent and IC-1 review. The first implementation
candidate should close original-photo retention, not create another transport
harness. CP-1 must produce its exact bounded implementation packet and settle
its fresh-versus-historical compatibility boundary before code changes. No
runtime code, schema, bundle or tests in this preparation.

## Exact comparison: what changed

Compared the tracked characterization subtree at executable baseline
`9c88cc72d35d925a3e4a7d7890f2ec8728d0e414` and current checkpoint `4598debc1`.
The retained 26-path SHA-256 comparison is
`.artifacts/client-prepared-media/ham2-candidate-preparation/delta.json`: 18
paths unchanged, eight changed/added. This is a source comparison, not a runtime
equivalence test or comparison of the entire shared checkout.

| Surface                                          | Difference and evidence                                                                                                                                      | Consequence                                                                                                                                                                                          |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Read/hash and transport                          | `verifier.ts`, `private_get.ts`, `telemetry.ts`, `policy.ts` unchanged.                                                                                      | No new behavior in these sources justifies repeating the old hosted reads.                                                                                                                           |
| Authentication / configuration / entry / staging | `runtime/auth.ts`, `config.ts`, `entrypoint.ts`, `stage.py` unchanged.                                                                                       | Existing evidence remains relevant to those exact source boundaries, not proof of a newly composed bundle.                                                                                           |
| Local GAC-1 option                               | New `gac1.ts`; `handler.ts` accepts optional `growthContract`; `runtime/worker.ts` forwards an optional second argument.                                     | This is real source/dependency change. `handler.ts` statically imports GAC-1, even when the option is absent; current artifact/import/allocation behavior is not proven identical to the old bundle. |
| Effective default hosted mode                    | `runtime/entrypoint.ts:createWorker` supplies no GAC-1 option. `createHandler` retains v1 acknowledgement and the legacy immediate growth veto in that mode. | Local opt-in behavior is not silently enabled on the hosted path. Do not infer a hosted regression or a new hosted pass from the local result.                                                       |
| Test/document changes                            | New `gac1_test.ts`, assertions in handler/runtime tests, two README updates.                                                                                 | Retained checks document opt-in separation. They were inspected, not rerun.                                                                                                                          |
| Retained local controllers                       | GAC stage explicitly opts into GAC-1; local loader, worker-control and shutdown changes remain in local evidence packages.                                   | They are not a deployment candidate or a supported hosted lifecycle. No new artifact may inherit their pass by assertion.                                                                            |

The unchanged legacy driver accepts the exact v1 acknowledgement shape,
schedules 26 attempts, permits two-item groups and requires 26 attempts to
complete. It is not HAM-2's five-slot serial driver or independent assessor.
Those would need future preparation if a meaningful changed boundary justifies
HAM-2. Creating that adapter solely to run the unchanged transport would reverse
the method's purpose gate, so it is not recommended now.

No new production route registration, CPM receipt implementation or production
verifier change is established by this characterization-subtree comparison.
Unrelated shared-checkout changes are excluded and preserved. A changed static
dependency is reason to withhold automatic evidence transfer, not reason to
spend another hosted campaign without a product objective.

## Product inventory and shortest dependency path

The alpha matrix and current checkpoint narrative remain authoritative; recent
resource experiments do not reset completed product work. The following is an
inventory of retained evidence and identified gaps, not a new full audit or a
claim that the shared checkout equals an earlier tested candidate.

| Boundary                      | Reuse / already recorded                                                                                                                                                                    | Still needed for the user-facing journey                                                                                                                                                                            |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Version history and selection | Foundation/parity at `b8eb3d64f`; photo and audio child lifecycles ready locally (A7/A8).                                                                                                   | New media/context and video-source integration, installed journey and current-candidate applicability. Do not rebuild the historical version model.                                                                 |
| Admission/funding/recovery    | Atomic admission, original funding, M1, private receipt/status recovery, positive-unused C1 cancellation/expiry and erasure accepted locally at `bc2a5af507a0ee56cbdb1a357f5221bec611371b`. | Distinct CPM fresh-branch consuming versions; S0 dispatch, durable validated result and successful completion integration remain open. C1 is not successful completion.                                             |
| Media handoff                 | Pure handoff/SQL parity at `f7b7181ec016b4d37206a290d0f54bce822d463d`; inactive runtime copy/M2/transfer family has recorded full local gates.                                              | Applicability to CPM identities, immutable-input authority and receipt/recovery rules. Do not rerun unchanged suites or relax old proof fields.                                                                     |
| Original photo retention      | Queue copies inference/display bytes; approved local feasibility includes exact file-copy/reopen primitives.                                                                                | Actual capture/import must retain original selected bytes before draft clear, with separate original/AI/preview references. `StagedImage.original` is decoded UI/crop lineage, not durable original-byte ownership. |
| Audio and video               | Existing WAV artifact/owner qualification and retained local media foundations.                                                                                                             | Final client audio recipe/version and signal/identification-quality acceptance; video source reuse with exact frames/audio/context binding. No faithful-derivation claim or automatic video publication/review.     |
| Shared references/deletion    | Existing inactive cleanup and erasure mechanisms plus retained model evidence.                                                                                                              | Authoritative CPM references, late-upload/release dependencies and complete restart/missing-file/deletion races. Preserve assets required by surviving versions.                                                    |

Sources:
[alpha checkpoint and matrix](identification-history-alpha-readiness-2026-10-11.md),
[IC-1](initial-completion-history-interface-2026-10-11.md),
[CPM amendment](client-prepared-media-amendment-2026-10-13.md),
[approved local plan](client-prepared-media-approved-local-plan-2026-10-13.md),
and [local feasibility](client-prepared-media-local-feasibility-2026-10-13.md).
CPM's versioned functional/schema, audio and reference agreements remain open;
HAM-2 adoption does not implicitly close them.

Keep the approved dependency order: resolve the narrow fresh CPM input and
ownership agreement; retain originals and freeze only fully prepared audio/AI
inputs; integrate eligible immutable media with the existing admission, funding,
dispatch/result/recovery owners; then prove saved-version projection, selection
and source reuse in the combined photo/audio/video journey. Required
reference/deletion and contention acceptance must accompany the affected
integration. Later individual-version deletion/source export and redesign keep
their approved sequence. Broader engine hardening, Field Trip and capture visual
refactoring remain separately owned.

## Proposed CP-1 scope: close the first implementation packet

One two-hour local window includes analysis, the packet and independent/IC-1
review. Read existing source/contracts/evidence only; no account access,
browser, provider contact, new source checkout or telemetry inventory. History
primary alone writes documentation and sanitized evidence. At most 64 KiB new
retained material inside the existing 512 MiB allowance with cleanup reserve;
preserve at least 20 GiB free. No fixtures, dependency installs or bundles. Stop
on expiry or storage shortage; no automatic extension.

The fixed deliverable is **P1: inactive original-photo ownership integration**,
with exact interfaces, proposed file list and compatibility decisions. CP-1 is
not another open-ended verifier survey. Inspect at most 12 implementation files
across these directly relevant owners:

- `StagedImage`, `CaptureSubmissionPayload`, the existing photo
  acquisition/import adapters and draft-clear caller;
- `OfflineQueueManager+CaptureEnqueue`, `OfflineCaptureFileStore` and their
  persisted queue/reference representation and cleanup owner;
- `ObservationReanalysisFileStore` and the existing source-reference reader,
  only to define reuse and missing-original semantics.

Record every selected path. Do not edit the user-owned capture changes or absorb
the separate capture-tools visual refactor. If an interface intersects those
edits, specify the minimal additive handoff and required ownership agreement;
existing dirty files cannot be replaced or assumed available for writing.

The proposed P1 implementation should be one bounded **four-hour local
checkpoint**, separately approved after CP-1, whose only new behavior is durable
original-photo ownership from acquisition through successful queue admission.
Its packet must settle these items before implementation, without inventing a
production CPM wire schema or silently rewriting old queue operations:

1. The exact captured/imported original bytes and acquisition policy; a decoded
   image or regenerated JPEG is not an original. Refuse unavailable/unsupported
   source bytes without clearing the draft or silently substituting a
   derivative.
2. Separate immutable original, AI-input and display identities; when and how a
   durable original-file reference joins the future fresh submission. Existing
   admitted records recover unchanged; old local drafts lacking originals need
   explicit remediation before a fresh CPM admission.
3. Copy/commit/clear ordering, restart recovery and cleanup authority. Failed
   admission may delete only its own new unreferenced copies; a surviving draft,
   operation or version keeps its required assets. Queue persistence is not
   provider dispatch authority.
4. Approved 32 MiB original-photo and whole-package/temporary-storage checks,
   including copies and interruption leftovers. Do not change the approved
   limits or estimate original cost as zero. Preserve the draft on refusal.
5. Exact feature-gate and persistence compatibility. If a persisted-field/schema
   change is needed, its versioned migration agreement and owner are explicit
   prerequisites. Do not bypass them with an ad hoc sidecar or claim that an
   inactive helper alone fixes the end-to-end retention gap.

P1 excludes audio processing changes, video behavior, backend schemas/dispatch,
version UI redesign, hosted calls and installation. Existing behavior must not
start sending originals to AI or admitting the new protocol. The packet must
show how the code stays inactive until its subsequent approved integration. If
the narrow original-reference/queue agreement cannot be closed safely in CP-1,
return that exact decision and proposed alternatives; do not expand P1 or
replace it with another transport campaign.

## New tests: only for the changed boundary, after separate approval

No test is authorized now. The P1 packet should propose the smallest checks
below, tied to its actual implementation, with exact selectors at handoff.
Unchanged completed evidence is reused only where source and behavior match.

| New or unresolved behavior                                      | Why retained evidence is insufficient                                                            | Smallest decisive check and acceptance consequence                                                                                                                                                                |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Capture/import original survives derivative edits and admission | File-copy primitive and hosted opaque bytes do not exercise real acquisition or queue ownership. | Synthetic distinct original/inference/display fixture through the changed owners; reopen and compare exact original bytes. Failure blocks original-retention acceptance.                                          |
| Interruption/restart between copy, persistence and draft clear  | Prior verifier cleanup has no native queue transaction.                                          | Inject interruption at each new durable transition and reopen the queue; originals remain recoverable, no false accepted admission or silent re-identification. Failure blocks P1.                                |
| Missing/oversized source and storage refusal                    | Existing derivative admission does not account for new original copies.                          | Boundary cases at the approved cap and cap plus one, missing file and insufficient reservation; reject while preserving draft/required assets. Failure blocks P1.                                                 |
| Cleanup must preserve another owner/version's original          | Old synthetic reader closure is not a shared-reference deletion race.                            | Deterministic owner/reference fixture for failed admission and release race; only unreferenced owned copies are removed. If P1 delegates references to a later owner, explicitly leave that integrated gate open. |
| New persistence or API surface                                  | Old passing suites cannot prove a newly added field or migration.                                | Only applicable compile, contract/migration and affected full gates, plus independent re-review; exact commands depend on the finalized file list. No device claim from local checks.                             |

User-owned device testing and a separately approved native installed journey
remain required where applicable. Audio quality, CPM receipt/funding integration
and final version persistence/selection get their own focused checks when those
behaviors actually change. Optional allocator/affinity diagnostics are not
prerequisites to this native preparation and are not proposed. The unresolved
native-memory/CPU measurement gap cannot justify repeating a test unable to
resolve it.

## Approval boundary and stopping decision

Current assessment: `no_new_test_justified` for the representative hosted path.
Do not construct a five-call adapter or relabel the old package simply to run
it. The exact hosted and local evidence retains its original scope, warnings and
failures. HAM-1 resource Gates M/R remain unavailable/pending; HAM-2 is adopted
only as the narrow method and supplies no execution or production authority.

**Requested next approval:** CP-1's two-hour local preparation of the bounded P1
original-photo retention implementation packet. No implementation or tests run
under CP-1. P1's proposed four-hour implementation/check window, exact scope and
reviews return for approval before code changes or execution. If preparation
finds a specific blocking contract/ownership decision, return it once; no
automatic additional investigation or generic experiment loop.

Activation disabled, ordinary access nil, AWS unapproved; package/storage limits
unchanged. Preserve existing push/merge, deployment, hosted and device
restrictions, original-operation recovery, immutable supporting descriptions,
media-backed photo/audio/video submissions and later deletion/export/redesign
sequencing. History primary remains sole writer; independent and IC-1 review
remain read-only.

Adoption, delta, preservation and review records are under
`.artifacts/client-prepared-media/ham2-candidate-preparation/`.
