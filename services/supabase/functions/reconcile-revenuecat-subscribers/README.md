# RevenueCat Subscriber Reconciler

Scheduled service-only repair for authoritative RevenueCat CustomerInfo. This
worker closes the gap left when a webhook exhausts retries or never arrives; it
is not a browser or iOS API.

## Contract

- `config.toml` sets `verify_jwt = false` only so `pg_net` can reach the
  function. The handler accepts `POST` and timing-safely compares the complete
  `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` value.
- Each claim RPC leases one six-row private queue wave for two minutes with
  `FOR UPDATE SKIP LOCKED`. The worker keeps claiming small waves until the
  queue is empty or its monotonic start-work cutoff is reached; there is no
  fixed per-invocation record ceiling.
- At most three RevenueCat `GET /v1/subscribers/{app_user_id}` requests run
  concurrently. They use `REVENUECAT_SECRET_API_KEY`, a ten-second deadline, and
  a 2 MiB streamed response ceiling.
- The invocation budget is 90 seconds. New claim waves stop after 60 seconds,
  reserving 30 seconds for the final bounded provider wave, database writes, and
  queue-health read. The cron dispatch uses a 120-second `pg_net` response
  timeout.
- `apply_revenuecat_reconciliation(...)` changes access only for a strictly
  newer authoritative `request_date_ms` while holding the queue, user, and
  customer-watermark locks. Every write is claim-fenced.
- Successful Pro rows are due again in six hours; free rows in 24 hours.
  Failures release their claim with durable bounded backoff.
- Periodic repair cannot restore a historical refunded detached `pro_week`
  purchase over a free/refunded customer watermark. Webhook event context owns
  that revocation decision.

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
until identity upgrade.

The independent `.github/workflows/revenuecat-reconciliation-health-monitor.yml`
check runs every 15 minutes. It fails by default when the oldest
unclaimed/expired due row is at least 30 minutes old or any lease has expired,
and marks 60 minutes as critical. It writes JSON and Markdown artifacts without
exposing subscriber identities. A failed RPC or network check also fails the
monitor.

For an alert, inspect the worker's structured `revenuecat_reconciliation_health`
event and the queue's bounded `last_error_code`/attempt state with the
owner-only runbook query. Fix provider/database configuration and allow the
claim-fenced queue to retry; do not grant table access or directly edit tiers.

Unit coverage lives in `db_test.ts`, `worker_test.ts`, and
`services/supabase/scripts/monitor_revenuecat_reconciliation_test.ts`. Migration
source contracts and executable ordering, lease reclamation, index, health, ACL,
and isolation coverage live in
`functions/_tests/revenueCatWebhookMigrationContract.test.ts` and
`tests/revenuecat_webhook_security.sql`.
