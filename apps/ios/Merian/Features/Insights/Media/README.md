# Insight Media

The `Media` directory manages the mixed-media presentation associated with a
scan.

## Purpose

This area drives the interactive mixed-media carousel at the top of an Insight
sheet. It combines live capture images, persisted image/video/audio/description
pages, and reference imagery such as GBIF or Wikipedia photos into one ordered
viewing experience.

The canonical behavior and product contract remains
[`docs/features-and-hardware/05-insight-sheet.md`](../../../../../../docs/features-and-hardware/05-insight-sheet.md).

## Ownership

`Carousel/ImagesCarousel.swift` is the Insight composition entry. Its
collaborators are organized by responsibility:

- `Carousel/Models/` owns deterministic Insight focus, selection, image-origin,
  and availability values. The model-owned `CarouselSelectionCandidate` contract
  lets selection policy consume only IDs, image identifiers, and source families
  rather than the SwiftUI-backed page value. Models do not import SwiftUI or
  UIKit or name view-backed page types.
- `Carousel/Builders/` converts `ActiveScanMedia` into ordered inline and
  fullscreen page values and applies transient availability policy.
- `Carousel/Services/InsightMediaPlaybackDependencies.swift` adds only the
  Insight feedback namespace and audio-boost telemetry adapter to the shared
  `MediaPlaybackDependencies` value.
- `Carousel/Playback/` owns the Insight inline-video surface and the stable
  coordinator that pauses it before fullscreen presentation.
- `Carousel/Pages/` owns Insight description and live-capture pages.
- `Carousel/Components/` owns render-only chrome, controls, analysis overlays,
  and focus gestures. `Carousel/Animation/` owns the time-derived analysis
  session and sweep policy.

The domain-neutral pager, page value, zoom host, pagination dots, hero
scroll-edge treatment, fullscreen gallery, audio page, and reusable video chrome
live in `Core/UI/Components/MediaCarousel`. Audio-session restoration, the
main-actor audio delegate, shared playback dependencies, and bounded export
processing live in `Core/Media`. `CarouselPageItem` remains Insight-owned and
projects its image-origin, still-source, and focus identity into the Core page
reuse key. Presentation-only view changes keep the mounted controller; an
image-origin, source-index, or focus-identity change remounts that page and
forces the native pager to discard cached neighbors.

The carousel performs no networking. Remote reference images continue through
the cross-feature `Core/UI/Components/AsyncLocalImageView` boundary, whose live
`LocalImageLoader` adapter is isolated in `Core/UI/Services`. Existing
entry-point initializers retain their arguments; an optional trailing dependency
seam defaults to the live adapter. Every production Swift file under `Carousel/`
stays at or below the 600-line review guard.

## Regression ownership

`InsightMediaAvailabilityTests` owns availability ordering and selection
fallback. `InsightMediaGalleryTests` owns mixed-media/fullscreen mapping, the
Insight reuse-key projection, the Core page's ID-only default, and data-source
reset when a reuse key changes. `InsightMediaFocusPresentationTests` owns focus
and animation policy; `InsightAudioBoostPolicyTests` owns the Insight-specific
availability and preference rules. Core `AudioPlaybackPresentationTests`,
`AudioBoostRequestStateTests`, and `MediaExportServiceTests` own shared
playback, overlap fencing, source mapping, and export request behavior.
`InsightMediaExportLifecycleTests` proves an uncooperative save/share completion
cannot publish after dismissal, while `InsightMediaCarouselArchitectureTests`
and `InsightsIntegrationArchitectureTests` lock the folder boundary, private
playback state, Core extraction, and 600-line ceiling. Pair those suites with
`FieldTripFeaturedMediaTests` whenever the shared pager or reuse contract
changes. `AsyncLocalImageDependenciesTests` remains under Core UI because it
tests the cross-feature loader seam rather than Insight behavior.

## Export and presentation lifetime

`Media/Utilities/InsightSheetViewModel+MediaExport.swift` maps the active scan
to Core `MediaSaveRequest` and `DiscoveryShareRequest` values. It owns one save
task and one share-preparation task, each fenced by operation UUID, scan ID, and
the sheet's presentation generation. Every dismissal path ends the presentation
session, cancels those tasks, and clears their operation IDs before navigation
continues. A dependency that ignores cancellation therefore cannot show stale
feedback or a share sheet over the next Insight.

Photo-library work, approved `media.merian.app` downloads, bounded image
downsampling, and batch request processing belong to `MediaExportService` in
Core. The feature view model performs no PhotoKit, URLSession, share-sheet, or
singleton work.

External reference URLs are normalized through
`ExternalReferenceImagePolicy.allowedURLStrings(from:)` before carousel pages
are built. The current policy silently removes iNaturalist media `605615444` and
preserves the order of all remaining URLs. Captured/staged user media is not
subject to this exact third-party denylist. If no permitted reference image
remains, the carousel keeps its existing non-reference media or empty-state
behavior; it never creates a censored placeholder page for the blocked URL.

Reference images also pass through the shared
`ReferenceImageDeduplicationPolicy` before the Insight page model is exposed.
`Shell/ViewModels/InsightSheetViewModel+MediaPresentation.swift` owns
`displayMedia(_:)` and excludes every visual identifier owned by the current
scan: image and video paths in `ActiveScanMedia`, persisted or queued thumbnail
paths, and the toolbar cover path. Naturebook URL variants for the same storage
object match even when their scheme, query, or fragment differs; external URLs
retain strict full-URL identity.

Filtering happens before `refUrls`, `totalImages`, inline carousel pages, and
fullscreen gallery items are derived. Consequently, inline and fullscreen views
share the same order and count, and an all-duplicate loaded reference set
becomes `.empty` instead of leaving an empty reference page or page indicator.
The rule is scoped to the exact scan, not the author: Naturebook imagery from
another scan remains eligible, as do unrelated Wikipedia and GBIF images.

Subject eligibility is applied before reference pages or hydration work.
`SpeciesData.shouldSuppressReferenceImages` and the matching persisted-record
policy remove reference imagery for Human aliases and unresolved biological
subjects while retaining the user's captured audio/video/image media.
`InferenceEngine` does not schedule live or historical Wikipedia/GBIF hydration
for either state and clears stale reference/candidate enrichment while loading a
guarded historical record. Canonical `Homo sapiens`, malformed `Homo sapien`,
and Human common-name aliases receive the same protection.

Image-load availability is tracked per scan and distinguishes captured user
photos from reference imagery. Failed visual pages are excluded once no usable
user image or video remains, and the existing `Original photo unavailable` state
is appended after every audio, description, reference, and loading page. This
terminal page never enters the fullscreen gallery. When other usable user
visuals remain, the established availability ordering still moves failed images
behind usable visual pages and removes them after a reference renders.

While a still image is inferencing, queued presentation caches must use
`QueuedScanContext.activeScanMedia`, not the raw captured-media snapshot, so the
focus-region map survives foreground-to-queue and queue-refresh handoffs. The
carousel keys focus interaction by scan ID plus the still image's canonical
source index rather than its content-derived page ID. Consequently, replacing an
in-memory live image with its persisted path does not replace the focus overlay
or discard a user-adjusted rectangle. User-adjusted geometry is normalized to
the visible carousel and owned by `InsightSheetViewModel`, so it also survives a
carousel remount and the queued-to-foreground analysis-owner handoff. The
carousel analysis treatment comes from
`InsightSheetViewModel.isCarouselAnalysisActive(for:)`, not the broad toolbar
processing flag:

| Presentation state                                     | Analysis overlay |
| ------------------------------------------------------ | ---------------- |
| Foreground analysis                                    | Active           |
| Exact live visual handoff: pending/uploading/staged    | Active           |
| Exact live visual handoff: inferencing                 | Active           |
| Ordinary queued scan: pending/uploading/staged         | Inactive         |
| Ordinary queued scan: inferencing                      | Active           |
| Failed, external-import, attention-required, or result | Inactive         |

For the exact handoff, `resolvedMedia(for:)` continues returning the engine's
in-memory `ActiveScanMedia` instead of swapping immediately to the persisted
queue path. The canonical scan ID and page identity therefore remain unchanged,
allowing `NativePageCarousel` to retain its page controller, selected index,
decoded image, and focus state while only the internal owner changes.

`ImagesCarousel` owns `AnalyzingMediaAnimationSession` above the conditional
`AnalyzingMediaOverlay`. The overlay derives its sweep and pulse from the
session's `startedAt` value through `TimelineView`; recomposition or an exact
same-scan owner change cannot restart the phase. A canonical scan-ID change or a
false-to-true processing transition after completion creates a fresh clock and
continuity token. Reduce Motion keeps the sweep at its midpoint without changing
those reset rules. The interaction state also retains the last confirmed
canonical scan ID through a transient nil-owner window and treats casing-only ID
changes as equivalent, while a genuinely different scan prunes the prior state.

Audio pages expose a filename-scoped playback-control accessibility identifier
only after the source has produced both a valid `AVAudioPlayer` and decoded
spectrogram columns. The seeded queued-audio UI regression writes a real PCM WAV
to Documents, waits for that control before completion, and requires the same
readable control after the completed record replaces the queued presentation.
The outer page identifier alone is not media-readiness evidence because it is
also present while decoding and in the unavailable state.

Video pages track the underlying `AVPlayerItem` status instead of treating a
created player as proof that media is playable. Each active video may carry one
retained image fallback: its stored poster first, otherwise the middle of its
five sampled inference frames. An explicitly empty cloud video URL manifest
demotes stale video records to that single image and repairs cached remote
records. Runtime playback failure performs the same replacement in place with
the original stable page ID, so selection is preserved, video/mute controls are
removed, and tapping opens normal fullscreen image zoom. Sampled frames are
never exposed as a five-page replacement.

Inline and fullscreen video each retain a `MediaPlaybackObservation` for the
mounted playback surface. Replacing or dismissing a player removes KVO,
AVPlayerItem notification, and periodic-time tokens from that exact player;
callbacks carry a generation fence so late events from a prior carousel page
cannot update the current page. The main-actor
`InsightCarouselVideoPlaybackCoordinator` also constructs its type-erased pause
publisher once. Production video pages receive that coordinator directly, while
the carousel retains it in stable `@State`. Builder-only callers without one
share a cached inactive publisher; carousel recomposition must not allocate
another erased publisher or `Empty` fallback. Do not register ad hoc AVPlayer
observers in a carousel view.
