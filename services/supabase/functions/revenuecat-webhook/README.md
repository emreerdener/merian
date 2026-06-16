# RevenueCat Webhook

The purchase-event bridge for paid Merian Pro access. Configured directly in
the RevenueCat dashboard. When Apple processes a subscription renewal,
cancellation, upgrade, or verified non-renewing purchase, RevenueCat fires an
authenticated POST to this function. It maps standard subscription entitlement
changes to `users.subscription_tier`, and maps the detached
`merian_7_day_pass` product to a timed Pro grant via
`users.subscription_expires_at`.

The dynamic 7-day Pro trial is not stored as `users.subscription_tier = "pro"`.
Trial access is derived by `_shared/tierCache.ts` from the user
creation/first-seen window and reported to analytics as `plan = "pro_trial"`,
while paid subscription and active paid-pass webhook events report as
`plan = "pro_paid"`. Keep the RevenueCat product identifiers stable unless the
actual purchasable product changes.

## Architecture

To ensure the synchronous network request from RevenueCat completes instantly
while handling massive backend data moves, the module is strictly decoupled:

- **`index.ts`** The lightweight HTTP router. Strictly handles verifying the
  `REVENUECAT_WEBHOOK_SECRET`, identifying the `event.type`, updating the
  database bounds, and deferring the heavy payload replication into the Deno
  background queue.

- **`events.ts`** The deterministic event classifier. Exact
  `merian_7_day_pass` `NON_RENEWING_PURCHASE` events become timed Pro grants
  using `purchased_at_ms + 7 days`; unrelated non-renewing purchases are
  ignored. Standard auto-renewing events clear `subscription_expires_at`, and
  pass refund/cancellation-style events downgrade immediately.

- **`db.ts`** Contains isolated Postgres wrappers, specifically handling the
  idempotent upsert to ensure the user row exists and transitioning
  `subscription_tier` and `subscription_expires_at` cleanly.

- **`storage.ts`** Re-exports the shared `migrateUserStorage` engine from
  `_shared/storageMigration.ts`. When a user transitions tiers, this function
  silently duplicates all of their 12 MP image binaries from the active `free`
  Cloudflare R2 bucket over to the `pro` bucket line (or vice versa), and
  meticulously rewrites the `scans` table urls in PostgreSQL to match. The same
  helper is used by `expire-subscription-passes` so webhook downgrades and timed
  pass expiry share storage semantics.

## 7-Day Pass Contract

- Product ID: `merian_7_day_pass` (exact match only).
- Purchase source: RevenueCat `NON_RENEWING_PURCHASE`.
- Expiry source: `event.purchased_at_ms + 7 days`, stored in
  `users.subscription_expires_at`.
- Backend authority: `expire-subscription-passes` runs hourly and downgrades
  expired timed Pro rows to free, clearing `subscription_expires_at`.
- Fallback: `_shared/tierCache.ts` treats stale timed Pro rows as free if the
  expiry worker has not processed them yet.

## Testing

Run the deterministic webhook and pass-policy tests with:

```bash
deno test --allow-all \
  services/supabase/functions/_shared/subscriptionPass_test.ts \
  services/supabase/functions/revenuecat-webhook/events_test.ts \
  services/supabase/functions/revenuecat-webhook/index_test.ts
```
