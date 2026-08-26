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
the Explore onboarding prompt. `Media/` owns the cross-area media boundary:

- `Components/` owns `ExplorePublicMediaView`, the thin player-layer bridge,
  hero-image rendering, and media indicators.
- `Playback/` owns audio seeking/boost, player configuration and recovery,
  lifecycle observation, and exact teardown extensions.
- `Models/` owns the playback coordinator, deterministic interaction/overlay/
  resume policies, and `ExplorePublicMediaPlaybackState`, the sole mutable
  player/task/observer state owner.
- `Services/` owns narrow live image and spectrogram loading closures. Shared
  components receive those dependencies and never resolve loaders directly.

Feed retains Feed-only square hosts, detail zoom, card composition, hashtags,
and card-author presentation. The domain-neutral Pro badge lives in
`Core/UI/Components/MerianProBadge.swift`; reusable spectrogram loading lives in
`Core/Media/AudioSpectrogramThumbnailLoader.swift`.

Changes to Shared media require its focused playback-state/policy tests, Feed
layout tests, and manual regression of Identify, Map, Shell previews, Author
Profile, Profile, and Species Dictionary consumers. The detailed matrix lives in
the [Feed README](../Feed/README.md#focused-tests).
