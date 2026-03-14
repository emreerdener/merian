# API Contracts and Network Mappings

Merian operates heavily decoupled. The iOS application exclusively hits Supabase Edge Functions, abstracting its physical networking entirely away from 3rd party providers like Google Gemini.

## Deno `/generate-upload-urls` Edge Node

To fetch cryptographic keys for direct-to-Cloudflare uploads safely bridging DDOS vectors, the client pushes standard limits arrays:

### Request Payload

```json
{
  "user_id": "Legacy device UUID strictly included for backward compatibility in Swift maps",
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
  "user_id": "Legacy Client String (Overridden securely by GoTrue Token)",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "depthScaleText": "1.2 meters",
  "weatherCondition": "Sunny",
  "weatherTemperatureF": 72.5,
  "deviceLocale": "en",
  "currentMonth": 3
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
  "diagnostic_comparison": null
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

**Client Authentication Caveat**: `MerianNetworkClient` explicitly abstracts GoTrue anonymous hardware tokens structurally. The backend **strictly extracts cryptographic JWT Identity** from the Supabase `Authorization: Bearer` Header utilizing `supabaseAdmin.auth.getUser()`, entirely disregarding untrusted `user_id` values passed into request body payloads. The payloads generated natively from Swift use `DeviceIdentityManager.shared.deviceId` strictly as a proxy binding string to sync RevenueCat identifiers but true API validation bridges dynamically exclusively over GoTrue JWT verification securely preventing API spoofing and session ghosting.

---

## Deno `/get-filtered-discovery-feed` Edge Node

Fetches the global social feed of public biological captures, explicitly excluding actors the user has explicitly blocked locally on their client. To prevent PostgreSQL parser exceptions and `in` modifier failures, the native Array matrix of blocked `user_id`s is strictly passed as a raw un-formatted TypeScript array (e.g. `.not("user_id", "in", isolatedExclusions)`) into the native Supabase JS abstraction layer.

### Authentication Enforcement

Unlike legacy edge structures which trusted unverified `userId` variables inside body payloads (enabling severe IDOR scrape vulnerabilities), this network mapping **strictly extracts cryptographic JWT Identity** from the Supabase `Authorization: Bearer` Header utilizing `supabaseAdmin.auth.getUser()`. 

**Critical Kong API Gateway Requirement**: 
Because we use `URLSession` inside `MerianNetworkClient` instead of the Supabase Swift Edge Function SDK, all HTTP requests strictly POSTing to Deno **MUST** include both the `Authorization: Bearer <JWT>` header AND the `apikey: <SUPABASE_ANON_KEY>` header. If the `apikey` header is omitted, the Supabase Kong API Gateway will intercept and strip the `Authorization` header before it reaches the Edge Function, resulting in unhandled `401 Unauthorized: Missing token` crashes.

Any request attempting to fake a user session via a manipulated JSON body without passing a valid structural JWT signature in the header natively fails with a `401 Unauthorized` token boundary. This guarantees actors can only physically query Discovery Feeds mapping dynamically to their own authenticated blocklists natively.

---

## Deno `/safe-delete` Edge Node

Fetches and deletes orphaned/inactive physical payload bytes isolated within the Cloudflare R2 bucket specifically resolving local edge caching bugs and ensuring compliance with Data Deletion policies. 

### Request Payload

```json
{
  "r2ObjectKey": "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_filename.jpg"
}
```

### Authentication Enforcement

To prevent arbitrary deletion vectors from hostile actors targeting the R2 storage limits natively, this system explicitly enforces Server-Side JWT Validation natively.
1. Natively maps `supabaseAdmin.auth.getUser()` to isolate the internal UUID binding securely.
2. Extracts the `uuid` subset strictly from the `r2ObjectKey` path string (e.g. mapping `/staging/<uuid>/...`).
3. Rigidly compares the parsed `uuid` mapped in the `r2ObjectKey` exactly against the authenticated JWT session `user.id`. 
4. If the explicit string bounds do not physically match securely, the Deno node actively throws a `403 Forbidden` response preventing structural access and drops execution immediately to protect the ecosystem passively.

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
5. Recursively deletes bytes natively mapped to the `AwsClient` bucket array based upon `image_storage_urls`.
6. Issues native `DELETE` commands wiping the Postgres row cleanly.
