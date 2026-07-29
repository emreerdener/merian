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

The create callback returns an explicit success result to `InsightShareButton`.
The composer closes only after publication returns and the response confirms
success, echoes the requested scan ID, supplies a valid post UUID, parseable
share timestamp, authoritative location choice, and published status, and the
post ID has been cached. A transport, readiness, moderation, persistence, or
response-integrity failure leaves the same draft mounted and presents a retry
alert; notes, hashtags, location choice, and ordered media selection are not
discarded merely because `isSharingToExplore` returned to `false`.

The backend corresponding to this client must expose
`publish_scan_to_explore_atomically(...)`. It commits post metadata, ordered
selected media, hashtags, and resolved-community publication state together
after one final owner/eligibility lock. The client does not accept a legacy
success response with missing `publication_status`; release the corrected
backend before this app build.

Describe text and private observation context are never copied into public field
notes, hashtags, captions, or media metadata unless the user explicitly writes
that text in the composer.

## Ask the Community Contract

Ask the Community uses the same stable scan UUID, owner boundary, canonical
public-media builder, and fail-closed audio moderation path as explicit Explore
publication. If compatibility recovery is required, iOS stages every surviving
eligible local media kind and sends images, playback video, and standalone audio
in their separate restored-key arrays. It does not require a recovered image
when a biological scan has only video or audio.

The action is complete only when the response reports true success, echoes the
exact scan UUID, contains valid request, post, requester, taxon, and taxonomy
UUIDs, supplies a parseable request timestamp, remains in `needs_id`, and has a
nonnegative consensus count. A decodable but unconfirmed HTTP `200` cannot clear
normal Explore state or show “Asked community.” Decoder failures and unknown
request statuses are normalized to `MerianError.invalidResponse` at the same
candidate-success boundary.

## Missing Cloud-Row Recovery

Current Identify success guarantees the exact owner scan already exists.
Recovery is for older/interrupted local/cloud drift only.

For video scans, the backend completed prerequisite represents one ready
playback clip with its poster. Sampled inference frames may remain in the
compatibility image array, but they are not standalone composer items and must
not be uploaded or selected as separate observation photos merely to satisfy
sharing. Backend migration
`20260729012153_fix_video_scan_canonical_finalization.sql` aligns finalization
with this existing composer contract.

When the ordinary share returns a handler-owned `404 Scan not found`, the
network client:

1. polls `/check-scan-status`;
2. leaves active or retryable richer ingestion authoritative;
3. refuses policy rejection, deletion, and ambiguous/unknown state;
4. resolves a server species UUID from the local scientific name;
5. builds bounded non-media `OwnedScanRecoveryPayload` using the authenticated
   persisted Auth owner;
6. asks single-scan status recovery to commit the guarded owner row and requires
   an authoritative `found` response; and
7. uploads only surviving local user media through the normal
   owner-authoritative staging signer.

The retried repair-capable share may idempotently combine `recovery_scan` with:

- `restored_object_keys` for images;
- `restored_video_object_keys` for one playable `.mp4`; and
- `restored_audio_object_keys` for bounded standalone recordings.

Ask the Community cannot accept `recovery_scan` directly. It first completes the
same guarded `/check-scan-status` owner-row recovery and then uses all three
restored-key fields on its own route.

The currently released/TestFlight client uses the older order: it stages exact
restore media first, then attaches `recovery_scan` to Share. Backend
compatibility keeps that cohort repairable, but only under the same guarded
owner/ledger proof described below. Signing alone grants no owner-row write or
publication authority.

The server validates traversal, owner prefix, count, type, promotion, canonical
media refresh, selection, privacy, and audible-media moderation before
publication. The shared restored-media parser allows no more than five images,
one playback video, two standalone recordings, or six keys total and rejects a
key claimed under two media kinds. Before requesting the first signing URL, iOS
preflights that same complete mixed-media count plus every image/video/audio
byte budget so an invalid legacy snapshot cannot upload a partial repair set. It
never sends a direct durable URL as recovery input and never upserts
`public.scans`. Every current restore manifest sets
`uploadPurpose = scan_share_restore`; the signer accepts that completed-scan or
guarded-terminal exception only for an exact deterministic scan/category
filename, canonical role, and fresh unrestricted scan read. A guarded terminal
restore is limited to exact `replay_exhausted`, or exact
`media_reconciliation_abandoned` together with the matching owner/scan
service-written post-result `failed_scan_ingestions` row. An existing row must
be active and JWT-owned; a genuinely absent row may only stage for the later
guarded reconstruction. Policy, unproven media abandonment, unknown/arbitrary
terminal state, a tombstoned or foreign scan, and an ordinary post-completion
upload remain rejected. The service-only recovery transaction independently
requires the same proof, shares the ingestion generation lock, honors deletion
tombstones and ID collisions, never overwrites an existing row, and commits the
owner row plus completed ledger together. Historical promoted capture rows do
not consume this repair's active six-item staging budget. Every current key must
also match an authoritative capture-upload ledger row for the exact
authenticated owner, scan ID, media kind, and role before the server promotes
any object. This prevents an owner key from another scan or a signed audio/video
key relabeled as an image from crossing into publication. Compatibility with
released clients that signed before ledger registration is limited to their
exact deterministic scan/category filename and legacy extension-derived kind.

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

The client applies reconciliation only when the response echoes the exact open
scan, post and Community IDs are valid UUIDs, the share time is parseable,
Community ID/status are paired, location is present, and an explicit feed
visibility Boolean has a coherent committed-post topology. Visibility is never
inferred from a partial response. A committed post may legitimately be hidden
without a Community request when the server has quarantined its media or
moderation has removed it; that owner-only publication identity is accepted
without being cached as a visible Explore destination. A stale, mismatched,
unknown-location, visible-without-post, or structurally partial HTTP `200` is
ignored as unavailable and cannot overwrite the optimistic cache for the open
Insight.

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
