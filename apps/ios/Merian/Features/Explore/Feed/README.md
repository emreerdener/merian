# Explore Feed

The `Feed` directory drives the core social timeline of the application.

## Purpose

This area owns the Observations catalog, hashtag collections, post detail,
publishing/editing presentation, and comment interactions. It supports the
global public feed, a following-only feed, trending observations, and
geographically nearby posts while preserving one shared `ExplorePostStore` for
cross-surface mutations.

The
[canonical Explore product contract](../../../../../../docs/rfcs/explore-page.md)
remains authoritative for shipped behavior, copy, routing, privacy, and backend
semantics; this README documents the iOS ownership boundary.

## Ownership Boundaries

Feed declarations are grouped by responsibility:

- `Models/` owns Feed routes, composer drafts, formatting, finite layout,
  badges, hashtags, Field Chat admission, and the device-local audio-boost
  preference.
- `Services/` owns the live dependency adapters for feed/comments/interactions,
  post detail, composer image loading, identity/entitlement presentation, and
  unread-notification realtime lifecycle. These are the only Feed declarations
  that resolve `MerianNetworkClient`, `SupabaseManager`, `RevenueCatManager`,
  `PostHogManager`, or `LocalImageLoader` singletons.
- `ViewModels/` owns catalog/filter/pagination state, the shared post store,
  comments/replies/reactions, post-detail loading and mutations, hashtag
  pagination, and the thin unread-notification facade. These state owners
  receive small grouped closure dependencies. Feed and hashtag
  refresh/pagination paths discard stale results through request identity or
  generation state, while comment page loads and submissions validate the active
  post and comments-session identity.
- `Views/` owns the Feed tab, hashtag collection, and post-detail route hosts.
  Selection, sheet occupancy, focus, scroll proxy, delayed-scroll work, and
  overlay timing remain view-local so extraction does not change SwiftUI
  lifecycle behavior.
- `Components/Catalog/` owns the filter sheet.
- `Components/Comments/` owns the shared thread/reply renderer used by the modal
  comments sheet and inline post-detail section; each host retains its distinct
  navigation, sticky-composer, focus, and scroll behavior.
- `Components/Composer/` and `ExplorePostComposerView` own the shared publish
  form, prepared image rendering, and media selection tiles.
- `Components/Detail/` owns post-detail structure, loading, and the single typed
  sheet renderer; `Components/DetailCards/` owns public detail cards.
- `Components/Cards/` owns `ExplorePostCard`, its loading skeleton, and preview
  fixtures. Cards consume `ExplorePostCardAuthorPresentation`, send mutations
  through parent callbacks, and do not resolve identity or entitlement services.
- `Components/Media/` owns Feed-only square feed/detail hosts and detail zoom.
- `Components/Shared/` owns the Feed-only hashtag pill.
- The remaining comment, post-detail action/header, composer, and reference
  gallery components are Feed-owned UI with no direct networking.
- `../Shared/Media/` owns the Explore-wide public-media renderer, remote hero
  image, media indicators, `AVPlayerLayer` bridge, playback extensions,
  coordinator, deterministic playback policies, dependency adapters, and the
  single mutable playback-state owner.
- `Core/UI/Components/MerianProBadge.swift` owns the domain-neutral Pro badge,
  while `Core/Media/` owns reusable playback observation, audio processing, and
  spectrogram loading.

Views and components must not call RPCs, Edge Functions, or raw `URLSession`
work. View models use their injected dependencies for endpoint, interaction,
feedback, and realtime work; live endpoint, realtime, identity/entitlement,
telemetry, and loader resolution stays in `Services/`. The Feed tab may read
injected environment identity and entitlement state to prepare card
presentation, but cards consume only those prepared values. Shared media
receives image-loading closures through its narrow Explore-wide adapter.

The stateless Feed, post/detail, and hashtag wire methods live in
`Core/Network/Endpoints/MerianNetworkClient+ExploreBrowsing.swift`. Comment,
reply, mention, like, report, and blocking requests live in
`Core/Network/Endpoints/MerianNetworkClient+ExploreInteractions.swift`. This
does not move Feed state into Core: Services retain live adapters, ViewModels
retain loading and interaction state, and `SocialGuardManager` retains shared
blocking state. Composer-media reads, both public-notes/content edits, and
unsharing use `MerianNetworkClient+ExplorePostManagement.swift`; direct
publication, owned-row recovery, and media restoration use the dedicated Core
Network Endpoint, Recovery, and Media owners. The
[post-management matrix](../../../Core/Network/README.md#explore-post-management-verification)
covers wire/retry behavior separately from Feed state. Codable wire models
remain in Core Network.

Keep existing Feed-tab, hashtag-route, post-detail, composer, and card
initializer signatures stable. Preserve visible copy, accessibility values, hit
regions, gestures, haptics, telemetry, autoplay rules, Low Power behavior,
audio-session behavior, observer lifetime, and coordinator semantics when moving
declarations between these folders. Production Feed files stay at or below the
pass's 600-line review guard.

### Cross-area media ownership

`Explore/Shared/Media` is the final Explore-wide owner for declarations consumed
by more than one product area:

- `ExplorePublicMediaView` and its Playback extensions render Feed/detail and
  Identify request-detail media.
- `ExploreMediaPlayIndicator` is shared by Feed media and Identify cards.
- `ExploreMediaTypeIndicator` and `ExploreHeroImageView` are consumed by Map,
  Shell, Author Profile, Profile, and Species Dictionary surfaces.
- `ExploreVideoPlaybackCoordinator`, mute policy, and playback policies form one
  Explore-wide lifecycle boundary.

`ExplorePublicMediaPlaybackState` contains player, observer, task, seek, audio
session, boost, and recovery mutation. View extensions receive read-only
forwarding values and invoke semantic mutations; they do not own mutable task or
observer storage. File-local view helpers remain `private`. The persisted mute
preference remains private to `ExplorePublicMediaView` so extraction cannot
change its SwiftUI update timing.

## Publication Ingress

Insight-originated publication does not write feed models directly. The
`Insights/Sharing` flow calls `/share-scan-to-explore`, which requires the exact
authenticated-owner scan, validates the selected user media, applies post-owned
location privacy and audible-media moderation, and saves a post-owned
`explore_post_media` snapshot before returning success.

A post is feed-visible only when the canonical public projection sees at least
one eligible saved media row. The share route writes the post and public media
snapshot in one transaction, so a failed snapshot cannot return a phantom
visible post; public projections also exclude any historical media-less row.
Older local scans may use the guarded owner-row/media recovery contract, but the
feed never treats local files, reference artwork, or client-selected URLs as
public observation evidence.

See [`Insights/Sharing/README.md`](../../Insights/Sharing/README.md) and the
[joined scan reliability contract](../../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#explore-publication).

## Post-detail reference gallery

An Explore post owns its primary media presentation. Its hero URL, every
resolved media-item URL, and every media-item thumbnail URL are therefore passed
to `ExplorePostDetail.referenceGalleryImages(excluding:)` before
`ExploreReferenceGallery` is constructed. The shared reference-media policy
removes Naturebook URL variants that resolve to the same host/object path while
keeping other scans' Naturebook images and unrelated external references.

The filtered list retains server order and the existing Naturebook, Wikipedia,
and GBIF attribution mapping. When no references survive, post detail omits the
reference gallery and its page indicators entirely. The iOS filtering remains a
client-side defense even though `get_explore_post_detail` also excludes the
backing scan's `image_storage_urls`, allowing backend and app changes to roll
out independently.

## Post-detail presentation ownership

The Observation card consumes the optional `map_point` from the public Explore
detail payload. It renders a noninteractive exact marker or 10 km approximate
circle only while the saved post location setting is `open`; `obscured`,
`private`, missing, invalid, and failed-refresh states omit the map. The payload
uses only the post-owned public coordinate projection and never local or raw
scan coordinates.

The main Explore feed marks its detail route as map-actionable. Tapping that
Observation card returns to the Explore root, switches Observations from Feed to
Map, clears species and media filters, focuses the public point, and selects the
post preview. Details opened from Map, notifications, hashtags, author/profile,
or Species Dictionary hosts render the same eligible map preview without a tap
action.

Auto-opening an owned Insight after a routed detail mounts is part of the
detail's lifecycle-owned load task; cancellation on unmount prevents its short
settling delay from targeting another post. Field Chat preparation is keyed to
the pending post ID with `.task(id:)` and revalidates both cancellation and the
current post before presenting. Its notes-draft binding is the sole dismissal
owner; cancel does not also call an independent `DismissAction`. Delayed comment
focus and follow-up scroll work is stored, replaced on a newer request, and
cancelled on detail disappearance so a timer cannot retain an old
`ScrollViewProxy` or focus a replacement post.

When a parent supplies the owned-Insight callback, post detail reports the scan
ID only. The Explore shell decides whether and when its own presentation should
dismiss; the leaf never tears down a parent-owned sheet.

Post detail owns one typed `ExplorePostDetailPresentation` sheet slot for
Insight, author/reply routes, Field Notes, post editing, Field Chat, and
paywall. Composer-media preparation is one stored, replaceable task. Leaving
detail or claiming another presentation cancels it; a completion can mount only
while its request UUID and post ID are still current and the slot is empty.
Field Chat preflight applies the same post, cancellation, and occupancy checks.
When a parent Explore shell supplies an author-route callback, that parent keeps
the author profile in its navigation stack; the local author case is the
standalone fallback. Do not add a sibling sheet modifier to this host.

The reusable conversation implementation belongs to `Features/FieldChat`. Feed
owns post eligibility, the captured post identity, menu/button admission, and
its typed sheet slot; `FieldChatEndpoint` owns source-specific network
adaptation and the shared view model owns subject-fenced conversation state.

## Video Playback

`ExplorePublicMediaView` is the shared media host for feed cards, post detail,
and Community ID media previews. Feed and detail are the only autoplay surfaces:
they start public videos muted, share the persisted mute preference, and keep
one active Explore player at a time. Feed autoplay still respects Low Power
Mode; post detail may autoplay after navigation because the user explicitly
opened the post.

Feed autoplay always re-enters muted. If the user unmutes a feed video and then
opens that post, detail inherits the current mute state. Leaving detail resets
the shared preference to muted before feed playback resumes, preventing audio
from continuing in the background when Explore is reopened or uncovered.

Feed audio and video reserve a 96-point square at the center of the media above
the full-card navigation gesture. A single tap there plays or pauses locally,
even after the 58-point visual control fades; a double tap likes the post. A
single tap outside that center zone still opens post detail, and an outer double
tap still likes. The center zone remains a VoiceOver Play/Pause button. Detail
media keeps its existing local playback controls.

Video recovery is coordinated through `ExploreVideoPlaybackCoordinator` in
`Shared/Media/Models`. `ExploreView` owns one coordinator and injects it into
the Explore environment. Sheet hosts use
`.exploreVideoPresentedOverlayLifecycle(...)` instead of ad-hoc
`NotificationCenter` events or paired manual pause/resume calls. The coordinator
tracks overlay tokens, nested overlay depth, `pauseGeneration`, and
`resumeGeneration`, so playback resumes only after the final Explore overlay is
gone.

When a covered video resumes, `ExplorePublicMediaView` treats the interruption
as recoverable: it saves the current time, rebuilds the `AVPlayer` and
`AVPlayerLayer`, seeks back, and attempts autoplay if eligible. If playback
cannot restart, the centered play control remains visible so the user can repair
playback without closing and reopening Explore. A hidden unhealthy video tap
repairs/reveals playback before feed navigation; healthy feed taps still open
post detail.

Use `MerianLog.exploreVideo` while diagnosing this path. The media view logs
player ids, surface names, player/layer rebuilds, overlay pauses/resumes,
`timeControlStatus`, watchdog results, visible-control transitions, and tap
recovery.

## Standalone Audio Playback and Boost

`ExplorePublicMediaView` also owns standalone-audio playback. It renders the
saved spectrogram with a moving playhead and elapsed/total timestamp, and it
participates in the same one-active-player and audio-session lifecycle as other
Explore media.

Explore post detail makes the spectrogram seekable: tapping jumps to a time and
dragging pauses temporarily while the playmarker follows the gesture, then
resumes only when playback was active before the drag. The center playback
control remains independently tappable and VoiceOver can adjust position in
five-second steps. Feed spectrograms intentionally do not seek because their
center and outer regions retain playback, like, and detail-navigation gestures.
`AudioSpectrogramSeekingPolicy` treats non-finite progress, duration, width, and
marker values as a safe zero and clamps finite playmarker offsets into the
available width. Do not calculate frame offsets directly from player time.

Detail zoom layout uses `ExploreDetailZoomLayoutPolicy.resolvedSize(...)` to
accept only finite positive proposed dimensions. It can use one valid dimension
when the other is invalid and returns `nil` when neither is usable, allowing
SwiftUI to choose an unconstrained fallback without an invalid-frame warning.
Any new geometry-dependent detail overlay must use the same finite guards.

User-initiated playback uses Merian's shared `HapticManager`: play and enabling
audio boost receive a medium confirmation, pause and mute changes receive light
feedback, and seeking produces one subtle begin pulse plus one commit selection.
Autoplay, playhead ticks, saved-setting restoration, and cross-surface state
updates never emit haptics. Explicit audio-boost failures use the standard error
feedback and respect the global haptics and expedition-mode preferences.

Feed cards and post detail with standalone primary audio expose a compact,
filled **Boost audio** pill at the bottom-left of the spectrogram, while their
ellipsis menus retain the same action. The pill owns its hit-test region above
feed navigation and detail spectrogram-seeking gestures; the rest of the media
keeps the existing navigation, seeking, and center-playback behavior.
`ExploreAudioBoostPreferenceStore` remembers enabled post IDs locally for 180
days, capped at 500 entries, so each post has an independent setting. The
loss-tolerant `AppEvent.exploreAudioBoostPreferenceChanged` invalidation keeps
visible feed and detail players synchronized; each consumer still reads the
persisted UserDefaults preference as authority. Preferences are device-only and
are never written to Supabase.

The shared `AudioBoostProcessor` in `Core/Media` creates a bounded temporary
enhanced WAV using RMS/peak analysis, at most 18 dB of adaptive gain, gentle
low-frequency rumble reduction, and peak limiting. It never changes or uploads
the canonical recording. Switching modes preserves position and play/pause
state; preparation failure falls back to the original audio. The processor keeps
at most eight temporary enhanced files. Images, videos, mixed-media ordering,
and feed playback are unaffected.

Once the enhanced file is ready and active, the feed pill transitions to
**Boosted audio** without its chevron and remains tappable to restore original
audio. Post detail retains its passive **Boosted audio** badge. The boosted
state is withheld during preparation and after fallback to original playback, so
it always describes the audio source the player can actually use. Direct
controls read **Boosting…** while preparing the enhanced source and
**Reverting…** while restoring the original; both transition states disable the
control until the source swap completes.

Saved preferences and cross-surface notifications prepare silently. The
**Boosting audio…** and fallback messages are reserved for a one-shot action
token created when the user explicitly selects **Boost audio** in the currently
visible menu. Completing, failing, or cancelling preparation consumes that
token; silent restoration still shows **Boosted audio** after enhancement
succeeds.

Analytics use `ExploreAudioBoostChanged` with an action, surface, and optional
coarse gain band only. Never add post IDs, media URLs, filenames, transcripts,
or captured audio to these events.

## Player observer ownership

Every `ExplorePublicMediaView` retains one `MediaPlaybackObservation`. Player
replacement removes KVO, AVPlayerItem notification, and periodic-time tokens
from the exact old player before the new player is observed. Generation checks
discard callbacks already queued for a replaced player, and teardown detaches
the observer explicitly. Do not add a parallel NotificationCenter or KVO array
inside feed/detail views.

## Overlay Ownership

Any new sheet or UIKit share surface launched from Explore feed/detail that can
cover a playing video must participate in the coordinator:

- SwiftUI sheets apply `.exploreVideoPresentedOverlayLifecycle(reason:)` to the
  presented content. The token is acquired when that content mounts and released
  only from its `onDisappear`, after UIKit teardown; the source binding may turn
  false earlier and is not dismissal authority.
- UIKit presenters such as `UIActivityViewController` should call
  `beginOverlay(reason:)` before presentation and end the returned token in the
  completion callback.
- Nested sheets are safe as long as each host owns exactly one token for its own
  presented state. Do not send global playback notifications.

## Focused Tests

Focused tests mirror their production owners:

- `MerianTests/Core/Network/Endpoints/ExploreBrowsingEndpointTests.swift` and
  `ExploreBrowsingEndpointTransportTests.swift` own browsing payload, response,
  error, replay, and cancellation coverage. They rehome the legacy Feed request
  tests from `MerianNetworkClientTests`; feature state tests stay here. When
  changing this wire boundary, run the
  [Core Network browsing matrix](../../../Core/Network/README.md#endpoint-verification).
- `MerianTests/Core/Network/Endpoints/ExploreInteractionEndpointTests.swift` and
  `ExploreInteractionEndpointTransportTests.swift` own comment/interaction
  payloads, server projections, body-ignoring success, errors, and replay rules.
  They rehome the aggregate comment/reply/create/post-report/block regressions.
  Run the
  [Core Network interaction matrix](../../../Core/Network/README.md#explore-interaction-verification)
  after changing this shared wire boundary; optimistic UI and comment-session
  behavior remain in the feature suites below.
- `MerianTests/Features/Explore/Shared/Media/ExploreMediaPlaybackPolicyTests.swift`
  covers overlay reduction, center-hit policy, resume intent, contained playback
  state, and nested coordinator tokens.
- `MerianTests/Features/Explore/Feed/ExploreMediaLayoutTests.swift` covers the
  stable Feed-owned square feed/detail hosts.
- `MerianTests/Features/Explore/Feed/ExplorePostCardAuthorPresentationTests.swift`
  covers prepared avatar fallback and Pro presentation without live services.
- `ExploreFeedViewModelTests`, `ExploreHashtagPostsViewModelTests`, and
  `ExplorePostDetailViewModelTests` cover catalog refresh/pagination races,
  transient versus blocking errors, optimistic rollback, comment validation and
  restoration, cross-session submission fencing, hashtag generation fencing,
  post-detail generation fencing, editor preparation, and typed mutations
  through injected closures.
- `ExploreReplyLoadingStateTests` and `ExploreCommentMentionTextTests` cover
  reply lifecycle/pagination and mention parsing/rendering without mutating the
  shared network client. Shared comment-avatar fallback coverage lives in
  `MerianTests/Features/Explore/Shared/ExploreCommentAuthorPresentationTests.swift`.
- `ExploreHashtagSuggestionTests`,
  `ExplorePostFieldChatPresentationPolicyTests`, and the rehomed formatting,
  route, location-privacy, store-merge, and share-copy suites cover their
  Feed-owned pure policies.
- `MerianTests/Features/Explore/ExploreAudioBoostTests.swift` remains one level
  higher because it exercises Explore preferences and playback policy together
  with the shared Core boost/seeking implementation. Insight-specific pill,
  source-handoff, live-playhead, and injected-effect coverage lives in
  `MerianTests/Core/Media/AudioPlaybackPresentationTests.swift`; the
  Insight-only preference and availability rules remain in
  `MerianTests/Features/Insights/Media/InsightAudioBoostPolicyTests.swift`.

After building the test bundle, run the focused XCTest suites with the canonical
simulator destination:

```bash
xcodebuild -scheme Merian -project Merian.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:merianTests/ExploreVideoPlaybackOverlayStateTests \
  -only-testing:merianTests/ExploreVideoPlaybackResumeIntentStateTests \
  -only-testing:merianTests/ExplorePublicMediaPlaybackStateTests \
  -only-testing:merianTests/ExploreVideoPlaybackCoordinatorTests \
  -only-testing:merianTests/ExploreMediaLayoutTests \
  -only-testing:merianTests/ExplorePostCardAuthorPresentationTests \
  -only-testing:merianTests/ExploreFeedViewModelTests \
  -only-testing:merianTests/ExploreHashtagPostsViewModelTests \
  -only-testing:merianTests/ExplorePostDetailViewModelTests \
  -only-testing:merianTests/ExploreReplyLoadingStateTests \
  -only-testing:merianTests/ExploreCommentAuthorPresentationTests \
  -only-testing:merianTests/ExploreCommentMentionTextTests \
  -only-testing:merianTests/ExploreHashtagSuggestionTests \
  -only-testing:merianTests/ExplorePostFieldChatPolicyTests test
```

Manual parity coverage must exercise image, audio, and video cards in feed and
detail; autoplay and mute reset; center play/pause; buffering, interruption, and
overlay recovery; audio boost, seeking, and source fallback; detail zoom; card
navigation; VoiceOver; large Dynamic Type; Reduce Motion; Low Power Mode; and
light/dark appearance. Because `Explore/Shared/Media` is cross-area, also
regress Identify request cards/detail, Map markers and previews, Shell-routed
post previews, Author Profile and Profile grids/Pro badges, and Species
Dictionary community sightings.
