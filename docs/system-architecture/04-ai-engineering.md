# 17. AI Engineering & LLMOps

Naturebook's inference engine uses `gemini-2.5-flash` for the ordinary
Naturebook tier and `gemini-2.5-pro` for the Pro tier, running inside serverless
Deno Edge Functions to protect provider keys and enforce structured output.
“Ordinary” describes Naturebook product access, not an unpaid Google API
project: production requires only `GEMINI_PAID_API_KEY` from the approved
billing-enabled project, with no unpaid-key fallback.

## Inference Layer Structure

The iOS inference layer is split across focused owners under
`apps/ios/Merian/Core/AI/`, shared `Core/SpeciesReference` infrastructure, and
its capture integration:

- **`InferenceEngine.swift`**: The main engine. Coordinates upload confirmation,
  delegates live provider preparation/dispatch, and delivers results to
  `CaptureWorkspaceViewModel`. Key `@ObservationIgnored` properties that track
  in-flight state: `inferenceTask: Task<Void, Error>?` (the live `analyze`
  task), `activeScanId: String?` (set to the `scanId` at the start of
  `analyze(scanId:...)`), `activeLiveInferenceAttemptGeneration: UUID?` (the
  presentation owner), and `activeForegroundInferenceGeneration: UUID?` (the
  durable queue owner). `OfflineQueueManager.processInferenceDownloadResult`
  reads the full tuple to detect whether the background URLSession path has
  completed for the exact live attempt it may replace — see the
  [offline pipeline InferenceEngine hydration note](../backend-and-data/01-offline-sync-pipeline.md).
  The `analyze` progression is mapped across 5 strict functional checkpoints
  enforcing UI hydration, image translation, and network payload dispatch
  gracefully. **`defer` race guard**: The `defer` block inside `analyze()`'s
  `inferenceTask` captures the scan and presentation UUID before the task body
  runs. It resets `isProcessing` and active ownership fields only when that
  local tuple still owns the slot. The durable foreground UUID is separately
  checked at provider and side-effect boundaries. Without both fences, a
  cancelled task could race against a replacement for the same scan.
  **Live-success helpers**: The visual and nonvisual success paths now share
  private `@MainActor` helpers for new-discovery marking, achievement refresh,
  completion notifications, queued-scan cleanup, reference URL normalization,
  and post-inference hydration scheduling. These helpers do not merge
  modality-specific request construction or media display setup.
  **`targetEradicationScanId` (reanalysis path)**: Both `analyze` and
  `analyzeNonVisual` accept `targetEradicationScanId: String?`, carrying the old
  scan's stable ID rather than retaining a managed record across inference
  suspensions. `transferReplacementMetadataIfNeeded(...)` passes the typed
  result outcome to `Inference/Result/InferenceScanReplacement.swift`. Only
  `.persisted` with distinct non-empty IDs, a replacement resolved in a fresh
  store context, and non-deleted original/replacement records may proceed. The
  helper copies `customTags` and non-empty collection memberships. Non-empty old
  field notes are copied only when the replacement's notes are empty. Review
  state (`userIdentificationOverride`, `userConfirmedIdentification`,
  `isFlagged`) is intentionally not transferred because this is a fresh
  analysis. The metadata save must succeed before the engine delegates
  old-record removal and queued cloud deletion to
  `ScanRepository.eradicateScan(record:modelContext:)`. On save failure, only
  the helper's staged fields are restored, preserving unrelated pending edits.
  Lookup failure, pending-only inserts, missing/same IDs, rejected persistence,
  and confidence-zero completed-without-record outcomes preserve the original
  and never authorize its cloud deletion. If later cleanup fails, retaining two
  scans is safer than deleting the original before metadata is durable.
  Confidence-zero results still publish and finalize their own exact queue
  owner; they do not count as a saved replacement. The result adapter itself
  remains free of replacement/deletion effects. **Stale enrichment/lookalikes
  guard** (`capturedScanId`): `fetchAndApplyEnrichment` captures
  `let capturedScanId = scanId` before the async `enrich-scan` network call.
  Both write sites — the enrichment scope write
  (`speciesData.habitatDescription`, taxonomy) and the lookalikes scope write
  (`speciesData.similarSpecies`) — gate on
  `self.speciesData?.scanId == capturedScanId` before mutating state. Without
  this guard, a slow enrichment Task started for scan A that completes after the
  user has already moved to scan B would overwrite scan B's `speciesData` with
  scan A's habitat description and lookalikes. The engine decides whether a
  write still matches the visible scan; it delegates task storage and ordering
  to `InferenceWriteCoordinator`.
- **`Inference/Hydration/InferenceHydrationCoordinator.swift`**: The private
  `@MainActor` owner for replaceable live, historical, and identification-review
  task slots; cancellation-ignoring task retention; Auth-transition admission
  and quiescence; bounded Wikipedia-success and historical-attempt histories;
  the persisted 24-hour enriched-species cache; and the temporary enrichment
  backoff. GBIF work is a structured child of the slot that resolved or loaded
  its taxon key. The engine supplies operations and decides presentation
  identity, observable mutation, and persistence. Raw hydration handles do not
  escape the coordinator.
- **`Inference/State/InferenceWriteCoordinator.swift`**: The private
  `@MainActor` owner for presentation generations, the Auth-transition write
  fence, and all best-effort/review write handles. It permits at most eight
  active and eight pending best-effort writes, drops overflow, clears pending
  work on presentation reset, and retains active handles until
  cancellation-ignoring work terminates. Confirm, override, flag, unflag, reset,
  and review-bound metadata writes share an ordered tail. Species-changing
  review work, same-species confirmation, and legacy flagging have independent
  per-scan action generations, each bounded to 500 entries. Confirmation
  therefore stays the newest review-state writer without invalidating live or
  historical hydration for the same species. The engine supplies operations and
  lifecycle events but cannot mutate these registries.
- **`Inference/LocalAnalysis/InferenceLocalAnalysisCoordinator.swift`**: The
  private `@MainActor` owner for Vision classification, deterministic trait,
  future Foundation-cue, and phrase-rotation task slots; the bounded derivative
  and provisional classification; request-body gate; phrase cursor; and
  application-inactivity pause/resume state. `InferenceEngine` supplies a typed
  scan/presentation/durable-generation session plus the authoritative
  current-session predicate and receives only phrase values. Raw task handles,
  the derivative, provisional candidates, and mutable phrase state do not escape
  the coordinator or participate in durable Auth draining. Sibling files under
  `Inference/LocalAnalysis/` own the classifier/category policy, image builder,
  deterministic extractor, Foundation contract/validation/eligibility, and
  phrase policy; each remains below 600 lines.
- **`Inference/Request/InferenceLiveRequestService.swift`**: The immutable,
  initializer-injected live request boundary shared by visual and nonvisual
  flows. It owns image base64 filtering and MIME detection, observation-context
  JSON, visual/audio/timeline descriptor forwarding, staged-video upload, and
  the single `/identify-multimodal` call. The engine supplies a main-actor
  exact-attempt validator after image encoding, staged-video upload, and
  provider return. Provider-ready and request-body callbacks return ownership
  effects to the engine; the service does not own presentation, queue
  retirement, parsing, persistence, or recovery state.
- **`Inference/Result/InferenceLiveResultService.swift`**: The injected live
  response-to-persistence adapter. It normalizes visual/nonvisual image
  requirements and optional audio/video paths while forwarding the original
  context JSON, canonical timeline/projection, model context, and exact
  `LiveInferencePersistenceFence` to `InferenceProcessingActor.parseAndSave`.
  The service calls the engine-supplied validator before and after that
  suspension, before mapping the outcome. Both
  `ParseAndSaveResult.didCompletePersistence` and a non-nil `mappedData` are
  required: positive confidence maps to `.persisted`, and non-positive
  confidence maps to `.completedWithoutRecord`. Otherwise the outcome is
  `.persistenceRejected`; confidence alone cannot prove completion. Parser and
  validation errors propagate to the engine unchanged, without a service-owned
  retry or recovery policy. The model context remains a main-actor input to the
  existing adapter, not a new Sendable value. AppDI owns the live request and
  result service values; neither service retains mutable attempt/task state.
  Observable commits, discovery feedback, queue cleanup, notifications,
  milestones, and hydration ordering stay engine-owned. Reanalysis metadata
  safety belongs to the synchronous `InferenceScanReplacement` helper described
  above, not to this result adapter.
- **`Inference/Recovery/`**: `InferenceLiveFailurePolicy` owns pure
  interruption, error, retirement-reason, and telemetry/circuit/feedback
  decisions; `InferenceFailurePresentation` owns recovery copy and
  `.inferenceError` `SpeciesData` construction. Both live catch paths call the
  engine's private synchronous `handleLiveInferenceFailure`. It snapshots full
  ownership, handles task cancellation, logical ownership cancellation,
  transport cancellation, and connectivity handoff in that order, then rejects
  stale attempts before queue release and terminal publication. The policy never
  reads queue state or invokes a live service; it reuses the existing Network
  stable-code helper and shared connectivity policy. The engine retains all
  effects and introduces no suspension between the ownership snapshot and
  terminal commit. Known conflict, consent, admission, observation rejection,
  and visual decoding remain outside circuit failure; nonvisual decoding retains
  its generic service/circuit path and Describe-versus-audio telemetry. Quota
  exhaustion requests the paywall without a placeholder or error haptic. No
  copy, endpoint, retry, or durable ownership contract changes with this
  extraction.
- **`Core/SpeciesReference/Services/SpeciesReferenceHydrationService.swift`**:
  The initializer-injected Wikipedia mobile-sections and GBIF taxon-key
  transport/parsing boundary shared with scan-thumbnail recovery. Its live value
  owns a cookie-free, cache-free public `URLSession`; private wire DTOs, HTML
  normalization, and GBIF image selection stay inside the service and run off
  the main actor. It returns Sendable values only. `InferenceEngine` remains
  responsible for requiring a Wikipedia overview, scan-generation checks,
  observable `SpeciesData` and media mutations, URL policy, and SwiftData
  persistence.
- **`CaptureTelemetry` abstraction
  (`Capture/Submission/Services/CaptureSubmissionTelemetry.swift`)**: Telemetry
  context creation is strictly abstracted away from UI controllers. Instead of
  view-layers writing inline logic trees to calculate and map GPS/Weather
  metrics manually, structural instantiation strictly defers to the
  `.resolveForActiveScan()` static wrapper. This strictly ensures that `Float`
  to `Double` numeric conversions for depth estimations map cleanly to payload
  schemas without risking memory bounding loops or precision errors crossing
  into the network interface.
- **`InferenceProcessingActor.swift`**: An off-main-thread actor responsible for
  base64 encoding image data, parsing Edge responses, and routing results to the
  correct `BackgroundDatabaseActor` save path. Its `parseAndSave(...)`
  parameters thread the ordered media timeline, structured observation contexts,
  and optional audio file paths through to both `saveLiveScanRecord` and
  `saveNonVisualRecord`.
- **`InferenceEdgeDTOs.swift`**: Codable DTOs used for Edge communication.
  `APIError` remains hand-written; the marked `EdgeResponseWrapper`,
  `EdgeResponse`, pet, candidate, taxonomy, quality, and insight graph is
  generated from the executable server contract with explicit coding keys and
  decoders.
- **`InferenceEdgeDTOs.swift`** also declares `EnrichScanResponse` — the
  `Codable` DTO for the `enrich-scan` Edge Function response, with nested
  `EnrichData` (maps `habitat_description`, `gbif_taxon_key`, `taxonomy`, and
  `similar_species: [SimilarSpeciesEntry]?`) and `SimilarSpeciesEntry` (maps
  `scientific_name`, `common_name`, `reference_image_url`,
  `iucn_red_list_status`) structs.

## Edge Function Architecture (`/identify-multimodal` + `_shared/identify`)

The active inference path is `/identify-multimodal`, with shared logic extracted
into `services/supabase/functions/_shared/identify/` so the live path,
`/identify`, and the legacy describe flow reuse the same executable contract,
schema, thresholds, DB helpers, media validation, and moderation logic:

- **`identify-multimodal/index.ts`**: The main active orchestrator. Executes the
  critical path (media resolution, Gemini invocation, durable moderation and
  promotion, primary species resolution, scan creation, and owner read-back) and
  spins off only optional analytics, group-tag, and candidate enrichment.
- **`_shared/identify/contract.ts`**: The dependency-free executable model and
  complete final wire contract. It generates provider schemas, infers deployed
  TypeScript payload types, runtime-validates provider and server-enriched
  values, and supplies deterministic Swift DTO generation metadata.
- **`_shared/identify/googleSchema.ts`**: The typed, exhaustive seam between the
  provider-neutral schema projection and the pinned Google SDK. SDK schema-field
  changes fail Deno checking without loading SDK runtime code into contract
  tooling.
- **`_shared/identify/schema.ts`**: The vision `systemInstruction` and cached
  provider schema generated from the executable contract. The Describe route
  generates its text-only zero-image-quality variant, and both audio-only routes
  generate their private-discriminator variant from the shared audio contract.
  `/identify` and image-only `/identify-multimodal` use the whole-frame visual
  primary-subject instruction; mixed image+audio dispatch uses its separate
  blended instruction.
- **`_shared/identify/audioSubjectPolicy.ts`**: The single audio-only prompt and
  structural normalization policy shared by active audio-only
  `/identify-multimodal` and compatibility `/audio-spec`. Its private provider
  discriminator orders resolved non-human, unresolved non-human, Human-only, and
  no-confident-biological-source results. It is consumed before public response
  assembly, so the existing Identify fields and generated Swift DTOs remain
  unchanged. Blended requests reuse only its non-human-over-Human acoustic
  tie-break and keep the existing cross-modal arbitration.
- **`_shared/identify/types.ts`**: Request/database contracts and the
  `MerianIdentification` / `ClientPayload` aliases inferred from `contract.ts`.

Provider JSON is parsed recursively against the model contract immediately after
syntax extraction. The full `{ success, data }` envelope is parsed again after
sanitization, dictionary hydration, candidate enrichment, and server-added
fields, before persistence or client delivery. This final gate rejects
requiredness, nullability, nested type, enum, cardinality, string, safe-integer,
and numeric-bound drift with stable public code `identify_response_invalid`. The
generated Swift boundary is checked exactly across the full iOS source graph by
`make validate-edge-dto-contract`. Audio-only normalization reads only the
private discriminator and structured identity fields, never `ai_reasoning`, and
provider response text is excluded from parse-failure logs.

### Visual Primary-Subject Guidance Boundary

Image-only provider instructions ask Gemini to decide the intended whole-frame
visual subject before taxonomic classification. Relative area, centrality,
focus, framing, repeated coverage, and explicit observation text are evidence.
An accepted Vision objectness `focusRegion` becomes only a tentative per-photo
attention hint; the complete image remains the provider input, and the region is
not proof of user intent. This guidance targets cases such as a laptop filling
the frame with incidental plant leaves in the background.

The boundary is not deterministic server classification. Executable-contract
parsing validates types, bounds, requiredness, and conditional response shape;
`normalizeProcessedMaterialSubject(...)` demotes manufactured and processed
objects. Neither step can infer visual prominence, so a plausible false positive
involving a background organism may still pass and persist. Tests that assert
prompt composition prove instruction wiring, not Gemini's classification of a
concrete image.

Mixed image+audio requests select `MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION`, which
retains the existing cross-modal and acoustic precedence policy and does not
currently include the complete image-only whole-frame instruction. A hinted
still photo continues to receive its tentative per-photo warning; unhinted
stills and sampled video frames do not. The shared base `is_biological_subject`
field description is also inherited by Describe and used for blended generation;
its current visual-only wording is a known semantic coordination gap. A future
harmonization must update the owning executable contract, every provider
instruction, tests, and this documentation together.

- **`_shared/identify/clientPayload.ts`**: Shared payload hydration for
  cache-hit species responses. Ensures `/identify` and `/identify-multimodal`
  project the same cached taxonomy, IUCN, hazard, habitat, GBIF key, group tags,
  and synonym fields back to iOS.
- **`_shared/identify/media.ts`**: Safely handles chunked sequential R2/Base64
  image and audio resolution to protect Deno's V8 heap under multi-item
  payloads. `parseAudioTransport(...)` proves the audio fields are arrays of
  nonempty strings and that inline bytes and staged keys are mutually exclusive
  before any `.length`, decode, or object lookup. Resolved multimodal audio must
  then pass the shared RIFF/WAVE probe and complete WAV parser; M4A is playback
  restore media, not an ordinary inference transport. One invalid clip rejects
  the complete request before the provider call.
- **`_shared/audioProcessing.ts`**: Owns the cheap `isWavContainer(...)` gate
  and the structural `processWAV(...)` decode/trim/resample/encode authority.
  Signing metadata and a `.wav` suffix do not substitute for this byte-level
  validation.
- **`_shared/identify/db.ts`**: Encapsulates PostgreSQL operations as typed,
  error-throwing helpers: `fetchCachedSpecies`, `fetchCandidateCommonNames`,
  `upsertSpeciesDictionary`, `insertScan`, `updateGroupTags`, the
  service-only/merge-aware `ensure_scan_user_profile` prerequisite, and the
  dictionary common-name merge rule that preserves existing `common_names.en`
  values over scan-level names.
- **`_shared/identify/completedResponse.ts`**: Loads exact owner-scoped
  completion before media/quota work, validates stored success envelopes,
  reconstructs pre-migration completed rows through the executable wire
  contract, and boundedly coalesces concurrent same-UUID delivery. All four
  scan-producing routes use it to replay marked `200` without another provider
  call.
- **`_shared/identify/subjectClassification.ts`**: Post-parse classification
  guard shared by visual and describe routes. It demotes manufactured or
  processed objects made from biological material to non-biological results
  before `isIdentifiedBio`, dictionary lookup/upsert, candidate enrichment, or
  novelty evaluation can run.
- **`../_shared/` Micro-Agents**: Auxiliary generation tools like
  `fetchExternalEnrichment` (Wikipedia/GBIF REST API polling in `external.ts`),
  `fetchGroupTags` (Flash AI), and `fetchStaticEncyclopedicData` are aggregated
  directly inside the generic `biology.ts` taxonomic node, making them globally
  accessible to both the `identify` and `enrich-scan` edge environments.
  `fetchSimilarSpecies` in `biology.ts` enforces **same taxonomic order as Rule
  1** in its system instruction — lookalikes must share the primary species'
  order, must exhibit genuine field visual similarity, and padding the array
  with unrelated species is explicitly forbidden. Before prompting, `biology.ts`
  normalizes placeholder taxonomy strings like `"Unknown"` / blank values to
  `null` so the model is never grounded on fake taxonomy. `external.ts` now
  additionally fetches GBIF vernacular names
  (`GET /v1/species/{key}/vernacularNames?language=eng&limit=30`) in parallel
  with occurrence imagery, returning `alternativeCommonNames: string[]` — these
  are written to `species_dictionary.alternative_common_names` on Cache Miss and
  served to the iOS client as `alternative_common_names` on Cache Hit.

## Edge Function Architecture (`/enrich-scan`)

The `/enrich-scan` Supabase Edge Function handles on-demand encyclopedic lookup
(habitat, taxonomy, and similar species lookalikes) for legacy scans lacking
full metadata.

- **`index.ts`**: The main orchestrator. Re-routes data fetched by the shared
  micro-agents, handling the concurrent `Promise.all` logic based on what
  Postgres data is currently missing. Unifies the output via
  `formatEnrichmentPayload` to strictly guarantee uniform JSON contracts back to
  Swift.
- **`types.ts`**: Strict TypeScript interfaces tracking the shape of
  `CachedSpeciesData` returned from Postgres. Removing these inline types from
  the orchestrator eliminates dangerous semantic type-casting across
  asynchronous LLM results. `CachedSpeciesData` includes
  `alternative_common_names: string[] | null`.
- **`db.ts`**: Encapsulates all Postgres operations: `getCachedSpecies`
  (dictionary lookup with `id` field), `fetchLookalikesFromJoinTable` (embedded
  join hydration from `species_lookalikes`; additionally selects `order` and
  `family` from the joined `species_dictionary` row, returned as `_order` /
  `_family` on the internal interface for stale-cache detection in the
  orchestrator), `resolveLookalikesToJoinTable` (maps Gemini-generated
  scientific names to join-table rows, back-fills `common_names`, and only
  persists entries that resolve to real `species_dictionary` rows with matching
  taxonomy), `clearLookalikesForSpecies(speciesId, supabase)` (deletes all
  `species_lookalikes` join table rows for a species, used for stale-cache
  invalidation), and `updateSpeciesEnrichment` (UPSERT patching). Lookalike
  thumbnail URLs prefer `species_reference_images` and fall back to the legacy
  comma-separated dictionary cache. `resolveLookalikesToJoinTable` now requires
  a real primary `kingdom` plus either `order` or `family`, then rejects any
  candidate lacking a matching real `kingdom` and matching `order` or fallback
  `family`. Candidates with missing taxonomy or no dictionary row are dropped
  rather than returned as provisional Flash stubs. **Stale cache detection**
  (`index.ts`): after fetching from the join table, if the primary species has a
  known `order` and all cached lookalikes carry a different known order, or if
  order is unavailable but family is known and all cached lookalikes carry a
  different known family, `clearLookalikesForSpecies` is called,
  `lookalikes_flash_attempted` and `similar_species` are reset to
  `false`/`null`, and the flow falls through to a fresh validated attempt.
  Internal `_order` / `_family` fields are stripped before serving to the iOS
  client.

### Enrichment Pipeline (`isEnrichmentLoading` / `fetchAndApplyEnrichment`)

After a successful biological scan, `InferenceEngine` automatically fires
`fetchAndApplyEnrichment(modelContext:)` for all users:

1. Sets `isEnrichmentLoading = true` — `HabitatAndDistributionCard` observes
   this via `@Environment(InferenceEngine.self)` and shows an animated loading
   skeleton.
2. Calls `MerianNetworkClient.shared.fetchEnrichment(scanId:scientificName:)` →
   POST `/enrich-scan`.
3. On success, collects all mutations into a local `var updated = speciesData`
   copy, then assigns `self.speciesData = updated` in a single write on
   `@MainActor`. This guarantees `@Observable` change notifications fire and
   `HabitatAndDistributionCard` updates live without reopening the sheet.
   Individual optional-chain mutations (`speciesData?.field = value`) do not
   reliably trigger observation for struct value types — a full-value
   replacement is the only guaranteed trigger. Fields patched:
   `habitatDescription`, `gbifTaxonKey` (when non-nil), and `taxonomy`.
4. Maps `data.similar_species` (a `[SimilarSpeciesEntry]` array, including
   `species_id` when the entry is dictionary-backed) to a local `mappedEntries`
   array, assigns it to
   `updated.similarSpecies = SimilarSpecies(entries: mappedEntries)`, then
   commits with `self.speciesData = updated` — same single-write pattern —
   triggering a live `SimilarSpeciesGallery` UI update. No confidence threshold
   gate — enrichment always sets the data, and the gallery renders validated
   entries with the stable "Similar species" label. Lookalikes are sourced from
   the validated `species_lookalikes` / `species_dictionary` path when
   available, with legacy local string fallback handled only during historical
   scan hydration.
   - **Client-side filtering:** `SimilarSpeciesGallery` removes entries whose
     scientific name matches the active species and deduplicates repeated
     scientific names before rendering. If a remaining lookalike shares the
     active species' common name, the card suppresses the duplicate common-name
     label so the scientific name remains the primary differentiator.

   **Common name resolution for lookalike species — three-tier priority:**
   - **Tier 1 (dictionary):** `fetchLookalikesFromJoinTable` reads
     `species_dictionary.common_names["en"]` via the embedded PostgREST join.
     This is the fast, zero-Flash path for all species that have been scanned at
     least once.
   - **Tier 2 (Flash + back-fill):** If the `"en"` key is absent (species in
     dictionary but `common_names` is `NULL`, `{}`, or only has non-English
     keys), `resolveLookalikesToJoinTable` calls the service-role-only, bounded
     `merge_common_name_en_batch` Postgres RPC once for the request to merge
     Flash-generated names as `{"en": "..."}` without overwriting existing
     locale keys. Implemented via a JSONB `||` merge operator:
     `COALESCE(common_names, '{}') || jsonb_build_object('en', p_en_name)` with
     a `NOT (common_names ? 'en')` guard so it is always a safe no-op for
     species that already have English.
   - **Tier 3 (drop-on-miss):** If the lookalike species is not yet in
     `species_dictionary` at all, or if its taxonomy cannot validate against the
     primary species, the entry is dropped. The long-term fix deliberately
     prefers "no card yet" over provisional unrelated cards.

   **`lookalikes_flash_attempted` flag**
   (`species_dictionary.lookalikes_flash_attempted BOOLEAN NOT NULL DEFAULT false`,
   migration `20260330160000`): Set to `true` in `enrich-scan/index.ts` after a
   Flash-sourced `resolveLookalikesToJoinTable` call completes — **only when
   `resolveResult.persisted === true`** (i.e. rows were actually written to the
   `species_lookalikes` join table). The flag is NOT set when the function
   returned early without writing (for example, missing usable primary taxonomy
   or all-failed validation). This is a critical guard: locking the flag when
   the join table was skipped would permanently prevent future enrichment
   retries for species whose taxonomy had not yet been enriched.
   ```typescript
   const hasLookalikes = lookalikes.some((l) => l.common_name !== null) ||
     cachedSpecies?.lookalikes_flash_attempted === true;
   ```
   Without the flag, species whose lookalikes are all legitimately obscure (no
   widely-recognised English common name) would cause Flash to re-run on every
   `enrich-scan` invocation indefinitely, since
   `.some(l => l.common_name !== null)` would never become true. The flag is
   **not** set by the legacy TEXT[] migration path so those species still
   trigger Flash once.

   **Recovery query for species incorrectly flagged before this guard was
   added** (covers both the empty-array case and the null-kingdom early-exit):
   ```sql
   UPDATE species_dictionary
   SET lookalikes_flash_attempted = false
   WHERE lookalikes_flash_attempted = true
     AND id NOT IN (SELECT DISTINCT species_id FROM species_lookalikes);
   ```
5. JSON-encodes `speciesData.similarSpecies?.entries` via `JSONEncoder` into a
   `Data` blob. Encode failures are logged via `MerianLog.general.debug` and
   result in `nil` — the field is never written with corrupt data. Persists all
   fields to `LocalScanRecord` via
   `BackgroundDatabaseActor.updateScanWithEnrichment(scanId:habitatDescription:gbifTaxonKey:similarSpeciesJsonData:taxonomy:)`
   through `InferenceWriteCoordinator`'s bounded background-write queue. A
   presentation reset advances the write generation, drops queued operations,
   and cancels active work, preventing a stale enrichment write from landing on
   the wrong `LocalScanRecord` when the user rapidly navigates between scans.
   The blob lands in `LocalScanRecord.lookalikesData` (`MerianSchemaV27`). The
   backend now only persists this blob for validated lookalikes; raw Flash names
   are never cached locally.
6. Sets `isEnrichmentLoading = false` (via `defer`).

`InferenceEngine.fetchAndApplyEnrichment(...)` also has a one-time retry path
for lookalikes. If metadata and lookalikes are requested together, the first
lookalikes call can legitimately return `null` because the species still lacks
usable taxonomy. Once the metadata scope lands and taxonomy becomes usable, the
engine retries the lookalikes scope exactly once within the same session.

`InferenceEngine.load(from:)` triggers enrichment for historical records that
are missing `habitatDescription`, `gbifTaxonKey`, both `lookalikesData` and
`similarSpecies`, where `lookalikesData` decodes to entries that are all
`commonName == nil` (indicating the join table was populated before the
common-name back-fill pipeline existed), or where the stored taxonomy itself is
not yet usable for validated lookalikes. Metadata scope remains
species-cache-aware, but the lookalikes scope still fires whenever the record
lacks rich local lookalike data. The `lookalikesData` blob is decoded once on
`@MainActor` for the gate check and the resulting `SimilarSpecies` value is
captured by the coordinator-owned `.historic` operation — no second
`JSONDecoder` pass on the same data.

Additionally, `load(from:)` asks `InferenceHydrationCoordinator` to record the
displayed hydration scientific name—the active override when present, otherwise
the original AI name—in its persisted enriched-species timestamp cache after a
successful enrichment call, matching the live inference path. Wikipedia,
enrichment, and GBIF use that same target so an override cannot receive the
original species' metadata or media. This prevents a redundant `enrich-scan`
Edge call when the user opens two different scan records of the same displayed
species within 24 hours. **Conditional insert guard**: the timestamp is only
written when `speciesData?.habitatDescription != nil` — a transient failure that
returns without populating `habitatDescription` remains retryable.

**Historical record load path** (`load(from:)`): When opening a scan from the
library, `InferenceEngine.load(from:)` reconstructs `speciesData.similarSpecies`
via a two-layer decode:

1. **Rich path** (preferred): If `LocalScanRecord.lookalikesData` is non-nil,
   `JSONDecoder` decodes it as `[SimilarSpeciesEntry]` and wraps the array in
   `SimilarSpecies(entries:)`. All four fields (`scientificName`, `commonName`,
   `referenceImageUrl`, `iucnRedListStatus`) are available —
   `SimilarSpeciesGallery` renders thumbnail images directly from
   `referenceImageUrl`.
2. **Legacy flat path** (fallback for pre-V27 records): If `lookalikesData` is
   nil, each string in `LocalScanRecord.similarSpecies: [String]?` is wrapped
   into a
   `SimilarSpeciesEntry(scientificName:, commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil)`.
   `SimilarSpeciesGallery` falls back to the generation-fenced
   `SimilarSpeciesImageFetcher`; its injected `SimilarSpeciesImageService` owns
   Wikipedia/GBIF metadata and thumbnail loading when
   `referenceImageUrl == nil`.

To heal previously poisoned local rich blobs, the client also carries a one-time
`localLookalikesCacheResetVersion`. When that version bumps, `load(from:)`
temporarily ignores stored `lookalikesData` / `similarSpecies`, schedules a
background wipe of those fields across local `LocalScanRecord`s, and lets
validated enrichment repopulate them.

## Multi-Modal Combined Image + Description Path

When a user stages an `ObservationContext` alongside a camera capture (or a
gallery image), `InferenceEngine.analyze()` runs a **multi-modal combined path**
that sends both the image and a structured text description to the edge
function. Current `ObservationContext` is text-only. Capture-composition time
belongs to the staged timeline wrapper; durable chronology belongs to
`ownerMediaTimeline` and final Captured Media array order, not to an `addedAt`
field inside the description payload:

1. **Media timeline build**: `analyze()` builds one ordered mixed-media timeline
   containing the current images plus any staged `ObservationContext` items,
   then passes its canonical projection to `InferenceLiveRequestService`. The
   text prompt sent to Gemini and the JSON persisted locally are both derived
   from that single source.

2. **Request/network layer**: `InferenceLiveRequestService` serializes the
   projection's observation contexts, preserves its aligned audio and owner-
   timeline descriptors, uploads staged video when present, and invokes
   `MerianNetworkClient.identifyMultiModal(...)` once.
   `MerianNetworkClient.buildMultiModalRequestBody(...)` and
   `buildMultiModalRequest(...)` deserialize the resulting JSON into
   `observation_contexts` objects alongside camelCase telemetry (`gpsLatitude`,
   `deviceTimeZone`, `currentMonth`, etc.). This is the canonical live request
   contract.

3. **Edge function**: `/identify-multimodal` merges `observation_contexts` into
   the Gemini context preamble while forwarding the structured value to
   `insertScan(... user_observation_context: ...)`.

4. **Persistence**: `InferenceLiveResultService` →
   `InferenceProcessingActor.parseAndSave(...)` →
   `BackgroundDatabaseActor.saveLiveScanRecord(..., persistenceFence: fence)` →
   scalar `LocalScanRecord.capturedMediaJSON` + V41 `capturedMediaEntries`
   mirror. New server manifests pass the strict Captured Media Wire V1 boundary:
   descriptions contain only bounded `freeText`, empty manifests are stored as
   SQL `null`, and legacy timestamps/device paths/nested video audio are never
   rewritten. The first structured observation context still persists to
   `public.scans.user_observation_context` on the cloud side.

5. **Attempt ownership**: A queue-backed live request carries the foreground
   generation created at submission. `InferenceEngine` compares it at task entry
   and supplies the request service's validator after every request-preparation
   suspension point and provider return. It also supplies the result service's
   validator before and after parsing/persistence, then checks every result or
   failure side-effect boundary. `BackgroundDatabaseActor` validates the same
   generation in the scan-ingestion job while holding the per-scan persistence
   coordinator. `OfflineQueueManager` atomically consumes the generation before
   provider dispatch and owns tokenized retirement for cancellation and
   pre-provider exits. Duplicate active or retiring generations therefore cannot
   restart, even through a second engine instance. Result publication and queue
   cleanup are owned by the single-use attempt UUID, not merely by the reusable
   `scanId`. Retirement registration immediately fences persistence, UI, and
   cleanup while raw durable release is pending. A transient durable-owner
   handoff failure retains the registry slot and retries with bounded backoff
   instead of reopening that UUID or indefinitely suppressing recovery. A
   failure handler snapshots the full current owner before synchronous
   retirement; only that owner may emit telemetry, update the circuit breaker,
   trigger an error haptic, or publish an error placeholder. A replaced task
   exits without observable failure effects. Confidence-zero is still a terminal
   response that intentionally saves no local record, but queue-backed
   foreground and generated background results must echo the exact scan ID
   before that response can finalize the job.

**Offline resilience**: the queue stores the same ordered media timeline at
enqueue time. `buildExtractedScanData` snapshots `capturedMediaItems`, and every
downstream derivation — prompt text, `observation_contexts`, local image paths,
audio paths, cleanup paths, and result hydration — is rebuilt from that one
source. New audio rows require a structurally supported local WAV before
admission. Historical local/HTTPS audio is materialized into a bounded canonical
WAV sidecar before refinement, and pre-WAV M4A/MP4 queue rows cross a durable
repair latch that clears old staging keys and atomically rewrites both timeline
representations before upload or replay. See the
[offline media contract](../backend-and-data/01-offline-sync-pipeline.md).

## Text-Only Describe Path

A text-only identification logs a past observation via `ObservationContext`
alone. The current app routes this through `/identify-multimodal` with no images
or audio attached, but still creates a zero-byte durable queue job before
provider dispatch:

1. **No image**: `InferenceEngine.analyzeNonVisual(...)` selects the nonvisual
   request path, and `InferenceLiveRequestService` never calls its injected
   image encoder or staged-video uploader for description-only submissions. The
   edge function receives structured observation context only — no
   `r2ObjectKeys`, `imageBase64s`, or `audioBase64s`.

2. **Unified edge function** (`/identify-multimodal`): The handler builds a
   text-only Gemini prompt from `observation_contexts`, takes the
   `DESCRIBE_SYSTEM_INSTRUCTION` branch, and returns the same response shape as
   the other inference modes. The legacy `/identify-describe` endpoint remains
   deployed for compatibility but is not the primary client path.

3. **`ObservationContext.isEmpty` guard**: The iOS client checks
   `observationContext.isEmpty` before enabling the submit button. An empty
   context is rejected at the UI layer.

4. **Durable ownership**: The queue inserts the scan directly as `.staged` and
   stores its foreground generation in the scan-ingestion job. The client
   revalidates that owner immediately before provider dispatch. The live save,
   result or failure publication, and successful queue deletion carry that exact
   UUID; failure hands the row to normal background replay.

5. **Persistence path**: `InferenceEngine.analyzeNonVisual` passes the ordered
   timeline and its canonical projection to `InferenceLiveResultService` with
   nonvisual image policy, then `InferenceProcessingActor.parseAndSave(...)`
   routes through `BackgroundDatabaseActor.saveNonVisualRecord(...)` and
   persists the same timeline into scalar `LocalScanRecord.capturedMediaJSON`
   plus the V41 `capturedMediaEntries` mirror.

---

## Generation Configuration Guardrails

- **Edge Native Router**: The shared identification stack powers
  `/identify-multimodal` first, with `/identify` reusing the same
  `_shared/identify` modules for schema, moderation, and DB writes. On the
  vision path it immediately checks the `species_dictionary` table before
  deciding whether enrichment is needed.
  - **Cache Hit**: If the species already exists in the dictionary with a valid
    `kingdom`, the function skips all generation loops and splices the stored
    data directly into the response.
  - **Cache Miss**: If this is the first time the species is discovered
    globally, the active inference path performs only lightweight enrichment on
    the immediate response path: it fetches Wikipedia/GBIF reference metadata
    via `fetchExternalEnrichment` and keeps IUCN / habitat / hazard fields
    deferred until later cache hits or `enrich-scan`. The same external helper
    now returns GBIF match taxonomy so the scheduled `refresh-species-content`
    worker can repair stale taxonomy without a model call.
  - **Processed-material demotion**: If the model output describes the primary
    subject as inanimate, man-made, manufactured, or processed material, and the
    subject evidence is an object/material such as a rug, textile, leather good,
    wooden furniture, paper, prepared food, artwork, toy, or species depiction,
    the shared classifier flips the result to `is_biological_subject=false`. It
    clears source-species scientific names, candidates, biology-only fields, and
    dictionary novelty before cache or upsert work can run. Living organisms,
    dead organisms, intact organism parts, fossils, pressed plants, dried
    specimens, and preserved specimens remain biological.
  - **Gap-fill condition**: If a species exists in `species_dictionary` but is
    missing `habitat_description`, the background task fires a Flash text call
    to fill the field. This covers species stored before the enrichment pipeline
    was introduced.
  - **Scheduled public-content refresh**: `refresh-species-content` is not part
    of the live inference path. It claims `gbif_wikipedia_reference` jobs from
    `species_enrichment_jobs`, falls back to `species_content_provenance`, and
    refreshes GBIF/Wikipedia-backed public fields. The paired
    `refresh-species-model-content` worker handles queued habitat, lookalikes,
    and group tags; IUCN status, hazard type, and common-name overrides remain
    curation-owned.
- **Flat Object Schema (Non-Biological Bounds)**: `merianModelContract` in
  `services/supabase/functions/_shared/identify/contract.ts` generates a single
  flat `OBJECT` provider schema — not a top-level `anyOf` with discriminated
  branches. All biology-specific fields (`ecology_type`, `is_invasive`,
  `invasive_status_region`, `invasive_rationale`, `invasive_confidence`,
  `life_stage`, `reproductive_condition`, `sex`, `sex_confidence`,
  `sex_evidence`, `individual_count`, `ecological_interactions`) are declared
  with `nullable: true` and are absent from the `required` array.
  `scientific_name` and `common_name` are likewise `nullable: true` to support
  identifiable geological subjects (rocks, minerals) while permitting omission
  for generic debris. Every numeric model property carries explicit finite
  bounds: confidence values are `0...1`, image-quality dimensions are `1...10`
  with `overall_score` at `0...100`, and `individual_count` is `1...99999`. The
  same bounds are enforced recursively on live provider and final response
  values. Generated JSON integers map to Swift `Int` and JSON numbers to
  `Double`; the boundary never infers a narrow integer from its nominal range.
- **Two-Call Identification Architecture (Optimised TTFM)**: Every scan follows
  a two-stage pipeline designed for absolute lowest "Time-To-First-Meaning"
  (latency from shutter to first UI render):
  1. **Vision call** (`identify-multimodal` for active app traffic): Routes to
     `gemini-2.5-pro` (Pro) or `gemini-2.5-flash` (free). This is the fastest,
     initial pass. It evaluates core identity (`scientific_name`, `common_name`,
     `confidence_score`, `inference_tier`, `is_biological_subject`) and
     instance-specific photo dependencies (`ai_reasoning`,
     `extracted_visual_traits`, `life_stage`, `reproductive_condition`, `sex`,
     `sex_confidence`, `sex_evidence`, `individual_count`, `ecology_type`,
     `ecological_interactions`). The model executes a "Micro-CoT" (Chain of
     Thought) by generating exactly 3 `extracted_visual_traits` _before_
     attempting classification. This ordering is strictly guaranteed by
     anchoring `extracted_visual_traits` and `ai_reasoning` at the top of the V8
     JSON Schema object, preventing the model from committing a classification
     until textual evidence is written. The invasive-status assessment
     (`is_invasive` plus region, rationale, and confidence) also securely
     remains here, pulling natively from the user's GPS/coarse location; forcing
     this to a secondary text payload would incur a sequential ~500ms network
     penalty. Heavy structure-agnostic generation fields (`hazard_type`,
     `colors`, `blur_score`) were explicitly **stripped** from the Vision schema
     properties and prompt omissions to boost inference speed.
     - **Structured Markdown Directives & Darwin Core Dictionary**:
       `getSystemInstruction()` in
       `services/supabase/functions/_shared/identify/schema.ts` defines
       instructions natively in Markdown. This serves two purposes: (1) grouping
       rules semantically improves LLM instruction-following versus dense
       paragraphs; (2) appending an extensive `Darwin Core Semantics Dictionary`
       block pushes the system instruction above the 2,048-token implicit
       caching threshold for `gemini-2.5-flash` while enforcing machine-exact
       semantics for DwC-A export. Key constraints include: `scientificName`
       must omit author citations/hybrid markers; exact phenotype boundaries for
       `lifeStage` (e.g. `larva` vs `nymph`), `reproductiveCondition` (e.g.
       `sporing`, `gravid`), and `sex` (including conservative
       `cannot_determine` handling); and treating fossils/preserved specimens as
       valid biological ID targets with `is_live_capture = false`.
     - **Disambiguation & Confidence Calibration**: Disambiguation prefers the
       species with the highest documented observation frequency in the
       region/season at the tiebreaker level, while expressly prohibiting the
       inflation of `confidence_score` just because a species is seasonally
       expected. Explicit calibration anchors (≥0.95 = unambiguous diagnostic
       features visible; 0.80–0.94 = confident but similar species can't be
       ruled out; 0.60–0.79 = probable; <0.60 = insufficient diagnostic detail)
       are embedded in the `confidence_score` field description of
       `merianModelContract` so the model encounters them in the generated
       structured output schema.
     - **`common_name` schema contract**: Defined in
       `services/supabase/functions/_shared/identify/contract.ts` as a nullable,
       bounded string in the flat model object. It is **not** required, so the
       model may omit it for non-biological subjects such as generic debris,
       while still populating it for identifiable geological subjects (rocks,
       minerals). `common_name` is not persisted to `public.scans`. For
       biological cache misses it may fill `species_dictionary.common_names.en`,
       but an existing English dictionary name always wins over the scan label.
       Non-biological processed-material results may still return an object
       display name, but they never write that name into `species_dictionary`.
  2. **Enrichment Text pass** (`enrich-scan`, plus follow-up cache warming):
     Generates the bulky metadata. `fetchStaticEncyclopedicData` is a text-only,
     image-free Flash prompt used by enrichment flows to deduce `hazard_type`,
     generalised `colors`, `taxonomy`, `habitat_description`, and
     `iucn_red_list_status` without slowing the first response from
     `/identify-multimodal`. `gbif_taxon_key` is fetched natively from GBIF APIs
     and then served back on later cache hits.
- **Tier-Based Model Selection**: The schema generated from
  `merianModelContract` is applied to all requests regardless of tier. Model
  selection is tier-based: effective Pro users use `gemini-2.5-pro` for maximum
  identification depth (rare species, fossils, subspecies, cultivars); effective
  free users use `gemini-2.5-flash` for 2–3× lower latency. `_shared/aiQuota.ts`
  obtains the model from an atomic database reservation rather than trusting the
  client or isolate memory. The reservation separates model choice from paid
  storage: paid subscribers and active paid 7-day passes return
  `plan = "pro_paid"`; held or available lifetime credits return
  `plan = "pro_complimentary"`; and exhausted compatible single-evidence
  captures return `plan = "free"` through the separate daily Flash policy.
  `pro_trial` is retained only for historical reservations and reports.
- **Fossil, Geological & Non-Biological Handling**: The system instruction
  explicitly distinguishes liveness from biological identity. Fossils, pressed
  plants, museum specimens, and dried organisms are
  `is_biological_subject = true` with `is_live_capture = false` — they are
  identified to species level (e.g. "Devil's Toenail" for _Gryphaea arcuata_).
  Geological objects (rocks, minerals) are evaluated as
  `is_biological_subject = false`, but Gemini is explicitly instructed to
  populate their `scientific_name` and `common_name`. This "soft expansion"
  allows the iOS app to neatly label geological items in the UI while safely
  bypassing Linnean-dependent species hydration, caching, and taxonomy
  enrichment. Only generic non-natural debris (buildings, food, shadows) sets
  `is_biological_subject = false` with omitted identification names.
- **`blur_score` Field**: Gemini's image sharpness diagnostic metric, surfaced
  as a `Double` in the range 0 (sharp) to 1 (very blurry). Extracted linearly
  from the formal required `image_quality.sharpness` encyclopedic schema matrix
  and mathematically derived natively within V8 inside the main edge
  orchestrator to bypass LLM latency loops. Mapped to `EdgeResponse.blur_score`
  in `InferenceEdgeDTOs.swift` and carried through to `SpeciesData.blurScore`.
  Populated from live inference only — `nil` for scans loaded from the local
  SwiftData library since it is not persisted to `LocalScanRecord`. Surfaced in
  `ScanScoreCallout` inside `ConfidenceExplanationSheet` as a blur advisory when
  the score exceeds 0.5.
- **`image_quality` Object**: Gemini evaluates the photographic quality of each
  submitted image as a structured sub-object in the executable shared contract
  (`services/supabase/functions/_shared/identify/contract.ts`), which generates
  the provider response schema. The object contains three sub-scores (each
  1–10): `sharpness` (optical clarity), `framing` (subject positioning and
  composition), and `diagnostic_utility` (how useful the photo is for species
  identification), plus an `overall_score` (0–100) aggregating all three. All
  four fields are required in the Gemini response schema. The inferred
  TypeScript alias is `ImageQuality` in
  `services/supabase/functions/_shared/identify/types.ts`; the Swift counterpart
  is the `ImageQuality` struct in `InferenceEdgeDTOs.swift`
  (`image_quality: ImageQuality?` on `EdgeResponse`). Only `overall_score` is
  persisted — to `public.scans.image_quality_score` (SMALLINT, migration
  `20260330150000_add_image_quality_score_to_scans.sql`) and to
  `LocalScanRecord.imageQualityScore` (`MerianSchemaV30`).
- **Implicit Context Caching (Flash tier)**: Gemini 2.5 models support implicit
  context caching — when repeated requests share an identical prompt prefix
  (system instruction), Google's backend automatically serves those prefix
  tokens from cache at a 75% token discount with zero SDK configuration. The
  minimum cacheable prefix for `gemini-2.5-flash` is **2,048 tokens**. The
  original system instruction in
  `services/supabase/functions/_shared/identify/schema.ts` measured ~550 tokens,
  below this threshold. The expansive Markdown-formatted
  `Darwin Core Semantics Dictionary` block and disambiguation rules push the
  system prefix toward the cacheable range; chat prompts in
  `services/supabase/functions/insight-chat` keep the repeated scan/species
  evidence before the variable conversation history so active Pro follow-up
  sessions can benefit from the same implicit-cache behavior.
- **Primary multimodal token budget (`maxOutputTokens: 8192`)**:
  `/identify-multimodal` keeps the existing 8,192-token ceiling for both tiers
  so the complete structured identification schema is not truncated. Other
  Gemini routes retain their own route-specific limits; the latency work does
  not normalize or lower any output budget.
- **Token Telemetry Tracking**: To measure AI inference costs accurately, Edge
  functions intercept Gemini `UsageMetadata`. The immediate identification path
  records the primary vision call and any synchronous group-tag work that
  actually runs inside that request lifecycle; deeper encyclopedic and
  similar-species enrichment is tracked separately by `EnrichmentCostAnalyzed`
  and the biology micro-agent events. Scan token telemetry includes
  backward-compatible `tier` plus explicit `effective_tier`, `plan`,
  `subscription_tier`, `trial_active`, and `llm_model` fields so
  `gemini-2.5-pro` spend can be split between paid Pro, complimentary Pro, and
  historical trial Pro. The `/identify` `ScanCompleted` event also includes
  `llm_cached_tokens` (from `usageMetadata.cachedContentTokenCount`) to track
  implicit cache hit volume — a non-zero value means Google served those prefix
  tokens from cache at the 75% discount rate.
- **Field Chat (`insight-chat` + `explore-post-chat` +
  `species-dictionary-chat`)**: Pro follow-up chat uses `gemini-2.5-flash` from
  authenticated Edge Functions and appears as an Insight, private per-viewer
  Explore, or private per-viewer Species Dictionary conversation surface.
  Insight context is text-only evidence from the owned completed scan; Explore
  context is only the privacy-filtered public post and Species Dictionary
  projection; Dictionary context is the latest bounded canonical names,
  taxonomy, overview, habitat, hazard, conservation, group tags, and lookalikes.
  Dictionary grounding excludes sightings, observation charts, scans, notes,
  users, locations, media, reference URLs, and attribution identities, and
  fences all source text as untrusted data. No route receives raw media, object
  keys/URLs, exact GPS, another viewer's chat, or export payloads.
  Conversations, messages, and feedback are private per user and subject. User
  messages are capped at 600 characters, each conversation at 30 messages, and
  all three routes share 20 sends per Pro user per day. That allowance is an
  admission-history limit: deleting private chat content must not restore sends
  from the same UTC day. Migration
  `20260824210544_preserve_field_chat_daily_usage.sql` introduces the
  content-free user/UTC-day aggregate, atomic admission increment, cascade
  independence, and conservative Ghost coalescing. The service-only read fails
  closed without a live-message fallback. The handler is registered in the
  effective Ghost policy allowlist and the migration asserts registry coverage.
  Because a lower-bound seed cannot recover already-deleted current-day rows,
  PostgreSQL short-locks all three conversation/message families, removes
  historical message-less threads, blocks every novel reservation through its
  recorded next UTC boundary and until explicit post-bundle activation, and
  permanently reserves conversation insertion for the atomic RPC; exact
  persisted replays remain available. Token usage and bounded telemetry retain
  route-specific events without prompt/chat text or dictionary identity. All
  routes use `_shared/fieldChatResponse.ts` so every empty/populated thread and
  action success echoes the exact requested scan/post/species as `subject_id`;
  iOS treats `200` as candidate evidence and validates that echo plus populated
  message/conversation identity before applying it. Every send requires a UUID
  request identity; the assistant stores its canonical lowercase form in private
  metadata and projects it as `client_message_id`, allowing duplicate,
  transport, and quota replays to coalesce into one saved user/assistant pair. A
  new send reserves its two rows within the 30-row cap; UUID reuse with
  different text fails explicitly. `_shared/fieldChatReservation.ts` calls the
  service-only atomic admission RPC, which locks per user before a deterministic
  subject resource, secures the shared 20/day slot, creates or reuses the exact
  conversation, inserts the user row, and applies 30-row/unanswered-request
  checks in one transaction. Browser roles have no direct chat-table or feedback
  privileges, so they cannot bypass admission or forge a copied rating target.
  Deferred composite foreign keys bind every retained Insight conversation to
  its exact scan owner, each retained message to its exact
  conversation/scan-or-post-or-species/viewer, and each rating to the exact
  copied message identity. Conversation-optional feature feedback has its own
  exact scan-owner binding; impossible historical cross-bound private rows are
  removed before those constraints validate
  (`20260730180000_bind_field_chat_rows_to_subjects.sql`). Dictionary tables,
  three-family admission/recovery, and account merge are added by
  `20260821030027_add_species_dictionary_field_chat.sql`. Deterministic
  assistant UUIDv8 rows and read-after-write reconciliation make answer
  persistence idempotent, including concurrent local refusals. In-flight replay
  polling is bounded, failed provider or persistence attempts resume under the
  same UUID, and iOS requires the exact pair, bounded message text, and a 1 MiB
  decode ceiling before clearing a pending send. Manual retry preserves the UUID
  rather than creating another question. Prompt suggestions are non-persisted,
  at most three strings of 120 characters, use allowlisted telemetry categories,
  and do not consume the send limit. Action-intent filtering blocks ingestion,
  treatment, dangerous handling, exact-location, and human-identification
  requests without rejecting harmless species names or educational ecology
  language. Insight note summaries scrub canonical UUIDs including UUIDv7 and
  fall back to bounded non-sensitive text if scrubbing empties the draft. An
  exact-row-bound service routine may reopen a committed request only after a
  ten-minute crash-safety window and proof that its assistant is absent; the
  retry is newly metered. After every production-hold criterion passes, apply
  the dictionary migration and then the durable daily-usage migration before any
  updated version of the three chat functions, then deploy them from one
  reviewed SHA and smoke same-UUID replay, different-key concurrency, both
  limits, stale recovery, and empty/action subject echoes before shipping the
  fail-closed iOS validator. Source fixtures use the real reservation RPCs and
  full Ghost merge orchestrator, enforce the pending/ready/active database
  cutover, and prove quota denial creates no empty conversation. One-way
  activation follows successful deployment of all three selected bundles and
  live observation of their `atomic-admission-v1` compatibility marker and
  candidate-derived `X-Merian-Field-Chat-Bundle-SHA256`, then records candidate,
  migration, and all three route digests. Database `ready` force-selects the
  fleet after the migration becomes the deployment baseline. Swift and Deno
  execute one versioned scalar fixture for U+2013 EN DASH, U+0085 normalization,
  U+FEFF rejection, punctuation, combining marks, and length boundaries. The
  handler tests cover the post-authenticated core and execute the actual wrapper
  with deterministic accepted/refused authenticators. The checked-in
  `species_dictionary_chat_production_hold` blocks production until controls
  execute without a database skip, hosted real-token wrapper evidence, same-SHA
  hosted gates, the real released-binary V49→V50 install-over, and external
  approvals pass. Its verifier requires the named hold ID before Production. If
  reviewed inactive, the independently exact-SHA-checked mutation job requires a
  protected clearance bound to the manifest, complete criterion set, GitHub
  artifacts, and current approval. It downloads and recomputes the evidence,
  verifies exact-SHA runs, and checks live branch/environment protections before
  mutation.
- **Dynamic Diagnostic Thresholds**: The dynamic presentation of diagnostic data
  (e.g., lookalikes, confidence hooks, and identification candidates) is gated
  by the tier-specific `diagnosticTrigger`. **Canonical source of truth**:
  `services/supabase/functions/_shared/identify/thresholds.ts` — exports
  `FLASH_STRONG = 0.95`, `FLASH_POSSIBLE = 0.75`,
  `FLASH_DIAGNOSTIC_TRIGGER = 0.99`, `PRO_STRONG = 0.85`, `PRO_POSSIBLE = 0.65`,
  `PRO_DIAGNOSTIC_TRIGGER = 0.99`, and `diagnosticTriggerForTier(tier)`. The iOS
  client mirrors the strong/possible thresholds in
  `MerianConfig.flashConfidence` and `MerianConfig.proConfidence`. The Possible
  thresholds are also the automatic evidence boundary for Field trip progress.
  An unreviewed score below the applicable boundary must not receive standard
  outing or Event credit; explicit confirmation or a confirmed
  correction/community resolution can qualify it later. Any threshold change
  must update the database evidence helper, migration contract, Field trip
  behavior tests, and
  [canonical progress policy](../features-and-hardware/25-field-trips.md#identification-evidence-policy)
  together. The diagnostic trigger (0.99 for both tiers) is intentionally above
  the `strong` threshold — candidates are stripped only when the model is
  effectively certain, so Possible, Weak, and Strong scans below `0.99` can
  still persist candidate alternatives as an escape hatch. Client display
  remains gated by `CandidateReviewVisibilityPolicy`.
  - **Similar species**: The enrichment path fetches or generates
    `similar_species` when validated lookalikes are not already cached in the
    database. The Swift client renders those entries with the stable "Similar
    species" gallery label in Insight and Explore detail. Confidence-specific
    uncertainty UX lives in `CandidatesCard`, not in the similar-species
    gallery.
  - **Identification candidates**: `candidates` is a **required field** in
    `merianModelContract` (`contract.ts`). Biological subjects are instructed to
    return exactly 2 alternative species, while non-biological subjects return
    an empty array. The server clears candidates for processed-material
    demotions and strips biological candidates to `null` if
    `confidence_score >= diagnosticTrigger` _before_ sending the response and
    before `insertScan`. This server gate is the sole confidence enforcement
    mechanism; the model is not asked to conditionally self-suppress biological
    candidates (which was unreliable). Candidates are persisted per-scan to
    `public.scans.candidates` (JSONB) and on-device to
    `LocalScanRecord.candidatesData` (Data blob, `MerianSchemaV28`). Persisted
    candidates do not automatically render UI: the iOS client filters them
    through `CandidateReviewVisibilityPolicy`. Candidate-review UI appears when
    the primary confidence is below the tier's Strong threshold, or when a
    Strong primary has a top candidate with `confidenceScore >= 0.80` within
    `0.15` of the primary confidence. The same thresholds feed the Needs review
    smart collection. Baseline guards suppress candidate review for unknown,
    non-biological, human, confirmed, overridden, and alternatives-exhausted
    scans. Legacy flag values no longer suppress candidate review.
  - **User identification review** (`MerianSchemaV29`): Users can confirm or
    override the AI's identification from the policy-visible `CandidatesCard` or
    the confidence explanation sheet. The pending card shows a direct
    confirmation affordance plus a Review alternatives path that opens
    `CandidateSwipeModal`; the swipe modal owns stack/grid review, skip/reject,
    candidate confirmation, exhausted-state recovery, optional reanalysis, and
    Ask the Community routing. The scan insight top menu uses the same
    policy-filtered candidate list for `Confirm species` and
    `Review alternatives`, while `Reanalyze species` and `Ask the community`
    remain separately gated. Within `IdentificationReview`, Services are the
    only layer that invokes the engine review mutations. Their view models
    revalidate the captured scan and presentation generation, then pass the
    expected scan ID into the engine so a replaced result cannot receive the
    deferred mutation.
    - `InferenceEngine` exposes three methods for this flow:
    - `applyIdentificationOverride(scientificName:expectedScanId:modelContext:)`:
      Immediately wipes all stale contextual fields (`wikipediaOverview`,
      `referenceImageUrl`, `habitatDescription`, `gbifTaxonKey`,
      `similarSpecies`, etc.) and sets `userIdentificationOverride` and
      `scientificName` to the chosen species name in a **single full-value
      replacement** (`speciesData = updated`) to guarantee `@Observable` fires
      exactly once for the entire wipe. It first enqueues and awaits
      `BackgroundDatabaseActor.beginScanIdentificationOverride`, which
      atomically persists the override state and cleared scientific-name
      placeholder before network suspension. It then resolves the confirmed UUID
      asynchronously via `fetchAndPatchOverrideData` and updates
      `LocalScanRecord` via
      `BackgroundDatabaseActor.updateScanWithOverride(scanId:override:confirmed:newConfirmedSpeciesId:userReviewState:)`
      (passing `.userOverridden`), and syncs to `public.scans` via
      `syncIdentificationReviewToCloud`.
    - `confirmAIIdentification(expectedScanId:modelContext:)`: Sets
      `speciesData.userConfirmedIdentification = true` through a full-value
      observable replacement. It advances the independent confirmation action
      generation, leaving same-species live/historical hydration valid, and
      rejects a stale confirmation action after an override presentation has
      already become current. It then securely fetches the immutable native UUID
      from SwiftData via a localized `FetchDescriptor`, avoiding corrupted view
      states. Persists to `LocalScanRecord` via `updateScanWithOverride`
      (passing `.aiConfirmed`), and syncs all three review variables to
      `public.scans` via `syncIdentificationReviewToCloud`.
    - `resetIdentificationReview(expectedScanId:modelContext:)`: Clears
      `userIdentificationOverride`, `userConfirmedIdentification`, the legacy
      `isFlagged` bit, and `alternativesExhausted`, reverts
      `speciesData.scientificName` to `aiScientificName`, and clears
      override-owned presentation metadata before any suspension. It enqueues
      the local `.unreviewed` mutation and cloud reset on the ordered
      identification tail. The local mutation atomically clears the same stale
      common-name, hazard, taxonomy, Wikipedia, reference, conservation,
      habitat, GBIF, lookalike, and alternate-name fields; every later hydrated
      metadata write is serialized behind it. The Species Dictionary request may
      execute while that reset drains, but cannot persist its patch ahead of the
      reset. Called by Undo, Change, and the alternatives-exhausted reset path.
    - `fetchAndPatchOverrideData(scientificName:scanId:modelContext:restoringAiReasoning:enrichOnCacheMiss:replacingSpeciesIdentity:reviewActionGeneration:)`:
      Queries `species_dictionary` via a PostgREST array select with `.limit(1)`
      and takes `.first` (the Supabase Swift SDK does not provide a
      `.maybeSingle()` method). On cache hit, collects all field updates —
      `commonName`, `insightData` (hazard type + aiReasoning), `taxonomy`,
      `iucnRedListStatus`, `habitatDescription`, `gbifTaxonKey`,
      `referenceImageUrl`, `wikipediaOverview`, `wikipediaUrl` — into a local
      `var updated = speciesData` copy, then commits with a single
      `speciesData = updated` assignment on `@MainActor`. This full-value
      replacement guarantees `@Observable` fires once for the entire patch;
      individual optional-chain mutations (`speciesData?.field = x`) do not
      reliably trigger observation for struct value types (see Gotcha §11 in
      `docs/development-guides/11-swiftdata-and-api-gotchas.md`). Also persists
      the same fields to `LocalScanRecord` via
      `BackgroundDatabaseActor.updateScanWithOverrideSpeciesData` so the data
      survives sheet dismissal and reopen without requiring a network call. For
      interactive override/reset, nil taxonomy plus prior
      lookalike/alternate-name values are destructive replacement inputs, not
      “leave unchanged” signals; this prevents one durable record from combining
      two species. Historical refresh passes `replacingSpeciesIdentity: false`,
      so a sparse row cannot erase valid same-species taxonomy or lookalikes
      already stored on the record. `scientificName` is intentionally excluded
      from this write — `record.scientificName` is preserved as the original-AI
      identifier and reused as `aiScientificName`. `commonName` is resolved with
      locale preference matching `ScanRepository.ingestScans`:
      `names["en"].flatMap { $0 } ?? names.compactMap { $0.value }.first ?? scientificName`.
      The `restoringAiReasoning` parameter controls the `aiReasoning` field in
      `InsightData`: pass `nil` (default) when calling from
      `applyIdentificationOverride` to wipe the AI reasoning (it was written for
      the rejected species); pass `record.aiReasoning` when calling from
      `resetIdentificationReview` so the original reasoning reappears after
      undo. For interactive apply, the atomic local admission has already
      persisted the scientific-name `commonName` placeholder. Reset has already
      enqueued its atomic `.unreviewed` placeholder ahead of every later
      metadata write on the same tail. On cache miss, either interactive path
      calls `fetchAndApplyEnrichment` using the already-mutated
      `speciesData.scientificName`; historical refresh passes
      `enrichOnCacheMiss: false` and leaves the single enrichment/GBIF sequence
      to its enclosing `.historic` operation.
    - `syncIdentificationReviewToCloud(scanId:override:confirmed:confirmedSpeciesId:userReviewState:)`:
      Private IDOR-guarded PATCH that sends `user_identification_override`,
      `user_confirmed_identification`, `confirmed_species_id`, and
      `user_review_state` together within a single `ReviewSyncPayload` Encodable
      struct. Accepts nil properties (encodes as JSON null → SQL NULL). Called
      by `applyIdentificationOverride`, `confirmAIIdentification`, and
      `resetIdentificationReview`.
  - `InferenceEngine.load(from:)` restores review state from `LocalScanRecord`
    on historical opens. When `userIdentificationOverride` is non-nil, two rules
    apply: (1) `speciesData.scientificName` is set to
    `userIdentificationOverride` (the override name) rather than
    `record.scientificName` (the original AI name), making the correct species
    title immediately visible without waiting for any async step; (2)
    `InsightData.aiReasoning` is suppressed, since the AI's vision reasoning was
    written for the original species and is misleading under the override name.
    `record.scientificName` is always used as `aiScientificName` — it is never
    overwritten — so `resetIdentificationReview` can recover the original name
    across any number of reopens. The coordinator-owned historical operation's
    Step 3 still fires `fetchAndPatchOverrideData` asynchronously as a freshness
    refresh (re-patching the same species data from the network), but display
    correctness no longer depends on this call completing.
- **Telemetry Pruning**: Legacy ephemeral fields (`cameraPitchDegrees`,
  `compassHeading`, `relativeHumidity`, `uvIndex`, `isFlashFired`) have been
  removed from the `CaptureTelemetry` JSON payload, saving hundreds of tokens
  per request. Schema nodes like `key_differentiators` and descriptive enum
  schemas inside Deno are compressed into flat string arrays. **Active telemetry
  fields** sent as a context string prefix to the vision prompt: `GPS` (lat/lon,
  range-validated), `Elev` (meters), `Depth` (scale text), `Zoom` (factor, only
  when >1), `Size` (subject size in cm from `estimated_size_cm` — a primary
  morphological discriminator for species pairs that differ primarily by size),
  `Loc` (semantic location name), `Wx` (weather condition), `Temp` (°F),
  `Locale` (device locale), `TZ` (IANA timezone), `Region` (ISO country code),
  `Month`, and `Time` (time of day). `estimated_size_cm` is validated as
  positive and finite before inclusion; the DB-level 50,000 cm cap is enforced
  separately at write time.
- **Deterministic Sampling (`temperature: 0.1`, `seed: 42`, `topK: 40`)**: Both
  `modelConfigs.flash` and `modelConfigs.pro` set `temperature: 0.1` (very low
  randomness), `seed: 42` (fixed random sampler state — identical inputs produce
  the same token sequence across runs), and `topK: 40` (caps the candidate-token
  pool, narrowing the sampling distribution for borderline identifications).
  Together these three parameters ensure that repeated scans of the same subject
  converge on the same identification rather than drifting across runs due to
  sampling noise. Genuine uncertainty is still expressed correctly through a
  lower `confidence_score` and populated `candidates` array — the determinism
  parameters eliminate noise, not signal.
- **Multi-Capture Context Fusion**: The `identify` Edge function accepts an
  array of `r2ObjectKeys: string[]`. Deno fetches R2 presigned URLs and encodes
  them to base64 in a single serial `for…of` loop. Each response body is
  consumed through `_shared/mediaBudgets.ts` capped stream readers: declared
  `Content-Length` is checked first, then chunks are counted as they arrive, the
  stream is cancelled on overflow, and the buffer is assembled only after the
  body stays within the aggregate 5 MB budget. The two-loop pattern previously
  used (a first pass checking `Content-Length` headers, a second pass consuming
  bodies) was eliminated because chunked transfer encoding makes
  `Content-Length` absent on R2 responses, allowing arbitrarily large payloads
  to exhaust the 256 MB Deno V8 heap before any guard fired. Serial body
  consumption also prevents back-pressure across V8's I/O loop when multiple
  bodies resolve simultaneously. The resulting base64 strings are injected as
  distinct `inlineData` MIME parts into the Gemini prompt, supporting macro
  shots alongside wider environmental images.
- **Base64 Payload Guard**: Before the R2 fetch loop, the Edge function
  validates that the incoming `imageBase64s` array has no more than 5 entries
  and that the total base64 byte length does not exceed 7 MB (≈ 5 MB raw).
  Requests violating either bound are rejected with `HTTP 400` / `HTTP 413`
  before any I/O runs, protecting Deno memory and Gemini quota.
- **Durable Ingestion Ledger, Compatibility Background Work, and Dead-Letter
  Logging**: Before AI inference, `identify-multimodal` claims
  `scan_ingestion_jobs` with expected media counts, staged object keys,
  recovered upload-session ids, and a deterministic `manifest_checksum`. Claim
  creation shares a per-scan database generation lock with compatibility
  recovery; stage updates then expose processing, finalizing, retryable,
  terminal, and complete states to `/check-scan-status` and the media
  reconciliation worker. The current multimodal route awaits moderation,
  required media promotion, primary species resolution, scan insertion,
  owner-scoped read-back, and a final transaction that proves every claimed key
  disposition plus every ready canonical media row. The response-aware wrapper
  writes ledger completion and the validated success envelope atomically.
  Canonical proof uses structured captured media when usable and otherwise the
  refresher's legacy standalone-image/playback/audio projection; sampled video
  inference frames retained in the compatibility image array are not display
  rows. Migration `20260729012153_fix_video_scan_canonical_finalization.sql`
  corrected the contradictory all-image-array check without relaxing exact
  owner, kind, URL, or staging-disposition requirements. Repeated delivery
  checks for stored completion or an exact reconstructible owner row first and
  returns marked `200`; reconstruction may coexist with a retryable canonical
  ledger, and concurrent delivery coalesces without another model call. Only
  analytics, group tags, and candidate enrichment remain behind
  `EdgeRuntime.waitUntil`. The same request records `scan_ingestion_intents`, a
  service-role-only sanitized schema-v3 replay payload with a
  `payload_checksum`; observation contexts are text-only, and raw inline media
  bytes are redacted and mark the intent non-resumable. Schema-v2 rows remain
  readable, but any retired description timestamp is discarded by multimodal
  normalization. The scheduled `replay-scan-ingestion` worker claims due
  resumable intents and dispatches them back through `identify-multimodal` with
  the same `client_scan_id`; inline-media rows remain client retry only. Server
  replay is capped at 10 claims per sanitized intent, after which the job
  becomes `failed_terminal / server_replay_limit_reached`. Compatibility
  scan-producing endpoints (`identify`, `identify-describe`, and `audio-spec`)
  now use `_shared/scanIngestionCompatibility.ts` to write the same ledger
  before provider dispatch and await their exact owner scan plus a complete-last
  finalization attempt before returning. A post-row finalization failure may use
  only the narrow validated compatibility fallback, with a retryable ledger.
  Their staged media and text-only intents are shaped as multimodal replay
  requests, while inline media is recorded only as redacted counts; failed
  required insertion retains the ledger/dead-letter fallback. All producer
  adapters settle through the shared exact-owner persistence boundary, so an
  ambiguous database response preserves quota and media instead of deleting a
  possibly committed reference. Operational finalization failures emit a
  structured event. They return customer-safe `503 scan_persistence_failed`
  before owner-row commit and to a fresh multimodal invocation; only the
  documented exact-owner compatibility/replay paths may deliver the validated
  response. Terminal policy rejection returns `400 observation_rejected`.
  Detailed failures remain observable in Supabase Edge Function logs without
  exposing internals to the client.
- **Shared Gemini Singleton** (`_shared/gemini.ts`): The `GoogleGenAI` client
  (from `@google/genai@1.0.0`) is instantiated once at module scope (`_genAI`)
  in `_shared/gemini.ts` and imported by `identify`, `enrich-scan`, and
  `_shared/diagnostic.ts`. Deno reuses the same V8 isolate across warm
  invocations, so a module-scope singleton avoids re-creating the SDK object and
  its internal HTTP pool on every request.
  `createFlashModel(systemInstruction, maxOutputTokens)` is a shared factory for
  all Flash-only background calls (encyclopedic data, group tags, diagnostic
  comparison, enrichment); it returns the **native `@google/genai`
  `GenerateContentResponse`** directly — callers access `result.text` and
  `result.usageMetadata` without any `.response` wrapper. The old compatibility
  shim that normalised to `{ response: { text: () => string, usageMetadata } }`
  has been removed now that all callers (`biology.ts`) are updated to the native
  SDK shape. Generation config is passed as `config:` (not `generationConfig:`).
  `extractJson<unknown>(text)` centralises the `indexOf`/`lastIndexOf`
  syntax-extraction pattern that Gemini occasionally requires even with
  `responseMimeType: "application/json"`. It does not establish a type.
  `_shared/identify/contract.ts` performs the model and final wire runtime
  validation.
- **Vision Model Safety Settings**: Both `modelConfigs.flash` and
  `modelConfigs.pro` in `identify/index.ts` include a shared
  `BIOLOGICAL_SAFETY_SETTINGS` array that relaxes two harm categories to
  `BLOCK_ONLY_HIGH`: `HARM_CATEGORY_DANGEROUS_CONTENT` (venomous animals, dead
  specimens, parasites, wounds trigger false positives at the default
  `BLOCK_MEDIUM_AND_ABOVE`) and `HARM_CATEGORY_SEXUALLY_EXPLICIT` (mating
  behaviour, reproductive organs, fruiting bodies). `HARM_CATEGORY_HARASSMENT`
  and `HARM_CATEGORY_HATE_SPEECH` remain at defaults — they are not relevant to
  biological photography. `BLOCK_ONLY_HIGH` passes all legitimate field-biology
  content while still blocking unambiguously harmful material.

## On-Device Pre-Classification & Scanning Phase UX

While the Edge inference round-trip runs, `InferenceEngine` drives progressive
local context through its existing SwiftUI-facing `scanningPhaseText`. Gemini
remains the only authority for species identity and completed Insight content.

### Current Pipeline

`AppDIContainer` owns injected `VisionSubjectClassifying`,
`LocalVisualTraitExtracting`, and `FoundationVisualCueProviding` implementations
and the live light-impact start-feedback closure; direct/default engine
instances use inert feedback. `InferenceEngine` passes those dependencies into
the private local-analysis coordinator and retains only presentation authority
plus observable `scanningPhaseText`. For the primary visual item, the
coordinator builds one bounded image, applying its accepted, already-padded
`NormalizedImageFocusRegion` when present and otherwise using the full square
inference image. The local derivative is bounded to 512 px and reused;
additional captures are not analyzed locally, and Gemini's request payload is
not changed.

The coordinator starts generic copy and injected light-impact feedback
immediately, then runs `AppleVisionSubjectClassifier` off the main actor. A
qualifying broad category is returned through the engine's phrase callback as
soon as Vision returns. The coordinator then launches its separately owned
deterministic-trait task without awaiting it. `AppleImageVisualTraitExtractor`
samples the same local derivative at 32×32 pixels and deterministically
describes its dominant colors, saturation distribution, lighting distribution,
light contrast, and surface detail. The five pixel observations are validated
against the Vision candidate denylist and become eligible at the next phrase
tick. Numeric midpoint buckets are converted to plain observations—for example,
**Reviewing softly colored areas** or **Observing light and shadow
areas**—rather than exposing phrases such as **moderate color levels** or
**balanced light and dark**.

A single `ScanningPhraseCoordinator` owns the monotonic source order: generic →
Vision category → deterministic image trait → Foundation Models cue. A less
specific tick therefore cannot replace image-derived context. The injected
phrase sleeper keeps automatic transitions at the 2.3-second cadence without
exposing partial tokens.

### Broad-Category Qualification

A broad-category phrase series is only activated if all four conditions are met:

1. **Confidence threshold** — the top `VNClassificationObservation` must score ≥
   0.65 (`MerianConfig.visionConfidenceThreshold`)
2. **Margin guard** — the top observation must lead the second-best by ≥ 0.15
   (`MerianConfig.visionMarginThreshold`); split/ambiguous results stay on the
   generic series
3. **Category map** — the top observation's tokenized identifier must map to one
   of the supported broad categories below; substring-only collisions do not
   qualify
4. **Ownership guard** — scan ID, presentation-attempt UUID, and durable
   foreground generation must all match the task that launched Vision

### Phrase Format

Generic, category, and image-trait decks describe only directly visible
morphology: form, color, contrast, texture, structure, arrangement, proportions,
and markings. Deterministic traits and future Foundation cues share the bounded
cue validator: details contain 2–5 words, the rendered pill plus ellipsis is at
most 36 characters, and duplicate, identity-bearing, certainty, match, taxonomy,
`-like`, or unsupported text is discarded. Local copy must not imply species
identity, confidence, a candidate match, a database or record lookup, geographic
range, or Gemini completion. `ConfidenceBadge` auto-appends `...` to any phrase
not already ending with one.

The constrained trait kind selects a natural action verb but is never exposed as
a field label. Render **Analyzing gray and green colors**, for example, rather
than **Color: gray and green tones**. Other kinds vary the action with wording
such as Reviewing, Comparing, Studying, or Tracing.

### Phrase Cycling & Freshness

`InferenceLocalAnalysisCoordinator` owns one cancellable phrase-rotation task.
The generic phrase is visible immediately; a qualifying Vision category hands
off immediately and restarts the interval so another label cannot follow less
than 2.3 seconds later. Later phrases advance through
`MerianConfig.scanningPhaseRotationIntervalNs`. Deterministic image traits enter
at the next clock tick. Foundation cues, when available, replace that deck at a
later tick and permanently raise source priority. `ScanningPhraseCoordinator`
records every normalized phrase already displayed during the scan and advances
through every currently available deck entry before wrapping to index zero for a
new round. A newly appended cue is consumed before the deck can wrap. When all
five deterministic image cues qualify, they span 11.5 seconds at the shared
cadence before their first repeat.

An active visual live-to-queue handoff snapshots this ephemeral order only after
the typed presentation owner matches both scan ID and attempt generation. The
current phrase remains first, unseen entries retain priority over phrases
already shown, and queue/server/save/connectivity changes do not restart its
cursor. Offline copy temporarily overlays rather than consumes the deck. A
prepared visual handoff receives the full generic deck without live media;
audio, Describe, and stale-owner handoffs receive no visual context. The
snapshot is cleared on result, replacement, dismissal, historical load, or Auth
reset and is never persisted, logged, or analyzed.

`InferenceEngine.genericScanningPhasePhrases` preserves the established
cloud-analysis deck for ordinary queued Insights, including audio-only and
Describe scans. `QueuedContentView` reuses that vocabulary while the server is
actively processing unless it is presenting the exact online handoff described
above, while preserving queue-specific phrases for upload, retry, finalization,
offline, and needs-attention states. Both paths render through
`ScanningExperienceView`, so phrase-source differences do not create a second
scanning layout.

### Haptics & Debug Simulation

- Local classification start fires `triggerLightImpact(intensity: 0.3)`.
- Result arrival, dismissal, replacement, queue handoff, Auth transition, and
  inference failure fence Vision, pixel-trait extraction, phrase rotation, and
  Foundation work while leaving durable networking intact. Dismissal also
  invalidates contextual media exposure, while Auth clears phrase and media
  ownership atomically. App deactivation stops local work but retains the exact
  visual owner and visible phrase. The normal consecutive inactive/background
  callbacks are idempotent and retain one pending resume; reactivation restarts
  cadence only for that owner and never for audio or Describe.
- `simulateProgressiveAnalyzing()` supplies the deterministic generic → category
  → visible-trait seed used by UI automation.

### Supported Categories

Broad-category series exist for: birds, insects/arthropods, arachnids,
fungi/lichen, flowering plants, trees/conifers, cacti/succulents, general
plants, reptiles, amphibians, fish, and mammals. Unrecognised, low-confidence,
or ambiguous subjects do not receive a category phrase, but can still advance
from generic copy to deterministic image-trait wording.

### Stable Xcode 27 Foundation Models Milestone

The release toolchain remains Xcode 26.6 with an iOS 17.2 deployment target.
`UnavailableFoundationVisualCueProvider` is therefore the current injected
implementation; no beta Foundation Models API ships. After stable Xcode 27 is
available locally and in hosted CI, the provider can be implemented behind iOS
27 availability without changing the deployment target.

This no-op applies only to generative multimodal cues. The injected
`AppleImageVisualTraitExtractor` already supplies image-specific color,
lighting, contrast, and surface wording on the current toolchain and remains the
silent fallback when the richer provider is unavailable or ineligible.

The provider contract is deliberately stricter than its UI consumer:

1. Start only after `onRequestBodySent` and local Vision completion, so model
   loading cannot delay Gemini and candidate labels can seed the identity
   denylist.
2. Use only `SystemLanguageModel.default`; unavailable or not-ready Apple
   Intelligence returns no stream and never falls back to Private Cloud Compute.
3. Request at most three broad-to-specific indexed cues, each with a constrained
   trait kind and a generated 2–5-word visible detail.
4. Buffer cumulative snapshots until each indexed cue object is complete.
5. Accept only unique rendered phrases of at most 36 characters, rejecting
   certainty, match, taxonomy, identity/candidate, `-like`, or unsupported text.
6. Skip or stop the stage when the app is inactive, Low Power Mode is enabled,
   or thermal state is serious/critical.

Vision classifications and cue text are ephemeral. They are never persisted,
sent to Gemini, attached to analytics, or logged. Foundation work is an
asynchronous, best-effort UI enhancement and is never awaited by networking,
persistence, or result publication; even a permanently hung stream is fenced and
cancelled at terminal ownership boundaries.

Deterministic trait extraction has the same non-blocking ownership rule. Its
protocol requires cooperative cancellation, but the engine still owns it as a
separate weak-engine task: an injected implementation that ignores cancellation
cannot suspend Vision completion, networking, result publication, or an Auth
drain, and its eventual return fails both cancellation and scan-generation
checks before touching the phrase coordinator.

This milestone changes no backend route, wire DTO, SwiftData schema, consent
surface, analytics event, or privacy-manifest declaration. Reassess those
contracts before any future provider changes the on-device-only boundary.

#### Stable-toolchain activation checklist

Do not activate the production provider until stable Xcode 27 is installed both
locally and on every hosted macOS lane. The migration is one reviewed toolchain
change, not an isolated source edit:

1. Change the exact Xcode generation pin in `project.yml`, keep the iOS 17.2
   deployment target, run `make xcodegen`, and review the generated project
   rather than editing it manually.
2. Update the `DEVELOPER_DIR` checks, asserted version strings, and Xcode-scoped
   Swift package cache keys in `.github/workflows/ios-build-and-test.yml` and
   `.github/workflows/ios-startup-safety.yml`.
3. Update the matching project guard in `scripts/check-ios-project-resources.sh`
   and workflow-contract expectations in
   `scripts/test-ios-build-and-test-workflow.sh`.
4. Update the supported-toolchain statements in `docs/CONTRIBUTING.md`,
   `docs/README.md`, the testing strategy, and the codebase map in the same
   change.
5. Add an iOS 27 availability-gated provider using only
   `SystemLanguageModel.default`. Preserve the request-body-sent start gate,
   readiness and runtime checks, structured buffering, cue validation,
   cancellation fences, and no-Private-Cloud-Compute rule above.
6. Format every changed Markdown file with `deno fmt`, then run `make xcodegen`,
   `make validate-ios-project`, the focused AI and Insight suites, the complete
   iOS unit and critical UI suites, and `make test-ios-ci-tooling`. Build the
   iOS 17.2 fallback and iOS 27 path, then verify enabled, disabled,
   model-not-ready, Low Power Mode, and serious/critical thermal states on a
   physical Apple Intelligence-capable device before release acceptance.

---

## Inference Latency Optimisations

The following changes were made to minimise the time between shutter press and
insight sheet display.

### iOS Critical Path

- **Pinned-session connection + auth pre-warm**
  (`CaptureWorkspaceViewModel.init`): a background task refreshes auth and sends
  an `OPTIONS` request to `/identify-multimodal` through `MerianNetworkClient`'s
  actual TLS-pinned `URLSession`. This warms the same connection pool used by
  inference instead of warming only the Supabase SDK's separate auth session.
- **Bounded environmental-context grace**
  (`Capture/Submission/Services/CaptureSubmissionEnvironmentContextGrace.swift`):
  durable queue acceptance remains mandatory. For eligible live-camera still
  scans, WeatherKit and reverse geocoding receive at most 150 ms after
  acceptance. That budget races context acquisition only; it does not bound
  existing telemetry preparation, including optional LiDAR/Vision size
  estimation, or total dispatch time. On timeout, submission continues with
  shutter-time coordinates/date/time/distance plus cached telemetry. Late
  weather or location is merged locally and through `/update-scan-context`; it
  never causes a second Gemini call. The deferred service writes locally before
  remote delivery and retries a real first failure at most once after 500 ms;
  endpoint, transport, and task cancellation are terminal. Queue rejection,
  queue-only routing, connectivity loss, supersession, and unavailable
  foreground ownership cancel context work with no live consumer. A
  timeout-losing late task retains only the injected deferred-context service
  and bounded telemetry inputs. A primary gallery image cancels any unrelated
  live-device lookup and uses its embedded historical context. Gallery,
  audio-bearing, and video submissions otherwise keep their prior full-context
  behavior in this pass.
- **Live/background upload handoff**: the eligible active live-camera still scan
  is durably queued but excluded from background upload until the inline request
  body finishes sending. Upload progress releases the queue immediately; a
  two-second fail-safe, transport failure, connectivity loss, app backgrounding,
  or relaunch keeps recovery durable without creating uplink contention. All
  other online queue-backed live paths may stage recovery media immediately, but
  their exact foreground inference generation prevents replay from starting a
  competing identification. A final online check after the bounded context grace
  catches path changes before dispatch. After dispatch, the required customer
  contract retires the live provider generation and binds that same sheet to the
  durable queued scan on the first transport failure, where **Queued for later**
  replaces a synthetic network error while background recovery continues. The
  durable-queue-owned foreground request is capped at 15 seconds, more than
  twice the documented six-second cache-hit p95 target; direct queue-less
  requests retain the 90-second provider window. Source now enforces that
  post-dispatch contract by using exact local presentation identity for the
  queued acknowledgement after connectivity retirement; provider/result commits
  still require durable ownership. A gated URLSession regression protects both
  path-retirement ordering and a path-satisfied timeout with the owner still
  active. Hosted exact-SHA and physical-device acceptance remain open; see the
  [live scan connectivity handoff incident](../incidents/2026-08-live-scan-connectivity-handoff-gap.md).
- **First-result commit before secondary work** (`InferenceEngine.swift`): after
  response parsing and local persistence, saved media and `speciesData` are
  committed immediately. Award calculation and Field trips run asynchronously;
  the server scan-ingestion transaction applies Field trip progress before the
  scan is reported persisted. Client follow-up retrieves the idempotent receipt
  for notifications without placing progress correctness on the first-result
  task.
- **base64 encoding priority** (`InferenceLiveRequestService` →
  `InferenceProcessingActor`): The request service invokes the actor's multi-
  image encoder, which uses `withTaskGroup` at `.userInitiated` priority so the
  CPU-bound work is not deprioritized behind background system tasks on a loaded
  device.
- **Inference request timeout 90s** (`MerianNetworkClient.identifyMultiModal` /
  `buildMultiModalRequest(...)`): The `URLRequest.timeoutInterval` for inference
  calls was raised from 30s (the shared default) to 90s, matching
  `timeoutIntervalForResource`. `gemini-2.5-pro` responses can reach 25–30s on
  slow connections; the previous 30s idle-timeout margin was too thin.
- **Queue-backed transport retry ownership**: The generic authenticated helper
  retains one selected transient `URLError` replay after two seconds when the
  caller permits ambiguous replay. `identifyMultiModal` now exposes a per-call
  policy: queue-backed live Identify disables that replay and returns the first
  transport failure for immediate exact-ID queue handoff, while reviewed
  queue-less/read/route-propagation behavior remains scoped to its existing
  callers. Protected request-count and bounded-timing regressions lock both
  sides. Exact-SHA and device execution remain release blockers.
- **5xx retry** (`MerianNetworkClient`): A single retry after a 2s pause on HTTP
  5xx responses absorbs transient Edge Function cold-start failures and
  momentary Deno isolate errors. If both attempts fail, queued work uses
  **Analysis delayed / Scan saved** rather than misreporting a server failure as
  device connectivity loss. That fallback is presentation error state, not a
  non-biological classification: its explicit `SpeciesData.presentationRole` is
  `.inferenceError`, so `isInferenceErrorPlaceholder` remains correct even when
  display copy changes. The queue-handoff source gates are repaired; hosted and
  device acceptance remain open.
- **Tier-conditional inference resolution**
  (`MerianConfig.inferenceImageMaxSize(isProActive:)`): Flash/free-tier captures
  are downsampled to **768 px** (single Gemini vision tile, ~258 input tokens);
  Pro captures are downsampled to **1024 px** (four tiles, ~1032 tokens). This
  reduces vision input-token cost by ~75% for free users with negligible
  accuracy impact for common-species macro-feature identification. Pro
  resolution is preserved to support the fine morphological detail required for
  subspecies and cultivar discrimination. The live entitlement owner is
  evaluated at the capture boundary before encoding: Scan carries it through
  `CaptureWorkspaceViewModel+PhotoCapture.swift` into
  `CaptureScanStillMediaPreparer`, while gallery input uses
  `CaptureWorkspaceViewModel+Imports.swift`. The image is therefore already
  correctly sized before the Edge function receives it.
- **Image compression quality 0.85** (`MerianConfig.imageCompressionQuality`):
  Raised from 0.80 to preserve fine morphological detail (feather barbs, insect
  wing venation, leaf margins) that influences AI identification accuracy. File
  size increase is ~10–15%, well within the 5 MB payload limit.

### Edge Function Critical Path

- **Local JWKS claims verification**: `/identify-multimodal` verifies the ES256
  JWT through the opt-in `claimsAuth.ts` `auth.getClaims(token)` path and
  validates signature-backed claims, issuer, audience, expiration/not-before,
  role, and `sub`. Anonymous and authenticated users remain supported;
  service-role JWTs are rejected on the public inference path. The cached JWKS
  path avoids an Auth-server request per scan, while the opt-in policy boundary
  keeps unrelated routes on their established `getUser` behavior. All Edge
  Functions use the same exact pinned Supabase SDK and shared frozen dependency
  lock.
- **Atomic ingestion setup RPC**: upload-session lookup, ingestion-job claim,
  sanitized replay-intent recording, and the `ai_inference_started` transition
  execute through one service-role-only SQL RPC. A compatibility fallback keeps
  rolling deployment safe until the migration reaches every environment.
- **At most one dictionary hydration RPC**: after Gemini returns, eligible
  biological results fetch cached primary-species data and candidate common
  names together. Moderation, required media promotion, primary cache-miss
  species resolution, and the scan insert form one durability boundary for every
  current multimodal observation: the route cannot return success until the
  owner row exists. Analytics, group tags, and candidate enrichment remain
  optional `EdgeRuntime.waitUntil` work.
- **Atomic critical-path consent and entitlement reservation**: Before iOS
  constructs a provider request, it pushes pending account consent and requires
  a fresh adult/Terms/all-version-Gemini-head proof. The service-role RPC
  repeats that consent decision before creating any reservation. Only then does
  it lock the user before quota or ledger rows, resolve `pro_paid`,
  `pro_complimentary`, or `free`, acquire an idempotent hold keyed by
  `(user_id, client_scan_id)`, select the operation's allowlisted model, and
  conditionally consume UTC-day/user/IP provider counters. Retries, internal
  replay, enrichment, chat, and subcalls retain the original analysis linkage
  without acquiring another credit. Each provider attempt has a ten-minute lease
  and UUID fencing token. Active timed passes are paid Pro; stale expired
  profiles resolve free. Missing/malformed user rows and database errors fail
  closed. `403 ai_consent_required` therefore consumes no entitlement or
  provider quota and is routed to durable disclosure recovery, while `402` and
  `429` retain entitlement and quota semantics. The first-user failure and
  exact-SHA closure test are recorded in the
  [first-scan consent-policy incident](../incidents/2026-08-first-scan-consent-policy-retry-loop.md).
- **No isolate-local entitlement authority**: RevenueCat tier changes advance a
  durable version in the same row update. Every provider reservation reads that
  database state, so another Edge isolate cannot retain stale Pro access.
  `_shared/entitlement.ts` also performs an uncached durable read for
  non-provider feature gates and telemetry.
- **Cost-safe settlement**: Provider counters are consumed while a reservation
  is `reserved` and are preserved after an attempted call. Complimentary holds
  settle independently: durable scan plus required media completion consumes a
  hold (including valid non-biological results), proven terminal failures
  release it, and retryable or ambiguous outcomes remain held for recovery. The
  service-only completion orchestrator locks the user before established
  scan/job locks and stores the enriched entitlement envelope atomically. The
  complete state machine, derived balances, client protocol, and rollout rules
  are normative in
  [`18-complimentary-pro-scans.md`](../backend-and-data/18-complimentary-pro-scans.md).
- **No hidden enrichment dispatch**: Overview, lookalike, and group-tag cache
  misses each reserve their explicit operation and pass the database-selected
  model to the biological helper. Service-only scheduled refreshes remain
  bounded and name their reviewed model directly.
- **System instruction structured via Markdown**: The instruction was migrated
  from a dense single paragraph to structured hierarchical Markdown headers
  (`# Subject Liveness & Status`, `# Identification Rules`, etc.). This
  dramatically improves instruction-following and TTFM alignment natively within
  Gemini's attention mechanisms.

### Benchmark Timing

Timing starts when Analyze is tapped, before environmental context and durable
queue persistence. `[⏱ BENCH]` markers and response headers provide both client
and server boundaries:

**iOS (`MerianLog.general.debug`)** — visible in Xcode console (filter:
`⏱ BENCH`) and Console.app:

```
[⏱ BENCH] tap→durable queue: 0.041s
[⏱ BENCH] context grace: 0.150s timed_out=true
[⏱ BENCH] URLSession request_upload=0.082s ttfb_after_upload=4.101s response_transfer=0.022s
[⏱ BENCH] HTTP identify-multimodal auth=0.006s transfer+server=4.205s status=200 requestBytes=183424 responseBytes=7824
[⏱ BENCH] Response parsing: 0.009s bytes=7824
[⏱ BENCH] Result persistence: 0.061s
[⏱ BENCH] response→first-result state: 0.082s
[⏱ BENCH] tap→first rendered frame: 4.478s
```

`requestBytes` and `responseBytes` are deliberately separate. Older clients
logged the request body count under an ambiguous `bytes` label, so that legacy
field is not evidence about response size or JSON topology.

**Edge Function (`console.log`)** — visible in Supabase Dashboard → Edge
Functions → identify-multimodal → Logs:

```
Server-Timing: auth;dur=3.1, body_read;dur=11.8, tier;dur=0.4, pre_gemini_db;dur=7.2, gemini;dur=4189.0, dictionary;dur=5.6, post_gemini;dur=8.1, edge_total;dur=4223.4
{"event":"multimodal/latency","tier":"free","model":"gemini-2.5-flash","image_count":1,"payload_bytes":183424,"edge_region":"...","constrained_network":false,"auth_ms":3,"gemini_latency_ms":4189,"edge_total_ms":4223}
```

`gemini_latency_ms` stops immediately when `generateContent` returns;
dictionary, enrichment, ingestion, and response assembly are not included.
Diagnostic headers are privacy-safe and do not contain scan, user, species,
location, or media identifiers. The production gates are non-Gemini p50 ≤300 ms,
non-Gemini p95 ≤1 second, and response-to-first-render p95 ≤300 ms. Region
selection remains automatic until an A/B test demonstrates at least a 150 ms p95
improvement with no failure-rate increase.

This work deliberately does not change inference economics or semantics. Free
remains `gemini-2.5-flash`, Pro remains `gemini-2.5-pro`, and thinking budgets,
schema, image resolutions, output-token limits, prompts, and one primary
identification Gemini call per scan remain fixed. If measured end-to-end p95
remains high while the `gemini` timing dominates, that model duration is the
documented latency floor.

### Production Rollout Gate

Deploy timing instrumentation first, then the client critical-path changes, then
the Edge/RPC migration. Edge changes advance through 10%, 50%, and 100% only
while non-Gemini p95 is ≤1 second, response-to-first-render p95 is ≤300 ms,
failure rate rises by less than 0.5 percentage points, identification-quality
metrics remain neutral, and missing remote scans/stuck ingestion jobs do not
increase. Automatic nearest-user Edge execution remains the baseline; a forced
database-region deployment requires an A/B p95 improvement of at least 150 ms
without higher failures.

## Canonical usage ledger

`public.ai_usage_events` is the source of truth for internal AI analytics. Scan
and Field assistant-message inserts populate it from database triggers so the
durable application row and successful usage event share a database write
boundary. Independent overview/lookalike/group-tag enrichment, Field prompts and
summaries, and Explore audio moderation use bounded background RPC writes.
Gemini `usageMetadata` is normalized into prompt, cached, candidate, thinking,
tool, total, and per-modality counts; prompts and responses are never stored.
Effective-dated model prices produce clearly labeled estimates. Historical token
columns are idempotently backfilled as partial/primary-only, and account
deletion clears account linkage while retaining aggregate usage.

`geminiUsageModalityBreakdown(...)` stores `prompt`, `cached`, `candidates`, and
`tool` objects inside the ledger's legacy-named `prompt_tokens_by_modality`
column. Preserve that nested shape when adding a writer; do not flatten
categories or put content into the JSON.

Canonical operations currently include:

- `scan_identification`
- `scan_overview_enrichment`
- `scan_lookalike_enrichment`
- `scan_group_tag_enrichment`
- `insight_chat_reply`
- `insight_chat_prompt_suggestions`
- `insight_chat_summary`
- `explore_audio_moderation`

Do not create a new spelling for an existing semantic operation. New Gemini call
sites must choose an operation, exact returned model, effective plan, input
modality, outcome, durable linkage, coverage scope, and normalized
`usageMetadata`. The ledger metadata field may contain non-content execution
facts, but never prompts, responses, report text, chat text, coordinates, or
media URLs.

Primary scan and assistant-message events use database triggers over durable
rows. Other operations call `recordAIUsageBestEffort` with a bounded background
write and structured failure logging. A best-effort writer is acceptable only
when the application result is durably independent of the ledger write; a
primary durable scan/message insert must not silently skip its transactional
event.

The unique source key `(source_type, source_id, operation)` makes retries and
backfill idempotent. When no stable source row exists, design one before relying
on retry deduplication. Account deletion invokes the tightly scoped
account-linkage clearing path; arbitrary event update/delete remains prohibited.

Admin analytics distinguish:

- **Primary per-scan usage**: successful `scan_identification` events grouped by
  scan.
- **All scan-related usage**: every filtered event carrying the same `scan_id`.
- **Cache hit rate**: events with cached tokens divided by events whose cached
  token field is known.
- **Complete coverage from**: earliest non-backfilled event in the selected
  range. Earlier historical rows remain explicitly partial.

Estimated cost uses the exact price row effective at `occurred_at`. Non-cached
prompt tokens use input price, cached tokens use cached-input price, and
candidate/thinking/tool tokens use output price. The seed represents Gemini 2.5
Standard pricing; it does not model long-context tiers, grounding/search/maps,
cache storage time, batch/flex/priority service, tax, credits, or negotiated
discounts. Price changes append a new effective-dated version rather than
rewriting historical rows. The maintenance procedure is in
[`../backend-and-data/11-internal-admin-operations.md`](../backend-and-data/11-internal-admin-operations.md#pricing-maintenance).

Google's authoritative references are the
[GenerateContent usage metadata](https://ai.google.dev/api/generate-content) and
[Gemini pricing table](https://ai.google.dev/gemini-api/docs/pricing).
