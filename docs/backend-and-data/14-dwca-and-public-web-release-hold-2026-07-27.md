# DwC-A and Public Web Release Assurance — 2026-07-27

Status: **IMPLEMENTED; BLOCK production promotion until exact-release-SHA
catalog and hosted-load evidence passes.**

Base reviewed implementation: `7b74289c3aaeb9f814088c4981bac715b46fae51`.

Remediation is implemented in forward migration
`20260728001723_repair_dwca_privacy_visibility_and_snapshot_work.sql` and its
paired Edge/web changes. This record remains the source of truth for deploying
and verifying that release unit. It does not replace the deployment runbook or
API contracts.

## Scope

The release unit contains:

- the immutable DwC-A source snapshot and resumable export worker;
- `request-export-dwca` and `export-dwca`;
- the server-only public-web Explore card/detail boundary; and
- `apps/web` when it consumes that boundary.

## Current Platform Assumptions

This release does not rely on a project's automatic Data API grants. Supabase
is making new-project exposure opt-in, while existing projects can retain
automatic privileges. The migration therefore revokes exact function execution
from `PUBLIC`, `anon`, and `authenticated`, then grants only the required
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
- An uploaded or staged archive is deleted when a source mismatch wins a race.
  Resend remains idempotent by job ID.
- If privacy changes after the final pre-provider check while Resend is already
  accepting the request, completion still repeats the fence, rejects the job,
  and deletes the archive. The email can exist, but its direct signed object is
  revoked rather than being published as a completed export.
- A processing job never exposes its staged signed URL through user-readable
  `public.export_jobs`. Staging stores the URL in
  `internal.export_job_work.delivery_file_url`; the final transaction copies it
  into the public job and marks the job completed only after the full fence.
  Every terminal transition also erases the private staged capability.

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

## Regression Evidence

Focused Deno coverage currently proves:

- early-member tombstoning after final paging is rejected before assembly;
- a source change during upload is rejected at staging and deletes the object;
- a source change before delivery, including after recipient lookup, sends no
  email and deletes the staged object;
- a source change while the email provider call is in flight fails completion,
  deletes the archive, and does not retry the idempotent provider call;
- SQLSTATE `55001` maps to terminal `source_snapshot_changed`;
- signed URLs stay private while a job is processing;
- direct hidden Explore detail and the atomic page routine return no row;
- the catalog owner can transition a fixture to moderated while
  `service_role`, which has no direct source-table write privilege, observes
  exclusion through only the granted RPCs;
- public API roles cannot execute either public-web routine; and
- oversized maximum-cardinality DTO sources stop at the aggregate sentinel
  without retaining partial source rows.

Local validation in the remediation working tree passed:

- 59 focused DwC-A/public-web TypeScript tests;
- the complete Edge Function suite: 1,166 tests, zero failures;
- the complete Supabase tooling gate, including its 89 standard tests, 16 DTO
  validator tests, 10 executable Identify contract tests, shell tests, and
  database-catalog discovery;
- whole-tree Supabase formatting and lint;
- all 86 function-specific Deno configuration checks and all 86 isolated
  dependency graphs across 272 runtime files; and
- the four changed public-web Supabase-boundary tests.

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
then re-enters `service_role` only to call the narrow RPCs. No table privilege is
added. This failed attempt is useful negative evidence, but it is not a pass;
the corrected test and all nineteen catalog files still require exact-SHA CI
replay.

## Remaining Release Evidence

These are assurance gates, not unresolved design work:

- fresh-catalog migration replay and pgTAP using the repository-pinned Supabase
  CLI;
- exact-release-SHA replay of the complete Edge, tooling, formatting, lint,
  isolated-graph, and web gates;
- hosted maximum-shape PostgreSQL measurements for duration, temporary bytes,
  memory pressure, lock age, and WAL;
- production catalog checks for RLS, ACLs, empty definer `search_path`, trigger
  installation, and service-only grants;
- real anon, publishable, authenticated, and server-key negative/positive smoke
  tests; and
- queue/invalidation/staged-object monitoring confirmation.

The local machine used for this remediation could not supply fresh-catalog
evidence: its installed CLI cannot parse the newer repository configuration, and
Docker access is unavailable. This is explicitly **unverified**, not a pass.

## Promotion Gate

Remove the production hold only when all of the following are attached to the
same release SHA:

- fresh-catalog migrations and all DwC-A/public-web pgTAP files pass;
- complete Deno, dependency, tooling, format, lint, DTO, and isolated-function
  graph checks pass;
- web frozen install, audit, test, type-check, and production build pass;
- hosted maximum-shape snapshot/export measurements remain inside agreed
  database, Edge CPU/memory, R2, and latency budgets;
- production catalog and credential smoke matrices match the contracts above;
  and
- operational monitors are enabled and healthy.

Until that evidence exists, do not enable new DwC-A intake/delivery or promote
the paired public-web release merely because focused unit/static suites are
green.
