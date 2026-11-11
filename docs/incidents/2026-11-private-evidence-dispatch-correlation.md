# Incident: Private cleanup receipt correlation

- **Date detected:** 2026-11-11
- **Status:** Reproduced; local mitigation and validation in progress
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

## Root cause and reproduction

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

**Not performed for this correction.** Deployment1866 succeeded for the earlier
cancellation fix. Its readback preserved the original held slot. No request
replayed, cleared, rebound or age-reset; no response rewritten or TTL changed.
Explicit original-receipt maintenance remains separate from deploying this fix.
A missing response after retention expiry is not authority to clear the slot.

## Exit criteria

- [x] Original timestamp defect reproduced; crash-ID risk independently traced.
- [ ] Exact implementation reviewed and all affected candidate gates pass.
- [ ] Exact successor deployment authorized and verified.
- [ ] Original held slot reconciled under separately approved maintenance.
- [ ] Recurring monitoring and actual-byte cleanup qualification verified.
- [ ] Phone full-flow testing completed with preserved user data.

This record contains only sanitized aggregate evidence and synthetic behavior;
no credentials, user records, transport identifiers or production bodies.
