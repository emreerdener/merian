# Explore Shared

The `Shared` directory owns helpers reused by more than one Explore product area
when they are not generic enough for Core.

## Purpose

Place a declaration here when Feed, Map, Identify, Author Profile, or Shell
share one Explore-specific presentation or lifecycle contract. Promote a
declaration to Core only when it is domain-neutral and reused outside Explore.
Product-area screens, cards, filters, and view models remain with their owning
area.

The root components own keyboard dismissal, unavailable-state presentation, and
the Explore onboarding prompt. `Models/ExploreCommentAuthorPresentation.swift`
owns secure comment-avatar fallback shared by Feed and Notifications. `Media/`
owns the cross-area media boundary:

`Components/FlowLayout.swift` owns the Explore-only wrapping layout shared by
Feed comments/details and Field Trips catalog cards. It remains a pure SwiftUI
layout value with no product state or live effects; promote it back to Core only
if a non-Explore product area adopts the same contract.

- `Components/` owns `ExplorePublicMediaView`, the thin player-layer bridge,
  hero-image rendering, and media indicators.
- `Playback/` owns audio seeking/boost, player configuration and recovery,
  lifecycle observation, and exact teardown extensions.
- `Models/` owns the playback coordinator, deterministic interaction/overlay/
  resume policies, and `ExplorePublicMediaPlaybackState`, the sole mutable
  player/task/observer state owner. That state also retains the shared
  token-aware audio-session controller and its activation task; Explore views
  never configure or deactivate `AVAudioSession` directly. User pause,
  external-player handoff, recoverable interruption, overlay cleanup,
  deselection, and reset cancel both the UI task and pending controller
  activation. Reset and deselection also release only the exact current lease,
  so another playback or recording owner cannot be torn down by stale cleanup.
  The shared controller fences teardown while an existing lease is being
  validated.
- `Services/` owns narrow live image and spectrogram loading closures. Shared
  components receive those dependencies and never resolve loaders directly.

`ExploreHeroImageView` uses Core UI's `ImageRecoveryReloadModifier` and includes
the source revision in its loading task identity. A corrected recovery mapping
therefore refreshes an already displayed hero image. Unversioned preloads are
reacquired through the loader once recovery has a nonzero revision; cancelled
loads cannot publish an obsolete bitmap. The shared evidence and cache contract
lives in the
[image pipeline](../../../../../../docs/system-architecture/03-image-pipeline.md).

Feed retains Feed-only square hosts, detail zoom, card composition, hashtags,
and card-author presentation. The domain-neutral Pro badge lives in
`Core/UI/Components/MerianProBadge.swift`; reusable spectrogram loading lives in
`Core/Media/AudioSpectrogramThumbnailLoader.swift`.

Changes to Shared media require its focused playback-state/policy tests, Feed
layout tests, and manual regression of Identify, Map, Shell previews, Author
Profile, Profile, and Species Dictionary consumers. Comment-author presentation
changes require the focused Shared presentation suite plus manual Feed and
Notifications avatar regression. The detailed media matrix lives in the
[Feed README](../Feed/README.md#focused-tests).
