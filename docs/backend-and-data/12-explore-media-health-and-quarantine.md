# Explore Media Health and Quarantine

Last updated: July 29, 2026

## Decision

Naturebook never automatically deletes or unpublishes an Explore post because
its media cannot be loaded. Unexpected media loss is an operational incident,
not an author action and not a moderation decision.

The system uses a reversible media quarantine:

- a client, CDN, or network failure only shows a retryable unavailable state;
- two direct Cloudflare R2 origin `HEAD` checks returning `404`, at least five
  minutes apart, confirm a primary object as missing;
- confirmed-missing items are omitted while any usable item remains;
- a post is removed from every public projection only when all of its primary
  media is confirmed missing;
- the post row, author publication state, likes, comments, reports, and audit
  history remain intact; and
- a successful repair automatically restores the item and republishes the post
  if the author has not unpublished it and moderation has not removed it.

Do not substitute dictionary or reference artwork for observation evidence.

## Why

Deleting a post destroys user intent and engagement during what may be a
temporary or repairable storage incident. Leaving an all-missing post public
produces a broken Feed, Map, profile, search, and share experience. Reversible
quarantine preserves both sides: the public product remains coherent and the
owner retains a repairable record.

Postgres stores metadata and URLs. R2 stores the bytes. A surviving URL is not a
byte-level backup, and R2 durability does not protect an object from a valid
application-authorized deletion.

## State model

### Media item

| State               | Meaning                                                            | Public behavior                                |
| ------------------- | ------------------------------------------------------------------ | ---------------------------------------------- |
| `healthy`           | Primary R2 object is expected to exist or was origin-verified.     | Included.                                      |
| `suspected_missing` | One direct origin `404`; confirmation is not yet due.              | Included to avoid reacting to one observation. |
| `missing`           | A second direct origin `404` occurred at least five minutes later. | Omitted.                                       |

A distinct poster or thumbnail is checked and its HTTP status is recorded, but
it is auxiliary. A missing poster is omitted; it does not hide an otherwise
playable video or audio object. For ordinary image rows, the primary and
thumbnail URL are the same object.

`5xx`, timeouts, malformed responses, credential failures, and transport errors
are `retryable_error` outcomes. They never advance an item to `missing`.

### Explore post

| State         | Condition                                       | Public behavior                                               |
| ------------- | ----------------------------------------------- | ------------------------------------------------------------- |
| `healthy`     | No item is confirmed missing.                   | Public if ordinary publication and moderation rules allow it. |
| `degraded`    | Some, but not all, items are confirmed missing. | Public with only usable items.                                |
| `quarantined` | Every item is confirmed missing.                | Hidden from all public projections.                           |

`media_health_status` is system-owned and independent from:

- `unshared_at`, which records the author's publish/unpublish intent;
- `moderated_at`, which records enforcement; and
- scan tombstoning or explicit deletion.

The canonical `explore_projected_post_cards` projection is the visibility
boundary used by Feed, Map, search, author profile, post detail, hashtag, and
public share consumers. Specialized projections must derive from it or enforce
the same quarantine and item-health predicates.

Author profile count, preview, and full grid must all use that canonical
projection. Preserved publication intent is a different owner-only concept and
must never be displayed as the number of currently visible posts.

`get_scan_explore_share_state` enforces the same moderation, aggregate-health,
and non-missing-item visibility predicates. It still returns the owner-only post
identity while quarantine or moderation hides a post, but sets
`is_explore_feed_visible = false`. A degraded post returns true when at least
one usable item remains. This lets clients distinguish repairable publication
intent from a destination that can actually be opened in Explore.

## Verification pipeline

`reconcile-explore-media-health` runs every five minutes:

The gateway uses `verify_jwt = false` because current Supabase project secret
keys are not JWTs. This does not make the worker public. The handler accepts the
exact configured server key through `_shared/serviceRoleAuth.ts`: an explicit
`SUPABASE_SERVER_API_KEY`, the production-deploy-synchronized
`MERIAN_SUPABASE_SERVER_API_KEY`, a named current key in the hosted
`SUPABASE_SECRET_KEYS` JSON dictionary, the singular `SUPABASE_SECRET_KEY`
local/manual fallback, or the legacy `SUPABASE_SERVICE_ROLE_KEY` migration
fallback. Current opaque keys use `apikey` only; a legacy service-role JWT uses
matching `apikey` and Bearer values. Authorization is an exact constant-time
comparison and never a table/RLS capability probe. Missing, conflicting,
ordinary user, publishable, and mismatched credentials fail with `401`.
Downstream database clients use the environment-resolved key rather than the
accepted request value. The full contract is in
[`13-server-credentials-and-database-release-safety.md`](./13-server-credentials-and-database-release-safety.md).

1. `claim_explore_media_health_checks` leases a bounded due batch with
   `FOR UPDATE SKIP LOCKED`.
2. The worker derives the canonical durable object key from the public URL. The
   key must be a direct `public_uploads/free|pro/{same-owner}/{object}` path;
   arbitrary prefixes and cross-owner keys fail closed.
3. It signs a direct R2 S3-origin `HEAD`; it does not use the public CDN as
   authority.
4. `record_explore_media_health_check` validates the lease and applies the state
   transition.
5. Database triggers recompute post health and owner notifications.
6. The worker records a reconciliation-run audit row.

Healthy active primary media is checked every 24 hours. A distinct impaired
poster is rechecked hourly without hiding its healthy primary. Suspected loss is
checked no earlier than five minutes later. Confirmed loss is rechecked hourly
so an operator restore or object reappearance can self-heal.

Cloudflare R2 event notifications are an accelerator only. A trusted Queue
consumer may send up to 100 durable keys to `ingest-r2-media-events`, which
makes matching rows due immediately. Create and delete events are not proof of
existence or loss; the direct origin reconciler remains the source of truth. See
Cloudflare's
[event notification documentation](https://developers.cloudflare.com/r2/buckets/event-notifications/)
and Supabase's
[scheduled Edge Function guidance](https://supabase.com/docs/guides/functions/schedule-functions).

## Owner experience

On the first transition from healthy into an active incident:

- create one unread `media_missing` in-app notification;
- send one push only to devices whose Explore notification preference allows it;
  and
- show a persistent **Needs attention** banner in Scan Library.

The owner's Profile `Published scans` preview and full grid also show a
persistent explanatory summary while recovery is pending. It reports preserved
publication intent, currently visible posts, and recovery-needed posts, then
directs the owner to Scan Library. It does not put a broken post back into a
public grid.

The banner explains whether the post is degraded or hidden and explicitly says
that the post, likes, and comments are safe. **Review** opens the linked local
scan when available, which lets device-assisted recovery inspect a strongly
matched surviving file.

When all media recovers:

- remove the active missing notification;
- create one `media_restored` in-app notification;
- do not send a restore push; and
- remove the Scan Library banner after refresh.

Tapping a missing notification opens Scan Library recovery. Tapping a restored
notification can open the public post.

## Recovery

The health lifecycle prevents broken public posts; it does not recreate bytes.
Recovery sources, in priority order, are:

1. a surviving strongly matched owner file on a device;
2. a verified operator-controlled recovery source, if one exists; or
3. owner replacement in a future explicit replacement workflow.

Current device-assisted image recovery uses `/repair-scan-image`. It verifies
ownership and source loss, promotes a new owner-scoped durable object, and
atomically replaces exact references in scan arrays, captured media,
`scan_media_assets`, and `explore_post_media`. The same transaction resets media
health to `healthy`, which can automatically clear quarantine.

A routine `refresh_explore_post_media` snapshot rebuild preserves health by
stable `(post_id, kind, url)` identity through a private continuity ledger. It
cannot accidentally republish confirmed-missing media.

If no recoverable byte copy exists, preserve the quarantined record for the
owner. Do not silently delete it and do not claim that repeated checks can
restore an object that no longer exists.

## Explicit deletion

Explicit owner deletion remains destructive and is different from operational
quarantine. A scan owns its Explore post through
`explore_posts.scan_id ON
DELETE CASCADE`; likes and comments then cascade from
the post.

Every scan-deletion confirmation must warn:

> This permanently removes the scan and cloud media. If it is published to
> Explore, that post, its likes, and its comments are also permanently removed.

The deletion path must use the existing owner-authorized worker. Health
reconciliation must never issue object or relational deletes.

## Security and storage controls

- Authenticated users can list only their own active media incidents.
- Claim, result, event-expedite, and audit-write paths are service-only.
- The origin verifier rejects non-durable, nested, traversal, and cross-owner
  keys before issuing R2 requests.
- Private lease and health-continuity tables are not directly granted even to
  API roles.
- Event ingress uses a dedicated secret of at least 32 random characters. Do not
  expose the Supabase service-role key to a Cloudflare Worker or Queue.
- Production requires bucket-scoped Object Read credentials in
  `R2_READ_ACCESS_KEY_ID` and `R2_READ_SECRET_ACCESS_KEY`. The verifier does not
  fall back to promotion/deletion credentials.
- Promotion and deletion credentials remain separate and least privileged.
- Durable `public_uploads/free/`, `public_uploads/pro/`, and avatar prefixes
  must have no age-based lifecycle expiry. Review lifecycle rules against
  Cloudflare's
  [object lifecycle contract](https://developers.cloudflare.com/r2/buckets/object-lifecycles/).
- Any future recovery-copy system must propagate explicit account/scan deletion
  and receive privacy/legal retention review before production use.

Supabase RLS remains defense in depth; function-level ownership checks and
explicit grants are mandatory. See the
[RLS guide](https://supabase.com/docs/guides/database/postgres/row-level-security).

## Monitoring and incident response

Alert on:

- no successful reconciliation run for 15 minutes;
- oldest due active item older than 15 minutes;
- expired leases or result-record failures;
- a sudden increase in first or confirmed missing observations;
- aggregate post state inconsistent with item counts; and
- any durable-prefix lifecycle rule with age-based expiration.

Every production backend deploy calls the service-only
`get_explore_publication_health_summary()` RPC and prints only aggregate totals:
active, healthy, degraded, quarantined, affected authors, and confirmed-missing
items. This is the authoritative first answer to “one account or several?”
without exposing owner identifiers or object keys. Affected totals above the
known incident cohort require immediate scoped investigation; zero does not
prove missing bytes were recovered because unreconciled references may still
await origin checks.

For a spike:

1. pause destructive storage workers, credential rotations, and lifecycle
   changes;
2. preserve reconciliation and account-deletion audit evidence;
3. identify owner/key concentration and first-observed time;
4. verify sample keys through direct R2 origin checks;
5. confirm the account-deletion claim fence is deployed;
6. restore only from evidence-backed owner or operator copies; and
7. let successful health checks restore public projection automatically.

Never bulk-update health to `healthy` without proving object existence.

## Implementation map

- Migrations: `20260726144647_add_explore_media_quarantine_lifecycle.sql` and
  `20260726144754_implement_explore_media_quarantine_state_machine.sql`, plus
  `20260726174555_align_explore_author_publication_contract.sql` for canonical
  profile/grid counts and aggregate scope, and
  `20260729120000_align_explore_share_state_media_health.sql` for owner
  share-state/public-projection parity
- Scheduled worker: `reconcile-explore-media-health`
- Owner API: `get-explore-media-incidents`
- Owner publication totals: `get_owned_explore_publication_summary`
- Owner scan share-state: service-only
  `get_scan_explore_share_state(self_id, target_scan_id)` behind the
  JWT-authenticated Edge wrapper
- Service aggregate scope: `get_explore_publication_health_summary`
- R2 event hint API: `ingest-r2-media-events`
- Device repair: `repair-scan-image`
- Database integration tests: `tests/explore_media_quarantine_security.sql` and
  `tests/scan_image_repair_security.sql`
- Edge tests: `reconcile-explore-media-health/worker_test.ts`,
  `ingest-r2-media-events/validation_test.ts`, and
  `_tests/exploreMediaQuarantineMigrationContract.test.ts`
- Incident history:
  [July 2026 account-scoped R2 image loss](../incidents/2026-07-account-scoped-r2-image-loss.md)

## Production rollout gate

The feature is not production-complete until all of the following are true:

- all four migrations are applied in order;
- all three new Edge Functions and the updated push function are deployed;
- the scheduled job can read `SUPABASE_URL` and an active current or legacy
  server key from the reviewed Vault slot;
- R2 read credentials are present for direct signed `HEAD`;
- if event acceleration is enabled, `R2_EVENT_WEBHOOK_SECRET` is configured at
  both trusted boundaries and the Cloudflare Queue consumer acknowledges only
  successful webhook batches;
- the integration and projection smoke matrix passes;
- lifecycle and credential audits pass; and
- dashboards and alerts consume reconciliation-run audit rows.
