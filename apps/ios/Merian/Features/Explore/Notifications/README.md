# Explore Notifications

The `Notifications` directory manages the in-app social alerts for the Explore feature.

## Purpose
This area is responsible for displaying the notification center containing alerts for social interactions, such as when someone likes a user's post, comments on it, replies to a comment, or follows their profile.

## Architecture boundary

Explore notifications are server-backed user activity rendered inside the
already-mounted Explore feature. They are not `NotificationCenter` broadcasts
and must not be used as the app's process-local event bus. Opening the
notification center mounts an Explore-owned sheet, contributes one
`ExploreVideoPlaybackCoordinator` overlay token for the presented content's
exact mount-to-disappear lifetime, and dismisses that sheet before
pushing a selected post, comment thread, community request, or Field trip on
Explore's existing navigation stack. A media-recovery alert instead requests
`AppRoute.scansLibrary` so the root can replace Explore with Scans safely.

The selection is stored as a typed `ExploreNotificationDismissalDestination`.
The sheet owner resumes it only from `ExploreNotificationsSheet.onDismiss`;
post/reply focus, community navigation, Field-trip publication navigation, and
the root Scans route never run during sheet teardown. Async post preparation
must still prove both a latest-wins open token and the current notifications
sheet before staging a target. A post destination stores only its post ID and
re-resolves the bounded feed-store value after dismissal instead of retaining a
full post model through UIKit teardown. Manual dismissal, a newer tap, or a
stale fetch produces no later navigation. Do not replace this callback with an
elapsed animation delay.

An OS push tap is a separate entry point. `PushNotificationManager` validates
its lightweight identifiers and submits a typed `.explorePost`,
`.communityIdentification`, or `.scan` request through `AppRouteCoordinator`
with source `.pushNotification`. The Capture root serializes that request with
the one app-level sheet host; this feature must not create a sibling root sheet
or post an application-defined notification to perform the handoff.
