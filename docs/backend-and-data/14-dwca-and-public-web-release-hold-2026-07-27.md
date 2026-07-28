# DwC-A and Public Web Release Assurance — 2026-07-27

Status: **IMPLEMENTED; BLOCK production promotion until exact-release-SHA
catalog and hosted-load evidence passes.**

Base reviewed implementation: `7b74289c3aaeb9f814088c4981bac715b46fae51`.

Remediation is implemented in forward migration
`20260728001723_repair_dwca_privacy_visibility_and_snapshot_work.sql` and its
paired Edge/web changes. Follow-on migration
`20260728035237_harden_dwca_downloads_and_scan_finalization.sql` adds revocable
download authorization, durable archive cleanup, and atomic scan-generation
finalization/recovery. This record remains the source of truth for deploying and
verifying that release unit. It does not replace the deployment runbook or API
contracts.

## Scope

The release unit contains:

- the immutable DwC-A source snapshot and resumable export worker;
- `request-export-dwca`, `export-dwca`, `download-dwca`, and
  `reconcile-dwca-archive-cleanup`;
- multimodal scan claim, owner-row recovery, replay, and media finalization;
- owner and retention scan deletion plus the independent
  `reconcile-scan-deletions` reaper and aggregate erasure-SLA monitoring;
- the server-only public-web Explore card/detail boundary; and
- `apps/web` when it consumes that boundary.

## Current Platform Assumptions

This release does not rely on a project's automatic Data API grants. Supabase is
making new-project exposure opt-in, while existing projects can retain automatic
privileges. The migration therefore revokes exact function execution from
`PUBLIC`, `anon`, and `authenticated`, then grants only the required
service-only routines. RLS is not treated as a function-execution boundary.

Privileged routines follow current
[Supabase Database Functions guidance](https://supabase.com/docs/guides/database/functions):
prefer invoker semantics where possible; otherwise use an empty fixed
`search_path`, qualify every object, perform authorization inside the routine,
and apply explicit grants. Data API grants and row policies remain separate
controls as described in
[Securing your API](https://supabase.com/docs/guides/api/securing-your-api).

## Implemented Repairs

### Full-lifecycle DwC-A privacy fence

Every creation-time source member is now checked, not only members after a phase
cursor:

- `internal.dwca_export_source_is_current(job_id)` verifies snapshot version,
  invalidation/purge state, exact member count, current eligibility, and every
  stored eligibility hash.
- Relevant scan deletion, tombstoning, ownership, live/ecology, geoprivacy,
  taxonomy identity, and protected-species policy changes durably invalidate
  affected nonterminal jobs.
- The worker invokes the claim-fenced `check_dwca_export_source_fence(...)`
  before assembly, before recipient lookup, and again immediately before the
  email provider call.
- Archive staging and completion repeat the full check transactionally and
  return SQLSTATE `55001` for terminal `source_snapshot_changed`.
- A source mismatch immediately revokes application download authority and
  durably enqueues the uploaded/staged archive for deletion. Resend remains
  idempotent by job ID.
- If privacy changes after the final pre-provider check while Resend is already
  accepting the request, completion still repeats the fence, rejects the job,
  and revokes the capability. The email can exist, but its application URL
  cannot authorize the object.
- A processing job never exposes its staged capability through user-readable
  `public.export_jobs`. Staging stores the URL in
  `internal.export_job_work.delivery_file_url`; the final transaction copies it
  into the public job and marks the job completed only after the full fence.
  Every terminal transition also erases the private staged capability.
- A completed job no longer exposes a one-day direct R2 signature. Every
  `download-dwca` click uses a SHA-256 capability index, a distributed IP-hash
  rate limit, and a fresh full-member privacy check before a read-only, no-store
  R2 redirect valid for at most 30 seconds.
- Scan and protected-species policy triggers monotonically invalidate every
  affected unpurged snapshot, regardless of the job status visible to the
  privacy statement. This closes the statement-snapshot race with a concurrent
  delivery transition. Any already-present grant is revoked and its current
  archive is enqueued; click-time authorization repeats the full fence as a
  fail-closed backstop.
- Grant expiry, revocation, failure, deletion, and legacy direct URLs feed a
  unique leased archive-cleanup outbox. Its five-minute service worker retries
  storage failure and reports aggregate oldest-due/backlog/expired-lease health.
  Cleanup completion is fenced to the exact current attempt-scoped object key,
  so a delayed cleanup lease cannot revoke a replacement grant or purge active
  source state.

Occurrence and multimedia still use immutable creation-time DTOs, so ordinary
content edits cannot mix revisions across phases. The live fence is limited to
eligibility and privacy policy changes.

### Canonical, atomic public-web Explore detail

`get_public_web_explore_post_detail(...)` now independently inner-joins the
canonical anonymous `explore_projected_post_cards(NULL)` projection. Direct
service-key invocation therefore returns no detail for content excluded by
moderation, publication, media-health, tombstone, or block predicates.

`get_public_web_explore_post_page(...)` returns card and detail from one
database statement and one MVCC snapshot. The Next.js page uses only this
combined routine, eliminating its former card-then-detail check race.

Both routines remain `SECURITY DEFINER`, require
`internal.require_service_role()`, use an empty fixed `search_path`, and revoke
execution from `PUBLIC`, `anon`, and `authenticated`.

### Cumulatively bounded snapshot creation

Snapshot creation no longer constructs all candidate JSON DTOs before deciding
the aggregate byte budget:

1. It counts only UUID membership up to `max_export_rows + 1`.
2. An index-backed eligible-ID cursor performs a parameterized
   `CROSS JOIN LATERAL ... LIMIT 1` projection.
3. One DTO is fetched, measured, and inserted at a time.
4. Projection stops at the first 256 KiB per-row violation or cumulative
   `max_source_bytes` violation.
5. An oversized attempt stores only the canonical budget-plus-one sentinel and
   removes partial private source rows.

This bounds DTO memory and temporary-sort amplification independently of the row
limit. The insert trigger is intentionally retained so job creation and
immutable membership share one creation-statement MVCC snapshot.

### Atomic scan generation and completion

`begin_scan_ingestion(...)`, the rolling-deployment compatibility
`claim_scan_ingestion_job(...)`, and `recover_missing_owned_scan(...)` take the
same transaction-scoped advisory lock derived from the normalized scan UUID.
Recovery writes the owner row and a completed recovery ledger atomically; setup
writes the active ledger and sanitized intent atomically. All four current
scan-producing routes use atomic setup before provider dispatch. Setup failure
fails closed and refunds unused quota rather than falling back to separate
writes. Their order therefore determines one generation without a
check-then-insert race. A legacy claim that arrives after recovery preserves the
completed generation.

`complete_scan_ingestion_finalization(...)` locks that generation, verifies
every claimed object key has an explicit promoted/deleted capture-asset
disposition, rebuilds canonical image/video/audio rows, proves every promoted
URL is ready, and writes ledger completion last. Multimodal inference, server
replay, media reconciliation, and the identify/audio/describe compatibility
routes no longer update `complete` independently. Required staging and
inference-only companion deletions must receive an R2 2xx or 404 result before
finalization; provider 5xx and other non-success responses retain a noncomplete
ledger. Compatibility finalization failure becomes explicit retryable work
rather than a swallowed background error. Compatibility recovery is allowlisted
only for structured `terminal_reason_code = replay_exhausted` and fails closed
on unknown reasons. The catalog trigger rejects unfenced completion, reopening,
and scan-identity changes even from service-key table writes. Completed owner
reparenting is allowed only when all exact source/target/enabled markers from
the atomic ghost-profile merge transaction match.

Individual scan erasure now takes the same generation lock and commits a private
owner/UUID deletion tombstone before R2 work. The tombstone terminal-marks
noncomplete ingestion and permanently rejects later claim, insert/update,
finalization, replay, or compatibility recovery. Only confirmed
2xx/idempotent-404 storage deletion permits the guarded database-row removal;
the client's durable cloud-deletion task safely retries a lost response.
Account-profile deletion nulls the tombstone's owner linkage while retaining the
deleted scan UUID fence.

Expired non-biological retention uses the same lifecycle rather than deleting
inline. `request_nonbiological_scan_retention_deletions(...)` selects bounded
oldest-first candidate sets, acquires generation locks in UUID order, and
rechecks age, classification, `is_tombstoned = false`, non-null/non-reserved
ownership, and generation-tombstone absence under each row lock before
requesting deletion. Ownerless, reserved-owner, and rows already tombstoned by
account erasure remain with the account-erasure pipeline. `auto-purge-nonbio`
deadline-drains only this database intake. The reaper reloads the fenced
canonical media afterward, closing the former window in which a finalizer could
append an object after the purge route captured its URL list but before it
deleted the row.

### Terminal delivery classification

Resend 4xx responses that cannot become successful by retrying the same
job-scoped request are terminal. Ambiguous success responses, network/timeouts,
408/409/425/429, 5xx, storage, database, and lost-fence failures remain durable
retries. A permanently invalid recipient can no longer consume queue capacity
forever.

## Regression Evidence

Focused Deno coverage currently proves:

- early-member tombstoning after final paging is rejected before assembly;
- a source change during upload is rejected at staging and enqueues the object;
- a source change before delivery, including after recipient lookup, sends no
  email and enqueues the staged object;
- a source change while the email provider call is in flight fails completion,
  revokes/enqueues the archive, and does not retry the idempotent provider call;
- SQLSTATE `55001` maps to terminal `source_snapshot_changed`;
- application capabilities stay private while a job is processing;
- completed capability clicks rerun full-source privacy and expose only a
  30-second read redirect; expired/revoked objects enter leased cleanup;
- permanent Resend rejection terminates while ambiguous/transient failures
  retain durable retry;
- concurrent scan claim/recovery has one locked winner, claimed media is
  disposition-complete, and ledger completion follows canonical media;
- an interrupted owner deletion remains mutation/recovery-fenced and completes
  through the server reaper without a client retry; stale lease release fails,
  R2 404 converges, and the completed UUID fence retains no owner linkage;
- compatibility routes cannot invoke a direct complete update, and
  inference-only audio deletion is confirmed before finalization;
- a delayed cleanup for an older attempt cannot revoke the current grant or
  purge its source state, while cleanup of the exact current key does both;
- privacy, delivery, deletion, and cleanup take the canonical export-job row
  lock and one per-job advisory generation lock before any grant/source/outbox
  child lock, preventing cross-generation transitions and lock inversion;
- scan/species catalog replacement performs lock-safe monotonic invalidation
  inside `TRUNCATE`, while the independent claimant later performs parent-first
  grant revocation and archive enqueue through supporting partial indexes;
- the independent export/archive monitor reads cleanup health even if the
  database cleanup cron or Vault configuration is absent;
- direct hidden Explore detail and the atomic page routine return no row;
- the catalog owner can transition a fixture to moderated while `service_role`,
  which has no direct source-table write privilege, observes exclusion through
  only the granted RPCs;
- public API roles cannot execute either public-web routine; and
- oversized maximum-cardinality DTO sources stop at the aggregate sentinel
  without retaining partial source rows.

Local validation in the remediation working tree passed:

- 83 focused DwC-A/download/scan-finalization TypeScript tests;
- the complete Edge Function suite: 1,238 tests, zero failures;
- all 144 tests across 21 discovered migration contract files;
- the complete Supabase tooling gate, including its 100 standard tests, 16 DTO
  validator tests, 10 executable Identify contract tests, shell tests, and
  database-catalog discovery;
- whole-tree Supabase formatting across 656 files and lint across 501 files;
- all 89 function-specific Deno configuration checks, all 89 isolated dependency
  graphs across 283 runtime files, and all 89 production entrypoint type checks;
  and
- all 56 public-web source tests.

The complete release workflow must replay these checks for the exact release
SHA. A frozen web dependency install could not be restored in the restricted
local environment after npm registry access failed, so the full web
test/type-check/build result is intentionally not claimed here.

### Catalog replay evidence: run 1534 attempt 1

GitHub run 1534 replayed the fresh local catalog for commit
`c58df29c9309cd4dad9674a4f012b037359d35fd` with the repository-pinned Supabase
CLI 2.109.1. Eighteen of nineteen discovered database catalog files passed. The
remaining public-web fixture failed before its visibility assertion because it
attempted to update `public.explore_posts` while impersonating `service_role`.
PostgreSQL returned SQLSTATE `42501`, confirming the intended direct-table ACL.

The corrected fixture resets to the catalog-test owner for moderation mutation,
then re-enters `service_role` only to call the narrow RPCs. No table privilege
is added. This failed attempt is useful negative evidence, but it is not a pass;
the corrected test and all nineteen catalog files still require exact-SHA CI
replay.

## Remaining Release Evidence

These are assurance gates, not unresolved design work:

- fresh-catalog migration replay and pgTAP using the repository-pinned Supabase
  CLI;
- exact-release-SHA replay of the complete Edge, tooling, formatting, lint,
  isolated-graph, and web gates;
- the stable hosted `iOS Build and Test / Production readiness` result, proving
  the complete iOS unit-test target and unsigned Release archive from that same
  SHA;
- hosted maximum-shape PostgreSQL measurements for duration, temporary bytes,
  memory pressure, lock age, and WAL;
- production catalog checks for RLS, ACLs, empty definer `search_path`, trigger
  installation, and service-only grants;
- real anon, publishable, authenticated, and server-key negative/positive smoke
  tests;
- queue, invalidation, staged-object, archive-cleanup, and scan-deletion
  monitoring confirmation; and
- concurrent scan claim/recovery, failed-finalization, and interrupted-erasure
  production smoke.

The local machine used for this remediation could not supply fresh-catalog
evidence: its installed CLI cannot parse the newer repository configuration, and
Docker access is unavailable. This is explicitly **unverified**, not a pass.

## Promotion Gate

Remove the production hold only when all of the following are attached to the
same release SHA:

- fresh-catalog migrations and all DwC-A/public-web/scan-finalization pgTAP
  files pass;
- complete Deno, dependency, tooling, format, lint, DTO, and isolated-function
  graph checks pass;
- web frozen install, audit, test, type-check, and production build pass;
- the complete hosted iOS unit-test target and independent unsigned Release
  archive pass for the exact release SHA;
- hosted maximum-shape snapshot/export measurements remain inside agreed
  database, Edge CPU/memory, R2, and latency budgets;
- production catalog and credential smoke matrices match the contracts above;
- export-queue, archive-cleanup, and scan-deletion operational monitors are
  enabled and healthy; and
- an interrupted staging scan deletion completes through
  `reconcile-scan-deletions` without a client retry while the permanent UUID
  fence prevents mutation, replay, and recovery.

Until that evidence exists, do not enable new DwC-A intake/delivery or promote
the paired public-web release merely because focused unit/static suites are
green.
