# Database Schema & Data Models

This document directly maps the expected shape of our persistence layers. AI Agents should refer to this to strictly bind TypeScript interfaces and Swift `Codable` structs without guessing.

## Supabase PostgreSQL Schema (`00001_initial_schema.sql`)

### `users`

Tracks the global state of the anonymous/authenticated user.

- `id` (UUID): Maps natively to `auth.users` and PostHog/RevenueCat IDs.
- `subscription_tier` (ENUM): `'free'` | `'pro'`
- `scans_remaining_today` (Int): Decoupled fallback. Managed physically via iOS `UsageManager` natively.
- `current_streak_count` (Int): Gamification metric.

### `species_dictionary`

The global source-of-truth mapping exact biological models natively.

- `id` (UUID): Primary key.
- `scientific_name` (Text): Unique strictly. (e.g., _Danaus plexippus_)
- `common_names` (JSONB): e.g., `{"default": "Monarch Butterfly"}`
- `kingdom`, `phylum`, `class`, `order`, `family`, `genus` (Text): Standard architectural Linnaean taxonomy.
- `native_region` (Text): Origin markers.

### `scans`

The transaction log for every identification ever successfully passed.

- `id` (UUID)
- `user_id` (UUID - Foreign Key)
- `species_id` (UUID - Foreign Key nullable)
- `ai_confidence_score` (Float): 0.0 to 1.0 boundary.
- `gps_lat_exact` / `gps_long_exact` (Float)
- `is_live_capture` (Boolean): AI flags whether this was a real photo vs a screen/book capture.
- `ecology_type` (ENUM): `'wild'` | `'urban'` | `'domesticated'` | `'unknown'`

## SwiftData Schema (Local Offline Queue)

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
