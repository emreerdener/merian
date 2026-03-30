# 17. AI Engineering & LLMOps

Merian's inference engine uses `gemini-2.5-flash` (free tier) and `gemini-2.5-pro` (Pro tier) running inside serverless Deno Edge functions to protect API keys and enforce structured output.

## Inference Layer Structure

The AI inference layer is split across three files under `merian/Core/AI/`:

- **`InferenceEngine.swift`**: The main engine. Coordinates upload confirmation, triggers the Edge function, and delivers results to `CameraViewModel`.
- **`InferenceProcessingActor.swift`**: An off-main-thread actor responsible for base64 encoding image data and parsing Edge responses.
- **`InferenceEdgeDTOs.swift`**: Codable DTOs used for Edge communication: `APIError`, `EdgeResponseWrapper`, and `EdgeResponse`.
- **`InferenceEdgeDTOs.swift`** also declares `EnrichScanResponse` — the `Codable` DTO for the `enrich-scan` Edge Function response, with nested `EnrichData` (maps `habitat_description`, `gbif_taxon_key`, `taxonomy`, and `similar_species: [SimilarSpeciesEntry]?`) and `SimilarSpeciesEntry` (maps `scientific_name`, `common_name`, `reference_image_url`, `iucn_red_list_status`) structs.

## Edge Function Architecture (`/identify`)

The `/identify` Supabase Edge Function is heavily modularized to guarantee minimal "Time-To-First-Meaning" (TTFM). The traditional monolith is split by strict domain responsibility, keeping the critical-path orchestrator extremely lightweight:

- **`index.ts`**: The main orchestrator. Executes the critical path (base64 image resolution, Gemini model invocation, Postgres caching checks) and safely spins off all telemetry and caching UPSERTS into a non-blocking background task.
- **`schema.ts`**: The semantic logic. Contains the highly specific `systemInstruction` prompting rules and the strongly-typed `merianResponseSchema` enforced on the Gemini payload output.
- **`types.ts`**: The API contracts. Exports `MerianIdentification` and `ClientPayload` (iOS DTO mapping), plus `CachedSpeciesRow` (the `species_dictionary` row shape shared with `db.ts`) and `StaticSpeciesData` (the assembled critical-path payload built from cache hit/miss branches, replacing a former inline anonymous type in the orchestrator).
- **`media.ts`**: Safely handles chunked sequential `R2` Base64 buffer loading to protect Deno's V8 edge heap constraints from crashing under massive multi-image payloads.
- **`db.ts`**: Encapsulates all PostgreSQL operations for the function as typed, error-throwing functions: `fetchCachedSpecies`, `upsertSpeciesDictionary`, `backfillSpeciesHabitat`, `insertScan`, `updateSimilarSpecies`, `updateGroupTags`, and `upsertGhostUserIfMissing`. `index.ts` contains zero direct Supabase client calls — all reads and writes route through this layer.
- **`../_shared/` Micro-Agents**: Auxiliary generation tools like `fetchExternalEnrichment` (Wikipedia/GBIF REST API polling in `external.ts`), `fetchGroupTags` (Flash AI), and `fetchStaticEncyclopedicData` are aggregated directly inside the generic `biology.ts` taxonomic node, making them globally accessible to both the `identify` and `enrich-scan` edge environments.

## Edge Function Architecture (`/enrich-scan`)

The `/enrich-scan` Supabase Edge Function handles on-demand encyclopedic lookup (habitat, taxonomy, and similar species lookalikes) for legacy scans lacking full metadata.

- **`index.ts`**: The main orchestrator. Re-routes data fetched by the shared micro-agents, handling the concurrent `Promise.all` logic based on what Postgres data is currently missing. Unifies the output via `formatEnrichmentPayload` to strictly guarantee uniform JSON contracts back to Swift.
- **`types.ts`**: Strict TypeScript interfaces tracking the shape of `CachedSpeciesData` returned from Postgres. Removing these inline types from the orchestrator eliminates dangerous semantic type-casting across asynchronous LLM results.
- **`db.ts`**: Encapsulates all Postgres operations: `getCachedSpecies` (dictionary lookup with `id` field), `fetchLookalikesFromJoinTable` (two-query rich hydration from `species_lookalikes`), `resolveLookalikesToJoinTable` (maps Gemini-generated scientific names to join table rows), and `updateSpeciesEnrichment` (UPSERT patching).

### Enrichment Pipeline (`isEnrichmentLoading` / `fetchAndApplyEnrichment`)

After a successful biological scan, `InferenceEngine` automatically fires `fetchAndApplyEnrichment(modelContext:)` for all users:

1. Sets `isEnrichmentLoading = true` — `HabitatAndDistributionCard` observes this via `@Environment(InferenceEngine.self)` and shows an animated loading skeleton.
2. Calls `MerianNetworkClient.shared.fetchEnrichment(scanId:scientificName:)` → POST `/enrich-scan`.
3. On success, patches `speciesData.habitatDescription` and (when non-nil) `speciesData.gbifTaxonKey` in-place on `@MainActor`, triggering a live UI update without reopening the sheet.
4. Maps `data.similar_species` (a `[SimilarSpeciesEntry]` array) to `speciesData.similarSpecies` as a `SimilarSpecies` wrapper struct (with `.entries: [SimilarSpeciesEntry]` and a backwards-compatible `.lookalikes: [String]` computed accessor) in-place on `@MainActor`, triggering a live `SimilarSpeciesGallery` UI update. No confidence threshold gate — enrichment always sets the data; the gallery UI decides labelling.
5. JSON-encodes `speciesData.similarSpecies?.entries` via `JSONEncoder` into a `Data` blob. Encode failures are logged via `MerianLog.general.debug` and result in `nil` — the field is never written with corrupt data. Persists all fields to `LocalScanRecord` via `BackgroundDatabaseActor.updateScanWithEnrichment(scanId:habitatDescription:gbifTaxonKey:similarSpeciesJsonData:taxonomy:)` on a background `Task`, writing the blob to `LocalScanRecord.lookalikesData` (`MerianSchemaV27`).
6. Sets `isEnrichmentLoading = false` (via `defer`).

`InferenceEngine.load(from:)` triggers enrichment for historical records that are missing `habitatDescription`, `gbifTaxonKey`, or both `lookalikesData` and `similarSpecies` (i.e., no lookalike data in either form).

**Historical record load path** (`load(from:)`): When opening a scan from the library, `InferenceEngine.load(from:)` reconstructs `speciesData.similarSpecies` via a two-layer decode:
1. **Rich path** (preferred): If `LocalScanRecord.lookalikesData` is non-nil, `JSONDecoder` decodes it as `[SimilarSpeciesEntry]` and wraps the array in `SimilarSpecies(entries:)`. All four fields (`scientificName`, `commonName`, `referenceImageUrl`, `iucnRedListStatus`) are available — `SimilarSpeciesGallery` renders thumbnail images directly from `referenceImageUrl`.
2. **Legacy flat path** (fallback for pre-V27 records): If `lookalikesData` is nil, each string in `LocalScanRecord.similarSpecies: [String]?` is wrapped into a `SimilarSpeciesEntry(scientificName:, commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil)`. `SimilarSpeciesGallery` falls back to `SimilarSpeciesImageFetcher` (Wikipedia / iNaturalist REST) for thumbnail images when `referenceImageUrl == nil`.

## Generation Configuration Guardrails

- **Edge Native Router**: The `/identify` Edge function now operates as an intelligent orchestrator rather than a blind proxy. It intercepts the "Skinny" multi-modal vision payload (which strictly handles image classification without expensive dictionary string generation) and immediately checks the `species_dictionary` table.
   - **Cache Hit**: If the species already exists in the dictionary with a valid `kingdom`, the function skips all generation loops and splices the stored data directly into the response.
   - **Cache Miss**: If this is the first time the species is discovered globally, the `/identify` API fires `fetchStaticEncyclopedicData` (a text-only Gemini 2.5 Flash request) and `fetchExternalEnrichment` (Wikipedia & GBIF polling) concurrently via `Promise.all`. This entirely hides the secondary network latency underneath the Gemini vision inference span. All results — including `habitat_description` and `reference_image_url` (populated via GBIF's `occurrence/search` API for high-quality iNaturalist field observations) — are upserted to `species_dictionary` immediately, so every subsequent scan of the same species is a Cache Hit regardless of tier. The Flash text model call uses `deviceLocale` from the request body so `habitat_description` is generated in the user's language on first cache population. A `??` coalescing guard protects any previously stored taxonomy, IUCN status, toxicity, and habitat data from being overwritten by the Flash-generated values on locale-miss upserts.
   - **Gap-fill condition**: If a species exists in `species_dictionary` but is missing `habitat_description`, the background task fires a Flash text call to fill the field. This covers species stored before the enrichment pipeline was introduced.
- **Dynamic Token Truncation (Non-Biological Bounds)**: To reduce API costs and output token usage, the `merianResponseSchema` was relaxed. Nested biological objects (`taxonomy`, `insight_data`) were removed from the `required: []` array. A `systemInstruction` rule now tells Gemini to omit these structures — including `colors` and `group_tags` — entirely when `is_biological_subject = false`. Because the Swift `EdgeResponse` struct declares these sub-nodes as optionals (`?`), `JSONDecoder` collapses missing keys to `nil` without crashing, cutting token usage on non-biological payloads.
- **Two-Call Identification Architecture (Optimised TTFM)**: Every scan follows a two-stage pipeline designed for absolute lowest "Time-To-First-Meaning" (latency from shutter to first UI render):
  1. **Vision call** (`identify`): Routes to `gemini-2.5-pro` (Pro) or `gemini-2.5-flash` (free). This is the fastest, initial pass. It evaluates core identity (`scientific_name`, `common_name`, `confidence_score`, `inference_tier`, `is_biological_subject`) and instance-specific photo dependencies (`ai_reasoning`, `extracted_visual_traits`, `life_stage`, `reproductive_condition`, `individual_count`, `ecology_type`, `ecological_interactions`). The model executes a "Micro-CoT" (Chain of Thought) by generating exactly 3 `extracted_visual_traits` *before* attempting classification to drastically reduce pareidolia and false positives (e.g. hallucinating snakes from pavement cracks). The `is_invasive` check also securely remains here because outputting a boolean costs exactly 1 token (~10ms latency), pulling natively from the user's GPS; forcing this to a secondary text payload would incur a sequential ~500ms network penalty. Heavy structure-agnostic generation fields (`hazard_type`, `colors`) were explicitly **stripped** from the Vision schema to boost inference speed.
  2. **Enrichment Text pass** (`enrich-scan` & background `identify`): Generates the bulky metadata. On Cache Misses, `fetchStaticEncyclopedicData` uses a text-only, image-free Flash prompt to rapidly deduce the species' `hazard_type`, generalised `colors`, `taxonomy`, `habitat_description`, and `iucn_red_list_status`. This allows the UI to populate the heavy static fields silently in the background without penalising the initial Vision pass. `gbif_taxon_key` is fetched natively from GBIF APIs here and cached to `species_dictionary`.
- **Tier-Based Model Selection**: The `merianResponseSchema` is applied to all requests regardless of tier. Model selection is tier-based: Pro users use `gemini-2.5-pro` for maximum identification depth (rare species, fossils, subspecies, cultivars); free users use `gemini-2.5-flash` for 2–3× lower latency. Tier is resolved via `getTierForUser()` from `_shared/tierCache.ts` (5-minute TTL worker-level cache); ghost-user upsert stays in the background task.
- **Fossil & Preserved Specimen Handling**: The system instruction explicitly distinguishes liveness from biological identity. Fossils, pressed plants, museum specimens, and dried organisms are `is_biological_subject = true` with `is_live_capture = false` — they are identified to species level (e.g. "Devil's Toenail" for *Gryphaea arcuata*). Only truly non-biological objects (rocks, buildings, food) set `is_biological_subject = false`.
- **`blur_score` Field**: Gemini's self-reported image sharpness metric, returned as a `Double` in the range 0 (sharp) to 1 (very blurry). Mapped to `EdgeResponse.blur_score` in `InferenceEdgeDTOs.swift` and carried through to `SpeciesData.blurScore`. Populated from live inference only — `nil` for scans loaded from the local SwiftData library since it is not persisted to `LocalScanRecord`. Surfaced in `ScanScoreCallout` inside `ConfidenceExplanationSheet` as a blur advisory when the score exceeds 0.5.
- **`image_quality` Object**: Gemini evaluates the photographic quality of each submitted image as a structured sub-object in the `/identify` response schema (`schema.ts`). The object contains three sub-scores (each 1–10): `sharpness` (optical clarity), `framing` (subject positioning and composition), and `diagnostic_utility` (how useful the photo is for species identification), plus an `overall_score` (0–100) aggregating all three. All four fields are required in the Gemini response schema. The TypeScript interface is `ImageQuality` in `identify/types.ts`; the Swift counterpart is the `ImageQuality` struct in `InferenceEdgeDTOs.swift` (`image_quality: ImageQuality?` on `EdgeResponse`). Only `overall_score` is persisted — to `public.scans.image_quality_score` (SMALLINT, migration `20260330150000_add_image_quality_score_to_scans.sql`) and to `LocalScanRecord.imageQualityScore` (`MerianSchemaV30`). The three sub-scores are evaluated in-memory only and are not stored anywhere. `imageQualityScore` is a `let` constant in `SpeciesData` (immutable after init) because the score is a property of the captured image, not something that changes. `nil` for all scans before V30 — no backfill. The feature is "collect now, use later": scores are gathered for future community reference-photo curation use cases.
- **Token Throttling (`maxOutputTokens: 1000`)**: All production Edge bindings enforce `maxOutputTokens: 1000` for the vision call. The 1000 token budget keeps the model focused on the structured JSON output without generating reasoning chains that can exhaust Edge execution time limits.
- **Token Telemetry Tracking**: To measure AI inference costs accurately, Edge functions intercept the `UsageMetadata` from Gemini responses. To provide a consolidated "total cost per scan", the main orchestrator edge functions explicitly `await` their sub-task Flash payloads (like `fetchStaticEncyclopedicData` or `fetchSimilarSpecies`). The `identify` function then emits a single `ScanCompleted` event containing both the granular token usage of individual micro-agents and the absolute integer total in `cumulative_scan_tokens`. Similarly, the `enrich-scan` function emits an aggregated `EnrichmentCostAnalyzed` event. All token telemetry includes the `tier` parameter to distinguish `gemini-2.5-pro` (Pro) vs `gemini-2.5-flash` (free) burn rates.
- **Dynamic Diagnostic Thresholds**: The dynamic presentation of diagnostic data (e.g., lookalikes, confidence hooks, and identification candidates) is gated by the tier-specific `diagnosticTrigger` (`0.88` Free/Flash, `0.80` Pro) from `MerianConfig.confidenceBands(forInferenceTier: inferenceTier).diagnosticTrigger`.
  - **Similar species**: The backend Edge Functions (`identify` and `enrich-scan`) blindly index and fetch `similar_species` if it is not already cached in the database. When the Swift client receives this data, `BiologicalView` and `SimilarSpeciesGallery` evaluate the scan's confidence against the threshold. This logic visually classifies the matched species data either as an actionable "POTENTIAL LOOKALIKES" interface, or purely informational "SIMILAR SPECIES".
  - **Identification candidates**: When `confidence_score < diagnosticTrigger`, Gemini is instructed (via `merianResponseSchema` and system instructions in `schema.ts`) to emit up to 2 alternative species it genuinely considered — each as `{ scientific_name, confidence_score }`. The `identify` `index.ts` server-side strips this array to `null` if confidence is at or above the trigger *before* sending the response and before `insertScan`. This provides defense-in-depth: even if the model emits candidates at high confidence, the server discards them. Candidates are persisted per-scan to `public.scans.candidates` (JSONB) and on-device to `LocalScanRecord.candidatesData` (Data blob, `MerianSchemaV28`). `CandidatesCard` renders the list in `BiologicalView` when `candidates.count >= 2`.
  - **User identification review** (`MerianSchemaV29`): Users can confirm or override the AI's identification from `CandidatesCard`. `InferenceEngine` exposes three methods for this flow:
    - `applyIdentificationOverride(scientificName:modelContext:)`: Mutates `speciesData.userIdentificationOverride` and `speciesData.scientificName` to the chosen species name, persists to `LocalScanRecord` via `BackgroundDatabaseActor.updateScanWithOverride`, syncs to `public.scans.user_identification_override` via `syncIdentificationReviewToCloud` (direct PostgREST PATCH with `.eq("user_id", userId)` IDOR guard), and fires `fetchAndPatchOverrideData` to hydrate species display data from `species_dictionary`.
    - `confirmAIIdentification(modelContext:)`: Sets `speciesData.userConfirmedIdentification = true`, persists to `LocalScanRecord`, and syncs to `public.scans.user_confirmed_identification` via `syncIdentificationReviewToCloud`.
    - `resetIdentificationReview(modelContext:)`: Clears both `userIdentificationOverride` and `userConfirmedIdentification`, reverts `speciesData.scientificName` to `aiScientificName`, persists locally, zeros both cloud columns via `syncIdentificationReviewToCloud`, and re-hydrates the AI's original species data via `fetchAndPatchOverrideData`. Called by both Undo (from `.overridden`) and Change (from `.confirmed`).
    - `fetchAndPatchOverrideData(scientificName:scanId:modelContext:)`: Queries `species_dictionary` via a PostgREST array select with `.limit(1)` and takes `.first` (the Supabase Swift SDK does not provide a `.maybeSingle()` method). On cache hit, patches `speciesData` fields — `commonName`, `insightData` (hazard type), `taxonomy`, `iucnRedListStatus`, `habitatDescription`, `gbifTaxonKey`, `referenceImageUrl`, `wikipediaOverview`, `wikipediaUrl` — in-place on `@MainActor`. `SpeciesData.commonName`, `scientificName`, and `iucnRedListStatus` are declared `var` (not `let`) specifically to allow this in-place mutation. On cache miss, calls `fetchAndApplyEnrichment` (which uses the already-mutated `speciesData.scientificName` as the lookup key to enrich the override species).
    - `syncIdentificationReviewToCloud(scanId:override:confirmed:)`: Private IDOR-guarded PATCH that sends both `user_identification_override` and `user_confirmed_identification` in a single `ReviewSyncPayload` Encodable struct. Accepts nil for `override` (encodes as JSON null → SQL NULL). Called by `applyIdentificationOverride`, `confirmAIIdentification`, and `resetIdentificationReview`.
  - `InferenceEngine.load(from:)` restores review state from `LocalScanRecord` on historical opens: sets `aiScientificName: record.scientificName` (always the AI's original), `userIdentificationOverride`, and `userConfirmedIdentification`. If an override is present, it also fires `fetchAndPatchOverrideData` asynchronously to ensure override species data is hydrated even when opening an older cached record.
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
