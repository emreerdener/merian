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
  availability, telemetry, and logging, and it adapts the customer-safe error
  formatter from `Explore/Shared/Models`.
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

Comment/reply request construction lives in
`Core/Network/Endpoints/MerianNetworkClient+ExploreInteractions.swift`.
`ExploreReplyThreadDependencies` still adapts those reads, and the reply-thread
state owner still controls traversal, fallback, pagination, and generation
fencing. Notification catalog/count/read-state and push-registration request
construction lives in
`Core/Network/Endpoints/MerianNetworkClient+Notifications.swift`. Core
Notifications retains push-token/permission state, account-aware registration
coordination, and badge lifecycle state behind focused Services and the stable
push/badge facades. Explore Notifications Services and ViewModels retain their
catalog, pagination, mark-read, reply-thread, and presentation state. Neither
extraction changes the notification or navigation contract.

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

Reaction taps update the local copy immediately and await the shared Feed
interaction owner with the requested selected state. Success reconciles the
authoritative count; failure restores the prior reactions and presents an error.
Route generations prevent late responses from changing a replacement thread.
`ExploreCommentAuthorPresentation` remains the shared presentation mapping used
to resolve a comment avatar from the row, current viewer, or post-author
fallback.

## Dismiss-then-navigate contract

The Shell-owned `ExploreNotificationNavigationCoordinator` owns the lightweight
`ExploreNotificationDismissalDestination`, latest-open token, and separated
staged and pending destination state; `ExploreView` retains the shared
`NavigationPath`. `ExploreNotificationsSheet` returns the selected notification
through its callback; it does not push a destination. The coordinator stages
only a typed destination, the root commits the matching token before dismissing
the sheet or reporting a preparation error, and navigation resumes from the
sheet's real `onDismiss`. Dismissal invalidates any uncommitted staged state
without clearing a destination that was already committed for that `onDismiss`.

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

An OS push tap is a separate Core Notifications entry point.
`PushNotificationPolicy` validates its lightweight identifiers and
`PushNotificationManager` submits the typed route through `AppRouteCoordinator`;
this feature does not own APNs/system effects, create a sibling root sheet, or
use `NotificationCenter` as an application event bus.

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
- `MerianTests/Features/Explore/Shell/ExploreNotificationNavigationCoordinatorTests.swift`
  locks root destination mapping, latest-selection and outcome-commit fencing,
  and dismissal invalidation after a row callback leaves this feature boundary.

Wire decoding and endpoint request/response tests remain under
`MerianTests/Core/Network/`. `Endpoints/ExploreInteractionEndpointTests.swift`
rehomes the comment/reply request regressions; its transport suite covers read
retries and cancellation. Run the
[Core Network interaction matrix](../../../Core/Network/README.md#explore-interaction-verification)
when changing that shared transport boundary.
`Endpoints/NotificationEndpointTests.swift` covers catalog/cursor payloads,
count/read projections, and push preferences.
`NotificationAndPublicProfileEndpointTransportTests.swift` covers their typed
versus body-ignoring success, errors, refresh/replay, and cancellation. Run the
[notification/public-profile matrix](../../../Core/Network/README.md#notification-and-public-profile-verification)
when changing notification transport; feature lifecycle tests remain here.

Run the focused matrix after changing this folder:

```bash
xcodebuild -scheme Merian -project Merian.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:merianTests/ExploreNotificationsViewModelTests \
  -only-testing:merianTests/ExploreReplyThreadViewModelTests \
  -only-testing:merianTests/ExploreNotificationRowPresentationTests \
  -only-testing:merianTests/ExploreNotificationNavigationCoordinatorTests \
  -only-testing:merianTests/ExploreCommentAuthorPresentationTests test
```

Manual parity must cover initial loading/error/empty states; pull-to-refresh
during pagination; mark all as read; notification settings; informational
follows; post, comment, mention, reaction, Community, media-recovery, and Field
trip destinations; unavailable reply fallback; reply pagination and reactions;
rapid selection/dismissal; VoiceOver; large Dynamic Type; Reduce Motion;
light/dark appearance; and video remaining paused until the final overlay
disappears.

## Emoji reactions

Post reactions are grouped by emoji and route to post detail. Native
list/count/read and push-registration requests declare reaction support. Reply
reactions await the Feed interaction owner and reconcile or roll back their
local copy; they use the shared Unicode picker and paginated chips.

`supports_post_reactions: true` is sent by current native list, count,
mark-read, and push-registration adapters. Omission remains false for older
clients. Post reaction activity groups by recipient/post/emoji; additions update
unread state, removals recompute without pushing, and self/blocked/unavailable
activity is suppressed. Post ❤️ stays in the existing like path. Eligible pushes
require both device capability and Explore opt-in, with matching badge counts.

Notification reply pagination and mutation callbacks share a per-comment queue.
The sheet applies optimistic state, awaits Feed's authoritative result, and
restores its local copy with visible error feedback on failure. Generation and
viewer checks reject results from a replaced route/account. See the
[reaction verification matrix](../../../../../../docs/development-guides/08-testing-strategy.md#explore-emoji-reaction-verification).

Capability filtering applies to notification list/count/read RPCs and push
fanout. The existing authenticated Realtime subscription still observes own-row
changes in `explore_post_notifications`; it is not capability-filtered. Native
clients consume these as opaque `AnyAction` refresh signals and obtain display
rows/counts through the filtered endpoints. Do not treat a raw Realtime change
as a notification DTO or display it directly.
