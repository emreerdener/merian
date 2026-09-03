# Request DwC-A Export

`request-export-dwca` is the authenticated, synchronous queue boundary for
Darwin Core Archive exports. It remains deployed as a stable fail-closed
boundary for old clients, but exports are disabled for the initial launch by the
canonical private database state installed in
`20260728133835_disable_dwca_exports_for_launch.sql`. A valid request currently
receives `403 feature_unavailable`; no queue row or source snapshot is created.
The iOS Release UI is hidden independently.

When the release gate is enabled through a reviewed migration, the route:

1. requires a permanent authenticated account and validates the bounded JSON
   request;
2. accepts only `personal` scope and a Boolean precision flag; `global` receives
   `403 global_export_forbidden` and requires an internal workflow;
3. calls the service-only `request_dwca_export_job(...)` RPC, which takes a
   per-user transaction advisory lock and atomically checks release state, the
   preceding 24-hour successful/non-terminal window, and queue insertion;
4. maps `disabled`, `rate_limited`, `already_pending`, and `queued` to stable
   public behavior;
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
A default-off BEFORE INSERT trigger also rejects old Edge bundles and unexpected
direct service-role insertion. The partial unique index on non-terminal jobs is
a final duplicate fence; the RPC reports only that exact index as
`already_pending` and rethrows unrelated uniqueness failures. Failed jobs do not
consume the 24-hour success limit, so a user can retry after a
worker/configuration failure once the feature is enabled.

Snapshot construction and final eligibility validation are implemented.
Fresh-catalog and negative production gate evidence still apply to the base
release. Hosted maximum-shape generation/delivery evidence is deferred to the
separate feature-enable checklist in the
[release assurance record](../../../../docs/backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md).

The queue row—not the webhook body—is authoritative for user ownership, scope,
coordinate policy, pseudonym key version, row/archive budgets, and current
durable phase. See `../export-dwca/README.md` for claim leases, persisted
cursors/chunk manifests, bounded assembly, delivery idempotency, and key
rotation.

## Native Caller And Verification

The iOS `Core/Network/Endpoints/MerianNetworkClient+Exports.swift` extension
owns `requestDwcAExport`: request construction, the existing 15-second deadline,
and ignored success-body semantics. Settings Services/ViewModels retain export
interaction state and error presentation. The endpoint forwards the caller's
scope unchanged; native raw-scope transport tests do not make non-personal
scopes valid server requests or enable the release gate.

See the
[canonical API contract](../../../../docs/backend-and-data/05-api-contracts.md#deno-request-export-dwca-edge-node),
[Settings ownership](../../../../apps/ios/Merian/Features/Profile/Settings/README.md),
and the
[native focused matrix](../../../../apps/ios/Merian/Core/Network/README.md#enrichment-export-and-feedback-verification)
for the unchanged intake contract and its endpoint coverage.
