# DwC-A and Public Web Release Assurance — 2026-07-27

Status: **DwC-A DEFAULT-OFF FOR INITIAL LAUNCH; BLOCK base production promotion
until exact-release-SHA catalog, complete-CI, and production negative gate
evidence passes. Active export load/delivery evidence is deferred to a separate
feature-enable gate.**

Base reviewed implementation: `7b74289c3aaeb9f814088c4981bac715b46fae51`.

Remediation is implemented in forward migration
`20260728001723_repair_dwca_privacy_visibility_and_snapshot_work.sql` and its
paired Edge/web changes. Follow-on migration
`20260728035237_harden_dwca_downloads_and_scan_finalization.sql` adds revocable
download authorization, durable archive cleanup, and atomic scan-generation
finalization/recovery. Launch-isolation migration
`20260728133835_disable_dwca_exports_for_launch.sql` then makes export behavior
default-off independently of app and Edge versions. This record remains the
source of truth for deploying and verifying the base release and later feature
enable. It does not replace the deployment runbook or API contracts.

## Scope

The release unit contains:

- the installed but launch-disabled immutable DwC-A source snapshot and
  resumable export worker;
- `request-export-dwca`, `export-dwca`, `download-dwca`, and
  `reconcile-dwca-archive-cleanup`;
- multimodal scan claim, owner-row recovery, replay, and media finalization;
- owner and retention scan deletion plus the independent
  `reconcile-scan-deletions` reaper and aggregate erasure-SLA monitoring;
- the server-only public-web Explore card/detail boundary; and
- `apps/web` when it consumes that boundary.

## Initial Launch Isolation

DwC-A is not part of the active initial-launch product surface:

- `FeatureFlag.dwcaExports` defaults false, so Release iOS builds omit the
  Settings section. Debug overrides are presentation-only.
- `internal.dwca_export_release_control` is a private no-API-grant singleton
  whose canonical state defaults false; missing state also fails closed.
- Every intake path retains a shared lock on that singleton until transaction
  end, so reviewed state updates cannot interleave with a job insertion.
- The alphabetically first `public.export_jobs` BEFORE INSERT trigger rejects
  old Edge bundles and unexpected direct service-role insertion with
  `dwca_exports_disabled`.
- `request_dwca_export_job(...)` takes a transaction advisory lock keyed by user
  and atomically combines release state, the rolling 24-hour window, and
  insertion. The route maps disabled to `403 feature_unavailable`.
- The service worker returns `200`/`disposition: disabled` before discovery;
  public download returns no-store `410` before R2 signing.
- The once-per-minute continuation cron is absent. Existing pending/processing
  rows are failed as `feature_disabled`, grants are revoked, and known final
  archives enter the durable deletion outbox.
- Archive cleanup cron and independent monitoring remain active. Temporary
  private work objects are bounded by the checked-in one-day R2 lifecycle rule.

This isolation removes active ZIP CPU/memory, export throughput, R2 multipart,
Resend delivery, and maximum-shape snapshot behavior from the initial runtime
surface. It does not remove the migrations, routines, triggers, tables, or
cleanup worker from the catalog. Fresh replay, ACL/RLS/search-path validation,
exact-SHA compile/test evidence, production negative smokes, and cleanup health
therefore remain base-release requirements.

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
- default-off release state is structurally validated and fails closed on
  malformed/unavailable RPC responses;
- request code uses only the atomic database routine and cannot fall back to
  direct `export_jobs` reads/inserts;
- Release iOS Settings presentation is bound to `.dwcaExports`; and
- static launch contracts retain archive cleanup while forbidding continuation
  rescheduling.

The exact focused DwC-A workflow command for the launch-isolation change passed
138 Deno tests, all three modified production entrypoint type checks, focused
lint, all 89 isolated function graphs across 284 runtime files, and all 10
dependency-graph tests. Fresh-catalog execution is still required; these
static/unit results do not validate migration execution.

Local validation in the remediation working tree passed:

- 138 focused DwC-A/download/scan-finalization TypeScript tests;
- the complete Edge Function suite: 1,246 tests, zero failures;
- all 145 tests across 21 discovered migration contract files;
- the complete Supabase tooling gate, including its 102 standard tests, 16 DTO
  validator tests, 10 executable Identify contract tests, shell tests, and
  database-catalog discovery;
- whole-tree Supabase formatting across 660 files and lint across 505 files;
- all 89 function-specific Deno configuration checks, all 89 isolated dependency
  graphs across 284 runtime files, and all 89 production entrypoint type checks;
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

### Focused test evidence: run 1539 attempt 1

GitHub run 1539 evaluated commit `7f83b391c5a77ca06384d2e4a68ec3e5597ad808`. Its
focused DwC-A lane passed 122 tests, then Deno rejected module loading because
the command did not grant read access to
`services/supabase/tests/dwca_download_and_scan_finalization_security.sql`. This
is a CI permission failure, not passing release evidence.

The correction adds the complete `supabase/tests` fixture root to that focused
lane and adds an earlier tooling contract requiring both that root and the iOS
release-boundary source root. The exact corrected SHA must replay the lane; run
1539 remains red and is not promoted as evidence.

### Fresh-catalog scan ACL evidence: run 1541 attempt 1

GitHub run 1541 evaluated commit `3cbc0a0d258e2ff4a85c9bd191646d95bcc83672`.
Twenty of twenty-one discovered catalog files passed. The remaining
`dwca_download_and_scan_finalization_security.sql` fixture failed because its
authenticated-column query classified every effective `UPDATE` as broad while
the same fixture required the five rolling-client compatibility-column grants.
The migration had already revoked table-level API mutation and granted only
those five columns, so this was a contradictory assurance query, not evidence
that another production privilege should be granted.

The corrected fixture defines one exact allowlist, rejects broad table mutation,
rejects every anonymous column mutation/reference privilege, rejects
authenticated insert/reference and non-allowlisted update privileges, and then
requires every allowlisted update. No schema, policy, or production grant is
widened. Run 1541 remains failed evidence; the corrected exact SHA must replay
all catalog files successfully before promotion.

### Explicit scan ACL evidence: run 1542 attempt 1

GitHub run 1542 evaluated commit `d4e2c0cc2de60b30b32d7f488764d5114a5f687b`.
Twenty of twenty-one catalog files passed. The corrected scan ACL assertion then
proved the fresh catalog lacked canonical `service_role` scan mutation
privileges. This is expected under Supabase's newer opt-in Data API exposure
mode: bypassing RLS does not grant table access, and repository migrations must
no longer depend on project-era automatic grants.

Forward migration `20260728151927_declare_scan_data_api_privileges.sql` now
clears table and historical column grants before declaring the exact boundary:
RLS-governed reads for `anon`/`authenticated`, five authenticated compatibility
updates, canonical CRUD for `service_role`, and no direct `PUBLIC` or
truncate/reference/trigger/maintain authority. Run 1542 remains failed evidence;
all twenty-one catalog files must pass from the corrected exact SHA before
promotion.

### Trigger static-validation evidence: run 1543 attempt 1

GitHub run 1543 evaluated commit `a0db2b89c34994ca384e74fde9a8bf246d1c4559`.
Twenty of twenty-one catalog files passed. The remaining fixture reached
`plpgsql_check` after its ACL assertions passed, then invoked six trigger
routines without the relation OID required to provide trigger context. The
resulting `missing trigger relation` exception was an assurance-harness failure,
not passing static-validation evidence.

The corrected fixture keeps all twenty-three routines in one typed registry,
passes zero only for ordinary routines, and supplies the expected table OID for
every trigger routine. It does not skip static validation or change a production
schema, policy, routine, or privilege. Run 1543 remains failed evidence; all
twenty-one catalog files must pass from the corrected exact SHA before
promotion.

### Production monitor catalog gap after failed deploys

The independent DwC-A monitor subsequently received `PGRST202` for
`public.get_dwca_archive_cleanup_health()`. Production therefore did not expose
the zero-argument health contract introduced by
`20260728035237_harden_dwca_downloads_and_scan_finalization.sql`; no queue or
cleanup health conclusion can be drawn from that run. This is expected
release-blocking evidence consistent with deployment stopping before migration
push. A direct catalog check must distinguish an absent routine from a stale
PostgREST cache; neither case is a reason to disable monitoring or substitute
zero values.

The monitor correction preserves a nonzero exit while writing a stable critical
artifact with `catalog_contract_missing/archive_cleanup` and unavailable health
values. Forward migration
`20260728144336_reload_postgrest_after_health_routines.sql` requests a PostgREST
schema reload after the required routines deploy. The base promotion hold
remains until exact-SHA deployment applies the routines, the service-only grants
pass catalog enforcement, and the independent monitor returns real consistent
rows.

## Remaining Base-release Evidence

These remain initial-launch assurance gates even though DwC-A is disabled:

- fresh-catalog migration replay and every discovered pgTAP file, including
  default-off state, routine ACL/search-path/static validation, direct-insert
  denial, continuation absence, and cleanup-schedule presence;
- exact-release-SHA replay of complete Edge, tooling, formatting, lint, DTO,
  isolated-graph, web, and admin gates;
- the stable hosted `iOS Build and Test / Production readiness` result, proving
  the complete iOS unit-test target and unsigned Release archive from that same
  SHA, with the export presentation default off;
- production catalog checks for RLS, ACLs, empty definer `search_path`, gate
  trigger order, service-only grants, zero nonterminal jobs, zero live grants,
  absent continuation cron, and active archive-cleanup cron;
- real anon/publishable/authenticated/server-key negative smokes proving request
  `403 feature_unavailable`, worker `200`/`disabled`, and capability `410`;
- public-web canonical visibility and atomic-page production smokes;
- archive-cleanup, scan-deletion, account-deletion, ingestion, and media-health
  monitoring confirmation; and
- concurrent scan claim/recovery, failed-finalization, and interrupted-erasure
  production smoke.

The local machine used for the launch-isolation follow-up could not supply
fresh-catalog evidence: its installed Supabase CLI 2.90.0 rejects the newer
repository `local_smtp` configuration before connecting, and a newer CLI could
not be restored in the restricted network environment. This is explicitly
**unverified**, not a pass.

## Initial-launch Promotion Gate

The base release may promote only when every **Remaining Base-release Evidence**
item is attached to the same SHA and production still reports the canonical
DwC-A state as disabled. Active export maximum-shape, queue-throughput, R2
multipart, Resend, and positive capability-delivery tests do not block that
default-off promotion because no supported or old-client path can create or
process a job. A hidden button without the database/catalog evidence is not
equivalent.

## Later DwC-A Feature-enable Gate

Before changing the database singleton or Release iOS default, attach to one
feature-release SHA:

- all base-release evidence above;
- hosted maximum-shape snapshot/export measurements for duration, temporary
  bytes, memory, lock age, WAL, Edge CPU/memory/546 behavior, and latency;
- bounded backlog/fairness/stuck-watchdog load evidence at intended user scale;
- production R2 multipart/read/delete, Resend idempotency/error classification,
  pseudonym-key, capability expiry/revocation, and cleanup convergence smokes;
- healthy export-queue and archive-cleanup monitors with agreed alert ownership;
  and
- a reviewed forward migration that enables the singleton and restores the
  bounded continuation cron before a server-first smoke and later iOS enable.

Until that evidence exists, keep DwC-A intake/delivery disabled. Do not promote
the feature merely because focused unit/static suites are green.
