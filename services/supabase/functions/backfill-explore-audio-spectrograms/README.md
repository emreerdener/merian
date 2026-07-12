# backfill-explore-audio-spectrograms

Service-role-only repair worker for published standalone-audio media whose
`explore_post_media.thumbnail_url` is blank. Each bounded call generates a
deterministic PNG beside the durable WAV in R2, updates the post snapshot, and
also updates the matching `scan_media_assets` row so later shares can reuse it.

The endpoint accepts only `POST` and compares the bearer token to
`SUPABASE_SERVICE_ROLE_KEY` with the shared timing-safe helper. It is configured
with `verify_jwt = false` only so modern service-role credentials reach the
function; the explicit in-function check remains mandatory. Never call this
worker from iOS or the public web app.

```bash
curl -X POST "$SUPABASE_URL/functions/v1/backfill-explore-audio-spectrograms" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"limit":50}'
```

Repeat while `generated_count` is greater than zero. The worker selects WAV
candidates only; legacy non-WAV clips retain the existing volume-icon fallback
and normal audio playback. A nonzero `unsupported_count` identifies a malformed
or mislabeled WAV that needs separate inspection. The service-role key must
never be used from a client.

## Response

```json
{
  "success": true,
  "scanned_count": 1,
  "generated_count": 1,
  "unsupported_count": 0,
  "failed_count": 0,
  "errors": []
}
```

- `limit` is clamped to `1...200`; the default is `50`.
- Candidates are standalone-audio rows with a `.wav` URL and a null/blank
  thumbnail, ordered oldest first.
- Generated object names are content-addressed. Retrying a partially completed
  batch reuses the existing PNG rather than creating duplicates.
- `unsupported_count` covers malformed or mislabeled WAV bytes. Non-WAV legacy
  clips are not candidates.
- Individual generation failures are bounded in `errors` by the batch size and
  do not stop later candidates.
- The worker never changes the recording URL, moderation attestation, post
  visibility, species data, or playback behavior.

## Verification

```bash
cd services/supabase/functions
deno fmt --check backfill-explore-audio-spectrograms _shared/audioSpectrogram.ts
deno lint backfill-explore-audio-spectrograms _shared/audioSpectrogram.ts
deno check backfill-explore-audio-spectrograms/index.ts
deno test backfill-explore-audio-spectrograms/worker_test.ts \
  _shared/audioSpectrogram_test.ts
```
