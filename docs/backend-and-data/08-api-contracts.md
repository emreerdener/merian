# API Contracts and Network Mappings

Merian operates heavily decoupled. The iOS application exclusively hits Supabase Edge Functions, abstracting its physical networking entirely away from 3rd party providers like Google Gemini.

## Deno `/generate-upload-urls` Edge Node

To fetch cryptographic keys for direct-to-Cloudflare uploads safely bridging DDOS vectors, the client pushes standard limits arrays:

### Request Payload

```json
{
  "user_id": "Supabase Auth UUID linking RevenueCat and PostHog",
  "fileNames": ["photo_1.jpg", "photo_2.jpg"]
}
```

The server automatically extracts the genuine user identity cryptographically mapped off the `Authorization` Header JWT (`supabaseAdmin.auth.getUser()`) overriding any untrusted parameters structurally. Yields securely locked Cloudflare R2 bounds natively tied to the genuine user preventing path traversal vulnerabilities completely. These pre-signed `PUT` URLs dynamically generate an explicit `X-Amz-Expires=86400` query parameter (24 Hours). This extensive validation window explicitly decouples strict network connections, granting native Apple iOS `BackgroundTasks` total flexibility to execute data bursts overnight purely dictated by internal OS memory profiles, thermal bounds, and active Wi-Fi availability without inducing 403 Forbidden AWS errors.

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

When the `NWPathMonitor` goes green, iOS POSTs this payload to Supabase. Notably, to defend against Path Traversal and Data Scraping, the server violently enforces that any `r2ObjectKey` structurally completely mandates `staging/${user.id}/` mappings and inherently rejects `../` traversal attempts explicitly dropping foreign malicious requests instantly returning `HTTP 400` status constraints implicitly.

```json
{
  "r2ObjectKey": "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_filename.jpg",
  "imageBase64": "<base64 encoded string array for instant processing (skips r2ObjectKey)>",
  "user_id": "Supabase Auth UUID explicitly linking natively via GoTrue Session",
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

To drastically optimize API expenditures, the `identify` Deno Edge node employs two fundamental strategies:
- **Model Routing**: The system physically isolates Gemini clusters natively mapping `isProActive` subscriptions directly to `gemini-2.5-pro`, dynamically degrading base layer users optimally cleanly to `gemini-2.5-flash`. Both physical tiers unconditionally execute the strict `merianResponseSchema` bound to protect SQLite UI logic safely. 
- **Dynamic Token Truncation (Non-biological targets)**: To inherently drop output limits securely when processing non-biological data, the Deno node actively strips objects like `taxonomy`, `insight_data`, `diagnostic_comparison`, and `ecology_type` out of the global `required: []` payload natively passing `is_biological_subject: false` instead. The iOS Swift layer gracefully receives the exact null pointer bindings seamlessly resolving down to Native Optionals natively!

If an AI Agent mutates any key mapping below, it MUST modify both the `index.ts` Deno code AND the `MerianNetworkClient.swift` Codable struct to simultaneously support both the Pro schema and Free text-prompt shapes equally without throwing `JSONDecoder()` crashing states!

**Critical Formatting Rule**: The Edge Function explicitly constraints Gemini to output the `common_name` tightly formatted in standard Title Case capitalization (e.g. "Monarch Butterfly"). However, for robust safety, the Swift decoding layer aggressively applies `.capitalized` properties downstream on rendering to guarantee older SQLite cache results physically display uniformly without requiring DB migrations natively.

**Critical Edge Limitation (Gemini 2.5):** The model natively errors with `400 Bad Request` if developers strictly supply descriptive strings for enum checks. The `ecology_type` must be explicitly formatted as a structural JSON `enum: ["wild", "urban", "domesticated", "unknown"]` constraint within Deno to map cleanly.

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
  "colors": ["orange", "black", "white"]
}
```

## The Standardized JSON Return Payload (From Supabase to Swift)

To completely eliminate network bottleneck latency, the `/identify` Edge Function generates the `scan_id` locally using `crypto.randomUUID()` and **instantaneously returns the `data` payload natively** to the iOS application as soon as the Gemini inference completes. It permanently abstracts all relational PostgreSQL insertions, background R2 uploads, and parallel API scrapers (GBIF/Wikipedia) securely behind an asynchronous `EdgeRuntime.waitUntil` boundary preventing UI threading locks implicitly.

### Gemini Parsing and Error Mitigation

To prevent Deno V8 Container crashes due to Catastrophic Backtracking (ReDoS) from hallucinated markdown payloads, the endpoint parses raw Gemini output using a strictly enforced lightweight string mapping `substring(indexOf)` methodology instead of unbounded regex. If `JSON.parse` fails these physical bounds, it explicitly traps the exception natively returning an `HTTP 422 Unprocessable Entity`. Because `422` is intentionally excluded from the iOS `OfflineQueueManager`'s list of recoverable `.networkError` codes, the host client natively drops the corrupted queue dependency gracefully mapping avoiding infinitely deadlocking background requests and protecting user bandwidth limits.

> **Note on Wikipedia Extraction:** Because the server asynchronously fetches Wikipedia payload metadata natively inside of PostgreSQL *after* delivering the active response down to iOS, live scans will execute instantaneously but omit Wikipedia references structurally. The iOS client intentionally triggers a secondary `fetch` to `en.wikipedia.org/api/rest_v1/page/summary/` synchronously with the rendering timeline to backfill the `InsightSheetView` UI organically via `@Published` property wrapper mutations without compromising initial AI performance.

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

This strict data contract bridges safely into the native Swift Codable layer where nested JSON `Data` is natively verified safely preventing `JSONDecoder()` crashing states on double-escaped strings.

```swift
struct IdentifyResponse: Codable {
    let success: Bool
    let data: SpeciesData?
    let error: String?
}
```

**Client Authentication Caveat**: `MerianNetworkClient` explicitly abstracts GoTrue anonymous hardware tokens structurally. The backend **strictly extracts cryptographic JWT Identity** from the Supabase `Authorization: Bearer` Header utilizing `supabaseAdmin.auth.getUser()`, entirely disregarding untrusted `user_id` values passed into request body payloads. The payloads generated natively from Swift use the `SupabaseManager`'s active session UUID strictly as a proxy binding string to sync RevenueCat identifiers but true API validation bridges dynamically exclusively over GoTrue JWT verification securely preventing API spoofing and session ghosting.

**Offline Ghost Overwrite Protection**: Prior to initializing generic `SupabaseManager.shared.getValidAuthHeaders()` catch blocks across standard timeouts natively, the iOS client strictly evaluates `UserDefaults.standard.bool(forKey: "Merian_HasAuthenticatedOAuth")`. If an authenticated Apple/Google user goes deep offline into the wilderness letting their JWT physically expire, the Swift client will explicitly `throw NetworkError.invalidResponse` immediately. This completely bypasses the iOS Sandbox from arbitrarily flushing their Pro status with a random Guest UUID natively stranding `.sqlite` payloads in the void, forcing the `CameraRootView` to pop UI demanding physical re-authentication instead.

---

## Deno `/get-filtered-discovery-feed` Edge Node

Fetches the global social feed of public biological captures, explicitly excluding actors the user has explicitly blocked locally on their client. To prevent PostgreSQL parser exceptions and `in` modifier failures, the native Array matrix of blocked `user_id`s is strictly passed as a raw un-formatted TypeScript array (e.g. `.not("user_id", "in", isolatedExclusions)`) into the native Supabase JS abstraction layer.

### Authentication Enforcement

Unlike legacy edge structures which trusted unverified `userId` variables inside body payloads (enabling severe IDOR scrape vulnerabilities), this network mapping **strictly extracts cryptographic JWT Identity** from the Supabase `Authorization: Bearer` Header utilizing `supabaseAdmin.auth.getUser()`. 

**Critical Kong API Gateway Requirement**: 
Because we use `URLSession` inside `MerianNetworkClient` instead of the Supabase Swift Edge Function SDK, all HTTP requests strictly POSTing to Deno **MUST** include both the `Authorization: Bearer <JWT>` header AND the `apikey: <SUPABASE_ANON_KEY>` header. If the `apikey` header is omitted, the Supabase Kong API Gateway will intercept and strip the `Authorization` header before it reaches the Edge Function, resulting in unhandled `401 Unauthorized: Missing token` crashes.

Any request attempting to fake a user session via a manipulated JSON body without passing a valid structural JWT signature in the header natively fails with a `401 Unauthorized` token boundary. This guarantees actors can only physically query Discovery Feeds mapping dynamically to their own authenticated blocklists natively.

### Global Geoprivacy & Endangered Species Shielding
To completely prevent physical location tracking, geolocation scraping, and poachers from harvesting targets mapping dynamically to IUCN Endangered, Vulnerable, or Near-Threatened species, the endpoint executes an aggressive stringent post-processing `map` array loop natively before JSON transmission. The system **unconditionally** deletes the exact `.gps_lat_exact` and `.gps_long_exact` numeric boundaries completely off the global JSON payload for every single user scan natively, closing global tracking bounds seamlessly regardless of whether the user explicitly opted into `Open` geoprivacy natively. Furthermore, if the specific Linnaean taxonomy flags the capture as protected, it organically rounds their `gps_lat_public` geometries mathematically down to 11km structural tiles masking the generalized discovery feed dynamically.

---

## Deno `/merge-ghost-profile` Edge Node

Transfers ownership of physical records originating from an ephemeral Anonymous Ghost Session securely into a fully enrolled, newly authenticated Google/Apple ID natively.

### Request Payload

```json
{
  "ghost_id": "Transient Anonymous UUID to merge"
}
```

### Authentication Enforcement

Because this completely reassigns thousands of physical PostgreSQL records, validation must tightly prevent IDOR Account Takeover (ATO) exploits natively:
1. Maps `supabaseAdmin.auth.getUser(jwt)` natively to extract the verified `targetUserId`.
2. Explicitly triggers `supabaseAdmin.auth.admin.getUserById(ghost_id)` natively validating `is_anonymous === true`. If a malicious actor passes a fully authenticated user's ID blindly attempting to hijack their cloud scans and force a `deleteUser`, the Edge loop instantly faults with a `403 Forbidden` IDOR termination shielding registered identities natively.
3. Completely transfers `scans` ownership mapping and cleanly drops the native `ghost_id` via `.deleteUser(ghost_id)`.

---

## Deno `/safe-delete` Edge Node

Permanently tombstones a user's account and initiates the total erasure of all their associated physical payload bytes across both PostgreSQL databases and Cloudflare R2 storage.

### Request Payload

No JSON body is required. The endpoint operates entirely off of cryptographic identity bindings to prevent IDOR vulnerabilities.

### Authentication Enforcement

To prevent arbitrary account deletion vectors from hostile actors:
1. Natively maps `supabaseAdmin.auth.getUser()` to isolate the internal UUID binding securely from the `Authorization: Bearer` header.
2. Directly executes the `apply_user_tombstone` PostgreSQL RPC strictly mapping against the exact authenticated JWT session `user.id`. 
3. The RPC securely cascades through the `public.scans`, `public.user_blocks`, and `public.flagged_reviews` tables, wiping the data natively and triggering Cloudflare R2 object purges.
4. Returns a `200 OK` prompting the iOS client to natively `signOut()`, drop all local SQLite `ModelContext` dependencies (via `ScanRepository.purgeAllData()`), and reset the user boundary to Guest.

---

## Deno `/delete-scan` Edge Node

Permanently deletes a fully cataloged biological scan from both the physical Supabase PostgreSQL database and the Cloudflare R2 bucket synchronously.

### Request Payload

```json
{
  "scanId": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
}
```

### Authentication Enforcement

Because this completely destroys a structural memory, validation is absolute:
1. Extracts `scanId` from the payload and queries `public.scans` using the Service Role.
2. If the scan natively doesn't exist (e.g. deleted while offline but already purged serverside), it safely returns a HTTP 200 payload telling the Swift queue system to drop the offline payload cleanly.
3. Retrieves the active GoTrue verification natively bridging the JWT boundary mapped by `supabaseAdmin.auth.getUser()`.
4. Statically equates `scan.owner_id === user.id`. A mismatch throws a `403 Forbidden` IDOR termination.
5. Recursively deletes bytes natively mapped to the `AwsClient` bucket array based upon exactly the `image_storage_urls` array payloads without manually rebuilding Cloudflare endpoints. This natively prevents 404 stranded images caused by accidental namespace duplication bounds.
6. Issues native `DELETE` commands wiping the Postgres row cleanly.

---

## Deno `/block-user` Edge Node

Executes a rigid moderation block, instantly dropping the specified offender from the authenticated identity's Discovery Feed ecosystem securely natively via `SocialGuardManager`.

### Request Payload

```json
{
  "blocked_id": "Target UUID to block"
}
```

### Authentication Enforcement

- Strictly pulls `supabaseAdmin.auth.getUser(jwt)` mapped from the GoTrue header.
- Physically writes the structural boundary into the `public.user_blocks` Table natively (schema migrated via `00001_initial_schema.sql`).
- Generates a `400 Bad Request` if `blocked_id` matches the calling identity's UUID safely.

---

## Deno `/flag-issue` Edge Node

Generates an ecosystem report against AI inferences mapped aggressively within the native UI (`ReportInsightView`), injecting raw data safely into `00005_flagged_reviews.sql`.

### Request Payload

```json
{
  "scanId": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "flagReason": "Incorrect Species",
  "userSuggestion": "Optional taxonomy string provided by the user manually"
}
```

### Authentication Enforcement

- Strictly pulls `user!.id` natively returning from the `requireAuth(jwt)` middleware.
- Validates JWT signature to ensure a genuine authenticated identity mapping against `scan_id` ignoring payload spoofing completely.
- Natively inserts a row mapped strictly into `public.flagged_reviews`.
- Triggers `HTTP 200` upon success securely decoupling the user's report without hanging the SwiftUI interface dynamically.

---

## Deno `/export-dwca` Edge Node

Generates a Darwin Core Archive (DwC-A) containing the user's biological captures or a global dataset, zipping the occurrence and multimedia data, then uploading it directly to Cloudflare R2 before generating an expiring download URL.

### Request Payload

```json
{
  "includePreciseCoordinates": true,
  "exportScope": "global" // or "user"
}
```

### Authentication Enforcement

- Strictly pulls `supabaseAdmin.auth.getUser(jwt)` mapped from the GoTrue header.
- **DwC-A Global Geoprivacy Leak Prevention**: Cryptographically enforces ownership gating for exact coordinate access. Evaluates `canAccessPrecise = includePreciseCoordinates && (scan.user_id === userId)`. If a user requests a global dataset (`exportScope = "global"`), they will only receive perturbed/public coordinates (`50km` obfuscated matrix) for scans they do not physically own, completely patching the global location scraping vulnerability. Exact coordinates (`gps_lat_exact`, `gps_long_exact`) are strictly included only when the authenticated JWT `user.id` cryptographically matches the specific `scan.user_id`.
