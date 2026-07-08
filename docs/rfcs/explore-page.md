# Explore Page RFC

Merian Explore is a manual-share, image-only public feed of discoveries. V1 is intentionally narrow: users can browse posts, like them, and leave comments, while Merian preserves its privacy-first posture for both authenticated and ghost users.

## Locked Product Decisions

- Sharing is manual per eligible scan. A scan does not become public just because its `geoprivacy` is `open`.
- Explore is image-only in V1. Audio is out of scope.
- Post descriptions/captions are out of scope in V1.
- Explore ships a hybrid notifications model: the in-app feed is the source of truth, and eligible post-backed activity can also fan out to APNs pushes for users who opt into Explore activity notifications. Follow notifications and Field Trip activity are in-app only.
- Explore feed posts open a dedicated public post detail page when the user taps the post body.
- The feed comment icon still opens a bottom-sheet comments view for quick interaction from the main feed.
- Explore includes a privacy-scoped public author profile sheet reachable from feed/detail author headers.
- The author profile sheet can transition sideways into the author's full published Explore scan library.
- The feed now ships four user-facing filters: `Recent`, `Following`, `Trending`, and `Nearby`.
- Explore posts may carry up to five normalized public hashtags. Hashtag chips
  open currently visible tagged-post collections; event and BioBlitz
  auto-submission remains later scope.
- Feed cards may show:
  - Hero image
  - Species common name and scientific name
  - Optional dog/cat pet label as the visible title when a scan carries
    confident `pet_identification`
  - Author label
  - General location only, at city or state level
  - Author avatar for authenticated users when a public avatar URL is available
  - Hashtag chips when the post is tagged
  - Like, comment, and external share actions
- The current V1 card layout is:
  - Author row above the image
  - Full-width square image
  - Species common/scientific name plaque over the bottom-left of the image,
    with `pet_identification.label` allowed to replace only the visible title
    text for confident dog/cat scans
  - Optional one-line scrolling hashtag chip row below the image
  - Action row below the tags or image
- The current V1 detail layout is:
  - Author row
  - Full-width hero image
  - Like, comment, and share actions
  - Optional centered wrapping hashtag chips
  - Species section
  - Public species insight cards
  - Privacy-safe telemetry cards
  - Inline comments with an inline composer
- Broad time context and weather data remain available as optional feed metadata. They are not rendered on the primary feed card UI, but they may appear as sanitized telemetry on the detail page.
- Any imported or captured photo already present in the scan library should be eligible for sharing.
- Future scope: feed cards can open a public species page once that separate species-page project exists.

## Goals

- Give users a lightweight way to publish discoveries to a public Explore feed.
- Preserve strong privacy defaults for ghost users and authenticated users.
- Reuse Merian's existing moderation, geoprivacy, blocking, and feed infrastructure where possible.
- Keep V1 species-first rather than person-first.

## Non-Goals

- Audio posts
- Captions, DMs, private sharing, mutual friend requests, or standalone social profile pages beyond the privacy-scoped author sheet
- Heavy personalization, editorial curation, or ranking beyond the shipped `Recent` / `Following` / `Trending` / `Nearby` modes
- Public species pages in this scope

## Shipped V1 Snapshot (2026-05-05)

The Explore feed and map shell are now live. The current shipped implementation is:

- `ExploreView` uses bottom navigation for `Observations`, `Identify`, `Field Trips`, and `Dictionary`. Observations owns a root-only Feed/Map header toggle with Feed first, Field Trips owns Available/Community, and Dictionary keeps Tree behind its Catalog/Tree header toggle.
- `ExploreMapView` and `ExploreMapViewModel` ship a real MapKit-backed surface with clusters, privacy-aware waypoints, `Search This Area`, `Recenter`, an offline banner, a top-banner empty state, and a two-step preview-card-to-detail interaction. At broad zooms, individual posts still use simple indicator dots; at close zooms, the shipped client upgrades them into circular scan thumbnails when the visible result set is small enough.
- Publication state and post geoprivacy live on `explore_posts`. Spatial reads use post-owned `public_latitude` / `public_longitude`; Explore Map reads them through `public.get_explore_map_posts(...)` and `get-explore-map-points`, and Nearby uses the same stored projection for radius matching. Non-owned spatial results require saved `location_sharing = 'open'`.
- Migration `20260428213000_fix_explore_map_public_coordinate_fallback.sql` added `trg_sync_scan_public_coordinates` so newly shared scans with exact coordinates are normalized/backfilled correctly before map reads.
- `ExplorePostStore` now owns shared Explore post state across feed, map, detail, comments, and notification-driven navigation, while `ExploreFeedViewModel` keeps feed-specific UI and pagination state.
- Explore post projections can carry `pet_identification` from the backing scan.
  Native clients may show its label on cards/detail/share text, while dictionary
  links, species stats, and taxonomy routing continue to use
  `species_scientific_name`.
- The feed tab now ships a filter row with `Recent`, `Following`, `Trending`, and `Nearby`.
- `Recent` remains the default mode and still uses the canonical `(shared_at, post_id)` cursor.
- `Following` is an asymmetric-follow feed backed by followed authors' visible Explore posts. It uses the same `(shared_at, post_id)` cursor as `Recent` and does not change `Recent`, `Trending`, `Nearby`, or map results.
- `Trending` is freshness-biased rather than all-time top. It uses recent like activity from the trailing 30 days and paginates on `(ranking_value, shared_at, post_id)`.
- `Nearby` requires viewer location, reads the same post-owned public coordinates as the map, filters non-owned coordinate-bearing posts to a roughly 50-mile radius, and then sorts the surviving posts by recency rather than raw distance.
- The Explore-tab unread badge and "last seen" bookkeeping remain tied to the `Recent` feed only so browsing alternate modes does not mutate recency tracking.

## Public Author Profile Extension (2026-05-11)

Explore now supports public author profile sheets without turning Explore into a private profile browser. The entry point is the author header on feed cards and post detail pages. The post media still opens `ExplorePostDetailView`.

The sheet renders:

- public author avatar and name
- follower and following counts
- a `Follow` / `Following` button for other users
- published Explore post count
- species discovered
- current streak
- 52-week scan heatmap
- up to 9 preview published scans in a 3-column grid
- active Field Trip checklist progress, when visible
- published Field Trip cards, when visible
- Field Trip challenge completion badges, when visible
- achievements as informational cards
- a "View all published scans" control that side-transitions into a paginated 3-column library

The profile and library have deliberately different privacy scopes:

- Profile stats, streak, heatmap, and achievement progress are computed from all of the author's non-tombstoned scans.
- Preview and full library grids include only currently visible Explore posts.
- Active Field Trip profile rows include checklist status only and never expose scan IDs, media, field notes, exact coordinates, public location labels, or evidence.
- Published Field Trip rows open Field Trip publication details, not Explore post details.
- Field Trip challenge badges are lightweight public reward cards. They expose
  badge/challenge labels and broad tags only, never scan IDs, media, exact
  locations, notes, or private evidence.
- Achievement payloads contain progress only and never include qualifying scan IDs.
- Public achievement cards do not open detail sheets or scans.
- Follow counts are public on visible profiles, but follower/following identities are not exposed and the counts do not open tappable lists.
- The `Follow` button is hidden for the viewer's own public profile. It follows asymmetrically; there are no friend requests, mutual-only states, DMs, or access changes to private scans.

The backend returns an author profile only if the target author has at least one Explore post visible to the requesting viewer or at least one visible Field Trip profile surface. This prevents the endpoint from exposing arbitrary user profiles by UUID. Shadowbanned authors, blocked relationships, unshared posts, tombstoned scans, private scans in published grids, posts without image media, posts without a species key, and non-visible Field Trips are all filtered using the same visibility posture as the rest of Explore.

The full library reuses the card-shaped Explore post projection and paginates on `(shared_at DESC, post_id DESC)` using `before_shared_at` and `before_post_id`.

## Following Extension (2026-05-11)

Explore now supports asymmetric follows for public author profiles. Following is intentionally a small discovery affordance, not a friend system.

Following changes only these surfaces:

- `get-explore-feed` accepts `filter: "following"` and returns visible posts from authors the viewer follows, ordered by `(shared_at DESC, post_id DESC)`.
- `get-explore-author-profile` returns `follower_count`, `following_count`, and `viewer_is_following`.
- `ExploreAuthorProfileSheet` shows follower/following counts and an optimistic `Follow` / `Following` button for non-self profiles.
- `explore_post_notifications` supports a postless `follow` row for in-app notifications.

Following intentionally does not:

- affect `Recent`, `Trending`, `Nearby`, map, or widget ranking
- create new-post alerts
- create APNs pushes
- expose follower or following lists
- make hidden profiles discoverable by UUID
- grant access to private scans

The follow write path is `/set-user-follow`. Follow requests require a visible Explore profile, no self-follow, no mutual block, and a non-shadowbanned target. Unfollow deletes the relationship even if the target is no longer visible so stale relationships can always be removed.

Blocking removes follow rows in both directions. Ghost-account merge reparents follow rows from the ghost public user to the authenticated public user and dedupes conflicts.

## Hashtag Extension (2026-05-22)

Explore hashtags are normalized public metadata on an Explore post, not parsed
caption text. The publishing flow accepts up to five display hashtags and stores
lowercase tag text without the leading `#` in `explore_post_hashtags`.

The shipped browse behavior is:

- feed-card post projections include `hashtags` arrays from a batched post-page
  lookup and render a one-line horizontally scrolling chip row
- detail payloads include the same tags and render centered wrapping chips
- tapping a chip opens `ExploreHashtagPostsView`, a paginated image grid backed by
  `get-explore-hashtag-posts` and `public.get_explore_hashtag_posts(...)`
- hashtag collections apply the same visible-post filters as feed and author
  library reads, then page by `(shared_at DESC, post_id DESC)`

The `(tag, post_id)` index keeps event or BioBlitz matching server-side. This
extension does not yet define event configuration, submission state, or
moderation rules for automatically attaching a tagged Explore post to an event.

## Recommended Product Model

Explore should be treated as a publishing layer on top of scans, not as a direct view over every public scan.

- A user shares a scan.
- Merian creates a public Explore post for that scan.
- Likes and comments belong to the Explore post.
- Unsharing removes the Explore post without deleting the underlying scan.
- One scan should have at most one active Explore post in V1.

This keeps the private scan record separate from the public publication state and makes manual sharing, unsharing, moderation, and future feed-specific behavior much cleaner.

## Identity Model

Explore should render a dedicated public author label rather than relying on raw auth metadata.

Recommended V1 shape on `public.users`:

- `public_author_name TEXT NOT NULL`
- `public_username TEXT NOT NULL`
- `public_identity_source TEXT NOT NULL`
  - Allowed values: `alias`, `derived_name`, `display_name`
- `public_avatar_url TEXT NULL`

Rules:

- Ghost users default to a stable alias that is also a valid username handle.
- Authenticated users default to `First L.` derived from auth metadata when available.
- If no safe first-name metadata exists, authenticated users also fall back to the stable alias.
- If auth metadata includes a provider avatar (`avatar_url` or `picture`), Merian may copy it into `public_avatar_url` for Explore rendering.
- Ghost users should leave `public_avatar_url` null.
- Editable usernames update `public_username`. `public_author_name` remains the
  Explore display label for logged-in/provider-derived identities.
- Feed and comments should render `public_author_name` for logged-in display
  labels and `@public_username` for default/ghost identities. Feed, map,
  profile, and comment surfaces may optionally render `public_avatar_url`.
- Future comment mentions should use `public_username`, not
  `public_author_name`.
- Email and raw auth metadata must never be exposed directly in Explore payloads. Public avatar access should happen only through the copied `public.users.public_avatar_url` field.

This gives us the "show a user if logged in, otherwise show an alias" behavior without coupling Explore to private identity fields.

Normalization rule:

- Public author identity should remain normalized on `public.users`.
- Feed, map, profile, and comment payloads should join `public.users` at read
  time rather than copying `public_author_name`, `public_username`, or
  `public_avatar_url` into `explore_posts`.
- This allows public alias and avatar updates to flow through to historical Explore content automatically.

## Feed Card Anatomy

Each Explore card should contain:

- Primary image
- Common name snapshot chosen by the post author
- Scientific name
- Author label
- Optional author avatar
- General location label
- Optional public hashtag chips
- Like count
- Comment count
- Like button
- Comment button
- External share button
- Overflow actions for block/report/unshare when appropriate

V1 card behavior:

- Tapping the card body pushes a dedicated Explore post detail page inside the Explore navigation stack.
- Tapping a hashtag chip opens the visible post collection for that tag.
- Tapping comments from the feed opens a bottom-sheet comment view for that post.
- Tapping the overflow menu exposes actions, not navigation.
- The Explore sheet header includes a bell button with an unread badge that opens the in-app notifications/activity view.

## Post Detail Page

The Explore detail page is a fuller public reading surface for a shared post.

It should contain:

- The same privacy-safe author identity used on the feed
- A full-width hero image
- Like, comment, and external share actions
- Optional public hashtag chips that wrap and route to tagged-post collections
- Common and scientific names
- Public species insight cards backed by `species_dictionary`
- Privacy-safe telemetry such as general location, broad time context, weather, and shared date
- An inline comment thread with an inline composer

Interaction model:

- Feed comment taps intentionally stay in a bottom sheet for quick engagement without leaving the feed.
- Detail-page comment taps should scroll/focus the inline composer rather than opening another modal.
- The detail page should not mount private `InferenceEngine` state. It should use a public Explore detail payload.

## Public Metadata Rules

Explore feed and detail surfaces should never expose exact coordinates. The map may expose privacy-safe public coordinates only when the underlying scan is eligible for exact public display.

Location:

- Use the scan's existing semantic location data, but sanitize it down to `City, ST` or just `State`.
- Do not expose exact coordinates, neighborhoods, trails, landmarks, or small-site labels.
- The feed response should omit latitude and longitude entirely.
- The map response may include only privacy-safe public coordinates: exact for eligible `open` scans, obscured for protected or obscured scans, and no coordinates at all for `private` scans.

Time:

- Render broad buckets such as `Morning`, `Afternoon`, `Evening`, or `Night`.
- A month or season can be included if useful, but V1 should avoid minute-level or exact timestamp display.
- The current V1 feed card does not render time metadata, but the feed contract may still return it for detail-page telemetry use.

Weather:

- Show only if already available on the scan.
- Use lightweight display such as `Rainy`, `Clear`, or `68F`.
- The current V1 feed card does not render weather metadata, but the feed contract may still return it for detail-page telemetry use.

## Eligibility Rules

An eligible Explore share in V1 must be:

- An image-backed scan
- Present in the user's scan library
- Biological and safe for public distribution
- Not currently tombstoned or deleted
- Not already represented by another active Explore post

Imported historical photos and in-app captured photos should both be eligible.

## V1 Media Lifecycle

> Superseded: current Explore media is post-owned through
> `explore_post_media`, with `hero_image_url` retained as the thumbnail
> fallback and videos allowed for public posts/Community ID requests. See
> `docs/backend-and-data/04-database-schema.md#explore_post_media` for the
> current contract.

Original V1 Explore was explicitly ephemeral. The historical assumptions below
are no longer the current contract:

- Posts read the underlying scan's existing image URL array.
- Explore did not snapshot post-owned media.
- If a shared scan's backing media was later purged or expired, the Explore post
  disappeared from the feed.
- Explore payloads only included posts whose scan still had at least one active
  image URL.

That initial implementation kept the first Explore surface smaller, but the
current mixed-media design uses post-owned media snapshots.

Implications:

- Shared Explore posts are not guaranteed to live forever.
- Free-tier posts may naturally age out when the underlying scan media expires.
- Likes and comments can remain attached to the post record, but the post should be hidden whenever media is no longer available.
- "Any imported or captured photo in the scan library is shareable" in V1 means any eligible image-backed scan whose media is currently available.

Future upgrade path:

- If Explore later needs durable public permanence, we can add a dedicated Explore media path without replacing the `explore_posts` wrapper model.

## Data Model Recommendation

Use a thin Explore wrapper around scans.

### `explore_posts`

Suggested fields:

- `id UUID PRIMARY KEY`
- `user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE`
- `scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE`
- `shared_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- `unshared_at TIMESTAMPTZ`
- `species_common_name TEXT`
- `like_count INTEGER NOT NULL DEFAULT 0`
- `comment_count INTEGER NOT NULL DEFAULT 0`

Suggested constraints:

- Unique active share per scan in V1
- Query only rows where `unshared_at IS NULL`

### `explore_post_hashtags`

Shipped normalized tag edges:

- `post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE`
- `tag TEXT NOT NULL` containing lowercase text without leading `#`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- `PRIMARY KEY (post_id, tag)`
- `(tag, post_id)` lookup index for tagged-post browsing and future event or
  BioBlitz matching

Current shipped note:

- Explore posts store post-level `location_sharing` with `open`, `obscured`, or `private`.
- Spatial reads use post-owned `public_latitude` / `public_longitude` fields. The map RPC returns only rows whose saved `location_sharing` is `open`, and Nearby uses the same stored coordinates for non-owned radius matching.
- The global/scan geoprivacy setting seeds the share composer, but editing a shared post changes only that post's saved location setting.

- `public_latitude DOUBLE PRECISION NULL`
- `public_longitude DOUBLE PRECISION NULL`
- `public_coordinate_visibility TEXT NULL`
  - Allowed values: `exact`, `obscured`
- `public_location_label TEXT NULL`

Coordinate rules:

- `public_latitude` and `public_longitude` must never store the raw private scan coordinate unless the post is safe to expose as `open`.
- `obscured` posts may keep a stable scrubbed public label but stay off the map.
- `private` posts remain visible as Explore content but do not expose public location fields.

Eligibility synchronization rules:

- Explore visibility must stay synchronized with the underlying scan after share time.
- A trigger on `scans` updates should hide or unshare the related `explore_posts` row if the scan becomes tombstoned or loses all publicly available media.
- The same trigger path refreshes stored post public coordinates when scan coordinates, species safety context, or public labels change.

### `explore_post_likes`

Suggested fields:

- `post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE`
- `user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`

Suggested constraints:

- `UNIQUE(post_id, user_id)`

### `explore_post_comments`

Suggested fields:

- `id UUID PRIMARY KEY`
- `post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE`
- `user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE`
- `body TEXT NOT NULL`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- `deleted_at TIMESTAMPTZ`

Suggested rules:

- No editing in V1
- Soft delete is acceptable if we want moderation history
- Comment text length should be capped server-side

### `user_follows`

Shipped fields:

- `follower_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE`
- `followee_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`

Shipped constraints:

- Primary key: `(follower_user_id, followee_user_id)`
- Check: `follower_user_id <> followee_user_id`

Shipped privacy rules:

- RLS lets users insert/delete their own follow rows and read only their own following rows.
- Public author profiles expose counts and viewer-specific follow state only.
- No v1 endpoint exposes follower or following identities.

### Counter Strategy

The feed should not compute like/comment aggregates expensively on every page load.

Recommended V1 approach:

- Keep `like_count` and `comment_count` on `explore_posts`
- Update them transactionally in edge functions or via triggers

## Why Not Put Sharing Directly On `scans`

Adding `is_shared_to_explore` directly to `scans` is the fastest-looking option, but it creates long-term coupling:

- Manual share state gets mixed into the private scan record
- Likes/comments would attach to a scan rather than a publication
- Explore-specific storage needs become awkward
- Unshare and moderation logic become harder to reason about
- Future public-feed features will likely need post-specific fields anyway

The `explore_posts` wrapper is the cleaner foundation.

## Backend Surface

Recommended V1 endpoints:

- `share-scan-to-explore`
  - Creates or re-activates an Explore post for a scan, including the optional selected `species_common_name` snapshot
- `unshare-explore-post`
  - Removes the post from the feed
- `update-explore-field-notes`
  - Updates an owned post's public field notes, hashtags, location-sharing intent, and optional `species_common_name` snapshot while preserving the existing name when it is omitted
- `get-explore-feed`
  - Returns Explore cards for `Recent`, `Following`, `Trending`, or `Nearby` depending on the requested filter
- `get-explore-post`
  - Returns a single Explore card projection for notification routing and deep links
- `get-explore-post-detail`
  - Returns public species-detail data for a single Explore post, including `alternative_common_names` for the detail header, conditional per-scan `ai_reasoning` when the underlying identification has not been flagged or overridden, normalized-reference-image-backed `reference_image_url` compatibility output, plus public `similar_species` hydrated from the species dictionary lookalike join table with `species_id` for canonical dictionary routing
- `get-explore-comments`
  - Returns paginated comments for a post, including the comment author's optional public avatar projection
- `field-trips`
  - Returns Field Trip catalog, template-detail, explicit-start, Community publication feed, Recent compatibility, profile-summary/pin, scan-progress, publication, like, and comment actions, plus Seasonal Challenge catalog/detail/join/progress, challenge entry, badge, and optional challenge hashtag suggestion actions. Field Trip and challenge comments/likes are stored separately from Explore post interactions, and publishing a Field Trip or challenge entry does not write Explore posts, map points, APNs, widgets, public web share pages, prizes, leaderboards, or feed cards.
- `get-explore-map-points`
  - Returns privacy-safe map clusters or individual map points for the current visible area
- `get-explore-notifications`
  - Returns the viewer's Explore activity feed
- `get-explore-unread-notification-count`
  - Returns the unread badge count for the bell icon
- `mark-explore-notifications-read`
  - Marks the viewer's Explore notifications as read
- `set-explore-post-like`
  - Idempotently sets liked state for the viewer
- `set-user-follow`
  - Idempotently follows or unfollows a visible Explore author profile
- `create-explore-comment`
  - Creates a comment
- `delete-explore-comment`
  - Deletes a comment if permitted
- `report-explore-comment`
  - Reports a comment for trust-and-safety review

Existing endpoint reuse:

- Reuse `/block-user` for author and commenter blocking.

The in-app notifications feed is the Explore source of truth. Remote APNs
fan-out layers on top of that same notification row model for eligible
post-backed activity through push-device registration plus a server-side
webhook trigger. Follow notifications and Field Trip activity stay in-app only.

## Feed Query Rules

`get-explore-feed` should:

- Return only active Explore posts
- Exclude blocked users
- Exclude shadowbanned users
- Exclude unshared posts
- Exclude posts whose scan no longer has active image media
- Order by the selected feed mode:
  - `Recent`: `shared_at DESC`
  - `Following`: followed authors only, then `shared_at DESC`
  - `Trending`: trailing-30-day recent-like count DESC, then `shared_at DESC`
  - `Nearby`: radius-filter first, then `shared_at DESC`
- Return only the fields the Explore UI needs

Pagination:

- `get-explore-feed` should use cursor pagination, not offset pagination
- `Recent`, `Following`, and `Nearby` should use `(shared_at, post_id)` so feed paging remains stable while new posts are inserted above the viewer
- `Trending` should use `(ranking_value, shared_at, post_id)` so ranking ties do not skip or duplicate rows
- Recommended request fields:
  - `filter`
  - `before_shared_at`
  - `before_post_id`
  - `before_ranking_value` for `Trending`
  - `latitude` and `longitude` for `Nearby`
  - `limit`
- Current shipped note: both cursor models are now canonical server and client paths.

Recommended response fields:

- `post_id`
- `scan_id`
- `hero_image_url`
- `shared_at`
- `author_name`
- `author_username`
- `author_avatar_url`
- `species_common_name` (author-selected post snapshot; native clients may still display a viewer-local SwiftData-backed preferred name on top of this fallback)
- `species_scientific_name`
- `public_location_label`
- `time_of_day`
- `current_month`
- `weather_condition`
- `weather_temperature_f`
- `like_count`
- `comment_count`
- `ranking_value` for `Trending` compatibility
- `viewer_has_liked`
- `is_owned_by_viewer`

The Explore payload should not include:

- Exact coordinates
- Email
- Raw auth metadata
- Full telemetry columns

Implementation note:

- Media availability must be cheap to filter.
- If the scan-media visibility check becomes a hot path, prefer a trigger-maintained post-level boolean such as `has_active_media` on `explore_posts`, or at minimum an expression/partial index that prevents repeated full-table scans over media arrays.

`get-explore-feed` should remain card-oriented even as filters expand. `Following` should stay a followee filter over the same visibility-safe post projection, not a separate user lookup surface. `Nearby` should stay feed-like by using a radius filter plus recency sort, while the map remains a separate spatial endpoint rather than overloading feed pagination with nearest-neighbor map semantics.

## Explore Map Addendum

The Explore map should be a second discovery surface over the same `explore_posts` model, not a separate content system.

Product principle:

- Feed is for passive browsing.
- Map is for spatial browsing.
- Both must open the same public Explore detail page.

Current backend note:

- `explore_posts` remains the publication state model.
- The shipped map projection comes from post-owned `explore_posts.public_latitude` / `public_longitude`, joined through `public.get_explore_map_posts(...)`. The map RPC returns only posts whose saved `location_sharing` is `open`; Nearby uses the same stored public coordinate fields for non-owned radius matching.

### Why Merian Can Beat A Basic Pin Map

The main weakness of competitor-style maps is "pin soup." Once the user zooms out, the product becomes visually dense but informationally weak.

Merian should improve on that by:

- Showing clusters or density at broad zoom levels instead of rendering every post as an equal pin
- Showing individual waypoints only when the camera is close enough for selection to feel intentional
- Using a compact preview card after tap, then opening the full Explore post detail page only on explicit expansion
- Making privacy visible through marker treatment so `obscured` posts look meaningfully different from exact public posts
- Surfacing "what is interesting here?" summaries such as counts, dominant groups, or recent activity rather than only exposing raw coordinates

### Map V1 UX

The Explore sheet already has feed and map tabs. Map V1 should behave like this:

- User opens the `Map` tab.
- The camera starts on either the user's current region or a sensible fallback world/continent view.
- The server returns clusters at broad zoom levels and individual posts at closer zoom levels.
- At sufficiently close zoom, individual posts may transition from simple dots into image-backed thumbnail markers so the user starts seeing the actual scans before opening detail.
- Panning the map does not immediately destroy the current results. Instead, the UI marks the region as stale and shows a `Search This Area` action.
- Tapping a cluster zooms the camera inward.
- Tapping an individual point selects it and reveals a compact preview card anchored above the bottom tab bar.
- Tapping the preview card opens `ExplorePostDetailView` for the same `post_id`.
- When no results are in view, the shipped empty state uses a top banner only so the map remains fully interactive underneath.

Recommended V1 controls:

- `Nearby`
- `Search This Area`
- `Recenter`
- `Map` or `Hybrid` style toggle if we want a fast-follow visual upgrade

Current shipped feed filters:

- `Recent`
- `Following`
- `Trending`
- `Nearby`

The map tab currently stays viewport-driven rather than mirroring the feed's filter row.

Taxonomic chips such as `Plants`, `Fungi`, `Birds`, and `Insects` are a good phase-two extension, but the initial map does not need to solve every taxonomy slice on day one.

### Map Selection Model

Map taps should not push full detail immediately.

Recommended interaction sequence:

- First tap selects a point and opens a compact preview card
- Second tap on the selected point, or tap on the preview card, opens `ExplorePostDetailView`
- Deselecting the point collapses the preview card

This keeps the map browsable and prevents the "tap anything, lose your place" problem.

### Map Privacy Model

Explore map coordinates must be stricter than the scan library's private map usage.

Rules:

- `private` scans remain entirely absent from Explore, including the map
- `open` scans may render with exact public coordinates
- `obscured` scans may remain visible on non-map Explore surfaces, but the shipped map excludes them unless a future explicit per-post override is added
- If Merian applies an endangered-species safety offset, the Explore map must use that already-sanitized public coordinate rather than the original point
- The client should never receive raw coordinates for non-open posts
- The client should receive a display hint such as `coordinate_visibility: exact|obscured`

Marker treatment:

- `exact` can use a standard pinpoint or image-backed marker
- Open posts whose public coordinates are approximate for species-safety or uncertainty rules should use a softer glyph or halo so the user understands the location is approximate
- In the current shipped client, posts begin as simple indicator dots, then switch to circular scan thumbnails once the camera is close enough. Approximate open posts keep their approximate-location halo in either mode.

### Public Coordinate Strategy

The shipped V1 now normalizes privacy-safe coordinates at the Explore post layer.

Current approach:

- `public.explore_posts.public_latitude` / `public_longitude` are the authoritative Explore map coordinates today.
- `trg_project_explore_post_location` derives them from exact scan telemetry only when the post's saved `location_sharing` is `open`.
- `private` and `obscured` posts produce `NULL` public map coordinates and remain absent from the map.
- Protected-species and uncertainty rules can round an `open` post into a stable coarse public cell with `public_coordinate_visibility = 'obscured'`.
- `public.get_explore_map_posts(...)` reads the stored post public coordinate fields and does not derive map output from exact GPS at read time.

Why this shipped post-layer approach works:

- Repeated re-jittering creates privacy leakage over multiple requests
- Stable points make the map feel consistent when users pan away and back
- The projection path keeps newly shared or edited exact-coordinate posts visible on spatial surfaces only when that post's saved location setting allows it

Implementation guardrail:

- Do not reintroduce map or Nearby read-time projection from exact scan GPS.
  Public spatial reads should consume the stored post-owned public coordinate
  fields.

### Backend Query Model

The map should not be powered by `get-explore-feed`.

Recommended new endpoint:

- `get-explore-map-points`

Request shape:

```json
{
  "north_latitude": 41.947,
  "south_latitude": 41.748,
  "east_longitude": -87.568,
  "west_longitude": -87.742,
  "zoom_level": 12.3,
  "limit": 300
}
```

Response shape:

```json
{
  "mode": "clusters",
  "visible_count": 243,
  "clusters": [
    {
      "id": "3015:2057",
      "latitude": 41.873,
      "longitude": -87.632,
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
  "clusters": [],
  "posts": [
    {
      "post_id": "UUID",
      "scan_id": "UUID",
      "latitude": 41.873,
      "longitude": -87.632,
      "coordinate_visibility": "obscured",
      "hero_image_url": "https://...",
      "author_user_id": "UUID",
      "author_name": "Nina P.",
      "author_username": "nina_p",
      "author_avatar_url": "https://...",
      "species_common_name": "Monarch Butterfly",
      "species_scientific_name": "Danaus plexippus",
      "public_location_label": "Chicago, IL",
      "shared_at": "2026-04-28T21:18:00.000Z",
      "time_of_day": "afternoon",
      "current_month": 4,
      "weather_condition": "clear",
      "weather_temperature_f": 72.4,
      "like_count": 12,
      "comment_count": 3,
      "viewer_has_liked": false,
      "is_owned_by_viewer": false
    }
  ]
}
```

Implementation notes:

- Broad zooms should return cluster rows rather than individual posts
- Close zooms should return individual posts
- The endpoint should keep the same blocking, shadowban, media-availability, missing-species, and unshared-post exclusions as `get-explore-feed`
- The endpoint should require post-level `location_sharing = 'open'` and stored post-owned public coordinates for map rows
- The endpoint should enforce a hard row cap to prevent pathological city-scale payloads

Clustering strategy:

- V1 does not require PostGIS
- Plain Postgres bounding-box filtering plus zoom-dependent grid bucketing is sufficient
- Bucket coordinates using a zoom-dependent snapped grid such as rounded lat/lon cells or `width_bucket`
- A cluster ID can be derived from the zoom bucket and snapped cell coordinates
- The shipped SQL path already uses a partial public-coordinate index at the scan layer (`idx_scans_public_coordinates_active`); if we ever move to stored post-owned coordinates, add the equivalent index on that projection too

### Map Preview Payload

The map point payload should be rich enough to render a compact card immediately, without an extra round trip.

The preview card needs:

- Hero image
- Common name
- Scientific name
- Public location label
- Author label
- Like/comment counts
- Coordinate visibility

The full detail page can still use the existing `get-explore-post` and `get-explore-post-detail` path after the user commits to the post. Alternate common names and similar-species content stay on the full detail payload rather than the map preview payload, keeping map cards light while still allowing detail pages to show species synonyms and open the public species dictionary.

### iOS Client Architecture For Map

Recommended additions:

- `apps/ios/Merian/Features/Explore/Map/Views/ExploreMapView.swift`
- `apps/ios/Merian/Features/Explore/Map/ViewModels/ExploreMapViewModel.swift`
- `apps/ios/Merian/Core/Network/ExploreAPIModels.swift`
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExploreFeedViewModel+Interactions.swift`

Current shipped state on `ExploreMapViewModel`:

- `cameraPosition`
- `visibleRegion`
- `lastCommittedRegion`
- `needsSearchInArea`
- `isLoading`
- `errorMessage`
- `mode`
- `clusters`
- `posts`
- `selectedPostId`
- `visibleCount`
- `isOffline`
- a computed `showsThumbnailWaypoints` gate derived from the active region zoom plus visible post count
- an in-memory recent-region cache with capped eviction

State machine:

1. On first appearance, request a starting camera position and perform an initial fetch
2. While the user pans or zooms, update `visibleRegion`
3. Once the camera movement settles, compare `visibleRegion` against `lastCommittedRegion`
4. If the delta is meaningful, set `needsSearchInArea = true`
5. If the same area was fetched recently, reuse the cached response immediately and only hit the network again once that cache entry is stale
6. When the user taps `Search This Area`, call `get-explore-map-points`
7. If the response is `clusters`, render clusters and clear any selected post
8. If the response is `posts`, render point annotations
9. If the camera is sufficiently close and the post count is still low enough, upgrade those point annotations into thumbnail-backed markers instead of plain dots
10. On point tap, set `selectedPost`
11. On preview-card tap, route to `ExplorePostDetailView(postId:)`

Technical notes:

- Use SwiftUI `Map` and `MapCameraPosition`
- Debounce camera-driven fetch eligibility rather than firing a network request on every frame
- Reuse the existing Explore detail route already owned by `ExploreView`
- Keep selection state local to the map view model so the feed view model does not absorb spatial UI concerns
- Reuse `ExploreHeroImageView` for thumbnail markers with a smaller decode size instead of introducing a separate image-loading path for the map
- In the current shipped architecture, feed and map mutations converge through `ExplorePostStore`, which acts as the shared in-memory source for likes, comment counts, unshares, reports, and blocks while screen-specific view models keep their own UI state

### Search And Caching Behavior

Current shipped V1 behavior:

- Keep the last successful result set on screen while the user pans
- Only replace results after a successful "search this area" fetch
- Cap rendered individual post annotations to a strict upper bound such as 500
- Only promote individual post annotations into thumbnail-backed markers when the zoom level is high enough and the visible post set is small enough, preventing dense areas from turning back into thumbnail soup
- If map fetches fail because the device is offline, show an explicit offline banner rather than silently leaving the map in a stale state
- Cache recent region payloads in memory and evict old or off-screen regions aggressively so revisiting nearby areas feels faster without letting long-distance panning grow memory unbounded

Fast-follow opportunities:

- Eagerly evict point annotations that fall outside an expanded region around the last committed viewport to reduce long-distance panning memory growth
- Prefetch `get-explore-post` for the selected marker if we want instant detail transitions later

### Rollout Strategy

Recommended delivery order:

- Phase 1: feed ships first
- Phase 2: map tab placeholder ships
- Phase 3: map endpoint plus static preview card
- Phase 4: clustering and privacy-aware marker system
- Phase 5: map polish such as summaries, taxon chips, and richer nearby UX

This sequencing keeps the map from blocking the already-valuable feed surface.

## Interaction Rules

Likes:

- Likes should be idempotent.
- Users can like their own posts unless product later decides otherwise.
- The feed should return `viewer_has_liked` to support optimistic UI.

Comments:

- Plain text only
- No editing in V1
- Server-side length cap
- Comment author can delete their own comment
- Post owner should also be allowed to remove comments on their own post
- Feed comment entry uses a bottom sheet; detail-page commenting is inline

Notifications:

- The in-app notifications feed is the source of truth for Explore activity.
- Like notifications should aggregate to one row per owner/post, maintain the latest actor names, and reset `is_read` whenever a new like arrives.
- Comment notifications should create one row per visible comment.
- Follow notifications should create one postless informational row per follower/followee pair.
- Self-likes, self-comments, and self-follows should never create notifications.
- Opening the notifications sheet should mark the fetched rows as read only after the initial fetch succeeds.
- Notifications pagination should be cursor-based on `(updated_at, notification_id)`, not offset-based.
- Comments pagination should be cursor-based on `(created_at, comment_id)`, not offset-based.
- Users can independently opt into remote Explore activity pushes without enabling discovery-result alerts.
- Follow notifications are excluded from remote push delivery.

Blocking:

- If user A blocks user B, B's Explore posts and comments should disappear for A.
- Interaction endpoints should reject likes, comments, reactions, and follows when either direction of blocking should disallow the relationship.

Reporting:

- V1 should support reporting both posts and comments for safety review.
- After a successful report, the client should locally hide the reported post or comment for that reporting user immediately rather than waiting for a full feed refresh.

## iOS Architecture

Recommended feature module:

- `apps/ios/Merian/Features/Explore/Shell/ExploreView.swift`
- `apps/ios/Merian/Features/Explore/Map/Views/ExploreMapView.swift`
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExploreFeedViewModel.swift`
- `apps/ios/Merian/Features/Explore/Map/ViewModels/ExploreMapViewModel.swift`
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExploreFeedViewModel+Interactions.swift`
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExploreFeedViewModel+Notifications.swift`
- `apps/ios/Merian/Features/Explore/Notifications/ViewModels/ExploreNotificationsViewModel.swift`
- `apps/ios/Merian/Features/Explore/Notifications/Models/ExploreNotification.swift`
- `apps/ios/Merian/Core/Network/ExploreAPIModels.swift`
- `apps/ios/Merian/Features/Explore/Feed/Components/ExplorePostCard.swift`
- `apps/ios/Merian/Features/Explore/Feed/Components/ExploreCommentsSheet.swift`
- `apps/ios/Merian/Features/Explore/Notifications/Components/NotificationRowView.swift`
- `apps/ios/Merian/Features/Explore/Notifications/Views/ExploreNotificationsSheet.swift`

Routing changes:

- Add `.explore` to `CaptureWorkspaceViewModel.ActiveSheet`
- Route the Explore tab through `CameraSheetRouter`
- Open Explore directly from `MainTabBar`

Share entry points:

- Scan-library context menu
- Insight sheet action menu

Client behavior:

- Explore is online-only in V1
- Likes/comments/shares do not use the offline queue
- `Recent`, `Following`, and `Nearby` pagination are cursor-based on `(shared_at, post_id)`
- `Trending` pagination is cursor-based on `(ranking_value, shared_at, post_id)`
- Comments pagination is cursor-based on `(created_at, comment_id)`
- Notifications pagination is cursor-based on `(updated_at, notification_id)`
- Like and comment counts should update optimistically
- Feed cards can single-tap into detail and double-tap the image to like
- The map should use a dedicated spatial endpoint rather than piggybacking on feed pagination
- The map should keep stale results visible while the user pans and only refetch on an explicit `Search This Area` action
- Marker selection should open a preview card first and only then open full detail
- The map should emit lightweight telemetry for tab open, explicit area search, cluster tap, waypoint preview open, and detail open
- Feed comment taps present `ExploreCommentsSheet`; detail-page comments render inline with the thread
- Explore feed share uses the system share sheet with species text plus the current hero image URL
- The detail page uses a separate public species payload so it can render safe `Taxonomy` and `Habitat & distribution` cards without loading private scan state
- The sheet toolbar bell shows an unread badge, opens the in-app notifications sheet, and uses `get-explore-post` so notification taps can route into posts that are not already present in the loaded feed page
- Follow notification rows are informational and do not navigate because their `post_id` is `NULL`

## Implementation Phases

### Phase 1: Schema and API Foundation

- Add Explore tables and public author fields
- Add feed, share, unshare, like, comment, and report endpoints
- Add unit tests for blocking, share eligibility, and idempotency

### Phase 2: Explore Client Foundation

- Add Explore routing and feature module
- Add feed loading, pagination, and empty/error states
- Render V1 cards with privacy-safe metadata

### Phase 3: Share Flow

- Add share/unshare actions to scan-library and insight entry points
- Gate sharing to scans whose image media is currently available
- Prevent duplicate active posts for the same scan

### Phase 4: Interaction and Moderation Polish

- Add comment sheet
- Add optimistic likes, comments, and follows
- Add block/report action flows
- Add telemetry for share, like, comment, follow, block, and report events

### Phase 5: Public Post Detail

- Add pushed Explore detail navigation from the feed
- Add privacy-safe telemetry cards on the detail page
- Add inline detail-page comments and composer
- Add a public species-detail payload for safe card reuse
- Reuse public-safe Insight visuals such as `TaxonomyCard`
- Add the in-app notifications sheet, unread badge, and single-post fetch path used by notification taps

### Phase 6: Explore Map

- Add `get-explore-map-points`
- Normalize privacy-safe spatial output through post-owned `explore_posts.public_latitude` / `public_longitude` fields and `public.get_explore_map_posts(...)`
- Add cluster and point rendering in `ExploreMapView`
- Add a preview-card selection model that routes into `ExplorePostDetailView`
- Reuse the Explore root navigation, with Map grouped under the Observations Feed/Map header toggle rather than exposed as its own bottom item.

### Phase 7: Fast Follow Ups

- Public species page route from Explore cards
- Standalone public user pages, if Explore later grows beyond the current sheet model
- Audio Explore posts
- Ranking and recommendation logic

## Future Species Page Integration

When the public species-page project exists:

- The Explore detail page can route from its species section into `species_dictionary`'s future public page
- Feed cards can either continue opening detail first or optionally deep-link through the same route later
- The Explore data model does not need to change
- The feed can keep reading species metadata from the underlying scan and species join

## Acceptance Criteria For V1

- A user can manually share an eligible image scan to Explore.
- A shared post appears in the public feed, with `Recent` as the default reverse-chronological mode plus shipped `Following`, `Trending`, and `Nearby` filters.
- The feed shows privacy-safe author identity and general location.
- Authenticated authors can show a public avatar when a provider avatar URL is available.
- Ghost users can participate with stable `@username` handles.
- Authenticated users show a safe public author label.
- Feed and detail payloads never include coordinates; map payloads include only privacy-safe public coordinates.
- Users can like and comment on posts.
- Users can externally share posts from the feed.
- Tapping a feed post opens a public post detail page.
- Tapping the feed comment icon opens a bottom-sheet comment view.
- The detail page shows inline comments plus privacy-safe telemetry and public species cards.
- The Explore surface includes a map tab backed by the same `explore_posts` model.
- Broad zoom levels render clusters instead of pin soup.
- Close zoom levels can upgrade individual points into thumbnail-backed markers without changing the selection flow.
- Tapping a map point opens a compact preview card before opening full detail.
- Tapping a map preview card opens the same public Explore detail page used by feed posts.
- `obscured` posts can render scrubbed public location text on feed/detail surfaces, but stay off spatial map and non-owned Nearby results.
- `open` posts with protected-species or uncertainty safety rules render with rounded post-owned public coordinates and `coordinate_visibility = 'obscured'`.
- The bell icon shows an unread count and opens an in-app notifications sheet for likes, comments, reactions, and follows.
- The bell unread count is refreshed on foreground, on a lightweight fallback poll, and by a Supabase realtime subscription to the viewer's notification rows.
- Users can opt into remote Explore activity pushes separately from discovery-result alerts.
- Users can block and report from Explore surfaces.
- Unsharing removes the post from the public feed without deleting the scan.
- Posts disappear from Explore once their backing scan media is no longer available.
