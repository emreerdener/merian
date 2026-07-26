# Ingest R2 media events

An R2 event notification is a hint, never proof of loss or restoration. A
Cloudflare Queue consumer batches `object-create` and `object-delete` messages
for direct durable `public_uploads/free/` and `public_uploads/pro/` keys with a
UUID owner segment and sanitized object name, then posts:

```json
{ "object_keys": ["public_uploads/pro/<user>/<object>"] }
```

to this function with `X-Merian-R2-Event-Secret`. Matching media becomes due for
a signed direct-origin check. The consumer and Edge function share only a
dedicated random webhook secret; the Supabase service-role key must never be
stored in Cloudflare.

Queue messages should be acknowledged only after a 2xx response. Failed requests
should be retried by the Queue. Configure both object-create and object-delete
notifications so repair writes expedite automatic restoration as well as
quarantine.
