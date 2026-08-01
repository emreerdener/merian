# Merian Supabase Backend

The Supabase backend for Merian. This directory contains the PostgreSQL database
migrations, Deno Edge Functions, and related configuration.

## Structure

```text
services/supabase/
  config.toml      # Supabase CLI and Edge Function configuration
  functions/       # Deno Edge Functions (e.g., identify-multimodal)
  migrations/      # PostgreSQL database migrations
  scripts/         # Helper scripts for backend tasks
  tests/           # pgTAP database authorization/behavior contracts
```

Do not add ad-hoc production probes, copied dashboard SQL, or credential-bearing
debug files to the service root. Reusable diagnostics belong in `scripts/` with
bounded transport, strict environment validation, tests, and documented output;
database assertions belong in disposable `tests/` fixtures.

## Migration Replay

Every migration must survive a complete fresh-catalog replay, not only an
incremental linked-project push. Schema-qualified PostgreSQL functions use
ordinary comma-separated invocation. In particular, write
`pg_catalog.SUBSTRING(value, pattern)`, not
`pg_catalog.SUBSTRING(value FROM pattern)`: the `FROM`, `FOR`, and `SIMILAR`
forms are unqualified SQL expressions. The migration execution contract scans
the complete migration fleet for this parser seam, but static checks are not
deployment evidence. The pinned CLI must still build the disposable database and
run every `tests/*.sql` catalog fixture before production `db push`.

Catalog fixtures preserve production signup behavior. An `auth.users` insert
fires `on_auth_user_created` and can create `public.users` synchronously; a
fixture that customizes the profile must use a constraint-valid
`ON CONFLICT (id) DO UPDATE` or update the created row, not follow with another
plain insert. Conflict handling does not bypass immediate username or identity
CHECKs. Keep fixture identities deterministic, catalog-wide unique, and inside
`BEGIN` / `ROLLBACK`.

A multi-phase fixture must not hide its PostgreSQL exception behind a pgTAP
`Bad plan`. Catch the outer exception, emit a bounded deterministic warning
containing phase, SQLSTATE, message, detail, and hint, and emit every planned
TAP result. Workflow run 1552 showed why: inline recovery completed 15
assertions before its video call raised, while the single-block identity-merge
fixture exposed only `planned 1, ran 0`. The identity fixture now follows this
diagnostic contract. The warning must never include credentials, raw media,
provider bodies, or nondeterministic private user data.

The next exact-SHA catalog run localized that identity failure to fixture setup:
a PL/pgSQL variable named `scan_id` was ambiguous beside `jobs.scan_id` in an
`INSERT ... SELECT`. Use a role-prefixed name such as `fixture_scan_id` for
synthetic identities and qualify real columns. The source contract rejects the
ambiguous declaration. Do not change production merge/recovery logic when the
phase proves it was never invoked.

The following 26-file catalog replay proved that rename: identity-merge recovery
passed, as did 23 other files. The two new atomic Explore/Community fixtures
then stopped at their first real service-role request lock because the
`SECURITY INVOKER` routines had `EXECUTE` but the hardened public-schema
defaults supplied no corresponding table privilege. Do not convert these
routines to `SECURITY DEFINER` or restore separate Data API mutations. Migration
`20260729044500_grant_atomic_explore_service_privileges.sql` grants only the
service-role operations used by the two transactions. The fixtures assert that
anon and authenticated retain no Community-table writes. Repeat all 27
rollback-only catalog files before any linked `db push`; source-contract success
alone is not relational authorization evidence.

## Edge Functions

Edge Functions are written in TypeScript and run on Deno. They handle logic like
AI inference (`identify-multimodal`), gamification telemetry, public user
profile updates, and Explore feed projections.

- **Configuration**: Every new Edge Function MUST have a `[functions.<name>]`
  entry in `config.toml`. Keep `verify_jwt = true` for routes called only with a
  Supabase user JWT (anonymous sessions also carry user JWTs). Use `false` only
  for deliberately public routes, service-key workers, webhooks, or a documented
  custom in-handler verification policy. A `false` route must enforce that
  replacement boundary in code. CI compares the complete configured-name set
  with the complete discoverable graph-name set; it does not maintain a
  hard-coded function count.
- **Dependencies**: `functions/deno.json` is the reviewed source manifest for
  exact dependency pins, and every deployable function has a generated local
  `deno.json` that points at the shared frozen `functions/dependencies.lock`.
  Runtime imports use those aliases instead of direct `esm.sh`, `deno.land`,
  npm, or JSR specifiers. The whole fleet uses one exact
  `@supabase/supabase-js@2.110.6` graph; `_shared/claimsAuth.ts` remains the
  opt-in authentication policy boundary for cached-JWKS claims verification, not
  a second SDK dependency. Generated configs explicitly retain Deno's one-day
  minimum dependency age; reviewed versions already present in the frozen lock
  install reproducibly, while future unlocked resolutions must age before
  adoption.

### JSON Ingress and Public Error Boundary

All production Edge JSON requests use the bounded primitives in
`functions/_shared/http.ts`; direct `req.json()` and `req.text()` calls are
prohibited. Most routes call `parseJsonBody(...)`. Signed webhooks retain exact
raw bytes through `readRequestBodyWithinLimit(...)`, and media adapters delegate
to `readBoundedJsonBody(...)`. The shared readers accept JSON media types,
validate decimal `Content-Length`, stream through the actual byte ceiling,
reject truncated or overlong bodies and invalid UTF-8, then parse the reviewed
JSON shape. Routes must pick the smallest reviewed class that fits their schema:

| Class      | Ceiling | Typical use                      |
| ---------- | ------: | -------------------------------- |
| `small`    |  16 KiB | IDs, actions, preference updates |
| `standard` |  64 KiB | ordinary structured API payloads |
| `bulk`     |   1 MiB | reviewed bounded batches         |

Media-bearing routes retain explicit larger budgets through
`_shared/mediaBudgets.ts`, whose JSON adapter delegates to the same streaming
reader. The canonical byte accumulator grows geometrically instead of retaining
one object per transport chunk, keeping memory proportional to accepted bytes.
Byte bounds do not replace field-level schema, count, or string-length
validation. Request compression is not part of the contract; clients send
uncompressed JSON so declared and actual sizes can be compared exactly.

`functions/_shared/edgeHandler.ts` assigns a server UUID to every request and
returns it in `X-Request-ID`. Authenticated handlers use `withEdgeHandler`;
public, webhook, and service-authenticated entrypoints register through
`serveEdge` so they cannot bypass the same response boundary. Expected thrown
failures use `PublicHttpError`, and explicit safe response contracts use the
validated `publicErrorResponse(...)` helper. Existing returned `4xx` application
contracts remain supported only for audited validation or caller state; the
boundary validates/adds a stable code and request ID. Arbitrary thrown objects
cannot select an HTTP status or leak a message. Unexpected exceptions become
`500 internal_error`; ordinary returned `5xx` responses keep their status but
receive a generic status-derived public envelope. Keep operational details,
provider responses, schema names, SQL text, and secrets out of public bodies.

Static coverage in `functions/_tests/jsonEndpointSecurityCoverage.test.ts`
prevents unbounded request readers and unwrapped custom entrypoints from
returning to deployable routes, and locks the shared raw-exception sanitization
boundary.

### Outbound Provider Boundary

Production HTTP calls use `functions/_shared/outbound.ts`.
`fetchWithDeadline(...)` combines caller cancellation with a hard timeout;
bounded text and JSON readers reject both declared and streamed oversized
responses before decoding or parsing. Global and injected fetch transports are
not called directly from production modules. Supabase SDK traffic is bounded at
the transport layer as well: privileged clients use a 30-second hard deadline,
authenticated user/claims lookups use 15 seconds, and the single shared Google
GenAI client uses the SDK's 90-second HTTP timeout.

`functions/_tests/outboundDeadlineCoverage.test.ts` enforces this architecture
and inventories the only remaining direct client transports: signed R2 calls in
the reviewed R2 SigV4, inference-media, and export-storage adapters. The legacy
`_shared/aws.ts` filename and `aws4fetch` dependency refer only to R2’s
S3-compatible signing protocol; no Amazon AWS service is used. Each such call
must receive `r2RequestWithDeadline(...)` or the export worker's bounded
`r2Request(...)`.

### Durable Account Deletion Boundary

Migration `20260725030308_durable_account_deletion.sql` establishes durable
deletion intake. Migration `20260725052337_enforce_account_storage_erasure.sql`
completes the private `pending → storage_pending → auth_pending → completed`
state machine. Migration `20260726041109_fence_storage_erasure_claims.sql` makes
that private state machine the sole authority for destructive storage claims.
`/safe-delete` persists intent before destructive work, then a five-minute
claim-fenced transaction writes the idempotent storage job, tombstones
relational data, and verifies that the public profile and original scan
ownership are gone. Auth Admin deletion is forbidden until R2 erasure is durably
verified.

Migration `20260725035737_repair_tombstone_profile_seed.sql` is an intentional
no-op compatibility bridge for production run 1461, where the attempted
public-only tombstone profile correctly failed the existing
`public.users.id → auth.users.id` foreign key. The immediately following
`20260725041308_ownerless_account_deletion_tombstones.sql` removes that invalid
sentinel design. Retained scans become ownerless tombstones and a validated
check permits `NULL user_id` only when `is_tombstoned = true`. Migration
`20260731154139_retain_scientific_coordinates_after_account_deletion.sql`
replaces the old clearing routine with the mandatory scientific-retention
contract: exact coordinates/elevation and every other scientific fact are left
unchanged while free-form intervention notes and account context are cleared.
`replay-scan-ingestion` treats that state as terminal and cannot dispatch
another AI request for a deleted account's scan.

The complete retained-versus-cleared field boundary, visibility rules, change
procedure, and verification requirements are canonicalized in
[`docs/backend-and-data/17-scientific-observation-retention.md`](../../docs/backend-and-data/17-scientific-observation-retention.md).

The same migration declares the production Auth/profile relationship with
`ON DELETE RESTRICT`, so an Auth Admin call cannot bypass verified relational
cleanup. It also excludes tombstones from the broad anonymous scan-read policy
and prevents the catalog-driven Ghost merge from trying to rewrite the public
profile's own Auth foreign key. Account deletion never creates a synthetic
`auth.users` or `public.users` principal.

The storage job owns five canonical prefixes: durable free and Pro uploads,
staging objects, avatars, and exports. A worker claims no more than four rows
per Edge invocation, deletes at most one 50-key keyset page from one prefix per
claim, persists its cursor, and moves through all prefixes. The invocation
ceiling keeps worst-case provider timeout waves inside the Edge wall-clock
budget. It then waits at least 25 hours—longer than generated export URL
lifetimes—and performs a second complete sweep. Only an empty delayed
verification pass marks storage complete and transactionally wakes the account
job. Listing and deletion have explicit deadlines and bounded response bodies;
claims, progress, and failures are token-fenced and retryable.

The SQL claim itself inner-joins the corresponding private job at
`storage_pending`, requires completed relational cleanup and incomplete storage,
and vetoes any target that still has a live public profile or owned scan. A
historical, orphaned, reset, or manually due `pending_storage_deletions` row is
inert. Worker code must not weaken or replace this database authorization
boundary.

Every retry repeats the idempotent relational cleanup before considering Auth
deletion. It also clears compatibility media URLs, structured captured-media
references, semantic location and its public label, device locale/time-zone
context, free-form notes, and custom tags from retained tombstones. Exact
coordinates, elevation, time, taxonomy, identification, environmental, quality,
and provenance fields are retained unchanged. An internal insert trigger
rejects recreation of `public.users`
while a deletion is active, so Auth metadata synchronization cannot restore a
profile before the terminal Auth step. New upload signing also fails closed with
`409 account_deletion_in_progress`.

`reconcile-account-deletions` is a scheduled service-role worker that resumes
due account and R2 work. It performs one bounded account pass, bounded storage
pages, and—when storage verification completes—a final account pass that can
remove Auth in the same invocation. Auth `404` / `user_not_found` is success,
transient failures receive database-calculated backoff, and expired workers
cannot finish a newer claim. Terminal jobs clear their direct user UUID. The
worker accepts no target UUID from HTTP.

Migration `20260727001630_monitor_account_deletion_health.sql` adds partial
indexes for active age, retry errors, and expired storage leases plus the
aggregate service-only `get_account_deletion_health()` RPC. It reports queue
depth, phase counts, oldest active/due ages, retry-error and expired-lease
counts, orphaned storage work, and booleans for the cron and its credentials. It
never returns a user UUID or raw error value. Credential readiness uses the same
Vault-first, NULL-only fallback as the reaper, so a blank Vault value cannot be
masked by a legacy app setting. The readiness boolean proves only that the
effective URL and key are nonblank. A post-deploy monitor smoke test validates
the independent health-RPC path; recent successful reaper cron requests validate
the separate URL and key-format-aware credential transport.

Migration `20260727013416_future_proof_server_key_boundaries.sql` gives every
installed database `pg_net` routine and persisted HTTP cron command the same
transport policy as Deno. Callers read the server key from the existing reviewed
Vault slot: an opaque `sb_secret_...` value is sent only as `apikey`, while a
legacy service-role JWT is sent in both `apikey` and Bearer Authorization. The
migration rewrites deployed catalog state transactionally and fails if any
active Bearer-only caller remains. Rotate the Vault value and project key
together; a present but blank Vault row still fails health checks rather than
falling through.

`.github/workflows/account-deletion-health-monitor.yml` queries that RPC every
five minutes, offset from the database reaper. It resolves a server API key
through the existing Supabase Management API token, so a missing Vault
configuration cannot also disable the alert. Default warning/critical thresholds
are 10/30 minutes for claimable work, 27/36 hours end to end, and 25/100 active
jobs. Missing reaper configuration, a disabled cron, orphaned storage work, or a
critical age/backlog breach is critical; retry errors or expired leases are
warnings. The workflow fails on warning by default and retains JSON and Markdown
evidence.

Coverage lives in `_tests/safeDelete.test.ts`,
`_tests/accountDeletionCoverage.test.ts`,
`_tests/accountDeletionMigrationContract.test.ts`, and
`tests/account_deletion_security.sql`, with R2 worker coverage in
`functions/safe-delete/storageWorker_test.ts` and monitor policy coverage in
`scripts/monitor_account_deletion_health_test.ts`.

### Owned Scan Image Recovery Boundary

Cloud media has two layers: Supabase Postgres stores owner/scan/post metadata
and public URLs, while Cloudflare R2 stores the referenced bytes. A surviving
URL does not imply that its object exists.

Migration `20260726041338_repair_owned_scan_image_references.sql` and
`repair-scan-image` restore a missing durable image from a surviving local owner
copy:

- shared authentication derives the user from the JWT and fails closed while
  account deletion is active;
- inspection requires an active scan owned by that user to reference the exact
  canonical source URL;
- R2 `HEAD` distinguishes healthy from missing media before any upload is
  promoted;
- a restored key must be a direct image child of the same user's staging prefix;
- promotion creates a new durable key under the user's current free/Pro prefix;
- one service-only transaction replaces the exact URL in scan arrays, recursive
  captured-media JSON, normalized media assets, and matching owner-post Explore
  snapshots; and
- a lost atomic-write response is reconciled from exact owner source and
  replacement references before cleanup.

The promoted replacement is deleted only after the database returned a rejection
and owner evidence proves the source still referenced and the replacement
unreferenced. Any lost response, unreadable owner state, concurrent repair, or
contradictory topology preserves the object and returns retryable
`scan_image_repair_persistence_unknown`; deleting it could break a repair that
committed.

The endpoint returns `healthy`, `missing`, or `not_referenced` for inspection
and `healthy` or `repaired` for a repair request. It is not a general media
replacement API and cannot select a target user from HTTP.

Coverage lives in `functions/repair-scan-image/worker_test.ts`,
`functions/repair-scan-image/validation_test.ts`,
`_tests/migrationMediaContract.test.ts`, `tests/scan_image_repair_security.sql`,
and the iOS `MerianNetworkClientTests`/`LocalImageLoaderTests` recovery suites.
Operational deployment and incident exit criteria are in
[`docs/backend-and-data/06-supabase-deployment-runbook.md`](../../docs/backend-and-data/06-supabase-deployment-runbook.md)
and the
[July 2026 incident report](../../docs/incidents/2026-07-account-scoped-r2-image-loss.md).

### Explore Media Health and Reversible Quarantine

Migrations `20260726144647`, `20260726144754`, `20260726174555`, and
`20260729120000` preserve published posts when primary media is unexpectedly
absent and keep author profile count/preview/grid and owner share-state
visibility aligned:

- `reconcile-explore-media-health` leases bounded active rows and performs
  signed direct R2-origin `HEAD` with required, bucket-scoped read-only
  `R2_READ_ACCESS_KEY_ID` / `R2_READ_SECRET_ACCESS_KEY`;
- one primary `404` is only suspected; a second at least five minutes later
  confirms missing;
- confirmed-missing items are omitted, while an all-missing post becomes system
  `quarantined` without changing author or moderation state;
- `get-explore-media-incidents` returns only the verified owner's active
  recovery queue in the canonical `{"data":[...]}` envelope; corrected iOS
  clients also accept the exact legacy direct array during rollout and reject
  all other successful-response shapes;
- optional `ingest-r2-media-events` batches make rows due under
  `R2_EVENT_WEBHOOK_SECRET` but never confirm state;
- owner repair atomically resets item health and restores ordinary projection;
- `get_scan_explore_share_state` preserves repairable owner publication identity
  but reports quarantined or moderated posts as not feed-visible; and
- one incident push/in-app row is replaced by an in-app-only restore row after
  full recovery.

`get_owned_explore_publication_summary(self_id)` gives only the authenticated
owner separate preserved-publication, canonical-visible, and recovery totals.
`get_explore_publication_health_summary()` is service-only and reports aggregate
affected-author/post/item scope without identities or object keys. The deploy
workflow calls the latter after function smoke tests.

The private continuity ledger preserves health across the existing DELETE+INSERT
snapshot refresh. The worker never deletes R2 objects, posts, likes, or
comments.

Coverage lives in `functions/reconcile-explore-media-health/worker_test.ts`,
`functions/ingest-r2-media-events/validation_test.ts`,
`_tests/exploreMediaQuarantineMigrationContract.test.ts`,
`tests/explore_media_quarantine_security.sql`, and
`tests/scan_image_repair_security.sql`.

The canonical product, architecture, API, security, monitoring, and deployment
contract is
[Explore Media Health and Quarantine](../../docs/backend-and-data/12-explore-media-health-and-quarantine.md).

### Community Identify Activity Boundary

Migration `20260731050009_add_community_identification_activity.sql` adds an
internal service-only projection for the Activity summary below Identify
Requests.
`20260731063804_index_community_identification_activity_actor_user_fk.sql` adds
the actor `user_id` reverse index required for bounded foreign-key enforcement
during account deletion and identity maintenance. The projection groups
adjacent suggestions on one request generation at an inclusive 60-minute
boundary, stores normalized actor IDs/counts without names, folds
submission-caused consensus metadata into the burst, and preserves standalone
consensus changes plus immutable resolution milestones. Backfill includes only
each request's current `requested_at` generation.

`get-community-identification-activity` requires a user JWT through
`withEdgeHandler` and calls `get_community_identification_activity(...)` with a
service-role client. The internal tables have RLS enabled; table and RPC access
is revoked from `PUBLIC`, `anon`, and `authenticated`. Every read reapplies
request ownership scope/group filters, withdrawal, unshare, moderation,
shadowban, blocking, tombstone, media quarantine, and usable-media rules.
Visible actor labels are resolved at read time. This feed never reads or
changes Explore notification unread state.

The route-local request/response, grouping, security, tests, and compatibility
deployment contract is in
[`functions/get-community-identification-activity/README.md`](functions/get-community-identification-activity/README.md).

### Darwin Core Export Boundary

Migration `20260728133835_disable_dwca_exports_for_launch.sql` is the current
production posture: a private, no-API-grant singleton defaults DwC-A off. A
BEFORE INSERT trigger rejects old bundles and unexpected service-role inserts;
the authenticated route uses
`request_dwca_export_job(user_id, scope, precision)` to hold a shared lock on
the release singleton and serialize the rolling 24-hour account window plus
insertion in one transaction. Reviewed state changes take the conflicting row
lock, so intake commits before the change or observes the new state. The
continuation cron is unscheduled, every pending/processing job becomes terminal
`feature_disabled`, download grants are revoked, and known final archives are
durably queued for deletion. `reconcile-dwca-archive-cleanup` and its
independent monitor remain active. Re-enable through a reviewed forward
migration only after the separate export release gate passes; changing the iOS
flag alone is never sufficient.

Migration `20260724230849_harden_dwca_export_jobs.sql` makes the database queue
authoritative. API roles cannot insert jobs directly, and the hardened worker
consumes only the webhook `job_id`. Deprecated canonical row hints exist only
for jobs created inside a private two-hour migration-before-bundle cohort; after
that deadline new webhook bodies contain `job_id` only and direct unclaimed
processing is rejected. Service-only definer RPCs atomically claim the row under
a private two-minute initial UUID lease, return immutable
user/scope/precision/key-version state, and fence renewal, staging, completion,
and failure to the current unexpired token. Long archive assembly renews the
same token before expiry. All routines have empty search paths, explicit
allowlist entries, and no public/authenticated execution.

Migration `20260725052339_bound_dwca_export_work.sql` makes generation resumable
and enforces canonical per-job limits of 5,000 CSV rows and an 8 MiB archive,
with hard schema ceilings of 20,000 rows and 16 MiB. Public callers can queue
only personal exports; global exports require a reviewed internal administrative
workflow.

Ordered migrations `20260725175312_bound_dwca_export_source_bytes.sql` and
`20260725180321_validate_dwca_export_source_bounds.sql` bound the source before
it reaches an Edge isolate. The first transaction installs new-write checks and
releases its `ALTER TABLE` lock; the second validates legacy rows before
activating reads. Scan rows may contain at most 24 exportable image URLs of
4,096 UTF-8 bytes each and 10 ecological interactions of 2,048 bytes each;
selected taxonomy fields are finite too. The service-only
`get_dwca_export_scan_batch(...)` RPC validates the active claim and canonical
cursor, then caps each keyset response at 100 scans and 256 KiB of serialized
source payload.

Migration
`20260727233841_add_public_web_explore_boundary_and_immutable_dwca_rows.sql`
upgrades the creation-time source snapshot to version 2. Forward migration
`20260728001723_repair_dwca_privacy_visibility_and_snapshot_work.sql` keeps the
same creation-statement MVCC boundary while streaming occurrence and multimedia
JSON DTOs one at a time into private `internal.export_job_source_rows`, records
their exact aggregate UTF-8 bytes in `internal.export_job_source_state`, and
rejects a source that exceeds four times the job archive budget (hard-capped at
64 MiB). Both CSV phases traverse those same immutable DTOs, so a later scan or
edit cannot mix taxonomy, media, or privacy revisions. Confirmed species
identity is authoritative; the original AI `species_id` remains audit history.
Exact GPS keys are retained only by an opted-in, snapshot-unprotected personal
job; global and non-precise personal DTOs omit them before persistence.

Snapshot construction first counts only UUIDs to the row lookahead, then uses a
parameterized lateral cursor to project, measure, and persist one DTO at a time.
It stops at the first per-row or aggregate violation and removes partial rows,
so the source ceiling also bounds JSON DTO memory and temporary-sort
amplification during rejection.

A full-member scope-aware eligibility fence covers deletion, tombstoning,
owner/live/ecology changes, global geoprivacy changes, taxonomy identity
changes, and protected-species coordinate-policy changes. Durable invalidation
triggers mark affected nonterminal jobs. A second monotonic trigger path fences
every affected unpurged snapshot without trusting a concurrently changing job
status, revokes any already-present grant, and enqueues the current archive. The
worker checks every member before assembly, before and after recipient lookup,
and before email; staging and completion repeat the check transactionally. A
mismatch becomes terminal `source_snapshot_changed`, revokes any application
capability, and durably enqueues the uploaded/staged object for deletion.
Processing jobs retain the opaque capability only in private work state; the
owner-visible application URL and completed status appear atomically after the
final fence. Failed snapshots purge immediately; completed snapshots remain only
until grant cleanup. If a revocation commits while Resend is already accepting
the request, completion still fails; the email can exist, but its capability is
revoked rather than publishing storage authority. Exact-SHA deployment evidence
is tracked in the
[release assurance record](../../docs/backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md).

When the release gate is enabled, `functions/export-dwca` executes one short
durable phase at a time—occurrence page, multimedia page, assembly, or
delivery—but a scheduled invocation now deadline-drains several phases
sequentially. An explicit insertion webhook attempts only its canonical job once
and returns, which bounds insert-burst fan-out. Empty-body cron wake-ups request
five-job oldest-due waves until a 40-second soft cutoff or a 40-step hard
ceiling. Successful work is requeued behind older due jobs; failed/contended
jobs are not retried in a hot loop. The two data phases use row-and-byte-aware
keyset reads over immutable job DTO rows and a narrow live privacy-revocation
fence. A fixed 512 KiB encoder appends one CSV row at a time, so page strings
and media rows are never expanded into an unbounded intermediate array. Each
page becomes a claim-token-fenced R2 CSV chunk and is committed to a durable
manifest with its cursor and cumulative budgets and unsigned CRC-32 in one
transaction. A late expired worker can neither overwrite the replacement
worker's chunk nor add it to the manifest.

Migration `20260726230837_scale_dwca_export_continuations.sql` adds an
outstanding-job partial index, the service-only aggregate
`get_dwca_export_queue_health()` RPC, and response-timeout headroom for the
minute pg_net wake-up. Dispatcher logs and the five-minute
`dwca-export-health-monitor.yml` automation alert on oldest due age, backlog
depth, and expired claims without exposing user IDs or private queue rows. The
monitor now also reads archive-cleanup health independently of the database
worker, detecting absent cron/Vault configuration and stuck deletion leases. An
unreadable aggregate never becomes a zero-count result. The monitor fails
closed, writes a bounded artifact with health payloads `null`, and emits only a
stable error code/component. Persistent `PGRST202` maps to
`catalog_contract_missing`; forward migration
`20260728144336_reload_postgrest_after_health_routines.sql` explicitly requests
a PostgREST schema reload after the routines are installed.

Assembly lazily reads manifest chunks into a streaming ZIP32 writer and bounded
R2 multipart upload; neither complete SQL results nor a complete CSV/ZIP is
buffered. Ordered chunk CRCs are composed algebraically during assembly, so the
final Edge invocation does not run a JavaScript checksum loop over every archive
byte. Emitted entry lengths must still exactly match the durable manifest, and
ZIP readers validate the composed CRC against extracted content. R2
create/complete XML and Resend replies are byte-capped; multipart completion
rejects an embedded S3 `<Error>` even under HTTP 200. Final archive keys also
include the claim UUID. Staged archives are reused after lease recovery, and
Resend delivery uses one job-scoped idempotency key.

Migration `20260728035237_harden_dwca_downloads_and_scan_finalization.sql`
replaces one-day direct R2 URLs with random application capabilities.
`download-dwca` applies a distributed IP-hash rate limit and rechecks the entire
immutable source fence on every click before issuing a no-store, read-only R2
signature valid for at most 30 seconds. Expired/revoked/terminal/legacy archives
enter a leased deletion outbox. `reconcile-dwca-archive-cleanup` deadline-drains
it every five minutes, retries provider failures, purges retained completed
snapshots after exact-current deletion, and emits aggregate
oldest-due/backlog/expired-lease health. Cleanup completion compares the leased
object key with the job's current attempt key, so an older cleanup generation
cannot revoke a replacement grant or purge active source state. Deterministic
Resend 4xx rejection is terminal; ambiguous or transient provider, storage, and
database failures remain retryable.

Every transition touching both the canonical job and source/grant/cleanup state
takes the job row `FOR UPDATE`, then a transaction-scoped per-job advisory lock,
then child rows. The migration retires the earlier source-state-first
invalidation triggers before installing the parent-first replacements; leaving
both active would invert delivery lock order. `TRUNCATE` is the deliberate
exception: because PostgreSQL has already taken `ACCESS EXCLUSIVE` on the source
table, its statement trigger performs only a monotonic source-state
invalidation. Download authorization fails closed immediately after commit; the
cleanup claimant then discovers the invalidated state and performs grant
revocation/archive enqueue under the canonical parent-first lock. Partial
indexes cover revoked grants and invalidated source states so this recovery path
does not degrade into an unbounded catalog scan.

Scan-ingestion completion is also enforced in the catalog.
`enforce_scan_ingestion_completion_fence` accepts a transition to `complete`
only when the atomic recovery/finalization transaction publishes the exact
owner-and-scan fence. Completed status and scan identity cannot be rewritten.
The sole owner-transition exception is the atomic ghost-profile merge, bound to
its exact `internal.ai_usage_reparenting`, source, and target transaction-local
markers; a generic service-key update cannot use the exception.

Canonical media completeness follows the app-facing media projection, not every
compatibility URL. `image_storage_urls` may retain five sampled inference frames
per video, but `refresh_scan_visual_media_assets` intentionally creates one
playback row and no standalone image rows for those frames. Forward migration
`20260729012153_fix_video_scan_canonical_finalization.sql` installs private
`internal.scan_canonical_media_projection_complete(scan_id)` and
`internal.scan_media_reference_is_video_inference_frame(scan_id, user_id, url)`
and rewires only the two exact contradictory finalizer blocks. Structured
`captured_media` wins when it contains a valid visual timeline; legacy rows use
standalone image count `images - (videos × 5)`, plus every playback video and
standalone audio. The second validator requires exact owner/job evidence, a
positive declared frame count, agreement between projected and
endpoint-normalized standalone-image counts, exact agreement between the
complete classified-frame set and the declared frame count, compatibility-array
membership, and exclusion from the canonical image set before a promoted image
capture can omit a ready display row. Native `identify-multimodal` jobs already
declare standalone `image_count`; compatibility jobs declare all inference
images, so the validator subtracts their separately validated frame count.
Unknown endpoint or malformed count contracts fail closed. The projection
validator also requires its image and video counts to equal the job's normalized
standalone-image and validated playback-video counts. Finalization still
requires exact scan/owner/kind/URL ready rows after refresh and retains all
storage-manifest checks, captured-promotion proof for every non-frame item,
completion fencing, and complete-last updates. Do not “fix” video scans by
hydrating inference frames as display images or by skipping image checks for all
mixed media.

Initial Explore publication has a matching catalog boundary. Forward migration
`20260729024157_atomic_explore_scan_publication.sql` installs
`public.publish_scan_to_explore_atomically(...)` as a service-role-only
`SECURITY INVOKER` RPC. After restoration, thumbnail generation, and audio
moderation, `share-scan-to-explore` calls that one final mutation. It locks and
revalidates the exact owner scan, checks every bounded media URL against the
scan's durable arrays, and upserts post metadata while replacing media,
hashtags, and resolved-community publication state in one transaction. An
omitted privacy default is resolved from the locked scan rather than a stale
Edge read. Any late constraint or trigger failure restores the prior complete
snapshot; the Edge route contains no separate table-mutation fallback.

Forward migration `20260729033000_atomic_community_identification_requests.sql`
applies the same boundary to Ask the Community. After taxonomy and moderation
preparation, `request-community-identification` makes one final RPC call that
commits the post/media snapshot and hidden `needs_id` request together.
Reopening withdrawn state clears stale publication and consensus generations
while retaining withdrawn vote history. A post trigger rechecks `needs_id` at
the actual `shared_at` update, closing the concurrent explicit-share race.

Forward migration `20260729044500_grant_atomic_explore_service_privileges.sql`
supplies the explicit table allowlist required by both `SECURITY INVOKER` RPCs
under the deny-by-default public-schema ACLs. It grants `service_role` only the
operation classes exercised by owner locking, snapshot replacement, request
creation, location projection, taxonomy validation, and withdrawn-request
consensus cleanup. It grants no browser-facing write, broad `ALL`, destructive
schema capability, or sequence access.

The export route's resource contract follows the current
[hosted Edge Function limits](https://supabase.com/docs/guides/functions/limits)
but does not consume the published CPU ceiling as a work budget. Keep
preparation bounded to one source page/chunk and assembly free of archive-sized
JavaScript loops. Validate maximum-shape exports against hosted function metrics
and 546/`CPU Time exceeded` logs before changing database or worker ceilings;
see `functions/export-dwca/README.md` and the deployment runbook for the
versioned limit note and release procedure.

Global attribution requires versioned `DWCA_PSEUDONYM_HMAC_KEY_V{n}` secrets.
Version 1 is required Base64 decoding to at least 32 random bytes, sourced from
GitHub `Production`, and has no fallback to a JWT/service credential or literal
salt. See the function README and deployment runbook before provisioning or
rotating a key.

Regression coverage lives in `functions/_tests/dwcaLaunchGateCoverage.test.ts`,
`functions/_tests/exportDwcaSecurityCoverage.test.ts`,
`functions/_tests/exportDwcaMigrationContract.test.ts`, the route-local export
tests, `tests/export_dwca_security.sql`, and
`tests/export_dwca_snapshot_security.sql`, plus
`tests/dwca_export_launch_gate_security.sql`,
`tests/dwca_export_queue_security.sql` and
`tests/dwca_download_and_scan_finalization_security.sql`. The latter migration
contract also keeps those disposable-catalog fixtures on the current
parent-first privacy trigger routines, requires explicit enum casts at
scan-recovery writes, and prevents reuse of a UUID after the fixture creates a
durable deletion tombstone.

### Public Web Explore Boundary

The public Next.js application does not execute native Explore RPCs with an
anonymous browser key and cannot provide a synthetic viewer ID. Migration
`20260727233841_add_public_web_explore_boundary_and_immutable_dwca_rows.sql`
adds two fixed-anonymous projections:

- `get_public_web_explore_posts(target_post_id, max_limit)`
- `get_public_web_explore_post_detail(target_post_id)`

Both routines have empty search paths and service-role caller checks and are
revoked from `PUBLIC`, `anon`, and `authenticated`. Only the server-rendered web
helper may invoke them with the validated current or legacy server key. The card
routine reuses `explore_projected_post_cards(NULL)`, forces engagement counts to
zero, and forces all viewer/ownership flags to false. Forward migration
`20260728001723_repair_dwca_privacy_visibility_and_snapshot_work.sql` makes the
detail routine independently inner-join that canonical card projection and adds
`get_public_web_explore_post_page(target_post_id)`, which returns card plus
detail from one statement/MVCC snapshot. The web helper uses the combined
routine. No routine widens grants on Explore, scan, user, or taxonomy source
relations.

`functions/_tests/publicWebExploreMigrationContract.test.ts`,
`functions/_tests/publicWebExploreCoverage.test.ts`,
`tests/public_web_explore_security.sql`, the web source-boundary test, and the
production deploy smoke prove that browser roles are denied and that the server
credential can obtain the tested visible projection. Database coverage also
proves direct detail and atomic page reads return no row after canonical
moderation exclusion. The complete production negative-state matrix and
exact-SHA evidence are tracked in the
[release assurance record](../../docs/backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md).

### Public Web Waitlist Boundary

Migration `20260724192124_harden_json_endpoints_and_waitlist.sql` revokes direct
API and service-role table access to `public.beta_waitlist_signups`, adds
new-row email/source/user-agent constraints, and creates the RLS-protected
`internal.beta_waitlist_rate_counters` table. The only write path is
`submit_beta_waitlist_signup(...)`, an empty-search-path, service-role-only
definer RPC with an explicit privileged-routine allowlist entry.

The Next.js route derives a daily, purpose-separated IP HMAC and calls
`claim_beta_waitlist_challenge_attempt(...)` before any Cloudflare request.
PostgreSQL permits at most 20 challenge checks per IP/10 minutes and 100/day.
The route validates its trusted-IP, HMAC, hostname, and Turnstile-secret
configuration before claiming a counter. Expired counter pruning is capped,
indexed, and uses `FOR UPDATE SKIP LOCKED` so concurrent public requests do not
wait on the same maintenance rows. After Turnstile succeeds, the insertion RPC
applies the tighter verified limits of 5 attempts per IP/10 minutes, 20 per
IP/day, and 2,000 new unique rows globally/day. Duplicate emails consume a
verified IP attempt but not global growth. Raw IPs and CAPTCHA tokens never
reach PostgreSQL.

Static migration coverage lives in
`functions/_tests/jsonEndpointSecurityMigrationContract.test.ts`; executable
ACL, constraint, uniqueness, and rate-limit coverage lives in
`tests/waitlist_security.sql`. Deploy the migration before enabling the secured
web form and follow the production rollout in the Supabase deployment runbook.

### Critical Scan Ingestion Reliability Boundary

All current scan-producing routes—`identify-multimodal`, `identify`,
`identify-describe`, and `audio-spec`—share one durable contract. They:

1. validate the authenticated owner and establish a valid Auth-backed public
   profile through service-only `ensure_scan_user_profile(uuid)`;
2. atomically establish `scan_ingestion_jobs` plus a sanitized
   `scan_ingestion_intents` row before provider dispatch;
3. commit the database quota reservation immediately before the provider call;
4. await moderation, required media promotion, primary species state,
   duplicate-safe scan insertion, and exact-owner read-back; and
5. synchronously invoke and await the database finalizer that proves every
   claimed key disposition and canonical ready media representation before it
   writes completion last.

Only analytics and optional enrichment may continue in Edge background work.
Provider success without an owned durable scan is a retryable failure, never an
HTTP success.

A fresh, provider-owning `identify-multimodal` invocation requires successful
completion-last finalization before its initial HTTP 200. If that finalizer
fails after owner-row commit, the invocation returns retryable 503. A later
same-UUID request may return `X-Merian-Idempotent-Replay: reconstructed` from
the exact owner row while the ledger remains retryable; that replay performs no
second provider call and canonical reconciliation still uses the completion-last
finalizer.

A compatibility producer has an additional narrower immediate fallback only
after its exact owner scan row was inserted and reread: if finalization or
bookkeeping then fails, it may return the already validated response while
leaving the ledger `failed_retryable` for same-UUID canonical reconciliation. No
producer returns success without the owner row, and required insertion never
continues in `EdgeRuntime.waitUntil`.

Foreground inline images carry no staged source keys. A historical filename hint
sent beside inline bytes is not an uploaded object and is excluded from
job/intent manifests, owner checks, promotion, capture-asset updates, and
finalization. Real offline image/audio/video sources must retain their exact
server-issued staging keys and upload sessions.

Historical inline completion recovery keeps its public service-only wrapper. Its
ledger, durable-media, and staged-asset checks live in three bounded `internal`
`SECURITY INVOKER` helpers with an empty search path and execution revoked from
all API roles, including `service_role`. They are not callable recovery APIs and
must not receive grants; the wrapper alone holds the required locks, rewrites
the exact ledgers, and invokes canonical finalization.

`functions/_shared/scanPersistence.ts` classifies every scan write using bounded
exact-owner read-back. A returned rejection plus proven owner-row absence may
authorize pre-insert rollback. A lost response, unreadable owner row,
success-without-visible-row anomaly, or contradictory topology is outcome
unknown: quota, lifecycle rows, and promoted objects are preserved for same-UUID
replay and reconciliation.

Scan signing registration is idempotent per authenticated owner, client scan
UUID, and deterministic object key. Requested media subsets compose with
existing unrequested rows for the same scan; their active staged/processing set
remains capped at six. Historical promoted rows remain audit evidence and do not
consume a later restore budget. A partial unique index serializes identical
active keys, while an owner-advisory-locked trigger enforces the staged-row cap
across concurrent disjoint-key requests. Completed ingestion rejects ordinary
signing. Only an exact `scan_share_restore` request with deterministic
scan/category identity may register repair media for a completed job. A fresh
unrestricted scan lookup must confirm an active authenticated-owner row or prove
the row absent for the later guarded reconstruction; any tombstoned or foreign
row fails closed. A failed-terminal job additionally requires exact
`replay_exhausted`, or exact `media_reconciliation_abandoned` with its matching
composite service proof: a post-result dead letter no earlier than the latest
charged normal/server-replay attempt, producer-generation-appropriate evidence,
no active reservation or invalid timestamp lineage, and no moderation-rejected
or moderation-pipeline-failed capture lifecycle row. Policy,
later-policy, and unproven abandonment remain closed. Do not remove failed
`superseded_staging_registration` rows: they are historical audit evidence used
by the narrow recovery contract.

The twelve joined incident migrations and the ten affected Edge Functions are
one ordered release unit. The last migration is
`20260729200000_harden_media_abandoned_scan_recovery_proof.sql`; both
media-abandonment files are separate migration-file transactions, even inside
one `supabase db push`. Before either can run, the production workflow
predeploys exact-SHA fail-closed `generate-upload-urls`, `check-scan-status`,
and `share-scan-to-explore` consumers. They require the final proof RPC only
when legacy repair is requested, so a missing or stale boundary returns
retryable `503` before signing or publication. Both migrations then land before
the structured Identify producer and final signer/status/share bundle
deployment. The final migration records its private legacy cutoff before that
producer, so an old producer in the gap remains fail-closed for automatic
recovery. Do not selectively deploy only the multimodal route, because older app
builds still use compatibility producers.
The production batch helper extracts
selected members of that unit from the graph plan, deploys them in compatibility
order before unrelated parallel batches, and stops on the first exhausted
ordered deployment. The normative joined state, recovery, security, deployment,
monitoring, and test contract is
[`docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md`](../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md).

### Identification Latency Contract

`identify-multimodal` remains the single production inference request for a
scan. Free uses `gemini-2.5-flash`; Pro uses `gemini-2.5-pro`. Latency changes
must not alter prompts, response schema, thinking budgets, media resolution,
output-token limits, or the one-`generateContent`-call invariant.

The latency-sensitive path uses cached ES256 JWKS verification through
`auth.getClaims`, injected only by the two latency-sensitive routes so unrelated
functions retain their existing `getUser` behavior; `begin_scan_ingestion` for
atomic pre-Gemini setup; and `hydrate_identification_dictionary` for post-Gemini
cache hydration. Moderation, required media promotion, primary external
cache-miss species resolution, duplicate-safe scan creation, and owner-scoped
read-back complete before HTTP success. One per-scan-locked finalization routine
verifies every claimed staging-key disposition and ready canonical
image/video/audio row before marking the ingestion ledger complete last. Every
current scan-producing route, including compatibility identify/audio/describe,
uses the same atomic setup before provider dispatch. The rolling-deployment
claim routine and owner-row recovery serialize on that same per-scan transaction
lock. Setup errors or malformed RPC output fail closed and refund unused quota;
there is no split-write fallback. Compatibility routes also use the shared
finalization routine. A failed finalization becomes durable retryable work; only
a compatibility invocation whose exact owner row already committed may still
return its validated owner-row response. The strict multimodal route returns
retryable 503 to that fresh invocation; a later same-UUID request may return a
marked reconstructed replay from the exact owner row while repair remains
retryable, with no second provider dispatch. Inference-only storage deletion
must receive R2 2xx or idempotent 404 before completion. Analytics, group tags,
and candidate enrichment remain optional Edge background tasks.
`/update-scan-context` applies or stages late owner weather/location fields
without rerunning inference. See the function-local READMEs and
`docs/system-architecture/04-ai-engineering.md` for the full contract.

Migration `20260728220000_persist_idempotent_scan_responses.sql` extends that
same finalization transaction with the validated Identify success envelope.
Every scan-producing route checks for a stored completion or an exact
reconstructible owner row before resolving staged media or reserving quota. A
retry after a lost HTTP response therefore returns `200` with
`X-Merian-Idempotent-Replay: stored|reconstructed` and never dispatches Gemini
again. Reconstruction covers both older completed rows from before response
persistence and exact durable owner rows whose canonical ledger is still
retryable. A duplicate that arrives before the original invocation creates that
row coalesces for at most 70 seconds, within the iOS 90-second request bound.

The response-aware finalization RPC is `SECURITY DEFINER` but deny-by-default:
the migration revokes every API role, grants only `service_role`, requires
`internal.require_service_role()` in the body, and registers the exact signature
in `internal.privileged_routine_grants`. The disposable catalog must reject any
grant/allowlist drift before production `db push`.

For older/interrupted missing rows, `_shared/scanRecovery.ts` delegates to one
atomic service-only non-media compatibility repair used only by single status
and Explore share requests. It shares the claim's advisory lock, writes the scan
and completed recovery ledger in one transaction, defers every active or unknown
state, and permits recovery from explicit `replay_exhausted`, or exact
`media_reconciliation_abandoned` with matching composite
dead-letter/quota/media-lifecycle proof. A reserved attempt, dead letter older
than the latest charged attempt, invalid terminal timestamps, moderation
rejection/pipeline failure, or unproven abandonment remains deferred.
Pre-rollout unstructured evidence must belong to the immutable exact
dead-letter-ID snapshot captured by the migration, precede the private database
cutoff, and satisfy a narrow first-normal-attempt rule. The ID snapshot prevents
a DDL-blocked producer insert from gaining legacy authority through an earlier
transaction-start timestamp. Post-rollout evidence binds the exact quota IDs and
completed safety evaluation. A bounded service-only proof RPC supplies the same
decision to restore signing, and both RPC signatures are recorded in the
privileged-routine grant ledger. Every exact failed/committed normal and replay
reservation remains exempt from ordinary quota pruning while the terminal job
is unresolved; refunded and unrelated terminal states retain normal retention.
The pruner conditionally casts legacy text scan IDs only after an in-expression
UUID-shape guard, so malformed historical rows cannot abort hourly cleanup.
Media remains accepted only through separate owner-scoped staging keys.

Owner deletion takes the same generation lock first. `/delete-scan` commits an
`internal.scan_deletion_tombstones` row before touching R2, terminal-marks
noncomplete ingestion, then removes the canonical row only after every storage
delete is confirmed. The private tombstone remains after completion, and claim,
scan mutation, finalization, replay, and recovery all reject that UUID. The
client's persistent `PendingCloudDeletionTask` can safely resume a lost response
without allowing cross-device resurrection. `reconcile-scan-deletions` is the
independent server completion path: every five minutes it deadline-drains
oldest-due UUID leases, reloads fenced media, and compare-before-releases
failures with bounded backoff. Successful completion clears the owner UUID from
the permanent fence. `scan-media-health` exposes only aggregate
oldest-pending/backlog/expired-lease state to its independent GitHub schedule,
so missing cron/Vault dispatch cannot silently strand erasure.

The daily `auto-purge-nonbio` route is only a retention intake. Its service-only
`request_nonbiological_scan_retention_deletions(integer)` RPC selects bounded
oldest-first candidates, acquires the canonical scan-generation locks in UUID
order, and rechecks age, `is_biological_subject = false`,
`is_tombstoned = false`, non-null/non-reserved ownership, and deletion-fence
absence under each row lock. It writes the same permanent deletion tombstone
used by owner deletion and performs no R2 or direct scan-row deletion. The
independent reaper reloads canonical media after fencing, preventing a delayed
finalizer from appending an object between URL capture and row removal.

Storage deletion is also owner-bound. A URL is eligible only when it is an exact
HTTPS `media.merian.app` key with the flat shape
`public_uploads/{free|pro}/{canonical-owner-uuid}/{safe-filename}`. The helper
rejects foreign owners, nested/dot paths, queries, fragments, credentials, and
other prefixes before signing and reports only aggregate rejection counts.
Authenticated API roles cannot insert/delete scans or update ownership, media,
privacy, ingestion, or model-result columns. Current iOS writes custom tags and
identification review through owner-derived fixed-search-path RPCs. A temporary
five-column UPDATE grant is retained solely for already-installed clients and
must be removed after the minimum supported release uses those RPCs. Database
checks bound the URL arrays, tags, and override text before service-role work.
`20260728151927_declare_scan_data_api_privileges.sql` removes historical table
and column ACL drift, grants RLS-governed scan reads to `anon` and
`authenticated`, and grants only canonical `SELECT`/`INSERT`/`UPDATE`/`DELETE`
to `service_role`. This explicit declaration is required even though
`service_role` bypasses RLS; no launch path may depend on Supabase's changing
automatic-exposure defaults.

### Incremental Species-Count Boundary

Migration `20260724222838_optimize_species_count_trigger.sql` replaces the
historical per-row full-history recount on `public.scans`. It creates the
private `internal.user_species_scan_counts` ledger keyed by
`(user_id, species_id)`, backfills it once while scan writes are locked, repairs
the public projection, and installs separate statement-level insert, delete,
update, and truncate triggers. The file opens an explicit transaction before
`LOCK TABLE` and commits only after the final trigger is installed, as required
by PostgreSQL for a table lock that spans the complete cutover. This is an
immutable historical migration contract, not a pattern for new files; new
migrations leave transaction and history ownership to the CLI.

Insert/delete transition tables aggregate each pair once. The update trigger
combines complete OLD and NEW transition sets and drops zero-net pairs, so
ordinary weather, media, moderation, and ingestion-state updates do not touch
species-count state. Owner or species changes debit the old pair and credit the
new pair in the same transaction. The private helper locks affected user rows in
UUID order and changes `users.total_species_discovered` only when a ledger row
is created or removed. A live-owner underflow fails the scan statement instead
of silently accepting drift. Ownerless tombstones, the legacy all-zero owner,
and null species remain excluded, preserving the previous metric definition.

The ledger and all helper functions deny direct execution or table access to
`PUBLIC`, `anon`, `authenticated`, and `service_role`; authenticated scan writes
reach them only through PostgreSQL triggers. Static coverage lives in
`functions/_tests/speciesCountTriggerMigrationContract.test.ts`. Executable
catalog and behavior coverage lives in
`tests/species_count_trigger_security.sql` and is included in
`make test-supabase-privileged-routines`.

### Public Species Contract

`species-dictionary` is an intentionally public, read-only Edge Function with
`verify_jwt = false`. Detail requests do not read viewer identity and return
only the versioned species-level projection built by
`functions/_shared/publicSpeciesProjection.ts`. Do not add scan, user, Explore
post, location, field-note, comment, local-media, AI-reasoning, or
preferred-name fields to that response.

The iOS Species Dictionary and the server-rendered
`https://naturebook.earth/species/{speciesId}/{slug}` route share this contract.
The web server invokes the function with `species_id`; the readable slug is
derived from response names and is never sent to Supabase or used for lookup.
UUID-only and stale-slug browser routes redirect to the current canonical path
after a successful response. The web server does not query broad tables. Before
rendering or choosing social metadata imagery, the web mapper runs
`publicWebReferenceImageAttributionIssues(...)` and omits incomplete rights
rows. Similar-species thumbnails stay hidden until their payload carries
equivalent license and attribution fields.

Contract coverage lives in `functions/_shared/publicSpeciesProjection_test.ts`
and `apps/web/lib/species.test.ts`. The former locks privacy, schema, content
quality, and attribution auditing; the latter locks UUID validation, public
mapping, slug generation and compatibility redirects, 404/transient error
semantics, metadata helpers, native URLs, and the exact AASA path list.

### Internal Admin Boundary

Migration `20260719161112_add_internal_admin_foundation.sql` owns the private
membership/session/audit/review/feedback/pricing schema, service-owned user
report intake, reversible Explore moderation, and append-only AI usage ledger.
The browser admin has no service-role key and reaches this state only through
the explicitly granted authenticated RPCs.

`functions/report-user/` is the authenticated visible-profile intake endpoint;
`functions/_shared/aiUsage.ts` normalizes Gemini usage for durable or bounded
best-effort ledger writes. Database authorization and behavior coverage lives in
`tests/admin_foundation_security.sql` and `tests/admin_review_ai.sql`.

See
[`docs/backend-and-data/10-internal-admin.md`](../../docs/backend-and-data/10-internal-admin.md)
and the
[`docs/backend-and-data/11-internal-admin-operations.md`](../../docs/backend-and-data/11-internal-admin-operations.md)
runbook before changing grants, roles, sessions, review transitions, visibility,
pricing, or auditing.

### Privileged Routine Execution Boundary

Migration `20260723144640_harden_privileged_routine_execution.sql` makes
public-schema `SECURITY DEFINER` functions deny-by-default even though `public`
remains a Data API schema. It revokes PostgreSQL's default function execution
from `PUBLIC` and the Supabase API roles for the repository migration owner,
removes historical execution from every public definer function, fixes every
definer to `search_path = ''`, and then reapplies only the reviewed entries in
`internal.privileged_routine_grants`.

The resulting contract is:

- `PUBLIC` and `anon` execute no public-schema definer function.
- `authenticated` receives only caller-bound admin and ghost-upgrade RPCs. Each
  authorized body must derive the caller from `auth.uid()`/`auth.jwt()` or call
  `internal.require_admin(...)`.
- `service_role` receives only an Edge worker or documented operator RPC. Every
  such body calls `internal.require_service_role()`; SQL-language functions are
  wrapped as PL/pgSQL so this check cannot be omitted.
- Trigger and implementation helpers receive no API-role grant.
- An application definer routine must be owned by `postgres`, use an empty fixed
  search path, and fully qualify application objects, types, and extension
  operators.

Never grant a definer function ad hoc. Add its exact identity signature and
purpose to the migration-owned allowlist, document its caller boundary, and run
both the static and catalog tests. If a public definer appears under another
owner (including a Supabase-managed owner), the audit fails; resolve ownership
or the creator's default privileges explicitly rather than weakening the test.

Migration `20260727010340_fix_service_role_authorization_guard.sql` keeps that
in-function boundary compatible with both server-key generations. Legacy
service-role JWTs are recognized through `auth.role()`; opaque `sb_secret_...`
keys are recognized through PostgREST's protected standard `role` setting.
Direct `postgres`/`service_role` sessions remain available for migrations and
incident repair. This migration changes the guard body only; it does not broaden
the exact RPC allowlist. Do not replace the standard-role check with a
caller-controlled header or custom GUC.

Catalog validation is semantic, not just migration-syntax validation.
`supabase db push --local` can succeed while SQL inside a PL/pgSQL routine still
contains an unresolved catalog function or overload. The pgTAP catalog gate runs
`plpgsql_check` and reports the exact routine signature, source line, SQLSTATE,
statement, query, detail, and hint. Treat that first PostgreSQL exception as the
root cause; pg_prove's later `Dubious`, `Bad plan`, and `planned 1 but ran 0`
messages are consequences of the aborted test.

Schema qualification does not compensate for a misspelled catalog routine or an
incorrect argument type. Verify the exact `pg_proc` identity and explicitly cast
overloaded arguments. The quota reservation lock, for example, deliberately uses
`pg_catalog.HASHTEXTEXTENDED(..., 0::BIGINT)`, and the migration contract locks
that signature.

PostgreSQL conditional expressions are not ordinary catalog routines and must
not be schema-qualified. In particular, do not write `pg_catalog.COALESCE(...)`.
When an `INSERT ... ON CONFLICT DO NOTHING RETURNING TRUE INTO event_inserted`
statement returns no row, PL/pgSQL leaves `event_inserted` null; branch on
`event_inserted IS NOT TRUE` so both null and false take the durable-duplicate
path. The catalog gate validates this routine body after migration replay.

```bash
make validate-supabase-migrations
make test-supabase-privileged-routines

# Read-only hosted-database verification. The URL is never printed.
MERIAN_DATABASE_URL='postgresql://...' \
  make audit-supabase-privileged-routines
```

Production CI runs the same catalog audit in report mode before `db push` and in
enforcement mode immediately afterward. See the deployment runbook for the
incident and forward-repair procedure.

### Authoritative AI Entitlement and Quota Boundary

Migration `20260723160229_enforce_server_ai_quotas.sql` makes paid-model access
a database decision. Public Edge routes use `_shared/aiQuota.ts` to call
`reserve_ai_quota(user, operation, request_id, ip_hash)` before provider work.
That single transaction locks and resolves the durable entitlement and selected
policy, chooses an allowlisted model, applies a daily safety ceiling plus shared
per-user/IP rate limits, and records an idempotent reservation. The row locks
give concurrent tier/policy changes and reservations a single database order;
future-dated profiles never extend the seven-day trial. The Edge route commits
immediately before provider dispatch. Only a proven pre-provider no-op, such as
a moderation cache hit or rejected empty multimodal request, may refund. Every
attempt carries a ten-minute database lease and a fresh fencing token; expired
pre-provider reservations are refunded automatically, and a late settlement from
an older attempt cannot mutate a retry. A provider failure transitions
`committed` to `failed`: counters remain charged, but the same request key can
make a newly metered retry.

Terminal quota reservations ordinarily prune after 30 days.
`20260729200000_harden_media_abandoned_scan_recovery_proof.sql` retains only
exact failed and committed normal/replay scan-identification reservations while
the matching job remains unresolved
`failed_terminal / media_reconciliation_abandoned`. These rows preserve the
complete chronological recovery/security authority; the latest row may support
or veto recovery depending on matching dead-letter lineage. Recovery or
explicit operator resolution returns them to ordinary pruning. Refunded
attempts are not retained by this exception.

The internal policy matrix distinguishes `free`, `pro_trial`, and `pro_paid`.
Current UTC-day safety ceilings are:

| Operation bucket                                   |   Free | Pro trial | Paid Pro |
| -------------------------------------------------- | -----: | --------: | -------: |
| Primary image/description/audio scans              |      1 |        50 |      500 |
| Cache-miss overview/lookalike/group-tag enrichment |      4 |       100 |      500 |
| Explore/Community audio moderation                 |      3 |        25 |      100 |
| Insight/Explore model chat work                    | denied |        60 |      120 |

These are abuse and cost ceilings, not client entitlements. Change them only in
a reviewed forward migration, increment the policy version, and keep every
operation in `AIQuotaOperation`, `aiQuotaMigrationContract.test.ts`,
`aiQuotaCoverage.test.ts`, and `tests/ai_quota_security.sql` aligned.

#### Atomic Field Chat Admission

Migration `20260729163616_reserve_field_chat_sends_atomically.sql` must apply
before the matching `insight-chat` and `explore-post-chat` functions. Its
service-only `reserve_field_chat_send(...)` RPC takes the per-user advisory lock
before the per-conversation lock, validates the exact subject and owner, and
atomically performs same-key replay/conflict handling, cross-table UTC-day
accounting, two-row conversation-cap admission, unanswered-request fencing, and
the user-row insert. Direct `anon` and `authenticated` chat-table privileges are
revoked, so clients cannot bypass this transaction with Data API writes.

If a worker terminates after quota commit but before assistant persistence,
`recover_stale_field_chat_quota(...)` fails closed for ten minutes. It can then
transition only the exact committed Field Chat reservation after proving its
subject-bound user row exists and UUID-bound assistant is absent. The route
re-reads the pair and makes any retry newly metered. Validate runtime behavior
with `tests/field_chat_reservation_security.sql`; source-contract success alone
does not prove PostgreSQL execution.

Migration `20260730180000_bind_field_chat_rows_to_subjects.sql` is a
compatibility-safe structural follow-up. It removes only impossible
cross-conversation private rows, binds every retained Insight conversation to
its exact scan owner, then makes message and copied-feedback identity a
validated deferred composite foreign key for both chat families. Deferred
checks preserve the existing all-in-one anonymous-account merge while requiring
every conversation, scan/post, user, message, and feedback identity to agree at
commit. Conversation-optional Insight feature feedback is independently bound
to its exact scan owner. The migration also revokes the legacy authenticated
Data API privileges from Insight answer/feature feedback and retains exact RLS
joins as defense in depth.

Executable security fixtures insert test profiles directly instead of running
the Auth signup trigger. Any such owner-only fixture must first insert the
matching transactional `auth.users` row, then insert `public.users` with a
deterministic, unique `public_username` accepted by
`public.is_valid_public_username(...)`, a non-empty `public_author_name`, and a
CHECK-valid `public_identity_source`; all three columns are `NOT NULL`.
Usernames are currently 3–24 lowercase characters, must start with a letter and
end with an alphanumeric character, cannot contain `__`, and cannot be reserved.
Fix a stale fixture rather than weakening the Auth FK or production identity
constraints.

`users.entitlement_version` advances whenever the tier or timed expiry changes.
`_shared/entitlement.ts` performs durable reads for non-provider checks; it
never caches authorization in an Edge isolate. A query error or missing user row
fails closed with `503 ai_entitlement_unavailable`. Authenticated clients cannot
insert/delete `public.users` rows or update tier, expiry, or entitlement
version; only the two reviewed preference columns remain directly writable.

IP buckets store a daily-rotating, domain-separated HMAC, never a raw address.
`AI_QUOTA_IP_HASH_SECRET` is an optional dedicated override. When it is absent,
Edge code uses the canonically resolved current or legacy server key; an
explicit override shorter than 32 characters still fails closed. The deploy
workflow validates and synchronizes the override only when configured.

### RevenueCat delivery boundary

`revenuecat-webhook` requires a constant-time Authorization credential and
RevenueCat's timestamped raw-body HMAC. After verification it fetches
authoritative CustomerInfo with `REVENUECAT_SECRET_API_KEY`; webhook event types
alone never grant or revoke access. All three credentials are required GitHub
`Production` secrets synchronized to Supabase by the deploy workflow.

Migration `20260723201500_secure_revenuecat_webhook_delivery.sql` records
RevenueCat event IDs under a unique constraint and keeps a per-user ordering
watermark. Migration `20260725052338_reconcile_revenuecat_subscribers.sql` makes
authoritative CustomerInfo snapshot time the primary monotonic version; provider
event time and event ID break only exact snapshot ties. The event ledger has
child subject rows so `TRANSFER` can reconcile and commit both its source and
destination under one event ID; all affected user rows are locked in
deterministic UUID order. Duplicate or delayed events cannot overwrite newer
access. Reuse of an event ID with a different payload digest is rejected. The
service-only `get_revenuecat_webhook_event_result(...)` lookup prevents durable
duplicates from causing another provider API call. Both RPCs use an empty search
path and caller check; the internal ledger tables have RLS enabled and no direct
API-role grants. Billing does not create missing users and rejects an identity
set that ambiguously maps to multiple live profiles.

Recurring and grace-period entitlement expirations are persisted in
`users.subscription_expires_at`; `NULL` is reserved for an explicitly
non-expiring lifetime entitlement. The expiry worker can therefore remove access
even if RevenueCat never delivers the final expiration webhook.

The service-only `reconcile-revenuecat-subscribers` route is invoked every 15
minutes. A durable queue leases six-record `FOR UPDATE SKIP LOCKED` waves and
keeps draining until empty or the 60-second start-work cutoff. Provider
concurrency remains three, and only newer CustomerInfo snapshots apply under the
claim token. A claimed-row partial index supports expired-lease cleanup. Pro
users reconcile every six hours and free users every 24 hours; webhook
processing also advances the due time for affected subjects. This authoritative
sweep repairs missed deliveries without granting a historical seven-day pass
after a refund.

The service-only `get_revenuecat_reconciliation_health()` RPC reports due and
expired-claim counts plus oldest due age. A separate pinned-action GitHub
monitor checks it every 15 minutes, fails on a 30-minute warning by default, and
marks 60 minutes critical. It uses the existing Production
`SUPABASE_ACCESS_TOKEN` to resolve the service-role key; no additional monitor
secret is required.

Keep `revenueCatWebhookCoverage.test.ts`,
`revenueCatWebhookMigrationContract.test.ts`, the route's focused unit tests,
and `tests/revenuecat_webhook_security.sql` in the deploy gate. See
[`functions/revenuecat-webhook/README.md`](./functions/revenuecat-webhook/README.md)
and
[`functions/reconcile-revenuecat-subscribers/README.md`](./functions/reconcile-revenuecat-subscribers/README.md)
for the protocol, repair cadence, rollout, and rotation contracts.

### Explore Author Maintenance

Explore read functions are projection-only. They must not refresh public author
identity or repair post ownership while serving feeds, profiles, comments,
notifications, maps, mentions, hashtags, species pages, or post detail. Public
author maintenance belongs on the write paths that can make the projection
observable: Explore sharing, Explore and Field trip comment creation, Community
requests, auth metadata triggers, and ghost-profile merge.

Migration `20260720042641_optimize_explore_author_maintenance.sql` keeps
`refresh_public_author_identity(uuid)` idempotent, hardens both maintenance
functions with `SECURITY DEFINER SET search_path = ''`, and grants execution
only to `service_role`. The refresh returns without writing when the safe public
projection already matches, preventing repeated row-version churn. Never grant
either maintenance RPC to `PUBLIC`, `anon`, or `authenticated`, and never move
them back into a read endpoint to repair data opportunistically. This follows
Supabase's
[database-function security guidance](https://supabase.com/docs/guides/database/functions)
for fixed search paths and explicit execute privileges.

### Internal Service Credential Boundary

`functions/_shared/serviceRoleAuth.ts` protects every internal worker and status
route that uses the common service-key policy. The static coverage catalog
currently inventories twenty such boundaries, including taxonomy maintenance,
media and account reconciliation, RevenueCat reconciliation, replay, push
delivery, and DwC-A continuation work. Authorization is a local exact comparison
against the explicit `SUPABASE_SERVER_API_KEY`, the deploy-synchronized
non-reserved Edge fallback `MERIAN_SUPABASE_SERVER_API_KEY`, a named
`sb_secret_...` value supplied by the platform in the JSON
`SUPABASE_SECRET_KEYS` dictionary, the singular `SUPABASE_SECRET_KEY`
local/manual fallback, or the migration-only `SUPABASE_SERVICE_ROLE_KEY` legacy
fallback. Successful empty reads, RLS behavior, JWT shape, and other capability
probes are never evidence of authority. A raw or JSON-string value in the plural
variable is malformed and never contributes a candidate. Every source is
classified independently for inbound authorization: a malformed source cannot
veto an exact request key from another valid source, but an unmatched request
still fails as invalid configuration. Do not compensate with a transport
workaround.

Configuration is classified before comparison: a current key must have the
platform `sb_secret_` prefix and a URL-safe opaque suffix of at least 20
characters, while a legacy fallback must be an HS256 JWT whose role is exactly
`service_role` and whose 43-character base64url signature is complete. A
publishable key, anon/user JWT, truncated placeholder, or malformed value in a
privileged variable fails closed. The server-only web client applies the same
classification.

Legacy service-role JWTs may use Bearer transport; named non-JWT secret keys
must use `apikey` only. Mixed Authorization/apikey values are rejected. After
authorization, the route creates its database client and internal calls with the
server-managed environment key rather than reflecting the caller's credential.
Public and webhook routes that need admin access resolve that same environment
key through `serviceRoleClient.ts`; production modules may not construct a
legacy-key admin client directly. The shared fetch boundary supports PostgREST,
Storage, Functions, and Auth Admin while keeping opaque keys out of Bearer
transport. The deploy smoke, Community Taxonomy import, and scan-media health
workflows use `scripts/resolve_project_api_keys.ts` to request revealed values
from the Management API, prefer the current `default` secret key, fall back only
to the exact legacy `service_role` key, and use the same shared transport rule.
The shared resolver makes at most five attempts for transport failures, HTTP
408/425/429, and HTTP 5xx with capped jitter/`Retry-After`; credentials, other
caller errors, malformed responses, and invalid or ambiguous key lists fail
immediately. Retry diagnostics expose no key, token, response body, or raw
transport message.

Before Function deployment, the production workflow masks and copies that exact
value to `MERIAN_SUPABASE_SERVER_API_KEY`; Supabase reserves built-in
`SUPABASE_*` names, so the fallback must not use one. The workflow then verifies
the stored secret's SHA-256 digest against the exact selected key and stops
before rollout on a missing, malformed, duplicate, or mismatched entry without
printing the key or digest. Positive deployment smoke requests make six bounded
propagation attempts. Before credentialed smoke, the workflow derives every
entrypoint from the reviewed dependency graph and sends an unbilled `OPTIONS`
probe to each route. Because the platform checks `verify_jwt` before executing
code, preflight includes the validated legacy anon JWT whenever any configured
route retains `verify_jwt = true`; a publishable key is never sent as Bearer.
The rollout fails closed if that execution credential is unavailable. Every
response must carry fixed `X-Merian-Handler: 1` execution evidence. Missing
routes retry together under one bounded propagation window and fail the rollout
without printing bodies or request identifiers. Before deactivating the legacy
anon key, either migrate every remaining gateway-verified route to the reviewed
in-handler auth boundary or provide a replacement short-lived user smoke
identity. Final Function failures report only HTTP status plus handler-marker
presence; Data API failures instead identify the PostgREST/RPC diagnostic path
without expecting a Function header. The production gate additionally calls
all eleven customer-critical scan, signing, share-state, Explore, Field Chat,
Community, and deletion routes without Authorization until each returns
fail-closed `401` with the fixed handler marker:
`generate-upload-urls`, `identify-multimodal`, `check-scan-status`,
`share-scan-to-explore`, `get-scan-explore-share-state`,
`get-explore-composer-media`, `get-explore-media-incidents`, `insight-chat`,
`explore-post-chat`, `request-community-identification`, and `delete-scan`. A
platform `404` therefore cannot be mistaken for an application-level missing
scan or a successful rollout. The RevenueCat reconciliation-health monitor uses
that resolver and transport too. Do not replace the resolver with the CLI
API-key listing: its hidden secret-key representation cannot pass the exact
request boundary. Migration
`20260726212549_harden_service_role_request_authentication.sql` separately
revokes all `taxonomy_import_runs` table access from `PUBLIC`, `anon`, and
`authenticated`, then grants `service_role` only `SELECT`, `INSERT`, and
`UPDATE`.

No custom server credential header is supported. Diagnostics never expose a key
prefix, suffix, length, partial fingerprint, accepted candidate, or failed
internal response body. The complete environment/header matrix and production
exit gate are in the
[server credential and database release safety
contract](../../docs/backend-and-data/13-server-credentials-and-database-release-safety.md).

User-scoped clients use the separate `functions/_shared/publishableKey.ts`
resolver. Hosted functions strictly parse the JSON `SUPABASE_PUBLISHABLE_KEYS`
dictionary and prefer its named `default` key; local and migration-overlap
environments may fall back to a complete legacy HS256 `SUPABASE_ANON_KEY`.
Authentication, claims, ghost-profile merge, and optional species-stats
authentication may not read either variable directly. Provider diagnostics are
logged server-side while public 401 bodies remain generic.

Migrations `20260727190637_secure_explore_comment_reactions_and_defaults.sql`
and `20260727190804_index_user_foreign_keys_for_identity_lifecycle.sql` close
the remaining exposed-table RLS gap, revoke direct reaction access from
unprivileged API roles, clear both global and public-schema default
table/sequence grants (including Postgres 17 `MAINTAIN`), and create any missing
leading indexes for owned single-column user foreign keys. The index migration
refuses to build against a relation larger than 32 MiB while holding a blocking
migration lock and never recursively builds a missing index on a partitioned
parent; use the deployment runbook's supervised concurrent procedure first. The
static migration contract and `tests/public_schema_security.sql` enforce the
same effective-schema invariants.

### Ghost Account Upgrade Boundary

Direct Apple/Google identity linking remains the primary anonymous upgrade path.
Only the exact Auth error `identity_already_exists` may enter
`functions/merge-ghost-profile/`. The anonymous source issues a hashed,
provider-subject-bound 30-day handoff; the permanent destination consumes it in
one serialized database transaction. The caller cannot nominate either user
UUID.

The foreground endpoint deletes the obsolete anonymous Auth row after commit.
`functions/reconcile-ghost-profile-merges/` is the five-minute, service-only
recovery worker for interrupted cleanup. It has `verify_jwt = false` solely for
`pg_net` compatibility and uses the shared exact environment-backed request
policy, accepting an opaque key only in `apikey`. See the two function READMEs
and the deployment runbook before changing this protocol.
`tests/ghost_profile_merge_security.sql` runs in the disposable catalog through
`make test-supabase-privileged-routines` and protects the exact profile/Auth-FK
exclusion used by generic ownership reparenting.

### Public Species-Stats Resource Boundary

Migration `20260724170709_harden_species_observation_stats.sql` bounds the
intentionally public `/species-observation-stats` route. The request must bind a
dictionary UUID to its canonical name. Atomic database counters enforce request
user/IP limits and colder user/IP/global provider-work limits. Exact taxon
misses and provider failures receive status-aware negative cache TTLs. Provider
failures with no useful buckets become `unavailable`, never empty `partial`
results.

Cold population uses a 90-second database row lease. The final cache write
compares the lease UUID in the same transaction, so another Edge isolate cannot
stampede the same species and a delayed generation cannot overwrite newer work.
The four public-schema wrappers preflight IP use, authorize canonical species,
claim work, and finalize cache state. Each is `SECURITY DEFINER`, uses an empty
search path, calls `internal.require_service_role()`, and is executable only by
`service_role`; their tables have no direct API-role grants. Provider fetches
also have explicit per-call/operation deadlines and streaming response caps. See
the function README and deployment runbook before changing these limits.

An unavailable refresh cannot erase positive data still inside the 37-day
retention ceiling. Fenced finalization preserves the payload and original
`fetched_at`, marks it `stale`, records the current row-level cache error, and
sets a five-minute retry backoff. The iOS memo cache similarly admits only
schema-v2 or newer responses whose canonical UUID/name matches its request.
Successful public responses do not vary by Authorization, preserving shared
cache reuse instead of creating per-token origin traffic.

### Testing Supabase Functions and Tooling

Before opening a PR targeting `services/supabase`, gate both deployable
functions and repository tooling:

```bash
deno fmt --check services/supabase/functions services/supabase/scripts
deno lint --config services/supabase/functions/deno.json \
  services/supabase/functions services/supabase/scripts
make test-supabase-tooling
make validate-edge-dto-contract
(cd services/supabase/functions && deno task test)

deno run --allow-read=services/supabase \
  services/supabase/scripts/sync_function_deno_configs.ts --check
deno run --allow-read=services/supabase \
  services/supabase/scripts/validate_function_dependencies.ts
deno check --frozen \
  --config services/supabase/functions/<function>/deno.json \
  services/supabase/functions/<function>/index.ts
```

`test_supabase_tooling.sh` dynamically type-checks every standard script and
runs every standard `*_test.ts`, including the ghost-user suites and the static
Function-caller contract. That contract requires exact config/entrypoint parity
and rejects literal calls from any application target, workflow, worker,
operator script, or migration to missing routes; the one historical retired
domesticated-purge schedule is accepted only while its later unschedule evidence
remains exact. The tooling gate then tests and executes the executable Identify
contract/Swift generator under its isolated frozen config, syntax-checks every
shell script, and runs every `*_test.sh`. It also rejects complete secret-shaped
`sb_secret_…` literals across repository files before deployment. Tests must
construct format-valid fake keys from separate fragments, and the gate reports
filenames rather than matching values. New conventionally named tooling tests
therefore enter the gate without editing CI.

`validate_edge_dto_contract.sh` is the shared isolated entrypoint used by both
the backend deployment workflow and the lightweight iOS project guardrail.
Consequently, an extension-only decoder change anywhere under `apps/ios` is
checked immediately without causing a production backend deployment.

`functions/_shared/identify/contract.ts` is the one source of truth for the
model output and final `{ success, data }` response. Its typed descriptor
generates both Vision and Describe provider schemas, infers deployed TypeScript
payload types, and executes recursive runtime validation for nested fields,
arrays, requiredness, nullability, enums, string/cardinality limits, safe
integers, and numeric bounds. Provider output is validated immediately after
JSON extraction. `functions/_shared/identify/googleSchema.ts` translates the
dependency-free projection into the pinned Google SDK through a structurally
typed adapter, so SDK schema-field changes fail Deno checking without loading
SDK runtime code into contract tooling. The complete payload is validated again
after cache hydration and server enrichment, before persistence or HTTP success;
invalid responses expose only the stable `identify_response_invalid` public
code. The successful envelope literal must be `success=true`; every route must
emit `blur_score`, `colors`, `candidates` (which may be `null`),
`estimated_size_cm` (which may be `null`), `image_quality`, and
`pet_identification` (which may be `null`), while biological-only enrichment
remains optional or nullable.

The same descriptor generates the marked Identify block in
`InferenceEdgeDTOs.swift`, including the full nested response graph, explicit
`CodingKeys`, and explicit `init(from:)` implementations. This makes custom
decoder replacement a Swift redeclaration error, while the fast contract gate
also rejects direct or aliased extensions and top-level redeclarations across
the complete `apps/ios` graph. Root Swift fields remain optional for
backward-compatible rollout, but the server runtime contract is strict before
delivery. `ai_reasoning` and `extracted_visual_traits` are intentionally
server-only because iOS receives reasoning through `insight_data` and does not
decode retained visual traits.

Every numeric contract node has finite bounds and is checked at runtime before
Swift decoding. Integers must also be JavaScript-safe; generated JSON integers
use signed Swift `Int` and JSON numbers use `Double`, avoiding implicit `UInt8`,
`Float`, or `CGFloat` narrowing. The validator has no compiler/parser dependency
and cannot accidentally resolve a shadow declaration: it imports the same
frozen, dependency-free contract code that the Edge runtime executes. Run
`make generate-edge-dto-contract` after an intentional contract change, review
the generated Swift diff, then run `make validate-edge-dto-contract`.

After changing a pin in `functions/deno.json`, regenerate the function-local
configs with `sync_function_deno_configs.ts`, refresh
`functions/dependencies.lock`, and commit all three surfaces together. CI
rejects stale generated configs, unlocked packages, direct runtime specifiers,
and any missing or stale `config.toml` function entry. When the fleet changes,
fix the reported name mismatch; never update a numeric expected-function count.

The checked-in `deno task test` is the canonical complete function source and
unit suite. Its read allowlist includes the function tree plus migrations,
monitor scripts, the complete pgTAP fixture directory, Supabase config,
repository workflows, iOS contract surfaces, and the waitlist route inspected by
security contract tests. Deployment CI runs it after migrating the disposable
database so database-backed cases cannot silently skip. Do not replace it in CI
with a selected test subset.

Selected source-inspection lanes retain narrow permissions, but their
`--allow-read` lists must include every transitive filesystem root they inspect.
The focused DwC-A lane therefore grants the complete `supabase/tests` fixture
root and `../apps/ios` source root from the workflow's `services` working
directory. `scripts/tooling_gate_test.ts` rejects removal of either root while
the scan-finalization/DwC-A contract remains selected. Passing tests before a
later permission denial does not constitute a successful lane or release
evidence.

Operational workflows run Deno with frozen dependencies and explicit
Supabase-host, environment-variable, and output-path permissions. The taxonomy
import runs with `contents: read` and cannot read a checkout credential; its
checklist artifact is committed by a separate five-minute writer. There are no
other reviewed `contents: write` paths; Xcode Organizer owns iOS distribution
without repository write access. Account deletion,
DwC-A, and RevenueCat health clients
additionally enforce a 15-second deadline and streaming 64 KiB response ceiling
beneath `supabase-js`; the detailed scan-media monitor uses the same deadline
with a 2 MiB ceiling for its bounded sample report.

Run it directly:

```bash
cd services/supabase/functions
deno task test
```

### Testing Database Migrations

Media durability migrations have an additional static contract test that runs
without a local Postgres instance. It checks the normalized scan-media lifecycle
schema, the scan-ingestion job ledger, the drift-repair SQL that must run before
media reconciliation indexes are created, and the source-aware uniqueness repair
for generated versus promoted capture-upload rows.

The same migration contract suite covers the identification-latency migration:
service-role-only RPC grants, the atomic ingestion setup function, combined
dictionary hydration, and the RLS-protected deferred-context table/trigger. It
also guards the APNs device-token repair so PostgreSQL format validation and
32...512 character length validation remain separate. The executable pgTAP
coverage in `tests/push_device_registration.sql` accepts a normal 64-character
hex token and rejects short, oversized, and non-hex tokens.

Species-count projection has paired tests:

- `_tests/speciesCountTriggerMigrationContract.test.ts` rejects restoration of
  `COUNT(DISTINCT ...)`, row-level triggers, missing transition tables, unsafe
  ACLs/search paths, removal of deterministic user locking, or a table lock
  outside the explicit whole-cutover transaction.
- `tests/species_count_trigger_security.sql` checks the live catalog plus bulk
  insert, unrelated update, owner transfer, species replacement, duplicate, scan
  deletion, and dictionary `SET NULL` behavior. It deliberately corrupts one
  projected total before an unrelated update to prove no hidden full-history
  recount still runs.

The suite also locks the Explore current-scan reference exclusion helper and the
unchanged `get_explore_post_detail` response projection. Run the static contract
plus the executable DB case after changing species-reference ordering,
blocked-media handling, legacy fallback, or scan media fields:

Public species stats have both static and executable security contracts:

- `_tests/speciesObservationStatsCoverage.test.ts` prevents removal of
  dictionary binding, deadlines, body limits, or fenced RPC calls.
- `_tests/speciesObservationStatsMigrationContract.test.ts` locks rates, ACLs,
  lease duration, negative TTLs, and finalization fencing.
- `tests/species_observation_stats_security.sql` executes canonical denial,
  persistent rate accounting, cross-isolate claim suppression, expired-token
  fencing, cache-race closure, and API-role ACL checks.

`_tests/migrationExecutionContract.test.ts` lexically masks comments and
inspects executable direct and dynamic SQL before rejecting concurrent
`CREATE INDEX`, `DROP INDEX`, or `REINDEX`. The public-schema migration contract
separately rejects top-level transaction-control aliases in new migrations after
masking quoted values and routine bodies. Supabase CLI `2.109.1` owns the
migration transaction and history boundary. Its normal apply path wraps
pipeline-compatible statements with the history insert, but fresh replay also
passes immutable historical compatibility artifacts. Top-level timeout guards
therefore use session `SET` plus matching `RESET`, never `SET LOCAL`, so they
work in either execution mode.

`_tests/publicSchemaSecurityMigrationContract.test.ts` also locks effective RLS
for every migration-created public table, final reaction-table grants, global
and schema default ACLs, and catalog-driven user-FK index rules.
`tests/public_schema_security.sql` verifies those behaviors in a fully migrated
PostgreSQL 17 catalog. For a large production table, create the index in a
separately supervised owner session outside `db push`, verify both
`pg_index.indisvalid` and `indisready`, and retry the unchanged size-gated
migration. A partitioned parent requires valid leaf indexes and a reviewed
metadata-only parent operation.

```bash
deno test --allow-read \
  services/supabase/functions/_tests/migrationMediaContract.test.ts
SUPABASE_DB_TEST_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  deno test --allow-env --allow-net \
  --filter "excludes only the current scan media" \
  services/supabase/functions/_tests/explorePostDetailDb.test.ts
```

Run the focused checks from the repository root after the local Supabase stack
is available:

```bash
make validate-supabase-migrations
make test-supabase-privileged-routines
bash services/supabase/scripts/test_database_catalogs.sh
```

Keep the pgTAP fixture local; do not substitute `--linked`. Before deploying a
database repair, run `supabase --workdir services db push --linked --dry-run`
and confirm only the reviewed migrations appear. After deployment, run
`supabase --workdir services migration list --linked`, then inspect
`pg_constraint` read-only. For the APNs repair, both
`user_push_devices_device_token_format_check` and
`user_push_devices_device_token_length_check` must exist with
`convalidated = true`. The migration is database-only; the existing
`register-push-device` Edge Function does not need redeployment.

For the scan-media uniqueness repair, the legacy
`scan_media_assets_scan_id_order_index_key` constraint must be absent. The
`idx_scan_media_assets_generated_unique` partial unique index must cover
`(scan_id, source, role, order_index)` only for `scan_refresh` and `backfill`,
and `idx_scan_media_assets_upload_session_unique` must cover
`(upload_session_id, order_index)` only when the upload session is present. This
allows a promoted `capture_upload` audit row to coexist with its generated ready
row while still rejecting duplicate positions within either writer contract.

Field trips migrations also have static contract coverage. The current chain is
V1 template/progress/publication storage, V2 guided detail/start/pins, V3
Community/activity, and V4 curated Seasonal Challenges with explicit joins,
challenge progress, badges, challenge entries, and optional Explore hashtag
suggestions. The contextual objective-guide migration supplies structured Tips,
`20260717195751_active_outing_capture_context.sql` adds the private service-role
capture read model.
`20260717213641_preserve_standard_outings_in_capture_context.sql` keeps the
underlying standard field trip visible after a Seasonal Challenge join while
still ignoring challenge-specific progress.
`20260717224544_retire_forest_edges_outing.sql` deactivates the Forest Edges
placeholder without deleting historical user data.
`20260718043218_expose_field_trip_completion_scan_ids.sql` adds the completing
scan ID to the private catalog/detail projections while restricting both RPCs to
`service_role`. `20260718051748_expose_field_trip_publication_status.sql` adds
the owner's active non-deleted publication ID/timestamp to private template
detail only. `20260718150932_add_credited_field_trip_progress.sql` extends both
standard and Seasonal Challenge scan-progress responses with the level
number/title and completed/target counts credited by the scan. It preserves the
existing RPC signatures, permissions, and response fields; the added fields let
a level- completion toast show the completed level rather than the newly active
level. `20260718162409_scope_credited_progress_to_current_attempt.sql` scopes
those credited counts to checklist items matched by the current application
attempt, so re-identifying an older scan cannot duplicate a destination or reuse
a previous level's ring.
`20260722025411_persistent_field_trip_scan_contributions.sql` adds the private
selected-goal preference, deterministic one-credit ranking, correction support,
and scan contribution projection.
`20260722064704_harden_atomic_field_trip_progress.sql` moves standard progress,
Event progress, preference persistence, first-outing achievement evaluation, and
the scan-revision receipt into one transaction. Scan insertion/correction
triggers call that boundary from the ingestion pipeline. The migration also
repairs completed-outing publication item materialization, removes the pin RPC's
temporary-table dependency, and revokes all Field trip/Event `SECURITY DEFINER`
functions from `PUBLIC`, `anon`, and `authenticated`; only `service_role` may
execute them. `20260722195453_exclude_ants_from_bee_wasp_goal.sql` first
excludes `Formicidae` from Park Pollinators' Hymenoptera goal and repairs
ant-backed progress. `20260722211636_tighten_field_trip_goal_matching.sql` adds
conjunctive taxonomy-plus-signal matching, finalizes **Bee or wasp** as
Hymenoptera plus `bee|wasp`, narrows active Spider/Butterfly/plant/animal goals,
aligns unverifiable Park prompt copy with saved-scan evidence, and repairs
progress credited by the former broader rules.
`20260730023042_gate_field_trip_progress_by_confidence.sql` then requires an
unreviewed AI identification to meet its inference tier's Possible-match
boundary (`Flash >= 0.75`, `Pro >= 0.65`), while explicit confirmations and
confirmed corrections/resolutions remain eligible. It repairs prior weak-match
credit without discarding the pending selected-goal preference. The forward
repair has a ten-second lock timeout and five-minute statement timeout; either
timeout fails deployment and must be investigated rather than weakened.
Confidence, inference tier, confirmation, and the pending preference are
carried in the atomic receipt revision. A later downgrade to weak unreviewed
evidence removes standard/Event credit even after completion, reopens progress,
clears derived Event badges, and soft-deletes invalid completion
publications/entries. The contract suite verifies caller identity, role grants,
ordering/filtering clauses, private completion links/status, credited progress
in both RPCs, and the absence of evidence from public/capture projections.
`fieldTripCaptureContextDb.test.ts` additionally executes the
filtering/order/privacy contract, while `fieldTripProgressDb.test.ts` exercises
standard/challenge credited counts, level advancement, exact tier boundaries,
pending-preference retention, weak-match confirmation, evidence-downgrade
reopening, re-identification, idempotent reapplication, and representative
positive/negative cases for every narrowed active goal.
`fieldTripAtomicProgressDb.test.ts` proves rollback when the Event half fails,
`fieldTripSecurityDb.test.ts` enumerates runtime execute privileges, and
`fieldTripPublicationDb.test.ts` executes publication materialization. These
require the local Postgres stack; a connection skip is not database validation.

Explore identity integration coverage in `_tests/exploreIdentityDb.test.ts`
executes the public projection and ownership-repair functions against Postgres.
It verifies custom-avatar precedence, no row rewrite after identity convergence,
ownership repair, and service-role-only execution. Database helpers use the
standard local URL when `SUPABASE_DB_TEST_URL` is absent and may report a skip
when that default stack is unavailable. When `SUPABASE_DB_TEST_URL` is set
explicitly, a connection failure fails the test; this is the required mode for
CI and release validation.

The shared Explore fixture snapshots scan media by calling
`public.refresh_explore_post_media(...)` after inserting a post. Pass
`refreshMedia: false` only when a test intentionally models a partial post write
or supplies its own deterministic `explore_post_media` rows. Public Explore
reads are post-media based: changing scan geoprivacy or clearing
`scans.image_storage_urls` does not retroactively remove an existing public
snapshot. Tests for media removal must exercise the cleanup contract by removing
the post-owned media. Expected database errors inside the helper's transaction
must use a savepoint and roll back to it before making subsequent assertions.

```bash
SUPABASE_DB_TEST_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  deno test --allow-env --allow-net \
  services/supabase/functions/_tests/exploreIdentityDb.test.ts
```

From the repo root:

```bash
make validate-supabase-migrations
```

## Local Development

Use Supabase CLI `2.109.1` for release-equivalent local verification because CI
pins that exact reviewed version and the migration execution/replay contract is
tested against it. Treat another version as an intentional pin upgrade that
requires rerunning and reviewing all migration contracts. The discovery-based
`validate_migration_contracts.sh` entrypoint is shared by the Make target and
deploy workflow, so a new conventionally named contract cannot fall out through
list drift. The repository keeps every migration compatible with fresh-schema
replay rather than depending on CLI-specific concurrent-index handling. The
local email catcher uses the current `[local_smtp]` configuration section.
Confirm the local version before database verification:

```bash
supabase --version
```

The shared catalog gate and mutation-capable Make targets enforce this exact pin
before touching a database or deploying a Function. A version mismatch fails
before config parsing, migration replay, or network mutation; upgrade or switch
the local CLI instead of rewriting `config.toml` for an older parser.

From the repo root, point the Supabase CLI at the backend service directory:

```bash
# Start local Supabase stack
supabase --workdir services start

# Serve edge functions locally
supabase --workdir services functions serve <function_name>
```

### Ghost User Audit

Use the read-only audit before considering any anonymous-user cleanup. It reads
Auth Admin users plus public activity tables, classifies likely empty ghost
profiles, and writes reviewable JSON/CSV/Markdown snapshots. The audit also
calls the service-role-only protected-source RPC; prepared handoffs and merged
receipts awaiting Auth cleanup count as activity and can never become deletion
candidates. It does not delete or mutate data.

```bash
SUPABASE_URL="https://<project>.supabase.co" \
SUPABASE_SECRET_KEY="<sb_secret_...>" \
make audit-ghost-users ARGS="--snapshot-json /tmp/ghost-users.json --snapshot-csv /tmp/ghost-users.csv --summary-md /tmp/ghost-users.md"
```

`SUPABASE_SERVICE_ROLE_KEY` is still accepted for older projects, but new
Supabase projects should use a secret key from Settings > API Keys.

Review cleanup candidates with the guarded cleanup dry-run. This reads the audit
JSON and does not delete unless `--execute` and the confirmation flag are both
present.

```bash
make cleanup-ghost-users ARGS="--snapshot-json /tmp/ghost-users.json --limit 10 --output-json /tmp/ghost-cleanup-dry-run.json"
```

After manually reviewing a dry-run batch, execute only a tiny batch:

```bash
SUPABASE_URL="https://<project>.supabase.co" \
SUPABASE_SECRET_KEY="<sb_secret_...>" \
make cleanup-ghost-users ARGS="--snapshot-json /tmp/ghost-users.json --limit 10 --execute --confirm-delete-likely-empty-ghosts --output-json /tmp/ghost-cleanup-result.json"
```

Execute mode performs a second, live database reservation for each candidate
before calling Auth Admin delete. The reservation and handoff issuance share an
advisory lock: if an account upgrade is prepared first, cleanup fails closed; if
cleanup reserves first, prepare returns a retryable error without switching the
guest session. Do not run a historical version of the cleanup script after the
secure merge migration.

## Deployment

### Database Migrations

```bash
supabase --workdir services db push
```

Do not bypass the privileged-routine gate for a manual push. Run
`make test-supabase-privileged-routines` against the fully migrated local
catalog, capture a hosted `--report` audit before the push, and require a clean
`make audit-supabase-privileged-routines` result after it.

### Edge Functions

```bash
supabase --workdir services functions deploy
```

That command is the emergency/manual full-fleet path. Production CI computes the
affected functions from the transitive runtime import graph, excludes erased
explicit type-only edges, deploys bounded batches, and isolates retries to
members of a failed batch. Whole-tree Deno checks still validate compile-only
imports. A manual workflow dispatch intentionally selects the full fleet. Every
deployment finishes with a graph-derived all-route handler-marker probe,
followed by stricter fail-closed authorization probes for eleven
customer-critical scan, signing, share-state, Explore media-incident, Field
Chat, Community, and deletion routes.
It then reaches the exact no-write SQLSTATE `22023` boundary in
`ensure_scan_user_profile`, `publish_scan_to_explore_atomically`,
`request_community_identification_atomically`, `recover_missing_owned_scan`,
`get_media_abandoned_scan_recovery_proofs`, `reserve_field_chat_send`, and
`recover_stale_field_chat_quota` with server authority, while proving every
real anon/publishable project credential remains denied from all seven
routines.

This verifies PostgREST schema-cache readiness and production grants without
creating a fixture or logging a response body. Database migrations still run
before function deployment, so same-release schema changes must follow
expand/migrate/contract compatibility: the migration must remain safe for the
currently live function version, and destructive cleanup ships only after the
new readers/writers are proven live.

For identification-latency releases, apply migrations before deploying function
code that calls the new RPCs, then stage the client and Edge rollout using the
gates in `docs/backend-and-data/06-supabase-deployment-runbook.md`. Do not force
an Edge region without the documented A/B evidence.

For Field Chat reliability releases, apply
`20260729163616_reserve_field_chat_sends_atomically.sql` before either chat
function and include
`20260730180000_bind_field_chat_rows_to_subjects.sql` before release acceptance.
Deploy `insight-chat` and `explore-post-chat` from the same exact SHA, then stage
same-key replay/conflict, different-key concurrency in one conversation,
28/29/30-row boundaries, a 19-to-20 send transition split across both chat
families, cross-bound-row rejection, feedback ACLs, and the ten-minute
stale-quota path before releasing iOS. An RPC timeout, malformed admission row,
or missing migration must remain a retryable `503` without provider dispatch.

For the Field trip Scan indicator, apply the contextual-guide, active-field trip
capture-context, and standard-field trip preservation migrations before
deploying `field-trips`, then smoke-test the authenticated `capture_context`
action before releasing the iOS client. The RPC is intentionally unavailable to
direct `anon` and `authenticated` database calls; only the verified Edge action
may invoke it with `service_role`. The long-term client/source boundary and
extension rules are recorded in `docs/rfcs/active-capture-goal-context.md`.

For completed-goal thumbnails, also apply
`20260718043218_expose_field_trip_completion_scan_ids.sql` before releasing the
iOS client. Smoke-test that catalog/detail return the exact completion
`scan_id`, direct client roles cannot execute those RPCs, and public profile,
publication, challenge, Explore, and capture-context payloads remain
evidence-free.

For the Private/Published detail badge, apply
`20260718051748_expose_field_trip_publication_status.sql` before releasing the
iOS surface. Verify only private template detail receives the requesting owner's
active publication ID/timestamp and that direct client roles remain unable to
execute the RPC.

For credited scan-progress notifications, apply
`20260718150932_add_credited_field_trip_progress.sql` and then
`20260718162409_scope_credited_progress_to_current_attempt.sql` before releasing
the iOS toast surface. Verify partial progress, level advancement, final
completion, multiple standard/challenge destinations, re-identification after
level advancement, and idempotent reapplication. Those two migrations add only
response fields; legacy clients ignore them and newer clients fall back to
current counts until the migrations are live. The later persistent- contribution
release adds optional `preferred_goal` to the request.

For persistent Insight contribution cards and selected-goal preference, apply
`20260719045306_first_field_trip_achievement.sql`,
`20260719160750_field_trip_lifecycle_controls.sql`,
`20260720014446_update_backyard_safari_copy.sql`,
`20260722025411_persistent_field_trip_scan_contributions.sql`,
`20260722064704_harden_atomic_field_trip_progress.sql`,
`20260722195453_exclude_ants_from_bee_wasp_goal.sql`, and
`20260722211636_tighten_field_trip_goal_matching.sql`, followed by
`20260730023042_gate_field_trip_progress_by_confidence.sql`, in order. Then
deploy the scan-ingestion functions and `field-trips` before the iOS client.
Smoke-test optional `preferred_goal`, Possible-match boundaries, weak-match
confirmation and downgrade reopening, pending-hint retention, one credit per
outing/Event, deterministic fallback, correction removal/move, bee/wasp
acceptance with ant and sawfly rejection, the representative negative-match
matrix, transactional rollback, receipt replay, publication, and
`scan_contributions`. Direct client roles must not read either private progress
table or execute any Field trip/Event `SECURITY DEFINER` RPC; contribution
payloads must contain no media, coordinates, place labels, notes, or public
evidence. Older clients omit the preference and remain compatible.
