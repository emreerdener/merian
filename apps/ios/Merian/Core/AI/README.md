# Core AI

This directory owns reusable on-device analysis and the client half of Merian's
remote identification pipeline. Capture-specific composition remains under
`Features/Capture`; server prompts, schema, and Gemini calls remain under
`services/supabase/functions/_shared/identify/` and `identify-multimodal/`.

## Responsibilities

- `InferenceEngine` coordinates live analysis, result state, saved-media
  handoff, offline-queue adoption, enrichment, awards, and Field trips.
- `InferenceProcessingActor` performs CPU/file/database work away from the main
  actor, including image encoding, response parsing, and scan persistence.
- On-device Vision classification runs concurrently with the network request to
  provide scanning phrases. It does not replace or add a Gemini call.
- The marked Identify wire block in `InferenceEdgeDTOs.swift` is generated from
  the server's executable contract. It owns explicit `CodingKeys` and
  `init(from:)` implementations; do not hand-edit or extend those DTOs.

## First-Result Critical Path

The Analyze-tap timestamp is passed into `InferenceEngine.analyze` or
`analyzeNonVisual`, so image, video, audio, and describe paths share the
tap-to-first-render boundary without changing non-image submission behavior.
After the HTTP response arrives, response decoding and local persistence are
measured separately. The engine rebuilds `ActiveScanMedia`, commits
`speciesData`, and ends processing immediately after those required operations
succeed.

Scan milestones and Field trips start in follow-up work through
`ScanMilestoneCoordinator`. Current multimodal `200` already guarantees the
authenticated server scan row; the coordinator still polls `/check-scan-status`
for compatibility and before reading the server progress receipt. After the
progress attempt it gathers new achievement unlocks without presenting them
early, evaluates the `New to Naturebook` eligibility flag, and batches standard
outing progress, Seasonal Challenge progress, achievements, then the dictionary
milestone. The background completion path uses the same coordinator; scan-ID
deduplication prevents a live/background race from presenting the batch twice.
The server receipt is also the evidence authority: a weak unconfirmed
identification returns no Field trip credit, and evidence-downgrade
reconciliation returns no new milestone. The coordinator must not infer credit
from the local confidence badge or fabricate a toast for either case.
Primary cache-miss Wikipedia/GBIF resolution may occur before the server
response as part of durable success; follow-up reference hydration remains
outside response-to-first-render.

Every external reference URL applied by `InferenceEngine` is normalized through
`ExternalReferenceImagePolicy` before it reaches `SpeciesData` or persisted scan
state. The current exact rule treats iNaturalist media `605615444` as absent
while preserving later permitted URLs in source order. Direct GBIF hydration
must use this same boundary; do not write a provider URL straight into
`referenceImageUrl`.

`InsightSheetView` closes the user-perceived measurement with a one-shot UIKit
draw probe after the first result frame participates in a display pass. Do not
replace that boundary with only a SwiftUI state assignment or `onAppear`; those
measure scheduling, not pixels presented.

## Inference Invariants

Model choice is server-owned and must remain:

- Free: `gemini-2.5-flash`
- Pro: `gemini-2.5-pro`

Latency work must not change thinking budgets, prompts, response schema, image
resolution, output-token limits, or the single Gemini `generateContent` call per
scan. If measured Gemini time dominates, report it as the remaining latency
floor rather than silently changing these economics or behavior.

An explicit capture timeline is also a request invariant. `InferenceEngine`
projects the ordered image, standalone-audio, video, and description items once,
then uses that same projection for audio file order, `audioMediaItems`,
observation contexts, video paths, and `ownerMediaTimeline`. Both live visual and
live nonvisual paths must send the projection. Do not independently aggregate
audio paths or descriptors: their raw input positions are the durable identity
used by Edge validation and promotion.

External-reference suppressions are also an invariant: they target an immutable
media identity, never a species name, result index, or provider host. A denied
first URL must promote the next permitted URL rather than removing the species
or producing a synthetic censored carousel item.

## Generated Edge DTO Boundary

The canonical response descriptor lives at
`services/supabase/functions/_shared/identify/contract.ts`. It generates the
provider schema, executes server runtime validation, and generates the marked
Identify DTO block in `InferenceEdgeDTOs.swift`. The generated client boundary
includes nested DTOs, array and primitive types, wire `CodingKeys`, and explicit
decoders. Domain types remain separate and are populated after decoding.

For an intentional contract change, regenerate and validate from the repository
root:

```sh
make generate-edge-dto-contract
make validate-edge-dto-contract
```

Review the Swift diff. The validation lane compares the generated block exactly
and scans all of `apps/ios` for redeclarations or direct/aliased extensions of
generated DTOs. Root response fields remain optional to decode older cached
payloads and support staggered rollout; the Edge runtime validates the full
final response strictly before sending it.

## Entitlement response state

`EdgeResponseWrapper.entitlement` is optional so historical stored envelopes
remain decodable. A usable current response may carry the server's `plan_used`,
whether a complimentary credit was consumed, and the complete
entitlement-after snapshot. `InferenceProcessingActor` forwards that metadata
to `EntitlementManager` and reconciles the advisory daily meter from the
server's actual funding plan; it does not derive a trial or decrement a
complimentary counter locally.

A scan response is already behind the server's scan-and-required-media
durability fence. Local record persistence can still fail and enter exact-ID
recovery without undoing the authoritative server settlement. Stored replay
metadata is version-checked and cannot establish current-launch complimentary
access before `get_my_entitlement()` supplies the baseline.

Complimentary holds belong to the original `scanId`. Retry generations,
enrichment, Field Chat, and provider subcalls reuse that analysis and cannot
spend another credit. The joined server/client contract is
[Three Complimentary Pro Scans](../../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

## Live Attempt Ownership

`scanId` identifies durable work; it does not identify the current attempt.
Every queue-backed live submission also creates a UUID inference generation and
writes it to the scan-ingestion `OfflineJobRecord.metadataJSON` in the same
transaction as the queued scan. `InferenceEngine` captures that UUID in the
provider task and revalidates it at task entry, after external suspension
points, immediately before provider dispatch, and again at each persistence,
result-publication, failure-publication, notification, hydration, and
queue-cleanup boundary.

All user-facing inference modes are queue-backed before provider dispatch.
Online text-only Describe submissions use a zero-byte `.staged` row, so they
receive the same durable persistence fence and exact cleanup as media-bearing
captures rather than relying only on a process-local presentation token.

A queue-backed generation is single-use. `OfflineQueueManager` atomically
consumes it before any engine instance starts a provider pipeline, so a
duplicate submission is an idempotent no-op across the process. Cancellation or
a pre-provider capture exit registers its UUID in the manager's generation task
registry synchronously, before the asynchronous durable handoff acquires the
per-scan coordinator, so a repeated call cannot restart that UUID in the handoff
window. A registered retirement is excluded from the definition of a current
attempt immediately, fencing delayed persistence, UI publication, and cleanup
while the durable release is still pending. Transient durable-owner fetch or
save failures retain the retiring marker and retry with bounded backoff; they
neither reopen the UUID nor abandon a claim that would suppress recovery
indefinitely. Any intentional new attempt must first claim a newly generated
durable UUID.

Terminal failure handling follows the same ownership protocol. The handler
captures whether the full scan, presentation-attempt, and durable foreground
generation still match before registering synchronous retirement. Only that
proven owner may emit failure telemetry, record a circuit-breaker failure,
trigger an error haptic, or publish an error placeholder, and it does so without
another suspension between the ownership snapshot and terminal commit. A
cooperatively cancelled or replaced task therefore exits silently instead of
overwriting the replacement attempt.

### Queue-backed connectivity contract

Connectivity failure must be a queue handoff for an exact queue-backed
foreground generation, not a terminal Insight error. The required path
publishes the matching `queuedPresentationScanId`, stops live analyzing without
synthesizing `SpeciesData` or firing an error haptic, and lets the open Insight
bind a value snapshot of that durable row. Direct requests without a queue owner
may still show **Network timeout**. Exhausted server and unclassified failures
use **Analysis delayed / Scan saved** for queued work so an HTTP/provider
failure is never mislabeled as proof that the device is offline.

Local presentation ownership and durable provider ownership are separate
authorities. A path-monitor callback may retire the durable foreground
generation before URLSession reports its failure. The exact still-current sheet
must remain eligible to publish the queued handoff, while a newer scan,
background completion, or replaced presentation must still fence every delayed
mutation. Durable retirement alone is not permission to leave the current sheet
with no result and no queued context.

**Current source status (2026-08-10): remediated; release acceptance pending.**
The catch paths now use full durable ownership for provider results and generic
failures, but retain the exact local presentation UUID solely for the queued
connectivity acknowledgement. They release queue-backed recovery state
idempotently and never record device connectivity loss against the provider
circuit. Queue-backed `identifyMultiModal` has one 15-second foreground window
and returns its first transient transport failure; queue-less callers retain the
reviewed 90-second window and replay. The protected URLSession-level regression
retires durable ownership before releasing visual and nonvisual transport
errors, including data-path and session-disconnect variants, and separately
delivers `.timedOut` while the exact durable owner and path-satisfied state
remain active. The shared scan connectivity policy recursively recognizes
wrapped URL failures while keeping certificate, authentication, and ATS policy
errors out of both decisions even when a broader outer error would otherwise be
eligible. It proves exact queued routing, one request,
bounded handoff, eventual durable retirement, and row survival. A companion
case proves a successful transport response that loses durable ownership before
the post-request check also hands the exact local presentation to the queue; a
transport-owned cancellation does the same. **Analysis delayed** remains an
error placeholder through the explicit `.inferenceError` presentation role;
customer-facing title changes cannot alter that routing.
Do not describe this as shipped until the remaining exact-SHA and
physical-device closure gates in the
[live scan connectivity handoff incident](../../../../../docs/incidents/2026-08-live-scan-connectivity-handoff-gap.md)
pass.

Required-consent failure is handled before the generic transport branch in
both visual and nonvisual live inference. It publishes the temporary
**Approval needed / Scan saved** recovery state while the root returns the
account to Ready, and it never records a `CircuitBreakerManager` failure.
Repeated policy rejections therefore cannot impose the 15-minute network
cooldown after the user completes fresh approval. The durable queue remains the
owner of the original scan and media throughout this transition. After explicit
approval opens the lifecycle gate, it resumes at most the newest consent-blocked
row whose unreleased, dispatchable funding reservation proves the current
account and exact scan ID. Rows without that ownership proof remain paused in
Scans.

Provider admission is also separated from transport health for both live
pipelines. Exact `402 pro_required` presents **Upgrade needed / Scan saved**;
`429 ai_quota_daily_exceeded` requests the root paywall without publishing a
synthetic Insight result; and stable user/IP rate limits present **Retrying
shortly / Scan saved**. These handler-owned decisions do not advance the device
network circuit. The durable queue retains the observation behind the paywall
and continues to honor the server retry schedule; entitlement exhaustion
becomes explicit attention after the server proof refresh, while temporary rate
limits use the server's bounded retry delay.

Exact `400 observation_rejected` is terminal policy feedback, not a transport
failure. Both live pipelines present **Try another capture / Scan not
processed**, keep the state out of the device network circuit, and immediately
mirror the background queue's non-actionable failed disposition when durable
state is available. A failed durable transition leaves the normal background
owner eligible to apply the same terminal response safely; the rejected media
is never automatically redispatched as though connectivity had failed.

Live persistence and background retry/finalization share
`ScanInferencePersistenceCoordinator`. The live save validates both the
in-memory foreground generation, durable job generation, and provider result
scan ID while holding that coordinator. A valid confidence-zero response remains
a terminal no-record result, but queue-backed work accepts it only when the
provider echoed the exact scan ID; a mismatched response remains queued for
recovery rather than causing another attempt's work to be finalized. Successful
live cleanup passes an exact `ForegroundInferenceGenerationExpectation` to
`deleteQueuedScan`; the expectation is compared again after URLSession task
enumeration. A stale generation must return without cancelling tasks, clearing
task registries, or deleting the queued row. An unfenced deletion is reserved
for an explicit user/system request whose intended outcome is to cancel every
generation. If background recovery wins, it invalidates the exact live
presentation UUID before cooperatively cancelling that task, fencing any delayed
error or result commit as well as queue mutation. A SwiftData error while
loading the durable owner also fails closed; it is not treated as proof that the
job was deleted.

If a foreground request loses its HTTP response after the server completed the
scan, the engine retains the exact failed presentation scan ID independently of
`activeScanId`. A normal background response or `/check-scan-status` recovery
may hydrate only that retained ID, only when the provider/result or local record
echoes the same scan ID, and only when no newer foreground scan owns the
presentation. Known exact ingestion/quota replay conflicts use the temporary
customer state **Restoring scan / Safely saved** instead of the misleading
**Network timeout** placeholder; installed clients are protected primarily by
the server's idempotent `200` response replay.

Foreground still analysis sends inline image bytes with `r2ObjectKeys: []`. A
destination filename is not an uploaded staging source; advertising a synthetic
key causes strict server finalization to wait for an asset that cannot exist.
Older affected responses are repaired only by the server's exact owner-scoped
inline-manifest recovery contract. If a durable failure happens before any owner
row exists, the offline queue discards potentially consumed staging keys and
uploads its retained local media again.

Loading a persisted library record is also a presentation replacement.
`load(from:)` invalidates the exact live UUID, releases its deferred-upload
hold, cancels live provider/hydration work, and schedules durable handoff before
assigning the historical `activeScanId`. The queued capture remains intact for
background recovery.

## Verification

Focused tests live under `apps/ios/MerianTests/Core/AI/`. Network timing and
request-upload handoff coverage lives under `MerianTests/Core/Network/`; the
full server generation invariants are enforced by the Deno tests beside
`identify-multimodal`.

A queue-handoff regression is not valid when it throws from consent preflight
or another pre-request seam. It must dispatch through mocked URLSession
transport, retire the exact durable foreground generation before releasing the
transport error, and prove the same-ID sheet becomes `.queued` without a second
request, placeholder, haptic, circuit failure, or manual test cleanup of queue
ownership. The full matrix and release evidence requirements live in the
[incident](../../../../../docs/incidents/2026-08-live-scan-connectivity-handoff-gap.md).
