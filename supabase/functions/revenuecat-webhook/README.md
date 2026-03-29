# RevenueCat Webhook

The single source of truth for Merian Pro subscription state.
Configured directly in the RevenueCat dashboard. When Apple processes a subscription renewal, cancellation, or upgrade, RevenueCat fires an authenticated POST to this function. It maps the change directly to the user's `subscription_tier` in Postgres, ensuring the Edge caching ecosystem instantly recognizes tier access.
