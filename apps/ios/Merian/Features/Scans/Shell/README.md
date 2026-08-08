# Scans Shell

The `Shell` directory acts as the root container and routing layer for the entire Scans feature.

Cross-module requests to open this feature arrive as `AppRoute.scansLibrary`,
`.nonBiologicalScans`, or `.scansLibraryRecovery`. The Capture root owns the
sole app-level `.sheet(item:)`; this shell pushes Insight destinations inside
its existing navigation stack and never adds another app-level sheet.

## Structure

- **Views**: Contains the top-level container views that host the tab bar or navigation stack for the scans area.
- **Modifiers**: Navigation and routing modifiers that manage sheet presentations or full-screen covers within the context of the scans feature.

## Purpose
Following the Merian iOS architecture guidelines, the `Shell` isolates routing, layout chrome, and tab-level coordination. It seamlessly switches between the `Library`, `Collections`, and `NonBiological` areas, keeping those individual product areas focused strictly on their respective domain logic and UI.

Completed and queued scans both open as pushed Insight destinations in the
Scans sheet's existing navigation stack with
`.embeddedInScansLibrary`. Completed scans use `ScanInsightRoute`, carrying only
the stable scan ID. The private queued route carries `QueuedScanContext` but
compares and hashes by that ID. This value snapshot lets the destination stay
open through SwiftData queue deletion and transition in place when the
completed local record appears. Both routes use native Back behavior; the
Scans shell must not layer another sheet over its library.

Batch save progress is a compact bottom capsule that permits hit testing to
pass through outside the capsule. Share, download, delete, and selection
mutations are disabled while the batch snapshot is being exported. Success and
failure toasts use identity-checked cancellable teardown so a stale timer cannot
clear replacement feedback.

`ScansSheetView` owns the bounded queued-row refresh task. Its identity contains
both durable row state and live path policy, and it starts only when at least
one visible row can make progress under the queue worker's current
online/constrained/large-upload rules. Path-ineligible rows stay visible but
quiet instead of producing a periodic Library kick/log loop.
