# Incident: Private cleanup receipt correlation

- **Date detected:** 2026-11-11
- **Status:** Correlation candidate deployed by successful1867; original-slot
  recovery and local acquisition-fence successor qualification pending
- **Affected version:** beta13dcc59a2 and preceding b6 backend
- **Affected surface:** Private evidence cleanup scheduler
- **Current contract:**
  [Worker owner](../../services/supabase/functions/erase-observation-evidence/README.md#prepared-operations-and-unknown-outcomes)

## Impact and detection

Read-only deployment preflight found the original cleanup request held unknown
although its HTTP200 response contained a valid all-zero terminal receipt. Its
response timestamp preceded dispatch by31.722ms. No private objects, histories,
pending erasure obligations or live claims were observed. This blocks enabling
full-flow phone qualification; no observed user-data loss is attributed to it.
Original identity and timestamps remain privately retained, outside artifacts.
HQ-334 tracks this defect. HQ-335 retains the earlier interval without observed
scheduled monitoring. Scheduled run3 at20:08UTC now failed correctly on unknown
dispatch and missing successful heartbeat, with zero pending objects. This
proves one scheduled observation, not a qualified ten-minute cadence; the prior
gap remains unexplained.

## November 11 approved rollout

The user approved exact7c838f47 deployment and one read-only prepromotion audit.
At23:27UTC that audit confirmed original request/time/project agreement, the
legacy NULL/unknown hold, exact518migration baseline and unchanged cron/cleanup
and other51closed gates. No objects, histories, pending erasures or live claims
were observed. The response was absent after its6-hour retention; absence does
not prove quiescence or successful recovery. The initial local audit parser
failure, strict timestamp correction,13synthetic tests and independent review
are retained in Completion366.

At that prepromotion checkpoint, non-force promotion and readback succeeded.
Deployment1867/run43120141285 was validating the exact candidate; production
completion had not yet been established. See the November12 completion below.
The original slot is preserved. Maintenance, activation and phone installation
remain separate and unexecuted. Automatic prompts remain paused.

## Root cause and reproduction

### November 11 — bounded legacy recovery inspection

The separately approved Completion368 inspection returned45 endpoint log
records, all HTTP200, and12 distinct execution-field values. Among4,586
PostgreSQL log records it found no matching pg_net-tagged error/start or
selected recovery message. These aggregate counts do not establish unique
deliveries or complete lifecycle coverage; generic worker errors can omit the
tag. No raw logs, headers, identifiers or scan data were retained. Engine
independently confirmed that the original hold cannot be cleared on this
evidence alone.

Pinned pg_net0.19.5 performs outbound HTTP before committing the transaction
containing queue deletion and response insertion. A transaction error can
restore the queued request after remote execution starts; a later successful
delivery does not prove the earlier delivery ended. This is a source-permitted
failure path, not evidence it occurred on beta. Graceful worker restart is
checked after commit and is not itself this abort path. The next recovery
decision must settle that concrete possibility without treating elapsed time or
aggregate success as proof. No additional deployment or cleanup maintenance was
performed.

### November 12 — local legacy acquisition fence under qualification

The aggregate inspection did not establish that every old delivery ended. The
local successor permanently denies the original three acquisition RPCs while
preserving their OIDs; new mandatory-dispatch service facades hold the singleton
lock through the existing retirement/claim owners. Original-token settlement
remains available after rotation or pause. This is local implementation, not
hosted recovery or activation.

A synthetic PostgreSQL probe demonstrated that an already-running old function
body can finish after replacement, even though later prepared calls are denied.
The operational cutover therefore also requires positive pre-cutoff transaction
drain with complete visibility and no outstanding old claims/effects. Elapsed
time, empty cleanup responses and migration success are insufficient.

The first new catalog run failed the existing privilege audit because the new
facades delegated caller authorization to a helper. Each now directly calls the
service-role guard as required; the helper defense and audit remain unchanged.
Corrected fresh replay and five focused catalogs pass154assertions. Four real
local database suites pass91cases, including both-order pause/rotation barriers,
same-dispatch serialization, independent locked-row skipping, token expiry and
reclaim, original settlement after closure and existing media retirement races.
At this earlier local checkpoint, Engine had reviewed the source and retained
results, while complete catalog, actual-routine/cache, PostgREST and exact
candidate evidence were pending and1867 was still running on7c. Later protocol
and deployment results are recorded below; original failures remain retained.
See the
[current cutover contract](../backend-and-data/06-supabase-deployment-runbook.md#local-legacy-acquisition-fence-successor-not-deployed).

### Timestamp defect

pg_net0.19.5 sets response `created` with `now()` (transaction start), which can
precede the caller's dispatch clock. The dispatcher incorrectly required a
response timestamp at or after dispatch. A transaction-local synthetic fixture
using the real dispatcher and real default reproduces a valid receipt left
unknown. It performs no network requests and rolls back all temporary objects.

Simply removing the lower timestamp bound is unsafe: pg_net's unlogged request
sequence may reset after recovery, while the logged pending slot survives.
PostgreSQL can recover without replacing its postmaster or catalog OIDs, so
neither numeric ID nor those identities alone prove correlation.

## Repository mitigation and compatibility

The forward migration adds a private nullable random dispatch UUID, committed
with the transport request ID. The service-only header selects a v2 terminal
receipt with matching UUID and six bounded counters. Exactly one response must
match. Missing, duplicate, wrong UUID, malformed or nonterminal responses hold
the original slot. Timestamp must remain finite and nonfuture, but represents
conservative transaction age, never freshened to observation time. Enqueue
collision rolls back the queued request and state update atomically.

Old scheduler/new worker retains the legacy response. New scheduler/old worker
holds rather than retrying. Legacy pending NULL UUID remains held, with no
invented correlation or automatic recovery. No client DTO or user API changes.

## Validation and review

Nineteen focused Deno tests passed, including invalid header rejection before
work, legacy/new shapes, terminal-only echo, and existing retirement/claim
limits. Initial error-cache assertion expected `no-store`; the shared error
boundary returns the stronger `private, no-store`, and the fixture was
corrected. The strengthened cleanup catalog passes66 assertions, including
otherwise-valid HTTP200 receipts with transport errors/timeouts, wrong UUID,
duplicates, missing responses, original NULL slots, paused reconciliation and
collision rollback. All125 deploy-time entrypoints and dependency graphs pass;
strict lint and migration/DTO contracts pass. Independent Engine review found no
blocking defect and verified the additional failure-precedence tests.

The first broader catalog run failed six fixtures (193files/9,770assertions)
because the runner placed a committed synthetic owners fixture before catalog
fixtures that require pristine configuration. That failure is retained; the
owned database was checked and disposed. The fresh catalog-before-owners run
passed all193files/11,620assertions; its cleanup fixture passed66. Full local
Edge retains36 database parent failures against the existing older local service
(3,842passed/1,180steps,532ignored); these are not waived by narrow cleanup
checks. Complete tooling repeated the previously recorded Gemini CLI
hidden-entry fixture failure; exact successor CI must still establish the
required gates in its runner environment. These statements do not qualify unrun
hosted or device behavior.

## Deployment, runtime and data recovery

### November 12 — deployment1867 completed; local recovery prerequisite

[Deployment1867](https://github.com/emreerdener/merian/actions/runs/43120141285)
completed successfully on exact7c. All six jobs, including production deployment
and existing workflow postconditions, passed. This is GitHub job/step evidence;
no additional hosted original-slot inspection or repair was performed. Do not
infer complete recovery or activation readiness from the successful workflow.

The local fence successor additionally passed12actual-routine and same-instance
PostgREST checks, including committed cutover, preserved original OIDs, warmed
service SQL calls denied, owner deny bodies and healthy new UUID-bound routes.
Engine reviewed source/results and migration hash. This reconstructs three
legacy routines on an empty local catalog; it is not a historical-schema replay
or proof of hosted quiescence. The companion and that owned database were
disposed. The earlier failed committed-fixture/catalog-order run was preserved
without deleting retained rows; the new full gate runs pristine catalogs first.
The rollback-only upgrade regression moved to its Deno fixture owner because
pg_prove does not mount sibling migration files; original mount failure remains
retained. Full verification and isolated candidate review remain open. No new
backend rollout, cleanup repair, activation or phone action occurred.

### November 11 — exact candidate CI535

[CI535](https://github.com/emreerdener/merian/actions/runs/43109008006) passed
all three jobs on `7c838f47b6e353a7d243758043a0ca99c6a24bc3`. Its exact
519-migration catalog passed191files/11,600assertions; complete Edge tests
passed4,408cases/1,182steps with no failures. Engine independently verified both
qualification archives,575combined source pins,18C1suites/301checks and
22handoff suites/1,043checks, including replay/disposal evidence and resource
limits. These are synthetic runner results, not hosted cleanup or device
qualification. The earlier local superset/failures and CI534 startup failures
remain historical evidence; this passing run does not establish their causes.

The deployment packet separately requests a bounded read-only original-state
audit. No reviewed exact-original legacy-slot repair operation is ready to
execute. Quiescence and durable-outcome proof, transactional preconditions,
synthetic failure tests, independent review and explicit maintenance approval
remain required before clearing the slot. The migration itself preserves it.

**Earlier checkpoint before1867 completed.** Deployment1866 had succeeded for
the preceding cancellation fix. Its readback preserved the original held slot.
No request replayed, cleared, rebound or age-reset; no response rewritten or TTL
changed. Explicit original-receipt maintenance remains separate from deploying
this fix. A missing response after retention expiry is not authority to clear
the slot.

## Exit criteria

- [x] Original timestamp defect reproduced; crash-ID risk independently traced.
- [x] Exact implementation reviewed and all affected candidate gates pass.
- [x] Correlation successor7c deployment workflow completed successfully.
- [ ] Local acquisition-fence successor fully qualified and separately released.
- [ ] Original held slot reconciled under separately approved maintenance.
- [ ] Recurring monitoring and actual-byte cleanup qualification verified.
- [ ] Phone full-flow testing completed with preserved user data.

This record contains only sanitized aggregate evidence and synthetic behavior;
no credentials, user records, transport identifiers or production bodies.
