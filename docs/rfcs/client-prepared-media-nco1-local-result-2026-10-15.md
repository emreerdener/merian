# NCO-1 local implementation result: acceptance remains open

October 15, 2026 local / October 16 UTC. This records the approved four-hour
local window, 23:17:59–03:17:59 UTC, and the human-approved validation-only
extension for the migration/startup scripts. Work stopped at the bounded
checkpoint below. Activation remains disabled, production P1 access nil, AWS
unapproved, existing media/package/storage limits unchanged, auto-prompts
paused.

## Implemented locally

The outgoing V58 graph was frozen and compiled before active-model edits. V59
adds four standalone scalar ownership entities, with no legacy-model field or
relationship change and no backfill of originals. The inactive P1 owner retains
original bytes before draft release; separates original, AI and display roles;
persists allocation and writer liabilities; freezes a held package; and
preserves account fencing, restart reconciliation and shared-asset cleanup
authority.

Capture uses an optional, nil-by-default handoff. Original acquisition precedes
existing image preparation. Manual/automatic submit can freeze the local held
package in qualification without enqueuing inference, claiming funding or
creating a server admission. Restored ordered context, missing-original refusal,
inbox retention, crop identity and explicit discard are covered by local tests.
Library inventory includes all four entities; purge fails closed without its
owner, and the optional Auth drain waits for actual local completion.

The approved validation-only extension changed these four scripts, preserving
historical checks and adding V58/V59 coverage:

- `scripts/check-ios-migration-source-guardrails.sh`
- `scripts/test-check-ios-migration-source-guardrails.sh`
- `scripts/ci-detect-startup-safety-source-changes.sh`
- `scripts/test-ci-detect-startup-safety-source-changes.sh`

No architecture thresholds, runtime media limits or activation settings were
changed by that extension.

## Exact candidates and results

Evidence root: `.artifacts/local-ios/nco1-20261015/`. Every failed run is
retained. These are shared-checkout results, not a clean/isolated commit
qualification.

| Check                              | Result and evidence                                                                                                                                                                                               |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Outgoing V58 freeze                | Managed build passed before V59 active-model edits; retained freeze evidence.                                                                                                                                     |
| Candidate 07                       | Manifest SHA-256 `6ffec2c40082bd17a8a83070d7b61cbedcb73d0599732d7798d2c212fe5e45a0`; managed build passed.                                                                                                        |
| Focused native lifecycle/migration | Candidate 07: **103 tests passed**, seven suites, zero failed/skipped. `candidate-07-test-summary.json`; reused unchanged passing coverage.                                                                       |
| Complete unit target               | Candidate 07: **5,943 total, 5,939 passed, four failed, zero skipped**. `candidate-07-full-unit-summary.json` and full log. Full affected gate remains failed.                                                    |
| Candidate 08                       | Manifest SHA-256 `17623653ad88a33966beee238915d0cfe0c244ff64e8cd946ae80e92c24660a2`; managed incremental build passed.                                                                                            |
| Corrected architecture suites      | Candidate 08: **18 tests passed**, zero failed/skipped, across StoreRecoveryArchitectureTests, CoreIntegrationArchitectureTests and IOSHygieneClosureArchitectureTests. `candidate-08-architecture-summary.json`. |
| Migration source guard             | Passed on candidate 08; guard regression and startup scope-detector tests also passed during this window.                                                                                                         |
| CI tooling aggregate               | Failed on the pre-existing capture selector mismatch described below. The aggregate is not green.                                                                                                                 |
| Other source/tooling checks        | Project/resource, event routing, privacy, transport, versioning and focused diagnostics/validator checks passed as recorded in the retained logs. Unchanged passes were not repeated without cause.               |
| UI / Release / archive / device    | Not completed for this checkpoint. UI/Release runs held after the full-unit failure. Managed wrapper does not authorize archive; no bypass. Device qualification remains user-owned.                              |

The table uses the XCResult summary's top-level aggregate counts. The raw
full-unit summary also reports 9,384 passed tests in its per-device field, which
does not match the top-level 5,939 passed count. That per-device field is not
used for the reported verdict; the raw summary, full log and XCResult remain
unchanged for inspection. No normalization or reconciliation of that count
discrepancy is claimed. Parameterized-test/device counts are not silently
substituted for the top-level totals.

Candidate 08 changes only the V58/V57 factory argument formatting relative to
07; plan, name, diagnostic argument and fallback order are identical. Reversing
that reflow reproduces 07's exact factory hash. It restores the factory to 599
physical lines / 600 under the final-newline-aware guard and fixes the three
factory-related failures without changing their thresholds. The complete unit
target has **not** been rerun or relabeled passed after this narrow correction.
The unchanged Auth failure remains open.

Candidate 08 also records the previously implicit, unchanged
`CaptureDraftSession.swift` baseline prerequisite as a verification dependency.
It does not claim that this source was in candidate 07's 53-file manifest.

## Remaining shared-checkout blockers

1. **Auth architecture budget.** The preserved baseline SupabaseManager had
   3,800 lines against a 3,792 cap. NCO adds 17 lines for its optional drain,
   producing 3,817; the aggregate is 13,720 against 13,695. Both the inherited
   eight-line excess and NCO's contribution are recorded. This is not wholly an
   unrelated failure. No threshold increase, unrelated Auth refactor or move
   solely to evade counting was made. A separately reviewed ownership/baseline
   correction is required before the full gate can pass.
2. **Stale critical capture selector.** `make test-ios-ci-tooling` expects
   `testLifecycleInterruptionCancelsVideoWaitingOnAdmission`, absent from the
   preserved baseline `CaptureScanDependenciesTests.swift`. That baseline
   instead includes `videoStartsWithoutWaitingForScanAdmission`. A simple rename
   would not establish equivalent lifecycle coverage. Reconcile the intended
   capture behavior and critical-test contract under its owner before changing
   `test-ios-build-and-test-workflow.sh`,
   `validate-ios-critical-test-results.sh` and
   `test-validate-ios-critical-test-results.sh`. These are outside this
   extension.
3. **Standalone commit prerequisite.** P1's draft integration uses baseline
   `CaptureDraftSession.ownership`, `bindAccount` and `allowsAccount`, absent at
   HEAD `fbf1145d0`. Its source/test and generated project contain other pending
   work. A standalone NCO-only commit would omit required APIs or absorb
   unrelated edits. No such commit was made. Resolve that baseline integration
   ownership first; do not call the shared-checkout build an isolated pass.

The native delta is retained as `candidate-08-native-on-baseline.patch` plus
`candidate-08-reviewed-source.tar.gz` and `candidate-08-retention.json`. The
patch is explicitly against the preserved pre-NCO shared baseline, not HEAD.
Original baseline copies/hashes remain in the evidence directory and the earlier
115-file inventory. No full-file staging or discard of unrelated work occurred.

The agreement says: “If implementation discovers an incompatible schema/source
change or exceeds this exact file boundary, stop with that concrete conflict.”
The four-script approval does not transfer the additional capture/Auth baseline
or CI selector ownership. Stop here with these blockers; do not invent another
feature slice or rerun unchanged failed gates.

## Review, evidence and remaining product gates

Independent read-only review and IC-1 concurred on candidate 08 before its build
and three-suite run. IC-1 turn: `01a14236-178c-70a3-944f-4b193ecfe1e6` in
`01a112ae-2c97-77a1-bd53-5a4434510d4c`. Exact review and commit-dependency
findings are retained in `candidate-08-review-before-execution.json`. Final
result review is recorded separately with the evidence after documentation
synchronization.

Managed checkout-local caches were reused; no build was duplicated or cancelled.
SQLite fixtures were retained after tests rather than unlinked while containers
still held open descriptors. The evidence inventory accounts for task artifacts,
XCResults and retained P1 fixtures; it remains below the approved 2 GiB cap.
Disk headroom remained above the 20 GiB floor. See the final budget receipt for
exact retained totals and its accounting boundary.

This does not close P1 or integrated acceptance. Installed mixed-allocator
reservation, native device codec/memory/file-protection qualification, server
admission and reference accounting, audio/video preparation, integrated history,
version deletion/export and the later redesign remain in their approved order.
The detailed capture-tools visual refactor stays separately owned. No new hosted
transport experiment is justified by these native changes. No push, merge,
deployment, installed-device action, credential change or AWS operation
occurred.
