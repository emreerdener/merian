# BI-1: bounded native integration proposal

October 15, 2026 local / October 16 UTC. **Proposal only; implementation and
execution await human approval after independent and IC-1 review.** Activation
disabled, ordinary P1 access nil, AWS unapproved, existing limits unchanged and
auto-prompts paused. This does not authorize push, merge, deployment, hosted
tests, secret installation, device installation or distribution.

## Recommendation and evidence

Request one fresh **two-hour local integration and validation window**,
including review and reporting, with at most **1 GiB additional retained
evidence**. Close three specific NCO-1 blockers: duplicate Auth logic exceeding
existing guards, a capture critical selector that no longer represents the
implemented lifecycle, and the incomplete ownership handoff of uncommitted
baseline prerequisites. History remains the sole implementation writer.
Independent and IC-1 reviewers remain read-only. This is an inactive integration
checkpoint, not P1 or alpha acceptance, and does not absorb the capture-tools
visual refactor or redesign.

The base is `fbf1145d038f6ba167e0f08384ce8cb60978a737` plus the preserved shared
checkout. The
[NCO-1 result](client-prepared-media-nco1-local-result-2026-10-15.md) records
candidate 08 manifest SHA-256
`17623653ad88a33966beee238915d0cfe0c244ff64e8cd946ae80e92c24660a2`. Its managed
build and 18 affected architecture tests passed; the preceding full unit target
had 5,939 passes and four failures. Three factory failures received the narrow
candidate-08 correction; Auth remains unresolved. The full gate has not passed.
The 103 focused NCO passes and failed CI tooling evidence remain valid within
their recorded scope, not as a clean-commit qualification.

Current SupabaseManager is 3,817 lines against 3,792; the aggregate is 13,720
against 13,695. The baseline already contributed eight excess lines and NCO
added 17. The CI mismatch is behavioral: video now starts before scan admission,
so renaming the old waiting-for-admission test would not prove cancellation. NCO
also depends on baseline admission and draft account hooks, not merely the
previously identified `CaptureDraftSession` fields.

## A. Preserve Auth behavior while consolidating existing owners

Only `apps/ios/Merian/Core/Network/SupabaseManager.swift` implementation changes
are proposed:

1. In `beginAuthTransition` and `finishAuthTransition`, replace each repeated
   AppRoute/Milestone controller notification pair with the existing private
   `beginAccountSession(userID:origin:)` helper. Preserve each call's position,
   nil/final account argument, runtime-transition origin, controller order and
   separate timestamp acquisition. Do not move cleanup or admission fences.
2. Keep `activeAnonymousSessionMatches(userId:expectedAuthGeneration:ownedBy:)`
   and its callers. Retain its current-user, anonymous and case-insensitive
   UUID-string guards, then delegate to existing
   `hasCurrentPublishedSession(_:expectedAuthGeneration:ownedBy:)`. Preserve
   cancellation, published authentication, SDK expiry, both account identities,
   anonymous state, generation and active-transition ownership fences. Both
   helpers execute synchronously on MainActor; introduce no suspension point.

The source estimate is approximately 32 fewer lines, leaving about seven lines
under both caps on this shared baseline. Actual counts and semantic equivalence
must pass; the estimate is not evidence of acceptance. No thresholds increase,
file splitting, whitespace removal to evade counting, visibility widening or
broader Auth hardening is authorized.

Update only delegation-sensitive assertions in
`apps/ios/MerianTests/Core/Network/Endpoints/CoreNetworkIntegrationArchitectureTests.swift`.
Assertions must prove that the canonical helper retains every fence, delegation
is required and notification order remains unchanged. Keep all caps and security
invariants. Reuse existing Auth bootstrap, purchase handoff and P1 drain tests;
do not introduce live SDK authentication or new public testing seams.

## B. Replace stale CI coverage with a real lifecycle assertion

In
`apps/ios/MerianTests/Features/Capture/Scan/CaptureScanDependenciesTests.swift`,
add `testLifecycleInterruptionCancelsPendingVideoStartupWithoutAdmission` using
the existing injected `CaptureScanCameraDependencies.recordVideo` closure. A
controlled test-only continuation enters `recordVideo` but withholds its started
callback, then returns a late result even after cancellation. This exercises
pending startup, before `isVideoRecording` becomes true. No production
dependency API expansion is needed.

Measurable pass criteria:

- Request recording while admission is unavailable; the camera dependency is
  entered, its started callback remains withheld, and admission call count stays
  zero. Retain `videoStartsWithoutWaitingForScanAdmission` separately.
- Interrupt through `handleVisualCaptureInterruption`; `cancelVideoRecording`
  count increments, `stopVideoRecording` count stays zero and recording/capture
  UI clears. No scan is queued or AI request initiated.
- Release the late recording result: no media preparation, camera-roll save,
  staging or automatic submission occurs; its owned temporary file is removed.
- Start a newer draft generation before late completion and prove that it is
  neither cleared nor mutated. Retain the existing account-change coverage.
- Preserve the separate started-recording contract: after its callback sets
  `isVideoRecording`, interruption requests **stop**, allowing completion; it
  does not request cancellation. Already-completed recording preparation also
  retains its existing interruption behavior. Assert this distinction in the
  same test file without changing production lifecycle semantics.

The critical selector and its semantic description change together in:

- `scripts/validate-ios-critical-test-results.sh`
- `scripts/test-ios-build-and-test-workflow.sh`
- `scripts/test-validate-ios-critical-test-results.sh`

Positive fixtures must contain the new required selector. A negative fixture
omitting it must fail. Keep all unrelated required selectors and failure checks.
Do not substitute a test that only proves recording starts.

## C. Explicit baseline integration and commit ownership

Approval would hand the primary a narrowly specified integration responsibility
for the existing account/capture prerequisites below, plus the already-reviewed
NCO delta. It would not transfer ownership of the other 115 baseline changes.
Use HEAD-to-baseline and baseline-to-NCO comparisons separately; the retained
`candidate-08-native-on-baseline.patch` is not a patch against HEAD.

Paths in this table are relative to `apps/ios/Merian/`. Adopt only the described
existing baseline hunks; no broader runtime redesign is proposed.

| Path                                                                                         | Proposed baseline handoff                                                                                                                                                                         |
| -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Features/Capture/Staging/Models/CaptureDraftSession.swift`                                  | Ownership enum/state, account ID, bind-once and allows-account APIs.                                                                                                                              |
| `Features/Capture/Submission/Services/CaptureSubmissionDependencies.swift`                   | `accountID` and `isLibraryAccessBlocked` closures and live bindings. Cached identity establishes local draft ownership only; never request authority.                                             |
| `Features/Capture/Shell/ViewModels/CaptureWorkspaceViewModel+Draft.swift`                    | Account-current predicate, bind helper, account-change retirement, operation/description binding, completion and audio account fences needed by the NCO modifications.                            |
| `Features/Capture/Shell/ViewModels/CaptureWorkspaceViewModel+Staging.swift`                  | Account/recovery-aware automatic arming and `allowingPendingQueue` cleanup parameter.                                                                                                             |
| `Features/Capture/Submission/ViewModels/CaptureWorkspaceViewModel+SubmissionAdmission.swift` | Recovery/account checks before and after awaiting admission; preserve drafts when admission is blocked.                                                                                           |
| `Features/Capture/Shell/ViewModels/CaptureWorkspaceViewModel+Refinement.swift`               | Existing two recovery guards and account binding before refinement staging, preserving the same account-safety contract. No refinement feature or UI changes.                                     |
| `Features/Capture/Shell/ViewModels/CaptureWorkspaceViewModel+Routing.swift`                  | Existing recovery guard on account-owned scan/refinement/history routes. No new routing behavior beyond the retained baseline hunk.                                                               |
| `Features/Capture/Shell/Modifiers/CaptureWorkspaceOrchestrationModifier.swift`               | Only the existing current-user and auth-generation observer calls to `handleDraftAccountChange`; exclude all viewfinder/animation/presentation changes.                                           |
| `Features/Capture/Scan/ViewModels/CaptureWorkspaceViewModel+PhotoCapture.swift`              | Existing removal of pre-capture admission and current-account completion guard, alongside the reviewed inactive P1 branch.                                                                        |
| `Features/Capture/Scan/ViewModels/CaptureWorkspaceViewModel+VideoCapture.swift`              | Existing start-before-admission flow and account/draft/generation completion fences that the replacement critical test exercises. No new video capability.                                        |
| `Features/Capture/Submission/ViewModels/CaptureWorkspaceViewModel+VisualSubmission.swift`    | Existing late failed-queue cleanup for superseded draft generations, alongside inactive P1 held submission.                                                                                       |
| `Models/Schema/.swiftlint.yml`                                                               | Existing frozen-schema namespace nesting allowance of two, unchanged; identify it explicitly as a build prerequisite rather than silently depending on an untracked file. No new lint relaxation. |

Also include the existing bind-once test in
`apps/ios/MerianTests/Features/Capture/Staging/CaptureDraftSessionTests.swift`
and the relevant capture/account tests in `CaptureScanDependenciesTests.swift`.
These are baseline integration hunks, not newly claimed NCO implementation.

Before implementation, reviewers must confirm the complete symbol and semantic
closure of this list. Missing prerequisites require a concrete amended handoff
and review; never stage whole dirty files to make the dependency disappear.
Preserve unrelated `hasCachedSessionAwaitingRefresh`, viewfinder dependency and
photo-library presentation changes outside the selected commit. Refinement UI,
maps, alternative-card layout, deployment configuration and backend edits are
not part of this proposal.

The existing early P1 return in `submitStagedCapture` must remain before
ordinary admission. Manual and automatic P1 submission both freeze only a local
held package; retain `automaticSubmissionFreezesOnlyLocalPackage` and its
zero-admission assertion. No new automatic-submission behavior or additional
diagnostic run is proposed for this already-covered invariant.

`project.yml` stays authoritative and unchanged unless a specifically identified
manifest correction is reviewed within an amended boundary. Run `make xcodegen`
and review its output; never hand-edit the generated project. Stage only
generated membership corresponding to approved source hunks. If unrelated
generated membership cannot be separated reproducibly, retain the patch and
report the specific blocker rather than committing an incoherent graph.

A reviewed local checkpoint may combine these prerequisites with NCO in one
coherent commit. Do not stage or commit unrelated baseline content. Record the
selected tree/diff and remaining dirty-path inventory for independent and IC-1
review before commit. Shared-checkout runtime results must remain labeled as
such: managed `--isolated` isolates DerivedData, not source. This proposal does
not authorize another checkout's dependency download, a cache-sharing workaround
or a new build runner to claim isolated source qualification.

## Execution order and acceptance, after approval only

1. Record the fresh two-hour start/deadline, unchanged source hashes,
   active-build state and disk headroom. Keep at least 20 GiB free. Preserve all
   existing evidence and the 115-file baseline inventory; no evidence or
   dependency deletion to meet the new 1 GiB allowance.
2. Implement A/B and assemble the reviewed C hunk closure as the sole writer.
   Synchronize Auth/Capture ownership and CI documentation. Obtain independent
   and IC-1 exact-candidate concurrence before runtime validation. Corrections
   invalidate affected review and require re-review.
3. Run focused selector/validator fixtures, affected architecture/security and
   capture/account lifecycle checks, then the affected full tooling gate
   `make test-ios-ci-tooling`. Reuse unchanged passing migration/tooling
   evidence where source and inputs are identical; never relabel the failed
   aggregate.
4. Use the managed checkout-local build/cache for compilation and one complete
   unit target at this coherent milestone. Changed Auth/capture behavior and the
   known failed full gate justify this run. Preserve raw aggregate and
   per-device XCResult counts separately; do not conceal the previous
   discrepancy.
5. If time, evidence and earlier gates permit, run the six existing critical UI
   smokes from the iOS workflow and generic unsigned Release compilation through
   supported managed commands. Archive is outside this wrapper's supported
   scope; do not bypass it. Device acceptance stays user-owned. Unfinished
   required gates remain explicit blockers, not deemed passes at timeout.
6. Review the exact final diff, dependency closure, evidence and preservation
   report independently and with IC-1. Commit only a coherent reviewed local
   checkpoint. A commit does not authorize push or make dirty-checkout evidence
   equivalent to exact clean-source qualification.

Do not edit sources during compilation, duplicate/cancel managed builds or start
another gate that cannot reasonably fit the remaining window. At expiry, stop
adding work, let an already-running managed build finish safely, retain its
evidence and report incomplete scope. A new blocker outside the named boundary
requires a concrete proposal rather than automatic scope expansion.

Auth acceptance requires both unchanged line caps and unchanged security/order
invariants. CI acceptance requires the actual interruption/late-completion test
and a missing-selector negative failure. Integration acceptance requires every
referenced API/configuration/project member in the selected tree, preserved
unrelated hunks and accurate validation provenance. A missing closure item or
failed full gate prevents declaring the checkpoint qualified.

## Documentation and review boundary

This proposal is the canonical owner of BI-1 scope. Synchronize status pointers
in the NCO agreement, alpha roadmap, IC-1 and the three continuation/capability/
acceptance summaries; retain historical results. After implementation approval,
the documentation boundary additionally includes Network and Capture
Scan/Shell/Staging/Submission READMEs, testing strategy and staged-capture
review where the chosen ownership and selector changes require it. No broad docs
churn.

No new backend, native schema version, media limit, provider/funding behavior or
activation authority is granted. Missing media still blocks fresh submission;
historical/admitted operations retain their meaning. Unknown AI execution
permits only recovery of the original operation, never another invocation or
refund. P1 installed/mixed-allocator acceptance, audio/video preparation, server
admission, integrated history, deletion/export and redesign remain separate open
gates.

Independent and IC-1 review receipts will identify the exact proposal hash and
source inventory. Review concurrence approves the proposal's fitness for human
approval; it is not execution permission.
