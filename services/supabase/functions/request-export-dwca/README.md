# Request DwC-A Export

`request-export-dwca` is the authenticated, synchronous queue boundary for
Darwin Core Archive exports. It:

1. requires a permanent authenticated account and validates the bounded JSON
   request;
2. accepts only `personal` scope and a Boolean precision flag; `global` receives
   `403 global_export_forbidden` and requires an internal workflow;
3. rejects a successful/non-terminal export created in the preceding 24 hours;
4. inserts one canonical `pending` `export_jobs` row with the service client;
5. returns immediately while PostgreSQL wakes `export-dwca`; the hardened worker
   consumes only the job UUID and reloads canonical state.

Authenticated and anonymous database roles cannot insert `export_jobs` directly.
The partial unique index on non-terminal jobs closes the check-then-insert race;
a concurrent duplicate becomes the same public `429` contract. Failed jobs do
not consume the 24-hour success limit, so a user can retry after a
worker/configuration failure.

The queue row—not the webhook body—is authoritative for user ownership, scope,
coordinate policy, pseudonym key version, row/archive budgets, and current
durable phase. See `../export-dwca/README.md` for claim leases, persisted
cursors/chunk manifests, bounded assembly, delivery idempotency, and key
rotation.
