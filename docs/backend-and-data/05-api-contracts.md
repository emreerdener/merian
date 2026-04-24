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

The server extracts the verified user identity from the `Authorization` Header JWT (`supabaseAdmin.auth.getUser()`), ignoring any `user_id` value in the request body. To prevent array-abuse memory locking on the Edge Node, the endpoint strictly requires exactly 1 to 5 `fileNames`. Pre-signed `PUT` URLs include an `X-Amz-Expires=86400` parameter (24 hours). This extended window gives iOS `BackgroundTasks` flexibility to transmit overnight, subject to OS memory, thermal, and Wi-Fi conditions, without hitting 403 errors.

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
  "deviceTimeZone": "America/Los_Angeles",
  "deviceRegion": "US",
  "currentMonth": 3,
  "timeOfDay": "2:00 PM",
  "timestamp": "2026-03-21T09:46:03.000Z",
  "estimated_size_cm": 15.2,
  "description": "Small brown moth, roughly 2 cm wingspan, spotted resting on bark at night",
  "observation_context": {
    "organism_class": "Insect",
    "colors": ["brown", "grey"],
    "size": "small",
    "habitats": ["woodland", "garden"],
    "behaviors": ["resting", "nocturnal"],
    "markings": "subtle eyespot pattern on forewings",
    "textures": "dusty wing scales",
    "free_text": "Found near porch light after dark"
  }
}
```

`description` is an optional plain-text string generated client-side by `ObservationContext.serialized()` — a pre-rendered key:value summary of the user's structured observation (e.g. `"Class: Insect\nColors: brown, grey\n..."`). It is appended to the Gemini context string at the edge function to ground identification before the vision model runs. `observation_context` is the full structured JSON object matching the iOS `ObservationContext` model; it is persisted server-side as `public.scans.user_observation_context` (JSONB) and returned to `LocalScanRecord.observationContextJSON` on the iOS layer. Both fields are `null` for image-only scans. The edge function accepts an array guard (`!Array.isArray(observation_context)`) before writing to prevent an accidental array submission from being persisted as malformed JSONB.

`currentMonth` and `timeOfDay` are derived from the image's own capture date (`telemetry.timestamp`) when available — not always from the current wall clock. For gallery photos with a valid EXIF date, this ensures Gemini receives the correct season and light context for the original photo (e.g., an October photo scanned in April sends `Month: 10`, not `Month: 4`). Falls back to current date/time for live captures and gallery photos with no EXIF.

`timestamp` is omitted (null) for gallery photos with no EXIF date rather than sending the current submission time. The server defaults `scans.timestamp` to `now()` in that case, which honestly represents when the scan was submitted. `deviceTimeZone` (IANA identifier, e.g. `"America/Los_Angeles"`) and `deviceRegion` (ISO 3166-1, e.g. `"US"`) are permission-free geographic signals sent as fallback context when GPS is not authorised. The Edge function injects them into the Gemini context string as `TZ:` and `Region:` tokens alongside `Locale:`, `Month:`, and `Time:` — grounding the model's regional species priors without requiring location permission. Neither field is stored in the `scans` table; they are inference-context only.

### The JSON Response Schema (From Gemini Back to Swift)

To optimize API expenditures, the `identify` Deno Edge node uses two strategies:
- **Model Routing**: The vision identification call routes Pro-tier subscribers to `gemini-2.5-pro` (maximum depth for rare species, fossils, subspecies, and cultivars) and free-tier users to `gemini-2.5-flash` (2–3× lower latency). All text-only calls — `fetchStaticEncyclopedicData`, `fetchDiagnosticComparison`, and all `enrich-scan` generation — always use `gemini-2.5-flash` regardless of tier. `gemini-2.5-pro` is exclusively for the multimodal vision identification step. Tier is resolved via a single lightweight `SELECT subscription_tier` on the critical path, with a module-scope `_tierCache` (5-minute TTL) that eliminates the DB round-trip on repeat scans within a warm isolate. Both tiers use the `merianResponseSchema` constraint to protect SQLite UI logic.
- **Dynamic Token Truncation (Non-biological targets)**: When processing non-biological subjects, the Deno node removes `taxonomy`, `insight_data`, and `ecology_type` from the `required: []` array and passes `is_biological_subject: false`. The Swift layer maps the absent fields to native Optionals. **Geology Bypass**: Gemini's prompt explicitly instructs the LLM to output `scientific_name` and `common_name` for geological subjects (e.g. rocks) despite being non-biological. This surfaces rocks cleanly in the iOS layer under `isBiological: false` (routing them out of the main dictionary and into the 30-day auto-purge graveyard) without reverting to generic "Unknown Subject" names.

If an AI Agent mutates any key mapping below, it MUST modify both the `index.ts` Deno code AND the `MerianNetworkClient.swift` Codable struct to simultaneously support both the Pro schema and Free text-prompt shapes without causing `JSONDecoder()` failures.

> **Image format**: All images in this pipeline are encoded as lossy **WebP** (`image/webp`). The `inlineData.mimeType` field passed to the Gemini SDK in `index.ts` must always be `"image/webp"`. Gemini 2.5 Flash and Pro both accept `image/webp` natively. If this value is changed to `image/jpeg` while the actual bytes are WebP, Gemini will reject or misinterpret the payload.

**`common_name` source**: On **Cache Miss** (first-ever scan of a species), `common_name` is taken directly from the Gemini vision model output. On **Cache Hit**, `index.ts` overrides the Gemini-supplied `common_name` with the canonical `species_dictionary.common_names.en` value so repeat scans of the same species always show a consistent display name regardless of which Gemini response generated it. The Swift decoding layer applies `.capitalized` on rendering for display consistency. For geological targets, it relies wholly on the Gemini output (no cache override applies).

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
  "reproductive_condition": "not_applicable",
  "individual_count": 1,
  "ecological_interactions": ["pollinating Asclepias syriaca"],
  "extracted_visual_traits": [
    "orange and black wing pattern",
    "white-spotted margins",
    "ventral silver spots"
  ],
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
  },

  "// Cache Hit — sourced from species_dictionary.alternative_common_names (populated from GBIF vernacular names on first enrichment):": "",
  "alternative_common_names": ["Monarch", "Common Tiger"],

  "// Present when confidence_score < diagnosticTrigger (0.99 both Flash and Pro — intentionally above strong threshold so Strong match scans still show candidates as escape hatch). Server strips to null at or above 0.99. See _shared/identify/thresholds.ts.": "",
  "candidates": [
    { "scientific_name": "Limenitis archippus", "common_name": "Viceroy", "confidence_score": 0.71, "distinguishing_feature": "Hindwing black postmedian band broader and more irregular than Monarch" },
    { "scientific_name": "Danaus gilippus", "common_name": "Queen", "confidence_score": 0.58, "distinguishing_feature": "Forewing lacks white spots in the black apex band" }
  ]
}
```

> **Vision schema lean principle**: The vision model response (`identify`) is optimised strictly for identification and ecosystem measurement. Data-as-a-Service fields (`estimated_size_cm`, `life_stage`, `reproductive_condition`, `individual_count`, `ecological_interactions`) are fully generated on the primary pass avoiding any secondary inference loops. `extracted_visual_traits` executes a Micro-CoT pass before taxonomic grouping to anchor the model to reality and avoid visual pareidolia. `insight_data.ai_reasoning` is always present for biological subjects — it is the Gemini vision model's per-scan reasoning about the specific photo submitted and is unique per scan. **LLM field caps** (enforced in `index.ts` after scientific name sanitization): `colors`, `extracted_visual_traits`, and `ecological_interactions` are each truncated to a maximum of 10 items; `ai_reasoning` is truncated to 2000 characters; `individual_count` is validated as a positive integer ≤ 99999; the client-supplied `estimated_size_cm` is validated as a positive finite number ≤ 50000; the `candidates` array is capped at 5 items before `payloadReadyForClient` is built. **GPS range validation**: `gpsLatitude` and `gpsLongitude` from the request payload are validated against physical bounds (`−90 ≤ lat ≤ 90`, `−180 ≤ lon ≤ 180`). Out-of-range values are sanitised to `null` (carried as `safeGpsLat`/`safeGpsLon` throughout `index.ts`) rather than failing the request — location is supplementary and a bad coordinate must not abort identification. These bounds protect the V8 heap and downstream SQLite columns from unbounded LLM output. To guarantee this Micro-CoT happens linearly, both `extracted_visual_traits` and `ai_reasoning` are anchored at the top of the `getSchemaProperties` object, forcing Gemini to output them *before* classification. Ghost fields (`colors`, `regional_status_rationale`, `blur_score`) are stripped out entirely from both schema descriptors and prompts to decrease inference loops and token footprint. `blur_score` is computed mathematically from the required `sharpness` attribute down-stream. Schema objects are aggressively memoized locally (`schemaCache`) per-tier to bypass redundant V8 isolations. `taxonomy` and `iucn_red_list_status` are only present on Cache Hit (read from `species_dictionary`). `gbif_taxon_key` is present on Cache Hit for **all tiers** — it is GBIF's deterministic species usage key (sourced from a REST call to `api.gbif.org`, not AI-generated) and powers the occurrence density heatmap in `BiologicalView` for free and Pro users alike. `species_insights` is present on Cache Hit for all tiers when `habitat_description` is already stored in `species_dictionary`. `alternative_common_names` is a `string[] | null` field present on Cache Hit. It contains all known English vernacular synonyms for the species beyond the primary `common_name`, sourced from the GBIF vernacular names endpoint (`GET /v1/species/{key}/vernacularNames?language=eng&limit=30`) during the background enrichment pass that fires on the first Cache Miss for a species. The primary `common_name` value is excluded from this array (case-insensitive deduplication applied server-side). `null` on Cache Miss or when GBIF returned no additional names. On the iOS side, these alternatives are stored in `LocalScanRecord.alternativeCommonNames` (SwiftData V34) and presented in `InsightHeader` as a tappable "Also known as" line. `similar_species` is never included in the `identify` response — it is generated asynchronously by the `enrich-scan` function unconditionally (Edge applies no confidence gate; the iOS client dynamically applies the tier-specific threshold in `BiologicalView` to decide display treatment). `hazard_type` inside `insight_data` comes from `species_dictionary` on Cache Hit (authoritative); on Cache Miss the live response currently defaults to `"none"` until later enrichment fills the richer species-level hazard metadata. The `hazard_type` column exists only on `species_dictionary`, not on `scans`. `candidates` is a **required field** in `merianResponseSchema` — Gemini always generates exactly 2 alternative species. `index.ts` calls `diagnosticTriggerForTier(tier)` from `_shared/identify/thresholds.ts` and sets `candidates = null` before sending the response and before the `scans` DB insert when `confidence_score >= diagnosticTrigger` (`0.99` for both Flash and Pro). This threshold is intentionally above the `strong` band on each tier (`0.95` Flash / `0.85` Pro), so Strong match scans (0.95–0.99) still reach the client with a full candidate list as an escape hatch for overconfident wrong IDs. Only scans at or above 0.99 have candidates stripped — every Possible, Weak, and Strong match scan carries alternatives for the verification UX. The server gate is the sole enforcement mechanism; the model is not asked to conditionally self-suppress. **Null confidence_score safety**: if Gemini unexpectedly returns a null `confidence_score` (malformed response), the gate falls back to `0.0` (not `1.0`) so that candidates are *preserved* — a scan with an unparseable confidence is exactly the scan where alternatives are most needed. Candidates are scan-specific (not species-level) and are persisted to `public.scans.candidates` (JSONB) and `LocalScanRecord.candidatesData` (Data blob, `MerianSchemaV28`).

### Background Ingestion & Media Moderation

After the HTTP `200 OK` response is returned to the client, `runBackground` schedules asynchronous ingestion via `EdgeRuntime.waitUntil`. This background task handles:

1. **Ghost user upsert** — ensures the `users` table row exists before the `scans` FK insert
2. **Content moderation** (`_shared/identify/moderation.ts`) — evaluates Gemini safety ratings and promotes media from staging to public storage
3. **Species dictionary enrichment** (Cache Miss only) — calls `fetchExternalEnrichment` for Wikipedia/GBIF data
4. **`insertScan`** — writes the final scan row to `public.scans`
5. **Group tags** — fires a background Flash call to populate `species_dictionary.group_tags` for first-time species

**Media promotion**: Safe media is moved from `staging/{userId}/{filename}` to `public_uploads/{tier}/{userId}/{filename}` inside Cloudflare R2, and the CDN URL (`https://media.merian.app/public_uploads/...`) is stored in `scans.image_storage_urls`. For the `imageBase64s` path, the bytes are uploaded directly to the public destination without a staging step. Any promotion failure now aborts the entire batch and immediately rolls back any already-promoted public objects from that same batch before returning `ERROR`; scans are not inserted with partial image arrays.

**Moderation failure handling**: If Gemini's `finishReason === "SAFETY"` or any `safetyRating.probability` is `"MEDIUM"` or `"HIGH"`, the staging object is deleted, `users.abuse_strikes` is incremented, and the scan is not inserted. At 3+ strikes `users.is_shadowbanned` is set to `true` and all future ingestion silently halts. See [Safety & Moderation](../development-guides/10-safety-and-moderation.md) for full details.

**R2 rollback**: If `insertScan` throws after media has already been promoted to public storage, the public objects are deleted via `deleteR2Object` to prevent orphaned CDN assets. The same rollback fires if a mid-loop R2 upload failure throws during the `imageBase64s` promotion pass.

### Error Responses

| Status | Body | Meaning |
|---|---|---|
| `400` | `{ "error": "Bad Request: Path traversal detected." }` | `r2ObjectKeys` contains a `../` traversal attempt |
| `400` | `{ "error": "Forbidden: r2ObjectKey does not belong to the requesting user." }` | IDOR — key does not belong to the authenticated user |
| `400` | `{ "error": "AI processing error. Please try again." }` | Permanent content policy failure (`finishReason` is `SAFETY` or `PROHIBITED_CONTENT`) |
| `413` | `{ "error": "Payload Too Large: Combined images exceed 5MB limit." }` | Combined image payload exceeds 5 MB |
| `422` | `{ "error": "Processing Error: Malformed AI response." }` | Gemini returned output that could not be parsed |
| `422` | `{ "error": "Processing Error: Invalid AI response format." }` | Gemini returned output in an unexpected format |
| `503` | `{ "error": "AI processing error. Please try again." }` | Transient Gemini failure (API error, rate limit, timeout, non-SAFETY non-STOP finish reason) |

`400` on a content policy failure is intentional — the iOS `OfflineQueueManager` treats `400` as a permanent tombstone and removes the queue entry rather than retrying. All other Gemini errors return `503` so the offline queue retries up to `maxUploadRetries` times before giving up. `422` is also excluded from recoverable codes and drops the entry immediately.

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

**Offline Ghost Overwrite Protection**: Before calling `SupabaseManager.shared.getValidAuthHeaders()`, the iOS client checks `UserDefaults.standard.bool(forKey: "Merian_HasAuthenticatedOAuth")`. If an authenticated user goes offline long enough for their JWT to expire, the Swift client throws `NetworkError.invalidResponse` immediately. This prevents a guest UUID from overwriting the user's Pro status or stranding their `.sqlite` data, and causes `CaptureWorkspaceView` to prompt re-authentication instead.

---

## Deno `/identify-multimodal` Edge Node

A unified identification pipeline that merges the capabilities of `/identify`, `/identify-describe`, and `/audio-spec` into a single multi-modal entry point. The current iOS client routes new inference traffic here. Supports array-based compositions of images, audio, and descriptive context.

### The JSON Request Payload (From Swift `OfflineQueueManager`)

```json
{
  "r2ObjectKeys": [
    "staging/A1B2C3D4.../uuid_image_1.webp"
  ],
  "imageBase64s": ["<base64>"],
  "audioBase64s": ["<base64>"],
  "user_id": "Supabase Auth UUID",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "semanticLocation": "Zilker Park",
  "weatherCondition": "Partly Cloudy",
  "weatherTemperatureF": 68.0,
  "deviceLocale": "en",
  "deviceTimeZone": "America/Chicago",
  "deviceRegion": "US",
  "currentMonth": 4,
  "timeOfDay": "10:30 AM",
  "depthScaleText": "1.3 meters",
  "zoomFactor": 2.0,
  "estimated_size_cm": 11.5,
  "timestamp": "2026-03-21T09:46:03.000Z",
  "observation_contexts": [
    {
      "freeText": "Heard rustling before spotting it",
      "addedAt": "2026-03-21T09:45:20.000Z"
    }
  ]
}
```

- Features dynamic `MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION` execution if both `audioBase64s` and `imageBase64s` are present.
- Executes `processWAV` in Deno to enforce mono/16kHz processing before Gemini ingestion.
- Audio currently stays inline as `audioBase64s` on this path; there is no shipped `audioR2Keys` request field in the active client/server contract.
- The canonical request contract is camelCase telemetry (`gpsLatitude`, `semanticLocation`, `deviceTimeZone`, etc.) plus `observation_contexts: [{ freeText, addedAt? }]`, matching `MerianNetworkClient.buildMultiModalRequest(...)` and the iOS `ObservationContext` model.
- The server still accepts legacy snake_case telemetry aliases (`gps_latitude`, `semantic_location`, `time_of_day`, etc.) and legacy `free_text` context keys so offline queue replays and older internal tooling do not break mid-migration.
- Candidate handling now matches `/identify`: the response strips `candidates` when `confidence_score >= diagnosticTrigger`, enriches forwarded candidates with cached English common names when available, and schedules background enrichment for cache misses.
- The multimodal background ingestion path shares the same `_shared/identify` DB, media, schema, threshold, and moderation primitives as `/identify`.



## Text-Only Describe Path

The current app routes text-only observations through `/identify-multimodal` with `observation_contexts` populated and no images or audio attached. The legacy `/identify-describe` endpoint remains deployed, but it is no longer the primary client path.

### Request Payload

```json
{
  "user_id": "Supabase Auth UUID",
  "client_scan_id": "UUID generated by iOS for idempotency",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "semanticLocation": "Zilker Park",
  "weatherCondition": "Partly Cloudy",
  "weatherTemperatureF": 68.0,
  "deviceLocale": "en",
  "deviceTimeZone": "America/Los_Angeles",
  "deviceRegion": "US",
  "currentMonth": 4,
  "timeOfDay": "10:30 AM",
  "timestamp": "2026-04-14T10:30:00.000Z",
  "observation_contexts": [
    {
      "freeText": "Medium-sized bird, vivid blue upperparts, rust-orange breast, perched on fence post in suburban garden. Heard a clear flute-like song before spotting it.",
      "addedAt": "2026-04-14T10:29:45.000Z"
    }
  ]
}
```

`client_scan_id` is generated by the iOS client and forwarded as `generatedScanId` to the edge function. The current multimodal text-only path inserts through the shared `insertScan` contract using the same idempotent scan ID semantics as image and audio requests.

The current iOS client does not send a top-level `description` field on this path. The edge function concatenates the `observation_contexts[*].freeText` entries into the multimodal prompt server-side. The first structured context object is also persisted to `public.scans.user_observation_context` for scan-level provenance. The iOS client guards on `ObservationContext.isEmpty` before allowing submission.

`r2ObjectKeys`, `imageBase64s`, and `audioBase64s` are intentionally absent — there is no media in a text-only submission. `scans.image_storage_urls` is written as an empty image array by the shared insert path because there is no promoted media to persist.

### Response Schema

The response shape mirrors the `/identify` / `/identify-multimodal` JSON response exactly. `scan_id` is returned as the scan UUID generated for that text-only request.

### IDOR & Auth

The server extracts the user identity from the `Authorization: Bearer` JWT via `supabaseAdmin.auth.getUser()`. The `user_id` in the request body is ignored for auth purposes.

### Error Responses

| Status | Body | Meaning |
|---|---|---|
| `400` | `{ "error": "At least one media element or description is required" }` | No image, audio, or non-empty `observation_contexts[*].freeText` text was provided |
| `400` | `{ "error": "AI processing error. Please try again." }` | Permanent Gemini safety / policy failure |
| `422` | `{ "error": "Processing Error: Malformed AI response." }` | Gemini returned unparseable output |
| `503` | `{ "error": "AI processing error. Please try again." }` | Transient Gemini failure |

---

## Deno `/enrich-scan` Edge Node

An enrichment endpoint that asynchronously surfaces habitat, taxonomy, and similar species data for a scan. Called automatically by the iOS client after every successful biological scan completes — the user sees a loading skeleton in `HabitatAndDistributionCard` while this request is in flight.

### Request Payload

```json
{
  "scan_id": "A1B2C3D4-...",
  "scientific_name": "Danaus plexippus",
  "confidence_score": 0.91,
  "inference_tier": "flash"
}
```

Only `scientific_name` is strictly required by the Edge function. `scan_id`, `confidence_score`, and `inference_tier` are sent by the iOS client for telemetry but are not used server-side — the Edge function applies no confidence gating of its own.

### Architecture

**No Tier Gate**: Available to all authenticated users. Enrichment data is generated by Flash and cached in `species_dictionary` at the species level — subsequent calls for the same species are served from cache with no AI call.

**Frontend-Driven Thresholds**: The Edge function unconditionally queries or fetches `similar_species` if it is not already cached in `species_dictionary`. It does not evaluate `confidence_score`. Instead, the iOS client (`InferenceEngine.fetchAndApplyEnrichment` and `BiologicalView`) dynamically compares the score against the user's tier-specific threshold (`0.88` for Flash, `0.80` for Pro) to decide whether to highlight the data as a "POTENTIAL LOOKALIKES" diagnostic warning or merely informational "SIMILAR SPECIES".

**Full Cache Hit**: If `species_dictionary` already has `habitat_description` and the `species_lookalikes` join table has entries for this species, the function returns all data immediately with no Gemini calls — typically sub-50ms.

**Two-Layer Lookalike Strategy**:
- **Layer 1 — Taxonomy trigger (zero token cost)**: A Postgres `AFTER INSERT` trigger (`trg_link_taxonomy_lookalikes`) auto-populates `species_lookalikes` with bidirectional same-genus links whenever a new species row is inserted. Same-genus species are almost always visually similar; this alone covers the majority of cases without any Gemini call.
- **Layer 2 — Gemini Flash for cross-family visual mimics**: `fetchSimilarSpecies` is only invoked when the `species_lookalikes` join table is empty AND `similar_species TEXT[]` has no legacy names. Flash receives the species' full taxonomy (kingdom, class, order, family) from `cachedSpecies` and is constrained by the system instruction to return lookalikes from the **same taxonomic order** — not merely the same kingdom. After Gemini returns entries, `resolveLookalikesToJoinTable` validates both kingdom and order match before writing to the join table.

**Taxonomy Grounding (`fetchSimilarSpecies` + `resolveLookalikesToJoinTable`)**: Flash is passed `kingdom`, `class`, `order`, and `family` from `species_dictionary` as context. The system instruction explicitly forbids cross-order results (e.g. grasses as lookalikes for Narcissus — both Plantae but different orders). `resolveLookalikesToJoinTable` accepts both `primaryKingdom` and `primaryOrder` and rejects any resolved species that contradicts either. Species with no kingdom/order recorded in `species_dictionary` are allowed through (cannot contradict what is unknown). **Early-exit on null kingdom**: If `primaryKingdom` is `null`, all join-table writes are skipped and Flash-generated entries are returned as stubs directly — preventing contamination when the primary species' kingdom is not yet populated (e.g., replication lag). `lookalikes_flash_attempted` is **only** set to `true` when `resolveLookalikesToJoinTable` returns `persisted: true`, ensuring the flag never locks before validated data is in the join table.

**Automatic Stale Contamination Detection**: On each `lookalikes` scope request, `index.ts` compares the primary species' `order` against every cached join-table entry's `order`. If the primary species' order is known and **every** cached entry has a different known order (100% cross-order contamination — the characteristic signature of a lookalikes Flash call that raced ahead of the enrichment scope that writes taxonomy), the stale rows are automatically cleared via `clearLookalikesForSpecies`, `lookalikes_flash_attempted` is reset to `false`, and a fresh Flash call fires. This is self-healing: no manual SQL intervention is required for contaminated species.

**Manual Cache Invalidation**: For one-off fixes, cross-order (or cross-kingdom) lookalikes cached before the automatic detection was introduced can still be cleared manually:
```sql
DELETE FROM species_lookalikes
WHERE species_id = (SELECT id FROM species_dictionary WHERE scientific_name = '<scientific_name>');
UPDATE species_dictionary SET similar_species = NULL, lookalikes_flash_attempted = FALSE
WHERE scientific_name = '<scientific_name>';
```
The next `enrich-scan` call will re-run Flash with the order-grounded prompt.

**Migration Path**: If the join table is empty but `similar_species TEXT[]` has legacy name strings (populated by older pipeline versions), they are resolved to the join table at zero token cost before returning.

**Parallel Flash Generation**: If enrichment data is missing, encyclopedic enrichment (`fetchStaticEncyclopedicData`) and similar species generation (`fetchSimilarSpecies`) run concurrently via `Promise.all`. Both use `gemini-2.5-flash` with `temperature: 0.1`. Results are persisted before the response is returned.

### Response Schema

```json
{
  "success": true,
  "data": {
    "habitat_description": "Frequently spotted in milkweed patches, meadows, and open plains.",
    "gbif_taxon_key": 5130978,
    "alternative_common_names": ["Monarch", "Common Tiger"],
    "similar_species": [
      {
        "scientific_name": "Limenitis archippus",
        "common_name": "Viceroy",
        "reference_image_url": "https://inaturalist-open-data.s3.amazonaws.com/...",
        "iucn_red_list_status": "LC"
      },
      {
        "scientific_name": "Danaus gilippus",
        "common_name": "Queen",
        "reference_image_url": "https://inaturalist-open-data.s3.amazonaws.com/...",
        "iucn_red_list_status": null
      }
    ],
    "taxonomy": {
      "kingdom": "Animalia",
      "phylum": "Arthropoda",
      "class": "Insecta",
      "order": "Lepidoptera",
      "family": "Nymphalidae",
      "genus": "Danaus"
    }
  }
}
```

`gbif_taxon_key` is `null` when the species has not yet been matched by GBIF. `similar_species` is `null` when no lookalike data is available. Each entry in the `similar_species` array is sourced from the `species_lookalikes` join table joined to `species_dictionary` — providing `common_name` (English), `reference_image_url`, and `iucn_red_list_status` in a single query.

`alternative_common_names` is `string[] | null` — `null` when GBIF has no English vernacular entries for the species. The enrichment scope serves this field from `species_dictionary.alternative_common_names` on a cache hit. When that column is `null` (covering both pre-V34 cached species and the timing race where a first scan's background ingestion has not yet written to the dictionary), the Edge function calls `fetchGBIFVernacularNames` live to retrieve English vernacular names from the GBIF API and populates the field from the result.

**iOS mapping**: The array is decoded as `[EnrichScanResponse.SimilarSpeciesEntry]` (snake_case Codable DTO in `InferenceEdgeDTOs.swift`) and mapped to the domain `SimilarSpecies` struct (camelCase, in `SpeciesData.swift`). `InferenceEngine.fetchAndApplyEnrichment` then JSON-encodes `[SimilarSpeciesEntry]` via `JSONEncoder` into a `Data` blob and persists it as `LocalScanRecord.lookalikesData` (added in `MerianSchemaV27`) — the primary SwiftData storage for rich lookalike data. The legacy `LocalScanRecord.similarSpecies: [String]?` field is retained as a backwards-compatible fallback for pre-V27 records where `lookalikesData` is nil. `SimilarSpeciesGallery` applies the tier-specific confidence threshold only to decide whether to label the section "POTENTIAL LOOKALIKES" vs "SIMILAR SPECIES" — enrichment data is always persisted regardless of confidence.

**Per-user daily rate limit**: Free-tier users are throttled after 50 `enrich-scan` requests per day (proxy for LLM budget). The tier is resolved via `getTierForUser` from `_shared/tierCache.ts`. When the limit is exceeded the function returns `429 Too Many Requests` before any Gemini call is made. Pro users are exempt.

### Error Responses

| Status | Body | Meaning |
|---|---|---|
| `400` | `{ "error": "Missing required parameters..." }` | `scan_id` or `scientific_name` absent |
| `400` | `{ "error": "AI processing error during enrichment..." }` | Gemini generation failure |
| `429` | `{ "error": "Rate limit exceeded. Try again tomorrow." }` | Free-tier daily quota exceeded |

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
2. **Batch Upserts**: All valid collections are written via a single atomic `.upsert(collectionPayloads)` call, resolving PostgreSQL `TIMESTAMPTZ` and `UUID` types without timing out. **The upsert now throws on database error** rather than logging silently — `upsertCollectionsAndFetchMemberships` propagates the error through `withEdgeHandler` so the iOS client receives `HTTP 500` and can retry rather than treating a failed collection persist as a successful sync.
3. **Centralised Ownership Filter (`filterOwnedCollections`)**: `index.ts` calls `filterOwnedCollections(userId, collections, supabaseAdmin)` before any write proceeds. This function queries the existing `collections` rows for the incoming IDs and removes any whose `user_id` does not match the authenticated user. The pre-filtered, ownership-verified set is then passed to all downstream functions (`upsertCollectionsAndFetchMemberships`, `syncMembershipDelta`, `deleteCollections`) — no downstream function needs to re-implement the ownership check independently. Collection IDs owned by other users are silently dropped.
4. **Delete IDOR Guard**: `deleteCollections` additionally scopes the DELETE query with `.eq("user_id", userId)` as a defence-in-depth layer. `deleteCollections` now throws on database error rather than logging silently, preventing false-success `200` responses when the deletion fails.
5. **Bulk Insertion & Mismatched FK Protection**: Setting up `collection_scans` relationships natively in a single atomic upsert avoids N+1 query timeouts. To prevent PostgreSQL Foreign Key violations from crashing the overarching chunk transaction, the Edge Node dynamically pre-validates all incoming `scan_id` payloads against the core `scans` table. If a user groups a scan while fully offline and the physical cloud `scans` row hasn't populated yet, mapping intelligently bypasses that specific missing scan natively. The pending relationship rests securely offline on the user's iPhone until the next sync pulse.
6. **Array-Bound Diffing Deletes**: Identifies obsolete collections by running `.select()` across the user's DB rows, building a `toDelete` array in memory and passing it to `.delete().in("id", toDelete)`. This avoids `.not("id", "in", "(...)")` string-builder failures.
7. **Strict Upstream Concurrency Latch**: Because `BackgroundTaskWrapper` calls push network traffic simultaneously out-of-order, the iOS client strictly clamps `sync-collections` invocations behind an `isCollectionSyncing` gate. This prevents race conditions where a user creates and immediately deletes a collection leading to the Edge Node executing `.upsert()` AFTER `.delete()`, causing ghost resurrections.

> **Parameter naming**: The `syncMembershipDelta` function parameter names were updated from `validCollections`/`activeIds` to `ownedCollections`/`ownedIds` to reflect that all inputs are pre-ownership-checked by the time they reach that function.

**Critical Kong API Gateway Requirement**:
To allow `sync-collections` to manually parse and extract the JWT using Deno `.headers.get("Authorization")`, the edge function must be explicitly exposed in `supabase/config.toml` with `verify_jwt = false`. If not disabled, Kong dynamically strips the `Authorization` header before it reaches Deno to prevent replay attacks, causing a `401 Unauthorized: Missing Authorization header` response from the Edge Runtime.

---

## Deno `/check-scan-status` Edge Node

Provides a lightweight outbox confirmation endpoint. After the iOS client receives an HTTP 200 from `/identify`, it can poll this endpoint to confirm the scan row actually landed in the `scans` table — mitigating the transactional outbox gap where the 200 is returned before the background `insertScan` has committed.

### Request Payload

```json
{ "scan_id": "<UUID>" }
```

### Response Payload

```json
{ "status": "found" | "not_found" }
```

### Authentication & IDOR

The `Authorization: Bearer` JWT is verified by `withEdgeHandler`. The DB query enforces ownership with a dual `.eq("id", scan_id).eq("user_id", user.id)` constraint — a user cannot probe another user's scan IDs. The query returns only the `id` column; no scan data is transmitted.

### Architecture

Follows the domain-driven module pattern: `index.ts` orchestrates auth and parameter validation; `db.ts` owns the `fetchScanOwnership(scanId, userId, supabaseAdmin): Promise<boolean>` PostgREST call. No `db.ts` writes occur. Errors from `fetchScanOwnership` are caught by `index.ts` and mapped to a structured `logStructuredError` + 500 response.

---

## Deno `/get-filtered-discovery-feed` Edge Node

Fetches the global social feed of public biological captures, excluding the requesting user and any users they have blocked.

### Feed Query Strategy

Block list and feed are fetched in **parallel** via `Promise.all`:

```typescript
const overFetchLimit = limit + Math.max(20, Math.ceil(limit * 0.2));
const [blockedIds, rawFeed] = await Promise.all([
  fetchBlockedUserIds(user.id, supabaseAdmin),
  fetchDiscoveryFeed(user.id, overFetchLimit, supabaseAdmin),
]);
const excludedSet = new Set(blockedIds);
const feedData = rawFeed.filter(s => s.user_id != null && !excludedSet.has(s.user_id)).slice(0, limit);
```

`fetchDiscoveryFeed` excludes only the requesting user at the DB level (`.neq("user_id", selfId)`). Blocked user filtering is applied post-query in TypeScript. To compensate for rows removed by the block filter, the DB query over-fetches by `Math.max(20, 20% of limit)` rows. For the default limit of 20, this fetches up to 40 rows. Block list filtering happens on the fast in-memory `Set`, not in the SQL query — this eliminates a SQL variable-length array parameter that required manual escaping.

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
2. **Revokes auth first** — calls `supabaseAdmin.auth.admin.deleteUser(user.id)` to immediately invalidate the user's JWT before any data mutation. This prevents the user from issuing new API calls during cleanup.
3. Executes the `apply_user_tombstone` PostgreSQL RPC against the authenticated `user.id`. The RPC cascades through `public.scans`, `public.user_blocks`, and `public.flagged_reviews`, removing rows and triggering Cloudflare R2 object purges.
4. Queues storage deletion for background processing.
5. **Partial-failure handling**: If step 3 or 4 throws after auth has already been revoked, a structured error is logged via `logStructuredError` with `event: "safe_delete_partial_failure"` and `action_required: "Manually run apply_user_tombstone RPC"`, and the error is re-thrown so the response is `500 Internal Server Error` rather than a false-success `200 OK`.
6. Returns `200 OK` only when all steps succeed. The iOS client then calls `signOut()`, drops all local SQLite `ModelContext` state via `ScanRepository.purgeAllData()`, and resets to Guest.

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

1. Extracts the verified user identity from the GoTrue JWT via the native `withEdgeHandler` middleware.
2. Extracts `scanId` from the payload and queries `public.scans` using the Service Role.
3. If the scan does not exist (e.g. already purged server-side while offline), returns HTTP 200 so the Swift queue system drops the pending deletion cleanly.
4. Compares the fetched `scan.user_id === user.id`. A mismatch natively returns `403 Forbidden` as an explicit IDOR trap.
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

- Extracts the verified user identity from the GoTrue JWT via the native `withEdgeHandler` middleware.
- Validates `blocked_id` as a well-formed UUID — a non-UUID string is rejected with `HTTP 400` before any database access.
- Upserts the block into `public.user_blocks` using `onConflict: "blocker_id,blocked_id"` with `ignoreDuplicates: true`, making repeated block requests fully idempotent. A second block by the same user returns `200 OK` without inserting a duplicate row or surfacing a constraint error.
- Returns `400 Bad Request` if `blocked_id` matches the calling user's UUID to explicitly enforce the anti-self-blocking mitigation.

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

- Extracts `user.id` from the `withEdgeHandler` middleware.
- Validates `scanId` as a well-formed UUID — a non-UUID string is rejected with `HTTP 400` before any database access.
- Validates `flagReason` against the enum `["Incorrect species", "Inappropriate content", "Bad image quality", "Other"]`. Values outside this set are rejected with `HTTP 400` before any database access.
- Inserts a row tracking the reporter's context into `public.flagged_reviews`.
- Automatically overrides the underlying `public.scans` row, configuring `is_flagged = true` and dynamically stamping the `flagReason` and `userSuggestion` into the `human_intervention_notes` column to prompt Admin Dashboard review.
- Returns `HTTP 200` on success.

---

## Deno `/request-export-dwca` Edge Node

Queues an asynchronous Darwin Core Archive (DwC-A) export. Because zipping thousands of records exceeds 30-second HTTP connection limits, this endpoint merely validates the user and inserts a job into the `export_jobs` PostgreSQL table, returning a `200 OK` instantly so the iOS client can release its thread.

### Request Payload

```json
{
  "includePreciseCoordinates": true,
  "exportScope": "personal" // or "global"
}
```

### Authentication Enforcement

- Extracts user identity from the GoTrue header via `supabaseAdmin.auth.getUser(jwt)`.
- **`exportScope` enum validation**: `exportScope` must be `"personal"` or `"global"`. Any other value (including the former default `"user"`) is rejected with `HTTP 400`. The default when omitted is `"personal"`.
- **`includePreciseCoordinates` type validation**: `includePreciseCoordinates` must be a boolean. A non-boolean value (e.g. a string `"true"`) is rejected with `HTTP 400`.
- **Database Rate Limit**: Queries `export_jobs` to verify the user has not queued an export in the last 24 hours. If they have, returns `429 Too Many Requests`.
- Inserts a row into `export_jobs` with status `pending`, triggering the `pg_net` webhook. The insert is idempotent against concurrent duplicate submissions: a `23505` unique-constraint violation (two requests racing in before either commits) is caught and also returns `429 Too Many Requests`, consistent with the explicit rate-limit path and preventing a `500` error from surfacing to the client.

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
- **DwC-A Global Geoprivacy Leak Prevention**: Enforces strict IUCN Red List and ownership gating during ZIP compilation. Evaluates `canAccessPrecise = include_precise_coordinates && (scan.user_id === user_id)`. For global exports, users receive bounding-box obfuscated coordinates (hardcoded 50km `coordinateUncertaintyInMeters`) for scans they do not own. Crucially, if a species is flagged as protected (`endangered`, `vulnerable`, etc.), the exporter is **always** denied exact coordinates (even for their own captures), and public coordinates are aggressively decimate-rounded down to ~11km tiles to prevent poachers from extracting precise habitats via standard scientific downloads.
- **Async Delivery**: Instead of holding the HTTP response open while zipping gigabytes of images, it uploads the final output to Cloudflare R2 and dispatches the signed expiring download URL to the user's inbox via the **Resend Node SDK**. Updates `export_jobs.status` to `completed`.
- **Stuck-job watchdog**: If the Edge function is killed mid-run (OOM, cold-start restart, edge timeout), the job remains in `'processing'` until the `pg_cron` watchdog (`expire-stuck-export-jobs`) expires it after 30 minutes. The watchdog sets `status = 'failed'` with a descriptive message so users can retry via the iOS client instead of waiting forever.

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
3. Aggregates all R2 `image_storage_urls` across the 500 scans and executes a single, massive batch `.deleteR2Objects([])` command natively against the Cloudflare API to minimize HTTP overhead.
4. Executes the discrete `.delete().in("id", [...])` cascade against PostgreSQL only after successfully purging the R2 remote hashes, preventing orphan binaries.

---

## Deno `/auto-purge-domesticated` Edge Node

A daily cron-job endpoint responsible for removing massive image footprints belonging to free-tier users who have scanned domesticated taxonomy (e.g., pets, houseplants) older than 90 days. It intentionally preserves the database row ID for offline user lifelist functionality, while zeroing out the network footprint. 

### Request Payload
No JSON body is required. The cron trigger issues an empty POST request.

### Authentication Enforcement
- Enforces strict cron authorization via `timingSafeCompare` against a `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` Authorization header. Returns `401` if invalid.
- Blocks accidental `GET` evaluations by validating `req.method === "POST"`.

### Deletion Safety
1. Performs a PostgREST Inner Join `users!inner(...)` to evaluate `users.subscription_tier == "free"`.
2. Queries scans where `ecology_type == 'domesticated'` and `timestamp < 90 days ago` with `.limit(500)`.
3. Aggregates R2 `image_storage_urls` and batches the AWS `DeleteObjects` evaluation in chunks of 500 directly via `deleteR2Objects`, honoring the strict Cloudflare 1,000 Key limit natively.
4. Safely executes `.update({ image_storage_urls: [] })` across the 500 scans to synchronize PostgreSQL natively without destroying the row telemetry context!

---

## Deno `/revenuecat-webhook` Edge Node

Receives POST push events triggered natively from the RevenueCat subscription platform to update Supabase row bounds directly, bypassing the iOS SDK entirely.

### Request Payload
Receives a raw RevenueCat Webhook structure wrapper targeting an internal JSON `.event`.

### Authentication Enforcement
- Reads `REVENUECAT_WEBHOOK_SECRET` environment bindings locally.
- Authenticates the RevenueCat push via `timingSafeCompare` comparing the `Authorization: Bearer` against the secret boundary.
- **`app_user_id` UUID validation**: After webhook auth, `event.app_user_id` is validated against a UUID regex (`/^[0-9a-f]{8}-...-[0-9a-f]{12}$/i`) before any database access. A falsy `!userId` check alone is insufficient — RevenueCat sends anonymous IDs like `$RCAnonymousID:xxx` for un-linked purchases, which would pass the truthy check but fail UUID constraints in the DB layer with a confusing 500. Anonymous-ID events are rejected early with `HTTP 400` and a warning log.

### Migration Mechanics
- Upgrades (`INITIAL_PURCHASE`, `RENEWAL`, `UNCANCELLATION`) convert `subscription_tier` to `pro`.
- Downgrades (`EXPIRATION`) revert the tier to `free`.
- **R2 Storage Relocation**: Migrates files between the `free` and `pro` prefix buckets in Cloudflare R2. To prevent execution timeouts on users with thousands of photos, the script iterates through SQL constraints utilizing a `size: 1000` chunk-by-chunk lookup bound in an independent `EdgeRuntime.waitUntil` detached thread.
- Defends against IDOR manipulations silently: If a user attempts to execute an R2 copy belonging to an external User UUID through manipulated array data, the proxy blocks the migration sequence logic and reports a silent violation to Edge telemetry logs.
