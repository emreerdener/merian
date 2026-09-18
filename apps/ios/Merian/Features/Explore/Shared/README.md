# Explore Shared

The `Shared` directory owns helpers reused by more than one Explore product area
when they are not generic enough for Core.

## Purpose

Place a declaration here when two or more Explore product areas, such as Feed,
Map, Identify, Author Profile, Field Trips, Notifications, or Shell, share one
Explore-specific presentation or lifecycle contract. Promote a declaration to
Core only when it is domain-neutral and reused outside Explore. A non-Explore
adapter that publishes into or presents an Explore experience does not change
the ownership of Explore-specific policy. Product-area screens, cards, filters,
and view models remain with their owning area.

The root components own keyboard dismissal, unavailable-state presentation, and
the Explore onboarding prompt. `Models/ExploreCommentAuthorPresentation.swift`
owns secure comment-avatar fallback shared by Feed and Notifications.

`Models/ExploreLocationSharingPresentation.swift` owns the labels, SF Symbols,
and explanatory copy for the Explore post-location modes used by Feed and the
Insights adapters that publish into Explore. The Codable/raw-value contract
lives in `Core/Network/Models/Explore/ExploreLocationSharingAPIModels.swift`, so
Core Network never depends on a feature-owned composer model.

`Models/ExploreErrorFormatter.swift` owns customer-safe error presentation for
Explore experiences and for non-Explore adapters that publish into or present
those experiences. It is a pure mapping boundary over caller-supplied errors;
callers retain task cancellation, retry state, logging, and presentation
lifetime. Do not return this Explore-specific copy policy to Core Utilities or
add live network resolution to it.

`Components/FlowLayout.swift` owns the Explore-only wrapping layout shared by
Feed comments/details and Field Trips catalog cards. It remains a pure SwiftUI
layout value with no product state or live effects; promote it back to Core only
if a non-Explore product area adopts the same contract.

`Media/` owns the cross-area media boundary:

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
Notifications avatar regression. Error-presentation changes require
`ExploreErrorFormatterTests` and `ExploreSharedArchitectureTests`, plus focused
regression of Feed, Author Profile, Map, Identify, Field Trips, Notifications,
Shell, Insights sharing, Scans publication, Species Dictionary, and
observation-statistics consumers. Location-sharing contract/presentation changes
require `ExploreLocationSharingAPIModelsTests`,
`ExploreLocationSharingPresentationTests`, and
`ExploreNetworkModelArchitectureTests`. The architecture suites also pin the
formatter's Foundation-only, effect-free boundary, layered location-sharing
ownership, and every Explore Shared production file at or below 600 lines. The
detailed media matrix lives in the
[Feed README](../Feed/README.md#focused-tests).

## Emoji reactions

`Reactions/` owns the bundled Unicode catalog, searchable picker, reaction
strip, and shared post action row. These components render injected
state/callbacks and perform no networking. Feed/Map card hosts and the existing
detail sheet host retain presentation ownership.

The picker starts at the medium detent, supports large, and expands on search
focus. It uses native glyphs plus catalog names and the existing video-overlay
suspension lifecycle. Picker selection adds; chip taps toggle. The strip reveals
new selections, leaves later page updates in place, and offers More for explicit
pagination/retry. Its height scales with Dynamic Type, with post chips moving
below fixed controls at `xxxLarge` and accessibility sizes. Post red-heart
mapping belongs to Feed state, not this generic comment-capable strip.

See the
[canonical behavior](../../../../../../docs/rfcs/explore-page.md#emoji-reactions-update-2026-09-18)
and
[verification matrix](../../../../../../docs/development-guides/08-testing-strategy.md#explore-emoji-reaction-verification).

### Reaction haptics

Opening a post or comment/reply emoji picker uses the shared sheet spring.
Choosing an emoji (including an already-selected one), toggling a chip, changing
categories, or tapping More gives one immediate selection pulse. Tapping the
active category again is silent unless it clears a search. Successful network
responses do not repeat the tap feedback, including post ❤️ picker selections;
direct Heart buttons retain their existing feedback. Failed mutations retain
error feedback alongside rollback and the visible error.

All reaction feedback routes through `HapticManager`, respecting the global
haptics preference and expedition-mode suppression. Search typing, scrolling,
sheet lifecycle updates, pagination results, and background reconciliation do
not emit haptics. Shared picker/chip components apply this behavior to feed,
detail, Map, hashtag, comment/reply, and notification reply surfaces.
