# Expire Subscription Passes

Hourly service-role worker that expires Merian-owned timed Pro grants.

The 7-day Pro pass is a detached RevenueCat non-renewing purchase, not a
RevenueCat entitlement. The RevenueCat webhook writes
`users.subscription_tier = 'pro'` plus `users.subscription_expires_at` when it
receives an exact `merian_7_day_pass` purchase. This worker is the durable
backend authority that turns those timed grants back into free accounts.

## Flow

1. `pg_cron` invokes `/functions/v1/expire-subscription-passes` hourly.
2. The function authenticates with the service-role bearer token.
3. It selects users where `subscription_tier = 'pro'` and
   `subscription_expires_at <= now()`.
4. Each matching row is downgraded to `subscription_tier = 'free'` and
   `subscription_expires_at = null`.
5. Existing scan media remains in place; both `public_uploads/free/` and
   `public_uploads/pro/` are durable scan-media prefixes.

Standard auto-renewing Pro subscriptions leave `subscription_expires_at = null`,
so they are ignored by this worker.

## Testing

Run the worker and guarded database-query tests with:

```bash
deno test --allow-all \
  services/supabase/functions/expire-subscription-passes/db_test.ts \
  services/supabase/functions/expire-subscription-passes/worker_test.ts
```
