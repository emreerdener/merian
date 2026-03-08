# API Contracts and Network Mappings

Merian operates heavily decoupled. The iOS application exclusively hits Supabase Edge Functions, abstracting its physical networking entirely away from 3rd party providers like Google Gemini.

## Deno `/identify` Edge Node

### The JSON Request Payload (From Swift `OfflineQueueManager`)

When the `NWPathMonitor` goes green, iOS POSTs this payload to Supabase:

```json
{
  "r2ObjectKey": "staging/uuid_filename.jpg",
  "user_id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "depthScaleText": "1.2 meters",
  "weatherCondition": "Sunny"
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
    "regional_status_rationale": "Native bounds active during summer months."
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
