# 17. AI Engineering & LLMOps

Merian's inference engine uses Google's Gemini 2.5 architecture (Flash/Pro) running inside serverless Deno Edge functions to protect API keys and enforce structured output.

## Inference Layer Structure

The AI inference layer is split across three files under `merian/Core/AI/`:

- **`InferenceEngine.swift`**: The main engine. Coordinates upload confirmation, triggers the Edge function, and delivers results to `CameraViewModel`.
- **`InferenceProcessingActor.swift`**: An off-main-thread actor responsible for base64 encoding image data and parsing Edge responses.
- **`InferenceEdgeDTOs.swift`**: Codable DTOs used for Edge communication: `APIError`, `EdgeResponseWrapper`, and `EdgeResponse`.

## Generation Configuration Guardrails

- **Dynamic Token Truncation (Non-Biological Bounds)**: To reduce API costs and output token usage, the `merianResponseSchema` was relaxed. Nested biological objects (`taxonomy`, `insight_data`, `diagnostic_comparison`) were removed from the `required: []` array. A `systemInstruction` rule now tells Gemini to omit these structures — including `colors` and `group_tags` — entirely when `is_biological_subject = false`. Because the Swift `EdgeResponse` struct declares these sub-nodes as optionals (`?`), `JSONDecoder` collapses missing keys to `nil` without crashing, cutting token usage on non-biological payloads.
- **`group_tags` Output Field**: Gemini is instructed to return 2–4 plain-English categorical labels for the identified subject, ordered from broadest to most specific (e.g. `["bird", "songbird"]` for an American Robin; `["insect", "butterfly"]` for a Monarch). These are stored in the `group_tags TEXT[]` column of the `scans` table, decoded into `EdgeResponse.group_tags`, carried through `SpeciesData.groupTags`, and appended to `semanticTags` at save time. Combined with the `commonGroupName` mapping in `SearchDatabaseActor`, this allows users to search broad categories ("bird", "mammal") without needing to know species names or Latin taxonomy.
- **Universal Schema Enforcement**: The `merianResponseSchema` is applied across all `isProActive` tier boundaries, enforcing strict JSON compliance and consistent object nesting for both Free and Pro models.
- **Token Throttling (`maxOutputTokens: 800`)**: All production Edge bindings enforce `maxOutputTokens: 800`. This keeps the model focused on populating the JSON output rather than generating internal reasoning chains that can silently exhaust Edge execution time limits.
- **Telemetry Pruning**: Legacy ephemeral fields (`cameraPitchDegrees`, `compassHeading`, `relativeHumidity`, `uvIndex`, `isFlashFired`) have been removed from the `CaptureTelemetry` JSON payload, saving hundreds of tokens per request. Schema nodes like `key_differentiators` and descriptive enum schemas inside Deno are compressed into flat string arrays.
- **Low Temperature Constraints (`temperature: 0.1`)**: Biological identification requires deterministic output. The model temperature is hardcoded to `0.1` to minimize hallucination.
- **Multi-Capture Context Fusion**: The `identify` Edge function accepts an array of `r2ObjectKeys: string[]`. Deno fetches R2 presigned URLs and encodes them to base64 in a single serial `for…of` loop — each response body is consumed via `arrayBuffer()` individually and the running `totalBytes` counter is incremented by `arrayBuffer.byteLength` (actual post-consumption byte count) before moving to the next image. If the accumulated total exceeds 5 MB, the loop immediately returns HTTP 413. The two-loop pattern previously used (a first pass checking `Content-Length` headers, a second pass consuming bodies) was eliminated because chunked transfer encoding makes `Content-Length` absent on R2 responses, allowing arbitrarily large payloads to exhaust the 256 MB Deno V8 heap before any guard fired. Serial body consumption also prevents back-pressure across V8's I/O loop when multiple bodies resolve simultaneously. The resulting base64 strings are injected as distinct `inlineData` MIME parts into the Gemini prompt, supporting macro shots alongside wider environmental images.
- **Base64 Payload Guard**: Before the R2 fetch loop, the Edge function validates that the incoming `imageBase64s` array has no more than 5 entries and that the total base64 byte length does not exceed 7 MB (≈ 5 MB raw). Requests violating either bound are rejected with `HTTP 400` / `HTTP 413` before any I/O runs, protecting Deno memory and Gemini quota.
- **Background Ingestion Dead-Letter Logging**: The `runBackground` task that handles moderation, enrichment, and Postgres UPSERTs wraps its work in a structured `try/catch`. On failure, a JSON-structured log line is emitted via `console.error` including `event`, `user_id`, `scan_id`, `error`, and `ts` fields. This replaces the previous silent swallow of background errors and makes failures observable in Supabase Edge Function logs without exposing internals to the client.
- **Module-Level Gemini Client**: The `GoogleGenerativeAI` client and API key are instantiated once at module scope (`_genAI` / `_geminiApiKey`) rather than inside the `serve()` request handler. Deno reuses the same V8 isolate across warm invocations, so a module-scope singleton avoids re-creating the SDK object and its internal HTTP pool on every request.

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
