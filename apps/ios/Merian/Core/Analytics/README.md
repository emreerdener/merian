# Core Analytics

The `Analytics` directory manages the app's telemetry and product analytics infrastructure.

## Purpose
This area integrates PostHog-backed app analytics. It provides a unified, cross-feature API for tracking user events, performance metrics, and gamification telemetry without coupling feature modules directly to the third-party analytics SDK.

## Advisory local usage meter

`UsageManager` keeps the capture and offline-queue UX responsive, but its
`UserDefaults` values are not an authorization boundary. Every paid-model call
must first reserve server-owned quota through the Supabase database. A modified
client, cleared defaults, or a clock change cannot grant additional provider
work.

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
