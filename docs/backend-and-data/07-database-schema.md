# Database Schema & Data Models

This document directly maps the expected shape of our persistence layers. AI Agents should refer to this to strictly bind TypeScript interfaces and Swift `Codable` structs without guessing.

## Supabase PostgreSQL Schema (`00001_initial_schema.sql`)

### `users`

Tracks the global state of the anonymous/authenticated user.

- `id` (UUID): Maps natively to the `auth.users` GoTrue unique identifiers, automatically generated via standard Supabase Ghost Sessions overriding generic IDFV fallback flows. Seamlessly mapped into PostHog/RevenueCat telemetry logic to ensure cohesive ecosystem-wide session persistence natively.
- `subscription_tier` (ENUM): `'free'` | `'pro'`
- `default_geoprivacy` (ENUM): `'open'` | `'obscured'` | `'private'`. Dictates the explicit GPS fuzzing boundaries applied dynamically to new scans, empowering citizens to default coordinates strictly into 50km approximations (`obscured`) or completely hidden from global bounds (`private`).
- `current_streak_count` (Int): Gamification metric.
- `total_species_discovered` (Int): Calculated strictly at the database level via a Postgres `AFTER INSERT` trigger (`update_user_species_count()`). To securely avoid concurrent TOCTOU race conditions during bulk offline uploads, it explicitly recalculates the sum mathematically via a subquery (`COUNT(DISTINCT species_id)`) rather than generically auto-incrementing. DO NOT MANUALLY UPDATE THIS FROM CLIENT CODE OR EDGE FUNCTIONS. This metric is also cleanly handled via an `AFTER DELETE` trigger (`decrement_user_species_count()`) automatically deducting the unified sum securely when a user deletes their absolute last scan of an entity.


### `species_dictionary`

The global source-of-truth mapping exact biological models natively.

- `id` (UUID): Primary key.
- `scientific_name` (Text): Unique strictly. (e.g., _Danaus plexippus_)
- `common_names` (JSONB): e.g., `{"default": "Monarch Butterfly"}`
- `kingdom`, `phylum`, `class`, `order`, `family`, `genus` (Text): Standard architectural Linnaean taxonomy.
- `descriptions`, `is_poisonous` (Boolean): Stores liability protections natively.
- `wikipedia_url`, `wikipedia_extract`, `gbif_taxon_key`, `reference_image_url`: Extended biological context integrations.
- `native_region` (Text): Origin markers.

### `scans`

The transaction log for every identification ever successfully passed.

- `id` (UUID)
- `user_id` (UUID - Foreign Key)
- `species_id` (UUID - Foreign Key nullable)
- `ai_confidence_score` (Float): 0.0 to 1.0 boundary.
- `blur_score` (Float): 0.0 to 1.0 boundary evaluating the optical sharpness of the captured image directly from Gemini 2.5 context logic.
- `gps_lat_exact` / `gps_long_exact` (Float)
- `gps_elevation` (Float): Altitude exactly at capture.
- `is_live_capture` (Boolean): AI flags whether this was a real photo vs a screen/book capture.
- `ecology_type` (ENUM): `'wild'` | `'urban'` | `'domesticated'` | `'unknown'`
- `colors` (Text Array): Extracted via Gemini natively indexing 1-3 dominant biological colors for immediate semantic searchability.
- `weather_condition`, `regional_status_rationale`, `semantic_location`, `device_locale`, `time_of_day`, `depth_scale_text` (Text)
- `weather_temperature_f` (Float)
- `llm_prompt_tokens`, `llm_candidate_tokens`, `llm_total_tokens` (Int): Exact Google Cloud token margins mapped safely per-scan from `usageMetadata` native payload tracking.
- `current_month` (Int)
- `image_storage_urls` (Text Array): Stores safe public Cloudflare links generated explicitly off the Moderation engine safely resolving explicit abuses natively.
- `is_flagged` (Boolean): Managed asynchronously via `00005_flagged_reviews.sql` indicating human-reported moderation flags natively mapped.
- `is_tombstoned` (Boolean): Handled locally via `00006_apply_user_tombstone.sql` anonymizing historical AI data for GDPR-compliant account deletions gracefully mapping offline cache continuity.

### `flagged_reviews`

Captures user feedback reporting improper or harmful inferences directly.

- `id` (UUID): Primary key.
- `scan_id` (UUID - Foreign Key): Natively binds to `scans`.
- `user_id` (UUID - Foreign Key): Natively binds to the `auth.users` GoTrue unique identifiers of the reporting identity.
- `flag_reason` (Text): e.g. "Incorrect Species" or "Inappropriate Content".
- `user_suggestion` (Text): Optional custom text feedback.
- `status` (Text): Enum state natively defaulting to `PENDING_REVIEW`.

### `user_blocks`

Registers blocked actors so they vanish securely completely detached natively from Discovery feeds. 

- `blocker_id` (UUID - Foreign Key): The actor executing the block.
- `blocked_id` (UUID - Foreign Key): The UUID of the offender mapping seamlessly inside the array boundary logically safely blocking them directly mapping.

## SwiftData Schema (Local Offline Queue)

_Note: The iOS persistence layer is strictly enforced via `ModelContainer` in `MerianApp.swift`. If a schema mismatch occurs during a production app update, the application will now intentionally execute a `fatalError` crash rather than silently wiping `URL.documentsDirectory` and the `ModelContainer` state. To prevent crashes as the schema evolves, Merian employs `MerianMigrationPlan` globally mapping `SchemaVersions.swift` configurations dynamically allowing lightweight and custom `.migrationStage` closures to safely transpose old structures (e.g. `MerianSchemaV8` jumping to `MerianSchemaV9`) keeping Local Scanss perfectly intact without corrupting biological caches._

### `OfflineQueuedScan`

Locally captures state when cell towers drop. `MerianSchemaV11` cleanly expands the cached telemetry payload securely caching explicit context boundaries locally when off-grid.

- `id`: String (UUID)
- `timestamp`: Date
- `localImagePaths`: [String] (References to High-Res JPEGs written inside `URL.documentsDirectory`)
- `gpsLatitude`, `gpsLongitude`, `gpsElevation`: Double?
- `weatherCondition`, `locationName`: String?
- `weatherTemperatureF`, `blurScore`: Double?
- `subjectDistanceInMeters`: Float?
- `isDeleted`: Bool (Soft-delete boundary once 200 OK receives back from Edge)

### `LocalScanRecord` (Scans)

Tracks locally synchronized and unique species scans natively for the Scans library.

- `id`: String (UUID natively bound 1-to-1 to the Postgres/Cloudflare explicit `/scans` row ID resolving the Duplicate Tile race condition).
- `speciesId`: String (UUID linking discrete physical photo tiles of the exact identical `scientificName` natively).
- `timestamp`: Date
- `scientificName`: String
- `commonName`: String
- `confidenceScore`: Double?
- `localImagePath`: String? (Thumbnail index pointing directly to the distinct physical capture binary)
- `additionalImagePaths`: [String]? *(Deprecated: The Inference Engine no longer silently merges distinct photos under a random unified UUID, ensuring each shutter press spawns a clean mapping. Preserved for backwards compatibility with V5 nodes).*
- `insightDescription`: String
- `isPoisonous`: Bool
- `isBiological`: Bool (from Edge)
- `isLiveCapture`: Bool (from Edge)
- `isInvasive`: Bool (from Edge)
- `ecologyType`: String (from Edge)
- `semanticTags`: [String] (AI-generated hidden array of contextual tags to power local, offline semantic search routing without requiring an internet connection).
- `wikipediaUrl`: String? (Asynchronously hydrated by the `BackgroundDatabaseActor` after standalone REST execution resolving bounds offline)
- `wikipediaExtract`: String? (Explicit text payload from REST API mapped iteratively by `updateScanWithWikipedia` natively into iOS persistent storage).
- `referenceImageUrl`: String?
- `isLocallyArchived`: Bool (Managed internally by the Archive Safety Protocol to track R2 payloads downloaded before the 90-day free tier expiration limit).
- `taxonomyKingdom`, `taxonomyPhylum`, `taxonomyClass`, `taxonomyOrder`, `taxonomyFamily`, `taxonomyGenus`: String? (Explicitly stored Linnaean taxonomy fields mapped into `MerianSchemaV3` enabling rigid detached background semantic discovery loops natively bypassing arbitrary UI `ecology_type` bounds safely.)
- `locationName`, `weatherCondition`, `weatherTemperatureF`: String/Double? (Mapped in `MerianSchemaV5` wrapping historical environmental context via Apple's native MapKit MKReverseGeocodingRequest natively powering localized UI inside the `InsightSheetView`.)
- `collections`: [ScanCollection]? (Mapped natively in `MerianSchemaV6` establishing referential boundaries into top-level custom user galleries, dynamically adding native iOS photo-album features without duplicating any raw data payloads directly.)
- `diagnosticPrimaryRationale`, `diagnosticLookalikeName`, `diagnosticDifferentiatorsJson`: String? (Mapped cleanly in `MerianSchemaV9` explicitly persisting Gemini's raw low-confidence comparisons logic locally so the physical UI rehydrates cleanly offline without losing contextual diagnostic data bounds).
- `iucnRedListStatus`: String? (Mapped in `MerianSchemaV10` explicitly tracking international species risk bounds natively, powering the offline state of the `InsightConservationCard`).
- `gpsElevation`: Double? (Mapped natively in `MerianSchemaV11` syncing the identical capture altitude context seamlessly mapping exactly bounded out of the hardware directly onto the offline cache without throwing lossy boundaries off the offline `InsightLocationWeatherCard`).
### `ScanCollection` (User Albums)

A top-level album paradigm mapped logically against `LocalScanRecord` nodes safely isolated explicitly from `MerianSchemaV9` updates.

- `id`: String (UUID)
- `name`: String
- `createdAt`: Date
- `scans`: [LocalScanRecord]? (An inverse `@Relationship` mapped to dynamically aggregate global references directly passing raw IDs rather than encoding memory, mitigating standard OOM faults directly).

### `PendingCloudDeletionTask`

Locally queues offline physical erasures mapped safely inside `MerianSchemaV7`.

- `scanId`: String (UUID mapping directly directly tracking the remote identifier locally)
- `timestamp`: Date
