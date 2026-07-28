# Request DwC-A Export

`request-export-dwca` is the authenticated, synchronous queue boundary for
Darwin Core Archive exports. It:

1. requires a permanent authenticated account and validates the bounded JSON
   request;
2. accepts only `personal` scope and a Boolean precision flag; `global` receives
   `403 global_export_forbidden` and requires an internal workflow;
3. rejects a successful/non-terminal export created in the preceding 24 hours;
4. inserts one canonical `pending` `export_jobs` row with the service client;
5. synchronously invokes the job-insert source-snapshot trigger before commit;
   and
6. returns after commit while PostgreSQL wakes `export-dwca`; the hardened
   worker consumes only the job UUID and reloads canonical state.

Snapshot version 2 freezes both phase DTOs consistently. The trigger counts only
UUIDs through the row lookahead, then projects, measures, and inserts one DTO at
a time through a parameterized lateral cursor. It stops at the first per-row or
cumulative source-byte violation, removes partial source rows, and records only
the canonical budget-plus-one sentinel for an oversized source.

Authenticated and anonymous database roles cannot insert `export_jobs` directly.
The partial unique index on non-terminal jobs closes the check-then-insert race;
a concurrent duplicate becomes the same public `429` contract. Failed jobs do
not consume the 24-hour success limit, so a user can retry after a
worker/configuration failure.

Snapshot construction and final eligibility validation are implemented.
Production promotion remains held for exact-SHA fresh-catalog, complete CI,
production smoke, and hosted maximum-shape evidence in the
[release assurance record](../../../../docs/backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md).

The queue row—not the webhook body—is authoritative for user ownership, scope,
coordinate policy, pseudonym key version, row/archive budgets, and current
durable phase. See `../export-dwca/README.md` for claim leases, persisted
cursors/chunk manifests, bounded assembly, delivery idempotency, and key
rotation.
