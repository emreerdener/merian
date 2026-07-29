# Insight Sharing

The `Sharing` directory handles the distribution of an Insight beyond the local
device.

## Purpose

This area manages the UI and logic for exporting the scan. It drives the native
iOS share sheet (Messages, Mail, etc.) and handles the specialized flow for
publishing a private scan to the public Naturebook `Explore` feed, including the
attachment of public hashtags and common-name snapshots.

## Explore Publication Contract

`InsightSheetViewModel+ExploreSharing` owns presentation state, while
`MerianNetworkClient.shareScanToExplore(scan:...)` owns the authenticated
publication and guarded recovery sequence. One user action always targets the
stable scan UUID.

Normal publication:

1. snapshot the local record into value-only `ExploreShareMediaSnapshot`;
2. send the exact scan UUID, user-authored public field notes, normalized
   hashtags, post-level location sharing, and ordered public media selection;
3. let `/share-scan-to-explore` bind ownership to the user JWT;
4. require a saved eligible `explore_post_media` snapshot before treating the
   post as feed-visible; and
5. persist the returned post ID and authoritative share state locally.

Describe text and private observation context are never copied into public field
notes, hashtags, captions, or media metadata unless the user explicitly writes
that text in the composer.

## Missing Cloud-Row Recovery

Current Identify success guarantees the exact owner scan already exists.
Recovery is for older/interrupted local/cloud drift only.

When the ordinary share returns a handler-owned `404 Scan not found`, the
network client:

1. polls `/check-scan-status`;
2. leaves active or retryable richer ingestion authoritative;
3. refuses policy rejection, deletion, and ambiguous/unknown state;
4. resolves a server species UUID from the local scientific name;
5. builds bounded non-media `OwnedScanRecoveryPayload` using the authenticated
   persisted Auth owner; and
6. uploads only surviving local user media through the normal
   owner-authoritative staging signer.

The repair-capable share may then combine `recovery_scan` with:

- `restored_object_keys` for images;
- `restored_video_object_keys` for one playable `.mp4`; and
- `restored_audio_object_keys` for bounded standalone recordings.

The server validates traversal, owner prefix, count, type, promotion, canonical
media refresh, selection, privacy, and audible-media moderation before
publication. iOS never sends a direct durable URL as recovery input and never
upserts `public.scans`.

If no eligible local user media survives, publication remains unavailable; a
reference image is not observation evidence and cannot replace it.

## Ambiguous Restore Handling

A lost database response can occur after restored media was promoted and the
owner scan update committed. In that case the server returns retryable
`503 scan_media_restore_unavailable` and preserves the promoted objects unless
an exact owner reread proves the update was rejected and the URLs absent.

The client retains its local record and retries the same scan. The server
recognizes already-durable owner filenames and does not consume the staging
source or duplicate canonical media. Do not implement client-side object
deletion or create a new scan UUID to work around this response.

Customer copy remains feature-level:

- missing/still-syncing owner state:
  `This observation is still syncing. Please wait a moment and try sharing again.`
- internal server-key/publication boundary failure:
  `Explore is temporarily unavailable. Please try again in a few minutes.`

Raw SQL, authorization, object-key, and internal recovery errors are never shown
to users.

## Share-State Reconciliation

The toolbar may render a cached same-device post ID immediately, then
`/get-scan-explore-share-state` reconciles the authoritative server result. A
post is considered shared only when it is active and has eligible saved public
media. A partial media-less post clears the local cache rather than opening a
phantom Explore destination.

## Privacy and Security

- Owner comes from the validated user JWT, never a body `user_id`.
- Public location is post-owned Open, Obscured, or Private and does not mutate
  the backing scan's geoprivacy.
- Exact GPS and private observation context remain out of public payloads unless
  the explicit Open projection is eligible.
- Staging keys and media URLs are private in application logs.
- No service-role or secret project key exists in the app.

See:

- [Explore share route](../../../../../../services/supabase/functions/share-scan-to-explore/README.md)
- [Scan ingestion reliability and recovery](../../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#explore-publication)
- [Insight sheet sharing behavior](../../../../../../docs/features-and-hardware/05-insight-sheet.md)
