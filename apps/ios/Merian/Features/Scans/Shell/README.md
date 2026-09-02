# Scans Shell

`Shell/` is the Scans feature's composition and routing boundary. It coordinates
Library, Collections, Non-biological scans, the private Scan map, and pushed
Insight destinations without moving those product areas' domain behavior into
the root view.

The canonical product behavior is documented in
[Feature Modules and UI](../../../../../../docs/features-and-hardware/07-feature-modules-and-ui.md),
with cross-feature delivery in
[Event and Presentation Routing](../../../../../../docs/system-architecture/10-event-and-presentation-routing.md).

## Ownership boundary

- `Models/ScansShellNavigation.swift` owns the Scans tab and typed navigation
  values plus the minimal authenticated-session snapshot used to fence recovery
  responses. `Models/ExploreMediaIncidentSummary.swift` owns the UI-only,
  deduplicated incident presentation model. Wire DTOs remain in `Core/Network`.
- `Services/ScansShellDataStore.swift` owns fresh-context SwiftData reads,
  queue-to-value projection, completed-row suppression, selected-record lookup,
  and repository-backed deletion. `ScansThumbnailPipeline.swift` owns recovery
  mapping, leading image/audio prefetch, cloud-image repair, reference-thumbnail
  backfill, and the resulting library invalidation. UI-only account preferences
  live in `ExploreMediaOverviewPreferences.swift`.
- `ViewModels/ScansShellViewModel.swift` owns queue snapshot state and polling
  policy, incident loading/coalescing/cancellation/account fencing, overview
  preference state, initial recovery filtering, store synchronization, and
  selected-scan mutations. Its small injected `Dependencies` value resolves live
  app events, authentication, incident networking, time, and badge updates;
  Service-level dependency values resolve repository, loader, actor, and
  invalidation-event integration.
- `Views/ScansSheetView.swift` retains view-only navigation path, pager anchor,
  focus, alerts, animation, and presentation timing. It composes the view model
  and contains no direct endpoint, Supabase, loader, actor, or app-container
  lookup.
- `Components/` owns tab composition, toolbar rendering, and root presentation
  modifiers. Components receive prepared values and actions; they do not load
  data.

Every production file in `Shell/` remains below the 600-line review guard.
`project.yml` includes the source tree recursively, so source membership is
regenerated with `make xcodegen` rather than editing the Xcode project by hand.

## Routing and presentation contract

Cross-module requests arrive as `AppRoute.scansLibrary`, `.nonBiologicalScans`,
or `.scansLibraryRecovery`. The Capture root owns the sole app-level
`.sheet(item:)`; this shell pushes completed and queued Insights inside its
existing `NavigationStack` with `.embeddedInScansLibrary`.

Completed scans use `ScanInsightRoute`, carrying only the stable scan ID. The
private queued route carries a `QueuedScanContext` value snapshot while hashing
and comparing by that ID. This lets the destination survive SwiftData queue
deletion and transition in place when the completed local record appears. The
shell must not layer another sheet over the Library.

Collections pushes the private **Scan map** in the same stack. The root keeps
the semantic `Collections` title behind its segmented toolbar so the map gets a
native **Collections** Back item and edge-swipe behavior. The full contract is
in
[Private Scan Map](../../../../../../docs/features-and-hardware/28-private-scan-map.md).

The Non-biological route pre-seeds its typed destination over Collections. When
Back reveals the root, view-local scroll-proxy logic re-anchors the horizontal
pager after layout so the selected segment and visible page stay aligned. The
Debug-only `-seedNonBiologicalCollectionRoute` fixture covers this path without
shipping test behavior in Release builds.

## Queue, media, and incident contract

`ScansShellDataStore` copies visible queue rows into `QueuedScanSnapshot` values
before any backing SwiftData model can detach. `ScansShellViewModel` owns the
bounded 1.5-second presentation refresh and the state-bearing task identity. It
polls only while at least one visible row can progress under current online,
constrained-network, large-upload, and explicit-override policy. Retry authority
remains in `OfflineQueueManager`.

`ScansThumbnailPipeline` prefetches only the leading 18 scan presentations,
submits deduplicated cloud-image repairs to their serial actor, and delegates
reference-thumbnail work to the actor's bounded pass. It publishes a library
invalidation only after a durable reference-image change; the view does not
invoke shared loaders or background actors directly.

Cross-feature rendering remains in Core UI. `ScanThumbnailLoader` owns the live
image/spectrogram adapters and cancellation fences for reused tiles, while the
thumbnail view restarts work from typed source, policy, pixel-size, placeholder,
and relevant connectivity identity. Shell owns scheduling and durable repair,
not per-tile media loading.

The view model loads authenticated Explore media incidents through its injected
endpoint closure. Concurrent triggers coalesce while preserving one trailing
refresh. The recovery-route owner is validated before a request starts. A
canceled driver cannot replace the last accepted incident state, an
account-replacement trigger remains queued behind the stale request, and the
captured authenticated session is revalidated after suspension before a response
enters UI state. Dismissal is scoped to the normalized account and exact
incident signature. Its live closure calls
`Core/Network/Endpoints/MerianNetworkClient+ExplorePostManagement.swift`;
`ExploreMediaIncidentEndpointTests` owns canonical/legacy decoding and network
compatibility, while Shell tests retain refresh and account-fence behavior. See
the
[post-management matrix](../../../Core/Network/README.md#explore-post-management-verification).
No JSON payload or endpoint contract changed.

## Focused verification

Tests mirror this owner under `MerianTests/Features/Scans/Shell/`:

- `ScansShellViewModelTests` covers navigation, recovery filtering, incident
  presentation/preferences, offline and owner fences, in-flight account changes,
  canceled-response rejection, account-replacement trailing handoff, overlapping
  refreshes, failure-state preservation, and resolved-filter cleanup.
- `ScansShellDataStoreTests` covers queue projection, completed/non-runnable
  suppression, biological and selected queries, selection limits, and injected
  deletion order.
- `ScansThumbnailPipelineTests` covers the leading-media bound, online cloud
  repair, reference backfill, and post-backfill invalidation.

Manual parity covers tab switching and Back re-anchoring; search, filters, and
selection; queued/completed Insight handoff; Scan map routing; incident
refresh/dismissal; thumbnails; VoiceOver; large Dynamic Type; and light/dark
appearance.
