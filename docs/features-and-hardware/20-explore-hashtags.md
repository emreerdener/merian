# Explore Hashtags

Explore hashtags are public metadata on a manually shared Explore post. They are
stored as normalized post-to-tag edges so Merian can browse tagged posts now and
later match event or BioBlitz submissions without parsing public field notes,
comments, or captions.

## Shipped Behavior

- The Explore share flow accepts up to five hashtags with spaces or commas in the
  iOS share sheet.
- A stored tag is lowercase text without the leading `#`.
- Feed cards render hashtag chips below the post media and above the action row.
  The chip row stays one line and scrolls horizontally on overflow.
- Post detail renders the same tag chips centered in a wrapping layout.
- Tapping a feed or detail chip opens a tagged-post collection headed by the
  selected hashtag.
- Tagged-post collections use a 3-column image grid, pull to refresh, and cursor
  pagination. Grid taps open the existing Explore post detail view.

## Data Model

`public.explore_post_hashtags` is the source of truth:

- `post_id UUID` references `public.explore_posts(id)` with cascade delete.
- `tag TEXT` stores normalized lowercase hashtag text without `#`.
- `(post_id, tag)` is the primary key.
- `(tag, post_id)` supports tag-to-post lookup and future event/BioBlitz
  matching.

Migration order matters:

1. `20260521190000_add_explore_post_hashtags.sql` creates the tag edge table and
   adds hashtag output to Explore detail.
2. `20260522090000_add_explore_hashtag_posts_rpc.sql` adds
   `public.get_explore_hashtag_posts(...)` for browse-by-tag collections.

## API Paths

Publishing uses `share-scan-to-explore`:

```json
{
  "scan_id": "uuid",
  "field_notes": "Optional public note",
  "hashtags": ["#CityBioBlitz", "springcount"]
}
```

The endpoint trims leading `#`, lowercases tags, deduplicates them, rejects more
than five tags, and accepts only 2 to 40 letters, digits, or underscores per tag.
Resharing writes the submitted tag set for that Explore post.

Read paths:

- `get-explore-feed`, `get-explore-post`, and `get-explore-author-posts` return
  feed-card `hashtags` arrays by batching a lookup for each returned page of
  `post_id` values.
- `get-explore-post-detail` returns `hashtags` from
  `public.get_explore_post_detail(...)`.
- `get-explore-hashtag-posts` accepts one display or normalized hashtag and
  returns visible card projections ordered by `(shared_at DESC, post_id DESC)`.

Example browse request:

```json
{
  "hashtag": "#CityBioBlitz",
  "limit": 30,
  "before_shared_at": "2026-05-12T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

All hashtag browse rows keep the standard Explore visibility posture: unshared
posts, hidden media, tombstoned scans, private scans, missing-species posts,
shadowbanned authors, and blocked relationships are excluded.

## iOS Touchpoints

- DTOs and network calls: `Core/Network/ExploreAPIModels.swift` and
  `Core/Network/MerianNetworkClient.swift`
- Feed chips: `Features/Explore/Components/ExplorePostCard.swift`
- Detail chips: `Features/Explore/Views/ExplorePostDetailView.swift`
- Tagged-post route and collection: `Features/Explore/Views/ExploreView.swift`
- Share input:
  `Features/Insights/Components/Toolbars/BottomToolbar/ShareButton.swift`

The feed `ExplorePost` DTO keeps `hashtags` optional for rollout tolerance. The
updated feed-like Edge functions should still return `[]` for untagged posts so
newer UI can make spacing decisions without per-card detail requests.

## Future Event Matching

Hashtag browsing does not auto-submit a post to an event yet. Event or BioBlitz
configuration should reference the same normalized tag strings and match the
public edge table server-side, preserving the existing Explore visibility and
moderation boundaries.
