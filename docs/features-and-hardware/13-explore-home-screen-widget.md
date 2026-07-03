# Explore Home Screen Widget

The Explore widget remains thumbnail-first. It caches still image thumbnails in
the shared App Group and overlays a compact play indicator when the source
Explore post contains video media; widgets do not load or play public videos
inline.

Merian ships a small iOS Home Screen widget that behaves like a thumbnail carousel for Recent Explore posts. The widget is intentionally static: a full-bleed square thumbnail with a compact play indicator when the post contains video, but no inline playback controls. Tapping the image opens the matching Explore post inside the main app.

## Product Contract

- Supported families: `WidgetFamily.systemSmall`, `WidgetFamily.systemMedium`, and `WidgetFamily.systemLarge`.
- Surfaces:
  - **Small Widget (`.systemSmall`):** full-fill image, edge to edge, clipped to the system widget square. Kept entirely text-free to respect the original design contract.
  - **Medium Widget (`.systemMedium`):** horizontal card displaying a 1:1 square photo of the discovery on the left, and an elegant description panel on the right displaying the species' common name. Blends seamlessly with system Light & Dark modes.
  - **Large Widget (`.systemLarge`):** full-fill image, edge to edge, featuring a beautiful bottom-anchored dark gradient overlay containing the species' common name.
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

Shared types live in `apps/ios/Merian/Features/Explore/Widgets/ExploreWidgetCache.swift` and are compiled into both the app target and widget extension target.

- App Group: `group.app.merian.shared`
- Widget kind: `ExploreCarouselWidget`
- Snapshot file: `explore-widget-snapshot.json`
- Image directory: `ExploreWidgetImages/`
- Max cached items: `12`
- Timeline rotation interval: `30 minutes`
- Empty-state refresh interval: `60 minutes`
- Bundled fallback asset: `ExploreWidgetPlaceholder` in the widget extension asset catalog. The same photo is also copied into `apps/ios/widgets/Explore/Resources/ExploreWidgetPlaceholder.jpg` as a direct bundle fallback for WidgetKit gallery rendering. Keep the widget extension copies downsampled for WidgetKit memory limits; the current bundled copies are `1024x1024`.

Each `ExploreWidgetItem` stores:

- `postId`
- `imageFilename`
- `sharedAt`
- `speciesCommonName` (optional)
- `speciesScientificName` (optional)

Do not add user-private scan metadata, exact coordinates, auth tokens, comments, field notes, or profile data to this cache. The widget should remain a public-image launch surface.

## Deep Linking

The app declares the `merian` URL scheme in `apps/ios/Merian/Configuration/Info.plist`. `MerianApp.handleMerianDeepLink(_:)` accepts only:

```text
merian://explore/post/{postId}
```

Accepted URLs publish `AppEvent.appDidEnterActivePhaseWithExplorePost(postId:)`. `CaptureWorkspaceViewModel` handles that event by:

1. Storing the tapped post id in `pendingExplorePostId`.
2. Refreshing `explorePresentationIdentity` so SwiftUI builds a fresh `ExploreView`.
3. Setting `activeSheet = .explore`, which presents the sheet through `CameraSheetRouter`.

`ExploreView(initialPostId:)` then seeds `selectedPostRoute`, pushing `ExplorePostDetailView` inside the sheet.

### Public Web Links

Widget taps continue to use the custom native URL scheme because they originate on the same iOS device:

```text
merian://explore/post/{postId}
```

External Explore shares should use the durable public HTTPS URL instead:

```text
https://merian.earth/explore/post/{postId}
```

The public web route lives in `apps/web/app/explore/post/[postId]/page.tsx` and renders a privacy-filtered post page plus Open Graph metadata. When Universal Links are enabled for `merian.earth`, the same HTTPS URL should open `ExplorePostDetailView` in the installed app and fall back to the web page for recipients without Merian.

### Session Timeout Race Guard

Widget taps often happen after Merian has been backgrounded for more than the 5-minute session timeout. On foreground, iOS can deliver the widget URL and Merian's `.appDidResumeAfterTimeout` reset in either order. If the URL route wins first, the timeout reset would otherwise clear `activeSheet` immediately and return the user to the camera.

To prevent that, `CaptureWorkspaceViewModel` calls `protectExternalRouteFromImmediateSessionTimeoutReset()` for Explore and scan deep links. This creates a short one-shot suppression window for the next session-timeout reset only. Ordinary stale sheets still clear on timeout, and `resetModalsForSessionTimeout()` also clears `pendingExplorePostId` so old widget routes cannot leak into later Explore launches.

## XcodeGen And Entitlements

`project.yml` is the source of truth for the target graph. When changing the widget target, update `project.yml` and run:

```sh
xcodegen generate
```

Both targets need the same App Group entitlement:

- `apps/ios/Merian/Configuration/Merian.entitlements`
- `apps/ios/widgets/Explore/Configuration/MerianExploreWidget.entitlements`

For device/TestFlight builds, the Apple Developer identifiers for both `app.merian.Merian` and `app.merian.Merian.ExploreWidget` must have the `group.app.merian.shared` App Group capability enabled. If provisioning does not include the group, `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil` and the widget stays empty.

The app target embeds `MerianExploreWidget`; the widget target also directly compiles `ExploreWidgetCache.swift` because it is the only shared source it needs.

## Maintenance Notes

- The widget is populated opportunistically by the app. If the user never opens Explore, the widget remains in the empty state.
- Avoid network work in the widget extension unless there is a strong product reason. Widget refresh budgets are limited, and authenticated Supabase work belongs in the app.
- Keep the `.systemSmall` widget view text-free. The larger `.systemMedium` and `.systemLarge` sizes display species metadata under an elegant protective overlay or split layout.
- When touching widget tap routing, keep `CaptureWorkspaceViewModel`'s external-route timeout suppression covered by tests. The expected behavior is: a fresh widget route survives an immediate `.appDidResumeAfterTimeout`, while an ordinary stale Explore sheet still clears on timeout.
- Keep widget custom-scheme routing and public web share routing aligned. Both should resolve the same post id shape, but only the HTTPS route should be used in user-to-user share text.
- If the visual design changes, preserve `.contentMarginsDisabled()`, `.scaledToFill()`, and the iOS 18+ `.widgetAccentedRenderingMode(.fullColor)` image modifier so the image remains full-bleed and full-color.
- If cache shape changes, keep decoding backward-compatible or tolerate a missing/old snapshot by showing the empty state.
