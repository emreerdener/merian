# Core Analytics

The `Analytics` directory manages the app's telemetry and product analytics infrastructure.

## Purpose
This area integrates PostHog-backed app analytics. It provides a unified, cross-feature API for tracking user events, performance metrics, and gamification telemetry without coupling feature modules directly to the third-party analytics SDK.

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
