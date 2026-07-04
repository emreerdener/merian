# Safety & Moderation Pipeline

Merian runs all user-submitted media through a two-layer moderation system before persisting any scan to the database. The shared implementation lives in `_shared/identify/moderation.ts` and is used by both `/identify` and `/identify-multimodal`. It never blocks the HTTP response.

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

Before any data is persisted, the Edge Function checks two Gemini safety signals:

1. **`finishReason === "SAFETY"`** — Gemini refused to generate a full response due to content policy. Immediately flagged as unsafe.
2. **`safetyRatings[]` probability** — If any individual safety category is rated `"MEDIUM"` or `"HIGH"`, the media is flagged regardless of `finishReason`.

`"LOW"` and `"NEGLIGIBLE"` probability ratings are treated as safe and do not trigger moderation.

## Abuse Strike System

Each unsafe media submission increments `users.abuse_strikes` in the Supabase `users` table:

| Strike Count | Status Returned | Behavior |
|---|---|---|
| 1–2 | `DELETED_WARNING` | Staging image deleted, scan not persisted, no user-facing message |
| 3+ | `SHADOWBANNED` | Same as above, plus `users.is_shadowbanned = true` |

The strike counter is read and written via the Supabase service role in `_shared/identify/moderation.ts`. The read uses `.select("abuse_strikes").eq("id", userId).single()`. `PGRST116` (no row found) falls back to `0`; any other read/write failure aborts moderation with `ERROR` so the caller never believes a strike was recorded when the DB write actually failed.

### Shadowban Behavior

`is_shadowbanned` is a boolean column on the `users` table (default `false`). Shadowbanned users are not informed of their status. The expected downstream effect is that their scans are silently dropped (background ingestion halts at the moderation gate), so the app appears to function normally from their perspective while no data is persisted.

**Important**: The shadowban is applied at the scan ingestion level only. The iOS client still receives a successful `200 OK` response with AI identification data — the background task halts invisibly. No iOS-layer check for `is_shadowbanned` currently exists.

## Media Promotion Pipeline

For safe scans, `moderation.ts` promotes images from temporary staging storage to permanent public storage. Short video scans still moderate through the ordered sampled frames sent to Gemini; when available, extracted accompanying audio can also inform identification but is not reference media. Once the frames are safe, `identify-multimodal` promotes the staged compressed playback `.mp4` separately into `video_storage_urls` for the scan record. The playback video is never used for AI inference or reference-media promotion. When a user shares that scan, Explore snapshots post-owned public video media from the promoted video URL and requires an image-backed poster thumbnail. Videos are not Dictionary/reference-media inputs in v1.

### R2 Bucket Layout

| Purpose | Path Pattern |
|---|---|
| Temporary staging (pre-moderation) | `staging/{userId}/{filename}.webp` |
| Temporary compressed playback video (pre-moderation) | `staging/{userId}/{filename}.mp4` |
| Permanent public storage (post-moderation) | `public_uploads/{tier}/{userId}/{filename}.webp` |
| Permanent compressed playback video storage (post-moderation) | `public_uploads/{tier}/{userId}/{filename}.mp4` |
| Durable public profile avatars | `avatars/{userId}/{uuid}.webp|jpg` |
| CDN base URL | `https://media.merian.app/` |

`{tier}` is either `"pro"` or `"free"`, determined from `userTier` resolved on the critical path.

`avatars/` is not part of the scan moderation pipeline. Custom profile pictures
are promoted by `/update-public-avatar` after a user-owned staged upload and are
deleted only by the avatar replacement helper for the same user. Scan purge,
moderation rollback, and storage lifecycle jobs must not target `avatars/`.

### Two Promotion Paths

**Path A — R2 Staging Key** (standard offline queue flow):
1. Copy the object from `staging/{userId}/...` to `public_uploads/{tier}/{userId}/...` via `copyR2Object`
2. Delete the staging object via `deleteR2Object`
3. Return the CDN URL as `https://media.merian.app/{publicUploadKey}`

**Path B — Base64 Direct Upload** (instant capture flow):
1. Decode the base64 string
2. `PUT` the bytes directly to `public_uploads/{tier}/{userId}/{filename}` via a signed S3 request
3. Return the CDN URL

The filename is derived from `r2ObjectKeys[i].split("/").pop()` when available; otherwise a random UUID is generated. When uploading from base64, `r2ObjectKeys` carries only the desired destination filename, not a staging object to copy.

### Upload Failure Handling

If any image promotion step fails (non-OK direct upload, failed staging copy, or staging delete after copy), the shared moderation helper aborts the entire promotion batch and rolls back any already-promoted public objects from that batch before returning `ERROR`. The scan is not inserted with a partial `image_storage_urls` array.

For video scans, unsafe moderation deletes any additional staged compressed playback video keys passed by `identify-multimodal` along with staged image keys. Safe video promotion is best-effort after the moderation gate; if promotion fails, the scan can still persist with sampled image media while the failed staged playback video is cleaned up.

### R2 Rollback on Scan Insert Failure

If `modResult.publicUrls` is populated but `insertScan` throws, `index.ts` rolls back the already-promoted public objects:

```typescript
if (!scanInserted && modResult?.publicUrls?.length) {
  const keysToPurge = modResult.publicUrls.map((url) =>
    url.replace("https://media.merian.app/", "")
  );
  await Promise.allSettled(
    keysToPurge.map((key) => deleteR2Object(key, r2Config))
  );
}
```

This prevents orphaned public objects when the database write fails after media has already been committed.

## Moderation Status Codes

| Status | Meaning | Ingestion Continues? |
|---|---|---|
| `PROMOTED` | Media safe, promoted to public storage | Yes |
| `DELETED_WARNING` | Unsafe (strike 1–2), staging deleted | No |
| `SHADOWBANNED` | Unsafe (strike 3+), user shadowbanned | No |
| `ERROR` | Internal exception in moderation pipeline | No (scan is NOT inserted — ingestion halts) |

The `ERROR` status now halts ingestion in `identify/index.ts` — when `modResult.status === "ERROR"`, the scan insert is skipped entirely. Without this guard, a moderation pipeline failure (e.g. abuse strike DB write failed) would create a permanent DB record with `image_storage_urls: null`. The outer catch in `moderation.ts` now uses `logStructuredError` instead of bare `console.error` for alertable observability. Abuse strike fetch/write failures now throw rather than log-and-continue — returning `SHADOWBANNED` or `DELETED_WARNING` when the DB write silently failed would falsely indicate the penalty was recorded.

## Insight Chat Safety

`/insight-chat` is a post-identification text-only follow-up surface, not a media
moderation path. It never receives raw image bytes or cloud image URLs. The Edge
Function builds context from private stored scan evidence and the species
dictionary, then calls `gemini-2.5-flash` only after ownership, Pro tier, and
rate-limit checks pass.

The chat prompt may include stored private species and scan text such as
taxonomy, hazard/invasive flags, review provenance, observed traits, ecological
annotations, species group tags, field notes, weather/elevation labels, and
image/capture-quality scores. It must not include raw image bytes, cloud image
URLs, storage keys, internal scan IDs, exact GPS coordinates,
Explore/community content, or export payloads.

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

## Flagged Reviews (User-Reported)

Separate from the automated moderation system, users can manually report a scan via the flag flow in `BiologicalView`. This writes a row to the `flagged_reviews` table via the `/flag-issue` Edge Function:

- `scan_id` — The scan being reported
- `user_id` — The reporting user
- `flag_reason` — e.g. "Incorrect Species" or "Inappropriate Content"
- `user_suggestion` — Optional free-text from the user
- `status` — Defaults to `PENDING_REVIEW`

Flagged reviews require human review and do not trigger automatic action. The automated abuse strike system and the flagged review system are entirely independent pipelines.

## Database Columns

### `users` table additions

- `abuse_strikes` (INT, DEFAULT 0) — Incremented on each unsafe media detection. Never decremented automatically.
- `is_shadowbanned` (BOOLEAN, DEFAULT false) — Set to `true` when `abuse_strikes >= 3`. Read by the moderation module; not currently read by the iOS client.

### `scans` table

- `is_flagged` (BOOLEAN) — Set by the `/flag-issue` Edge Function when a user-reported flag reaches a review threshold. Managed via `00005_flagged_reviews.sql`.
- `is_tombstoned` (BOOLEAN) — GDPR-compliant account deletion marker. Anonymizes scan metadata while preserving the row for offline cache continuity. Managed via `00006_apply_user_tombstone.sql`.
