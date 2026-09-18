# Queued Insight Same-ID Handoff Regression

**Date:** 2026-07-30\
**Severity:** Release-blocking\
**Affected flow:** Offline queue / staged scan → completed Insight → Field Chat
/ Share / Explore\
**Repository status:** Remediated on `main` at
`c7eac9c8f3124437712ee72eeff49d09e6ea55b1`; hosted acceptance pending\
**Production status:** Open until a matching iOS build satisfies the closure
gates below

**Scope boundary:** This incident begins after a queued Insight already exists
and covers its same-ID promotion to a completed result. It does not prove that a
live foreground transport failure can enter queued presentation. That earlier
boundary is tracked by the
[live scan connectivity handoff incident](./2026-08-live-scan-connectivity-handoff-gap.md).

## User Impact

A scan could finish while its queued Insight destination was open but fail to
become a fully usable completed result. In the earliest fixture revisions the
screen could remain queued or be rebuilt from a stale queued navigation value
even though a same-ID `LocalScanRecord` had been saved. After direct promotion
was made reliable, the completed result and playable audio appeared, but the
bottom toolbar did not. Field Chat and Share—including deliberate Explore
publication—were therefore unreachable until the user reopened the scan.

The defect is most visible in offline recovery because queue and completed
presentations intentionally preserve one stable scan UUID. It is an iOS
presentation-lifecycle regression, not an alternate AWS backend path; cloud scan
readiness and publication continue to use the Supabase backend contracts.

## Evidence Timeline

- Hosted Run 100 on `8642a8c6d` passed 1,241 unit tests and its exact-SHA
  Release archive, but a fixed four-second Debug fixture timer replaced queued
  UI before the hosted accessibility query reached `ScanningStatusBadge`.
- Hosted Run 101 on `399482b649` passed all unit tests and the archive. The
  explicit badge handshake proved native Back, queued scanning content, and
  decoded audio, then failed because the completed record was written through a
  different `ModelContext` from the open destination.
- Hosted Run 102 on `838533e985` did not execute the UI case after an
  independent cancellation test used executor-yield counting as its URLSession
  rendezvous. Its Release archive still passed.
- Hosted Run 103 on `4f68e68913` passed all 1,241 unit tests, every protected
  critical regression, and the exact-SHA Release archive. The UI case again
  reached the badge and failed at completed-record takeover.
- A local exact-case diagnostic run after correcting child/event ordering
  committed the transaction, promoted **Northern Cardinal**, retained the
  filename-scoped decoded audio control, and preserved native Back. It then
  failed because neither `FieldChatToolbarButton` nor `InsightShareButton`
  existed in the accessibility hierarchy.
- A later exact local rerun after the same-ID toolbar correction again stopped
  at takeover. Its verbose XCTest session log exposed an earlier interaction
  boundary: `ScanningStatusBadge` reported `{{-384.7, 464.0}, {703.0, 36.0}}`
  inside a 402-point-wide app window. XCTest classified that rectangle as
  invalid and synthesized the tap at its fallback visible point, `(5, 482)`,
  rather than on the usable capsule. The queued screen therefore remained intact
  and its audio was still present; this run did not disprove the transaction or
  promotion path because it never reliably invoked the Debug handshake.
- The retained hierarchy also captured the same Button at width 1,406 while its
  visible image and text remained inside the roughly 234-point capsule. Those
  703- and 1,406-point extents track the glare rectangle's negative and positive
  translated animation phases. The decoration was being unioned into the
  ancestor's accessibility frame even while analyzing opacity made it invisible.
- Hosted Run 104 on `2ca985f607` compiled both test bundles, passed all 1,243
  unit tests and all 73 protected cases, and passed its exact-SHA Release
  archive. The UI smoke reached queued navigation, shared scanning content, and
  decoded audio, then deliberately failed before tapping because the badge frame
  remained outside the app window. This proved visual clipping did not remove
  transformed semantic geometry.
- Hosted Run 105 on `6ed0f557b3` passed all 1,243 unit tests, every protected
  critical case, and its exact-SHA Release archive after translated badge
  geometry was replaced with Canvas drawing. The UI smoke opened the queued
  Insight and observed native Back, then failed because `ScanningStatusBadge`
  was not discoverable through `app.buttons`. The new
  `.accessibilityElement(children: .ignore)` modifier had re-composed the native
  control and changed where the caller's identifier was exposed.

Run 105's retained archive evidence is version/build `1.0.2 (235)`, size
239,095,808 bytes, source fingerprint
`6141847844d37a450109e7d2ef2e7bd42512c1fc68991f5b7ef497a9625b2e7c`, verified
main dSYM UUIDs, and no Debug-only seed markers. This evidence applies only to
`6ed0f557b3`; it is not acceptance for the native-control correction committed
at `c7eac9c8f3`.

## Root Cause

Five lifecycle boundaries combined:

1. The deterministic fixture originally used elapsed time, allowing completion
   to race accessibility startup. Replacing that timer with an explicit badge
   handshake exposed the real handoff boundary.
2. The fixture saved through a context other than the one already bound to the
   open Insight, then depended on an asynchronous library event merge. Passing
   the environment context fixed visibility, but the first implementation
   synchronously published the parent event before direct child promotion. A
   parent rebuild could therefore rebind the child from its retained
   `QueuedScanContext` value.
3. Promotion correctly advances `scanBoundActionGeneration` and clears
   result-only UI. The delayed toolbar reveal was nevertheless
   `.task(id: viewModel.persistentScanId)`. Queue and completion share that ID,
   so promotion canceled the queued generation without changing the task key;
   SwiftUI had no reason to schedule a completed-result reveal. Field Notes
   synchronization used the same unsuitable task identity.
4. The shared analyzing badge contained animated `GeometryReader` overlays. One
   exact simulator layout exposed an oversized, horizontally translated
   rectangle as the Button's accessibility frame. Intrinsic sizing, clipping,
   and hiding the decorative child constrained pixels but not the transformed
   semantic geometry. XCTest's ordinary element tap therefore targeted the
   five-point fallback sliver at the window edge instead of invoking the
   deterministic completion request.
5. The first geometry-free revision also re-composed the native Button with
   `.accessibilityElement(children: .ignore)`. Because `ScanningStatusBadge` is
   assigned by the reusable caller, the identifier no longer resolved through
   the native Button query used by the smoke and assistive control semantics.

The individual fixes kept moving the hosted smoke farther through the flow, so
earlier attempts appeared to solve one failure while leaving the next seam
unexercised.

## Resolution

- The Debug-only transaction saves through the exact environment `ModelContext`
  bound to the open destination.
- The child directly invokes the production
  `promoteQueuedScanIfLocalRecordExists` path before it emits typed
  `.scanLibraryChanged` invalidation for parent refresh.
- `bindQueuedPresentationPreferringCompletedRecord` treats a persisted same-ID
  completion as authoritative whenever SwiftUI rebinds a retained queued route.
  If that completion is already the exact bound presentation, the bind is an
  idempotent no-op that preserves its generation and visible result controls. If
  no completion exists, it preserves the queued media and state.
- Delayed result-toolbar reveal and Field Notes synchronization use
  `scanBoundActionGeneration` as their task identity, so an in-place same-ID
  promotion starts fresh result work.
- `revealBottomBarTools` independently requires a non-queued presentation, the
  exact completed local record, a matching immutable toolbar snapshot, scan ID,
  and generation before exposing actions. A stale queued callback cannot unlock
  result controls.
- Once promotion succeeds, the event-driven completion poller stops consulting
  the immutable route value and cannot produce repeated same-ID fetch/log loops.
- `ConfidenceBadge` no longer lays out translated animation descendants.
  Completed-state glare is painted inside a fixed Canvas, label changes use an
  opacity-only content transition, and analyzing state neither instantiates nor
  animates the glare. The native Button receives an explicit label without
  `.accessibilityElement(children: .ignore)`, so the shared caller's identifier
  remains discoverable as a Button after it fixes the control to intrinsic size.
- The exact smoke rejects any badge accessibility frame outside the application
  window before tapping and reports both rectangles, so a future animation
  regression cannot masquerade as a queue-promotion failure.

The fixture remains unavailable outside app-target `DEBUG` compilation and
ordinary Debug sessions cannot activate it without the private UI-test launch
arguments. Release retains only false/no-op signatures, and the archive gate
rejects fixture markers in the shipping binary.

## Regression Coverage

The complete unit result allowlist now protects 73 exact cases. The two added
cases prove:

- a persisted completed record wins over a stale same-ID queued route, advances
  presentation generation, exits processing, binds biological subject and
  toolbar identity, and passes the result-action reveal fence; and
- a queued route remains queued with its media when no completed record exists.

The portable workflow contract also pins child-promotion-before-event ordering,
completed-wins destination binding, generation-keyed toolbar/Field Notes tasks,
the centralized reveal fence, Canvas/opacity-only badge animation, absence of
`GeometryReader`/horizontal offset geometry, absence of synthetic native-Button
recomposition, an explicit accessibility label, exactly one
`ScanningStatusBadge` identifier occurrence bound to
`let scanningStatusBadge = app.buttons["ScanningStatusBadge"]`, intrinsic
scanning-badge bounds, and the diagnostic window-frame assertion. The exact XCUI
smoke still requires native Back, queued badge and fact card, decoded audio
before and after completion, Northern Cardinal takeover, Field Chat, and Share
under exactly one passed, unskipped result.

Hosted Run 105 passed the complete 1,243-unit target and all protected routing
cases on Xcode 26.6, then failed before the frame assertion because the
synthetically re-composed badge was absent from `app.buttons`. Commit
`c7eac9c8f3124437712ee72eeff49d09e6ea55b1` preserves the native Button while
retaining the Canvas/opacity geometry fix and passes the portable workflow
contract and diff validation. A local exact-SHA Xcode 26.6 generic-Simulator
`build-for-testing` compiled and linked the app, complete unit bundle, and UI
bundle for arm64 and x86_64. Asset-catalog/storyboard compilation was excluded
only because workspace sandbox policy denies CoreSimulator user-cache/device
access, so this is source/link evidence rather than local XCUI runtime
acceptance.

## Closure Gates

This incident is closed only when one hosted run on `c7eac9c8f3` or a committed
descendant supplies all of the following:

1. hosted Xcode 26.6 compilation of the app, complete unit bundle, and UI
   bundle;
2. all 1,243 unit tests passed with zero failed or skipped and all 73 exact
   critical cases validated;
3. exactly one passed and unskipped
   `testQueuedAudioScanRetainsAudioAcrossCompletionHandoff` result;
4. a current-SHA Release archive with matching source fingerprint and dSYMs and
   no Debug fixture markers;
5. physical-device recovery of image and audio scans queued fully offline,
   proving the open destination transitions once, retains media, exposes Field
   Chat and Share, and produces no periodic Library reconciliation loop; and
6. the matching Supabase deployment/catalog and joined staging evidence required
   by the normative
   [scan reliability contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md).

Do not waive the XCUI assertions because unit and archive lanes are green. Run
103 demonstrates that those lanes can pass while the user-visible joined handoff
remains broken.

## Historical README Evidence — Retained 2026-09-18

The following July 2026 chronology was moved from the root README without
changing its observations, candidate identities, fingerprints, or verification
limits. It is historical evidence, not a new validation result or a statement of
today's toolchain requirements. Current release procedures live in the
[iOS publishing runbook](../development-guides/14-ios-release-versioning.md) and
[testing strategy](../development-guides/08-testing-strategy.md).

**TestFlight addendum (2026-07-29):** build 1.0.2 (235) exposed a client
state-machine deadlock after `failed_retryable / background_ingestion_failed`.
Media uploaded successfully, but every status preflight skipped the Identify
request required to reclaim the failed generation; upload success also erased
its retry count. A follow-up archive showed the initial single-row latch fix was
insufficient on a migrated store: retry state survived in the durable job while
a drifted queued-scan snapshot restarted at attempt one. Retry authority now
reconciles both copies and advances from their monotonic maximum. A separate
same-session smoke proved new Identify and Explore publication healthy while an
eligible older `media_reconciliation_abandoned` record was rejected by the
terminal repair signer. The tree now preserves one exact retry latch through
re-stage, permits its generation-fenced Identify dispatch, bounds automatic
churn, and allows only authenticated tombstone-free `replay_exhausted` repair,
or `media_reconciliation_abandoned` repair backed by composite service proof: a
post-result dead letter no earlier than the latest charged normal/replay
attempt, evidence shaped for its producer generation, no active reservation or
corrupt timestamp lineage, and no moderation-rejected or
moderation-infrastructure-failed capture lifecycle row. Pre-rollout evidence
narrowly supports the vulnerable producer’s first committed normal attempt; it
must also belong to the immutable exact dead-letter-ID snapshot captured by the
migration, predate the private cutoff, and match the audited multimodal
post-safety error path. The exact snapshot prevents a producer blocked behind
migration DDL from gaining legacy authority through its earlier
transaction-start timestamp. Post-rollout evidence must bind the exact quota
IDs, validated provider result, and completed Identify safety evaluation.
Because the rollout uses two separate migration-file transactions, production
now predeploys fail-closed signing, status, and share consumers before either
file, then deploys the schema-dependent Identify producer only after proof
hardening and service-only readiness checks succeed. Library, scheduler,
reconnect, and URLSession replay wakes now share one process-local driver plus
at most one trailing pass, preventing overlapping status probes, orphan
transitions, retry inflation, and start-log storms. See the
[retry deadlock incident](./2026-07-failed-retryable-scan-status-upload-deadlock.md)
and
[legacy share incident](./2026-07-media-abandoned-explore-share-recovery.md). A
later physical-device smoke also staged and submitted a scan with Wi-Fi and
cellular disabled; it remained queued and completed after connectivity was
restored. This positively exercises ordinary offline replay, but build `235`
predates the remediation and its retained console lacks the transaction-level
sequence, so a fresh globally higher exact-source TestFlight build remains a
release requirement. Hosted iOS Runs 97 and 153 are stale failure evidence for
parent SHA `0aa170fa`: both stopped on two ambiguous offline-sync
`Set(compactMap:)` expressions before test or archive execution. Pushed
descendant `f292dc48` explicitly types every equivalent snapshot as
`Set<String>` and locally passes the complete app/unit/UI `build-for-testing`
product graph under the documented CoreSimulator resource bypass. Run 99 on
exact descendant `631e123e8` subsequently exposed three stale test-contract
expectations; their test-only correction is committed in `8642a8c6d`. Run 100 on
that exact descendant passed all 1,241 unit tests and every protected critical
scan-flow regression, while exposing a fixed four-second Debug-fixture race
before the hosted accessibility hierarchy could observe `ScanningStatusBadge`.
The timer-free handshake is committed as
`399482b649363c820b59fee1967bf94e35a5c0e7`. Run 101 on that exact SHA again
passed all 1,241 unit tests and protected regressions, and its current-SHA
Release archive passed at 239,079,424 bytes for `1.0.2 (235)`, fingerprint
`989544a7bbb531c91673c1949ed676497c6cd08a2028375fc5fc3a73ca7b100c`, with
verified main dSYM UUIDs and no Debug UI-seed markers. The UI smoke now proved
queued navigation, shared scanning content, decoded audio playback, and the
explicit badge tap; it failed only when the seeded completed record did not take
over the already-open sheet. That late Debug transaction used the container main
context while the sheet was bound to its environment `ModelContext`, then relied
on an asynchronous library event to merge the insert. The context-bound
follow-up performs the transaction in that exact context and immediately calls
the existing production queue-promotion path. Release retains a no-op
coordinator, and production queue timing is unchanged. That portion is committed
as `838533e98589f4fca89643e966864a7d59adca05`. Run 102 on that exact SHA did not
reach the queued UI smoke because its complete unit target reported 1,240 passed
and one failed:
`testCancelledExploreShareUsesCanonicalCancellationAndDoesNotReplay` observed
zero requests while expecting the first request. Its fixed loop of 100 executor
yields did not provide a time-bounded rendezvous with URLSession on the loaded
hosted simulator. Commit `4f68e68913fca6276458cd093ad167c9bc7d5d9e` replaces
that loop with a wait of up to five monotonic seconds for the observable first
dispatch, then preserves both exact assertions: one request before cancellation
and still one after cancellation. Run 102's current-SHA Release archive
independently passed at 239,083,520 bytes for `1.0.2 (235)`, fingerprint
`2f79712ff4b08ac6fea2e972e9819c5b9d54a0a46bf4d051a3facaddc1963a30`, with
verified main dSYM UUIDs and no Debug UI-seed markers. Run 103 on exact SHA
`4f68e68913` passed all 1,241 unit tests, every protected critical case, and its
239,083,520-byte current-SHA archive with fingerprint
`99c82c4e68eceb39c0d29db26bfe57236105de25c499dcd1a9acbe3c82e25c0e`. The queued
UI smoke still failed after its explicit badge tap because the seeded completed
record did not take over the queued sheet. A local result-bundle run after
correcting child-before-parent event ordering reached **Northern Cardinal** and
retained decoded audio, then proved the bottom toolbar was absent: queued and
completed states share one UUID, so a toolbar task keyed to that ID did not
restart after promotion advanced the presentation generation. Commit
`2ca985f6079c41c45c6a6e78d382c8283eb0db3b` makes a persisted completion
authoritative over stale same-ID queued routes and keys result-toolbar plus
Field Notes tasks to that generation. Rebinding that stale route after the exact
completion is already visible is an idempotent no-op that preserves the result
generation and controls. A later verbose exact-case rerun exposed an independent
test-interaction defect: the animated scanning badge advertised a 703-point
accessibility frame beginning at x=-384.7 in a 402-point window, so XCTest
rejected the rectangle and tapped its x=5 fallback sliver. Commit
`2ca985f6079c41c45c6a6e78d382c8283eb0db3b` proved that visually clipping those
translated descendants was insufficient: Run 104 compiled both test bundles,
passed all 1,243 unit tests and the 239,112,192-byte Release archive
(fingerprint
`145b2bb7571b18c556bc6e8ff6944b60fdb14e9c85c73896936f978c0886faeb`), then failed
the explicit containment assertion before tapping because the badge still
exposed an off-window accessibility frame. Commit
`6ed0f557b3222890aca55e4c383b2c110ffc8269` removes translated SwiftUI geometry
from the control: completed-state glare is drawn inside a fixed Canvas and label
changes use a bounded opacity transition. Run 105 on that exact SHA passed all
1,243 unit tests, every protected critical case, and its 239,095,808-byte
Release archive (fingerprint
`6141847844d37a450109e7d2ef2e7bd42512c1fc68991f5b7ef497a9625b2e7c`), but failed
earlier in the UI smoke because `ScanningStatusBadge` was no longer discoverable
through `app.buttons`. The queued Insight and native Back control were present.
Re-composing the native Button with `.accessibilityElement(children: .ignore)`
had changed where the caller's identifier was exposed. Commit
`c7eac9c8f3124437712ee72eeff49d09e6ea55b1` removes that recomposition, retains
the explicit label on the native Button, and adds a source guard rejecting its
return. On that exact SHA, a local Xcode 26.6 generic-Simulator
`build-for-testing` compiled and linked the app, complete unit bundle, and UI
bundle for both simulator architectures; local resource compilation and XCUI
execution remain unavailable in the desktop sandbox. The smoke still reports
both app and badge rectangles if containment ever fails again. A hosted run on
`c7eac9c8f3` or a committed descendant must pass the queued completion case
together with the companion live-Insight connectivity-to-queue case and its
current-SHA archive. See the
[queued Insight same-ID handoff incident](./2026-07-queued-insight-same-id-handoff-regression.md).
