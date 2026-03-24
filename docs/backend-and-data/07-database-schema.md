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


### `species_dictionary`

The global source-of-truth for biological models.

- `id` (UUID): Primary key.
- `scientific_name` (Text): Unique. (e.g., _Danaus plexippus_)
- `common_names` (JSONB): e.g., `{"default": "Monarch Butterfly"}`
- `kingdom`, `phylum`, `class`, `order`, `family`, `genus` (Text): Standard Linnaean taxonomy.
- `descriptions`, `is_poisonous` (Boolean): Stores liability-relevant biological properties.
- `wikipedia_url`, `wikipedia_extract`, `gbif_taxon_key`, `reference_image_url`: Extended biological context.
- `native_region` (Text): Origin markers.

### `scans`

The transaction log for every successful identification.

- `id` (UUID)
- `user_id` (UUID - Foreign Key)
- `species_id` (UUID - Foreign Key nullable)
- `ai_confidence_score` (Float): 0.0 to 1.0.
- `blur_score` (Float): 0.0 to 1.0. Evaluates the optical sharpness of the captured image from Gemini 2.5 context.
- `gps_lat_exact` / `gps_long_exact` (Float)
- `gps_elevation` (Float): Altitude at capture.
- `is_live_capture` (Boolean): AI flags whether this was a real photo vs a screen/book capture.
- `ecology_type` (ENUM): `'wild'` | `'urban'` | `'domesticated'` | `'unknown'`
- `colors` (Text Array): 1–3 dominant biological colors extracted by Gemini for semantic searchability.
- `weather_condition`, `regional_status_rationale`, `semantic_location`, `device_locale`, `time_of_day`, `depth_scale_text` (Text)
- `weather_temperature_f` (Float)
- `llm_prompt_tokens`, `llm_candidate_tokens`, `llm_total_tokens` (Int): Token counts from `usageMetadata` per scan.
- `current_month` (Int)
- `image_storage_urls` (Text Array): Public Cloudflare links generated after moderation.
- `is_flagged` (Boolean): Managed via `00005_flagged_reviews.sql` for human-reported moderation flags.
- `is_tombstoned` (Boolean): Managed via `00006_apply_user_tombstone.sql` for GDPR-compliant account deletions. Anonymizes historical AI data while preserving offline cache continuity.

### `flagged_reviews`

Captures user feedback reporting improper or harmful inferences.

- `id` (UUID): Primary key.
- `scan_id` (UUID - Foreign Key): References `scans`.
- `user_id` (UUID - Foreign Key): References the `auth.users` GoTrue identifier of the reporting user.
- `flag_reason` (Text): e.g. "Incorrect Species" or "Inappropriate Content".
- `user_suggestion` (Text): Optional custom text feedback.
- `status` (Text): Defaults to `PENDING_REVIEW`.

### `user_blocks`

Registers blocked users so they are excluded from Discovery feeds.

- `blocker_id` (UUID - Foreign Key): The user executing the block.
- `blocked_id` (UUID - Foreign Key): The UUID of the blocked user.

### `00007_auto_purge_nonbio_cron.sql` (Lifecycle Sync)

Configures the automated garbage collection pipeline using `pg_cron` and `pg_net`. Schedules an HTTP POST to the `/functions/v1/auto-purge-nonbio` Deno node at 03:00 UTC, authenticating via `SUPABASE_SERVICE_ROLE_KEY` from `vault.decrypted_secrets`. Bridges logical `is_biological_subject = false` database purges with Cloudflare R2 object deletion to prevent storage bloat.

## SwiftData Schema (Local Offline Queue)

_Note: The iOS persistence layer is enforced via `ModelContainer` in `MerianApp.swift`. If a schema mismatch occurs during a production app update, the application executes a `fatalError` crash rather than silently wiping `URL.documentsDirectory` and the `ModelContainer` state. To prevent crashes as the schema evolves, Merian uses `MerianMigrationPlan` with lightweight and custom `.migrationStage` closures that safely transpose old structures (e.g. `MerianSchemaV8` to `MerianSchemaV9`) without corrupting local scan data._

**File layout:** Each schema version lives in its own file (`merian/Models/Schema/SchemaV1.swift` through `SchemaV12.swift`). The sole remaining purpose of `merian/Models/SchemaVersions.swift` is to declare `MerianMigrationPlan` — the ordered list of schemas and migration stages. When bumping to a new version, add a `SchemaV{N+1}.swift` file, append it to `MerianMigrationPlan.schemas`, add the lightweight stage, and update `Aliases.swift`. No other files need to change.

### `OfflineQueuedScan`

Captures state when network connectivity is unavailable. `MerianSchemaV12` expands the cached telemetry payload to include additional off-grid context.

- `id`: String (UUID)
- `timestamp`: Date
- `localImagePaths`: [String] (References to high-res JPEGs written inside `URL.documentsDirectory`)
- `gpsLatitude`, `gpsLongitude`, `gpsElevation`: Double?
- `weatherCondition`, `locationName`: String?
- `weatherTemperatureF`, `blurScore`: Double?
- `subjectDistanceInMeters`: Float?
- `isDeleted`: Bool (Soft-delete flag set after receiving HTTP 200 from Edge)

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
- `insightDescription`: String
- `isPoisonous`: Bool
- `isBiological`: Bool (from Edge)
- `isLiveCapture`: Bool (from Edge)
- `isInvasive`: Bool (from Edge)
- `ecologyType`: String (from Edge)
- `semanticTags`: [String] (AI-generated contextual tags powering local offline semantic search).
- `wikipediaUrl`: String? (Hydrated asynchronously by `BackgroundDatabaseActor` via REST)
- `wikipediaExtract`: String? (Text payload from the Wikipedia REST API, written by `updateScanWithWikipedia`).
- `referenceImageUrl`: String? (Stores Wikipedia/GBIF biological reference images only. Kept separate from scan images to prevent duplication in the UI Image Carousel).
- `isLocallyArchived`: Bool (Managed by the Archive Safety Protocol to track R2 payloads downloaded before the 90-day free tier expiration).
- `taxonomyKingdom`, `taxonomyPhylum`, `taxonomyClass`, `taxonomyOrder`, `taxonomyFamily`, `taxonomyGenus`: String? (Linnaean taxonomy fields added in `MerianSchemaV3`, enabling background semantic discovery without relying on `ecology_type`.)
- `locationName`, `weatherCondition`, `weatherTemperatureF`: String/Double? (Added in `MerianSchemaV5`. Stores environmental context via MapKit reverse geocoding, powering the `InsightSheetView`.)
- `collections`: [ScanCollection]? (Added in `MerianSchemaV6`. Establishes relationships to top-level custom user galleries without duplicating raw data.)
- `diagnosticPrimaryRationale`, `diagnosticLookalikeName`, `diagnosticDifferentiatorsJson`: String? (Added in `MerianSchemaV9`. Persists Gemini's low-confidence diagnostic comparisons locally so the UI can display them offline.)
- `iucnRedListStatus`: String? (Added in `MerianSchemaV10`. Tracks international species risk status, powering the offline `ConservationBanner`.)
- `gpsElevation`: Double? (Added in `MerianSchemaV11`. Syncs capture altitude for the offline `InsightLocationWeatherCard`.)
- `gpsLatitude`, `gpsLongitude`: Double? (Added in `MerianSchemaV12`. Stores raw GPS coordinates for the `ScanInformationCard` MapKit integration.)

### `ScanCollection` (User Albums)

A top-level album type associated with `LocalScanRecord` nodes, added in `MerianSchemaV9`.

- `id`: String (UUID)
- `name`: String
- `createdAt`: Date
- `scans`: [LocalScanRecord]? (Inverse `@Relationship` using IDs rather than encoded objects, reducing memory pressure.)

### `PendingCloudDeletionTask`

Queues offline cloud deletions, added in `MerianSchemaV7`.

- `scanId`: String (UUID of the remote record to delete)
- `timestamp`: Date
