# Reported content visibility

A successful **Report post** hides the specific post throughout the reporting
account's signed-in experience. This is a durable account preference derived
from existing `explore_post_reports` rows, including `PENDING_REVIEW`,
`DISMISSED` and `ACTIONED` reports. Moderation status does not restore
visibility. No unhide interface or backfill is required. Other viewers and
anonymous public pages retain their existing visibility rules.

## Backend boundary

`explore_projected_post_cards` excludes the viewer's reports before feed,
author, species, search, map clustering, pagination and counts. Independent
Community Identification list/detail/activity, comment/reply and notification
readers apply the same rule. Post-backed notification counts follow their
filtered readers. The service role retains only the SELECT grants on discussion
comments/mentions and lookalike relations needed by the existing invoker
readers; report records remain unavailable to client roles. Shared interaction
guards return the existing unavailable response for reported posts. Direct links
cannot hydrate a hidden post.

The service-only `filter_reported_explore_media` routine and viewer-aware SQL
reference-image helpers exclude exact known URLs from reported scans, published
post media (including thumbnails), and promotion provenance. Scan/published
media matching continues to work if promotion provenance is reassigned. Gallery,
catalog, overview, similar-species, authenticated search and Explore fallback
images choose the next eligible reference, or no image. Species entries remain.
Existing global reference-image suppression still applies. Explore detail’s
nested lookalike projection uses the same viewer image selection. The shared
native lookalike gallery uses the viewer dictionary rather than persisted
lookalike URLs or direct provider fallback.

`species-dictionary-for-viewer` derives the viewer from the authenticated user,
reuses dictionary request/response shapes and schema version 1, and responds
with `Cache-Control: private, no-store` and `Vary: Authorization`. The existing
anonymous `species-dictionary` route remains available to public web consumers.

## Native ownership and cache lifecycle

`ExploreContentVisibilityStore`, under Explore Shared and owned by
`AppDIContainer`, tracks the active account, reported IDs, content generation
and account generation. Both native report entry points publish only confirmed
success for the same account session; failures do not hide content. Repeating a
report does not invalidate again. Account switches clear local IDs and advance
the account generation, including switches away and back to the same account.

Post stores reject hidden posts from late hydration and pagination. Explore
presentation owners rebuild on visibility changes; hidden post discussions and
media presentations close. Map invalidation cancels pending work, drops cached
regions/clusters/facets and reloads current results/counts. Naturebook clears
loaded reference projections and refreshes through the viewer route.

Dictionary response memo keys include account and visibility generation, and
requests recheck both before accepting a response. Report/account invalidation
clears dictionary entries. Widget writes are serialized on their owner actor,
cancelled and generation-fenced; invalidation removes hidden snapshots and their
unused images, while account changes clear the previous snapshot entirely.

The server remains authoritative across relaunches and devices. Another device
observes the preference on its next authenticated read; there is no realtime
synchronization. Reporting users or comments retains its separate behavior.

## Verification and rollout

`reportedPostVisibilityDb.test.ts`, `reported_post_visibility.sql`, dictionary
viewer handler/media tests and native visibility/cache tests exercise the
boundary. Run the full migration replay, database catalogs, recursive Deno
checks and native build/test gates for the candidate. Manual acceptance should
cover already-loaded feed/map/search/author/Community content, detail and
comment presentation dismissal, audio/video stop, cached regions, delayed
pagination, widget writes, account switches, relaunch and the next read on
another device.

Prepare/deploy backend support before releasing the native client that requires
the new route. This implementation does not authorize deployment or publication.
