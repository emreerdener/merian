# Generate Upload URLs

The authenticated staging signer for scan images, playback video, standalone
audio, and profile avatars. Instead of tunneling large media through a Supabase
Edge isolate, iOS requests short-lived S3 presigned URLs and uploads each
validated item directly to Cloudflare R2 using `PUT`. Scan media additionally
receives durable lifecycle registration before any URL is returned.

## Architecture

- **`index.ts`**: The HTTP orchestrator. It reads a bounded JSON object through
  the shared `parseJsonBody(...)` ingress contract, accepts the structured
  `files` manifest (`fileName`, `mediaKind`, `contentType`, `sizeBytes`,
  optional `clientScanId`, optional `mediaRole`, optional `uploadPurpose`),
  rejects legacy manifests that cannot declare a byte size, blocks requests
  that exceed the shared six-file staging cap, and creates staged
  `scan_media_assets` rows for scan media before returning signed URLs.
- **`storage.ts`**: Validates media kind/content type/byte budgets and role/kind
  combinations before signing, enforces the `Promise.all` key generation
  mapping, injects the verified `userId` to strictly namespace objects
  dynamically, and executes regex sanitization against `fileName` to prevent
  `/../` directory traversal vulnerabilities on Cloudflare's staging bucket.
  Video signing is strict: the client supplies one upload-bounded `video/mp4`
  playback file per video capture or repair attempt, and downstream
  identify/share flows fail rather than silently accepting a partial video set.
  The sixth staging slot exists for the Pro video shape: five sampled
  `image/webp` inference frames plus one playback `.mp4`; image, audio, and
  video sub-limits still prevent broader over-batching.
- **`assetRegistration.ts`**: Converts the validated signing response into
  owner-scoped `capture_upload` lifecycle rows. It proposes one upload session
  per client scan for newly registered items and assigns order indexes within
  that scan, independent of unrelated scans or legacy uploads in the same batch.
  Exact rows reused after an ambiguous response retain their original committed
  session and order identity.

## Structured Scan Request

```json
{
  "files": [
    {
      "fileName": "11111111-1111-4111-8111-111111111111_0.webp",
      "mediaKind": "image",
      "contentType": "image/webp",
      "sizeBytes": 482310,
      "clientScanId": "11111111-1111-4111-8111-111111111111",
      "mediaRole": "display"
    }
  ]
}
```

`clientScanId` accepts `client_scan_id`, `mediaRole` accepts `media_role`, and
`uploadPurpose` accepts `upload_purpose` for compatibility. `uploadPurpose` is
normally omitted. `scan_share_restore` is reserved for re-staging surviving
local media bound to an exact scan during explicit Explore or Community repair,
including guarded missing-owner-row recovery. Every structured entry requires a
positive integer `sizeBytes`; empty media is rejected before signing. The
filename must already be sanitized, flat, and unique within the request.
Role/kind combinations are strict:

If both spellings of a compatibility field are present, their values must be
identical. Conflicting aliases are rejected rather than choosing one silently.

- image: `display`, `thumbnail`, or `inference_frame`;
- video: `playback`; and
- audio: `audio`.

The authenticated JWT—not a body owner field—selects the owner. The returned key
is always directly under `staging/{authenticatedUserId}/`.

`scan_share_restore` additionally requires `clientScanId`, the canonical role
for its kind, and the exact deterministic
`{clientScanId}_explore_restore_{category/index}.{extension}` filename shape.
When the ingestion job is complete, registration performs a fresh unrestricted
`scans` lookup. An existing row must be active, non-tombstoned, and owned by the
authenticated user; a genuinely absent row may only stage the exact media before
guarded owner-row reconstruction. A missing or nonterminal job may stage for the
same guarded flow. Signing grants no scan-write or publication authority, and
the later recovery route must validate the authenticated owner and payload. A
failed-terminal job may sign only for exact `replay_exhausted`, or exact
`media_reconciliation_abandoned` with matching composite service proof: a
post-result dead letter no earlier than the latest charged normal/replay
attempt, producer-generation-appropriate evidence, no active reservation or
invalid timestamp lineage, and no moderation-rejected or
moderation-pipeline-failed capture lifecycle row. The signer obtains this
decision from the bounded service-only
`get_media_abandoned_scan_recovery_proofs` routine. Database errors, malformed
rows, and unexpected scan IDs fail before signing. Every exact failed/committed
normal and replay reservation remains retained as chronological authority while
the terminal job is unresolved. The signer never permits policy, later-policy,
unproven abandonment, another terminal reason, a cross-scan filename, arbitrary
repair key, mixed ordinary/repair registration for one scan, or a completed
non-owner scan.

This signer is one of three fail-closed consumers predeployed before the
baseline and hardening recovery files execute as separate migration-file
transactions. Its ordinary signing path does not consult the new proof RPC. Only
a legacy `media_reconciliation_abandoned` restore reaches that surface, and an
absent, stale, malformed, or denied response stops before URL issuance. The
schema-dependent Identify producer deploys after both files commit.

For example, an image repair entry is:

```json
{
  "fileName": "11111111-1111-4111-8111-111111111111_explore_restore_0.webp",
  "mediaKind": "image",
  "contentType": "image/webp",
  "sizeBytes": 482310,
  "clientScanId": "11111111-1111-4111-8111-111111111111",
  "mediaRole": "display",
  "uploadPurpose": "scan_share_restore"
}
```

Response:

```json
{
  "success": true,
  "urls": [
    {
      "fileName": "11111111-1111-4111-8111-111111111111_0.webp",
      "signedUrl": "https://signed-r2-upload.example/...",
      "objectKey": "staging/22222222-2222-4222-8222-222222222222/11111111-1111-4111-8111-111111111111_0.webp",
      "requiredHeaders": {
        "Content-Type": "image/webp",
        "Content-Length": "482310"
      },
      "mediaAssetId": "33333333-3333-4333-8333-333333333333",
      "mediaSessionId": "44444444-4444-4444-8444-444444444444"
    }
  ]
}
```

iOS must validate the complete response before starting any PUT and persist the
exact returned `objectKey` in the background task description. It must not
reconstruct the owner segment from delayed in-memory Auth state. A partial,
extra, malformed, cross-owner, or media-incompatible response starts no upload.
Every PUT must apply the response-declared `Content-Type` and `Content-Length`.
Both values are covered by the signature; the signed-header set is exactly
`content-length;content-type;host` because signing uses `allHeaders: true`. Every
iOS data, file, avatar, repair, restore, foreground, and background PUT applies
the returned map rather than reconstructing headers. A file is re-statted
immediately before task creation, and a changed size discards the URL so the
next pass re-signs it. Legacy `{ "fileNames": [...] }` requests, structured
entries without `sizeBytes`, top-level arrays, and other old/non-object request
shapes all receive the stable `400 size_bytes_required` response.

The declared size is not trusted as proof of storage. Integration verification
must perform the exact signed PUT, reject wrong size and MIME, then HEAD the
object and compare its stored length to the declaration. Existing media budgets
and the 24-hour signed-URL/staging expiry remain unchanged.

## Idempotent Scan Registration

Signed URL generation and lifecycle registration are separate operations. A
request is successful only after every structured scan item has a compatible
staged lifecycle row; signing URLs and then failing registration returns `503`
rather than handing the client an untracked upload.

`createStagedScanMediaAssets` treats authenticated owner, client scan UUID, and
deterministic object key as the registration identity:

- a lost HTTP response followed by the same request reuses the staged row and
  original upload session;
- a compatible retryable failed row may be reactivated;
- failed-terminal, deleted, incompatible, and ordinary completed-ingestion
  registration fails closed;
- an exact `scan_share_restore` request may register or reactivate media after
  ingestion is complete only when the fresh scan read finds the active
  authenticated-owner row or no row for guarded reconstruction; tombstoned,
  foreign, moderation-rejected, and moderation-pipeline-failed rows cannot be
  reopened;
- requested subsets compose with existing unrequested rows for the same scan;
  and
- the union of active staged/processing sources remains capped at six.

This subset rule is intentional. A live inline still has no staged source but
may later be recovered by the queue, and video/recovery components may be signed
in separate requests for the same stable scan UUID. Existing rows do not define
an immutable full manifest for later signing calls. Historical promoted rows
remain durable identity/audit evidence but do not consume the separate active
staging budget when an owner deliberately repairs sharing.

Migration `20260728231000_make_staged_scan_media_registration_idempotent.sql`
must be applied before this function version. It:

- marks historical extra registrations as failed
  `superseded_staging_registration` audit rows;
- installs partial unique index
  `idx_scan_media_assets_active_staging_key_unique`; and
- installs `enforce_staged_scan_media_budget`, whose owner-scoped transaction
  lock prevents concurrent disjoint-key requests from exceeding six staged
  sources for one scan.

Do not delete superseded rows or weaken the database trigger to clear a signing
failure. Inspect the exact owner/scan/key lifecycle and repair forward.

## Avatar Uploads

Profile pictures use this same staging signer. The iOS Profile tab sends a
single structured `files` entry for a prepared square WebP or JPEG avatar,
uploads it to `staging/{userId}/...`, then calls `update-public-avatar` with the
returned `objectKey`. This function does not promote or persist avatars; it only
signs the temporary staging upload. The durable object is created later under
`avatars/{userId}/...`.

Avatar and other non-scan uploads omit `clientScanId`, so the response does not
include `mediaAssetId` or `mediaSessionId`. Scan uploads include those optional
response fields and `identify-multimodal` later moves the staged rows to
`promoted`, `deleted`, or `failed`. During ingestion, the server recovers the
matching upload-session ids from `scan_media_assets` for the submitted staged
object keys and records them in `scan_ingestion_jobs`; they are part of the
manifest checksum used by retry, status, and reconciliation paths. The same
session ids are copied into `scan_ingestion_intents`, whose sanitized request
payload is the server-side replay source for staged scan requests consumed by
`replay-scan-ingestion`.

## Failure Semantics

- `400`: malformed manifest, duplicate/unsafe filename, invalid UUID, media
  count, kind, content type, role, or restore-purpose contract.
- `409 account_deletion_in_progress`: destructive account lifecycle owns the
  identity; the client must not upload or recreate profile state.
- `413`: one item or the combined image set exceeds its byte budget.
- `503`: signing lifecycle rows could not be registered compatibly. No returned
  URLs are usable.

Public responses do not expose database errors, prior lifecycle metadata, object
listings, credentials, or internal R2 diagnostics.

## Verification

```bash
deno test --config services/supabase/functions/deno.json \
  services/supabase/functions/generate-upload-urls/storage_test.ts \
  services/supabase/functions/generate-upload-urls/assetRegistration_test.ts \
  services/supabase/functions/_shared/scanMediaAssets_test.ts

deno check --frozen \
  --config services/supabase/functions/generate-upload-urls/deno.json \
  services/supabase/functions/generate-upload-urls/index.ts
```

The joined client/server contract and rollout order are in
[`docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md`](../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md).
