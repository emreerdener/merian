# Explore Notifications

The `Notifications` directory manages the in-app social alerts for the Explore feature.

## Purpose
This area is responsible for displaying the notification center containing alerts for social interactions, such as when someone likes a user's post, comments on it, replies to a comment, or follows their profile.

## Architecture boundary

Explore notifications are server-backed user activity rendered inside the
already-mounted Explore feature. They are not `NotificationCenter` broadcasts
and must not be used as the app's process-local event bus. Opening the
notification center mounts an Explore-owned sheet, contributes one
`ExploreVideoPlaybackCoordinator` overlay token, and dismisses that sheet before
pushing a selected post, comment thread, community request, or Field trip on
Explore's existing navigation stack. A media-recovery alert instead requests
`AppRoute.scansLibrary` so the root can replace Explore with Scans safely.

An OS push tap is a separate entry point. `PushNotificationManager` validates
its lightweight identifiers and submits a typed `.explorePost`,
`.communityIdentification`, or `.scan` request through `AppRouteCoordinator`
with source `.pushNotification`. The Capture root serializes that request with
the one app-level sheet host; this feature must not create a sibling root sheet
or post an application-defined notification to perform the handoff.
