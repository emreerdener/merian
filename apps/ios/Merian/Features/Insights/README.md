# Insights

Insights owns the private result experience for live, queued, and completed
scans. The canonical behavior contract is
[Insight Sheet](../../../../../docs/features-and-hardware/05-insight-sheet.md).

## Ownership

- `Shell/` owns the presentation session, root state, scan binding, typed
  destinations, toolbar assembly, and lifecycle invalidation.
- `Content/` owns biological/non-biological results and analyzing/queued
  presentation.
- `IdentificationReview/` owns candidate and confidence workflows.
- `Media/` owns Insight media ordering, availability, focus, inline video, boost
  preference/telemetry adaptation, and scan-to-export request mapping.
- `FieldNotes/` and `Sharing/` own their named workflows.
- `Toolbars/` owns Insight action composition.
- `Shared/` contains only presentation reused by multiple Insights subareas and
  by no other top-level feature.

Cross-feature declarations must live with a neutral or domain owner. Reusable
media export and playback infrastructure belongs to `Core/Media`; carousel,
gallery, card, toolbar, and feedback presentation belongs to `Core/UI`;
species-level reference presentation belongs to `Features/SpeciesReference`; and
private conversation presentation belongs to `Features/FieldChat`.

## Lifetime and effects

Every mounted Insight starts one explicit presentation session. Every dismissal
path ends it before navigation proceeds. Ending invalidates scan-generation
work, delayed presentation, Field-trip contribution loads, sharing operations,
and retained media save/share tasks. Asynchronous commits must still own both
their operation identity and the active scan generation.

Views and components perform no endpoint work. Live networking, persistence,
SDK, feedback, and platform presentation are adapted in focused `Services`
dependency values. UI-only selection, focus, scroll, gallery, animation, and
dismissal timing remain in views.

## Verification

Mirrored product-area suites live under `MerianTests/Features/Insights`. Core
media/UI suites own extracted primitive behavior, and
`MerianTests/Features/SpeciesReference` owns the relocated species reference
tests. `InsightsIntegrationArchitectureTests` enforces the top-level inventory,
cross-feature owner locations, live-service boundaries, export fencing, and the
600-line production-file ceiling.
