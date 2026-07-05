# API Contracts and Network Mappings

Merian operates decoupled. The iOS application exclusively hits Supabase Edge
Functions, abstracting its networking away from 3rd-party providers like Google
Gemini.

## Deno `/generate-upload-urls` Edge Node

To fetch cryptographic keys for direct-to-Cloudflare uploads, the client sends a
structured media manifest. The cross-language contract lives in
`docs/contracts/media-staging-upload-manifest.json`; Swift and Deno tests both
load that file so limits and allowed content types cannot drift silently.

### Request Payload

```json
{
  "user_id": "Supabase Auth UUID linking RevenueCat and PostHog",
  "files": [
    {
      "fileName": "scan-id_photo_1.webp",
      "mediaKind": "image",
      "contentType": "image/webp",
      "sizeBytes": 124000,
      "clientScanId": "00000000-0000-0000-0000-000000000001",
      "mediaRole": "display"
    },
    {
      "fileName": "scan-id_audio_1.wav",
      "mediaKind": "audio",
      "contentType": "audio/wav",
      "sizeBytes": 42000,
      "clientScanId": "00000000-0000-0000-0000-000000000001",
      "mediaRole": "audio"
    }
  ]
}
```

The server extracts the verified user identity from the `Authorization` Header
JWT (`supabaseAdmin.auth.getUser()`), ignoring any `user_id` value in the
request body. To prevent array-abuse memory locking on the Edge Node, the
endpoint strictly requires exactly 1 to 5 `files`, with at most 2 audio files.
The main app queue builds this manifest through `MediaStagingContract` and must
apply the same filename sanitization as the Edge function before upload URL
generation. For scan uploads, each structured entry may also include
`clientScanId` and `mediaRole`; when present, `/generate-upload-urls` creates a
server-owned staged `scan_media_assets` row before returning the signed URL.
Image roles may be `display`, `thumbnail`, or `inference_frame`; video uses
`playback`; audio uses `audio`. The Edge parser rejects unsanitized filenames,
invalid `mediaKind` values, invalid role/kind combinations,
content-type/kind mismatches, and oversized media before signing. Structured
manifests require `sizeBytes`; the legacy `fileNames` array remains accepted for
older clients but is compatibility-only and cannot express byte budgets or media
asset sessions. Pre-signed `PUT` URLs include an `X-Amz-Expires=86400`
parameter (24 hours). This extended window
gives iOS `BackgroundTasks` flexibility to transmit overnight, subject to OS
memory, thermal, and Wi-Fi conditions, without hitting 403 errors.

The Edge function uses the `fileName` parameter from the JSON body (after
applying basic sanitization to prevent path traversal vectors) rather than
generating random internal UUIDs. This guarantees that the pre-signed S3
`objectKey` will deterministically match the paths requested by the iOS client
during subsequent offline inference triggers.

```json
{
  "urls": [
    {
      "fileName": "photo_1.webp",
      "signedUrl": "https://<R2_URL>?X-Amz-Signature=...",
      "objectKey": "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_photo_1.webp",
      "mediaAssetId": "scan_media_assets row UUID",
      "mediaSessionId": "upload session UUID"
    }
  ]
}
```

`mediaAssetId` and `mediaSessionId` are omitted for non-scan uploads, such as
profile avatars, and for legacy `fileNames` clients. During
`identify-multimodal` finalization, promoted image/video staging keys update the
matching staged rows to `promoted` and link them to the completed scan. Consumed
audio staging keys become `deleted`; moderation, promotion, or scan-insert
failures mark still-staged rows as `failed`. The returned `mediaSessionId`
values also let ingestion recover the exact upload sessions for the staged
object keys; those session ids participate in the `scan_ingestion_jobs`
`manifest_checksum`, giving retries and repair workers a stable server-side
description of the requested media set without storing media bytes.

> The pre-signed URL is generated with the exact `contentType` from the
> structured manifest. The iOS `URLRequest` must send the same `Content-Type`
> header on the `PUT`, or Cloudflare R2 will reject the upload with
> `403 SignatureDoesNotMatch`.

---

## Deno `/reconcile-scan-media-assets` Internal Worker

This endpoint is not called by iOS. It is invoked hourly by pg_cron with
`Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}`. Supabase gateway JWT
verification is disabled so pg_net can reach the function, and the function
performs service-role key validation internally.

Optional request payload:

```json
{
  "limit": 100,
  "repairAfterMinutes": 15,
  "abandonAfterHours": 36,
  "dryRun": false
}
```

Response payload:

```json
{
  "success": true,
  "scanned": 3,
  "promoted": 1,
  "repairedVideoScans": 1,
  "deletedStagingObjects": 2,
  "failedAssets": 1,
  "missingObjects": 0,
  "stillPending": 1,
  "errors": []
}
```

The worker only reconciles media lifecycle state. It can repair an existing scan
that has a surviving staged playback video by promoting the video, updating
`video_storage_urls`, rebuilding `captured_media`, and refreshing ready
`scan_media_assets` rows. It can also delete abandoned staging objects and mark
their staged rows failed. Before treating an orphan as abandoned, it checks the
matching `scan_ingestion_jobs` row: active leases and future retry windows keep
the media pending, repaired scans mark the job complete when required video
media is present, and TTL-abandoned media marks the job `failed_terminal`.
Sanitized `scan_ingestion_intents` rows preserve staged-media replay metadata for
operations and future tooling, but this worker does not replay AI inference for
scans that never created a cloud scan row; those remain the responsibility of
the iOS offline queue retry path unless a dedicated server replay worker is
added later.

---

## Deno `/scan-media-health` Internal Status

Read-only service-role endpoint for media durability observability. Supabase
gateway JWT verification is disabled for automation reachability, and the
function validates `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` or an
equivalent service-role `apikey` before querying.

Optional request payload:

```json
{
  "limit": 25,
  "stuckAfterMinutes": 20,
  "staleAssetAfterMinutes": 15,
  "recentScanLimit": 250
}
```

Response payload:

```json
{
  "success": true,
  "generated_at": "2026-07-05T15:00:00.000Z",
  "status": "warning",
  "thresholds": {
    "stuck_after_minutes": 20,
    "stale_asset_after_minutes": 15
  },
  "counts": {
    "ingestion_jobs_checked": 3,
    "stale_capture_upload_assets": 1,
    "failed_assets": 0,
    "recent_scans_checked": 250,
    "ready_video_assets_checked": 2,
    "explore_video_rows_checked": 10,
    "reconciliation_runs_checked": 5,
    "ingestion_intents_checked": 3,
    "issues": 1,
    "critical_issues": 0,
    "warning_issues": 1
  },
  "asset_breakdown": {
    "stale_capture_upload_assets": [
      { "kind": "image", "role": "display", "count": 1 }
    ],
    "failed_assets": []
  },
  "issues": [
    {
      "code": "stale_capture_upload_assets",
      "severity": "warning",
      "message": "Capture-upload media assets remain staged past the reconciliation window.",
      "count": 1,
      "sample": []
    }
  ]
}
```

The status can be `ok`, `warning`, or `critical`. Critical issues indicate a
durability invariant is already broken or a server-owned ingestion job is stuck
past its lease. Warning issues indicate retry/repair work may still complete but
should be monitored, including missing or non-resumable ingestion intents for
retryable work. The endpoint does not repair media; writers remain
`identify-multimodal`, `reconcile-scan-media-assets`, and the iOS offline queue.
The scheduled **Scan Media Health Monitor** workflow calls this endpoint every
30 minutes, stores JSON/Markdown artifacts, and fails only on `critical` by
default.

---

## Deno `/update-public-avatar` Edge Node

Promotes one user-owned staged R2 image into the durable public avatar prefix.
The iOS Profile tab first requests a signed URL from `/generate-upload-urls`,
uploads the prepared square avatar to `staging/{userId}/...`, then calls this
endpoint.

### Request Payload

```json
{
  "r2_object_key": "staging/a1b2c3d4-e5f6-7890-abcd-ef1234567890/avatar_11111111-1111-4111-8111-111111111111.webp",
  "mime_type": "image/webp"
}
```

Rules:

- `r2_object_key` must be a string owned by the authenticated user under
  `staging/{user.id}/...`.
- Path traversal is rejected with `400`.
- Wrong-user staging keys are rejected with `403`.
- `mime_type` must be `image/webp` or `image/jpeg`, and it must also be in the
  staged image MIME allowlist.

### Response Payload

```json
{
  "avatar_url": "https://media.merian.app/avatars/a1b2c3d4-e5f6-7890-abcd-ef1234567890/22222222-2222-4222-8222-222222222222.webp"
}
```

The function copies the staged object to `avatars/{userId}/{uuid}.webp` or
`avatars/{userId}/{uuid}.jpg`, updates `users.custom_avatar_url`,
`users.custom_avatar_updated_at`, and `users.public_avatar_url`, and deletes
only the previous same-user custom avatar object. OAuth avatars remain fallback
metadata when no custom avatar exists.

---

## Community Identification Edge Nodes

Community Identification is the Ask the Community queue under Explore. It is
backed by `taxon_nodes`, `explore_community_requests`, and
`explore_identifications`, with versioned taxonomy, queued consensus jobs, and
the `explore_observation_projection` public feed boundary.

### `/request-community-identification`

Creates or reopens an Explore post as a `needs_id` community request. The
request is gated to the authenticated user's biological scan with shareable
media. It accepts `scan_id`, optional `note`, optional `location_sharing`
(`open`, `obscured`, `private`), optional `species_common_name`, and optional
`restored_object_keys` for media repair.

The endpoint intentionally returns `404 { "error": "Scan not found." }` when
`public.scans` has no row for the authenticated user. The iOS Insight client
handles that specific error by inserting a minimal owned `scans` row from the
local `LocalScanRecord`, resolving the server `species_dictionary.id` by
scientific name, uploading local images to staging, and retrying with
`restored_object_keys`. This is the recovery path for scans where inference
returned to the device but background scan ingestion failed.

Before inspecting or returning an existing active request, the endpoint repairs
any Community request on that `scan_id` whose `requested_by` no longer matches
the authenticated scan owner. This covers legacy ghost-account ownership drift
and keeps the Identify Yours filter, owner-only actions, and duplicate-request
guard tied to the current account.

The response envelope is:

```json
{
  "success": true,
  "data": {
    "id": "request uuid",
    "post_id": "explore post uuid",
    "scan_id": "scan uuid",
    "status": "needs_id",
    "initial_taxon_node_id": "taxon uuid",
    "taxonomy_version_id": "taxonomy version uuid"
  }
}
```

### `/get-community-identification-feed`

Returns unresolved `needs_id` requests for the Identify tab. Optional `scope`
accepts `all` or `mine` and defaults to `all`; `mine` returns unresolved
requests created by the authenticated viewer. Optional `latitude` and
`longitude` sort local public-coordinate requests first, followed by recent
requests. Cursor fields are `before_requested_at` and `before_request_id`. Rows
may include `taxonomy_version_id`, `projection_state`, and
`consensus_processing_state`.

### `/get-community-identification-detail`

Returns one visible request with author identity, current consensus state,
privacy-safe location fields, and the full identification timeline. Tombstoned
scans, unshared posts, blocked relationships, and shadowbanned authors are
filtered out server-side. Identification timeline rows include a computed
`role_label` such as `supporting`, `leading`, `maverick`, or `withdrawn` for
internal consensus/audit behavior; clients should not expose these labels as
user-facing copy. The response also includes additive `suggested_taxa` for the
Suggest ID sheet and the detail header card. The top-level `inference_tier`
mirrors `scans.inference_tier` so clients can label the card as Merian Pro or
Merian Flash; missing or unknown tiers should display as Flash. The first
suggestion is the request's `ai_initial` taxon, hydrated from the backing scan's
`ai_confidence_score` and `ai_reasoning` so clients can frame it as Merian's
starting identification without borrowing human consensus or alternative
candidate copy. Confidence is optional and should render as compact card
metadata only when present; reasoning remains collapsed behind the AI reasoning
row. Additional `ai_candidate` suggestions come from resolvable
`scans.candidates` entries in the request's pinned taxonomy version. Suggested
taxa use the same taxon fields as search results and may include
`suggestion_source`, `confidence_score`, and `distinguishing_feature`; for
`ai_initial`, `distinguishing_feature` carries the scan's primary AI reasoning.

Example `suggested_taxa` shape:

```json
[
  {
    "taxon_id": "taxon uuid",
    "taxonomy_version_id": "taxonomy version uuid",
    "common_name": "Sweet Orange",
    "scientific_name": "Citrus sinensis",
    "rank": "species",
    "path": "plantae.tracheophyta.angiosperms.sapindales.rutaceae.citrus.citrus_sinensis",
    "species_id": "species uuid",
    "suggestion_source": "ai_initial",
    "confidence_score": 0.82,
    "distinguishing_feature": "The glossy evergreen leaves and citrus fruit shape support Sweet Orange."
  },
  {
    "taxon_id": "alternative taxon uuid",
    "taxonomy_version_id": "taxonomy version uuid",
    "common_name": "Mandarin Orange",
    "scientific_name": "Citrus reticulata",
    "rank": "species",
    "path": "plantae.tracheophyta.angiosperms.sapindales.rutaceae.citrus.citrus_reticulata",
    "species_id": "alternative species uuid",
    "suggestion_source": "ai_candidate",
    "confidence_score": 0.61,
    "distinguishing_feature": "Similar foliage, but the visible fruit proportions are less clearly mandarin-like."
  }
]
```

### `/update-community-identification-request`

Updates the authenticated request owner’s editable request info. Accepts
`request_id`, optional `note`, and required `location_sharing` (`open`,
`obscured`, `private`). The backend only updates non-withdrawn requests owned by
the current user and also updates the backing Explore post’s `location_sharing`.

### `/search-community-taxa`

Searches `taxon_nodes` through `taxon_names` by scientific name, common name, or
synonym. Local index search runs first. If results are thin and the query is at
least three characters, the Edge function asks GBIF for additional suggestions,
caches them into the active Community Taxonomy Index, and searches again. GBIF
failures do not block local results. Accepts optional `taxonomy_version_id`;
request detail searches should pass the request's pinned version.

Rows return `taxon_id`, `taxonomy_version_id`, `common_name`, `scientific_name`,
`rank`, `path`, `species_id`, `gbif_taxon_key`, `source`, `is_in_dictionary`,
`accepted_gbif_taxon_key`, and `taxonomic_status`. `species_id = null` is valid
for GBIF-only taxa that have not been materialized into Merian's enriched
Dictionary yet. The Swift client uses `path` to decide whether a selected ID is
exact, descendant, ancestor, or conflicting before presenting any disagreement
sheet.

### `/submit-community-identification`

Accepts `request_id`, `taxon_id`, optional `disagreement_mode`, optional
`reasoning`, and optional `is_genus_best_possible`. The backend validates that
the taxon belongs to the request's pinned taxonomy version, withdraws the
current user's previous active ID, inserts a new audit row, enqueues a consensus
job, and attempts one immediate best-effort processing pass. Consensus rules are
unchanged: active human IDs only, at least two identifications, score strictly
greater than `2 / 3`, sibling/unrelated votes counting against a candidate, and
coarse ancestor IDs staying neutral unless explicitly marked as disagreement.
Species consensus resolves immediately; genus consensus resolves only when at
least one exact genus ID marks genus as best practical.

### `/withdraw-community-identification` and `/restore-community-identification`

Accept `identification_id` and mutate only the authenticated user's own rows.
Withdraw and restore keep the audit trail intact, enqueue consensus work, and
attempt immediate best-effort processing.

### `/refresh-taxonomy-nodes`

Internal service-role endpoint. Rebuilds a draft taxonomy version from
`species_dictionary`, seeds `taxon_names`, activates the version atomically, and
retires the previous Merian dictionary version. Optional body:

```json
{ "source_revision": "species-dictionary-2026-06-20" }
```

### `/sync-community-taxonomy-index`

Internal service-role endpoint. Imports bounded GBIF taxonomy pages into the
active Community Taxonomy Index without materializing `species_dictionary` rows.
v1 supports only the `birds` target, which maps to GBIF taxon key `212` (`Aves`)
and imports accepted species through GBIF species search.

Optional body:

```json
{
  "target": "birds",
  "offset": 0,
  "limit": 50,
  "page_count": 1,
  "dry_run": false,
  "refresh_coverage": true,
  "retry": false
}
```

`limit` is capped at `200` and `page_count` is capped at `20`. If `offset` is
omitted, the worker continues from
`taxonomy_coverage_targets.next_import_offset`; explicit offsets remain
available for manual recovery. `retry = true` with no explicit offset replays
the last failed offset when present, otherwise the last successfully imported
page offset. Each successful page calls `upsert_gbif_community_taxa(...)`,
annotates the created `taxonomy_import_runs` row as
`scope = "gbif_bounded_birds"`, and suppresses per-page coverage recomputation.
After the run imports at least one row, the worker refreshes coverage once when
`refresh_coverage = true`, then updates the target cursor fields.
`dry_run = true` fetches and normalizes the GBIF page without writing taxonomy
rows or advancing the cursor.

### `/process-community-consensus-jobs`

Internal service-role endpoint. Processes pending or retryable failed
`community_consensus_jobs`. Optional body:

```json
{ "limit": 25 }
```

---

## Deno `/identify` Edge Node

### The JSON Request Payload (From Swift `OfflineQueueManager`)

When `NWPathMonitor` goes green, iOS POSTs this payload to Supabase. The server
enforces that all paths within `r2ObjectKeys` begin with `staging/${user.id}/`
and rejects `../` traversal attempts with `HTTP 400`.

The endpoint rejects media JSON requests whose declared `Content-Length` exceeds
the shared `/identify` body ceiling before parsing the body. The body is then
parsed through `_shared/mediaBudgets.ts` using `readRequestJsonWithinBudget`,
making the streaming byte counter authoritative for chunked or missing-length
requests. Inline `imageBase64s` are validated against the shared aggregate
base64 budget; staged `r2ObjectKeys` are validated through
`_shared/identify/media.ts` and R2 bytes are consumed with capped stream readers
before any full response buffer is assembled.

> **Important IDOR Constraint:** The `user.id` resolved by the Deno Edge
> Function from the Supabase JWT is always a **lowercase** Postgres UUID format.
> Swift's `UUID().uuidString` evaluates to uppercase by default. Therefore, the
> iOS client must explicitly lowercase any user UUID injected into
> `r2ObjectKeys` payloads; otherwise, the case-sensitive string matching
> (`!r2ObjectKey.startsWith`) will fail the IDOR check and return a
> `403 Forbidden`.

```json
{
  "r2ObjectKeys": [
    "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_filename_1.webp",
    "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_filename_2.webp"
  ],
  "imageBase64s": [
    "<base64 encoded string array for instant processing within the shared aggregate budget>"
  ],
  "user_id": "Supabase Auth UUID linking via GoTrue Session",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "depthScaleText": "1.2 meters",
  "semanticLocation": "Zilker Park",
  "publicLocationLabel": "Austin, Texas",
  "geoprivacy": "obscured",
  "weatherCondition": "Sunny",
  "weatherTemperatureF": 72.5,
  "deviceLocale": "en",
  "deviceTimeZone": "America/Los_Angeles",
  "deviceRegion": "US",
  "currentMonth": 3,
  "timeOfDay": "2:00 PM",
  "timestamp": "2026-03-21T09:46:03.000Z",
  "zoomFactor": 2,
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

`description` is an optional plain-text string generated client-side by
`ObservationContext.serialized()` — a pre-rendered prompt summary of the user's
structured observation. It is appended to the Gemini context string at the edge
function to ground identification before the vision model runs.
`observation_context` is the full structured JSON object matching the iOS
`ObservationContext` model; it is persisted server-side as
`public.scans.user_observation_context` (JSONB) and lands in the local
mixed-media scan representation via `LocalScanRecord.observationContextsJSON`,
the scalar `capturedMediaJSON` timeline, and the V41 `capturedMediaEntries`
relationship mirror. Both fields are `null` for image-only scans. The edge
function accepts an array guard (`!Array.isArray(observation_context)`) before
writing to prevent an accidental array submission from being persisted as
malformed JSONB.

`zoomFactor` is sent when the capture used a non-default camera zoom. The Edge
function persists it to `public.scans.zoom_factor` for owner-facing context such
as Insight scan information and Field chat; it is omitted for 1x captures and
non-visual submissions.

`currentMonth` and `timeOfDay` are derived from the image's own capture date
(`telemetry.timestamp`) when available — not always from the current wall clock.
For gallery photos with a valid EXIF date, this ensures Gemini receives the
correct season and light context for the original photo (e.g., an October photo
scanned in April sends `Month: 10`, not `Month: 4`). Falls back to current
date/time for live captures and gallery photos with no EXIF.

`timestamp` is omitted (null) for gallery photos with no EXIF date rather than
sending the current submission time. The server defaults `scans.timestamp` to
`now()` in that case, which honestly represents when the scan was submitted.
`deviceTimeZone` (IANA identifier, e.g. `"America/Los_Angeles"`) and
`deviceRegion` (ISO 3166-1, e.g. `"US"`) are permission-free geographic signals
sent as fallback context when GPS is not authorised. The Edge function injects
them into the Gemini context string as `TZ:` and `Region:` tokens alongside
`Locale:`, `Month:`, and `Time:` — grounding the model's regional species priors
without requiring location permission. `deviceTimeZone` is also persisted to
`scans.device_time_zone` for timezone-aware public profile streaks and heatmaps;
`deviceRegion` remains inference-context only.

`geoprivacy` is optional for backward compatibility. Valid values are `open`,
`obscured`, and `private`. When absent or invalid, the Edge insert helper reads
`users.default_geoprivacy`. Private scans may still persist exact owner-owned
telemetry, but public projections are scrubbed: public coordinates,
`coordinate_uncertainty_in_meters`, and `public_location_label` are cleared by
insert helpers and database triggers. Current iOS clients omit
`publicLocationLabel` when `geoprivacy == "private"` and send sanitized labels
for open/obscured scans.

### The JSON Response Schema (From Gemini Back to Swift)

To optimize API expenditures, the `identify` Deno Edge node uses two strategies:

- **Model Routing**: The vision identification call routes effective Pro users
  to `gemini-2.5-pro` (maximum depth for rare species, fossils, subspecies, and
  cultivars) and effective free users to `gemini-2.5-flash` (2–3× lower
  latency). Effective Pro includes paid subscribers and dynamic 7-day trial
  users. All text-only calls — `fetchStaticEncyclopedicData`,
  `fetchDiagnosticComparison`, and all `enrich-scan` generation — always use
  `gemini-2.5-flash` regardless of tier. `gemini-2.5-pro` is exclusively for the
  multimodal vision identification step. Tier is resolved via
  `resolveTierForUser`, which performs a lightweight
  `SELECT subscription_tier, created_at, subscription_expires_at` on cache miss
  and returns `effective_tier`, `plan`, `subscription_tier`, and `trial_active`
  for telemetry. Active timed passes resolve as paid Pro; stale timed Pro rows
  resolve as free until the hourly expiry worker clears the row. A module-scope
  `_tierCache` (5-minute TTL) eliminates the DB round-trip on repeat scans
  within a warm isolate. Both tiers use the `merianResponseSchema` constraint to
  protect SQLite UI logic.
- **Dynamic Token Truncation (Non-biological targets)**: When processing
  non-biological subjects, the Deno node removes `taxonomy`, `insight_data`, and
  `ecology_type` from the `required: []` array and passes
  `is_biological_subject: false`. The Swift layer maps the absent fields to
  native Optionals. **Geology Bypass**: Gemini's prompt explicitly instructs the
  LLM to output `scientific_name` and `common_name` for geological subjects
  (e.g. rocks) despite being non-biological. This surfaces rocks cleanly in the
  iOS layer under `isBiological: false` (routing them out of the main dictionary
  and into the 30-day auto-purge graveyard) without reverting to generic
  "Unknown Subject" names.

If an AI Agent mutates any key mapping below, it MUST modify both the `index.ts`
Deno code AND the `MerianNetworkClient.swift` Codable struct to simultaneously
support both the Pro schema and Free text-prompt shapes without causing
`JSONDecoder()` failures.

> **Image format**: All images in this pipeline are encoded as lossy **WebP**
> (`image/webp`). The `inlineData.mimeType` field passed to the Gemini SDK in
> `index.ts` must always be `"image/webp"`. Gemini 2.5 Flash and Pro both accept
> `image/webp` natively. If this value is changed to `image/jpeg` while the
> actual bytes are WebP, Gemini will reject or misinterpret the payload.

**`common_name` source**: On **Cache Miss** (first-ever scan of a species),
`common_name` is taken directly from the Gemini vision model output. On **Cache
Hit**, `index.ts` overrides the Gemini-supplied `common_name` with the canonical
`species_dictionary.common_names.en` value so repeat scans of the same species
always show a consistent display name regardless of which Gemini response
generated it. The Swift decoding layer applies `.capitalized` on rendering for
display consistency. For geological targets, it relies wholly on the Gemini
output (no cache override applies).

**`pet_identification` source**: Dog and cat scans may include a separate
display object when the primary species is `Canis lupus familiaris` or
`Felis catus`. This object is not taxonomy. It is sanitized after Gemini
generation and dropped when the label is generic, below `0.70` confidence, or
attached to any non-dog/cat taxon. Dog labels may be a breed or visible mix; cat
labels prefer visible coat pattern or body type unless a true breed is visually
supported. Clients can use the label for Insight, search, sharing, and Explore
display, while `common_name` and `scientific_name` remain authoritative.

**`is_new_to_merian_dictionary` source**: The biological identify routes
(`/identify`, `/identify-multimodal`, `/identify-describe`, and `/audio-spec`)
return this boolean in the client payload. It is `true` only when the scan is a
biological subject and the initial `species_dictionary` lookup found no existing
row for the normalized scientific name. iOS decodes the field as
`SpeciesData.isNewToMerianDictionary` and uses it to show the bottom in-app
`New to Merian` milestone notification. Do not infer global dictionary novelty
from missing enrichment fields such as `alternative_common_names`; cache gaps,
GBIF gaps, and partial rows are not milestone signals. Existing dictionary rows
with incomplete taxonomy/enrichment are still treated as not new to Merian.

**Critical Edge Limitation (Gemini 2.5):** The model returns `400 Bad Request`
when enum fields include descriptive strings. `ecology_type` must be formatted
as a structural JSON `enum: ["wild", "urban", "domesticated", "unknown"]`
constraint in the Deno schema.

```json
{
  "scan_id": "Generated via crypto.randomUUID() on Deno Edge",
  "is_biological_subject": true,
  "is_live_capture": true,
  "is_new_to_merian_dictionary": false,
  "ecology_type": "wild",
  "scientific_name": "Danaus plexippus",
  "common_name": "Monarch Butterfly",
  "pet_identification": null,
  "confidence_score": 0.98,
  "blur_score": 0.1,
  "is_invasive": false,
  "invasive_status_region": "Central Texas",
  "invasive_rationale": "The original AI assessment did not flag this species as invasive for the scan region.",
  "invasive_confidence": 0.78,
  "colors": ["orange", "black", "white"],
  "estimated_size_cm": 15.2,
  "life_stage": "adult",
  "reproductive_condition": "not_applicable",
  "sex": "female",
  "sex_confidence": 0.84,
  "sex_evidence": "dimorphic wing pattern",
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

  "// Present when confidence_score < diagnosticTrigger (0.99 both Flash and Pro — intentionally above strong threshold so Strong match scans can still persist candidates as an escape hatch). Server strips to null at or above 0.99. Client display is separately gated by CandidateReviewVisibilityPolicy. See _shared/identify/thresholds.ts.": "",
  "candidates": [
    {
      "scientific_name": "Limenitis archippus",
      "common_name": "Viceroy",
      "confidence_score": 0.71,
      "distinguishing_feature": "Hindwing black postmedian band broader and more irregular than Monarch"
    },
    {
      "scientific_name": "Danaus gilippus",
      "common_name": "Queen",
      "confidence_score": 0.58,
      "distinguishing_feature": "Forewing lacks white spots in the black apex band"
    }
  ]
}
```

> **Vision schema lean principle**: The vision model response (`identify`) is
> optimised strictly for identification and ecosystem measurement.
> Data-as-a-Service fields (`estimated_size_cm`, `life_stage`,
> `reproductive_condition`, `sex`, `sex_confidence`, `sex_evidence`,
> `individual_count`, `ecological_interactions`) are fully generated on the
> primary pass avoiding secondary inference loops. `extracted_visual_traits`
> executes a Micro-CoT pass before taxonomic grouping to anchor the model to
> reality and avoid visual pareidolia. `insight_data.ai_reasoning` is always
> present for biological subjects because it is the Gemini vision model's
> per-scan reasoning about the specific photo submitted. LLM field caps are
> enforced in `index.ts` after scientific name sanitization: `colors`,
> `extracted_visual_traits`, and `ecological_interactions` are each capped at 10
> items; `ai_reasoning` is truncated to 2000 characters; `individual_count` is
> validated as a positive integer <= 99999; client-supplied `estimated_size_cm`
> is validated as a positive finite number <= 50000; and `candidates` is capped
> at 5 items before `payloadReadyForClient` is built. GPS coordinates are
> range-checked and out-of-range values are sanitized to `null` rather than
> aborting identification. `taxonomy`, `iucn_red_list_status`, `gbif_taxon_key`,
> `species_insights`, and `alternative_common_names` are species-dictionary
> cache fields, not scan-specific model output. `similar_species` is never
> included in the `identify` response; it is generated asynchronously by
> `/enrich-scan`, and iOS renders validated entries with the stable "Similar
> species" label. `hazard_type` inside `insight_data` comes from
> `species_dictionary` on Cache Hit; on Cache Miss the live response defaults to
> `"none"` until later enrichment fills species-level hazard metadata.
> `pet_identification` is optional and nullable. For a confident dog scan, the
> value may look like
> `{"species_group":"dog","label":"Australian Cattle Dog mix","label_type":"breed_mix","confidence_score":0.82,"evidence":["blue-roan ticking","black saddle patch","compact herding-dog build"]}`.
> The stored species would still be `Domestic Dog` / `Canis lupus familiaris`.
>
> `candidates` is required in `merianResponseSchema`; `identify` strips it to
> `null` only when `confidence_score >= diagnosticTrigger` (`0.99` for both
> Flash and Pro), preserving candidates for Possible, Weak, and Strong scans
> below that near-certain threshold. Candidates are scan-specific and persist to
> `public.scans.candidates` plus `LocalScanRecord.candidatesData`, while client
> display is separately gated by `CandidateReviewVisibilityPolicy`.

### Background Ingestion & Media Moderation

After the HTTP `200 OK` response is returned to the client, `runBackground`
schedules asynchronous ingestion via `EdgeRuntime.waitUntil`. This background
task handles:

1. **Ghost user upsert** — ensures the `users` table row exists before the
   `scans` FK insert
2. **Content moderation** (`_shared/identify/moderation.ts`) — evaluates Gemini
   safety ratings and promotes media from staging to public storage
3. **Species dictionary enrichment** (Cache Miss only) — calls
   `fetchExternalEnrichment` for Wikipedia/GBIF data
4. **`insertScan`** — writes the final scan row to `public.scans`, including
   sanitized `pet_identification` when present
5. **Group tags** — fires a background Flash call to populate
   `species_dictionary.group_tags` for first-time species

**Media promotion**: Safe image media is moved from
`staging/{userId}/{filename}` to `public_uploads/{tier}/{userId}/{filename}`
inside Cloudflare R2, and the CDN URL
(`https://media.merian.app/public_uploads/...`) is stored in
`scans.image_storage_urls`. For the `imageBase64s` path, the bytes are uploaded
directly to the public destination without a staging step. Safe video media is
moderated through five sampled frames, then the staged upload-bounded playback
`.mp4` is promoted separately and persisted in `scans.video_storage_urls`. Multimodal
inserts also write `scans.captured_media`, a canonical ordered media timeline
that attaches video playback URLs and poster thumbnails together; this prevents
sampled video inference frames from hydrating as standalone Insight carousel
images. Ready display/playback scan-media asset rows are refreshed by the
database trigger plus a best-effort Edge refresh call, so server-side
composer/status reads can prefer lifecycle media rows before falling back to
compatibility arrays. Any image promotion failure aborts the entire batch and
immediately rolls
back any already-promoted public objects from that same batch before returning
`ERROR`; scans are not inserted with partial image arrays. Video promotion failure
is also a durability failure for video captures: the edge cleans up promoted
objects/staging where possible and does not insert a frame-only scan row.

**Moderation failure handling**: If Gemini's `finishReason === "SAFETY"` or any
`safetyRating.probability` is `"MEDIUM"` or `"HIGH"`, the staging object is
deleted, `users.abuse_strikes` is incremented, and the scan is not inserted. At
3+ strikes `users.is_shadowbanned` is set to `true` and all future ingestion
silently halts. See
[Safety & Moderation](../development-guides/10-safety-and-moderation.md) for
full details.

**R2 rollback**: If `insertScan` throws after media has already been promoted to
public storage, the public objects are deleted via `deleteR2Object` to prevent
orphaned CDN assets. The same rollback fires if a mid-loop R2 upload failure
throws during the `imageBase64s` promotion pass.

### Error Responses

| Status | Body                                                                            | Meaning                                                                                      |
| ------ | ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `400`  | `{ "error": "Bad Request: Path traversal detected." }`                          | `r2ObjectKeys` contains a `../` traversal attempt                                            |
| `400`  | `{ "error": "Forbidden: r2ObjectKey does not belong to the requesting user." }` | IDOR — key does not belong to the authenticated user                                         |
| `400`  | `{ "error": "AI processing error. Please try again." }`                         | Permanent content policy failure (`finishReason` is `SAFETY` or `PROHIBITED_CONTENT`)        |
| `413`  | `{ "error": "Payload Too Large: Combined images exceed 5MB limit." }`           | Combined image payload exceeds 5 MB                                                          |
| `422`  | `{ "error": "Processing Error: Malformed AI response." }`                       | Gemini returned output that could not be parsed                                              |
| `422`  | `{ "error": "Processing Error: Invalid AI response format." }`                  | Gemini returned output in an unexpected format                                               |
| `503`  | `{ "error": "AI processing error. Please try again." }`                         | Transient Gemini failure (API error, rate limit, timeout, non-SAFETY non-STOP finish reason) |

`400` on a content policy failure is intentional — the iOS `OfflineQueueManager`
treats `400` as a permanent failure and marks the queued row as needing user
attention rather than silently deleting media. All other Gemini errors return
`503` so the offline queue retries with persisted `queueNextRetryAt` /
`OfflineJobRecord.nextRunAt` metadata. `422` is also excluded from recoverable
codes and is treated as a terminal validation failure.

## The Standardized JSON Return Payload (From Supabase to Swift)

To reduce latency, the `/identify` Edge Function generates `scan_id` locally via
`crypto.randomUUID()` and returns the `data` payload to iOS as soon as Gemini
inference completes. All PostgreSQL insertions, R2 uploads, and parallel API
calls (GBIF/Wikipedia) run asynchronously behind `EdgeRuntime.waitUntil`.

### Gemini Parsing and Error Mitigation

To prevent ReDoS from hallucinated markdown payloads, the endpoint parses raw
Gemini output using a `substring(indexOf)` approach rather than unbounded regex.
If `JSON.parse` fails, the endpoint returns `HTTP 422 Unprocessable Entity`.
Because `422` is not in the iOS `OfflineQueueManager`'s recoverable error list,
the client drops the corrupted queue entry rather than retrying.

> **Note on Wikipedia Extraction:** During a "Cache Miss" (first discovery
> globally), the Edge Router fires the Wikipedia HTTP extraction _concurrently_
> alongside Gemini Text Inference latency via a `Promise.all` envelope. This
> guarantees high-resolution encyclopedia metadata maps directly to the user
> natively on the very first roundtrip without requiring the iOS app to skeleton
> load.

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

This data contract maps into the Swift Codable layer where nested JSON `Data` is
verified to prevent `JSONDecoder()` failures on double-escaped strings.

```swift
struct IdentifyResponse: Codable {
    let success: Bool
    let data: SpeciesData?
    let error: String?
}
```

**Client Authentication Caveat**: `MerianNetworkClient` abstracts GoTrue
anonymous hardware tokens. The backend extracts cryptographic JWT identity from
the `Authorization: Bearer` header via `supabaseAdmin.auth.getUser()`, ignoring
any `user_id` in the request body. The Swift payload uses the
`SupabaseManager`'s active session UUID only as a proxy string for syncing
RevenueCat identifiers — actual API validation runs over GoTrue JWT verification
only.

**Offline Ghost Overwrite Protection**: Before calling
`SupabaseManager.shared.getValidAuthHeaders()`, the iOS client checks
`UserDefaults.standard.bool(forKey: "Merian_HasAuthenticatedOAuth")`. If an
authenticated user goes offline long enough for their JWT to expire, the Swift
client throws `NetworkError.invalidResponse` immediately. This prevents a guest
UUID from overwriting the user's Pro status or stranding their `.sqlite` data,
and causes `CaptureWorkspaceView` to prompt re-authentication instead.

---

## Public Species Dictionary Edge Node

The `/species-dictionary` Edge Function returns species-level dictionary data
for the standalone Species Dictionary Page, Explore Dictionary catalog, and Tree
of Life canvas. It is deliberately separate from both the Insight scan and
Explore post-detail contracts:

- Insight scan data can include local media, user review state, field notes, and
  per-scan AI reasoning.
- Explore detail data can include a public shared scan projection.
- Species dictionary data includes only canonical dictionary fields and
  reference imagery.

The function has `verify_jwt = false` in `services/supabase/config.toml`. Detail
and catalog requests do not call `requireAuth`; they may receive normal app auth
headers from `MerianNetworkClient`, but identity is not read and must not affect
those responses. Tree mode does call `requireAuth` because the graph membership
is scoped to the signed-in user's scan library, but the returned nodes still use
only the public species projection.

The response is built through the shared public species projection in
`services/supabase/functions/_shared/publicSpeciesProjection.ts`. That module
owns common-name fallback, alternate-name dedupe, normalized/legacy
reference-image mapping, nullable taxonomy shape, and contract tests for
private-field leaks. SQL-only Explore detail lookalikes use matching database
helpers so the same species DTO rules apply outside Deno.

### `/species-dictionary`

Request body:

```json
{
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "scientific_name": "Danaus plexippus"
}
```

Validation rules:

- Either `species_id` or `scientific_name` is required.
- `species_id`, when present, must be a valid UUID and is preferred for lookup.
- `scientific_name`, when present, must be a string and non-empty after
  trimming.
- Internal whitespace is collapsed before lookup.
- Names longer than 160 characters return `400`.

Current response shape:

```json
{
  "schema_version": 1,
  "data": {
    "id": "uuid",
    "scientific_name": "Danaus plexippus",
    "common_name": "Monarch Butterfly",
    "content_quality": "complete",
    "alternative_common_names": [],
    "taxonomy": {
      "kingdom": "Animalia",
      "phylum": "Arthropoda",
      "class": "Insecta",
      "order": "Lepidoptera",
      "family": "Nymphalidae",
      "genus": "Danaus"
    },
    "hazard_type": "none",
    "iucn_red_list_status": "least concern",
    "wikipedia_url": "https://en.wikipedia.org/wiki/Monarch_butterfly",
    "wikipedia_overview": "The monarch butterfly is a milkweed butterfly...",
    "habitat_description": "Often found in open meadows and milkweed patches.",
    "gbif_taxon_key": 5139790,
    "group_tags": ["animal", "insect"],
    "reference_images": [
      {
        "url": "https://upload.wikimedia.org/...",
        "source": "wikipedia",
        "license": "CC BY-SA 4.0",
        "attribution": "Example Photographer",
        "width": 1200,
        "height": 800
      },
      { "url": "https://static.inaturalist.org/...", "source": "gbif" }
    ],
    "similar_species": [
      {
        "species_id": "uuid",
        "scientific_name": "Limenitis archippus",
        "common_name": "Viceroy",
        "reference_image_url": "https://...",
        "iucn_red_list_status": "least concern",
        "reason": "Similar orange-and-black wing pattern.",
        "visual_traits": ["orange wings", "dark venation"],
        "confidence": 0.86,
        "source": "model_enrichment",
        "review_status": "unreviewed",
        "is_bidirectional": false,
        "sort_order": 0
      }
    ]
  }
}
```

`schema_version = 1` marks the current public species contract shared by
`/species-dictionary`, Explore detail similar species, and the future web
species surface. Within this version, new response keys must be additive,
existing nullable fields may remain `null`, and clients should ignore unknown
keys. A versioned endpoint path should be introduced only for a breaking change
such as removing/renaming fields or changing a field's type.

Catalog mode:

```json
{
  "mode": "catalog",
  "query": "Danaus",
  "limit": 40,
  "cursor": {
    "scientific_name": "Danaus plexippus",
    "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
  }
}
```

- `mode: "catalog"` returns a compact cursor-paginated list for the Explore
  Dictionary catalog.
- `limit` defaults to `40` and is capped at `100`.
- `query` is optional, trims/collapses whitespace, and filters scientific names.
- `cursor` carries the last `scientific_name` and `species_id` returned.
- Response rows include `id`, `scientific_name`, `common_name`,
  `content_quality`, nullable `taxonomy`, status fields, `group_tags`, and one
  `reference_image_url`; full page content still requires a detail request.

Caching:

- `200 OK` responses include
  `Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800`
  and `Vary: Accept-Encoding`.
- Tree mode sends `Cache-Control: private, no-store` and
  `Vary: Authorization, Accept-Encoding` because the species set depends on the
  authenticated user's scans.
- `400`, `401`, `404`, and `500` responses do not include public cache headers.
- iOS adds a 10-minute, 64-key in-memory memo cache in `MerianNetworkClient`,
  keyed by normalized `species_id` and scientific name. The cache is route-local
  only and never persists species pages to disk.
- Refreshed dictionary rows become visible after the iOS memo TTL and public
  HTTP freshness window expire. Future public web curation flows that require
  immediate visibility should add CDN/cache purge tooling to the write path.

Content quality:

- `content_quality` is additive and may be `complete`, `sparse`, or
  `needs_enrichment`.
- The Edge projection classifies quality from four public content signals: at
  least one reference image, a usable Wikipedia overview, habitat/distribution
  data, and meaningful taxonomy.
- `complete` means all four signals are present. `sparse` means two or three
  signals are present. `needs_enrichment` means fewer than two signals are
  available.
- iOS treats the field as optional and estimates the same state for older
  payloads. Sparse and needs-enrichment pages render an intentional status card
  rather than leaving the missing sections unexplained.
- iOS sends species dictionary analytics through TelemetryDeck only. Events
  include `entryPoint`, `contentQuality`, and image `source` where relevant;
  species names, species IDs, scan IDs, Explore post IDs, user locations, field
  notes, comments, image URLs, and review state are not attached.

Name and imagery mapping:

- `common_name` resolves from `common_names.en`, then the first non-empty
  `common_names` value, then `scientific_name`.
- `alternative_common_names` is trimmed, deduped, and excludes the resolved
  primary common name.
- `reference_images` prefers ordered rows from `species_reference_images`. Each
  item includes `url` and `source`, plus optional `license`, `attribution`,
  `width`, and `height` when present.
- If no normalized image rows exist, `reference_images` falls back to the
  comma-separated `species_dictionary.reference_image_url` field by splitting,
  trimming, and deduping URLs.
- `source` is `merian` for Merian-published app media, `wikipedia` for
  Wikimedia/Wikipedia hosts, and `gbif` for external occurrence imagery. If
  `wikipedia_url` exists, the first unresolved legacy image also maps to
  `wikipedia`; otherwise unresolved legacy images map to `gbif`.
- Normalized rows are ordered Merian first, then Wikipedia, then GBIF.
- `similar_species` is hydrated from `species_lookalikes` using the explicit
  PostgREST hint `species_dictionary!lookalike_id` and includes `species_id` for
  canonical tap-through routing. Similar-species thumbnails prefer the first
  normalized `species_reference_images` row and fall back to the legacy
  dictionary cache. Additive relation metadata includes `reason`,
  `visual_traits`, `confidence`, `source`, `review_status`, `is_bidirectional`,
  and `sort_order`; rejected rows are omitted from public projections.

Image licensing and attribution:

- `species_reference_images.license` and `species_reference_images.attribution`
  are the canonical public media rights fields.
- `/species-dictionary` preserves `license` and `attribution` on each normalized
  `reference_images` item when the metadata exists. Legacy comma-separated
  fallback images usually have only `url` and `source`.
- iOS displays the active image's attribution/license below the species
  dictionary gallery when either field is present.
- Future web species pages must call
  `publicWebReferenceImageAttributionIssues(...)` from
  `_shared/publicSpeciesProjection.ts` before rendering reference media. Web
  must not publish an image with missing license or attribution unless the web
  renderer supplies an equivalent source-specific attribution path.

Provenance and refresh metadata:

- The response shape does not yet expose provenance fields.
- Dictionary writers record field-level source/freshness rows in
  `species_content_provenance` for common names, alternate names, taxonomy,
  Wikipedia content, habitat, GBIF keys, reference images, group tags,
  hazard/conservation fields, and lookalikes.
- `refresh-species-content` uses `public.get_species_content_refresh_queue(...)`
  rather than scanning `species_dictionary` directly for stale content. V1
  refreshes only GBIF/Wikipedia-backed fields and leaves model/curation-backed
  fields untouched.
- Reference image refreshes call `public.replace_species_reference_images(...)`
  so normalized rows stay aligned with the legacy compatibility cache while
  preserving existing license/attribution metadata.

Error responses:

| Status | Body                                                                       | Meaning                                                                    |
| ------ | -------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `400`  | `{ "error": "Missing required parameter: species_id or scientific_name" }` | Missing, non-string, or blank lookup                                       |
| `400`  | `{ "error": "species_id must be a valid UUID." }`                          | Invalid species ID                                                         |
| `400`  | `{ "error": "scientific_name must be a string when provided." }`           | Non-string scientific name was supplied alongside a valid species ID       |
| `400`  | `{ "error": "scientific_name is too long." }`                              | Scientific name exceeds the request bound                                  |
| `404`  | `{ "error": "Species not found" }`                                         | No `species_dictionary` row exists for the requested ID or normalized name |
| `500`  | `{ "error": "Internal Server Error" }`                                     | Database or unexpected function failure                                    |

Swift mapping:

```swift
MerianNetworkClient.shared.getSpeciesDictionary(scientificName:)
MerianNetworkClient.shared.getSpeciesDictionary(speciesId:scientificName:)
```

decodes into `SpeciesDictionaryResponse` / `SpeciesDictionaryEntry` in
`SpeciesDictionaryAPIModels.swift`. `SpeciesDictionaryEntry.taxonomyData` adapts
the response into the shared `TaxonomyCard`, and `similarSpeciesData` adapts
hydrated lookalikes into the shared `SimilarSpeciesGallery`.
`SpeciesDictionaryRoute` prefers `speciesId` when present and keeps
`scientificName` as a display/fallback key.

---

## Public Species Observation Stats Edge Node

The `/species-observation-stats` Edge Function returns public, global
iNaturalist observation aggregates for a species. It is deliberately separate
from local Merian observation aggregation:

- iOS aggregates local `LocalScanRecord` data on-device through
  `SpeciesObservationStatsDatabaseActor` and `SpeciesObservationStatsReducer`.
- The Edge Function receives only `species_id` and `scientific_name`.
- The Edge Function returns only public iNaturalist-derived species aggregates
  and cache metadata.

The function has `verify_jwt = false` in `services/supabase/config.toml` and
does not call `requireAuth`. The iOS client uses an unauthenticated public GET;
legacy POST callers may still send normal app auth headers, but identity is not
read and must not affect the response.

### `/species-observation-stats`

Preferred request:

```text
GET /functions/v1/species-observation-stats?species_id=1cf79982-e5ee-4e3d-8d65-274527e6ae01&scientific_name=Danaus%20plexippus
```

Compatibility request body:

```json
{
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "scientific_name": "Danaus plexippus"
}
```

Validation rules:

- `scientific_name` is required.
- `scientific_name` must be a string and non-empty after trimming.
- Internal whitespace is collapsed before lookup.
- Names longer than 160 characters return `400`.
- `species_id`, when present and non-empty, must be a valid UUID.

Current response shape:

```json
{
  "schema_version": 1,
  "data": {
    "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    "scientific_name": "Danaus plexippus",
    "source": {
      "provider": "inaturalist",
      "scope": "global",
      "inaturalist_taxon_id": 48662,
      "fetched_at": "2026-05-17T12:00:00.000Z"
    },
    "status": "fresh",
    "total_observations": 450448,
    "last_observation_date": "2026-05-17",
    "fetched_at": "2026-05-17T12:00:00.000Z",
    "provider_errors": [],
    "seasonality": [{ "month": 5, "count": 1200 }],
    "history": [{ "year": 2026, "month": 5, "count": 1200 }],
    "life_stage": [
      {
        "key": "adult",
        "label": "Adult",
        "values": [{ "month": 8, "count": 100 }]
      }
    ],
    "sex": [
      {
        "key": "female",
        "label": "Female",
        "values": [{ "month": 8, "count": 12 }]
      }
    ]
  }
}
```

`schema_version = 1` marks the current public observation-stats contract. Within
this version, new response keys must be additive, existing nullable fields may
remain `null`, and clients should ignore unknown keys.

Status values:

- `fresh`: provider fetch completed and data exists.
- `no_data`: provider fetch completed but no observation buckets were found.
- `partial`: one or more provider buckets failed, but useful data is still
  available. On cold cache misses, core stats may be returned as `partial` while
  life-stage and sex annotation buckets refresh in the background.
- `stale`: a usable stale cache payload was returned while refresh work is
  deferred off the response path.
- `unavailable`: provider refresh failed and no usable cache existed.

Series shapes:

- `seasonality`: month-of-year counts, `month` in `1...12`.
- `history`: rolling monthly counts from January of current year minus six
  through the current month.
- `life_stage`: category series with month-of-year values.
- `sex`: category series with month-of-year values. This remains part of the
  backend payload for provider parity, but the current iOS chart does not render
  Sex as a tab; per-scan AI sex appears in the Overview card.

iNaturalist mapping:

- Taxon lookup prefers `species_dictionary.inaturalist_taxon_id`.
- If absent, Deno resolves an exact `scientific_name` through `/v1/taxa`.
- If no exact taxon ID is found, Deno falls back to iNaturalist `taxon_name`.
- Observation totals and latest dates use `/v1/observations`.
- Seasonality, history, life stage, and sex use `/v1/observations/histogram`.
- Life Stage annotation IDs use `term_id = 1` with values Adult `2`, Teneral
  `3`, Pupa `4`, Nymph `5`, Larva `6`, Egg `7`, Juvenile `8`, and Subimago `16`.
- Sex annotation IDs use `term_id = 9` with values Female `10`, Male `11`, and
  Cannot determine `20`.

Caching:

- Backend cache table: `species_observation_stats_cache`.
- Cache key: `species_id + source + scope`.
- Source: `inaturalist`.
- Scope: `global`.
- Fresh TTL: 7 days.
- Stale fallback window: 30 additional days.
- Cold misses fetch taxon lookup, observation summary, seasonality, and history
  synchronously, then queue life-stage and sex annotation refresh via
  `runBackground`.
- Usable stale cache rows return immediately and queue a full refresh in the
  background. Duplicate in-flight refreshes for the same species are suppressed
  per isolate.
- Fresh and `no_data` `200 OK` responses include
  `Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800`
  and `Vary: Accept-Encoding`.
- `partial`, `stale`, and `unavailable` `200 OK` responses use
  `Cache-Control: public, max-age=30, s-maxage=60, stale-while-revalidate=300`
  and `Vary: Accept-Encoding`.
- iOS adds a 5-minute, 64-key in-memory memo cache in `MerianNetworkClient`,
  keyed by normalized `species_id` and scientific name.

Privacy:

- Local Merian logs are never sent to Supabase.
- The response must not include scan IDs, user IDs, Explore post IDs, field
  notes, comments, user locations, local media, local observation counts, or
  preferred-name overrides.

Error responses:

| Status | Body                                                         | Meaning                                   |
| ------ | ------------------------------------------------------------ | ----------------------------------------- |
| `400`  | `{ "error": "Missing required parameter: scientific_name" }` | Missing, non-string, or blank name        |
| `400`  | `{ "error": "species_id must be a valid UUID." }`            | Invalid species ID                        |
| `400`  | `{ "error": "scientific_name is too long." }`                | Scientific name exceeds the request bound |
| `500`  | `{ "error": "Internal Server Error" }`                       | Database or unexpected function failure   |

Swift mapping:

```swift
MerianNetworkClient.shared.getSpeciesObservationStats(
    speciesId:scientificName:
)
```

decodes into `SpeciesObservationStatsResponse` / `SpeciesObservationStatsEntry`
in `SpeciesObservationStatsAPIModels.swift`. `SpeciesObservationStatsViewModel`
combines that public baseline with local SwiftData aggregates for
`SpeciesObservationChartsCard`, which currently renders seasonality, history,
and life-stage series.

---

## Explore Edge Nodes

Explore traffic is intentionally separate from the identify pipeline. The iOS
client uses dedicated Edge Functions for feed reads and social interactions, all
authenticated through the same Supabase session headers used elsewhere in the
app.

### Explore Public Identity Contract

Explore payloads distinguish between the public display label and the canonical
handle:

- `author_name`: display label for Explore rows. Logged-in authors with safe
  provider/account names keep labels such as `Emre E.`.
- `author_username`: stable public username stored without `@`. Clients render
  it as `@author_username` for profile handles and for default/ghost author
  rows.
- `author_avatar_url`: optional copied public avatar projection.

`public_author_name` is not a future mention handle. Comment mentions and other
handle-based features must use `public_username` / `author_username`. The field
is additive and optional for rollout tolerance; older clients may ignore it.

### `/get-explore-feed`

Returns public Explore feed cards for the shipped `recent`, `following`,
`trending`, and `nearby` modes. The backend routes to a dedicated SQL RPC per
mode and already filters out:

- unshared posts
- tombstoned scans
- scans with no remaining image URLs
- shadowbanned authors
- both directions of user blocking

Post `location_sharing` controls public location output, not ordinary feed
visibility. `private` posts can still appear in Recent, Following, Trending,
profile, hashtag, and detail surfaces, but their public location fields are
empty. The `nearby` filter is spatial and uses post-owned public coordinates;
for non-owned posts this means only saved `location_sharing = "open"` posts with
a stored public coordinate can match the radius query.

Primary request shapes:

Recent feed, which is also the default when `filter` is omitted:

```json
{
  "limit": 20,
  "filter": "recent",
  "before_shared_at": "2026-04-28T21:18:00.000Z",
  "before_post_id": "uuid"
}
```

Following feed:

```json
{
  "limit": 20,
  "filter": "following",
  "before_shared_at": "2026-05-03T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

Trending feed:

```json
{
  "limit": 20,
  "filter": "trending",
  "before_ranking_value": 12,
  "before_shared_at": "2026-05-02T16:45:00.000Z",
  "before_post_id": "uuid"
}
```

Nearby feed:

```json
{
  "limit": 20,
  "filter": "nearby",
  "latitude": 30.2672,
  "longitude": -97.7431,
  "before_shared_at": "2026-05-03T11:22:00.000Z",
  "before_post_id": "uuid"
}
```

Validation rules:

- `recent`, `following`, and `nearby` page on `(shared_at DESC, post_id DESC)`.
  Omit both cursor fields for the first page.
- `following` returns only posts by followed authors that remain visible to the
  requester.
- `trending` pages on `(ranking_value DESC, shared_at DESC, post_id DESC)`. The
  cursor is only valid when `before_ranking_value`, `before_shared_at`, and
  `before_post_id` are all supplied together.
- `nearby` requires both `latitude` and `longitude`.
- `before_ranking_value` is rejected for `recent`, `following`, and `nearby`.
- `trending` is freshness-biased rather than all-time top. The ranking value is
  the post's like activity from the trailing 30 days.
- `nearby` reads `explore_posts.public_latitude` / `public_longitude` and limits
  non-owned coordinate-bearing posts to roughly 50 miles around the supplied
  viewer location before applying recency sort. `obscured` and `private` posts
  remain visible in non-spatial feeds but do not expose coordinates for Nearby.

`Recent` remains the iOS default for first load and for the Explore-tab unread
badge refresh path.

Current response shape:

```json
{
  "data": [
    {
      "post_id": "uuid",
      "scan_id": "uuid",
      "hero_image_url": "https://...",
      "shared_at": "2026-04-26T17:22:11.000Z",
      "author_user_id": "uuid",
      "author_name": "Emre E.",
      "author_username": "emre_e",
      "author_avatar_url": "https://lh3.googleusercontent.com/...",
      "hashtags": ["citybioblitz", "springcount"],
      "species_common_name": "Monarch Butterfly",
      "species_scientific_name": "Danaus plexippus",
      "pet_identification": null,
      "public_location_label": "Austin, TX",
      "location_sharing": "open",
      "time_of_day": "afternoon",
      "current_month": 4,
      "weather_condition": "clear",
      "weather_temperature_f": 78.2,
      "like_count": 3,
      "comment_count": 1,
      "ranking_value": 12,
      "viewer_has_liked": false,
      "is_owned_by_viewer": false
    }
  ]
}
```

`author_username` is the copied public handle stored on
`public.users.public_username` without `@`. `author_avatar_url` is a copied
public projection stored on `public.users.public_avatar_url`. Neither field is
read directly from `auth.users` on the client. `ranking_value` is populated for
`trending` rows and omitted or `null` for `recent`, `following`, and `nearby`.
Feed-card hashtag hydration is a batched lookup over the page's `post_id`
values. `hashtags` is returned by the updated feed function as normalized public
tag text without leading `#`; it is `[]` for untagged posts.
`species_common_name` is the post snapshot selected by the author when sharing
or editing. It should be preferred over dictionary names for the public post
projection, while clients may still apply viewer-local preferred-name display on
top of the DTO for personalized native surfaces. When `pet_identification` is
non-null, native clients may use `pet_identification.label` as the visible
dog/cat card title. That label does not replace `species_common_name`,
`species_scientific_name`, dictionary routes, or species stats.

### `/get-explore-post`

Returns the same Explore card projection as `/get-explore-feed`, but for a
single post:

```json
{
  "post_id": "uuid"
}
```

This endpoint exists for notification routing, native deep links, and the
privacy-safe projection behind public web share pages such as
`https://merian.earth/explore/post/{postId}`. It solves the case where the
tapped or shared post is not already present in the currently loaded in-memory
feed page. The Next.js web route may call the underlying `get_explore_post` SQL
RPC directly from the server, but it must preserve this response boundary rather
than querying private scan/auth tables.

Current response shape:

```json
{
  "schema_version": 1,
  "data": {
    "post_id": "uuid",
    "scan_id": "uuid",
    "hero_image_url": "https://...",
    "shared_at": "2026-04-26T17:22:11.000Z",
    "author_user_id": "uuid",
    "author_name": "Emre E.",
    "author_username": "emre_e",
    "author_avatar_url": "https://lh3.googleusercontent.com/...",
    "hashtags": ["citybioblitz", "springcount"],
    "species_common_name": "Monarch Butterfly",
    "species_scientific_name": "Danaus plexippus",
    "pet_identification": null,
    "public_location_label": "Austin, TX",
    "location_sharing": "open",
    "time_of_day": "afternoon",
    "current_month": 4,
    "weather_condition": "clear",
    "weather_temperature_f": 78.2,
    "like_count": 3,
    "comment_count": 1,
    "viewer_has_liked": false,
    "is_owned_by_viewer": false
  }
}
```

If the post is no longer visible to the viewer because it was unshared, blocked,
tombstoned, or lost media, the endpoint returns `404`.

### `/get-explore-post-detail`

Returns the public species-detail payload for a single Explore post. The backend
reads from `public.get_explore_post_detail(...)`, which enforces the same
filters as the main feed:

- unshared posts are excluded
- tombstoned scans are excluded
- scans with no remaining image URLs are excluded
- shadowbanned authors are excluded
- both directions of user blocking are excluded

Post `location_sharing` is returned for edit hydration and controls public
location fields. It does not hide an otherwise visible detail page.

Request body:

```json
{
  "post_id": "uuid"
}
```

Current response shape:

```json
{
  "data": {
    "post_id": "uuid",
    "location_sharing": "open",
    "hashtags": ["citybioblitz", "springcount"],
    "species_dictionary_id": "uuid",
    "alternative_common_names": ["Milkweed Butterfly", "Common Tiger"],
    "taxonomy_kingdom": "Animalia",
    "taxonomy_phylum": "Arthropoda",
    "taxonomy_class": "Insecta",
    "taxonomy_order": "Lepidoptera",
    "taxonomy_family": "Nymphalidae",
    "taxonomy_genus": "Danaus",
    "ai_reasoning": "The bright orange wings with black veining and white-spotted margins are consistent with a monarch rather than the mimicking viceroy.",
    "habitat_description": "Often found in open meadows, milkweed patches, and migration corridors.",
    "gbif_taxon_key": 5130978,
    "iucn_red_list_status": "least_concern",
    "hazard_type": "poisonous",
    "wikipedia_url": "https://en.wikipedia.org/wiki/Monarch_butterfly",
    "reference_image_url": "https://upload.wikimedia.org/.../Monarch.jpg,https://inaturalist-open-data.s3.amazonaws.com/photos/123/original.jpg",
    "wikipedia_overview": "The monarch butterfly is a milkweed butterfly in the family Nymphalidae...",
    "similar_species": [
      {
        "species_id": "uuid",
        "scientific_name": "Limenitis archippus",
        "common_name": "Viceroy",
        "reference_image_url": "https://upload.wikimedia.org/.../Viceroy.jpg",
        "iucn_red_list_status": "least_concern"
      }
    ],
    "field_notes": "Found at the shaded meadow edge after rain."
  }
}
```

This endpoint exists so Explore can render public species cards on the detail
page without loading private scan state or the Insight `InferenceEngine`.

`hashtags` uses the same normalized public tag edge table as feed cards. Detail
renders tags as centered wrapping chips; tag taps route into the tagged-post
collection rather than querying field notes, comments, or private scan state.

`schema_version = 1` uses the same public species contract marker as
`/species-dictionary`. Older clients can continue decoding the `data` field and
ignore the wrapper key; newer clients may use it to gate future additive UI
behavior.

`alternative_common_names` is sourced from
`species_dictionary.alternative_common_names` and returned as an empty array
when no alternate names are available.

For posts owned by the current viewer, iOS also uses `field_notes` as a repair
source for the local insight sheet. `FieldNotesRepository` checks
`LocalScanRecord.fieldNotes`, `OfflineQueuedScan.fieldNotes`, and then the
legacy `FieldNotesStore` bridge before accepting the Explore value. If all
local/private stores are empty but the public Explore post still has notes, the
repository promotes the public value back into SwiftData and mirrors the bridge.
Existing local/private notes are preserved and are not overwritten by the
Explore copy.

`reference_image_url` remains a comma-separated compatibility field for Explore
detail clients, but the RPC now composes it from ordered
`species_reference_images` rows first and falls back to
`species_dictionary.reference_image_url` for older species rows. Explore detail
uses it to render the public reference gallery below the post's AI reasoning
without making an extra authenticated scan fetch.

`similar_species` is hydrated from `species_lookalikes` for the post's resolved
dictionary species through `public.public_species_similar_species(...)`. Each
entry contains public species-level data only and is shaped like the existing
lookalike DTO: `species_id`, `scientific_name`, `common_name`,
`reference_image_url`, and `iucn_red_list_status`, plus optional relation
metadata (`reason`, `visual_traits`, `confidence`, `source`, `review_status`,
`is_bidirectional`, `sort_order`). The lookalike image URL prefers the first
normalized `species_reference_images` row and falls back to the legacy
dictionary cache. Empty lookalike sets return an empty array, and iOS omits the
section. Older clients can continue to route by `scientific_name`; new clients
prefer `species_id` for dictionary sheet lookup.

`ai_reasoning` is returned conditionally from the backing `scans` row, not
copied into `explore_posts`. It is only exposed when the scan still reflects the
original AI identification:

- `is_flagged = false`
- `user_review_state != 'user_overridden'`
- `user_identification_override IS NULL`

That means the Explore detail page automatically hides the reasoning if the user
later flags the identification or overrides it, while still allowing
AI-confirmed scans to show the original per-photo reasoning.

### `/get-explore-author-profile`

Returns a privacy-scoped public author profile for an Explore author. This
endpoint exists for the author profile sheet opened from Explore feed/detail
author headers.

Request body:

```json
{
  "author_user_id": "uuid",
  "preview_limit": 9
}
```

Validation and availability rules:

- `author_user_id` is required and must be a UUID.
- `preview_limit` is optional, defaults to `9`, and is capped at `30`.
- The endpoint returns `404` if the target author has no currently visible
  Explore post for the requesting viewer.
- Shadowbanned authors and either direction of user blocking return no profile.
- Profile aggregates are computed from all non-tombstoned scans owned by the
  author.
- Species count and achievement progress use biological species-backed scans via
  `COALESCE(confirmed_species_id, species_id)`.
- Public achievement progress includes the full current app achievement catalog,
  including domestic cat and dog scan achievements.
- Preview posts use the same Explore visibility rules as feed/library posts and
  never include private, unshared, tombstoned, media-less, or non-species-backed
  posts.
- Achievement progress never includes qualifying scan IDs.
- Follower/following counts are aggregate-only and do not expose browsable
  identities.
- `viewer_is_following` is specific to the requesting viewer and drives the
  profile sheet follow button.

Current response shape:

```json
{
  "data": {
    "author_user_id": "uuid",
    "author_name": "River W.",
    "author_username": "river_w",
    "author_avatar_url": "https://...",
    "species_count": 42,
    "current_streak": 5,
    "published_post_count": 19,
    "follower_count": 124,
    "following_count": 17,
    "viewer_is_following": true,
    "heatmap": {
      "total_captures": 124,
      "current_month_captures": 8,
      "year_string": "2026",
      "weeks": [
        {
          "month_label": "May",
          "days": [
            { "count": 1, "date": "2026-05-03T00:00:00Z" },
            { "count": 0, "date": "2026-05-04T00:00:00Z" },
            { "count": -1, "date": "2026-05-05T00:00:00Z" }
          ]
        }
      ]
    },
    "awards": [
      {
        "type": "explorer",
        "current_count": 5,
        "last_interaction_at": "2026-05-03T12:00:00.000Z"
      }
    ],
    "preview_posts": [
      {
        "post_id": "uuid",
        "scan_id": "uuid",
        "hero_image_url": "https://...",
        "shared_at": "2026-05-03T12:00:00.000Z",
        "author_user_id": "uuid",
        "author_name": "River W.",
        "author_username": "river_w",
        "author_avatar_url": "https://...",
        "species_common_name": "River Birch",
        "species_scientific_name": "Betula nigra",
        "pet_identification": null,
        "public_location_label": "Austin, TX",
        "time_of_day": "day",
        "current_month": 5,
        "weather_condition": "clear",
        "weather_temperature_f": 74.0,
        "like_count": 8,
        "comment_count": 1,
        "viewer_has_liked": false,
        "is_owned_by_viewer": false,
        "ranking_value": null
      }
    ]
  }
}
```

Heatmap day `count = -1` marks future days in the fixed 52-week grid and renders
as empty/clear in `ScansHeatmap`. The backend chooses the author's latest valid
persisted `scans.device_time_zone` for day-boundary calculations and falls back
to UTC when no timezone is available.

`follower_count` and `following_count` are public aggregate counts on visible
profiles only. They do not imply browsable lists. `viewer_is_following` is
specific to the requesting user and should replace any optimistic client follow
state after a write.

### `/get-explore-author-posts`

Returns a paginated grid library of an author's currently visible published
Explore scans. The response shape is the same card projection used by
`/get-explore-feed`, with `ranking_value = null`.

First page request:

```json
{
  "author_user_id": "uuid",
  "limit": 30
}
```

Follow-up page request:

```json
{
  "author_user_id": "uuid",
  "limit": 30,
  "before_shared_at": "2026-05-03T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

Validation and pagination rules:

- `author_user_id` is required and must be a UUID.
- `limit` is optional, defaults to `30`, and is capped at `100`.
- `before_shared_at` and `before_post_id` must be omitted together or supplied
  together.
- Pagination is stable on `(shared_at DESC, post_id DESC)`.
- The endpoint filters unshared posts, tombstoned scans, scans with no image
  media, scans without a species key, shadowbanned authors, and both directions
  of user blocking. Post `location_sharing` controls public location fields, not
  feed visibility.
- The card projection includes batched `hashtags` arrays just like the feed.

### `/get-explore-hashtag-posts`

Returns a paginated grid collection of currently visible Explore posts tagged
with one normalized public hashtag. iOS opens this collection when the viewer
taps a hashtag chip on a feed card or post detail page. The response shape is
the same card projection used by `/get-explore-feed`, with
`ranking_value = null` and a `hashtags` array hydrated for each row.

First page request:

```json
{
  "hashtag": "#CityBioBlitz",
  "limit": 30
}
```

Follow-up page request:

```json
{
  "hashtag": "citybioblitz",
  "limit": 30,
  "before_shared_at": "2026-05-12T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

Rules:

- `hashtag` is required. Display input may include leading `#`; the Edge
  function trims it, lowercases it, and requires 2 to 40 letters, digits, or
  underscores.
- `limit` is optional, defaults to `30`, and is capped at `100`.
- `before_shared_at` and `before_post_id` must be omitted together or supplied
  together.
- Pagination is stable on `(shared_at DESC, post_id DESC)`.
- The endpoint applies the same unshared, tombstoned, missing-media,
  missing-species, shadowban, and mutual-block filters as the Explore feed. Post
  `location_sharing` controls public location fields, not tagged-post
  visibility.
- The backing RPC is `public.get_explore_hashtag_posts(...)`, which reads the
  normalized `(tag, post_id)` edge index from `public.explore_post_hashtags`.

### `/get-explore-map-points`

Returns privacy-safe Explore map data for the currently visible bounds. The
request body is:

```json
{
  "north_latitude": 30.489,
  "south_latitude": 30.139,
  "east_longitude": -97.517,
  "west_longitude": -98.001,
  "zoom_level": 10.7,
  "limit": 500,
  "species_categories": ["birds", "insects"]
}
```

- `north_latitude`, `south_latitude`, `east_longitude`, and `west_longitude` are
  required numeric bounds.
- `zoom_level` is used only to decide whether the response should be clustered
  or return individual posts.
- `limit` is optional and capped at `500`.
- `species_categories` is optional. Allowed values are `plants`, `fungi`,
  `birds`, `mammals`, `reptiles`, `amphibians`, `fish`, `insects`, `arachnids`,
  and `other`.

The Edge Function reads `public.get_explore_map_posts(...)` and then applies
species-type filters and zoom-aware clustering in
`services/supabase/functions/get-explore-map-points/cluster.ts`. The shipped
behavior is:

- category counts are computed from the unfiltered privacy-safe rows in the
  current region
- selected species categories are applied before clustering, so clusters and
  waypoints reflect the active filters
- when the visible result set is small, return `mode: "posts"`
- when the viewport is broad or dense, return `mode: "clusters"`
- at close zooms, individual posts are still capped to prevent annotation
  overload

Current response shapes:

```json
{
  "mode": "clusters",
  "visible_count": 243,
  "category_counts": [
    { "category": "birds", "count": 82 },
    { "category": "insects", "count": 51 }
  ],
  "clusters": [
    {
      "id": "3015:2057",
      "latitude": 30.267,
      "longitude": -97.743,
      "post_count": 36
    }
  ],
  "posts": []
}
```

```json
{
  "mode": "posts",
  "visible_count": 24,
  "category_counts": [
    { "category": "birds", "count": 12 },
    { "category": "insects", "count": 8 }
  ],
  "clusters": [],
  "posts": [
    {
      "post_id": "uuid",
      "scan_id": "uuid",
      "latitude": 30.267,
      "longitude": -97.743,
      "coordinate_visibility": "obscured",
      "hero_image_url": "https://...",
      "shared_at": "2026-04-28T21:18:00.000Z",
      "author_user_id": "uuid",
      "author_name": "Nina P.",
      "author_username": "nina_p",
      "author_avatar_url": "https://...",
      "species_common_name": "Monarch Butterfly",
      "species_scientific_name": "Danaus plexippus",
      "pet_identification": null,
      "taxonomy_kingdom": "Animalia",
      "taxonomy_class": "Insecta",
      "public_location_label": "Austin, TX",
      "location_sharing": "open",
      "time_of_day": "afternoon",
      "current_month": 4,
      "weather_condition": "clear",
      "weather_temperature_f": 78.2,
      "like_count": 12,
      "comment_count": 3,
      "viewer_has_liked": false,
      "is_owned_by_viewer": false
    }
  ]
}
```

Privacy and filtering rules:

- the map excludes unshared posts, tombstoned scans, scans with no remaining
  image URLs, non-open post `location_sharing`, shadowbanned authors, and both
  directions of user blocking
- `coordinate_visibility` communicates whether an open post point is exact or
  approximate because species-safety or uncertainty rules rounded the public
  projection
- the shipped map projection comes from post-owned public coordinates on
  `explore_posts`, not from raw scan GPS at read time
- the map returns the post-owned scrubbed `public_location_label`; it does not
  derive labels from raw semantic location fields

### `/get-explore-comments`

Returns comment rows for a single Explore post. The read path enforces the same
visible-post and mutual-block filters as the feed. Comment rows include the
public author label, the stable author username handle, the optional public
author avatar projection, and three viewer capability flags:

- `viewer_can_delete`: The viewer authored this comment and may delete it.
- `viewer_can_moderate`: The viewer owns the Explore post and may remove someone
  else's comment from that post.
- `viewer_can_report`: The viewer may report this comment for abuse review.

This endpoint powers both the feed's bottom-sheet comments view and the inline
comment thread on the Explore detail page.

Current response shape:

```json
{
  "data": [
    {
      "comment_id": "uuid",
      "post_id": "uuid",
      "author_user_id": "uuid",
      "author_name": "Nick H.",
      "author_username": "nick_h",
      "author_avatar_url": "https://lh3.googleusercontent.com/...",
      "body": "Oooh mucho gusto",
      "created_at": "2026-05-12T20:43:00.000Z",
      "viewer_can_delete": false,
      "viewer_can_moderate": false,
      "viewer_can_report": true,
      "mentions": [
        {
          "user_id": "uuid",
          "username": "ash_b",
          "display_name": "Ash B.",
          "avatar_url": "https://..."
        }
      ],
      "reactions": [
        {
          "emoji": "👍",
          "count": 1,
          "viewer_has_reacted": false
        }
      ]
    }
  ]
}
```

`author_avatar_url` is sourced from `public.users.public_avatar_url`, the same
copied public projection used by feed cards, map previews, and author profiles.
The client must treat it as optional and fall back to iconography when it is
`null`.

`mentions` is an additive array of resolved `@username` spans in `body`. The raw
body remains plain text; the client links only usernames that appear in
`mentions`. Unresolved `@text` stays normal text.

The request body supports cursor pagination on
`(created_at ASC, comment_id ASC)`:

```json
{
  "post_id": "uuid",
  "limit": 100
}
```

Follow-up page requests send:

```json
{
  "post_id": "uuid",
  "limit": 100,
  "after_created_at": "2026-04-28T10:00:00.000Z",
  "after_comment_id": "uuid"
}
```

### `/get-explore-comment-replies`

Returns one page of visible replies under a top-level Explore comment. Replies
use the same row shape as `/get-explore-comments`, including `author_username`,
`author_avatar_url`, `reactions`, and `mentions`.

Request:

```json
{
  "parent_comment_id": "uuid",
  "limit": 25
}
```

Follow-up page requests send both cursor fields:

```json
{
  "parent_comment_id": "uuid",
  "limit": 25,
  "after_created_at": "2026-04-28T10:00:00.000Z",
  "after_comment_id": "uuid"
}
```

Replies stay one level deep. A reply cannot be the parent of another reply.

### `/share-scan-to-explore` and `/unshare-explore-post`

- `share-scan-to-explore` creates or reactivates a manual-share Explore post for
  an eligible biological scan with shareable public media. If a scan's public
  media URLs expired but the client can provide owner-scoped
  `restored_object_keys`, the function promotes safe image media back into
  `image_storage_urls` before sharing. If the local scan still has the original
  playback `.mp4` and the cloud row is missing durable video media, clients may
  provide `restored_video_object_keys`; the function promotes those videos into
  `video_storage_urls`, rebuilds `captured_media`, makes a best-effort
  `scan_media_assets` refresh for ready playback rows, and then writes the
  public Explore snapshot.
- Sharing snapshots image and video URLs into `explore_post_media`, ordered for
  the public carousel. `hero_image_url` remains the required thumbnail and
  backward-compatible image field; video media without an image thumbnail is
  rejected with `Video thumbnail unavailable.`
- New clients may pass ordered `media_items` using owner-scoped
  `source_media_id` values from `/get-explore-composer-media`; legacy
  `source_index` and `thumbnail_source_index` are accepted only when they map to
  eligible scan image/video URLs. Empty selections, non-visual media kinds,
  Describe/observation context, AI/reference images, and Dictionary media are
  rejected or ignored before the public post snapshot is written.
- `source_media_id` values are resolved through the same media source list
  returned to the composer: ready display/playback `scan_media_assets` rows
  first, `captured_media` second, and legacy image/video URL arrays last. This
  keeps video playback URLs and poster thumbnails paired even when sampled
  inference frames remain in compatibility image URL arrays. Share-state
  visibility
  requires a saved `explore_post_media` row, preventing failed media writes from
  appearing as existing Explore posts. When a selected video source is missing
  from the cloud row, the endpoint returns a clean validation error so the iOS
  client can attempt local `.mp4` repair instead of publishing an image-only
  historical row.
- When the scan has an active Identify request, sharing to Explore is blocked
  until that request resolves. Publishing a resolved Identify request marks the
  request with `explore_published_at`, materializes any new GBIF-backed resolved
  species into `species_dictionary`, sets the scan's `confirmed_species_id`, and
  queues species-content hydration/provenance rows before promoting the existing
  post into normal Explore surfaces without creating a duplicate post.
- `unshare-explore-post` soft-removes the post from the public feed via
  `unshared_at` without deleting the underlying scan.
- `field_notes` is optional and capped at 1000 characters. It is a public copy
  controlled by the user, not the private local source of truth.
- `species_common_name` is optional. When provided it must be a string; the Edge
  function trims it, collapses internal whitespace, caps it at 200 characters,
  and stores it as the Explore post's public common-name snapshot. When omitted
  or empty, legacy dictionary fallback behavior is preserved.
- `hashtags` is optional. The share endpoint accepts at most five hashtag
  strings, strips leading `#`, lowercases them, deduplicates them, and requires
  each tag to be 2 to 40 letters, digits, or underscores. Resharing replaces the
  post's public hashtag edges with the submitted normalized set; omitted
  hashtags clear the set for that share request.
- Unsharing also purges any Explore notifications tied to that post so the
  activity feed cannot route into hidden content.
- `location_sharing` is optional for backward compatibility. If omitted, the
  share uses the scan's current geoprivacy. Valid values are `open`, `obscured`,
  and `private`; legacy `hidden` is treated as `private`.
- The Explore map reads post-owned public coordinates from `explore_posts`. Only
  posts whose saved `location_sharing` is `open` can appear on the map or match
  non-owned Nearby radius queries. Protected-species and uncertainty rules can
  still store rounded public coordinates with
  `coordinate_visibility = "obscured"`.
- Updating the user's global/default geoprivacy or the backing scan's
  `geoprivacy` later does not overwrite an existing Explore post's explicit
  `location_sharing` choice.

### `/update-explore-field-notes`

Updates public share options on an already-shared Explore post owned by the
current viewer. Despite the legacy endpoint name, this includes field notes,
hashtags, the public common-name snapshot, and post-level `location_sharing`.
This endpoint does not mutate the private local notes stored in SwiftData; iOS
continues to treat `FieldNotesRepository` as the local source of truth.

Request body:

```json
{
  "post_id": "uuid",
  "field_notes": "Found at the shaded meadow edge after rain.",
  "species_common_name": "Black-Tailed Deer",
  "hashtags": ["deer", "urbanwildlife"],
  "location_sharing": "obscured"
}
```

Response body:

```json
{
  "success": true,
  "post_id": "uuid",
  "field_notes": "Found at the shaded meadow edge after rain.",
  "hashtags": ["deer", "urbanwildlife"],
  "species_common_name": "Black-Tailed Deer",
  "location_sharing": "obscured"
}
```

Rules:

- Requires an authenticated user through `withEdgeHandler`.
- `post_id` must be a valid UUID.
- `field_notes` may be a string or `null`.
- Empty or whitespace-only strings are normalized to `null`.
- Non-empty notes are trimmed and capped at 1000 characters.
- `species_common_name` is optional. If omitted, the existing
  `explore_posts.species_common_name` snapshot is preserved. If provided, it
  follows the same validation as `/share-scan-to-explore`: string-only, trimmed,
  internal whitespace collapsed, and capped at 200 characters. Empty strings and
  `null` clear the snapshot so read RPCs can fall back to dictionary names.
- `hashtags` is optional and, when provided, replaces the post's public hashtag
  edges using the same normalization as `/share-scan-to-explore`.
- `location_sharing`, when provided, updates only this Explore post. Valid
  values are `open`, `obscured`, and `private`; legacy `hidden` is treated as
  `private`.
- `media_items`, when provided, replaces the post's public media snapshot. New
  clients submit `source_media_id` values from `/get-explore-composer-media`;
  those IDs resolve through the same asset-first source list as
  `/share-scan-to-explore`, so captured-media videos keep their playback `.mp4`
  and poster thumbnail paired during edit/reorder flows. Legacy URL-based
  reorders are accepted only for rows already present on the post.
- Changing `location_sharing` reprojects only the post-owned public location
  fields. It does not mutate `scans.geoprivacy` or the user's global default.
- The update is scoped by `explore_posts.id`, `explore_posts.user_id`, and
  `unshared_at IS NULL`; non-owned or unshared posts return 404.

### `/update-public-username`

Updates the current user's canonical public username handle. Usernames are
stored without `@`; clients should render them as `@username`.

Request body:

```json
{
  "username": "@Stone Glen 72"
}
```

Response body:

```json
{
  "username": "stone_glen_72"
}
```

Rules:

- Requires an authenticated user through `withEdgeHandler`.
- Input may include a leading `@`; normalization strips it.
- Whitespace and punctuation separators normalize to underscores.
- The stored username must be lowercase ASCII letters, numbers, and underscores;
  3 to 24 characters; start with a letter; end with a letter or number; and
  contain no repeated underscores.
- Reserved names such as `admin`, `api`, `explore`, `merian`, `support`, and
  `system` are rejected with `400`.
- Duplicate normalized usernames return `409`.
- Alias-source users also have `public_author_name` updated to the username so
  ghost/default Explore rows render as `@username`. Derived/display-name users
  keep their existing Explore display label.

### `/check-public-username`

Validates a candidate username for the current authenticated user without
updating their profile. The endpoint uses the same normalization, reserved-name
rules, and cross-user uniqueness check as `/update-public-username`.

Request body:

```json
{
  "username": "@Stone Glen 72"
}
```

Response body:

```json
{
  "available": true,
  "username": "stone_glen_72",
  "error": null
}
```

Invalid or taken usernames return `200` with `available: false` and an `error`
message for inline UI. The current user's own username is considered available.

### `/get-scan-explore-share-state`

Returns the current viewer's authoritative Explore share mapping for one owned
scan. This endpoint exists to revalidate the Insight sheet's fast local cache
after relaunch or on a second device, so the Share button can switch back to
`View post` when a scan is still live in Explore without relying on device-local
memory alone.

Request body:

```json
{
  "scan_id": "uuid"
}
```

Current response shape:

```json
{
  "data": {
    "scan_id": "uuid",
    "post_id": "uuid",
    "shared_at": "2026-04-29T22:18:03.000Z",
    "community_request_id": "uuid-or-null",
    "community_request_status": "needs_id|resolved|withdrawn|null",
    "is_explore_feed_visible": false,
    "location_sharing": "obscured"
  }
}
```

Behavior notes:

- the lookup is owner-only: it reads only scans where `scans.user_id = self_id`
- when a live Explore post exists, `location_sharing` is the post-owned value
  used to hydrate share/edit options
- `community_request_id` and `community_request_status` restore the Identify
  request state for scans that have been made public as community ID requests
- `is_explore_feed_visible` is true only when the post belongs in normal Explore
  feed/map/author/hashtag surfaces
- pending Identify requests and resolved-but-unpublished Identify requests
  return their request state with `is_explore_feed_visible = false`; resolved
  requests become feed-visible only after the owner explicitly publishes them to
  Explore
- when no live post exists, `location_sharing` falls back to the scan's current
  geoprivacy so a new share composer can seed the default option
- the endpoint does not mutate scan or post geoprivacy
- if the scan still has an active Explore post and is still publicly visible,
  `post_id` and `shared_at` are returned
- if the scan exists but the Explore post was unshared or the scan is no longer
  publicly viewable because it was tombstoned, lost all media, became private,
  or no longer resolves to a species, the endpoint returns the same `scan_id`
  with `post_id = null`
- if the scan no longer exists for the current viewer, the Edge Function still
  returns `200` with `post_id = null` so the client can safely clear stale local
  cache without branching on `404`

### `/set-explore-post-like`

Idempotently toggles liked state for the current viewer and returns:

- `post_id`
- `viewer_has_liked`
- `like_count`

Important regression note: boolean request bodies must treat `liked: false` as a
valid value, not as a missing parameter. The shared `requireParams` helper was
hardened accordingly.

Notification side effects:

- Like notifications are maintained server-side through
  `explore_post_notifications`.
- The server aggregates likes into one row per recipient/post rather than
  inserting one notification row per like.
- Self-likes do not create notifications.

### `/set-user-follow`

Idempotently follows or unfollows a visible Explore author profile.

Request body:

```json
{
  "author_user_id": "uuid",
  "is_following": true
}
```

Response body:

```json
{
  "success": true,
  "author_user_id": "uuid",
  "follower_count": 12,
  "following_count": 4,
  "viewer_is_following": true
}
```

Validation and behavior:

- `author_user_id` is required and must be a UUID.
- `is_following` is required and must be a boolean. `false` is a valid request
  value.
- Self-follow is rejected with `400`.
- Follow inserts require no mutual block, a non-shadowbanned target, and a
  currently visible Explore author profile for the requester.
- Follow writes use the `(follower_user_id, followee_user_id)` primary key and
  are idempotent.
- Unfollow deletes the relationship even if the target profile is no longer
  visible.
- The returned state is authoritative and should replace optimistic client
  counts.

Notification side effects:

- Follow creates a postless in-app notification for the followed user.
- Unfollow removes the corresponding follow notification.
- Blocking either direction removes follow rows and follow notifications.
- Follow notifications are not sent to APNs.

### `/create-explore-comment` and `/delete-explore-comment`

- Create/delete plain-text comments on Explore posts.
- Server-side body cap: 500 characters.
- The response returns the updated `comment_count` so the feed can stay
  optimistic without a full reload.
- The created comment response includes `author_username` from
  `public.users.public_username` and `author_avatar_url` from
  `public.users.public_avatar_url` so the newly-appended row matches the
  subsequent `/get-explore-comments` read payload.
- The created comment response includes `mentions`, an array of resolved
  `@username` tokens from the saved body.
- Mention resolution is scoped to the post author, visible participants in the
  relevant thread, and followed users. It does not allow arbitrary public-user
  tagging.
- The resolver skips self, blocked, shadowbanned, invisible-profile, duplicate,
  and ineligible mentions, then stores at most five unique eligible users.
- Mention notifications use `comment_mention` and are deduped against existing
  `comment` or `comment_reply` notifications for the same recipient/comment.
- Comment notifications are created and removed server-side through triggers on
  `explore_post_comments`.
- Self-comments do not create notifications.

Removal semantics:

- If the current viewer authored the comment, `/delete-explore-comment` sets
  `deleted_at`.
- If the current viewer owns the Explore post but did not author the comment,
  `/delete-explore-comment` performs an owner moderation action by setting
  `moderated_at` and `moderated_by_user_id`.
- Both paths remove the comment from public reads and decrement `comment_count`,
  but they remain distinguishable in the database for auditability.

### `/get-explore-mention-suggestions`

Returns eligible `@username` suggestions for the current comment composer. The
endpoint is intentionally scoped and is not a global public-user search.

Request:

```json
{
  "post_id": "uuid",
  "parent_comment_id": "uuid",
  "query": "as",
  "limit": 8
}
```

- `post_id` is required.
- `parent_comment_id` is optional. When present, it must be a visible top-level
  comment on the same post and thread-participant suggestions are scoped to that
  reply thread.
- Empty or short queries may return the post author and visible thread
  participants.
- Followed-user suggestions require a typed query so the endpoint cannot become
  a follower-list browser.

Response:

```json
{
  "data": [
    {
      "user_id": "uuid",
      "username": "ash_b",
      "display_name": "Ash B.",
      "avatar_url": "https://...",
      "source": "thread"
    }
  ]
}
```

`source` is one of `post_author`, `thread`, or `following`.

### `/toggle-explore-comment-reaction`

Idempotently toggles an emoji reaction for the current viewer on a specific
comment and returns:

- `success`
- `comment_id`
- `emoji`

Request body:

```json
{
  "comment_id": "uuid",
  "emoji": "👍"
}
```

- If the viewer has not yet reacted with this emoji, the reaction is inserted.
- If the viewer has already reacted with this emoji, the reaction is removed.
- Reactions are aggregated into a `reactions` JSON array by the
  `/get-explore-comments` read endpoint.
- The server also maintains aggregated Explore notification rows per
  `(comment author, comment, emoji)` so comment authors can be notified when
  other viewers react.

### `/report-explore-comment`

Creates or updates a moderation report for an Explore comment without removing
it immediately.

- Required body fields: `comment_id`, `reason`
- Optional body field: `details`
- Current allowed `reason` values: `Spam`, `Harassment`,
  `Inappropriate content`, `Other`
- Users cannot report their own comments.
- Duplicate reports by the same user collapse into a single row keyed by
  `(comment_id, reporter_user_id)`.

### `/get-explore-notifications`

Returns the viewer's in-app Explore activity feed. The request body is optional:

```json
{
  "limit": 50
}
```

- `limit` defaults to `50` and is capped server-side.
- The read path mirrors Explore visibility rules: unshared posts, tombstoned
  scans, posts with no remaining media, shadowbanned owners, blocked actors, and
  soft-deleted comments are filtered out. Post `location_sharing` controls
  public location fields, not notification visibility.
- Follow notifications are validated against an active follow relationship and
  blocked or shadowbanned actors are filtered out.
- Community Identification notifications include `community_request_id` plus
  display fields for the current or resolved taxon, and the client routes them
  to the Community request detail instead of regular post detail.
- Pagination is cursor-based on `(updated_at DESC, notification_id DESC)`.
  Follow-up page requests send:

```json
{
  "limit": 50,
  "before_updated_at": "2026-04-27T12:05:00.000Z",
  "before_notification_id": "uuid"
}
```

Current response shape:

```json
{
  "data": [
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "community_request_id": null,
      "type": "like_aggregated",
      "comment_id": null,
      "reaction_emoji": null,
      "triggering_user_id": "uuid",
      "triggering_user_name": "User C",
      "comment_body": null,
      "recent_actor_names": ["User C", "User B"],
      "action_count": 2,
      "is_read": false,
      "community_taxon_common_name": null,
      "community_taxon_scientific_name": null,
      "community_request_display_name": null,
      "created_at": "2026-04-27T12:00:00.000Z",
      "updated_at": "2026-04-27T12:05:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "type": "comment",
      "comment_id": "uuid",
      "reaction_emoji": null,
      "triggering_user_id": "uuid",
      "triggering_user_name": "User D",
      "comment_body": "Beautiful find",
      "recent_actor_names": [],
      "action_count": 1,
      "is_read": false,
      "created_at": "2026-04-27T12:06:00.000Z",
      "updated_at": "2026-04-27T12:06:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "type": "comment_mention",
      "comment_id": "uuid",
      "reaction_emoji": null,
      "triggering_user_id": "uuid",
      "triggering_user_name": "User M",
      "comment_body": "Looping in @ash_b",
      "recent_actor_names": [],
      "action_count": 1,
      "is_read": false,
      "created_at": "2026-04-27T12:07:00.000Z",
      "updated_at": "2026-04-27T12:07:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "type": "comment_reaction",
      "comment_id": "uuid",
      "reaction_emoji": "🔥",
      "triggering_user_id": "uuid",
      "triggering_user_name": "User E",
      "comment_body": "Beautiful find",
      "recent_actor_names": ["User E", "User F"],
      "action_count": 2,
      "is_read": false,
      "created_at": "2026-05-05T10:00:00.000Z",
      "updated_at": "2026-05-05T10:05:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "community_request_id": "uuid",
      "type": "community_request_resolved",
      "comment_id": null,
      "reaction_emoji": null,
      "triggering_user_id": null,
      "triggering_user_name": null,
      "comment_body": null,
      "recent_actor_names": [],
      "action_count": 1,
      "is_read": false,
      "community_taxon_common_name": "Pinwheel",
      "community_taxon_scientific_name": "Aeonium haworthii",
      "community_request_display_name": "Pinwheel",
      "created_at": "2026-06-20T19:30:00.000Z",
      "updated_at": "2026-06-20T19:30:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": null,
      "type": "follow",
      "comment_id": null,
      "reaction_emoji": null,
      "triggering_user_id": "uuid",
      "triggering_user_name": "User F",
      "comment_body": null,
      "recent_actor_names": [],
      "action_count": 1,
      "is_read": false,
      "created_at": "2026-05-11T16:10:00.000Z",
      "updated_at": "2026-05-11T16:10:00.000Z"
    }
  ]
}
```

`post_id` is nullable because follow notifications are not post-backed. The iOS
notifications UI treats follow rows as informational and does not attempt post
navigation.

### `/get-explore-unread-notification-count`

Returns the unread bell badge count for visible Explore notifications:

```json
{
  "unread_count": 3
}
```

Unlike most read endpoints, this response returns the scalar at the top level
rather than nesting it under `data`.

### `/mark-explore-notifications-read`

Marks the viewer's Explore notifications as read and returns the number of rows
updated:

```json
{
  "success": true,
  "marked_count": 3
}
```

The current iOS client calls this only after `/get-explore-notifications`
succeeds, matching the shipped "clear the unread badge when the sheet opens
successfully" behavior.

### `/register-push-device`

Registers or refreshes the current iOS device for optional remote Explore
activity pushes:

```json
{
  "device_token": "lowercasehex...",
  "platform": "ios",
  "environment": "sandbox",
  "explore_enabled": true,
  "comment_mentions_enabled": true,
  "community_identifications_enabled": true
}
```

- The endpoint is authenticated with the viewer's existing Supabase session,
  just like the other Explore nodes.
- `device_token` is normalized to lowercase and upserted by
  `(device_token, platform, environment)`.
- `explore_enabled` is feature-specific. Users can opt into Explore activity
  pushes without also enabling discovery-result alerts. New installs default
  this setting on.
- `comment_mentions_enabled` is optional for compatibility with older clients.
  New installs default this setting on. When omitted, the server treats the
  mention preference like the submitted `explore_enabled` value for older
  clients. When present, `comment_mention` payloads require
  `comment_mentions_enabled` to be true. Other Explore activity payloads require
  `explore_enabled` to be true.
- `community_identifications_enabled` is optional for compatibility with older
  clients. New installs default this setting on. When omitted, the server treats
  the Community preference like the submitted `explore_enabled` value for older
  clients. Community Identification payloads require
  `community_identifications_enabled` to be true.
- The server stores these rows in `public.user_push_devices`. Delivery failures
  from APNs feed back into that table via `last_error_*` fields and `is_active`.

### iOS Mapping

The Explore client decodes these endpoints via:

- `apps/ios/Merian/Core/Network/ExploreAPIModels.swift`
- `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExploreFeedViewModel.swift`
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExploreFeedViewModel+Interactions.swift`
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExploreFeedViewModel+Notifications.swift`
- `apps/ios/Merian/Features/Explore/Map/ViewModels/ExploreMapViewModel.swift`
- `apps/ios/Merian/Features/Explore/Notifications/ViewModels/ExploreNotificationsViewModel.swift`
- `apps/ios/Merian/Features/Explore/Notifications/Models/ExploreNotification.swift`
- `apps/ios/Merian/Features/Explore/AuthorProfile/Views/ExploreAuthorProfileSheet.swift`
- `apps/ios/Merian/Features/Explore/Map/Views/ExploreMapView.swift`
- `apps/ios/Merian/Features/Explore/Shell/ExploreView.swift`

The current feed UI uses only a subset of the payload for visible card
rendering:

- `author_name`
- `author_username`
- `author_avatar_url`
- `public_location_label`
- `species_common_name` (displayed through `ExploreFeedViewModel`'s
  SwiftData-backed preferred-name cache when the viewer has a
  `UserSpeciesPreference`; dog/cat pet labels can sit above this display
  resolver when `pet_identification` is present)
- `species_scientific_name`
- `pet_identification`
- `hero_image_url`
- `hashtags`
- `like_count`
- `comment_count`
- `viewer_has_liked`

The Explore detail page additionally uses:

- `/get-explore-post` for notification-driven navigation into posts that are not
  already loaded in the current feed page
- `/get-explore-post-detail` for taxonomy and habitat/distribution data
- `/get-explore-hashtag-posts` when a feed or detail hashtag chip opens its
  visible tagged-post collection
- `time_of_day` + `current_month` to derive broad public observation context
  such as `Morning • April`
- `weather_condition` + `weather_temperature_f` for optional public weather
  telemetry
- `/get-explore-comments` for the inline thread and composer state
- `/get-explore-comment-replies` for reply pagination under top-level comments
- `/get-explore-mention-suggestions` for trailing-token `@username` autocomplete
- `mentions` from comment and reply rows for tappable mention spans that open
  `ExploreAuthorProfileSheet`
- `author_username` from post/profile/comment rows for stable handle display and
  default/ghost author labels
- `author_avatar_url` from comment rows for both `ExploreCommentsSheet` and
  `ExplorePostDetailView`
- cursor-based comment pagination on `(created_at, comment_id)` so long threads
  page safely in both the sheet and detail view
- `/get-explore-unread-notification-count` for the bell badge and
  `/get-explore-notifications` plus `/mark-explore-notifications-read` for the
  in-app activity sheet
- cursor-based activity pagination on `(updated_at, notification_id)` so the
  notifications sheet does not skip or duplicate rows during active usage
- `/set-user-follow` to apply public author Follow/Following state from
  `ExploreAuthorProfileSheet`
- `/check-public-username` and `/update-public-username` from the Profile
  account card username editor
- `/register-push-device` to sync the APNs token, the Explore-specific push
  preference, the independent comment mention push preference, and the
  independent Community identification push preference

The Explore map additionally uses:

- `/get-explore-map-points` for cluster or waypoint payloads in the current
  visible region
- `ExploreMapPointsResponse`, `ExploreMapCluster`, and `ExploreMapPost` from
  `ExploreAPIModels.swift`
- `ExplorePostStore` as the shared in-memory post state layer, so likes,
  unshares, reports, and blocks stay synchronized between the feed tab, map
  preview card, detail route, and notification-driven navigation
- a two-step interaction in `ExploreMapView`: tap a waypoint to select and
  preview, then open `ExplorePostDetailView`
- a zoom-aware annotation treatment in `ExploreMapView`, where cluster payloads
  stay aggregate at broad zooms and individual `ExploreMapPost` payloads can
  render either simple dots or thumbnail-backed markers depending on the current
  client camera zoom and visible post count

Time and weather metadata remain in the contract for future Explore presentation
experiments, but are not currently rendered on the primary feed card.

Remote Explore APNs delivery is layered on top of this contract through the
internal `send-push-notification` webhook path. That webhook is not called by
the iOS client directly; it is triggered server-side from
`public.explore_post_notifications`. Follow notifications are excluded from push
dispatch and remain in-app only. Comment mention pushes are dispatched only to
devices with `comment_mentions_enabled` enabled; regular Explore activity pushes
use `explore_enabled`. Community Identification pushes include
`communityRequestId` and use `community_identifications_enabled`. The in-app
notification row is still retained even when the related push toggle is off.

Preferred species display names are not part of the Explore endpoint payload.
The iOS client syncs `user_species_preferences` directly through PostgREST under
Supabase RLS, hydrates
`ExploreFeedViewModel.preferredSpeciesNamesByScientificName` from local
SwiftData, and applies those names in feed cards, map previews, comments, detail
titles, and share text.

---

## Deno `/identify-multimodal` Edge Node

A unified identification pipeline that merges the active capabilities of
`/identify` and the app's shipped non-visual flows into a single multi-modal
entry point. The current iOS client routes new inference traffic here. Supports
ordered compositions of images, audio, and descriptive context.

### The JSON Request Payload (From Swift `OfflineQueueManager`)

```json
{
  "r2ObjectKeys": [
    "staging/A1B2C3D4.../uuid_image_1.webp"
  ],
  "videoR2ObjectKeys": [
    "staging/a1b2c3d4.../uuid_video_1.mp4"
  ],
  "videoFrameCount": 5,
  "visualMediaItems": [
    { "kind": "image", "sourceIndex": 0 },
    { "kind": "video_frame", "clipIndex": 0, "frameIndex": 0 },
    { "kind": "video_frame", "clipIndex": 0, "frameIndex": 1 },
    { "kind": "video_frame", "clipIndex": 0, "frameIndex": 2 },
    { "kind": "video_frame", "clipIndex": 0, "frameIndex": 3 },
    { "kind": "video_frame", "clipIndex": 0, "frameIndex": 4 }
  ],
  "audioMediaItems": [
    { "kind": "video_audio", "clipIndex": 0 }
  ],
  "audioR2ObjectKeys": [
    "staging/a1b2c3d4.../uuid_audio.wav"
  ],
  "imageBase64s": ["<base64>"],
  "audioBase64s": ["<base64>"],
  "user_id": "Supabase Auth UUID",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "semanticLocation": "Zilker Park",
  "publicLocationLabel": "Austin, Texas",
  "geoprivacy": "obscured",
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

- Features dynamic `MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION` execution if audio
  and visual evidence are both present, regardless of whether the audio arrived
  inline, from R2 staging, or as extracted audio from a video scan.
- Video scans send five ordered sampled frames through the image payload path,
  extracted accompanying audio through the audio payload path when available,
  and stage the upload-bounded playback `.mp4` in `videoR2ObjectKeys`. That
  staged video is normally a compressed 720p export, but clients may fall back to
  the original recording when it is already within the hard video byte cap. New clients send
  `visualMediaItems` (or snake-case `visual_media_items`) with one entry per
  resolved visual input so the prompt can distinguish still photos from ordered
  `video_frame` samples by `clipIndex` and `frameIndex`; `audioMediaItems` (or
  `audio_media_items`) identifies standalone audio versus `video_audio` by
  `clipIndex`. If the visual metadata count does not match the resolved image
  count, the edge ignores it and falls back to the legacy `videoFrameCount` hint;
  if the audio metadata count does not match the resolved audio buffer count,
  the prompt treats the audio as ordinary standalone audio. The playback clip is
  promoted only after those frames pass moderation and is not used as Gemini
  inference or reference-media input. If `videoR2ObjectKeys` is non-empty, the
  scan is only successful when every requested video key is promoted and
  persisted into `video_storage_urls` and `captured_media`; otherwise the client
  receives a retryable failure rather than a frame-only video scan. Uploads
  signed with `clientScanId`/`mediaRole` already have staged
  `scan_media_assets` rows; this endpoint links those rows to the scan as
  `promoted`, marks consumed audio rows `deleted`, and marks failed finalization
  rows `failed`.
- Before inference work starts, the endpoint claims a `scan_ingestion_jobs` row
  for the authenticated user and `client_scan_id`. The claim records media
  counts, staged image/audio/video object keys, recovered upload-session ids, and
  a normalized `manifest_checksum`; subsequent stage updates make
  `/check-scan-status`, health checks, and reconciliation agree on whether the
  scan is processing, retryable, complete, or terminal.
- The endpoint also records a `scan_ingestion_intents` row for server recovery.
  That row stores a sanitized replay payload with telemetry, observation context,
  media descriptors, staged keys, upload-session ids, and a `payload_checksum`.
  It never stores raw base64 media bytes or local device paths. Requests that
  used inline foreground media are marked `resumable = false` with
  `inline_media_redacted = true`; queued/staged-media requests are resumable.
- The edge writes `captured_media` for new multimodal scan rows. That JSON keeps
  still photos as image items but collapses ordered `video_frame` samples into a
  single video media item with a thumbnail reference, preserving playback-first
  Insight hydration for biological and non-biological video scans. The
  ready display/playback `scan_media_assets` rows are refreshed from the same
  manifest by the database trigger plus a best-effort Edge refresh call, so
  server-side composer and status checks no longer need to infer video assets
  directly from sampled frame arrays.
- Executes `processWAV` in Deno to enforce mono/16kHz processing before Gemini
  ingestion.
- Queued replay audio uses `audioR2ObjectKeys`; queued and live video use
  `videoR2ObjectKeys`; live foreground audio uses size-preflighted inline
  `audioBase64s`. The edge rejects oversized declared media JSON
  `Content-Length` before body parsing, then parses through
  `readRequestJsonWithinBudget` so missing-length/chunked bodies are still
  capped. Clip count, byte budgets, IDOR ownership, and path traversal are
  validated through `_shared/identify/media.ts` before decode/fetch.
- The canonical request contract is camelCase telemetry (`gpsLatitude`,
  `semanticLocation`, `publicLocationLabel`, `geoprivacy`, `deviceTimeZone`,
  etc.) plus `observation_contexts: [{ freeText, addedAt? }]`, matching
  `MerianNetworkClient.buildMultiModalRequest(...)` and the iOS
  `ObservationContext` model. The same Swift inference payload builder also
  backs `/identify` so visual and multimodal requests share telemetry
  formatting, user context, and pre-serialization inline media budget
  validation.
- If `geoprivacy` is missing, invalid, or supplied by an old queued payload, the
  Edge insert helper resolves the scan privacy from `users.default_geoprivacy`.
  Private scans clear `public_location_label` server-side even if a stale client
  supplied one.
- `deviceTimeZone` is persisted to `public.scans.device_time_zone` when present
  so public profile streaks and heatmaps can use the author's local day
  boundary. Missing or invalid legacy rows fall back to UTC at profile-read
  time.
- The server still accepts legacy snake_case telemetry aliases (`gps_latitude`,
  `semantic_location`, `time_of_day`, etc.) and legacy `free_text` context keys
  so offline queue replays and older internal tooling do not break
  mid-migration.
- Candidate handling now matches `/identify`: the response strips `candidates`
  when `confidence_score >= diagnosticTrigger`, enriches forwarded candidates
  with cached English common names when available, and schedules background
  enrichment for cache misses.
- The multimodal background ingestion path shares the same `_shared/identify`
  DB, media, schema, threshold, and moderation primitives as `/identify`.

## Text-Only Describe Path

The current app routes text-only observations through `/identify-multimodal`
with `observation_contexts` populated and no images or audio attached. Locally,
that request is still assembled from the same canonical mixed-media timeline
used by image and audio submissions; the server simply receives an empty media
body plus the description payload.

### Request Payload

```json
{
  "user_id": "Supabase Auth UUID",
  "client_scan_id": "UUID generated by iOS for idempotency",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "semanticLocation": "Zilker Park",
  "publicLocationLabel": "Austin, Texas",
  "geoprivacy": "obscured",
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

`client_scan_id` is generated by the iOS client and forwarded as
`generatedScanId` to the edge function. The current multimodal text-only path
inserts through the shared `insertScan` contract using the same idempotent scan
ID semantics as image and audio requests.

The current iOS client does not send a top-level `description` field on this
path. The edge function concatenates the `observation_contexts[*].freeText`
entries into the multimodal prompt server-side. The first structured context
object is also persisted to `public.scans.user_observation_context` for
scan-level provenance. The iOS client guards on `ObservationContext.isEmpty`
before allowing submission.

`r2ObjectKeys`, `imageBase64s`, and `audioBase64s` are intentionally absent —
there is no media in a text-only submission. `scans.image_storage_urls` is
written as an empty image array by the shared insert path because there is no
promoted media to persist.

### Response Schema

The response shape mirrors the `/identify` / `/identify-multimodal` JSON
response exactly. `scan_id` is returned as the scan UUID generated for that
text-only request.

### IDOR & Auth

The server extracts the user identity from the `Authorization: Bearer` JWT via
`supabaseAdmin.auth.getUser()`. The `user_id` in the request body is ignored for
auth purposes.

### Error Responses

| Status | Body                                                                   | Meaning                                                                            |
| ------ | ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `400`  | `{ "error": "At least one media element or description is required" }` | No image, audio, or non-empty `observation_contexts[*].freeText` text was provided |
| `400`  | `{ "error": "AI processing error. Please try again." }`                | Permanent Gemini safety / policy failure                                           |
| `422`  | `{ "error": "Processing Error: Malformed AI response." }`              | Gemini returned unparseable output                                                 |
| `503`  | `{ "error": "AI processing error. Please try again." }`                | Transient Gemini failure                                                           |

---

## Deno `/enrich-scan` Edge Node

An enrichment endpoint that asynchronously surfaces habitat, taxonomy, and
similar species data for a scan. Called automatically by the iOS client after
every successful biological scan completes — the user sees a loading skeleton in
`HabitatAndDistributionCard` while this request is in flight.

### Request Payload

```json
{
  "scan_id": "A1B2C3D4-...",
  "scientific_name": "Danaus plexippus",
  "confidence_score": 0.91,
  "inference_tier": "flash"
}
```

Only `scientific_name` is strictly required by the Edge function. `scan_id`,
`confidence_score`, and `inference_tier` are sent by the iOS client for
telemetry but are not used server-side — the Edge function applies no confidence
gating of its own.

### Architecture

**No Tier Gate**: Available to all authenticated users. Enrichment data is
generated by Flash and cached in `species_dictionary` at the species level —
subsequent calls for the same species are served from cache with no AI call.

**No Confidence Gate**: The Edge function accepts `confidence_score` for
telemetry compatibility but does not use it to decide whether similar species
should be generated or returned. Similar-species generation is gated by taxonomy
quality and cache state, not confidence, and the iOS gallery renders validated
entries with the stable "Similar species" label.

**Full Cache Hit**: If `species_dictionary` already has `habitat_description`,
usable taxonomy (`kingdom` plus `order` or `family`), and validated
`species_lookalikes` rows for this species, the function returns all data
immediately with no Gemini calls — typically sub-50ms.

**Two-Layer Lookalike Strategy**:

- **Layer 1 — Taxonomy trigger (zero token cost)**: A Postgres `AFTER INSERT`
  trigger (`trg_link_taxonomy_lookalikes`) auto-populates `species_lookalikes`
  with same-genus links whenever a new species row is inserted, but only when
  both rows have a real genus and matching kingdom. Placeholder taxonomy such as
  `"Unknown"` is normalized away and never participates in trigger linking.
- **Layer 2 — Gemini Flash for cross-family visual mimics**:
  `fetchSimilarSpecies` is only invoked when the `species_lookalikes` join table
  is empty, `similar_species TEXT[]` has no usable legacy names, and the primary
  species already has usable taxonomy. Flash receives the species' normalized
  taxonomy (`kingdom`, `class`, `order`, `family`) from `cachedSpecies` and is
  constrained by the system instruction to return lookalikes from the **same
  taxonomic order** — not merely the same kingdom. After Gemini returns entries,
  `resolveLookalikesToJoinTable` validates the candidates again before writing
  anything durable.

**Taxonomy Grounding (`fetchSimilarSpecies` + `resolveLookalikesToJoinTable`)**:
Flash is passed normalized `kingdom`, `class`, `order`, and `family` from
`species_dictionary`. Placeholder strings like `"Unknown"` or blank values are
collapsed to `null` before prompting. The system instruction explicitly forbids
cross-order results (e.g. grasses as lookalikes for Narcissus — both Plantae but
different orders). `resolveLookalikesToJoinTable` now requires a real
`primaryKingdom` and at least one higher-rank discriminator (`primaryOrder` or
`primaryFamily`). Each resolved candidate must have a real matching `kingdom`,
and then either a matching `order` or, if order is unavailable on both sides, a
matching `family`. Candidates with missing taxonomy or no `species_dictionary`
row are dropped rather than returned as provisional stubs. **Early-exit on
insufficient taxonomy**: If the primary species lacks usable taxonomy, the
lookalikes scope returns `similar_species: null` and does not call Flash.
`lookalikes_flash_attempted` is **only** set to `true` when
`resolveLookalikesToJoinTable` returns `persisted: true`, ensuring the flag
never locks before validated data is in the join table.

**Automatic Stale Contamination Detection**: On each `lookalikes` scope request,
`index.ts` compares the primary species' normalized `order` or `family` against
cached join-table entries. If the primary species has a known `order` and every
cached entry has a different known order, or if order is unavailable but family
is known and every cached entry has a different known family, the stale rows are
automatically cleared via `clearLookalikesForSpecies`,
`lookalikes_flash_attempted` is reset to `false`, and a fresh validated attempt
can run. This is self-healing for the characteristic contamination signature
created by old placeholder-taxonomy writes.

**Manual Cache Invalidation**: For one-off fixes, cross-order (or cross-kingdom)
lookalikes cached before the automatic detection was introduced can still be
cleared manually:

```sql
DELETE FROM species_lookalikes
WHERE species_id = (SELECT id FROM species_dictionary WHERE scientific_name = '<scientific_name>');
UPDATE species_dictionary SET similar_species = NULL, lookalikes_flash_attempted = FALSE
WHERE scientific_name = '<scientific_name>';
```

The next `enrich-scan` call will re-run Flash only after the species has usable
taxonomy.

**Migration Path**: If the join table is empty but `similar_species TEXT[]` has
legacy name strings (populated by older pipeline versions), they are resolved to
the join table at zero token cost before returning, using the same
kingdom/order/family validation as fresh Flash output.

**Parallel Flash Generation**: If enrichment data is missing, encyclopedic
enrichment (`fetchStaticEncyclopedicData`) and similar species generation
(`fetchSimilarSpecies`) can still run concurrently via `Promise.all`. Both use
`gemini-2.5-flash` with `temperature: 0.1`. The difference now is that
lookalikes only participate in that parallel branch when the primary species
already has usable taxonomy; otherwise the function returns metadata first and
the iOS client retries the lookalikes scope once taxonomy lands.

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
        "species_id": "uuid",
        "scientific_name": "Limenitis archippus",
        "common_name": "Viceroy",
        "reference_image_url": "https://inaturalist-open-data.s3.amazonaws.com/...",
        "iucn_red_list_status": "LC",
        "reason": "Similar orange-and-black wing pattern.",
        "visual_traits": ["orange wings", "dark venation"],
        "confidence": 0.86,
        "source": "model_enrichment",
        "review_status": "unreviewed",
        "is_bidirectional": false,
        "sort_order": 0
      },
      {
        "species_id": "uuid",
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

`gbif_taxon_key` is `null` when the species has not yet been matched by GBIF.
`similar_species` is `null` when no validated lookalike data is available,
including the intentional case where the species still lacks usable taxonomy.
Each entry in the `similar_species` array is sourced from the
`species_lookalikes` join table joined to `species_dictionary` — providing
`species_id`, `common_name` (English), `reference_image_url`,
`iucn_red_list_status`, and additive relation metadata (`reason`,
`visual_traits`, `confidence`, `source`, `review_status`, `is_bidirectional`,
`sort_order`) when available. The image URL prefers the first
`species_reference_images` row and falls back to the legacy dictionary cache.
Raw Gemini names with no dictionary/taxonomy validation are no longer returned
or persisted; legacy `similar_species TEXT[]` fallbacks may omit `species_id`
and relation metadata until they are resolved into the join table. Successful
enrichment writes also record source/freshness metadata in
`species_content_provenance`; this does not change the client response.

`alternative_common_names` is `string[] | null` — `null` when GBIF has no
English vernacular entries for the species. The enrichment scope serves this
field from `species_dictionary.alternative_common_names` on a cache hit. When
that column is `null` (covering both pre-V34 cached species and the timing race
where a first scan's background ingestion has not yet written to the
dictionary), the Edge function calls `fetchGBIFVernacularNames` live to retrieve
English vernacular names from the GBIF API and populates the field from the
result. Taxonomy fields in the response likewise use `null` for unknown ranks;
the backend no longer emits placeholder strings like `"Unknown"`.

**iOS mapping**: The array is decoded as
`[EnrichScanResponse.SimilarSpeciesEntry]` (snake_case Codable DTO in
`InferenceEdgeDTOs.swift`) and mapped to the domain `SimilarSpecies` struct
(camelCase, in `SpeciesData.swift`). `InferenceEngine.fetchAndApplyEnrichment`
then JSON-encodes `[SimilarSpeciesEntry]` via `JSONEncoder` into a `Data` blob
and persists it as `LocalScanRecord.lookalikesData` (added in `MerianSchemaV27`)
— the primary SwiftData storage for rich lookalike data. The legacy
`LocalScanRecord.similarSpecies: [String]?` field is retained as a
backwards-compatible fallback for pre-V27 records where `lookalikesData` is nil.
`InferenceEngine.load(from:)` also supports a one-time local cache reset version
so previously poisoned `lookalikesData` blobs are ignored and refreshed through
the hardened backend validation path. `SimilarSpeciesGallery` always labels
validated entries as "Similar species"; identification uncertainty is handled by
the separate candidates/review surface.

**Per-user daily rate limit**: Effective free users are throttled after 50
`enrich-scan` requests per day (proxy for LLM budget). The tier is resolved via
`getTierForUser` from `_shared/tierCache.ts`, which returns the effective tier
from the paid/trial/free resolver. When the limit is exceeded the function
returns `429 Too Many Requests` before any Gemini call is made. Effective Pro
users, including active trial users, are exempt.

### Error Responses

| Status | Body                                                      | Meaning                               |
| ------ | --------------------------------------------------------- | ------------------------------------- |
| `400`  | `{ "error": "Missing required parameters..." }`           | `scan_id` or `scientific_name` absent |
| `400`  | `{ "error": "AI processing error during enrichment..." }` | Gemini generation failure             |
| `429`  | `{ "error": "Rate limit exceeded. Try again tomorrow." }` | Free-tier daily quota exceeded        |

---

## Deno `/insight-chat` Edge Node

Private Pro follow-up chat for completed biological Insight sheets. The endpoint
uses the authenticated Supabase user from `withEdgeHandler`, verifies ownership of
`scan_id`, and resolves the effective tier through `_shared/tierCache.ts`.

### Request Payload

```json
{
  "action": "send",
  "scan_id": "A1B2C3D4-...",
  "message_text": "What traits support this identification?",
  "client_message_id": "11111111-1111-4111-8111-111111111111"
}
```

Feedback and field-notes summary actions use the same endpoint:

```json
{
  "action": "feedback",
  "scan_id": "A1B2C3D4-...",
  "message_id": "33333333-3333-4333-8333-333333333333",
  "feedback_rating": "wrong",
  "feedback_note": "Optional short private note"
}
```

```json
{
  "action": "feature_feedback",
  "scan_id": "A1B2C3D4-...",
  "feature_feedback_sentiment": "positive",
  "feedback_note": "Optional short private note"
}
```

```json
{
  "action": "summarize_notes",
  "scan_id": "A1B2C3D4-..."
}
```

AI-generated quick prompts use the same endpoint and never include user draft
text:

```json
{
  "action": "suggest_prompts",
  "scan_id": "A1B2C3D4-..."
}
```

`action` accepts `load`, `send`, `delete`, `feedback`, `feature_feedback`,
`summarize_notes`, or `suggest_prompts`.
`load` returns the single saved conversation for the scan when one exists.
`send` creates that conversation when missing, requires `message_text`, and may
include `client_message_id` for idempotency. `delete` clears the scan's saved
chat. `feedback` stores private owner-only answer feedback for an assistant
`message_id` with `feedback_rating` (`helpful`, `not_helpful`, `wrong`,
`unsafe`, `other`) and optional `feedback_note`. `feature_feedback` stores
private owner-only feedback on the Field chat sheet itself with optional
`feature_feedback_sentiment` (`positive` or `negative`) and optional
`feedback_note`; at least one is required. `summarize_notes` returns a reviewable
field-notes draft from the current saved chat and scan context; the client must
append it only after user confirmation and must never replace existing field
notes. `suggest_prompts` returns three short, non-persisted prompt chip
suggestions plus allowlisted categories for telemetry; it uses the same owned
scan context and recent saved chat history, does not consume the daily send
limit, and is best-effort so load/send chat behavior remains independent if
prompt generation fails. The server caps v1 at 600 characters per user message,
30 total messages per conversation, and 20 sends per Pro user per day across all
of that user's Insight chats. Effective Pro includes active trial users.

### Prompt and Privacy Boundary

The server builds chat context from stored text data only: species names,
taxonomy, hazard type, confidence, candidates/lookalikes, habitat/Wikipedia
overview, invasive flag plus its original AI region/rationale/confidence,
identification provenance, user review state, observed traits, ecological
annotations, species group tags, `ai_reasoning`, field notes, capture
date/month, location label, weather, elevation, and image/capture-quality
metadata. It does not include raw image bytes, R2 object keys, cloud image URLs,
internal scan IDs, exact GPS coordinates, Explore comments, public post
metadata, or Darwin Core export payloads.

Location-aware answers may use only the saved private location label, month,
elevation, ecology type, and weather. The prompt explicitly forbids inferring,
requesting, revealing, or reconstructing exact GPS coordinates.

The Gemini request uses `gemini-2.5-flash` with a stable prompt prefix,
`maxOutputTokens: 700`, no streaming, no Google Search grounding, and thinking
disabled. Assistant messages store model/token telemetry, including cached tokens
when Gemini reports implicit cache hits.

Prompt suggestions are generated with the same text-only privacy boundary. The
model must return exactly three short prompt strings with safe categories such as
`evidence`, `lookalike_compare`, `habitat`, `season`, `hazard`, `invasive`,
`confidence`, `field_notes`, or `generic`. The guardrail prompt forbids edible
certainty, medical/veterinary treatment, illegal collection, pesticide/poison
instructions, exact-location requests, and human-subject identification.

### Response Payload

```json
{
  "data": {
    "conversation_id": "22222222-2222-4222-8222-222222222222",
    "messages": [
      {
        "id": "33333333-3333-4333-8333-333333333333",
        "role": "user",
        "text": "What traits support this identification?",
        "created_at": "2026-06-26T16:20:00.000Z",
        "is_refusal": false,
        "refusal_reason": null
      },
      {
        "id": "44444444-4444-4444-8444-444444444444",
        "role": "assistant",
        "text": "The saved evidence points to...",
        "created_at": "2026-06-26T16:20:02.000Z",
        "is_refusal": false,
        "refusal_reason": null
      }
    ],
    "limits": {
      "max_user_message_chars": 600,
      "max_messages_per_conversation": 30,
      "daily_send_limit": 20,
      "sends_remaining_today": 19
    }
  }
}
```

For `suggest_prompts`:

```json
{
  "data": {
    "conversation_id": "22222222-2222-4222-8222-222222222222",
    "prompts": [
      {
        "text": "Which leaf detail should I check next?",
        "category": "evidence"
      },
      {
        "text": "Could this be a lookalike?",
        "category": "lookalike_compare"
      },
      {
        "text": "Does this habitat fit?",
        "category": "habitat"
      }
    ]
  }
}
```

For `feedback`:

```json
{
  "data": {
    "ok": true,
    "message_id": "33333333-3333-4333-8333-333333333333",
    "rating": "wrong"
  }
}
```

For `feature_feedback`:

```json
{
  "data": {
    "ok": true,
    "id": "44444444-4444-4444-8444-444444444444",
    "sentiment": "positive"
  }
}
```

For `summarize_notes`:

```json
{
  "data": {
    "summary_text": "Concise reviewed draft text for append-only field notes."
  }
}
```

### Safety and Errors

The system prompt states the assistant has no raw image access and answers only
from stored scan evidence. The Edge Function refuses or redirects edible/foraging
certainty, medical/veterinary treatment, dangerous handling, illegal collection,
pesticide/poison instructions, and human-subject identification requests.

| Status | Body | Meaning |
| ------ | ---- | ------- |
| `400` | `{ "code": "unsupported_scan", ... }` | Scan is non-biological or request shape is invalid |
| `402` | `{ "code": "pro_required", ... }` | Effective tier is not Pro/trial |
| `404` | `{ "code": "scan_not_ready", ... }` | No owned completed scan row exists yet |
| `429` | `{ "code": "daily_limit_reached", ... }` | Daily send cap reached |

Telemetry emits `InsightChatSent`, `InsightChatAnswered`, `InsightChatRefused`,
`InsightChatRateLimited`, `InsightChatModelError`,
`InsightChatPromptsGenerated`, `InsightChatFeedbackSubmitted`,
`InsightChatFeatureFeedbackSubmitted`, and `InsightChatNotesSummarized` with
latency and token fields when available. Send/answer events include a
deterministic `answer_category` so token cost can be reviewed by broad question
type. Prompt generation events include prompt categories, fallback/error state,
and token usage when available. iOS also emits `InsightChatActionTapped` to
PostHog for local answer actions, prompt-chip taps, the sheet options menu, and
feedback affordances.

---

## Deno `/sync-collections` Edge Node

Synchronizes locally created Scan Collections with the PostgreSQL `collections`
and `collection_scans` schemas, handling diffing and missing FK references.

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

1. **Dual Casing Delete Parsing**: To protect against Swift `JSONEncoder`
   converting structural snake_case keys into camelCase payloads based on
   codable strategies, the Edge function supports both `is_deleted` and
   `isDeleted` attributes when resolving the deleted tombstone array.
2. **Batch Upserts**: All valid collections are written via a single atomic
   `.upsert(collectionPayloads)` call, resolving PostgreSQL `TIMESTAMPTZ` and
   `UUID` types without timing out. **The upsert now throws on database error**
   rather than logging silently — `upsertCollectionsAndFetchMemberships`
   propagates the error through `withEdgeHandler` so the iOS client receives
   `HTTP 500` and can retry rather than treating a failed collection persist as
   a successful sync.
3. **Centralised Ownership Filter (`filterOwnedCollections`)**: `index.ts` calls
   `filterOwnedCollections(userId, collections, supabaseAdmin)` before any write
   proceeds. This function queries the existing `collections` rows for the
   incoming IDs and removes any whose `user_id` does not match the authenticated
   user. The pre-filtered, ownership-verified set is then passed to all
   downstream functions (`upsertCollectionsAndFetchMemberships`,
   `syncMembershipDelta`, `deleteCollections`) — no downstream function needs to
   re-implement the ownership check independently. Collection IDs owned by other
   users are silently dropped.
4. **Delete IDOR Guard**: `deleteCollections` additionally scopes the DELETE
   query with `.eq("user_id", userId)` as a defence-in-depth layer.
   `deleteCollections` now throws on database error rather than logging
   silently, preventing false-success `200` responses when the deletion fails.
5. **Bulk Insertion & Mismatched FK Protection**: Setting up `collection_scans`
   relationships natively in a single atomic upsert avoids N+1 query timeouts.
   To prevent PostgreSQL Foreign Key violations from crashing the overarching
   chunk transaction, the Edge Node dynamically pre-validates all incoming
   `scan_id` payloads against the core `scans` table. If a user groups a scan
   while fully offline and the physical cloud `scans` row hasn't populated yet,
   mapping intelligently bypasses that specific missing scan natively. The
   pending relationship rests securely offline on the user's iPhone until the
   next sync pulse. Existing memberships are hydrated for all owned collections
   with one paginated `.in("collection_id", ownedIds)` query ordered by
   `(collection_id, scan_id)`, rather than one pagination loop per collection.
   This keeps latency sublinear for users with many collections while bounding
   each page in V8 memory.
6. **Array-Bound Diffing Deletes**: Identifies obsolete collections by running
   `.select()` across the user's DB rows, building a `toDelete` array in memory
   and passing it to `.delete().in("id", toDelete)`. This avoids
   `.not("id", "in", "(...)")` string-builder failures.
7. **Strict Upstream Concurrency Latch**: Because `BackgroundTaskWrapper` calls
   push network traffic simultaneously out-of-order, the iOS client strictly
   clamps `sync-collections` invocations behind a shared collection
   single-flight latch. `OfflineQueueManager` retains the active
   `collectionSyncTask`, so concurrent callers await the same request instead of
   launching parallel pushes. A monotonic `collectionSyncRevision` is captured
   when each request starts; the coalesced `OfflineJobRecord(id:
   "collection-sync")` is marked complete only if no newer collection mutation
   was enqueued while that request was in flight. This prevents race conditions
   where a stale `.upsert()` snapshot lands after a newer `.delete()`, causing
   ghost resurrections.

> **Parameter naming**: The `syncMembershipDelta` function parameter names were
> updated from `validCollections`/`activeIds` to `ownedCollections`/`ownedIds`
> to reflect that all inputs are pre-ownership-checked by the time they reach
> that function.

**Critical Kong API Gateway Requirement**: To allow `sync-collections` to
manually parse and extract the JWT using Deno `.headers.get("Authorization")`,
the edge function must be explicitly exposed in `services/supabase/config.toml`
with `verify_jwt = false`. If not disabled, Kong dynamically strips the
`Authorization` header before it reaches Deno to prevent replay attacks, causing
a `401 Unauthorized: Missing Authorization header` response from the Edge
Runtime.

---

## Deno `/check-scan-status` Edge Node

Provides a lightweight outbox confirmation endpoint. After the iOS client
receives an HTTP 200 from `/identify`, it can poll this endpoint to confirm the
scan row actually landed in the `scans` table — mitigating the transactional
outbox gap where the 200 is returned before the background `insertScan` has
committed.

### Request Payload

```json
{ "scan_id": "<UUID>", "required_video_count": 1 }
```

`required_video_count` is optional. Omit it for legacy/image status probes. When
present and greater than zero, the endpoint returns `"found"` only if the scan
row exists for the authenticated user and has at least that many public
`video_storage_urls` plus matching ready playback entries in `scan_media_assets`
or video entries in `captured_media`.

### Response Payload

```json
{
  "status": "found",
  "job_status": null,
  "job_stage": null,
  "job_attempt_count": null,
  "retry_after": null,
  "last_error": null
}
```

`status` remains the compatibility field and is still only `"found"` or
`"not_found"`. When the scan row is not complete yet, newer clients and ops
tools can inspect the optional job fields backed by `scan_ingestion_jobs`:
`job_status` may be `processing`, `finalizing`, `retrying`,
`failed_retryable`, `failed`, or `complete`; `job_stage` names the precise
server step; `retry_after` and `last_error` are only populated for failed jobs.
iOS decodes the full response via `ScanStatusResponse`: queued scans use these
fields to keep server-owned `.inferencing` rows from being resubmitted while
media promotion or scan insertion is still finalizing.

### Authentication & IDOR

The `Authorization: Bearer` JWT is verified by `withEdgeHandler`. The DB query
enforces ownership with a dual `.eq("id", scan_id).eq("user_id", user.id)`
constraint — a user cannot probe another user's scan IDs. The query returns only
the media fields needed for the durability check (`id`, `video_storage_urls`,
`captured_media`, normalized scan-media asset rows, and the user's own
scan-ingestion job state); no private scan content is transmitted.

### Architecture

Follows the domain-driven module pattern: `index.ts` orchestrates auth,
parameter validation, and optional video-count gating; `db.ts` owns the
`fetchScanStatusMedia(scanId, userId, supabaseAdmin)` PostgREST call. No `db.ts`
writes occur. Errors from `fetchScanStatusMedia` are caught by `index.ts` and
mapped to a structured `logStructuredError` + 500 response.

---

## Deno `/get-filtered-discovery-feed` Edge Node

Fetches the global social feed of public biological captures, excluding the
requesting user and any users they have blocked.

### Feed Query Strategy

Block list and feed are fetched in **parallel** via `Promise.all`:

```typescript
const overFetchLimit = limit + Math.max(20, Math.ceil(limit * 0.2));
const [blockedIds, rawFeed] = await Promise.all([
  fetchBlockedUserIds(user.id, supabaseAdmin),
  fetchDiscoveryFeed(user.id, overFetchLimit, supabaseAdmin),
]);
const excludedSet = new Set(blockedIds);
const feedData = rawFeed.filter((s) =>
  s.user_id != null && !excludedSet.has(s.user_id)
).slice(0, limit);
```

`fetchDiscoveryFeed` excludes only the requesting user at the DB level
(`.neq("user_id", selfId)`). Blocked user filtering is applied post-query in
TypeScript. To compensate for rows removed by the block filter, the DB query
over-fetches by `Math.max(20, 20% of limit)` rows. For the default limit of 20,
this fetches up to 40 rows. Block list filtering happens on the fast in-memory
`Set`, not in the SQL query — this eliminates a SQL variable-length array
parameter that required manual escaping.

### Authentication Enforcement

The endpoint extracts user identity from the `Authorization: Bearer` header via
`supabaseAdmin.auth.getUser()`, ignoring any `userId` in the request body.

**Critical Kong API Gateway Requirement**: Because we use `URLSession` inside
`MerianNetworkClient` instead of the Supabase Swift SDK, all HTTP requests to
Deno **MUST** include both the `Authorization: Bearer <JWT>` header AND the
`apikey: <SUPABASE_ANON_KEY>` header. If the `apikey` header is omitted, the
Supabase Kong API Gateway strips the `Authorization` header before it reaches
the Edge Function, causing `401 Unauthorized: Missing token`.

Any request with a manipulated JSON body but no valid JWT signature in the
header returns `401 Unauthorized`.

### Global Geoprivacy & Endangered Species Shielding

To prevent location tracking and poaching of IUCN Endangered, Vulnerable, or
Near-Threatened species, the endpoint runs a post-processing `map` loop before
JSON transmission. The `.gps_lat_exact` and `.gps_long_exact` fields are removed
from every scan in the payload, regardless of the user's geoprivacy setting.
Additionally, if the taxonomy flags a capture as a protected species, the
endpoint rounds `gps_lat_public` coordinates to 11km tiles.

---

## Deno `/merge-ghost-profile` Edge Node

Transfers ownership of records from an anonymous Ghost Session to a newly
authenticated Google/Apple ID.

### Request Payload

```json
{
  "ghost_id": "Transient Anonymous UUID to merge"
}
```

### Authentication Enforcement

1. Calls `supabaseAdmin.auth.getUser(jwt)` to extract the verified
   `targetUserId`.
2. Calls `supabaseAdmin.auth.admin.getUserById(ghost_id)` and validates
   `is_anonymous === true`. If a malicious actor passes a fully authenticated
   user's ID to hijack their scans, the endpoint returns `403 Forbidden`.
3. Transfers owned data before purge in this order: `scans`, `collections`,
   `explore_posts`, `explore_community_requests`, and follow rows. Community
   request transfer is required because
   `explore_community_requests.requested_by` references
   `public.users(id) ON DELETE CASCADE`; deleting the ghost public user before
   reparenting would remove active Ask the Community requests.
4. Refreshes the target public Explore identity.
5. Deletes the `ghost_id` via `.deleteUser(ghost_id)` and removes the ghost
   `public.users` row.

---

## Deno `/safe-delete` Edge Node

Tombstones a user's account and initiates deletion of all associated data from
PostgreSQL and Cloudflare R2.

### Request Payload

No JSON body is required. The endpoint operates from the JWT identity alone to
prevent IDOR vulnerabilities.

### Authentication Enforcement

1. Calls `supabaseAdmin.auth.getUser()` to extract the authenticated user's UUID
   from the `Authorization: Bearer` header.
2. **Revokes auth first** — calls `supabaseAdmin.auth.admin.deleteUser(user.id)`
   to immediately invalidate the user's JWT before any data mutation. This
   prevents the user from issuing new API calls during cleanup.
3. Executes the `apply_user_tombstone` PostgreSQL RPC against the authenticated
   `user.id`. The RPC cascades through `public.scans`, `public.user_blocks`, and
   `public.flagged_reviews`, removing rows and triggering Cloudflare R2 object
   purges.
4. Queues storage deletion for background processing.
5. **Partial-failure handling**: If step 3 or 4 throws after auth has already
   been revoked, a structured error is logged via `logStructuredError` with
   `event: "safe_delete_partial_failure"` and
   `action_required: "Manually run apply_user_tombstone RPC"`, and the error is
   re-thrown so the response is `500 Internal Server Error` rather than a
   false-success `200 OK`.
6. Returns `200 OK` only when all steps succeed. The iOS client then calls
   `signOut()`, drops all local SQLite `ModelContext` state via
   `ScanRepository.purgeAllData()`, and resets to Guest.

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

1. Extracts the verified user identity from the GoTrue JWT via the native
   `withEdgeHandler` middleware.
2. Extracts `scanId` from the payload and queries `public.scans` using the
   Service Role.
3. If the scan does not exist (e.g. already purged server-side while offline),
   returns HTTP 200 so the Swift queue system drops the pending deletion
   cleanly.
4. Compares the fetched `scan.user_id === user.id`. A mismatch natively returns
   `403 Forbidden` as an explicit IDOR trap.
5. Deletes all Cloudflare R2 objects referenced in `image_storage_urls` and
   `video_storage_urls` via the `AwsClient`, avoiding 404 errors from namespace
   duplication. Public `explore_post_media` rows are hidden or removed with the
   backing scan/post cleanup path.
6. Deletes the Postgres row.

---

## Deno `/block-user` Edge Node

Inserts a moderation block, removing the specified user from the authenticated
user's Discovery Feed via `SocialGuardManager`.

### Request Payload

```json
{
  "blocked_id": "Target UUID to block"
}
```

### Authentication Enforcement

- Extracts the verified user identity from the GoTrue JWT via the native
  `withEdgeHandler` middleware.
- Validates `blocked_id` as a well-formed UUID — a non-UUID string is rejected
  with `HTTP 400` before any database access.
- Upserts the block into `public.user_blocks` using
  `onConflict: "blocker_id,blocked_id"` with `ignoreDuplicates: true`, making
  repeated block requests fully idempotent. A second block by the same user
  returns `200 OK` without inserting a duplicate row or surfacing a constraint
  error.
- Returns `400 Bad Request` if `blocked_id` matches the calling user's UUID to
  explicitly enforce the anti-self-blocking mitigation.

---

## Deno `/flag-issue` Edge Node

Submits a report against an AI inference from the `ReportInsightView`, inserting
a row into `00005_flagged_reviews.sql`.

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
- Validates `scanId` as a well-formed UUID — a non-UUID string is rejected with
  `HTTP 400` before any database access.
- Validates `flagReason` against the enum
  `["Incorrect species", "Inappropriate content", "Bad image quality", "Other"]`.
  Values outside this set are rejected with `HTTP 400` before any database
  access.
- Inserts a row tracking the reporter's context into `public.flagged_reviews`.
- Automatically overrides the underlying `public.scans` row, configuring
  `is_flagged = true` and dynamically stamping the `flagReason` and
  `userSuggestion` into the `human_intervention_notes` column to prompt Admin
  Dashboard review.
- Returns `HTTP 200` on success.

---

## Deno `/request-export-dwca` Edge Node

Queues an asynchronous Darwin Core Archive (DwC-A) export. Because zipping
thousands of records exceeds 30-second HTTP connection limits, this endpoint
merely validates the user and inserts a job into the `export_jobs` PostgreSQL
table, returning a `200 OK` instantly so the iOS client can release its thread.

### Request Payload

```json
{
  "includePreciseCoordinates": true,
  "exportScope": "personal" // or "global"
}
```

### Authentication Enforcement

- Extracts user identity from the GoTrue header via
  `supabaseAdmin.auth.getUser(jwt)`.
- **`exportScope` enum validation**: `exportScope` must be `"personal"` or
  `"global"`. Any other value (including the former default `"user"`) is
  rejected with `HTTP 400`. The default when omitted is `"personal"`.
- **`includePreciseCoordinates` type validation**: `includePreciseCoordinates`
  must be a boolean. A non-boolean value (e.g. a string `"true"`) is rejected
  with `HTTP 400`.
- **Database Rate Limit**: Queries `export_jobs` to verify the user has not
  queued an export in the last 24 hours. If they have, returns
  `429 Too Many Requests`.
- Inserts a row into `export_jobs` with status `pending`, triggering the
  `pg_net` webhook. The insert is idempotent against concurrent duplicate
  submissions: a `23505` unique-constraint violation (two requests racing in
  before either commits) is caught and also returns `429 Too Many Requests`,
  consistent with the explicit rate-limit path and preventing a `500` error from
  surfacing to the client.

---

## Deno `/export-dwca` Edge Node (Webhook Worker)

Generates the DwC-A ZIP, uploads it to Cloudflare R2, and emails the user the
download link. This endpoint acts purely as a Server-to-Server webhook triggered
by `pg_net` after an `export_jobs` insertion. It does _not_ accept iOS client
connections.

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

- Authenticates the Postgres origin by verifying that
  `Authorization: Bearer <token>` exactly matches `SUPABASE_SERVICE_ROLE_KEY`.
- Uses `supabaseAdmin.auth.admin.getUserById(user_id)` to resolve the user's
  email address for the Resend API delivery.
- **DwC-A Global Geoprivacy Leak Prevention**: Enforces strict IUCN Red List and
  ownership gating during ZIP compilation. Evaluates
  `canAccessPrecise = include_precise_coordinates && (scan.user_id === user_id)`.
  For global exports, users receive bounding-box obfuscated coordinates
  (hardcoded 50km `coordinateUncertaintyInMeters`) for scans they do not own.
  Crucially, if a species is flagged as protected (`endangered`, `vulnerable`,
  etc.), the exporter is **always** denied exact coordinates (even for their own
  captures), and public coordinates are aggressively decimate-rounded down to
  ~11km tiles to prevent poachers from extracting precise habitats via standard
  scientific downloads.
- **Async Delivery**: Instead of holding the HTTP response open while zipping
  gigabytes of images, it uploads the final output to Cloudflare R2 and
  dispatches the signed expiring download URL to the user's inbox via the
  **Resend Node SDK**. Updates `export_jobs.status` to `completed`.
- **Stuck-job watchdog**: If the Edge function is killed mid-run (OOM,
  cold-start restart, edge timeout), the job remains in `'processing'` until the
  `pg_cron` watchdog (`expire-stuck-export-jobs`) expires it after 30 minutes.
  The watchdog sets `status = 'failed'` with a descriptive message so users can
  retry via the iOS client instead of waiting forever.

---

## Deno `/refresh-species-content` Edge Node (Cron Worker)

Internal service-role worker for stale public species dictionary fields. It is
invoked hourly by `pg_cron`/`pg_net`, not by iOS clients.

### Request Payload

Scheduled call:

```json
{ "limit": 25 }
```

Manual service-role calls may also include:

```json
{
  "limit": 10,
  "dry_run": true,
  "as_of": "2026-05-13T00:00:00Z",
  "content_keys": ["wikipedia_url", "reference_images"]
}
```

### Authentication Enforcement

- `verify_jwt = false` is configured for `pg_net` compatibility.
- The function still requires
  `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` and validates it with
  `timingSafeCompare`.
- Non-POST requests return `405`.

### Refresh Behavior

1. Claims `gbif_wikipedia_reference` rows from `species_enrichment_jobs` with
   the service role. If no jobs are available, falls back to
   `public.get_species_content_refresh_queue(limit, as_of)` for legacy
   provenance-driven refreshes.
2. Groups queued work by `species_id`.
3. Refreshes supported external fields from GBIF/Wikipedia:
   `alternative_common_names`, `taxonomy`, `wikipedia_url`,
   `wikipedia_overview`, `gbif_taxon_key`, and `reference_images`.
4. Updates `species_dictionary` only for fields where fresh external data
   exists.
5. Synchronizes normalized images through
   `public.replace_species_reference_images(...)`, which preserves
   `source = "merian"` rows managed by the Merian reference-image worker.
6. Records new `species_content_provenance` rows for refreshed keys and marks
   claimed enrichment jobs succeeded or failed.

Per-species refreshes run with a concurrency cap of 4.

Unsupported provenance keys (`common_names`, `habitat_description`,
`lookalikes`, `group_tags`, `iucn_red_list_status`, and `hazard_type`) are
skipped until curation/model refresh tooling exists.

---

## Deno `/refresh-species-model-content` Edge Node (Cron Worker)

Internal service-role worker for model-heavy species enrichment jobs. It is
invoked hourly by `pg_cron`/`pg_net`, not by iOS clients.

Scheduled call:

```json
{ "limit": 12 }
```

Manual service-role calls may also include `dry_run`, `as_of`, and
`content_groups` with any of `habitat`, `lookalikes`, or `group_tags`.

The worker claims matching `species_enrichment_jobs`, runs the same
species-level biology primitives behind `enrich-scan`, persists results to
`species_dictionary` / `species_lookalikes`, records provenance, and marks each
job succeeded or failed. It does not attach media to species and does not change
scan identity; scan-to-species attachment remains owner publish through
`confirmed_species_id`.

---

## Deno `/community-taxonomy-status` Edge Node (Internal Status)

Internal service-role endpoint for Community Taxonomy Index and species
enrichment observability. It is read-only and is intended for operational
dashboards, cron health checks, and manual rollout verification after GBIF cache
imports or Community ID publish flows.

### Authentication Enforcement

- `verify_jwt = false` is configured for service-role calls.
- The function still requires a service-role credential. It first accepts an
  exact `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` match, then falls
  back to proving that the provided bearer token can read service-role-only
  taxonomy import state.
- Non-POST requests return `405`.

### Request Payload

All fields are optional:

```json
{
  "import_run_limit": 10,
  "job_limit": 10,
  "view": "full",
  "target": "birds"
}
```

Both limits must be integers from `1` to `50`. `failure_limit` is accepted as a
backward-compatible alias for `job_limit`. `view = "full"` returns the full
taxonomy/enrichment health snapshot. `view = "coverage"` skips expensive active
taxonomy count queries and returns only bounded import runs plus coverage target
cursor state. `target = "birds"` filters the coverage view to the Birds import
scope.

### Response Payload

```json
{
  "success": true,
  "generated_at": "2026-06-22T00:00:00.000Z",
  "view": "full",
  "active_taxonomy": {
    "id": "taxonomy-version-id",
    "status": "active",
    "source": "merian_dictionary",
    "source_revision": "species_dictionary",
    "node_count": 1000,
    "species_node_count": 600,
    "dictionary_species_count": 240,
    "gbif_only_taxa_count": 360
  },
  "node_counts_by_source": [
    { "key": "gbif", "count": 500 }
  ],
  "node_counts_by_rank": [
    { "key": "species", "count": 600 }
  ],
  "latest_import_runs": [],
  "enrichment_jobs": {
    "counts": [
      { "content_group": "habitat", "status": "queued", "count": 10 }
    ],
    "next_jobs": [],
    "recent_failures": []
  },
  "coverage_targets": [
    {
      "slug": "birds",
      "display_name": "Birds",
      "indexed_species_count": 1000,
      "dictionary_species_count": 600,
      "coverage_ratio": 0.6,
      "last_imported_offset": 950,
      "next_import_offset": 1000,
      "last_successful_import_at": "2026-06-23T00:00:00.000Z",
      "last_import_error": null,
      "gbif_total_count": 14641
    }
  ]
}
```

The endpoint does not refresh coverage, claim jobs, cache GBIF taxa, materialize
Dictionary rows, or attach scan media. It only reports the current database
state available to the service role. Import operators and deploy smoke checks
should use `view = "coverage"` unless they explicitly need source/rank counts
or enrichment queue health.

---

## Deno `/sync-community-taxonomy-index` Edge Node (Internal Import Worker)

Internal service-role worker for bounded GBIF imports into the Community
Taxonomy Index. It is manual-first and resumable; no cron schedule is installed
in v1.

### Authentication Enforcement

- `verify_jwt = false` is configured for service-role calls.
- The function still requires a service-role credential. It first accepts an
  exact `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` match, then falls
  back to proving that the provided bearer token can read service-role-only
  taxonomy import state.
- Non-POST requests return `405`.

### Request Payload

All fields are optional:

```json
{
  "target": "birds",
  "offset": 0,
  "limit": 50,
  "page_count": 1,
  "dry_run": false
}
```

Constraints:

- `target`: only `birds` in v1.
- `offset`: non-negative integer.
- `limit`: integer from `1` to `200`.
- `page_count`: integer from `1` to `5`.

### Response Payload

```json
{
  "success": true,
  "target": "birds",
  "root_gbif_taxon_key": 212,
  "dry_run": false,
  "imported_count": 50,
  "fetched_count": 50,
  "normalized_count": 50,
  "end_of_records": false,
  "next_offset": 50,
  "pages": [
    {
      "offset": 0,
      "limit": 50,
      "requested_query": "bounded:birds:root=212:rank=species:status=accepted:offset=0:limit=50",
      "fetched_count": 50,
      "normalized_count": 50,
      "imported_count": 50,
      "dry_run": false,
      "end_of_records": false,
      "next_offset": 50
    }
  ]
}
```

### Import Behavior

1. Fetches GBIF species search pages with `highertaxon_key=212`, `rank=SPECIES`,
   and `status=ACCEPTED`.
2. Normalizes rows into Merian's GBIF community taxon payload.
3. Calls `upsert_gbif_community_taxa(...)`, which inserts lineage and species
   nodes into `taxon_nodes` / `taxon_names` without deleting Dictionary-backed
   rows.
4. Annotates the created `taxonomy_import_runs` row as
   `scope = "gbif_bounded_birds"` with page metadata.
5. Relies on the existing RPC side effect to recompute
   `taxonomy_coverage_targets`.

The worker does not create `species_dictionary` rows, enqueue species
enrichment, or attach scan media. Those still happen only through
materialization triggers such as owner-published Community ID consensus.

### Manual Rollout Sequence

After migrations and Edge Functions are deployed:

1. Call `/sync-community-taxonomy-index` with `dry_run = true`, `offset = 0`,
   `limit = 50`, and `page_count = 1`.
2. If GBIF returns normalized rows, repeat the call without `dry_run`.
3. Call `/community-taxonomy-status` and confirm the latest import run has
   `scope = "gbif_bounded_birds"` and the Birds coverage target has a non-zero
   `indexed_species_count`.
4. Continue with the previous import response's `next_offset`.

Keep the first rollout to one page per call. Increase `page_count` only after
status checks show expected import rows and coverage counts.

---

## Deno `/refresh-merian-reference-images` Edge Node (Cron Worker)

Internal service-role worker for promoting high-quality published Explore media
into public species dictionary galleries. It is invoked hourly by
`pg_cron`/`pg_net`, not by iOS clients.

### Request Payload

Scheduled call:

```json
{
  "quality_threshold": 80,
  "species_confidence_threshold": 0.95,
  "per_species_limit": 8
}
```

Manual service-role calls may also include:

```json
{
  "quality_threshold": 95,
  "species_confidence_threshold": 0.98,
  "per_species_limit": 4,
  "dry_run": true
}
```

### Authentication Enforcement

- `verify_jwt = false` is configured for `pg_net` compatibility.
- The function still requires
  `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` and validates it with
  `timingSafeCompare`.
- Non-POST requests return `405`.

### Refresh Behavior

1. Calls `public.refresh_merian_reference_images(...)` with the service role.
2. The SQL helper selects visible Explore posts only: shared, not unshared,
   non-tombstoned, media present, non-private backing scan geoprivacy,
   non-shadowbanned author, and resolved species present. This species-reference
   promotion gate is stricter than ordinary Explore visibility; post-level
   `private` location sharing can keep the post visible while omitting public
   location, but private backing scans are not promoted into Merian reference
   imagery.
3. It unnests all non-empty `scans.image_storage_urls`, requires
   `image_quality_score >= 80` and `ai_confidence_score >= 0.95` by default
   unless `confirmed_species_id` is present, dedupes by
   `(species_id, image_url)`, and promotes up to 8 images per species. Public
   videos are intentionally excluded from Dictionary/reference galleries.
4. Public rows use `source = "merian"`,
   `license = "Used with permission via Merian"`, and
   `attribution = users.public_author_name`. This intentionally preserves the
   public display label rather than switching attribution to the username
   handle.
5. Provenance remains private in `species_reference_image_merian_sources`; no
   public species API exposes source scan, post, user IDs, confidence score, or
   confidence qualification source.
6. Rows are removed on the next refresh when the source Explore post/media is no
   longer publicly visible.

Response:

```json
{
  "success": true,
  "candidate_count": 12,
  "promoted_count": 8,
  "removed_count": 1,
  "species_count": 2,
  "dry_run": false
}
```

---

## Deno `/submit-feedback-survey` Edge Node

Accepts the one-time beta feedback survey from the iOS app. The endpoint is
authenticated through `withEdgeHandler`; the server ignores any client-provided
user identity and stores the response under the JWT user id.

### Request Payload

```json
{
  "survey_campaign_id": "beta_feedback_2026_06",
  "satisfaction_rating": 4,
  "recommendation_rating": 9,
  "used_features": ["identify_found_subject", "browse_explore"],
  "most_useful_features": ["camera_identification", "insight_sheet"],
  "confusing_or_disappointing": "Occasionally slow on older devices.",
  "wished_next": "More collection organization tools.",
  "bug_status": "workaround",
  "bug_details": "Retrying fixed one failed scan.",
  "may_follow_up": false,
  "contact": "",
  "app_version": "1.0",
  "build_number": "99",
  "platform": "ios",
  "device_model": "iPhone",
  "os_version": "19.0",
  "locale": "en_US",
  "timezone": "America/Chicago"
}
```

Validation rules:

- `survey_campaign_id` must match the active one-time campaign.
- Satisfaction must be an integer from 1 to 5.
- Recommendation must be an integer from 0 to 10.
- Feature/use values must be from the native survey enum sets.
- Free-text fields are trimmed and capped at 4,000 characters.
- Follow-up fields are retained for API compatibility. The current native survey
  sends `may_follow_up: false` and an empty `contact` value.

### Response Payload

```json
{
  "success": true
}
```

Responses are stored in `public.feedback_survey_responses` with RLS enabled.
Users can insert and read their own rows; product review happens through
Supabase dashboard/service-role tooling rather than public app APIs.

---

## Deno `/auto-purge-nonbio` Edge Node

A daily cron-job endpoint responsible for removing stale
`.is_biological_subject = false` scans to prevent arbitrary file bloat on
Cloudflare R2 and PostgreSQL.

### Request Payload

No JSON body is required. The cron trigger issues an empty POST request.

### Authentication Enforcement

- Enforces strict cron authorization via `timingSafeCompare` against a
  `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` Authorization header. Returns `401` if
  invalid.
- Prevents accidental `GET` evaluations by aggressively validating
  `req.method === "POST"`.

### Deletion Safety

1. Queries scans isolated strictly to `is_biological_subject == false` where
   `timestamp < 30 days ago`.
2. Employs `.limit(500)` memory pagination barriers to prevent container timeout
   triggers.
3. Aggregates all R2 `image_storage_urls` and `video_storage_urls` across the
   500 scans and passes them to `deleteScanMediaR2Objects([])`, which filters to
   `public_uploads/free|pro/` before using the bounded R2 delete helper.
   Durable `avatars/` profile images are skipped.
4. Executes the discrete `.delete().in("id", [...])` cascade against PostgreSQL
   only after successfully purging the R2 remote hashes, preventing orphan
   binaries.

## Deno `/revenuecat-webhook` Edge Node

Receives POST push events triggered natively from the RevenueCat subscription
platform to update Supabase row bounds directly, bypassing the iOS SDK entirely.

### Request Payload

Receives a raw RevenueCat Webhook structure wrapper targeting an internal JSON
`.event`.

### Authentication Enforcement

- Reads `REVENUECAT_WEBHOOK_SECRET` environment bindings locally.
- Authenticates the RevenueCat push via `timingSafeCompare` comparing the
  `Authorization: Bearer` against the secret boundary.
- **`app_user_id` UUID validation**: After webhook auth, `event.app_user_id` is
  validated against a UUID regex (`/^[0-9a-f]{8}-...-[0-9a-f]{12}$/i`) before
  any database access. A falsy `!userId` check alone is insufficient —
  RevenueCat sends anonymous IDs like `$RCAnonymousID:xxx` for un-linked
  purchases, which would pass the truthy check but fail UUID constraints in the
  DB layer with a confusing 500. Anonymous-ID events are rejected early with
  `HTTP 400` and a warning log.

### Migration Mechanics

- Upgrades (`INITIAL_PURCHASE`, `RENEWAL`, `UNCANCELLATION`) convert
  `subscription_tier` to `pro` and clear `subscription_expires_at`.
- Exact `merian_7_day_pass` `NON_RENEWING_PURCHASE` events convert
  `subscription_tier` to `pro` and set `subscription_expires_at` to
  `purchased_at_ms + 7 days`. Other non-renewing products are ignored.
- Standard subscription downgrades (`EXPIRATION`) revert the tier to `free`.
- Pass refund/cancellation-style events downgrade immediately. Timed passes that
  naturally reach `subscription_expires_at` are downgraded by the hourly
  `expire-subscription-passes` worker.
- Existing scan media stays in place on tier changes. Both
  `public_uploads/free/` and `public_uploads/pro/` are durable scan-media
  prefixes.
