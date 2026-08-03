# Capture Submission

The `Submission` directory handles the visual transition between capturing data
and viewing the result.

## Purpose

This area manages the UI and state during the network round-trip. It displays
the scanning overlay, animates status phrases driven by the concurrent on-device
`VNClassifyImageRequest`, handles local SwiftData queuing (`OfflineQueuedScan`)
before network work begins, and orchestrates the presentation of the final
Insight sheet or durable queued state.

## Analysis Submission Contract

`Analysis.submitActiveScan()` starts the user-perceived clock when Analyze is
tapped. It creates one stable `scan_id` and persists the ordered media timeline
to `OfflineQueuedScan` before live inference is allowed to start. When online,
it also creates one foreground inference UUID and persists it on the
scan-ingestion job in the same queue transaction. The live engine receives the
same scan/generation pair. A failed queue acceptance is a hard failure: source
files are cleaned up and the UI must not pretend that the scan is analyzing or
safely queued.

For an eligible online live-camera still scan with no audio or video, the
durable row is created with `startSyncImmediately: false`. The
shutter-prefetched WeatherKit and reverse-geocoding task receives at most 150 ms
after queue acceptance. If it is still running, inference uses shutter-time
coordinates, date/time, distance, and cached telemetry. When the context task
later finishes it updates both the local queue and `/update-scan-context`; it
never resubmits images or triggers another Gemini call.

Gallery images and audio-bearing or video visual submissions retain their
immediate queue-sync race. Audio/video/Describe submission commits the
non-visual queue row synchronously before any environment-context await. It then
gives the pinned context task 150 ms for the live request and late-merges a
completed context locally and through `/update-scan-context`; weather or
geocoding can never prevent the local capture from becoming durable.

## Entitlement and fallback

Capture never shows the complimentary countdown. It uses
`RevenueCatManager.canStartProScan` only to expose modes that require a new
Pro-funded analysis. Video, multiple or mixed evidence, refinement, and other
Pro-only entry points open the soft paywall when unavailable.

Actual admission is a synchronous `@MainActor` funding claim keyed by the stable
scan ID and active account before any source file is written or foreground
inference starts. The claim subtracts unresolved local complimentary
reservations from the verified server snapshot; entitlement booleans do not
authorize queue insertion. One remaining credit can therefore create only one
local complimentary reservation. Its funding payload is saved on the durable
scan-ingestion job in the same acceptance flow.

An ordinary single-image, standalone-audio, or Describe submission can still
start under the advisory daily meter. The local claim mirrors the server
evidence shape: exactly one image, one standalone audio clip, or one description
with no video may reserve immediate or deferred Flash. When an earlier local
complimentary scan is unresolved, a later eligible scan is queued as deferred
and cannot run foreground inference. The scheduler establishes earlier holds,
performs one bulk funding-state read, and persists safe reclassification before
dispatch. The server still automatically selects paid Pro, then complimentary
Pro, then the independent daily Flash policy. The client cannot ask to preserve
a complimentary credit or override server fallback.

Complimentary-only modes stay locked until online entitlement verification
succeeds on every launch. RevenueCat paid-offline behavior remains available,
and ordinary offline Flash work continues to queue durably. A queued retry keeps
the same `scan_id`, so server replay and recovery reuse the original hold rather
than spending another complimentary scan. Proven local pre-dispatch failures
are durably released; ambiguous delivery stays reserved, and manual retry of
released work must make a fresh funding claim. See
[Three Complimentary Pro Scans](../../../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

## Field Trip Goal Preference

`CaptureGoalPreferencePolicy` may snapshot the visibly selected standard goal
when Field trips and the **Field trip goals** setting are enabled, visual Scan
is active, and Capture is not refining. `Analysis` performs the final media
gate: only camera still images with no gallery still, audio, or video preserve
the hint. Automatic single-shot, crop-confirmed, and manual submission share
this path. Gallery, mixed camera/gallery, Describe, Record, refinement, hidden
goal UI, and missing selections submit no preference.

The optional value is queued durably and later sent to Field trip progress; it
does not enter the identification request. It can choose the one credited item
inside that standard outing only. The server still evaluates every eligible
experience and ignores stale, unauthorized, completed, or nonmatching hints.

The active live request temporarily owns the uplink. Its request-body completion
callback releases the queue row for normal background upload only when the
expected foreground generation still matches; a two-second fail-safe carries the
same fence. Request failure, connectivity loss, or app backgrounding
synchronously retires that exact generation, and relaunch naturally clears
process-local upload suppression. Live success deletes the queue only with a
matching foreground-generation expectation. Recovery media may finish staging
while the live request awaits Gemini, but the durable foreground claim prevents
the queue from dispatching a second identification call. Failure, cancellation,
or backgrounding releases that claim and replays any staged row. Staged replay
checks the server ingestion ledger first and polls an already-processing
foreground job instead of issuing a duplicate model call.

## Latency Boundaries

The capture submission layer logs Analyze tap, durable queue commit, the still-
image or non-visual context grace, and inference dispatch. `MerianNetworkClient`
measures upload/response transport, `InferenceProcessingActor` measures parse
and persistence, and `InsightSheetView` records the first rendered result frame.
Awards, Field trips, and optional enrichment must not be awaited before that
frame.

After the result commit, foreground completion passes the final scan ID,
`SpeciesData`, and model container to `ScanMilestoneCoordinator`. Background
queue completion calls the same coordinator. It waits for remote scan
persistence and Field trip progress, deduplicates the two paths by final scan
ID, then batches standard outing progress, Seasonal Challenge progress,
achievements, and `New to Naturebook` in that order. This follow-up must remain
outside the first-result latency boundary.

Still images use the accepted `NormalizedImageFocusRegion` to render four
detached white corner brackets and a dimmed exterior in the Insight carousel.
The brackets fade and resolve once, then remain static while a soft low-opacity
illumination band sweeps only inside the accepted region. The treatment remains
noninteractive and replaces the old full-image laser. Reduce Motion disables the
interior sweep. Images without a clear isolated subject use the uniform
analyzing tint, status phrase, and original full-image scan sweep—there is no
centered or full-image focus box. The full-image sweep is omitted whenever an
accepted focus region exists, so it never competes with the isolated-region
animation. Video, audio, and description animations retain their existing
behavior.
