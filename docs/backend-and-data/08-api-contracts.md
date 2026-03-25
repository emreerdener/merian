# API Contracts and Network Mappings

Merian operates decoupled. The iOS application exclusively hits Supabase Edge Functions, abstracting its networking away from 3rd-party providers like Google Gemini.

## Deno `/generate-upload-urls` Edge Node

To fetch cryptographic keys for direct-to-Cloudflare uploads, the client sends a filename array:

### Request Payload

```json
{
  "user_id": "Supabase Auth UUID linking RevenueCat and PostHog",
  "fileNames": ["photo_1.jpg", "photo_2.jpg"]
}
```

The server extracts the verified user identity from the `Authorization` Header JWT (`supabaseAdmin.auth.getUser()`), ignoring any `user_id` value in the request body. Pre-signed `PUT` URLs include an `X-Amz-Expires=86400` parameter (24 hours). This extended window gives iOS `BackgroundTasks` flexibility to transmit overnight, subject to OS memory, thermal, and Wi-Fi conditions, without hitting 403 errors.

```json
{
  "urls": [
    {
      "fileName": "photo_1.jpg",
      "signedUrl": "https://<R2_URL>?X-Amz-Signature=...",
      "objectKey": "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_photo_1.jpg"
    }
  ]
}
```

---

## Deno `/identify` Edge Node

### The JSON Request Payload (From Swift `OfflineQueueManager`)

When `NWPathMonitor` goes green, iOS POSTs this payload to Supabase. The server enforces that all paths within `r2ObjectKeys` begin with `staging/${user.id}/` and rejects `../` traversal attempts with `HTTP 400`.

```json
{
  "r2ObjectKeys": [
    "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_filename_1.jpg",
    "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_filename_2.jpg"
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
  "timestamp": "2026-03-21T09:46:03.000Z"
}
```

### The JSON Response Schema (From Gemini Back to Swift)

To optimize API expenditures, the `identify` Deno Edge node uses two strategies:
- **Model Routing**: The system routes `isProActive` subscribers to `gemini-2.5-pro` and base-tier users to `gemini-2.5-flash`. Both tiers use the `merianResponseSchema` constraint to protect SQLite UI logic.
- **Dynamic Token Truncation (Non-biological targets)**: When processing non-biological subjects, the Deno node removes `taxonomy`, `insight_data`, `diagnostic_comparison`, and `ecology_type` from the `required: []` array and passes `is_biological_subject: false`. The Swift layer maps the absent fields to native Optionals.

If an AI Agent mutates any key mapping below, it MUST modify both the `index.ts` Deno code AND the `MerianNetworkClient.swift` Codable struct to simultaneously support both the Pro schema and Free text-prompt shapes without causing `JSONDecoder()` failures.

**Critical Formatting Rule**: The Edge Function instructs Gemini to output `common_name` in Title Case (e.g. "Monarch Butterfly"). For safety, the Swift decoding layer also applies `.capitalized` on rendering to ensure older cached results display consistently without requiring DB migrations.

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
  "iucn_red_list_status": "least_concern",
  "taxonomy": {
    "kingdom": "Animalia",
    "phylum": "Arthropoda",
    "class": "Insecta",
    "order": "Lepidoptera",
    "family": "Nymphalidae",
    "genus": "Danaus"
  },
  "insight_data": {
    "description": "An iconic pollinator...",
    "regional_status_rationale": "Native bounds active during summer months.",
    "is_poisonous": true
  },
  "wikipedia_url": "https://en.wikipedia.org/wiki/Monarch_butterfly",
  "wikipedia_extract": "The monarch butterfly or simply monarch is a milkweed butterfly in the family Nymphalidae. Other common names, depending on region, include milkweed, common tiger...",
  "reference_image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Monarch_In_May.jpg/320px-Monarch_In_May.jpg",
    "diagnostic_comparison": {
      "primary_match_rationale": "High structural alignment with expected wing vein layout.",
      "confusing_lookalike_name": "Viceroy Butterfly",
      "key_differentiators": [
        "Hindwing patterning: Subject has no horizontal black line vs Viceroy Pattern has distinct horizontal line across veins"
      ]
    },
  "colors": ["orange", "black", "white"],
  "group_tags": ["insect", "butterfly"]
}
```

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

> **Note on Wikipedia Extraction:** The server fetches Wikipedia metadata asynchronously after returning the response to iOS. Live scans therefore omit Wikipedia references in the initial response. The iOS client triggers a secondary fetch to `en.wikipedia.org/api/rest_v1/page/summary/` to backfill the `InsightSheetView` via `@Published` property mutations without blocking the initial AI response.

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
      "is_deleted": false
    }
  ]
}
```

### Safety and Transactional Integrity

1. **Batch Upserts**: All valid collections are written via a single atomic `.upsert(collectionPayloads)` call, resolving PostgreSQL `TIMESTAMPTZ` and `UUID` types without timing out.
2. **Bulk Insertion (N+1 Prevention)**: Pushing `collection_scans` entries in a `for` loop triggered N+1 query timeouts. The Edge Node routes the entire array into a single `.insert(allMappings)` call. If a user groups a scan while offline and the backend `scans` row hasn't arrived yet, Supabase catches the constraint error in `insertError` without crashing the container.
3. **Array-Bound Diffing Deletes**: Identifies obsolete collections by running `.select()` across the user's DB rows, building a `toDelete` array in memory and passing it to `.delete().in("id", toDelete)`. This avoids `.not("id", "in", "(...)")` string-builder failures.

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

## Deno `/export-dwca` Edge Node

Generates a Darwin Core Archive (DwC-A) containing the user's biological captures or a global dataset, zips the occurrence and multimedia data, uploads it to Cloudflare R2, and returns an expiring download URL.

### Request Payload

```json
{
  "includePreciseCoordinates": true,
  "exportScope": "global" // or "user"
}
```

### Authentication Enforcement

- Extracts user identity from the GoTrue header via `supabaseAdmin.auth.getUser(jwt)`.
- **DwC-A Global Geoprivacy Leak Prevention**: Enforces ownership gating for exact coordinates. Evaluates `canAccessPrecise = includePreciseCoordinates && (scan.user_id === userId)`. For global exports, users receive perturbed coordinates (50km obfuscation) for scans they do not own. Exact `gps_lat_exact` / `gps_long_exact` values are only included when the authenticated `user.id` matches the scan's `user_id`.
