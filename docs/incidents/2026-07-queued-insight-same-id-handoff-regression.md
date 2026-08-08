# Queued Insight Same-ID Handoff Regression

**Date:** 2026-07-30\
**Severity:** Release-blocking\
**Affected flow:** Offline queue / staged scan → completed Insight → Field Chat
/ Share / Explore\
**Repository status:** Remediated on `main` at
`c7eac9c8f3124437712ee72eeff49d09e6ea55b1`; hosted acceptance pending\
**Production status:** Open until a matching iOS build satisfies the closure
gates below

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
  `promoteQueuedScanIfLocalRecordExists` path before it emits
  typed `.scanLibraryChanged` invalidation for parent refresh.
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
scanning-badge bounds, and the diagnostic window-frame assertion. The exact
XCUI smoke still requires native Back, queued badge and fact card, decoded audio
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
