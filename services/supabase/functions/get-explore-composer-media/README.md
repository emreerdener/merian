# get-explore-composer-media

Returns the owner-only media source list used by the Explore post composer. This
endpoint bridges private scan media to public Explore post media without adding
private scan media to public feed/detail payloads.

## Request

```json
{
  "scan_id": "uuid"
}
```

or:

```json
{
  "post_id": "uuid"
}
```

## Response

```json
{
  "data": {
    "scan_id": "uuid",
    "post_id": "uuid-or-null",
    "media_items": [
      {
        "source_media_id": "scan:uuid:image:0",
        "kind": "image",
        "url": "https://public.example/images/photo.webp",
        "thumbnail_url": "https://public.example/images/photo.webp",
        "order_index": 0,
        "has_audio": false,
        "is_selected": true,
        "selection_order_index": 0
      },
      {
        "source_media_id": "scan:uuid:video:0",
        "kind": "video",
        "url": "https://public.example/videos/clip.mp4",
        "thumbnail_url": "https://public.example/images/poster.webp",
        "order_index": 1,
        "has_audio": true,
        "is_selected": false,
        "selection_order_index": null
      },
      {
        "source_media_id": "scan:uuid:audio:0",
        "kind": "audio",
        "url": "https://public.example/audio/clip.wav",
        "thumbnail_url": "",
        "order_index": 2,
        "has_audio": true,
        "is_selected": true,
        "selection_order_index": 2
      }
    ]
  }
}
```

## Rules

- Requires an authenticated owner.
- `post_id` must belong to the current user and resolve to an active Explore
  post.
- `scan_id` must belong to the current user and must not be tombstoned.
- Returns only durable image/video/audio URLs that can be selected for Explore
  posts.
- Video rows include their playable public `.mp4` URL plus the required public
  poster image URL. The poster is selection metadata for the video row, not a
  separate image item unless the scan also contains that image as user media.
- The response prefers ready display/playback rows in `scan_media_assets`, then
  falls back to `scans.captured_media`, then legacy image/video/audio URL
  arrays. This keeps video clips and poster thumbnails paired while allowing old
  rows to keep working. `/share-scan-to-explore` resolves submitted
  `source_media_id` values through this same source list.
- `has_audio` is true only when normalized media or `captured_media` proves that
  a video has an audio companion; legacy URL-array video sources default false.
- The iOS composer should prefer this endpoint for cloud-backed scans before
  opening the share UI. It is server-authoritative for repaired video rows and
  legacy rows whose `image_storage_urls` still contain sampled inference frames.
  If the cloud row lacks a video item but the local scan still has a playback
  `.mp4`, the client can fall back to local media long enough to attempt
  `/share-scan-to-explore` repair.
- Standalone audio is returned with `has_audio = true`. A never-published audio
  source may have an empty thumbnail; a previously shared or backfilled WAV may
  reuse its persisted `scan_media_assets.thumbnail_url` spectrogram. Extracted
  `video_audio`, Describe content, observation context, AI/reference images, and
  Dictionary media are not returned as standalone items.
- For first-share `scan_id` requests, all eligible media is selected by default.
- For edit `post_id` requests, current public post media is marked selected and
  ordered by `selection_order_index`; eligible unselected scan media is returned
  after the selected set.

Public Explore feeds continue to read from `explore_post_media`; this endpoint
is only for the authenticated composer.
