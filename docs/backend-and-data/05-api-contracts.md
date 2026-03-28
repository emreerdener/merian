# API Contracts and Network Mappings

Merian operates decoupled. The iOS application exclusively hits Supabase Edge Functions, abstracting its networking away from 3rd-party providers like Google Gemini.

## Deno `/generate-upload-urls` Edge Node

To fetch cryptographic keys for direct-to-Cloudflare uploads, the client sends a filename array:

### Request Payload

```json
{
  "user_id": "Supabase Auth UUID linking RevenueCat and PostHog",
  "fileNames": ["photo_1.webp", "photo_2.webp"]
}
```

The server extracts the verified user identity from the `Authorization` Header JWT (`supabaseAdmin.auth.getUser()`), ignoring any `user_id` value in the request body. Pre-signed `PUT` URLs include an `X-Amz-Expires=86400` parameter (24 hours). This extended window gives iOS `BackgroundTasks` flexibility to transmit overnight, subject to OS memory, thermal, and Wi-Fi conditions, without hitting 403 errors.

The Edge function uses the `fileName` parameter from the JSON body (after applying basic sanitization to prevent path traversal vectors) rather than generating random internal UUIDs. This guarantees that the pre-signed S3 `objectKey` will deterministically match the paths requested by the iOS client during subsequent offline inference triggers.

```json
{
  "urls": [
    {
      "fileName": "photo_1.webp",
      "signedUrl": "https://<R2_URL>?X-Amz-Signature=...",
      "objectKey": "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_photo_1.webp"
    }
  ]
}
```

> The pre-signed URL is generated with `Content-Type: image/webp`. The iOS `URLRequest` must send a matching `Content-Type: image/webp` header on the `PUT`, or Cloudflare R2 will reject the upload with `403 SignatureDoesNotMatch`.

---

## Deno `/identify` Edge Node

### The JSON Request Payload (From Swift `OfflineQueueManager`)

When `NWPathMonitor` goes green, iOS POSTs this payload to Supabase. The server enforces that all paths within `r2ObjectKeys` begin with `staging/${user.id}/` and rejects `../` traversal attempts with `HTTP 400`. 

> **Important IDOR Constraint:** The `user.id` resolved by the Deno Edge Function from the Supabase JWT is always a **lowercase** Postgres UUID format. Swift's `UUID().uuidString` evaluates to uppercase by default. Therefore, the iOS client must explicitly lowercase any user UUID injected into `r2ObjectKeys` payloads; otherwise, the case-sensitive string matching (`!r2ObjectKey.startsWith`) will fail the IDOR check and return a `403 Forbidden`.

```json
{
  "r2ObjectKeys": [
    "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_filename_1.webp",
    "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_filename_2.webp"
  ],
  "imageBase64s": ["<base64 encoded string array for instant processing (up to 2 limits, skips r2ObjectKeys)>"],
  "user_id": "Supabase Auth UUID linking via GoTrue Session",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "depthScaleText": "1.2 meters",
  "semanticLocation": "Zilker Park",
  "weatherCondition": "Sunny",
  "weatherTemperatureF": 72.5,
  "deviceLocale": "en",
  "currentMonth": 3,
  "timeOfDay": "2:00 PM",
  "timestamp": "2026-03-21T09:46:03.000Z",
  "estimated_size_cm": 15.2
}
```

### The JSON Response Schema (From Gemini Back to Swift)

To optimize API expenditures, the `identify` Deno Edge node uses two strategies:
- **Model Routing**: The vision identification call routes Pro-tier subscribers to `gemini-2.5-pro` (maximum depth for rare species, fossils, subspecies, and cultivars) and free-tier users to `gemini-2.5-flash` (2–3× lower latency). All text-only calls — `fetchStaticEncyclopedicData`, `fetchDiagnosticComparison`, and all `enrich-scan` generation — always use `gemini-2.5-flash` regardless of tier. `gemini-2.5-pro` is exclusively for the multimodal vision identification step. Tier is resolved via a single lightweight `SELECT subscription_tier` on the critical path, with a module-scope `_tierCache` (5-minute TTL) that eliminates the DB round-trip on repeat scans within a warm isolate. Both tiers use the `merianResponseSchema` constraint to protect SQLite UI logic.
- **Dynamic Token Truncation (Non-biological targets)**: When processing non-biological subjects, the Deno node removes `taxonomy`, `insight_data`, and `ecology_type` from the `required: []` array and passes `is_biological_subject: false`. The Swift layer maps the absent fields to native Optionals.

If an AI Agent mutates any key mapping below, it MUST modify both the `index.ts` Deno code AND the `MerianNetworkClient.swift` Codable struct to simultaneously support both the Pro schema and Free text-prompt shapes without causing `JSONDecoder()` failures.

> **Image format**: All images in this pipeline are encoded as lossy **WebP** (`image/webp`). The `inlineData.mimeType` field passed to the Gemini SDK in `index.ts` must always be `"image/webp"`. Gemini 2.5 Flash and Pro both accept `image/webp` natively. If this value is changed to `image/jpeg` while the actual bytes are WebP, Gemini will reject or misinterpret the payload.

**`common_name` source**: `common_name` is always taken directly from the Gemini vision model output. It is never overridden from the `species_dictionary` database. The Swift decoding layer applies `.capitalized` on rendering for display consistency.

**Critical Edge Limitation (Gemini 2.5):** The model returns `400 Bad Request` when enum fields include descriptive strings. `ecology_type` must be formatted as a structural JSON `enum: ["wild", "urban", "domesticated", "unknown"]` constraint in the Deno schema.

```json
{
  "scan_id": "Generated via crypto.randomUUID() on Deno Edge",
  "is_biological_subject": true,
  "is_live_capture": true,
  "ecology_type": "wild",
  "scientific_name": "Danaus plexippus",
  "common_name": "Monarch Butterfly",
  "confidence_score": 0.98,
  "blur_score": 0.1,
  "is_invasive": false,
  "colors": ["orange", "black", "white"],
  "estimated_size_cm": 15.2,
  "life_stage": "adult",
  "reproductive_condition": "none",
  "individual_count": 1,
  "ecological_interactions": ["pollinating Asclepias syriaca"],
  "insight_data": {
    "ai_reasoning": "The distinctive orange and black wing pattern with white-spotted margins, combined with the milkweed habitat context, is diagnostic for Danaus plexippus. The ventral hindwing silver spots confirm this is not the mimicking Viceroy.",
    "hazard_type": "none"
  },
  "// Cache Hit only — sourced from species_dictionary:": "",
  "wikipedia_url": "https://en.wikipedia.org/wiki/Monarch_butterfly",
  "wikipedia_overview": "The monarch butterfly or simply monarch is a milkweed butterfly in the family Nymphalidae...",
  "reference_image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Monarch_In_May.jpg/320px-Monarch_In_May.jpg",
  "taxonomy": {
    "kingdom": "Animalia",
    "phylum": "Arthropoda",
    "class": "Insecta",
    "order": "Lepidoptera",
    "family": "Nymphalidae",
    "genus": "Danaus"
  },
  "iucn_red_list_status": "least_concern",

  "// Cache Hit, all tiers — sourced from species_dictionary (REST, not AI-generated):": "",
  "gbif_taxon_key": 5130978,

  "// Cache Hit, all tiers — sourced from species_dictionary:": "",
  "species_insights": {
    "habitat_description": "Frequently spotted in milkweed patches, meadows, and open plains."
  }
}
```

> **Vision schema lean principle**: The vision model response (`identify`) is optimised strictly for identification and ecosystem measurement. Data-as-a-Service fields (`estimated_size_cm`, `life_stage`, `reproductive_condition`, `individual_count`, `ecological_interactions`) are fully generated on the primary pass avoiding any secondary inference loops. `insight_data.ai_reasoning` is always present for biological subjects — it is the Gemini vision model's per-scan reasoning about the specific photo submitted and is unique per scan. `taxonomy` and `iucn_red_list_status` are only present on Cache Hit (read from `species_dictionary`). `gbif_taxon_key` is present on Cache Hit for **all tiers** — it is GBIF's deterministic species usage key (sourced from a REST call to `api.gbif.org`, not AI-generated) and powers the occurrence density heatmap in `BiologicalView` for free and Pro users alike. `species_insights` is present on Cache Hit for all tiers when `habitat_description` is already stored in `species_dictionary`. `diagnostic_comparison` is never included in the `identify` response — it is generated asynchronously by the `enrich-scan` function only when confidence is below the dynamic diagnostic threshold (0.88 for Flash, 0.80 for Pro on both Edge and iOS client). `hazard_type` inside `insight_data` comes from `species_dictionary` on Cache Hit (authoritative) or from the vision model on Cache Miss (stored in `species_dictionary` for future hits). The `hazard_type` column exists only on `species_dictionary`, not on `scans`.

### Error Responses

| Status | Body | Meaning |
|---|---|---|
| `400` | `{ "error": "AI processing error. Please try again." }` | Gemini generation failure |
| `400` | `{ "error": "Bad Request: Path traversal detected." }` | `r2ObjectKeys` contains a `../` traversal attempt |
| `400` | `{ "error": "Forbidden: r2ObjectKey does not belong to the requesting user." }` | IDOR — key does not belong to the authenticated user |
| `413` | `{ "error": "Payload Too Large: Combined images exceed 5MB limit." }` | Combined image payload exceeds 5 MB |
| `422` | `{ "error": "Processing Error: Malformed AI response." }` | Gemini returned output that could not be parsed |
| `422` | `{ "error": "Processing Error: Invalid AI response format." }` | Gemini returned output in an unexpected format |

`422` is excluded from the iOS `OfflineQueueManager`'s list of recoverable error codes. The client drops the queue entry rather than retrying indefinitely.

## The Standardized JSON Return Payload (From Supabase to Swift)

To reduce latency, the `/identify` Edge Function generates `scan_id` locally via `crypto.randomUUID()` and returns the `data` payload to iOS as soon as Gemini inference completes. All PostgreSQL insertions, R2 uploads, and parallel API calls (GBIF/Wikipedia) run asynchronously behind `EdgeRuntime.waitUntil`.

### Gemini Parsing and Error Mitigation

To prevent ReDoS from hallucinated markdown payloads, the endpoint parses raw Gemini output using a `substring(indexOf)` approach rather than unbounded regex. If `JSON.parse` fails, the endpoint returns `HTTP 422 Unprocessable Entity`. Because `422` is not in the iOS `OfflineQueueManager`'s recoverable error list, the client drops the corrupted queue entry rather than retrying.

> **Note on Wikipedia Extraction:** During a "Cache Miss" (first discovery globally), the Edge Router fires the Wikipedia HTTP extraction *concurrently* alongside Gemini Text Inference latency via a `Promise.all` envelope. This guarantees high-resolution encyclopedia metadata maps directly to the user natively on the very first roundtrip without requiring the iOS app to skeleton load.

```json
{
  "success": true,
  "data": {
    "is_biological_subject": true,
    "ecology_type": "wild",
    "scientific_name": "Danaus plexippus"
  }
}
```

This data contract maps into the Swift Codable layer where nested JSON `Data` is verified to prevent `JSONDecoder()` failures on double-escaped strings.

```swift
struct IdentifyResponse: Codable {
    let success: Bool
    let data: SpeciesData?
    let error: String?
}
```

**Client Authentication Caveat**: `MerianNetworkClient` abstracts GoTrue anonymous hardware tokens. The backend extracts cryptographic JWT identity from the `Authorization: Bearer` header via `supabaseAdmin.auth.getUser()`, ignoring any `user_id` in the request body. The Swift payload uses the `SupabaseManager`'s active session UUID only as a proxy string for syncing RevenueCat identifiers — actual API validation runs over GoTrue JWT verification only.

**Offline Ghost Overwrite Protection**: Before calling `SupabaseManager.shared.getValidAuthHeaders()`, the iOS client checks `UserDefaults.standard.bool(forKey: "Merian_HasAuthenticatedOAuth")`. If an authenticated user goes offline long enough for their JWT to expire, the Swift client throws `NetworkError.invalidResponse` immediately. This prevents a guest UUID from overwriting the user's Pro status or stranding their `.sqlite` data, and causes `CameraRootView` to prompt re-authentication instead.

---

## Deno `/enrich-scan` Edge Node

An enrichment endpoint that asynchronously surfaces habitat data and (when confidence is low) diagnostic comparison data for a scan. Called automatically by the iOS client after every successful biological scan completes — the user sees a loading skeleton in `HabitatAndDistributionCard` while this request is in flight.

### Request Payload

```json
{
  "scan_id": "A1B2C3D4-...",
  "scientific_name": "Danaus plexippus"
}
```

### Architecture

**No Tier Gate**: Available to all authenticated users. Enrichment data is generated by Flash and cached in `species_dictionary` at the species level — subsequent calls for the same species are served from cache with no AI call.

**No Ownership Check on `scan_id`**: The function looks up `ai_confidence_score` from `scans` using `scan_id` alone (no `user_id` filter). If the scan is not found in Supabase (local-only record, cross-session ghost, or re-install scenario), confidence defaults to `1` and the diagnostic path is skipped. Ownership is intentionally not verified because the response contains only public species biology data (`habitat_description`, `gbif_taxon_key`, `diagnostic_comparison`) — nothing user-private. Enforcing `user_id` would permanently block enrichment for historical scans opened from the library when the current JWT user differs from the scan's stored `user_id` (e.g. after a zombie session recovery or ghost session re-creation).

**Dynamic Diagnostic Thresholds**: A scan's `ai_confidence_score` is compared against a dynamic threshold (0.88 for Flash, 0.80 for Pro) on the Edge. If below threshold, diagnostic comparison data is also fetched/generated. The diagnostic is a species-level cache — if the data already exists in `species_dictionary` from a prior low-confidence scan of the same species, it is returned immediately without a Gemini call. Note: The iOS UI handles its display logic using these exact same dynamic tier thresholds.

**Full Cache Hit**: If `species_dictionary` already has `habitat_description` and (when needed) `diagnostic_primary_rationale`, the function returns all data immediately with no Gemini calls — typically sub-50ms.

**Parallel Flash Generation**: If any data is missing, premium insights Flash and diagnostic Flash run concurrently via `Promise.all`. Both use `gemini-2.5-flash` with `temperature: 0.1`. Premium uses `maxOutputTokens: 600`, diagnostic uses `maxOutputTokens: 400`. Results are persisted to `species_dictionary` (species-level, not per-scan) before the response is returned.

**Race Condition Mitigation (Poll Before Flash)**: On a Cache Miss, `identify`'s background task and the iOS `/enrich-scan` request race to populate `species_dictionary`. To avoid a duplicate Flash token spend, `enrich-scan` polls `species_dictionary` up to 3 times with 2-second intervals before deciding to call Flash. If the background task lands before the 3rd poll, `enrich-scan` returns the cached data with no AI call. The background task typically completes within 2–4 seconds, so the first or second poll usually hits the data. This poll runs only when `habitat_description` is missing from the cache.

### Response Schema

```json
{
  "success": true,
  "data": {
    "habitat_description": "Frequently spotted in milkweed patches, meadows, and open plains.",
    "gbif_taxon_key": 5130978,
    "diagnostic_comparison": {
      "primary_match_rationale": "High structural alignment with expected wing vein layout.",
      "confusing_lookalike_name": "Viceroy Butterfly",
      "key_differentiators": [
        "Hindwing patterning: Subject has no horizontal black line vs Viceroy Pattern has distinct horizontal line across veins"
      ]
    }
  }
}
```

`gbif_taxon_key` is `null` when the species has not yet been matched by GBIF (Cache Miss species where `identify`'s background task has not yet completed). `diagnostic_comparison` is `null` when the scan's `ai_confidence_score` is above its respective tier's diagnostic threshold (e.g. 0.88 for flash, 0.80 for pro). The iOS client (`InferenceEngine.fetchAndApplyEnrichment`) applies this same dynamic threshold to write `speciesData.diagnosticComparison` and the display of the UI itself is identically gated dynamically per tier in `BiologicalView`.

### Error Responses

| Status | Body | Meaning |
|---|---|---|
| `400` | `{ "error": "Missing required parameters..." }` | `scan_id` or `scientific_name` absent |
| `400` | `{ "error": "AI processing error during enrichment..." }` | Gemini generation failure |

---

## Deno `/sync-collections` Edge Node

Synchronizes locally created Scan Collections with the PostgreSQL `collections` and `collection_scans` schemas, handling diffing and missing FK references.

### Request Payload

```json
{
  "collections": [
    {
      "id": "A1B2C3D4-...",
      "name": "My Favorites",
      "created_at": "2026-03-23T12:00:00Z",
      "scan_ids": ["B2C3D4E5-..."],
      "is_deleted": false,
      "isDeleted": false
    }
  ]
}
```

### Safety and Transactional Integrity

1. **Dual Casing Delete Parsing**: To protect against Swift `JSONEncoder` converting structural snake_case keys into camelCase payloads based on codable strategies, the Edge function supports both `is_deleted` and `isDeleted` attributes when resolving the deleted tombstone array.
2. **Batch Upserts**: All valid collections are written via a single atomic `.upsert(collectionPayloads)` call, resolving PostgreSQL `TIMESTAMPTZ` and `UUID` types without timing out.
2. **Bulk Insertion & Mismatched FK Protection**: Setting up `collection_scans` relationships natively in a single atomic upsert avoids N+1 query timeouts. To prevent PostgreSQL Foreign Key violations from crashing the overarching chunk transaction, the Edge Node dynamically pre-validates all incoming `scan_id` payloads against the core `scans` table. If a user groups a scan while fully offline and the physical cloud `scans` row hasn't populated yet, mapping intelligently bypasses that specific missing scan natively. The pending relationship rests securely offline on the user's iPhone until the next sync pulse.
3. **Array-Bound Diffing Deletes**: Identifies obsolete collections by running `.select()` across the user's DB rows, building a `toDelete` array in memory and passing it to `.delete().in("id", toDelete)`. This avoids `.not("id", "in", "(...)")` string-builder failures.

**Critical Kong API Gateway Requirement**:
To allow `sync-collections` to manually parse and extract the JWT using Deno `.headers.get("Authorization")`, the edge function must be explicitly exposed in `supabase/config.toml` with `verify_jwt = false`. If not disabled, Kong dynamically strips the `Authorization` header before it reaches Deno to prevent replay attacks, causing a `401 Unauthorized: Missing Authorization header` response from the Edge Runtime.

---

## Deno `/get-filtered-discovery-feed` Edge Node

Fetches the global social feed of public biological captures, excluding users the authenticated user has blocked. The blocked `user_id` array is passed as a raw TypeScript array (e.g. `.not("user_id", "in", isolatedExclusions)`) to avoid PostgreSQL parser exceptions.

### Authentication Enforcement

The endpoint extracts user identity from the `Authorization: Bearer` header via `supabaseAdmin.auth.getUser()`, ignoring any `userId` in the request body.

**Critical Kong API Gateway Requirement**:
Because we use `URLSession` inside `MerianNetworkClient` instead of the Supabase Swift SDK, all HTTP requests to Deno **MUST** include both the `Authorization: Bearer <JWT>` header AND the `apikey: <SUPABASE_ANON_KEY>` header. If the `apikey` header is omitted, the Supabase Kong API Gateway strips the `Authorization` header before it reaches the Edge Function, causing `401 Unauthorized: Missing token`.

Any request with a manipulated JSON body but no valid JWT signature in the header returns `401 Unauthorized`.

### Global Geoprivacy & Endangered Species Shielding

To prevent location tracking and poaching of IUCN Endangered, Vulnerable, or Near-Threatened species, the endpoint runs a post-processing `map` loop before JSON transmission. The `.gps_lat_exact` and `.gps_long_exact` fields are removed from every scan in the payload, regardless of the user's geoprivacy setting. Additionally, if the taxonomy flags a capture as a protected species, the endpoint rounds `gps_lat_public` coordinates to 11km tiles.

---

## Deno `/merge-ghost-profile` Edge Node

Transfers ownership of records from an anonymous Ghost Session to a newly authenticated Google/Apple ID.

### Request Payload

```json
{
  "ghost_id": "Transient Anonymous UUID to merge"
}
```

### Authentication Enforcement

1. Calls `supabaseAdmin.auth.getUser(jwt)` to extract the verified `targetUserId`.
2. Calls `supabaseAdmin.auth.admin.getUserById(ghost_id)` and validates `is_anonymous === true`. If a malicious actor passes a fully authenticated user's ID to hijack their scans, the endpoint returns `403 Forbidden`.
3. Transfers `scans` ownership and deletes the `ghost_id` via `.deleteUser(ghost_id)`.

---

## Deno `/safe-delete` Edge Node

Tombstones a user's account and initiates deletion of all associated data from PostgreSQL and Cloudflare R2.

### Request Payload

No JSON body is required. The endpoint operates from the JWT identity alone to prevent IDOR vulnerabilities.

### Authentication Enforcement

1. Calls `supabaseAdmin.auth.getUser()` to extract the authenticated user's UUID from the `Authorization: Bearer` header.
2. Executes the `apply_user_tombstone` PostgreSQL RPC against the authenticated `user.id`.
3. The RPC cascades through `public.scans`, `public.user_blocks`, and `public.flagged_reviews`, removing rows and triggering Cloudflare R2 object purges.
4. Returns `200 OK`. The iOS client then calls `signOut()`, drops all local SQLite `ModelContext` state via `ScanRepository.purgeAllData()`, and resets to Guest.

---

## Deno `/delete-scan` Edge Node

Deletes a single scan from both Supabase PostgreSQL and Cloudflare R2.

### Request Payload

```json
{
  "scanId": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
}
```

### Authentication Enforcement

1. Extracts `scanId` from the payload and queries `public.scans` using the Service Role.
2. If the scan does not exist (e.g. already purged server-side while offline), returns HTTP 200 so the Swift queue system drops the pending deletion.
3. Extracts the verified user identity from the JWT via `supabaseAdmin.auth.getUser()`.
4. Compares `scan.owner_id === user.id`. A mismatch returns `403 Forbidden`.
5. Deletes all Cloudflare R2 objects referenced in `image_storage_urls` via the `AwsClient`, avoiding 404 errors from namespace duplication.
6. Deletes the Postgres row.

---

## Deno `/block-user` Edge Node

Inserts a moderation block, removing the specified user from the authenticated user's Discovery Feed via `SocialGuardManager`.

### Request Payload

```json
{
  "blocked_id": "Target UUID to block"
}
```

### Authentication Enforcement

- Extracts user identity from the GoTrue header via `supabaseAdmin.auth.getUser(jwt)`.
- Writes the block into `public.user_blocks` (schema in `00001_initial_schema.sql`).
- Returns `400 Bad Request` if `blocked_id` matches the calling user's UUID.

---

## Deno `/flag-issue` Edge Node

Submits a report against an AI inference from the `ReportInsightView`, inserting a row into `00005_flagged_reviews.sql`.

### Request Payload

```json
{
  "scanId": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "flagReason": "Incorrect Species",
  "userSuggestion": "Optional taxonomy string provided by the user manually"
}
```

### Authentication Enforcement

- Extracts `user.id` from the `requireAuth(jwt)` middleware.
- Validates the JWT signature against the `scan_id`.
- Inserts a row into `public.flagged_reviews`.
- Returns `HTTP 200` on success.

---

## Deno `/request-export-dwca` Edge Node

Queues an asynchronous Darwin Core Archive (DwC-A) export. Because zipping thousands of records exceeds 30-second HTTP connection limits, this endpoint merely validates the user and inserts a job into the `export_jobs` PostgreSQL table, returning a `200 OK` instantly so the iOS client can release its thread.

### Request Payload

```json
{
  "includePreciseCoordinates": true,
  "exportScope": "user" // or "global"
}
```

### Authentication Enforcement

- Extracts user identity from the GoTrue header via `supabaseAdmin.auth.getUser(jwt)`.
- **Database Rate Limit**: Queries `export_jobs` to verify the user has not queued an export in the last 24 hours. If they have, returns `429 Too Many Requests`.
- Inserts a row into `export_jobs` with status `pending`, triggering the `pg_net` webhook.

---

## Deno `/export-dwca` Edge Node (Webhook Worker)

Generates the DwC-A ZIP, uploads it to Cloudflare R2, and emails the user the download link. This endpoint acts purely as a Server-to-Server webhook triggered by `pg_net` after an `export_jobs` insertion. It does *not* accept iOS client connections.

### Request Payload (From Postgres `pg_net` Webhook)

```json
{
  "job_id": "UUID_A",
  "user_id": "UUID_B",
  "export_scope": "user",
  "include_precise_coordinates": true
}
```

### Security & Enforcement

- Authenticates the Postgres origin by verifying that `Authorization: Bearer <token>` exactly matches `SUPABASE_SERVICE_ROLE_KEY`.
- Uses `supabaseAdmin.auth.admin.getUserById(user_id)` to resolve the user's email address for the Resend API delivery.
- **DwC-A Global Geoprivacy Leak Prevention**: Enforces ownership gating for exact coordinates during ZIP generation. Evaluates `canAccessPrecise = include_precise_coordinates && (scan.user_id === user_id)`. For global exports, users receive perturbed coordinates (50km obfuscation) for scans they do not own. Exact `gps_lat_exact` / `gps_long_exact` values are only included when the origin `user.id` matches the scan's `user_id`.
- **Async Delivery**: Instead of holding the HTTP response open while zipping gigabytes of images, it uploads the final output to Cloudflare R2 and dispatches the signed expiring download URL to the user's inbox via the **Resend API**. Updates `export_jobs.status` to `completed`.

---

## Deno `/auto-purge-nonbio` Edge Node

A daily cron-job endpoint responsible for removing stale `.is_biological_subject = false` scans to prevent arbitrary file bloat on Cloudflare R2 and PostgreSQL.

### Request Payload
No JSON body is required. The cron trigger issues an empty POST request.

### Authentication Enforcement
- Enforces strict cron authorization via `timingSafeCompare` against a `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` Authorization header. Returns `401` if invalid.
- Prevents accidental `GET` evaluations by aggressively validating `req.method === "POST"`.

### Deletion Safety
1. Queries scans isolated strictly to `is_biological_subject == false` where `timestamp < 30 days ago`.
2. Employs `.limit(500)` memory pagination barriers to prevent container timeout triggers.
3. Clears Cloudflare R2 binary references using parallel promises.
4. Executes the `.delete().in(...)` cascade against PostgreSQL only if R2 deletion doesn't crash the Node isolate.

---

## Deno `/revenuecat-webhook` Edge Node

Receives POST push events triggered natively from the RevenueCat subscription platform to update Supabase row bounds directly, bypassing the iOS SDK entirely.

### Request Payload
Receives a raw RevenueCat Webhook structure wrapper targeting an internal JSON `.event`.

### Authentication Enforcement
- Reads `REVENUECAT_WEBHOOK_SECRET` environment bindings locally.
- Authenticates the RevenueCat push via `timingSafeCompare` comparing the `Authorization: Bearer` against the secret boundary.

### Migration Mechanics
- Upgrades (`INITIAL_PURCHASE`, `RENEWAL`, `UNCANCELLATION`) convert `subscription_tier` to `pro`.
- Downgrades (`EXPIRATION`) revert the tier to `free`.
- **R2 Storage Relocation**: Migrates files between the `free` and `pro` prefix buckets in Cloudflare R2. To prevent execution timeouts on users with thousands of photos, the script iterates through SQL constraints utilizing a `size: 1000` chunk-by-chunk lookup bound in an independent `EdgeRuntime.waitUntil` detached thread.
- Defends against IDOR manipulations silently: If a user attempts to execute an R2 copy belonging to an external User UUID through manipulated array data, the proxy blocks the migration sequence logic and reports a silent violation to Edge telemetry logs.
