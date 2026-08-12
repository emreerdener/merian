# RevenueCat Subscriber Reconciler

Scheduled service-only repair for authoritative RevenueCat CustomerInfo. This
worker closes the gap left when a webhook exhausts retries or never arrives; it
is not a browser or iOS API.

## Contract

- `config.toml` sets `verify_jwt = false` only so `pg_net` can reach the
  function. The handler accepts `POST` and timing-safely compares one exact
  platform-managed server key. Opaque keys use `apikey` only; legacy
  service-role JWTs use matching `apikey` and Bearer headers.
- Each claim RPC leases at most three rows per identity lane for two minutes
  with `FOR UPDATE SKIP LOCKED`. A combined legacy-plus-principal wave is
  therefore capped at six provider lookups. The worker keeps claiming small
  waves until the queue is empty or its monotonic start-work cutoff is reached;
  there is no fixed per-invocation record ceiling.
- The invocation drains two purpose-specific queues: legacy rows keyed by a
  Supabase user UUID and stable rows keyed by a purchase-principal UUID. Stable
  lookup IDs are immutable server-owned values; they are never canonicalized as
  Auth UUIDs or used directly as account IDs.
- At most three RevenueCat `GET /v1/subscribers/{app_user_id}` requests run
  concurrently. They use `REVENUECAT_SECRET_API_KEY`, a ten-second deadline, and
  a 2 MiB streamed response ceiling.
- RevenueCat's GET is a get-or-create operation and App User IDs are
  case-sensitive. Migration
  `20260809055035_canonicalize_revenuecat_app_user_ids.sql` makes the uppercase
  Supabase UUID canonical for new-user enqueue and ghost-merge repair, and
  normalizes only queue values that are provably the same UUID. Emails, aliases,
  `$RCAnonymousID` values, and other provider IDs remain unchanged.
- The invocation budget is 90 seconds. New claim waves stop after 60 seconds,
  reserving 30 seconds for the final bounded provider wave, database writes, and
  queue-health read. The cron dispatch uses a 120-second `pg_net` response
  timeout.
- `apply_revenuecat_reconciliation(...)` and
  `apply_purchase_principal_reconciliation(...)` change their respective input
  state only for a strictly newer authoritative `request_date_ms` while holding
  the queue, user, and customer-watermark locks. Every write is claim-fenced.
  CustomerInfo must be no more than 15 minutes old and no more than five minutes
  in the future; an out-of-window response is failed and retried without
  changing either entitlement lane.
- A principal claim removes at most 100 unbound, state-free `pending` principals
  with no activity for 24 hours. Each begin attempt refreshes the activity time
  under the principal lock, so cleanup cannot delete a live retry between begin
  and completion. Those abandoned preparations never mutated RevenueCat and
  cannot reserve an identity or alert forever after a lost installation.
- Successful Pro rows are due again in six hours; free rows in 24 hours.
  Failures release their claim with durable bounded backoff.
- Periodic repair cannot restore a historical refunded detached `pro_week`
  purchase over a free/refunded customer watermark. Each stable-principal claim
  carries a durable pass-policy flag. Signed webhook purchase evidence may
  enable it; a transfer destination can inherit it only from a resolved stable
  source whose policy is already enabled and only after the destination snapshot
  shows an active App Store pass. Refund/revocation/source evidence disables it,
  and unrelated events plus reconciliation preserve it rather than deriving
  policy from retained CustomerInfo history.

The projected Pro/free labels in this worker refer only to RevenueCat-backed Pro
state. The legacy `pro_paid` policy name includes store trials and approved
promotions and is not proof that money changed hands. Reconciliation does not
edit complimentary usage or infer access from the complimentary ledger.
Effective access may fall through from a non-Pro provider snapshot to an
existing complimentary credit or hold. The joined entitlement contract is
[Three Complimentary Pro Scans](../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

The queue has RLS enabled and no direct API-role or service-role table grants.
All state-machine RPCs use an empty fixed `search_path`, call
`internal.require_service_role()`, and are explicitly executable only by
`service_role`.

## Schedule and operations

Migration `20260725052338_reconcile_revenuecat_subscribers.sql` seeds every
identified account, schedules identities observed by accepted webhooks, and
installs `reconcile_revenuecat_subscribers_every_fifteen_minutes`. Migration
`20260726031502_scale_revenuecat_reconciliation.sql` adds the claimed-row
expiration index, deadline-draining cron timeout, and service-only
`get_revenuecat_reconciliation_health()` RPC. Anonymous accounts are excluded
until identity upgrade. Migration
`20260809055035_canonicalize_revenuecat_app_user_ids.sql` aligns PostgreSQL with
the case-sensitive iOS customer ID and invalidates any claimed lowercase UUID
lookup before making it immediately due. Migration
`20260812144948_introduce_stable_purchase_principals.sql` adds the separate
stable-principal queue and service-only claim/apply/fail/health RPCs. The same
worker drains both queues with independent claims and uses stable-first identity
resolution. `account_grant_mode = authoritative` causes provider promo records
to remain evidence-only; only the private account-grant ledger can then
contribute that access.

The independent `.github/workflows/revenuecat-reconciliation-health-monitor.yml`
check runs every 15 minutes and reads both aggregate health RPCs. It fails by
default when the oldest unclaimed/expired due row, pending sign-out handoff, or
pending purchase principal is at least 30 minutes old, when any lease has
expired, or when an active principal with current StoreKit access has no Auth
binding; 60 minutes is critical. It writes JSON and Markdown artifacts without
exposing subscriber, handoff, source, or destination identities. A failed RPC or
network check also fails the monitor. Sign-out telemetry counts unexpired
prepared proofs and every bound proof; expired unbound bearer capabilities are
terminal and do not alert forever.

For an alert, inspect the worker's structured `revenuecat_reconciliation_health`
event and the queue's bounded `last_error_code`/attempt state with the
owner-only runbook query. Fix provider/database configuration and allow the
claim-fenced queue to retry; do not grant table access or directly edit tiers.

For beta migration and customer-count investigation, use the offline
`audit_revenuecat_customers.ts` export comparison and the dry-run-first
`grant_revenuecat_beta_entitlements.ts` workflow documented in the deployment
runbook. Never delete RevenueCat customer history as a reconciliation strategy;
the separately authorized empty-shell cleanup can delete only a live-revalidated
customer proven to have no such history and never writes this queue or Supabase.
Promotional grants emit production `NON_RENEWING_PURCHASE` webhooks; the normal
webhook/reconciliation path remains the only tier writer.

The grant workflow is currently production-held and may be used only in dry-run
mode. Its GET path must accept both successful CustomerInfo statuses (`200`
found and `201` created), and beta membership must come from an explicit
reviewed UUID cohort rather than current `subscription_tier`. The canonical
migration makes normalized rows immediately due, so a future apply must pause
only this named reconciler during the bounded migration/grant window, then
restore its exact schedule and prove queue health. The full hold and exit
criteria are in the
[RevenueCat customer identity incident](../../../../docs/incidents/2026-08-revenuecat-customer-identity-drift.md).

Unit coverage lives in `db_test.ts`, `worker_test.ts`, and
`services/supabase/scripts/monitor_revenuecat_reconciliation_test.ts`. Migration
source contracts and executable ordering, lease reclamation, index, health, ACL,
and isolation coverage live in
`functions/_tests/revenueCatWebhookMigrationContract.test.ts` and
`tests/revenuecat_webhook_security.sql`.
