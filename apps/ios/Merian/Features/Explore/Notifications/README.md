# Explore Notifications

Explore Notifications owns the in-app activity catalog and the
notification-specific reply-thread presentation used by Explore post detail. The
[Explore product contract](../../../../../../docs/rfcs/explore-page.md) remains
authoritative for visible behavior, activity eligibility, unread semantics,
routing, and backend payloads; this README documents iOS ownership.

## Ownership boundary

- `Models/ExploreNotification.swift` owns the decoded feature model and
  notification-type classification.
- `Models/ExploreNotificationRowPresentation.swift` maps notification values to
  stable visible copy, symbols, accent roles, secondary text, and disclosure
  policy without resolving services.
- `Models/ExploreNotificationReplyThreadRoute.swift` owns the typed post,
  parent, target-reply, and bounded notification fallback carried into the
  notification-specific reply sheet.
- `Services/ExploreNotificationsDependencies.swift` is the only catalog layer
  that resolves the live notification fetch/read endpoints, feature
  availability, telemetry, logging, and error formatting.
- `Services/ExploreReplyThreadDependencies.swift` is the only reply-thread layer
  that resolves live comment/reply endpoints and current-viewer avatar context.
- `ViewModels/ExploreNotificationsViewModel.swift` owns catalog loading,
  read-state presentation, cursor pagination, filtering, and request-generation
  fencing.
- `ViewModels/ExploreNotificationReplyThreadViewModel.swift` owns parent and
  target discovery, bounded cursor traversal, fallback insertion, reply
  pagination, route-generation fencing, optimistic local reactions, and avatar
  presentation input.
- `Views/` owns the notification and reply-thread sheet hosts, detents,
  navigation chrome, refresh gestures, dismissal, and task lifetimes.
- `Components/NotificationRowView.swift` and `Components/ReplyThread/` render
  prepared presentation and observable state. They perform no networking or
  singleton lookup.

Views and components must not call RPCs, Edge Functions, `URLSession`, or
identity singletons. New endpoint work belongs in a narrow closure dependency
under `Services/`; JSON DTOs and wire validation remain in `Core/Network`.

## Catalog lifecycle

Opening the sheet fetches the first page before marking unread rows as read. A
successful mark-read call highlights only the rows that were unread in that page
and notifies the Shell so its bell and app badge can clear. A mark-read failure
preserves the fetched rows and the existing error behavior.

The catalog uses the server's `(updated_at, notification_id)` cursor. Each
first-page load advances a generation and invalidates any active pagination or
mark-all request. Late pages cannot merge into refreshed state, late read
completion cannot clear a replacement generation's highlight set, and stale
errors do not replace the active result. Pagination failure remains transient
and leaves loaded rows usable. A failed refresh preserves the last successful
cursor so the still-visible catalog can continue loading older activity.

## Reply-thread lifecycle

Reply notifications carry `ExploreNotificationReplyThreadTarget` inside the
Feed-owned `ExplorePostRoute`. Post detail converts that target into
`ExploreNotificationReplyThreadRoute` and presents the existing thin
`ExploreNotificationReplyThreadSheet(viewModel:route:)` wrapper.

The reply view model loads the parent comment and traverses reply pages
concurrently until it finds the target or reaches the existing bounded page
limit. When the target is no longer publicly readable, the sanitized
notification fallback remains visible if it contains a non-empty body. A route
replacement or refresh advances the load generation and invalidates active
pagination, so old routes, pages, and errors cannot mutate the mounted thread.
If a later page returns the authoritative target reply, it replaces the bounded
notification fallback in place.

Reaction taps retain the existing behavior: the reply sheet updates its local
copy immediately and forwards the original comment and emoji to the shared Feed
interaction owner. `ExploreCommentAuthorPresentation` remains the shared
presentation mapping used to resolve a comment avatar from the row, current
viewer, or post-author fallback.

## Dismiss-then-navigate contract

The Shell owns the private `ExploreNotificationDismissalDestination`, latest
open token, and shared `NavigationPath`. `ExploreNotificationsSheet` returns the
selected notification through its callback; it does not push a destination. The
Shell stages only a lightweight typed destination, dismisses the sheet, and
resumes the destination from the sheet's real `onDismiss`.

Post-backed activity retains only a post ID and re-resolves it from
`ExplorePostStore`. Community requests and Field-trip publications use their
typed identifiers. A media-recovery alert requests `AppRoute.scansLibrary` so
the root can replace Explore safely. Manual dismissal, a newer selection, or a
late post fetch invalidates the previous open token. Do not replace this handoff
with a fixed delay or navigation during sheet teardown.

Opening either Notifications sheet contributes one
`ExploreVideoPlaybackCoordinator` overlay token for the presented content's
mount-to-disappear lifetime. The sheet binding becoming false begins teardown;
it does not authorize early video resume.

An OS push tap is a separate entry point. `PushNotificationManager` validates
its lightweight identifiers and submits a typed route through
`AppRouteCoordinator`; this feature does not create a sibling root sheet or use
`NotificationCenter` as an application event bus.

## Focused tests

Tests mirror this owner under `MerianTests/Features/Explore/Notifications/`:

- `ExploreNotificationsViewModelTests` covers initial read clearing, read
  failure, transient pagination failure, availability filtering,
  refresh-over-pagination invalidation, failed-refresh cursor preservation, and
  stale mark-all completion.
- `ExploreReplyThreadViewModelTests` covers parent/target cursor traversal,
  sanitized fallback insertion and authoritative replacement,
  refresh-over-pagination, route replacement, reaction forwarding, and error
  mapping.
- `ExploreNotificationRowPresentationTests` locks aggregated, reaction,
  informational, and Field-trip copy plus icon/accent/disclosure mapping.
- `MerianTests/Features/Explore/Shared/ExploreCommentAuthorPresentationTests.swift`
  locks the secure comment-avatar fallback shared with Feed.

Wire decoding and endpoint request/response tests remain under
`MerianTests/Core/Network/`.

Run the focused matrix after changing this folder:

```bash
xcodebuild -scheme Merian -project Merian.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:merianTests/ExploreNotificationsViewModelTests \
  -only-testing:merianTests/ExploreReplyThreadViewModelTests \
  -only-testing:merianTests/ExploreNotificationRowPresentationTests \
  -only-testing:merianTests/ExploreCommentAuthorPresentationTests test
```

Manual parity must cover initial loading/error/empty states; pull-to-refresh
during pagination; mark all as read; notification settings; informational
follows; post, comment, mention, reaction, Community, media-recovery, and Field
trip destinations; unavailable reply fallback; reply pagination and reactions;
rapid selection/dismissal; VoiceOver; large Dynamic Type; Reduce Motion;
light/dark appearance; and video remaining paused until the final overlay
disappears.
