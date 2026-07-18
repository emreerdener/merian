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

Award calculation and Field trips start in follow-up work. Field trips first
polls the existing `/check-scan-status` ingestion ledger, so remote-persistence
tools remain unavailable until the server confirms the scan. Cache-miss
Wikipedia/GBIF enrichment is also outside first render.

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

## Verification

Focused tests live under `apps/ios/MerianTests/Core/AI/`. Network timing and
request-upload handoff coverage lives under `MerianTests/Core/Network/`; the
full server generation invariants are enforced by the Deno tests beside
`identify-multimodal`.
