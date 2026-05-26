# Explore Hashtags

Explore hashtags are public metadata on a manually shared Explore post. They are
stored as normalized post-to-tag edges so Merian can browse tagged posts now and
later match event or BioBlitz submissions without parsing public field notes,
comments, or captions.

## Shipped Behavior

- The Explore share flow accepts up to five hashtags with spaces or commas in the
  iOS share sheet.
- The share sheet also renders quick-tap AI-assisted suggestions below the
  hashtag text field. Suggestions are derived locally from the scan's field
  notes, species identity, AI metadata, public location label, habitat/weather
  context, image-quality signals, and event tags when supplied.
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

## Composer Suggestions

`ExploreHashtagSuggestionEngine` owns the iOS-side suggestion pass for the share
composer. It is intentionally local and deterministic: the composer does not
call an LLM or another network endpoint while the user is typing. Instead, it
uses the already-available identification and scan metadata:

- species common name and scientific name
- public location label after `ExploreLocationPrivacy` has removed exact
  coordinates
- public field notes as currently edited in the composer
- ecology type, taxonomy kingdom/class/order/family, habitat, weather, colors,
  group tags, semantic tags, invasive flag, image quality score, life stage,
  reproductive condition, and ecological interactions
- optional `eventHashtags` for future local event or BioBlitz configuration

Suggestions are normalized through the same client-side helper used for typed
hashtags:

- leading `#` is ignored
- tags are lowercased
- diacritics and width variants are folded
- only letters, digits, and underscores are retained
- duplicate and already-selected tags are removed
- `featured` is reserved and never suggested or submitted
- tag length stays within the backend's 2-40 character contract

The composer shows at most eight chips, but it also respects the five-tag
publishing limit. If the user already typed four tags, only a small remaining
set is shown. Tapping a chip appends `#tag` to the hashtag field and emits a
selection haptic. Field-note edits refresh the suggestions immediately, so a
note like "schooling in a shallow creek after rain" can surface `#creeklife`,
`#freshwater`, `#schoolingfish`, or `#afterrain` before the post is shared.

Suggestion ranking prefers high-signal tags first: explicit event tags, the full
species name, location tags such as `#austintx`, taxonomy/ecology tags such as
`#freshwaterfish`, then field-note and image-quality tags. Individual words from
the common name are deliberately lower priority so they do not crowd out useful
context.

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
- Composer UI:
  `Features/Explore/Components/ExplorePostComposerView.swift`
- Suggestion context and ranking:
  `Features/Explore/Models/ExploreHashtagSuggestion.swift`
- Context assembly from scan/identification metadata:
  `Features/Insights/Components/Toolbars/BottomToolbar/InsightBottomToolbar.swift`
- Regression tests:
  `MerianTests/Features/Explore/ExploreHashtagSuggestionTests.swift`

The feed `ExplorePost` DTO keeps `hashtags` optional for rollout tolerance. The
updated feed-like Edge functions should still return `[]` for untagged posts so
newer UI can make spacing decisions without per-card detail requests.

## Future Event Matching

Hashtag browsing does not auto-submit a post to an event yet. Event or BioBlitz
configuration should reference the same normalized tag strings and match the
public edge table server-side, preserving the existing Explore visibility and
moderation boundaries.
