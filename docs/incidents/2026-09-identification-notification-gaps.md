# Incident: Missing identification-success notifications

- **Date detected:** 2026-09-17
- **Status:** Mitigated in source; candidate and device validation pending
- **Affected versions/environments:** Repository paths confirmed; affected
  shipped versions and user counts unknown
- **Affected surfaces:** iOS Capture, background result recovery, notifications
- **Current contract:**
  [Insight notification delivery](../features-and-hardware/05-insight-sheet.md#push-notification-delivery)

## Summary

A report of missing identification-success alerts led to two source findings.
Discovery alerts default to disabled, but the first-result opt-in was attached
to an inner binding that native Insight dismissal bypassed. Separately,
server-result recovery committed the local result and removed its queue row
without scheduling an alert or updating the unseen-scan badge.

## Impact and detection

The permission gap affects users who close Insight through its normal Close
action or swipe. The recovery gap affects completed server results obtained by
reconciliation, watchdogs, or retries, including users with Discovery alerts
enabled. This scope follows code paths; no production counts or device-delivery
measurements were collected. Existing foreground suppression while Insight is
visible is intentional and remains unchanged.

## Timeline and reproduction

On 2026-09-17, source tracing confirmed the Close action calls SwiftUI
`dismiss()`, while the permission prompt existed only in the child's
`isPresented` setter. The outer sheet's dismissal handler did not offer it.
Tracing `recoverFoundScanFromServer` confirmed successful queue deletion led to
milestone processing and library updates without notification effects.

Regression fixtures reproduce the root dismissal state transition without
writing the child binding. Notification fixtures use an injected system center
and synthetic species/scan values. Successful recovery admission is checked by
source ordering, not an end-to-end network/SwiftData recovery run.

## Root cause and repository mitigation

`CaptureWorkspaceViewModel.handleRootSheetDismissed` now offers the one-time
opt-in after a completed non-error Insight closes. It excludes processing
results and enabled/previously prompted preferences. Pending navigation takes
priority without marking the prompt as offered.

Direct background completion and recovery now share
`BackgroundScanNotificationService`. Recovery invokes it after exact-owner queue
deletion succeeds and before milestone processing suspends. It preserves
Discovery-alert opt-out, foreground suppression, unseen-scan badge behavior, and
the existing manager's scheduling deduplication.

## Regression coverage and candidate validation

- `CaptureWorkspaceViewModelRefinementTests`, extended by
  `CaptureWorkspaceNotificationPromptTests.swift`: completed dismissal,
  duplicate callback, previous decline, already enabled, incomplete/error
  result, other sheet, and competing local/global navigation.
- `BackgroundScanNotificationServiceTests`: enabled/suppressed combinations,
  duplicate completion, and retry after notification scheduling failure.
- `BackgroundInferenceArchitectureTests`: both background callers admit
  notifications after successful queue cleanup and before milestones.
- XcodeGen regenerated the project with the new service and test memberships.
- Swift syntax parsing for changed sources, full strict SwiftLint, generated
  project validation, event-routing guards, changed-Markdown formatting, and
  whitespace checks passed. These are static checks, not compiled test results.
- The focused simulator test command was attempted through
  `make ios-local-build`; its process-inspection preflight was denied by the
  session sandbox. Compilation, focused/full unit tests, and device checks
  remain pending. Source checks cannot establish runtime delivery.

## Production deployment and runtime verification

**Not performed.** No release operation or hosted mutation was requested.
Physical-device checks must cover first-result Close/swipe, native allow/deny,
enabled/disabled alerts, direct and recovered results while locked, foreground
suppression, duplicate completion, badges, and tapping an alert.

## Data recovery and privacy

No scan-data repair is proposed: the missing effects follow result persistence.
Historical missed alerts are not replayed. No credentials, personal data,
coordinates, session state, or production response bodies appear in this record
or its fixtures.

## Exit criteria and follow-ups

- [x] Both repository failure paths and their owners are identified.
- [x] Source mitigation, regression fixtures, and current contracts are updated.
- [ ] iOS owner completes focused/full tests and candidate compilation.
- [ ] Release owner determines affected shipped versions and deployment need.
- [ ] iOS owner verifies the physical-device delivery matrix.
- [ ] Production impact and closure are assessed from sanitized evidence.

## Dated corrections

On 2026-09-17, the subsequent default-preference change made Discovery alerts
enabled when no saved value exists, preserving all stored choices. The initial
disabled default described above is historical. The post-result prompt now
requires enabled Discovery alerts and missing system authorization, so the new
default does not bypass the native permission flow. Saved opt-outs suppress the
automatic prompt. See the current notification contract linked above.
