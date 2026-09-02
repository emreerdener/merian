# Capture Submission

The `Submission` directory owns admission and durable dispatch after a staged
Capture observation is ready to analyze.

## Purpose

This area normalizes staged media, admits it to the durable SwiftData queue
(`OfflineQueuedScan`) before live work begins, coordinates visual and nonvisual
foreground inference, and prepares the existing Insight or queued presentation.
Shell owns the mounted UI and presentation timing; `InferenceEngine` owns
provider dispatch and its concurrent on-device `VNClassifyImageRequest` status
phrases.

## Ownership

- `Models/` owns deterministic admission, media, goal-preference, and latency
  policy plus the normalized staged payload and sendable environment-context
  snapshot. It also owns `CaptureSubmissionMediaTimeline`, the aligned
  `CaptureSubmissionMediaProjection`, and the hand-written `Identify*` request/
  replay descriptors. Staging owns chronological draft nodes; Submission alone
  maps those nodes into live and durable transport values.
- `Services/` composes narrow live admission and context closures, owns the 150
  ms one-shot context race, formats submission telemetry, and is the only
  Submission layer that adapts `/update-scan-context`. The deferred-context
  adapter persists locally before remote delivery and performs at most one
  remote retry after 500 ms; endpoint, transport, or task cancellation is
  terminal and does not trigger that retry.
- `ViewModels/` contains responsibility-specific `CaptureWorkspaceViewModel`
  extensions for visual, nonvisual, Describe, admission, and presentation
  orchestration. These extensions issue no endpoint calls.

Submission intentionally has no Views or Components. UI-only selection,
animation, sheet, focus, and cancellation timing remain with Capture Shell and
the modality views. Mirrored tests live under
`MerianTests/Features/Capture/Submission/`; an architecture suite enforces these
boundaries and the 600-line production-file review guard.

`CaptureSubmissionMediaTimelineTests` locks chronological staging conversion,
legacy fallback order, and snapshot cleanup.
`CaptureSubmissionMediaProjectionTests` locks interleaved video/standalone audio
alignment, sparse persisted source indexes, compact indexing after omitted
inputs, local Codable provenance, network-key omission, focus lookup, and
descriptor factories. These are hand-written request/replay values rather than
generated response DTOs; moving them here changes no request field, enum raw
value, JSON key, persistence schema, or replay rule.

For visual scans, submission passes only the first visual item's existing focus
region with the primary inference image to `InferenceEngine`. The engine starts
the exact visual-presentation session in `InferenceLocalAnalysisCoordinator`;
that private owner uses `LocalVisualAnalysisImageBuilder` to derive one 512 px
local image, applies the accepted padded focus region when present, and
otherwise uses the full square. Apple Vision and the deterministic pixel-trait
extractor reuse that derivative; the extractor samples it at 32×32 pixels to
produce five bounded palette, color-intensity, tone, contrast, and surface cues.
It never analyzes the second capture locally or changes the ordered images sent
to Gemini. Audio-only and Describe submissions retain their established
analyzing copy.

## Submission Contract

`CaptureWorkspaceViewModel.submitStagedCapture(...)` starts the user-perceived
clock when Analyze is tapped. The caller-scoped admission preview may suspend,
so staged input remains intact and its captured snapshot is revalidated before
the visual path clears buffers or initiates the queue. Submission then creates
one stable `scan_id` and persists the ordered media timeline to
`OfflineQueuedScan` before live inference is allowed to start. A still-online
foreground route also creates one foreground inference UUID and persists it on
the scan-ingestion job in the same queue transaction; a queue-only route does
not. The live engine receives the same scan/generation pair. A failed queue
acceptance is a hard failure: source files are cleaned up and the UI must not
pretend that the scan is analyzing or safely queued.

The context lookup captured from the shutter or recorder has one live consumer.
Submission cancels it whenever queue acceptance fails or a pre-dispatch branch
hands sole ownership to the durable queue, including queue-only admission,
connectivity loss, supersession, and an unavailable foreground generation. Only
a lookup that loses the 150 ms grace race remains alive for the late-context
merge. That late task retains the injected service and bounded telemetry inputs,
not the workspace view model or full display-image collection. A primary gallery
image cancels any irrelevant live-device lookup and uses only its embedded
historical context.

For an eligible online live-camera still scan with no audio or video, the
durable row is created with `startSyncImmediately: false`. The
shutter-prefetched WeatherKit and reverse-geocoding task receives at most 150 ms
after queue acceptance. If it is still running, inference uses shutter-time
coordinates, date/time, distance, and cached telemetry. When the context task
later finishes, `CaptureSubmissionDeferredContextService` updates the local
queue first and then `/update-scan-context`, retrying that remote update once
after 500 ms when necessary. It never resubmits images or triggers another
Gemini call. The 150 ms value bounds only the optional environment-context wait;
it is not a total tap-to-dispatch deadline. Existing telemetry preparation,
including optional LiDAR/Vision size estimation, still runs after that race.

The online check is repeated after that 150 ms grace because the path monitor's
earlier value is advisory and connectivity may change while context resolves. An
unavailable exact foreground generation is retired as well, so its durable owner
cannot suppress queue recovery after no live request starts. Known offline state
before the Insight opens stays in Capture with a queued toast. If connectivity
or ownership changes during the grace, Capture changes the open sheet to
**Queued for later**.

The same customer contract applies after provider dispatch: the first
queue-backed transport failure must relinquish live ownership and change the
exact open sheet to **Queued for later**, with no synthetic **Network timeout**
result or error haptic. A direct request with no durable queue owner may still
use timeout recovery copy. Server/provider failures use **Analysis delayed /
Scan saved** and remain distinct from connectivity.

**Current source status (2026-08-09): remediated; release acceptance pending.**
The post-grace/pre-dispatch and post-dispatch branches now converge on the same
exact-ID queued presentation. The post-dispatch engine may acknowledge queue
takeover using only its still-current local presentation after connectivity
monitoring retires durable provider ownership, and queue-backed Identify returns
its first transport failure without an inline replay. URLSession-level visual
and nonvisual race tests protect the ordering. Exact-SHA and device validation
remain release blockers in the
[live scan connectivity handoff incident](../../../../../../docs/incidents/2026-08-live-scan-connectivity-handoff-gap.md).

Gallery images and audio-bearing or video visual submissions retain their
immediate queue-sync race. Audio/video/Describe submission commits the
non-visual queue row synchronously before any environment-context await. It then
gives the pinned context task 150 ms for the live request and late-merges a
completed context locally and through `/update-scan-context`; weather or
geocoding can never prevent the local capture from becoming durable.

Audio queue admission is stricter than playback import. Every new standalone or
video-companion inference reference must resolve to a local, nonempty,
structurally supported WAV within the byte budget before submission claims
funding or persists `OfflineQueuedScan`; queue upload preflight repeats the same
check. Historical refinement is a separate asynchronous boundary: it may resolve
a local or secure remote WAV/M4A reference, materialize a new canonical WAV
sidecar, and then submit that local file. It must never forward an HTTPS string
through a generic file-path API. Missing historical visual media can fall back
to standalone audio, a video companion track, or description in timeline order.
Pre-WAV rows already persisted by older builds are owned by the durable repair
state machine documented in [Core Data](../../../Core/Data/README.md), not by
this presentation layer.

## Entitlement and fallback

Capture never shows the complimentary countdown. It uses
`RevenueCatManager.canStartProScan` only to expose modes that require a new
Pro-funded analysis. Video, multiple or mixed evidence, refinement, and other
Pro-only entry points open the soft paywall when unavailable.

Before a camera shutter, audio recorder, or staged submission can begin work,
online Capture calls the authenticated, caller-scoped
`get_my_scan_admission_preview(...)` RPC. A daily-allowance or Pro-access denial
opens the existing root paywall immediately and leaves staged input untouched;
Capture does not start hardware, create a queue row, open Insight, or invoke
inference. Flash eligibility is true only for one ordinary image, standalone
audio clip, or description; video, mixed/multiple evidence, and refinement
preflight as Pro-only. The RPC is a short-lived, read-only UX preview, not a
reservation.

The preview uses a dedicated ephemeral transport with an exact two-second
request/resource bound, no connectivity wait, no cache, and no inline retry. If
that transport reports a classified connectivity failure while reachability is
still optimistic, current local eligibility may admit capture only onto a
queue-only route. Submission persists the normal `OfflineQueuedScan`, starts no
foreground inference generation, opens no analyzing Insight, and leaves the
durable scheduler as the sole retry owner. Known-offline Capture uses the same
local-meter route without calling the RPC. This prevents captive, black-holed,
or stale-path Wi-Fi from turning an otherwise saveable observation into a
pre-queue network-timeout failure.

The fallback is intentionally narrow. Cancellation, a missing or malformed row,
authentication/TLS failure, and server failure preserve staged input and show
retry feedback; they cannot masquerade as offline admission. A valid quota/plan
denial still opens the paywall. The later `reserve_ai_quota(...)` transaction
remains authoritative, so an exact `429` from a cross-device race still replaces
Insight with the paywall as a recovery fallback.

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
than spending another complimentary scan. Proven local pre-dispatch failures are
durably released; ambiguous delivery stays reserved, and manual retry of
released work must make a fresh funding claim. See
[Three Complimentary Pro Scans](../../../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

## First-scan consent boundary

A new account's first ordinary scan is not supposed to enter a no-scans-left
state. Consent is checked before the separate paid Pro → included Pro → daily
Flash admission order. Before Capture can construct the first Identify request,
the client uploads pending adult, Terms, and Gemini evidence for the active
anonymous account and verifies those rows plus the all-version Gemini head in a
fresh fetch.

If that proof is absent—or the handler returns exact
`403 ai_consent_required`—the observation remains durable with all media, but
automatic inference stops. The affected account returns to Ready for fresh
head-anchored approval. **Start scanning** resumes at most the newest row whose
unreleased, dispatchable funding reservation matches the current account and
exact original scan ID; provider dispatch still waits for another authoritative
fetch. Capture must not show the paywall, daily-limit copy, or an unchanged
**Retry now** loop for this code. If the insight presentation remains visible
during the root transition, it shows **Approval needed / Scan saved** instead of
**Network timeout**. Consent-policy failures never advance the network circuit
breaker, so fresh approval is not followed by an artificial cooldown. The full
incident and release test are documented in the
[first-scan consent-policy incident](../../../../../../docs/incidents/2026-08-first-scan-consent-policy-retry-loop.md).

The adjacent provider-admission codes keep their own recovery UX. Exact
`402 pro_required` shows **Upgrade needed / Scan saved**; daily allowance
exhaustion replaces the open Insight sheet with the existing root paywall and
never publishes a **Daily limit reached** result; and stable user/IP rate limits
show **Retrying shortly / Scan saved**. None are labeled as network timeouts or
advance the device network circuit. The queued observation remains the recovery
owner behind the paywall, with `402` becoming explicit attention and `429`
honoring the server retry delay. These transient values carry the explicit
`.inferenceError` `SpeciesData.presentationRole`; UI routing never derives their
meaning from the displayed title.

Exact `400 observation_rejected` requires different source media. It presents
**Try another capture / Scan not processed**, does not advance the network
circuit, and mirrors the background queue's terminal non-actionable state
instead of retrying the rejected observation as a connectivity failure.

Once a scan is durable, Capture does not own an ad hoc retry timer. The shared
queue policy uses a five-second minimum, jittered exponential backoff, a
30-second ordinary local maximum, and ten automatic scan-analysis attempts. Safe
server `Retry-After` and status `retry_after` values remain authoritative
minimums even when they exceed 30 seconds within the existing safety bound.
Maintenance and reconciliation retain their separate 15-minute maximum, and
existing stored deadlines are not rewritten.

## Field Trip Goal Preference

`CaptureGoalPreferencePolicy` may snapshot the visibly selected standard goal
when Field trips and the **Field trip goals** setting are enabled, visual Scan
is active, and Capture is not refining. Submission performs the final media
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

That same request-body completion callback is the earliest point at which the
injected Foundation visual-cue provider may start. The callback only marks the
current scan/generation as eligible; it never waits for model loading or a
stream. Vision may run before dispatch, but richer on-device work therefore
cannot delay Gemini upload. Result arrival and every ownership handoff fence
local producers without awaiting them. A queue transfer is accepted only from a
typed prepared or active presentation owner. Prepared visual work transfers the
generic rotating deck without media; active visual work additionally requires
the exact attempt generation and can carry only already-validated ephemeral
phrases and presentation-owned media. Audio and Describe owners are nonvisual
and never inherit either. Dismissing the Insight invalidates local presentation
state but deliberately leaves durable Gemini, upload, persistence, and result
recovery work running.

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
The brackets fade and resolve once while a soft low-opacity illumination band
sweeps only inside the accepted region. Users may move the frame or resize it
from any corner; those presentation-only edits do not change the queued region
or the already-dispatched AI request. Focus metadata and interaction state stay
attached to the same scan and still-image source across queue refreshes and the
live-image-to-persisted-path handoff. Reduce Motion disables the interior sweep.
Images without a clear isolated subject use the uniform analyzing tint, status
phrase, and original full-image scan sweep—there is no centered or full-image
focus box. The full-image sweep is omitted whenever an accepted focus region
exists, so it never competes with the isolated-region animation. All sweep
positions are derived from the active animation timeline rather than a retained
one-shot animation transaction, so carousel updates and foreground re-entry
cannot strand a band at its last rendered position. Video, audio, and
description animations retain their existing behavior.
