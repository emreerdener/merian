# Safety & Moderation Pipeline

Naturebook runs all user-submitted media through a two-layer moderation system
before publishing scan media or persisting the final scan row. The shared
implementation lives in `_shared/identify/moderation.ts` and is used by both
`/identify` and `/identify-multimodal`. The active multimodal route awaits this
decision before HTTP success; compatibility image and audio routes await the
same required moderation, promotion, and scan insertion plus a synchronous
finalization attempt. Only an exact post-row finalization failure can use their
narrow compatibility fallback; marked retries may reconstruct from that durable
owner row without repeating moderation or provider work.

Public Explore audio uses a separate publication gate. Identification safety and
public-audio safety are intentionally different decisions: a clip may be valid
biological evidence while its background speech is unsuitable for a public feed.

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
  enrichment is returned and before normalized or legacy reference-image data is
  projected or persisted.
- Migration `20260719023147_suppress_european_wildcat_roadkill_image.sql`
  removes existing normalized and comma-separated legacy values, filters the
  public SQL image helpers, and installs a service-write trigger that silently
  discards future rows for the exact media path.
- iOS mirrors the rule in `ExternalReferenceImagePolicy`. The loader checks it
  before cache lookup and again at the network boundary; DTO normalization and
  cached `SimilarSpeciesEntry` decoding treat a denied URL as absent.
- `SimilarSpeciesImageFetcher` removes denied candidates before download and
  restores source order after concurrent work. A blocked first result therefore
  promotes the next successful image deterministically; an empty result uses the
  existing leaf placeholder.

The API payload shape is unchanged. Suppression removes a value from an existing
image field or array; it does not introduce moderation metadata into a public
response.

When adding another exact external-media outlier:

1. Record a stable provider media identity and the narrowest immutable host/path
   prefix.
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

1. downloads the selected media from the exact approved host with a 15-second
   deadline and 12 MB hard cap, then computes SHA-256;
2. reuses a matching content-addressed attestation only when checksum, model,
   and publication-policy version all match;
3. on a cache miss, sends the bounded bytes inline to a dedicated
   `gemini-2.5-flash` classifier;
4. evaluates speech, non-speech sounds, policy categories, confidence, and
   review state through strict structured output;
5. persists only the checksum, decision, model, policy version, MIME type, and
   byte size—never transcript, URL, user identity, filename, or media bytes;
6. continues into the normal atomic share write only when every audible selected
   item is approved.

Rejected classifications and any fetch, provider, configuration, or
response-shape failure return an error and leave the prior Explore state
unchanged; nothing is shared. Transcripts and non-speech descriptions are not
persisted or logged. This path reuses the existing `GEMINI_API_KEY` Edge secret.
Manual reports remain necessary because model moderation cannot guarantee
complete detection. The immutable publication policy is a Gemini system
instruction so speech or lyrics inside untrusted media cannot replace it.
Standalone audio preserves its supported audio MIME type; audio-bearing MP4 uses
`video/mp4` so Gemini evaluates the actual container instead of relabeling video
bytes as WAV. Public web post pages include a support-email report action
containing the immutable post id. Native Explore post reports write the
dedicated `explore_post_reports` moderation queue through
`/report-explore-post`; they do not enter identification review or set
`scans.is_flagged`. Structured moderation telemetry logs only outcome, model,
latency, and sanitized errors; transcripts and media URLs must never be logged.
A policy-version or model change is an automatic cache miss, so changed safety
rules always force a new Gemini decision. Cache read/write failures degrade to
live moderation and never bypass the publication gate.

Spectrogram generation is downstream presentation work, not a safety decision.
Only after standalone WAV media is approved may `_shared/audioSpectrogram.ts`
derive and upload its deterministic PNG. Generation failure must preserve the
approved canonical recording and speaker fallback; it must never reinterpret a
failed thumbnail as moderation approval, reprocess unapproved bytes, persist a
transcript, or log a media URL.

Legacy audio repair does not bypass this gate. Owner-scoped staging keys are
promoted and persisted to the scan before selection resolution; the restored
bytes then require the same checksum attestation or live Gemini decision as new
audio. A definite scan-persistence rejection rolls back promoted R2 objects only
after an exact-owner read proves their URLs absent. Lost or unreadable responses
preserve the objects and return retryable 503.

Native and public-web **Boost audio** are strictly post-publication playback
DSP. Native processing uses a bounded temporary local copy; web processing uses
an allowlisted same-origin stream plus browser-local gain/filter/limiting. They
must never overwrite or upload enhanced audio, change the R2 object/checksum,
create a new moderation attestation, or moderate the processed waveform instead
of the original public bytes. Boost preferences remain local listening state and
are not part of the safety or publication decision. The web proxy accepts only
HTTPS `.wav` objects on exact host `media.merian.app` below `public_uploads/`;
it must not become a general-purpose fetch proxy.

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

Before scan media is published or the final scan row is persisted, the Edge
Function checks two Gemini safety signals. Quota, ingestion-ledger, and
sanitized replay-intent records may already exist at this point:

1. **`finishReason === "SAFETY"`** — Gemini refused to generate a full response
   due to content policy. Immediately flagged as unsafe.
2. **`safetyRatings[]` probability** — If any individual safety category is
   rated `"MEDIUM"` or `"HIGH"`, the media is flagged regardless of
   `finishReason`.

`"LOW"` and `"NEGLIGIBLE"` probability ratings are treated as safe and do not
trigger moderation.

A provider response that ends before structured output with exact finish reason
`SAFETY` or `PROHIBITED_CONTENT` follows the earlier provider-policy terminal
path. The ingestion ledger records `ai_inference_non_stop_finish` plus stable
`terminal_reason_code = 'provider_policy_rejected'`. Owner-row recovery does not
interpret provider text and cannot convert that rejected request into a scan.
This path may not have a usable `safetyRatings[]` object and therefore is
distinct from the strike-recording pass below.

## Abuse Strike System

Each unsafe media submission increments `users.abuse_strikes` in the Supabase
`users` table:

| Strike Count | Internal status   | Behavior                                           |
| ------------ | ----------------- | -------------------------------------------------- |
| 1–2          | `DELETED_WARNING` | Staging media deleted and scan not persisted       |
| 3+           | `SHADOWBANNED`    | Same as above, plus `users.is_shadowbanned = true` |

For `/identify-multimodal`, either internal status becomes generic
customer-facing HTTP `400 observation_rejected`; no successful local scan should
be created. Compatibility routes may already have returned their AI response
before the shared moderation/insertion task reaches this decision.

The strike counter is read and written via the Supabase service role in
`_shared/identify/moderation.ts`. The read uses
`.select("abuse_strikes").eq("id", userId).single()`. `PGRST116` (no row found)
falls back to `0`; any other read/write failure aborts moderation with `ERROR`
so the caller never believes a strike was recorded when the DB write actually
failed.

### Shadowban Behavior

`is_shadowbanned` is a boolean column on the `users` table (default `false`).
Shadowbanned users are not informed of that account state. Public Explore,
Community Identification, notification, and related projections exclude
shadowbanned authors server-side.

The moderation helper sets this flag after the third unsafe submission, but it
does not currently read the flag as a blanket veto for every later safe scan
insert. The flagged request itself is rejected and not persisted. A later safe
owner scan may still persist privately while its public/social projections
remain suppressed. No iOS-layer check for `is_shadowbanned` currently exists.

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
work can prove they are handling the same media set. A paired
`scan_ingestion_intents` row stores the sanitized replay request without raw
media bytes; inline foreground media is redacted and marked non-resumable. The
scheduled `replay-scan-ingestion` worker retries resumable staged
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
moderation rollback, and storage lifecycle jobs must not target `avatars/`. The
explicit account-erasure state machine is the only owner-prefix exception: after
relational cleanup, its fenced five-prefix job also removes that owner's
avatars. Neither `public_uploads/free/`, `public_uploads/pro/`, nor `avatars/`
may have an age-based expiration lifecycle rule.

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

For a true staging promotion, the filename is derived from
`r2ObjectKeys[i].split("/").pop()`. Base64 direct uploads always receive a
server-generated UUID plus the bounded image extension; an ignored legacy
transport hint cannot influence the public object name, extension, durable
manifest, or media ownership checks.

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

If `modResult.publicUrls` is populated and scan insertion returns a definite
database rejection, the shared persistence boundary first proves the exact owner
row is absent. Only then does `index.ts` roll back promoted objects:

```typescript
if (
  !scanInserted &&
  !persistenceOutcomeUnknown &&
  modResult?.publicUrls?.length
) {
  const keysToPurge = modResult.publicUrls.map((url) =>
    url.replace("https://media.merian.app/", "")
  );
  await Promise.allSettled(
    keysToPurge.map((key) => deleteR2ObjectIfPresent(key, r2Config)),
  );
}
```

This prevents known orphans without turning a lost database response into
permission to delete media referenced by a scan that may have committed.

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

User-profile reports follow the same separation rule. `/report-user` accepts
only a visible non-self author profile and writes `user_reports`; it does not
block the user automatically. Identification, post, comment, and user intake
rows are grouped into private `internal.review_cases`. Moderator hide/restore is
reversible and independent of explicit case resolution. A hidden post is
excluded from feed, map, profile, detail, notification, community, and public
web projections through the shared `moderated_at IS NULL` visibility contract.
All review reads and transitions are audited, and raw report text is never
placed in application logs or URLs.

### Operational media quarantine is not moderation

`explore_posts.media_health_status = 'quarantined'` means every primary
observation object was confirmed missing by two spaced direct R2-origin checks.
It is system-owned availability state, not a safety judgment, strike, report
outcome, or moderator action.

Media reconciliation must not set `moderated_at`, resolve/reopen a review case,
increment abuse strikes, or delete report evidence. Conversely, restoring media
does not clear `moderated_at` or republish content the author has unpublished.
Public projections require all independent visibility conditions to pass.

Do not use reference imagery to make a missing observation appear intact.
Confirmed-missing evidence is omitted; all-missing posts are preserved for the
owner and removed from public projection. See
[Explore Media Health and Quarantine](../backend-and-data/12-explore-media-health-and-quarantine.md).

### Internal review operating contract

The admin case is the workflow source of truth; legacy intake `status` columns
remain source-specific evidence state and are not a substitute for the grouped
case. Moderators use this sequence:

1. Open the case, review all source rows and the minimum subject/account context
   needed for the decision. Exact location is permitted only on identification
   detail and the access is audited.
2. Move the case to `in_review`, set priority, and assign an active moderator or
   owner when ownership is clear.
3. Append notes instead of editing prior notes. Do not paste report/chat text or
   coordinates into external logs, URLs, or unapproved tickets.
4. Hide a post/comment immediately when public harm warrants it. Hiding is
   reversible and does not imply that the report is substantiated or resolved.
5. Set `resolved` or `dismissed` explicitly with a meaningful resolution code.
   Identification resolution only clears `scans.is_flagged` when no other
   open/in-review identification case exists; it does not rewrite the species.
6. Restore content only through the audited restore action and only after the
   visibility decision is independently justified.

A new source from a reporter already represented in the case updates evidence
without incrementing independent report count or reopening terminal state. The
first source from a different reporter reopens a resolved/dismissed case. This
rule prevents one user from repeatedly reopening a case while preserving new
independent safety signals.

Hidden posts must remain absent from Recent/Following/trending/nearby feeds,
maps, author profiles, post detail, community-identification surfaces, derived
notifications, widgets, and public web. A release that changes an Explore
projection must run the moderation projection contract before deployment.

Owners may revoke an admin session or disable membership during a suspected
staff-account compromise. Audit and note rows are immutable evidence and must
never be deleted as part of incident cleanup. Full incident procedures are in
[`../backend-and-data/11-internal-admin-operations.md`](../backend-and-data/11-internal-admin-operations.md#incident-response).

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
  scan metadata while preserving the row for offline cache continuity. Initially
  introduced by `00006_apply_user_tombstone.sql`; the durable state machine and
  ownerless retained-observation model are installed by the `20260725030308` and
  `20260725041308` forward migrations. Ownerless rows must be tombstoned, clear
  exact location/elevation and intervention notes, and are excluded from
  anonymous scan-table reads.
