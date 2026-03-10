# API Contracts and Network Mappings

Merian operates heavily decoupled. The iOS application exclusively hits Supabase Edge Functions, abstracting its physical networking entirely away from 3rd party providers like Google Gemini.

## Deno `/generate-upload-urls` Edge Node

To fetch cryptographic keys for direct-to-Cloudflare uploads safely bridging DDOS vectors, the client pushes standard limits arrays:

### Request Payload

```json
{
  "user_id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "fileNames": ["photo_1.jpg", "photo_2.jpg"]
}
```

Yields securely locked Cloudflare R2 bounds explicitly tied to the original `user_id` preventing path traversal. These pre-signed `PUT` URLs dynamically generate an explicit `X-Amz-Expires=86400` query parameter (24 Hours). This extensive validation window explicitly decouples strict network connections, granting native Apple iOS `BackgroundTasks` total flexibility to execute data bursts overnight purely dictated by internal OS memory profiles, thermal bounds, and active Wi-Fi availability without inducing 403 Forbidden AWS errors.

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
  "r2ObjectKey": "staging/uuid_filename.jpg",
  "user_id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "depthScaleText": "1.2 meters",
  "weatherCondition": "Sunny",
  "weatherTemperatureF": 72.5
}
```

### The JSON Response Schema (From Gemini Back to Swift)

The `merianResponseSchema` within Deno forces Gemini structurally into this exact format. If an AI Agent mutates any key here, it MUST modify both the `index.ts` Deno code AND the `MerianNetworkClient.swift` Codable struct to prevent silent Swift failures during decoding.

**Critical Edge Limitation (Gemini 2.5):** The model natively errors with `400 Bad Request` if developers strictly supply descriptive strings for enum checks. The `ecology_type` must be explicitly formatted as a structural JSON `enum: ["wild", "urban", "domesticated", "unknown"]` constraint within Deno to map cleanly.

```json
{
  "is_biological_subject": true,
  "is_live_capture": true,
  "ecology_type": "wild",
  "scientific_name": "Danaus plexippus",
  "common_name": "Monarch Butterfly",
  "confidence_score": 0.98,
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

**Client Authentication Caveat**: `MerianNetworkClient` explicitly enforces device-level hardware tokens natively. The `user_id` mapped inside the request body payload is extracted natively from `DeviceIdentityManager.shared.deviceId` (Apple IDFV) ensuring persistent identity mapping across sessions cleanly bypassing brittle Supabase authenticated cookie states.

---

## Deno `/get-filtered-discovery-feed` Edge Node

Fetches the global social feed of public biological captures, explicitly excluding actors the user has explicitly blocked locally on their client. To prevent PostgreSQL parser exceptions and `in` modifier failures, the native Array matrix of blocked `user_id`s is strictly passed as a raw un-formatted TypeScript array (e.g. `.not("user_id", "in", isolatedExclusions)`) into the native Supabase JS abstraction layer.

### Authentication Enforcement

Unlike legacy edge structures which trusted unverified `userId` variables inside body payloads (enabling severe IDOR scrape vulnerabilities), this network mapping **strictly extracts cryptographic JWT Identity** from the Supabase `Authorization: Bearer` Header utilizing `supabaseAdmin.auth.getUser()`.

Any request attempting to fake a user session via a manipulated JSON body without passing a valid structural JWT signature in the header natively fails with a `401 Unauthorized` token boundary. This guarantees actors can only physically query Discovery Feeds mapping dynamically to their own authenticated blocklists natively.
