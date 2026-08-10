# Insight Content

The `Content` directory handles the display of the core ecological data within
an Insight sheet.

## Purpose

This area is responsible for rendering the detailed biological text, including
the primary ecological description, toxicity warnings, conservation statuses
(IUCN Red List), and the diagnostic visual comparison against confusing
lookalike species.

`BiologicalView` also owns the persistent `FieldTripProgressCard`. It appears
after toxicity and identification-review content and before Field notes and
educational cards when the view model has server-backed contribution rows. The
card shows every credited outing/Event under the visible **Field trips** header.
While eligible contribution rows are loading, the same position is reserved by a
card-shaped, motion-aware skeleton so later content does not jump when the
server response arrives; empty and failed responses still hide silently. The
heading reuses `InsightCardHeader`; its undivided rows use an uppercase **GOAL
COMPLETE** eyebrow, headline-sized goal name, enlarged objective artwork/check
badge, experience-only subtitle, and a prominent trailing `GoalProgressRing`.
The full row is tappable without a redundant chevron and forwards a
card-specific overview destination that deliberately omits Capture's
checklist-item focus. The card does not load data, cache contribution rows, or
trigger celebration effects.

## Scanning presentation

Foreground and queued scans share `ScanningExperienceView`, which owns the
status pill, optional actionable supplemental content, **Did you know?** card,
Field notes, and scan telemetry in that order. This keeps queued retry timing,
errors, and recovery controls ahead of educational content whenever they are
present. Foreground analysis supplies `InferenceEngine.scanningPhaseText`.
Queued scans rotate phrases from their exact queue/server state and reuse
generic engine phrases during active inference.

When a live request loses connectivity after this sheet opens, the required
contract is for the engine to publish the exact durable scan ID and for the
sheet to snapshot that queued row. Existing queued content then replaces
analyzing content with **Queued for later**, plus a saved/automatic-resume
message. This handoff must not create a synthetic **Network timeout** result or
an error haptic, and normal same-ID queued completion must still replace it in
place.

This behavior is release-gated. The current catch path can lose full durable
ownership before it publishes the still-current local presentation, and the
transport helper can replay once before returning the failure. **Analysis
delayed** is now classified as an inference error placeholder, so a saved
service failure does not receive non-biological success treatment; that isolated
repair does not close the transport handoff. See the
[live scan connectivity handoff incident](../../../../../../docs/incidents/2026-08-live-scan-connectivity-handoff-gap.md)
for current status and closure tests.

Queued scans supply snapshot telemetry but do not add a separate title, helper
paragraph, media-kind summary, or file-size label. Retry timing, errors, and
recovery controls are inserted only when actionable. Keep `ScanningStatusBadge`
on the shared pill for UI-test and accessibility stability.

The deterministic queued-audio UI fixture uses that badge as an explicit
post-assertion handoff control. It first proves queued navigation, shared
scanning content, and decoded audio playback, then taps the badge to replace the
exact seeded row with its completed record. Do not reintroduce a fixed delay:
hosted simulator accessibility startup can be much slower than local rendering.
The coordinator performs that transaction on the exact environment
`ModelContext` bound to the open Insight sheet and immediately invokes the
existing production queue-promotion path with the same context. The library
event still refreshes the parent Scans surface; the deterministic transition
does not depend on a cross-context merge. The coordinator is enabled only for
the exact Debug UI-test seed; normal app sessions and Release builds retain
ordinary badge behavior.
