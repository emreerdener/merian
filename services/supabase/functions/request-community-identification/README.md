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

Both final transaction RPCs remain `SECURITY INVOKER`. Forward migration
`20260729044500_grant_atomic_explore_service_privileges.sql` grants their
`service_role` caller only the table operation classes needed for locks,
snapshot replacement, taxonomy validation, request creation, and clean reopen.
It grants no browser-role write and does not convert either boundary to definer
authority.

## Request

```json
{
  "scan_id": "uuid",
  "note": "What should identifiers know?",
  "species_common_name": "Unknown warbler",
  "location_sharing": "obscured",
  "restored_object_keys": ["staging/user-id/restored-image.webp"],
  "restored_video_object_keys": ["staging/user-id/restored-video.mp4"],
  "restored_audio_object_keys": ["staging/user-id/restored-audio.wav"]
}
```

The three optional restored-key arrays are the bounded owner-scoped repair path
for surviving local images, playback video, and standalone audio. They use the
same flat, traversal-safe `staging/{authenticated-owner}/{filename}` validator
as explicit Explore publication. Empty entries are removed, duplicates are
collapsed, images are bounded to five input keys, playback video to one, and
standalone audio to two. The combined repair set cannot exceed the canonical
six-file staging cap, and one staging key cannot be claimed as two media kinds.
Before any object is promoted, current keys must match capture-upload ledger
rows for the authenticated owner, exact scan ID, declared kind, and canonical
role (`display`, `playback`, or `audio`). A ledger row for another scan or kind
is a conflict and cannot fall back to filename inference. Ledger-less
compatibility is narrowly limited to the exact deterministic filename emitted by
older released restore clients, including its scan/category marker and legacy
extension-derived kind. Promotion, canonical media refresh, eligibility, and
audible-media moderation still run before the Community transaction.

This endpoint does not accept `recovery_scan`. For older/interrupted local-cloud
drift, current iOS first sends the bounded non-media payload to the single
`/check-scan-status` recovery contract. The server defers to active/retryable
ingestion, blocks known moderation/provider-policy rejection, and
duplicate-safely reloads the authenticated owner row. Only after that succeeds
does iOS stage the surviving local image, playback-video, and standalone-audio
media and retry this endpoint with the corresponding restored-key arrays. A
video-only or audio-only biological scan is valid recovery input; repair does
not require an image key. Normal current `/identify-multimodal` success already
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

An HTTP-successful response is only a candidate success. Current iOS requires
`success: true`, the exact requested scan UUID, valid request/post/requester and
taxonomy UUIDs, a parseable request timestamp, `needs_id` status, and a
nonnegative consensus count before changing Community or Explore UI state. A
decodable but unconfirmed `200` remains a failure and does not dismiss the
user's action as completed.

The Edge/database boundary also verifies that `scan_id` and `requested_by`
identify the exact requested scan and authenticated owner after canonical UUID
case normalization. PostgreSQL emits lowercase UUID text while Apple clients may
emit uppercase UUID strings; casing alone must neither reject a committed
request nor weaken identity equality.

The route uses `withEdgeHandler`; the authenticated user ID is always the owner
boundary. It never accepts a caller-supplied owner ID.
