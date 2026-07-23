# share-scan-to-explore

Creates or reactivates the current user's Explore post for one eligible scan.
The endpoint shares the post content; post-level location visibility is stored
separately from the backing scan's `geoprivacy`.

## Request

```json
{
  "scan_id": "uuid",
  "field_notes": "Found at the shaded meadow edge after rain.",
  "species_common_name": "Black-Tailed Deer",
  "hashtags": ["deer", "urbanwildlife"],
  "location_sharing": "obscured",
  "restored_video_object_keys": ["staging/user-id/restored-video.mp4"],
  "restored_audio_object_keys": ["staging/user-id/restored-audio.wav"],
  "media_items": [
    {
      "kind": "image",
      "source_media_id": "scan:uuid:image:0",
      "order_index": 0
    },
    {
      "kind": "video",
      "source_media_id": "scan:uuid:video:0",
      "order_index": 1
    },
    {
      "kind": "audio",
      "source_media_id": "scan:uuid:audio:0",
      "order_index": 2
    }
  ]
}
```

`location_sharing` is optional for backward compatibility. When omitted, the new
or reactivated post uses the scan's current `geoprivacy` as the initial
post-owned value.

Clients should attach one UUID `Idempotency-Key` to the share request and reuse
it across transport, auth-refresh, and media-restoration retries. On audible
shares the Edge Function derives a separate opaque reservation UUID for each
checksum and moderation-policy version, so multiple clips remain independent
without exposing their checksums in the quota ledger. A later manual share may
use a new key; an existing content-addressed attestation then avoids and refunds
the provisional provider reservation.

`media_items` is optional for legacy clients. When present, it is the ordered
public media selection for this post. New clients should submit
`source_media_id` values returned by `get-explore-composer-media`. Legacy
clients may still submit `source_index` and `thumbnail_source_index` values that
point to the scan's promoted image/video/audio URL arrays; for videos,
`thumbnail_source_index` must resolve to the scan's promoted poster image.
Describe content, AI/reference images, and Dictionary media are not valid
Explore post media.

For video scans, `source_media_id` resolves through the same source list shown
by the composer: ready display/playback rows in `scan_media_assets` first, then
`scans.captured_media`, then legacy URL arrays. This keeps the playback `.mp4`
and poster thumbnail paired even when sampled inference frames also exist in
legacy image URL arrays.

Video `has_audio` metadata is copied from normalized media rows or derived from
the `captured_media` video audio reference. Legacy URL-array videos default to
`false` because those rows do not prove that an audio companion was persisted.

`restored_video_object_keys` is optional and only used by repair-capable
clients. If the owner still has the original local `.mp4` but the cloud scan row
is missing `video_storage_urls`, the client uploads that clip to staging and
sends the returned keys here. The function promotes the videos, rebuilds
`captured_media`, makes a best-effort `scan_media_assets` refresh, and validates
the selected video media again before publishing. Rows whose original local
video is gone remain image-only historical rows.

`restored_audio_object_keys` is the equivalent owner-scoped repair input for
legacy audio scans whose local WAV/M4A still exists but whose cloud scan
predates durable `audio_storage_urls`. At most two staging keys are accepted.
The function promotes them, replaces legacy local audio references in
`captured_media`, updates `audio_storage_urls`, refreshes normalized media
assets, and then applies the normal fail-closed publication moderation. Failed
promotion or scan persistence rolls back promoted R2 objects and publishes
nothing. If the local recording is gone, the audio cannot be recovered.

Valid location values:

- `open`: project post-owned public coordinates and allow Explore Map and
  non-owned Nearby eligibility when coordinates are safe.
- `obscured`: keep a scrubbed public location label when available, but do not
  expose map coordinates.
- `private`: share the post without public location fields.

Legacy `hidden` input is accepted as `private`.

## Response

```json
{
  "success": true,
  "post_id": "uuid",
  "scan_id": "uuid",
  "shared_at": "2026-06-17T19:30:00.000Z",
  "location_sharing": "obscured",
  "publication_status": "published"
}
```

All successful shares return `200` with `publication_status = "published"`. For
standalone audio or an audio-bearing video, `_shared/audioModeration.ts` must
resolve an approved attestation for every audible selected item before the
post/media upsert runs. A matching attestation can be reused; otherwise Gemini
evaluates speech and non-speech content live. Flagged content returns `422`;
provider or configuration failures on a cache miss return `503`. In both cases
nothing is created, reactivated, or made public. Cache misses reserve the
database-owned `explore_audio_moderation` quota before provider dispatch. The
reservation atomically applies the durable entitlement, model policy, daily
limit, and shared per-user/IP rate limits.

The same mandatory quota-backed moderation preparation is reused by
`request-community-identification` and media-bearing
`update-explore-field-notes` requests. The shared default helper refuses
provider work when a caller omits that boundary.

When one share request must repair more than one media kind, the function
resolves that caller's durable entitlement once and reuses it only within the
current handler invocation. It does not keep a process-local or cross-request
entitlement cache.

The function emits privacy-safe PostHog funnel events for each audible media
moderation outcome and for successful publication. Properties are limited to
coarse outcome, media composition, model, latency bucket, and location-sharing
mode. They never include transcripts, media URLs, filenames, post IDs, species
identity, or coordinates. Telemetry uses the Edge background execution lock so
PostHog latency cannot delay publication.

Moderation decisions are cached by SHA-256, policy version, and model in
`explore_audio_moderation_attestations`. The cache is shared across identical
bytes without storing a URL or user identity. Cache hits avoid a second Gemini
call; changed bytes, policy versions, or models force live moderation. Cache
failures fall back to live Gemini classification and never approve content by
default.

After standalone WAV audio is approved, `_shared/audioSpectrogram.ts` performs
the presentation-only media step: it decodes bounded PCM WAV, applies the same
2048-point Hann-windowed FFT, 128 mel bins, 80 Hz–16 kHz range, −80 dB floor,
and palette used by iOS, then writes a deterministic
`spectrogram-v1-{sha256}.png` beside the durable recording. An existing object
with the same content-derived key is reused. The URL is copied to the audio
`explore_post_media.thumbnail_url` snapshot and matching
`scan_media_assets.thumbnail_url` row.

Spectrogram creation never weakens or replaces moderation. It runs only after
approval and is non-blocking: unsupported legacy codecs, malformed WAV data, or
R2 thumbnail failures keep the recording playable with the speaker fallback.
`backfill-explore-audio-spectrograms` applies the same deterministic generator
to historical blank WAV snapshots in bounded service-role-only batches.

## Rules

- Requires an authenticated user through `withEdgeHandler`.
- `scan_id` must belong to the current user.
- Tombstoned scans, media-less scans, and scans without a resolved species are
  not share-eligible.
- Sharing snapshots public image/video/audio URLs into `explore_post_media` for
  the post. Video posts require a public thumbnail image; otherwise the endpoint
  returns `Video thumbnail unavailable.`
- Approved standalone WAV rows normally carry a generated PNG `thumbnail_url`;
  non-WAV legacy rows may keep that field blank without losing playback
  eligibility.
- Media selections are validated before the post is reported as shared. Public
  feed/share-state visibility requires at least one saved `explore_post_media`
  row, so a failed media snapshot cannot leave a phantom visible Explore post.
- Restored video keys are promoted before the public media snapshot is written.
  If promotion fails or selected video media still cannot be resolved, the
  request fails cleanly instead of publishing sampled frames as a video.
- Describe/observation context is private scan context. It is never copied into
  `field_notes`, hashtags, captions, media metadata, or the public media
  snapshot unless the user manually writes that text into the composer.
- When `media_items` is supplied, only the selected image/video/audio rows are
  written to `explore_post_media`, ordered by `order_index`; the first selected
  visual URL, video poster, or persisted audio spectrogram becomes the computed
  `hero_image_url`.
- Empty media selections, unsupported media kinds, invalid source indexes, and
  videos without a thumbnail are rejected.
- Audio moderation reuses the `GEMINI_API_KEY` Edge secret. Gemini transcripts
  and non-speech descriptions are not persisted, logged, or returned to clients.
- The policy is supplied as an immutable system instruction and its effective
  cache version is derived from the prompt, categories, confidence threshold,
  and structured-output contract. Standalone audio keeps a supported audio MIME
  type and audible playback video keeps `video/mp4`; unsupported or ambiguous
  media types fail closed.
- Audio moderation runs before `explore_posts`, `explore_post_media`, hashtags,
  or resolved-community publication state is mutated. Approval is therefore a
  strict prerequisite for the share, not a post-publication status.
- If the scan has a resolved Ask the Community request, publishing materializes
  any new GBIF-backed resolved species into `species_dictionary`, sets
  `scans.confirmed_species_id`, and stamps the request's `explore_published_at`
  before the post becomes visible in normal Explore surfaces. Materialization
  also queues species-content provenance rows so normal Dictionary enrichment
  can hydrate the new species over time.
- Private backing scans can be shared; `private` means no public location on the
  post, not blocked sharing.
- The endpoint does not mutate `scans.species_id`, `scans.geoprivacy`, or
  `users.default_geoprivacy`.
- Hashtags are normalized to lowercase text without `#`, capped at five tags,
  and replace the post's existing hashtag edges for this share request.
- `species_common_name` stores the public post common-name snapshot when
  provided; omitted or empty values preserve dictionary fallback behavior.

## Spatial Privacy

The database trigger on `explore_posts` writes post-owned `public_latitude`,
`public_longitude`, `public_coordinate_visibility`, and `public_location_label`
from the saved `location_sharing` value. Even when a post is set to `open`,
protected-species and coordinate-uncertainty rules can store rounded public
coordinates with `coordinate_visibility = "obscured"`.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/share-scan-to-explore/index.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/communityIdentificationDb.test.ts
```

DB integration tests require a running local Supabase Postgres instance at the
configured test URL.
