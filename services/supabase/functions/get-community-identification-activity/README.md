# Get Community Identification Activity

`get-community-identification-activity` is the authenticated client boundary for
the grouped Activity feed shown in Explore Identify. It returns privacy-filtered
suggestion bursts, standalone consensus changes, and immutable resolution
milestones. It is not the Explore bell/notifications feed.

## Authentication

`services/supabase/config.toml` deliberately sets `verify_jwt = false` for this
route because authentication is owned in handler code:

1. `withEdgeHandler` creates the server client and calls `requireAuth`.
2. `requireAuth` validates the request's user JWT and returns the canonical
   user.
3. The handler derives `self_id` from that user; no viewer ID is accepted from
   JSON.
4. `db.ts` invokes the service-role-only
   `public.get_community_identification_activity(...)` RPC.

The platform setting does not make the function public. Missing or invalid user
authentication returns `401`. Never expose the server secret or invoke the RPC
directly from iOS.

## Request

Method: `POST`

Body:

```json
{
  "limit": 10,
  "scope": "all",
  "group": "birds",
  "before_activity_at": "2026-07-30T19:00:00.000Z",
  "before_activity_id": "00000000-0000-4000-8000-000000000002"
}
```

All fields are optional:

| Field                | Contract                                                                          |
| -------------------- | --------------------------------------------------------------------------------- |
| `limit`              | Finite number, floored and clamped to `0...100`; missing/nonnumeric values use 30 |
| `scope`              | `all` or `mine`; `mine` means requests owned by the viewer                        |
| `group`              | `all`, `plants`, `birds`, `insects`, `fungi`, `mammals`, or `reptiles_amphibians` |
| `before_activity_at` | Valid cursor timestamp; must accompany `before_activity_id`                       |
| `before_activity_id` | Valid UUID; must accompany `before_activity_at`                                   |

Unknown enum values, malformed cursors, and unpaired cursor fields return `400`.
The request uses the bounded `small` JSON ingress class.

## Response

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

`activity_type` is one of:

- `suggestion_burst`
- `consensus_changed`
- `resolved`

Non-suggestion rows return `suggestion_count: 0` and an empty
`recent_actor_names` array. Taxon, consensus, hero image, and media fields may
be nullable or empty when no visible value is available.

Results are ordered by `(activity_at DESC, activity_id DESC)`. To request the
next page, copy both cursor fields from the final returned row. Never send a
timestamp-only cursor; equal timestamps are disambiguated by UUID.

## Projection semantics

Migration `20260731050009_add_community_identification_activity.sql` owns the
projection:

- Suggestions for one request `requested_at` generation chain into one burst
  while each adjacent suggestion occurs no more than 60 minutes after the prior
  suggestion. Exactly 60 minutes remains in the burst.
- Repeated suggestions from one actor increment that actor's count; actor IDs
  are normalized separately from the group.
- The actor table tracks every distinct actor's count and `last_suggested_at`;
  the read RPC returns up to the three most recent visible actors and resolves
  their names at that time.
- A consensus event caused by `identification_submitted` enriches the associated
  suggestion burst's latest taxon/score metadata.
- A consensus change without an associated submission is a standalone
  `consensus_changed` row.
- A transition to resolved is always a separate immutable `resolved` milestone.
- Backfill replays suggestions and consensus events only from each request's
  current `requested_at` generation. Earlier withdrawn/reopened generations stay
  available in request audit detail but are not returned in Activity.

AFTER INSERT triggers on `explore_identifications` and
`community_consensus_events` maintain new rows. Request locking serializes
concurrent suggestions for one generation and prevents duplicate bursts around
the boundary.

Companion migration
`20260731063804_index_community_identification_activity_actor_user_fk.sql`
indexes `community_identification_activity_actors.user_id`. Existing indexes
lead with `activity_group_id`; the reverse index prevents account deletion or
identity maintenance from scanning the actor table while enforcing its user
foreign key.

## Visibility and security

Every read reapplies current visibility rather than trusting projection state:

- request is not withdrawn;
- post is shared and unmoderated;
- scan is not tombstoned;
- request owner is not shadowbanned;
- neither viewer/owner block direction exists;
- aggregate media is not quarantined; and
- at least one non-missing post media item remains.

Burst suggestion counts and recent actors additionally exclude blocked or
shadowbanned actors. A burst with no visible actor suggestions is omitted.
Visible actor names are resolved from `public_author_name` at read time with the
generic Naturebook explorer fallback.

Both internal projection tables have RLS enabled. `PUBLIC`, `anon`, and
`authenticated` have no direct table privileges. Only `service_role` can
maintain/read the tables and execute the RPC. Fetching Activity never reads,
creates, marks, or aggregates Explore notification unread state.

## Client policy

- Requests dashboard preview: exactly 10 Activity groups.
- Complete **Identify activity** feed: 30 rows per page.
- The same All/Yours/organism filter is sent to Requests and Activity.
- Activity failure is independent from request failure.
- Tapping any Activity row opens existing request detail.

These limits and UI rules are owned by `CommunityIdentificationDashboardPolicy`
in the iOS Identify view.

## Verification

Run the discovery-based backend gate:

```bash
make test-supabase-tooling
```

Run the complete fresh-catalog pgTAP gate before production migration push:

```bash
make test-supabase-privileged-routines
```

Focused coverage lives in:

- `db_test.ts` — RPC arguments, filters, cursor forwarding, and error
  propagation.
- `../_tests/communityIdentificationActivityDb.test.ts` — inclusive 60-minute
  grouping, repeated actors, top-three actor order, consensus folding,
  standalone consensus, resolution, shared filters, cursor ties, visibility, and
  reopen behavior against PostgreSQL.
- `../_tests/communityIdentificationActivityMigrationContract.test.ts` —
  table/RLS/ACL, trigger, RPC, backfill, and service-role source contracts.

The PostgreSQL-backed test requires the repository's disposable/local test
database. A connection skip is discovery evidence only and must not be reported
as relational acceptance.

## Deployment

Deploy in compatibility order:

1. Push the activity projection migration and its actor-user foreign-key index
   companion in timestamp order, then wait for PostgREST schema reload.
2. Deploy `get-community-identification-activity`.
3. Smoke authentication, shared filters, exact-timestamp cursor ties, and direct
   RPC denial with client credentials.
4. Release the iOS build that exposes dashboard Activity.

Do not grant the RPC to client roles to work around route propagation. If
Activity must be contained, roll the iOS/Edge presentation forward while
retaining the additive projection; Requests is designed to remain usable through
an independent Activity error state.
