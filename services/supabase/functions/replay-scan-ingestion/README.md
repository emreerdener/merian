# replay-scan-ingestion

Service-role-only dispatcher for server-side scan ingestion replay.

## Purpose

`identify-multimodal` records two durable rows for accepted scan requests. The
legacy scan-producing endpoints (`identify`, `identify-describe`, and
`audio-spec`) record compatible rows before returning success:

- `scan_ingestion_jobs`: mutable state, stage, leases, retry timing, and media
  manifest checksums.
- `scan_ingestion_intents`: sanitized replay payloads for staged
  media/audio/video requests and text-only compatibility requests.

This worker turns those rows into real recovery. It claims retryable or
lease-expired jobs whose paired intent is `resumable = true`, reconstructs the
staged media/audio/video or text-only request, and invokes
`/identify-multimodal` with the same `client_scan_id`. The authenticated
`X-Merian-Replay-Attempt` header carries the durable claim count; multimodal
derives a distinct deterministic quota UUID from that count and the scan UUID.
Each claim is therefore metered once without colliding with the original
foreground reservation.

Inline foreground media is never replayed by the server because raw base64 media
bytes are intentionally redacted from `scan_ingestion_intents`.

Automatic replay is capped at 10 claims per sanitized intent. Once
`replay_attempt_count` reaches that ceiling, the claim RPC marks the paired job
`failed_terminal` with `stage = 'server_replay_limit_reached'` instead of
claiming it again, and records stable
`terminal_reason_code = 'replay_exhausted'`.

## Invocation

The worker is scheduled every five minutes by
`20260705150000_schedule_scan_ingestion_replay.sql` through `pg_cron` /
`pg_net`.

It uses `verify_jwt = false` at the gateway, then requires service-role
authorization inside the function. The request credential must exactly match the
explicit `SUPABASE_SERVER_API_KEY`, the production-deploy-synchronized
`MERIAN_SUPABASE_SERVER_API_KEY`, a named `sb_secret_...` value in the JSON
`SUPABASE_SECRET_KEYS` dictionary, the singular `SUPABASE_SECRET_KEY`
local/manual fallback, or the migration-only `SUPABASE_SERVICE_ROLE_KEY` legacy
fallback; no database capability probe is used. Send a named non-JWT secret only
in `apikey`. Legacy callers normally send the same service-role JWT in
Authorization and `apikey`; mismatched headers are rejected. The replay worker
uses the server environment key—not the accepted request value—for database
access and its internal multimodal invocation.

Optional POST body:

```json
{
  "limit": 5,
  "leaseSeconds": 300,
  "retryAfterMinutes": 5,
  "awaitInvocations": false
}
```

`awaitInvocations` is mainly for local verification and tests. Production cron
dispatches replay attempts through `EdgeRuntime.waitUntil` so the scheduler
returns quickly while the existing multimodal endpoint owns inference,
moderation, promotion, insert idempotency, and video durability gates.

The downstream multimodal request has a hard 120-second deadline. Claims are
therefore clamped to a minimum 150-second lease, preserving a 30-second
settlement margin even when a manual caller requests a shorter lease. A failed
downstream response is consumed through an 8 KiB streaming ceiling before any
diagnostic text is retained.

## Rules

- Only staged media/audio/video or description-only intents marked
  `resumable = true` are eligible.
- Completed and terminal jobs are never replayed.
- Replay attempt headers are accepted only on the service-role path, are bounded
  to 1–10, and participate in quota idempotency.
- A replay lease must outlive the downstream request deadline plus its
  settlement margin.
- Over-budget intents are terminal-marked in bounded batches using the same
  claim window as normal replay work.
- A cloud scan row that already has all required media is finalized through the
  per-scan-locked canonical-media RPC without replaying AI. The worker never
  updates ledger completion directly.
- A cloud scan row that exists but lacks required video media is left retryable
  for reconciliation/repair instead of re-running AI against an already-inserted
  scan.
- Video scans keep the same strict contract: replay is successful only when the
  playback `.mp4`, `video_storage_urls`, and `captured_media` video item are
  complete.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/replay-scan-ingestion/index.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/replay-scan-ingestion/worker_test.ts
```

Database integration requires a running local Supabase Postgres instance.
