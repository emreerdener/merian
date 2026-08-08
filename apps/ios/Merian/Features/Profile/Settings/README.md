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

## Privacy and processing permissions

Google Gemini processing is required for Naturebook's core identification
experience. Permission is granted through the required onboarding disclosure,
and Settings intentionally provides no Gemini processing opt-out. A user who
does not permit that processing cannot use the scanner. The consent ledger and
inference gates still fail closed when required evidence is missing, outdated,
or revoked by historical or remote account state.

The first row in Settings → Resources is **Analytics & diagnostics**. Its binding
appends an immutable account-wide PostHog grant or revocation through
`ConsentManager`.
Absence of a grant is off. Withdrawal opts out and closes the SDK, synchronizes
across devices, and never changes core functionality. The displayed and applied
state comes from the provider-wide greatest accepted revision across all
disclosure versions. An older-disclosure revocation at that head remains off;
only a current-disclosure head grant can reopen PostHog.

That paragraph is the required behavior. The withdrawal transport/order and
offline ghost-account handoff findings are complete in source: reset-time
feature-flag work is rejected locally after the transport gate closes, and a
durable handoff suppresses analytics until local evidence is rebound, pushed,
refetched, and the queue removal is verified. Account restoration activates and
flushes the target ledger before refetch; Realtime has independent channel
ownership, bounded retry, and foreground repair; OAuth account replacement
suppresses analytics before session installation and reconciles the actual
session afterward. The final synchronization merge rechecks task cancellation,
observed user, Supabase SDK session, and synchronization generation before an
account-wide grant can alter the ledger or reopen capture. All tracked findings
are closed in source. Internal test builds may continue; keep public production
held until the same SHA passes the hosted iOS and Supabase candidate gates and
the external controls in the
[production consent readiness record](../../../../../../docs/legal/production-consent-readiness-2026-08-03.md)
are complete.

## Account deletion

`DeleteAccountSheet` calls the authenticated `safe-delete` Edge Function and
must treat every successful `2xx` response as an accepted deletion. A `200`
means relational cleanup, delayed R2 verification, and Auth removal were already
fully complete; a new request normally returns `202` because the durable
server-side reaper must sweep and later verify storage before deleting Auth.
Both responses are safe points for local sign-out and device-data cleanup.

Every successful response must also contain
`manual_provider_revocation_required`. When true, `DeleteAccountSheet` records
the durable app-level notice before sign-out. The root app then presents
Apple's Settings/support instructions on launch and foreground until the user
explicitly confirms removal. New Apple accounts normally use automatic
server-side revocation; this fallback exists for accounts authorized before a
refresh token could be captured. The confirmation sheet explains both paths.

Older binaries do not implement the required receipt field or durable notice.
App Store availability of the supporting build is not proof that those clients
received the fallback. Public promotion requires either an enforceable
minimum-supported-build control with a clear update path back to this in-app
deletion flow, or an independent server-delivered manual fallback.

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
The Apple-specific capture, deletion ordering, legacy fallback, and production
gate are canonical in
[`20-sign-in-with-apple-account-deletion.md`](../../../../../../docs/backend-and-data/20-sign-in-with-apple-account-deletion.md).

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

In a Debug simulator build, Settings → Developer → **Preview Pro scans** opens a
deterministic gallery of the real Settings card and Results badge. Its segmented
control covers three, two, one, and exhausted states. The gallery uses a local
presentation override and never mutates the signed-in account, server ledger,
or RevenueCat purchase state. Visible counters say “3 Pro scans remain” or “1
Pro scan remains”; internal entitlement code retains its complimentary names.

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
It may present the generic Explore feed only after onboarding and current
required consent are complete.
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
  (`Settings_PreviewFieldTripProgressToast`), which shows the objective artwork,
  goal-complete title, outing name, and typed tap destination used after a saved
  scan.

Use the Field trip preview at compact and large widths, with VoiceOver and
Reduced Motion, to verify wrapping, artwork readability, timeout, manual
dismissal, haptics, and the tap target. Preview payloads bypass RPCs, progress mutation,
achievement persistence, dictionary mutation, analytics, and local push
delivery.

The presenter is obtained from the `AppDIContainer` environment; Settings does
not construct or overlay a second milestone singleton. Its ordinary cache and
preference results are typed `ToastPayload` values rendered by
`merianSystemFeedback`. While Settings is the foremost mounted feedback host it
renders the shared milestone stack; dismissing Settings restores the prior host
without repeating haptics/VoiceOver or restarting the active timeout. Settings
places ordinary feedback at the bottom and milestone previews at the top, so
the shared modifier keeps both visible; same-alignment surfaces remain mutually
exclusive to prevent Z-plane collisions. Preview taps use the preview
container's environment-injected route coordinator and cannot enqueue a route
in the production container.
