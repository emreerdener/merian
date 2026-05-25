# RevenueCat Webhook

The single source of truth for paid Merian Pro subscription state. Configured
directly in the RevenueCat dashboard. When Apple processes a subscription
renewal, cancellation, or upgrade, RevenueCat fires an authenticated POST to
this function. It maps paid entitlement changes directly to the user's
`subscription_tier` in Postgres, ensuring the Edge caching ecosystem instantly
recognizes paid access.

The dynamic 7-day Pro trial is not stored as `users.subscription_tier = "pro"`.
Trial access is derived by `_shared/tierCache.ts` from the user
creation/first-seen window and reported to analytics as `plan = "pro_trial"`,
while paid subscription webhook events report as `plan = "pro_paid"`. Keep the
RevenueCat entitlement/product identifiers stable unless the actual purchasable
product changes.

## Architecture

To ensure the synchronous network request from RevenueCat completes instantly
while handling massive backend data moves, the module is strictly decoupled:

- **`index.ts`** The lightweight HTTP router. Strictly handles verifying the
  `REVENUECAT_WEBHOOK_SECRET`, identifying the `event.type`, updating the
  database bounds, and deferring the heavy payload replication into the Deno
  background queue.

- **`db.ts`** Contains isolated Postgres wrappers, specifically handling the
  idempotent upsert to ensure the user row exists and transitioning
  `subscription_tier` cleanly.

- **`storage.ts`** Contains the highly-complex `migrateUserStorage` engine. When
  a user transitions tiers, this function silently duplicates all of their 12 MP
  image binaries from the active `free` Cloudflare R2 bucket over to the `pro`
  bucket line (or vice versa), and meticulously rewrites the `scans` table urls
  in PostgreSQL to match. Runs concurrently using `Promise.allSettled` to
  prevent single-blob timeout failure.
