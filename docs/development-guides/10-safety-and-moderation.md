# Safety & Moderation Pipeline

Naturebook runs all user-submitted media through a two-layer moderation system
before persisting any scan to the database. The shared implementation lives in
`_shared/identify/moderation.ts` and is used by both `/identify` and
`/identify-multimodal`. It never blocks the HTTP response.

Public Explore audio uses a separate publication gate. Identification safety
and public-audio safety are intentionally different decisions: a clip may be
valid biological evidence while its background speech is unsuitable for a
public feed.

## Exact External Reference Image Suppression

Wikipedia, GBIF, and iNaturalist reference images are third-party educational
media, not user submissions to the scan moderation pipeline above. Naturebook
does not currently classify every external image. For a confirmed outlier, the
app instead uses a small exact-media denylist and silently advances to the next
available reference image. It does not hide the species card, add a censor
overlay, or block the provider or taxon as a whole.

The current denylist contains one item:

- GBIF occurrence `5938154750`
- iNaturalist media ID `605615444`
- exact origin/path prefix
  `inaturalist-open-data.s3.amazonaws.com/photos/605615444/`

Matching uses the normalized hostname and path prefix, so original, resized,
query-string, and fragment variants are all suppressed. An unrelated image on
the same host, other GBIF imagery for `Felis silvestris`, and URLs that merely
contain the digits elsewhere remain allowed. Never implement an outlier by
species name, result position, filename such as `original.jpg`, or a broad GBIF
or iNaturalist host block.

Suppression is enforced in depth:

- Deno uses `_shared/externalImagePolicy.ts` before live Wikipedia/GBIF
  enrichment is returned and before normalized or legacy reference-image data
  is projected or persisted.
- Migration
  `20260719023147_suppress_european_wildcat_roadkill_image.sql` removes existing
  normalized and comma-separated legacy values, filters the public SQL image
  helpers, and installs a service-write trigger that silently discards future
  rows for the exact media path.
- iOS mirrors the rule in `ExternalReferenceImagePolicy`. The loader checks it
  before cache lookup and again at the network boundary; DTO normalization and
  cached `SimilarSpeciesEntry` decoding treat a denied URL as absent.
- `SimilarSpeciesImageFetcher` removes denied candidates before download and
  restores source order after concurrent work. A blocked first result therefore
  promotes the next successful image deterministically; an empty result uses
  the existing leaf placeholder.

The API payload shape is unchanged. Suppression removes a value from an
existing image field or array; it does not introduce moderation metadata into a
public response.

When adding another exact external-media outlier:

1. Record a stable provider media identity and the narrowest immutable
   host/path prefix.
2. Add the same match to the Deno and iOS policy helpers.
3. Add a forward-only migration that cleans normalized and legacy caches and
   extends write/projection prevention. Do not edit a deployed migration.
4. Cover original, resized, query-string, unrelated-media, historical-cache,
   next-image, and all-blocked cases.
5. Deploy the migration and dependent Edge Functions before relying on the iOS
   update. Older clients that fetch GBIF directly are protected only after an
   app update.

## Explore Audio Publication Moderation

When selected media contains standalone audio or an audio-bearing playback
video, `/share-scan-to-explore` treats moderation as a precondition. Before any
Explore post or public-media snapshot is created or reactivated, the function:

1. downloads the selected media with a 12 MB hard cap and computes SHA-256;
2. reuses a matching content-addressed attestation only when checksum, model,
   and publication-policy version all match;
3. on a cache miss, sends the bounded bytes inline to a dedicated
   `gemini-2.5-flash` classifier;
4. evaluates speech, non-speech sounds, policy categories, confidence, and
   review state through strict structured output;
5. persists only the checksum, decision, model, policy version, MIME type, and
   byte size—never transcript, URL, user identity, filename, or media bytes;
6. continues into the normal atomic share write only when every audible
   selected item is approved.

Rejected classifications and any fetch, provider, configuration, or response-shape
failure return an error and leave the prior Explore state unchanged; nothing is
shared. Transcripts and non-speech descriptions are not persisted or logged.
This path reuses the existing `GEMINI_API_KEY` Edge secret. Manual reports
remain necessary because model moderation cannot guarantee complete detection.
The immutable publication policy is a Gemini system instruction so speech or
lyrics inside untrusted media cannot replace it. Standalone audio preserves its
supported audio MIME type; audio-bearing MP4 uses `video/mp4` so Gemini evaluates
the actual container instead of relabeling video bytes as WAV.
Public web post pages include a support-email report action containing the
immutable post id. Native Explore post reports write the dedicated
`explore_post_reports` moderation queue through `/report-explore-post`; they do
not enter identification review or set `scans.is_flagged`.
Structured moderation telemetry logs only outcome, model, latency, and sanitized
errors; transcripts and media URLs must never be logged. A policy-version or
model change is an automatic cache miss, so changed safety rules always force a
new Gemini decision. Cache read/write failures degrade to live moderation and
never bypass the publication gate.

Spectrogram generation is downstream presentation work, not a safety decision.
Only after standalone WAV media is approved may `_shared/audioSpectrogram.ts`
derive and upload its deterministic PNG. Generation failure must preserve the
approved canonical recording and speaker fallback; it must never reinterpret a
failed thumbnail as moderation approval, reprocess unapproved bytes, persist a
transcript, or log a media URL.

Legacy audio repair does not bypass this gate. Owner-scoped staging keys are
promoted and persisted to the scan before selection resolution; the restored
bytes then require the same checksum attestation or live Gemini decision as new
audio. Failed scan persistence rolls back the promoted R2 objects.

Native and public-web **Boost audio** are strictly post-publication playback
DSP. Native processing uses a bounded temporary local copy; web processing uses
an allowlisted same-origin stream plus browser-local gain/filter/limiting. They
must never overwrite or upload enhanced audio, change the R2 object/checksum,
create a new moderation attestation, or moderate the processed waveform instead
of the original public bytes. Boost preferences remain local listening state
and are not part of the safety or publication decision. The web proxy accepts
only HTTPS `.wav` objects on exact host `media.merian.app` below
`public_uploads/`; it must not become a general-purpose fetch proxy.

Private scan-library Insight boost uses the same local DSP after scan
finalization, with a separate per-scan preference. It likewise never overwrites
or uploads enhanced bytes and cannot change identification, retention,
moderation, or later Explore publication decisions; any public share is still
moderated against the canonical original recording.

## Architecture Overview

```
[Gemini Vision Response]
        │
        ▼
[evaluateAndProcessPayload]  ← _shared/identify/moderation.ts
        │
        ├─ UNSAFE (SAFETY finish reason or HIGH/MEDIUM safety rating)
        │       │
        │       ├─ Delete staging R2 object (if r2ObjectKeys path)
        │       ├─ Increment users.abuse_strikes
        │       ├─ Set users.is_shadowbanned = true  (if strikes ≥ 3)
        │       └─ Return SHADOWBANNED | DELETED_WARNING  → halt ingestion
        │
        └─ SAFE
                │
                ├─ Promote staging image → public_uploads/{tier}/{userId}/
                │     (or upload base64 directly to public_uploads)
                └─ Return PROMOTED { publicUrls[] }  → continue to insertScan
```

## Gemini Safety Ratings Evaluation

Before any data is persisted, the Edge Function checks two Gemini safety
signals:

1. **`finishReason === "SAFETY"`** — Gemini refused to generate a full response
   due to content policy. Immediately flagged as unsafe.
2. **`safetyRatings[]` probability** — If any individual safety category is
   rated `"MEDIUM"` or `"HIGH"`, the media is flagged regardless of
   `finishReason`.

`"LOW"` and `"NEGLIGIBLE"` probability ratings are treated as safe and do not
trigger moderation.

## Abuse Strike System

Each unsafe media submission increments `users.abuse_strikes` in the Supabase
`users` table:

| Strike Count | Status Returned   | Behavior                                                          |
| ------------ | ----------------- | ----------------------------------------------------------------- |
| 1–2          | `DELETED_WARNING` | Staging image deleted, scan not persisted, no user-facing message |
| 3+           | `SHADOWBANNED`    | Same as above, plus `users.is_shadowbanned = true`                |

The strike counter is read and written via the Supabase service role in
`_shared/identify/moderation.ts`. The read uses
`.select("abuse_strikes").eq("id", userId).single()`. `PGRST116` (no row found)
falls back to `0`; any other read/write failure aborts moderation with `ERROR`
so the caller never believes a strike was recorded when the DB write actually
failed.

### Shadowban Behavior

`is_shadowbanned` is a boolean column on the `users` table (default `false`).
Shadowbanned users are not informed of their status. The expected downstream
effect is that their scans are silently dropped (background ingestion halts at
the moderation gate), so the app appears to function normally from their
perspective while no data is persisted.

**Important**: The shadowban is applied at the scan ingestion level only. The
iOS client still receives a successful `200 OK` response with AI identification
data — the background task halts invisibly. No iOS-layer check for
`is_shadowbanned` currently exists.

## Media Promotion Pipeline

For safe scans, `moderation.ts` promotes images from temporary staging storage
to permanent public storage. Short video scans still moderate through the five
ordered sampled frames sent to Gemini; when available, extracted accompanying
audio can also inform identification but is not reference media. Once the frames
are safe, `identify-multimodal` must also promote every requested staged
upload-bounded playback `.mp4` into `video_storage_urls` before inserting the
scan row. If playback-video promotion fails or returns fewer URLs than
requested, the edge returns a retryable failure, preserves the staged playback
object for retry, and does not create a frame-only video scan. That playback
file is normally the client's compressed 720p export, but the client may stage
the original recording when compression is slow or unavailable and the source
remains within the hard video byte cap. The playback video is never used for AI
inference or reference-media promotion. `/generate-upload-urls` creates staged
`scan_media_assets` rows for scan media uploads before the final `scans` row
exists or a public media URL is available; `scan_id = NULL` and `url = NULL` are
therefore valid for those staged rows until `identify-multimodal` promotes,
deletes, or fails them during finalization. The ingestion request also claims
`scan_ingestion_jobs` with media counts, staged object keys, recovered
upload-session ids, and a normalized `manifest_checksum`, so retries and repair
work can prove they are handling the same media set. A
paired `scan_ingestion_intents` row stores the sanitized replay request without
raw media bytes; inline foreground media is redacted and marked non-resumable.
The scheduled `replay-scan-ingestion` worker retries resumable staged
media/audio/video and text-only requests by dispatching them back through
`identify-multimodal`; the scheduled `reconcile-scan-media-assets` worker
revisits stale staged rows when a scan row already exists or when media has aged
past its abandonment TTL. If a scan row exists, reconciliation can promote a
surviving playback video and rebuild the manifest; if no scan row exists after
the TTL, it deletes the staging object, marks the asset failed, and marks the
matching ingestion job terminal unless an active lease or future retry window
still owns that media. The same table is refreshed from `captured_media` after
scan insert or repair so newer readers can resolve only ready display/playback
media without treating sampled frames as standalone user media. When a user
shares that scan, Explore snapshots post-owned public video media from the
promoted video URL and requires an image-backed poster thumbnail. Videos are not
Dictionary/reference-media inputs in v1.

### R2 Bucket Layout

| Purpose                                            | Path Pattern                                     |
| -------------------------------------------------- | ------------------------------------------------ |
| Temporary staging (pre-moderation)                 | `staging/{userId}/{filename}.webp`               |
| Temporary playback video (pre-moderation)          | `staging/{userId}/{filename}.mp4`                |
| Permanent public storage (post-moderation)         | `public_uploads/{tier}/{userId}/{filename}.webp` |
| Permanent playback video storage (post-moderation) | `public_uploads/{tier}/{userId}/{filename}.mp4`  |
| Durable public profile avatars                     | `avatars/{userId}/{uuid}.webp                    |
| CDN base URL                                       | `https://media.merian.app/`                      |

`{tier}` is either `"pro"` or `"free"`, determined from `userTier` resolved on
the critical path.

`avatars/` is not part of the scan moderation pipeline. Custom profile pictures
are promoted by `/update-public-avatar` after a user-owned staged upload and are
deleted only by the avatar replacement helper for the same user. Scan purge,
moderation rollback, and storage lifecycle jobs must not target `avatars/`.

### Two Promotion Paths

**Path A — R2 Staging Key** (standard offline queue flow):

1. Copy the object from `staging/{userId}/...` to
   `public_uploads/{tier}/{userId}/...` via `copyR2Object`
2. Delete the staging object via `deleteR2Object`
3. Return the CDN URL as `https://media.merian.app/{publicUploadKey}`

**Path B — Base64 Direct Upload** (instant capture flow):

1. Decode the base64 string
2. `PUT` the bytes directly to `public_uploads/{tier}/{userId}/{filename}` via a
   signed S3 request
3. Return the CDN URL

The filename is derived from `r2ObjectKeys[i].split("/").pop()` when available;
otherwise a random UUID is generated. When uploading from base64, `r2ObjectKeys`
carries only the desired destination filename, not a staging object to copy.

### Upload Failure Handling

If any image promotion step fails (non-OK direct upload, failed staging copy, or
staging delete after copy), the shared moderation helper aborts the entire
promotion batch and rolls back any already-promoted public objects from that
batch before returning `ERROR`. The scan is not inserted with a partial
`image_storage_urls` array.

For video scans, unsafe moderation deletes any additional staged playback video
keys passed by `identify-multimodal` along with staged image keys. Safe video
promotion is a durability gate: if any requested playback video cannot be
promoted, `identify-multimodal` does not insert a frame-only video scan and the
client can retry through the offline queue. The reconciliation worker exists for
drift after that boundary, such as a scan row that already exists while its
staged playback asset row was never finalized; it must consult
`scan_ingestion_jobs` before abandoning orphaned staged media.

### R2 Rollback on Scan Insert Failure

If `modResult.publicUrls` is populated but `insertScan` throws, `index.ts` rolls
back the already-promoted public objects:

```typescript
if (!scanInserted && modResult?.publicUrls?.length) {
  const keysToPurge = modResult.publicUrls.map((url) =>
    url.replace("https://media.merian.app/", "")
  );
  await Promise.allSettled(
    keysToPurge.map((key) => deleteR2Object(key, r2Config)),
  );
}
```

This prevents orphaned public objects when the database write fails after media
has already been committed.

## Moderation Status Codes

| Status            | Meaning                                   | Ingestion Continues?                        |
| ----------------- | ----------------------------------------- | ------------------------------------------- |
| `PROMOTED`        | Media safe, promoted to public storage    | Yes                                         |
| `DELETED_WARNING` | Unsafe (strike 1–2), staging deleted      | No                                          |
| `SHADOWBANNED`    | Unsafe (strike 3+), user shadowbanned     | No                                          |
| `ERROR`           | Internal exception in moderation pipeline | No (scan is NOT inserted — ingestion halts) |

The `ERROR` status now halts ingestion in `identify/index.ts` — when
`modResult.status === "ERROR"`, the scan insert is skipped entirely. Without
this guard, a moderation pipeline failure (e.g. abuse strike DB write failed)
would create a permanent DB record with `image_storage_urls: null`. The outer
catch in `moderation.ts` now uses `logStructuredError` instead of bare
`console.error` for alertable observability. Abuse strike fetch/write failures
now throw rather than log-and-continue — returning `SHADOWBANNED` or
`DELETED_WARNING` when the DB write silently failed would falsely indicate the
penalty was recorded.

## Insight Chat Safety

`/insight-chat` is a post-identification text-only follow-up surface, not a
media moderation path. It never receives raw image bytes or cloud image URLs.
The Edge Function builds context from private stored scan evidence and the
species dictionary, then calls `gemini-2.5-flash` only after ownership, Pro
tier, and rate-limit checks pass.

The chat prompt may include stored private species and scan text such as
taxonomy, hazard/invasive flags, review provenance, observed traits, ecological
annotations, species group tags, field notes, weather/elevation labels, and
image/capture-quality scores. It must not include raw image bytes, cloud image
URLs, storage keys, internal scan IDs, exact GPS coordinates, Explore/community
content, or export payloads.

AI-generated quick prompt chips are produced through the same `/insight-chat`
privacy boundary with `action: "suggest_prompts"`. They must remain short,
scan-specific, and safe; prompt generation must not ask for edible certainty,
medical/veterinary treatment, illegal collection, pesticide/poison instructions,
exact-location details, or human-subject identification. Prompt generation is
best-effort and must fail independently from normal chat load/send behavior.

The system prompt must state that the assistant has no raw image access and
answers only from saved evidence. Local deterministic guards refuse or redirect
edible/foraging certainty, medical or veterinary treatment, dangerous handling,
illegal collection, pesticide/poison instructions, and human-subject
identification. Refused answers should stay educational and conservative rather
than giving action instructions.

## Identification Flags and Explore Content Reports

Separate from automated publication moderation, users can dispute a scan's
identification via the flag flow in `BiologicalView`. This writes a row to the
`flagged_reviews` table via the `/flag-issue` Edge Function:

- `scan_id` — The scan being reported
- `user_id` — The reporting user
- `flag_reason` — e.g. "Incorrect Species" or "Inappropriate Content"
- `user_suggestion` — Optional free-text from the user
- `status` — Defaults to `PENDING_REVIEW`

Flagged reviews require human review and do not trigger automatic action. The
automated abuse strike system and the flagged review system are entirely
independent pipelines.

Reporting a public Explore post is a different pipeline. The authenticated
`/report-explore-post` function validates that the post is visible and not owned
by the reporter, then upserts `explore_post_reports`. Repeat reports from the
same reporter update one row without reopening a report that moderators already
dismissed or actioned. Post reporting must never call `/flag-issue`, set
`scans.is_flagged`, or create an identification-review record.

## Database Columns

### `users` table additions

- `abuse_strikes` (INT, DEFAULT 0) — Incremented on each unsafe media detection.
  Never decremented automatically.
- `is_shadowbanned` (BOOLEAN, DEFAULT false) — Set to `true` when
  `abuse_strikes >= 3`. Read by the moderation module; not currently read by the
  iOS client.

### `scans` table

- `is_flagged` (BOOLEAN) — Set by the `/flag-issue` Edge Function when a
  user-reported flag reaches a review threshold. Managed via
  `00005_flagged_reviews.sql`.
- `is_tombstoned` (BOOLEAN) — GDPR-compliant account deletion marker. Anonymizes
  scan metadata while preserving the row for offline cache continuity. Managed
  via `00006_apply_user_tombstone.sql`.
