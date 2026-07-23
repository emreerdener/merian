# Field trips

Action-based Edge Function for Field trips. The function is authenticated via
`withEdgeHandler`; request bodies cannot choose `self_id`.

The backing SQL lives in this ordered migration chain:

1. `20260708021110_field_trips_v1.sql`
2. `20260708033451_field_trips_v2.sql`
3. `20260708042713_field_trips_v3_community.sql`
4. `20260708051414_field_trips_v4_challenges.sql`
5. `20260717150222_contextual_outing_objective_guides.sql`
6. `20260717195751_active_outing_capture_context.sql`
7. `20260717213641_preserve_standard_outings_in_capture_context.sql`
8. `20260717224544_retire_forest_edges_outing.sql`
9. `20260718043218_expose_field_trip_completion_scan_ids.sql`
10. `20260718051748_expose_field_trip_publication_status.sql`
11. `20260718150932_add_credited_field_trip_progress.sql`
12. `20260718162409_scope_credited_progress_to_current_attempt.sql`
13. `20260719045306_first_field_trip_achievement.sql`
14. `20260719160750_field_trip_lifecycle_controls.sql`
15. `20260720014446_update_backyard_safari_copy.sql`
16. `20260722025411_persistent_field_trip_scan_contributions.sql`
17. `20260722064704_harden_atomic_field_trip_progress.sql`
18. `20260722195453_exclude_ants_from_bee_wasp_goal.sql`
19. `20260722211636_tighten_field_trip_goal_matching.sql`

Deploy the migrations, updated scan-ingestion functions, and then this function
before the iOS client begins sending preferred-goal hints or requesting
contribution rows.

## Client Rollout State (2026-07-22)

- The backend supports standard Outings and Seasonal Challenge Events and is
  deployed before the full Events UI release.
- Standard Field trips and Outings are public in iOS.
- Events remain staged by the `.fieldTripEvents` default in the iOS
  `FeatureFlags` registry; the tester account and simulator builds bypass that
  client default. This function must not treat the flag as authentication or
  authorization.
- The shared `apply_scan_progress` transaction can return standard and challenge
  updates. Events-disabled clients discard challenge-only results before local
  caching, refresh publication, routing, or UI presentation.
- Flipping Events public is an iOS release operation and does not require a
  function redeploy unless this function or its database contract also changes.
  The canonical checklist lives in
  `docs/features-and-hardware/25-field-trips.md`.

## Privacy Contract

- Active profile summaries are checklist-status only.
- Active summaries must not return scan IDs, media URLs, field notes, exact
  coordinates, public location labels, or private evidence.
- Published Field trips are snapshots in Field trip tables, not Explore posts.
- Publishing a Field trip must not create Explore feed posts, Explore map
  points, normal Explore post notifications, APNs, widgets, or public web share
  pages.
- Published Field trips appear on public profiles, template-detail Community
  previews, and as typed cards in unfiltered Explore Recent and Following. They
  remain absent from Trending, Nearby, map, APNs, widgets, and public web, and
  they never create duplicate `explore_posts` rows.
- Field trip comments, replies, and followed-author publications can create
  Field trip-only in-app activity rows. They appear in Explore activity and may
  increment the bell, but never fan out to push delivery.
- Field trip comments and likes use Field trip publication tables, not Explore
  post interaction tables.
- Field trip likes do not create notifications in V3/V4.
- Seasonal challenges are Field trips-native. Challenge participation, badges,
  entries, likes, and comments are stored separately from normal Field trip
  progress/publications.
- Publishing a challenge entry must not create Explore posts, Explore map
  points, APNs, widgets, public web share pages, prizes, leaderboards, or
  automatic Explore hashtags.
- Challenge joins, likes, badges, and progress updates do not notify other users
  in V4.
- Challenge suggested hashtags are optional Explore composer suggestions only;
  this function never auto-posts or auto-tags scans.
- Visibility checks must reject shadowbanned authors and mutual blocks.
- `completed_scan_id` is private viewer evidence metadata exposed only by
  catalog/detail. It is never copied into capture context, public profile
  summaries, publication/challenge snapshots, Explore surfaces, or media URLs.
- First Field trip achievement evidence is available only through a
  `service_role` RPC. Public Explore author awards expose its binary count and
  earliest completion date, never a template slug, challenge ID, or scan ID.
- Standard outing activity periods are private, protected by RLS, and available
  only to `service_role`. Stopped progress is returned only to the owning caller
  through the authenticated Edge Function.
- Scan goal preferences and scan contribution lookup are private,
  `service_role`-only contracts. Contribution rows contain typed routing and
  checklist progress, never media, notes, or location evidence.
- The progress receipt is private and `service_role`-only. Every public-schema
  Field trip/Event `SECURITY DEFINER` function is revoked from `PUBLIC`, `anon`,
  and `authenticated`; no direct client RPC is part of this API.

## Actions

`actions.ts` is the server action allowlist and the type source consumed by the
handler. Add or retire an action there and update
`_tests/fieldTripActions.test.ts` in the same change. That test contains a
manually maintained snapshot of the actions emitted by the iOS client; reviewers
must compare Swift call sites when the contract changes because the test does
not parse Swift source. A missing or non-string action returns `HTTP 400`. An
unknown string also returns `HTTP 400` and emits the structured warning
`field_trip_action_rejected` with only the first 64 characters of the rejected
action. Use that event to identify a stale client or undeployed server action;
do not log the full request body or user ID.

```json
{ "action": "achievement_progress" }
```

Returns the caller's earliest completed standard outing or Seasonal Challenge,
or `null` when neither is complete. The Edge handler supplies the verified user
ID to a `service_role`-only RPC. When timestamps tie exactly, the Seasonal
Challenge destination wins deterministically.

```json
{
  "data": {
    "kind": "standard_outing",
    "completed_at": "2026-07-18T14:00:00Z",
    "template_slug": "backyard_safari",
    "challenge_id": null
  }
}
```

For `kind: "seasonal_challenge"`, `template_slug` is null and `challenge_id`
contains the destination ID.

```json
{
  "action": "apply_scan_progress",
  "scan_id": "uuid",
  "preferred_goal": {
    "user_field_trip_id": "uuid",
    "item_id": "uuid"
  }
}
```

The preference is optional and is honored only when it is owned, active at the
scan timestamp, current, visible, and matching. A scan can advance multiple
active experiences, but receives at most one credit per standard outing and one
per joined Event. The Edge action invokes one atomic RPC for standard progress,
Event progress, preference persistence, and first-outing achievement state. New
scan ingestion may already have applied it transactionally; the unchanged scan
revision then returns its stored receipt, preserving the original unlock result
without a partial second mutation.

```json
{ "action": "scan_contributions", "scan_id": "uuid" }
```

Returns every standard outing and Event credit owned by the scan, including the
credited item and level counts plus a typed destination. Missing, unauthorized,
non-biological, or uncredited scans return an empty array.

```json
{ "action": "capture_context" }
```

Returns the caller's accessible, incomplete standard field trips and unfinished
targets from each current level, ordered by recent engagement and curated
checklist order. This capture-only contract contains aggregate progress and
prompts, never scan IDs, media, field notes, location, or completion evidence.
The backing RPC is executable only by `service_role`; `withEdgeHandler` supplies
the verified user ID. It reads only standard Field trip item completions and
never challenge-specific completions or Seasonal labels. Because joining a
challenge starts or continues the same underlying standard field trip, that
field trip remains eligible for the indicator. The cross-client ownership,
cache, navigation, and future-source decision lives in
`docs/rfcs/active-capture-goal-context.md`.

Response:

```json
{
  "data": [
    {
      "user_field_trip_id": "uuid",
      "template_id": "uuid",
      "template_slug": "backyard_safari",
      "outing_title": "Backyard Safari",
      "last_engaged_at": "2026-07-17T18:00:00.000Z",
      "level_number": 1,
      "level_title": "Level 1",
      "completed_count": 1,
      "target_count": 4,
      "targets": [
        {
          "item_id": "uuid",
          "prompt": "Butterfly",
          "sort_order": 10,
          "has_guide": true
        }
      ]
    }
  ]
}
```

`last_engaged_at` is the later of the field trip start and its most recent item
completion. Field trips order by `(last_engaged_at DESC, user_field_trip_id)`
and targets order by `(sort_order, item_id)`. Only unfinished targets from the
current unlocked level are returned. An eligible account with no remaining
targets receives `{ "data": [] }`.

```json
{ "action": "catalog", "user_region": "optional", "limit": 40 }
```

Returns active templates, access state, levels, checklist items, and the
requesting user's active or stopped progress. `active_progress` remains the
legacy active/completed contract; an unfinished stopped outing instead adds
`stopped_progress` with its saved checklist state. V2 catalog rows may include
`cover_image_url`, `estimated_duration_minutes`, `guide_where_to_look`,
`guide_why_it_matters`, `guide_safety_ethics`, and item-level `guide_tip`
values. Completed checklist items include the private `completed_scan_id` so
first-party clients can show the owner's scan thumbnail and reopen its insight.
This field is not included in public Field trip publication snapshots. Catalog
and template-detail RPC execution is restricted to `service_role`; the Edge
Function supplies the verified caller ID.

```json
{ "action": "template_detail", "template_id": "uuid" }
```

Returns one template detail payload with guide fields, levels, checklist tips,
access state, viewer progress, and the same private `completed_scan_id` on
completed checklist items. Its `active_progress` also includes the owner's
optional active `publication_id` and `published_at`; clients render Published
only when that ID is non-null. `slug` may be supplied instead of `template_id`.

```json
{ "action": "start", "template_id": "uuid" }
```

Explicitly starts or unhides the caller's progress for an accessible template
and returns the refreshed template detail. Starting a stopped outing resumes it
by opening a new activity period. Matching scans never create or restart a
standard outing.

```json
{ "action": "stop", "user_field_trip_id": "uuid" }
{ "action": "reset", "user_field_trip_id": "uuid" }
```

`stop` closes the outing's open activity period, hides it from Capture and
active profile summaries, preserves its checklist state, and returns refreshed
template detail containing `stopped_progress`. `reset` is restricted to an
unfinished, unpublished standard outing. It clears standard completion rows and
activity periods while preserving the shared `user_field_trips` row and all
Seasonal Challenge participation, badges, entries, and engagement data. Both
actions are idempotent and ownership-scoped to the verified caller.

```json
{
  "action": "community_publications",
  "mode": "smart",
  "template_id": "optional-template-uuid",
  "user_region": "us-ca",
  "habitat_tags": ["neighborhood"],
  "season_tags": ["spring"],
  "limit": 20,
  "before_rank_bucket": 2,
  "before_published_at": "2026-07-08T13:00:00.000Z",
  "before_publication_id": "uuid"
}
```

Returns published completed Field trips for the Field trips `Community` segment.
`mode` accepts `smart`, `following`, or `recent`. `smart` ranks by
followed-author plus local/template relevance, followed author, local/habitat/
season match, global fallback, then other visible fallback. Within each bucket,
pagination is stable on
`(rank_bucket ASC, published_at DESC, publication_id DESC)`. `template_id`
filters results for template-detail Community previews.

```json
{
  "action": "recent_publications",
  "user_region": "us-ca",
  "limit": 20,
  "before_published_at": "2026-07-08T13:00:00.000Z",
  "before_publication_id": "uuid"
}
```

`recent_publications` remains as a compatibility alias for
`community_publications` with `mode: "recent"`.

```json
{
  "action": "apply_scan_progress",
  "scan_id": "uuid",
  "preferred_goal": {
    "user_field_trip_id": "uuid",
    "item_id": "uuid"
  }
}
```

Applies the Field trip progress rules for one saved scan. The backing RPC only
counts scans owned by the caller whose capture timestamp falls inside one of
that outing's activity periods, and only for the current unlocked level. This
allows a pre-stop scan to count after late approval while permanently excluding
scans captured during a stopped gap. V4 also updates joined live challenge
progress for the same scan when the scan was created after `joined_at` and
before `ends_at`; upload after the period/Event closes remains eligible because
the scan timestamp, not request time, owns the boundary. Eligibility is independent of photo/video modality once the
biological scan is saved. One scan can complete at most one current-level item
per eligible standard outing and one per joined live challenge; it may still
advance several experiences, and every created completion row retains the same
scan ID. The optional preference is honored only for its owned, active,
current, visible, matching standard goal. Otherwise the database ranks exact
species, scientific name, taxonomy from genus through kingdom, taxonomy with an
explicit excluded family, taxonomy combined with a required
ecology/habitat/semantic signal, semantic tag, ecology, habitat, curated
checklist order, and item ID. Compound matching requires every populated
taxonomy and signal constraint. Park Pollinators' **Bee or wasp** goal uses
Hymenoptera plus either the `bee` or `wasp` semantic category, so ants,
sawflies, and other broader-order members do not satisfy it. Compound semantic
alternatives are separated with `|`. Spider goals require `Araneae`, and
animal/plant signal goals require their named kingdom.

Returns:

```json
{
  "data": [
    {
      "user_field_trip_id": "uuid",
      "template_id": "uuid",
      "slug": "backyard_safari",
      "title": "Backyard Safari",
      "current_level_number": 1,
      "current_level_title": "Level 1",
      "completed_count": 3,
      "target_count": 4,
      "is_complete": false,
      "credited_level_number": 1,
      "credited_level_title": "Level 1",
      "credited_completed_count": 3,
      "credited_target_count": 4,
      "removed_item_ids": [],
      "newly_completed_items": [
        {
          "item_id": "uuid",
          "prompt": "Butterfly or moth",
          "common_name": "Vine Sphinx",
          "scientific_name": "Eumorpha vitis",
          "completed_at": "2026-07-18T14:00:00Z"
        }
      ]
    }
  ],
  "challenge_updates": [],
  "first_field_trip_achievement": {
    "kind": "standard_outing",
    "completed_at": "2026-07-18T14:00:00Z",
    "template_slug": "backyard_safari",
    "challenge_id": null
  },
  "first_field_trip_achievement_newly_unlocked": true
}
```

Both standard `data` entries and `challenge_updates` include the optional
`credited_*` fields. They describe the level changed by this scan. When a scan
finishes a level and immediately unlocks the next one, `current_*` and the
existing counts describe the new active level while `credited_*` retains the
completed level and its full progress for scan-completion feedback. Older
clients can continue using the existing fields. The response is scoped to rows
inserted by the current application attempt so re-identifying an older scan
cannot return its historical level again alongside a newly credited item.

`preferred_goal` is an optional additive request field; legacy clients continue
to omit it and receive deterministic fallback ranking. Clients should treat a
progress update as newly credited only when `newly_completed_items` is
nonempty. An unchanged reapplication returns the scan-revision receipt so a
client that terminated after ingestion can recover the original notification;
iOS owns acknowledgement and scan-ID milestone deduplication. `removed_item_ids`
identifies prior unfinished credit invalidated by an identification correction.
Completed outings and Events are immutable.

The two `first_field_trip_achievement*` response fields are additive and may be
absent when the caller has no completed outing or challenge. The payload always
describes the earliest qualifying completion. `newly_unlocked` is true only when
this request's progress mutation created the first completion; idempotent,
non-final, and later completions return false.

```json
{ "action": "scan_contributions", "scan_id": "uuid" }
```

Returns every credit currently owned by one saved biological scan. Each row
contains `source_kind` (`standard_outing` or `event`), source/template/challenge
IDs, title/slug, credited item and level, credited-level counts, completion
state, artwork inputs, and typed-routing inputs. It returns no media, notes,
coordinates, place labels, or public evidence. Missing, unauthorized,
non-biological, queued, and uncredited scans produce an empty array.

```json
{ "action": "challenges_catalog", "user_region": "optional", "limit": 20 }
```

Returns live/upcoming/ended curated seasonal challenges with schedule, aggregate
counts, access state, suggested hashtags, and the viewer's participation
summary.

```json
{ "action": "challenge_detail", "challenge_id": "uuid", "entries_limit": 12 }
{ "action": "join_challenge", "challenge_id": "uuid" }
```

`challenge_detail` returns one challenge with linked template guide context,
viewer progress, aggregate counts, badge state, and initial published entries.
`join_challenge` is explicit and idempotent for a live accessible challenge; it
starts or continues the linked Field trip and creates/returns separate challenge
participation.

```json
{ "action": "scan_challenge_hashtags", "scan_id": "uuid" }
```

Returns normalized suggested hashtags for challenge items completed by that
scan, for optional Explore composer suggestions only.

```json
{
  "action": "challenge_publications",
  "challenge_id": "uuid",
  "limit": 20,
  "before_published_at": "2026-07-08T13:00:00.000Z",
  "before_entry_id": "uuid"
}
```

Paginates visible published challenge entries by
`(published_at DESC, entry_id DESC)`.

```json
{ "action": "publish_challenge_entry", "participation_id": "uuid", "title": "optional", "description": "optional" }
{ "action": "challenge_entry_detail", "entry_id": "uuid" }
{ "action": "set_challenge_entry_like", "entry_id": "uuid", "liked": true }
{ "action": "challenge_entry_comments", "entry_id": "uuid", "limit": 50 }
{ "action": "create_challenge_entry_comment", "entry_id": "uuid", "body": "Nice finds!" }
```

Challenge entries are separate snapshots from normal Field trip publications.
Their likes and comments use challenge-specific tables and never write Explore
post interaction tables.

```json
{ "action": "profile_summaries", "author_user_id": "uuid", "limit": 6 }
```

Returns active, pinned, and published Field trip summaries visible to the
requester. Active summaries are checklist-status only and must not include scan
IDs, media, field notes, or location details. Pinned summaries are capped at 3
and are omitted from the general `published` list.

```json
{ "action": "set_pinned_publications", "publication_ids": ["uuid"] }
```

Replaces the caller's profile-pinned published Field trips and returns refreshed
profile summaries. The list is capped at 3 publication IDs.

```json
{
  "action": "publish",
  "user_field_trip_id": "uuid",
  "title": "optional",
  "description": "optional",
  "ai_summary": "optional"
}
```

Publishes a completed Field trip into Field trip snapshot tables. This does not
write `explore_posts`, Explore map points, normal Explore post notifications,
APNs, widgets, or public web share pages.

```json
{ "action": "detail", "publication_id": "uuid" }
{ "action": "set_like", "publication_id": "uuid", "liked": true }
{ "action": "comments", "publication_id": "uuid", "limit": 50 }
{ "action": "create_comment", "publication_id": "uuid", "body": "Nice finds!" }
```

Published pages use Field trip likes and comments stored separately from Explore
post likes and comments. `comments` also accepts the paired cursor fields
`after_created_at` and `after_comment_id`; both must be supplied together.
`create_comment` accepts an optional `parent_comment_id` for one-level replies
and limits body text to 500 characters.

## iOS Callers

The iOS client maps this endpoint through:

```swift
MerianNetworkClient.shared.getFieldTripCaptureContext()
MerianNetworkClient.shared.getFieldTrips(userRegion:limit:)
MerianNetworkClient.shared.getFieldTripTemplate(templateId:)
MerianNetworkClient.shared.startFieldTrip(templateId:)
MerianNetworkClient.shared.stopFieldTrip(userFieldTripId:)
MerianNetworkClient.shared.resetFieldTrip(userFieldTripId:)
MerianNetworkClient.shared.getFieldTripChallenges(userRegion:limit:)
MerianNetworkClient.shared.getFieldTripChallenge(challengeId:entriesLimit:)
MerianNetworkClient.shared.joinFieldTripChallenge(challengeId:)
MerianNetworkClient.shared.getFieldTripCommunityPublications(mode:templateId:userRegion:habitatTags:seasonTags:limit:beforeRankBucket:beforePublishedAt:beforePublicationId:)
MerianNetworkClient.shared.getRecentFieldTripPublications(userRegion:habitatTags:limit:beforePublishedAt:beforePublicationId:)
MerianNetworkClient.shared.applyFieldTripProgress(scanId:preferredGoal:)
MerianNetworkClient.shared.getFieldTripScanContributions(scanId:)
MerianNetworkClient.shared.getFieldTripChallengeHashtags(scanId:)
MerianNetworkClient.shared.getFieldTripProfileSummaries(authorUserId:limit:)
MerianNetworkClient.shared.setPinnedFieldTripPublications(publicationIds:)
MerianNetworkClient.shared.publishFieldTrip(userFieldTripId:title:description:aiSummary:)
MerianNetworkClient.shared.getFieldTripChallengePublications(challengeId:limit:beforePublishedAt:beforeEntryId:)
MerianNetworkClient.shared.publishFieldTripChallengeEntry(participationId:title:description:)
MerianNetworkClient.shared.getFieldTripChallengeEntry(entryId:)
MerianNetworkClient.shared.getFieldTripPublication(publicationId:)
MerianNetworkClient.shared.setFieldTripLike(publicationId:liked:)
MerianNetworkClient.shared.setFieldTripChallengeEntryLike(entryId:liked:)
MerianNetworkClient.shared.getFieldTripComments(publicationId:limit:afterCreatedAt:afterCommentId:)
MerianNetworkClient.shared.getFieldTripChallengeEntryComments(entryId:limit:afterCreatedAt:afterCommentId:)
MerianNetworkClient.shared.createFieldTripComment(publicationId:body:parentCommentId:)
MerianNetworkClient.shared.createFieldTripChallengeEntryComment(entryId:body:parentCommentId:)
```

Progress correctness is server-owned. Scan ingestion invokes the atomic
mutation in the scan transaction; the later Edge call retrieves its receipt for
feedback. If any progress component fails, the scan transaction rolls back and
the ingestion retry remains authoritative.

## Deployment Order

1. Apply `20260708021110_field_trips_v1.sql`.
2. Apply `20260708033451_field_trips_v2.sql`.
3. Apply `20260708042713_field_trips_v3_community.sql`.
4. Apply `20260708051414_field_trips_v4_challenges.sql`.
5. Apply `20260717150222_contextual_outing_objective_guides.sql`.
6. Apply `20260717195751_active_outing_capture_context.sql`.
7. Apply `20260717213641_preserve_standard_outings_in_capture_context.sql`.
8. Apply `20260717224544_retire_forest_edges_outing.sql`.
9. Apply `20260718043218_expose_field_trip_completion_scan_ids.sql`.
10. Apply `20260718051748_expose_field_trip_publication_status.sql`.
11. Apply `20260718150932_add_credited_field_trip_progress.sql`.
12. Apply `20260718162409_scope_credited_progress_to_current_attempt.sql`.
13. Apply `20260719045306_first_field_trip_achievement.sql`.
14. Apply `20260719160750_field_trip_lifecycle_controls.sql`.
15. Apply `20260720014446_update_backyard_safari_copy.sql`.
16. Apply `20260722025411_persistent_field_trip_scan_contributions.sql`.
17. Apply `20260722064704_harden_atomic_field_trip_progress.sql`.
18. Apply `20260722195453_exclude_ants_from_bee_wasp_goal.sql`.
19. Apply `20260722211636_tighten_field_trip_goal_matching.sql`.
20. Deploy the scan-ingestion functions.
21. Deploy this function.
22. Deploy `get-explore-author-profile` so profile responses include
    `field_trips`.
23. Deploy `get-explore-notifications`, `get-explore-unread-notification-count`,
    and `mark-explore-notifications-read` so Field trip activity appears in the
    in-app activity sheet and bell.
24. Ship the iOS client.

## Verification

```sh
deno fmt --check services/supabase/functions/field-trips services/supabase/functions/_tests/fieldTripActions.test.ts services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts services/supabase/functions/_tests/fieldTripCaptureContextDb.test.ts services/supabase/functions/_tests/fieldTripProgressDb.test.ts services/supabase/functions/_tests/fieldTripLifecycleDb.test.ts services/supabase/functions/_tests/fieldTripAtomicProgressDb.test.ts services/supabase/functions/_tests/fieldTripSecurityDb.test.ts services/supabase/functions/_tests/fieldTripPublicationDb.test.ts
deno check --config services/supabase/functions/field-trips/deno.json services/supabase/functions/field-trips/index.ts
deno test services/supabase/functions/_tests/fieldTripActions.test.ts
deno test --config services/supabase/functions/field-trips/deno.json --allow-read services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts services/supabase/functions/field-trips/db_test.ts
deno test --allow-env --allow-net --allow-read services/supabase/functions/_tests/fieldTripCaptureContextDb.test.ts
deno test --allow-env --allow-net --allow-read services/supabase/functions/_tests/fieldTripProgressDb.test.ts
deno test --allow-env --allow-net --allow-read services/supabase/functions/_tests/fieldTripLifecycleDb.test.ts
deno test --allow-env --allow-net --allow-read services/supabase/functions/_tests/fieldTripAtomicProgressDb.test.ts services/supabase/functions/_tests/fieldTripSecurityDb.test.ts services/supabase/functions/_tests/fieldTripPublicationDb.test.ts
supabase db lint --workdir services
supabase db advisors --local --workdir services --type all --level warn --fail-on none
```

Before deployment, verify the active objective catalog against the canonical
criteria table in
[`docs/features-and-hardware/25-field-trips.md`](../../../../docs/features-and-hardware/25-field-trips.md#active-objective-matching-contract).
At minimum, the database suite must prove that moths do not satisfy Backyard
Butterfly;
ticks/scorpions do not satisfy Spider; ants and sawflies do not satisfy Bee or
wasp; cultivated/urban plants do not satisfy animal ecology goals; a fern does
not satisfy Flowering plant; and a fruit fly, deer, or meadowlark does not
satisfy the corresponding fruiting-, wild-, or meadow-plant goal.

The capture-context, progress, lifecycle, atomic, security, and publication database integration tests require
a running local Supabase/Postgres stack. A reported skip because port `54322` is
unavailable is not a successful database execution and must be covered before
release or by the linked deployment validation path. The progress test
re-identifies one scan after standard and challenge level advancement and
asserts that only rows inserted by the current attempt appear in the response.

The static migration contract also verifies that both private checklist RPCs
project `completed_scan_id` and grant execution only to `service_role`. Release
QA must compare the returned ID to `user_field_trip_item_completions.scan_id`
and confirm public/capture payloads still omit it.

The lifecycle test covers saved stopped progress, Capture/profile exclusion,
late approval, stopped-gap exclusion, repeated periods, Reset preservation of
Seasonal Challenge data, the post-reset scan boundary, and explicit restart.

The contract also verifies that publication status stays detail-only, joins the
requesting owner's active non-deleted publication, and preserves the
service-role-only template-detail grant.
