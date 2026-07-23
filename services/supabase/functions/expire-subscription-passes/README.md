# Expire Subscription Passes

Hourly service-role worker that expires Merian-owned timed Pro grants.

The 7-day Pro pass is a detached RevenueCat non-renewing purchase, not a
RevenueCat entitlement. The signed RevenueCat webhook fetches authoritative
CustomerInfo, derives an unexpired exact `pro_week` transaction from
`subscriber.non_subscriptions`, and writes `users.subscription_tier = 'pro'`
plus `users.subscription_expires_at` through the service-only ordered
transaction. It never grants the pass from webhook event fields alone.

Time passing does not necessarily produce another provider event at the exact
pass boundary. This worker is therefore the bounded repair path that turns an
already-expired timed row back into stored free state. Server entitlement and
quota resolution treat an expired timed row as free even before this repair
runs.

## Flow

1. `pg_cron` invokes `/functions/v1/expire-subscription-passes` hourly.
2. The function authenticates with the service-role bearer token.
3. It selects users where `subscription_tier = 'pro'` and
   `subscription_expires_at <= now()`.
4. Each candidate receives a conditional update that repeats the tier,
   non-null-expiry, and boundary predicates. A concurrent authoritative renewal
   that clears or extends the expiry therefore wins instead of being
   overwritten by a stale worker page.
5. A successful downgrade sets `subscription_tier = 'free'` and
   `subscription_expires_at = null`; the existing database trigger advances
   `users.entitlement_version`. The worker does not synthesize a RevenueCat
   event or alter the provider ordering ledger.
6. Existing scan media remains in place; both `public_uploads/free/` and
   `public_uploads/pro/` are durable scan-media prefixes.

Standard auto-renewing Pro subscriptions leave `subscription_expires_at = null`,
so they are ignored by this worker.

## Testing

Run the worker and guarded database-query tests with:

```bash
deno test --frozen \
  --config services/supabase/functions/deno.json \
  services/supabase/functions/expire-subscription-passes/db_test.ts \
  services/supabase/functions/expire-subscription-passes/worker_test.ts
```

The authoritative webhook, event ordering, and deployment-secret contract is
documented in
[`../revenuecat-webhook/README.md`](../revenuecat-webhook/README.md).
