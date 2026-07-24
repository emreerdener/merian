# RevenueCat Webhook

The server-owned purchase synchronization boundary for Naturebook Pro. The
endpoint treats a RevenueCat webhook as a signed synchronization signal, not as
entitlement truth: every new accepted event causes a fresh server-to-server
CustomerInfo lookup before one transactional database routine may change a
user's tier. RevenueCat `TRANSFER` reconciles both the source and destination
before one atomic write. A durable duplicate receipt is the only lookup bypass
for an event that maps to a Merian user.

Existing scan media never moves when a tier changes. Both `public_uploads/free/`
and `public_uploads/pro/` are durable prefixes.

## Security and processing order

`config.toml` sets `verify_jwt = false` because RevenueCat is not a Supabase JWT
caller. The handler replaces that gateway check with two independent
server-to-server credentials:

1. Constant-time comparison of
   `Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>`.
2. Verification of `X-RevenueCat-Webhook-Signature` using
   `REVENUECAT_WEBHOOK_SIGNING_SECRET`.

The signature has the form `t=<unix-seconds>,v1=<sha256-hex>`. Its HMAC-SHA256
input is the exact UTF-8 value `<t>.<raw-request-body>`. The handler reads the
bounded raw body, verifies the signature before JSON parsing, uses a five-minute
past/future replay window, and compares digests in constant time. Do not parse,
normalize, or reserialize the body before verification.

After ingress verification, the handler:

1. Requires a bounded `event.id`, `event.event_timestamp_ms`, and event type. An
   event timestamp more than five minutes ahead of the signed delivery timestamp
   is rejected so it cannot poison the ordering watermark.
2. Resolves ordered Supabase UUID candidates from `app_user_id`,
   `original_app_user_id`, and `aliases`. A `TRANSFER` event has no
   `app_user_id`; its `transferred_from` and `transferred_to` arrays become
   independent source/destination subjects. Purely anonymous or otherwise
   unmappable events are written to the durable ledger as `ignored` without a
   provider lookup; a later alias event carries its own durable event ID.
3. Checks the private event ledger through a service-only read RPC. A committed
   duplicate with the same event timestamp, type, and payload SHA-256 returns
   immediately, preventing at-least-once retries or a captured in-window replay
   from amplifying RevenueCat API traffic. Reuse with different immutable data
   is a conflict.
4. Calls RevenueCat `GET /v1/subscribers/{app_user_id}` with
   `REVENUECAT_SECRET_API_KEY` for every mapped customer. Both sides of a
   transfer are fetched concurrently, and either lookup failing prevents both
   database changes.
5. Derives standard Pro from the active `pro` or `Naturalist Tier` entitlement.
   The detached `pro_week` purchase remains a seven-day timed grant derived from
   authoritative non-subscription transactions; a matching refund/revocation
   removes the affected transaction and fails closed if identifiers cannot be
   matched. Future-dated pass purchases and future-dated CustomerInfo snapshots
   also fail closed.
6. Calls `public.apply_revenuecat_customer_state(...)` once with zero, one, or
   two authoritative subjects.

An API timeout, rate limit, malformed CustomerInfo response, missing current or
destination public profile, ambiguous mapping to multiple live Merian UUIDs, or
database error returns a non-2xx response so RevenueCat retries. A transfer
source whose account was already deleted is safely omitted so it cannot block
the live destination. No failure becomes a free or Pro write by inference.

## Idempotency and monotonic ordering

Migration `20260723201500_secure_revenuecat_webhook_delivery.sql` owns the write
boundary:

- `internal.revenuecat_webhook_events` stores one immutable row per RevenueCat
  event ID under a primary-key constraint. It retains event metadata and a
  SHA-256 payload digest, not the raw body.
- `internal.revenuecat_webhook_event_subjects` stores each resolved user's
  authoritative snapshot, projected state, outcome, and entitlement version. A
  normal event has one subject; a transfer can have source and destination
  subjects under the same event ID.
- `internal.revenuecat_customer_state` stores the per-user ordering watermark.
- `public.get_revenuecat_webhook_event_result(...)` provides a service-only
  committed-receipt lookup, and `public.apply_revenuecat_customer_state(...)`
  owns the mutation. Both use `SECURITY DEFINER SET search_path = ''`, call
  `internal.require_service_role()`, and are executable only by `service_role`.
  All three internal tables have RLS enabled and no direct API-role or
  service-role table grants.

The transaction requires each RevenueCat customer to map to exactly one live
`public.users` row, locks all resolved UUIDs in sorted order, deduplicates the
event ID, and commits all subjects together. A missing normal or
transfer-destination user fails retryably. A missing transfer source has no
remaining Merian entitlement to revoke and is omitted.

Each resolved subject compares this tuple independently:

1. `event_timestamp_ms`
2. authoritative CustomerInfo `request_date_ms`
3. event ID as a deterministic final tie-breaker

Only a newer tuple can update `subscription_tier` and `subscription_expires_at`.
The existing user trigger advances `entitlement_version` only when those values
actually change. A duplicate returns `duplicate`; an event with no Merian
subject returns `ignored`; an older delivery returns `stale`; a transfer whose
subjects have different ordering outcomes returns `mixed`. None can overwrite a
newer per-user state. Source/destination transfer changes commit together.

Auth owns public-user creation. The webhook never inserts or upserts a user.

## Secrets and RevenueCat dashboard setup

The GitHub `Production` environment must contain:

- `REVENUECAT_WEBHOOK_SECRET`: at least 32 random characters; configure the
  webhook's Authorization header in RevenueCat as `Bearer <that value>`.
- `REVENUECAT_WEBHOOK_SIGNING_SECRET`: the signing secret shown by RevenueCat
  when HMAC signing is enabled.
- `REVENUECAT_SECRET_API_KEY`: a secret server API key authorized to read this
  RevenueCat project. It must begin with `sk_`; never use a public iOS, Android,
  Amazon, or Test Store SDK key.

The production workflow validates all three values and synchronizes them to
Supabase before deploying the function. Configure the RevenueCat dashboard and
GitHub environment before merging the first hardened deployment; otherwise the
handler intentionally returns `503`.

Rotate one credential at a time. Update RevenueCat and the GitHub Production
secret as one supervised change, dispatch the deploy workflow, send a test
event, and verify an `applied` or `duplicate` ledger outcome before retiring the
previous operational record. RevenueCat signing-secret rotation invalidates the
old signing secret immediately.

## Testing

Run the focused unit and source-contract suite:

```bash
deno test --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/functions/revenuecat-webhook,.github/workflows/deploy.yml \
  services/supabase/functions/_tests/revenueCatWebhookCoverage.test.ts \
  services/supabase/functions/_shared/subscriptionPass_test.ts \
  services/supabase/functions/revenuecat-webhook/handler_test.ts \
  services/supabase/functions/revenuecat-webhook/index_test.ts \
  services/supabase/functions/revenuecat-webhook/signature_test.ts \
  services/supabase/functions/revenuecat-webhook/subscriber_test.ts

deno test --frozen \
  --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/migrations \
  services/supabase/functions/_tests/revenueCatWebhookMigrationContract.test.ts

make test-supabase-privileged-routines
```

The database suite proves duplicate delivery, delayed expiration, refund then
old-purchase replay, atomic source/destination transfer (including a deleted
source), missing and ambiguous-user failure, event-ID/payload conflict
detection, ACLs, and private-table isolation.

The event insert uses
`ON CONFLICT DO NOTHING RETURNING TRUE INTO event_inserted`. A duplicate returns
no row and therefore leaves the PL/pgSQL variable null; keep the branch as
`event_inserted IS NOT TRUE`. `COALESCE` is a PostgreSQL conditional expression,
not an ordinary catalog routine, so `pg_catalog.COALESCE(...)` fails the
`plpgsql_check` catalog gate.

The pgTAP fixture inserts `public.users` rows directly and therefore must provide
identity fields normally derived by the Auth trigger. Keep its deterministic
usernames within the 3–24 character limit and valid under
`public.is_valid_public_username(...)`; do not weaken the production constraint
for test data.

RevenueCat's protocol references:

- [Webhook behavior and HMAC verification](https://www.revenuecat.com/docs/integrations/webhooks)
- [Event types and fields](https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields)
- [Subscriber API](https://www.revenuecat.com/docs/api-v1#tag/customers/operation/subscribers)
