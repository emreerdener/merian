# backfill-explore-audio-spectrograms

Service-role-only repair worker for published standalone-audio media whose
`explore_post_media.thumbnail_url` is blank. Each bounded call generates a
deterministic PNG beside the durable WAV in R2, updates the post snapshot, and
also updates the matching `scan_media_assets` row so later shares can reuse it.

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
