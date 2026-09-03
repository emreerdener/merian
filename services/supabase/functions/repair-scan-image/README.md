# repair-scan-image

Owner-authenticated inspection and recovery for a durable scan image whose
Cloudflare R2 object is unexpectedly missing while the scan metadata still
references its public URL.

This is an incident-recovery endpoint, not a general image replacement, editing,
or cross-account migration API.

## Authentication and Ownership

`config.toml` uses `verify_jwt = false` so the function can retain its reviewed
in-handler authentication behavior across supported project-key formats. The
route is not public: `withEdgeHandler` validates a live Supabase user JWT,
creates the privileged downstream client only after authentication, and derives
the owner from that user.

The request accepts no target user ID. Every scan lookup is constrained by:

- `user_id = authenticated user`;
- `is_tombstoned = false`; and
- the exact source URL in `image_storage_urls`.

Account deletion wins. The function returns `409 account_deletion_in_progress`
before inspection, promotion, or metadata repair when destructive cleanup owns
the identity.

## Inspect Request

```json
{
  "source_url": "https://media.merian.app/public_uploads/free/11111111-1111-4111-8111-111111111111/original.webp"
}
```

`source_url` must have the HTTPS protocol, exact `media.merian.app` hostname, no
query or fragment, and a flat
`public_uploads/free|pro/{single-segment}/{single-segment}` path. The exact URL
must also appear in an active `image_storage_urls` array owned by the
authenticated user; the path alone is not ownership evidence.

Response:

```json
{
  "data": {
    "status": "healthy"
  }
}
```

Status is:

- `healthy`: the exact active owned scan reference exists and R2 returns 2xx;
- `missing`: the owner reference exists and R2 returns 404; or
- `not_referenced`: no active scan owned by the caller references the URL.

Inspection never uploads, promotes, rewrites, or deletes media. R2 errors other
than 404 fail closed as `503`.

## Repair Request

iOS first uploads the strongly matched surviving local image through
`generate-upload-urls`, then submits the exact returned staging key:

```json
{
  "source_url": "https://media.merian.app/public_uploads/free/11111111-1111-4111-8111-111111111111/original.webp",
  "restored_object_key": "staging/11111111-1111-4111-8111-111111111111/restored.webp"
}
```

The restored key must be one flat supported image filename directly under the
authenticated user's staging prefix. The worker then:

1. proves the owner scan still references the exact source URL;
2. `HEAD`s the source object;
3. if the source recovered, removes the now-redundant staging upload when
   possible and returns `healthy` without changing metadata;
4. otherwise proves the restored staging object exists;
5. resolves the owner's durable entitlement;
6. safely promotes exactly one image into the owner's current free/Pro durable
   prefix;
7. validates the returned durable owner prefix; and
8. calls service-only `repair_owned_scan_image_reference` to replace the exact
   URL atomically across:
   - `scans.image_storage_urls`;
   - recursively nested `scans.captured_media` strings;
   - matching owner `scan_media_assets.url`, `thumbnail_url`, and storage
     metadata; and
   - matching `explore_post_media` rows owned by the same user.

The database transaction also resets matching Explore media-health evidence so
ordinary public projection can recover without deleting the post or engagement.

Successful response:

```json
{
  "data": {
    "status": "repaired",
    "replacement_url": "https://media.merian.app/public_uploads/pro/11111111-1111-4111-8111-111111111111/restored.webp",
    "updated_scan_count": 1,
    "updated_post_media_count": 1
  }
}
```

## Ambiguous Persistence

An RPC/client exception does not prove the atomic transaction rolled back; its
response may have been lost after commit. The worker rereads exact active-owner
references for both the source and replacement:

| Owner topology                                                  | Resolution | Replacement cleanup                       |
| --------------------------------------------------------------- | ---------- | ----------------------------------------- |
| source absent, replacement present                              | committed  | preserve and return reconstructed success |
| returned database rejection, source present, replacement absent | rejected   | checked best-effort delete                |
| source and replacement both present/absent                      | unknown    | preserve                                  |
| owner reread unavailable                                        | unknown    | preserve                                  |
| thrown/lost response with source present, replacement absent    | unknown    | preserve                                  |

Only the definite-rejection topology authorizes removal of the newly promoted
replacement. Every unknown topology returns retryable
`503 scan_image_repair_persistence_unknown`. Deleting the replacement in that
state could turn a committed repair back into a missing-media incident.

All direct R2 deletes inspect the response status and drain/cancel the body.
Partial rollback failure emits a restricted structured error for reconciliation;
it is never converted into false success.

## Error Contract

- `400`: invalid durable source URL or restored staging key.
- `401`: no valid live user JWT.
- `404`: repair requested for an exact source no longer referenced by an active
  owned scan.
- `409 account_deletion_in_progress`: destructive lifecycle owns the account.
- `409`: restored staging object was not found.
- `503`: source/restored R2 state could not be verified.
- `503 scan_image_repair_persistence_unknown`: metadata may have committed;
  preserve the replacement and retry inspection.
- `500`: unexpected promotion or definite database failure.

Public responses omit object listings, credentials, SQL errors, internal
topology, local paths, and provider details.

## Database Boundary

Migration `20260726041338_repair_owned_scan_image_references.sql` installs
`repair_owned_scan_image_reference(uuid,text,text)`. The function is:

- `SECURITY DEFINER` with an empty fixed search path;
- guarded by `internal.require_service_role()`;
- revoked from `PUBLIC`, `anon`, and `authenticated`;
- explicitly granted only to `service_role`; and
- registered in `internal.privileged_routine_grants`.

iOS cannot execute it directly and never receives a server key.

## Verification

Native inspect/repair methods live in
`Core/Network/Endpoints/MerianNetworkClient+MediaStorage.swift`, with unchanged
hand-written DTOs in `MediaStorageAPIModels.swift`. They forward raw source/key
values, require the `data` envelope and known status, default missing/null
counts to zero, and preserve 30-second deadlines, plain decoding errors,
classified refresh, and ambiguous-replay refusal.
`Core/Data/Images/LocalImageLoader.swift` retains inspect → validate surviving
local image → sign → file-backed upload → repair, plus cache and event handling.
The endpoint does not infer workflow success from decoding alone. Raw upload
policy and file planning live in `Core/Network/Media/` without owning another
session or retry loop. Run the
[native media storage matrix](../../../../apps/ios/Merian/Core/Network/README.md#media-storage-and-upload-verification)
alongside these handler checks for cross-boundary changes.

```bash
deno test --config services/supabase/functions/deno.json \
  services/supabase/functions/repair-scan-image/validation_test.ts \
  services/supabase/functions/repair-scan-image/db_test.ts \
  services/supabase/functions/repair-scan-image/worker_test.ts

deno check --frozen \
  --config services/supabase/functions/repair-scan-image/deno.json \
  services/supabase/functions/repair-scan-image/index.ts
```

Executable authorization/behavior coverage lives in
`services/supabase/tests/scan_image_repair_security.sql` and must run only
against a disposable local or staging catalog.

See:

- [Scan ingestion reliability and recovery contract](../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
- [API contract](../../../../docs/backend-and-data/05-api-contracts.md#deno-repair-scan-image-edge-node)
- [Account-scoped image-loss incident](../../../../docs/incidents/2026-07-account-scoped-r2-image-loss.md)
