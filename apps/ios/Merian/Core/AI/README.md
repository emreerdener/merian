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

## First-Result Critical Path

The Analyze-tap timestamp is passed into `InferenceEngine.analyze` or
`analyzeNonVisual`, so image, video, audio, and describe paths share the
tap-to-first-render boundary without changing non-image submission behavior.
After the HTTP response arrives, response decoding and local persistence are
measured separately. The engine rebuilds `ActiveScanMedia`, commits
`speciesData`, and ends processing immediately after those required operations
succeed.

Scan milestones and Field trips start in follow-up work through
`ScanMilestoneCoordinator`. It first polls the existing `/check-scan-status`
ingestion ledger, so remote-persistence tools remain unavailable until the
server confirms the final saved scan ID. After the progress attempt it gathers
new achievement unlocks without presenting them early, evaluates the
`New to Naturebook` eligibility flag, and batches standard outing progress,
Seasonal Challenge progress, achievements, then the dictionary milestone. The
background completion path uses the same coordinator; scan-ID deduplication
prevents a live/background race from presenting the batch twice. Cache-miss
Wikipedia/GBIF enrichment is also outside first render.

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

External-reference suppressions are also an invariant: they target an immutable
media identity, never a species name, result index, or provider host. A denied
first URL must promote the next permitted URL rather than removing the species
or producing a synthetic censored carousel item.

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
