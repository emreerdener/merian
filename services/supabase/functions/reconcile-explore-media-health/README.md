# Reconcile Explore media health

Service-role-only worker for published Explore media.

Gateway JWT verification is disabled because current Supabase project secret
keys are not JWTs. The handler still fails closed: it accepts the exact
automatically provisioned legacy service-role value, or an exact named
`sb_secret_...` value from the platform's `SUPABASE_SECRET_KEYS` environment. It
never uses a database/RLS result as proof. Legacy keys may use Bearer transport;
named non-JWT secret keys must use `apikey` only, and mixed credentials fail
closed. Worker RPCs use the server-managed environment key, not the accepted
request value. Missing and mismatched keys receive `401`.

The worker leases due media rows, derives canonical object keys from
`media.merian.app` URLs, and sends signed `HEAD` requests directly to the R2 S3
origin. Direct durable keys must belong to the leased post owner; cross-owner,
nested, temporary-prefix, and arbitrary keys fail closed. It records one of:

- `healthy` for successful origin responses;
- `missing` only for origin HTTP 404;
- `retryable_error` for timeouts, network failures, and non-404 errors.

The database requires two missing observations at least five minutes apart
before a media item becomes confirmed missing. Confirmed-missing items are
omitted from projections; a post is reversibly quarantined only when all of its
items are missing. No scan, post, like, comment, or publication-intent row is
deleted.

The scheduled invocation runs every five minutes. Healthy objects are checked
daily, distinct impaired posters and confirmed-missing objects hourly, and
retryable primary failures after fifteen minutes. Production uses dedicated
bucket-scoped `R2_READ_ACCESS_KEY_ID` / `R2_READ_SECRET_ACCESS_KEY` credentials;
the worker never receives object-write or object-delete authority.

Primary and distinct-poster checks run in parallel per media row under a global
24-row cap. Scheduled batches use a five-minute lease and a two-minute caller
timeout so a ten-second R2 outage timeout cannot routinely expire work. Run
audits retain only fixed failure reason codes and at most 50 row samples;
provider error messages and complete media URLs are not persisted.
