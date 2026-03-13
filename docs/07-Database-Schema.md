# Database Schema & Data Models

This document directly maps the expected shape of our persistence layers. AI Agents should refer to this to strictly bind TypeScript interfaces and Swift `Codable` structs without guessing.

## Supabase PostgreSQL Schema (`00001_initial_schema.sql`)

### `users`

Tracks the global state of the anonymous/authenticated user.

- `id` (UUID): Maps natively to the `auth.users` GoTrue unique identifiers, automatically generated via standard Supabase Ghost Sessions overriding generic IDFV fallback flows. Seamlessly mapped into PostHog/RevenueCat telemetry logic to ensure cohesive ecosystem-wide session persistence natively.
- `subscription_tier` (ENUM): `'free'` | `'pro'`
- `scans_remaining_today` (Int): Decoupled fallback. Managed physically via iOS `UsageManager` natively.
- `current_streak_count` (Int): Gamification metric.
- `total_species_discovered` (Int): Auto-incremented strictly at the database level via a Postgres `AFTER INSERT` trigger (`update_user_species_count()`) evaluating unique `species_id` transactions on the `scans` table. DO NOT MANUALLY UPDATE THIS FROM CLIENT CODE OR EDGE FUNCTIONS.

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
- `weather_condition`, `regional_status_rationale` (Text)
- `weather_temperature_f` (Float): Local degrees fahrenheit.
- `image_storage_urls` (Text Array): Stores safe public Cloudflare links generated explicitly off the Moderation engine safely resolving explicit abuses natively.

## SwiftData Schema (Local Offline Queue)

_Note: The iOS persistence layer is strictly enforced via `ModelContainer` in `MerianApp.swift`. If a schema mismatch occurs during a production app update, the application will now intentionally execute a `fatalError` crash rather than silently wiping `URL.documentsDirectory` and the `ModelContainer` state. To prevent crashes as the schema evolves, Merian employs `MerianMigrationPlan` globally mapping `SchemaVersions.swift` configurations dynamically allowing lightweight and custom `.migrationStage` closures to safely transpose old structures (e.g. `MerianSchemaV5` jumping to `MerianSchemaV6`) keeping Local Life Lists perfectly intact without corrupting biological caches._

### `OfflineQueuedScan`

Locally captures state when cell towers drop.

- `id`: String (UUID)
- `timestamp`: Date
- `localImagePaths`: [String] (References to High-Res JPEGs written inside `URL.documentsDirectory`)
- `gpsLatitude`, `gpsLongitude`, `gpsElevation`: Double?
- `weatherCondition`: String?
- `weatherTemperatureF`: Double?
- `blurScore`: Double?
- `isDeleted`: Bool (Soft-delete boundary once 200 OK receives back from Edge)

### `LocalScanRecord` (Life List)

Tracks locally synchronized and unique species scans natively for the Life List.

- `id`: String (UUID)
- `timestamp`: Date
- `scientificName`: String
- `commonName`: String
- `confidenceScore`: Double?
- `localImagePath`: String? (Thumbnail index)
- `additionalImagePaths`: [String]? (Multiple historic encounter arrays)
- `insightDescription`: String
- `isPoisonous`: Bool
- `isBiological`: Bool (from Edge)
- `isLiveCapture`: Bool (from Edge)
- `isInvasive`: Bool (from Edge)
- `ecologyType`: String (from Edge)
- `semanticTags`: [String] (AI-generated hidden array of contextual tags to power local, offline semantic search routing without requiring an internet connection).
- `wikipediaUrl`: String?
- `wikipediaExtract`: String? (Explicit text payload from REST API mapped into `MerianSchemaV5` for native offline UI caching).
- `referenceImageUrl`: String?
- `isLocallyArchived`: Bool (Managed internally by the Archive Safety Protocol to track R2 payloads downloaded before the 90-day free tier expiration limit).
- `taxonomyKingdom`, `taxonomyPhylum`, `taxonomyClass`, `taxonomyOrder`, `taxonomyFamily`, `taxonomyGenus`: String? (Explicitly stored Linnaean taxonomy fields mapped into `MerianSchemaV3` enabling rigid detached background semantic discovery loops natively bypassing arbitrary UI `ecology_type` bounds safely.)
- `locationName`, `weatherCondition`, `weatherTemperatureF`: String/Double? (Mapped in `MerianSchemaV5` wrapping historical environmental context via Apple's native CoreLocation CLGeocoder natively powering localized UI inside the `InsightSheetView`.)
- `collections`: [ScanCollection]? (Mapped natively in `MerianSchemaV6` establishing referential boundaries into top-level custom user galleries, dynamically adding native iOS photo-album features without duplicating any raw data payloads directly.)

### `ScanCollection` (User Albums)

A top-level album paradigm mapped logically against `LocalScanRecord` nodes safely within `MerianSchemaV6`.

- `id`: String (UUID)
- `name`: String
- `createdAt`: Date
- `scans`: [LocalScanRecord]? (An inverse `@Relationship` mapped to dynamically aggregate global references directly passing raw IDs rather than encoding memory, mitigating standard OOM faults directly).
