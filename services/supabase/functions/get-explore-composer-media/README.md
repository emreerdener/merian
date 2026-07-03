# get-explore-composer-media

Returns the owner-only media source list used by the Explore post composer.
This endpoint bridges private scan media to public Explore post media without
adding private scan media to public feed/detail payloads.

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
        "is_selected": true,
        "selection_order_index": 0
      },
      {
        "source_media_id": "scan:uuid:video:0",
        "kind": "video",
        "url": "https://public.example/videos/clip.mp4",
        "thumbnail_url": "https://public.example/images/poster.webp",
        "order_index": 1,
        "is_selected": false,
        "selection_order_index": null
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
- Returns only public image/video URLs that can be selected for Explore posts.
- Video rows include their playable public `.mp4` URL plus the required public
  poster image URL. The poster is selection metadata for the video row, not a
  separate image item unless the scan also contains that image as user media.
- Audio, Describe content, observation context, AI/reference images, and
  Dictionary media are not returned.
- For first-share `scan_id` requests, all eligible media is selected by default.
- For edit `post_id` requests, current public post media is marked selected and
  ordered by `selection_order_index`; eligible unselected scan media is returned
  after the selected set.

Public Explore feeds continue to read from `explore_post_media`; this endpoint
is only for the authenticated composer.
