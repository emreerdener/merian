# update-explore-field-notes

Updates the public share options on an existing Explore post owned by the
current user. Despite the legacy function name, this endpoint now updates the
public field-notes copy, public common-name snapshot, hashtags, and post-level
location sharing.

This function intentionally does not update the private local notes stored in
SwiftData. The iOS app keeps private notes in `LocalScanRecord.fieldNotes` or
`OfflineQueuedScan.fieldNotes` and uses `FieldNotesRepository` as the local
source of truth. Explore receives only the public copy the user explicitly
chooses to show.

## Request

```json
{
  "post_id": "uuid",
  "field_notes": "Found at the shaded meadow edge after rain.",
  "species_common_name": "Black-Tailed Deer",
  "hashtags": ["deer", "urbanwildlife"],
  "location_sharing": "obscured",
  "media_items": [
    {
      "kind": "video",
      "source_media_id": "scan:uuid:video:0",
      "order_index": 0
    },
    {
      "kind": "image",
      "source_media_id": "scan:uuid:image:0",
      "order_index": 1
    }
  ]
}
```

`field_notes` and `species_common_name` may also be `null`. `location_sharing`
may be `open`, `obscured`, or `private`; legacy `hidden` input is accepted as
`private`.

`media_items` is optional. New clients should submit `source_media_id` values
returned by `get-explore-composer-media`; this allows owners to reorder, remove,
or re-add eligible source scan media. Legacy clients may still reorder/remove
the post's existing public image/video rows by URL. Arbitrary URLs are not
accepted, and videos must resolve to an image-backed thumbnail.

For video scans, `source_media_id` is resolved through the same source list used
by `share-scan-to-explore` and `get-explore-composer-media`: ready
display/playback rows in `scan_media_assets` first, then `scans.captured_media`,
then legacy URL arrays. That keeps the playback `.mp4` paired with its poster
thumbnail instead of relying on sampled frame indexes. Video `has_audio`
metadata follows the selected source's actual audio evidence; legacy URL-array
video sources default false.

Standalone-audio edits use the same publication contract as first share. Every
newly selected audible item must pass the existing content-addressed
attestation/live moderation gate before public media changes are written. An
approved WAV then reuses or generates its deterministic spectrogram PNG and
copies that URL into the replacement `explore_post_media` rows plus matching
normalized scan asset. Reordering an existing legacy audio row preserves a blank
thumbnail instead of substituting the WAV playback URL as image media; web
playback therefore keeps the speaker fallback safely.

Clients send one UUID `Idempotency-Key` for an edit that includes media. The
function derives one opaque child key per checksum and policy version. A cache
miss reserves the database-owned `explore_audio_moderation` quota, including
durable entitlement, selected model, daily ceiling, and user/IP rate limits.
Cache hits refund; a provider attempt commits immediately before dispatch. The
default moderation helper fails closed before fetching media if the quota
callback is absent.

## Response

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

## Validation And Authorization

- Runs through `withEdgeHandler`; the caller must resolve to a Supabase user.
- `post_id` must be a valid UUID.
- `field_notes` must be a string or `null`.
- Empty or whitespace-only values are normalized to `null`.
- Non-empty values are trimmed and capped at 1000 characters.
- `species_common_name`, when supplied, is trimmed, internal whitespace is
  collapsed, and the stored public snapshot is capped at 200 characters.
- `hashtags`, when supplied, replaces the post's public hashtag edges after the
  same normalization used by `share-scan-to-explore`.
- `location_sharing`, when supplied, updates only this Explore post. It does not
  mutate `scans.geoprivacy` or `users.default_geoprivacy`.
- `media_items`, when supplied, must contain at least one existing image/video
  source row owned by this post's scan or one existing public post media URL.
  Non-visual kinds and videos without thumbnails are rejected.
- `open` can make the post eligible for Explore Map and non-owned Nearby when
  public coordinates are safe; `obscured` can keep a scrubbed public label but
  stays off spatial results; `private` clears public location fields.
- Updates are scoped to `explore_posts.id`, `explore_posts.user_id`, and
  `unshared_at IS NULL`; non-owned, missing, or unshared posts return 404.
