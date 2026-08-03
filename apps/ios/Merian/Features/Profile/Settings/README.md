# Settings

The `Settings` directory contains the user-facing configuration screens and preference toggles for the app.

## Structure

- **Views**: Contains the primary views like `SettingsTabView.swift` and modal flows like `DeleteAccountSheet.swift`.
- **Changelog**: Components and logic for presenting the bundled feature notes and release history.
- **Plan**: UI handling the RevenueCat subscription flows (free vs pro tier) and related upsells.
- **Feedback**: Forms and routing for user support and feedback submission.
- **Notifications**: Toggles for managing local and push notification preferences (e.g., species discoveries, achievements).
- **Components**: Reusable list rows, toggles, and section headers specific to the Settings layout.

## Purpose
This area provides users with control over their app experience. It manages
general preferences, the Capture workspace, geoprivacy, data export, and account
lifecycle (signing in/out and deletion). It operates in conjunction with the
`ProfileViewModel` and updates the app's global state and preferences through
the injected `AppSettings` boundary.

## Account deletion

`DeleteAccountSheet` calls the authenticated `safe-delete` Edge Function and
must treat every successful `2xx` response as an accepted deletion. A `200`
means relational cleanup, delayed R2 verification, and Auth removal were already
fully complete; a new request normally returns `202` because the durable
server-side reaper must sweep and later verify storage before deleting Auth.
Both responses are safe points for local sign-out and device-data cleanup.

The server owns all ordering and retry semantics. The app must not send a target
user ID, attempt to delete the Auth identity directly, or retry individual
cleanup phases. Account detachment and private-content clearing are verified
before Auth removal, while media deletion continues through the existing
durable storage-cleanup outbox.

Every submitted scan also contributes mandatory Scientific Data. Account
deletion leaves that observation as an ownerless tombstone with exact
coordinates/elevation, time, taxonomy, identification, environmental, quality,
and provenance facts unchanged. It removes account attribution, media, private
free-form notes, semantic/public location labels, device context, and custom
tags. `DeleteAccountSheet` must state both sides of this boundary and must not
describe account deletion as deleting every submitted scan. Geoprivacy governs
public display, not this restricted backend retention.

The complete boundary and required update procedure are canonical in
[`17-scientific-observation-retention.md`](../../../../../../docs/backend-and-data/17-scientific-observation-retention.md).

## Plan and prelaunch purchase testing

Settings → Plan is the canonical manual entry point for `PaywallView`. Every
release build enables the advisory local meter, while Supabase remains the
authoritative quota boundary. Debug builds can bypass only the local meter from
Settings → Feature Flags or with `MERIAN_DISABLE_FREE_SCAN_LIMIT=1`; the backend
still reserves quota and applies the durable plan limits. Purchase QA should
open Plan directly instead of relying on a quota-triggered presentation.

The paywall is ready only when RevenueCat's current offering resolves packages
for both `pro_week` and `pro_annual`. A successful RevenueCat login proves the
Supabase customer identity was linked, not that StoreKit returned products.
Simulator Test Store, local StoreKit, and TestFlight/App Store sandbox setup are
documented in
[`02-revenue-and-identity.md`](../../../../../../docs/features-and-hardware/02-revenue-and-identity.md#prelaunch-purchase-testing).

## Complimentary display and exhaustion

When the server's entitlement mode is cut over, Settings → Plan is one of only
two places that shows the complimentary countdown; Results is the other.
`PlanCard` uses the current-launch server snapshot to show scans remaining out
of three and explicitly keeps the separate daily Flash allowance visible. It
never calculates a calendar expiry.

After the third durable Pro result, the card shows exhaustion and an Upgrade to
Pro action. That result and all earlier stored Pro results remain fully
viewable. Only new Pro actions lock; an ordinary compatible capture can still
use the daily Flash policy. Before online launch verification succeeds,
complimentary-only actions remain locked, while paid RevenueCat offline access
is preserved.

The paid **7 Day Pass** product, price treatment, and purchase copy are
unchanged. Public Pro badges continue to use paid status rather than
complimentary functional access. See
[Three Complimentary Pro Scans](../../../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

## Preference layout

The top general-preferences section begins with Theme. **Open Explore on
launch** follows Theme and sits directly above Notifications. The toggle uses
`safari.fill` and the user-facing description:

> Show Explore when you launch Naturebook. Close it to return to Scan, Record,
> or Describe.

The setting is opt-in. `opensExploreOnLaunch` registers a `false` default in
`UserDefaults`, persists through `AppSettings`, and participates in
`reloadFromDefaults()` so externally changed defaults are reflected in the
running settings model.

The section previously named **Capture** is now **Workspace**. It continues to
own Camera, Audio, **Reorder modes**, Field trip goals, and confirmation
preferences; the rename does not move those controls or change their behavior.

### Reorder modes

`captureModeOrderRaw` stores a comma-separated permutation of `visual`, `audio`,
and `describe`; the registered default is `visual,audio,describe`.
`CaptureMode.userOrder(from:)` ignores unsupported values and appends any
missing supported modes. `CaptureWorkspaceView` writes that healed sequence
back when necessary. The Settings reorder UI itself always emits one entry per
supported mode.

The workspace samples the first decoded mode in its initializer. Therefore a
fresh workspace opens directly into the user's first mode, whether that is
Scan, Record, or Describe. Audio-first does not start the camera, and
Description-first mounts the text workflow immediately. Reordering while the
workspace already exists preserves the active mode and reanchors that page in
the new sequence; the new first mode becomes the default on the next fresh
workspace launch.

## Fresh-launch contract

`MerianApp` samples `opensExploreOnLaunch` once when a new process is created.
It may present the generic Explore feed only after onboarding is complete.
Returning from the background never resamples the preference and never reopens
Explore.

Explicit user intent always outranks the generic launch destination. A Photos
or Files image handoff dismisses Explore and continues through the normal
staging/crop workflow. Deep links and tapped notifications replace the generic
feed with their requested Explore post, community request, scan Insight, or
Scans library destination. While the initial Explore sheet is visible, Capture
does not start camera hardware; dismissing the sheet returns to the configured
Scan, Record, or Describe mode. Presenting Explore also marks its one-time
**New** chip as seen.

## DEBUG milestone previews

Developer settings can enqueue representative payloads through the production
`MilestoneToastPresenter` without changing user progress or notification
authorization:

- achievement previews, including long-title coverage;
- `Preview New to Naturebook notification`
  (`Settings_PreviewNewToMerianNotification`); and
- `Preview Field trip progress toast`
  (`Settings_PreviewFieldTripProgressToast`), which shows the contextual copy
  and credited `GoalProgressRing` used after a saved scan.

Use the Field trip preview at compact and large widths, with VoiceOver and
Reduced Motion, to verify wrapping, ring readability, timeout, manual dismissal,
haptics, and the tap target. Preview payloads bypass RPCs, progress mutation,
achievement persistence, dictionary mutation, analytics, and local push
delivery.

## Beta offline-queue diagnostics

Debug and TestFlight builds expose **Beta Diagnostics** in Settings only for
`erdener.emre@gmail.com`. Generate the artifact after an offline/reconnect
smoke, then use **Share offline queue diagnostics** before deleting the tested
observation. The bounded JSON contains
app version/build, embedded source revision/fingerprint/state, queue/job
identifiers, lifecycle kinds, timestamps, retry/error codes, HTTP status, and
server status/stage. Only canonical lowercase machine tokens survive in the
retained error/status/stage fields. It never exports media paths or payload
contents, descriptions, Field notes, location/GPS, raw metadata, or arbitrary
persisted error/event messages. App Store builds do not expose this control.
The artifact declares `formatVersion: 1`; jobs, scans, and events are each
capped at 500 rows, and caller-supplied event limits are clamped to 1...500 so
zero cannot accidentally mean “unlimited.” The temporary file uses complete
data protection; refreshing the artifact removes the previous Settings export.
