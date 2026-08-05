# Core Analytics

The `Analytics` directory manages the app's telemetry and product analytics infrastructure.

## Purpose

This area integrates optional, consent-gated PostHog app analytics. It provides
a unified, cross-feature API without coupling feature modules directly to the
third-party SDK. The required contract makes `ConsentManager` the sole
lifecycle authority: without the latest account-wide grant, PostHog must not be
configured or identified and every capture call must be rejected. Withdrawal
must leave core functionality unchanged and shut down analytics without
starting another SDK request.

## Release status

The consent architecture is implemented but this release candidate is held.
`CONSENT-001` is complete in source: PostHog's dedicated
`URLSessionConfiguration` installs a closed-by-default, configured-host-only
`URLProtocol` gate. Every SDK setup receives a unique transport ID; only the
currently active ID is admitted, so reopening for a new grant cannot admit a
delayed reset request from an old SDK session. A grant opens its ID immediately
before setup. Withdrawal or a direct wrapper-level account transition disables
app capture and closes the gate before preserving `reset → optOut → close`, so
PostHog 3.69.0's reset-time feature-flag reload is cancelled locally. SDK access
is isolated behind `PostHogSDKClient`, and permission generations prevent stale
overlapping setup work from completing for a replaced account.

`CONSENT-007` is also complete in source: true-account OAuth replacement closes
analytics and consent Realtime before session installation, reconciles the
actual SDK session on success or failure, and generation-fences overlapping
logins. Target-account restoration keeps capture closed while pending actions
are pushed and authoritative state is fetched. Its final merge independently
rejects cancellation, observed-user, SDK-session, or synchronization-generation
drift before any old account grant can reopen analytics. This synchronization
generation fence is inside the mutation boundary. Hosted verification must
still prove zero setup, identification,
capture, or network activity before grant and after withdrawal/account change.
See the
[production consent readiness record](../../../../../docs/legal/production-consent-readiness-2026-08-03.md).

## Advisory local usage meter

`UsageManager` keeps the capture and offline-queue UX responsive, but its
`UserDefaults` values are not an authorization boundary. Every paid-model call
must first reserve server-owned quota through the Supabase database. A modified
client, cleared defaults, or a clock change cannot grant additional provider
work.

The local meter represents only the ordinary daily Flash allowance; it is not a
mirror of the three-scan lifetime grant. Complimentary Pro is always selected
before Flash when the server has unheld capacity, so a new account can receive
three Pro results plus one separate Flash result on day one. Users cannot spend
Flash manually to preserve a complimentary credit.

`FeatureFlag.unlimitedFreeScans.defaultValue` is `false`. DEBUG builds may
temporarily bypass the local meter from Settings → Feature Flags or
`MERIAN_DISABLE_FREE_SCAN_LIMIT=1`; Release and TestFlight builds ignore those
persisted overrides. The bypass never changes a database entitlement or the
server quota, so it is useful for UI testing but cannot create free provider
capacity.

The local meter may refund a staged scan after a client-side failure. The
authoritative server reservation is separate: provider attempts consume their
database quota, while a verified pre-provider no-op may transition its
reservation to `refunded`. Provider failure remains charged and transitions to
`failed`, allowing a new metered retry with the stable scan request key. Keep
`UsageManagerTests`,
`FieldTripsAvailabilityTests`, the Edge quota tests, and the pgTAP quota
contract aligned whenever this UX changes.

After a valid success envelope, `reconcileServerPlanUsed(_:scanId:)` uses the
authoritative `plan_used`: a complimentary or paid result refunds any optimistic
local Flash reservation, while an actual `free` fallback consumes it. The scan
ID makes this reconciliation idempotent. Complimentary holds settle separately
from provider quota—a terminal credit release does not refund a provider call
that was attempted. See
[Three Complimentary Pro Scans](../../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

## External Image Import

`AppTelemetry.trackExternalImageImport(outcome:)` emits one
`ExternalImageImport` event for receipt, staging, temporary quota/capacity
blocks, and coarse terminal failures. Its only feature-specific property is
`outcome`; the shared facade also adds `event_source = "ios_client"`.

Never attach filenames, file paths, image bytes, EXIF values, coordinates,
capture dates, Photos asset identifiers, scan IDs, or user IDs. The authoritative
event inventory and privacy boundary live in
`docs/features-and-hardware/03-gamification-and-telemetry.md`.

## Capture Goals

`AppTelemetry.trackCaptureGoalIndicator(action:source:)` emits one
`CaptureGoalIndicator` event for a shown indicator, an open, or a previous/next
selection. Only the source kind and coarse action are included. Do not attach
the goal prompt, goal ID, source instance ID/title, progress counts, route IDs,
or account identifiers.
