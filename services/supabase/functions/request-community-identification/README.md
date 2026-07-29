# request-community-identification

Creates or reopens an authenticated user's Explore post as an Ask the Community
identification request. The scan must be owned, biological, non-tombstoned, and
have publishable media plus a resolvable taxon in the active taxonomy version.

## AI Cost and Publication Boundary

Community requests share the same fail-closed audio publication path as
`share-scan-to-explore`. Both newly created and existing Explore posts run every
selected audio clip or audio-bearing video through the content-addressed
attestation/live moderation gate before replacing public media.

Clients attach one UUID `Idempotency-Key` and preserve it across transport,
authentication, and local-media restoration retries. For each audible item, the
function derives an opaque child UUID from the parent key, media checksum, and
moderation policy version. A cache miss atomically reserves
`explore_audio_moderation`, including durable entitlement, database-selected
model, UTC-day limit, and shared user/IP rate limits. Cache hits refund the
provisional reservation; provider attempts commit immediately before dispatch.

The default moderation helper refuses to fetch media or call Gemini when this
authoritative quota callback is absent. A database, policy, entitlement,
provider, or moderation failure publishes nothing.

After taxonomy resolution and moderation, the route performs one final
relational mutation: `request_community_identification_atomically(...)`. The
service-role-only, invoker-rights RPC locks an existing request before the exact
owner scan, preserves existing field notes and hashtags, writes the complete
post/media snapshot, and creates or reopens `needs_id` state in the same
transaction. A taxonomy, constraint, trigger, or request write failure rolls the
post snapshot back. A reopened request clears its prior publication marker,
worker state, and active-vote generation while retaining identification rows as
withdrawn audit history.

The accompanying post trigger rechecks `needs_id` at the actual `shared_at`
write. This closes the race where an explicit Explore share observed no request,
waited on the scan lock, and otherwise could have returned success after a
Community request committed.

## Request

```json
{
  "scan_id": "uuid",
  "note": "What should identifiers know?",
  "species_common_name": "Unknown warbler",
  "location_sharing": "obscured",
  "restored_object_keys": ["staging/user-id/restored-image.webp"]
}
```

`restored_object_keys` is the bounded owner-scoped image repair path used when
the device still has local image media but the cloud scan row lacks publishable
images.

This endpoint does not accept `recovery_scan`. For older/interrupted local-cloud
drift, current iOS first sends the bounded non-media payload to the single
`/check-scan-status` recovery contract. The server defers to active/retryable
ingestion, blocks known moderation/provider-policy rejection, and
duplicate-safely reloads the authenticated owner row. Only after that succeeds
does iOS stage the local image and retry this endpoint with
`restored_object_keys`. Normal current `/identify-multimodal` success already
guarantees the owner row, so this sequence is a compatibility repair rather than
the expected scan path.

## Response

```json
{
  "success": true,
  "data": {
    "id": "request uuid",
    "post_id": "post uuid",
    "scan_id": "scan uuid",
    "status": "needs_id",
    "taxonomy_version_id": "taxonomy version uuid"
  }
}
```

The route uses `withEdgeHandler`; the authenticated user ID is always the owner
boundary. It never accepts a caller-supplied owner ID.
