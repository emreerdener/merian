# Resend account-deletion webhook

This public-to-provider Edge route is the authoritative delivery boundary for
legacy Sign in with Apple account deletion. The send API response is only
dispatch acceptance. Supabase Auth remains protected by the restrictive database
row until this route commits a matching `email.delivered` event.

The handler:

- accepts `POST application/json` only;
- reads at most 64 KiB and verifies the Svix signature over the exact raw bytes
  with `RESEND_WEBHOOK_SIGNING_SECRET` before JSON parsing;
- rejects missing, invalid, future, or stale signatures;
- uses `svix-id` for durable event idempotency;
- correlates only the opaque `attempt_id` Resend tag and provider email ID;
- persists no recipient, sender, subject, headers, or raw payload; and
- treats `email.delivery_delayed`, `email.bounced`, `email.failed`, and
  `email.suppressed` as non-completion states that retain the Auth fence.

Successful new or duplicate reductions return HTTP `200`. Invalid signatures or
timestamps return `401`, unsupported methods/media types and malformed payloads
return `4xx`, an event-ID reuse with conflicting content returns `409`, and
unavailable configuration or database persistence returns `5xx` so Resend can
retry. Responses and logs never echo the recipient or raw payload.

`services/supabase/config.toml` intentionally sets `verify_jwt = false` because
Resend does not send a Supabase JWT. That does not make the route
unauthenticated: the handler owns authentication with the endpoint-specific Svix
signing secret.

Production rollout requires registering exactly one Resend webhook endpoint for
`email.delivered`, `email.delivery_delayed`, `email.bounced`, `email.failed`,
and `email.suppressed`, then storing its `whsec_...` signing secret as the
GitHub `Production` environment secret `RESEND_WEBHOOK_SIGNING_SECRET`. Validate
a real Apple private-relay delivery before releasing the deletion path.
