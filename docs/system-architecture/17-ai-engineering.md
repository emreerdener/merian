# 17. AI Engineering & LLMOps

Merian's inference engine uses Google's Gemini 2.5 architecture (Flash/Pro) running inside serverless Deno Edge functions to protect API keys and enforce structured output.

## Inference Layer Structure

The AI inference layer is split across three files under `merian/Core/AI/`:

- **`InferenceEngine.swift`**: The main engine. Coordinates upload confirmation, triggers the Edge function, and delivers results to `CameraViewModel`.
- **`InferenceProcessingActor.swift`**: An off-main-thread actor responsible for base64 encoding image data and parsing Edge responses.
- **`InferenceEdgeDTOs.swift`**: Codable DTOs used for Edge communication: `APIError`, `EdgeResponseWrapper`, and `EdgeResponse`.

## Generation Configuration Guardrails

- **Dynamic Token Truncation (Non-Biological Bounds)**: To reduce API costs and output token usage, the `merianResponseSchema` was relaxed. Nested biological objects (`taxonomy`, `insight_data`, `diagnostic_comparison`) were removed from the `required: []` array. A `systemInstruction` rule now tells Gemini to omit these structures entirely when `is_biological_subject = false`. Because the Swift `EdgeResponse` struct declares these sub-nodes as optionals (`?`), `JSONDecoder` collapses missing keys to `nil` without crashing, cutting token usage on non-biological payloads.
- **Universal Schema Enforcement**: The `merianResponseSchema` is applied across all `isProActive` tier boundaries, enforcing strict JSON compliance and consistent object nesting for both Free and Pro models.
- **Token Throttling (`maxOutputTokens: 800`)**: All production Edge bindings enforce `maxOutputTokens: 800`. This keeps the model focused on populating the JSON output rather than generating internal reasoning chains that can silently exhaust Edge execution time limits.
- **Telemetry Pruning**: Legacy ephemeral fields (`cameraPitchDegrees`, `compassHeading`, `relativeHumidity`, `uvIndex`, `isFlashFired`) have been removed from the `CaptureTelemetry` JSON payload, saving hundreds of tokens per request. Schema nodes like `key_differentiators` and descriptive enum schemas inside Deno are compressed into flat string arrays.
- **Low Temperature Constraints (`temperature: 0.1`)**: Biological identification requires deterministic output. The model temperature is hardcoded to `0.1` to minimize hallucination.
- **Multi-Image Context Fusion**: The `identify` Edge function accepts an array of `r2ObjectKeys: string[]`. Deno fetches multiple presigned S3 URLs concurrently via `Promise.all()`, encodes the results as base64, and injects them as distinct `inlineData` MIME parts into the Gemini prompt, supporting macro shots alongside wider environmental images without payload timeouts.

## On-Device Pre-Classification & Scanning Phase UX

While the Edge inference round-trip runs (typically 6–11s), `CameraViewModel` runs a concurrent `VNClassifyImageRequest` on-device to drive the fullscreen scanning overlay's status pill text.

### Phase Rotation System

`classifySubjectLocally(from:)` starts a **generic phrase series** immediately ("Scanning subject...", "Detecting morphological features...", etc.) so the overlay is never blank. Concurrently, `VNClassifyImageRequest` executes on a `Task.detached(priority: .userInitiated)` background thread (typically < 100ms). If Vision returns a confident subject category, a **subject-specific phrase series** is queued. Phrases rotate every 2.3 seconds via a cancellable `phaseRotationTask`.

### Subject-Specific Series Qualification

A specific phrase series is only activated if all three conditions are met:

1. **Confidence threshold** — the top `VNClassificationObservation` must score ≥ 0.65 (raised from 0.50 to reduce cross-category misclassification)
2. **Margin guard** — the top observation must lead the second-best by ≥ 0.15; split/ambiguous results (e.g., 0.52 bird / 0.48 plant) stay on the generic series
3. **3-second minimum delay** — even when Vision qualifies, the specific series is held for 3 seconds before replacing the generic one; this guarantees the user always sees neutral phrases first and limits the visible duration of an incorrect category label to the back half of the scan

If `isAnalyzingFullscreen` has already been set to `false` by the time the 3-second hold expires (fast network response), the switch is silently dropped.

### Supported Categories

Subject-specific series exist for: birds, insects/arthropods, arachnids, fungi/lichen, flowering plants, trees/conifers, cacti/succulents, general plants, reptiles, amphibians, fish, and mammals. Each series is 8 phrases long, starting with moderately general observations and progressing to field-specific terminology. Unrecognised or low-confidence subjects fall through to the generic series.
