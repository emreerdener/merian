# Database Schema & Data Models

This document maps the expected shape of our persistence layers. AI Agents should refer to this to bind TypeScript interfaces and Swift `Codable` structs without guessing.

## Supabase PostgreSQL Schema (`00001_initial_schema.sql`)

### `users`

Tracks the global state of the anonymous/authenticated user.

- `id` (UUID): Maps to the `auth.users` GoTrue unique identifier, automatically generated via standard Supabase Ghost Sessions with IDFV fallback. Mapped into PostHog/RevenueCat telemetry for ecosystem-wide session continuity.
- `subscription_tier` (ENUM): `'free'` | `'pro'`
- `default_geoprivacy` (ENUM): `'open'` | `'obscured'` | `'private'`. Dictates the GPS fuzzing applied to new scans. `obscured` rounds coordinates to a ~50km approximation; `private` hides them from all public bounds.
- `current_streak_count` (Int): Gamification metric.
- `total_species_discovered` (Int): Calculated at the database level via a Postgres `AFTER INSERT` trigger (`update_user_species_count()`). To avoid TOCTOU race conditions during bulk offline uploads, it recalculates the sum via a subquery (`COUNT(DISTINCT species_id)`) rather than auto-incrementing. DO NOT MANUALLY UPDATE THIS FROM CLIENT CODE OR EDGE FUNCTIONS. This metric is also maintained via an `AFTER DELETE` trigger (`decrement_user_species_count()`) that deducts from the sum when a user deletes their last scan of a species.
- `abuse_strikes` (INT, DEFAULT 0): Incremented by the `/identify` background moderation pipeline each time Gemini's safety ratings flag submitted media as `MEDIUM` or `HIGH` probability, or when `finishReason === "SAFETY"`. Never decremented automatically. See [Safety & Moderation](../development-guides/10-safety-and-moderation.md).
- `is_shadowbanned` (BOOLEAN, DEFAULT false): Set to `true` when `abuse_strikes` reaches 3. Shadowbanned users continue to receive AI identification responses (the HTTP response is unchanged), but all background ingestion silently halts — no scans are persisted. Not currently read by the iOS client.


### `species_dictionary`

The global source-of-truth for biological models.

- `id` (UUID): Primary key.
- `scientific_name` (Text): Unique. (e.g., _Danaus plexippus_)
- `common_names` (JSONB): Keyed by ISO 639-1 language code. e.g., `{"en": "Monarch Butterfly"}`. Always written under the `"en"` key by the identify Cache Miss path.
- `kingdom`, `phylum`, `class`, `order`, `family`, `genus` (Text): Standard Linnaean taxonomy.
- `wikipedia_overview` (Text): Cached Wikipedia summary paragraph for the species. Written by the identify Cache Miss path from the Wikipedia REST API (`/page/summary`). Served to the client as `wikipedia_overview` in the `/identify` response. Mirrors `LocalScanRecord.wikipediaOverview` and `SpeciesData.wikipediaOverview` in the Swift layer.
- `hazard_type` (TEXT): Hazard classification for the species. CHECK constraint enforces one of: `'none'` | `'poisonous'` | `'venomous'` | `'allergenic'` | `'irritant'`. Added in migration `20260327000000_add_hazard_type.sql`. This column exists only on `species_dictionary` — **not on `scans`**. The feed reads it from `species_dictionary` via join.
- `wikipedia_url`, `gbif_taxon_key`, `reference_image_url`: Extended biological context.
- `native_region` (Text): Origin markers.
- `habitat_description` (Text): Summarizes the expected ecosystem parameters for the species.
- ~~`global_distribution_regions`~~ (JSONB): Dropped in migration `20260327140000_drop_global_distribution_regions.sql`. Previously populated with Gemini Flash-generated ISO 3166-1/3166-2 region codes that proved inaccurate. Species geographic range is now communicated exclusively through the GBIF occurrence density tile overlay (driven by `gbif_taxon_key`).
- `similar_species` (Text Array): Legacy flat array of similar species scientific names. Populated by `fetchSimilarSpecies` (Gemini Flash) via the `enrich-scan` Edge Function on Cache Miss. Kept for backwards compatibility — the authoritative rich lookalike store is now the `species_lookalikes` join table. Added as `diagnostic_lookalike_name TEXT` in `20260326200000_add_diagnostic_comparison.sql`, converted to `diagnostic_lookalikes TEXT[]` in `20260329062600_add_lookalike_species_array.sql`, and renamed to `similar_species` in `20260329070941_rename_similar_species.sql`.
- ~~`diagnostic_primary_rationale`~~: Dropped in `20260329070941_rename_similar_species.sql`. Previously stored the primary identification rationale for low-confidence scans.
- ~~`diagnostic_differentiators_json`~~: Dropped in `20260329070941_rename_similar_species.sql`. Previously stored a JSON-encoded array of key field marks distinguishing the species from its lookalike.
- `group_tags` (Text Array): Broad-to-specific categorical labels for the species (e.g. `["animal", "bird", "songbird", "warbler"]`). Generated once by a `gemini-2.5-flash` background call on the first scan of a species; subsequent scans read from this cache. Returned to the client in the `/identify` response as `group_tags` and merged into `LocalScanRecord.semanticTags` for library keyword search. Added in migration `20260327100000_add_group_tags_to_species_dictionary.sql`.

### `species_lookalikes`

Self-referential join table linking species that are visually similar or commonly confused. Added in migration `20260329200000_add_species_lookalikes.sql`. This is the authoritative source for rich lookalike data returned by the `/enrich-scan` Edge Function.

- `species_id` (UUID FK → `species_dictionary.id`, CASCADE DELETE): The subject species.
- `lookalike_id` (UUID FK → `species_dictionary.id`, CASCADE DELETE): A species that could be confused with the subject.
- Primary key: `(species_id, lookalike_id)`. Composite ensures uniqueness; a `CHECK (species_id != lookalike_id)` prevents self-links.
- All links are **one-directional** — `resolveLookalikesToJoinTable` inserts `(speciesId, lookalike)` only; the reverse `(lookalike, speciesId)` is intentionally not written. A pine cone is not necessarily a lookalike for a rose just because Flash once suggested the reverse. Bidirectional writes caused cross-family contamination that bypassed the kingdom-only validation guard.

**Postgres trigger** (`trg_link_taxonomy_lookalikes`): Fires `AFTER INSERT` on `species_dictionary`. Auto-links same-genus species at zero token cost. The trigger was backfilled on all existing rows at migration time.

**Rich hydration**: The `/enrich-scan` `db.ts` resolves entries via a single embedded PostgREST join — `species_lookalikes` joined to `species_dictionary` via `!lookalike_id` FK hint, fetching `scientific_name`, `common_names`, `reference_image_url`, `iucn_red_list_status`, and `kingdom` in one round-trip. The `!lookalike_id` hint is required because `species_lookalikes` has two FKs referencing `species_dictionary` (`species_id` and `lookalike_id`); without the explicit hint PostgREST cannot determine which FK to follow.

**Kingdom validation guard**: `resolveLookalikesToJoinTable` rejects any resolved lookalike whose `kingdom` differs from the primary species' kingdom before writing to this table. Prevents cross-kingdom hallucinations (e.g. plants stored as insect lookalikes) from persisting in cache. Rows with a `NULL` kingdom pass through unchecked. If bad cross-kingdom data was previously cached, clear it with `DELETE FROM species_lookalikes WHERE species_id = (SELECT id FROM species_dictionary WHERE scientific_name = '...')` and reset `lookalikes_flash_attempted = FALSE` on the primary species row.

### `scans`

The transaction log for every successful identification.

- `id` (UUID)
- `user_id` (UUID - Foreign Key)
- `species_id` (UUID - Foreign Key nullable)
- `ai_confidence_score` (Float): 0.0 to 1.0. Bounded explicitly within the Gemini schema description ruleset.
- `blur_score` (Float): 0.0 to 1.0. Mathematically derived natively in the Edge orchestrator from Gemini's `image_quality.sharpness` score to reduce generation latency.
- `gps_lat_exact` / `gps_long_exact` (Float)
- `gps_elevation` (Float): Altitude at capture.
- `is_live_capture` (Boolean): AI flags whether this was a real photo vs a screen/book capture.
- `ecology_type` (ENUM): `'wild'` | `'urban'` | `'domesticated'` | `'unknown'`
- `colors` (Text Array): 1–3 dominant biological colors extracted by Gemini for semantic searchability.
- `weather_condition`, `semantic_location`, `device_locale`, `time_of_day`, `depth_scale_text` (Text)
- `estimated_size_cm` (Float): Physical size dimension computed client-side using LiDAR distance and Vision bounding boxes.
- `life_stage` (ENUM): Phenology tracking extracted by Gemini mapped to Darwin Core vocabulary (`egg`, `larva`, `pupa`, `nymph`, `juvenile`, `subadult`, `adult`, `seedling`, `sapling`, `unknown`).
- `reproductive_condition` (ENUM): Multi-kingdom condition tracking extracted by Gemini mapped to Darwin Core vocabulary (`flowering`, `fruiting`, `budding`, `vegetative`, `sporing`, `pregnant`, `gravid`, `mating`, `spawning`, `nesting`, `dormant`, `not_applicable`).
- `individual_count` (Int): Primary subject population density within the frame.
- `ecological_interactions` (Text Array): Biotic interactions between subjects (e.g., predation, pollination, parasitism) derived by the AI.
- `extracted_visual_traits` (Text[]): Array of 3 specific physical/structural bullet points extracted by the Gemini vision model (Micro-CoT) *before* evaluating identity or scientific name (forced by schema key-ordering) to prevent false-positive pareidolia.
- `ai_reasoning` (Text): Per-scan visual justification text generated by the Gemini vision model for the specific photo submitted. Unique per scan — never shared across scans of the same species. Ordered aggressively at the top of the schema to guarantee it evaluates before classification. Returned as `insight_data.ai_reasoning` in the `/identify` response.
- `weather_temperature_f` (Float)
- `llm_prompt_tokens`, `llm_candidate_tokens`, `llm_total_tokens` (Int): Token counts from `usageMetadata` per scan.
- `current_month` (Int)
- `image_storage_urls` (Text Array): Public Cloudflare links generated after moderation.
- `is_flagged` (Boolean): Managed via `00005_flagged_reviews.sql` for human-reported moderation flags.
- `is_tombstoned` (Boolean): Managed via `00006_apply_user_tombstone.sql` for GDPR-compliant account deletions. Anonymizes historical AI data while preserving offline cache continuity.
- `custom_tags` (Text Array): User-defined plain-text labels for personal categorization. Synchronized via direct PostgREST RPC, favoring the cloud state as the source-of-truth. Added in `20260328221000_add_custom_tags_to_scans.sql`.
- `candidates` (JSONB, nullable): Per-scan array of 2 alternative species generated by Gemini. Gemini always generates candidates (the field is required in `merianResponseSchema`); the edge function strips this to `NULL` server-side before insert when `confidence_score >= diagnosticTrigger` (`0.96` Flash / `0.85` Pro — see `identify/thresholds.ts`). `NULL` for high-confidence scans and all scans captured before migration `20260330000000_add_candidates_to_scans.sql`. Shape: `[{"scientific_name": "...", "confidence_score": 0.71}, ...]`. A partial index (`idx_scans_candidates_not_null WHERE candidates IS NOT NULL`) keeps index overhead minimal since the majority of scans are high-confidence (NULL).
- `user_identification_override` (TEXT, nullable): The scientific name the user selected when they disputed the AI's primary identification in `CandidatesCard`. `NULL` for scans where the user confirmed the AI's identification or has not yet reviewed. Added in migration `20260330120000_add_user_identification_override.sql`. Synced to the cloud via a direct PostgREST PATCH in `InferenceEngine.syncIdentificationReviewToCloud`, guarded by a `.eq("user_id", userId)` IDOR bound.
- `user_confirmed_identification` (BOOLEAN, default `FALSE`): Set to `TRUE` when the user explicitly confirmed the AI's primary identification as correct via the `CandidatesCard` "Yes, correct" button. Distinct from override — this records ground-truth positive feedback (the AI was right) rather than a correction. Added in migration `20260330130000_add_user_confirmed_identification.sql`. Synced to the cloud in the same `ReviewSyncPayload` PATCH as `user_identification_override`.
- `image_quality_score` (SMALLINT, nullable): Gemini's overall image quality rating for the captured photo, on a 0–100 scale. Derived from three sub-dimensions evaluated in-memory by the model (`sharpness` 1–10, `framing` 1–10, `diagnostic_utility` 1–10); only the aggregate `overall_score` is persisted here. A `CHECK (image_quality_score BETWEEN 0 AND 100)` constraint is enforced at the database level. Added in migration `20260330150000_add_image_quality_score_to_scans.sql`. `NULL` for all scans captured before this migration — no backfill is performed. Feature is "collect now, use later": scores are gathered for future community reference-photo curation use cases.

### `flagged_reviews`

Captures user feedback reporting improper or harmful inferences.

- `id` (UUID): Primary key.
- `scan_id` (UUID - Foreign Key): References `scans`.
- `user_id` (UUID - Foreign Key): References the `auth.users` GoTrue identifier of the reporting user.
- `flag_reason` (Text): e.g. "Incorrect Species" or "Inappropriate Content".
- `user_suggestion` (Text): Optional custom text feedback.
- `status` (Text): Defaults to `PENDING_REVIEW`.

### `export_jobs`

Stateful queueing table for asynchronous Darwin Core Archive (DwC-A) exports.

- `id` (UUID): Primary key.
- `user_id` (UUID - Foreign Key): References `auth.users`. Rate-limited to 1 request per 24 hours per user inside the Edge Function.
- `status` (ENUM): `'pending'` | `'processing'` | `'completed'` | `'failed'`.
- `export_scope` (Text): Default `'personal'`. Accepted values: `'personal'` | `'global'`. Validated at the Edge layer — values outside this set are rejected with `HTTP 400`. Defines whether to export only the requesting user's captures (`'personal'`) or all globally open data (`'global'`).
- `include_precise_coordinates` (Boolean): Access control flag.
- `file_url` (Text): The Cloudflare R2 signed URL holding the completed zip. Exists when `status == 'completed'`.
- `error_message` (Text): Present if `status == 'failed'`.
- `created_at`, `completed_at` (TIMESTAMPTZ): Lifecycle tracking metrics.

*Note: A `pg_net` Postgres Trigger listens to `INSERT` on this table to invoke the background `export-dwca` Server-to-Server edge function webhook.*

### `user_blocks`

Registers blocked users so they are excluded from Discovery feeds.

- `blocker_id` (UUID - Foreign Key): The user executing the block.
- `blocked_id` (UUID - Foreign Key): The UUID of the blocked user.

### `00007_auto_purge_nonbio_cron.sql` (Lifecycle Sync)

Configures the automated garbage collection pipeline using `pg_cron` and `pg_net`. Schedules an HTTP POST to the `/functions/v1/auto-purge-nonbio` Deno node at 03:00 UTC, authenticating via `SUPABASE_SERVICE_ROLE_KEY` from `vault.decrypted_secrets`. Bridges logical `is_biological_subject = false` database purges with Cloudflare R2 object deletion to prevent storage bloat.

## SwiftData Schema (Local Offline Queue)

_Note: The iOS persistence layer is enforced via `ModelContainer` in `MerianApp.swift`. If a schema mismatch occurs during a production app update, the application executes a `fatalError` crash rather than silently wiping `URL.documentsDirectory` and the `ModelContainer` state. To prevent crashes as the schema evolves, Merian uses `MerianMigrationPlan` with lightweight and custom `.migrationStage` closures that safely transpose old structures (e.g. `MerianSchemaV8` to `MerianSchemaV9`) without corrupting local scan data._

**File layout:** The universally active models natively live in the global namespace within `merian/Models/ActiveSchema/`. Historical schema snapshots live in their own file (`merian/Models/Schema/SchemaV1.swift` through `SchemaV27.swift`). The file `merian/Models/SchemaVersions.swift` declares `MerianMigrationPlan` — the ordered list of schemas and migration stages. When bumping to V{N+1}, follow the runbook at `.agents/workflows/schema_update.md` (or run it via `/schema_update` command):

1. **Run `python3 .agents/workflows/freeze_schema.py {N} --apply`** — generates a frozen `LocalScanRecord` snapshot for `SchemaV{N}.swift` from the current `ActiveSchema/` before any changes. Move the generated class into the enum body (not the extension block the script outputs).
2. Update `SchemaV{N}.swift` `models` array to use fully-qualified `MerianSchemaV{N}.LocalScanRecord.self` references — this locks the checksum and prevents the iOS 26 "equal model references" crash for custom migration stages.
3. Create `SchemaV{N+1}.swift` tying its `models` array to the active global classes.
4. Update `typealias CurrentSchema = MerianSchemaV{N+1}` in `Aliases.swift`.
5. Add the `migrateV{N}toV{N+1}` stage to `MerianMigrationPlan.stages`.

There is **no need** to update model references in `MerianApp.swift`, nor anywhere else in the application, because the entire app dynamically inherits `CurrentSchema` and the active global models natively.

The current active schema is `MerianSchemaV33`.

**Edge DTO Layer** (`merian/Core/AI/InferenceEdgeDTOs.swift`): Declares `EdgeResponseWrapper`, `EdgeResponse` (the `/identify` response), and `EnrichScanResponse` (the `/enrich-scan` response). `EnrichScanResponse` contains nested `EnrichData` (maps `habitat_description`, `gbif_taxon_key`, `taxonomy`, and `similar_species: [SimilarSpeciesEntry]?`) and `SimilarSpeciesEntry` (maps `scientific_name`, `common_name`, `reference_image_url`, `iucn_red_list_status`) structs. `EdgeResponse` also contains a nested `IdentificationCandidate` struct (`scientific_name: String`, `confidence_score: Double`) and a `candidates: [IdentificationCandidate]?` field mapping the `/identify` response candidates array. `EdgeResponse` additionally contains a nested `ImageQuality` struct (`sharpness: Int?`, `framing: Int?`, `diagnostic_utility: Int?`, `overall_score: Int?`) and an `image_quality: ImageQuality?` field. When adding new fields to either Edge Function response, update both the TypeScript schema and the corresponding Swift `Codable` struct simultaneously.

**`SpeciesData` override fields** (`merian/Models/SpeciesData.swift`): `SpeciesData` carries four identification-review fields that are never part of the Edge response but are synthesised from `LocalScanRecord` when opening a historical scan:
- `aiScientificName: String` — always set to `LocalScanRecord.scientificName` (the AI's original identification). Preserved immutably (`let`) so the UI can display "AI originally suggested X" after an override. Derived in `InferenceEngine.load(from:)` as `record.scientificName`.
- `userIdentificationOverride: String?` — mirrors `LocalScanRecord.userIdentificationOverride`. When non-nil, `InferenceEngine.load(from:)` sets `speciesData.scientificName` to the override name directly (not via an async patch), so the correct title is immediately visible on sheet open. All accompanying species-dict fields (`commonName`, `hazardType`, `taxonomy`, etc.) are persisted to `LocalScanRecord` by `fetchAndPatchOverrideData` → `BackgroundDatabaseActor.updateScanWithOverrideSpeciesData` when the override is first applied, so they survive reopen without a network call. Drives the "Your ID" state in `ConfidenceBadge`.
- `userConfirmedIdentification: Bool` — mirrors `LocalScanRecord.userConfirmedIdentification`. Cloud-synced. Drives the "Confirmed" state in `ConfidenceBadge`.
- `isFlagged: Bool` — mirrors `LocalScanRecord.isFlagged`. When `true`, overrides the `ConfidenceBadge` state natively to display an "Under Review" status and smoothly unmounts `CandidatesCard` from the view hierarchy via `EmptyView()`. Tapping the badge allows the user to undo the flag via `unflagAIIdentification`, which persists locally.

**`SpeciesData` mutable display fields**: Three `SpeciesData` properties are declared `var` (not `let`) specifically because the identification override hydration path (`fetchAndPatchOverrideData`) patches them in-place after querying `species_dictionary` for the override species:
- `var scientificName: String` — patched by `applyIdentificationOverride` and `resetIdentificationReview` to the chosen/reverted name. On `load(from:)`, set to `userIdentificationOverride ?? record.scientificName` so the correct name is visible immediately.
- `var commonName: String` — patched by `fetchAndPatchOverrideData` to the override species' canonical common name from `species_dictionary.common_names`. Also persisted to `LocalScanRecord.commonName` by `updateScanWithOverrideSpeciesData` so the name survives reopen.
- `var iucnRedListStatus: String?` — patched by `fetchAndPatchOverrideData` to the override species' conservation status. Also persisted to `LocalScanRecord.iucnRedListStatus` by `updateScanWithOverrideSpeciesData`.

`aiScientificName` remains `let` — it is set once at init and never mutated, making it a safe anchor for revert operations regardless of how many times the user cycles through overrides.

**Historical Sync DTO** (`merian/Core/Data/Database/ScanRepository.swift`): `HistoricalScanResponse` (the cloud sync DTO) includes `candidates: [CloudIdentificationCandidate]?`, `user_identification_override: String?`, `user_confirmed_identification: Bool?`, and `image_quality_score: Int?` fields. `CloudIdentificationCandidate` is a plain `Codable` struct (`scientific_name: String`, `confidence_score: Double`) that maps the JSONB array from `public.scans`. `ingestScans` re-encodes candidates to `[IdentificationCandidate]`, writes `user_identification_override`, writes `user_confirmed_identification` (defaulting to `false`), and writes `image_quality_score`. `updateExistingScans` only writes `candidatesData` if `existing.candidatesData == nil`; only writes `userConfirmedIdentification` in the `true` direction (cloud=true, local=false) to avoid overwriting an unsynced local state; backfills `imageQualityScore` when the local value is `nil` and the cloud has a value.

### `OfflineQueuedScan`

Captures state when network connectivity is unavailable. `MerianSchemaV13` adds `zoomFactor` so the active zoom level is preserved through offline queuing and replayed to the Edge function when connectivity is restored.

- `id`: String (UUID)
- `timestamp`: Date
- `localImagePaths`: [String] (References to high-res WEBPs written inside `URL.documentsDirectory`)
- `gpsLatitude`, `gpsLongitude`, `gpsElevation`: Double?
- `weatherCondition`, `locationName`: String?
- `weatherTemperatureF`, `blurScore`: Double?
- `subjectDistanceInMeters`: Float?
- `zoomFactor`: Double? (Added in `MerianSchemaV13`. Active zoom factor at capture. `nil` at 1× — omitted when it carries no signal.)
- `scanStateRaw`: Int (Added in `MerianSchemaV33`. Raw value of `ScanQueueState`, replacing the old `isUploaded: Bool` + `isDeleted: Bool` pair. Stored as `Int` for `#Predicate` compatibility. Valid values: `0` = `.pending`, `1` = `.uploading`, `2` = `.staged`, `3` = `.inferencing`, `5` = `.failed` (raw value 4 reserved). Defaults to `0` (`.pending`). Access via the typed `queueState: ScanQueueState` computed property — never read `scanStateRaw` directly in business logic. The `migrateV32toV33` custom migration stage backfills this field from the old booleans: `isDeleted=true` → `5`, `isUploaded=true` → `2`, else → `0`.)
- `stagedR2Keys`: [String]? (Added in `MerianSchemaV33`. Cloudflare R2 object keys written atomically by `BackgroundDatabaseActor.markScanAsStaged` when the last image upload receives HTTP 200. Eliminating auth-dependent key reconstruction at inference time — keys are recorded at upload-completion time under the auth session that performed the upload, preventing the 403 IDOR edge case that occurred when keys were reconstructed hours later from an expired session. `nil` for scans migrated from V32; `replayInferenceForUploadedScans` falls back to reconstructing keys from the current session for those records.)

### `LocalScanRecord` (Scans)

Tracks locally synchronized species scans for the Scans library.

- `id`: String (UUID bound 1-to-1 to the Postgres/Cloudflare `/scans` row ID, resolving the Duplicate Tile race condition).
- `speciesId`: String (UUID linking scan tiles for the same `scientificName`).
- `timestamp`: Date
- `scientificName`: String
- `commonName`: String
- `confidenceScore`: Double?
- `localImagePath`: String? (Path to the local capture binary, or the primary historical Cloudflare remote URL for archived scans).
- `additionalImagePaths`: [String]? (Subsequent Cloudflare URL payloads, kept separate from `localImagePath` to avoid Image Carousel duplication).
- ~~`insightDescription`~~: Removed in `MerianSchemaV17`. Per-scan AI reasoning is now stored exclusively in `aiReasoning` (see below). The V17 custom migration stage backfills `aiReasoning` from `insightDescription` for any pre-V15 records that had a description but no `aiReasoning` value.
- `hazardType`: String — hazard classification for the species. One of: `"none"` | `"poisonous"` | `"venomous"` | `"allergenic"` | `"irritant"`. Added in `MerianSchemaV16`. Migration `migrateV15toV16` maps old `isPoisonous = true` records to `hazardType = "poisonous"`.
- `isBiological`: Bool (from Edge)
- `isLiveCapture`: Bool (from Edge)
- `isInvasive`: Bool (from Edge)
- `ecologyType`: String (from Edge)
- `semanticTags`: [String] (AI-generated contextual tags powering local offline semantic search).
- `wikipediaUrl`: String? (Hydrated asynchronously by `BackgroundDatabaseActor` via REST)
- `wikipediaOverview`: String? (Wikipedia summary paragraph cached from the REST API. Renamed from `wikipediaExtract` in `MerianSchemaV17` using `@Attribute(originalName:)` — existing data is preserved automatically via lightweight migration. Written by `BackgroundDatabaseActor.updateScanWithWikipedia`.)
- `referenceImageUrl`: String? (Stores Wikipedia/GBIF biological reference images only. Kept separate from scan images to prevent duplication in the UI Image Carousel).
- `isLocallyArchived`: Bool (Managed by the Archive Safety Protocol to track R2 payloads downloaded before the 90-day free tier domesticated expiration).
- `taxonomyKingdom`, `taxonomyPhylum`, `taxonomyClass`, `taxonomyOrder`, `taxonomyFamily`, `taxonomyGenus`: String? (Linnaean taxonomy fields added in `MerianSchemaV3`, enabling background semantic discovery without relying on `ecology_type`.)
- `locationName`, `weatherCondition`, `weatherTemperatureF`: String/Double? (Added in `MerianSchemaV5`. Stores environmental context via MapKit reverse geocoding, powering the `InsightSheetView`.)
- `collections`: [ScanCollection]? (Added in `MerianSchemaV6`. Establishes relationships to top-level custom user galleries without duplicating raw data.)
- `similarSpecies`: [String]? — Similar or commonly confused species for the identified subject. Renamed from `diagnosticLookalikes` in `MerianSchemaV26` (backfilled via `migrateV25toV26`). Retained as a backwards-compatible fallback — the richer persistence path is `lookalikesData` (see below). When `lookalikesData` is nil (historical record), `InferenceEngine.load(from:)` wraps each entry in a `SimilarSpeciesEntry` with nil enrichment fields.
- `candidatesData`: Data? (Added in `MerianSchemaV28`. JSON-encoded `[IdentificationCandidate]` blob — each entry is `{ scientificName, confidenceScore }`. Written by `BackgroundDatabaseActor.saveLiveScanRecord` from the live `/identify` response, and by `ScanRepository.ingestScans` / `updateExistingScans` on historical cloud sync. `InferenceEngine.load(from:)` decodes this field back to `[IdentificationCandidate]` via `JSONDecoder` and sets it as `speciesData.candidates`. `nil` for high-confidence scans where the server stripped candidates, and for all scans captured before V28. A lightweight migration (`migrateV27toV28`) handles the version bump — no data transform required since the field is optional with a nil default.)
- `userIdentificationOverride`: String? (Added in `MerianSchemaV29`. The scientific name the user selected when overriding the AI's primary identification via `CandidatesCard`. `nil` when the user confirmed the AI or hasn't reviewed. Synced to `public.scans.user_identification_override` via `InferenceEngine.syncIdentificationReviewToCloud`. A lightweight migration (`migrateV28toV29`) handles the version bump.)
- `userConfirmedIdentification`: Bool (Added in `MerianSchemaV29`, defaults to `false`. Set to `true` when the user taps "Yes, correct" in `CandidatesCard`. Cloud-synced via `InferenceEngine.syncIdentificationReviewToCloud` (same PATCH payload as `userIdentificationOverride`). Backfilled from `public.scans.user_confirmed_identification` by `ScanRepository.ingestScans` and `updateExistingScans`. `updateExistingScans` propagates this field in the `true` direction only — a cloud `false` (written by `resetIdentificationReview` on another device) does not overwrite a local `true`. Full bidirectional review-state sync across devices is deferred. Used to trigger the `ConfidenceBadge` "Confirmed" state and to render `ConfirmedView` in `CandidatesCard`.)
- `isFlagged`: Bool (Added in `MerianSchemaV31`, defaults to `false`. Indicates the user rejected the AI payload and opted to flag the local scan for upstream moderation review. Drives the `ConfidenceBadge` 'Under Review' state in UI, which mounts `UnderReviewView` inside the explanation sheet. A lightweight migration (`migrateV30toV31`) handles the schema bump without data transformation.)
- `imageQualityScore`: Int? (Added in `MerianSchemaV30`. Gemini's 0–100 overall image quality rating for the captured photo, persisted from `image_quality.overall_score` in the `/identify` response. Immutable after init (`let` in `SpeciesData`) — the score is a property of the image, not something that changes. `nil` for scans captured before V30. A lightweight migration (`migrateV29toV30`) handles the version bump — no data transform required since the field is optional with a nil default. Backfilled from `public.scans.image_quality_score` by `ScanRepository.updateExistingScans` when the local value is nil and the cloud has a value. Gathered for future community reference-photo curation use cases.)
- `lookalikesData`: Data? (Added in `MerianSchemaV27`. JSON-encoded `[SimilarSpeciesEntry]` blob persisting the full rich lookalike payload — `scientificName`, `commonName`, `referenceImageUrl`, `iucnRedListStatus` — through the SwiftData layer. Written by `InferenceEngine.fetchAndApplyEnrichment` after decoding the `/enrich-scan` response. `InferenceEngine.load(from:)` decodes this field first; if nil, it falls back to the flat `similarSpecies: [String]?` array. A lightweight migration (`migrateV26toV27`) handles the version bump — no data transform is required since the field is optional with a nil default on existing records.)
- ~~`diagnosticPrimaryRationale`~~: Removed in `MerianSchemaV26`. Previously stored the primary identification rationale for low-confidence scans (added in `MerianSchemaV9`).
- ~~`diagnosticDifferentiatorsJson`~~: Removed in `MerianSchemaV26`. Previously stored a JSON-encoded `[String]` array of key field marks distinguishing the species from its lookalike (added in `MerianSchemaV9`).
- `iucnRedListStatus`: String? (Added in `MerianSchemaV10`. Tracks international species risk status, powering the offline `ConservationBanner`.)
- `gpsElevation`: Double? (Added in `MerianSchemaV11`. Syncs capture altitude for the offline `InsightLocationWeatherCard`.)
- `gpsLatitude`, `gpsLongitude`: Double? (Added in `MerianSchemaV12`. Stores raw GPS coordinates for the `ScanInformationCard` MapKit integration.)
- `zoomFactor`: Double? (Added in `MerianSchemaV13`. Records the active optical zoom at the moment of capture. `nil` for 1× scans and any scan captured before V13. Displayed in `ScanInformationCard` and forwarded to the Edge function as a Gemini telemetry cue.)
- `aiReasoning`: String? (Added in `MerianSchemaV15`. The sole storage for per-scan AI vision reasoning as of `MerianSchemaV17` — replaces `insightDescription`. Populated from the `insight_data.ai_reasoning` field in the `/identify` response, and on cloud sync from `scans.ai_reasoning`. Unique to each photo submitted — never shared across scans of the same species.)
- `extractedVisualTraits`: [String]? (Not mapped to the SwiftData schema; this data point is currently edge-and-cloud-only for diagnostic and hallucination telemetry.)
- `habitatDescription`: String? (Added in `MerianSchemaV15`. Populated asynchronously by `BackgroundDatabaseActor.updateScanWithEnrichment` after `enrich-scan` returns. Loads 2–3 seconds after each biological scan completes via `InferenceEngine.fetchAndApplyEnrichment`. Displayed in `HabitatAndDistributionCard` inside `BiologicalView`.)
- ~~`globalDistributionRegionsJson`~~: Removed in `MerianSchemaV19`. Was added in `MerianSchemaV15` to cache AI-generated region codes, but proved inaccurate. Distribution data is now communicated exclusively through the GBIF tile overlay driven by `gbifTaxonKey`.
- `gbifTaxonKey`: Int? (Added in `MerianSchemaV18`. The GBIF species usage key sourced from `species_dictionary.gbif_taxon_key`, which is populated by `fetchExternalEnrichment` during the `identify` background task via a REST call to `api.gbif.org/v1/species/match`. Not AI-generated — it is GBIF's own deterministic taxonomy ID. Forwarded to the client at the top-level of the `/identify` response for **all tiers** on Cache Hit, and via `/enrich-scan` for all users on the enrichment path. Used by `GBIFHeatmapMapView` in `HabitatAndDistributionCard` to fetch occurrence density tile overlays from `api.gbif.org/v2/map/occurrence/density`, visible to free and Pro users alike. `nil` for scans of Cache Miss species where the GBIF background lookup has not yet completed, or for scans captured before V18.)
- `estimatedSizeCm`: Double? (Added in `MerianSchemaV20`. Physical dimension metric computed via LiDAR / AI context. Parsed and persistently cached locally.)
- `lifeStage`: String? (Added in `MerianSchemaV20`. Phenological tracking, e.g. "adult" or "larva", extracted by Gemini API.)
- `reproductiveCondition`: String? (Added in `MerianSchemaV20`. Phenological state, e.g. "flowering" or "fruiting", extracted by Gemini API.)
- `individualCount`: Int? (Added in `MerianSchemaV20`. Core population scale within the frame.)
- `ecologicalInteractions`: [String]? (Added in `MerianSchemaV20`. Array of behavioral interactions observed, such as predation or parasitism.)
- `customTags`: [String] (Added in `MerianSchemaV22`. User-defined textual tags enabling personal categorization and precise local library search queries.)
- `captureDate`: Date? — Secondary date field distinct from `timestamp`. Stores the EXIF capture date from the original photo asset when available.
- `inferenceTier`: String? — Records the Gemini model tier (`"flash"` or `"pro"`) used for this scan. Forwarded from the `/identify` response. Used by `InferenceEngine` to apply the correct confidence threshold for diagnostics display.
- `hasBeenViewed`: Bool — Defaults to `true` on historical cloud-synced records. Set to `false` on newly inferred scans so the Scans library can display a "New" badge until the user opens the insight sheet.

### `ScanCollection` (User Albums)

A top-level album type associated with `LocalScanRecord` nodes, added in `MerianSchemaV9`.

- `id`: String (UUID)
- `name`: String
- `createdAt`: Date
- `scans`: [LocalScanRecord]? (Inverse `@Relationship` using IDs rather than encoded objects, reducing memory pressure.)
- `isDeleted`: Bool (Added in `MerianSchemaV14`. Soft-delete flag explicitly passed to the Edge function for safe cloud erasure instead of destructive state-diffs.)

### `PendingCloudDeletionTask`

Queues offline cloud deletions, added in `MerianSchemaV7`.

- `scanId`: String (UUID of the remote record to delete)
- `timestamp`: Date
