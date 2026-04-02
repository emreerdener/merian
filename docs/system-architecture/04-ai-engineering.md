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

- **`index.ts`**: The main orchestrator. Executes the critical path (base64 image resolution, Gemini model invocation, Postgres caching checks) and safely spins off all telemetry and caching UPSERTS into a non-blocking background task. Dynamically calculates downstream variables (`blur_score`) from base fields (`image_quality.sharpness`) natively in V8.
- **`schema.ts`**: The semantic logic. Contains the highly specific `systemInstruction` prompting rules and the strongly-typed `merianResponseSchema` enforced on the Gemini payload output. Aggressively memoizes generated schemas (`schemaCache`) and strictly dictates payload key-ordering to force linear LLM evaluation flows.
- **`types.ts`**: The API contracts. Exports `MerianIdentification` and `ClientPayload` (iOS DTO mapping), plus `CachedSpeciesRow` (the `species_dictionary` row shape shared with `db.ts`) and `StaticSpeciesData` (the assembled critical-path payload built from cache hit/miss branches, replacing a former inline anonymous type in the orchestrator).
- **`media.ts`**: Safely handles chunked sequential `R2` Base64 buffer loading to protect Deno's V8 edge heap constraints from crashing under massive multi-image payloads.
- **`db.ts`**: Encapsulates all PostgreSQL operations for the function as typed, error-throwing functions: `fetchCachedSpecies`, `upsertSpeciesDictionary`, `backfillSpeciesHabitat`, `insertScan`, `updateSimilarSpecies`, `updateGroupTags`, and `upsertGhostUserIfMissing`. `index.ts` contains zero direct Supabase client calls — all reads and writes route through this layer.
- **`../_shared/` Micro-Agents**: Auxiliary generation tools like `fetchExternalEnrichment` (Wikipedia/GBIF REST API polling in `external.ts`), `fetchGroupTags` (Flash AI), and `fetchStaticEncyclopedicData` are aggregated directly inside the generic `biology.ts` taxonomic node, making them globally accessible to both the `identify` and `enrich-scan` edge environments.

## Edge Function Architecture (`/enrich-scan`)

The `/enrich-scan` Supabase Edge Function handles on-demand encyclopedic lookup (habitat, taxonomy, and similar species lookalikes) for legacy scans lacking full metadata.

- **`index.ts`**: The main orchestrator. Re-routes data fetched by the shared micro-agents, handling the concurrent `Promise.all` logic based on what Postgres data is currently missing. Unifies the output via `formatEnrichmentPayload` to strictly guarantee uniform JSON contracts back to Swift.
- **`types.ts`**: Strict TypeScript interfaces tracking the shape of `CachedSpeciesData` returned from Postgres. Removing these inline types from the orchestrator eliminates dangerous semantic type-casting across asynchronous LLM results.
- **`db.ts`**: Encapsulates all Postgres operations: `getCachedSpecies` (dictionary lookup with `id` field), `fetchLookalikesFromJoinTable` (embedded join hydration from `species_lookalikes`), `resolveLookalikesToJoinTable` (maps Gemini-generated scientific names to join table rows, back-fills `common_names`, returns Flash-generated stubs for species not yet in the dictionary, and **rejects any resolved species whose `kingdom` differs from the primary species' kingdom** — hard guard against cross-kingdom hallucinations persisting in cache), and `updateSpeciesEnrichment` (UPSERT patching).

### Enrichment Pipeline (`isEnrichmentLoading` / `fetchAndApplyEnrichment`)

After a successful biological scan, `InferenceEngine` automatically fires `fetchAndApplyEnrichment(modelContext:)` for all users:

1. Sets `isEnrichmentLoading = true` — `HabitatAndDistributionCard` observes this via `@Environment(InferenceEngine.self)` and shows an animated loading skeleton.
2. Calls `MerianNetworkClient.shared.fetchEnrichment(scanId:scientificName:)` → POST `/enrich-scan`.
3. On success, patches `speciesData.habitatDescription` and (when non-nil) `speciesData.gbifTaxonKey` in-place on `@MainActor`, triggering a live UI update without reopening the sheet.
4. Maps `data.similar_species` (a `[SimilarSpeciesEntry]` array) to `speciesData.similarSpecies` as a `SimilarSpecies` wrapper struct (with `.entries: [SimilarSpeciesEntry]` and a backwards-compatible `.lookalikes: [String]` computed accessor) in-place on `@MainActor`, triggering a live `SimilarSpeciesGallery` UI update. No confidence threshold gate — enrichment always sets the data; the gallery UI decides labelling. Each `SimilarSpeciesEntry` carries `common_name?: String` — present for all species resolved from the join table or generated by Flash, null only for legacy migration stubs that predate the common-name enrichment pipeline. `SimilarSpeciesCard` shows `common_name` above the scientific name when non-nil and gracefully degrades to scientific-name-only when nil.

   **Common name resolution for lookalike species — three-tier priority:**
   - **Tier 1 (dictionary):** `fetchLookalikesFromJoinTable` reads `species_dictionary.common_names["en"]` via the embedded PostgREST join. This is the fast, zero-Flash path for all species that have been scanned at least once.
   - **Tier 2 (Flash + back-fill):** If the `"en"` key is absent (species in dictionary but `common_names` is `NULL`, `{}`, or only has non-English keys), `resolveLookalikesToJoinTable` calls the `merge_common_name_en` Postgres RPC to merge the Flash-generated name as `{"en": "..."}` without overwriting existing locale keys. Implemented via a JSONB `||` merge operator: `COALESCE(common_names, '{}') || jsonb_build_object('en', p_en_name)` with a `NOT (common_names ? 'en')` guard so it is always a safe no-op for species that already have English.
   - **Tier 3 (Flash stub):** If the lookalike species is not yet in `species_dictionary` at all, `resolveLookalikesToJoinTable` returns the Flash-generated `common_name` directly as a `LookalikeSummary` stub with `reference_image_url: null`. The `SimilarSpeciesCard` falls back to `SimilarSpeciesImageFetcher` (Wikipedia / iNaturalist REST) for thumbnail images when `referenceImageUrl` is nil.

   **`lookalikes_flash_attempted` flag** (`species_dictionary.lookalikes_flash_attempted BOOLEAN NOT NULL DEFAULT false`, migration `20260330160000`): Set to `true` in `enrich-scan/index.ts` after any Flash-sourced `resolveLookalikesToJoinTable` call completes, regardless of how many common names were resolved. The `hasLookalikes` gate in `index.ts` ORs this flag:
   ```typescript
   const hasLookalikes =
     lookalikes.some((l) => l.common_name !== null) ||
     cachedSpecies?.lookalikes_flash_attempted === true;
   ```
   Without the flag, species whose lookalikes are all legitimately obscure (no widely-recognised English common name) would cause Flash to re-run on every `enrich-scan` invocation indefinitely, since `.some(l => l.common_name !== null)` would never become true. The flag is **not** set by the legacy TEXT[] migration path so those species still trigger Flash once.
5. JSON-encodes `speciesData.similarSpecies?.entries` via `JSONEncoder` into a `Data` blob. Encode failures are logged via `MerianLog.general.debug` and result in `nil` — the field is never written with corrupt data. Persists all fields to `LocalScanRecord` via `BackgroundDatabaseActor.updateScanWithEnrichment(scanId:habitatDescription:gbifTaxonKey:similarSpeciesJsonData:taxonomy:)` on a background `Task` whose handle is stored in `enrichmentWriteTask` (`@ObservationIgnored private var enrichmentWriteTask: Task<Void, Never>?`). The handle is cancelled in `prepareForNewScan()`, `analyze()` (reset block), and `cancelActiveRequest()`, preventing a stale enrichment write from landing on the wrong `LocalScanRecord` when the user rapidly navigates between scans. The blob lands in `LocalScanRecord.lookalikesData` (`MerianSchemaV27`).
6. Sets `isEnrichmentLoading = false` (via `defer`).

`InferenceEngine.load(from:)` triggers enrichment for historical records that are missing `habitatDescription`, `gbifTaxonKey`, both `lookalikesData` and `similarSpecies`, **or** where `lookalikesData` decodes to entries that are all `commonName == nil` (indicating the join table was populated before the common-name back-fill pipeline existed). The `lookalikesData` blob is decoded once on `@MainActor` for the gate check and the resulting `SimilarSpecies` value is passed directly into the `historicHydrationTask` — no second `JSONDecoder` pass on the same data.

Additionally, `load(from:)` now inserts `recordScientificName` into `enrichedSpeciesNames` after a successful enrichment call, matching the behaviour of the live inference path. This prevents a redundant `enrich-scan` Edge call when the user opens two different scan records of the same species in the same session.

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
  1. **Vision call** (`identify`): Routes to `gemini-2.5-pro` (Pro) or `gemini-2.5-flash` (free). This is the fastest, initial pass. It evaluates core identity (`scientific_name`, `common_name`, `confidence_score`, `inference_tier`, `is_biological_subject`) and instance-specific photo dependencies (`ai_reasoning`, `extracted_visual_traits`, `life_stage`, `reproductive_condition`, `individual_count`, `ecology_type`, `ecological_interactions`). The model executes a "Micro-CoT" (Chain of Thought) by generating exactly 3 `extracted_visual_traits` *before* attempting classification. This ordering is strictly guaranteed by anchoring `extracted_visual_traits` and `ai_reasoning` at the top of the V8 JSON Schema object, preventing the model from committing a classification until textual evidence is written. The `is_invasive` check also securely remains here because outputting a boolean costs exactly 1 token (~10ms latency), pulling natively from the user's GPS; forcing this to a secondary text payload would incur a sequential ~500ms network penalty. Heavy structure-agnostic generation fields (`hazard_type`, `colors`, `blur_score`) were explicitly **stripped** from the Vision schema properties and prompt OMISSIONS to boost inference speed.
     - **`common_name` schema contract**: Defined in `identify/schema.ts` as `SchemaType.STRING` with description *"Most specific, commonly recognised English name in Title Case."* It is **intentionally absent from `required[]`** — system instruction rule 6 instructs Gemini to omit `common_name` entirely for `is_biological_subject = false` subjects (rocks, food, buildings). For biological subjects it is effectively required via the instruction. `common_name` is not persisted to `public.scans` — it is stored only in `species_dictionary.common_names` as a locale-keyed JSONB object (`{"en": "..."}`) and always sourced fresh from the vision model response on every scan. The DB value is locale storage only; the live Gemini output is always the authoritative display value.
  2. **Enrichment Text pass** (`enrich-scan` & background `identify`): Generates the bulky metadata. On Cache Misses, `fetchStaticEncyclopedicData` uses a text-only, image-free Flash prompt to rapidly deduce the species' `hazard_type`, generalised `colors`, `taxonomy`, `habitat_description`, and `iucn_red_list_status`. This allows the UI to populate the heavy static fields silently in the background without penalising the initial Vision pass. `gbif_taxon_key` is fetched natively from GBIF APIs here and cached to `species_dictionary`.
- **Tier-Based Model Selection**: The `merianResponseSchema` is applied to all requests regardless of tier. Model selection is tier-based: Pro users use `gemini-2.5-pro` for maximum identification depth (rare species, fossils, subspecies, cultivars); free users use `gemini-2.5-flash` for 2–3× lower latency. Tier is resolved via `getTierForUser()` from `_shared/tierCache.ts` (5-minute TTL worker-level cache); ghost-user upsert stays in the background task.
- **Fossil, Geological & Non-Biological Handling**: The system instruction explicitly distinguishes liveness from biological identity. Fossils, pressed plants, museum specimens, and dried organisms are `is_biological_subject = true` with `is_live_capture = false` — they are identified to species level (e.g. "Devil's Toenail" for *Gryphaea arcuata*). Geological objects (rocks, minerals) are evaluated as `is_biological_subject = false`, but Gemini is explicitly instructed to populate their `scientific_name` and `common_name`. This "soft expansion" allows the iOS app to neatly label geological items in the UI while safely bypassing Linnean-dependent species hydration, caching, and taxonomy enrichment. Only generic non-natural debris (buildings, food, shadows) sets `is_biological_subject = false` with omitted identification names.
- **`blur_score` Field**: Gemini's image sharpness diagnostic metric, surfaced as a `Double` in the range 0 (sharp) to 1 (very blurry). Extracted linearly from the formal required `image_quality.sharpness` encyclopedic schema matrix and mathematically derived natively within V8 inside the main edge orchestrator to bypass LLM latency loops. Mapped to `EdgeResponse.blur_score` in `InferenceEdgeDTOs.swift` and carried through to `SpeciesData.blurScore`. Populated from live inference only — `nil` for scans loaded from the local SwiftData library since it is not persisted to `LocalScanRecord`. Surfaced in `ScanScoreCallout` inside `ConfidenceExplanationSheet` as a blur advisory when the score exceeds 0.5.
- **`image_quality` Object**: Gemini evaluates the photographic quality of each submitted image as a structured sub-object in the `/identify` response schema (`schema.ts`). The object contains three sub-scores (each 1–10): `sharpness` (optical clarity), `framing` (subject positioning and composition), and `diagnostic_utility` (how useful the photo is for species identification), plus an `overall_score` (0–100) aggregating all three. All four fields are required in the Gemini response schema. The TypeScript interface is `ImageQuality` in `identify/types.ts`; the Swift counterpart is the `ImageQuality` struct in `InferenceEdgeDTOs.swift` (`image_quality: ImageQuality?` on `EdgeResponse`). Only `overall_score` is persisted — to `public.scans.image_quality_score` (SMALLINT, migration `20260330150000_add_image_quality_score_to_scans.sql`) and to `LocalScanRecord.imageQualityScore` (`MerianSchemaV30`). The three sub-scores are evaluated in-memory only and are not stored anywhere. `imageQualityScore` is a `let` constant in `SpeciesData` (immutable after init) because the score is a property of the captured image, not something that changes. `nil` for all scans before V30 — no backfill. The feature is "collect now, use later": scores are gathered for future community reference-photo curation use cases.
- **Token Throttling (`maxOutputTokens: 1000`)**: All production Edge bindings enforce `maxOutputTokens: 1000` for the vision call. The 1000 token budget keeps the model focused on the structured JSON output without generating reasoning chains that can exhaust Edge execution time limits.
- **Token Telemetry Tracking**: To measure AI inference costs accurately, Edge functions intercept the `UsageMetadata` from Gemini responses. To provide a consolidated "total cost per scan", the main orchestrator edge functions explicitly `await` their sub-task Flash payloads (like `fetchStaticEncyclopedicData` or `fetchSimilarSpecies`). The `identify` function then emits a single `ScanCompleted` event containing both the granular token usage of individual micro-agents and the absolute integer total in `cumulative_scan_tokens`. Similarly, the `enrich-scan` function emits an aggregated `EnrichmentCostAnalyzed` event. All token telemetry includes the `tier` parameter to distinguish `gemini-2.5-pro` (Pro) vs `gemini-2.5-flash` (free) burn rates.
- **Dynamic Diagnostic Thresholds**: The dynamic presentation of diagnostic data (e.g., lookalikes, confidence hooks, and identification candidates) is gated by the tier-specific `diagnosticTrigger`. **Canonical source of truth**: `supabase/functions/identify/thresholds.ts` — exports `FLASH_DIAGNOSTIC_TRIGGER = 0.96`, `PRO_DIAGNOSTIC_TRIGGER = 0.85`, and `diagnosticTriggerForTier(tier)`. The iOS client mirrors these in `MerianConfig.flashConfidence.diagnosticTrigger` and `MerianConfig.proConfidence.diagnosticTrigger`. Both sets of values are intentionally equal to their respective `strong` thresholds: candidates are stripped only for Strong match scans, ensuring every Possible and Weak match scan reaches the client with the full candidate list for the verification UX.
  - **Similar species**: The backend Edge Functions (`identify` and `enrich-scan`) blindly index and fetch `similar_species` if it is not already cached in the database. When the Swift client receives this data, `BiologicalView` and `SimilarSpeciesGallery` evaluate the scan's confidence against the threshold. This logic visually classifies the matched species data either as an actionable "POTENTIAL LOOKALIKES" interface, or purely informational "SIMILAR SPECIES".
  - **Identification candidates**: `candidates` is a **required field** in `merianResponseSchema` (`schema.ts`) — Gemini always generates exactly 2 alternative species regardless of its confidence level. The `identify` `index.ts` server-side strips this array to `null` if `confidence_score >= diagnosticTrigger` *before* sending the response and before `insertScan`. This server gate is the sole enforcement mechanism; the model is not asked to conditionally self-suppress (which was unreliable). Candidates are persisted per-scan to `public.scans.candidates` (JSONB) and on-device to `LocalScanRecord.candidatesData` (Data blob, `MerianSchemaV28`). `CandidatesCard` renders the list in `BiologicalView` when `candidates.count >= 2`.
  - **User identification review** (`MerianSchemaV29`): Users can confirm or override the AI's identification from `CandidatesCard`. The card has two distinct pending-state layouts depending on whether the model produced candidates:
    - **With candidates** (`candidates.count >= 2`): Two buttons — **"Yes, correct"** (confirms AI result) and **"Not sure"** (expands the candidate list). After expanding, the user taps a candidate to trigger a confirmation dialog, then `applyIdentificationOverride`. An "Actually, the AI is correct" fallback button collapses the list and confirms.
    - **Without candidates** (`candidates.isEmpty`, card shown because `hasLowConfidence`): Two buttons — **"Yes, correct"** (confirms AI result) and **"No, incorrect"** (routes directly to the flag/report sheet via the `onFlagIssue` callback wired in `BiologicalView`). This path exists because there are no alternatives to offer; the flag flow is the appropriate escape hatch so the user can indicate what they think the correct identification is.
    - `onFlagIssue: (() -> Void)?` is an optional callback on `CandidatesCard`. `BiologicalView` sets it to `{ viewModel.isFlagIssuePresented = true }`. The parameter is optional so `CandidatesCard` can be placed in other contexts without requiring a flag route.
    - `InferenceEngine` exposes three methods for this flow:
    - `applyIdentificationOverride(scientificName:modelContext:)`: Mutates `speciesData.userIdentificationOverride` and `speciesData.scientificName` to the chosen species name, persists to `LocalScanRecord` via `BackgroundDatabaseActor.updateScanWithOverride`, syncs to `public.scans.user_identification_override` via `syncIdentificationReviewToCloud` (direct PostgREST PATCH with `.eq("user_id", userId)` IDOR guard), and fires `fetchAndPatchOverrideData` to hydrate species display data from `species_dictionary`.
    - `confirmAIIdentification(modelContext:)`: Sets `speciesData.userConfirmedIdentification = true`, persists to `LocalScanRecord`, and syncs to `public.scans.user_confirmed_identification` via `syncIdentificationReviewToCloud`.
    - `resetIdentificationReview(modelContext:)`: Clears both `userIdentificationOverride` and `userConfirmedIdentification`, reverts `speciesData.scientificName` to `aiScientificName`, persists locally, zeros both cloud columns via `syncIdentificationReviewToCloud`, and re-hydrates the AI's original species data via `fetchAndPatchOverrideData`. Called by both Undo (from `.overridden`) and Change (from `.confirmed`).
    - `fetchAndPatchOverrideData(scientificName:scanId:modelContext:restoringAiReasoning:)`: Queries `species_dictionary` via a PostgREST array select with `.limit(1)` and takes `.first` (the Supabase Swift SDK does not provide a `.maybeSingle()` method). On cache hit, patches `speciesData` fields — `commonName`, `insightData` (hazard type + aiReasoning), `taxonomy`, `iucnRedListStatus`, `habitatDescription`, `gbifTaxonKey`, `referenceImageUrl`, `wikipediaOverview`, `wikipediaUrl` — in-place on `@MainActor`. Also persists the same fields to `LocalScanRecord` via `BackgroundDatabaseActor.updateScanWithOverrideSpeciesData` so the data survives sheet dismissal and reopen without requiring a network call. `scientificName` is intentionally excluded from this write — `record.scientificName` is preserved as the original-AI identifier and reused as `aiScientificName`. `commonName` is resolved with locale preference matching `ScanRepository.ingestScans`: `names["en"].flatMap { $0 } ?? names.compactMap { $0.value }.first ?? scientificName`. The `restoringAiReasoning` parameter controls the `aiReasoning` field in `InsightData`: pass `nil` (default) when calling from `applyIdentificationOverride` to wipe the AI reasoning (it was written for the rejected species); pass `record.aiReasoning` when calling from `resetIdentificationReview` so the original reasoning reappears after undo. On cache miss, persists the scientific name as a `commonName` placeholder (minimum viable reopen state) and calls `fetchAndApplyEnrichment` (which uses the already-mutated `speciesData.scientificName` as the lookup key to enrich the override species).
    - `syncIdentificationReviewToCloud(scanId:override:confirmed:)`: Private IDOR-guarded PATCH that sends both `user_identification_override` and `user_confirmed_identification` in a single `ReviewSyncPayload` Encodable struct. Accepts nil for `override` (encodes as JSON null → SQL NULL). Called by `applyIdentificationOverride`, `confirmAIIdentification`, and `resetIdentificationReview`.
  - `InferenceEngine.load(from:)` restores review state from `LocalScanRecord` on historical opens. When `userIdentificationOverride` is non-nil, two rules apply: (1) `speciesData.scientificName` is set to `userIdentificationOverride` (the override name) rather than `record.scientificName` (the original AI name), making the correct species title immediately visible without waiting for any async step; (2) `InsightData.aiReasoning` is suppressed, since the AI's vision reasoning was written for the original species and is misleading under the override name. `record.scientificName` is always used as `aiScientificName` — it is never overwritten — so `resetIdentificationReview` can recover the original name across any number of reopens. `historicHydrationTask` Step 3 still fires `fetchAndPatchOverrideData` asynchronously as a freshness refresh (re-patching the same species data from the network), but display correctness no longer depends on this call completing.
- **Telemetry Pruning**: Legacy ephemeral fields (`cameraPitchDegrees`, `compassHeading`, `relativeHumidity`, `uvIndex`, `isFlashFired`) have been removed from the `CaptureTelemetry` JSON payload, saving hundreds of tokens per request. Schema nodes like `key_differentiators` and descriptive enum schemas inside Deno are compressed into flat string arrays.
- **Low Temperature Constraints (`temperature: 0.1`)**: Biological identification requires deterministic output. The model temperature is hardcoded to `0.1` to minimize hallucination.
- **Multi-Capture Context Fusion**: The `identify` Edge function accepts an array of `r2ObjectKeys: string[]`. Deno fetches R2 presigned URLs and encodes them to base64 in a single serial `for…of` loop — each response body is consumed via `arrayBuffer()` individually and the running `totalBytes` counter is incremented by `arrayBuffer.byteLength` (actual post-consumption byte count) before moving to the next image. If the accumulated total exceeds 5 MB, the loop immediately returns HTTP 413. The two-loop pattern previously used (a first pass checking `Content-Length` headers, a second pass consuming bodies) was eliminated because chunked transfer encoding makes `Content-Length` absent on R2 responses, allowing arbitrarily large payloads to exhaust the 256 MB Deno V8 heap before any guard fired. Serial body consumption also prevents back-pressure across V8's I/O loop when multiple bodies resolve simultaneously. The resulting base64 strings are injected as distinct `inlineData` MIME parts into the Gemini prompt, supporting macro shots alongside wider environmental images.
- **Base64 Payload Guard**: Before the R2 fetch loop, the Edge function validates that the incoming `imageBase64s` array has no more than 5 entries and that the total base64 byte length does not exceed 7 MB (≈ 5 MB raw). Requests violating either bound are rejected with `HTTP 400` / `HTTP 413` before any I/O runs, protecting Deno memory and Gemini quota.
- **Background Ingestion Dead-Letter Logging**: The `runBackground` task that handles moderation, enrichment, and Postgres UPSERTs wraps its work in a structured `try/catch`. On failure, a JSON-structured log line is emitted via `console.error` including `event`, `user_id`, `scan_id`, `error`, and `ts` fields. This replaces the previous silent swallow of background errors and makes failures observable in Supabase Edge Function logs without exposing internals to the client.
- **Shared Gemini Singleton** (`_shared/gemini.ts`): The `GoogleGenerativeAI` client is instantiated once at module scope (`_genAI`) in `_shared/gemini.ts` and imported by `identify`, `enrich-scan`, and `_shared/diagnostic.ts`. Deno reuses the same V8 isolate across warm invocations, so a module-scope singleton avoids re-creating the SDK object and its internal HTTP pool on every request. `createFlashModel(systemInstruction, maxOutputTokens)` is a shared factory for all Flash-only background calls (encyclopedic data, group tags, diagnostic comparison, enrichment). `extractJson<T>(text)` centralises the `indexOf`/`lastIndexOf` JSON extraction pattern that Gemini occasionally requires even with `responseMimeType: "application/json"`.

## On-Device Pre-Classification & Scanning Phase UX

While the Edge inference round-trip runs, `InferenceEngine` runs a concurrent **multi-pass Apple Vision pipeline** on-device. This serves two purposes: (1) driving the `ConfidenceBadge` phrase in `AnalyzingContentView` and (2) streaming a real-time analysis paragraph to `inferenceEngine.visionAnalysisText` character-by-character as each Vision pass completes.

### Multi-Pass Vision Pipeline

`classifySubjectLocally(from:)` launches a single `Task.detached(priority: .userInitiated)` that runs five sequential Vision requests against a 512 px downsampled `CGImage` (shared `VNImageRequestHandler`):

| Pass | Request | Output sentence |
|---|---|---|
| 1 | `VNClassifyImageRequest` | Category + confidence label. Also drives the subject-specific phrase series. |
| 2 | `VNGenerateAttentionBasedSaliencyImageRequest` | Subject position in frame (e.g. "Focal attention concentrated on upper-right subject.") |
| 3 | `VNRecognizeAnimalsRequest` | On-device animal species confirmation (e.g. "Robin confirmed by on-device species model.") |
| 4 | `VNGenerateObjectnessBasedSaliencyImageRequest` | Multi-subject detection (e.g. "Two distinct subjects present in scene.") |
| 5 | `VNRecognizeTextRequest` | Text/label detection ("Text or labels detected in frame.") |

Each pass calls `await self.streamSentence(sentence)` on `@MainActor`, which appends the sentence character-by-character (22 ms per character) to `inferenceEngine.visionAnalysisText`. `isVisionStreaming` is `true` for the duration of the pipeline and `false` once all five passes complete (or on cancellation). A `guard !Task.isCancelled` precedes every pass so cancellation is handled cleanly between requests.

### Phase Rotation System

`classifySubjectLocally(from:)` starts a **generic phrase series** immediately ("Scanning subject...", "Analyzing subject morphology", etc.) so `ConfidenceBadge`'s analyzing phrase is never empty. After Pass 1, if Vision returns a confident subject category, a **subject-specific phrase series** replaces the generic one after a 1.5-second hold. Phrases rotate every 2.3 seconds via a cancellable `phaseRotationTask`. Each phrase change fires `HapticManager.shared.triggerSelectionPulse()` (skipping the first to avoid a double-tap with the sheet-open haptic).

### Subject-Specific Series Qualification

A specific phrase series is only activated if all three conditions are met:

1. **Confidence threshold** — the top `VNClassificationObservation` must score ≥ 0.65 (`MerianConfig.visionConfidenceThreshold`)
2. **Margin guard** — the top observation must lead the second-best by ≥ 0.15 (`MerianConfig.visionMarginThreshold`); split/ambiguous results stay on the generic series.
3. **1.5-second minimum delay** (`MerianConfig.scanningPhaseSubjectDelayNs`) — guarantees the user always sees neutral phrases first and limits the visible duration of an incorrect category label to the back half of the scan.

If `isProcessing` has already been set to `false` by the time the hold expires (fast network response), the switch is silently dropped.

### Phrase Format

All phrases use a verb-prefix format to describe active analysis: openers ("Arthropod detected") and closers ("Confirming species...") are kept as-is; all middle phrases use "Analyzing …" for morphological examination (e.g., "Analyzing wing venation", "Analyzing skin texture") and "Checking …" for record/database lookups (e.g., "Checking eBird records", "Checking herpetology records"). `ConfidenceBadge` auto-appends `...` to any phrase not already ending with one.

### Phrase Cycling & Freshness

`startPhaseRotation` runs an infinite `while !Task.isCancelled` loop. This prevents the badge from stalling on a frozen final phrase during long `gemini-2.5-pro` responses (25–30s on slow connections). Generic phrases are shuffled on each scan (with "Scanning subject..." anchored first) so frequent users do not memorise the sequence.

### Vision → Gemini Paragraph Transition

When the Gemini result arrives and `InsightHeader` renders for the first time, `visionTransitionText` is passed as the Vision paragraph accumulated so far. `InsightHeader.onAppear` fires two haptics and two animations:

1. `HapticManager.shared.triggerLightImpact(intensity: 0.5)` — the peak reveal moment.
2. Spring animation (`.delay(0.15)`) slides the common name title up from a 10 pt offset.
3. After 700 ms, `HapticManager.shared.triggerSelectionPulse()` + `showVisionParagraph = false` — the Vision paragraph cross-fades to the Gemini `aiReasoning` text via `.easeInOut(duration: 0.45)`.

### Analyzing Mode Haptics

Four strategic haptic touchpoints span the full analysis experience:

| Moment | Call | Style |
|---|---|---|
| Vision pipeline onset (`isVisionStreaming = true`) | `triggerLightImpact(intensity: 0.3)` | Barely perceptible — "AI is reading the image" |
| Each badge phrase rotation tick (after first) | `triggerSelectionPulse()` | Subtle selection click every 2.3 s |
| Common name title reveal | `triggerLightImpact(intensity: 0.5)` | Marks the peak reveal moment |
| Vision → Gemini paragraph crossfade (700 ms) | `triggerSelectionPulse()` | Signals the hand-off from local to cloud reasoning |

### Debug Simulation

`InferenceEngine` exposes a `#if DEBUG func simulateAnalyzing()` method that sets `isProcessing = true`, seeds `visionAnalysisText` with pre-baked arthropod copy, and calls `startPhaseRotation` with the arthropod series — enabling full analyzing-state UI development in the simulator without a real scan submission.

### Supported Categories

Subject-specific series exist for: birds, insects/arthropods, arachnids, fungi/lichen, flowering plants, trees/conifers, cacti/succulents, general plants, reptiles, amphibians, fish, and mammals. Each series is 8 phrases long. Unrecognised or low-confidence subjects fall through to the generic series.

---

## Inference Latency Optimisations

The following changes were made to minimise the time between shutter press and insight sheet display.

### iOS Critical Path

- **Connection + auth pre-warm** (`CameraViewModel.init`): A background task calls `SupabaseManager.shared.getValidAuthHeaders()` the moment `CameraViewModel` is initialised — before the user composes a shot. This opens the persistent HTTPS connection to Supabase and refreshes the JWT if near expiry, eliminating TCP/TLS handshake latency (~200–400ms) and token refresh latency from the scan submission path.
- **Redundant `MainActor.run` removal** (`InferenceEngine.swift`): Post-inference state commits (gamification, awards, image paths, `speciesData`, push notification check) previously had three separate `await MainActor.run` suspension points. Since `inferenceTask` is created on `@MainActor` and returns there after each off-actor `await`, those closures already execute on main — the explicit hops were no-ops that introduced unnecessary task suspension points. All post-inference work is now inlined.
- **base64 encoding priority** (`InferenceProcessingActor`): Multi-image base64 encoding uses `withTaskGroup` at `.userInitiated` priority so the CPU-bound work is not deprioritized behind background system tasks on a loaded device.
- **Inference request timeout 90s** (`MerianNetworkClient.analyzeSubject`): The `URLRequest.timeoutInterval` for inference calls was raised from 30s (the shared default) to 90s, matching `timeoutIntervalForResource`. `gemini-2.5-pro` responses can reach 25–30s on slow connections; the previous 30s idle-timeout margin was too thin.
- **5xx retry** (`MerianNetworkClient`): A single retry after a 2s pause on HTTP 5xx responses absorbs transient Edge Function cold-start failures and momentary Deno isolate errors that would otherwise surface to the user as "Network Timeout".
- **Tier-conditional inference resolution** (`MerianConfig.inferenceImageMaxSize(isProActive:)`): Flash/free-tier captures are downsampled to **768 px** (single Gemini vision tile, ~258 input tokens); Pro captures are downsampled to **1024 px** (four tiles, ~1032 tokens). This reduces vision input-token cost by ~75% for free users with negligible accuracy impact for common-species macro-feature identification. Pro resolution is preserved to support the fine morphological detail required for subspecies and cultivar discrimination. `diContainer.revenueCatManager.isProActive` is evaluated at the capture boundary — before encoding — in both `Capture.swift` (camera shutter) and `CameraViewModel.swift` (gallery picker), so the image is already correctly sized before the Edge function receives it.
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
