# Integrated identification-history review — October 7, 2026

## Scope and decision

This review covers the accumulated identification-history work in merged PR #115
and draft PR #116, beginning at `eb0d4e7c1`. It follows the
[approved review plan](identification-history-integrated-review-plan-2026-10-07.md).
Three independent read-only streams reviewed native persistence/UX, backend
integrity/privacy, and cross-surface contracts. The primary agent made repairs;
independent re-review checked those changes. No schema, frozen snapshot, wire
payload, production backend behavior or activation setting changed.

All six confirmed findings were repaired and independently re-reviewed. Local
validation is recorded below; exact repair-SHA CI is tracked on
[PR #116](https://github.com/emreerdener/merian/pull/116). Closure requires
those checks to pass, rather than inheriting a prior candidate’s results.
Integrated review completion does **not** establish production readiness.
Schedules remain paused and all activation gates disabled.

## Findings and repairs

| ID    | Severity              | Reachable trigger and impact                                                                                                                                                                                                       | Repair and proving coverage                                                                                                                                                                                                                                                                                                                                                                                              |
| ----- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| IR-01 | High                  | A rejected legacy scan is replaced by a new proposal. `carryRejection` creates `awaitingAcceptance`, but confidence presentation treated every unresolved state as Incorrect, falsely claiming the user rejected the new proposal. | Preserve carry authority and display Review new result separately from explicit rejection and damaged review. Restored-state presentation and audio proposal tests cover the distinction.                                                                                                                                                                                                                                |
| IR-06 | High                  | A retained legacy Accept, Reject, Undo or candidate override fires after the same scan's review changes. Broad capability checks could still allow the action against the newer review.                                            | Capture the displayed review across menu/card/gesture and delayed child handoffs, recheck eligibility, and compare fresh durable authority inside each existing write transaction. A denied write stops UI and cloud work. Retained request, changed-revision Reject/Undo, authority-free confirmation/override and verified-primary tests prove stale actions cannot write; a current proposal creates only one intent. |
| IR-02 | Medium                | A settled species-level legacy proposal has no competitive alternatives. Confirmation eligibility required alternatives, leaving the proposal without an obvious acceptance action.                                                | Offer Accept this identification for an eligible proposal, independent of alternative candidates. Pending, damaged and ineligible states explain the restriction. Audio/no-alternative capability tests cover this path.                                                                                                                                                                                                 |
| IR-03 | Medium                | An enrolled result has a valid receipt-backed rejection Undo. The main menu receives the protected action but the confidence card only permits legacy Undo.                                                                        | Forward the same retained protected action to the card, with Shell and engine scope checks. Both locations explain unavailable reversal. Control and existing exact-receipt/stale-host tests preserve Undo semantics.                                                                                                                                                                                                    |
| IR-04 | Medium                | A child analysis completes while Insight/History/status is open. Persistence appends correctly, but the UI has no completion event and can retain a stale page or hidden history menu.                                             | Publish the existing library-change event only after committed completion and current-owner validation. Recompute menu availability and coalesce list/status refresh, deferring active preview/review/consent/pending selection. Notification, pending-operation, disk-reopen and list refresh tests cover this behavior.                                                                                                |
| IR-05 | Medium, documentation | Current Field Chat and native review contracts describe implemented gated owners as future work. This obscures the release boundary.                                                                                               | Correct current API/owner documentation to distinguish implemented preparation from disabled ordinary access. Preserve historical RFC facts. Documentation/DTO checks and default-off handler regression cover the boundary.                                                                                                                                                                                             |

Principal source evidence is in `InferenceScanReplacement.transferMetadata`,
`IdentificationReviewSyncService.carryRejection/enqueue`,
`ConfidenceBadgePresentation.resolve`, `ConfidenceExplanationSheet`,
`InsightSheetView.confirmReviewAction/confidenceReviewControls`,
`ObservationReanalysisExecutionService.drain`, and the History/status models.
The reviewed source paths are linked from the
[Insight contract](../features-and-hardware/05-insight-sheet.md) and
[review owner README](../../apps/ios/Merian/Features/Insights/IdentificationReview/README.md).

## Reproducible regression selectors

- IR-01:
  `ConfidenceReviewPresentationTests.proposalAndRejectedPresentationRemainDistinctAfterRestoration`
  verifies that restored proposal authority is not presented as a user
  rejection.
- IR-02:
  `InsightShellCapabilitiesTests.audioReanalysisProposalCanBeAcceptedWithoutAlternatives`
  verifies the species-level audio proposal has explicit acceptance without
  alternatives.
- IR-03:
  `ConfidenceReviewPresentationTests.forwardedControlsRejectDelayedSubjectAndPreserveExactUndo`
  verifies forwarded controls remain tied to their original subject; existing
  selected-review receipt tests enforce the original Reject association.
- IR-04:
  `ObservationReanalysisExecutionTests.completedChildSurvivesDiskReopenWithOriginalRejectionAndBecomesDiscoverable`
  and
  `IdentificationHistoryViewModelTests.completionRefreshesListButKeepsOpenExactPreviewUntilBack`
  verify append discovery without authority or active-preview replacement.
- IR-05: `documentation_contract_test.ts` and the protected-send execution-gate
  regression verify current documentation and the disabled routing boundary.
- IR-06:
  `AIIdentificationReviewTests.staleRejectOrUndoCannotRebaseOntoNewerReview`,
  `InferenceReviewCoordinatorTests.staleOverrideCannotAdmitOrPublishOverNewerDurableReview`,
  and
  `CandidateReviewViewModelTests.delayedCandidateDismissalRetainsReviewAndCannotConfirmAfterRevisionChange`
  exercise stale durable writes and delayed clear/rejected handoffs. The same
  focused run covers stale verified and authority-free confirmation.

## Reported Incorrect scenario

The supplied device log identifies an older dirty build based on `3cb005adb`
using legacy identification/review endpoints. This establishes the route, not
the exact saved review payload. The reachable label defect is consistent with
the screenshot; the log alone cannot prove the complete record transition. No
private log content was copied into repository evidence.

Legacy compatibility keeps the original rejected result while the new proposal
awaits explicit acceptance. Prepared history instead appends B as an independent
unreviewed result and leaves A selected. Therefore selected rejected A correctly
remains Incorrect after B completes. Viewing B and selecting B are explicit
actions; selecting B uses B's authority, and returning to A restores A's
rejection. Species-name equality does not transfer authority between IDs.

Existing A→B→A projection tests verify independent authority, retained private
details and denial of delayed revisions. Exact receipt tests verify that Undo
requires A's reversible rejection and never confirms a result. New tests add
display restoration, audio proposal eligibility, delayed control checks,
transactional stale-review denial, append discovery and disk reopen. These are
composed regression tests, not a claim that one real-device end-to-end recording
or physical process-restart test exercised the complete sequence.

The log also reports `PGRST202` for the owned-library-details RPC. This is an
environment/API compatibility observation, not an established cause of the
Incorrect label. No hosted schema-cache repair or deployment was performed.

## Reviewed coverage and limits

- Native: V57→V58 queue discrimination and correction preservation, legacy
  deletion fencing, explicit enrollment, source/media identity, durable
  preparation/execution, append and rollback, account drain, review receipts,
  selected-first paired reconciliation, historical/selected action routing and
  immutable chat/publication preparation.
- Backend: observation/review revisions, one-time dispatch and complimentary
  settlement, exact recovery, immutable ordered media, fixed-expiry copy
  cohorts, binding and revocation, deletion fences, marker erasure, account
  merge and scientific scalar retention.
- Contracts: native/Edge DTO boundaries, ownership and disabled composition,
  endpoint-specific dependency graphs, documentation and release controls.

No additional concrete authority, charge, provider-retry, media-immutability or
erasure defect was established in the bounded backend paths reviewed. This is
not an exhaustive audit of every historical line or every public Explore
consumer. A proposed internal-byte consent finding was withdrawn after checking
the canonical authorization boundary: current processor consent is enforced at
external provider dispatch. No competing policy boundary was added.

Cosmetic cleanup and broader refactoring were deferred. Existing interfaces and
stored schema were retained. The review does not resolve hosted liveness,
storage/CDN behavior or physical-device resource limits by inspection.

## Validation and evidence

- Final shared-worktree native run: **5,392 passed, zero failed or skipped**
  (5,381 unit tests and 11 UI tests), with the critical-result validator
  passing. Result:
  `.artifacts/local-ios/a660fe5b38c346afb7281f1b5a797257.xcresult`. The UI
  selectors cover three History tests, two publication/name-confirmation tests,
  analyzing, live-to-queue, queued retry, queued audio, exact chat identity and
  explicit stale-chat refresh.
- Final focused stale-action run: **89 passed, zero failed or skipped**,
  including 81 Swift Testing cases and eight XCTest architecture checks. Result:
  `.artifacts/local-ios/5a54462037b14e2794fb821415fb9993.xcresult`.
- Full local backend run: **2,714 passed, 425 steps, zero failed; 219 ignored**.
  Database-dependent cases were not enabled in this local run. No database
  object or runtime backend behavior changed. Exact-candidate Supabase CI must
  independently replay migrations and run database/concurrency/security checks.
- All **117 endpoint-specific deployment configurations** and isolated graphs
  checked; recursive Deno formatting/lint, focused protected-send tests, DTO21,
  docs26, full Supabase tooling TypeScript phases and shell scenarios passed.
- Uncached strict SwiftLint, project/migration/event-routing guards and exact
  indexed source membership for all seven targets passed. No frozen snapshot,
  generated-project or activation edits are included in the repair.
- Baseline `eb0d4e7c1` passed all eight workflows, including Supabase Candidate
  Validation304, iOS Build788 and Startup734. These are baseline evidence only;
  the repair commit requires its own current-SHA results.

The findings ledger and local evidence inventory remain under
`.artifacts/identification-history-integrated-review/`. No critical/high or
core-invariant medium finding remains unresolved at source-review level. This
statement does not waive final CI or the separate qualification below.

Agent Quality600 caught missing catalog entries for the two new review RFCs. The
follow-up registers them only as supporting engineering documents and
regenerates the register; no study, dataset or capability assessment changes.
The full local `validate-agent-assets` gate passed after correction.

Failed evidence remains retained: the first added audio fixture used an invalid
test API; the next presentation fixture omitted required authority origin. Both
were corrected. A later full run was intentionally stopped after IR-06 was
confirmed, before its obsolete candidate could be mistaken for final evidence.
Only the review-owned processes were stopped; no other task's build was
cancelled. The synthetic shell launcher initially failed because the sandbox
denied its PTY interaction; the launcher and remaining shell tests passed
outside that sandbox using fake providers and zero API calls.

Local validation uses the shared worktree, which also contains user-owned
changes to capture, maps, profile/Explore, dependency seams, generated project
membership and tooling. Those changes were preserved and excluded from the
repair commit. The overlapping History model contributes separate formatting
edits that are likewise excluded. Local integration results must not be called
clean-candidate results; exact-SHA CI is tracked separately.

## Remaining acceptance

The
[device checklist](../development-guides/24-identification-history-device-review.md)
and retained acceptance artifact separate guided synthetic UI testing from:

- Real V57 install-over, corrected authority preservation and second launch.
- Process interruption/restart and account-switch testing on a device.
- Sustained retained-heap, camera/codec, thermal and memory-pressure behavior.
- Named nonproduction provider/worker deadlines and CPU/heap limits.
- Real R2/CDN revocation/cache bypass and delayed-writer marker races.
- Independently scheduled private/public erasure and backlog monitoring.

The user owns device testing. External execution still needs named-target
authorization. This review authorizes no merge, deployment, hosted scheduling,
activation or TestFlight distribution.

## Undo confirmation addendum — October 7, 2026

This addendum records the separately approved work after the integrated review
above; it does not rewrite that review's original scope or test results.
Implementation `11d3df525` and the reviewed Debug-fixture/test follow-up
`e3aec22eb` add durable primary/name confirmation Undo. The exact validated
candidate is `e3aec22eb17ef85050af17ee8a175ff182e442de` on PR #116. The
[API contract](../backend-and-data/05-api-contracts.md#durable-undo-confirmation)
and
[History owner](../../apps/ios/Merian/Features/Insights/History/README.md#durable-confirmation-undo)
own current behavior. This follow-up adds a forward SQL migration and an action
to the existing closed wire; it makes no SwiftData schema or frozen-snapshot
change. The alternatives card remains unchanged.

Three independent read-only re-reviews checked backend authority/privacy, native
persistence/lifetime/UI and cross-surface contracts. No new confirmed
correctness defect was found. In particular, receipt eligibility compares the
outer target-review revision and current confirmation association, not the
original parent revision or nested AI counter. Recovered native admission does
not require a fabricated local confirmation receipt. Exact saved replay and
paired-state reconciliation preserve selection; Undo never resurrects an older
rejection or reverses community authority.

### Candidate validation

| Evidence                                                                                           | Observed result                                                                                                                                                                                                                             |
| -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Clean iOS Build and Test792](https://github.com/emreerdener/merian/actions/runs/37574162907)      | 5,380 unit tests, critical-result validator, all six exact required UI smokes and unsigned Release archive passed.                                                                                                                          |
| [Clean Startup Safety738](https://github.com/emreerdener/merian/actions/runs/37574162934)          | 169 startup/migration tests passed.                                                                                                                                                                                                         |
| [Supabase Candidate Validation308](https://github.com/emreerdener/merian/actions/runs/37574162892) | Passed on the same candidate; all eight candidate workflows passed.                                                                                                                                                                         |
| Final shared-workspace native run                                                                  | 5,395 units plus six UI tests: 5,401 passed, zero failures/skips; critical validator and exact UI selectors verified. The 15 extra units belong to preserved unrelated workspace changes.                                                   |
| Focused native checks                                                                              | Initial 56 tests across ten suites passed; final correction passed 16 units and three named-confirmation/chat UI tests, zero skips.                                                                                                         |
| Full local backend                                                                                 | 2,940 tests/425 steps; 114 fresh disposable catalogs/1,862 assertions; four new real concurrency cases; 434 migration contracts; all 117 isolated endpoint configurations passed.                                                           |
| Supporting checks                                                                                  | Native/backend tooling, scoped lint/source guards, exact seven-target indexed project membership, DTO21, docs26 and database lint/privilege/advisor error gates passed. Existing advisor warnings remain; this is not a zero-warning claim. |

Local native results are retained in
`.artifacts/local-ios/3d5bf0111c1041578f75f28565e4467c.xcresult` (full) and
`.artifacts/local-ios/282076c32e9e46f9aa23fa643b44f265.xcresult` (final
focused). The evidence inventory and subsequent source-only double-check are
`.artifacts/undo-confirmation/final-validation.json` and
`.artifacts/undo-confirmation/double-check.json`. The double-check reverified
current-candidate CI; it did not rerun unchanged suites.

Failed evidence is retained. The first full run caught outdated expectations for
explicit-opening/failed-save discovery wakes and a Debug fixture that
incorrectly demanded a saved named confirmation on empty discovery. The repair
keeps exact persisted-request checks once work exists; the final full pass
supersedes those failures. A focused invocation was stopped during package
resolution to correct its named-confirmation UI selector, before tests ran. A
synthetic tooling PTY restriction required an unsandboxed rerun; that case and
the remaining shell checks passed without provider calls.

### Re-review limits and activation hold

The
[canonical verification matrix](../development-guides/08-testing-strategy.md#durable-confirmation-undo-verification)
tracks two still-open coverage items: direct primary/named Undo UI taps and
alert behavior, and one cancelled presentation with a surviving joined lookup
waiter. Existing selection-Undo, named-confirmation and chat UI smokes do not
close those items. They are coverage gaps, not confirmed production defects.
Shared lookup continuation after one waiter closes is intentional bounded
coalescing, not an idle lease or account-isolation failure.

Keep all activation gates false, ordinary access nil and schedules paused.
Source validation and this re-review authorize no merge, deployment or
distribution. Field Trip's held downstream reconciliation consumer remains a
separate activation requirement: emitting an obligation does not establish live
credit revocation. Real device migration/restart/heap, hosted runtime,
storage/CDN and independent erasure qualification remain separately open.
