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

When the `NWPathMonitor` goes green, iOS POSTs this payload to Supabase:

```json
{
  "r2ObjectKey": "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_filename.jpg",
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
  "isFlashFired": true,
  "cameraPitchDegrees": -85.2,
  "compassHeading": 12.5,
  "relativeHumidity": 0.85,
  "uvIndex": 6
}
```

### The JSON Response Schema (From Gemini Back to Swift)

The `merianResponseSchema` within Deno forces Gemini structurally into this exact format. If an AI Agent mutates any key here, it MUST modify both the `index.ts` Deno code AND the `MerianNetworkClient.swift` Codable struct to prevent silent Swift failures during decoding.

**Critical Formatting Rule**: The Edge Function explicitly constraints Gemini to output the `common_name` tightly formatted in standard Title Case capitalization (e.g. "Monarch Butterfly"). However, for robust safety, the Swift decoding layer aggressively applies `.capitalized` properties downstream on rendering to guarantee older SQLite cache results physically display uniformly without requiring DB migrations natively.

**Critical Edge Limitation (Gemini 2.5):** The model natively errors with `400 Bad Request` if developers strictly supply descriptive strings for enum checks. The `ecology_type` must be explicitly formatted as a structural JSON `enum: ["wild", "urban", "domesticated", "unknown"]` constraint within Deno to map cleanly.

```json
{
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
      {
        "trait": "Hindwing patterning",
        "subject_value": "No horizontal black line",
        "lookalike_value": "Distinct horizontal black line across veins"
      }
    ]
  },
  "colors": ["orange", "black", "white"]
}
```

## The Standardized JSON Return Payload (From Supabase to Swift)

To seamlessly integrate with `MerianNetworkClient.swift` securely, the `/identify` Edge function returns standard, nested JSON array logic.

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

**Offline Ghost Overwrite Protection**: Prior to initializing generic `SupabaseManager.shared.initializeGhostSession()` catch blocks across standard `.getActiveJWT()` timeouts natively, the iOS client strictly evaluates `UserDefaults.standard.bool(forKey: "Merian_HasAuthenticatedOAuth")`. If an authenticated Apple/Google user goes deep offline into the wilderness letting their JWT physically expire, the Swift client will explicitly `throw NetworkError.invalidResponse` immediately. This completely bypasses the iOS Sandbox from arbitrarily flushing their Pro status with a random Guest UUID natively stranding `.sqlite` payloads in the void, forcing the `CameraRootView` to pop UI demanding physical re-authentication instead.

---

## Deno `/get-filtered-discovery-feed` Edge Node

Fetches the global social feed of public biological captures, explicitly excluding actors the user has explicitly blocked locally on their client. To prevent PostgreSQL parser exceptions and `in` modifier failures, the native Array matrix of blocked `user_id`s is strictly passed as a raw un-formatted TypeScript array (e.g. `.not("user_id", "in", isolatedExclusions)`) into the native Supabase JS abstraction layer.

### Authentication Enforcement

Unlike legacy edge structures which trusted unverified `userId` variables inside body payloads (enabling severe IDOR scrape vulnerabilities), this network mapping **strictly extracts cryptographic JWT Identity** from the Supabase `Authorization: Bearer` Header utilizing `supabaseAdmin.auth.getUser()`. 

**Critical Kong API Gateway Requirement**: 
Because we use `URLSession` inside `MerianNetworkClient` instead of the Supabase Swift Edge Function SDK, all HTTP requests strictly POSTing to Deno **MUST** include both the `Authorization: Bearer <JWT>` header AND the `apikey: <SUPABASE_ANON_KEY>` header. If the `apikey` header is omitted, the Supabase Kong API Gateway will intercept and strip the `Authorization` header before it reaches the Edge Function, resulting in unhandled `401 Unauthorized: Missing token` crashes.

Any request attempting to fake a user session via a manipulated JSON body without passing a valid structural JWT signature in the header natively fails with a `401 Unauthorized` token boundary. This guarantees actors can only physically query Discovery Feeds mapping dynamically to their own authenticated blocklists natively.

### Endangered Species Payload Shielding
To completely prevent poachers from harvesting exact GPS geometries for IUCN Endangered, Vulnerable, or Near-Threatened species, the endpoint executes a stringent post-processing `map` array loop natively before JSON transmission. If the specific Linnaean taxonomy flags the capture as protected, the `.gps_lat_exact` and `.gps_long_exact` numeric boundaries are aggressively deleted completely off the global JSON payload, natively rounding their `gps_lat_public` geometries mathematically to 11km bounds. This completely obscures the data seamlessly regardless of whether the user opted into `Open` geoprivacy natively.

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

Generates an ecosystem report against AI inferences mapped aggressively within the native UI (`FlagIssueView`), injecting raw data safely into `00005_flagged_reviews.sql`.

### Request Payload

```json
{
  "scanId": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "userId": "Supabase Auth UUID explicitly linking for analytical parsing locally",
  "flagReason": "Incorrect Species",
  "userSuggestion": "Optional taxonomy string provided by the user manually"
}
```

### Authentication Enforcement

- Validates JWT signature to ensure a genuine authenticated identity mapping against `scan_id`. 
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
