# 17. AI Engineering & LLMOps

Merian's inference engine uses `gemini-2.5-flash` (free tier) and `gemini-2.5-pro` (Pro tier) running inside serverless Deno Edge functions to protect API keys and enforce structured output.

## Inference Layer Structure

The AI inference layer is split across three files under `merian/Core/AI/`:

- **`InferenceEngine.swift`**: The main engine. Coordinates upload confirmation, triggers the Edge function, and delivers results to `CameraViewModel`.
- **`InferenceProcessingActor.swift`**: An off-main-thread actor responsible for base64 encoding image data and parsing Edge responses.
- **`InferenceEdgeDTOs.swift`**: Codable DTOs used for Edge communication: `APIError`, `EdgeResponseWrapper`, and `EdgeResponse`.
- **`InferenceEdgeDTOs.swift`** also declares `EnrichScanResponse` — the `Codable` DTO for the `enrich-scan` Edge Function response, with nested `EnrichData` and `DiagnosticData` structs.

### Enrichment Pipeline (`isEnrichmentLoading` / `fetchAndApplyEnrichment`)

After a successful biological scan, `InferenceEngine` automatically fires `fetchAndApplyEnrichment(modelContext:)` for all users:

1. Sets `isEnrichmentLoading = true` — `SpeciesInsightsCard` observes this via `@Environment(InferenceEngine.self)` and shows an animated loading skeleton.
2. Calls `MerianNetworkClient.shared.fetchEnrichment(scanId:scientificName:)` → POST `/enrich-scan`.
3. On success, patches `speciesData.habitatDescription`, `speciesData.globalDistributionRegions`, and (when non-nil) `speciesData.gbifTaxonKey` in-place on `@MainActor`, triggering a live UI update without reopening the sheet.
4. If `confidenceScore < 0.85` and the response contains `diagnostic_comparison`, patches `speciesData.diagnosticComparison` in-place.
5. Persists all fields to `LocalScanRecord` via `BackgroundDatabaseActor.updateScanWithEnrichment` on a background Task.
6. Sets `isEnrichmentLoading = false` (via `defer`).

`InferenceEngine.load(from:)` triggers enrichment for historical records that are missing `habitatDescription`, `gbifTaxonKey`, or have a low-confidence score without a cached diagnostic.

## Generation Configuration Guardrails

- **Edge Native Router**: The `/identify` Edge function now operates as an intelligent orchestrator rather than a blind proxy. It intercepts the "Skinny" multi-modal vision payload (which strictly handles image classification without expensive dictionary string generation) and immediately checks the `species_dictionary` table.
   - **Cache Hit**: If the species already exists in the dictionary with a valid `kingdom`, the function skips all generation loops and splices the stored data directly into the response.
   - **Cache Miss**: If this is the first time the species is discovered globally, the `/identify` API fires `fetchStaticEncyclopedicData` (a text-only Gemini 2.5 Flash request) and `fetchExternalEnrichment` (Wikipedia & GBIF polling) concurrently via `Promise.all`. This entirely hides the secondary network latency underneath the Gemini vision inference span. All results — including `habitat_description` and `global_distribution_regions` — are upserted to `species_dictionary` immediately, so every subsequent scan of the same species is a Cache Hit regardless of tier. The Flash text model call uses `deviceLocale` from the request body so `habitat_description` is generated in the user's language on first cache population. A `??` coalescing guard protects any previously stored taxonomy, IUCN status, toxicity, and habitat data from being overwritten by the Flash-generated values on locale-miss upserts.
   - **Gap-fill (`||` condition)**: If a species exists in `species_dictionary` but is missing either `habitat_description` OR `global_distribution_regions` (not just when both are absent), the background task fires a Flash text call to fill whichever field is missing. This covers species stored before premium fields were introduced that may have one field but not the other.
- **Dynamic Token Truncation (Non-Biological Bounds)**: To reduce API costs and output token usage, the `merianResponseSchema` was relaxed. Nested biological objects (`taxonomy`, `insight_data`, `diagnostic_comparison`) were removed from the `required: []` array. A `systemInstruction` rule now tells Gemini to omit these structures — including `colors` and `group_tags` — entirely when `is_biological_subject = false`. Because the Swift `EdgeResponse` struct declares these sub-nodes as optionals (`?`), `JSONDecoder` collapses missing keys to `nil` without crashing, cutting token usage on non-biological payloads.
- **Two-Call Identification Architecture**: Every scan follows a two-stage pipeline:
  1. **Vision call** (`identify`): Routes to `gemini-2.5-pro` (Pro) or `gemini-2.5-flash` (free). Returns identification fields only — `scientific_name`, `common_name`, `confidence_score`, `blur_score`, `is_biological_subject`, `is_live_capture`, `is_invasive`, `ecology_type`, `colors`, `insight_data` (containing `ai_reasoning`, `hazard_type`), `wikipedia_url`, `wikipedia_overview`, `reference_image_url`. `taxonomy` and `iucn_red_list_status` are only present on Cache Hit (read from `species_dictionary`, not generated by the model). `gbif_taxon_key` is present on Cache Hit for **all tiers** — it is GBIF's deterministic species usage key (REST-sourced, not AI-generated) and drives the occurrence heatmap in `BiologicalView` for free and Pro users alike. `species_insights` is present on Cache Hit for all tiers when habitat or distribution data is already stored in `species_dictionary`. `insight_data.ai_reasoning` is always present for biological subjects — it is the vision model's per-scan reasoning about the specific photo, unique to each submission. `hazard_type` is authoritative from `species_dictionary` on Cache Hit; sourced from the vision model on Cache Miss and then cached. The `hazard_type` column exists only on `species_dictionary`, not on `scans`.
  2. **Enrichment call** (`enrich-scan`): Triggered automatically by the iOS client (`InferenceEngine.fetchAndApplyEnrichment`) for all users after the vision call completes. Returns `habitat_description`, `global_distribution_regions`, `gbif_taxon_key`, and `diagnostic_comparison` (if confidence < 0.85). `gbif_taxon_key` is GBIF's deterministic species usage ID — it is sourced from `species_dictionary` (populated by a REST call to `api.gbif.org/v1/species/match` in the `identify` background task) and is never AI-generated. It may be `null` for Cache Miss species where the background GBIF lookup has not yet completed. Always uses `gemini-2.5-flash` — never the Pro model. Results are stored at the species level in `species_dictionary`. To avoid a duplicate Flash spend when `identify`'s background task and this call race on a Cache Miss, `enrich-scan` polls `species_dictionary` up to 3 times (2-second intervals) before falling back to a Flash generation call.
- **Tier-Based Model Selection**: The `merianResponseSchema` is applied to all requests regardless of tier. Model selection is tier-based: Pro users use `gemini-2.5-pro` for maximum identification depth (rare species, fossils, subspecies, cultivars); free users use `gemini-2.5-flash` for 2–3× lower latency. Tier is resolved via `getTierForUser()` from `_shared/tierCache.ts` (5-minute TTL worker-level cache); ghost-user upsert stays in the background task.
- **Fossil & Preserved Specimen Handling**: The system instruction explicitly distinguishes liveness from biological identity. Fossils, pressed plants, museum specimens, and dried organisms are `is_biological_subject = true` with `is_live_capture = false` — they are identified to species level (e.g. "Devil's Toenail" for *Gryphaea arcuata*). Only truly non-biological objects (rocks, buildings, food) set `is_biological_subject = false`.
- **`blur_score` Field**: Gemini's self-reported image sharpness metric, returned as a `Double` in the range 0 (sharp) to 1 (very blurry). Mapped to `EdgeResponse.blur_score` in `InferenceEdgeDTOs.swift` and carried through to `SpeciesData.blurScore`. Populated from live inference only — `nil` for scans loaded from the local SwiftData library since it is not persisted to `LocalScanRecord`. Surfaced in `ScanScoreCallout` inside `ConfidenceExplanationSheet` as a blur advisory when the score exceeds 0.5.
- **Token Throttling (`maxOutputTokens: 1000`)**: All production Edge bindings enforce `maxOutputTokens: 1000` for the vision call. The 1000 token budget keeps the model focused on the structured JSON output without generating reasoning chains that can exhaust Edge execution time limits.
- **Diagnostic Comparison Threshold (`DIAGNOSTIC_THRESHOLD = 0.85`)**: Diagnostic comparison data (primary rationale, confusing lookalike, key differentiators) is only generated when `confidence_score < 0.85`. This constant is defined in both `identify/index.ts` and `enrich-scan/index.ts`. On the Swift client, `InferenceEngine.fetchAndApplyEnrichment` applies the same threshold before writing `speciesData.diagnosticComparison`, so the diagnostic UI in `BiologicalView` is never shown for high-confidence scans. Diagnostic data is cached at the species level in `species_dictionary` — once generated for a species, subsequent low-confidence scans read from cache without a Gemini call.
- **Telemetry Pruning**: Legacy ephemeral fields (`cameraPitchDegrees`, `compassHeading`, `relativeHumidity`, `uvIndex`, `isFlashFired`) have been removed from the `CaptureTelemetry` JSON payload, saving hundreds of tokens per request. Schema nodes like `key_differentiators` and descriptive enum schemas inside Deno are compressed into flat string arrays.
- **Low Temperature Constraints (`temperature: 0.1`)**: Biological identification requires deterministic output. The model temperature is hardcoded to `0.1` to minimize hallucination.
- **Multi-Capture Context Fusion**: The `identify` Edge function accepts an array of `r2ObjectKeys: string[]`. Deno fetches R2 presigned URLs and encodes them to base64 in a single serial `for…of` loop — each response body is consumed via `arrayBuffer()` individually and the running `totalBytes` counter is incremented by `arrayBuffer.byteLength` (actual post-consumption byte count) before moving to the next image. If the accumulated total exceeds 5 MB, the loop immediately returns HTTP 413. The two-loop pattern previously used (a first pass checking `Content-Length` headers, a second pass consuming bodies) was eliminated because chunked transfer encoding makes `Content-Length` absent on R2 responses, allowing arbitrarily large payloads to exhaust the 256 MB Deno V8 heap before any guard fired. Serial body consumption also prevents back-pressure across V8's I/O loop when multiple bodies resolve simultaneously. The resulting base64 strings are injected as distinct `inlineData` MIME parts into the Gemini prompt, supporting macro shots alongside wider environmental images.
- **Base64 Payload Guard**: Before the R2 fetch loop, the Edge function validates that the incoming `imageBase64s` array has no more than 5 entries and that the total base64 byte length does not exceed 7 MB (≈ 5 MB raw). Requests violating either bound are rejected with `HTTP 400` / `HTTP 413` before any I/O runs, protecting Deno memory and Gemini quota.
- **Background Ingestion Dead-Letter Logging**: The `runBackground` task that handles moderation, enrichment, and Postgres UPSERTs wraps its work in a structured `try/catch`. On failure, a JSON-structured log line is emitted via `console.error` including `event`, `user_id`, `scan_id`, `error`, and `ts` fields. This replaces the previous silent swallow of background errors and makes failures observable in Supabase Edge Function logs without exposing internals to the client.
- **Shared Gemini Singleton** (`_shared/gemini.ts`): The `GoogleGenerativeAI` client is instantiated once at module scope (`_genAI`) in `_shared/gemini.ts` and imported by `identify`, `enrich-scan`, and `_shared/diagnostic.ts`. Deno reuses the same V8 isolate across warm invocations, so a module-scope singleton avoids re-creating the SDK object and its internal HTTP pool on every request. `createFlashModel(systemInstruction, maxOutputTokens)` is a shared factory for all Flash-only background calls (encyclopedic data, group tags, diagnostic comparison, enrichment). `extractJson<T>(text)` centralises the `indexOf`/`lastIndexOf` JSON extraction pattern that Gemini occasionally requires even with `responseMimeType: "application/json"`.

## On-Device Pre-Classification & Scanning Phase UX

While the Edge inference round-trip runs (typically 3–8s on `gemini-2.5-flash` / 6–12s on `gemini-2.5-pro`), `CameraViewModel` runs a concurrent `VNClassifyImageRequest` on-device to drive the fullscreen scanning overlay's status pill text.

### Phase Rotation System

`classifySubjectLocally(from:)` starts a **generic phrase series** immediately ("Scanning subject...", "Detecting morphological features...", etc.) so the overlay is never blank. Concurrently, `VNClassifyImageRequest` executes on a `Task.detached(priority: .userInitiated)` background thread (typically < 100ms). If Vision returns a confident subject category, a **subject-specific phrase series** is queued. Phrases rotate every 2.3 seconds via a cancellable `phaseRotationTask`.

### Subject-Specific Series Qualification

A specific phrase series is only activated if all three conditions are met:

1. **Confidence threshold** — the top `VNClassificationObservation` must score ≥ 0.65 (`MerianConfig.visionConfidenceThreshold`)
2. **Margin guard** — the top observation must lead the second-best by ≥ 0.15 (`MerianConfig.visionMarginThreshold`); split/ambiguous results (e.g., 0.67 bird / 0.60 plant) stay on the generic series. Implemented at the top of `specificPhraseSeries(for:)` before any category matching runs.
3. **1.5-second minimum delay** (`MerianConfig.scanningPhaseSubjectDelayNs`) — even when Vision qualifies, the specific series is held for 1.5 seconds before replacing the generic one; this guarantees the user always sees neutral phrases first and limits the visible duration of an incorrect category label to the back half of the scan.

If `isAnalyzingFullscreen` has already been set to `false` by the time the 1.5-second hold expires (fast network response), the switch is silently dropped.

### Phrase Cycling & Freshness

`startPhaseRotation` runs an infinite `while !Task.isCancelled` loop rather than a one-shot pass through the phrase array. This prevents the overlay from stalling on a frozen final phrase during long inference calls — `gemini-2.5-pro` responses can reach 25–30s on slow connections, which would leave "Awaiting identification..." static for ~10s after the 8-phrase × 2.3s rotation (18.4s) exhausted the array. The loop is cancelled cleanly by `synchronizeAnalysisState` when the overlay closes.

Generic phrases are shuffled on each scan (with "Scanning subject..." anchored first) so frequent users do not memorise the sequence.

### Pill Feedback

`ScanningOverlayView` adds two micro-interactions on each phrase change:
- The `sparkles.2` icon fires one `.variableColor.cumulative` animation cycle per phrase instead of looping blindly — communicating "new information arrived" rather than continuous idle activity.
- The pill container briefly scales to 1.04× via a spring animation (response: 0.18, dampingFraction: 0.45) before settling back to 1.0×, giving tactile feedback that analysis state has updated.

### Supported Categories

Subject-specific series exist for: birds, insects/arthropods, arachnids, fungi/lichen, flowering plants, trees/conifers, cacti/succulents, general plants, reptiles, amphibians, fish, and mammals. Each series is 8 phrases long, starting with moderately general observations and progressing to field-specific terminology. Unrecognised or low-confidence subjects fall through to the generic series.

---

## Inference Latency Optimisations

The following changes were made to minimise the time between shutter press and insight sheet display.

### iOS Critical Path

- **Connection + auth pre-warm** (`CameraViewModel.init`): A background task calls `SupabaseManager.shared.getValidAuthHeaders()` the moment `CameraViewModel` is initialised — before the user composes a shot. This opens the persistent HTTPS connection to Supabase and refreshes the JWT if near expiry, eliminating TCP/TLS handshake latency (~200–400ms) and token refresh latency from the scan submission path.
- **Redundant `MainActor.run` removal** (`InferenceEngine.swift`): Post-inference state commits (gamification, awards, image paths, `speciesData`, push notification check) previously had three separate `await MainActor.run` suspension points. Since `inferenceTask` is created on `@MainActor` and returns there after each off-actor `await`, those closures already execute on main — the explicit hops were no-ops that introduced unnecessary task suspension points. All post-inference work is now inlined.
- **base64 encoding priority** (`InferenceProcessingActor`): Multi-image base64 encoding uses `withTaskGroup` at `.userInitiated` priority so the CPU-bound work is not deprioritized behind background system tasks on a loaded device.
- **Inference request timeout 90s** (`MerianNetworkClient.analyzeSubject`): The `URLRequest.timeoutInterval` for inference calls was raised from 30s (the shared default) to 90s, matching `timeoutIntervalForResource`. `gemini-2.5-pro` responses can reach 25–30s on slow connections; the previous 30s idle-timeout margin was too thin.
- **5xx retry** (`MerianNetworkClient`): A single retry after a 2s pause on HTTP 5xx responses absorbs transient Edge Function cold-start failures and momentary Deno isolate errors that would otherwise surface to the user as "Network Timeout".
- **Image compression quality 0.85** (`MerianConfig.imageCompressionQuality`): Raised from 0.80 to preserve fine morphological detail (feather barbs, insect wing venation, leaf margins) that influences AI identification accuracy. File size increase is ~10–15%, well within the 5 MB payload limit.

### Edge Function Critical Path

- **Lightweight critical-path tier SELECT**: A single `SELECT subscription_tier` runs before the Gemini call to determine which model to use (Pro → `gemini-2.5-pro`, free → `gemini-2.5-flash`). Ghost-user upsert stays in the background task. The SELECT is skipped on cache hit.
- **Worker-level tier cache** (`_shared/tierCache.ts`): A module-scope `Map<userId, { tier, ts }>` with a 5-minute TTL persists across warm Deno isolate re-use via `getTierForUser()`. Cache hits are near-instant on both the critical path and the background task. Ghost users are intentionally not cached by `getTierForUser` so that `hasTierCached()` returns `false` in the background task, triggering the `users` table upsert before the `scans` FK insert. After the upsert, `setTierCache()` writes the entry explicitly.
- **System instruction trimmed and clarified (~120 tokens)**: The system instruction was trimmed and clarified. The liveness instruction was expanded to explicitly include fossils and preserved specimens as biological subjects with `is_live_capture = false`, preventing Flash from returning generic names for paleontological subjects.

### Benchmark Timing

`[⏱ BENCH]` timing markers are emitted at each stage:

**iOS (`MerianLog.general.debug`)** — visible in Xcode console (filter: `⏱ BENCH`) and Console.app:
```
[⏱ BENCH] Pre-flight (encode+auth): 0.052s
[⏱ BENCH] Post-flight (parse+save+state): 0.087s
[⏱ BENCH] Total pipeline: 4.123s
```

**Edge Function (`console.log`)** — visible in Supabase Dashboard → Edge Functions → identify → Logs:
```
[⏱ BENCH] payload_resolved: 12ms
[⏱ BENCH] pre_gemini: 14ms
[⏱ BENCH] gemini_done: 4203ms total, 4189ms inference
[⏱ BENCH] total_to_response: 4218ms
```

Tier resolution now emits no separate bench log — on a cache hit it is effectively free; on a cache miss the SELECT completes before `pre_gemini` fires and its latency is absorbed into the `payload_resolved → pre_gemini` gap.
