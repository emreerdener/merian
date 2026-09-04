# Insight Sharing

The `Sharing` directory handles the distribution of an Insight beyond the local
device.

## Purpose

This area manages the UI and logic for exporting the scan. It drives the native
iOS share sheet (Messages, Mail, etc.) and handles the specialized flow for
publishing a private scan to the public Naturebook `Explore` feed, including the
attachment of public hashtags and common-name snapshots.

## Ownership

- `Models/` owns platform-neutral Share action and copy projection.
- `Services/` is the only Sharing owner allowed to resolve live network,
  application-event, cache, repository, and haptic dependencies. Its small
  initializer-injected closure values adapt those effects for the root Insight
  state owner, the Share component, and the Community request editor.
- `ViewModels/` owns Explore publication and editing actions, authoritative
  share-state reconciliation, Community request mutation, generation/revision
  fencing, and the observable Community request draft. The root
  `InsightSheetViewModel` remains Shell-owned; Sharing extends it without
  creating another root state owner.
- `Views/` owns Community request composition and sheet presentation.
- `Components/` owns the stable `InsightShareButton` entry and its nested
  options, warning, and Explore composer presentations. Selection, sheet, focus,
  and component action-generation state remain view-local.

Views and components perform no networking or live singleton resolution. Every
production Swift file in this directory remains below the 600-line review guard.
Wire DTOs, strict response validation, and recovery transport remain in
`Core/Network`; this refactor does not change an endpoint, payload, persistence,
feature flag, or navigation contract.

`InsightSharingDependencies.loadExplorePostDetail` adapts `getExplorePostDetail`
from
[Core Network's Explore browsing extension](../../../Core/Network/README.md#explore-browsing-endpoints).
Sharing retains advisory-detail reconciliation and scan/generation fencing.
Composer-media reads, content/field-note mutations, and authoritative
share-state reads use
[Core Network's post-management extension](../../../Core/Network/README.md#explore-post-management-endpoints).
It retains request construction and response validation only; Sharing retains
drafts, cache reconciliation, callbacks, and generation/revision fencing. Direct
publication, owned-row recovery, and local-media restoration live in the
dedicated Core Network Endpoint, Recovery, and Media owners; the main client
retains the private authenticated transport they reuse. The
[post-management matrix](../../../Core/Network/README.md#explore-post-management-verification)
joins endpoint regression and existing Sharing state coverage.

## Explore Publication Contract

The focused `Sharing/ViewModels` extensions own presentation and mutation state,
while the injected closures in `Sharing/Services` adapt
`MerianNetworkClient.shareScanToExplore(scan:...)` and the guarded recovery
sequence. One user action always targets the stable scan UUID. Explore actions
remain disabled unless the completed engine result, active local-record model
and ID, and immutable toolbar snapshot all identify that same scan. A failed
lookup for a newly presented scan clears stale scan-bound post, Community,
notes, media, and action state from the previous record; a transient lookup miss
for the same scan preserves its snapshot while SwiftData contexts propagate.

Both direct Explore and Ask the Community additionally require a resolved,
non-Human biological subject in the live `SpeciesData` and persisted-record
snapshot. The shared identity policy recognizes Human common names, canonical
`Homo sapiens`, malformed `Homo sapien`, and Human user overrides; unresolved
sentinels such as “Unknown Subject,” “Taxonomy Unavailable,” and “Unidentified
Wildlife” also fail eligibility. The authenticated Edge routes repeat the same
decision from the owner row, so a stale client or direct request cannot publish
Human, unresolved, or non-biological data.

Each persisted-record presentation also has a monotonic action generation.
Changing records invalidates the prior generation, dismisses scan-bound editors
and confirmations, and clears their busy flags. Explore publication, post
content and field-note edits, Community creation and editing, and authoritative
share-state detail refresh capture both the scan ID and generation. Their
success and failure paths revalidate both after every network await, so an older
response may update only its scan-keyed global cache and cannot overwrite the
newly presented observation. Same-scan user mutations advance the share-state
revision so an older detail refresh cannot restore stale hashtags, privacy, or
field-note visibility. Post and Community mutations additionally retain the
exact post or request UUID they addressed; a same-scan topology change cannot
let an older response update the replacement publication.

Detail hydration also requires the decoded response to echo the exact requested
post or Community request UUID. A mismatched Community response leaves the
editor draft intact and reports the normal invalid-response error; a mismatched
advisory post detail is ignored without weakening the already confirmed Share
state.

`InsightShareButton` has an independent action generation for its nested
options, warning, and composer sheets. Opening Share captures the scan ID and
the parent view model's presentation generation. Each nested options, warning,
composer, and failure presentation also retains that exact component action
generation, and its binding may dismiss only the matching token. Changing the
scan or parent generation advances the component generation, dismisses every
nested presentation, and clears pending actions and drafts. Every callback
compares the captured parent generation directly, so it is stale even before
SwiftUI delivers `onChange`. Composer-media hydration and asynchronous
publication completion revalidate all values before opening or closing a sheet.
The Insight-owned Explore editor, Community editor, Field Notes editor, delayed
Explore onboarding prompt, and New Collection alert also capture the view
model's exact scan ID and presentation generation. This closes both ordinary A →
B switches and A → B → A callbacks where the UUID happens to match again but the
original presentation no longer owns the UI.

The delayed onboarding prompt is one explicitly retained main-actor task, not an
unstructured fire-and-forget timer. Repeated completion evaluation for the same
scan/generation leaves the original deadline intact. Reset, scan-bound state
invalidation, or an ineligible result cancels and releases it; the wake path
revalidates identity, current share recommendation, and the persisted one-time
flag before changing presentation state.

When an Insight-hosted Explore sheet opens the current user's published post,
the post detail reports only the scan ID. The Explore shell owns its dismissal,
and the enclosing Insight stages and applies that scan only from Explore's real
`onDismiss`. A leaf view must not call `dismiss()` for a presentation owned by
its parent.

The same boundary covers callbacks outside the nested Share component. Toolbar
collection/export/Field Chat/identification/review/reanalysis/delete actions,
media and audio controls, local-gallery and Wikipedia/Safari sheets, common-name
and candidate modals, copied Explore-composer submissions, and toast actions all
retain an immutable scan/generation target. A queued result handoff advances the
generation even when the completed record reuses the same UUID, so controls
created by the queued presentation cannot act on the result presentation. Stale
dismissal callbacks clear only their captured presentation, never a newer one.

The delayed result-toolbar reveal and completed Field Notes synchronization use
that generation as their SwiftUI task identity. Keying either task to the stable
UUID would leave it canceled after an in-place queued-to-completed promotion and
could hide Share or retain stale notes until the user reopened the observation.
Every queued destination bind also prefers a persisted completed record with the
same UUID over its retained navigation snapshot.

An authoritative share-state `404` activates compatibility behavior only when
the handler supplies stable `code: "not_found"` (or the narrow released-response
fallback has no stable code). That outcome proves an absent owner row cannot own
a valid Explore post or Community request, so the client clears only that scan's
obsolete local publication marker. The toolbar then offers normal publication,
whose deliberate user action enters the guarded owner-row and media recovery
sequence below. Availability, malformed, foreign-code, and unconfirmed responses
preserve the optimistic cache.

Normal publication:

1. snapshot the local record into the private value-only
   `ScanPublicationSnapshot`;
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
when an eligible resolved non-Human biological scan has only video or audio.

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

When the ordinary share returns a handler-owned `404` with stable
`code: "not_found"` (or a released-backend `Scan not found` message without a
stable code), the network client:

1. polls `/check-scan-status`;
2. leaves active or retryable richer ingestion authoritative;
3. refuses policy rejection, deletion, and ambiguous/unknown state;
4. resolves every surviving local observation-media path and validates the
   complete mixed-media count and byte budget, refusing owner-row reconstruction
   when no eligible bytes survive;
5. resolves a server species UUID from the local scientific name;
6. builds bounded non-media `OwnedScanRecoveryPayload` using the authenticated
   persisted Auth owner;
7. asks single-scan status recovery to commit the guarded owner row and requires
   an authoritative `found` response; and
8. uploads only the prevalidated local user-media plan through the normal
   owner-authoritative staging signer.

A handler-owned `503 service_unavailable` on the recovery-capable status call
occurs before restore signing or media PUT. The client preserves the local
record/media and presents retry; it does not treat that response as owner-row
creation. Production must first prove both service-only recovery RPCs reach
their exact no-write validation boundaries.

The local plan is read-only and requests no signing URL. This fail-before-
mutation boundary prevents a 404 durable URL, missing local file, empty file, or
over-budget legacy snapshot from creating an empty completed cloud observation
that cannot subsequently publish.

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
`media_reconciliation_abandoned` together with the matching composite
dead-letter/quota/media-lifecycle proof. Signing obtains that decision from a
bounded service-only proof RPC; malformed/error responses fail before a URL is
returned. An existing row must be active and JWT-owned; a genuinely absent row
may only stage for the later guarded reconstruction. Current/later policy,
unproven media abandonment, unknown/arbitrary terminal state, a tombstoned or
foreign scan, and an ordinary post-completion upload remain rejected. The
service-only recovery transaction independently requires the same proof, shares
the ingestion generation lock, honors deletion tombstones and ID collisions,
never overwrites an existing row, and commits the owner row plus completed
ledger together. Historical promoted capture rows do not consume this repair's
active six-item staging budget. Every current key must also match an
authoritative capture-upload ledger row for the exact authenticated owner, scan
ID, media kind, and role before the server reconstructs the owner row or
promotes any object. This prevents an owner key from another scan or a signed
audio/video key relabeled as an image from crossing into publication.
Compatibility with released clients that signed before ledger registration is
limited to their exact deterministic scan/category filename and legacy
extension-derived kind.

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
Insight. The follow-up post-detail read is advisory: transport or availability
failure preserves the last confirmed or optimistic hashtags, privacy, and
field-note visibility rather than treating a failed read as proof that public
notes became private.

## Verification

Run the focused Sharing and affected Shell suites after regenerating the
project:

```bash
make xcodegen
xcodebuild -project merian.xcodeproj -scheme Merian \
  -destination 'id=<BOOTED_SIMULATOR_ID>' \
  -only-testing:merianTests/InsightSharingPresentationTests \
  -only-testing:merianTests/InsightSharePresentationModelTests \
  -only-testing:merianTests/InsightSharingOperationStateTests \
  -only-testing:merianTests/CommunityIdentificationRequestViewModelTests \
  -only-testing:merianTests/InsightExploreSharingViewModelTests \
  -only-testing:merianTests/InsightSharingCacheRefreshTests \
  -only-testing:merianTests/InsightSharingArchitectureTests \
  -only-testing:merianTests/InsightShellPresentationTests test
```

`InsightSharingArchitectureTests` enforces folder ownership, platform-neutral
Models, Services-only live resolution, the Views/Components networking ban,
aggregate removal, and the 600-line production-file ceiling.
`InsightSharingCacheRefreshTests` owns missing-cache clearing and preservation
of a restored Community request; those assertions no longer live in the Field
Notes state suite.

For shared post-detail transport changes, also run the
[Core Network browsing matrix](../../../Core/Network/README.md#endpoint-verification).
It includes Sharing's publication and cache-refresh state suites alongside the
endpoint request/response and transport tests.

For publication, owner-row recovery, or restored-media changes, run the
[Core Network scan-publication matrix](../../../Core/Network/README.md#scan-publication-and-owned-recovery-verification)
as well as this feature matrix.

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
