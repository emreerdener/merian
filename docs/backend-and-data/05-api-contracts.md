# API Contracts and Network Mappings

Naturebook operates through a decoupled backend. The iOS application exclusively
hits Supabase Edge Functions, abstracting its networking away from 3rd-party
providers like Google Gemini.

The normative end-to-end success, retry, recovery, security, and rollout
contract for Capture → Identify → Insight → Field Chat / Explore is
[Scan Ingestion Reliability and Recovery](./16-scan-ingestion-reliability-and-recovery.md).
The sections below remain authoritative for individual request and response
shapes.

## Fleet-Wide JSON Ingress and Error Contract

Every production Deno endpoint reads JSON through bounded primitives in
`services/supabase/functions/_shared/http.ts`. Most routes use
`parseJsonBody(...)`; signed webhooks use the same module's exact raw-byte
reader, and reviewed media adapters delegate to its bounded JSON reader. The
ordinary object reader:

- accepts `application/json` and `application/*+json` only;
- rejects malformed, negative, non-decimal, or conflicting `Content-Length`
  values;
- compares the declared size with the actual streamed size;
- cancels the stream before retaining a chunk that would cross the limit;
- coalesces accepted chunks into a geometrically growing bounded buffer so
  allocation stays proportional to byte count rather than transport chunk count;
- rejects invalid UTF-8 and malformed JSON; and
- requires a JSON object unless the endpoint explicitly documents another shape.

Routes use the smallest endpoint class that can contain a valid request:

| Class      | Maximum body | Intended payload                     |
| ---------- | -----------: | ------------------------------------ |
| `small`    |       16 KiB | scalar IDs, actions, and preferences |
| `standard` |       64 KiB | ordinary structured API requests     |
| `bulk`     |        1 MiB | explicitly bounded batches           |

Media endpoints may use a reviewed larger ceiling through
`_shared/mediaBudgets.ts`; they still use the same streaming reader. Bodies are
uncompressed JSON. These byte limits are an allocation boundary, not a schema
validator: each endpoint must continue to validate field types, string lengths,
array counts, UUIDs, and ownership.

Parser failures use stable public codes:

| HTTP | Code                                                               |
| ---: | ------------------------------------------------------------------ |
|  400 | `invalid_content_length`, `invalid_json`, or `invalid_json_object` |
|  413 | `payload_too_large`                                                |
|  415 | `unsupported_media_type`                                           |

Edge errors return:

```json
{
  "error": "A stable caller-safe message",
  "code": "stable_machine_code",
  "request_id": "server-generated-uuid"
}
```

`X-Request-ID` carries the same UUID and is exposed through CORS. The server
does not trust an inbound request-ID header. Every wrapped response also carries
the fixed, non-secret `X-Merian-Handler: 1` marker. This marker is diagnostic
metadata for distinguishing a handler response from a gateway/router response;
it is never authorization evidence. Authenticated routes use `withEdgeHandler`;
custom-auth, webhook, and intentionally public routes use `serveEdge`. Expected
thrown failures use `PublicHttpError`, while explicit safe response failures use
`publicErrorResponse(...)`. Retained returned `4xx` contracts must contain only
audited validation or caller-state data; the boundary validates/adds their
stable code and request ID. An arbitrary exception is logged privately and
becomes `500 internal_error`; an ordinary returned `5xx` keeps its status but
receives the generic status-derived code/message. Retryable public failures may
additionally include `retry_after_seconds` and a bounded `Retry-After` header.

The Next.js waitlist API uses the equivalent web envelope with `message` in
place of `error`. Its 4 KiB request ceiling, CAPTCHA, database rate limits, and
service-only pre-challenge and insertion RPCs are documented in the web README
and deployment runbook. The distributed IP claim runs before Turnstile; the
tighter verified-attempt and global-growth transaction runs only after a valid
challenge.

## Fleet-Wide Outbound Provider Contract

Production Edge modules use `services/supabase/functions/_shared/outbound.ts`
rather than invoking global or injected fetch transports. Every outbound
provider call carries a hard deadline that is combined with caller cancellation.
Text and JSON responses are streamed through endpoint-specific byte ceilings
before decoding or parsing. Signed R2 requests are the only direct
client-transport calls; CI enumerates those adapter modules and verifies each
call receives a deadline-bound `Request`.

Telemetry follows the same rule even though it is best-effort. PostHog capture
has a 2.5-second deadline. A timeout or oversized provider diagnostic is logged
privately and does not become a raw public API error.

## Deno `/field-trips` Edge Node

`/field-trips` is an action-based Explore-adjacent social endpoint. It is
authenticated through `withEdgeHandler`; request bodies cannot choose `self_id`
or otherwise assign progress to another user.

All public-schema Field trip/Event `SECURITY DEFINER` functions are Edge-owned.
Execute is revoked from `PUBLIC`, `anon`, and `authenticated` and granted only
to `service_role`; there is no intentionally direct client RPC in this feature.

`services/supabase/functions/field-trips/actions.ts` is the canonical action
allowlist. A missing/non-string or unknown action returns `HTTP 400`. Unknown
strings emit `field_trip_action_rejected` with the value truncated to 64
characters so operators can distinguish a stale client from an incomplete Edge
deployment without logging the request body or user identity.

### Catalog

Request:

```json
{
  "action": "catalog",
  "user_region": "us-ca",
  "limit": 40
}
```

Response:

```json
{
  "data": [
    {
      "template_id": "uuid",
      "slug": "backyard_safari",
      "title": "Backyard Safari",
      "subtitle": "Observe local species often found in your own backyard.",
      "description": "A starter checklist for neighborhood discoveries.",
      "cover_image_url": "https://...",
      "estimated_duration_minutes": 30,
      "guide_where_to_look": "Look near flowers, fences, planters, and quiet corners.",
      "guide_why_it_matters": "Neighborhood trips build a habit of noticing everyday biodiversity.",
      "guide_safety_ethics": "Stay where you have permission and avoid handling animals.",
      "region_tags": ["global"],
      "season_tags": ["all"],
      "habitat_tags": ["neighborhood"],
      "difficulty": "starter",
      "is_pro_only": false,
      "is_rotating_free": true,
      "viewer_has_access": true,
      "access_kind": "starter",
      "active_progress": {
        "user_field_trip_id": "uuid",
        "started_at": "2026-07-08T12:00:00.000Z",
        "current_level_number": 1,
        "completed_at": null,
        "is_profile_visible": true,
        "completed_count": 2,
        "target_count": 4
      },
      "stopped_progress": null,
      "levels": [
        {
          "level_id": "uuid",
          "level_number": 1,
          "title": "Level 1",
          "description": "Start close to home.",
          "items": [
            {
              "item_id": "uuid",
              "prompt": "Butterfly",
              "match_type": "taxonomy",
              "guide_tip": "Wait for the insect to settle with wings visible.",
              "is_completed": true,
              "completed_at": "2026-07-08T12:05:00.000Z",
              "completed_scan_id": "saved-scan-uuid",
              "completed_common_name": "Monarch",
              "completed_scientific_name": "Danaus plexippus"
            }
          ]
        }
      ]
    }
  ]
}
```

Free users receive starter and rotating-free trips plus locked Pro templates for
upgrade display. Pro users receive the full active catalog. The backend owns
access decisions; iOS uses `viewer_has_access` and `access_kind` only for UI
state.

`completed_scan_id` is a private, viewer-specific link to the exact
`user_field_trip_item_completions.scan_id` that satisfied the item. It is
non-null only for completed standard-outing items; incomplete items return the
key as `null`. The response deliberately does not add a media URL: iOS resolves
the ID against the caller's device-local scan library and renders the normal
photo or video-poster thumbnail. If that record is unavailable locally, clients
retain the curated placeholder. Completion count or array position must never be
used to infer which checklist items are complete.

The catalog and template-detail RPCs are revoked from `PUBLIC`, `anon`, and
`authenticated` and granted only to `service_role`. The authenticated
`/field-trips` action supplies the verified `user.id`; a client cannot call the
RPC directly or request another user's evidence. `completed_scan_id` is not
projected into public profile summaries, publication or challenge snapshots,
Explore feed/map contracts, or capture context.

`template_detail` additionally projects `publication_id` and `published_at`
inside `active_progress` when the caller owns an active, non-deleted Field trip
publication for that outing. Missing/null values mean the outing has no current
public snapshot and the client renders **Private**; a non-null publication ID
renders **Published**. Completion alone must not imply publication. These fields
are detail-only private viewer metadata and are not added to catalog, capture
context, public profile, or Explore-post projections.

An unfinished stopped outing has `active_progress: null` and an optional
`stopped_progress` object with the same saved checklist counts plus
`stopped_at`. Its `levels` include the saved completion state. Clients use
active-or-stopped viewer progress for catalog status, filters, and detail cards,
but active-only surfaces such as Capture and public active summaries continue to
read only active progress.

### Template Detail and Explicit Start

Template detail request:

```json
{
  "action": "template_detail",
  "template_id": "uuid"
}
```

`slug` may be sent instead of `template_id`. The response is one catalog-shaped
template object with guide fields, levels, item tips, access state, viewer
progress, and the same optional private `completed_scan_id` for completed
standard-outing items.

For template detail only, a published outing's progress includes:

```json
{
  "active_progress": {
    "publication_id": "publication-uuid",
    "published_at": "2026-07-08T13:00:00.000Z"
  }
}
```

Start request:

```json
{
  "action": "start",
  "template_id": "uuid"
}
```

The start action is idempotent for an existing trip. It creates or unhides the
caller's `user_field_trips` row for an accessible template and returns the
refreshed template detail. For a stopped outing it acts as Resume and opens a
new activity period. Matching scans never create or resume a standard outing,
including after Reset.

Lifecycle requests:

```json
{ "action": "stop", "user_field_trip_id": "uuid" }
{ "action": "reset", "user_field_trip_id": "uuid" }
```

Stop preserves standard checklist progress, closes the open activity period, and
removes the outing from Capture/profile active projections. Reset rejects
completed or published outings, clears only unfinished standard progress and
activity periods, and retains the shared outing row so Seasonal Challenge data
is not cascaded away. Both responses contain refreshed template detail and use
the verified Edge caller for ownership.

### Capture Context

Request:

```json
{
  "action": "capture_context"
}
```

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

This is a narrow read model for the idle visual Scan surface. It returns only
active, incomplete, non-hidden standard Field trips that the caller can access.
For each field trip it returns unfinished targets from the current unlocked
level; completed targets and later levels are absent. Seasonal Challenge
participation, labels, and challenge-specific completions are not projected.
Joining a challenge reuses the underlying standard `user_field_trips` row, so
that standard field trip remains eligible and continues to show only its normal
Field Trip progress.

Stopped trips are deliberately absent. A reset Backyard Safari can qualify for
the unstarted introduction again; a stopped one cannot because its
`stopped_progress` proves it has saved viewer progress.

Field trips order by `last_engaged_at DESC`, where engagement is the later of
the trip start and any item completion. `user_field_trip_id` is the stable tie
breaker. Targets order by curated `(sort_order, item_id)`. Field trips with no
unfinished target are omitted, and an account with no eligible field trips
receives `{ "data": [] }`.

Privacy and authorization are deliberately stricter than the catalog contract:

- The request accepts no user identifier. `withEdgeHandler` verifies the caller,
  and the Edge action passes only `user.id` to the database helper.
- `public.get_field_trip_capture_context(uuid)` is `SECURITY INVOKER`, with an
  empty search path and fully qualified database objects. Execute access is
  revoked from `PUBLIC`, `anon`, and `authenticated`, then granted only to
  `service_role`.
- The response contains no scan ID, media URL, location, field note, completed
  common/scientific name, or other evidence.

The iOS mapping is `MerianNetworkClient.shared.getFieldTripCaptureContext()`.
Capture treats the request as non-blocking enrichment: it may retain the last
successful account-scoped result and must not show a request error over the
camera.

### Scan Progress

Request:

```json
{
  "action": "apply_scan_progress",
  "scan_id": "saved-scan-uuid",
  "preferred_goal": {
    "user_field_trip_id": "uuid",
    "item_id": "uuid"
  }
}
```

Response:

```json
{
  "data": [
    {
      "user_field_trip_id": "uuid",
      "template_id": "uuid",
      "slug": "backyard_safari",
      "title": "Backyard Safari",
      "current_level_number": 2,
      "current_level_title": "Level 2",
      "completed_count": 0,
      "target_count": 6,
      "is_complete": false,
      "credited_level_number": 1,
      "credited_level_title": "Level 1",
      "credited_completed_count": 4,
      "credited_target_count": 4,
      "removed_item_ids": [],
      "newly_completed_items": [
        {
          "item_id": "uuid",
          "prompt": "Bird",
          "common_name": "Northern Cardinal",
          "scientific_name": "Cardinalis cardinalis",
          "completed_at": "2026-07-08T12:07:00.000Z"
        }
      ]
    }
  ],
  "challenge_updates": [
    {
      "participation_id": "uuid",
      "challenge_id": "uuid",
      "slug": "summer_pollinator_watch",
      "title": "Summer Pollinator Watch",
      "current_level_number": 1,
      "current_level_title": "Level 1",
      "completed_count": 2,
      "target_count": 4,
      "is_complete": false,
      "badge_awarded_at": null,
      "suggested_hashtags": ["summerpollinators"],
      "credited_level_number": 1,
      "credited_level_title": "Level 1",
      "credited_completed_count": 2,
      "credited_target_count": 4,
      "removed_item_ids": [],
      "newly_completed_items": [
        {
          "item_id": "uuid",
          "prompt": "Bee or wasp",
          "common_name": "Common Eastern Bumble Bee",
          "scientific_name": "Bombus impatiens",
          "completed_at": "2026-07-08T12:07:00.000Z"
        }
      ]
    }
  ],
  "first_field_trip_achievement": {
    "kind": "standard_outing",
    "completed_at": "2026-07-08T12:07:00.000Z",
    "template_slug": "backyard_safari",
    "challenge_id": null
  },
  "first_field_trip_achievement_newly_unlocked": true
}
```

The backing atomic RPC counts only scans owned by the caller, only after the
Field Trip starts, and only against the current unlocked level. Matching accepts
unreviewed AI identifications only at the inference tier's Possible-match
boundary (`Flash >= 0.75`, `Pro >= 0.65`). A weaker match remains uncredited
until the user confirms it or a correction/community resolution supplies a
confirmed species. Those paths use the same scan row and write the same
idempotent item completions. Eligibility is based on the saved biological scan,
not its capture modality, so qualifying photos and videos can count.
Upload/request time does not replace the scan timestamp, so a scan captured
inside a now-closed outing period or Event window can receive delayed first
credit. A single scan is evaluated against every matching current-level item in
every eligible active standard outing, but receives at most one credit per
outing and one per joined live challenge. It may still advance several
deliberately active experiences, with every completion row pointing to the same
scan.

The optional `preferred_goal` is accepted only for an owned standard outing that
was active at the scan timestamp and whose current visible item matches the
saved identification. It wins inside that outing only. Missing, stale,
unauthorized, completed, and nonmatching hints are ignored. Fallback selection
is exact species, scientific name, taxonomy from genus through kingdom,
including excluded-family and taxonomy-plus-signal variants, semantic tag,
ecology, habitat, curated checklist order, then item ID. A `taxonomy_and_signal`
goal requires at least one taxonomy constraint, at least one
ecology/habitat/semantic constraint, and every populated constraint to match.
The exact catalog is maintained in the
[Field Trips matching contract](../features-and-hardware/25-field-trips.md#active-objective-matching-contract).
Park Pollinators' **Bee or wasp** goal requires order `Hymenoptera` plus either
the `bee` or `wasp` semantic category, so ants, sawflies, and other
broader-order matches do not satisfy it. Compound semantic alternatives are
`|`-separated. Spider goals require order `Araneae`; animal and plant signal
goals also require their named kingdom.

For new scans, the identify ingestion intent stores the validated preference and
the scan-insert trigger invokes the same atomic RPC before scan persistence
commits. Standard progress, Event progress, preference persistence, first Field
trip achievement evaluation, and a private scan-revision receipt therefore
commit or roll back together. `apply_scan_progress` retrieves that receipt for
notification delivery. Relevant identification, confidence, inference-tier, or
explicit-confirmation changes create a new scan revision and re-evaluate
progress through the same transaction. Normal identification corrections only
move or remove credit while an experience is unfinished. Confidence,
inference-tier, or confirmation changes can also remove credit from a completed
experience when the scan becomes weak and unconfirmed, reopening its earliest
incomplete level.

V4 clients should continue reading `data` for normal Field trip progress and may
read `challenge_updates` for joined live challenge progress. Older clients can
ignore `challenge_updates`.

Both arrays add four backward-compatible credited-level fields:
`credited_level_number`, `credited_level_title`, `credited_completed_count`, and
`credited_target_count`. They describe the level that accepted this scan's newly
completed item. If the write finishes a level and advances immediately, the
existing `current_*`, `completed_count`, and `target_count` fields describe the
newly active level while `credited_*` retains the completed level and therefore
reports a full ring instead of the next level's `0/N`. During a staged
database/client rollout, iOS decodes these fields optionally and falls back to
the existing counts when they are absent. Credited counts and
`newly_completed_items` are scoped to completion rows inserted by the current
application attempt. If an older scan is re-identified after level advancement,
its historical completion rows cannot duplicate a destination or replace the new
level's ring.

Both update kinds may also include `removed_item_ids`. While an experience is
unfinished, an identification correction can move or remove this scan's credit
within its original credited level and reset progress to the earliest incomplete
level. Completed outings and challenges are immutable for normal identification
corrections; evidence-policy invalidation is the exception.

Migration `20260722195453_exclude_ants_from_bee_wasp_goal.sql` performs a
one-time repair for ant scans credited before that family exclusion existed. It
removes the standard/Event completion and its private preference/receipt,
reopens the earliest incomplete level, clears any derived Event badge, and
withdraws a now-invalid completion publication until an eligible scan completes
the goal. Migration `20260722211636_tighten_field_trip_goal_matching.sql`
applies the same repair policy to other active goals whose former taxonomy or
signal rule was broader than its label. Park's unverifiable **Spider near
flowers** and **Bird near flowers** prompts become **Spider** and **Bird**; the
former **Pollinator habitat** scene prompt becomes the verifiable
plant-plus-meadow **Meadow plant** goal.
Migration
`20260730023042_gate_field_trip_progress_by_confidence.sql` removes standard and
Event credit backed by weak unreviewed identifications, reopens affected
progress, clears derived badges, and withdraws completion publications/entries.
It retains the private selected-goal preference and writes an empty durable
receipt so later confirmation can re-evaluate the pending scan. The same
reconciliation runs on future evidence downgrades, including after completion:
it removes standard/Event credit, reopens progress, clears the Event badge, and
soft-deletes invalid completion publications or entries. Its empty
`newly_completed_items` result cannot generate a completion toast.

Only updates with a nonempty `newly_completed_items` array are eligible for a
scan progress toast. Reapplying an unchanged scan is idempotent and returns its
stored receipt, including the original update payload; this lets a client that
terminated after ingestion recover the unlock notification. iOS acknowledges and
deletes its durable goal-hint outbox after consuming success/terminal state, and
separately deduplicates already released milestones by scan ID. A changed
identification revision replaces the receipt with its correction result.
`preferred_goal` is an optional additive request field. Older clients omit it
and receive the deterministic fallback. The response remains backward-
compatible because credited and removed-item fields decode optionally.

### Scan Contributions

Request:

```json
{ "action": "scan_contributions", "scan_id": "saved-scan-uuid" }
```

Response:

```json
{
  "data": [
    {
      "source_kind": "standard_outing",
      "source_id": "uuid",
      "user_field_trip_id": "uuid",
      "participation_id": null,
      "template_id": "uuid",
      "challenge_id": null,
      "title": "Park Pollinators",
      "slug": "park_pollinators",
      "item_id": "uuid",
      "prompt": "Butterfly or moth",
      "level_number": 1,
      "level_title": "Level 1",
      "completed_count": 3,
      "target_count": 4,
      "is_complete": false,
      "artwork_prompt": "Butterfly or moth",
      "artwork_template_slug": "park_pollinators",
      "destination_kind": "field_trip",
      "destination_template_id": "uuid",
      "destination_checklist_item_id": "uuid",
      "destination_challenge_id": null
    }
  ]
}
```

The authenticated Edge action supplies the verified caller to the private
service-role RPC. It returns one current credit per standard outing/Event for
the supplied saved biological scan. Rows include only labels, counts, artwork
inputs, and typed-routing inputs. They never include media, storage URLs,
coordinates, place labels, notes, or public evidence. Missing, unauthorized,
queued, non-biological, and uncredited scans return an empty array. Events-
disabled clients filter Event rows before state or presentation.

### Seasonal Challenges

The challenge API is deployed before the Events UI is public. Standard Outings
are available to every iOS user, while the client omits the Events segment,
catalog/detail requests, badges, entry routes, and hashtag suggestions unless
`FieldTripEventsAvailability` is enabled. `apply_scan_progress` may still return
challenge progress from the shared server transaction; an Events-disabled client
filters those rows before caching, refresh publication, navigation, or
presentation. This release gate is not an authorization boundary: all actions
continue to enforce the verified viewer and existing database policies. The
future public Events flip does not change these request or response shapes.

Catalog request:

```json
{
  "action": "challenges_catalog",
  "user_region": "us-ca",
  "limit": 20
}
```

Catalog rows include:

```json
{
  "challenge_id": "uuid",
  "template_id": "uuid",
  "template_slug": "park_pollinators",
  "template_title": "Park Pollinators",
  "slug": "summer_pollinator_watch",
  "title": "Summer Pollinator Watch",
  "subtitle": "Find pollinators while flowers are active.",
  "description": "A non-competitive seasonal challenge.",
  "cover_image_url": "https://...",
  "starts_at": "2026-06-01T00:00:00.000Z",
  "ends_at": "2026-08-31T23:59:59.000Z",
  "status": "live",
  "region_tags": ["global"],
  "season_tags": ["summer"],
  "habitat_tags": ["park", "garden"],
  "suggested_hashtags": ["summerpollinators", "pollinators"],
  "is_pro_only": false,
  "is_temporarily_free": true,
  "viewer_has_access": true,
  "access_kind": "temporarily_free",
  "participant_count": 42,
  "completion_count": 9,
  "published_entry_count": 4,
  "viewer_participation": {
    "participation_id": "uuid",
    "user_field_trip_id": "uuid",
    "joined_at": "2026-07-08T12:00:00.000Z",
    "current_level_number": 1,
    "completed_at": null,
    "badge_awarded_at": null,
    "completed_count": 1,
    "target_count": 4
  },
  "template": null,
  "entries": []
}
```

`status` is one of `live`, `upcoming`, or `ended`. Access is
server-authoritative and independent from the linked template's ordinary catalog
access; a challenge can be free, Pro-only, or temporarily free during its
schedule.

Detail and join requests:

```json
{ "action": "challenge_detail", "challenge_id": "uuid", "entries_limit": 12 }
{ "action": "join_challenge", "challenge_id": "uuid" }
```

`challenge_detail` returns one challenge object with linked template guide
context and initial entries. `join_challenge` requires a live accessible
challenge, starts or continues the linked Field trip, creates or returns the
separate participation row, and returns refreshed challenge detail. It is
idempotent for repeated joins.

Challenge progress is updated through `apply_scan_progress`. A scan counts only
when it is owned by the caller, created at or after `joined_at`, created at or
before `ends_at`, satisfies the same Possible-match-or-confirmed evidence
policy, and matches the participant's current challenge level. Challenge
completions are separate from normal Field trip completions and are limited to
one credited item per participation and scan.

Challenge hashtag request:

```json
{ "action": "scan_challenge_hashtags", "scan_id": "saved-scan-uuid" }
```

Response:

```json
{ "data": ["summerpollinators", "pollinators"] }
```

The response is for optional Explore composer suggestions only. The endpoint
does not auto-post, auto-tag, create Explore challenge feeds, or persist private
challenge evidence on device.

### Challenge Entries

Publication list request:

```json
{
  "action": "challenge_publications",
  "challenge_id": "uuid",
  "limit": 20,
  "before_published_at": "2026-07-08T13:00:00.000Z",
  "before_entry_id": "uuid"
}
```

Rows paginate by `(published_at DESC, entry_id DESC)` and use the same
block/shadowban visibility rules as Field trip publications. Challenge entries
are not `field_trip_publications` and do not create Explore posts.

Publish/detail/like/comment requests:

```json
{
  "action": "publish_challenge_entry",
  "participation_id": "uuid",
  "title": "My Pollinator Watch",
  "description": "Optional"
}
{ "action": "challenge_entry_detail", "entry_id": "uuid" }
{ "action": "set_challenge_entry_like", "entry_id": "uuid", "liked": true }
{ "action": "challenge_entry_comments", "entry_id": "uuid", "limit": 50 }
{ "action": "create_challenge_entry_comment", "entry_id": "uuid", "body": "Nice finds!" }
```

Publishing requires a completed challenge participation and snapshots challenge
item completions into `field_trip_challenge_entry_items`. Challenge entry likes
and comments are stored in challenge-specific tables, not Explore or normal
Field trip publication tables. Joins, likes, badges, and progress updates do not
notify other users in V4.

### Profile Summaries

Request:

```json
{
  "action": "profile_summaries",
  "author_user_id": "uuid",
  "limit": 6
}
```

Response:

```json
{
  "data": {
    "active": [
      {
        "user_field_trip_id": "uuid",
        "template_id": "uuid",
        "slug": "backyard_safari",
        "title": "Backyard Safari",
        "started_at": "2026-07-08T12:00:00.000Z",
        "current_level_number": 1,
        "current_level_title": "Level 1",
        "completed_count": 3,
        "target_count": 4,
        "is_complete": false
      }
    ],
    "pinned": [
      {
        "publication_id": "uuid",
        "title": "Backyard Safari with Sam",
        "description": "A quiet morning checklist.",
        "published_at": "2026-07-08T13:00:00.000Z",
        "like_count": 4,
        "comment_count": 1,
        "slug": "backyard_safari",
        "template_title": "Backyard Safari",
        "cover_image_url": "https://...",
        "item_count": 4,
        "viewer_has_liked": false,
        "is_pinned": true,
        "pin_position": 1
      }
    ],
    "published": [
      {
        "publication_id": "uuid",
        "title": "Backyard Safari with Sam",
        "description": "A quiet morning checklist.",
        "published_at": "2026-07-08T13:00:00.000Z",
        "like_count": 4,
        "comment_count": 1,
        "slug": "backyard_safari",
        "template_title": "Backyard Safari",
        "cover_image_url": "https://...",
        "item_count": 4,
        "viewer_has_liked": false,
        "is_pinned": false,
        "pin_position": null
      }
    ],
    "challenge_badges": [
      {
        "badge_id": "uuid",
        "challenge_id": "uuid",
        "badge_key": "summer_pollinator_watch_complete",
        "title": "Summer Pollinator Watch",
        "awarded_at": "2026-07-08T13:00:00.000Z",
        "challenge_slug": "summer_pollinator_watch",
        "challenge_title": "Summer Pollinator Watch",
        "cover_image_url": "https://...",
        "region_tags": ["global"],
        "season_tags": ["summer"],
        "habitat_tags": ["park"]
      }
    ]
  }
}
```

Active summaries are profile-status only. They must not expose scan IDs, media
URLs, field notes, exact coordinates, public location labels, or private
evidence. Published summaries expose only Field trip publication IDs and
snapshot metadata. `pinned` is capped at 3 and omitted from the general
`published` list. Shadowbanned authors and mutual blocks are excluded. Challenge
badges are lightweight profile rewards only; they expose no scan IDs, media
URLs, exact location, field notes, or private evidence.

Set pinned publications request:

```json
{
  "action": "set_pinned_publications",
  "publication_ids": ["uuid"]
}
```

The response is the refreshed profile summaries payload. The endpoint replaces
the caller's pin list, preserves the supplied order, rejects more than 3 IDs,
and accepts only the caller's visible Field trip publications.

### Community Publications

Request:

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

Response:

```json
{
  "data": [
    {
      "publication_id": "uuid",
      "template_id": "uuid",
      "title": "Backyard Safari with Sam",
      "description": "A quiet morning checklist.",
      "published_at": "2026-07-08T13:00:00.000Z",
      "like_count": 4,
      "comment_count": 1,
      "slug": "backyard_safari",
      "template_title": "Backyard Safari",
      "region_tags": ["global", "neighborhood"],
      "season_tags": ["spring"],
      "habitat_tags": ["yard"],
      "cover_image_url": "https://...",
      "item_count": 4,
      "viewer_has_liked": false,
      "author_user_id": "uuid",
      "author_name": "River W.",
      "author_username": "river_w",
      "author_avatar_url": "https://...",
      "is_pinned": false,
      "pin_position": null,
      "rank_bucket": 0,
      "community_reason": "following",
      "viewer_is_following_author": true
    }
  ]
}
```

`mode` accepts `smart`, `following`, or `recent`. `smart` is deterministic
bucketed ranking, not ML: followed author plus local/template relevance,
followed author, local/habitat/season/template match, global/no-region fallback,
then other visible fallback. Within each bucket, rows order by
`published_at DESC, publication_id DESC`. `following` filters to existing
`user_follows` relationships. `recent` is reverse chronological for all visible
published Field trips. `template_id` limits results for template-detail
Community previews.

Pagination is stable on
`(rank_bucket ASC, published_at DESC, publication_id DESC)`, so community
cursors must send all three cursor fields together.

Compatibility request:

```json
{
  "action": "recent_publications",
  "user_region": "us-ca",
  "habitat_tags": ["neighborhood"],
  "limit": 20,
  "before_published_at": "2026-07-08T13:00:00.000Z",
  "before_publication_id": "uuid"
}
```

`recent_publications` is a compatibility alias for `community_publications` with
`mode: "recent"`.

Community Publications is Field trips-native and never creates Explore post
rows. The iOS client also reuses this action to mix typed Field trip cards into
unfiltered Explore Recent and Following. Those cards retain Field trip identity
and interactions. Field trips remain absent from Trending, Nearby, map, widgets,
APNs, and public web share surfaces.

### Publication Detail, Likes, and Comments

Publish request:

```json
{
  "action": "publish",
  "user_field_trip_id": "uuid",
  "title": "Backyard Safari with Sam",
  "description": "A quiet morning checklist.",
  "ai_summary": "Optional generated summary."
}
```

Detail request:

```json
{
  "action": "detail",
  "publication_id": "uuid"
}
```

Detail response:

```json
{
  "data": {
    "publication_id": "uuid",
    "user_field_trip_id": "uuid",
    "template_id": "uuid",
    "template_slug": "backyard_safari",
    "template_title": "Backyard Safari",
    "title": "Backyard Safari with Sam",
    "description": "A quiet morning checklist.",
    "ai_summary": null,
    "published_at": "2026-07-08T13:00:00.000Z",
    "author_user_id": "uuid",
    "author_name": "River W.",
    "author_username": "river_w",
    "author_avatar_url": "https://...",
    "like_count": 4,
    "comment_count": 1,
    "viewer_has_liked": false,
    "items": [
      {
        "publication_item_id": "uuid",
        "item_id": "uuid",
        "prompt": "Bird",
        "common_name": "Northern Cardinal",
        "scientific_name": "Cardinalis cardinalis",
        "hero_image_url": "https://...",
        "reference_image_url": "https://...",
        "taxonomy": {
          "kingdom": "Animalia",
          "class": "Aves"
        }
      }
    ]
  }
}
```

Like request:

```json
{
  "action": "set_like",
  "publication_id": "uuid",
  "liked": true
}
```

Comments request:

```json
{
  "action": "comments",
  "publication_id": "uuid",
  "limit": 50,
  "after_created_at": "2026-07-08T13:01:00.000Z",
  "after_comment_id": "uuid"
}
```

Create-comment request:

```json
{
  "action": "create_comment",
  "publication_id": "uuid",
  "body": "Nice finds!",
  "parent_comment_id": null
}
```

Field trip likes and comments are stored in `field_trip_publication_likes` and
`field_trip_publication_comments`, not in Explore post tables. Comment payloads
intentionally mirror the compact `ExploreComment` shape for iOS reuse, with
`post_id` carrying the Field trip publication ID inside this scoped endpoint.

Publishing a Field trip never writes `explore_posts`, Explore feed cards,
Explore map rows, normal Explore post notifications, APNs, widgets, or public
web share pages. Field trip comments, replies, and followed-author publications
may create Field trip-only in-app activity rows that appear in Explore activity
and the unread bell. Sharing is a future layer.

---

## Deno `/generate-upload-urls` Edge Node

To fetch cryptographic keys for direct-to-Cloudflare uploads, the client sends a
structured media manifest. The cross-language contract lives in
`docs/contracts/media-staging-upload-manifest.json`; Swift and Deno tests both
load that file so limits and allowed content types cannot drift silently.

### Request Payload

```json
{
  "user_id": "Supabase Auth UUID linking RevenueCat and PostHog",
  "files": [
    {
      "fileName": "scan-id_photo_1.webp",
      "mediaKind": "image",
      "contentType": "image/webp",
      "sizeBytes": 124000,
      "clientScanId": "00000000-0000-0000-0000-000000000001",
      "mediaRole": "display"
    },
    {
      "fileName": "scan-id_audio_1.wav",
      "mediaKind": "audio",
      "contentType": "audio/wav",
      "sizeBytes": 42000,
      "clientScanId": "00000000-0000-0000-0000-000000000001",
      "mediaRole": "audio"
    }
  ]
}
```

The server extracts the verified user identity from the `Authorization` Header
JWT (`supabaseAdmin.auth.getUser()`), ignoring any `user_id` value in the
request body. To prevent array-abuse memory locking on the Edge Node, the
endpoint strictly requires exactly 1 to 6 `files`, with at most 5 images, 2
audio files, and 1 video file. The six-file ceiling exists for the canonical Pro
video scan shape: five sampled `image/webp` inference frames plus one
`video/mp4` playback clip. It is not a general expansion to six images. The main
app queue builds this manifest through `MediaStagingContract` and must apply the
same filename sanitization as the Edge function before upload URL generation.
For scan uploads, each structured entry may also include `clientScanId` and
`mediaRole`; when present, `/generate-upload-urls` creates a server-owned staged
`scan_media_assets` row before returning the signed URL. Those staged rows are
valid with `scan_id = NULL` until the final scan row exists and with
`url = NULL` until media promotion produces a public URL; they are keyed by
owner, client scan id, deterministic object key, and upload session for later
promotion or cleanup. Image roles may be `display`, `thumbnail`, or
`inference_frame`; video uses `playback`; audio uses `audio`. The Edge parser
rejects unsanitized filenames, duplicate filenames (including legacy names that
sanitize to one key), invalid `mediaKind` values, invalid role/kind
combinations, content-type/kind mismatches, empty media, and oversized media
before signing. Structured manifests require a positive integer `sizeBytes`;
the legacy `fileNames` array remains
accepted for older clients but is compatibility-only and cannot express byte
budgets or media asset sessions. Pre-signed `PUT` URLs include an
`X-Amz-Expires=86400` parameter (24 hours). This extended window gives iOS
`BackgroundTasks` flexibility to transmit overnight, subject to OS memory,
thermal, and Wi-Fi conditions, without hitting 403 errors.

An already-persisted observation that is missing durable sharing media adds
`"uploadPurpose": "scan_share_restore"` to each repair entry. That purpose is
accepted only with `clientScanId`, the canonical media role, and an exact
scan/category-bound deterministic restore filename. For a completed job, the
signer performs a fresh unrestricted scan read. An existing row must be active,
non-tombstoned, and owned by the authenticated caller; a genuinely absent row
may only stage these exact files before guarded owner-row reconstruction. A
missing or nonterminal job can stage for the same guarded flow, but signing
grants no scan-write or publication authority; the recovery route still
validates the owner and payload. Repair and ordinary files cannot mix for one
scan. Ordinary uploads cannot use completed ingestion as a new staging
namespace. Failed-terminal repair is limited to exact `replay_exhausted`, or
exact `media_reconciliation_abandoned` plus matching composite
dead-letter/quota/media-lifecycle proof. Current/later policy, unproven
abandonment, and every other terminal reason remain closed. Signing obtains
that decision from bounded service-only
`get_media_abandoned_scan_recovery_proofs`; database errors, malformed rows, or
an unexpected scan id fail before any URL is returned. This exception is what
lets Explore and Ask the Community restore surviving local image,
playback-video, or standalone-audio media after analysis has durably completed.
When camelCase and snake_case compatibility aliases are both supplied for scan
ID, media role, or upload purpose, their values must be identical; contradictory
aliases fail before lifecycle registration.

The Edge function uses the `fileName` parameter from the JSON body (after
applying basic sanitization to prevent path traversal vectors) rather than
generating random internal UUIDs. The verified server identity, not the optional
body `user_id`, determines the `objectKey` owner segment. A client that planned
with a device identity before lazy anonymous authentication must accept the
canonical returned key. Before dispatching any PUT, iOS requires exact response
count/order, matching filenames, one canonical staging owner, and signed URL
paths that resolve to the returned keys. Each background task carries its exact
returned key through suspension.

```json
{
  "urls": [
    {
      "fileName": "photo_1.webp",
      "signedUrl": "https://<R2_URL>?X-Amz-Signature=...",
      "objectKey": "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_photo_1.webp",
      "mediaAssetId": "scan_media_assets row UUID",
      "mediaSessionId": "upload session UUID"
    }
  ]
}
```

`mediaAssetId` and `mediaSessionId` are omitted for non-scan uploads, such as
profile avatars, and for legacy `fileNames` clients. During
`identify-multimodal` finalization, promoted image/video/standalone-audio
staging keys update the matching staged rows and link them to the completed
scan. Consumed extracted `video_audio` staging keys become `deleted`;
moderation, promotion, or scan-insert failures mark still-staged rows as
`failed`. The returned `mediaSessionId` values also let ingestion recover the
exact upload sessions for the staged object keys; those session ids participate
in the `scan_ingestion_jobs` `manifest_checksum`, giving retries and repair
workers a stable server-side description of the requested media set without
storing media bytes.

Scan-media registration is idempotent on
`(authenticated owner, clientScanId, objectKey)`. A retry after a lost signing
response returns the committed asset and original upload session. An exactly
compatible failed row may reactivate when its ingestion job is absent or
retryable. An exact `scan_share_restore` row may also register or reactivate for
completed ingestion when the fresh scan read finds either the active owned row
or no row for the guarded reconstruction; tombstoned, foreign, and
moderation-rejected/moderation-pipeline-failed rows fail closed.
Failed-terminal, deleted, ordinary
completed-ingestion, or media-incompatible rows also fail closed. A partial
unique index serializes registration races, while the repair migration retains
historical extras as `failed / superseded_staging_registration` audit rows. New
rows use a per-client-scan media index, never a flat position among other scans
in the signing request. The six-item union counts active staged/processing
sources; historical promoted capture rows remain audit evidence but do not
consume a later explicit share-repair budget. Any response manifest mismatch
starts no upload and returns the claimed scans to `.pending` with durable
backoff.

> The pre-signed URL is generated with the exact `contentType` from the
> structured manifest. The iOS `URLRequest` must send the same `Content-Type`
> header on the `PUT`, or Cloudflare R2 will reject the upload with
> `403 SignatureDoesNotMatch`.

---

## Deno `/reconcile-scan-media-assets` Internal Worker

This endpoint is not called by iOS. It is invoked hourly by pg_cron with one
exact platform-managed current or legacy server key. Supabase gateway JWT
verification is disabled so pg_net can reach the function, and the function
performs service-key validation internally. Opaque keys use `apikey` only.

Optional request payload:

```json
{
  "limit": 100,
  "repairAfterMinutes": 15,
  "abandonAfterHours": 36,
  "dryRun": false
}
```

Response payload:

```json
{
  "success": true,
  "scanned": 3,
  "promoted": 1,
  "repairedVideoScans": 1,
  "deletedStagingObjects": 2,
  "failedAssets": 1,
  "missingObjects": 0,
  "stillPending": 1,
  "errors": []
}
```

The worker only reconciles media lifecycle state. It can repair an existing scan
that has a surviving staged playback video by promoting the video, updating
`video_storage_urls`, rebuilding `captured_media`, and refreshing ready
`scan_media_assets` rows. It can also delete abandoned staging objects and mark
their staged rows failed. Before treating an orphan as abandoned, it checks the
matching `scan_ingestion_jobs` row: active leases and future retry windows keep
the media pending, repaired scans complete only through the shared
claimed-key/canonical-media finalization routine, and TTL-abandoned media marks
the job `failed_terminal` with a structured terminal reason. Sanitized
`scan_ingestion_intents` rows preserve staged media/audio/video and text-only
replay metadata for operations and `replay-scan-ingestion`, but this worker does
not replay AI inference for scans that never created a cloud scan row.

---

## Deno `/replay-scan-ingestion` Internal Worker

This endpoint is not called by iOS. It is invoked every five minutes by pg_cron
with one exact platform-managed current or legacy server key. Supabase gateway
JWT verification is disabled so pg_net can reach the function, and the function
performs local exact service-key validation internally. Opaque keys use `apikey`
only. The route never uses a database/RLS result as proof, rejects mixed
credentials, and uses its server environment key for database and downstream
multimodal calls.

Optional request payload:

```json
{
  "limit": 5,
  "leaseSeconds": 300,
  "retryAfterMinutes": 5,
  "awaitInvocations": false
}
```

Response payload:

```json
{
  "success": true,
  "claimed": 1,
  "dispatched": 1,
  "completedExisting": 0,
  "skippedExistingIncomplete": 0,
  "failedDispatches": 0,
  "errors": []
}
```

The worker claims due `scan_ingestion_jobs` rows whose paired
`scan_ingestion_intents` are `resumable = true` and not inline-redacted,
reconstructs the staged media/audio/video or text-only request from the
sanitized intent payload, and invokes `/identify-multimodal` with the original
`client_scan_id`. The multimodal endpoint still owns AI inference, moderation,
media promotion, scan insert idempotency, and the strict playback-video
durability gate. A service-authenticated `X-Merian-Replay-Attempt` header
derives a distinct deterministic quota UUID from the scan UUID and durable claim
count. This prevents the original committed reservation from blocking recovery
while keeping each replay metered and idempotent within one claim. Inline
foreground requests remain client-owned because their raw media bytes are never
stored server-side.

Automatic replay is capped at 10 claims per sanitized intent. The claim RPC
excludes over-budget intents from new replay work and marks the paired
`scan_ingestion_jobs` row `failed_terminal` with
`stage = 'server_replay_limit_reached'` in the same bounded claim window, so a
permanently broken replay payload cannot churn forever.

The internal `/identify-multimodal` invocation has a 120-second hard deadline.
`leaseSeconds` is clamped to at least 150 seconds, reserving 30 seconds for
durable failure settlement before a replacement claim is possible. Non-success
diagnostics are retained only within an 8 KiB streamed response ceiling.

Compatibility scan-producing endpoints (`/identify`, `/identify-describe`, and
`/audio-spec`) call `begin_scan_ingestion` before provider dispatch and write
`scan_ingestion_jobs` plus sanitized `scan_ingestion_intents` atomically. A
setup error returns `503 scan_ingestion_unavailable` and refunds unused quota;
an owner-recovery winner reloads the exact owner-scoped completed result and
returns idempotent `200`; neither path calls the provider. A compatibility
fallback conflict is possible only when completion evidence cannot be safely
loaded. Those intents set `endpoint: "identify-multimodal"` inside the replay
payload and preserve the legacy route name as `compatibilityEndpoint`, so staged
legacy image/audio and text-only rows recover through the same replay worker.
Inline base64 media is represented only by redacted counts and is marked
non-resumable. Compatibility setup uses the same per-scan advisory lock as
current claim and recovery. Compatibility completion invokes the response-aware
finalization wrapper; staged inference-only audio must receive R2 2xx or
idempotent 404 deletion confirmation before completion.

If the scan row already exists, the worker invokes
`complete_scan_ingestion_finalization` without replaying AI. That transaction
marks the job complete only after every manifest key has a permitted terminal
disposition and every promoted image/video/audio URL has a ready canonical row.
If the scan row or media is incomplete, the worker leaves the job retryable for
reconciliation or local video restore instead of rerunning inference against an
already-created scan row.

---

## Deno `/scan-media-health` Internal Status

Read-only service-key endpoint for media durability observability. Supabase
gateway JWT verification is disabled for automation reachability, and the
function validates an exact key from the shared current-or-legacy server-key
resolver before querying. Opaque `sb_secret_...` keys are valid only in
`apikey`; legacy service-role JWTs use matching `apikey` and Bearer headers. It
never treats a successful database/RLS response as proof and does not reuse the
request credential for database access.

Optional request payload:

```json
{
  "limit": 25,
  "stuckAfterMinutes": 20,
  "staleAssetAfterMinutes": 15,
  "recentScanLimit": 250
}
```

Response payload:

```json
{
  "success": true,
  "generated_at": "2026-07-05T15:00:00.000Z",
  "status": "warning",
  "thresholds": {
    "stuck_after_minutes": 20,
    "stale_asset_after_minutes": 15
  },
  "counts": {
    "ingestion_jobs_checked": 3,
    "stale_capture_upload_assets": 1,
    "failed_assets": 0,
    "recent_scans_checked": 250,
    "ready_video_assets_checked": 2,
    "explore_video_rows_checked": 10,
    "reconciliation_runs_checked": 5,
    "ingestion_intents_checked": 3,
    "issues": 1,
    "critical_issues": 0,
    "warning_issues": 1
  },
  "asset_breakdown": {
    "stale_capture_upload_assets": [
      { "kind": "image", "role": "display", "count": 1 }
    ],
    "failed_assets": []
  },
  "issues": [
    {
      "code": "stale_capture_upload_assets",
      "severity": "warning",
      "message": "Capture-upload media assets remain staged past the reconciliation window.",
      "count": 1,
      "sample": []
    }
  ]
}
```

The status can be `ok`, `warning`, or `critical`. Critical issues indicate a
durability invariant is already broken or a server-owned ingestion job is stuck
past its lease. Warning issues indicate retry/repair work may still complete but
should be monitored, including missing or non-resumable ingestion intents for
retryable work. The endpoint does not repair media; writers remain
`identify-multimodal`, `reconcile-scan-media-assets`, and the iOS offline queue.
The scheduled **Scan Media Health Monitor** workflow calls this endpoint every
30 minutes, stores JSON/Markdown artifacts, and fails only on `critical` by
default. The monitor's Markdown summary adds an **Incident Actions** table for
each issue code with owner, next step, runbook, and sample-field hints; use that
as the first operational response before querying individual scan/media rows.

---

## Deno `/update-public-avatar` Edge Node

Promotes one user-owned staged R2 image into the durable public avatar prefix.
The iOS Profile tab first requests a signed URL from `/generate-upload-urls`,
uploads the prepared square avatar to `staging/{userId}/...`, then calls this
endpoint.

### Request Payload

```json
{
  "r2_object_key": "staging/a1b2c3d4-e5f6-7890-abcd-ef1234567890/avatar_11111111-1111-4111-8111-111111111111.webp",
  "mime_type": "image/webp"
}
```

Rules:

- `r2_object_key` must be a string owned by the authenticated user under
  `staging/{user.id}/...`.
- Path traversal is rejected with `400`.
- Wrong-user staging keys are rejected with `403`.
- `mime_type` must be `image/webp` or `image/jpeg`, and it must also be in the
  staged image MIME allowlist.

### Response Payload

```json
{
  "avatar_url": "https://media.merian.app/avatars/a1b2c3d4-e5f6-7890-abcd-ef1234567890/22222222-2222-4222-8222-222222222222.webp"
}
```

The function copies the staged object to `avatars/{userId}/{uuid}.webp` or
`avatars/{userId}/{uuid}.jpg`, updates `users.custom_avatar_url`,
`users.custom_avatar_updated_at`, and `users.public_avatar_url`, and deletes
only the previous same-user custom avatar object. OAuth avatars remain fallback
metadata when no custom avatar exists.

---

## Community Identification Edge Nodes

Community Identification is the Ask the Community queue under Explore. It is
backed by `taxon_nodes`, `explore_community_requests`, and
`explore_identifications`, with versioned taxonomy, queued consensus jobs, and
the `explore_observation_projection` public feed boundary.

### `/request-community-identification`

Creates or reopens an Explore post as a `needs_id` community request. The
request is gated to the authenticated user's biological scan with shareable
media. It accepts `scan_id`, optional `note`, optional `location_sharing`
(`open`, `obscured`, `private`), optional `species_common_name`, and optional
`restored_object_keys`, `restored_video_object_keys`, and
`restored_audio_object_keys` for bounded media repair.

Clients attach one UUID `Idempotency-Key` and preserve it across transport,
authentication, and media-restoration retries. Newly created and existing
Explore posts use the same mandatory audio publication gate as
`share-scan-to-explore`: each audible item receives a checksum/policy-derived
child key, and a cache miss reserves `explore_audio_moderation` before provider
dispatch. The database resolves entitlement/model and applies daily plus user/IP
limits. Cache hits refund the provisional reservation. Missing quota,
entitlement, policy, provider, or moderation state fails closed and does not
replace public media.

Taxonomy resolution also completes before publication. The final relational
mutation is service-only `request_community_identification_atomically(...)`: it
locks an existing request before the exact owner scan and commits the post
metadata, complete media snapshot, and `needs_id` request together. An error at
any later request, projection-trigger, or constraint boundary restores the prior
complete post. Reopening withdrawn state resets its public-publish marker,
cached consensus, worker lease/job, and active vote generation while preserving
withdrawn identification rows as audit history. A post-level recheck at the
actual `shared_at` update also rejects an explicit share that lost a concurrent
race with new `needs_id` state.

The final RPC and the companion direct-share RPC are `SECURITY INVOKER`. Forward
migration `20260729044500_grant_atomic_explore_service_privileges.sql` grants
only their required table operation classes to `service_role`. Their existing
`EXECUTE` allowlists still exclude `PUBLIC`, `anon`, and `authenticated`, and
the forward migration grants those browser roles no new writes. A service-role
table permission failure is a deployment/catalog defect, not a reason to weaken
the routine to definer authority.

The endpoint intentionally returns `404 { "error": "Scan not found." }` when
`public.scans` has no row for the authenticated user. The iOS Insight client
handles that specific error by resolving the server `species_dictionary.id` by
scientific name and sending a bounded non-media `recovery_scan` through the
single `/check-scan-status` contract. The server defers to active/retryable
richer ingestion, permits exact structured `replay_exhausted`, and admits exact
`media_reconciliation_abandoned` only with matching composite
dead-letter/quota/media-lifecycle proof. It creates only an absent
authenticated-owner row and reloads it by owner. After status returns `found`, iOS uploads surviving eligible local
images, playback video, and standalone audio to staging and retries this
endpoint with the three category-specific restored-key arrays. This endpoint
itself does not accept `recovery_scan`; the sequence is compatibility repair
for older/interrupted drift, not the expected current multimodal success path.

Before inspecting or returning an existing active request, the endpoint repairs
any Community request on that `scan_id` whose `requested_by` no longer matches
the authenticated scan owner inside that same transaction. This covers legacy
ghost-account ownership drift and keeps the Identify Yours filter, owner-only
actions, and duplicate-request guard tied to the current account.

The response envelope is:

```json
{
  "success": true,
  "data": {
    "id": "request uuid",
    "post_id": "explore post uuid",
    "scan_id": "scan uuid",
    "status": "needs_id",
    "initial_taxon_node_id": "taxon uuid",
    "taxonomy_version_id": "taxonomy version uuid"
  }
}
```

The Edge/database boundary accepts the returned request only when `scan_id` and
`requested_by` equal the requested scan and authenticated owner after canonical
UUID case normalization. PostgreSQL emits lowercase UUID text while Apple
clients may send uppercase UUID strings; casing alone is not an identity
mismatch.

iOS also treats this `200` as candidate evidence. Decode failure, an unknown
status, `success: false`, a mismatched scan, malformed request/post/owner/taxon
UUID, invalid request timestamp, any status other than `needs_id`, or a negative
consensus count becomes `MerianError.invalidResponse`. No Community success
state is cached from that response.

### `/get-community-identification-feed`

Returns unresolved `needs_id` requests for the Identify Requests dashboard and
full **Identify requests** stack page. `limit` defaults to 30 and is capped at
100. Optional `scope` accepts `all` or `mine` and defaults to `all`; `mine`
returns unresolved requests created by the authenticated viewer. Optional
`group` accepts `all`, `plants`, `birds`, `insects`, `fungi`, `mammals`, or
`reptiles_amphibians`. Requests and Activity share the same lineage-backed
classifier.

Optional `latitude` and `longitude` must be supplied together and sort local
public-coordinate requests first, followed by recent requests. Cursor fields
`before_requested_at` and `before_request_id` must also be supplied together.
Rows may include `taxonomy_version_id`, `projection_state`,
`consensus_processing_state`, `request_group`, and ordered `media_items`. The
iOS dashboard explicitly requests 12 rows; the complete feed explicitly
requests 30.

### `/get-community-identification-activity`

Returns privacy-filtered, community-wide Identify activity. Optional `scope`
and `group` use the same values as the request feed, so `mine` means activity
for requests created by the authenticated viewer rather than activity performed
by that viewer. `limit` defaults to 30 and is capped at 100. The paired cursor
fields are `before_activity_at` and `before_activity_id`; ordering is
deterministic by `(activity_at DESC, activity_id DESC)`.

The authenticated JSON request is:

```json
{
  "limit": 10,
  "scope": "mine",
  "group": "birds",
  "before_activity_at": "2026-07-30T19:00:00.000Z",
  "before_activity_id": "00000000-0000-4000-8000-000000000002"
}
```

The cursor fields are optional, but supplying only one returns `400`. Unknown
scope/group values, malformed cursor timestamps, and malformed cursor UUIDs
also return `400`. `limit` follows the shared Explore policy: finite numbers
are floored and clamped to `0...100`; missing or nonnumeric values use 30.

The success envelope is:

```json
{
  "data": [
    {
      "activity_id": "00000000-0000-4000-8000-000000000010",
      "activity_type": "suggestion_burst",
      "request_id": "00000000-0000-4000-8000-000000000011",
      "post_id": "00000000-0000-4000-8000-000000000012",
      "scan_id": "00000000-0000-4000-8000-000000000013",
      "hero_image_url": "https://media.example/request.jpg",
      "activity_at": "2026-07-30T20:00:00.000Z",
      "suggestion_count": 3,
      "recent_actor_names": ["Explorer A", "Explorer B"],
      "taxon_id": "00000000-0000-4000-8000-000000000014",
      "taxon_common_name": "White-tailed Eagle",
      "taxon_scientific_name": "Haliaeetus albicilla",
      "taxon_rank": "species",
      "consensus_score": 0.78,
      "request_group": "birds",
      "media_items": []
    }
  ]
}
```

Items have type `suggestion_burst`, `consensus_changed`, or `resolved`.
Suggestions on one request lifecycle chain into the same burst when each
suggestion is no more than 60 minutes after the prior suggestion, including the
exact 60-minute boundary. A burst returns its visible suggestion count and up to
three most recent distinct visible actor names. Consensus caused by a suggestion
is folded into the burst's latest taxon metadata. Consensus without a new
suggestion is standalone, and resolution is always a separate immutable
milestone.

The Edge Function is the only client entry point. Its RPC and internal
projection are granted to `service_role` only; `PUBLIC`, `anon`, and
`authenticated` cannot invoke or read them directly. Reads apply the same
request visibility, blocking, shadowban, tombstone, unshare, moderation, media
health quarantine, and active-media rules as Identify. Actor names are resolved
from visible users at read time and are not stored in the projection. A
suggestion burst with no actors visible to the viewer is omitted. Fetching this
feed does not read or mutate bell unread state.

`config.toml` deliberately uses `verify_jwt = false` for this route because the
repository owns JWT verification inside `withEdgeHandler`/`requireAuth`.
Anonymous-session and authenticated user JWTs are still required; the setting
does not make the endpoint public. The handler derives `self_id` from the
verified user and never accepts it from the request body, then calls
`public.get_community_identification_activity(...)` through its service-role
client.

The route-local implementation, verification, and compatibility deployment
guide is
[`services/supabase/functions/get-community-identification-activity/README.md`](../../services/supabase/functions/get-community-identification-activity/README.md).

### `/get-community-identification-detail`

Returns one visible request with author identity, current consensus state,
privacy-safe location fields, and the full identification timeline. Tombstoned
scans, unshared posts, blocked relationships, and shadowbanned authors are
filtered out server-side. Identification timeline rows include a computed
`role_label` such as `supporting`, `leading`, `maverick`, or `withdrawn` for
internal consensus/audit behavior; clients should not expose these labels as
user-facing copy. The response also includes additive `suggested_taxa` for the
Suggest ID sheet and the detail header card. The top-level `inference_tier`
mirrors `scans.inference_tier` so clients can label the card as Naturebook Pro
or Naturebook Flash; missing or unknown tiers should display as Flash. The first
suggestion is the request's `ai_initial` taxon, hydrated from the backing scan's
`ai_confidence_score` and `ai_reasoning` so clients can frame it as Merian's
starting identification without borrowing human consensus or alternative
candidate copy. Confidence is optional and should render as compact card
metadata only when present; reasoning remains collapsed behind the AI reasoning
row. Additional `ai_candidate` suggestions come from resolvable
`scans.candidates` entries in the request's pinned taxonomy version. Suggested
taxa use the same taxon fields as search results and may include
`suggestion_source`, `confidence_score`, and `distinguishing_feature`; for
`ai_initial`, `distinguishing_feature` carries the scan's primary AI reasoning.

Example `suggested_taxa` shape:

```json
[
  {
    "taxon_id": "taxon uuid",
    "taxonomy_version_id": "taxonomy version uuid",
    "common_name": "Sweet Orange",
    "scientific_name": "Citrus sinensis",
    "rank": "species",
    "path": "plantae.tracheophyta.angiosperms.sapindales.rutaceae.citrus.citrus_sinensis",
    "species_id": "species uuid",
    "suggestion_source": "ai_initial",
    "confidence_score": 0.82,
    "distinguishing_feature": "The glossy evergreen leaves and citrus fruit shape support Sweet Orange."
  },
  {
    "taxon_id": "alternative taxon uuid",
    "taxonomy_version_id": "taxonomy version uuid",
    "common_name": "Mandarin Orange",
    "scientific_name": "Citrus reticulata",
    "rank": "species",
    "path": "plantae.tracheophyta.angiosperms.sapindales.rutaceae.citrus.citrus_reticulata",
    "species_id": "alternative species uuid",
    "suggestion_source": "ai_candidate",
    "confidence_score": 0.61,
    "distinguishing_feature": "Similar foliage, but the visible fruit proportions are less clearly mandarin-like."
  }
]
```

### `/update-community-identification-request`

Updates the authenticated request owner’s editable request info. Accepts
`request_id`, optional `note`, and required `location_sharing` (`open`,
`obscured`, `private`). The backend only updates non-withdrawn requests owned by
the current user and also updates the backing Explore post’s `location_sharing`.

### `/search-community-taxa`

Searches `taxon_nodes` through `taxon_names` by scientific name, common name, or
synonym. Local index search runs first. If results are thin and the query is at
least three characters, the Edge function asks GBIF for additional suggestions,
caches them into the active Community Taxonomy Index, and searches again. GBIF
failures do not block local results. Accepts optional `taxonomy_version_id`;
request detail searches should pass the request's pinned version.

Rows return `taxon_id`, `taxonomy_version_id`, `common_name`, `scientific_name`,
`rank`, `path`, `species_id`, `gbif_taxon_key`, `source`, `is_in_dictionary`,
`accepted_gbif_taxon_key`, and `taxonomic_status`. `species_id = null` is valid
for GBIF-only taxa that have not been materialized into Merian's enriched
Dictionary yet. The Swift client uses `path` to decide whether a selected ID is
exact, descendant, ancestor, or conflicting before presenting any disagreement
sheet.

### `/submit-community-identification`

Accepts `request_id`, `taxon_id`, optional `disagreement_mode`, optional
`reasoning`, and optional `is_genus_best_possible`. The backend validates that
the taxon belongs to the request's pinned taxonomy version, withdraws the
current user's previous active ID, inserts a new audit row, enqueues a consensus
job, and attempts one immediate best-effort processing pass. Consensus rules are
unchanged: active human IDs only, at least two identifications, score strictly
greater than `2 / 3`, sibling/unrelated votes counting against a candidate, and
coarse ancestor IDs staying neutral unless explicitly marked as disagreement.
Species consensus resolves immediately; genus consensus resolves only when at
least one exact genus ID marks genus as best practical.

### `/withdraw-community-identification` and `/restore-community-identification`

Accept `identification_id` and mutate only the authenticated user's own rows.
Withdraw and restore keep the audit trail intact, enqueue consensus work, and
attempt immediate best-effort processing.

### `/refresh-taxonomy-nodes`

Internal service-role endpoint. Rebuilds a draft taxonomy version from
`species_dictionary`, seeds `taxon_names`, activates the version atomically, and
retires the previous Merian dictionary version. Optional body:

```json
{ "source_revision": "species-dictionary-2026-06-20" }
```

### `/sync-community-taxonomy-index`

Internal service-role endpoint. Imports bounded GBIF taxonomy pages into the
active Community Taxonomy Index without materializing `species_dictionary` rows.
v1 supports only the `birds` target, which maps to GBIF taxon key `212` (`Aves`)
and imports accepted species through GBIF species search.

Optional body:

```json
{
  "target": "birds",
  "offset": 0,
  "limit": 50,
  "page_count": 1,
  "dry_run": false,
  "refresh_coverage": true,
  "retry": false
}
```

`limit` is capped at `200` and `page_count` is capped at `20`. If `offset` is
omitted, the worker continues from
`taxonomy_coverage_targets.next_import_offset`; explicit offsets remain
available for manual recovery. `retry = true` with no explicit offset replays
the last failed offset when present, otherwise the last successfully imported
page offset. Each successful page calls `upsert_gbif_community_taxa(...)`,
annotates the created `taxonomy_import_runs` row as
`scope = "gbif_bounded_birds"`, and suppresses per-page coverage recomputation.
After the run imports at least one row, the worker refreshes coverage once when
`refresh_coverage = true`, then updates the target cursor fields.
`dry_run = true` fetches and normalizes the GBIF page without writing taxonomy
rows or advancing the cursor.

### `/process-community-consensus-jobs`

Internal service-role endpoint. Processes pending or retryable failed
`community_consensus_jobs`. Optional body:

```json
{ "limit": 25 }
```

---

## Deno `/identify` Edge Node

### The JSON Request Payload (From Swift `OfflineQueueManager`)

When `NWPathMonitor` goes green, iOS POSTs this payload to Supabase. The server
enforces that all paths within `r2ObjectKeys` begin with `staging/${user.id}/`
and rejects `../` traversal attempts with `HTTP 400`.

The endpoint rejects media JSON requests whose declared `Content-Length` exceeds
the shared `/identify` body ceiling before parsing the body. The body is then
parsed through `_shared/mediaBudgets.ts` using `readRequestJsonWithinBudget`,
making the streaming byte counter authoritative for chunked or missing-length
requests. Inline `imageBase64s` are validated against the shared aggregate
base64 budget; staged `r2ObjectKeys` are validated through
`_shared/identify/media.ts` and R2 bytes are consumed with capped stream readers
before any full response buffer is assembled.

### AI authorization and idempotency

Every authenticated route that can dispatch paid model work uses the same
database boundary. Clients should send a UUID `Idempotency-Key`; scan routes use
the exact `client_scan_id`, and chat sends use `client_message_id`. A validated
body request ID takes precedence over the header. The iOS network layer
preserves the same key across transient transport, auth-refresh,
missing-session, and `5xx` retries.

Before provider dispatch, `reserve_ai_quota` atomically verifies entitlement,
selects the operation's database policy/model, and consumes daily/user/IP
counters. Reusing a key for a `reserved` or `committed` attempt does not consume
or dispatch again: the API returns `409 ai_request_in_progress` or
`409 ai_request_already_completed`. A previously explicit `refunded` key may be
reserved again. `reserved` attempts carry a ten-minute lease; abandoned leases
are automatically refunded, and every retry receives a new fencing token so a
late settlement from an earlier attempt is rejected. A provider error changes
`committed` to `failed`: the original counters remain charged, but the same key
may begin a newly metered attempt. This reservation protects cost idempotency;
by itself it does not promise to replay a prior HTTP response body. The
scan-specific durable replay contract below absorbs these quota conflicts when
safe completion evidence exists.

Terminal reservations ordinarily prune after 30 days. Exact failed/committed
normal and replay scan reservations remain retained as chronological authority
only while the corresponding owner/scan job is unresolved
`failed_terminal / media_reconciliation_abandoned`. Refunded and unrelated
states retain ordinary retention, and successful recovery or explicit operator
resolution ends the exception.

### Scan response replay

`/identify-multimodal`, `/identify`, `/identify-describe`, and `/audio-spec` use
the canonical scan UUID as both the response identity and paid-provider request
identity. Before resolving staged media or reserving quota, each route loads
`scan_ingestion_jobs` by both `scan_id` and authenticated `user_id`. A
`complete` job with its owner scan returns `200` and
`X-Merian-Idempotent-Replay: stored|reconstructed`.

Migration `20260728220000_persist_idempotent_scan_responses.sql` makes current
completions persist the executable-contract-validated success envelope inside
the same transaction that proves scan/media completion. Persistence is immutable
for that generation and excludes raw media bytes. Older complete jobs without an
envelope reconstruct a conservative valid response from the exact owner scan and
species summary. Deletion-request and owner-removal triggers clear the stored
response.

If quota reports the same scan UUID as in progress or already completed, the
route waits up to 70 seconds for the original invocation to reach that boundary
and then replays success. It never makes a second provider call. Only an
unresolved or malformed completion may fall back to the stable `409`; current
iOS retains the queued scan and shows **Restoring scan** rather than a network
timeout for the four exact replay codes.

Shared authorization errors are:

| Status | Code                                                        | Meaning                                                                                    |
| ------ | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `400`  | `ai_request_id_invalid`                                     | Supplied body/header request key is not a UUID                                             |
| `402`  | `pro_required`                                              | Operation is disabled for the effective plan                                               |
| `409`  | `ai_request_in_progress` / `ai_request_already_completed`   | Duplicate paid-provider attempt; an in-progress response retries after the remaining lease |
| `429`  | `ai_quota_daily_exceeded`                                   | Database UTC-day safety ceiling reached                                                    |
| `429`  | `ai_user_rate_limit_exceeded` / `ai_ip_rate_limit_exceeded` | Shared minute ceiling reached                                                              |
| `503`  | `ai_entitlement_unavailable` / `ai_quota_unavailable`       | Durable authorization could not be verified                                                |

Rate-limit and temporary entitlement responses may include both the
`Retry-After` header and `retry_after_seconds` JSON field. Clients must not
silently fall back to a paid tier or alternate model on any of these failures.

> **Important IDOR Constraint:** The `user.id` resolved by the Deno Edge
> Function from the Supabase JWT is always a **lowercase** Postgres UUID format.
> Swift's `UUID().uuidString` evaluates to uppercase by default. Therefore, the
> iOS client must explicitly lowercase any user UUID injected into
> `r2ObjectKeys` payloads; otherwise, the case-sensitive string matching
> (`!r2ObjectKey.startsWith`) will fail the IDOR check and return a
> `403 Forbidden`.

```json
{
  "r2ObjectKeys": [
    "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_filename_1.webp",
    "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_filename_2.webp"
  ],
  "imageBase64s": [
    "<base64 encoded string array for instant processing within the shared aggregate budget>"
  ],
  "user_id": "Supabase Auth UUID linking via GoTrue Session",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "depthScaleText": "1.2 meters",
  "semanticLocation": "Zilker Park",
  "publicLocationLabel": "Austin, Texas",
  "geoprivacy": "obscured",
  "weatherCondition": "Sunny",
  "weatherTemperatureF": 72.5,
  "deviceLocale": "en",
  "deviceTimeZone": "America/Los_Angeles",
  "deviceRegion": "US",
  "currentMonth": 3,
  "timeOfDay": "2:00 PM",
  "timestamp": "2026-03-21T09:46:03.000Z",
  "zoomFactor": 2,
  "estimated_size_cm": 15.2,
  "description": "Small brown moth, roughly 2 cm wingspan, spotted resting on bark at night",
  "observation_context": {
    "organism_class": "Insect",
    "colors": ["brown", "grey"],
    "size": "small",
    "habitats": ["woodland", "garden"],
    "behaviors": ["resting", "nocturnal"],
    "markings": "subtle eyespot pattern on forewings",
    "textures": "dusty wing scales",
    "free_text": "Found near porch light after dark"
  }
}
```

`description` is an optional plain-text string generated client-side by
`ObservationContext.serialized()` — a pre-rendered prompt summary of the user's
structured observation. It is appended to the Gemini context string at the edge
function to ground identification before the vision model runs.
`observation_context` is the full structured JSON object matching the iOS
`ObservationContext` model; it is persisted server-side as
`public.scans.user_observation_context` (JSONB) and lands in the local
mixed-media scan representation via `LocalScanRecord.observationContextsJSON`,
the scalar `capturedMediaJSON` timeline, and the V41 `capturedMediaEntries`
relationship mirror. Both fields are `null` for image-only scans. The edge
function accepts an array guard (`!Array.isArray(observation_context)`) before
writing to prevent an accidental array submission from being persisted as
malformed JSONB.

`zoomFactor` is sent when the capture used a non-default camera zoom. The Edge
function persists it to `public.scans.zoom_factor` for owner-facing context such
as Insight scan information and Field chat; it is omitted for 1x captures and
non-visual submissions.

`currentMonth` and `timeOfDay` are derived from the image's own capture date
(`telemetry.timestamp`) when available — not always from the current wall clock.
For gallery photos with a valid EXIF date, this ensures Gemini receives the
correct season and light context for the original photo (e.g., an October photo
scanned in April sends `Month: 10`, not `Month: 4`). Falls back to current
date/time for live captures and gallery photos with no EXIF.

`timestamp` is omitted (null) for gallery photos with no EXIF date rather than
sending the current submission time. The server defaults `scans.timestamp` to
`now()` in that case, which honestly represents when the scan was submitted.
`deviceTimeZone` (IANA identifier, e.g. `"America/Los_Angeles"`) and
`deviceRegion` (ISO 3166-1, e.g. `"US"`) are permission-free geographic signals
sent as fallback context when GPS is not authorised. The Edge function injects
them into the Gemini context string as `TZ:` and `Region:` tokens alongside
`Locale:`, `Month:`, and `Time:` — grounding the model's regional species priors
without requiring location permission. `deviceTimeZone` is also persisted to
`scans.device_time_zone` for timezone-aware public profile streaks and heatmaps;
`deviceRegion` remains inference-context only.

`geoprivacy` is optional for backward compatibility. Valid values are `open`,
`obscured`, and `private`. When absent or invalid, the Edge insert helper reads
`users.default_geoprivacy`. Private scans may still persist exact owner-owned
telemetry, but public projections are scrubbed: public coordinates,
`coordinate_uncertainty_in_meters`, and `public_location_label` are cleared by
insert helpers and database triggers. Current iOS clients omit
`publicLocationLabel` when `geoprivacy == "private"` and send sanitized labels
for open/obscured scans.

### The JSON Response Schema (From Gemini Back to Swift)

To optimize API expenditures, the `identify` Deno Edge node uses two strategies:

- **Model Routing**: The vision identification call routes effective Pro users
  to `gemini-2.5-pro` (maximum depth for rare species, fossils, subspecies, and
  cultivars) and effective free users to `gemini-2.5-flash` (2–3× lower
  latency). Effective Pro includes paid subscribers and dynamic 7-day trial
  users. The server does not trust an iOS tier hint. It atomically calls
  `reserve_ai_quota` before provider work; that transaction resolves the durable
  plan and expiry, selects an allowlisted model from
  `internal.ai_quota_policies`, and consumes daily/user/IP counters under the
  request idempotency key. Text-only enrichment currently selects
  `gemini-2.5-flash` through the same database policy. A missing user row,
  entitlement query failure, disabled/missing policy, or unsupported model fails
  closed before Gemini. Both identification models use the structured schema
  generated from `merianModelContract`.
- **Conditional biological fields**: The static executable contract makes
  biological-only fields optional and nullable. The prompt requires them to be
  omitted for non-biological subjects; the runtime parser and processed-material
  guard then enforce the safe boundary. **Geology Bypass**: Gemini's prompt
  explicitly instructs the LLM to output `scientific_name` and `common_name` for
  identifiable geological subjects despite `is_biological_subject=false`. This
  surfaces rocks cleanly in the iOS layer while routing them out of the main
  biological dictionary.

The canonical source for every model and final response key is
`services/supabase/functions/_shared/identify/contract.ts`. It generates the
provider schema and Swift wire DTO block, infers the deployed TypeScript
payloads, and recursively validates live values. Provider output is validated
immediately after JSON syntax extraction. After name sanitization, cache
hydration, candidate enrichment, and server-added fields, the complete
`{ "success": true, "data": ... }` envelope is validated again before
persistence or HTTP success.

Successful Identify responses always contain `blur_score`, `colors`,
`candidates` (nullable), `estimated_size_cm` (nullable), `image_quality`, and
`pet_identification` (nullable); the contract rejects an omitted key even though
generated root Swift properties remain optional for staggered rollout
compatibility. The Describe model contract also rejects `is_live_capture=true`
and nonzero image-quality values.

For an intentional response change, edit the executable contract, run
`make generate-edge-dto-contract`, review the generated
`InferenceEdgeDTOs.swift` diff, and run `make validate-edge-dto-contract`. Do
not hand-edit or extend a generated wire DTO. The final server contract is
strict; generated root Swift properties are optional only to support older
cached payloads and staggered rollout.

> **Image format**: All images in this pipeline are encoded as lossy **WebP**
> (`image/webp`). The `inlineData.mimeType` field passed to the Gemini SDK in
> `index.ts` must always be `"image/webp"`. Gemini 2.5 Flash and Pro both accept
> `image/webp` natively. If this value is changed to `image/jpeg` while the
> actual bytes are WebP, Gemini will reject or misinterpret the payload.

**`common_name` source**: On **Cache Miss** (first-ever scan of a species),
`common_name` is taken directly from the Gemini vision model output. On **Cache
Hit**, `index.ts` overrides the Gemini-supplied `common_name` with the canonical
`species_dictionary.common_names.en` value so repeat scans of the same species
always show a consistent display name regardless of which Gemini response
generated it. Cache-miss writes preserve an existing `common_names.en` and only
fill it from the scan when the dictionary row does not already have an English
name, preventing a single malformed scan label from overwriting canonical
species naming. The Swift decoding layer applies `.capitalized` on rendering for
display consistency. For geological targets, it relies wholly on the Gemini
output (no cache override applies).

**`pet_identification` source**: Dog and cat scans may include a separate
display object when the primary species is `Canis lupus familiaris` or
`Felis catus`. This object is not taxonomy. It is sanitized after Gemini
generation and dropped when the label is generic, below `0.70` confidence, or
attached to any non-dog/cat taxon. Dog labels may be a breed or visible mix; cat
labels prefer visible coat pattern or body type unless a true breed is visually
supported. Clients can use the label for Insight, search, sharing, and Explore
display, while `common_name` and `scientific_name` remain authoritative.

**`is_new_to_merian_dictionary` source**: The biological identify routes
(`/identify`, `/identify-multimodal`, `/identify-describe`, and `/audio-spec`)
return this boolean in the client payload. It is `true` only when the scan is a
biological subject and the initial `species_dictionary` lookup found no existing
row for the normalized scientific name. iOS decodes the field as
`SpeciesData.isNewToMerianDictionary` and uses it to show the bottom in-app
`New to Naturebook` milestone notification. Do not infer global dictionary
novelty from missing enrichment fields such as `alternative_common_names`; cache
gaps, GBIF gaps, and partial rows are not milestone signals. Existing dictionary
rows with incomplete taxonomy/enrichment are still treated as not new to the
Naturebook dictionary.

**Processed-material guardrail**: The identify routes demote manufactured or
processed objects to `is_biological_subject=false` before cache lookup,
dictionary upsert, candidate enrichment, or milestone evaluation. Wool rugs,
kilims, leather goods, wooden furniture, paper/cardboard, cotton or linen
fabric, prepared food, toys, artwork, ornaments, and species depictions are not
biological observations even when made from biological material. The response
keeps the object `common_name` when useful for the non-biological result, clears
source-species `scientific_name`, strips candidates, and never sets
`is_new_to_merian_dictionary`. iOS also treats `is_biological_subject=false` as
authoritative during decode, forcing `SpeciesData.isNewToMerianDictionary=false`
and `SpeciesData.candidates=nil` even if a stale or malformed Edge response
includes those fields.

Processed-material response shape:

```json
{
  "scan_id": "Generated via crypto.randomUUID() on Deno Edge",
  "is_biological_subject": false,
  "is_live_capture": false,
  "is_new_to_merian_dictionary": false,
  "common_name": "Wool Kilim Rug",
  "scientific_name": null,
  "confidence_score": 0.82,
  "candidates": null,
  "insight_data": {
    "ai_reasoning": "The subject is an inanimate, man-made textile rather than an organism.",
    "hazard_type": "none"
  }
}
```

Operational cleanup for historical pollution is intentionally manual. Use
`services/supabase/scripts/repair_processed_material_scan_pollution.ts` in dry
run first; apply mode only patches rows whose scan evidence explicitly contains
artifact/process terms and then nulls scan species links, marks the scan
non-biological, clears biological metadata, and restores/removes polluted
dictionary English names.

**Critical Edge Limitation (Gemini 2.5):** The model returns `400 Bad Request`
when enum fields include descriptive strings. `ecology_type` must be formatted
as a structural JSON `enum: ["wild", "urban", "domesticated", "unknown"]`
constraint in the Deno schema.

```json
{
  "scan_id": "Generated via crypto.randomUUID() on Deno Edge",
  "is_biological_subject": true,
  "is_live_capture": true,
  "is_new_to_merian_dictionary": false,
  "ecology_type": "wild",
  "scientific_name": "Danaus plexippus",
  "common_name": "Monarch Butterfly",
  "pet_identification": null,
  "confidence_score": 0.98,
  "blur_score": 0.1,
  "is_invasive": false,
  "invasive_status_region": "Central Texas",
  "invasive_rationale": "The original AI assessment did not flag this species as invasive for the scan region.",
  "invasive_confidence": 0.78,
  "colors": ["orange", "black", "white"],
  "estimated_size_cm": 15.2,
  "life_stage": "adult",
  "reproductive_condition": "not_applicable",
  "sex": "female",
  "sex_confidence": 0.84,
  "sex_evidence": "dimorphic wing pattern",
  "individual_count": 1,
  "ecological_interactions": ["pollinating Asclepias syriaca"],
  "extracted_visual_traits": [
    "orange and black wing pattern",
    "white-spotted margins",
    "ventral silver spots"
  ],
  "insight_data": {
    "ai_reasoning": "The distinctive orange and black wing pattern with white-spotted margins, combined with the milkweed habitat context, is diagnostic for Danaus plexippus. The ventral hindwing silver spots confirm this is not the mimicking Viceroy.",
    "hazard_type": "none"
  },
  "// Cache Hit only — sourced from species_dictionary:": "",
  "wikipedia_url": "https://en.wikipedia.org/wiki/Monarch_butterfly",
  "wikipedia_overview": "The monarch butterfly or simply monarch is a milkweed butterfly in the family Nymphalidae...",
  "reference_image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Monarch_In_May.jpg/320px-Monarch_In_May.jpg",
  "taxonomy": {
    "kingdom": "Animalia",
    "phylum": "Arthropoda",
    "class": "Insecta",
    "order": "Lepidoptera",
    "family": "Nymphalidae",
    "genus": "Danaus"
  },
  "iucn_red_list_status": "least_concern",

  "// Cache Hit, all tiers — sourced from species_dictionary (REST, not AI-generated):": "",
  "gbif_taxon_key": 5130978,

  "// Cache Hit, all tiers — sourced from species_dictionary:": "",
  "species_insights": {
    "habitat_description": "Frequently spotted in milkweed patches, meadows, and open plains."
  },

  "// Cache Hit — sourced from species_dictionary.alternative_common_names (populated from GBIF vernacular names on first enrichment):": "",
  "alternative_common_names": ["Monarch", "Common Tiger"],

  "// Present when confidence_score < diagnosticTrigger (0.99 both Flash and Pro — intentionally above strong threshold so Strong match scans can still persist candidates as an escape hatch). Server strips to null at or above 0.99. Client display is separately gated by CandidateReviewVisibilityPolicy. See _shared/identify/thresholds.ts.": "",
  "candidates": [
    {
      "scientific_name": "Limenitis archippus",
      "common_name": "Viceroy",
      "confidence_score": 0.71,
      "distinguishing_feature": "Hindwing black postmedian band broader and more irregular than Monarch"
    },
    {
      "scientific_name": "Danaus gilippus",
      "common_name": "Queen",
      "confidence_score": 0.58,
      "distinguishing_feature": "Forewing lacks white spots in the black apex band"
    }
  ]
}
```

> **Vision schema lean principle**: The vision model response (`identify`) is
> optimised strictly for identification and ecosystem measurement.
> Data-as-a-Service fields (`estimated_size_cm`, `life_stage`,
> `reproductive_condition`, `sex`, `sex_confidence`, `sex_evidence`,
> `individual_count`, `ecological_interactions`) are fully generated on the
> primary pass avoiding secondary inference loops. `extracted_visual_traits`
> executes a Micro-CoT pass before taxonomic grouping to anchor the model to
> reality and avoid visual pareidolia. `insight_data.ai_reasoning` is always
> present for biological subjects because it is the Gemini vision model's
> per-scan reasoning about the specific photo submitted. LLM field caps are
> declared in the structured model contract and enforced again in `index.ts`
> after scientific name sanitization. All model `NUMBER` fields use explicit
> `0...1` bounds. Image-quality integer bounds are `1...10` for `sharpness`,
> `framing`, and `diagnostic_utility`, and `0...100` for `overall_score`;
> `individual_count` is `1...99999`. The DTO deployment validator requires
> finite bounds for every numeric schema before accepting the corresponding
> Swift wire type. Runtime caps remain defense in depth: `colors`,
> `extracted_visual_traits`, and `ecological_interactions` are each capped at 10
> items; `ai_reasoning` is truncated to 2000 characters; `individual_count` is
> validated as a positive integer <= 99999; client-supplied `estimated_size_cm`
> is validated as a positive finite number <= 50000; and `candidates` is capped
> at 5 items before `payloadReadyForClient` is built. GPS coordinates are
> range-checked and out-of-range values are sanitized to `null` rather than
> aborting identification. `taxonomy`, `iucn_red_list_status`, `gbif_taxon_key`,
> `species_insights`, and `alternative_common_names` are species-dictionary
> cache fields, not scan-specific model output. `similar_species` is never
> included in the `identify` response; it is generated asynchronously by
> `/enrich-scan`, and iOS renders validated entries with the stable "Similar
> species" label. `hazard_type` inside `insight_data` comes from
> `species_dictionary` on Cache Hit; on Cache Miss the live response defaults to
> `"none"` until later enrichment fills species-level hazard metadata.
> `pet_identification` is optional and nullable. For a confident dog scan, the
> value may look like
> `{"species_group":"dog","label":"Australian Cattle Dog mix","label_type":"breed_mix","confidence_score":0.82,"evidence":["blue-roan ticking","black saddle patch","compact herding-dog build"]}`.
> The stored species would still be `Domestic Dog` / `Canis lupus familiaris`.
>
> `candidates` is required in `merianModelContract`; biological subjects are
> instructed to return exactly 2 alternatives, while non-biological subjects
> return an empty array. The identify routes strip candidates to `null` when
> `confidence_score >= diagnosticTrigger` (`0.99` for both Flash and Pro),
> preserving candidates for Possible, Weak, and Strong biological scans below
> that near-certain threshold. Non-biological and processed-material results are
> stripped to `null` regardless of confidence. Candidates are scan-specific and
> persist to `public.scans.candidates` plus `LocalScanRecord.candidatesData`,
> while client display is separately gated by `CandidateReviewVisibilityPolicy`.
>
> **Executable validation**: Numeric bounds, enums, nested required fields,
> nullability, safe-integer semantics, string lengths, and array cardinalities
> above are enforced by the Edge runtime, not only documented in the provider
> schema. Unknown provider/server keys follow the contract's explicit strip
> policy. A malformed provider object returns retryable HTTP `503`. If the final
> server-enriched envelope violates its wire contract, the route returns HTTP
> `502` with stable code `identify_response_invalid` before persistence or
> client delivery.

### Durable Ingestion & Media Moderation

For `/identify-multimodal`, the route completes the owner-row durability work
before returning HTTP `200 OK`. A successful response therefore guarantees the
returned `scan_id` is available to Field Chat, Explore sharing, field trips, and
owner sync. The durability task handles:

1. **Scan-user profile prerequisite** — calls service-only
   `ensure_scan_user_profile(authenticated_user_id)` before the `scans` FK
   insert. An existing profile is unchanged. A missing profile is created only
   for the exact Auth identity with canonical mandatory public-identity fields;
   account deletion, merged-ghost retirement, and cleanup races fail closed.
2. **Content moderation** (`_shared/identify/moderation.ts`) — evaluates Gemini
   safety ratings and promotes media from staging to public storage
3. **Species dictionary enrichment** (Cache Miss only) — calls
   `fetchExternalEnrichment` for Wikipedia/GBIF data
4. **`insertScan`** — writes the final scan row to `public.scans`, including
   sanitized `pet_identification` when present
5. **Owner read-back** — reloads by `scan_id` and authenticated `user_id`;
   duplicate no-op or cross-owner collision cannot be reported as success
6. **Optional post-insert work** — schedules analytics, group tags, and
   candidate enrichment through `EdgeRuntime.waitUntil`

**Media promotion**: Safe image media is moved from
`staging/{userId}/{filename}` to `public_uploads/{tier}/{userId}/{filename}`
inside Cloudflare R2, and the CDN URL
(`https://media.merian.app/public_uploads/...`) is stored in
`scans.image_storage_urls`. For the `imageBase64s` path, the bytes are uploaded
directly to the public destination without a staging step, and `r2ObjectKeys` is
empty: only genuine staged sources belong in the strict ingestion/promotion
manifest. Safe video media is moderated through five sampled frames, then the
staged upload-bounded playback `.mp4` is promoted separately and persisted in
`scans.video_storage_urls`. Multimodal inserts also write
`scans.captured_media`, a canonical ordered media timeline that attaches video
playback URLs and poster thumbnails together; this prevents sampled video
inference frames from hydrating as standalone Insight carousel images. The
required finalization transaction refreshes ready display/playback scan-media
asset rows and proves the canonical representation before ledger completion, so
server-side composer/status reads can prefer lifecycle media rows before falling
back to compatibility arrays. Any image promotion failure aborts the entire
batch and immediately rolls back any already-promoted public objects from that
same batch before returning `ERROR`; scans are not inserted with partial image
arrays. Video promotion failure is also a durability failure for video captures:
the edge cleans up promoted objects/staging where possible and does not insert a
frame-only scan row.

Canonical proof does not reinterpret sampled video inference frames as
standalone user images. After migration
`20260729012153_fix_video_scan_canonical_finalization.sql`, the finalizer
validates the structured captured-media visual timeline when usable; legacy
video rows validate only the standalone image prefix
`max(images - videos × 5, 0)`, every playback video, and standalone audio. Each
projected item must still have a ready normalized row matching the exact scan
owner, kind, and URL. A missing playback row, real standalone image row, audio
row, promoted capture mapping, or claimed storage disposition still fails the
request before completion and before a fresh HTTP `200`.

**Moderation failure handling**: If Gemini's `finishReason === "SAFETY"` or any
`safetyRating.probability` is `"MEDIUM"` or `"HIGH"`, the staging object is
deleted, `users.abuse_strikes` is incremented, and the scan is not inserted. At
3+ strikes `users.is_shadowbanned` is set to `true`; public/social projections
exclude that author. The flag is not currently a blanket veto for every later
safe private scan insert. The rejected current multimodal request returns
generic `400 observation_rejected` rather than a successful phantom scan. See
[Safety & Moderation](../development-guides/10-safety-and-moderation.md) for
full details.

**R2 rollback**: A returned scan-insert rejection is followed by an exact
`(scan_id, user_id)` read. Public objects are deleted through
`deleteR2ObjectIfPresent` only when that read definitively proves the owner row
is absent. A thrown/lost write response, a reported-success response without a
verifiable owner row, or unavailable verification is
`ScanPersistenceOutcomeUnknownError`: the route returns retryable HTTP 503 but
does not fail committed quota, retire staged assets, or delete promoted media
that a committed scan may reference. A same-UUID retry reconciles from the exact
owner row before another provider call. Mid-loop promotion failures still roll
back objects whose creation is known to that promotion batch.

### Error Responses

| Status | Body                                                                                                                              | Meaning                                                                                      |
| ------ | --------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `400`  | `{ "error": "Bad Request: Path traversal detected." }`                                                                            | `r2ObjectKeys` contains a `../` traversal attempt                                            |
| `400`  | `{ "error": "Forbidden: r2ObjectKey does not belong to the requesting user." }`                                                   | IDOR — key does not belong to the authenticated user                                         |
| `400`  | `{ "error": "AI processing error. Please try again." }`                                                                           | Permanent content policy failure (`finishReason` is `SAFETY` or `PROHIBITED_CONTENT`)        |
| `400`  | `{ "error": "We couldn’t process this observation. Please try a different photo or recording.", "code": "observation_rejected" }` | Media was rejected by the durable safety-moderation pass                                     |
| `413`  | `{ "error": "Payload Too Large: Combined images exceed 5MB limit." }`                                                             | Combined image payload exceeds 5 MB                                                          |
| `502`  | `{ "error": "AI response validation failed. Please retry.", "code": "identify_response_invalid" }`                                | Final server-enriched payload violated the executable wire contract                          |
| `503`  | `{ "error": "Processing Error: Malformed AI response." }`                                                                         | Gemini returned malformed or structurally invalid output; offline delivery may retry         |
| `503`  | `{ "error": "AI processing error. Please try again." }`                                                                           | Transient Gemini failure (API error, rate limit, timeout, non-SAFETY non-STOP finish reason) |
| `503`  | `{ "error": "We couldn’t finish saving this observation. Please try again.", "code": "scan_persistence_failed" }`                 | Durable moderation pipeline, media promotion, species resolution, or scan insertion failed   |

`400` on a content policy failure is intentional — the iOS `OfflineQueueManager`
treats `400` as a permanent failure and marks the queued row as needing user
attention rather than silently deleting media. All other Gemini errors return
`503` so the offline queue retries with persisted `queueNextRetryAt` /
`OfflineJobRecord.nextRunAt` metadata. For `scan_persistence_failed`, an
owner-row status probe wins first. If a readable exact-owner probe proves no
scan row exists, the server transitions the committed provider reservation to
`failed` so the stable request UUID can reserve a fenced metered retry, while
iOS clears potentially consumed staged keys and performs a fresh upload from
durable local files. If the insert outcome cannot be proved, quota and media
remain fenced and intact until the next owner-row recovery. A post-insert
failure retains the committed reservation because owner-row reconstruction is
the no-provider-call recovery surface. Malformed paid-provider output is 503,
not 422, so persisted offline delivery remains retryable.

Migration `20260728232000_ensure_scan_user_profile.sql` must precede deployment
of all four scan-producing Edge bundles. It preserves the mandatory Explore
identity constraints instead of retrying the obsolete partial
`users(id, subscription_tier)` insert that production logs proved could return
503 after provider work.

## The Standardized JSON Return Payload (From Supabase to Swift)

The compatibility `/identify` Edge Function resolves the canonical `scan_id`
from the client idempotency UUID and does not return `data` when Gemini alone
finishes. Profile repair, required media promotion, exact-owner scan insertion,
and complete-last response finalization are attempted and awaited in the
required task. A pre-insert failure returns retryable 503. If only finalization
or bookkeeping fails after exact-owner insertion, the compatibility route may
return its already validated response from that durable owner-row surface while
the ledger remains retryable for no-provider-call reconciliation. Only
analytics, group tags, candidate enrichment, and other nonessential work may run
behind `EdgeRuntime.waitUntil`. Current app traffic uses `/identify-multimodal`;
a fresh provider-owning invocation additionally requires completed canonical
finalization before its initial HTTP success. A later request may return
`X-Merian-Idempotent-Replay: reconstructed` from the exact owner row while the
canonical ledger remains retryable, without another provider call. Both routes
make the same non-negotiable owner-row durability promise.

### Gemini Parsing and Error Mitigation

To prevent ReDoS from hallucinated markdown payloads, the endpoint parses raw
Gemini output using a `substring(indexOf)` approach rather than unbounded regex.
If extraction or executable provider validation fails, the endpoint returns HTTP
503 and marks the exact ingestion generation retryable. The iOS offline queue
therefore retains and backs off the durable job instead of classifying a paid
transient/provider-format failure as terminal.

> **Note on Wikipedia Extraction:** During a "Cache Miss" (first discovery
> globally), the Edge Router fires the Wikipedia HTTP extraction _concurrently_
> alongside Gemini Text Inference latency via a `Promise.all` envelope. This
> guarantees high-resolution encyclopedia metadata maps directly to the user
> natively on the very first roundtrip without requiring the iOS app to skeleton
> load.

```json
{
  "success": true,
  "data": {
    "is_biological_subject": true,
    "ecology_type": "wild",
    "scientific_name": "Danaus plexippus"
  }
}
```

This data contract maps into the Swift Codable layer where nested JSON `Data` is
verified to prevent `JSONDecoder()` failures on double-escaped strings.

```swift
struct IdentifyResponse: Codable {
    let success: Bool
    let data: SpeciesData?
    let error: String?
}
```

**Client Authentication Caveat**: `MerianNetworkClient` abstracts GoTrue
anonymous hardware tokens. The backend extracts cryptographic JWT identity from
the `Authorization: Bearer` header via `supabaseAdmin.auth.getUser()`, ignoring
any `user_id` in the request body. The Swift payload uses the
`SupabaseManager`'s active session UUID only as a proxy string for syncing
RevenueCat identifiers — actual API validation runs over GoTrue JWT verification
only.

**Offline Ghost Overwrite Protection**: Before calling
`SupabaseManager.shared.getValidAuthHeaders()`, the iOS client checks
`UserDefaults.standard.bool(forKey: "Merian_HasAuthenticatedOAuth")`. If an
authenticated user goes offline long enough for their JWT to expire, the Swift
client throws `NetworkError.invalidResponse` immediately. This prevents a guest
UUID from overwriting the user's Pro status or stranding their `.sqlite` data,
and causes `CaptureWorkspaceView` to prompt re-authentication instead.

---

## Public Species Dictionary Edge Node

The `/species-dictionary` Edge Function returns species-level dictionary data
for the standalone Species Dictionary Page, Explore Dictionary catalog, Tree of
Life canvas, and server-rendered `/species/[speciesId]/[slug]` web route. The
UUID-only web route is retained as a permanent compatibility redirect. It is
deliberately separate from both the Insight scan and Explore post-detail
contracts:

- Insight scan data can include local media, user review state, field notes, and
  per-scan AI reasoning.
- Explore detail data can include a public shared scan projection.
- Species dictionary data includes only canonical dictionary fields and
  reference imagery.

Related Explore cards are intentionally fetched afterward through the separate
authenticated `/get-explore-species-posts` contract below; they are never added
to the publicly cached dictionary payload.

The function has `verify_jwt = false` in `services/supabase/config.toml`. Detail
and catalog requests do not call `requireAuth`; they may receive normal app auth
headers from `MerianNetworkClient`, but identity is not read and must not affect
those responses. Tree mode does call `requireAuth` because the graph membership
is scoped to the signed-in user's scan library, but the returned nodes still use
only the public species projection.

A missing dictionary row may use bounded GBIF/Wikipedia enrichment to construct
a non-persisted public fallback. It never invokes Gemini. Model-backed habitat,
lookalike, and group-tag refreshes belong to authenticated quota-guarded
enrichment or service-only scheduled workers; the anonymous public route is not
an alternate provider-cost surface.

The response is built through the shared public species projection in
`services/supabase/functions/_shared/publicSpeciesProjection.ts`. That module
owns common-name fallback, alternate-name dedupe, normalized/legacy
reference-image mapping, nullable taxonomy shape, and contract tests for
private-field leaks. SQL-only Explore detail lookalikes use matching database
helpers so the same species DTO rules apply outside Deno.

### `/species-dictionary`

Request body:

```json
{
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "scientific_name": "Danaus plexippus"
}
```

Compatibility POST bodies are stream-bounded to 4 KiB before JSON decoding.

Validation rules:

- Either `species_id` or `scientific_name` is required.
- `species_id`, when present, must be a valid UUID and is preferred for lookup.
- `scientific_name`, when present, must be a string and non-empty after
  trimming.
- Internal whitespace is collapsed before lookup.
- Names longer than 160 characters return `400`.

Current response shape:

```json
{
  "schema_version": 1,
  "data": {
    "id": "uuid",
    "scientific_name": "Danaus plexippus",
    "common_name": "Monarch Butterfly",
    "content_quality": "complete",
    "alternative_common_names": [],
    "taxonomy": {
      "kingdom": "Animalia",
      "phylum": "Arthropoda",
      "class": "Insecta",
      "order": "Lepidoptera",
      "family": "Nymphalidae",
      "genus": "Danaus"
    },
    "hazard_type": "none",
    "iucn_red_list_status": "least concern",
    "wikipedia_url": "https://en.wikipedia.org/wiki/Monarch_butterfly",
    "wikipedia_overview": "The monarch butterfly is a milkweed butterfly...",
    "habitat_description": "Often found in open meadows and milkweed patches.",
    "gbif_taxon_key": 5139790,
    "group_tags": ["animal", "insect"],
    "reference_images": [
      {
        "url": "https://media.merian.app/public_uploads/...",
        "source": "merian",
        "license": "Used with permission via Naturebook",
        "attribution": "Ayla E.",
        "author_user_id": "uuid",
        "author_username": "ayla"
      },
      {
        "url": "https://upload.wikimedia.org/...",
        "source": "wikipedia",
        "license": "CC BY-SA 4.0",
        "attribution": "Example Photographer",
        "width": 1200,
        "height": 800
      },
      { "url": "https://static.inaturalist.org/...", "source": "gbif" }
    ],
    "similar_species": [
      {
        "species_id": "uuid",
        "scientific_name": "Limenitis archippus",
        "common_name": "Viceroy",
        "reference_image_url": "https://...",
        "iucn_red_list_status": "least concern",
        "reason": "Similar orange-and-black wing pattern.",
        "visual_traits": ["orange wings", "dark venation"],
        "confidence": 0.86,
        "source": "model_enrichment",
        "review_status": "unreviewed",
        "is_bidirectional": false,
        "sort_order": 0
      }
    ]
  }
}
```

`schema_version = 1` marks the current public species contract shared by
`/species-dictionary`, Explore detail similar species, and the public web
species surface. Within this version, new response keys must be additive,
existing nullable fields may remain `null`, and clients should ignore unknown
keys. A versioned endpoint path should be introduced only for a breaking change
such as removing/renaming fields or changing a field's type.

#### Public web consumer

`apps/web/lib/species.ts` validates the route segment as a UUID before invoking
the Edge Function with `{ "species_id": "..." }` through the server-only
Supabase client. It requires `schema_version = 1`, validates the returned
identity, and explicitly maps only public fields. The web route must never query
`species_dictionary`, scan, profile, or Explore tables directly to reconstruct
this response.

The mapper runs `publicWebReferenceImageAttributionIssues(...)` before any
reference image is rendered or selected for Open Graph/Twitter metadata. Images
missing `license` or `attribution` are omitted. Similar-species thumbnails are
not rendered because the current lookalike payload does not carry those rights
fields; name and canonical UUID navigation remain available.

The web canonical path is `/species/{speciesId}/{slug}`. The UUID remains the
only Edge request and identity field; the web layer derives its lowercase ASCII
slug from `common_name`, then `scientific_name`, then `species`. UUID-only and
stale-slug requests redirect after successful UUID resolution, so name changes
require neither a database migration nor an Edge contract revision.

Invalid route UUIDs and marked handler-owned Edge `404` responses map to a
non-indexable Next.js not-found page. An unmarked Edge `404` is a
platform/router failure and remains a server error, as do missing server
configuration, network errors, other Edge failures, unsupported schema versions,
malformed payloads, and identity mismatch. Transient errors are therefore never
cached as missing species. Successful pages revalidate every 300 seconds.

Overview mode:

```json
{ "mode": "overview", "user_region": "US" }
```

The `your_region` category includes the English country title in `region` and
the canonical ISO 3166-1 alpha-2 value in additive `region_code`. Country rows
in `regions` likewise include additive `code`. Counts and representatives come
from `species_country_occurrences`, using exact country equality and positive
GBIF occurrence counts. The underlying provider query is limited to PRESENT,
georeferenced records without geospatial issues; the product language is
"recorded in," never a native-range claim. A valid user country remains in the
response with `count = 0` while its durable backfill is pending, allowing iOS to
show a non-interactive coverage state instead of silently removing the card.
Legacy English region-title matching is retained only when that country has no
normalized occurrence coverage, for deployed-client and backfill compatibility.

Catalog mode:

```json
{
  "mode": "catalog",
  "query": "Danaus",
  "limit": 40,
  "cursor": {
    "scientific_name": "Danaus plexippus",
    "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
  }
}
```

- `mode: "catalog"` returns a compact cursor-paginated list for the Explore
  Dictionary catalog.
- `limit` defaults to `40` and is capped at `100`.
- `query` is optional, trims/collapses whitespace, and filters scientific names.
- `category: "region"` requires `region`. ISO country codes and English country
  titles normalize to an exact `species_country_occurrences.country_code`
  filter once coverage exists; broad free-text ranges are not treated as
  canonical country membership.
- `cursor` carries the last `scientific_name` and `species_id` returned.
- Response rows include `id`, `scientific_name`, `common_name`,
  `content_quality`, nullable `taxonomy`, status fields, `group_tags`, and one
  `reference_image_url`; full page content still requires a detail request.

Caching:

- `200 OK` responses include
  `Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800`
  and `Vary: Accept-Encoding`.
- Tree mode sends `Cache-Control: private, no-store` and
  `Vary: Authorization, Accept-Encoding` because the species set depends on the
  authenticated user's scans.
- `400`, `401`, `404`, and `500` responses do not include public cache headers.
- iOS adds a 10-minute, 64-key in-memory memo cache in `MerianNetworkClient`,
  keyed by normalized `species_id` and scientific name. The cache is route-local
  only and never persists species pages to disk.
- Refreshed dictionary rows become visible after the iOS memo TTL and public
  HTTP freshness window expire. Future public web curation flows that require
  immediate visibility should add CDN/cache purge tooling to the write path.

Content quality:

- `content_quality` is additive and may be `complete`, `sparse`, or
  `needs_enrichment`.
- The Edge projection classifies quality from four public content signals: at
  least one reference image, a usable Wikipedia overview, habitat/distribution
  data, and meaningful taxonomy.
- `complete` means all four signals are present. `sparse` means two or three
  signals are present. `needs_enrichment` means fewer than two signals are
  available.
- iOS treats the field as optional and estimates the same state for older
  payloads. Sparse and needs-enrichment pages render an intentional status card
  rather than leaving the missing sections unexplained.
- iOS sends species dictionary analytics through `AppTelemetry` to PostHog.
  Events include `entryPoint`, `contentQuality`, and image `source` where
  relevant; species names, species IDs, scan IDs, Explore post IDs, user
  locations, field notes, comments, image URLs, and review state are not
  attached.

Name and imagery mapping:

- `common_name` resolves from `common_names.en`, then the first non-empty
  `common_names` value, then `scientific_name`.
- `alternative_common_names` is trimmed, deduped, and excludes the resolved
  primary common name.
- `reference_images` prefers ordered rows from `species_reference_images`. Each
  item includes `url` and `source`, plus optional `license`, `attribution`,
  `width`, and `height` when present. A currently promoted `merian` item also
  includes `author_user_id` and the contributor's current `author_username` when
  its promoted private source row matches the species and exact image URL;
  external items never receive those fields.
- If no normalized image rows exist, `reference_images` falls back to the
  comma-separated `species_dictionary.reference_image_url` field by splitting,
  trimming, and deduping URLs.
- `source` is `merian` for Merian-published app media, `wikipedia` for
  Wikimedia/Wikipedia hosts, and `gbif` for external occurrence imagery. If
  `wikipedia_url` exists, the first unresolved legacy image also maps to
  `wikipedia`; otherwise unresolved legacy images map to `gbif`.
- Normalized rows are ordered Merian first, then Wikipedia, then GBIF.
- Normalized rows and legacy strings are filtered through
  `_shared/externalImagePolicy.ts` before source mapping or first-image
  selection. The current exact rule removes every original/resized/query variant
  below `inaturalist-open-data.s3.amazonaws.com/photos/605615444/`. If it was
  first, the next permitted ordered image is promoted. If none remain, existing
  image fields are empty/null according to their existing types; no moderation
  field is added and the species or lookalike row is not removed.
- `similar_species` is hydrated from `species_lookalikes` using the explicit
  PostgREST hint `species_dictionary!lookalike_id` and includes `species_id` for
  canonical tap-through routing. Similar-species thumbnails prefer the first
  normalized `species_reference_images` row and fall back to the legacy
  dictionary cache. Additive relation metadata includes `reason`,
  `visual_traits`, `confidence`, `source`, `review_status`, `is_bidirectional`,
  and `sort_order`; rejected rows are omitted from public projections.

Image licensing and attribution:

- `species_reference_images.license` and `species_reference_images.attribution`
  are the canonical public media rights fields.
- `/species-dictionary` preserves `license` and `attribution` on each normalized
  `reference_images` item when the metadata exists. Legacy comma-separated
  fallback images usually have only `url` and `source`.
- For a promoted Naturebook image, the Edge data layer uses the private source
  row's stable `(species_id, image_url)` key to resolve only the public author
  ID and current username. This works even if the nullable `reference_image_id`
  link is absent. Scan IDs, post IDs, source media indexes, confidence data, and
  locations remain private.
- iOS shows a truncated, tappable `@username` badge over Naturebook images and
  opens the existing public profile sheet. It renders no attribution/license
  footer below the species gallery. The fullscreen viewer uses its bottom
  overlay for fuller credit: `@username · Naturebook` for Naturebook images,
  without falling back to stored display-name or permission wording, or external
  attribution/license/source metadata when present. A Naturebook image missing
  username data shows only the source label.
- The web species mapper calls `publicWebReferenceImageAttributionIssues(...)`
  from `_shared/publicSpeciesProjection.ts` before rendering reference media or
  selecting metadata images, and omits any image with missing license or
  attribution.

Provenance and refresh metadata:

- The response shape does not yet expose provenance fields.
- Dictionary writers record field-level source/freshness rows in
  `species_content_provenance` for common names, alternate names, taxonomy,
  Wikipedia content, habitat, GBIF keys, reference images, group tags,
  hazard/conservation fields, and lookalikes.
- `refresh-species-content` uses `public.get_species_content_refresh_queue(...)`
  as its legacy fallback rather than scanning `species_dictionary` directly for
  stale content. First-class `gbif_wikipedia_reference` jobs come from
  `species_enrichment_jobs`; `refresh-species-model-content` owns the paired
  `habitat`, `lookalikes`, and `group_tags` jobs. Common-name overrides,
  conservation, and hazard data remain curation-owned.
- Reference image refreshes call `public.replace_species_reference_images(...)`
  so normalized rows stay aligned with the legacy compatibility cache while
  preserving existing license/attribution metadata.

Error responses:

| Status | Body                                                                       | Meaning                                                                    |
| ------ | -------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `400`  | `{ "error": "Missing required parameter: species_id or scientific_name" }` | Missing, non-string, or blank lookup                                       |
| `400`  | `{ "error": "species_id must be a valid UUID." }`                          | Invalid species ID                                                         |
| `400`  | `{ "error": "scientific_name must be a string when provided." }`           | Non-string scientific name was supplied alongside a valid species ID       |
| `400`  | `{ "error": "scientific_name is too long." }`                              | Scientific name exceeds the request bound                                  |
| `404`  | `{ "error": "Species not found" }`                                         | No `species_dictionary` row exists for the requested ID or normalized name |
| `500`  | `{ "error": "Internal Server Error" }`                                     | Database or unexpected function failure                                    |

Swift mapping:

```swift
MerianNetworkClient.shared.getSpeciesDictionary(scientificName:)
MerianNetworkClient.shared.getSpeciesDictionary(speciesId:scientificName:)
```

decodes into `SpeciesDictionaryResponse` / `SpeciesDictionaryEntry` in
`SpeciesDictionaryAPIModels.swift`. `SpeciesDictionaryEntry.taxonomyData` adapts
the response into the shared `TaxonomyCard`, and `similarSpeciesData` adapts
hydrated lookalikes into the shared `SimilarSpeciesGallery`.
`SpeciesDictionaryRoute` prefers `speciesId` when present and keeps
`scientificName` as a display/fallback key.

---

## Public Species Observation Stats Edge Node

The `/species-observation-stats` Edge Function returns public, global
iNaturalist observation aggregates for a species. It is deliberately separate
from local Merian observation aggregation:

- iOS aggregates local `LocalScanRecord` data on-device through
  `SpeciesObservationStatsDatabaseActor` and `SpeciesObservationStatsReducer`.
- The Edge Function receives only `species_id` and `scientific_name`.
- The Edge Function returns only public iNaturalist-derived species aggregates
  and cache metadata.

The function has `verify_jwt = false` in `services/supabase/config.toml` because
anonymous public reads remain supported. The first-party iOS client sends its
normal session headers. A valid JWT adds a per-user rate bucket; a missing
header or project publishable/anon key uses only the IP bucket; an invalid
supplied user token returns `401`. Every request consumes the atomic IP
preflight before optional token validation, so malformed tokens cannot amplify
Auth traffic. Identity never changes the response body.

### `/species-observation-stats`

Preferred request:

```text
GET /functions/v1/species-observation-stats?species_id=1cf79982-e5ee-4e3d-8d65-274527e6ae01&scientific_name=Danaus%20plexippus
```

Compatibility request body:

```json
{
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "scientific_name": "Danaus plexippus"
}
```

Validation rules:

- `species_id` is required and must be a canonical RFC-variant dictionary UUID
  using version 1...8. Dictionary rows are UUIDv4 today; accepting newer
  versions keeps the HTTP parser aligned with the database identity boundary.
- `scientific_name` is required.
- `scientific_name` must be a string and non-empty after trimming.
- Internal whitespace is collapsed before lookup.
- Names longer than 160 characters return `400`.
- A service-only database RPC binds the UUID to its canonical normalized name.
  Unknown UUIDs and mismatched names return `404` before provider work.

Current response shape:

```json
{
  "schema_version": 2,
  "data": {
    "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    "scientific_name": "Danaus plexippus",
    "source": {
      "provider": "inaturalist",
      "scope": "global",
      "inaturalist_taxon_id": 48662,
      "fetched_at": "2026-05-17T12:00:00.000Z"
    },
    "status": "fresh",
    "total_observations": 450448,
    "last_observation_date": "2026-05-17",
    "fetched_at": "2026-05-17T12:00:00.000Z",
    "provider_errors": [],
    "seasonality": [{ "month": 5, "count": 1200 }],
    "history": [{ "year": 2026, "month": 5, "count": 1200 }],
    "life_stage": [
      {
        "key": "adult",
        "label": "Adult",
        "values": [{ "month": 8, "count": 100 }]
      }
    ],
    "sex": [
      {
        "key": "female",
        "label": "Female",
        "values": [{ "month": 8, "count": 12 }]
      }
    ]
  }
}
```

`schema_version = 2` marks mandatory dictionary identity and the bounded
population path. The response shape remains compatible with version 1. New
response keys must be additive, existing nullable fields may remain `null`, and
clients should ignore unknown keys. The current iOS client requires schema
version 2 or newer, checks the returned UUID and normalized scientific name
against the request, and does not cache a legacy or identity-mismatched
response. It also rejects malformed UUIDs and names outside the 1...160
character bound before making a network request.

Status values:

- `fresh`: provider fetch completed and data exists.
- `no_data`: exact taxon resolution found no match, or the provider completed
  but no observation buckets were found. The result is negatively cached.
- `partial`: one or more provider buckets failed, but useful data is still
  available. On cold cache misses, core stats may be returned as `partial` while
  life-stage and sex annotation buckets refresh in the background. If provider
  calls fail and no useful bucket exists, the result is `unavailable`, not an
  empty `partial`.
- `stale`: a usable stale cache payload was returned while refresh work is
  deferred off the response path.
- `unavailable`: provider refresh failed and no usable cache existed.

Series shapes:

- `seasonality`: month-of-year counts, `month` in `1...12`.
- `history`: rolling monthly counts from January of current year minus six
  through the current month.
- `life_stage`: category series with month-of-year values.
- `sex`: category series with month-of-year values. This remains part of the
  backend payload for provider parity, but the current iOS chart does not render
  Sex as a tab; per-scan AI sex appears in the Overview card.

iNaturalist mapping:

- Taxon lookup prefers `species_dictionary.inaturalist_taxon_id`.
- If absent, the current lease owner resolves the canonical database
  `scientific_name` exactly through `/v1/taxa`.
- Observation and histogram calls require a positive `taxon_id`. There is no
  caller-controlled `taxon_name` fallback.
- Observation totals and latest dates use `/v1/observations`.
- Seasonality, history, life stage, and sex use `/v1/observations/histogram`.
- Life Stage annotation IDs use `term_id = 1` with values Adult `2`, Teneral
  `3`, Pupa `4`, Nymph `5`, Larva `6`, Egg `7`, Juvenile `8`, and Subimago `16`.
- Sex annotation IDs use `term_id = 9` with values Female `10`, Male `11`, and
  Cannot determine `20`.

Caching:

- Backend cache table: `species_observation_stats_cache`.
- Cache key: `species_id + source + scope`.
- Source: `inaturalist`.
- Scope: `global`.
- Fresh TTLs: seven days (`fresh`), 24 hours (`no_data`), one hour (`partial`),
  and five minutes (`unavailable`).
- Positive data has a 30-day additional stale window. Negative `no_data` has a
  seven-day stale refresh window; `unavailable` is never served stale.
- Cold misses fetch taxon lookup, observation summary, seasonality, and history
  synchronously, then queue life-stage and sex annotation refresh via
  `runBackground`.
- Usable stale rows return immediately. A 90-second database lease suppresses
  cross-isolate duplicate refreshes; fenced finalization prevents an expired
  generation from overwriting newer work.
- If that refresh fails, a positive payload within 37 days of its original
  `fetched_at` remains intact. Finalization marks it `stale`, records the latest
  row-level cache `provider_error`, preserves its original age, and applies a
  five-minute retry backoff. Cold/negative/too-old rows instead use the
  five-minute `unavailable` cache.
- Atomic request limits are 60/user/minute and 120/IP/minute. Cold population
  additionally allows 12/user/minute, 30/IP/minute, and four globally/minute.
- Every provider fetch has a five-second timeout. Foreground/background work has
  15/45-second deadlines and each response body is stream-limited to 1 MiB.
- Database RPCs and cache reads are client-aborted after five seconds; the
  privileged RPCs independently enforce a five-second statement timeout.
- Fresh and `no_data` `200 OK` responses include
  `Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800`
  and `Vary: Accept-Encoding`.
- `partial`, `stale`, and `unavailable` `200 OK` responses use
  `Cache-Control: public, max-age=30, s-maxage=60, stale-while-revalidate=300`
  and `Vary: Accept-Encoding`.
- Successful payloads do not vary by Authorization because identity affects only
  abuse accounting, not the public body. This avoids per-token cache
  fragmentation. Errors remain `private, no-store` and vary by Authorization.
- iOS adds a 5-minute, 64-key in-memory memo cache in `MerianNetworkClient`,
  keyed by normalized `species_id` and scientific name. Only schema-v2-or-newer
  responses with an exact canonical identity match enter that cache.

Privacy:

- Local Merian logs are never sent to Supabase.
- The response must not include scan IDs, user IDs, Explore post IDs, field
  notes, comments, user locations, local media, local observation counts, or
  preferred-name overrides.

Error responses:

| Status | Code                                                  | Meaning                                            |
| ------ | ----------------------------------------------------- | -------------------------------------------------- |
| `400`  | `species_stats_invalid_request` or validation message | Missing/invalid UUID or bounded name               |
| `401`  | `invalid_session_token`                               | Invalid supplied user credential                   |
| `404`  | `species_stats_species_not_found`                     | Unknown dictionary UUID or canonical-name mismatch |
| `413`  | validation message                                    | Compatibility POST body exceeds 4 KiB              |
| `429`  | `species_stats_rate_limited`                          | Request or cold-population budget exhausted        |
| `503`  | `species_stats_refresh_in_progress`                   | Another isolate owns the cold lease                |
| `503`  | `species_stats_unavailable`                           | Database/security boundary unavailable             |

`429`/`503` retry responses include `retry_after_seconds` and `Retry-After`.
Every error response is `private, no-store`.

Swift mapping:

```swift
MerianNetworkClient.shared.getSpeciesObservationStats(
    speciesId:scientificName:
)
```

decodes into `SpeciesObservationStatsResponse` / `SpeciesObservationStatsEntry`
in `SpeciesObservationStatsAPIModels.swift`. `SpeciesObservationStatsViewModel`
combines that public baseline with local SwiftData aggregates for
`SpeciesObservationChartsCard`, which currently renders seasonality, history,
and life-stage series.

---

## Explore Edge Nodes

Explore traffic is intentionally separate from the identify pipeline. The iOS
client uses dedicated Edge Functions for feed reads and social interactions, all
authenticated through the same Supabase session headers used elsewhere in the
app.

### Explore Public Identity Contract

Explore payloads distinguish between the public display label and the canonical
handle:

- `author_name`: display label for Explore rows. Logged-in authors with safe
  provider/account names keep labels such as `Emre E.`.
- `author_username`: stable public username stored without `@`. Clients render
  it as `@author_username` for profile handles and for default/ghost author
  rows.
- `author_avatar_url`: optional copied public avatar projection.

`public_author_name` is not a future mention handle. Comment mentions and other
handle-based features must use `public_username` / `author_username`. The field
is additive and optional for rollout tolerance; older clients may ignore it.

### `/get-explore-species-posts`

Returns visibility-safe Explore cards whose effective canonical species is the
requested dictionary UUID. Confirmed identifications use the confirmed species;
community-resolved observations use the projected resolved taxon. Genus-level
and merely similar-species posts do not match.

```json
{
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "limit": 30,
  "before_image_quality_score": 87,
  "before_shared_at": "2026-07-14T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

- `species_id` must be a UUID and `limit` must be an integer from 1 through 100.
- Omit all cursor fields for the first page. `before_shared_at` and
  `before_post_id` must be supplied together. An omitted/null quality field with
  those two fields represents a cursor in the unscored tier.
- Ordering is `image_quality_score DESC`, then `shared_at DESC`, then post UUID
  descending. Null quality scores sort after every scored post.
- The response is `{ "data": [<standard Explore cards>], "next_cursor": ... }`.
  `next_cursor` contains the three ordering fields or is `null` when exhausted.
- `image_quality_score` is never included in a card. It is used only inside the
  service-role RPC and in `next_cursor`.
- Image, video, audio, legacy, and text-first presentation variants use the
  standard Explore card/media metadata and species reference-thumbnail fallback.
- The shared Explore projection continues to exclude unshared, tombstoned,
  blocked, shadowbanned, identification-pending, and media-less posts.
- The SQL RPC grants `EXECUTE` only to `service_role`; clients call the
  authenticated Edge Function, never PostgREST directly.

### `/get-explore-feed`

Returns public Explore feed cards for the shipped `recent`, `following`,
`trending`, and `nearby` modes. The backend routes to a dedicated SQL RPC per
mode and already filters out:

- unshared posts
- tombstoned scans
- scans with no remaining published image, video, or audio media
- shadowbanned authors
- both directions of user blocking

Post `location_sharing` controls public location output, not ordinary feed
visibility. `private` posts can still appear in Recent, Following, Trending,
profile, hashtag, and detail surfaces, but their public location fields are
empty. The `nearby` filter is spatial and uses post-owned public coordinates;
for non-owned posts this means only saved `location_sharing = "open"` posts with
a stored public coordinate can match the radius query.

Primary request shapes:

Recent feed, which is also the default when `filter` is omitted:

```json
{
  "limit": 20,
  "filter": "recent",
  "before_shared_at": "2026-04-28T21:18:00.000Z",
  "before_post_id": "uuid"
}
```

Following feed:

```json
{
  "limit": 20,
  "filter": "following",
  "before_shared_at": "2026-05-03T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

Trending feed:

```json
{
  "limit": 20,
  "filter": "trending",
  "before_ranking_value": 12,
  "before_shared_at": "2026-05-02T16:45:00.000Z",
  "before_post_id": "uuid"
}
```

Nearby feed:

```json
{
  "limit": 20,
  "filter": "nearby",
  "latitude": 30.2672,
  "longitude": -97.7431,
  "nearby_radius_miles": 25,
  "before_shared_at": "2026-05-03T11:22:00.000Z",
  "before_post_id": "uuid"
}
```

Optional advanced filters for every mode:

```json
{
  "species_categories": ["birds", "insects"],
  "media_types": ["audio", "video"],
  "shared_since": "2026-06-26T12:00:00.000Z"
}
```

Validation rules:

- `recent`, `following`, and `nearby` page on `(shared_at DESC, post_id DESC)`.
  Omit both cursor fields for the first page.
- `following` returns only posts by followed authors that remain visible to the
  requester.
- `trending` pages on `(ranking_value DESC, shared_at DESC, post_id DESC)`. The
  cursor is only valid when `before_ranking_value`, `before_shared_at`, and
  `before_post_id` are all supplied together.
- `nearby` requires both `latitude` and `longitude`.
- `nearby_radius_miles` is used only by `nearby`, defaults to `50`, and must be
  between `1` and `100`.
- `species_categories` accepts the same taxonomy groups as Explore Map:
  `plants`, `fungi`, `birds`, `mammals`, `reptiles`, `amphibians`, `fish`,
  `insects`, `arachnids`, and `other`.
- `media_types` accepts `image`, `audio`, and `video`; mixed-media posts match
  when any saved public media item has a selected kind.
- `shared_since` is an inclusive ISO-8601 cutoff over `shared_at`.
- Values are OR-ed within species/media groups and AND-ed across all populated
  groups. The SQL RPCs apply them before ordering and `LIMIT`; clients must not
  fetch a page and discard non-matching rows locally.
- `before_ranking_value` is rejected for `recent`, `following`, and `nearby`.
- `trending` is freshness-biased rather than all-time top. The ranking value is
  the post's like activity from the trailing 30 days.
- `nearby` reads `explore_posts.public_latitude` / `public_longitude` and limits
  non-owned coordinate-bearing posts to the requested radius around the supplied
  viewer location before applying recency sort. `obscured` and `private` posts
  remain visible in non-spatial feeds but do not expose coordinates for Nearby.

`Recent` remains the iOS default for first load and for the Explore-tab unread
badge refresh path.

Current response shape:

```json
{
  "data": [
    {
      "post_id": "uuid",
      "scan_id": "uuid",
      "hero_image_url": "https://...",
      "shared_at": "2026-04-26T17:22:11.000Z",
      "author_user_id": "uuid",
      "author_name": "Emre E.",
      "author_username": "emre_e",
      "author_avatar_url": "https://lh3.googleusercontent.com/...",
      "hashtags": ["citybioblitz", "springcount"],
      "species_common_name": "Monarch Butterfly",
      "species_scientific_name": "Danaus plexippus",
      "pet_identification": null,
      "public_location_label": "Austin, TX",
      "location_sharing": "open",
      "time_of_day": "afternoon",
      "current_month": 4,
      "weather_condition": "clear",
      "weather_temperature_f": 78.2,
      "like_count": 3,
      "comment_count": 1,
      "ranking_value": 12,
      "viewer_has_liked": false,
      "is_owned_by_viewer": false
    }
  ]
}
```

`author_username` is the copied public handle stored on
`public.users.public_username` without `@`. `author_avatar_url` is a copied
public projection stored on `public.users.public_avatar_url`. Neither field is
read directly from `auth.users` on the client. `ranking_value` is populated for
`trending` rows and omitted or `null` for `recent`, `following`, and `nearby`.
Feed-card hashtag hydration is a batched lookup over the page's `post_id`
values. `hashtags` is returned by the updated feed function as normalized public
tag text without leading `#`; it is `[]` for untagged posts.
`species_common_name` is the post snapshot selected by the author when sharing
or editing. It should be preferred over dictionary names for the public post
projection, while clients may still apply viewer-local preferred-name display on
top of the DTO for personalized native surfaces. When `pet_identification` is
non-null, native clients may use `pet_identification.label` as the visible
dog/cat card title. That label does not replace `species_common_name`,
`species_scientific_name`, dictionary routes, or species stats.

### `/get-explore-post`

Returns the same Explore card projection as `/get-explore-feed`, but for a
single post:

```json
{
  "post_id": "uuid"
}
```

This endpoint exists for notification routing and native deep links. It solves
the case where the tapped post is not already present in the currently loaded
in-memory feed page. Public web routes do not call this viewer-parameterized RPC
directly; they use the dedicated fixed-anonymous server projection described
below.

Current response shape:

```json
{
  "schema_version": 1,
  "data": {
    "post_id": "uuid",
    "scan_id": "uuid",
    "hero_image_url": "https://...",
    "media_items": [
      {
        "kind": "video",
        "url": "https://media.merian.app/public_uploads/pro/.../video_playback.mp4",
        "thumbnail_url": "https://media.merian.app/public_uploads/pro/.../poster.webp",
        "order_index": 0,
        "duration_seconds": 8.2,
        "has_audio": false
      }
    ],
    "shared_at": "2026-04-26T17:22:11.000Z",
    "author_user_id": "uuid",
    "author_name": "Emre E.",
    "author_username": "emre_e",
    "author_avatar_url": "https://lh3.googleusercontent.com/...",
    "hashtags": ["citybioblitz", "springcount"],
    "species_common_name": "Monarch Butterfly",
    "species_scientific_name": "Danaus plexippus",
    "pet_identification": null,
    "public_location_label": "Austin, TX",
    "location_sharing": "open",
    "time_of_day": "afternoon",
    "current_month": 4,
    "weather_condition": "clear",
    "weather_temperature_f": 78.2,
    "like_count": 3,
    "comment_count": 1,
    "viewer_has_liked": false,
    "is_owned_by_viewer": false
  }
}
```

If the post is no longer visible to the viewer because it was unshared, blocked,
tombstoned, or lost media, the endpoint returns `404`.

The recent `get_explore_feed` SQL projection additionally exposes
`reference_thumbnail_url` beside `hero_image_url` and `media_items`. Public web
grid cards use the species reference thumbnail for audio posts, while detail and
social-preview surfaces retain the audio spectrogram from the canonical media
snapshot.

### Public-web Explore database projection

`https://naturebook.earth/explore/post/{postId}` and the anonymous discovery
grid are server-rendered. `apps/web/lib/explore.ts` invokes the card routine for
the grid:

```json
{
  "rpc": "get_public_web_explore_posts",
  "args": {
    "p_target_post_id": "uuid-or-null",
    "p_max_limit": 16
  }
}
```

and the atomic page routine for detail and metadata:

```json
{
  "rpc": "get_public_web_explore_post_page",
  "args": {
    "p_target_post_id": "uuid"
  }
}
```

The Next.js helper is `server-only` and uses the validated platform-managed
server API key. All public-web SQL routines call
`internal.require_service_role()`, fix the canonical viewer to `NULL`, and are
revoked from `PUBLIC`, `anon`, and `authenticated`; callers cannot supply or
configure a synthetic viewer. The card result exposes no viewer-dependent
engagement state: `like_count` and `comment_count` are zero, while
`viewer_has_liked` and `is_owned_by_viewer` are false. Card visibility,
moderation, tombstone, media health, shadowban, block, and location redaction
remain owned by `explore_projected_post_cards(NULL)`.

The detail routine independently inner-joins that canonical card projection.
`get_public_web_explore_post_page(target_post_id)` returns `post_payload` and
`detail_payload` from one statement/MVCC snapshot, and the page helper uses only
that combined routine. A direct detail call and the combined call therefore
return no row for content excluded by canonical anonymous visibility. The server
must not reconstruct this DTO through direct privileged table reads. Exact-SHA
verification is tracked in the
[release assurance record](./14-dwca-and-public-web-release-hold-2026-07-27.md).

### `GET /api/explore/audio?url={canonicalWavUrl}` (Public Web)

Next.js same-origin stream used only after a visitor activates **Boost audio**.
It accepts HTTPS `.wav` URLs on exact host `media.merian.app` below
`/public_uploads/`, forwards byte ranges and safe cache/media headers, and
rejects arbitrary hosts, credentials, staging/private paths, unsupported
formats, missing upstream media, and oversized non-range responses. It stores no
bytes and does not change the public recording or moderation state.

### `/get-explore-post-detail`

Returns the public species-detail payload for a single Explore post. The backend
reads from `public.get_explore_post_detail(...)`, which enforces the same
filters as the main feed:

- unshared posts are excluded
- tombstoned scans are excluded
- scans with no remaining published image, video, or audio media are excluded
- shadowbanned authors are excluded
- both directions of user blocking are excluded

Post `location_sharing` is returned for edit hydration and controls public
location fields. It does not hide an otherwise visible detail page.

Request body:

```json
{
  "post_id": "uuid"
}
```

Current response shape:

```json
{
  "data": {
    "post_id": "uuid",
    "location_sharing": "open",
    "hashtags": ["citybioblitz", "springcount"],
    "species_dictionary_id": "uuid",
    "alternative_common_names": ["Milkweed Butterfly", "Common Tiger"],
    "taxonomy_kingdom": "Animalia",
    "taxonomy_phylum": "Arthropoda",
    "taxonomy_class": "Insecta",
    "taxonomy_order": "Lepidoptera",
    "taxonomy_family": "Nymphalidae",
    "taxonomy_genus": "Danaus",
    "ai_reasoning": "The bright orange wings with black veining and white-spotted margins are consistent with a monarch rather than the mimicking viceroy.",
    "habitat_description": "Often found in open meadows, milkweed patches, and migration corridors.",
    "gbif_taxon_key": 5130978,
    "iucn_red_list_status": "least_concern",
    "hazard_type": "poisonous",
    "wikipedia_url": "https://en.wikipedia.org/wiki/Monarch_butterfly",
    "reference_image_url": "https://upload.wikimedia.org/.../Monarch.jpg,https://inaturalist-open-data.s3.amazonaws.com/photos/123/original.jpg",
    "wikipedia_overview": "The monarch butterfly is a milkweed butterfly in the family Nymphalidae...",
    "similar_species": [
      {
        "species_id": "uuid",
        "scientific_name": "Limenitis archippus",
        "common_name": "Viceroy",
        "reference_image_url": "https://upload.wikimedia.org/.../Viceroy.jpg",
        "iucn_red_list_status": "least_concern"
      }
    ],
    "field_notes": "Found at the shaded meadow edge after rain."
  }
}
```

This endpoint exists so Explore can render public species cards on the detail
page without loading private scan state or the Insight `InferenceEngine`.

`hashtags` uses the same normalized public tag edge table as feed cards. Detail
renders tags as centered wrapping chips; tag taps route into the tagged-post
collection rather than querying field notes, comments, or private scan state.

`schema_version = 1` uses the same public species contract marker as
`/species-dictionary`. Older clients can continue decoding the `data` field and
ignore the wrapper key; newer clients may use it to gate future additive UI
behavior.

`alternative_common_names` is sourced from
`species_dictionary.alternative_common_names` and returned as an empty array
when no alternate names are available.

For posts owned by the current viewer, iOS also uses `field_notes` as a repair
source for the local insight sheet. `FieldNotesRepository` checks
`LocalScanRecord.fieldNotes`, `OfflineQueuedScan.fieldNotes`, and then the
legacy `FieldNotesStore` bridge before accepting the Explore value. If all
local/private stores are empty but the public Explore post still has notes, the
repository promotes the public value back into SwiftData and mirrors the bridge.
Existing local/private notes are preserved and are not overwritten by the
Explore copy.

`reference_image_url` remains a comma-separated compatibility field for Explore
detail clients, but the RPC now composes it from ordered
`species_reference_images` rows first and falls back to
`species_dictionary.reference_image_url` for older species rows. Before
returning the field, the RPC passes that ordered projection and the backing
scan's `image_storage_urls` through
`public.public_species_reference_image_urls_excluding_media(...)`. Exact current
scan URLs are removed while other scans' Merian references and external
Wikipedia/GBIF references retain their order. The helper reuses the existing
projection, so blocked-image filtering and legacy fallback behavior are
unchanged. If every candidate belongs to the current scan, the field is `null`.

This is a read-time, exact-scan exclusion. It does not remove normalized rows,
filter all contributions by the author, or perform perceptual matching across
different storage objects. The response keys and types are unchanged, allowing
the backend, iOS, and web changes to roll out independently. Explore detail uses
the field to render the public reference gallery below the post's AI reasoning
without making an extra authenticated scan fetch.

`similar_species` is hydrated from `species_lookalikes` for the post's resolved
dictionary species through `public.public_species_similar_species(...)`. Each
entry contains public species-level data only and is shaped like the existing
lookalike DTO: `species_id`, `scientific_name`, `common_name`,
`reference_image_url`, and `iucn_red_list_status`, plus optional relation
metadata (`reason`, `visual_traits`, `confidence`, `source`, `review_status`,
`is_bidirectional`, `sort_order`). The lookalike image URL prefers the first
normalized `species_reference_images` row and falls back to the legacy
dictionary cache. Empty lookalike sets return an empty array, and iOS omits the
section. Older clients can continue to route by `scientific_name`; new clients
prefer `species_id` for dictionary sheet lookup.

`ai_reasoning` is returned conditionally from the backing `scans` row, not
copied into `explore_posts`. It is only exposed when the scan still reflects the
original AI identification:

- `user_review_state != 'user_overridden'`
- `user_identification_override IS NULL`

Report flags do not hide reasoning because moderation workflow state does not
rewrite the identification. The Explore detail page hides reasoning only after
the user overrides the AI identification, preventing stale reasoning from being
presented for a replacement identification.

### `/get-explore-author-profile`

Returns a privacy-scoped public author profile for an Explore author. This
endpoint exists for the author profile sheet opened from Explore feed/detail
author headers.

Request body:

```json
{
  "author_user_id": "uuid",
  "preview_limit": 9
}
```

Validation and availability rules:

- `author_user_id` is required and must be a UUID.
- `preview_limit` is optional, defaults to `9`, and is capped at `30`.
- For another viewer, the endpoint returns `404` if the target author has
  neither a currently visible Explore post nor a visible Field trip profile
  surface. The authenticated owner may load their own zero-visible-post profile
  so media recovery remains explainable.
- Shadowbanned authors and either direction of user blocking return no profile.
- Profile aggregates are computed from all non-tombstoned scans owned by the
  author.
- Species count and achievement progress use biological species-backed scans via
  `COALESCE(confirmed_species_id, species_id)`.
- Public achievement progress includes the full current app achievement catalog,
  including domestic cat and dog scan achievements.
- Preview posts use the same Explore visibility rules as feed/library posts and
  never include unshared, tombstoned, media-less, system-quarantined, or
  non-species-backed posts. Confirmed-missing items are omitted. Private post
  location sharing withholds location but does not hide the post.
  Administratively hidden posts (`moderated_at IS NOT NULL`) are also excluded
  from both profile discoverability and previews.
- Achievement progress never includes qualifying scan IDs.
- Follower/following counts are aggregate-only and do not expose browsable
  identities.
- `viewer_is_following` is specific to the requesting viewer and drives the
  profile sheet follow button.
- `viewer_can_report` is viewer-scoped and is `true` only for a non-self profile
  returned by this visibility contract. It controls whether the overflow menu
  offers **Report user**; `/report-user` independently revalidates the target.

Current response shape:

```json
{
  "data": {
    "author_user_id": "uuid",
    "author_name": "River W.",
    "author_username": "river_w",
    "author_avatar_url": "https://...",
    "species_count": 42,
    "current_streak": 5,
    "published_post_count": 5,
    "follower_count": 124,
    "following_count": 17,
    "viewer_is_following": false,
    "viewer_can_report": false,
    "owner_publication_summary": {
      "publication_intent_count": 38,
      "visible_post_count": 5,
      "recovery_needed_post_count": 33,
      "degraded_post_count": 0,
      "quarantined_post_count": 33
    },
    "heatmap": {
      "total_captures": 124,
      "current_month_captures": 8,
      "year_string": "2026",
      "weeks": [
        {
          "month_label": "May",
          "days": [
            { "count": 1, "date": "2026-05-03T00:00:00Z" },
            { "count": 0, "date": "2026-05-04T00:00:00Z" },
            { "count": -1, "date": "2026-05-05T00:00:00Z" }
          ]
        }
      ]
    },
    "awards": [
      {
        "type": "explorer",
        "current_count": 5,
        "last_interaction_at": "2026-05-03T12:00:00.000Z"
      }
    ],
    "preview_posts": [
      {
        "post_id": "uuid",
        "scan_id": "uuid",
        "hero_image_url": "https://...",
        "shared_at": "2026-05-03T12:00:00.000Z",
        "author_user_id": "uuid",
        "author_name": "River W.",
        "author_username": "river_w",
        "author_avatar_url": "https://...",
        "species_common_name": "River Birch",
        "species_scientific_name": "Betula nigra",
        "pet_identification": null,
        "public_location_label": "Austin, TX",
        "time_of_day": "day",
        "current_month": 5,
        "weather_condition": "clear",
        "weather_temperature_f": 74.0,
        "like_count": 8,
        "comment_count": 1,
        "viewer_has_liked": false,
        "is_owned_by_viewer": true,
        "ranking_value": null
      }
    ],
    "field_trips": {
      "pinned": [],
      "active": [],
      "published": []
    }
  }
}
```

Heatmap day `count = -1` marks future days in the fixed 52-week grid and renders
as empty/clear in `ScansHeatmap`. The backend chooses the author's latest valid
persisted `scans.device_time_zone` for day-boundary calculations and falls back
to UTC when no timezone is available.

`follower_count` and `following_count` are public aggregate counts on visible
profiles only. They do not imply browsable lists. `viewer_is_following` is
specific to the requesting user and should replace any optimistic client follow
state after a write. `viewer_can_report` is an authorization-aware UI hint, not
authority to bypass the report endpoint's self-report and visibility checks.
`published_post_count` and `preview_posts` use the same canonical
`explore_projected_post_cards(self_id)` projection.

`owner_publication_summary` is non-null only for the authenticated owner. It
separates preserved, active publication intent from current canonical visibility
and reports active degraded/quarantined recovery totals. Other viewers receive
`null`; the object is not a public author statistic. `field_trips` is hydrated
separately after the core profile RPC and contains only privacy-scoped active
progress and published snapshots; it never exposes scan IDs, field notes, exact
coordinates, or private evidence.

### `/get-explore-author-posts`

Returns a paginated grid library of an author's currently visible published
Explore scans. The response shape is the same card projection used by
`/get-explore-feed`, with `ranking_value = null`.

First page request:

```json
{
  "author_user_id": "uuid",
  "limit": 30
}
```

Follow-up page request:

```json
{
  "author_user_id": "uuid",
  "limit": 30,
  "before_shared_at": "2026-05-03T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

Validation and pagination rules:

- `author_user_id` is required and must be a UUID.
- `limit` is optional, defaults to `30`, and is capped at `100`.
- `before_shared_at` and `before_post_id` must be omitted together or supplied
  together.
- Pagination is stable on `(shared_at DESC, post_id DESC)`.
- The endpoint filters unshared posts, tombstoned scans, scans with no image
  media, scans without a species key, system-quarantined posts, shadowbanned
  authors, and both directions of user blocking. Confirmed-missing items are
  omitted. Post `location_sharing` controls public location fields, not feed
  visibility.
- The card projection includes batched `hashtags` arrays just like the feed.
- The Edge function fetches `limit + 1`; `next_cursor` is non-null only when
  another page exists. Clients stop only when it is `null`.

Response envelope:

```json
{
  "data": [
    {
      "post_id": "uuid",
      "scan_id": "uuid",
      "shared_at": "2026-05-03T12:00:00.000Z"
    }
  ],
  "next_cursor": {
    "before_shared_at": "2026-05-03T12:00:00.000Z",
    "before_post_id": "uuid"
  }
}
```

At the end of the collection, `next_cursor` is `null`. Clients must not infer
completion from a short page or a separately fetched profile count.

### `/get-explore-hashtag-posts`

Returns a paginated grid collection of currently visible Explore posts tagged
with one normalized public hashtag. iOS opens this collection when the viewer
taps a hashtag chip on a feed card or post detail page. The response shape is
the same card projection used by `/get-explore-feed`, with
`ranking_value = null` and a `hashtags` array hydrated for each row.

First page request:

```json
{
  "hashtag": "#CityBioBlitz",
  "limit": 30
}
```

Follow-up page request:

```json
{
  "hashtag": "citybioblitz",
  "limit": 30,
  "before_shared_at": "2026-05-12T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

Rules:

- `hashtag` is required. Display input may include leading `#`; the Edge
  function trims it, lowercases it, and requires 2 to 40 letters, digits, or
  underscores.
- `limit` is optional, defaults to `30`, and is capped at `100`.
- `before_shared_at` and `before_post_id` must be omitted together or supplied
  together.
- Pagination is stable on `(shared_at DESC, post_id DESC)`.
- The endpoint applies the same unshared, tombstoned, missing-media,
  missing-species, shadowban, and mutual-block filters as the Explore feed. Post
  `location_sharing` controls public location fields, not tagged-post
  visibility.
- The backing RPC is `public.get_explore_hashtag_posts(...)`, which reads the
  normalized `(tag, post_id)` edge index from `public.explore_post_hashtags`.

### `/get-explore-map-points`

Returns privacy-safe Explore map data for the currently visible bounds. The
request body is:

```json
{
  "north_latitude": 30.489,
  "south_latitude": 30.139,
  "east_longitude": -97.517,
  "west_longitude": -98.001,
  "zoom_level": 10.7,
  "limit": 500,
  "species_categories": ["birds", "insects"],
  "media_types": ["image", "audio"]
}
```

- `north_latitude`, `south_latitude`, `east_longitude`, and `west_longitude` are
  required numeric bounds.
- `zoom_level` is used only to decide whether the response should be clustered
  or return individual posts.
- `limit` is optional and capped at `500`.
- `species_categories` is optional. Allowed values are `plants`, `fungi`,
  `birds`, `mammals`, `reptiles`, `amphibians`, `fish`, `insects`, `arachnids`,
  and `other`.
- `media_types` is optional. Allowed values are `image`, `video`, and `audio`.

The Edge Function reads `public.get_explore_map_posts(...)` and then applies
species-category and media-type filters plus zoom-aware clustering in
`services/supabase/functions/get-explore-map-points/cluster.ts`. The shipped
behavior is:

- category counts are computed after applying media filters, while media-type
  counts are computed after applying species filters
- selected values use OR within each filter group and AND between species and
  media groups; both groups are applied before clustering
- when the visible result set is small, return `mode: "posts"`
- when the viewport is broad or dense, return `mode: "clusters"`
- at close zooms, individual posts are still capped to prevent annotation
  overload

Current response shapes:

```json
{
  "mode": "clusters",
  "visible_count": 243,
  "category_counts": [
    { "category": "birds", "count": 82 },
    { "category": "insects", "count": 51 }
  ],
  "media_type_counts": [
    { "media_type": "image", "count": 132 },
    { "media_type": "video", "count": 71 },
    { "media_type": "audio", "count": 40 }
  ],
  "clusters": [
    {
      "id": "3015:2057",
      "latitude": 30.267,
      "longitude": -97.743,
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
  "category_counts": [
    { "category": "birds", "count": 12 },
    { "category": "insects", "count": 8 }
  ],
  "media_type_counts": [
    { "media_type": "image", "count": 14 },
    { "media_type": "video", "count": 6 },
    { "media_type": "audio", "count": 4 }
  ],
  "clusters": [],
  "posts": [
    {
      "post_id": "uuid",
      "scan_id": "uuid",
      "latitude": 30.267,
      "longitude": -97.743,
      "coordinate_visibility": "obscured",
      "hero_image_url": "https://...",
      "shared_at": "2026-04-28T21:18:00.000Z",
      "author_user_id": "uuid",
      "author_name": "Nina P.",
      "author_username": "nina_p",
      "author_avatar_url": "https://...",
      "species_common_name": "Monarch Butterfly",
      "species_scientific_name": "Danaus plexippus",
      "pet_identification": null,
      "taxonomy_kingdom": "Animalia",
      "taxonomy_class": "Insecta",
      "public_location_label": "Austin, TX",
      "location_sharing": "open",
      "time_of_day": "afternoon",
      "current_month": 4,
      "weather_condition": "clear",
      "weather_temperature_f": 78.2,
      "like_count": 12,
      "comment_count": 3,
      "viewer_has_liked": false,
      "is_owned_by_viewer": false,
      "media_items": [
        {
          "kind": "image",
          "url": "https://...",
          "thumbnail_url": "https://...",
          "order_index": 0,
          "duration_seconds": null,
          "has_audio": false
        }
      ]
    }
  ]
}
```

Privacy and filtering rules:

- the map excludes unshared posts, tombstoned scans, scans with no remaining
  published image/video/audio media, non-open post `location_sharing`,
  shadowbanned authors, and both directions of user blocking
- media filters match authoritative `media_items.kind` values, not poster images
  or a video's `has_audio` flag; legacy rows without media items count as images
  only when they retain a non-empty hero image
- `category_counts` reflects the active media selection and `media_type_counts`
  reflects the active species selection; absent facet values are omitted rather
  than returned with zero counts
- `coordinate_visibility` communicates whether an open post point is exact or
  approximate because species-safety or uncertainty rules rounded the public
  projection
- the shipped map projection comes from post-owned public coordinates on
  `explore_posts`, not from raw scan GPS at read time
- the map returns the post-owned scrubbed `public_location_label`; it does not
  derive labels from raw semantic location fields

### `/get-explore-comments`

Returns comment rows for a single Explore post. The read path enforces the same
visible-post and mutual-block filters as the feed. Comment rows include the
public author label, the stable author username handle, the optional public
author avatar projection, and three viewer capability flags:

- `viewer_can_delete`: The viewer authored this comment and may delete it.
- `viewer_can_moderate`: The viewer owns the Explore post and may remove someone
  else's comment from that post.
- `viewer_can_report`: The viewer may report this comment for abuse review.

This endpoint powers both the feed's bottom-sheet comments view and the inline
comment thread on the Explore detail page.

Current response shape:

```json
{
  "data": [
    {
      "comment_id": "uuid",
      "post_id": "uuid",
      "author_user_id": "uuid",
      "author_name": "Nick H.",
      "author_username": "nick_h",
      "author_avatar_url": "https://lh3.googleusercontent.com/...",
      "body": "Oooh mucho gusto",
      "created_at": "2026-05-12T20:43:00.000Z",
      "viewer_can_delete": false,
      "viewer_can_moderate": false,
      "viewer_can_report": true,
      "mentions": [
        {
          "user_id": "uuid",
          "username": "ash_b",
          "display_name": "Ash B.",
          "avatar_url": "https://..."
        }
      ],
      "reactions": [
        {
          "emoji": "👍",
          "count": 1,
          "viewer_has_reacted": false
        }
      ]
    }
  ]
}
```

`author_avatar_url` is sourced from `public.users.public_avatar_url`, the same
copied public projection used by feed cards, map previews, and author profiles.
The client must treat it as optional and fall back to iconography when it is
`null`.

`mentions` is an additive array of resolved `@username` spans in `body`. The raw
body remains plain text; the client links only usernames that appear in
`mentions`. Unresolved `@text` stays normal text.

The request body supports cursor pagination on
`(created_at ASC, comment_id ASC)`:

```json
{
  "post_id": "uuid",
  "limit": 100
}
```

Follow-up page requests send:

```json
{
  "post_id": "uuid",
  "limit": 100,
  "after_created_at": "2026-04-28T10:00:00.000Z",
  "after_comment_id": "uuid"
}
```

### `/get-explore-comment-replies`

Returns one page of visible replies under a top-level Explore comment. Replies
use the same row shape as `/get-explore-comments`, including `author_username`,
`author_avatar_url`, `reactions`, and `mentions`.

Request:

```json
{
  "parent_comment_id": "uuid",
  "limit": 25
}
```

Follow-up page requests send both cursor fields:

```json
{
  "parent_comment_id": "uuid",
  "limit": 25,
  "after_created_at": "2026-04-28T10:00:00.000Z",
  "after_comment_id": "uuid"
}
```

Replies stay one level deep. A reply cannot be the parent of another reply.

### `/share-scan-to-explore` and `/unshare-explore-post`

- Both Scan Library quick-share and the full Insight composer call
  `/share-scan-to-explore` with the signed-in user's access token.
  `withEdgeHandler` authenticates that user, and the route verifies scan
  ownership and share eligibility. Only then does its server-side admin client
  call service-only author-maintenance and publication RPCs. The iOS client
  never receives or submits a service-role key.
- Privileged database execution has two layers. The exact RPC signature must be
  granted to `service_role` through `internal.privileged_routine_grants`, and
  the routine body calls `internal.require_service_role()`. Migration
  `20260727010340_fix_service_role_authorization_guard.sql` lets that helper
  recognize either a legacy JWT claim or PostgREST's protected `service_role`
  impersonation for an opaque server key; it does not add an `authenticated`
  grant.
- `service_role authorization required` in Edge/database logs is an internal
  deployment or server-key compatibility failure, not a scan-eligibility
  rejection or a user-facing `401`/`403`. Apply the compatibility migration and
  verify the service-only ACL. Never recover by granting the maintenance RPC to
  the user role or putting a service key in the app.
- `share-scan-to-explore` creates or reactivates a manual-share Explore post for
  an eligible biological scan with shareable public media. If a scan's public
  media URLs expired but the client can provide owner-scoped
  `restored_object_keys`, the function promotes safe image media back into
  `image_storage_urls` before sharing. If the local scan still has the original
  playback `.mp4` and the cloud row is missing durable video media, clients may
  provide `restored_video_object_keys`; the function promotes those videos into
  `video_storage_urls`, rebuilds `captured_media`, makes a best-effort
  `scan_media_assets` refresh for ready playback rows, and then writes the
  public Explore snapshot.
- If the authenticated owner's local observation exists but its cloud row does
  not, current clients may combine those validated staging keys with a bounded
  non-media `recovery_scan` object. The handler derives and verifies the owner,
  inserts with duplicate protection, reloads by both scan and owner, and then
  follows the normal eligibility and media-promotion path. The server refuses
  media-less owner recovery with `409 scan_restore_media_required` before the
  recovery RPC is invoked, and proves every supplied key's exact
  scan/kind/role upload-ledger binding before that mutation. It also refuses
  this repair while richer ingestion is active or retryable and after a known
  terminal moderation or provider safety-policy rejection.
- Sharing snapshots image, video, and standalone-audio URLs into
  `explore_post_media`, ordered for the public carousel. `hero_image_url`
  remains the backward-compatible image field; author-post reads also return
  `reference_thumbnail_url` for compact audio tiles. Video media without an
  image thumbnail is rejected with `Video thumbnail unavailable.`
- New clients may pass ordered `media_items` using owner-scoped
  `source_media_id` values from `/get-explore-composer-media`; legacy
  `source_index` and `thumbnail_source_index` are accepted only when they map to
  eligible scan image/video/audio URLs. Empty selections, unsupported media
  kinds, Describe/observation context, AI/reference images, and Dictionary media
  are rejected or ignored before the public post snapshot is written.
- `source_media_id` values are resolved through the same media source list
  returned to the composer: ready display/playback/audio `scan_media_assets`
  rows first, `captured_media` second, and legacy image/video/audio URL arrays
  last. This keeps video playback URLs and poster thumbnails paired even when
  sampled inference frames remain in compatibility image URL arrays. Share-state
  visibility requires a saved `explore_post_media` row, preventing failed media
  writes from appearing as existing Explore posts. When a selected video source
  is missing from the cloud row, the endpoint returns a clean validation error
  so the iOS client can attempt local `.mp4` repair instead of publishing an
  image-only historical row. Scan finalization now proves this same canonical
  projection, so a valid playback scan can reach the completed prerequisite
  consumed here without requiring inference frames to become separately
  selectable media.
- Video `has_audio` metadata is copied from ready media rows or derived from the
  `captured_media` video audio reference. Legacy URL-array video sources default
  false because they do not prove that an audio companion exists.
- `restored_audio_object_keys` accepts at most two owner-scoped
  `staging/{userId}/` WAV/M4A keys for legacy scans that still have local audio
  but no durable cloud audio. Successful repair promotes the objects, writes
  `audio_storage_urls`, replaces standalone local references in
  `captured_media`, refreshes normalized assets, and then enters the normal
  moderation gate. Promotion failure, or a returned persistence rejection plus
  exact-owner proof that the URLs are absent, publishes nothing and rolls back
  promoted objects. A lost/unreadable update response returns retryable
  `scan_media_restore_unavailable` and preserves them until same-owner retry
  settles the outcome.
- If any selected item is standalone audio or an audio-bearing video, every
  audible item must have a matching content-addressed attestation or pass the
  database-selected structured audio classifier (currently `gemini-2.5-flash`)
  before the Explore post/media upsert runs. Attestations match SHA-256, model,
  and the automatically derived policy-contract hash; changed bytes or rules
  force a new decision. A rejected clip returns `422`; provider/configuration
  failures return `503`. Neither failure creates, reactivates, or changes a
  public post. Successful shares return `200` with
  `publication_status = published`. The transcript and non-speech description
  are not persisted, and the Edge runtime reuses `GEMINI_API_KEY`. Cache
  lookup/store failures degrade to live classification rather than approving by
  default.
- iOS accepts a `200` share response only when `success` is true, `scan_id`
  exactly echoes the requested scan UUID, `post_id` is a UUID, `shared_at` is a
  parseable ISO-8601 timestamp, `location_sharing` is authoritative, and
  `publication_status` explicitly equals `published`. A missing, malformed, or
  contradictory response is `MerianError.invalidResponse`: the post ID is not
  cached, the composer remains open with its draft intact, and the user can
  retry.
- After media restoration, selection, thumbnail work, and moderation, the Edge
  route performs exactly one final publication mutation through
  `publish_scan_to_explore_atomically(...)`. That service-role-only invoker RPC
  locks and revalidates the owner scan, locks and rechecks community readiness,
  and replaces post metadata, selected media, hashtags, and resolved-community
  publication state in one transaction. A transaction-time `needs_id` request
  returns conflict only when PostgreSQL reports the exact reviewed `P0001`
  condition and canonical message; matching text on another SQLSTATE is not
  downgraded to a user conflict. A failure in any relational step restores the
  prior complete snapshot and returns no published response.
- Forward migration `20260729044500_grant_atomic_explore_service_privileges.sql`
  provides the service role's narrow table-operation allowlist for both atomic
  invoker RPCs. Browser roles retain no direct publication write and neither RPC
  uses definer authority.
- Clients send one UUID `Idempotency-Key` for the share and preserve it through
  transport/auth/media-restoration retries. Each audible checksum and policy
  version receives a deterministic child reservation ID, allowing multiple clips
  without duplicate provider spend on an ambiguous retry. Cache hits explicitly
  refund the provisional reservation. Cache misses atomically apply the
  `explore_audio_moderation` daily and per-user/IP limits before dispatch.
- After standalone WAV audio passes moderation, `share-scan-to-explore` and
  media edits through `update-explore-field-notes` generate or reuse a
  deterministic PNG spectrogram beside the durable recording and store its URL
  in both the post snapshot and matching normalized scan asset. This
  presentation step is non-blocking: unsupported legacy codecs and generation
  failures retain playback plus the volume-icon fallback. The service-role-only
  `/backfill-explore-audio-spectrograms` endpoint accepts an optional bounded
  `{ "limit": 1...200 }` batch size and repairs older blank WAV thumbnails;
  repeat while `generated_count` is greater than zero.
- When the scan has an active Identify request, sharing to Explore is blocked
  until that request resolves. Publishing a resolved Identify request marks the
  request with `explore_published_at`, materializes any new GBIF-backed resolved
  species into `species_dictionary`, sets the scan's `confirmed_species_id`, and
  queues species-content hydration/provenance rows before promoting the existing
  post into normal Explore surfaces without creating a duplicate post.
- `unshare-explore-post` soft-removes the post from the public feed via
  `unshared_at` without deleting the underlying scan.
- `field_notes` is optional and capped at 1000 characters. It is a public copy
  controlled by the user, not the private local source of truth.
- `species_common_name` is optional. When provided it must be a string; the Edge
  function trims it, collapses internal whitespace, caps it at 200 characters,
  and stores it as the Explore post's public common-name snapshot. When omitted
  or empty, legacy dictionary fallback behavior is preserved.
- `hashtags` is optional. The share endpoint accepts at most five hashtag
  strings, strips leading `#`, lowercases them, deduplicates them, and requires
  each tag to be 2 to 40 letters, digits, or underscores. Resharing replaces the
  post's public hashtag edges with the submitted normalized set; omitted
  hashtags clear the set for that share request.
- Unsharing also purges any Explore notifications tied to that post so the
  activity feed cannot route into hidden content.
- `location_sharing` is optional for backward compatibility. If omitted, the
  atomic publication transaction resolves the share from the scan's current
  geoprivacy after locking the exact owner row. A concurrent privacy change
  cannot publish with a stale pre-lock default. Valid values are `open`,
  `obscured`, and `private`; legacy `hidden` is treated as `private`.
- The Explore map reads post-owned public coordinates from `explore_posts`. Only
  posts whose saved `location_sharing` is `open` can appear on the map or match
  non-owned Nearby radius queries. Protected-species and uncertainty rules can
  still store rounded public coordinates with
  `coordinate_visibility = "obscured"`.
- Updating the user's global/default geoprivacy or the backing scan's
  `geoprivacy` later does not overwrite an existing Explore post's explicit
  `location_sharing` choice.

### `/backfill-explore-audio-spectrograms` (Internal)

Service-role-only `POST` worker for historical standalone WAV
`explore_post_media` rows with a null/blank thumbnail. `verify_jwt = false`
allows server automation through the gateway; the function still requires an
exact environment-managed credential through `_shared/serviceRoleAuth.ts`.
Current `sb_secret_...` keys use `apikey` only; legacy service-role JWTs may use
matching Bearer and `apikey` transport. It must never be called by iOS or public
web code.

Request:

```json
{ "limit": 50 }
```

`limit` defaults to 50 and is clamped to 1...200. Oldest candidates run first.
Each successful item reuses or creates the deterministic PNG, updates the
post-owned thumbnail, and best-effort updates the matching normalized scan
asset. The worker does not change moderation, visibility, recording URLs, or
species data.

Response counters are `scanned_count`, `generated_count`, `unsupported_count`,
and `failed_count`, plus bounded per-media `errors`. Repeat bounded calls while
`generated_count` is greater than zero. Non-WAV legacy audio is not selected;
malformed/mislabeled WAV increments `unsupported_count` and retains the playback
fallback.

### `/update-explore-field-notes`

Updates public share options on an already-shared Explore post owned by the
current viewer. Despite the legacy endpoint name, this includes field notes,
hashtags, the public common-name snapshot, and post-level `location_sharing`.
This endpoint does not mutate the private local notes stored in SwiftData; iOS
continues to treat `FieldNotesRepository` as the local source of truth.

Request body:

```json
{
  "post_id": "uuid",
  "field_notes": "Found at the shaded meadow edge after rain.",
  "species_common_name": "Black-Tailed Deer",
  "hashtags": ["deer", "urbanwildlife"],
  "location_sharing": "obscured"
}
```

Response body:

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

Rules:

- Requires an authenticated user through `withEdgeHandler`.
- `post_id` must be a valid UUID.
- `field_notes` may be a string or `null`.
- Empty or whitespace-only strings are normalized to `null`.
- Non-empty notes are trimmed and capped at 1000 characters.
- `species_common_name` is optional. If omitted, the existing
  `explore_posts.species_common_name` snapshot is preserved. If provided, it
  follows the same validation as `/share-scan-to-explore`: string-only, trimmed,
  internal whitespace collapsed, and capped at 200 characters. Empty strings and
  `null` clear the snapshot so read RPCs can fall back to dictionary names.
- `hashtags` is optional and, when provided, replaces the post's public hashtag
  edges using the same normalization as `/share-scan-to-explore`.
- `location_sharing`, when provided, updates only this Explore post. Valid
  values are `open`, `obscured`, and `private`; legacy `hidden` is treated as
  `private`.
- `media_items`, when provided, replaces the post's public media snapshot. New
  clients submit `source_media_id` values from `/get-explore-composer-media`;
  those IDs resolve through the same asset-first source list as
  `/share-scan-to-explore`, so captured-media videos keep their playback `.mp4`
  and poster thumbnail paired during edit/reorder flows. Video `has_audio`
  metadata follows the selected source's actual audio evidence instead of the
  media kind. Legacy URL-based reorders are accepted only for rows already
  present on the post.
- An edit that includes audible media uses the same fail-closed attestation gate
  as initial sharing. Unchanged bytes normally reuse the checksum/model/policy
  decision; replaced bytes or a changed moderation contract call Gemini again.
  Editing text or location without `media_items` does not re-moderate media.
- Changing `location_sharing` reprojects only the post-owned public location
  fields. It does not mutate `scans.geoprivacy` or the user's global default.
- The update is scoped by `explore_posts.id`, `explore_posts.user_id`, and
  `unshared_at IS NULL`; non-owned or unshared posts return 404.

### `/update-public-username`

Updates the current user's canonical public username handle. Usernames are
stored without `@`; clients should render them as `@username`.

Request body:

```json
{
  "username": "@Stone Glen 72"
}
```

Response body:

```json
{
  "username": "stone_glen_72"
}
```

Rules:

- Requires an authenticated user through `withEdgeHandler`.
- Input may include a leading `@`; normalization strips it.
- Whitespace and punctuation separators normalize to underscores.
- The stored username must be lowercase ASCII letters, numbers, and underscores;
  3 to 24 characters; start with a letter; end with a letter or number; and
  contain no repeated underscores.
- Reserved names such as `admin`, `api`, `explore`, `merian`, `support`, and
  `system` are rejected with `400`.
- Duplicate normalized usernames return `409`.
- Alias-source users also have `public_author_name` updated to the username so
  ghost/default Explore rows render as `@username`. Derived/display-name users
  keep their existing Explore display label.

### `/check-public-username`

Validates a candidate username for the current authenticated user without
updating their profile. The endpoint uses the same normalization, reserved-name
rules, and cross-user uniqueness check as `/update-public-username`.

Request body:

```json
{
  "username": "@Stone Glen 72"
}
```

Response body:

```json
{
  "available": true,
  "username": "stone_glen_72",
  "error": null
}
```

Invalid or taken usernames return `200` with `available: false` and an `error`
message for inline UI. The current user's own username is considered available.

### `/get-scan-explore-share-state`

Returns the current viewer's authoritative Explore share mapping for one owned
scan. This endpoint exists to revalidate the Insight sheet's fast local cache
after relaunch or on a second device, so the Share button can switch back to
`View post` when a scan is still live in Explore without relying on device-local
memory alone.

Request body:

```json
{
  "scan_id": "uuid"
}
```

Current response shape:

```json
{
  "data": {
    "scan_id": "uuid",
    "post_id": "uuid",
    "shared_at": "2026-04-29T22:18:03.000Z",
    "community_request_id": "uuid-or-null",
    "community_request_status": "needs_id|resolved|withdrawn|null",
    "is_explore_feed_visible": false,
    "location_sharing": "obscured"
  }
}
```

Behavior notes:

- the Edge wrapper derives owner identity from the validated user JWT; the
  underlying `SECURITY INVOKER` routine is executable only by `service_role`,
  and `PUBLIC`, `anon`, or `authenticated` cannot submit a replacement `self_id`
  directly
- the lookup is owner-only: it reads only scans where `scans.user_id = self_id`
- when a live Explore post exists, `location_sharing` is the post-owned value
  used to hydrate share/edit options
- `community_request_id` and `community_request_status` restore the Identify
  request state for scans that have been made public as community ID requests
- `is_explore_feed_visible` is true only when the post belongs in normal Explore
  feed/map/author/hashtag surfaces, including the same moderation,
  post-media-health, and item-health predicates as the canonical public
  projection
- pending Identify requests and resolved-but-unpublished Identify requests
  return their request state with `is_explore_feed_visible = false`; resolved
  requests become feed-visible only after the owner explicitly publishes them to
  Explore
- a fully media-quarantined or moderated post preserves owner-only `post_id`,
  `shared_at`, and its location choice while returning
  `is_explore_feed_visible = false`, even when there is no Community request; a
  degraded post remains visible when at least one non-missing item is eligible
- when no live post exists, `location_sharing` falls back to the scan's current
  geoprivacy so a new share composer can seed the default option
- the endpoint does not mutate scan or post geoprivacy
- if the scan still has an active Explore publication snapshot, `post_id` and
  `shared_at` are returned even when an independent server visibility boundary
  currently hides it
- if the scan exists but the Explore post was unshared or the scan is no longer
  a valid live snapshot because it was tombstoned, lost every media row, no
  longer resolves to a species, or its owner is shadowbanned, the endpoint
  returns the same `scan_id` with `post_id = null`; Private location sharing
  hides location, not the post
- if the scan no longer exists for the current viewer, the Edge Function still
  returns `200` with `post_id = null` so the client can safely clear stale local
  cache without branching on `404`

### `/set-explore-post-like`

Idempotently toggles liked state for the current viewer and returns:

- `post_id`
- `viewer_has_liked`
- `like_count`

Important regression note: boolean request bodies must treat `liked: false` as a
valid value, not as a missing parameter. The shared `requireParams` helper was
hardened accordingly.

Notification side effects:

- Like notifications are maintained server-side through
  `explore_post_notifications`.
- The server aggregates likes into one row per recipient/post rather than
  inserting one notification row per like.
- Self-likes do not create notifications.

### `/set-user-follow`

Idempotently follows or unfollows a visible Explore author profile.

Request body:

```json
{
  "author_user_id": "uuid",
  "is_following": true
}
```

Response body:

```json
{
  "success": true,
  "author_user_id": "uuid",
  "follower_count": 12,
  "following_count": 4,
  "viewer_is_following": true
}
```

Validation and behavior:

- `author_user_id` is required and must be a UUID.
- `is_following` is required and must be a boolean. `false` is a valid request
  value.
- Self-follow is rejected with `400`.
- Follow inserts require no mutual block, a non-shadowbanned target, and a
  currently visible Explore author profile for the requester.
- Follow writes use the `(follower_user_id, followee_user_id)` primary key and
  are idempotent.
- Unfollow deletes the relationship even if the target profile is no longer
  visible.
- The returned state is authoritative and should replace optimistic client
  counts.

Notification side effects:

- Follow creates a postless in-app notification for the followed user.
- Unfollow removes the corresponding follow notification.
- Blocking either direction removes follow rows and follow notifications.
- Follow notifications are not sent to APNs.

### `/create-explore-comment` and `/delete-explore-comment`

- Create/delete plain-text comments on Explore posts.
- Server-side body cap: 500 characters.
- The response returns the updated `comment_count` so the feed can stay
  optimistic without a full reload.
- The created comment response includes `author_username` from
  `public.users.public_username` and `author_avatar_url` from
  `public.users.public_avatar_url` so the newly-appended row matches the
  subsequent `/get-explore-comments` read payload.
- The created comment response includes `mentions`, an array of resolved
  `@username` tokens from the saved body.
- Mention resolution is scoped to the post author, visible participants in the
  relevant thread, and followed users. It does not allow arbitrary public-user
  tagging.
- The resolver skips self, blocked, shadowbanned, invisible-profile, duplicate,
  and ineligible mentions, then stores at most five unique eligible users.
- Mention notifications use `comment_mention` and are deduped against existing
  `comment` or `comment_reply` notifications for the same recipient/comment.
- Comment notifications are created and removed server-side through triggers on
  `explore_post_comments`.
- Self-comments do not create notifications.

Removal semantics:

- If the current viewer authored the comment, `/delete-explore-comment` sets
  `deleted_at`.
- If the current viewer owns the Explore post but did not author the comment,
  `/delete-explore-comment` performs an owner moderation action by setting
  `moderated_at` and `moderated_by_user_id`.
- Both paths remove the comment from public reads and decrement `comment_count`,
  but they remain distinguishable in the database for auditability.

### `/get-explore-mention-suggestions`

Returns eligible `@username` suggestions for the current comment composer. The
endpoint is intentionally scoped and is not a global public-user search.

Request:

```json
{
  "post_id": "uuid",
  "parent_comment_id": "uuid",
  "query": "as",
  "limit": 8
}
```

- `post_id` is required.
- `parent_comment_id` is optional. When present, it must be a visible top-level
  comment on the same post and thread-participant suggestions are scoped to that
  reply thread.
- Empty or short queries may return the post author and visible thread
  participants.
- Followed-user suggestions require a typed query so the endpoint cannot become
  a follower-list browser.

Response:

```json
{
  "data": [
    {
      "user_id": "uuid",
      "username": "ash_b",
      "display_name": "Ash B.",
      "avatar_url": "https://...",
      "source": "thread"
    }
  ]
}
```

`source` is one of `post_author`, `thread`, or `following`.

### `/toggle-explore-comment-reaction`

Idempotently toggles an emoji reaction for the current viewer on a specific
comment and returns:

- `success`
- `comment_id`
- `emoji`

Request body:

```json
{
  "comment_id": "uuid",
  "emoji": "👍"
}
```

- If the viewer has not yet reacted with this emoji, the reaction is inserted.
- If the viewer has already reacted with this emoji, the reaction is removed.
- Reactions are aggregated into a `reactions` JSON array by the
  `/get-explore-comments` read endpoint.
- The server also maintains aggregated Explore notification rows per
  `(comment author, comment, emoji)` so comment authors can be notified when
  other viewers react.

### `/report-explore-comment`

Creates or updates a moderation report for an Explore comment without removing
it immediately.

- Required body fields: `comment_id`, `reason`
- Optional body field: `details`
- Current allowed `reason` values: `Spam`, `Harassment`,
  `Inappropriate content`, `Other`
- Users cannot report their own comments.
- Duplicate reports by the same user collapse into a single row keyed by
  `(comment_id, reporter_user_id)`.

### `/report-explore-post`

Creates or updates a moderation report for a visible Explore post without
changing the underlying identification review state.

```json
{
  "post_id": "00000000-0000-0000-0000-000000000001",
  "reason": "Inappropriate content",
  "details": "Optional context"
}
```

- Required body fields: `post_id`, `reason`
- Optional body field: `details` (trimmed and capped at 500 characters)
- Allowed reasons: `Spam`, `Harassment`, `Inappropriate content`, `Other`
- Users cannot report their own or an unavailable post.
- Duplicate reports collapse on `(post_id, reporter_user_id)` and preserve an
  existing moderation status rather than reopening dismissed or actioned work.
- Writes only `explore_post_reports`; it never calls `/flag-issue`, inserts an
  identification `flagged_reviews` row, or sets `scans.is_flagged`.
- Returns `HTTP 200` with `success`, `post_id`, and a moderation message.
  Missing authentication returns `HTTP 401`; invalid input or self-reporting
  returns `HTTP 400`; unavailable posts return `HTTP 404`.
- The anonymous public web page does not call this endpoint. Its report action
  opens a support email containing the immutable public post id.

### `/get-explore-notifications`

Returns the viewer's in-app Explore activity feed. The request body is optional:

```json
{
  "limit": 50
}
```

- `limit` defaults to `50` and is capped server-side.
- The ordinary activity read path mirrors Explore visibility rules: unshared
  posts, tombstoned scans, quarantined/media-less posts, shadowbanned owners,
  blocked actors, and soft-deleted comments are filtered out. Owner-scoped
  `media_missing` and `media_restored` lifecycle rows remain visible even while
  the affected post is quarantined. Post `location_sharing` controls public
  location fields, not notification visibility.
- Follow notifications are validated against an active follow relationship and
  blocked or shadowbanned actors are filtered out.
- Community Identification notifications include `community_request_id` plus
  display fields for the current or resolved taxon, and the client routes them
  to the Community request detail instead of regular post detail.
- Field trip activity notifications include `field_trip_publication_id`; the
  client routes them to `FieldTripPublicationDetailView`.
- `media_missing` routes to Scan Library recovery. `media_restored` routes to
  ordinary post detail when the post remains published.
- Pagination is cursor-based on `(updated_at DESC, notification_id DESC)`.
  Follow-up page requests send:

```json
{
  "limit": 50,
  "before_updated_at": "2026-04-27T12:05:00.000Z",
  "before_notification_id": "uuid"
}
```

Current response shape:

```json
{
  "data": [
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "community_request_id": null,
      "field_trip_publication_id": null,
      "type": "like_aggregated",
      "comment_id": null,
      "reaction_emoji": null,
      "triggering_user_id": "uuid",
      "triggering_user_name": "User C",
      "comment_body": null,
      "recent_actor_names": ["User C", "User B"],
      "action_count": 2,
      "is_read": false,
      "community_taxon_common_name": null,
      "community_taxon_scientific_name": null,
      "community_request_display_name": null,
      "created_at": "2026-04-27T12:00:00.000Z",
      "updated_at": "2026-04-27T12:05:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "community_request_id": null,
      "field_trip_publication_id": null,
      "type": "comment",
      "comment_id": "uuid",
      "reaction_emoji": null,
      "triggering_user_id": "uuid",
      "triggering_user_name": "User D",
      "comment_body": "Beautiful find",
      "recent_actor_names": [],
      "action_count": 1,
      "is_read": false,
      "created_at": "2026-04-27T12:06:00.000Z",
      "updated_at": "2026-04-27T12:06:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "community_request_id": null,
      "field_trip_publication_id": null,
      "type": "comment_mention",
      "comment_id": "uuid",
      "reaction_emoji": null,
      "triggering_user_id": "uuid",
      "triggering_user_name": "User M",
      "comment_body": "Looping in @ash_b",
      "recent_actor_names": [],
      "action_count": 1,
      "is_read": false,
      "created_at": "2026-04-27T12:07:00.000Z",
      "updated_at": "2026-04-27T12:07:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "community_request_id": null,
      "field_trip_publication_id": null,
      "type": "comment_reaction",
      "comment_id": "uuid",
      "reaction_emoji": "🔥",
      "triggering_user_id": "uuid",
      "triggering_user_name": "User E",
      "comment_body": "Beautiful find",
      "recent_actor_names": ["User E", "User F"],
      "action_count": 2,
      "is_read": false,
      "created_at": "2026-05-05T10:00:00.000Z",
      "updated_at": "2026-05-05T10:05:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "community_request_id": "uuid",
      "field_trip_publication_id": null,
      "type": "community_request_resolved",
      "comment_id": null,
      "reaction_emoji": null,
      "triggering_user_id": null,
      "triggering_user_name": null,
      "comment_body": null,
      "recent_actor_names": [],
      "action_count": 1,
      "is_read": false,
      "community_taxon_common_name": "Pinwheel",
      "community_taxon_scientific_name": "Aeonium haworthii",
      "community_request_display_name": "Pinwheel",
      "created_at": "2026-06-20T19:30:00.000Z",
      "updated_at": "2026-06-20T19:30:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": null,
      "community_request_id": null,
      "field_trip_publication_id": "uuid",
      "type": "field_trip_comment",
      "comment_id": "uuid",
      "reaction_emoji": null,
      "triggering_user_id": "uuid",
      "triggering_user_name": "User T",
      "comment_body": "Great Field trip.",
      "recent_actor_names": [],
      "action_count": 1,
      "is_read": false,
      "created_at": "2026-07-08T16:00:00.000Z",
      "updated_at": "2026-07-08T16:00:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": null,
      "community_request_id": null,
      "field_trip_publication_id": null,
      "type": "follow",
      "comment_id": null,
      "reaction_emoji": null,
      "triggering_user_id": "uuid",
      "triggering_user_name": "User F",
      "comment_body": null,
      "recent_actor_names": [],
      "action_count": 1,
      "is_read": false,
      "created_at": "2026-05-11T16:10:00.000Z",
      "updated_at": "2026-05-11T16:10:00.000Z"
    }
  ]
}
```

`post_id` is nullable because follow notifications and Field trip activity are
not Explore-post-backed. Field trip activity rows include
`field_trip_publication_id` and route to `FieldTripPublicationDetailView`;
follow rows remain informational and do not attempt post navigation.

### `/get-explore-unread-notification-count`

Returns the unread bell badge count for visible Explore and Field trip in-app
activity notifications:

```json
{
  "unread_count": 3
}
```

Unlike most read endpoints, this response returns the scalar at the top level
rather than nesting it under `data`.

The iOS client coordinates this request globally through
`AppIconBadgeCoordinator`. Concurrent callers await one in-flight request, and a
successful count may be reused for 10 seconds. Explore-post activity uses
Realtime as the primary refresh path, while routine five-minute polling also
covers Field trip-only rows, missed events, and subscription failure. Realtime
events and notification-sheet dismissal force a fresh count. Keep the server
endpoint side-effect-free so this deduplication remains safe.

### `/mark-explore-notifications-read`

Marks the viewer's Explore notifications as read and returns the number of rows
updated:

```json
{
  "success": true,
  "marked_count": 3
}
```

The current iOS client calls this only after `/get-explore-notifications`
succeeds, matching the shipped "clear the unread badge when the sheet opens
successfully" behavior.

### `/register-push-device`

Registers or refreshes the current iOS device for optional remote Explore
activity pushes:

```json
{
  "device_token": "lowercasehex...",
  "platform": "ios",
  "environment": "sandbox",
  "explore_enabled": true,
  "comment_mentions_enabled": true,
  "community_identifications_enabled": true
}
```

- The endpoint is authenticated with the viewer's existing Supabase session,
  just like the other Explore nodes.
- `device_token` is normalized to lowercase and upserted by
  `(device_token, platform, environment)`. It must contain only hexadecimal
  characters and be 32...512 characters long. The Edge Function may express that
  complete policy as the JavaScript regex `/^[0-9a-f]{32,512}$/i` because
  JavaScript accepts that repetition bound. PostgreSQL enforces the same policy
  as separate format and length constraints because its regex engine rejects
  repetition bounds above 255. Do not "repair" the valid Edge Function regex or
  recombine the database checks.
- `explore_enabled` is feature-specific. Users can opt into Explore activity
  pushes without also enabling discovery-result alerts. New installs default
  this setting on.
- `comment_mentions_enabled` is optional for compatibility with older clients.
  New installs default this setting on. When omitted, the server treats the
  mention preference like the submitted `explore_enabled` value for older
  clients. When present, `comment_mention` payloads require
  `comment_mentions_enabled` to be true. Other Explore activity payloads require
  `explore_enabled` to be true.
- `community_identifications_enabled` is optional for compatibility with older
  clients. New installs default this setting on. When omitted, the server treats
  the Community preference like the submitted `explore_enabled` value for older
  clients. Community Identification payloads require
  `community_identifications_enabled` to be true.
- The server stores these rows in `public.user_push_devices`. Delivery failures
  from APNs feed back into that table via `last_error_*` fields and `is_active`.
- Migration `20260720174209_fix_push_device_token_constraint.sql` is a
  database-only repair. It does not require an Edge Function deployment. After
  applying it, the next notification-permission/token synchronization retries
  registration through the existing function.

### iOS Mapping

The Explore client decodes these endpoints via:

- `apps/ios/Merian/Core/Network/ExploreAPIModels.swift`
- `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExploreFeedViewModel.swift`
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExploreFeedViewModel+Interactions.swift`
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExploreFeedViewModel+Notifications.swift`
- `apps/ios/Merian/Features/Explore/Map/ViewModels/ExploreMapViewModel.swift`
- `apps/ios/Merian/Features/Explore/Notifications/ViewModels/ExploreNotificationsViewModel.swift`
- `apps/ios/Merian/Features/Explore/Notifications/Models/ExploreNotification.swift`
- `apps/ios/Merian/Features/Explore/AuthorProfile/Views/ExploreAuthorProfileSheet.swift`
- `apps/ios/Merian/Features/Explore/Map/Views/ExploreMapView.swift`
- `apps/ios/Merian/Features/Explore/Shell/ExploreView.swift`

The current feed UI uses only a subset of the payload for visible card
rendering:

- `author_name`
- `author_username`
- `author_avatar_url`
- `public_location_label`
- `species_common_name` (displayed through `ExploreFeedViewModel`'s
  SwiftData-backed preferred-name cache when the viewer has a
  `UserSpeciesPreference`; dog/cat pet labels can sit above this display
  resolver when `pet_identification` is present)
- `species_scientific_name`
- `pet_identification`
- `hero_image_url`
- `reference_thumbnail_url` (author-post grids; nullable species reference image
  used for audio-backed compact thumbnails)
- `hashtags`
- `like_count`
- `comment_count`
- `viewer_has_liked`

The Explore detail page additionally uses:

- `/get-explore-post` for notification-driven navigation into posts that are not
  already loaded in the current feed page
- `/get-explore-post-detail` for taxonomy and habitat/distribution data
- `/get-explore-hashtag-posts` when a feed or detail hashtag chip opens its
  visible tagged-post collection
- `time_of_day` + `current_month` to derive broad public observation context
  such as `Morning • April`
- `weather_condition` + `weather_temperature_f` for optional public weather
  telemetry
- `/get-explore-comments` for the inline thread and composer state
- `/get-explore-comment-replies` for reply pagination under top-level comments
- `/get-explore-mention-suggestions` for trailing-token `@username` autocomplete
- `mentions` from comment and reply rows for tappable mention spans that open
  `ExploreAuthorProfileSheet`
- `author_username` from post/profile/comment rows for stable handle display and
  default/ghost author labels
- `author_avatar_url` from comment rows for both `ExploreCommentsSheet` and
  `ExplorePostDetailView`
- cursor-based comment pagination on `(created_at, comment_id)` so long threads
  page safely in both the sheet and detail view
- `/get-explore-unread-notification-count` for the bell badge and
  `/get-explore-notifications` plus `/mark-explore-notifications-read` for the
  in-app activity sheet
- cursor-based activity pagination on `(updated_at, notification_id)` so the
  notifications sheet does not skip or duplicate rows during active usage
- `/set-user-follow` to apply public author Follow/Following state from
  `ExploreAuthorProfileSheet`
- `/check-public-username` and `/update-public-username` from the Profile
  account card username editor
- `/register-push-device` to sync the APNs token, the Explore-specific push
  preference, the independent comment mention push preference, and the
  independent Community identification push preference

The Explore map additionally uses:

- `/get-explore-map-points` for cluster or waypoint payloads in the current
  visible region
- `ExploreMapPointsResponse`, `ExploreMapCluster`, and `ExploreMapPost` from
  `ExploreAPIModels.swift`
- `ExplorePostStore` as the shared in-memory post state layer, so likes,
  unshares, reports, and blocks stay synchronized between the feed tab, map
  preview card, detail route, and notification-driven navigation
- a two-step interaction in `ExploreMapView`: tap a waypoint to select and
  preview, then open `ExplorePostDetailView`
- a zoom-aware annotation treatment in `ExploreMapView`, where cluster payloads
  stay aggregate at broad zooms and individual `ExploreMapPost` payloads can
  render either simple dots or thumbnail-backed markers depending on the current
  client camera zoom and visible post count

Time and weather metadata remain in the contract for future Explore presentation
experiments, but are not currently rendered on the primary feed card.

Remote Explore APNs delivery is layered on top of this contract through the
internal `send-push-notification` webhook path. That webhook is not called by
the iOS client directly; it is triggered server-side from
`public.explore_post_notifications`. Follow notifications are excluded from push
dispatch and remain in-app only. Comment mention pushes are dispatched only to
devices with `comment_mentions_enabled` enabled; regular Explore activity pushes
use `explore_enabled`. Community Identification pushes include
`communityRequestId` and use `community_identifications_enabled`. The in-app
notification row is still retained even when the related push toggle is off.
`media_missing` uses the ordinary Explore preference and dispatches only when
the incident row is first inserted. `media_restored` remains in app only. Each
APNs delivery has a 10-second deadline, a 4 KiB diagnostic-body ceiling, and an
`apns-collapse-id` equal to the durable notification UUID. Replaying the same
notification therefore does not intentionally create a second presented push.

Preferred species display names are not part of the Explore endpoint payload.
The iOS client syncs `user_species_preferences` directly through PostgREST under
Supabase RLS, hydrates
`ExploreFeedViewModel.preferredSpeciesNamesByScientificName` from local
SwiftData, and applies those names in feed cards, map previews, comments, detail
titles, and share text.

---

## Deno `/identify-multimodal` Edge Node

A unified identification pipeline that merges the active capabilities of
`/identify` and the app's shipped non-visual flows into a single multi-modal
entry point. The current iOS client routes new inference traffic here. Supports
ordered compositions of images, audio, and descriptive context.

### The JSON Request Payload (From Swift `OfflineQueueManager`)

```json
{
  "r2ObjectKeys": [
    "staging/A1B2C3D4.../uuid_image_1.webp"
  ],
  "videoR2ObjectKeys": [
    "staging/a1b2c3d4.../uuid_video_1.mp4"
  ],
  "videoFrameCount": 5,
  "visualMediaItems": [
    {
      "kind": "image",
      "sourceIndex": 0,
      "focusRegion": {
        "x": 0.125,
        "y": 0.25,
        "width": 0.5,
        "height": 0.4,
        "source": "vision_objectness"
      }
    },
    { "kind": "video_frame", "clipIndex": 0, "frameIndex": 0 },
    { "kind": "video_frame", "clipIndex": 0, "frameIndex": 1 },
    { "kind": "video_frame", "clipIndex": 0, "frameIndex": 2 },
    { "kind": "video_frame", "clipIndex": 0, "frameIndex": 3 },
    { "kind": "video_frame", "clipIndex": 0, "frameIndex": 4 }
  ],
  "audioMediaItems": [
    { "kind": "video_audio", "clipIndex": 0 }
  ],
  "audioR2ObjectKeys": [
    "staging/a1b2c3d4.../uuid_audio.wav"
  ],
  "imageBase64s": ["<base64>"],
  "audioBase64s": ["<base64>"],
  "user_id": "Supabase Auth UUID",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "semanticLocation": "Zilker Park",
  "publicLocationLabel": "Austin, Texas",
  "geoprivacy": "obscured",
  "weatherCondition": "Partly Cloudy",
  "weatherTemperatureF": 68.0,
  "deviceLocale": "en",
  "deviceTimeZone": "America/Chicago",
  "deviceRegion": "US",
  "currentMonth": 4,
  "timeOfDay": "10:30 AM",
  "depthScaleText": "1.3 meters",
  "zoomFactor": 2.0,
  "estimated_size_cm": 11.5,
  "timestamp": "2026-03-21T09:46:03.000Z",
  "observation_contexts": [
    {
      "freeText": "Heard rustling before spotting it",
      "addedAt": "2026-03-21T09:45:20.000Z"
    }
  ]
}
```

- Features dynamic `MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION` execution if audio
  and visual evidence are both present, regardless of whether the audio arrived
  inline, from R2 staging, or as extracted audio from a video scan.
- Video scans send five ordered sampled frames through the image payload path,
  extracted accompanying audio through the audio payload path when available,
  and stage the upload-bounded playback `.mp4` in `videoR2ObjectKeys`. That
  staged video is normally a compressed 720p export, but clients may fall back
  to the original recording when it is already within the hard video byte cap.
  New clients send `visualMediaItems` (or snake-case `visual_media_items`) with
  one entry per resolved visual input so the prompt can distinguish still photos
  from ordered `video_frame` samples by `clipIndex` and `frameIndex`;
  `audioMediaItems` (or `audio_media_items`) identifies standalone audio versus
  `video_audio` by `clipIndex`. If the visual metadata count does not match the
  resolved image count, the edge ignores it and falls back to the legacy
  `videoFrameCount` hint; if the audio metadata count does not match the
  resolved audio buffer count, the prompt treats the audio as ordinary
  standalone audio. The playback clip is promoted only after those frames pass
  moderation and is not used as Gemini inference or reference-media input. If
  `videoR2ObjectKeys` is non-empty, the scan is only successful when every
  requested video key is promoted and persisted into `video_storage_urls` and
  `captured_media`; otherwise the client receives a retryable failure rather
  than a frame-only video scan. Uploads signed with `clientScanId`/`mediaRole`
  already have staged `scan_media_assets` rows; this endpoint links those rows
  to the scan as durable media, marks consumed extracted `video_audio` rows
  `deleted`, and marks failed finalization rows `failed`.
- Still-photo descriptors may include `focusRegion` using top-left-normalized
  coordinates for the same complete post-crop image. The edge accepts only
  finite positive rectangles contained within `[0, 1]` with
  `source = vision_objectness`; invalid regions and all video-frame regions are
  stripped without rejecting the scan. Valid regions add a primary-subject hint
  to that photo's prompt entry while the full image remains the only Gemini
  visual part. The sanitized region survives `scan_ingestion_intents` replay; no
  raw image bytes or completed-scan field are added.
- Before inference work starts, the endpoint claims a `scan_ingestion_jobs` row
  for the authenticated user and `client_scan_id`. The claim records media
  counts, genuine staged image/audio/video source keys, recovered upload-session
  ids, and a normalized `manifest_checksum`; subsequent stage updates make
  `/check-scan-status`, health checks, and reconciliation agree on whether the
  scan is processing, retryable, complete, or terminal. Claim and compatibility
  owner-row recovery share one transaction-scoped advisory lock for that scan. A
  recovery-first winner writes a completed recovery ledger, causing claim to
  return `already_complete` before any provider call and the route replays the
  completed owner response as `200`; a claim-first winner makes recovery defer.
- Before normal retry work, a failed post-insert generation can invoke
  `recover_inline_scan_ingestion_completion`. The service-only routine repairs
  only an exact already-owned job/intent/media topology. Redacted inline-image
  counts prove when an image key was merely a historical filename hint; zero
  inline-image bytes prove queued image keys are real sources. Every real
  image/audio/video key requires one exact active owner upload row and a
  one-to-one canonical URL filename match. Only migration-marked superseded
  registration rows may coexist. Sanitized audio descriptors prove standalone
  promotion versus companion deletion. Ambiguous shapes return `not_applicable`;
  exact shapes recompute both ledgers and call the canonical finalizer in one
  transaction.
- Before that claim, staged-media resolution, or quota reservation, the endpoint
  checks for a stored completion or an exact reconstructible owner row. A
  lost-response retry returns the stored canonical envelope, or reconstructs the
  exact durable owner row through the executable response contract even while
  its canonical ledger remains retryable. Concurrent quota conflicts coalesce
  for at most 70 seconds. Successful replay carries
  `X-Merian-Idempotent-Replay: stored|reconstructed` and cannot dispatch Gemini.
- The endpoint also records a `scan_ingestion_intents` row for server recovery.
  That row stores a sanitized replay payload with telemetry, observation
  context, media descriptors, staged keys, upload-session ids, and a
  `payload_checksum`. It never stores raw base64 media bytes or local device
  paths. Requests that used inline foreground media are marked
  `resumable = false` with `inline_media_redacted = true`; queued/staged
  media/audio/video and text-only requests are resumable. Server-side replay of
  those resumable intents is capped at 10 automatic claims before the paired job
  becomes `failed_terminal / server_replay_limit_reached` with
  `terminal_reason_code = replay_exhausted`.
- Completion is one service-only transaction. It validates every submitted
  promoted/deleted key against the claimed media manifest, permits deletion only
  for claimed audio companions, locks the owner scan, rebuilds canonical media,
  verifies every promoted capture URL has a matching ready image/video/audio
  row, writes `media_finalization_complete` last, and immutably stores the
  validated success envelope through the response-aware wrapper. Replay and
  media reconciliation use this routine rather than updating the ledger
  directly. Scan deletion clears the envelope at tombstone insertion before
  asynchronous media erasure starts.
- The edge writes `captured_media` for new multimodal scan rows. That JSON keeps
  still photos as image items but collapses ordered `video_frame` samples into a
  single video media item with a thumbnail reference, preserving playback-first
  Insight hydration for biological and non-biological video scans. The video
  item carries an audio reference only when extracted video audio exists, so
  downstream `scan_media_assets` and Explore rows can set `has_audio`
  accurately. The required finalization transaction refreshes ready
  display/playback `scan_media_assets` rows from the same manifest and proves
  them before completion, so server-side composer and status checks no longer
  need to infer video assets directly from sampled frame arrays.
- Executes `processWAV` in Deno to enforce mono/16kHz processing before Gemini
  ingestion.
- Queued replay audio uses `audioR2ObjectKeys`; queued and live video use
  `videoR2ObjectKeys`; live foreground audio uses size-preflighted inline
  `audioBase64s`. The edge rejects oversized declared media JSON
  `Content-Length` before body parsing, then parses through
  `readRequestJsonWithinBudget` so missing-length/chunked bodies are still
  capped. Clip count, byte budgets, IDOR ownership, and path traversal are
  validated through `_shared/identify/media.ts` before decode/fetch.
- The canonical request contract is camelCase telemetry (`gpsLatitude`,
  `semanticLocation`, `publicLocationLabel`, `geoprivacy`, `deviceTimeZone`,
  etc.) plus `observation_contexts: [{ freeText, addedAt? }]`, matching
  `MerianNetworkClient.buildMultiModalRequest(...)` and the iOS
  `ObservationContext` model. The same Swift inference payload builder also
  backs `/identify` so visual and multimodal requests share telemetry
  formatting, user context, and pre-serialization inline media budget
  validation.
- If `geoprivacy` is missing, invalid, or supplied by an old queued payload, the
  Edge insert helper resolves the scan privacy from `users.default_geoprivacy`.
  Private scans clear `public_location_label` server-side even if a stale client
  supplied one.
- `deviceTimeZone` is persisted to `public.scans.device_time_zone` when present
  so public profile streaks and heatmaps can use the author's local day
  boundary. Missing or invalid legacy rows fall back to UTC at profile-read
  time.
- The server still accepts legacy snake_case telemetry aliases (`gps_latitude`,
  `semantic_location`, `time_of_day`, etc.) and legacy `free_text` context keys
  so offline queue replays and older internal tooling do not break
  mid-migration.
- Candidate handling now matches `/identify`: the response strips `candidates`
  when `confidence_score >= diagnosticTrigger`, enriches forwarded candidates
  with cached English common names when available, and schedules background
  enrichment for cache misses.
- The multimodal durable-ingestion path shares the same `_shared/identify` DB,
  media, schema, threshold, and moderation primitives as `/identify`.

The Gemini object and final server-enriched response are both parsed through
`_shared/identify/contract.ts`. The second parse occurs before durable image or
video finalization and HTTP success, so cache/provider drift cannot reach the
generated Swift decoder or durable scan state. Contract failures use stable
public code `identify_response_invalid`; detailed path errors remain in
structured server logs.

### Latency and Authentication Contract

The request and JSON response bodies remain backward-compatible. The endpoint
adds only diagnostic response headers:

- `Server-Timing`: `auth`, `body_read`, `tier`, `pre_gemini_db`, `gemini`,
  `dictionary`, `post_gemini`, and `edge_total` durations in milliseconds.
- `X-Merian-Edge-Region`: the runtime region reported by the Edge environment,
  when available.

The request may include `X-Merian-Constrained-Network: true|false` for aggregate
latency segmentation. Logs and headers never contain user ID, scan ID, species,
location, media keys, or request contents. `gemini` stops immediately after the
single `generateContent` call returns.

`/identify-multimodal` verifies the bearer token with the cached ES256 JWKS path
through `auth.getClaims(token)`, then explicitly validates issuer, audience,
expiration, not-before, role, and `sub`. Both anonymous and authenticated user
JWTs are accepted. Service-role tokens are rejected on this public endpoint. The
request body's `user_id` is never an authority source. The existing
`X-Merian-Internal-Replay` path is checked before public claims auth and retains
its exact platform-managed service-key verification plus explicit replay-user
header. Legacy service-role JWTs use Bearer transport; named non-JWT
`sb_secret_...` values use `apikey` only. The accepted request value is not
reused by the privileged database client.

Before Gemini, one service-role-only `begin_scan_ingestion` RPC performs upload
session lookup, ingestion claim, sanitized intent recording, and the
`ai_inference_started` stage transition atomically. It returns the recovered
upload-session ids plus manifest and payload checksums canonicalized from the
exact stored values. This is also the pre-provider boundary for `/identify`,
`/identify-describe`, and `/audio-spec`; no route falls back to separate writes.
The client fails closed on malformed UUID/checksum/stage/completion output.
After Gemini, eligible biological results use at most one
`hydrate_identification_dictionary` RPC to return cached primary-species data
and candidate common names. Primary Wikipedia/GBIF cache misses, moderation,
required media promotion, and scan insertion complete before success for every
current multimodal observation. Analytics, group tags, and candidate enrichment
remain optional `EdgeRuntime.waitUntil` work.

## Deno `/update-scan-context` Edge Node

Adds late WeatherKit/geocoding data to the owner's active ingestion job or
completed scan without rerunning identification.

### Request Payload

```json
{
  "scan_id": "A1B2C3D4-0000-4000-8000-000000000000",
  "gps_elevation": 42.5,
  "weather_condition": "Partly Cloudy",
  "weather_temperature_f": 68.0,
  "semantic_location": "Zilker Park"
}
```

`scan_id` is required and must be a UUID. Every other field is optional, but at
least one valid late-context field must be present. The endpoint accepts
camelCase aliases and normalizes them before the database call. Empty strings
and non-finite/out-of-range numeric values are omitted; a request with no valid
context returns `400`.

### Response

```json
{ "success": true, "applied": true }
```

`applied` is `true` when the owner's scan already exists and `false` when the
update is staged until ingestion creates it. The endpoint verifies the same
anonymous/authenticated user claims as `/identify-multimodal`. The
service-role-only `apply_or_stage_scan_context` RPC owns the update, so a caller
cannot attach context to another user's scan.

The route returns `409` when neither the owner scan nor its ingestion claim is
visible yet. The iOS live path retries once after 500 ms and preserves the same
context in the durable local queue; this condition never causes a second
identification request.

## Text-Only Describe Path

The current app routes text-only observations through `/identify-multimodal`
with `observation_contexts` populated and no images or audio attached. Locally,
that request is still assembled from the same canonical mixed-media timeline
used by image and audio submissions; the server simply receives an empty media
body plus the description payload.

### Request Payload

```json
{
  "user_id": "Supabase Auth UUID",
  "client_scan_id": "UUID generated by iOS for idempotency",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "semanticLocation": "Zilker Park",
  "publicLocationLabel": "Austin, Texas",
  "geoprivacy": "obscured",
  "weatherCondition": "Partly Cloudy",
  "weatherTemperatureF": 68.0,
  "deviceLocale": "en",
  "deviceTimeZone": "America/Los_Angeles",
  "deviceRegion": "US",
  "currentMonth": 4,
  "timeOfDay": "10:30 AM",
  "timestamp": "2026-04-14T10:30:00.000Z",
  "observation_contexts": [
    {
      "freeText": "Medium-sized bird, vivid blue upperparts, rust-orange breast, perched on fence post in suburban garden. Heard a clear flute-like song before spotting it.",
      "addedAt": "2026-04-14T10:29:45.000Z"
    }
  ]
}
```

`client_scan_id` is generated by the iOS client and forwarded as
`generatedScanId` to the edge function. The current multimodal text-only path
inserts through the shared `insertScan` contract using the same idempotent scan
ID semantics as image and audio requests.

The current iOS client does not send a top-level `description` field on this
path. The edge function concatenates the `observation_contexts[*].freeText`
entries into the multimodal prompt server-side. The first structured context
object is also persisted to `public.scans.user_observation_context` for
scan-level provenance. The iOS client guards on `ObservationContext.isEmpty`
before allowing submission.

Legacy `/identify-describe` requests still use a top-level `description` field,
but that compatibility endpoint records a multimodal-shaped
`scan_ingestion_intents` row before returning success. Retryable text-only
compatibility rows therefore recover through `/identify-multimodal` with the
same `client_scan_id`.

`r2ObjectKeys`, `imageBase64s`, and `audioBase64s` are intentionally absent —
there is no media in a text-only submission. `scans.image_storage_urls` is
written as an empty image array by the shared insert path because there is no
promoted media to persist.

### Response Schema

The response shape mirrors the `/identify` / `/identify-multimodal` JSON
response exactly and is validated by the same executable final wire contract.
The Describe provider schema is generated from a text-only contract variant that
requires every `image_quality` value to be exactly zero. `scan_id` is returned
as the scan UUID generated for that text-only request.

### IDOR & Auth

The server extracts the user identity from the verified `Authorization: Bearer`
JWT claims. The `user_id` in the request body is ignored for auth purposes.

### Error Responses

| Status | Body                                                                                               | Meaning                                                                            |
| ------ | -------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `400`  | `{ "error": "At least one media element or description is required" }`                             | No image, audio, or non-empty `observation_contexts[*].freeText` text was provided |
| `400`  | `{ "error": "AI processing error. Please try again." }`                                            | Permanent Gemini safety / policy failure                                           |
| `503`  | `{ "error": "Processing Error: Malformed AI response." }`                                          | Gemini returned malformed or structurally invalid output; delivery may retry       |
| `502`  | `{ "error": "AI response validation failed. Please retry.", "code": "identify_response_invalid" }` | Final server-enriched payload violated the wire contract                           |
| `503`  | `{ "error": "AI processing error. Please try again." }`                                            | Transient Gemini failure                                                           |

---

## Deno `/enrich-scan` Edge Node

An enrichment endpoint that asynchronously surfaces habitat, taxonomy, and
similar species data for a scan. Called automatically by the iOS client after
every successful biological scan completes — the user sees a loading skeleton in
`HabitatAndDistributionCard` while this request is in flight.

### Request Payload

```json
{
  "scan_id": "A1B2C3D4-...",
  "scientific_name": "Danaus plexippus",
  "confidence_score": 0.91,
  "inference_tier": "flash"
}
```

Only `scientific_name` is strictly required by the Edge function. `scan_id`,
`confidence_score`, and `inference_tier` are sent by the iOS client for
telemetry but are not used server-side — the Edge function applies no confidence
gating of its own.

### Architecture

**No Tier Gate**: Available to all authenticated users. Enrichment data is
generated by Flash and cached in `species_dictionary` at the species level —
subsequent calls for the same species are served from cache with no AI call.

**No Confidence Gate**: The Edge function accepts `confidence_score` for
telemetry compatibility but does not use it to decide whether similar species
should be generated or returned. Similar-species generation is gated by taxonomy
quality and cache state, not confidence, and the iOS gallery renders validated
entries with the stable "Similar species" label.

**Full Cache Hit**: If `species_dictionary` already has `habitat_description`,
usable taxonomy (`kingdom` plus `order` or `family`), and validated
`species_lookalikes` rows for this species, the function returns all data
immediately with no Gemini calls — typically sub-50ms.

**Two-Layer Lookalike Strategy**:

- **Layer 1 — Taxonomy trigger (zero token cost)**: A Postgres `AFTER INSERT`
  trigger (`trg_link_taxonomy_lookalikes`) auto-populates `species_lookalikes`
  with same-genus links whenever a new species row is inserted, but only when
  both rows have a real genus and matching kingdom. Placeholder taxonomy such as
  `"Unknown"` is normalized away and never participates in trigger linking.
- **Layer 2 — Gemini Flash for cross-family visual mimics**:
  `fetchSimilarSpecies` is only invoked when the `species_lookalikes` join table
  is empty, `similar_species TEXT[]` has no usable legacy names, and the primary
  species already has usable taxonomy. Flash receives the species' normalized
  taxonomy (`kingdom`, `class`, `order`, `family`) from `cachedSpecies` and is
  constrained by the system instruction to return lookalikes from the **same
  taxonomic order** — not merely the same kingdom. After Gemini returns entries,
  `resolveLookalikesToJoinTable` validates the candidates again before writing
  anything durable.

**Taxonomy Grounding (`fetchSimilarSpecies` + `resolveLookalikesToJoinTable`)**:
Flash is passed normalized `kingdom`, `class`, `order`, and `family` from
`species_dictionary`. Placeholder strings like `"Unknown"` or blank values are
collapsed to `null` before prompting. The system instruction explicitly forbids
cross-order results (e.g. grasses as lookalikes for Narcissus — both Plantae but
different orders). `resolveLookalikesToJoinTable` now requires a real
`primaryKingdom` and at least one higher-rank discriminator (`primaryOrder` or
`primaryFamily`). Each resolved candidate must have a real matching `kingdom`,
and then either a matching `order` or, if order is unavailable on both sides, a
matching `family`. Candidates with missing taxonomy or no `species_dictionary`
row are dropped rather than returned as provisional stubs. **Early-exit on
insufficient taxonomy**: If the primary species lacks usable taxonomy, the
lookalikes scope returns `similar_species: null` and does not call Flash.
`lookalikes_flash_attempted` is **only** set to `true` when
`resolveLookalikesToJoinTable` returns `persisted: true`, ensuring the flag
never locks before validated data is in the join table.

**Automatic Stale Contamination Detection**: On each `lookalikes` scope request,
`index.ts` compares the primary species' normalized `order` or `family` against
cached join-table entries. If the primary species has a known `order` and every
cached entry has a different known order, or if order is unavailable but family
is known and every cached entry has a different known family, the stale rows are
automatically cleared via `clearLookalikesForSpecies`,
`lookalikes_flash_attempted` is reset to `false`, and a fresh validated attempt
can run. This is self-healing for the characteristic contamination signature
created by old placeholder-taxonomy writes.

**Manual Cache Invalidation**: For one-off fixes, cross-order (or cross-kingdom)
lookalikes cached before the automatic detection was introduced can still be
cleared manually:

```sql
DELETE FROM species_lookalikes
WHERE species_id = (SELECT id FROM species_dictionary WHERE scientific_name = '<scientific_name>');
UPDATE species_dictionary SET similar_species = NULL, lookalikes_flash_attempted = FALSE
WHERE scientific_name = '<scientific_name>';
```

The next `enrich-scan` call will re-run Flash only after the species has usable
taxonomy.

**Migration Path**: If the join table is empty but `similar_species TEXT[]` has
legacy name strings (populated by older pipeline versions), they are resolved to
the join table at zero token cost before returning, using the same
kingdom/order/family validation as fresh Flash output.

**Parallel Flash Generation**: If enrichment data is missing, encyclopedic
enrichment (`fetchStaticEncyclopedicData`) and similar species generation
(`fetchSimilarSpecies`) can still run concurrently via `Promise.all`. Both use
`gemini-2.5-flash` with `temperature: 0.1`. The difference now is that
lookalikes only participate in that parallel branch when the primary species
already has usable taxonomy; otherwise the function returns metadata first and
the iOS client retries the lookalikes scope once taxonomy lands.

### Response Schema

```json
{
  "success": true,
  "data": {
    "habitat_description": "Frequently spotted in milkweed patches, meadows, and open plains.",
    "gbif_taxon_key": 5130978,
    "alternative_common_names": ["Monarch", "Common Tiger"],
    "similar_species": [
      {
        "species_id": "uuid",
        "scientific_name": "Limenitis archippus",
        "common_name": "Viceroy",
        "reference_image_url": "https://inaturalist-open-data.s3.amazonaws.com/...",
        "iucn_red_list_status": "LC",
        "reason": "Similar orange-and-black wing pattern.",
        "visual_traits": ["orange wings", "dark venation"],
        "confidence": 0.86,
        "source": "model_enrichment",
        "review_status": "unreviewed",
        "is_bidirectional": false,
        "sort_order": 0
      },
      {
        "species_id": "uuid",
        "scientific_name": "Danaus gilippus",
        "common_name": "Queen",
        "reference_image_url": "https://inaturalist-open-data.s3.amazonaws.com/...",
        "iucn_red_list_status": null
      }
    ],
    "taxonomy": {
      "kingdom": "Animalia",
      "phylum": "Arthropoda",
      "class": "Insecta",
      "order": "Lepidoptera",
      "family": "Nymphalidae",
      "genus": "Danaus"
    }
  }
}
```

`gbif_taxon_key` is `null` when the species has not yet been matched by GBIF.
`similar_species` is `null` when no validated lookalike data is available,
including the intentional case where the species still lacks usable taxonomy.
Each entry in the `similar_species` array is sourced from the
`species_lookalikes` join table joined to `species_dictionary` — providing
`species_id`, `common_name` (English), `reference_image_url`,
`iucn_red_list_status`, and additive relation metadata (`reason`,
`visual_traits`, `confidence`, `source`, `review_status`, `is_bidirectional`,
`sort_order`) when available. The image URL prefers the first
`species_reference_images` row and falls back to the legacy dictionary cache.
Raw Gemini names with no dictionary/taxonomy validation are no longer returned
or persisted; legacy `similar_species TEXT[]` fallbacks may omit `species_id`
and relation metadata until they are resolved into the join table. Successful
enrichment writes also record source/freshness metadata in
`species_content_provenance`; this does not change the client response.

`alternative_common_names` is `string[] | null` — `null` when GBIF has no
English vernacular entries for the species. The enrichment scope serves this
field from `species_dictionary.alternative_common_names` on a cache hit. When
that column is `null` (covering pre-V34 cached species, compatibility-route
timing, or a current model response that preceded its awaited dictionary
resolution), the Edge function calls `fetchGBIFVernacularNames` live to retrieve
English vernacular names from the GBIF API and populates the field from the
result. Taxonomy fields in the response likewise use `null` for unknown ranks;
the backend no longer emits placeholder strings like `"Unknown"`.

**iOS mapping**: The array is decoded as
`[EnrichScanResponse.SimilarSpeciesEntry]` (snake_case Codable DTO in
`InferenceEdgeDTOs.swift`) and mapped to the domain `SimilarSpecies` struct
(camelCase, in `SpeciesData.swift`). `InferenceEngine.fetchAndApplyEnrichment`
then JSON-encodes `[SimilarSpeciesEntry]` via `JSONEncoder` into a `Data` blob
and persists it as `LocalScanRecord.lookalikesData` (added in `MerianSchemaV27`)
— the primary SwiftData storage for rich lookalike data. The legacy
`LocalScanRecord.similarSpecies: [String]?` field is retained as a
backwards-compatible fallback for pre-V27 records where `lookalikesData` is nil.
`InferenceEngine.load(from:)` also supports a one-time local cache reset version
so previously poisoned `lookalikesData` blobs are ignored and refreshed through
the hardened backend validation path. `SimilarSpeciesGallery` always labels
validated entries as "Similar species"; identification uncertainty is handled by
the separate candidates/review surface.

**Authoritative quota**: Cache hits perform no paid provider work and consume no
AI quota. A cache miss reserves either `scan_overview_enrichment` or
`scan_lookalike_enrichment` before generation. Their shared UTC-day ceilings are
4 for free, 100 for Pro trial, and 500 for paid Pro, with additional shared
per-user/IP minute ceilings. iOS uses the stable scan UUID as the
`Idempotency-Key` for both scopes (the operation is part of the database
namespace), so later app-level retries cannot allocate a fresh reservation.
Provider attempts consume quota even if the provider response is malformed; a
pre-provider cache/no-op path may refund.

### Error Responses

| Status      | Body                                                                | Meaning                                       |
| ----------- | ------------------------------------------------------------------- | --------------------------------------------- |
| `400`       | `{ "error": "Missing required parameters..." }`                     | Required enrichment input absent              |
| `400`       | `{ "code": "ai_request_id_invalid", ... }`                          | Supplied request key is not a UUID            |
| `400`/`500` | `{ "error": "AI processing error during enrichment..." }`           | Provider or enrichment persistence failure    |
| `429`       | `{ "code": "ai_quota_daily_exceeded", "retry_after_seconds": ... }` | Plan's UTC-day AI ceiling reached             |
| `429`       | `{ "code": "ai_user_rate_limit_exceeded", ... }`                    | Per-user minute ceiling reached               |
| `429`       | `{ "code": "ai_ip_rate_limit_exceeded", ... }`                      | Network minute ceiling reached                |
| `503`       | `{ "code": "ai_entitlement_unavailable", ... }`                     | Entitlement/quota state could not be verified |

---

## Deno `/insight-chat` Edge Node

Private Pro follow-up chat for completed biological Insight sheets. The endpoint
uses the authenticated Supabase user from `withEdgeHandler`, verifies ownership
of `scan_id`, and reads durable effective tier through `_shared/entitlement.ts`.
Each provider action then reserves its operation in the database, which repeats
entitlement verification atomically with quota and model selection.

### Request Payload

```json
{
  "action": "send",
  "scan_id": "A1B2C3D4-...",
  "message_text": "What traits support this identification?",
  "client_message_id": "11111111-1111-4111-8111-111111111111"
}
```

Feedback and field-notes summary actions use the same endpoint:

```json
{
  "action": "feedback",
  "scan_id": "A1B2C3D4-...",
  "message_id": "33333333-3333-4333-8333-333333333333",
  "feedback_rating": "wrong",
  "feedback_note": "Optional short private note"
}
```

```json
{
  "action": "feature_feedback",
  "scan_id": "A1B2C3D4-...",
  "feature_feedback_sentiment": "positive",
  "feedback_note": "Optional short private note"
}
```

```json
{
  "action": "summarize_notes",
  "scan_id": "A1B2C3D4-..."
}
```

AI-generated quick prompts use the same endpoint and never include user draft
text:

```json
{
  "action": "suggest_prompts",
  "scan_id": "A1B2C3D4-..."
}
```

`action` accepts `load`, `send`, `delete`, `feedback`, `feature_feedback`,
`summarize_notes`, or `suggest_prompts`. `load` returns the single saved
conversation for the scan when one exists. `send` creates that conversation when
missing, and requires both `message_text` and a UUID `client_message_id` for
idempotency. `delete` clears the scan's saved chat. `feedback` stores private
owner-only answer feedback for an assistant `message_id` with `feedback_rating`
(`helpful`, `not_helpful`, `wrong`, `unsafe`, `other`) and optional
`feedback_note`. `feature_feedback` stores private owner-only feedback on the
Field chat sheet itself with optional `feature_feedback_sentiment` (`positive`
or `negative`) and optional `feedback_note`; at least one is required.
`summarize_notes` returns a reviewable field-notes draft from the current saved
chat and scan context; the client must append it only after user confirmation
and must never replace existing field notes. `suggest_prompts` returns three
short, non-persisted prompt chip suggestions plus allowlisted categories for
telemetry; it uses the same owned scan context and recent saved chat history,
does not consume the daily send limit, and is best-effort so load/send chat
behavior remains independent if prompt generation fails. The server caps v1 at
600 characters per user message, 30 total persisted message rows per
conversation, and 20 sends per Pro user per day across all of that user's
Insight and Explore chats. A new request reserves room for its user and
assistant rows together; an incomplete retry already owns its user row but must
still have one slot for the assistant. Effective Pro includes active trial
users.

`send` uses `client_message_id` as the UUID provider idempotency key. The iOS
client sends a UUID `Idempotency-Key` header for `suggest_prompts` and
`summarize_notes`; every automatic network/auth/server retry preserves the same
value. For a send, the UUID is also the durable saved request identity: the
server canonicalizes it to lowercase, binds it to the user row and assistant
safety metadata, then projects it as `client_message_id` on both messages.
Reusing the UUID with different normalized text returns
`409 field_chat_idempotency_conflict`. The server rechecks that binding after a
duplicate/waited replay, while the service-only `reserve_field_chat_send(...)`
RPC performs the authoritative check and user-row insert atomically. It
serializes every user's cross-table UTC-day admission before conversation
admission, rejects a second different UUID while an answer is missing, and
checks both conversation slots and the daily send before the row is visible.
Thus contradictory same-UUID requests and different-key capacity races cannot
both pass an earlier Edge read. The assistant row has a deterministic UUIDv8
derived from conversation and request identity. A duplicate or quota replay
either returns that exact pair, waits a bounded interval for the original
in-flight answer, or returns retryable `503 field_chat_send_in_progress`. A
failed provider or assistant-persistence attempt may resume under the same UUID
without inserting another user question. An ambiguous assistant insert is
read-after-write reconciled before failure; deterministic identity prevents a
concurrent local refusal from saving two answers. iOS manual retry preserves the
failed UUID.

If an invocation terminates after quota commit but before assistant persistence,
same-UUID retries remain in progress during a ten-minute safety window. After
that window, `recover_stale_field_chat_quota(...)` may mark only the exact
subject/user/request reservation failed after proving the user row exists and
its bound assistant is absent. The route re-reads the pair before reserving a
newly metered provider attempt. A live or completed pair cannot be reopened.
`load`, delete, feedback, and local safety refusals do not invoke Gemini and do
not consume AI quota, although a newly admitted local refusal still counts as
one of the user's 20 Field Chat sends.

### Prompt and Privacy Boundary

The server builds chat context from stored text data only: species names,
taxonomy, hazard type, confidence, candidates/lookalikes, habitat/Wikipedia
overview, invasive flag plus its original AI region/rationale/confidence,
identification provenance, user review state, observed traits, ecological
annotations, species group tags, `ai_reasoning`, field notes, capture
date/month, location label, weather, elevation, and image/capture-quality
metadata. It does not include raw image bytes, R2 object keys, cloud image URLs,
internal scan IDs, exact GPS coordinates, Explore comments, public post
metadata, or Darwin Core export payloads.

Location-aware answers may use only the saved private location label, month,
elevation, ecology type, and weather. The prompt explicitly forbids inferring,
requesting, revealing, or reconstructing exact GPS coordinates.

The Gemini request uses `gemini-2.5-flash` with a stable prompt prefix,
`maxOutputTokens: 700`, no streaming, no Google Search grounding, and thinking
disabled. Assistant text is normalized to a nonempty fallback and capped at
4,000 Unicode code points before persistence. Assistant messages store
model/token telemetry, including cached tokens when Gemini reports implicit
cache hits.

Prompt suggestions are generated with the same text-only privacy boundary. The
model must return exactly three short prompt strings with safe categories such
as `evidence`, `lookalike_compare`, `habitat`, `season`, `hazard`, `invasive`,
`confidence`, `field_notes`, or `generic`. The guardrail prompt forbids edible
certainty, medical/veterinary treatment, illegal collection, pesticide/poison
instructions, exact-location requests, and human-subject identification. The
send-time classifier and post-generation filter match direct unsafe action
intent rather than isolated words, so harmless names such as poison ivy and
educational questions about animal foraging, bee stings, or discouraged handling
remain usable and are not automatically refused.

### Response Payload

```json
{
  "data": {
    "subject_id": "11111111-1111-4111-8111-111111111111",
    "conversation_id": "22222222-2222-4222-8222-222222222222",
    "messages": [
      {
        "id": "33333333-3333-4333-8333-333333333333",
        "conversation_id": "22222222-2222-4222-8222-222222222222",
        "scan_id": "A1B2C3D4-...",
        "role": "user",
        "text": "What traits support this identification?",
        "client_message_id": "11111111-1111-4111-8111-111111111111",
        "created_at": "2026-06-26T16:20:00.000Z",
        "is_refusal": false,
        "refusal_reason": null
      },
      {
        "id": "44444444-4444-4444-8444-444444444444",
        "conversation_id": "22222222-2222-4222-8222-222222222222",
        "scan_id": "A1B2C3D4-...",
        "role": "assistant",
        "text": "The saved evidence points to...",
        "client_message_id": "11111111-1111-4111-8111-111111111111",
        "created_at": "2026-06-26T16:20:02.000Z",
        "is_refusal": false,
        "refusal_reason": null
      }
    ],
    "limits": {
      "max_user_message_chars": 600,
      "max_messages_per_conversation": 30,
      "daily_send_limit": 20,
      "sends_remaining_today": 19
    }
  }
}
```

iOS treats this HTTP `200` as candidate evidence. Before replacing the current
thread it requires `subject_id` to echo the requested scan even when the thread
is empty, the exact v1 message/conversation limits, a bounded message count,
unique UUID message IDs, a valid envelope conversation UUID whenever messages
are present, and exact agreement between each message's `conversation_id`,
envelope conversation, and requested `scan_id`. Message text must be exactly
trimmed, nonempty, and at most 4,000 characters, and the JSON body must not
exceed the reviewed 1 MiB decode ceiling. A send response must contain exactly
one user and one assistant message carrying the requested `client_message_id`.
Any decode, identity, incomplete-pair, size, duplicate, limit, or conversation
mismatch is `MerianError.invalidResponse`; a pending send stays failed and
retryable under the same UUID.

For `suggest_prompts`:

```json
{
  "data": {
    "subject_id": "11111111-1111-4111-8111-111111111111",
    "conversation_id": "22222222-2222-4222-8222-222222222222",
    "prompts": [
      {
        "text": "Which leaf detail should I check next?",
        "category": "evidence"
      },
      {
        "text": "Could this be a lookalike?",
        "category": "lookalike_compare"
      },
      {
        "text": "Does this habitat fit?",
        "category": "habitat"
      }
    ]
  }
}
```

For `feedback`:

```json
{
  "data": {
    "ok": true,
    "subject_id": "11111111-1111-4111-8111-111111111111",
    "message_id": "33333333-3333-4333-8333-333333333333",
    "rating": "wrong"
  }
}
```

For `feature_feedback`:

```json
{
  "data": {
    "ok": true,
    "subject_id": "11111111-1111-4111-8111-111111111111",
    "id": "44444444-4444-4444-8444-444444444444",
    "sentiment": "positive"
  }
}
```

For `summarize_notes`:

```json
{
  "data": {
    "subject_id": "11111111-1111-4111-8111-111111111111",
    "summary_text": "Concise reviewed draft text for append-only field notes."
  }
}
```

iOS validates each action-specific `200` before applying success. Every action
must echo the exact requested scan through `subject_id`. Answer feedback must
also report `ok: true`, the requested message UUID, and the requested rating.
Feature feedback must report `ok: true`, a valid saved-feedback UUID, and the
requested optional sentiment. A field-note summary must be nonempty, no longer
than 4,000 characters, and contain no canonical internal UUID, including current
UUIDv7 identifiers. Prompt suggestions permit zero through three unique, trimmed
strings of at most 120 characters, require an allowlisted category and optional
valid conversation UUID, and repeat the server's
unsafe-action/exact-location/human-subject intent filter as client defense in
depth. Any mismatch is `MerianError.invalidResponse`; prompt generation falls
back locally, while feedback and summary surfaces remain unsuccessful.

Roll this contract out backend-first. Apply
`20260729163616_reserve_field_chat_sends_atomically.sql` before deploying either
new chat function; deploying a function that calls the RPC against an older
catalog fails closed with `field_chat_admission_unavailable`. Then deploy the
additive `subject_id` field and assistant request-pair projection to both
`/insight-chat` and `/explore-post-chat`, verify empty-thread/action responses,
different-key concurrency, cap boundaries, stale recovery, and an ambiguous
same-UUID send replay in staging, and only then ship the hardened iOS validator.
Existing iOS versions ignore the additive response fields; the corrected version
deliberately fails closed against an older anonymous-success envelope or a send
that cannot prove its persisted pair.

Before release acceptance, also apply
`20260730180000_bind_field_chat_rows_to_subjects.sql`. It is compatible with
both old and corrected chat functions: impossible historical cross-bound
private rows are removed first, then deferred composite foreign keys require
every retained Insight conversation to match its exact scan owner and every
retained message and rating to match its exact conversation, scan-or-post, and
viewer identity at commit. Conversation-optional feature feedback also matches
its exact scan owner without relying on a parent thread. Insight answer and
feature feedback lose their legacy direct authenticated Data API writes and
remain available only through the authenticated action envelopes above. This
structural boundary prevents one malformed persisted row from making every
future strict load of that thread fail.

### Safety and Errors

The system prompt states the assistant has no raw image access and answers only
from stored scan evidence. The Edge Function refuses or redirects
edible/foraging certainty, medical/veterinary treatment, dangerous handling,
illegal collection, pesticide/poison instructions, and human-subject
identification requests.

| Status | Body                                             | Meaning                                            |
| ------ | ------------------------------------------------ | -------------------------------------------------- |
| `400`  | `{ "code": "unsupported_scan", ... }`            | Scan is non-biological or request shape is invalid |
| `402`  | `{ "code": "pro_required", ... }`                | Effective tier is not Pro/trial                    |
| `404`  | `{ "code": "scan_not_ready", ... }`              | No owned completed scan row exists yet             |
| `409`  | `{ "code": "field_chat_idempotency_conflict" }`  | UUID was reused with different normalized text     |
| `429`  | `{ "code": "daily_limit_reached", ... }`         | Daily send cap reached                             |
| `429`  | `{ "code": "ai_quota_daily_exceeded", ... }`     | Database AI safety ceiling reached                 |
| `429`  | `{ "code": "ai_user_rate_limit_exceeded", ... }` | Shared user minute ceiling reached                 |
| `429`  | `{ "code": "ai_ip_rate_limit_exceeded", ... }`   | Shared network minute ceiling reached              |
| `503`  | `{ "code": "field_chat_send_in_progress", ... }` | Same or different in-flight send has no answer yet |
| `503`  | `{ "code": "field_chat_admission_unavailable" }` | Atomic admission could not be verified             |
| `503`  | `{ "code": "field_chat_recovery_unavailable" }`  | Stale-request recovery could not be verified       |
| `503`  | `{ "code": "ai_entitlement_unavailable", ... }`  | Entitlement/quota lookup failed closed             |

The iOS client treats `404 scan_not_ready`, action-level `message_not_found` /
`conversation_not_found`, and a preflight status `not_found` as retryable state.
None may set scan-scoped permanent unavailability or hide the Field Chat action.
Only terminal ownership failure, `unsupported_scan`, and unavailable
Explore-post sources identified by `post_not_available` do so. In particular,
Explore feedback’s `message_not_found` does not hide chat for the healthy post.

Telemetry emits `InsightChatSent`, `InsightChatAnswered`, `InsightChatRefused`,
`InsightChatRateLimited`, `InsightChatModelError`,
`InsightChatPromptsGenerated`, `InsightChatFeedbackSubmitted`,
`InsightChatFeatureFeedbackSubmitted`, and `InsightChatNotesSummarized` with
latency and token fields when available. Send/answer events include a
deterministic `answer_category` so token cost can be reviewed by broad question
type. Prompt generation events include prompt categories, fallback/error state,
and token usage when available. iOS also emits `InsightChatActionTapped` to
PostHog for local answer actions, prompt-chip taps, the sheet options menu, and
feedback affordances. When iOS detects local identification-concern intent -
direct wrong-ID language, soft doubt, alternate-ID suggestions, trait mismatch,
or recheck/reanalysis requests - it can attach local
`review_alternatives_from_identification_concern` and
`reanalyze_species_from_identification_concern` actions to the next assistant
reply; these actions route through existing on-device candidates/reanalysis
flows and do not change the `/insight-chat` response payload.

---

## Deno `/explore-post-chat` Edge Node

Private Pro Field chat for any active Explore post visible to the viewer,
including their own. The endpoint authenticates with `withEdgeHandler`, derives
the viewer from the verified JWT, requires the post to be visible to that
viewer, and resolves Pro/trial access server-side. Each
`(post_id, viewer user_id)` pair has its own conversation. Other viewers cannot
load or mutate it; the post author may own a conversation when viewing their own
published post.

Model sends reserve `explore_post_chat_reply` using
`client_message_id`/`Idempotency-Key` before provider dispatch and use the
database-selected model. Local safety refusals and deterministic prompt
suggestions do not call Gemini and do not consume AI quota. Explore and Insight
model chat share the `ai_chat` quota buckets. `client_message_id` is required
for `send`, binds the persisted user/assistant pair, and is reused by automatic
and manual retries. Quota replays coalesce into the saved pair or return the
same retryable in-progress contract as Insight Chat.

Request bodies use `post_id` and support `load`, `send`, `delete`, `feedback`,
and `suggest_prompts`:

```json
{
  "action": "send",
  "post_id": "22222222-2222-4222-8222-222222222222",
  "message_text": "How can I distinguish this species from lookalikes?",
  "client_message_id": "11111111-1111-4111-8111-111111111111"
}
```

The response reuses the iOS `InsightChatResponse` envelope. For compatibility,
each message's `scan_id` field contains the Explore post ID; it never exposes
the owner's source scan ID. Top-level `subject_id` also contains the requested
Explore post ID on every thread, feedback, and prompt-suggestion response,
including an empty thread. Conversations allow 600 characters per user message,
30 total persisted rows, and share the 20-send UTC daily allowance with the
viewer's Insight chats. New sends reserve room for user and assistant rows
together through the same atomic cross-table RPC, which also rejects a different
request while one bound user row remains unanswered. Request UUIDs are canonical
lowercase values; UUID reuse with different normalized text returns
`409 field_chat_idempotency_conflict`, and deterministic assistant UUIDv8 rows
make answer persistence idempotent. A charged request missing its assistant
follows the same exact-row-bound ten-minute stale recovery contract as Insight
Field Chat. Assistant text is capped at 4,000 Unicode code points before
persistence. Prompt suggestions and feedback do not consume a send. The same iOS
candidate-success validation binds the envelope and every returned message to
the requested post ID and one conversation; a send also requires its exact
two-message `client_message_id` pair, exact acknowledged user text, and bounded
response body before the private thread can be displayed, a pending send can be
cleared, or an action can show success.

The model context is built from the privacy-filtered `get_explore_post` and
`get_explore_post_detail` projections plus public Species Dictionary fields. It
excludes private owner scan rows, exact coordinates, unpublished notes,
comments, owner chat history, and media bytes/URLs. Questions that require
direct inspection of the post's media must be answered without claiming media
access. These technical boundaries remain server-enforced even though the iOS
empty state presents only the concise trust message:
`This Field chat is
private and visible only to you.`

`404 post_not_available` covers missing, unpublished, or blocked posts;
`402
pro_required` covers non-Pro viewers; `404 message_not_found` covers
feedback targeting a non-owned assistant message; and `429 daily_limit_reached`
returns the current conversation envelope with no new send. Shared `409`, `429`,
and fail-closed `503` AI quota errors follow the authorization table above.
Unpublishing a post deletes all of its private viewer conversations.

---

## Deno `/sync-collections` Edge Node

Synchronizes locally created Scan Collections with the PostgreSQL `collections`
and `collection_scans` schemas, handling diffing and missing FK references.

### Request Payload

```json
{
  "collections": [
    {
      "id": "A1B2C3D4-...",
      "name": "My Favorites",
      "created_at": "2026-03-23T12:00:00Z",
      "scan_ids": ["B2C3D4E5-..."],
      "is_deleted": false,
      "isDeleted": false
    }
  ]
}
```

### Safety and Transactional Integrity

1. **Dual Casing Delete Parsing**: To protect against Swift `JSONEncoder`
   converting structural snake_case keys into camelCase payloads based on
   codable strategies, the Edge function supports both `is_deleted` and
   `isDeleted` attributes when resolving the deleted tombstone array.
2. **Batch Upserts**: All valid collections are written via a single atomic
   `.upsert(collectionPayloads)` call, resolving PostgreSQL `TIMESTAMPTZ` and
   `UUID` types without timing out. **The upsert now throws on database error**
   rather than logging silently — `upsertCollectionsAndFetchMemberships`
   propagates the error through `withEdgeHandler` so the iOS client receives
   `HTTP 500` and can retry rather than treating a failed collection persist as
   a successful sync.
3. **Centralised Ownership Filter (`filterOwnedCollections`)**: `index.ts` calls
   `filterOwnedCollections(userId, collections, supabaseAdmin)` before any write
   proceeds. This function queries the existing `collections` rows for the
   incoming IDs and removes any whose `user_id` does not match the authenticated
   user. The pre-filtered, ownership-verified set is then passed to all
   downstream functions (`upsertCollectionsAndFetchMemberships`,
   `syncMembershipDelta`, `deleteCollections`) — no downstream function needs to
   re-implement the ownership check independently. Collection IDs owned by other
   users are silently dropped.
4. **Delete IDOR Guard**: `deleteCollections` additionally scopes the DELETE
   query with `.eq("user_id", userId)` as a defence-in-depth layer.
   `deleteCollections` now throws on database error rather than logging
   silently, preventing false-success `200` responses when the deletion fails.
5. **Bulk Insertion & Mismatched FK Protection**: Applying `collection_scans`
   relationships in bounded set-based upsert chunks avoids N+1 query timeouts.
   To prevent PostgreSQL Foreign Key violations from crashing the overarching
   chunk transaction, the Edge Node dynamically pre-validates all incoming
   `scan_id` payloads against the core `scans` table. If a user groups a scan
   while fully offline and the physical cloud `scans` row hasn't populated yet,
   mapping intelligently bypasses that specific missing scan natively. The
   pending relationship rests securely offline on the user's iPhone until the
   next sync pulse. Existing memberships are hydrated for all owned collections
   with one keyset-paginated `.in("collection_id", ownedIds)` query ordered by
   `(collection_id, scan_id)`, rather than one pagination loop per collection.
   Each bounded page resumes after its last composite primary key instead of
   paying progressively higher range/OFFSET costs. This keeps latency sublinear
   for users with many collections while bounding each page in V8 memory.
6. **Array-Bound Diffing Deletes**: Identifies obsolete collections by running
   `.select()` across the user's DB rows, building a `toDelete` array in memory
   and passing it to `.delete().in("id", toDelete)`. This avoids
   `.not("id", "in", "(...)")` string-builder failures.
7. **Strict Upstream Concurrency Latch**: Because `BackgroundTaskWrapper` calls
   push network traffic simultaneously out-of-order, the iOS client strictly
   clamps `sync-collections` invocations behind a shared collection
   single-flight latch. `OfflineQueueManager` retains the active
   `collectionSyncTask`, so concurrent callers await the same request instead of
   launching parallel pushes. A monotonic `collectionSyncRevision` is captured
   when each request starts; the coalesced
   `OfflineJobRecord(id:
   "collection-sync")` is marked complete only if no
   newer collection mutation was enqueued while that request was in flight. This
   prevents race conditions where a stale `.upsert()` snapshot lands after a
   newer `.delete()`, causing ghost resurrections.

> **Parameter naming**: The `syncMembershipDelta` function parameter names were
> updated from `validCollections`/`activeIds` to `ownedCollections`/`ownedIds`
> to reflect that all inputs are pre-ownership-checked by the time they reach
> that function.

**Authentication ownership**: `sync-collections` is configured with
`verify_jwt = false`, so the handler owns JWT validation and authorization
through the shared auth boundary. Raw iOS requests send the public project key
in `apikey` and the signed-in user's JWT in `Authorization: Bearer …`.
`verify_jwt = false` does not make the route public and should not be explained
as gateway header stripping.

---

## Deno `/check-scan-status` Edge Node

Provides a lightweight outbox confirmation endpoint. Current
`/identify-multimodal` success already includes durable owner-row insertion;
polling remains useful for compatibility endpoints, interrupted older requests,
and queued recovery.

### Request Payload

```json
{ "scan_id": "<UUID>", "required_video_count": 1 }
```

`required_video_count` is optional. Omit it for legacy/image status probes. When
present and greater than zero, the endpoint returns `"found"` only if the scan
row exists for the authenticated user and has at least that many public
`video_storage_urls` plus matching ready playback entries in `scan_media_assets`
or video entries in `captured_media`.

For one local observation whose owner row is absent, iOS may include a
`recovery_scan` object containing validated non-media fields. Its `id` must
match `scan_id`, its `user_id` must match the authenticated user, and
`image_storage_urls` must be empty. The endpoint delegates to one atomic
service-only routine, which takes the ingestion claim's per-scan advisory lock,
inserts only a missing scan, and writes `client_recovery_complete` in the ledger
within the same transaction. It cannot overwrite an existing scan. Direct media
URLs are rejected, and recovery is not supported in bulk probes. Processing,
finalizing, retrying, retryable, policy, legacy-unknown, and every other
terminal state are never preempted. A missing ledger row also fails closed. Only
an existing `complete` ledger whose owner row is unexpectedly absent or an
explicit `terminal_reason_code = replay_exhausted` state is recoverable without
additional provenance. Exact `media_reconciliation_abandoned` additionally
requires an owner/scan-matching post-result `failed_scan_ingestions` row no
earlier than the latest charged exact normal/replay quota attempt, no exact
reserved attempt or invalid terminal timestamp lineage, and no
moderation-rejected or moderation-pipeline-failed capture lifecycle row.
Pre-rollout unstructured evidence must be one of the exact dead-letter IDs
snapshotted by the hardening migration, predate the private database cutoff, and
either follow a failed latest authority or match the historical first committed
normal attempt with no charged replay. Timestamp alone is not authority: an
older producer insert blocked by migration DDL can resume later while retaining
an earlier transaction-start `failed_at`; the immutable ID snapshot excludes
that row. Legacy evidence must come from the audited multimodal post-safety
error lineage, not the known pre-safety user prerequisite or a moderation
failure. Post-rollout structured evidence must bind the exact quota
reservation/request IDs, validated provider output, and completed Identify
safety evaluation. All exact failed/committed normal and replay reservation keys
are retained as chronological authority across ordinary quota pruning until the
terminal ledger is resolved. The recovery and proof routines are service-only,
recorded in
`internal.privileged_routine_grants`, and probed in production through exact
null-input SQLSTATE `22023` no-write boundaries.
A handler-owned `503 service_unavailable` while processing `recovery_scan`
therefore means the guarded database recovery boundary was not authoritative;
the client must preserve local media and must not proceed to restore signing.
This check is also the rollout fence. The baseline and hardening SQL files are
separate migration-file transactions, so exact-SHA fail-closed
`generate-upload-urls`, `check-scan-status`, and `share-scan-to-explore`
consumers predeploy before either file. A recovery call proves that the
service-only `get_media_abandoned_scan_recovery_proofs` surface is available
before it can invoke `recover_missing_owned_scan`; an empty proof set is valid
readiness for non-media-abandonment outcomes, but malformed, foreign, missing,
or denied responses stop the flow. The structured Identify producer deploys
only after both migrations commit.

If the exact owner row is still absent, the route also invokes service-only
`recover_stranded_scan_ingestion_attempt` before projecting client-safe job
state. This narrow reconciliation applies to single and bulk probes and may
adjust only an already-existing scanless job/quota/staging topology whose
endpoint, operation, lease, owner, and optional merge handoff agree. It never
guesses or inserts a scan row, refunds dispatched usage, reparents arbitrary
state, or exposes the authorized source identity.

### Response Payload

```json
{
  "status": "found",
  "job_status": null,
  "job_stage": null,
  "job_attempt_count": null,
  "retry_after": null,
  "last_error": null
}
```

`status` remains the compatibility field and is still only `"found"` or
`"not_found"`. When the scan row is not complete yet, newer clients and ops
tools can inspect the optional job fields backed by `scan_ingestion_jobs`:
`job_status` may be `processing`, `finalizing`, `retrying`, `failed_retryable`,
`failed`, or `complete`; `failed` is the client-safe projection of a
`failed_terminal` ledger row. iOS also accepts the legacy `failed_terminal`
response spelling. `job_stage` names the precise server step, including
`server_replay_limit_reached` when the scheduled replay budget is exhausted.
`retry_after` and `last_error` are only populated for failed jobs. iOS decodes
the full response via `ScanStatusResponse`: queued scans use these fields to
keep server-owned `.inferencing` rows from being resubmitted while media
promotion or scan insertion is still finalizing, and to surface terminal server
replay exhaustion as needs-attention instead of continuing automatic retry.

### Authentication & IDOR

The `Authorization: Bearer` JWT is verified by `withEdgeHandler`. The DB query
enforces ownership with a dual `.eq("id", scan_id).eq("user_id", user.id)`
constraint — a user cannot probe another user's scan IDs. Recovery additionally
derives the canonical owner from the authenticated user and validates UUIDs,
numeric ranges, bounded text, enums, and geoprivacy-derived public coordinates.
The atomic database write enforces ownership and ingestion-generation state
independently of iOS polling. The query returns only the media fields needed for
the durability check (`id`, `video_storage_urls`, `captured_media`, normalized
scan-media asset rows, and the user's own scan-ingestion job state); no private
scan content is transmitted.

### Architecture

Follows the domain-driven module pattern: `index.ts` orchestrates auth,
parameter validation, optional owner-row recovery, narrow stranded-attempt
reconciliation, and video-count gating; `db.ts` owns status reads,
`_shared/scanRecovery.ts` owns DTO validation and atomic row repair, and
`_shared/scanIngestionJobs.ts` owns stranded-attempt response validation. Read
or repair errors are caught by `index.ts` and mapped to a structured
`logStructuredError` + 500 response.

---

## Deno `/get-filtered-discovery-feed` Edge Node

Fetches the global social feed of public biological captures, excluding the
requesting user and any users they have blocked.

### Feed Query Strategy

Block list and feed are fetched in **parallel** via `Promise.all`:

```typescript
const overFetchLimit = limit + Math.max(20, Math.ceil(limit * 0.2));
const [blockedIds, rawFeed] = await Promise.all([
  fetchBlockedUserIds(user.id, supabaseAdmin),
  fetchDiscoveryFeed(user.id, overFetchLimit, supabaseAdmin),
]);
const excludedSet = new Set(blockedIds);
const feedData = rawFeed.filter((s) =>
  s.user_id != null && !excludedSet.has(s.user_id)
).slice(0, limit);
```

`fetchDiscoveryFeed` excludes only the requesting user at the DB level
(`.neq("user_id", selfId)`). Blocked user filtering is applied post-query in
TypeScript. To compensate for rows removed by the block filter, the DB query
over-fetches by `Math.max(20, 20% of limit)` rows. For the default limit of 20,
this fetches up to 40 rows. Block list filtering happens on the fast in-memory
`Set`, not in the SQL query — this eliminates a SQL variable-length array
parameter that required manual escaping.

### Authentication Enforcement

The endpoint extracts user identity from the `Authorization: Bearer` header via
`supabaseAdmin.auth.getUser()`, ignoring any `userId` in the request body.

**Raw-client header requirement**: Because `MerianNetworkClient` uses
`URLSession` instead of the Supabase Swift SDK, requests send both
`Authorization: Bearer <user JWT>` and `apikey: <public project key>`. The
gateway can reject a request that does not identify the project, while the
handler independently validates the Bearer user JWT. Do not describe this as the
gateway stripping Authorization.

Any request with a manipulated JSON body but no valid JWT signature in the
header returns `401 Unauthorized`.

### Global Geoprivacy & Endangered Species Shielding

To prevent location tracking and poaching of IUCN Endangered, Vulnerable, or
Near-Threatened species, the endpoint runs a post-processing `map` loop before
JSON transmission. The `.gps_lat_exact` and `.gps_long_exact` fields are removed
from every scan in the payload, regardless of the user's geoprivacy setting.
Additionally, if the taxonomy flags a capture as a protected species, the
endpoint rounds `gps_lat_public` coordinates to 11km tiles.

---

## Deno `/merge-ghost-profile` Edge Node

Securely transfers a Ghost profile only when direct OAuth identity linking
cannot preserve its UUID. The route accepts `POST` only, has a 4 KiB JSON body
limit, and uses `verify_jwt = true`. An anonymous Supabase session JWT is
required for prepare; a non-anonymous user JWT is required for complete and
identity refresh. `withEdgeHandler` resolves the live Auth user after the
gateway check.

The iOS client may enter this fallback only for Supabase Auth code
`identity_already_exists`. Other identity-link failures do not switch sessions.

### Prepare

```json
{
  "operation": "prepare",
  "provider": "apple",
  "provider_subject": "Provider ID-token subject"
}
```

The live anonymous session is the source authority. The response contains
`handoff_id`, a one-time 256-bit `handoff_secret`, and `expires_at`; it is
marked `Cache-Control: no-store`. The database stores only the secret hash and
binds it to `auth.uid()` plus the exact provider identity for 30 days. Provider
subjects must be 1–255 characters with no Unicode control characters. iOS
persists the proof in a versioned Keychain queue using
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` before changing sessions.

Successful response: HTTP 201.

```json
{
  "success": true,
  "handoff_id": "UUID",
  "handoff_secret": "43-character base64url secret",
  "expires_at": "RFC 3339 timestamp"
}
```

### Complete

```json
{
  "operation": "complete",
  "handoff_id": "UUID returned by prepare",
  "handoff_secret": "One-time URL-safe secret"
}
```

The permanent destination is derived from the completion JWT and never from a
request UUID. In one database transaction, the RPC:

1. verifies the source remains anonymous and the destination owns the prepared
   provider subject;
2. serializes concurrent attempts by source and locks both users;
3. resolves known relationship/progress uniqueness conflicts;
4. reparents all supported `public.users` and external `auth.users` foreign keys
   and refuses unknown composite ownership; and
5. records an idempotent receipt before commit.

The Edge Function deletes the anonymous Auth user only after commit. A cleanup
failure returns a retryable `503`; replay by the same destination is safe. The
client queues independent handoffs rather than overwriting an older interrupted
upgrade. It removes a queue item only after success or terminal
`handoff_expired`/`handoff_invalid`. A 403 for a different active destination is
retained so the proof can complete when its bound account signs in.

Successful response: HTTP 200.

```json
{
  "success": true,
  "target_user_id": "UUID",
  "merged_at": "RFC 3339 timestamp",
  "already_merged": false,
  "message": "Guest profile securely upgraded."
}
```

`already_merged` is `true` on an idempotent replay by the original destination.

### Error contract

Error bodies use `{ "code": "...", "error": "..." }`.

| HTTP | Code                                       | Meaning                                                                  | Client action                                      |
| ---- | ------------------------------------------ | ------------------------------------------------------------------------ | -------------------------------------------------- |
| 400  | `invalid_request`                          | Invalid JSON, unsupported fields, provider/subject, UUID, or secret      | Do not switch away during prepare; fix the request |
| 413  | `invalid_request`                          | JSON body exceeds 4 KiB                                                  | Do not retry unchanged                             |
| 401  | shared auth error                          | Missing, invalid, expired, or non-live user JWT                          | Refresh/re-authenticate                            |
| 403  | `ghost_session_required`                   | Prepare caller is not anonymous                                          | Do not retry as that session                       |
| 403  | `permanent_session_required`               | Complete/refresh caller is anonymous                                     | Sign in to the permanent account                   |
| 403  | `handoff_forbidden`                        | Destination is not the exact bound provider identity                     | Retain the queued proof for the correct account    |
| 404  | `handoff_invalid`                          | Unknown, superseded, consumed by another destination, or unusable source | Remove that queued proof                           |
| 409  | `source_already_merged` / `merge_conflict` | Source already upgraded or conflicting concurrent state                  | Refresh state; do not create an unproved fallback  |
| 410  | `handoff_expired`                          | 30-day recovery window elapsed                                           | Remove that queued proof                           |
| 503  | `auth_cleanup_pending`                     | Data merge committed; Auth deletion still pending                        | Retain and retry safely                            |
| 503  | `merge_temporarily_unavailable`            | Timeout, deadlock, serialization/lock failure, or guarded schema drift   | Retain and retry; alert operations on repetition   |
| 500  | `merge_failed`                             | Unexpected server failure                                                | Retain and retry; investigate logs                 |

`{"operation":"refresh_identity"}` is the separate permanent-session operation
for refreshing public provider identity when no merge is required. It returns
`{"success":true}`.

### Durable Auth cleanup

`/reconcile-ghost-profile-merges` is not a client API. A five-minute `pg_cron`
job calls it with one exact platform-managed current or legacy server key; the
function uses `verify_jwt = false` only so that server credential can reach
Deno, then performs an exact timing-safe comparison. It leases at most 100
merged receipts, deletes the obsolete anonymous Auth users, and records each
claim-token-bound outcome. HTTP 404 and exact Auth code `user_not_found` are
idempotent cleanup success.

---

## Deno `/safe-delete` Edge Node

Deletes a user's account and account-owned content from PostgreSQL and
Cloudflare R2 while retaining mandatory ownerless Scientific Data on each
submitted observation.

### Request Payload

No JSON body is required. The endpoint operates from the JWT identity alone to
prevent IDOR vulnerabilities.

### Authentication Enforcement

1. Calls `supabaseAdmin.auth.getUser()` to extract the authenticated user's UUID
   from the `Authorization: Bearer` header.
2. Calls service-only `request_account_deletion(user.id)`. This inserts or
   returns the active private job before any destructive work.
3. Attempts a target-bound lease through
   `claim_account_deletion_jobs(1, user.id)`. Another live claim produces a
   durable `202` response rather than duplicate work.
4. For every `pending`, `storage_pending`, or `auth_pending` claim,
   `complete_account_deletion_cleanup` atomically writes the idempotent storage
   job, invokes `apply_user_tombstone`, and verifies no public user or scan
   still references the UUID. Retained scans become ownerless tombstones and
   clear compatibility media URLs, structured captured-media references,
   semantic/public location labels, device locale/time-zone context, free-form
   notes, and custom tags. Exact coordinates, elevation, time, taxonomy,
   identification, environmental, quality, and provenance facts remain
   unchanged as mandatory Scientific Data. No synthetic `auth.users` or
   `public.users` identity is created.
5. Relational completion returns `storage_pending` and releases the account
   claim. The storage worker keyset-sweeps the user's free uploads, Pro uploads,
   staging, avatars, and exports prefixes in 50-key pages. After at least 25
   hours it repeats all five prefixes from the beginning. Only an empty delayed
   verification pass transactionally advances the account to `auth_pending`. A
   storage row is claimable only when the matching private job is
   `storage_pending` with completed cleanup and incomplete storage, and no live
   public profile or scan ownership remains. An outbox row by itself never
   authorizes R2 deletion.
6. Only `auth_pending` may call `supabaseAdmin.auth.admin.deleteUser(user.id)`.
   HTTP `404` and exact Auth code `user_not_found` are treated as idempotent
   success.
7. `finish_account_deletion_attempt` records terminal completion or releases the
   claim with bounded retry backoff. Completion clears the private job's direct
   `user_id`.

All state-machine RPCs are `service_role`-only, call
`internal.require_service_role()`, and have empty `search_path` values. The
caller cannot supply a user ID in the body.

While the job is active, a private database trigger rejects recreation of the
original `public.users` row. Auth metadata synchronization and trusted backend
upserts therefore cannot restore a profile after cleanup but before the external
Auth call. `/generate-upload-urls` also returns
`409 account_deletion_in_progress`, preventing new signed writes during erasure.

### Responses

- `200 OK`, `{ "success": true, "status": "completed", ... }`: relational
  cleanup, delayed empty R2 verification, and Auth deletion are confirmed; the
  terminal account job no longer retains the user UUID.
- `202 Accepted`, `{ "success": true, "status": "pending", ... }`: the request
  is durably recorded. A five-minute scheduled reaper resumes it. This is a
  successful deletion request, not a prompt to submit another target.
- `405 Method Not Allowed`: any method except `POST`.
- `500 Internal Server Error`: durable intake itself failed, so no destructive
  work began.

After either success response, the iOS client performs local Supabase sign-out,
drops all local SQLite `ModelContext` state through
`ScanRepository.purgeAllData()`, and resets to Guest.

### Service-only reaper

`/reconcile-account-deletions` accepts a bounded optional `{ "limit": n }`
object and authenticates one exact platform-managed current or legacy server key
with a timing-safe comparison. Opaque keys use `apikey` only; legacy
service-role JWTs use matching `apikey` and Bearer headers. It never accepts a
target UUID. Each invocation performs a bounded account pass, bounded storage
pages, and, when storage verification completes, one final account pass. It
returns only aggregate `account_claimed`, `account_completed`,
`account_deferred`, `waiting_for_storage`, `storage_claimed`,
`storage_completed`, and `storage_deferred` counts. Claim expiry, persisted
prefix cursors, delayed verification, idempotent Auth-not-found handling, and
database-calculated backoff make crashes and lost responses resumable.

The scheduled caller reads its key from Vault and delegates header construction
to `internal.server_api_request_headers(...)`. A modern opaque `sb_secret_...`
key is sent only in `apikey`; a legacy service-role JWT is sent in both
supported headers. The Vault value must be one of the project's active server
keys.

### Service-only deletion health RPC

`POST /rest/v1/rpc/get_account_deletion_health` accepts an empty JSON object and
requires a Supabase server/service-role API credential. Execute is revoked from
`PUBLIC`, `anon`, and `authenticated`; the definer routine also calls
`internal.require_service_role()` before reading private state.

The response is a one-row array of aggregate values:

```json
[
  {
    "generated_at": "2026-07-27T01:00:00Z",
    "active_job_count": 2,
    "pending_cleanup_count": 0,
    "storage_pending_count": 1,
    "auth_pending_count": 1,
    "due_job_count": 1,
    "failed_job_count": 1,
    "active_lease_count": 0,
    "expired_lease_count": 0,
    "oldest_pending_at": "2026-07-25T22:00:00Z",
    "oldest_pending_age_seconds": 97200,
    "oldest_due_at": "2026-07-27T00:45:00Z",
    "oldest_due_age_seconds": 900,
    "storage_backlog_count": 1,
    "storage_due_count": 0,
    "storage_failed_job_count": 0,
    "storage_active_lease_count": 0,
    "storage_expired_lease_count": 0,
    "verification_waiting_count": 1,
    "orphaned_storage_job_count": 0,
    "oldest_storage_pending_at": "2026-07-25T22:00:00Z",
    "oldest_storage_pending_age_seconds": 97200,
    "oldest_storage_due_at": null,
    "oldest_storage_due_age_seconds": null,
    "reaper_cron_active": true,
    "reaper_credentials_configured": true
  }
]
```

`failed_job_count` fields mean active rows carrying their most recent bounded
retry code; the code itself is not exposed. Oldest timestamps and ages are both
null when their corresponding count is zero. The RPC never returns a user UUID,
claim token, cursor, object prefix, or raw error, and it never advances state.
The independent scheduled monitor consumes this contract with a 15-second
deadline and 64 KiB response ceiling.

`reaper_credentials_configured` selects each Vault value first and uses the
legacy app setting only when no Vault row exists, then checks that both
effective values are nonblank. A blank Vault value therefore yields `false` even
if the fallback is populated. The field does not test URL reachability,
credential validity, or a reconciler round trip; the required post-deploy
monitor dispatch validates the independent health-RPC path, while a recent
successful reaper cron request validates the worker path.

---

## Deno `/repair-scan-image` Edge Node

Inspects an active owned scan-image reference and, when the referenced R2 object
is missing, promotes a surviving local image and atomically repairs its cloud
metadata. The same transaction updates matching Scan Library and Explore media
references.

### Request Payloads

Inspection:

```json
{
  "source_url": "https://media.merian.app/public_uploads/free/11111111-1111-4111-8111-111111111111/old.webp"
}
```

Repair after the client obtains a signed upload URL and uploads the surviving
file:

```json
{
  "source_url": "https://media.merian.app/public_uploads/free/11111111-1111-4111-8111-111111111111/old.webp",
  "restored_object_key": "staging/11111111-1111-4111-8111-111111111111/repair_uuid.webp"
}
```

`source_url` must have the HTTPS protocol, exact `media.merian.app` hostname, no
query or fragment, and a flat
`public_uploads/free|pro/{single-segment}/{single-segment}` path. Its exact
string must also be present in an active owned scan's `image_storage_urls`; path
shape alone is not ownership evidence. `restored_object_key` is optional; when
present it must be one image directly under the authenticated user's exact
staging prefix. The JWT identity—not a body field—selects the owner.

`config.toml` uses `verify_jwt = false` for this app-facing route, so the
function must retain `withEdgeHandler` as its custom live-user authentication
boundary. Disabling the gateway check does not make inspection or repair public.

### Inspection Response

```json
{
  "data": {
    "status": "healthy"
  }
}
```

`status` is:

- `healthy`: an active scan owned by the caller references the URL and the
  source object exists;
- `missing`: the owned reference exists but R2 returns 404; or
- `not_referenced`: no active scan owned by the caller references the URL.

Inspection does not upload, promote, rewrite, or delete media.

### Repair Response

```json
{
  "data": {
    "status": "repaired",
    "replacement_url": "https://media.merian.app/public_uploads/pro/11111111-1111-4111-8111-111111111111/repair_uuid.webp",
    "updated_scan_count": 1,
    "updated_post_media_count": 1
  }
}
```

The repair boundary:

1. rejects the request while account deletion is active;
2. confirms an active owned scan references the exact source URL;
3. `HEAD`s the source and restored staging objects;
4. attempts status-checked removal of the redundant staging upload and returns
   `healthy` without metadata changes if the source has recovered;
5. otherwise promotes the staging image into the caller's current durable
   free/Pro prefix;
6. validates the promoted owner prefix; and
7. invokes service-only `repair_owned_scan_image_reference` to replace the exact
   URL across scan arrays, recursive captured-media JSON, normalized scan
   assets, and owner Explore snapshots in one transaction. Matching Explore
   media health is reset to `healthy` in that transaction, allowing projection
   and owner incident state to restore automatically.

After any unsuccessful or malformed atomic metadata response, the function
rereads exact owner references for both URLs. Source-absent plus
replacement-present evidence proves commit and reconstructs success. It deletes
the newly promoted object only after a returned database rejection when the
source remains referenced and the replacement is provably unreferenced. A lost
response, unavailable owner read, concurrent repair, or any other topology is
outcome-unknown and preserves the object. The old missing URL is not changed
until the atomic metadata transaction succeeds.

### Error Contract

- `400`: invalid source URL or restored staging key.
- `401`: missing/invalid authenticated user.
- `404`: repair requested for a source not referenced by an active owned scan.
- `409 account_deletion_in_progress`: destructive account cleanup is active.
- `409`: the restored staging object does not exist.
- `503`: R2 source or restored-object status could not be verified.
- `503 scan_image_repair_persistence_unknown`: the atomic repair may have
  committed but exact owner references could not confirm it; the promoted
  replacement is preserved and the caller may retry.
- `500`: promotion, atomic persistence, or an unexpected internal boundary
  failed; provider details, keys, and SQL errors are not returned.

This endpoint is a recovery mechanism, not a general media replacement API. See
the
[July 2026 account-scoped R2 image-loss incident report](../incidents/2026-07-account-scoped-r2-image-loss.md).

---

## Deno `/get-explore-media-incidents` Edge Node

Returns only the authenticated owner's active degraded or quarantined Explore
media incidents. The function uses custom JWT authentication and derives the
owner UUID; no target-user field is accepted.

Request:

```json
{}
```

Response:

```json
{
  "data": [
    {
      "post_id": "uuid",
      "scan_id": "uuid",
      "species_common_name": "White-winged Dove",
      "media_health_status": "quarantined",
      "missing_media_count": 2,
      "total_media_count": 2,
      "media_quarantined_at": "2026-07-26T12:10:00.000Z",
      "media_health_updated_at": "2026-07-26T12:10:00.000Z",
      "missing_media_urls": [
        "https://media.merian.app/public_uploads/pro/{owner}/one.webp",
        "https://media.merian.app/public_uploads/pro/{owner}/two.webp"
      ]
    }
  ]
}
```

The canonical handler response is always the wrapped `{"data":[...]}` object
above. During rollout, corrected iOS builds also accept the exact legacy direct
array response (`[...]`) emitted by an older deployed handler; no other
successful-response topology is accepted. Incident entries remain strictly
decoded in either envelope, and a malformed `2xx` response maps to
`invalidResponse` rather than being interpreted as an incident or triggering
scan recovery.

`media_health_status` is `degraded` or `quarantined`. Unpublished, moderated,
tombstoned, and healthy records are excluded. The backing definer RPC verifies
`auth.uid() = self_id` for authenticated direct use, while the Edge boundary
uses service role only with the auth-derived UUID. Its final body dispatches on
identity first: a present user must match `self_id`, while only the no-user path
calls `internal.require_service_role()`. Migration
`20260727183356_restore_identity_first_media_incident_guard.sql` restores this
contract after the later quarantine migration accidentally reintroduced
role-first dispatch.

The iOS Scan Library refreshes this response on entry, foreground, connection
changes, and library repair events. Rapid queue-driven refresh triggers are
coalesced within five seconds because this is an independent read-only alert
surface. A trigger received during an in-flight call receives one trailing
refresh rather than being dropped, and the expected authenticated owner is
revalidated before private incidents enter view state. A failed refresh retains
the last in-memory incident state instead of falsely claiming recovery.

---

## Deno `/reconcile-explore-media-health` Edge Node

Scheduled service-role worker for direct R2-origin health verification.

Request:

```json
{
  "limit": 200,
  "leaseSeconds": 300
}
```

- Gateway JWT verification is disabled so the endpoint can receive both legacy
  service-role JWTs and current non-JWT project secret keys. The handler accepts
  only an exact server key resolved from `SUPABASE_SERVER_API_KEY`, the
  production-deploy-synchronized `MERIAN_SUPABASE_SERVER_API_KEY`, the hosted
  `SUPABASE_SECRET_KEYS` JSON dictionary, the singular `SUPABASE_SECRET_KEY`
  local/manual fallback, or the legacy `SUPABASE_SERVICE_ROLE_KEY` migration
  fallback. It never uses a database/RLS result as proof. Missing, conflicting,
  and mismatched keys receive `401`; ordinary user and publishable keys are not
  accepted. Worker RPCs use the server environment key rather than the accepted
  request value.
- `limit` is clamped to `1...500`.
- `leaseSeconds` is clamped to `30...600`.
- Primary and distinct-poster `HEAD` requests run in parallel per row within a
  global 24-media-row concurrency cap (at most 48 simultaneous `HEAD` requests);
  a five-minute lease covers the bounded provider-timeout envelope.
- The request cannot specify media IDs, post IDs, object keys, or owner IDs.
- Every primary/poster URL must resolve to a direct durable free/Pro key for the
  owner already attached to the leased database row. Cross-owner,
  temporary-prefix, nested, and arbitrary keys fail closed.
- Each leased primary URL receives a signed S3-origin `HEAD`. A distinct
  thumbnail receives an auxiliary check.
- Primary `404` maps to `missing`; `2xx` maps to `healthy`; timeouts, non-404
  failures, invalid URLs, and provider errors map to `retryable_error`.
- A thumbnail `404` is recorded and omitted but does not mark a healthy primary
  video/audio object as missing.
- Two `missing` outcomes at least five minutes apart are required before
  `health_status = missing`.

Response:

```json
{
  "success": true,
  "claimed": 37,
  "healthy": 34,
  "missingObservations": 2,
  "retryableErrors": 1,
  "errorCount": 0,
  "omittedErrors": 0,
  "errors": []
}
```

Every invocation attempts to write `explore_media_health_reconciliation_runs`.
Per-row result failures are reported as at most 50 private structured samples
with fixed reason codes; complete URLs/provider messages are never persisted or
returned. `errorCount` remains the authoritative total and `omittedErrors`
reports truncated samples. Any failure produces `partial_failure` audit status.
Configuration or lease-claim failures attempt a fixed-code `failed` audit row
before the endpoint returns its generic internal error.

---

## Deno `/ingest-r2-media-events` Edge Node

Accepts trusted Cloudflare Queue batches as reconciliation hints. It never
changes media health directly.

Headers:

```http
X-Merian-R2-Event-Secret: <dedicated random secret, at least 32 characters>
Content-Type: application/json
```

Request:

```json
{
  "object_keys": [
    "public_uploads/pro/{owner}/one.webp"
  ]
}
```

- One to 100 unique direct durable free/Pro object keys are accepted.
- Staging, export, quarantine, avatar, nested, traversal, and arbitrary keys are
  rejected.
- The Cloudflare consumer must not receive or forward the Supabase service-role
  key.
- Create and delete events both make matching health rows due now. The event is
  not treated as existence or deletion proof.
- Queue messages are acknowledged only after a `2xx` response.

Response:

```json
{
  "success": true,
  "accepted_key_count": 1,
  "matched_media_count": 2
}
```

The canonical state, projection, communication, recovery, and operations
contract for all three endpoints is
[Explore Media Health and Quarantine](./12-explore-media-health-and-quarantine.md).

---

## Authenticated Scan Metadata RPCs

Current iOS clients do not PATCH `public.scans` directly:

- `update_owned_scan_custom_tags(p_scan_id, p_custom_tags)` accepts at most 50
  control-free tags of at most 256 UTF-8 bytes each.
- `update_owned_scan_identification_review(p_scan_id, p_override, p_confirmed,
  p_confirmed_species_id, p_user_review_state)`
  validates one coherent `unreviewed`, `ai_confirmed`, or `user_overridden`
  state and updates all four review fields atomically.

Both SECURITY DEFINER routines have an empty fixed `search_path`, derive the
owner from `auth.uid()`, return the same permission failure for a foreign or
missing scan, and are executable only by `authenticated`. They never accept a
caller-supplied user ID. `anon` and `service_role` cannot execute them. A
temporary column-level UPDATE grant preserves already-installed app versions; it
covers only these five metadata columns and must be retired after the minimum
supported iOS version uses the RPCs.

---

## Deno `/delete-scan` Edge Node

Deletes a single scan from both Supabase PostgreSQL and Cloudflare R2.

### Request Payload

```json
{
  "scanId": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
}
```

### Authentication Enforcement

1. Extracts the verified user identity from the GoTrue JWT via the native
   `withEdgeHandler` middleware.
2. Calls the service-only `request_scan_deletion(scanId, userId)` transaction.
   It verifies exact ownership under the per-scan generation lock and persists
   the private deletion tombstone before external work. Foreign ownership
   returns `403`; a genuinely absent or already-completed owner generation
   returns idempotent `200`.
3. Reads the fenced canonical scan, normalized media assets, and post-derived
   thumbnails. A database read error is a sanitized `5xx`, never not-found.
4. Deletes only exact
   `https://media.merian.app/public_uploads/{free|pro}/{verified-owner-uuid}/{safe-filename}`
   objects, requiring 2xx or idempotent 404 for every accepted object. Foreign
   owners, nested/dot paths, query strings, fragments, credentials, staging,
   avatars, and malformed URLs are skipped without logging their values.
5. Calls `complete_scan_deletion(scanId, userId)`, which verifies the durable
   owner tombstone, deletes the Postgres row, and records completion. The linked
   Explore post, likes, comments, and media snapshots are permanently removed
   through foreign-key cascades.

The private tombstone survives completion and rejects any delayed inference,
replay, insert/update, or compatibility owner-row recovery for the UUID. A lost
response leaves a retryable deletion rather than permitting an ABA-style scan
resurrection. Completion clears the owner UUID from the private fence.

This explicit owner action is destructive and must be preceded by client copy
that names the linked Explore/engagement deletion. Operational media quarantine
never invokes this endpoint.

---

## Deno `/reconcile-scan-deletions` Edge Node

Service-only recovery worker for interrupted individual-scan erasure. It accepts
no caller-selected scan or user identity. Exact platform server-key
authorization is required before any claim.

PostgreSQL schedules the route every five minutes. One invocation claims
oldest-due rows in 25-job waves with UUID leases, processes at most 100 jobs at
concurrency four, and stops claiming near a 40-second deadline. For each claim
it reloads the canonical fenced source/derived media set, requires every owned
flat canonical R2 deletion to return 2xx or idempotent 404, and calls
`complete_scan_deletion(scan_id, user_id)`. A failure is compare-before-released
with bounded exponential backoff; a stale worker cannot clear a newer lease.

Successful response:

```json
{
  "success": true,
  "claimed": 2,
  "completed": 2,
  "deferred": 0,
  "health_status": "healthy"
}
```

The response and structured logs expose aggregate counters only. Scan IDs, owner
IDs, media URLs, and provider bodies are omitted. The independent Scan Media
Health Monitor calls the service-only `get_scan_deletion_health()` path every 30
minutes and warns at 15 minutes/25 pending jobs; it becomes critical at one
hour/100 pending jobs or any expired lease.

---

## Deno `/block-user` Edge Node

Inserts a moderation block, removing the specified user from the authenticated
user's Discovery Feed via `SocialGuardManager`.

### Request Payload

```json
{
  "blocked_id": "Target UUID to block"
}
```

### Authentication Enforcement

- Extracts the verified user identity from the GoTrue JWT via the native
  `withEdgeHandler` middleware.
- Validates `blocked_id` as a well-formed UUID — a non-UUID string is rejected
  with `HTTP 400` before any database access.
- Upserts the block into `public.user_blocks` using
  `onConflict: "blocker_id,blocked_id"` with `ignoreDuplicates: true`, making
  repeated block requests fully idempotent. A second block by the same user
  returns `200 OK` without inserting a duplicate row or surfacing a constraint
  error.
- Returns `400 Bad Request` if `blocked_id` matches the calling user's UUID to
  explicitly enforce the anti-self-blocking mitigation.

---

## Deno `/flag-issue` Edge Node

Requests human review of an AI inference from `ReportInsightView`, inserting a
row into the `flagged_reviews` table created by `00005_flagged_reviews.sql`.
This endpoint is not the Explore post-content reporting API.

### Request Payload

```json
{
  "scanId": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "flagReason": "Incorrect Species",
  "userSuggestion": "Optional taxonomy string provided by the user manually"
}
```

### Authentication Enforcement

- Extracts `user.id` from the `withEdgeHandler` middleware.
- Validates `scanId` as a well-formed UUID — a non-UUID string is rejected with
  `HTTP 400` before any database access.
- Validates `flagReason` against the enum
  `["Incorrect species", "Inappropriate content", "Bad image quality", "Other"]`.
  Values outside this set are rejected with `HTTP 400` before any database
  access.
- Inserts a row tracking the review request into `public.flagged_reviews`.
- Automatically overrides the underlying `public.scans` row, configuring
  `is_flagged = true` and dynamically stamping the `flagReason` and
  `userSuggestion` into the `human_intervention_notes` column to prompt Admin
  Dashboard review.
- Returns `HTTP 200` on success.
- Explore post-content reports use `/report-explore-post` instead and never
  change `scans.is_flagged` or `human_intervention_notes`.

---

## Deno `/request-export-dwca` Edge Node

This route remains deployed for old-client compatibility, but DwC-A is
authoritatively disabled for the initial launch. A valid permanent-account
request receives `403 feature_unavailable`; the alphabetically first database
BEFORE INSERT trigger independently rejects old Edge bundles and direct
service-role inserts. Release iOS builds hide the control.

When enabled through a reviewed migration, it queues an asynchronous Darwin Core
Archive (DwC-A) export. Because zipping thousands of records exceeds 30-second
HTTP connection limits, this endpoint validates the user and performs a bounded
`export_jobs` insertion transaction. That transaction fixes bounded immutable
phase DTOs plus compact live eligibility metadata under canonical row- and
source-byte budgets; CSV, ZIP, storage, and email work remains asynchronous. The
iOS client awaits the queue response off-main with a 15-second HTTP timeout.

### Request Payload

```json
{
  "includePreciseCoordinates": true,
  "exportScope": "personal"
}
```

### Authentication Enforcement

- Extracts user identity from the GoTrue header via
  `supabaseAdmin.auth.getUser(jwt)`.
- Rejects anonymous/ghost sessions with `403 account_required`; export email and
  per-account rate limits require a permanent authenticated identity.
- **`exportScope` authorization**: the public route accepts only `"personal"`.
  The default when omitted is `"personal"`. A `"global"` request receives
  `403 global_export_forbidden`; repository-wide exports require a reviewed
  internal administrative workflow. A non-string scope receives `HTTP 400`.
- **`includePreciseCoordinates` type validation**: `includePreciseCoordinates`
  must be a boolean. A non-boolean value (e.g. a string `"true"`) is rejected
  with `HTTP 400`.
- **Atomic release/rate boundary**: Calls service-only
  `request_dwca_export_job(user_id, scope, precision)`. PostgreSQL first locks
  the private release singleton in shared mode and fails closed if its state is
  absent/off. When enabled, it then takes a transaction advisory lock keyed by
  user, checks the rolling 24-hour successful/nonterminal window, and inserts in
  the same transaction. Reviewed state changes take the conflicting singleton
  row lock, so intake commits before the change or observes its new value.
  `disabled` maps to `403 feature_unavailable`; `rate_limited` and
  `already_pending` map to `429 Too Many Requests`. Failed jobs are excluded
  from the rolling window.
- On `queued`, inserts a row into `export_jobs` with status `pending`. Before
  the `pg_net` webhook can run, an ordered database trigger materializes the
  eligible scan IDs plus immutable bounded occurrence/multimedia JSON DTOs in
  one MVCC statement. Taxonomy follows `confirmed_species_id` when present,
  otherwise the original AI `species_id`. The account advisory lock prevents
  same-user check/insert races. The pending-job partial unique index remains a
  final duplicate fence; only its exact name maps to `already_pending`, while
  any unrelated uniqueness failure is rethrown and fails closed.
- The insertion statement counts only UUIDs through the row lookahead, then
  projects, measures, and inserts one DTO at a time through a parameterized
  lateral cursor. It stops at the first per-row or cumulative source-byte
  violation and removes partial rows, making the aggregate cap a DTO
  memory/temporary-sort work cap as well as a persistence cap.
- `anon` and `authenticated` have no direct `INSERT` privilege on `export_jobs`;
  callers cannot bypass this validation/rate-limit boundary through the Data
  API.

---

## Deno `/export-dwca` Edge Node (Webhook Worker)

For the initial launch, valid service-authenticated calls read the canonical
database release state and return `HTTP 200` with `"disposition":"disabled"`
before queue discovery or provider work. The global continuation cron is
unscheduled and all prior nonterminal jobs are terminal `feature_disabled`.

When enabled, the worker generates the DwC-A ZIP, uploads it to Cloudflare R2,
and emails the user the download link. This endpoint acts purely as a
Server-to-Server webhook triggered by `pg_net` after an `export_jobs` insertion.
It does _not_ accept iOS client connections.

### Request Payload (From Postgres `pg_net` Webhook)

```json
{
  "job_id": "UUID_A"
}
```

Only `job_id` is consumed by the hardened worker. For jobs created inside the
private two-hour migration rollout cohort, PostgreSQL may additionally send
canonical row-derived `user_id`, `export_scope`, and
`include_precise_coordinates` hints for the prior deployed bundle. They are not
authority, they stop appearing automatically after the protocol deadline, and
post-deadline jobs cannot enter processing without a private claim.

The minute-level resume cron sends `{}`. In that form the route repeatedly asks
`get_due_export_job_ids(5)` for oldest-due canonical work until the dispatcher's
soft deadline or step ceiling. An explicit webhook `job_id` is attempted once
without global discovery, bounding fan-out when many jobs are inserted together.
This empty-body contract is also bounded by the shared small JSON reader.

### Security & Enforcement

- Authenticates the Postgres origin by exact comparison with an
  environment-managed current or legacy server key. Current `sb_secret_...` keys
  use `apikey` only; legacy service-role JWTs may use matching Bearer and
  `apikey` transport. The route accepts only `POST`, uses the shared small
  bounded JSON reader, and returns stable request-correlated errors.
- Treats `job_id` only as an opaque wake-up identifier and never reads the
  deprecated user/scope/precision rollout hints. Status, pseudonym version, and
  object-key fields are absent from the webhook contract.
- Calls service-only `claim_export_job_step(job_id, claim_token)`. The RPC locks
  the queue and private work rows, returns immutable canonical state plus the
  current durable phase/cursors/budgets, and creates a private two-minute lease.
  An active, not-due, or terminal job returns no claim and performs no
  source/provider work.
- Calls service-only
  `get_dwca_export_scan_batch(job_id, claim_token, phase, cursor, 100, 262144)`
  for data phases. The database revalidates the claim and canonical cursor,
  keyset-paginates immutable creation-time `(job_id, scan_id)` DTO rows, and
  stops at either 100 scans or 256 KiB of serialized source. Each projection is
  limited to 256 KiB before insertion; total source JSON is limited to four
  times the job archive budget and at most 64 MiB. Global and non-precise
  personal DTOs omit exact GPS keys; an opted-in personal DTO retains them only
  when its snapshot taxonomy does not require protected-species redaction. A
  later scan or ordinary taxonomy/media edit is not part of and cannot alter the
  job. Page reads retain a compact post-cursor eligibility check. A shared
  full-member predicate verifies exact count, snapshot/invalidation state,
  current eligibility, and every stored hash before assembly, staging, email,
  completion, and each download authorization. Relevant scan and
  protected-species changes durably invalidate affected nonterminal jobs. A
  revocation becomes terminal `source_snapshot_changed`, sends no
  not-yet-started email, and removes an uploaded/staged object through the
  durable cleanup outbox. Validated row checks separately cap media-array
  cardinality/URL size, interaction-array cardinality/element size, and selected
  taxonomy text in UTF-8 bytes. Failed jobs purge immutable source DTOs;
  completed DTOs remain only through their live grant and verified cleanup.
- Opaque application capability URLs remain in API-inaccessible work state while
  processing. The final full-fence transaction publishes `file_url` and
  `completed` status atomically. The capability points to `download-dwca`, never
  directly to storage.
- Advance, manifest lookup, staging, completion, release, and heartbeat RPCs
  require the same unexpired UUID token; a delayed worker cannot mutate a
  replacement attempt. These definer routines use an empty `search_path`, call
  `internal.require_service_role()`, and are not executable by `PUBLIC`, `anon`,
  or `authenticated`.
- Resolves the email from the claimed canonical `user_id` through
  `supabaseAdmin.auth.admin.getUserById(...)`.
- **DwC-A Global Geoprivacy Leak Prevention**: Enforces strict IUCN Red List and
  ownership gating during ZIP compilation. Evaluates
  `canAccessPrecise = include_precise_coordinates && (scan.user_id === user_id)`.
  For global exports, users receive bounding-box obfuscated coordinates
  (hardcoded 50km `coordinateUncertaintyInMeters`) for scans they do not own.
  Crucially, if a species is flagged as protected (`endangered`, `vulnerable`,
  etc.), the exporter is **always** denied exact coordinates (even for their own
  captures), and public coordinates are aggressively decimate-rounded down to
  ~11km tiles to prevent poachers from extracting precise habitats via standard
  scientific downloads.
- **Versioned pseudonyms**: Global `recordedBy` values use a domain-separated
  HMAC-SHA256 truncated to 128 bits and prefixed with the pinned key version.
  The required Base64 `DWCA_PSEUDONYM_HMAC_KEY_V{n}` is independent of Supabase
  JWT/service keys and has no fallback.
- **Canonical budgets**: Jobs default to at most 5,000 CSV rows and an 8 MiB
  final archive; immutable database constraints cap custom internal jobs at
  20,000 rows and 16 MiB. Budget overflow terminates with `export_too_large`.
- **Resumable generation**: Every claim performs exactly one occurrence page,
  multimedia page, assembly, or delivery phase. An empty-body scheduled route
  invocation processes several claims sequentially, starting no new step after
  the 40-second soft cutoff and attempting at most 40 steps; a targeted insert
  wake-up attempts only its requested job once. Five-job discovery waves remain
  oldest-due ordered, so a successful advance rotates behind older work; failed
  or contended IDs are suppressed for the remainder of that invocation. Data
  phases use row-and-byte-aware `id > last_id` pages over one immutable DTO
  snapshot with page and final full-member privacy-revocation fences. A
  fixed-capacity encoder appends one header/row at a time and fails before
  exceeding 512 KiB; it does not retain a page-wide line array or expanded
  multimedia-row array. Each chunk's CRC-32 is calculated within that bounded
  preparation step and committed to the ordered private manifest together with
  the next cursor and cumulative budgets.
- **Aggregate queue health**: After every drain, the route calls the
  service-only `get_dwca_export_queue_health()` RPC and logs backlog, due,
  active/expired claim, and oldest-due-age values. The five-minute external
  monitor reads the same aggregate only; no job/user identity appears in its
  artifact.
- **Bounded assembly**: Manifest chunks lazily feed a streaming ZIP32 `STORE`
  writer and fixed 8 MiB R2 multipart upload. No complete page history, CSV,
  ZIP, `arrayBuffer()`, or media binary collection is retained in memory. R2
  create/complete XML and Resend replies are streamed through explicit byte
  limits. Completion rejects an S3-compatible `<Error>` body even when R2
  returns HTTP 200. Ordered manifest CRCs are combined algebraically, so
  assembly performs checksum work proportional to chunk count rather than a
  JavaScript loop over every archive byte. Streamed entry sizes must exactly
  match the manifest. Outbound operations have explicit deadlines.
- **Attempt-fenced storage**: Temporary chunk keys contain
  `phase/sequence-claim_token.csv`, and final archives use
  `exports/{user_id}/{job_id}/{claim_token}.zip`. A stale writer can therefore
  neither overwrite the winning chunk/archive nor commit an unexpected key to
  the manifest. After staging, a replacement lease reuses the stored archive key
  and opaque application capability.
- **Idempotent delivery**: Calls Resend directly with
  `Idempotency-Key: dwca-export/{job_id}` and marks the job complete only after
  Resend accepts the request. Re-entry with a staged archive does not regenerate
  it. Because the provider call cannot share a database transaction, completion
  repeats the full-member fence. If privacy changes while Resend is accepting
  the request, the email may exist, but completion fails terminally, revokes the
  capability, and enqueues the attempt-fenced archive for deletion. Permanent
  Resend 4xx rejection is terminal; ambiguous/transient responses remain
  retryable.
- **Revocable downloads**: A capability contains 32 random bytes encoded as an
  exact 43-character base64url token. The database looks it up by SHA-256 hash,
  applies a distributed 60-attempt/IP-hash/five-minute ceiling, and reruns the
  full immutable-membership privacy fence for every click. An authorized request
  receives only a no-store, read-only R2 redirect valid for at most 30 seconds.
  Unknown, revoked, expired, rate-limited, and dependency-error states fail
  closed with stable public codes.
- **Durable archive cleanup**: Expired/revoked grants, privacy races, terminal
  failures, deleted jobs, and legacy direct URLs enter a unique leased outbox.
  `reconcile-dwca-archive-cleanup` drains up to 100 oldest-due rows every five
  minutes with bounded concurrency and durable backoff. Its service-only health
  RPC exposes only backlog, oldest-due age, and expired-lease aggregates.
  Completion compares the leased key with the job's exact current attempt key;
  an old cleanup generation cannot revoke a replacement grant or purge active
  source state. An independent scheduled GitHub monitor calls both export queue
  and cleanup health RPCs, so absent cron/Vault configuration or a stuck
  deletion worker cannot be silent.
- **Stuck-job watchdog**: The watchdog fails pending rows with no phase progress
  for 30 minutes and processing rows with no live claim or durable progress for
  two hours. Public rows store stable failure codes/messages; provider responses
  and internal errors remain only in structured Edge logs. Failed jobs do not
  consume the next 24-hour request window.

### Response

After authentication and bounded parsing, the route synchronously performs a
deadline-bounded drain and returns `HTTP 200`:

```json
{
  "success": true,
  "request_id": "UUID",
  "disposition": "processed",
  "drain": {
    "targeted_wakeup": false,
    "attempted_steps": 8,
    "advanced_steps": 7,
    "completed_jobs": 1,
    "not_claimed_steps": 0,
    "failed_steps": 0,
    "discovery_waves": 3,
    "queue_drained": true,
    "runtime_deadline_reached": false,
    "step_limit_reached": false,
    "elapsed_milliseconds": 1234
  },
  "health": {
    "status": "ok",
    "backlog_count": 0,
    "due_count": 0,
    "active_claim_count": 0,
    "expired_claim_count": 0,
    "oldest_due_at": null,
    "oldest_due_age_seconds": null,
    "generated_at": "2026-07-26T22:00:00.000Z"
  },
  "results": [
    {
      "job_id": "UUID_A",
      "disposition": "advanced",
      "phase": "multimedia"
    }
  ]
}
```

Queue and health fields have deliberately different scopes:

- `backlog_count` includes every nonterminal job, including rows in retry
  backoff or protected by a live claim.
- `due_count`, `oldest_due_at`, and `oldest_due_age_seconds` include only rows
  whose retry deadline has arrived and which have no unexpired claim.
- `active_claim_count` and `expired_claim_count` count claim rows attached to
  outstanding jobs. Any expired claim makes health at least `warning`.
- `queue_drained` means no currently claimable due work remains after the
  invocation. It can be `true` while `backlog_count` is nonzero because another
  worker owns a live lease or work is waiting for bounded backoff.
- `runtime_deadline_reached` and `step_limit_reached` identify why an empty-body
  global drain stopped with due work remaining. Neither is set merely because
  delayed or leased backlog remains.

With no attempted job it returns `"disposition":"idle"` and an empty result
list. A duplicate wake-up can return a result with
`"disposition":"not_claimed"`. A step failure is durably released for retry or
terminal failure, appears only as `"disposition":"failed"` plus a stable
`failure_code`, and does not prevent unrelated due jobs from advancing. Invalid
auth/body values or dispatcher discovery/health failures receive stable
request-correlated HTTP errors; implementation/provider details remain in
structured logs only.

---

## Deno `/download-dwca` Edge Node

Public `GET` capability endpoint:

```text
/functions/v1/download-dwca?token={43-character-base64url-token}
```

For the initial launch, the canonical release state is off and the route returns
no-store `410 download_unavailable` before R2 signing. The launch migration
independently revokes existing capability hashes and queues known archives for
deletion.

The token is the only credential; JWT verification is disabled and
`Authorization` is not accepted as export ownership. Malformed/unknown tokens
return `404`, revoked or expired grants return `410`, the narrow
email-accepted/database-completion race returns retryable `425`, distributed
address-limit exhaustion returns `429`, and database/storage-signing outages
fail closed with `503`. All responses are no-store and request-correlated.

An authorized request transactionally reruns the complete source privacy fence,
then returns `303` to an attachment-only R2 GET signature valid for at most 30
seconds. Privacy triggers also invalidate every affected unpurged snapshot
without relying on a concurrently changing job status. No write credential or
long-lived direct URL is exposed.

---

## Deno `/reconcile-dwca-archive-cleanup` Edge Node

Internal `POST` worker invoked every five minutes. It accepts only one exact
platform-managed server credential, ignores caller-owned work identifiers, and
deadline-drains up to 100 leased deletion jobs in 25-row waves with four
concurrent R2 deletes. A missing object is idempotent success; all other storage
failures release the UUID-fenced claim with durable backoff.

Unlike intake, continuation, delivery, and downloads, this worker remains
scheduled during the initial launch-disabled period so revoked and legacy
objects still converge to physical deletion.

Database completion is also fenced to the exact current `archive_object_key`.
Physical deletion for an older attempt can complete its own outbox row, but it
cannot revoke a replacement grant or purge active source state. Exact-current
terminal cleanup revokes/marks the grant cleaned and then purges retained source
DTOs.

The response contains only claimed/completed/deferred counts and aggregate
health status. Structured health warns at 25 pending or 15 minutes oldest due,
and becomes critical at 100 pending, one hour oldest due, or any expired lease.
Tokens, users, object keys, and provider detail never enter the response or
health event. The independent **DwC-A Export and Archive Health Monitor** reads
this RPC directly on its own schedule as a worker-independent backstop.

---

## Deno `/refresh-species-content` Edge Node (Cron Worker)

Internal service-role worker for stale public species dictionary fields. It is
invoked hourly by `pg_cron`/`pg_net`, not by iOS clients.

### Request Payload

Scheduled call:

```json
{ "limit": 25 }
```

Manual service-role calls may also include:

```json
{
  "limit": 10,
  "dry_run": true,
  "as_of": "2026-05-13T00:00:00Z",
  "content_keys": ["wikipedia_url", "reference_images"]
}
```

### Authentication Enforcement

- `verify_jwt = false` is configured for `pg_net` compatibility.
- The function still requires one exact platform-managed current or legacy
  server key and validates it with `timingSafeCompare`; opaque keys use `apikey`
  only.
- Non-POST requests return `405`.

### Refresh Behavior

1. Claims `gbif_wikipedia_reference` rows from `species_enrichment_jobs` with
   the service role. If no jobs are available, falls back to
   `public.get_species_content_refresh_queue(limit, as_of)` for legacy
   provenance-driven refreshes.
2. Groups queued work by `species_id`.
3. Refreshes supported external fields from GBIF/Wikipedia:
   `alternative_common_names`, `taxonomy`, `wikipedia_url`,
   `wikipedia_overview`, `gbif_taxon_key`, and `reference_images`.
4. Updates `species_dictionary` only for fields where fresh external data
   exists.
5. Synchronizes normalized images through
   `public.replace_species_reference_images(...)`, which preserves
   `source = "merian"` rows managed by the Merian reference-image worker. Denied
   external media has already been removed from both the legacy string and
   normalized RPC payload; a database trigger silently rejects the current exact
   outlier if another service-role path attempts to write it.
6. Records new `species_content_provenance` rows for refreshed keys and marks
   claimed enrichment jobs succeeded or failed.

`20260707153931_species_dictionary_enrichment_queue_backfill.sql` is the source
of new queue coverage: it adds a `species_dictionary` insert trigger for future
rows and backfills existing sparse rows into the same `species_enrichment_jobs`
contract. The trigger intentionally runs only on insert so refresh updates do
not continuously reopen completed enrichment jobs.

Per-species refreshes run with a concurrency cap of 4.

Unsupported provenance keys (`common_names`, `habitat_description`,
`lookalikes`, `group_tags`, `iucn_red_list_status`, and `hazard_type`) are
skipped by this worker rather than overwritten. Habitat, lookalikes, and group
tags are handled by `/refresh-species-model-content`; common-name overrides,
IUCN status, and hazard type remain curation-owned.

---

## Deno `/refresh-species-model-content` Edge Node (Cron Worker)

Internal service-role worker for model-heavy species enrichment jobs. It is
invoked hourly by `pg_cron`/`pg_net`, not by iOS clients.

Scheduled call:

```json
{ "limit": 12 }
```

Manual service-role calls may also include `dry_run`, `as_of`, and
`content_groups` with any of `habitat`, `lookalikes`, or `group_tags`.

The worker claims matching `species_enrichment_jobs`, runs the same
species-level biology primitives behind `enrich-scan`, persists results to
`species_dictionary` / `species_lookalikes`, records provenance, and marks each
job succeeded or failed. It does not attach media to species and does not change
scan identity; scan-to-species attachment remains owner publish through
`confirmed_species_id`.

---

## Deno `/community-taxonomy-status` Edge Node (Internal Status)

Internal service-role endpoint for Community Taxonomy Index and species
enrichment observability. It is read-only and is intended for operational
dashboards, cron health checks, and manual rollout verification after GBIF cache
imports or Community ID publish flows.

### Authentication Enforcement

- `verify_jwt = false` is configured for service-role calls.
- The function still requires an exact platform-managed service credential:
  `SUPABASE_SERVER_API_KEY`, the production-deploy-synchronized
  `MERIAN_SUPABASE_SERVER_API_KEY`, a named `sb_secret_...` value from
  `SUPABASE_SECRET_KEYS`, the singular `SUPABASE_SECRET_KEY` local/manual
  fallback, or the migration-only `SUPABASE_SERVICE_ROLE_KEY` fallback. Current
  keys use `apikey` only; legacy JWTs use matching `apikey` and Bearer
  transport. Conflicting headers fail closed. Taxonomy table reachability and
  RLS-filtered results are never authorization evidence. Database reads use the
  server environment key, not the accepted request value.
- Non-POST requests return `405`.

### Request Payload

All fields are optional:

```json
{
  "import_run_limit": 10,
  "job_limit": 10,
  "view": "full",
  "target": "birds"
}
```

Both limits must be integers from `1` to `50`. `failure_limit` is accepted as a
backward-compatible alias for `job_limit`. `view = "full"` returns the full
taxonomy/enrichment health snapshot. `view = "coverage"` skips expensive active
taxonomy count queries and returns only bounded import runs plus coverage target
cursor state. `target = "birds"` filters the coverage view to the Birds import
scope.

### Response Payload

```json
{
  "success": true,
  "generated_at": "2026-06-22T00:00:00.000Z",
  "view": "full",
  "active_taxonomy": {
    "id": "taxonomy-version-id",
    "status": "active",
    "source": "merian_dictionary",
    "source_revision": "species_dictionary",
    "node_count": 1000,
    "species_node_count": 600,
    "dictionary_species_count": 240,
    "gbif_only_taxa_count": 360
  },
  "node_counts_by_source": [
    { "key": "gbif", "count": 500 }
  ],
  "node_counts_by_rank": [
    { "key": "species", "count": 600 }
  ],
  "latest_import_runs": [],
  "enrichment_jobs": {
    "counts": [
      { "content_group": "habitat", "status": "queued", "count": 10 }
    ],
    "next_jobs": [],
    "recent_failures": []
  },
  "coverage_targets": [
    {
      "slug": "birds",
      "display_name": "Birds",
      "indexed_species_count": 1000,
      "dictionary_species_count": 600,
      "coverage_ratio": 0.6,
      "last_imported_offset": 950,
      "next_import_offset": 1000,
      "last_successful_import_at": "2026-06-23T00:00:00.000Z",
      "last_import_error": null,
      "gbif_total_count": 14641
    }
  ]
}
```

The endpoint does not refresh coverage, claim jobs, cache GBIF taxa, materialize
Dictionary rows, or attach scan media. It only reports the current database
state available to the service role. Import operators and deploy smoke checks
should use `view = "coverage"` unless they explicitly need source/rank counts or
enrichment queue health.

---

## Deno `/sync-community-taxonomy-index` Edge Node (Internal Import Worker)

Internal service-role worker for bounded GBIF imports into the Community
Taxonomy Index. It is manual-first and resumable; no cron schedule is installed
in v1.

### Authentication Enforcement

- `verify_jwt = false` is configured for service-role calls.
- The function still requires an exact platform-managed service credential:
  `SUPABASE_SERVER_API_KEY`, the production-deploy-synchronized
  `MERIAN_SUPABASE_SERVER_API_KEY`, a named `sb_secret_...` value from
  `SUPABASE_SECRET_KEYS`, the singular `SUPABASE_SECRET_KEY` local/manual
  fallback, or the migration-only `SUPABASE_SERVICE_ROLE_KEY` fallback. Current
  keys use `apikey` only; legacy JWTs use matching `apikey` and Bearer
  transport. Conflicting headers fail closed. Taxonomy table reachability and
  RLS-filtered results are never authorization evidence. Privileged database
  work uses the server environment key, not the accepted request value.
- Non-POST requests return `405`.

### Request Payload

All fields are optional:

```json
{
  "target": "birds",
  "offset": 0,
  "limit": 50,
  "page_count": 1,
  "dry_run": false
}
```

Constraints:

- `target`: only `birds` in v1.
- `offset`: non-negative integer.
- `limit`: integer from `1` to `200`.
- `page_count`: integer from `1` to `5`.

### Response Payload

```json
{
  "success": true,
  "target": "birds",
  "root_gbif_taxon_key": 212,
  "dry_run": false,
  "imported_count": 50,
  "fetched_count": 50,
  "normalized_count": 50,
  "end_of_records": false,
  "next_offset": 50,
  "pages": [
    {
      "offset": 0,
      "limit": 50,
      "requested_query": "bounded:birds:root=212:rank=species:status=accepted:offset=0:limit=50",
      "fetched_count": 50,
      "normalized_count": 50,
      "imported_count": 50,
      "dry_run": false,
      "end_of_records": false,
      "next_offset": 50
    }
  ]
}
```

### Import Behavior

1. Fetches GBIF species search pages with `highertaxon_key=212`, `rank=SPECIES`,
   and `status=ACCEPTED`.
2. Normalizes rows into Merian's GBIF community taxon payload.
3. Calls `upsert_gbif_community_taxa(...)`, which inserts lineage and species
   nodes into `taxon_nodes` / `taxon_names` without deleting Dictionary-backed
   rows.
4. Annotates the created `taxonomy_import_runs` row as
   `scope = "gbif_bounded_birds"` with page metadata.
5. Relies on the existing RPC side effect to recompute
   `taxonomy_coverage_targets`.

The worker does not create `species_dictionary` rows, enqueue species
enrichment, or attach scan media. Those still happen only through
materialization triggers such as owner-published Community ID consensus.

### Manual Rollout Sequence

After migrations and Edge Functions are deployed:

1. Call `/sync-community-taxonomy-index` with `dry_run = true`, `offset = 0`,
   `limit = 50`, and `page_count = 1`.
2. If GBIF returns normalized rows, repeat the call without `dry_run`.
3. Call `/community-taxonomy-status` and confirm the latest import run has
   `scope = "gbif_bounded_birds"` and the Birds coverage target has a non-zero
   `indexed_species_count`.
4. Continue with the previous import response's `next_offset`.

Keep the first rollout to one page per call. Increase `page_count` only after
status checks show expected import rows and coverage counts.

---

## Deno `/refresh-merian-reference-images` Edge Node (Cron Worker)

Internal service-role worker for promoting high-quality published Explore media
into public species dictionary galleries. It is invoked hourly by
`pg_cron`/`pg_net`, not by iOS clients.

### Request Payload

Scheduled call:

```json
{
  "quality_threshold": 80,
  "species_confidence_threshold": 0.95,
  "per_species_limit": 8
}
```

Manual service-role calls may also include:

```json
{
  "quality_threshold": 95,
  "species_confidence_threshold": 0.98,
  "per_species_limit": 4,
  "dry_run": true
}
```

### Authentication Enforcement

- `verify_jwt = false` is configured for `pg_net` compatibility.
- The function still requires one exact platform-managed current or legacy
  server key and validates it with `timingSafeCompare`; opaque keys use `apikey`
  only.
- Non-POST requests return `405`.

### Refresh Behavior

1. Calls `public.refresh_merian_reference_images(...)` with the service role.
2. The SQL helper selects visible Explore posts only: shared, not unshared,
   non-tombstoned, media present, non-private backing scan geoprivacy,
   non-shadowbanned author, and resolved species present. This species-reference
   promotion gate is stricter than ordinary Explore visibility; post-level
   `private` location sharing can keep the post visible while omitting public
   location, but private backing scans are not promoted into Merian reference
   imagery.
3. It unnests all non-empty `scans.image_storage_urls`, requires
   `image_quality_score >= 80` and `ai_confidence_score >= 0.95` by default
   unless `confirmed_species_id` is present, dedupes by
   `(species_id, image_url)`, and promotes up to 8 images per species. Public
   videos are intentionally excluded from Dictionary/reference galleries.
4. Public rows use the stable technical `source = "merian"`,
   `license = "Used with permission via Naturebook"`, and
   `attribution = users.public_author_name`. This intentionally preserves the
   public display label rather than switching attribution to the username
   handle.
5. Provenance remains private in `species_reference_image_merian_sources`; no
   public species API exposes source scan, post, user IDs, confidence score, or
   confidence qualification source.
6. Rows are removed on the next refresh when the source Explore post/media is no
   longer publicly visible.

Response:

```json
{
  "success": true,
  "candidate_count": 12,
  "promoted_count": 8,
  "removed_count": 1,
  "species_count": 2,
  "dry_run": false
}
```

---

## Deno `/submit-feedback-survey` Edge Node

Accepts the one-time beta feedback survey from the iOS app. The endpoint is
authenticated through `withEdgeHandler`; the server ignores any client-provided
user identity and stores the response under the JWT user id.

### Request Payload

```json
{
  "survey_campaign_id": "beta_feedback_2026_06",
  "satisfaction_rating": 4,
  "recommendation_rating": 9,
  "used_features": ["identify_found_subject", "browse_explore"],
  "most_useful_features": ["camera_identification", "insight_sheet"],
  "confusing_or_disappointing": "Occasionally slow on older devices.",
  "wished_next": "More collection organization tools.",
  "bug_status": "workaround",
  "bug_details": "Retrying fixed one failed scan.",
  "may_follow_up": false,
  "contact": "",
  "app_version": "1.0",
  "build_number": "99",
  "platform": "ios",
  "device_model": "iPhone",
  "os_version": "19.0",
  "locale": "en_US",
  "timezone": "America/Chicago"
}
```

Validation rules:

- `survey_campaign_id` must match the active one-time campaign.
- Satisfaction must be an integer from 1 to 5.
- Recommendation must be an integer from 0 to 10.
- Feature/use values must be from the native survey enum sets.
- Free-text fields are trimmed and capped at 4,000 characters.
- Follow-up fields are retained for API compatibility. The current native survey
  sends `may_follow_up: false` and an empty `contact` value.

### Response Payload

```json
{
  "success": true
}
```

Responses are stored in `public.feedback_survey_responses` with RLS enabled.
Users can insert and read their own rows; product review happens through
Supabase dashboard/service-role tooling rather than public app APIs.

---

## Deno `/auto-purge-nonbio` Edge Node

A daily service-only retention endpoint responsible for generation-fencing stale
`.is_biological_subject = false` scans and enqueuing them for the durable
scan-erasure reaper.

### Request Payload

No JSON body is required. The cron trigger issues an empty POST request.

### Authentication Enforcement

- Enforces strict cron authorization via `timingSafeCompare` against one exact
  platform-managed current or legacy server key. Returns `401` if invalid.
- Prevents accidental `GET` evaluations by aggressively validating
  `req.method === "POST"`.

### Deletion Safety

1. Deadline-drains 500-row database batches, with a 40-second runtime budget and
   10,000-generation invocation ceiling.
2. The database selects only rows older than 30 days whose canonical
   `is_biological_subject` value is false, whose `is_tombstoned` value is false,
   whose owner is non-null and non-reserved, and which have no existing
   generation deletion tombstone.
3. Candidate discovery is oldest first, but generation locks are acquired in
   UUID order. Age, classification, scan-tombstone state, owner validity, and
   generation-tombstone absence are rechecked under the generation and scan-row
   locks.
4. The transaction writes the permanent private deletion fence and makes any
   incomplete ingestion ledger terminal. It does no R2 work and leaves the scan
   row available to the reaper.
5. `reconcile-scan-deletions` reloads the fenced row, deletes only exact
   owner-bound scan-media keys, retries interrupted work, and removes the row
   after external erasure succeeds.

Success reports newly requested work rather than completed object deletion:

```json
{
  "success": true,
  "requested_count": 42,
  "runtime_deadline_reached": false
}
```

`requested_count` is intake telemetry, not proof that R2 or relational erasure
has completed. Completion is observable only through the service-only
`get_scan_deletion_health()` summary and the independent health monitor.

| Status | Public contract                                                    |
| -----: | ------------------------------------------------------------------ |
|  `200` | Bounded retention intake completed                                 |
|  `401` | Exact server-key authorization failed                              |
|  `405` | Non-POST method                                                    |
|  `500` | Stable `internal_error` envelope with `X-Request-ID`; no raw error |

## Deno `/report-user`

Authenticated Explore viewers report a visible, non-self author profile. The
function has `verify_jwt = false` because it uses the repository's shared custom
Edge authentication wrapper; it is not an anonymous endpoint.

### Request payload

```json
{
  "reported_user_id": "6a4a8da6-41f5-45de-9569-5f77a60519c1",
  "reason": "Harassment",
  "details": "Optional context, at most 1,000 characters."
}
```

| Field              | Required | Contract                                                                   |
| ------------------ | -------: | -------------------------------------------------------------------------- |
| `reported_user_id` |      Yes | UUID; must differ from authenticated user                                  |
| `reason`           |      Yes | `Spam`, `Harassment`, `Impersonation`, `Inappropriate profile`, or `Other` |
| `details`          |       No | Trimmed text, maximum 1,000 characters; blank becomes `null`               |

Before persisting, the function calls
`get_explore_author_profile(self_id, target_author_user_id, 1)` with the service
client. A syntactically valid but non-visible/arbitrary target returns 404. This
reuses the profile's block, shadowban, post-moderation, and discoverability
rules instead of introducing a user lookup surface.

Success returns HTTP 200:

```json
{
  "success": true,
  "reported_user_id": "6a4a8da6-41f5-45de-9569-5f77a60519c1",
  "message": "Report submitted for moderation."
}
```

Validation/self-report errors return 400, missing/invalid authentication returns
401, and a non-visible profile returns 404.

The service-role upsert key is `(reporter_user_id, reported_user_id)`. The write
updates reason/details/time but deliberately omits `status`, so repeat evidence
from the same reporter does not reset `DISMISSED` or `ACTIONED`. A database
insert trigger attaches a new intake source to the private grouped user case.
The reporting action never blocks the target or modifies abuse state.

`get-explore-author-profile` includes `viewer_can_report`; it is true only when
the current viewer can use this endpoint for the non-self target.

## Internal admin RPCs

All RPCs use the normal authenticated Supabase client. The admin deployment has
no service-role key and does not read tables directly.

`admin_get_access_state` is the restricted pre-MFA routing check. It returns:

```json
{
  "is_authenticated": true,
  "is_member": true,
  "role": "moderator",
  "aal": "aal1",
  "session_active": false
}
```

It does not return raw application data. At `aal2`, `admin_begin_session`
creates/refreshes the internal session for the JWT `session_id` and returns the
role plus absolute expiry.

Every remaining RPC calls `internal.require_admin`, which verifies:

- immutable `auth.uid()` and valid JWT `session_id`;
- registered, active Google user and private membership;
- `aal2`;
- matching live `auth.sessions` row;
- internal session not revoked, not over eight hours, and active within 30
  minutes;
- minimum role.

### Aggregate RPCs

| RPC                      | Parameters                                                                    | Minimum role | Response                                                                                      |
| ------------------------ | ----------------------------------------------------------------------------- | ------------ | --------------------------------------------------------------------------------------------- |
| `admin_get_overview`     | `p_days`, `p_timezone`, `p_refresh`                                           | Analyst      | Range, account/plan counts, open reviews, new feedback, AI totals, prior period, daily rows   |
| `admin_ai_usage_summary` | `p_days`, optional operation/model/plan/modality, `p_scan_scope`, `p_refresh` | Analyst      | Token categories, cache rate, scan avg/p50/p95, modality totals, daily rows, coverage cutover |

`p_days` is clamped from 0 (all time) through 36,500. Overview daily rows use
the requested IANA timezone; AI summary daily rows currently use database time.
`p_scan_scope` is `primary` or `all_scan_related`. Authorized results are cached
for five minutes by the full filter key; `p_refresh = true` bypasses the cache.

### Review RPCs

| RPC                            | Important parameters                                                       | Minimum role |
| ------------------------------ | -------------------------------------------------------------------------- | -----------: |
| `admin_list_review_cases`      | Optional status/type/priority/assignee/reason/from/to, tuple cursor, limit |    Moderator |
| `admin_get_review_case`        | `p_case_id`                                                                |    Moderator |
| `admin_update_review_case`     | Case ID, optional status/priority/assignee change/resolution/note          |    Moderator |
| `admin_set_content_visibility` | Case ID, hidden boolean, required reason                                   |    Moderator |

Review list responses use:

```json
{
  "items": [],
  "limit": 100,
  "next_cursor": {
    "updated_at": "2026-07-19T12:00:00Z",
    "id": "00000000-0000-0000-0000-000000000000"
  }
}
```

Case detail returns `case`, `subject`, `sources`, `notes`, and a nullable
`scan`. The scan object, available only for identification review, may include
exact coordinates; the read is audited. Assignments accept only active moderator
or owner UUIDs. Note storage permits 4,000 characters, but the current
transition RPC mirrors the note into the audit `reason` field and therefore has
an effective 1,000-character limit. Hide/restore is valid only for post/comment
cases, requires a reason of at least three characters, and never changes case
status.

### Feedback and user RPCs

| RPC                     | Parameters                                                     | Minimum role |
| ----------------------- | -------------------------------------------------------------- | -----------: |
| `admin_list_feedback`   | Optional source/status/rating/app-version, tuple cursor, limit |    Moderator |
| `admin_update_feedback` | Source type/ID, state, assignee, tags, optional note           |    Moderator |
| `admin_list_users`      | Search, `(created_at,id)` cursor, limit                        |    Moderator |
| `admin_get_user_detail` | User UUID                                                      |    Moderator |

Feedback states are `new`, `reviewed`, `planned`, and `closed`; original
submissions are never changed. User search matches partial/exact email, Auth
UUID, and public handle. Search input is sent through a server action rather
than a URL query. Both search and detail access are audited.

### Owner RPCs

| RPC                    | Parameters                                 | Purpose                                         |
| ---------------------- | ------------------------------------------ | ----------------------------------------------- |
| `admin_list_members`   | None                                       | Membership inventory                            |
| `admin_upsert_member`  | Exact email, role, active state            | Add/update an existing verified Google user     |
| `admin_list_sessions`  | None                                       | Supabase/internal admin sessions                |
| `admin_revoke_session` | Session UUID, reason                       | Revoke internal session and delete Auth session |
| `admin_list_audit`     | Optional exact action, tuple cursor, limit | Immutable audit history                         |

The member RPC accepts roles `analyst`, `moderator`, and `owner`, and prevents
disabling/demoting the final active owner. Revocation reasons must contain at
least three characters.

All list limits are clamped to 1–100. Callers must pass back the complete
`next_cursor`; there is no offset pagination. Sensitive list/detail access and
mutations write an audit row. Browser server actions additionally enforce an
exact same-host `Origin` check before mutation.

See [`10-internal-admin.md`](./10-internal-admin.md) for the data/security model
and [`11-internal-admin-operations.md`](./11-internal-admin-operations.md) for
setup, deployment, and recovery.

## Deno `/revenuecat-webhook` Edge Node

Receives signed POST events from RevenueCat and reconciles the latest
authoritative subscriber state into Supabase. The route is a server-to-server
boundary; the iOS SDK and client-reported entitlements never authorize the
database write.

### Request Payload

The body is a RevenueCat Webhook envelope with an `.event`. The handler requires
bounded, non-control-character values for `event.id` and `event.type`, plus a
non-negative safe-integer `event.event_timestamp_ms`. Optional `app_user_id`,
`original_app_user_id`, `aliases`, `product_id`, `transaction_id`, and
`original_transaction_id` are validated before use. `TRANSFER` instead requires
non-empty, bounded `transferred_from` and `transferred_to` arrays. An event
timestamp more than five minutes ahead of the signed delivery timestamp is
rejected before database access. The request body is capped at 256 KiB.

### Authentication Enforcement

- Requires `Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>` and compares it
  in constant time.
- Requires
  `X-RevenueCat-Webhook-Signature:
  t=<unix-seconds>,v1=<hmac-sha256-hex>`.
  `REVENUECAT_WEBHOOK_SIGNING_SECRET` signs the ASCII timestamp/dot prefix plus
  the exact raw request bytes. Verification happens before UTF-8 decoding or
  JSON parsing, permits more than one `v1` digest for protocol compatibility,
  and rejects timestamps more than five minutes in the past or future.
- Missing any of the Authorization, signing, or server API secrets returns `401`
  or `503`; there is no static-secret-only compatibility path.
- **Customer identity contract**: iOS logs RevenueCat into the Supabase Auth
  UUID and writes subscriber attributes (`supabase_user_id`, `auth_email`,
  `public_username`, `public_author_name`, `public_identity_source`,
  `account_kind`) before entitlement checks. Manual dashboard adjustments should
  use the UUID/App User ID first, with subscriber attributes as the
  human-readable cross-reference. This applies to both RevenueCat Test Store and
  production keys.
- UUID candidates are ordered from `app_user_id`, `original_app_user_id`, then
  `aliases` and deduplicated. A RevenueCat `TRANSFER` creates independent source
  and destination subjects from its two identity arrays; it does not have an
  `app_user_id`. Each subject must resolve transactionally to exactly one live
  `public.users` row. A purely anonymous customer receives a durable
  `200 ignored` event receipt without a provider call; a later alias event has a
  different event ID and can carry the linked UUID. A UUID with no public
  profile returns retryable `503`, while a group that maps to multiple live
  profiles returns `409`. The one exception is an already-deleted transfer
  source: no Merian access remains to revoke, so that subject is omitted without
  blocking the destination. Billing never creates a user.

### Authoritative state and transaction

- The server calls, for every mapped customer,
  `GET https://api.revenuecat.com/v1/subscribers/{app_user_id}` with
  `Authorization: Bearer <REVENUECAT_SECRET_API_KEY>` after each new accepted
  webhook. Before that call, `get_revenuecat_webhook_event_result(...)` checks
  the private ledger; a committed duplicate with the same event timestamp, type,
  and payload SHA-256 returns immediately so normal retries and in-window
  replays do not amplify provider traffic. The response is capped at 2 MiB and
  must contain a safe-integer `request_date_ms` and subscriber object; an
  implausibly future snapshot is rejected. Network/provider errors return
  `502`/`503` without a database mutation. For `TRANSFER`, source and
  destination lookups run concurrently and both must succeed before the database
  call.
- An active standard entitlement whose identifier is `pro` or `Naturalist Tier`
  projects `subscription_tier = pro` and persists the later of recurring
  expiration and grace-period expiration. `NULL` is reserved for an entitlement
  whose provider expiration is explicitly null (lifetime).
- An unexpired authoritative `pro_week` transaction projects a timed Pro expiry
  at `purchase_date + 7 days`. A matching pass refund/revocation is excluded; an
  unmatchable revocation fails closed for transactions at or before the event
  time while preserving a provably later purchase.
- No active paid state projects `subscription_tier = free` and a null expiry.
- `public.apply_revenuecat_customer_state(...)` records `event.id` under a
  primary key, records zero to two per-user subject rows, and locks all selected
  users in sorted UUID order. Authoritative `request_date_ms` is the primary
  monotonic version; provider event timestamp and event ID break only exact
  snapshot ties. Duplicate IDs and older snapshots cannot update a user; a
  conflicting reuse of the same ID with a different event timestamp, type, or
  payload digest is rejected. Transfer source/destination transitions commit or
  roll back together.
- The RPCs and private ledger tables are not client APIs. Only `service_role`
  may execute the duplicate lookup and mutation definer routines; both perform
  their own caller check and use an empty search path.
- Existing scan media stays in place on tier changes. Both
  `public_uploads/free/` and `public_uploads/pro/` are durable scan-media
  prefixes.

### Response contract

- `200 {"success":true,"outcome":"applied","subject_count":N,
  "applied_count":N,"stale_count":0}`:
  all mapped authoritative transitions were accepted.
- `200 ... "duplicate"`: the exact event ID/timestamp/type/payload was already
  committed; the three counts describe its original result.
- `200 ... "stale"`: all mapped subjects were recorded but their ordering tuples
  were older.
- `200 ... "mixed"`: a multi-subject transfer applied for one user while the
  other already had a newer watermark.
- `200 {"success":true,"outcome":"ignored","subject_count":0,
  "applied_count":0,"stale_count":0}`:
  no Supabase UUID existed in the RevenueCat identity set; the event ID was
  still persisted.
- `400`: malformed event data.
- `401`: Authorization or HMAC verification failed, including replay-window
  rejection.
- `409`: the same event ID was reused with conflicting immutable fields, or a
  RevenueCat identity group mapped to multiple live Merian profiles.
- `413`: the raw webhook body exceeds 256 KiB.
- `405`: any method other than `POST`.
- `502`/`503`: authoritative subscriber lookup, configuration, public-profile,
  or database availability failed. RevenueCat should retry these non-2xx
  responses.

### Service-only authoritative reconciliation

`/reconcile-revenuecat-subscribers` is not a client API. The 15-minute `pg_cron`
call sends `POST {}` with one exact platform-managed current or legacy server
key. The route also requires a configured `sk_` RevenueCat server key and
accepts no user ID, lookup ID, tier, or limit from HTTP. Its `pg_net` response
timeout is 120 seconds.

The private queue leases six due linked customers per short
`FOR UPDATE SKIP LOCKED` wave for two minutes. The worker repeats waves until
empty or until its 60-second monotonic start-work cutoff; the remaining 30
seconds are reserved for the final bounded wave, writes, and health read.
CustomerInfo lookups run with concurrency three and reuse the same 10-second, 2
MiB provider boundary as webhook processing. A claim-token-fenced
`apply_revenuecat_reconciliation(...)` updates access only when
`request_date_ms` is newer than the transactional customer watermark. Pro users
are next due in six hours and free users in 24 hours; transient failures use
durable database backoff.

Background reconciliation does not newly grant a historical `pro_week`
transaction after a free/revoked watermark, preventing refunded pass history
from restoring access. Its response is aggregate only:

```json
{
  "success": true,
  "claimed": 3,
  "reconciled": 3,
  "applied": 1,
  "stale": 2,
  "failed": 0,
  "claimBatches": 2,
  "queueDrained": true,
  "runtimeDeadlineReached": false,
  "healthStatus": "ok",
  "health": {
    "generatedAt": "2026-07-26T03:30:00.000Z",
    "dueCount": 0,
    "expiredClaimCount": 0,
    "oldestDueAt": null,
    "oldestDueAgeSeconds": null
  }
}
```

`get_revenuecat_reconciliation_health()` is a separate service-role-only Data
API RPC. It returns one aggregate row and no customer identity. The scheduled
GitHub monitor invokes it directly, warning when oldest due age reaches 30
minutes or any claim expires and marking 60 minutes critical.
