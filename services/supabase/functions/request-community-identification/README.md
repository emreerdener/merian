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
the device received an inference result but background scan ingestion failed.

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
