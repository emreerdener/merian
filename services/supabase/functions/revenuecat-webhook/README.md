# RevenueCat Webhook

The purchase-event bridge for paid Naturebook Pro access. Configured directly in
the RevenueCat dashboard. When Apple processes a subscription renewal,
cancellation, upgrade, or verified non-renewing purchase, RevenueCat fires an
authenticated POST to this function. It maps standard subscription entitlement
changes to `users.subscription_tier`, and maps the detached
`pro_week` product to a timed Pro grant via `users.subscription_expires_at`.

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

- **`events.ts`** The deterministic event classifier. Exact `pro_week`
  `NON_RENEWING_PURCHASE` events become timed Pro grants
  using `purchased_at_ms + 7 days`; unrelated non-renewing purchases are
  ignored. Standard auto-renewing events clear `subscription_expires_at`, and
  pass refund/cancellation-style events downgrade immediately.

- **`db.ts`** Contains isolated Postgres wrappers, specifically handling the
  idempotent upsert to ensure the user row exists and transitioning
  `subscription_tier` and `subscription_expires_at` cleanly.

- Tier transitions do not copy existing scan media between R2 prefixes. Both
  `public_uploads/free/` and `public_uploads/pro/` are durable scan-media
  prefixes, so the webhook only updates subscription state and the in-process
  tier cache.

## 7-Day Pass Contract

- Product ID: `pro_week` (exact match only).
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
deno test --config services/supabase/functions/deno.json --allow-all \
  services/supabase/functions/_shared/subscriptionPass_test.ts \
  services/supabase/functions/revenuecat-webhook/events_test.ts \
  services/supabase/functions/revenuecat-webhook/index_test.ts
```
