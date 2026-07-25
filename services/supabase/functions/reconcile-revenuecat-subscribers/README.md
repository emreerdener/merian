# RevenueCat Subscriber Reconciler

Scheduled service-only repair for authoritative RevenueCat CustomerInfo. This
worker closes the gap left when a webhook exhausts retries or never arrives; it
is not a browser or iOS API.

## Contract

- `config.toml` sets `verify_jwt = false` only so `pg_net` can reach the
  function. The handler accepts `POST` and timing-safely compares the complete
  `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` value.
- `claim_revenuecat_reconciliations(10)` leases due private queue rows for two
  minutes with `FOR UPDATE SKIP LOCKED`.
- At most three RevenueCat `GET /v1/subscribers/{app_user_id}` requests run
  concurrently. They use `REVENUECAT_SECRET_API_KEY`, a ten-second deadline, and
  a 2 MiB streamed response ceiling.
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
installs `reconcile_revenuecat_subscribers_every_fifteen_minutes`. Anonymous
accounts are excluded until identity upgrade.

Alert when `last_error_code` or `attempt_count` grows, when due rows remain
unclaimed, or when `last_reconciled_at` is older than the expected six/24-hour
cadence. Fix provider/database configuration and allow the durable queue to
retry; do not grant table access or directly edit tiers.

Unit coverage lives in `worker_test.ts`. Migration source contracts and
executable ordering, lease, ACL, and isolation coverage live in
`functions/_tests/revenueCatWebhookMigrationContract.test.ts` and
`tests/revenuecat_webhook_security.sql`.
