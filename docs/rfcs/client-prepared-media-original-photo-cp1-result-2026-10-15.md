## October 15, 2026 — NCO-1 native agreement; P1 execution awaits approval

The authorized two-hour local agreement scope after `600b5ce28` prepares P1-L1:
freeze V58, add four standalone V59 ownership entities, retain exact original
bytes before draft release, and bind capture/cleanup to account-work leases and
fail-closed purge. The canonical NCO-1 packet records the concrete file boundary
and acceptance plan. Exact independent/IC-1 review is required for closure; its
evidence is retained with this candidate. The next request is one four-hour
local implementation/validation window, including up to 2 GiB new native test
evidence under the existing managed-build procedure. It is not authorized yet.
Qualification excludes competing non-P1 allocators; installed mixed-allocator
and integrated product gates remain open. No tests, builds, runtime edits or
hosted actions occurred. No transport rerun is justified. Activation disabled,
ordinary access nil, AWS unapproved, existing limits unchanged, auto-prompts
paused. Canonical packet:
`docs/rfcs/client-prepared-media-native-ownership-agreement-2026-10-15.md`.
Earlier entries remain historical and exactly recoverable.

# CP-1 result: original-photo ownership and the P1 boundary

October 15, 2026. CP-1 preparation authorized by the human's “proceed” after
`cae2329a1`; two-hour window started 22:46:21 UTC. Documentation/source review
only: twelve implementation files, no tests, builds, runtime edits or hosted
reads/actions. Activation disabled, AWS unapproved, all limits unchanged.

## Decision

**A durable, versioned local preparation ledger is required before P1 can safely
retain originals through restart and admission.** Recommend typed SwiftData
ownership in the existing app container, separate from dispatchable
`OfflineQueuedScan` work. Do not add an original path to arbitrary job JSON or
save unreferenced files beside the queue. A local preparation commit must not
consume scan funding, create a server admission or start inference.

CP-1 identifies the exact missing agreement rather than claiming an executable
four-hour implementation is ready. The twelve-file review establishes the
acquisition and queue boundaries, but does not establish the current complete
schema registration/recovery graph or the uninspected preparation/cleanup
helpers. Those need a bounded native persistence and capture ownership handoff
before source edits. No further verifier test is justified.

The recommended decision is to approve this native ledger design and a narrow
schema/capture handoff, retaining History as sole writer. The proposed P1
implementation window remains four hours, contingent on the exact migration,
file list and inactive composition receiving independent/IC-1 concurrence before
implementation. This document does not authorize that window or turn an
incomplete file inventory into a ready execution packet.

## What the inspected source establishes

Paths are rooted at `apps/ios/Merian/`; all twelve exact hashes are in
`.artifacts/client-prepared-media/cp1-result/sources.json`. Statements describe
the shared checkout, including retained user changes, not a tested candidate.

| Owner                                                                                         | Evidence                                                                                                                                | Necessary change                                                                                                                   |
| --------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `Features/Capture/Scan/ViewModels/CaptureWorkspaceViewModel+PhotoCapture.swift:46`            | `captureImage()` returns encoded Data before `prepareStill`; only inference/display and decoded preview reach `StagedImage` at line 87. | Acquire durable ownership of exactly that Data before processing can release it.                                                   |
| `Features/Capture/Shell/ViewModels/CaptureWorkspaceViewModel+Imports.swift:50`                | Picker file is loaded, then removed by defer at line 55. External import ownership is removed after staging at line 165.                | Commit an owned original before either source-release action; preserve recoverable selection/failure state.                        |
| `Core/Data/Images/PhotoLibraryManager.swift`                                                  | Camera-roll writes pass through GPS scrubbing.                                                                                          | Camera-roll output is not a byte-exact private retention fallback. Leave that export/privacy behavior intact.                      |
| `Features/Capture/Staging/Models/StagedImage.swift`                                           | `original` is decoded UI/crop lineage; replacement methods retain provenance but have no original-file ownership.                       | Add an independent immutable original reference; cropping changes AI/display identities only.                                      |
| `Features/Capture/Submission/Models/CaptureSubmissionPayload.swift`                           | Admission snapshot freezes image IDs, inference payloads, provenance and order; video frames also enter inference images.               | Snapshot exact original references for physical still sources only; do not count video frames/posters as extra originals.          |
| `Features/Capture/Staging/Models/CaptureDraftSession.swift`                                   | In-memory generation/operations/account binding; reset replaces the struct.                                                             | Persist recoverable draft ownership and reservations; process-local generation alone cannot authorize file deletion after restart. |
| `Core/Data/OfflineSync/Services/CaptureAdmission/OfflineQueueManager+CaptureEnqueue.swift:64` | Claims funding, writes derivatives, then saves ordinary pending scan/job and may dispatch at line 583.                                  | Keep preparation outside this entry point. `startSyncImmediately=false` is not a durable no-dispatch contract.                     |
| `Core/Data/OfflineSync/Services/CaptureAdmission/OfflineCaptureFileStore.swift`               | Unique copies preserve caller-owned files; image JSON describes display media.                                                          | Reuse copy-before-ack principle, not its display role as an original or its unbounded copy operation as CPM admission.             |
| `Models/ActiveSchema/OfflineQueuedScan.swift`                                                 | Separate inference/display references; work kind defaults ordinary and ordinary permits inference at line 155.                          | Do not create an ordinary row as a held CPM package or reinterpret existing fields.                                                |
| `Features/Capture/Submission/ViewModels/CaptureWorkspaceViewModel+VisualSubmission.swift`     | Clears matching draft only after accepted timeline; then foreground inference remains possible.                                         | New prepared-package acknowledgement must be distinct from this dispatch-capable acknowledgement.                                  |

`CameraPhotoCaptureCoordinator.swift` confirms Data continuation lifetime and
cancellation ownership, not durable retention. `+SubmissionAdmission.swift`
confirms account/generation and preview checks, not a storage reservation or
server grant. No additional implementation files were opened under CP-1.

## Proposed local contract: P1-L1

These are proposed native interfaces and invariants, not a production CPM wire
schema. Final Swift names and schema version must be resolved from the actual
schema sources before implementation; never infer the next version from a
comment on one model.

- `PhotoOriginalReference`: opaque asset ID, owner scope, relative package path,
  exact byte count, SHA-256, actual supported type, acquisition kind and
  immutable generation. Do not expose absolute paths, metadata or bytes to
  telemetry. Hash is byte identity, not safe-decoding or derivation proof.
- `PhotoPreparationRecord`: stable package/draft ID, owner scope, contract
  discriminator `P1-L1`, revision, phase, ordered role references, supporting
  description snapshot when frozen, allocation/reservation obligations and
  deletion intent. Original, AI input and display are separate roles. Distinct
  files count separately even if hashes match; no speculative deduplication.
- Typed asset-owner edges and local read/copy leases, in the same durable
  authority, identify draft and held-package references. No legacy job metadata
  or ad hoc sidecar may become authoritative. A manifest may be a validated
  projection, never a second source of truth.
- Native actor operations: reserve acquisition, commit owned original, freeze
  prepared package, recover existing package, explicitly discard owner,
  reconcile local cleanup. All operate on stable IDs, account scope and expected
  revision; none accept an upload/provider capability or call funding.
- Phases: `acquiring`, `draftOwned`, `preparedHeld`, `needsAttention`,
  `retiring`. `preparedHeld` is local-only, never synonymous with
  server-admitted or dispatchable. Release builds and ordinary composition
  cannot select this experimental branch. No new user-visible route or capture
  visual redesign.

Recommend requiring resolved account ownership for this inactive branch; when
unresolved, retain existing draft/selection and block P1 acquisition with an
explanation. Do not silently bind an owned package to another account. Existing
legacy unauthenticated capture policy is unchanged. This proposed restriction
and the typed ledger require approval, not implicit adoption.

Retain camera bytes exactly as returned by `captureImage()`; retain picker bytes
exactly as delivered by `ImageFileWrapper`, including selected Photos edits.
This is not the unedited Photos master or Live Photo companion. Keep current
supported formats; no RAW/animated/multi-resource expansion. Use private,
account-scoped Documents-backed opaque directories. Propose
complete-until-first- user-authentication protection for background
compatibility, with no unprotected fallback; device lock/restart qualification
remains open. Originals contain metadata and do not enter AI, publication,
Photos export or logs implicitly.

Draft originals remain until explicit discard or a durable ownership transfer;
held/uncertain work retains them without TTL. P1 provides no cloud
acknowledgement or eviction right. Later history ownership must be acquired
before a package owner can release its last reference. No local cleaner decides
server erasure.

## Commit, recovery and release rules

1. Reserve the missing physical bytes and a pending-package slot durably before
   allocating an app-owned copy. Keep one acquisition/preparation active.
   Provider temporary files already acquired must be counted, not hidden outside
   the package. Failure to bound acquisition before allocation is a blocker, not
   permission to exceed the envelope.
2. Write bounded bytes into that attempt's exclusive protected partial file;
   count/hash incrementally. Validate actual supported type and pixel bounds
   before derivative decoding. Flush/close and atomically finalize within the
   owned directory before committing the asset/owner record. File and database
   commits are not one transaction: retain a durable intent describing either
   side of the crash window.
3. Commit original ownership before deleting a picker temporary representation,
   consuming an external-import handoff or presenting capture as safely
   retained. Revalidate account/generation after suspension. Stale completion
   cannot attach to a new draft or delete its files.
4. Freeze prepared original/AI/display ordered references and supporting text
   only after all photo processing and budget checks finish. Persist the held
   package and transfer the draft edge in one database transaction. Clear UI
   only after its matching durable acknowledgement; ambiguous save means recover
   by package ID, never delete files or create a replacement operation.
5. On reopen, reconstruct reservations and owners before new work. An intended
   final file without a committed owner is reconciled against its durable
   intent, not deleted by age. Missing/corrupt files enter `needsAttention`,
   preserve text and identity, and require explicit replacement before fresh
   admission.
6. Discard releases only that owner. Serialize release/acquire with a revision
   and terminal tombstone: once retiring, new acquisition fails. Physical
   deletion requires zero owner edges and zero active leases plus positive local
   writer completion. A writer crash requires reconciliation after process
   restart; lease timeout alone is insufficient. Record deletion success before
   releasing reserved liability; failed cleanup remains recoverable and charged.

These rules require application lifecycle/account-deletion and cleanup
integration; a file-copy helper alone cannot satisfy them. Cross-version server
references, late PUT closure and version deletion races remain separate open CPM
gates. Existing admitted operations keep exact snapshots and recovery semantics.
Old unadmitted drafts without originals require explicit remediation for a fresh
CPM request; never synthesize an original from a preview or silently migrate an
old operation into P1-L1.

## Limits retained without change

| Boundary         | Existing approved ceiling / consequence                                                                                                                      |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Original still   | 33,554,432 bytes each, two physical sources / 64 MiB total; 64 million primary-image pixels. Reject over limit without conversion.                           |
| AI / display     | AI images 5 MiB aggregate / at most five; display 8 MiB aggregate, 4 MiB each / at most five. P1 is still-photo only.                                        |
| Package          | 96 MiB including metadata; 1 MiB manifest/context, 24 file objects and 32 role references. Existing text limits unchanged.                                   |
| Pending local    | Four packages including preparing draft, 384 MiB durable total. Unknown work retains its slot.                                                               |
| Shared temporary | 192 MiB: 96 acquisition/commit, 64 preparation, 32 transfer/export. Real duplicates and interruption leftovers count; no retry allowance reset.              |
| Free space       | Preserve 256 MiB after reservations; maximum new 96+192 MiB allocation requires 544 MiB available. Count existing files once and every duplicate separately. |

No upload/export runs in P1. The shared pool still has to coexist with their
owners; absence of P1 network activity does not make their storage free. A
reservation has a physical allocation ledger, avoiding double reservation of an
existing owned file and avoiding undercounting a second copy. Never assume
clones or hard links consume zero bytes. Reconcile unknown capacity before
admission.

On refusal preserve supporting text, selected source and any already-owned
original. Offer explicit removal/replacement or freeing storage. If an oversized
provider file cannot be retained, preserve selection/error and explain
reselection is required. Do not promise durable original retention before it
succeeds. Interrupted work reuses exact local intent; no re-preparation of
frozen input or provider retry is inferred. Package limits and user experience
are not adjusted to make a feasibility check pass.

## Ownership decision and bounded P1 proposal

History primary remains the sole writer of native ledger, repository, queue
handoff and migration. Capture visual work remains separately owned. The dirty
`+PhotoCapture`, `+VisualSubmission`, `+SubmissionAdmission` and
`CaptureDraftSession` files are user-owned and cannot be replaced. Recommend an
explicit additive handoff restricted to original-reference propagation,
copy/commit/clear sequencing and error handling, preserving crop flow, toolbar,
Add details UI and alternatives-card layout. No second writer is proposed.

Two prerequisites prevent calling P1 execution-ready:

1. **Schema agreement:** exact current alias, schema arrays/stages, affected
   relationship closure and startup/recovery plans must be enumerated; choose
   typed ledger placement and migration. Freeze/compile the outgoing shape
   before changing active models, as required by the migration skill. No guessed
   V59, automatic lightweight-stage assertion, destructive reset or shadow file
   DB.
2. **Capture and cleanup handoff:** inspect the existing image-transfer wrapper,
   preparation/result structs, injected dependency assembly, draft-file cleanup
   and account lifecycle owners to name the complete minimum file list.
   Establish pre-allocation import bounds and protection policy. These were
   beyond the twelve-file cap; they are not assumed correct or available to
   overwrite.

Approve the proposed ledger/ownership direction before that bounded follow-up.
Recommend one maximum two-hour source/contract closure limited to those two
items, with no tests or implementation. It must produce either one exact P1
four-hour implementation/check packet or a concrete incompatible requirement; no
additional transport survey. This is a new proposed scope, not continuation
under the consumed CP-1 read allowance. If the native agreement cannot close,
stop and report the specific conflict rather than repeatedly extending scope.

The intended P1 file families are the listed Staging/Payload/capture/submission
owners; a typed local preparation repository/file-store under Core/Data; active
preparation/asset/reference entities and only the required schema/migration/
startup files; minimal dependency composition; owning acceptance tests and
canonical docs. `PhotoLibraryManager` and `CameraPhotoCaptureCoordinator` need
no change based on this review. Ordinary queue dispatch, inference payloads and
backend code remain outside P1. The exact file list is deliberately not claimed
complete until the two prerequisites close.

## Acceptance plan; no checks executed now

Existing file-copy and hosted transport evidence cannot prove this new ownership
path. New tests are justified only when this implementation exists:

| Check                                         | Measurable pass condition                                                                                                                                                                                 |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Camera/picker source to reopened held package | Original hash/length exact; distinct synthetic original/AI/display stay distinct after crop, queue-like local commit and reopen. No funding/network/AI call.                                              |
| Interruption points                           | Before/after file finalize, owner commit, held-package commit and UI acknowledgement: original recoverable or explicitly unacquired; same IDs; no premature clear, duplicate slot or silent admission.    |
| Boundary refusal                              | Exact cap succeeds when other predicates hold; cap+1, pixel excess, unavailable source and unknown/insufficient capacity fail preserving draft and owned files. Temporary duplicates count.               |
| Owner/cleanup races                           | Both acquire/discard orders, stale completion, deletion failure and restart: surviving reference never loses bytes; retired reference never resurrects; liability released only after confirmed deletion. |
| Legacy compatibility                          | Existing queued/admitted records unchanged, no synthesized originals, no migration into dispatchable new work. Missing original fresh CPM entry is explicit remediation.                                  |
| Inactive composition                          | Ordinary app access remains nil; no runtime flag enables P1, no ordinary scan/job is created by held preparation, no provider/funding calls.                                                              |
| Migration                                     | Real outgoing disk-store migration and startup/recovery paths retain records; no reset fallback; complete MigrationPlanTests plus full affected native gates.                                             |

Existing candidate-specific checks are reused where source/behavior are
unchanged. Proposed new selector `merianTests/PhotoOriginalPreparationTests`
covers the new owner path; extend existing `CaptureWorkspaceSubmissionTests`,
`CaptureWorkspacePresentationAndImportTests`, `CaptureDraftSessionTests`,
`CaptureAdmissionTests` and `MigrationPlanTests` only for changed boundaries.
These are intended selectors, not a claim tests exist or have run. Use the
managed `make ios-local-build` cache, one compilation at a time and no edits
while compiling; no new task DerivedData. All required affected native gates
must pass for a completion claim, even if the four-hour limit means returning
incomplete. No device installation/testing, provider quality or hosted
acceptance is inferred.

Retain 20 GiB checkout headroom and existing evidence. CP-1 adds at most 64 KiB
sanitized evidence/documents within the 512 MiB CPM evidence allowance plus its
reserved cleanup space. Future build/test artifact budgeting must be explicit in
P1; this nearly full experiment allowance is not an implicit XCResult budget.

## Status and review

CP-1 result: `preparation_complete_contract_handoff_required`. P1
implementation, tests and activation remain blocked on the named agreement and
separate approval. HAM-2 method adoption remains intact; no new hosted campaign
is justified or requested. AWS unapproved, limits unchanged, auto-prompts
paused; push, merge, deployment, credentials, device and later redesign
restrictions remain intact. Independent/IC-1 exact-document review and
preservation records are retained in
`.artifacts/client-prepared-media/cp1-result/`.
