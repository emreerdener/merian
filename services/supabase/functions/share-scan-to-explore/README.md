# share-scan-to-explore

Creates or reactivates the current user's Explore post for one eligible scan.
The endpoint shares the post content; post-level location visibility is stored
separately from the backing scan's `geoprivacy`.

## Authorization Boundary

Scan Library quick-share and the full Insight composer use this same endpoint.
The client sends only the signed-in user's access token. `withEdgeHandler`
authenticates that user, and the route binds scan ownership and share
eligibility to the resulting user ID; the iOS app never receives a service-role
key.

After those user checks, the server-side admin client refreshes the public
author projection, completes restoration/moderation preparation, and invokes
`publish_scan_to_explore_atomically`. That `SECURITY INVOKER` RPC revalidates
and locks the exact owner scan, validates that every bounded media URL belongs
to it, rechecks any community request after taking its row lock, and replaces
the post row, media snapshot, hashtag edges, and resolved community-publication
state in one service-role transaction. A transaction-time `needs_id` request
returns conflict without changing the prior publication. The request lock
precedes the scan lock to match the existing community publisher and prevent a
lock-order cycle. The RPC is revoked from `PUBLIC`, `anon`, and `authenticated`;
no privileged definer is introduced for ordinary publication.

Because the RPC is `SECURITY INVOKER`, forward migration
`20260729044500_grant_atomic_explore_service_privileges.sql` also installs the
operation-scoped table privileges needed by its `service_role` caller and the
existing location-projection trigger. It grants no browser-role write and does
not restore any split post/media/hashtag mutation fallback.

`refresh_public_author_identity(uuid)` and the other privileged database RPCs
remain granted only to `service_role`, and each service-exposed definer calls
`internal.require_service_role()`. Migration
`20260727010340_fix_service_role_authorization_guard.sql` lets that helper
recognize both legacy service-role JWT claims and PostgREST's protected
`service_role` impersonation for opaque secret keys without broadening any RPC
grant.

If Edge/database logs contain `service_role authorization required`, the failure
is a server migration/key-path regression, not a scan-level permission denial.
Verify that the compatibility migration is applied and that `service_role`—not
`authenticated`—has the reviewed RPC grant. Do not add a service key to the
client or grant the maintenance RPC to users.

## Subject Eligibility

The endpoint independently enforces a resolved, non-Human biological subject;
client visibility is not authorization. Its final owner-row read rejects
`is_biological_subject=false`, a missing selected species relation, unresolved
scientific-name placeholders (`Unknown Subject`, `Taxonomy Unavailable`,
`Unidentified Wildlife`, `No Wildlife Detected`, and equivalent sentinel
values), Human taxonomy aliases including malformed `Homo sapien`, and a Human
user-identification override. Confirmed taxonomy takes precedence over the
original species relation. The same exported owner-row validator is reused by
`request-community-identification`, so direct Explore and Ask the Community
requests cannot publish Human, unresolved, or non-biological scans. No decision
is derived from `ai_reasoning`.

## Request

```json
{
  "scan_id": "uuid",
  "field_notes": "Found at the shaded meadow edge after rain.",
  "species_common_name": "Black-Tailed Deer",
  "hashtags": ["deer", "urbanwildlife"],
  "location_sharing": "obscured",
  "restored_object_keys": ["staging/user-id/restored-image.webp"],
  "restored_video_object_keys": ["staging/user-id/restored-video.mp4"],
  "restored_audio_object_keys": ["staging/user-id/restored-audio.wav"],
  "recovery_scan": {
    "id": "same-scan-uuid",
    "user_id": "authenticated-user-uuid",
    "species_id": "server-species-uuid",
    "confirmed_species_id": null,
    "image_storage_urls": [],
    "timestamp": "2026-07-27T18:00:00Z",
    "geoprivacy": "private",
    "ai_confidence_score": 0.94,
    "ecology_type": "wild",
    "is_invasive": false,
    "is_live_capture": true,
    "is_biological_subject": true,
    "inference_tier": "flash",
    "user_confirmed_identification": false,
    "user_review_state": "unreviewed"
  },
  "media_items": [
    {
      "kind": "image",
      "source_media_id": "scan:uuid:image:0",
      "order_index": 0
    },
    {
      "kind": "video",
      "source_media_id": "scan:uuid:video:0",
      "order_index": 1
    },
    {
      "kind": "audio",
      "source_media_id": "scan:uuid:audio:0",
      "order_index": 2
    }
  ]
}
```

`location_sharing` is optional for backward compatibility. When omitted, the
atomic publication RPC resolves the new or reactivated post's initial post-owned
value from the scan's current `geoprivacy` after locking the exact owner row. A
concurrent privacy change therefore cannot publish with a stale Edge-layer
default.

`recovery_scan` is optional and intended only for an older/interrupted local
observation whose authenticated owner row is absent. It contains bounded
non-media fields; `id` must match `scan_id`, `user_id` must match the
authenticated user, and `image_storage_urls` must be empty. The server validates
UUIDs, numeric ranges, enums, text limits, and geoprivacy-derived public
coordinates. It then calls the same per-scan-locked atomic repair RPC as status
polling and reloads by both scan and owner before continuing. A raced existing
row is never overwritten, and a cross-owner UUID remains indistinguishable from
a missing scan.

When the owner row is actually absent, at least one validated restored image,
video, or audio staging key is required in the same Share request. A media-less
`recovery_scan` returns `409 scan_restore_media_required`. Every supplied key
must then prove its exact scan/kind/role upload-ledger binding before owner
recovery is invoked. This server backstop protects older released clients and
malformed direct requests from creating an empty completed scan—or mutating one
from an unrelated staging key—that cannot publish.

The database reads the owner-scoped ingestion job under the claim's generation
lock. Processing, finalizing, retrying, retryable, policy, unproven
media-abandonment, legacy-unknown, and arbitrary terminal reasons defer to the
richer original attempt. A missing ledger also defers. A complete-but-missing
row or exact `terminal_reason_code = replay_exhausted` may be repaired. Exact
`media_reconciliation_abandoned` additionally requires the matching composite
dead-letter/quota/media-lifecycle proof and rejects later policy authority. The
exact failed/committed normal and replay quota keys remain retained as
chronological authority while this terminal ledger is unresolved. Media is never
accepted inside `recovery_scan`; owner-scoped `restored_object_keys`,
`restored_video_object_keys`, and `restored_audio_object_keys` remain the only
repair inputs and still pass the endpoint's normal promotion, eligibility, and
publication gates.

Before it invokes owner-row recovery, the shared repair path first proves that
the hardening migration's service-only proof RPC is available and returns only
the requested scan identity. This route predeploys with the signer and status
consumer before the two recovery files execute as separate migration-file
transactions. Missing, stale, malformed, or denied proof readiness returns
retryable `503` without promotion or publication; normal fresh-scan sharing is
unchanged.

Clients should attach one UUID `Idempotency-Key` to the share request and reuse
it across transport, auth-refresh, and media-restoration retries. On audible
shares the Edge Function derives a separate opaque reservation UUID for each
checksum and moderation-policy version, so multiple clips remain independent
without exposing their checksums in the quota ledger. A later manual share may
use a new key; an existing content-addressed attestation then avoids and refunds
the provisional provider reservation.

`media_items` is optional for legacy clients. When present, it is the ordered
public media selection for this post. New clients should submit
`source_media_id` values returned by `get-explore-composer-media`. Legacy
clients may still submit `source_index` and `thumbnail_source_index` values that
point to the scan's promoted image/video/audio URL arrays; for videos,
`thumbnail_source_index` must resolve to the scan's promoted poster image.
Describe content, AI/reference images, and Dictionary media are not valid
Explore post media.

For video scans, `source_media_id` resolves through the same source list shown
by the composer: ready display/playback rows in `scan_media_assets` first, then
`scans.captured_media`, then legacy URL arrays. This keeps the playback `.mp4`
and poster thumbnail paired even when sampled inference frames also exist in
legacy image URL arrays.

The completed-scan prerequisite uses the same projection. Forward migration
`20260729012153_fix_video_scan_canonical_finalization.sql` prevents valid video
scans from being rejected merely because their compatibility frame URLs have no
standalone ready image rows; it still requires the ready playback row and every
genuine standalone image/audio row for the exact owner. Sharing must never
publish those inference frames as separate observation media.

Video `has_audio` metadata is copied from verified normalized playback rows.
Historical compatibility manifests may still expose a nested video-audio
reference as read evidence, but strict Captured Media Wire V1 rewrites remove
it. V1 manifest and legacy URL-array sources therefore default to `false` unless
independent durable playback metadata proves audio.

`restored_video_object_keys` is optional and only used by repair-capable
clients. At most one playback-video staging key is accepted. If the owner still
has the original local `.mp4` but the cloud scan row is missing
`video_storage_urls`, the client uploads that clip to staging and sends the
returned key here. The function promotes the video, rebuilds `captured_media`,
makes a best-effort `scan_media_assets` refresh, and validates the selected
video media again before publishing. Rows whose original local video is gone
remain image-only historical rows.

`restored_audio_object_keys` is the equivalent owner-scoped repair input for
legacy audio scans whose local WAV/M4A still exists but whose cloud scan
predates durable `audio_storage_urls`. At most two staging keys are accepted.
The function promotes them, replaces legacy local audio references in
`captured_media`, updates `audio_storage_urls`, refreshes normalized media
assets, and then applies the normal fail-closed publication moderation. When an
already-durable audio URL is rebuilt alongside a restored clip, its existing
optional `sourceIndex` is preserved; a newly restored legacy clip remains
unindexed unless the request can prove its original identity. Failed promotion
or a returned database rejection whose exact-owner reread proves the URLs absent
rolls back promoted R2 objects and publishes nothing. A lost update response or
unavailable reread returns retryable `503 scan_media_restore_unavailable` and
preserves promoted objects; deleting them could break a scan whose update
actually committed. The retry recognizes the canonical durable URLs and does not
consume the staging source twice. If the local recording is gone, the audio
cannot be recovered.

Both audio and video restoration use a compatibility-read/strict-write boundary.
Readable legacy aliases are normalized, device-local references and historical
nested video audio are removed, and the result is revalidated as Captured Media
Wire V1 before persistence. If no durable item survives, the writer stores
`null`, not an empty manifest.

Across images, playback video, and standalone audio, one repair request accepts
at most six staging keys in total. A key cannot appear under two media kinds.
This mirrors the canonical signing ledger and rejects contradictory repair
payloads before promotion.

Current restore keys are also bound to the authoritative capture-upload ledger
before owner reconstruction or the first promotion. Each row must match the
authenticated owner, exact client scan ID, media kind, and canonical role.
Therefore an owner-scoped key registered to another scan, an inference-only
frame, or a signed audio/video key relabeled into an image field cannot become
public through repair. If a ledger row exists but conflicts, it always wins and
the request is rejected. For compatibility with released clients that signed
restore media before ledger registration, a missing row is accepted only when
the key matches their exact deterministic scan/category filename and legacy
extension-derived kind.

Valid location values:

- `open`: project post-owned public coordinates and allow Explore Map and
  non-owned Nearby eligibility when coordinates are safe.
- `obscured`: keep a scrubbed public location label when available, but do not
  expose map coordinates.
- `private`: share the post without public location fields.

Legacy `hidden` input is accepted as `private`.

## Response

```json
{
  "success": true,
  "post_id": "uuid",
  "scan_id": "uuid",
  "shared_at": "2026-06-17T19:30:00.000Z",
  "location_sharing": "obscured",
  "publication_status": "published"
}
```

All successful shares return `200`; `publication_status` must be exactly
`published`, `post_id` must be a UUID, and `shared_at` must be a parseable
timestamp. A missing, malformed, or different value is not publication evidence.
The transaction-time Community conflict is mapped to `409` only for the exact
PostgreSQL `P0001` code and canonical pending-request message; matching text
from an unrelated database error remains a server failure. For standalone audio
or an audio-bearing video, `_shared/audioModeration.ts` must resolve an approved
attestation for every audible selected item before the transactional publication
RPC runs. A matching attestation can be reused; otherwise Gemini evaluates
speech and non-speech content live. Flagged content returns `422`; provider or
configuration failures on a cache miss return `503`. In both cases nothing is
created, reactivated, or made public. Cache misses reserve the database-owned
`explore_audio_moderation` quota before provider dispatch. The reservation
atomically applies the durable entitlement, model policy, daily limit, and
shared per-user/IP rate limits.

The same mandatory quota-backed moderation preparation is reused by
`request-community-identification` and media-bearing
`update-explore-field-notes` requests. The shared default helper refuses
provider work when a caller omits that boundary.

When one share request must repair more than one media kind, the function
resolves that caller's durable entitlement once and reuses it only within the
current handler invocation. It does not keep a process-local or cross-request
entitlement cache.

The function emits privacy-safe PostHog funnel events for each audible media
moderation outcome and for successful publication. Properties are limited to
coarse outcome, media composition, model, latency bucket, and location-sharing
mode. They never include transcripts, media URLs, filenames, post IDs, species
identity, or coordinates. Telemetry uses the Edge background execution lock so
PostHog latency cannot delay publication.

Moderation decisions are cached by SHA-256, policy version, and model in
`explore_audio_moderation_attestations`. The cache is shared across identical
bytes without storing a URL or user identity. Cache hits avoid a second Gemini
call; changed bytes, policy versions, or models force live moderation. Cache
failures fall back to live Gemini classification and never approve content by
default.

After standalone WAV audio is approved, `_shared/audioSpectrogram.ts` performs
the presentation-only media step: it decodes bounded PCM WAV, applies the same
2048-point Hann-windowed FFT, 128 mel bins, 80 Hz–16 kHz range, −80 dB floor,
and palette used by iOS, then writes a deterministic
`spectrogram-v1-{sha256}.png` beside the durable recording. An existing object
with the same content-derived key is reused. The URL is copied to the audio
`explore_post_media.thumbnail_url` snapshot and matching
`scan_media_assets.thumbnail_url` row.

Spectrogram creation never weakens or replaces moderation. It runs only after
approval and is non-blocking: unsupported legacy codecs, malformed WAV data, or
R2 thumbnail failures keep the recording playable with the speaker fallback.
`backfill-explore-audio-spectrograms` applies the same deterministic generator
to historical blank WAV snapshots in bounded service-role-only batches.

## Rules

- Requires an authenticated user through `withEdgeHandler`.
- `scan_id` must belong to the current user.
- An absent owner row may be reconstructed only through the validated
  `recovery_scan` contract above. The endpoint never accepts caller-selected
  ownership, direct media URLs, or a client-side database upsert as repair.
- Tombstoned scans, media-less scans, scans without a resolved species, Human
  scans, and scans with unresolved placeholder taxonomy are not share-eligible.
- Sharing snapshots public image/video/audio URLs into `explore_post_media` for
  the post. Video posts require a public thumbnail image; otherwise the endpoint
  returns `Video thumbnail unavailable.`
- Approved standalone WAV rows normally carry a generated PNG `thumbnail_url`;
  non-WAV legacy rows may keep that field blank without losing playback
  eligibility.
- Media selections are validated before the post is reported as shared. Public
  feed/share-state visibility requires at least one saved `explore_post_media`
  row. The final owner check, post upsert, complete media replacement, hashtag
  replacement, community-readiness recheck, and resolved-community publication
  are one transaction. A request that is still `needs_id` fails with conflict.
  Any relational failure rolls back the prior post metadata, timestamp, media,
  and hashtags rather than exposing a partial publication.
- Restored video keys are promoted before the public media snapshot is written.
  If promotion fails or selected video media still cannot be resolved, the
  request fails cleanly instead of publishing sampled frames as a video.
- Describe/observation context is private scan context. It is never copied into
  `field_notes`, hashtags, captions, media metadata, or the public media
  snapshot unless the user manually writes that text into the composer.
- When `media_items` is supplied, only the selected image/video/audio rows are
  written to `explore_post_media`, ordered by `order_index`; the first selected
  visual URL, video poster, or persisted audio spectrogram becomes the computed
  `hero_image_url`.
- Empty media selections, unsupported media kinds, invalid source indexes, and
  videos without a thumbnail are rejected.
- Audio moderation reuses the paid-project `GEMINI_PAID_API_KEY` Edge secret.
  Gemini transcripts and non-speech descriptions are not persisted, logged, or
  returned to clients.
- The policy is supplied as an immutable system instruction and its effective
  cache version is derived from the prompt, categories, confidence threshold,
  and structured-output contract. Standalone audio keeps a supported audio MIME
  type and audible playback video keeps `video/mp4`; unsupported or ambiguous
  media types fail closed.
- Audio moderation runs before `explore_posts`, `explore_post_media`, hashtags,
  or resolved-community publication state is mutated. Approval is therefore a
  strict prerequisite for the share, not a post-publication status.
- If the scan has a resolved Ask the Community request, publishing materializes
  any new GBIF-backed resolved species into `species_dictionary`, sets
  `scans.confirmed_species_id`, and stamps the request's `explore_published_at`
  before the post becomes visible in normal Explore surfaces. Materialization
  also queues species-content provenance rows so normal Dictionary enrichment
  can hydrate the new species over time.
- Private backing scans can be shared; `private` means no public location on the
  post, not blocked sharing.
- The endpoint does not mutate `scans.species_id`, `scans.geoprivacy`, or
  `users.default_geoprivacy`.
- Hashtags are normalized to lowercase text without `#`, capped at five tags,
  and replace the post's existing hashtag edges for this share request.
- `species_common_name` stores the public post common-name snapshot when
  provided; omitted or empty values preserve dictionary fallback behavior.

## Spatial Privacy

The database trigger on `explore_posts` writes post-owned `public_latitude`,
`public_longitude`, `public_coordinate_visibility`, and `public_location_label`
from the saved `location_sharing` value. Even when a post is set to `open`,
protected-species and coordinate-uncertainty rules can store rounded public
coordinates with `coordinate_visibility = "obscured"`.

## Local Verification

```sh
make validate-supabase-migrations
make test-supabase-privileged-routines
deno check --config services/supabase/functions/deno.json services/supabase/functions/share-scan-to-explore/index.ts
deno test --config services/supabase/functions/deno.json \
  services/supabase/functions/_tests/atomicExplorePublicationMigrationContract.test.ts \
  services/supabase/functions/_shared/scanRecovery_test.ts \
  services/supabase/functions/share-scan-to-explore/restoredMediaValidation_test.ts \
  services/supabase/functions/share-scan-to-explore/db_test.ts

supabase --workdir services test db --local \
  supabase/tests/atomic_explore_scan_publication_security.sql
```

DB integration tests require a running local Supabase Postgres instance at the
configured test URL. The privileged-routine catalog fixture must run only
against the disposable local database; never substitute `--linked`.

The joined durability, media restoration, Field Chat/Explore recovery, and
deployment guarantees are in
[`docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md`](../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#explore-publication).
