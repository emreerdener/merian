# Capture Submission

The `Submission` directory handles the visual transition between capturing data and viewing the result.

## Purpose
This area manages the UI and state during the network round-trip. It displays
the scanning overlay, animates status phrases driven by the concurrent on-device
`VNClassifyImageRequest`, handles local SwiftData queuing (`OfflineQueuedScan`)
if connectivity fails, and orchestrates the presentation of the final Insight
sheet.

## Analysis Submission Contract

`Analysis.submitActiveScan()` starts the user-perceived clock when Analyze is
tapped. It creates one stable `scan_id` and persists the ordered media timeline
to `OfflineQueuedScan` before live inference is allowed to start. A failed queue
acceptance is a hard failure: source files are cleaned up and the UI must not
pretend that the scan is analyzing or safely queued.

For an eligible online live-camera still scan with no audio or video, the
durable row is created with `startSyncImmediately: false`. The
shutter-prefetched WeatherKit/reverse-
geocoding task receives at most 150 ms after queue acceptance. If it is still
running, inference uses shutter-time coordinates, date/time, distance, and
cached telemetry. When the context task later finishes it updates both the local
queue and `/update-scan-context`; it never resubmits images or triggers another
Gemini call.

Gallery images and audio-bearing or video visual submissions retain the
existing full-context wait and immediate queue-sync race. They receive latency
instrumentation but no submission-behavior change in this pass.

The active live request temporarily owns the uplink. Its request-body completion
callback releases the queue row for normal background upload; a two-second
fail-safe covers missing progress callbacks. Request failure, connectivity loss,
or app backgrounding releases the row immediately, and relaunch naturally
clears the process-local suppression. Existing live-success cancellation and
queue cleanup remain authoritative when both paths complete. Recovery media may
finish staging while the live request awaits Gemini, but a separate foreground
inference claim prevents the queue from dispatching a second identification
call. Failure, cancellation, or backgrounding releases that claim and replays
any staged row. Staged replay checks the server ingestion ledger first and polls
an already-processing foreground job instead of issuing a duplicate model call.

## Latency Boundaries

The capture submission layer logs Analyze tap, durable queue commit, the still-
image context grace or unchanged non-visual context wait, and inference
dispatch. `MerianNetworkClient` measures upload/response transport,
`InferenceProcessingActor` measures parse and persistence, and
`InsightSheetView` records the first rendered result frame. Awards, Field trips,
and optional enrichment must not be awaited before that frame.

Still images use the accepted `NormalizedImageFocusRegion` to render four
detached white corner brackets and a dimmed exterior in the Insight carousel.
The brackets fade and resolve once, then remain static while a soft low-opacity
illumination band sweeps only inside the accepted region. The treatment remains
noninteractive and replaces the old full-image laser. Reduce Motion disables the
interior sweep. Images without a clear isolated subject use the uniform
analyzing tint, status phrase, and original full-image scan sweep—there is
no centered or full-image focus box. The full-image sweep is omitted whenever
an accepted focus region exists, so it never competes with the isolated-region
animation. Video, audio, and description animations retain their existing
behavior.
