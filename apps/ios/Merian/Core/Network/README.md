# Core Network

This directory owns Merian's authenticated, certificate-pinned foreground
network client. Durable background uploads and replay scheduling live under
`Core/Data/OfflineSync`.

## `MerianNetworkClient`

- Builds authenticated requests to Supabase Edge Functions and retains the
  existing response/request DTO contracts.
- Uses one pinned `URLSession` for both inference and connection prewarming.
  `prewarmInferenceEndpoint()` sends `OPTIONS` to `/identify-multimodal`; an auth
  SDK request is not considered a prewarm because it uses another connection
  pool.
- Adds `X-Merian-Constrained-Network` for aggregate diagnostics without exposing
  the active interface or user identity.
- Reads privacy-safe `Server-Timing` and `X-Merian-Edge-Region` response headers.
- Records URLSession request-upload, time-to-first-byte-after-upload, and
  response-transfer intervals.

## Field Trip capture context

`getFieldTripCaptureContext()` posts `{"action":"capture_context"}` to the
authenticated `/field-trips` Edge Function and decodes the narrow
`FieldTripCaptureContextResponse`. The response contains standard outing/current
level metadata, aggregate progress, and unfinished target prompts only. It must
not contain scan evidence, media, location, or field notes.

`MerianNetworkClient` performs the request. `FieldTripCaptureGoalProvider` maps
the source DTOs into generic `CaptureGoal` values, and
`ActiveCaptureGoalStore` owns the five-minute freshness policy, per-account
cache, selected-goal persistence, refresh coalescing, and silent stale-data
retention. Capture never imports these Field Trip DTOs. Callers must never await
this request before starting the camera or accepting a capture. See
`docs/backend-and-data/05-api-contracts.md` and
`docs/features-and-hardware/25-field-trips.md`. The source-agnostic ownership
decision and future provider aggregation rules live in
`docs/rfcs/active-capture-goal-context.md`.

## Request-Body Completion

`performAuthenticatedRequest` accepts an optional, idempotent body-upload-
complete callback. `MerianRequestUploadDelegate` fires it from
`urlSession(_:task:didSendBodyData:...)` when all expected bytes have been sent.
Receiving the response is the fallback for protocols that do not deliver upload
progress; a transport failure fires it immediately.

For eligible live-camera still-image analysis this callback releases the durable
queue row for background upload after the inline body no longer competes for
uplink capacity.
The caller also installs a two-second fail-safe. Connectivity loss and app
backgrounding release ownership through `OfflineQueueManager` directly.

## Deferred Context

`updateScanContext` sends owner-authenticated late WeatherKit/geocoding data to
`/update-scan-context`, keyed by `scan_id`. It carries only supported optional
elevation, weather, and semantic-location fields and never resubmits media or
starts another identification.

## Failure Rules

Authentication failures propagate to callers; they are not converted to missing
headers. TLS pin failures, invalid HTTPS URLs, and response validation failures
remain fail-closed. Upload-completion callbacks release queue ownership on
failure, but they do not delete the durable row; the existing live-success path
alone performs queue cleanup and task cancellation.
