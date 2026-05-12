# Explore Home Screen Widget

Merian ships a small iOS Home Screen widget that behaves like an image carousel for Recent Explore posts. The widget is intentionally image-only: a full-bleed square photo with no labels, badges, controls, gradients, or text. Tapping the image opens the matching Explore post inside the main app.

## Product Contract

- Supported family: `WidgetFamily.systemSmall` only.
- Surface: full-fill image, edge to edge, clipped to the system widget square.
- Content source: Recent Explore feed, not Following, Trending, or Nearby.
- Tap behavior: `merian://explore/post/{postId}` opens `ExploreView` and routes to `ExplorePostDetailView`.
- Carousel behavior: WidgetKit timeline entries rotate through cached images. This is not a swipeable carousel; iOS controls when timeline snapshots actually advance.
- Empty state: bundled image-only flower photo fallback. The app populates the cache after Recent Explore successfully loads.

## Architecture

The widget extension does not authenticate with Supabase and does not mount Merian app services. It reads a tiny App Group cache written by the main app:

1. `ExploreFeedViewModel.loadInitialFeed(force:)` fetches Recent posts through `MerianNetworkClient.getExploreFeed(...)`.
2. When `activeFilter == .recent`, the app calls `ExploreWidgetSnapshotWriter.refreshRecentFeedSnapshot(from:)`.
3. The writer downscales each post's `heroImageUrl` to `ExploreWidgetConstants.imageMaxDimension`, writes JPEG files into the App Group image directory, and writes `explore-widget-snapshot.json`.
4. The writer calls `WidgetCenter.shared.reloadTimelines(ofKind: ExploreWidgetConstants.kind)`.
5. `MerianExploreWidget` reads the snapshot, filters out missing image files, and emits one `TimelineEntry` per cached item.

This keeps the extension lightweight and reliable. The widget process only needs `Foundation`, `SwiftUI`, `UIKit`, and `WidgetKit`; all Supabase, auth, SwiftData, and Explore feed pagination logic stays in the containing app.

## Shared Cache Contract

Shared types live in `merian/Features/Explore/Widgets/ExploreWidgetCache.swift` and are compiled into both the app target and widget extension target.

- App Group: `group.app.merian.shared`
- Widget kind: `ExploreCarouselWidget`
- Snapshot file: `explore-widget-snapshot.json`
- Image directory: `ExploreWidgetImages/`
- Max cached items: `12`
- Timeline rotation interval: `30 minutes`
- Empty-state refresh interval: `60 minutes`
- Bundled fallback asset: `ExploreWidgetPlaceholder` in the widget extension asset catalog, sourced from `merian/Assets.xcassets/Widget/widget-flower.imageset/widget-flower.jpg`. The same photo is also copied into `MerianExploreWidget/Resources/ExploreWidgetPlaceholder.jpg` as a direct bundle fallback for WidgetKit gallery rendering. Keep the widget extension copies downsampled for WidgetKit memory limits; the current bundled copies are `1024x1024`.

Each `ExploreWidgetItem` stores only:

- `postId`
- `imageFilename`
- `sharedAt`

Do not add user-private scan metadata, exact coordinates, auth tokens, comments, field notes, or profile data to this cache. The widget should remain a public-image launch surface.

## Deep Linking

The app declares the `merian` URL scheme in `merian/Configuration/Info.plist`. `MerianApp.handleMerianDeepLink(_:)` accepts only:

```text
merian://explore/post/{postId}
```

Accepted URLs publish `AppEvent.appDidEnterActivePhaseWithExplorePost(postId:)`. `CaptureWorkspaceViewModel` already handles that event by presenting the Explore sheet and seeding its initial route.

## XcodeGen And Entitlements

`project.yml` is the source of truth for the target graph. When changing the widget target, update `project.yml` and run:

```sh
xcodegen generate
```

Both targets need the same App Group entitlement:

- `merian/Configuration/Merian.entitlements`
- `MerianExploreWidget/Configuration/MerianExploreWidget.entitlements`

For device/TestFlight builds, the Apple Developer identifiers for both `app.merian.Merian` and `app.merian.Merian.ExploreWidget` must have the `group.app.merian.shared` App Group capability enabled. If provisioning does not include the group, `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil` and the widget stays empty.

The app target embeds `MerianExploreWidget`; the widget target also directly compiles `ExploreWidgetCache.swift` because it is the only shared source it needs.

## Maintenance Notes

- The widget is populated opportunistically by the app. If the user never opens Explore, the widget remains in the empty state.
- Avoid network work in the widget extension unless there is a strong product reason. Widget refresh budgets are limited, and authenticated Supabase work belongs in the app.
- Keep the widget view text-free. Widget gallery display name and description are allowed because they are system configuration metadata, not in-widget UI.
- If the visual design changes, preserve `.contentMarginsDisabled()`, `.scaledToFill()`, and the iOS 18+ `.widgetAccentedRenderingMode(.fullColor)` image modifier so the image remains full-bleed and full-color.
- If cache shape changes, keep decoding backward-compatible or tolerate a missing/old snapshot by showing the empty state.
