# Core Network

This directory owns Merian's certificate-pinned foreground network client,
including authenticated endpoints, capability-only deletion recovery, and signed
uploads. Durable background uploads and replay scheduling live under
`Core/Data/OfflineSync`.

## Environment selection

`SupabaseManager` is initialized from the typed `MerianEnvironment`
configuration. Missing or invalid Supabase values keep app startup non-crashing
but block real endpoint construction. A Debug simulator that resolves to the
known production Supabase host is different: the configuration remains valid,
and the app logs a conspicuous production-use diagnostic while auth, reads, and
writes continue.

Use matching local/staging URL and client-key overrides in ignored
`Config.local.xcconfig` for routine simulator work. For a deliberate production
smoke test, the Xcode Run environment variable
`MERIAN_ALLOW_PRODUCTION_SUPABASE_IN_DEBUG_SIMULATOR=1` suppresses only the
diagnostic. It does not redirect traffic, isolate rows, or prevent a cleared
session from creating an anonymous production user.

Every resolved Supabase origin must be credential-free HTTPS.
`MerianEnvironment`, `MerianSupabaseClientFactory`, and `MerianNetworkClient`
enforce `SecureTransportPolicy` before constructing a client or Edge endpoint.
Signed upload URLs and remote media references are validated at their
corresponding request boundaries. The main application has no ATS exception; see
the
[iOS App Transport Security Contract](../../../../../docs/development-guides/17-ios-transport-security.md).

## Explore model ownership

[`Models/Explore/`](Models/Explore/README.md) owns the focused Codable response
and request-value families shared by Explore endpoints and their cross-feature
consumers. The former `ExploreAPIModels.swift` aggregate is retired. Browsing,
Community Identification, author profile, Map, post-detail, comments, sharing,
media-incident, notification, public-profile, and Community-feedback contracts
now have separate owners, each below the 600-line review ceiling.

This is a source-ownership split only. Type names, access levels, Codable
conformances, coding keys, defaults, compatibility fallbacks, endpoint
signatures, and JSON shapes are unchanged. The cross-feature
`ExploreLocationPrivacy` redaction policy lives in
[`Core/Models/ExploreLocationPrivacy.swift`](../Models/ExploreLocationPrivacy.swift)
because environment context, inference/recovery, Explore, Insights, and Profile
all consume it; no wire model owns that privacy policy.

`ExploreNetworkModelArchitectureTests` freezes the thirteen-file inventory, sole
representative declaration ownership, retired aggregate, effect exclusions,
privacy-policy placement, and line ceiling. It also keeps the Codable
`ExplorePostLocationSharing` contract in Core Network while its labels, symbols,
and explanatory copy remain in Explore Shared presentation. Wire decoding and
endpoint tests remain with their existing Core Network suites, while feature
presentation and state tests retain their feature owners.

## Field Trips model ownership

[`Models/FieldTrips/`](Models/FieldTrips/README.md) owns eight focused Codable
and request-value families for achievement, capture, catalog, Events, community
queries, profile, progress, and publications. The former
`FieldTripAPIModels.swift` aggregate is retired; all 49 network-model
declarations retain their names, access, conformances, coding behavior,
fallbacks, endpoint signatures, and JSON shapes.

Feature presentation extensions live in `Features/Explore/FieldTrips/Models`.
Insights Shell owns contribution-route projection, Core UI Feedback owns
milestone/progress policy, and Core Preferences owns the account-qualified
achievement cache. `FieldTripNetworkModelArchitectureTests` freezes those
boundaries, production-wide exact declaration ownership, the retired aggregate,
effect exclusions, and the 600-line model ceiling. Existing Field Trips
decoding, endpoint, feature, Insights, feedback, and preference suites retain
behavior coverage.

## Supabase Auth cold-start adoption

`MerianSupabaseClientFactory` enables `emitLocalSessionAsInitialSession`. The
pinned Supabase Swift SDK therefore emits the cached session immediately,
including a session whose access token is expired, and refreshes an expired
session in the background. `AuthTransitionPolicy.authSessionAdoption` classifies
the initial value. `SupabaseManager` advances the `AuthRuntimeState` generation,
maps the SDK value into a provider-neutral `AuthSessionLifecycleEvent`, and
delegates its observable projection to `AuthSessionLifecycleCoordinator`:

- no session is `.signedOut` and may resolve required-consent restoration as
  unauthenticated;
- a non-expired session is `.authenticated` and may start entitlement, identity,
  and synchronization work; and
- an expired session with a user is `.awaitingRefresh`. Authenticated request
  and RevenueCat mutation readiness remain closed and `currentUser` remains
  unset, but the known user ID is passed to `ConsentManager` so a completed user
  stays on the launch-matched restoration root.

The SDK's later `tokenRefreshed` event adopts the valid session through the
normal authenticated path and re-resolves the purchase identity. A terminal
refresh-token cleanup emits `signedOut`, immediately closes RevenueCat session
readiness without creating a provider-anonymous customer, and only then
establishes that no active account remains. Never route an expired cached
session through sign-out cleanup: doing so can briefly resolve restoration and
mount the Ready approval screen before refresh completes.

## Auth-transition foundation

[`Auth/`](Auth/README.md) owns the value-only transition models and errors,
Guest-presentation and transition-decision policies, exact-session account-work
lease coordinator, exclusive transition coordinator, and main-actor sign-out
single-flight. `AuthRuntimeState` composes those values as the effect-free,
observable main-actor owner for transition state, Auth generation,
transition-analytics generations, exact-session lease/drain state, and the local
sign-out flag. It also owns account-deletion stable-error and cached-session
classification plus pure phase sequencing and separate dependency-injected
fresh-deletion and recovery coordinators, purchase-safe sign-out routing and
phase order, stable and compatibility handoff completion keyed by destination,
Auth generation, and transition owner, pending-proof/source-restoration/retry
policy, ghost-profile queue/error policy plus finalization ordering, and
provider-neutral OAuth credentials/metadata, token-subject policy, session-
replacement/Apple-registration workflow, shared completion coordinator, and
provider-presentation admission coordinator. The fallback authentication
callback dependency package and coordinator separately own callback transition
admission, anonymous/different-account refusal, replacement reconciliation,
purchase/entitlement order, final exact-session verification, and mutation-aware
cleanup without creating a task. Focused Auth Services own the Apple/Google SDK
presentation, value mapping, Apple controller/nonce boundary, shared window
policy, provider and callback diagnostics, and a typed Apple credential-
registration boundary whose live adapter alone owns the Function wire DTOs and
invocation. The task-free `SupabaseAuthSessionService` owns provider-credential,
fallback-callback URL, canonical profile-metadata, and recovery-session
adaptation; its live adapter alone performs the request-scoped Auth session
read/current snapshot, refresh, identity link, ID-token or callback-URL
installation, metadata update, and local sign-out calls. The focused bootstrap
service projects cached, loaded, and newly anonymous SDK sessions and owns
missing-session classification; its `+Live` adapter alone performs bootstrap
session reads and anonymous sign-in, while its diagnostics owner retains the
established privacy-safe log copy. The provider-neutral Auth-session bootstrap
snapshot/dependency package and keyed coordinator own reusable-session
admission, sign-out/quiescence waiting, complete-token exact-context task
sharing, pre-session cancellation fencing, true-missing-only anonymous creation,
publication, purchase readiness, and final exact-session validation. The
recovery dependency package and coordinator own ordinary and transition-owned
exact-session refresh, anonymous replacement recovery, and terminal local
cleanup behind account-work, cancellation, transition, purchase-handoff, and
final-session fences. Terminal cleanup snapshots the expected session before
quiescence, repeats the expected/current-session check afterward, and reports a
typed cleared, rejected, or purchase-handoff-blocked outcome instead of
conflating admission with completed cleanup. The separate local-sign-out
coordinator owns ordinary and account-cleanup retained task lifetime and exact
cleanup order. Both paths use the shared Auth session adapter, whose live file
also owns their established privacy-safe diagnostics. The lifecycle models,
dependency boundaries, and coordinator own deletion/transition deferral,
fail-closed durable-fence projection, authenticated/awaiting-refresh/signed-out
state order, purchase and entitlement sequencing, immediate local
server-verified entitlement projection closure behind an accepted deletion
barrier, and historical-sync admission. Sign-out recovery drains account-bound
work before session-bound completion, and the phase workflow rejects
cancellation between preparation, local sign-out, anonymous initialization, and
completion. The OAuth coordinator owns direct same-UUID linking versus
provider-bound Ghost fallback and the common metadata, purchase, entitlement,
public-author, and marker sequence. It requires an Apple credential-registration
effect, rejects one for Google, and requires the owned transition to name the
credential provider before session mutation. The public-author refresh
dependency package and coordinator own transition-owned refresh plus the keyed
restored-session Ghost-completion/refresh/event sequence behind nested
account-work and exact-current-user fences. Stale scheduling targets cannot
replace current-user work, and cancellation is checked before lease/remote
admission and after remote suspension. The task-free fallback authentication URL
coordinator stops a cancelled caller after preflight, reconciles the SDK's
actual session after installation, and refuses adoption or publication when
sign-out starts during that installation. Purchase and entitlement continuations
retain cancellation and exact-session fences. `SupabaseManager` remains the live
Supabase Auth facade and effect assembler; it delegates transition state to
`AuthRuntimeState`, retains the focused lifecycle provider, preserves the public
Apple/Google and fallback-URL entry points, and injects Auth-listener,
bootstrap, recovery, callback coordination/error, the shared Supabase Auth
session service and its callback-install operation, exact-session registration
assembly, consent, purchase-identity, endpoint, Keychain, sign-out, handoff,
purge, logging, and lifecycle effects into the focused coordinators. Source-side
purchase-proof preparation, exact-session abandonment/restoration, and aggregate
fail-closed projection live in `PurchaseIdentitySourceHandoffCoordinator`;
cancellation during compatibility preparation's final SDK-session read cannot
report success or discard the already-durable proof. Its focused Auth journal
adapter owns established error translation. Core Security's
`PurchaseHandoffPreparationCoordinator` owns stable and compatibility proof
construction and durable checkpoint order. The separate live public-author
effects adapter is the sole application-event and privacy-safe log owner for
that sequence. Its public bootstrap entry point remains SDK-typed while task
state is coordinator-owned. Core Security's
[`GhostProfileMergeStore`](../Security/GhostProfileMerge/README.md) owns the
ghost handoff/queue codecs, legacy migration, validation, device-only verified
persistence, and removal. Its
[`PurchaseIdentityHandoffStore`](../Security/PurchaseIdentity/README.md) owns
the two purchase-handoff journal codecs, validation, device-only accessibility,
verified writes, and removal. The provider-neutral extracted owners import no
provider SDK or resolve a singleton; focused live-provider Services are the only
Auth owners allowed to acquire Apple/Google/UIKit framework dependencies. All
preserve externally consumed signatures, error copy, actor isolation, and
successful transition behavior. Bootstrap admission is intentionally narrower:
cancelled callers and callers holding a stale or replaced complete transition
token cannot begin or join session work. Direct anonymous provider linking is
complete only after the SDK exposes a permanent session for the same UUID and
the active transition adopts and revalidates it; provider-bound ghost-merge
recovery remains durable until that commit point.

Task ownership is explicit: Auth owns the sign-out single-flight, bootstrap,
keyed purchase-handoff, keyed Ghost-merge, keyed public-author-refresh,
lifecycle replay, Apple credential-revalidation, Apple OAuth-completion,
SDK-listener, and historical-synchronization tasks. `SupabaseManager` retains
the lifecycle and history services plus the local-sign-out coordinator. The
latter owns the retained single-flight task; its focused live adapter alone
invalidates the local Supabase session. The lifecycle coordinator admits
listener-driven purchase, entitlement, and historical-sync effects only while
the exact manager-published user, nonexpired SDK session, Auth-event generation,
and absence of an active Auth transition remain current after suspension. The
retained history service repeats that fence before each account-leased
synchronization and cancels every outstanding task at facade teardown. Its
`+Live` adapter is the reviewed Auth composition owner of
`AppDIContainer.shared` for offline-queue context and scan-repository
acquisition. Anonymous bootstrap uses the same publication fence after
complete-token task admission. Loaded and newly created bootstrap sessions
repeat cancellation immediately after purchase readiness before returning an
identity. Coordinator-owned replaceable public-author refresh uses a target
account plus task UUID and compare-before-clear cleanup, and records completion
only after the exact session succeeds. Direct linking checks cancellation in the
OAuth coordinator; replacement checks both sides of its synchronous
analytics-suppression boundary, and a cancelled boundary reconciles the current
session without invoking SDK replacement.

Authenticated-request recovery creates no task of its own. It captures the
transition's exact expected session before quiescing account work, then repeats
cancellation, ownership, and session checks after SDK refresh/load, purchase
readiness, entitlement, and final SDK readback. A transition-owned refresh never
opens or finishes a nested transition or relinks purchase/public-author state.
Local cleanup preserves any pending purchase handoff and, once SDK sign-out has
started, completes observable, secure-marker, analytics, and purchase cleanup
even if the SDK call fails or cancellation arrives.

## `MerianNetworkClient`

Field Trips, Community Identification browsing/contribution, Explore browsing,
Explore interactions, notifications, public-profile operations, Explore post
management, inference, scan publication, Field Chat, Species Dictionary, scan
lifecycle, collection sync, scan enrichment and deferred context, exports,
product feedback, media storage, and account deletion live below `Endpoints/`.
Inference request values, JSON/media/account policy, and the narrow
identification-review PostgREST/RPC adapter live in `Inference/`. Raw signed
uploads, foreground video planning, and publication-media restoration live in
`Media/`; owned-row publication and Field Chat recovery live in `Recovery/`;
stateless endpoint URL, route/error classification, retry allowlist, account
binding, value-only Auth-recovery decisions, and the request-scoped executor
live in `Transport/`. The executor owns logical request construction, bounded
retry state, cancellation checkpoints, response mapping, and injected Auth,
entitlement, and consent effects. `PinnedNetworkTransport` owns the sole
configured `URLSession`, lock-backed one-time initialization, exact Supabase
host/subdomain policy, TLS delegate, raw dispatch, caller-bounded wall-clock
dispatch, and DEBUG session override. Supabase server-trust challenges require
both the platform trust evaluation and a matching pin, and fail closed when
either check fails or the certificate chain cannot be read. Unrelated hosts and
non-server-trust challenges keep the platform's default handling.
`AuthenticatedTransportDispatcher` owns per-attempt Auth leases and headers,
transition validation, the constrained-network header, and its file-local upload
delegate. `MerianNetworkClient.swift` retains configuration diagnostics and
injects both stateful transport owners behind narrow bridges. Endpoint
extensions use those bridges to construct the endpoint, serialize the payload,
and invoke the existing authenticated POST. Typed calls decode with the existing
snake-case decoder; body-ignoring calls preserve HTTP-only success without
decoding. The typed bridge can forward an existing idempotency key and replace
decoding failures with a caller-specified `MerianError`; both options default to
nil. Error replacement surrounds only decoding, never request construction,
transport, auth, or cancellation.

`ScanAdmissionManager` is the one non-Edge PostgREST consumer admitted through
the facade. Its bridge accepts only
`POST /rest/v1/rpc/get_my_scan_admission_preview` on the configured Supabase
origin with a nonempty bearer credential and nonempty anon API key, then
dispatches through the same pinned session. It exposes no general raw-request
capability, refresh, or replay. The transport applies the preview's two-second
request and wall-clock deadline plus no-cache policy; PostgREST keeps retry
disabled. `performAuthenticatedEncodedJSONPost` encodes an `Encodable` body with
`JSONEncoder` and returns bytes for domain-specific validation. It forwards the
timeout and optional idempotency key without catching encoding, transport, or
cancellation errors. Classified-401 recovery remains enabled by default. A
durable caller that is itself part of Auth-transition quiescence may explicitly
defer that recovery so it cannot recursively await its own task; the original
HTTP failure then returns to that caller's retry policy. None of these bridges
adds a retry or task owner or exposes mutable transport state.

`performAuthenticatedJSONDataPost` serializes an untyped JSON body and returns
bytes for scan lifecycle's explicit-key decoder. Its optional expected Auth user
ID flows into the same private transport, keeping recovery account-bound without
exposing Auth leases, constructing a second session, or catching errors. Like
the encoded bridge, it permits an endpoint whose durable caller already owns an
outer account-work lease to return a classified `401` to that caller instead of
starting recursive Auth recovery.

`performAuthenticatedPreparedJSONPost` forwards an already-serialized JSON body,
timeout, and optional idempotency key without changing bytes or adding
validation/replay. Enrichment checks configuration, serializes its payload, and
validates the scan UUID before this bridge; that ordering preserves the existing
configuration, serialization, and invalid-ID failure precedence. The endpoint
owns plain response decoding, while the bridge keeps transport private.

`performAccountBoundEncodedJSONPost` checks endpoint configuration, captures the
explicit or privately resolved Auth UUID, and passes that UUID to a nonescaping
body builder before encoding. It forwards the same UUID to private authenticated
transport. This does not bypass current-session resolution or live Auth leases.
The two `performPresignedUpload` overloads forward a prepared request through
the same private session, using `data(for:)` or file-backed
`upload(for:fromFile:)`. They add no Auth headers, refresh, retry, cancellation
mapping, or task owner.

The private `performAuthenticatedJSONGet` accepts ordered query items, uses the
same authenticated transport, and decodes a typed response without mapping
errors. Dictionary detail and stats use the fixed-result
`performCachedSpeciesDictionaryRequest` and
`performCachedSpeciesObservationStatsRequest` bridges. Only these bridges can
read the client's private cache instance or insert a network response after the
fixed schema/identity validator accepts it; they accept no cache object,
response DTO, custom loader, or insertion callback. Dictionary implementations
call the internal `Void` `validateEndpointConfiguration` guard before input
validation or cache lookup to preserve missing-configuration error precedence.
It exposes no URL or mutable state and adds no cancellation check; a cache miss
then enters the existing authenticated transport through the appropriate bridge.

`Endpoints/MerianNetworkClient+FieldTrips.swift` owns all Field Trips request
actions and typed response projections, including cross-feature capture,
profile, achievement, and feed callers.

Codable Field Trips contracts live in eight focused owners under
`Models/FieldTrips/`; `Features/Explore/FieldTrips/Services` retains feature
dependency adapters and presentation-facing endpoint values. Existing client
methods, argument defaults, actions, optional/null fields, cursor rules, and
timeouts are unchanged. Request filters reuse Core's
`String.trimmedNonEmptyValue`; publication and comment text is still forwarded
without transport-level trimming.

`MerianTests/Core/Network/Endpoints/FieldTripEndpointTests.swift` exercises
these methods with a private client and scoped mock session per case, covering
request mapping, typed decoding, errors, refresh, ambiguous-failure replay
refusal, and pre-dispatch cancellation. Payload comparisons ignore object-key
order but preserve Boolean/number/string and null/omission distinctions.
`MerianNetworkArchitectureTests.swift` guards the endpoint owner and private
transport boundary. Run the canonical
[Field Trips verification matrix](../../../../../docs/features-and-hardware/25-field-trips.md#verification)
and the complete `merianTests` target; DTO decoding remains in
`FieldTripAPIModelsTests`; `FieldTripNetworkModelArchitectureTests` freezes the
model boundary; `FirstFieldTripProgressStoreTests` owns the compatibility cache;
and feature state/presentation tests stay feature-owned.

### Inference endpoints, payloads, and policies

[`Endpoints/MerianNetworkClient+Inference.swift`](Endpoints/MerianNetworkClient+Inference.swift)
owns the existing `/identify` compatibility request, `/identify-multimodal`
request construction and dispatch, pinned-session prewarm, consent preflight,
and the queue-backed 15-second (30-second Pro trial) versus direct 90-second
transport selection. Public method names, defaults, request-body completion
behavior, entitlement protocol, stable idempotency keys, and Auth-account
fencing are unchanged. The three off-main body-preparation blocks use
`DetachedWork.value(category: .inferenceRequestPreparation)` so cancellation of
the owning request reaches the detached handle. The endpoint checks cancellation
before and after JSON construction and between inline-audio file reads; the
stateless payload and policy owners remain task-free.

The sibling [`Inference/`](Inference/) folder contains value/stateless request
concerns plus one explicitly state-free live adapter. `InferencePayloadBuilder`
owns the shared telemetry, observation-context, media-descriptor,
owner-timeline, preferred-goal, and geoprivacy JSON mapping.
`InferenceMediaPolicy` owns inline image/audio and WAV file limits.
`InferenceRequestPolicy` owns staged-object owner checks and the stable
recoverable-conflict allowlist. `InferencePayloadContext` and
`AuthenticatedInferenceRequest` carry immutable values across suspension. These
owners acquire no session, Auth manager, consent manager, app container, or task
lifetime.

`InferenceIdentificationReviewService` separately owns exact-name
`species_dictionary` reads and the `update_owned_scan_identification_review`
RPC. Its immutable injected closures acquire one account-work lease per
operation, verify that lease after the network suspension, and expose only typed
records/mutations to `InferenceIdentificationReviewCoordinator`. Review
mutations can be built only through coherent override, confirmation, and reset
factories. Their typed `UserReviewState` encodes the existing raw enum string,
including the existing explicit nulls, without changing the wire contract. The
Core AI review workflow owns registered review-task ordering, while the
action/effect coordinator sequences local persistence before this transport and
its live adapter owns post-success effects. `InferenceEngine` retains stable
public entry points. `InferenceSpeciesPresentationCoordinator` owns observable
commits and supplies current species, presentation generation, exact-identity
checks, and write admission through the workflow's one hydration callback
bundle; neither owner contains interactive review timing or a direct Supabase
query.

`Transport/` owns pure endpoint URL, classification, account-binding, and
value-only recovery/replay decisions plus the request-scoped executor that
applies them. Its pinned transport owns the one session/TLS boundary, and its
authenticated dispatcher owns per-attempt Auth/session validation and upload
progress. Five narrow inference bridges expose only prepared bytes, request
values, timeout/replay choices, and the exact expected Auth UUID. The endpoint
cannot access mutable transport state or create another session. See the
[focused matrix](#inference-verification).

`Endpoints/MerianNetworkClient+CommunityIdentification.swift` owns the eight
request feed, activity feed, detail, request-editing, taxonomy-search, and
submit/withdraw/restore operations. Codable DTOs and cursor wire values live in
`Models/Explore/CommunityIdentificationAPIModels.swift`. Identify and Insight
Sharing Services retain their live adapters. The two
`requestCommunityIdentification` scan-publication overloads are intentionally
separate in the scan-publication and owned-recovery owners described below.

This split preserves the 30-second timeout, snake-case projection, explicit null
note/reasoning fields, optional taxonomy version, and raw caller text. Cursors
are emitted only when both fields are nonnil; coordinate arguments remain
independently forwarded, with pairing validation owned by the backend. Ambiguous
replay stays on the existing feed/activity/detail/taxonomy-search allowlist.
Taxonomy search can enrich the backend cache; its existing allowance does not
make it a pure read. Editing and contribution mutations do not replay after
ambiguous transport or server failures. No endpoint adds an idempotency key,
caller identity field, direct RPC, or UI policy.

`MerianTests/Core/Network/Endpoints/CommunityIdentificationEndpointTests.swift`
owns 32 payload cases plus typed response, malformed-success, denial, refresh,
replay-allowlist, and cancellation coverage. It rehomes the previous
feed/activity/edit endpoint regressions from `MerianNetworkClientTests`.
Distinct submit/withdraw/restore fixtures retain lifecycle timestamps. Repeated
network/503 failures and failed post-refresh 401/503 responses guard the shared
single-replay budget; handler denials explicitly forbid refresh. Nonzero,
out-of-range coordinate sentinels verify forwarding without real location data.
The suite uses the shared endpoint fixtures and assertions described under
[Endpoint verification](#endpoint-verification). The architecture suite protects
source owners and keeps scan publication separate. Run the
[Identify focused matrix](../../Features/Explore/Identify/README.md#verification)
and the complete unit target. For shared bridge or test-support changes, follow
[Endpoint verification](#endpoint-verification) to cover all extracted groups.
These tests do not replace backend authorization or Activity projection
verification.

### Scan publication and owned recovery

[`Endpoints/MerianNetworkClient+ScanPublication.swift`](Endpoints/MerianNetworkClient+ScanPublication.swift)
owns the direct scan-ID overloads for `/share-scan-to-explore` and
`/request-community-identification`. It maps the existing payloads, forwards one
stable idempotency key, decodes with the shared snake-case decoder, and rejects
contradictory success envelopes. It contains no local-record, filesystem,
upload, Supabase query, or retry orchestration.

[`Recovery/MerianNetworkClient+OwnedScanRecovery.swift`](Recovery/MerianNetworkClient+OwnedScanRecovery.swift)
owns the two record-based compatibility overloads, status polling, missing-row
classification, bounded owner-row payload construction, species-ID lookup, and
Field Chat cloud-readiness preflight. Its immutable private snapshot severs the
recovery task from mutable `LocalScanRecord` state. Persistence polling is
cancellation-owned by its caller: cancellation before a status probe, while a
probe is in flight, or during a retry delay propagates as `CancellationError`
and cannot resume recovery or issue another status request.
[`Recovery/OwnedScanRecoveryPayload.swift`](Recovery/OwnedScanRecoveryPayload.swift)
retains the unchanged encoded recovery contract, while
[`Recovery/OwnedScanRecoveryPolicy.swift`](Recovery/OwnedScanRecoveryPolicy.swift)
contains the deterministic ingestion-state admission policy. The recovery owner
can read the existing default-geoprivacy and species lookup dependencies, but it
does not construct `URLRequest` values, acquire transport, inspect the
filesystem, or upload bytes. A value-only client bridge obtains the current
persisted owner through the authenticated dispatcher's private Auth boundary.

[`Media/ScanPublicationMediaRestorer.swift`](Media/ScanPublicationMediaRestorer.swift)
owns immutable local-media planning, file resolution, MIME inspection, signed
upload preparation, and bounded image upload concurrency.
[`Media/ScanPublicationMediaRestorePolicy.swift`](Media/ScanPublicationMediaRestorePolicy.swift)
owns retryable restoration-error classification, count/byte validation, and the
`scan_share_restore` signing projection. The restorer reuses the extracted
signing and raw PUT methods; it does not own publication, status recovery,
idempotency, or UI state.

This is a source-ownership split only. Public method signatures and defaults,
JSON fields, response validation, one-key retry identity, polling delays,
recovery eligibility, media order and limits, upload behavior, customer copy,
and backend authorization are unchanged. Insights Sharing and Identify Services
keep their injected adapters, and Field Chat keeps presentation state. See the
[focused matrix](#scan-publication-and-owned-recovery-verification).

### Explore browsing endpoints

`Endpoints/MerianNetworkClient+ExploreBrowsing.swift` owns eight stateless
reads: `getExploreFeed`, `getExploreMapPoints`, `getExplorePost`,
`getExplorePostDetail`, `getExploreAuthorProfile`, `getExploreAuthorPosts`,
`getExploreHashtagPosts`, and `getExploreSpeciesPosts`. Feed, Map, Author
Profile, Profile, Species Dictionary, Insights Sharing, and the tab badge keep
their existing callers; feature Services and ViewModels still own adapters and
state. Comments, mutations, notifications, composer media, publication/recovery,
and Species Dictionary identity validation/caching remain outside this
extension.

This split changes no signatures, DTOs, defaults, route names, or 30-second
timeouts. Feed categories retain presentation-priority ordering; Map categories
and both media-filter arrays retain lexical ordering. Feed coordinates are
forwarded independently, radius is included only for Nearby, and `shared_since`
uses the caller-supplied cutoff with `DateUtilities.iso8601Formatter`. Transport
does not derive that cutoff from the UI date filter. Paired cursors require both
fields, while a Feed ranking value is independent. Species pagination retains
its distinct quality-score cursor and omits only a nil score. Blank strings,
zero scores, raw IDs/hashtags, and caller limits are forwarded without new
validation or normalization. Author/species pages and Map keep their full
response envelopes; array/detail methods preserve their existing projections.
All eight routes retain their existing ambiguous-failure replay allowance.

`MerianTests/Core/Network/Endpoints/ExploreBrowsingEndpointTests.swift` owns 40
independent request cases and typed response regressions, including the nine
rehomed Feed/Map/author/species request tests. It locks response order,
media-only cards, public/owner profile metadata, Map mode/facets, and server
cursors even on empty pages. `ExploreBrowsingEndpointTransportTests.swift`
checks malformed success, handler denials without refresh, one auth-refresh
replay, bounded network/503 replays, failed replays, and pre-dispatch
cancellation for every route. These suites reuse the isolated shared fixture;
standalone Explore DTO decoding remains in `Models/Explore/`, while presentation
and state tests retain their feature owners. The architecture suite guards the
exact eight-method inventory and private transport boundary.

### Explore interaction endpoints

`Endpoints/MerianNetworkClient+ExploreInteractions.swift` owns 12 methods:
comment/reply/mention reads, likes, follows, comment
creation/deletion/reactions, post/comment/user reports, and blocking. Feed,
Author Profile, Notifications, Identify, and `Core/Security/SocialGuardManager`
retain their existing callers, interaction state, optimistic updates, and
presentation. Notification catalog operations, public identity edits, composer
media, post editing/unsharing, publication, and media recovery remain outside
this extension.

All signatures, 30-second deadlines, DTOs, and wire rules remain unchanged.
Comment/reply cursors require both fields; blank complete pairs are forwarded.
Limits, IDs, query/body/emoji text, and post/comment report text remain raw.
Only `reportUser` trims optional details and omits them when blank. Boolean
`false` remains a real payload value. Seven methods decode typed results,
including server counts, capabilities, mention/reaction metadata, and
caller-owned success flags. Five `Void` methods deliberately ignore any
successful 2xx body, including empty, malformed, or `success: false` bodies;
they must not acquire a dummy DTO or a new response-validation requirement.

The three reads retain one bounded ambiguous network/503 replay. The nine
mutations retain refusal to replay ambiguous failures without an idempotency
key, including server-idempotent follows/reports/blocks. Reaction toggle is not
an absolute-state setter. A classified refreshable 401 is a separate existing
auth path and permits one refresh/replay for all 12 methods.

`ExploreInteractionEndpointTests.swift` owns 41 independent request cases, typed
projection coverage, and six regressions rehomed from
`MerianNetworkClientTests`. `ExploreInteractionEndpointTransportTests.swift`
distinguishes seven decoding operations from five body-ignoring operations,
covers handler denials, refresh/replay ceilings, mutation replay refusal, and
both task-owned pre-dispatch and independent transport cancellation. The
architecture suite guards the exact 12-method inventory, stateless owner, and
both narrow POST overloads. All use the existing per-case fixture and retain
feature-owned state tests.

### Notification endpoints

`Endpoints/MerianNetworkClient+Notifications.swift` owns four methods:
`getExploreNotifications`, `getUnreadExploreNotificationCount`,
`markExploreNotificationsRead`, and `registerPushDevice`. Notification Services
and ViewModels under Explore retain catalog, pagination, and read-clearing
state; Core Notifications' `PushNotificationManager` retains OS permission and
token entry points, `PushRegistrationCoordinator` owns account-aware
latest-state registration draining, and `AppIconBadgeController` owns badge
refresh/cache state behind the source-compatible badge facade. Only their
focused Services call these endpoints.

The endpoint owner preserves caller limits, paired cursors (including a complete
blank pair), server row order, and top-level count projections without clamping.
Mark-read still decodes the required `success` field but returns `markedCount`
without interpreting that flag. Push registration sends all six existing fields,
including `platform: "ios"` and all three independent Boolean preferences, and
ignores successful response bodies. No token/environment normalization or new
response validation occurs in this layer. The Core Notifications account scope
is process-local coordination metadata and never enters this six-field payload.

### Public-profile endpoints

`Endpoints/MerianNetworkClient+PublicProfile.swift` owns four methods:
`updatePublicUsername`, `updatePublicDisplayName`, `updatePublicAvatar`, and
`checkPublicUsernameAvailability`. The shared `ProfileViewModel` retains live
client resolution, identity refresh/events, and cloud state. Avatar preparation,
upload signing, PUT, and account fencing stay with their existing owners; only
the final staging-key promotion request moves into this extension.

Strings, empty values, staging keys, and MIME types pass through unchanged.
Response values remain server-authoritative rather than request echoes. Clearing
the display name still sends an empty string and accepts the returned alias.
Username unavailability is a valid typed success response, and its optional
`error` remains optional. Backend normalization/validation and feature editor
feedback are not moved into transport.

Both owners preserve 30-second deadlines and the existing replay split: the
notification list, unread count, and username-availability reads allow one
ambiguous network/503 replay; the other five operations do not. All eight retain
the shared classified-401 refresh/replay path and cancellation behavior.

`NotificationEndpointTests.swift` owns 19 request cases and typed notification,
count, and mark-read projections. `PublicProfileEndpointTests.swift` owns 16
request cases and public-identity/availability projections. Together they rehome
four aggregate regressions with their names preserved. The protected
`MerianNetworkClientTests.testEdgeFunctionSelfHealingRefreshesInvalidSessionBeforeRetry`
selector remains in the aggregate suite because it tests shared Auth recovery,
even though its request uses push registration.
`NotificationAndPublicProfileEndpointTransportTests.swift` distinguishes seven
typed results from the body-ignoring push call and covers malformed success,
handler denials, refresh/replay ceilings, mutation replay refusal, and both
cancellation paths. The two owners share immutable test cases and the existing
per-case transport fixture. Fixture-local client overrides are isolated; the
suites never mutate shared-client overrides or global endpoint handlers. The
architecture suite guards their exact inventories and private transport
boundary.

### Explore post-management endpoints

`Endpoints/MerianNetworkClient+ExplorePostManagement.swift` owns six methods:
`getExploreComposerMedia`, `getExploreShareState`, `getExploreMediaIncidents`,
`unshareExplorePost`, `updateExplorePostFieldNotes`, and
`updateExplorePostContent`. Feed Services retain composer/edit/unshare adapters;
Insights Sharing retains composer hydration, share-state reconciliation, and
mutation fencing; Scans Shell retains private incident loading, account fencing,
and coalesced refresh. Direct publication, owned-row recovery, and local-media
restoration remain separate in their dedicated Endpoint, Recovery, and Media
owners.

All signatures, defaults, DTOs, and 30-second deadlines are unchanged. Composer
IDs are independently omitted only when nil, even when both or neither are
supplied. Legacy notes edits send only the post ID and nullable public notes.
Full edits preserve null notes, empty hashtags, raw ordered media selections,
nil-versus-empty media, and outer-whitespace-only common-name trimming and blank
omission. Private local notes and post-owned location policy stay with their
existing owners.

Share-state decoding and semantic validation still require matching scan
identity, coherent UUID/timestamp/Community topology, authoritative visibility,
and known location sharing. Hidden posts without Community requests remain
valid. Media incidents retain both the canonical object envelope and the exact
legacy direct array, including an empty array. Only these two methods map
decoding failures to `invalidResponse`; composer and edit DTO failures remain
`DecodingError`. HTTP/auth/cancellation failures are never replaced by that
mapping. Unshare continues to ignore every successful response body.

Validated share state is returned without changing a cache or publishing an app
event. [Insight Sharing](../../Features/Insights/Sharing/README.md) owns the
scan-keyed cache reconciliation, request/revision checks, and
presentation-generation fence for displayed state.

The three reads retain one ambiguous network/503 replay. Full content edits
generate one lowercase UUID per invocation, even without media, and preserve
that key and request body through auth or ambiguous-failure replay. Legacy
field-notes edits use the same route without a key and do not replay ambiguous
failures; unshare also refuses them. All six retain the shared classified-401
refresh and cancellation behavior.

`ExplorePostManagementEndpointTests.swift` owns 36 independent payload cases and
composer/edit projections. `ExploreShareStateEndpointTests.swift` and
`ExploreMediaIncidentEndpointTests.swift` own semantic and compatibility
coverage; together they rehome six direct endpoint regressions without changing
their names. `ExplorePostManagementEndpointTransportTests.swift` checks the
three-raw/two-mapped/one-body-ignoring response split, replay budgets, exact
body/key preservation, distinct keys across edits, denials, and both
cancellation paths. Four CI-required cases now name their new suite/type owners
in the critical-result validator and its adversarial fixtures. The mixed
incident/notification DTO test and Insight cache-clearing integration test stay
in `MerianNetworkClientTests`; the protected-case count is unchanged.

### Field Chat endpoints and validation

[`Endpoints/MerianNetworkClient+FieldChat.swift`](Endpoints/MerianNetworkClient+FieldChat.swift)
owns 17 public methods across three action-based routes: seven Insight methods,
five Explore-post methods, and five Species Dictionary methods. Its private
family helpers share the encoded-body POST bridge without acquiring session,
retry, task, or presentation state. Raw subject/message IDs, text, and notes
retain their existing encoding; nil optional request fields remain omitted.
`InsightChatAPIModels.swift` remains the Codable wire owner for all three
sources. The compatibility `InsightChat...` names and public signatures are
unchanged.

| Source             | Actions                           | Timeout    | Idempotency key                       |
| ------------------ | --------------------------------- | ---------- | ------------------------------------- |
| Insight            | load, delete                      | 45 seconds | None                                  |
| Insight            | send                              | 45 seconds | Caller-supplied `client_message_id`   |
| Insight            | answer feedback, feature feedback | 20 seconds | None                                  |
| Insight            | summarize notes                   | 45 seconds | One new lowercase UUID per invocation |
| Insight            | suggest prompts                   | 30 seconds | One new lowercase UUID per invocation |
| Explore post       | load, delete, answer feedback     | 20 seconds | None                                  |
| Explore post       | send                              | 20 seconds | Caller-supplied `client_message_id`   |
| Explore post       | suggest prompts                   | 30 seconds | None                                  |
| Species Dictionary | load, delete, answer feedback     | 20 seconds | None                                  |
| Species Dictionary | send                              | 45 seconds | Caller-supplied `client_message_id`   |
| Species Dictionary | suggest prompts                   | 30 seconds | None                                  |

The five keyed operations retain the existing single ambiguous-failure replay;
the twelve unkeyed operations do not gain one, including load and deterministic
prompt requests. Classified-401 refresh still uses the shared single-replay
budget. Replays retain the exact encoded body, timeout, and key. The client does
not regenerate a caller's send UUID or trim the outbound text.

[`Decoding/FieldChatResponseDecoder.swift`](Decoding/FieldChatResponseDecoder.swift)
is the one stateless candidate-success validator. It preserves the 1 MiB byte
ceiling, fixed limits, subject/conversation/message binding, exactly
acknowledged send pair, strict action confirmations, trimmed bounded summaries,
safe prompt allowlist, and `MerianError.invalidResponse` mapping. Date decoding
reuses `DateUtilities`' existing fractional and whole-second ISO formatters.
Validation does not select a route or own feature state.

`FieldChatNetworkEndpointTests` owns 60 request variants for all 17 operations;
`FieldChatNetworkTransportTests` covers malformed/oversized success, denials,
refresh, bounded keyed replay, unkeyed replay refusal, cancellation, generated
key lifetime, and encoding-error propagation.
`FieldChatConversationEndpointTests`, `FieldChatActionEndpointTests`, and
`SpeciesDictionaryChatEndpointTests` rehome five existing strict-response
regressions with per-test clients and unchanged test names.
`Core/Network/Decoding/FieldChatResponseDecoderTests.swift` directly tests all
five validators and their boundary values.

`OwnedScanRecoveryPolicyTests` retains the cloud identity fence and
deterministic recovery admission; `ScanPublicationRecoveryArchitectureTests`
protects the relocated preflight. `FieldChatAPIModelsTests` retains standalone
wire decoding. Presentation/effect adapters and generation-fenced state remain
in [`Features/FieldChat`](../../Features/FieldChat/README.md). Run the
[Field Chat matrix](#field-chat-verification) and the complete unit target.

### Species Dictionary endpoints, validation, and caches

[`Endpoints/MerianNetworkClient+SpeciesDictionary.swift`](Endpoints/MerianNetworkClient+SpeciesDictionary.swift)
owns six public method variants: two detail lookups, two catalog overloads,
overview, and public observation stats. Detail, catalog, and overview retain
authenticated JSON POSTs at 30 seconds; stats retains an authenticated GET with
ordered `species_id` and `scientific_name` query items at 20 seconds. Both
routes keep their existing safe-read replay allowance and add no idempotency
key. Catalog filters trim only their edges and omit blanks; category `all` is
omitted, limits remain raw, and cursor fields remain raw with only nil
`created_at` omitted. Overview generates one uppercase UUID `cache_buster` per
call, reused across transport retries.

Overview responses remain `no-store`, and this client has no overview memo.
Catalog's overview view model independently retains one successful result for
the Explore presentation and skips navigation fetches while its five-minute
same-country freshness window is valid. Explicit refresh still reaches this
endpoint. See the
[feature-owned overview lifecycle](../../../../../docs/features-and-hardware/16-species-dictionary.md#ios-catalog-ownership-and-request-lifecycle)
for ownership, cancellation, and dismissal behavior.

[`Decoding/SpeciesDictionaryResponseValidator.swift`](Decoding/SpeciesDictionaryResponseValidator.swift)
owns typed schema/identity validation after wire decoding. Dictionary schemas
must be exactly 1; stats accepts schema 2 or newer and requires both the
canonical ID and normalized name to match. Wire decoding failures remain raw
`DecodingError`s; schema/identity failures remain `MerianError.invalidResponse`.
Neither failure enters the response cache. Codable contracts remain unchanged in
`SpeciesDictionaryAPIModels.swift` and `SpeciesObservationStatsAPIModels.swift`.

[`Caching/SpeciesDictionaryResponseCache.swift`](Caching/SpeciesDictionaryResponseCache.swift)
contains both per-client locked memos behind a private immutable client
reference. Endpoint extensions cannot read or mutate that instance directly; the
two fixed-result client bridges own lookup, authenticated load, validation, and
insertion. Storage, locks, and the shared memo implementation are private; the
injected clock supports deterministic expiry tests. See the
[identity/cache boundary](#species-dictionary-identity-and-cache-boundary) for
the preserved TTL, capacity, alias, reset, and cancellation rules. Catalog and
Detail Services and `Features/SpeciesReference/Services` retain their live
adapters; Views, ViewModels, navigation, chart aggregation, and Field Chat do
not move into Core Network. Run the
[Dictionary verification matrix](#species-dictionary-verification).

### Scan lifecycle endpoints and decoding

[`Endpoints/MerianNetworkClient+ScanLifecycle.swift`](Endpoints/MerianNetworkClient+ScanLifecycle.swift)
owns `checkScanStatusDetails`, `checkScanStatuses`, the `checkScanStatus`
compatibility wrapper, and `deleteScan`. The four unchanged status DTOs live in
[`ScanLifecycleAPIModels.swift`](ScanLifecycleAPIModels.swift);
[`Decoding/ScanLifecycleResponseDecoder.swift`](Decoding/ScanLifecycleResponseDecoder.swift)
owns plain `JSONDecoder` decoding, scan matching, nonnegative attempt
validation, and explicit deletion confirmation. Bulk/deletion envelope types
remain private to the decoder. Wire keys, optionality, legacy `failed_terminal`
mapping, public signatures, raw inputs, and the 30-second deadline are
unchanged.

Single status checks validate configuration before encoding an optional
`OwnedScanRecoveryPayload`. They pass its parsed owner UUID to the private
authenticated transport. Positive required-video counts are included; zero and
negative counts are omitted. A returned single `scan_id` may be absent, but a
present ID must match case-insensitively without trimming. Bulk checks return an
empty dictionary immediately for empty input, reject blank/duplicate normalized
IDs before configuration or Auth, and forward the original IDs. Responses must
contain exactly one row per requested ID; trimmed/lowercased response identities
map back to the original caller keys, independent of response order. These
compatibility rules add no client-side UUID or batch-size restriction.

`deleteScan` keeps its raw camel-case `scanId` body and requires a decodable
Boolean `success: true`. Malformed or unconfirmed success remains
`MerianError.invalidResponse`, not proof of remote erasure. Status requests
retain the existing single ambiguous-failure replay allowance even though
server-side reconciliation can mutate job/quota/staging state. Deletion retains
ambiguous-replay refusal and adds no idempotency key. Single status,
compatibility status, and deletion keep the shared classified-401 refresh. The
bulk status request instead returns a classified `401` to its sole production
caller, whose funding task already retains an outer Auth-quiescence lease. All
four keep the shared per-attempt Auth lease and cancellation behavior.

`Recovery/` owns `OwnedScanRecoveryPayload`, missing-row classification, and the
record-based publication and Field Chat compatibility flows. `Media/` owns
publication-media planning and restoration. Durable queue scheduling, deletion
outbox persistence, and retry authority remain in Core Data. This is endpoint
organization, not a new recovery policy. See the canonical
[status contract](../../../../../docs/backend-and-data/05-api-contracts.md#deno-check-scan-status-edge-node),
[deletion contract](../../../../../docs/backend-and-data/05-api-contracts.md#deno-delete-scan-edge-node),
and [focused matrix](#scan-lifecycle-verification).

### Collection sync endpoint

[`Endpoints/MerianNetworkClient+Collections.swift`](Endpoints/MerianNetworkClient+Collections.swift)
owns the authenticated `/sync-collections` request. It maps immutable
`CollectionSyncSnapshot` values to a private request DTO with the unchanged
`created_at`, `is_deleted`, and `scan_ids` keys, uses an explicit 30-second
client deadline, adds no idempotency key, and intentionally ignores successful
response bytes. Because the durable collection task and its outer account-work
lease are themselves drained before an Auth transition can advance, this
endpoint returns a classified `401` to the durable retry owner without starting
nested session recovery. The bulk funding-status probe is the other narrowly
reviewed opt-out; endpoints without a quiescence-owned outer lease retain the
default classified-401 recovery behavior. The collection endpoint owns no
SwiftData access, scheduling, Auth-transition lifecycle, or local
acknowledgement policy.

Core Data retains those responsibilities: `CollectionSyncService` holds the
outer account-work lease across snapshot, request, and commit; the focused
database actor extension projects non-Favorites relationships and commits only
tombstones still pending deletion. `CollectionSyncEndpointTests` owns the exact
wire mapping through a private client and scoped transport. See the canonical
[offline collection pipeline](../../../../../docs/backend-and-data/01-offline-sync-pipeline.md#the-collections-pipeline)
and
[`/sync-collections` contract](../../../../../docs/backend-and-data/05-api-contracts.md#deno-sync-collections-edge-node).

### Enrichment, export, and product feedback endpoints

These small operations have separate domain owners rather than a miscellaneous
endpoint file:

- [`MerianNetworkClient+ScanEnrichment.swift`](Endpoints/MerianNetworkClient+ScanEnrichment.swift)
  owns `updateDeferredScanContext` and `fetchEnrichment`. Capture Submission
  retains local persistence and its single delayed context retry;
  `InferenceSpeciesEnrichmentService+Live` is Core AI's sole endpoint adapter,
  its injected core resolves no live client directly and maps scoped domain
  patches, and `InferenceHydrationPersistenceService+Live` owns admitted local
  writes and off-main lookalike encoding. The species-hydration coordinator and
  its private-state enrichment sub-coordinator retain scope scheduling, result
  application, retry, and stale-result checks; `InferenceHydrationCoordinator`
  owns task lifetime and backoff, while
  `InferenceSpeciesPresentationCoordinator` exposes observable callbacks and
  bounded write admission behind the stable engine facade. `EnrichScanResponse`
  remains hand-written below the generated Identify block in
  [`Core/AI/InferenceEdgeDTOs.swift`](../AI/InferenceEdgeDTOs.swift).
- [`MerianNetworkClient+Exports.swift`](Endpoints/MerianNetworkClient+Exports.swift)
  owns `requestDwcAExport`. Settings retains presentation and the launch-gated
  control. The request still defaults to `personal`, forwards caller scope
  unchanged, and sends the Boolean `includePreciseCoordinates: true`. Server
  release/scope authorization remains authoritative; this extraction does not
  enable exports.
- [`MerianNetworkClient+ProductFeedback.swift`](Endpoints/MerianNetworkClient+ProductFeedback.swift)
  owns survey and Community feedback submission. `FeedbackSurveySubmission`
  remains in Settings Feedback Models; `CommunityFeedbackSubmission` remains in
  `Models/Explore/CommunityFeedbackAPIModels.swift`. Their existing constructors
  retain trimming and metadata construction, and JSONEncoder retains wire keys,
  enum values, array order, and empty fields. Community's model is still
  constructed before endpoint configuration is checked. Feature
  Services/ViewModels retain validation, drafts, single-flight submission, error
  feedback, and prompt/cooldown policy.

Deferred context checks configuration before its no-context return. Only nonnil
elevation, weather condition, temperature, and semantic location are forwarded,
without new client trimming or range checks; it sends no raw coordinates.
Context and export retain 15-second deadlines and ignore every successful HTTP
body. Enrichment and both feedback routes retain 30-second deadlines. Enrichment
serializes before validating the UUID, uses its canonical lowercase value as the
stable idempotency key, and preserves plain JSONDecoder errors and the
enrichment DTO's optional success/data fields. Feedback also ignores successful
bodies. Only keyed enrichment retains ambiguous-failure replay; the other four
mutations do not add a replay or key. All five retain the existing
classified-401 refresh and cancellation rules.

See the canonical
[deferred-context contract](../../../../../docs/backend-and-data/05-api-contracts.md#deno-update-scan-context-edge-node),
[enrichment contract](../../../../../docs/backend-and-data/05-api-contracts.md#deno-enrich-scan-edge-node),
[export contract](../../../../../docs/backend-and-data/05-api-contracts.md#deno-request-export-dwca-edge-node),
[survey contract](../../../../../docs/backend-and-data/05-api-contracts.md#deno-submit-feedback-survey-edge-node),
[Community feedback contract](../../../../../docs/backend-and-data/05-api-contracts.md#deno-submit-community-feedback-edge-node),
and [focused matrix](#enrichment-export-and-feedback-verification).

### Media storage and upload ownership

- [`Endpoints/MerianNetworkClient+MediaStorage.swift`](Endpoints/MerianNetworkClient+MediaStorage.swift)
  owns `generateUploadURLs`, `inspectScanImageCloudStatus`, and
  `repairScanImageCloudReference`. Signing uses the account-bound body bridge,
  lowercase `user_id`, and the unchanged structured manifest. Inspection and
  repair preserve raw `source_url` and optional `restored_object_key` values.
  All three retain 30-second deadlines, plain JSONDecoder failures, classified
  401 refresh, and no ambiguous-failure replay or new idempotency key.
- [`MediaStorageAPIModels.swift`](MediaStorageAPIModels.swift) owns the
  wire-unchanged, value-only `Sendable` signing and scan-image inspection DTOs.
  Signing requires `urls` and every URL's filename, signed URL, object key, and
  headers; lifecycle IDs remain optional. Inspection requires the private `data`
  envelope and known status, preserves explicit snake-case keys, and defaults
  absent/null counts to zero. Private request/envelope types stay with the
  endpoint.
- [`Media/MerianNetworkClient+MediaUploads.swift`](Media/MerianNetworkClient+MediaUploads.swift)
  owns both `uploadToR2` overloads and `uploadStagedVideoFiles`.
  [`PresignedMediaUpload.swift`](Media/PresignedMediaUpload.swift) owns HTTPS
  admission, the exact two-header map, the signed
  `content-length;content-type;host` set, and HTTP-200-only success. File
  uploads re-stat before URL/header validation and remain file-backed. A size
  mismatch rejects that PUT; retry/re-signing belongs to the caller. Transport
  errors, including independent and task-owned URL cancellation, propagate
  unchanged; raw PUTs do not apply the authenticated POST's cancellation
  translation.
- [`Media/StagedVideoUploadPlan.swift`](Media/StagedVideoUploadPlan.swift) owns
  immutable local-file resolution, Documents/temporary basename fallback,
  sanitized playback manifests, and existing count/byte limits. Missing or
  partially missing inputs fail before size planning; invalid counts or sizes
  fail before signing. Foreground video checks response count, uploads
  sequentially, and returns the server's keys in order without adding response
  correspondence or lifecycle validation.

These primitives do not own durable jobs or feature workflows. OfflineSync's
media-upload services retain complete signing-response validation, background
task/account binding, and durable retry authority. Inference's live request
service retains attempt fencing. Core Data Images'
[`CloudScanImageRepairActor`](../Data/Images/Services/CloudScanImageRepairActor.swift)
retains inspect → validate local image → sign → upload → repair and
library-event handling. Admission requires direct filename or registered strong
evidence for the exact local URL; a timestamp guess cannot authorize inspection
or upload. The actor rechecks evidence before subsequent network effects and
allows a later verified retry if evidence disappears. `LocalImageLoader` retains
only cache/load orchestration, local-file discovery, and repair enqueueing.
Shared Profile state retains avatar preparation and promotion. Scan
publication's dedicated Recovery owner coordinates the Media restorer through
these same signing and PUT primitives. The signing primitive decodes the
response; it does not replace the queue's stronger whole-manifest checks or add
server-side input policy.

See the canonical
[signing contract](../../../../../docs/backend-and-data/05-api-contracts.md#deno-generate-upload-urls-edge-node),
[image repair contract](../../../../../docs/backend-and-data/05-api-contracts.md#deno-repair-scan-image-edge-node),
and [focused matrix](#media-storage-and-upload-verification).

### Account deletion and recovery ownership

- [`Endpoints/MerianNetworkClient+AccountDeletion.swift`](Endpoints/MerianNetworkClient+AccountDeletion.swift)
  owns the six existing legacy intake, v2 preparation/commit, and public
  recovery/acknowledgement methods. Three request-only payloads remain private
  to that file. Legacy no-capability intake still sends a nil body; v2 recovery
  and acknowledgement omit the other operation's proof key rather than sending
  null. No wire field or feature-facing workflow signature changes.
- [`AccountDeletionAPIModels.swift`](AccountDeletionAPIModels.swift) owns the
  four-field `AccountDeletionPreparationReceipt`, strict accepted/recovery
  `AccountDeletionReceipt`, status DTOs, and v2 preparation/commit payloads. The
  manual provider-revocation Boolean remains required for accepted deletion and
  recovery; optional expiry, acknowledgement, and version fields on that receipt
  retain their decoding behavior.
- [`Decoding/AccountDeletionResponseDecoder.swift`](Decoding/AccountDeletionResponseDecoder.swift)
  owns operation-specific receipt admission and maps decoding/receipt failures
  to `invalidResponse`. Intake/commit require matching pending/202 or
  completed/200; `decodePreparation` requires the dedicated preparation receipt
  to be prepared/200, successful, protocol 2, and unexpired. Public recovery
  requires an explicit acknowledgement-state field: legacy operations admit only
  `pending|completed`, while v2 recovery alone may additionally admit a
  nonacknowledged, provider-neutral `not_committed` receipt. Prepared receipts
  and v2 `not_committed` acknowledgements fail closed. Expired timestamps are
  accepted only for acknowledged receipts or v2 `not_committed` recovery.
- [`AccountDeletionRecoveryValidation.swift`](AccountDeletionRecoveryValidation.swift)
  owns exact 43-byte base64url proof syntax and 20–40-byte ISO timestamp parsing
  through cached `DateUtilities` formatters. Its injected clock is read only
  after successful parsing and preserves the strict five-minute tolerance. The
  three client static validators remain compatibility forwards.

The two route-fixed, nonescaping client bridges return only response bytes and
HTTP status. `performAccountDeletionJSONPost` resolves configuration before
building the body and forwards the exact optional transition owner to private
authenticated transport. Legacy proof validation remains inside that builder; v2
preparation/commit validate before calling it, preserving failure precedence.
`performAccountDeletionRecoveryJSONPost` delegates to the unchanged private
capability-only transport: publishable `apikey`, no user Bearer token, 20-second
timeout, and at most one two-second retry for the existing transient URL errors
or 5xx responses. Its 64 KiB response check occurs after URLSession has read the
data, before status handling; it is not a streaming memory bound. No new Auth
admission, replay policy, task owner, or singleton is introduced.

`Core/Network/Auth/` owns deterministic transition admission, stable-error
classification, cached-session restoration eligibility, pure phase order, and
separate dependency-injected fresh-deletion and recovery coordinators.
`AuthRuntimeState` retains live transition, generation, lease/drain, and local
sign-out state. `SupabaseManager`, `Core/Security/AccountDeletion`, and
`AppDIContainer` retain endpoint and SDK calls, Keychain proof/marker effects,
verified local sign-out, SwiftData cleanup, and runtime proof retirement. The
decoder cannot authorize cleanup or reinterpret a 404/410 error. Every live
deletion result that can advance or retire those durable effects is fenced by
the transition's exact session and Auth generation on both success and failure;
token ownership by itself is insufficient. Installed pre-capability intake uses
the raw v1 Keychain format for its legacy request and subsequent recovery; it
cannot persist a v2 envelope that would relaunch against the separate v2 hash
domain. A proofless prepared-v2 marker cancels locally because its destructive
commit marker was never reached. If an earlier binary already produced the mixed
v2-envelope/v1-intake state, a v2 unknown response at the intake or cleanup
phase must check legacy recovery. Only a positive v1 match authorizes cleanup; a
second unknown result retains the proof and lifecycle barrier.
[Core Account Deletion Security](../Security/AccountDeletion/README.md) owns
secure proof and durable recovery-phase storage;
[Settings](../../Features/Profile/Settings/README.md#account-deletion) continues
to delegate deletion and recovery to the retained owners. See the canonical
[account-deletion API](../../../../../docs/backend-and-data/05-api-contracts.md#deno-safe-delete-edge-node),
[Apple deletion lifecycle](../../../../../docs/backend-and-data/20-sign-in-with-apple-account-deletion.md),
and [focused matrix](#account-deletion-and-recovery-verification).

### Core Network integration audit

`CoreNetworkIntegrationArchitectureTests` protects the complete boundary across
the individually extracted slices. It requires exactly 18 endpoint-extension
owners, rejects an endpoint entry point duplicated in the remaining aggregate,
and applies the 600-line review ceiling to every Swift owner under `Auth/`,
`Endpoints/`, `Inference/`, `Media/`, `Recovery/`, and `Transport/`, plus the
client façade. The Auth inventory is exactly sixty-one production files; its
source guard also caps Auth at 7,734 production lines, Purchase Identity at
2,016, `SupabaseManager.swift` at 3,461, and the combined surface at 13,211. It
freezes the effect-free observable runtime owner for transition, generation,
analytics-token, exact-session lease/drain, and local sign-out state, the
focused SDK listener/current-state adapter, historical-sync task owner,
lifecycle diagnostics, and the live listener's
generation/context/transition-observation order; the fallback-callback
dependency/coordinator/diagnostics split; plus the bootstrap dependency package,
coordinator, focused SDK service/live adapter, and diagnostics owner, and the
recovery dependency package and coordinator, plus the local-sign-out coordinator
and its colocated dependency boundaries; one shared task-free Supabase Auth
service/live adapter and diagnostics owner covers OAuth, recovery, and local
sign-out. Separately, the guard freezes bootstrap and sign-out task ownership,
missing-session-only creation, exact-session refresh, anonymous readiness,
local-clear completion, and cancellation fences; the lifecycle event model,
dependency boundaries, coordinator, and conditional deferred-event replay task;
the OAuth model, identity-token policy, replacement/retry workflow, completion
dependency package/coordinator, provider-admission dependency
package/coordinator, and focused provider presentation/mapping Services; the
shared Supabase Auth service/live-adapter pair and its canonical OAuth metadata
mapping; the replacement mutation observer at the successful live SDK-install
boundary plus exact-target transition adoption before cancellation can escape;
explicit facade teardown of retained purchase-handoff and purchase-identity
resolution tasks; and the exact remaining generic Supabase Auth operation
inventory owned by the facade; the shared deletion dependency package; separate
fresh/recovery coordinators, pure deletion workflow, purchase-safe sign-out,
source-side purchase-handoff fencing/restoration, keyed destination-handoff
completion, and ghost-profile-merge policy/workflow/dependency/coordinator
inventories, plus the public-author refresh and Apple credential-revocation
dependency/coordinator pairs; requires the ten explicit Auth task owners; and
rejects both current and legacy helper, provider-SDK, and task declarations in
`SupabaseManager`. It matches callback-URL SDK installation independently of the
URL argument name and rejects direct current-session SDK reads in the facade
callback assembly. It separately locks the Core Security ghost-merge
model/service/store and purchase-handoff model/store boundaries, including
device-only verified persistence and sole live endpoint-DTO ownership. It also
requires the Purchase Identity session live-effects service to own legacy
profile precedence, RevenueCat binding/resolution, entitlement readiness, and
privacy-safe diagnostics while the facade retains only Auth state, account-work,
and handoff assembly for that path.

The audit also makes the remaining live-dependency exceptions explicit:

- only `Transport/PinnedNetworkTransport.swift` constructs the production
  `URLSession`, owns certificate pins/TLS validation and bounded no-cache
  dispatch, and exposes the DEBUG replacement seam;
- only `MerianNetworkClient.swift` applies endpoint-configuration diagnostics,
  stores and injects the two transport owners, invokes the private logical
  request core, and exposes the exact-route scan-admission PostgREST bridge;
- only `Transport/EdgeFunctionRoutePolicy.swift` constructs validated Edge
  endpoint URLs and classifies unavailable-route evidence;
- only `Transport/AuthenticatedRequestRetryPolicy.swift` owns the safe-read and
  server-idempotency-aware replay sets, retry-account binding, and pure Auth
  recovery decisions;
- only `Transport/AuthenticatedRequestExecutor.swift` owns one logical
  authenticated request's recursive attempt state, cancellation checkpoints,
  bounded route/transport/server replay, response mapping, and injected Auth,
  entitlement, and consent effects. It switches on `UnauthorizedRefreshTarget`
  but constructs no URLSession or client singleton;
- only `Transport/AuthenticatedTransportDispatcher.swift` owns per-attempt Auth
  headers and account-work leases, constrained-network headers, transition/
  session validation, classified ordinary refresh, and the file-local upload
  delegate around the injected pinned transport;
- the inference endpoint alone owns its consent preflight, profile-derived
  default geoprivacy, and cancellation-propagating detached body preparation;
- owned-scan recovery alone reads profile-derived default geoprivacy and
  performs its scan-repair Species Dictionary PostgREST lookup;
- `Inference/InferenceIdentificationReviewService.swift` alone owns the live
  review dictionary projections and review RPC, both fenced by an account-work
  lease; and
- `Auth/` owns the transition/lease and OAuth values, presentation, transition,
  and identity-token policies, state/OAuth coordinators, replacement/retry
  workflow, sign-out single-flight, Auth-session bootstrap and conditional
  lifecycle-replay tasks, and keyed purchase-handoff, Ghost-merge,
  public-author-refresh, Apple OAuth-completion, Apple credential-revalidation,
  SDK-listener, and historical-synchronization tasks. Provider-neutral owners
  contain no provider SDK or singleton access; only the named Apple/Google
  authorization Services acquire their frameworks and UIKit presentation
  context. The bootstrap service and its `+Live` adapter own bootstrap SDK
  projection, missing-session classification, SDK reads, and anonymous sign-in.
  The typed Apple credential-registration service owns strict receipt
  validation, and only its `+Live` adapter imports Supabase and invokes the
  registration Function. The guard also freezes the policy-function inventory,
  direct-link same-UUID upgrade decision, the ten explicit structured task
  owners, and actor isolation. `SupabaseManager` retains the lifecycle provider,
  history service, consent, and application-container coordination.
  `SupabasePublicAuthorIdentityRefreshLiveEffects.swift` is the explicit
  application-container/logging exception for public-author refresh.
  `AppleCredentialRevocationLiveProvider.swift` and
  `AppleCredentialRevocationLiveDiagnostics.swift` are the explicit Apple SDK
  notification/lookup and privacy-safe logging boundaries for credential
  revalidation. The source guard requires SDK session readback, policy
  admission, transition adoption, and exact-session revalidation before direct
  linking can retire durable ghost-merge recovery. No unlisted extracted owner
  may acquire these globals or create a detached task.

The `SupabaseManager`-wide follow-up audit extends this boundary across the
remaining joined live paths. It requires pre-destructive cancellation for both
account-deletion intake protocols and sign-out, cancellation before Google
provider presentation and after its return, cancellation immediately before a
direct provider-link SDK mutation, cancellation fencing and explicit
installed/failed/cancelled reconciliation around shared OAuth session
replacement, keyed bootstrap replacement safety, repeated post-suspension
listener/session checks, conditional replay of a transition-deferred listener
event, signed-out cleanup postflight, completion-owned cleanup after a cancelled
OAuth mutation, coordinator-owned compare-before-clear public-author task
ownership, and proof-removal-last verification against the exact anonymous
manager-published user, nonexpired SDK session, captured Auth generation, and
transition context. A lifecycle completion without a transition owner cannot
remain valid after a new transition opens.

The final Auth integration audit adds five cross-owner defenses: bootstrap
cannot return a loaded or created identity after cancellation arrives during
purchase readiness; an unsafe Apple credential result reaches recovery only
through an exact-identity, no-replacement-transition terminal-clear admission;
terminal cleanup repeats its exact expected/current-session fence after
account-work quiescence; purchase-handoff-blocked cleanup returns a distinct
outcome and retains the Apple signal without an immediate retry loop; a context
generation changed while clear was suspended replays after the deferred result
instead of losing its earlier stable-context wakeup; and a stale Apple provider
callback idempotently finishes its superseded token. A centralized aggregate
purchase-handoff publication resumes retained revocation work when the fence
becomes false. Clear diagnostics are emitted only after local cleanup completes.

The suite freezes exactly six production Transport owners—three stateless
policies, the request-scoped executor, the pinned session, and the authenticated
dispatcher—the exact disjoint function-name sets used for safe-read and
server-idempotency-aware ambiguous replay, and the requirement that every
classified route have exactly one endpoint owner. It also prevents the executor
from constructing a URLSession, another network client, a singleton instance, or
detached task. Individual endpoint transport suites remain responsible for
request identity at the feature bridge. This audit changes no request, response,
retry, Auth, persistence, or backend contract.

`MerianTests/Core/Network/Transport/` mirrors all six production owners. The
eleven policy tests rehome route classification, ambiguous replay, retry-account
binding, guest regeneration, and transition-owner refresh selection from the
aggregate Network and Inference suites. Eleven executor tests directly cover
exact body/account binding across replay, ordinary, transition-owned,
durable-owner-deferred, and missing-guest Auth recovery, payment and consent
effects, cancellation before dispatch and after a suspended unauthorized
refresh, the bounded 1/2/4-second route schedule, failed-attempt upload release
plus the successful-attempt response fallback. The body-release case
intentionally receives two callbacks across one logical failure/retry chain: the
failed attempt releases immediately, and the successful attempt invokes its
response fallback. Callers therefore keep the callback idempotent across
attempts; each upload delegate separately suppresses duplicate progress/fallback
notification within its own attempt. Stateful endpoint transport tests continue
to prove feature-bridge request identity without changing bodies, owners,
attempt counts, or cancellation. Seven pinned-transport tests cover the
production configuration, valid SHA-256 pins, exact Supabase hostname admission,
concurrent single-session initialization, full-chain intermediate fallback,
missing/empty/unmatched or platform-untrusted chain rejection, and
injected-session dispatch. One dispatcher test covers value-only account
resolution and exact authenticated JSON request construction without live Auth
or network access. The architecture guard requires the Release
`SecTrustEvaluateWithError` gate and both fail-closed cancellation paths. The
unauthorized-refresh cancellation regression runs the production request in a
child task, so cancelling that request does not cancel the owning Swift Testing
test task or turn a cancellation into a false-positive suite result.

`PurchaseIdentitySignOutWorkflowTests` owns the rehomed sign-out ordering
regressions plus preflight and inter-phase cancellation, cancellation before and
immediately after the legacy server destination bind, and proof-retention
coverage. `PurchaseIdentitySignOutCoordinatorTests` owns stable-versus-legacy
routing, pending-proof recovery, unrelated-source refusal, fail-closed
post-retirement journal verification, anonymous replacement, quiesced
exact-session foreground retry, cancelled admission, and recovery-only reset
admission. `PurchaseIdentityHandoffCoordinatorTests` owns eleven deterministic
stable and compatibility completion cases: cancelled-caller preflight, exact
phase order, same-context single-flight, same-session transition-owner
replacement, replacement-generation cancellation, late cancelled-task mutation
suppression, stale-session retention, terminal-only retirement,
unreadable-selection fail-closure, and restored-source abandonment.
`PurchaseIdentitySourceHandoffCoordinatorTests` owns fifteen deterministic
source-side cases spanning aggregate fail closure, preparation drift,
cancellation during compatibility preparation's final SDK-session read,
exact-source retirement, stale-cancel retention, unowned account-work lifetime
and pre-dispatch/pre-removal invalidation, restoration order, pending refusal,
and cancellation. `PurchaseIdentityHandoffAuthJournalTests` owns exact Auth
error mapping and underlying clear-error propagation; Core Security's
`PurchaseIdentityHandoffPreparationCoordinatorTests` owns five construction and
durability-checkpoint cases. `PurchaseIdentityHandoffStoreTests` owns thirteen
deterministic journal cases for format compatibility, fail-closed validation
before writes and after reads, device-only accessibility, read-back
verification, and removal. `GhostProfileMergeStoreTests` owns the corresponding
queue cases, including legacy migration that preserves readable proof when its
rewrite cannot be verified and server-owned expiry classification.
`GhostProfileMergePolicyTests`, `GhostProfileMergeWorkflowTests`, and
`GhostProfileMergeCoordinatorTests` freeze stable replacement, durable
preparation, provider-transition mismatch and post-response source-session
rejection, keyed completion and supersession, queue-wide retry, cancellation
boundaries, terminal cleanup, phase order, and proof-removal-last behavior.
`GhostProfileMergeRemoteServiceTests` freezes typed operation forwarding,
provider-conflict classification, and terminal error adaptation.
`LegacyPurchaseHandoffRemoteServiceTests` freezes typed compatibility operation
forwarding and terminal-error classification.
`PurchaseIdentitySessionCoordinatorTests` owns keyed stable/legacy resolution,
durable-handoff fence projection and fail closure, exact-session rejection,
stale final-admission cache rejection, already-ready elision, same-key
single-flight, and differently keyed task supersession;
`PurchaseIdentityReadinessCoordinatorTests` owns account-work-fenced foreground
repair and its final provider/session fence;
`PurchaseIdentitySessionLiveServiceTests` owns legacy profile precedence, blank-
Auth public fallback, profile-query failure fallback, exact account-kind
mapping, provider/entitlement/diagnostic forwarding, legacy readiness, and
facade-release rejection for deferred linking and entitlement refresh without
live SDKs; `LegacyPurchaseIdentityProfileServiceTests` owns typed legacy-profile
query forwarding. The nine OAuth suites own token validation, metadata
normalization, session replacement and disposition, Apple registration retry,
shared completion ordering, provider admission/callback/task ownership, provider
value mapping, Apple controller/nonce retention, Google pre/post-return
cancellation, strict registration-receipt validation and transport-error
propagation, post-suspension completion fencing, fail-closed provider/transition
and registration configuration, and failure fences. `SupabaseManagerTests`
retains live Supabase effect assembly; `AuthenticationCallbackCoordinatorTests`
adds fifteen focused cases for callback order, overlap and source/target
admission, exact-account refresh, pre-install and suspended-phase cancellation,
mutation-aware cleanup, exact installed-target transition adoption, sign-out
overlap, purchase readiness, and final-session drift. Focused provider suites
own Apple/Google authorization and Apple credential-state mapping. The injected
coordinator suites do not execute Supabase, RevenueCat, StoreKit, or Keychain.
`AuthSessionLifecycleCoordinatorTests` owns fifteen deterministic cases covering
deletion and transition deferral, independent durable-store fail closure,
session projection and cleanup order, purchase/entitlement sequencing,
post-suspension generation and transition fences before historical sync,
replay-owner-driven deferred sign-out cleanup, signed-out postflight rejection,
and malformed events. The integration architecture suite forbids lifecycle
replay dependencies from strongly capturing `SupabaseManager`, preserving
owner-teardown cancellation while a synthetic replay is suspended.
`AuthLifecycleReplayCoordinatorTests` owns five cases covering replacement
cancellation, transition carry-forward, stable-event obligation clearing, owner
release during suspension, and the stable-transition no-op boundary.
`AuthSessionRecoveryCoordinatorTests` owns eighteen deterministic cases covering
ordinary and transition-owned exact-session refresh, cancellation and session
drift around suspension, anonymous purchase/entitlement/final-readback
admission, pending-handoff preservation, local SDK sign-out failure,
cancellation after SDK sign-out begins, and caller-owned transition lifetime
plus cleanup admission for a cancelled OAuth owner that already mutated the SDK
session, exact adopted-target cleanup, and rejection of a replacement session
installed during quiescence. The consolidated `SupabaseAuthSessionServiceTests`
suite owns fourteen OAuth, recovery, and local sign-out SDK-boundary cases.
`AuthLocalSignOutCoordinatorTests` owns eight coordinator cases; the separate
colocated `AuthLocalSignOutFacadeTests` suite owns the rehomed facade
request-gate regression. `PublicAuthorIdentityRefreshCoordinatorTests` owns
eighteen deterministic cases covering stale-target scheduling, keyed
replacement, exact phase order, direct and scheduled cancellation
admission/postflight, cancellation-diagnostic suppression, lease/session drift,
remote failure, and completed-marker reset. `AppleRevocationCoordinatorTests`
owns seventeen deterministic cases for transition deferral, authorized
preservation, fail-closed results, Auth-context and identity drift, transition
overlap, terminal-clear rejection and stable-context replay, notification
coalescing, cancellation, owner release during a suspended lookup, recovery
deferral without a hot loop, explicit stable resume, context-change replay
without a lost wakeup, and exactly-once clear. The four-case
`AppleRevocationLiveProviderTests` suite owns the AuthenticationServices state
mapping and observer replacement, explicit-stop, deinitialization cleanup, and
off-main notification delivery into the main-actor handler.

Three cross-language Edge source contracts bind this split to its backend
lifecycles: `accountDeletionCoverage.test.ts` reads both deletion coordinators,
the pure deletion workflow, Apple authorization live provider, provider sign-in
coordinator, facade assembly, OAuth coordinator/workflow, and Apple credential-
revocation coordinator/live provider for credential capture, provider-to-
transition agreement, and generation-fenced live wiring;
`purchasePrincipalMigrationContract.test.ts` requires readiness to reread both
durable purchase journals and fail closed, pins the completion coordinator plus
compatibility live adapter, and reads the Auth-session lifecycle coordinator for
awaiting-refresh, purchase-readiness, and sign-out ordering, including local
entitlement closure at the accepted-deletion barrier; and
`ghostProfileMergeClientContract.test.ts` reads `SupabaseManager`, the OAuth
coordinator, models, identity-token policy, replacement workflow, and
cancellation suite, the extracted Ghost coordinator/dependencies, typed
service/live adapter, storage, policy, workflow, and focused tests, plus the
Consent facade, runtime, cloud-session core/live adapter, state projection,
synchronization, restoration, Realtime, repository, retry, merge, and focused
tests. A file or suite rehome must update its Deno path in the same change.

The final policy-boundary review replaced its async refresh closure with the
value-only `UnauthorizedRefreshTarget`. The request-scoped executor now switches
on that value and performs the same ordinary or exact transition-owned refresh
through injected live closures. The architecture guard rejects
actor/async/global-effect dependencies in all three stateless Transport
policies, confines Edge route construction and ambiguous-replay application to
their reviewed owners, and verifies the executor applies both refresh branches.
A post-fix arm64 generic Simulator `build-for-testing` compiled the complete app
and test bundles, repository-wide production lint remained clean, and a native
deterministic probe executed both target-selection branches.
CoreSimulatorService was unavailable, so the post-fix focused and full runtime
matrices were not rerun; the 2,809-case result below remains the immediately
preceding green baseline rather than post-fix runtime evidence.

Follow-up verification removed `get-filtered-discovery-feed` from the iOS
safe-read classification because the app has no endpoint owner or caller for
that backend route. The Edge Function and its backend contract remain unchanged;
the strengthened architecture guard now rejects any future replay classification
that lacks exactly one iOS endpoint owner.

The executor follow-up review corrected two test-only fidelity defects without
changing production behavior. The transport fake now returns the successful
attempt's body-sent fallback instead of silently dropping it, and the source
guard searches for the actual `/functions/v1/` route fragment. A native
deterministic harness compiled the production executor and policies and executed
all nine executor plus five integration-architecture tests: 14 passed. The fresh
Xcode attempt stopped before compilation because the host denied SwiftPM's
manifest sandbox and CoreSimulatorService was unavailable, so this review adds
no new Simulator or complete-target runtime evidence; the green XCResults below
remain the latest such baseline.

The final transport-ownership candidate and its concurrency/domain/trust
follow-ups compiled through native typechecking and executed all seven
pinned-transport cases, the dispatcher request-construction case, and all 50
affected architecture cases without failure. The trust review made ordinary
platform validation a prerequisite for pin acceptance and added a deterministic
negative assertion for a known pin paired with failed system trust. Byte-stable
XcodeGen, project/source membership, event routing, CI-tooling,
transport-security, strict SwiftLint, Swift parsing, documentation contracts,
Markdown formatting, and whitespace validation also passed. Fresh Xcode attempts
stopped before compilation because the host denied SwiftPM manifest-cache writes
and CoreSimulatorService was unavailable; this candidate therefore adds no new
Simulator or complete-target runtime evidence, and the green XCResults below
remain the latest such baseline.

The 2026-09-04 Network-wide closure audit removed the unused, self-recursive
private `performPublicGETRequest` declaration and reduced the client façade from
600 to 545 lines. It also corrected owned-scan persistence polling so task
cancellation throws through every call site instead of being translated into a
deferred-recovery result. The poller also rechecks cancellation after every
successful status response, before interpreting that response or starting
follow-up recovery. A scoped transport regression cancels before the first retry
window expires and requires canonical `CancellationError`, one publication
request, one status request, and no resumed polling. Endpoint signatures,
payloads, response DTOs, retry eligibility and delays, Auth ownership,
persistence, and backend contracts remain unchanged.

The recovery architecture suite also requires the throwing persistence helper,
all three throwing call sites, the loop, successful-response, and error-path
cancellation checkpoints, and the non-swallowing retry sleep. This source guard
complements the transport regression; it does not replace runtime execution.

The same closure audit moved the reusable `MockURLProtocol`,
`ScopedMockURLProtocol`, and `ScopedMockTransport` declarations out of the
aggregate client suite and into
`MerianTests/Core/Network/NetworkTransportTestSupport.swift`. The architecture
guard requires that dedicated owner and prevents the aggregate test file from
reacquiring those cross-suite fixtures. This is a test-ownership correction; the
legacy process-global interceptor and isolated per-case transport retain their
existing behavior.

Closure verification typechecked all 980 current production target sources and
the affected aggregate/support/publication test sources, then executed all 50
current Network architecture tests across eight suites in a native deterministic
harness. Byte-stable XcodeGen after regeneration, generated-project/resource and
source membership, event routing and its adversarial tests, complete iOS CI
tooling, Edge DTO parity, transport security, scoped strict SwiftLint, recursive
Network parsing, Supabase tooling, documentation contracts, Markdown formatting,
and whitespace checks passed. Fresh device-specific and generic Simulator
`build-for-testing` attempts stopped before compilation when
CoreSimulatorService disconnected and SwiftPM's nested `sandbox-exec` was denied
by the host sandbox. No fresh Simulator or complete-target runtime result is
claimed for this closure candidate; the recorded 2,809-case result remains the
latest such baseline.

The initial integration-audit candidate passed 53 focused Core Network tests and
the complete 2,802-test `merianTests` target. The Transport extraction's fresh
generic Simulator `build-for-testing`, focused selector matrix with 202 passed
XCResult cases, and complete 2,809-case `merianTests` target also pass with zero
failures, skips, or expected failures. Those recorded green implementation
candidates also passed repository-wide strict SwiftLint, Swift parsing,
byte-stable XcodeGen, project/source membership, event routing, CI-tooling,
documentation contracts, Markdown formatting, and whitespace validation. These
remain the required gates for future behavior-changing candidates.

After building fresh test products, run the integration guard with:

```sh
xcodebuild test-without-building \
  -scheme Merian \
  -project merian.xcodeproj \
  -derivedDataPath '<build-for-testing-derived-data>' \
  -destination 'id=<booted-simulator-id>' \
  -parallel-testing-enabled NO \
  -only-testing:merianTests/AuthTransitionFoundationTests \
  -only-testing:merianTests/AuthRuntimeStateTests \
  -only-testing:merianTests/AuthTransitionPolicyTests \
  -only-testing:merianTests/AuthSessionBootstrapCoordinatorTests \
  -only-testing:merianTests/AuthSessionBootstrapLiveServiceTests \
  -only-testing:merianTests/AuthSessionRecoveryCoordinatorTests \
  -only-testing:merianTests/SupabaseAuthSessionServiceTests \
  -only-testing:merianTests/AuthLocalSignOutCoordinatorTests \
  -only-testing:merianTests/AuthLocalSignOutFacadeTests \
  -only-testing:merianTests/AuthSessionLifecycleCoordinatorTests \
  -only-testing:merianTests/AuthSessionLifecycleLiveProviderTests \
  -only-testing:merianTests/HistoricalSessionSyncLiveServiceTests \
  -only-testing:merianTests/AuthLifecycleReplayCoordinatorTests \
  -only-testing:merianTests/PublicAuthorIdentityRefreshCoordinatorTests \
  -only-testing:merianTests/AppleRevocationCoordinatorTests \
  -only-testing:merianTests/AppleRevocationLiveProviderTests \
  -only-testing:merianTests/OAuthIdentityTokenPolicyTests \
  -only-testing:merianTests/OAuthSignInModelsTests \
  -only-testing:merianTests/OAuthSignInWorkflowTests \
  -only-testing:merianTests/OAuthSignInCoordinatorTests \
  -only-testing:merianTests/OAuthSignInCancellationTests \
  -only-testing:merianTests/OAuthProviderSignInCoordinatorTests \
  -only-testing:merianTests/GoogleOAuthLiveProviderTests \
  -only-testing:merianTests/AppleOAuthAuthorizationLiveProviderTests \
  -only-testing:merianTests/AppleOAuthRegistrationServiceTests \
  -only-testing:merianTests/AccountDeletionTransitionPolicyTests \
  -only-testing:merianTests/AccountDeletionIntakeWorkflowTests \
  -only-testing:merianTests/AccountDeletionCleanupWorkflowTests \
  -only-testing:merianTests/AccountDeletionCoordinatorTests \
  -only-testing:merianTests/AccountDeletionRecoveryCoordinatorTests \
  -only-testing:merianTests/PurchaseIdentitySignOutCoordinatorTests \
  -only-testing:merianTests/PurchaseIdentitySignOutWorkflowTests \
  -only-testing:merianTests/SourceHandoffCoordinatorTests \
  -only-testing:merianTests/PurchaseIdentityHandoffAuthJournalTests \
  -only-testing:merianTests/HandoffPreparationCoordinatorTests \
  -only-testing:merianTests/PurchaseIdentityHandoffCoordinatorTests \
  -only-testing:merianTests/PurchaseIdentityHandoffStoreTests \
  -only-testing:merianTests/LegacyPurchaseHandoffRemoteServiceTests \
  -only-testing:merianTests/PurchaseIdentitySessionCoordinatorTests \
  -only-testing:merianTests/PurchaseIdentityReadinessCoordinatorTests \
  -only-testing:merianTests/PurchaseIdentitySessionLiveServiceTests \
  -only-testing:merianTests/LegacyPurchaseIdentityProfileServiceTests \
  -only-testing:merianTests/GhostProfileMergePolicyTests \
  -only-testing:merianTests/GhostProfileMergeCoordinatorTests \
  -only-testing:merianTests/GhostProfileMergeRemoteServiceTests \
  -only-testing:merianTests/GhostProfileMergeWorkflowTests \
  -only-testing:merianTests/GhostProfileMergeStoreTests \
  -only-testing:merianTests/CoreNetworkIntegrationArchitectureTests \
  -only-testing:merianTests/PinnedNetworkTransportTests \
  -only-testing:merianTests/AuthenticatedTransportDispatcherTests \
  -only-testing:merianTests/AuthenticatedRequestExecutorTests \
  -only-testing:merianTests/AuthenticatedRequestRetryPolicyTests \
  -only-testing:merianTests/EdgeFunctionRoutePolicyTests \
  -only-testing:merianTests/EdgeFunctionErrorPolicyTests \
  -only-testing:merianTests/SupabaseManagerTests \
  -only-testing:merianTests/ConsentManagerRestorationTests
```

Any endpoint inventory, transport bridge, replay classification, or reviewed
live-dependency-owner change must update this guard and run the complete
endpoint matrices below plus the full `merianTests` target. The next hygiene
slice must preserve the now-extracted single-session/Auth boundary and the
600-line façade ceiling.

### Inference verification

`InferenceEndpointTransportTests` owns the eight request/transport regressions
rehomed from `MerianNetworkClientTests`: pinned-session prewarm, body-sent
notification, consent admission/mapping, `/identify` payload dispatch, inline
budget refusal, and queue-backed/direct timeout and replay behavior. Its added
cancellation regression proves a cancelled owner stops before request dispatch;
the prewarm case also proves the `OPTIONS` request carries no Auth, entitlement,
content-type, or body state. `InferencePayloadBuilderTests`,
`InferenceMediaPolicyTests`, and `InferenceRequestPolicyTests` own deterministic
JSON, size/WAV, object-owner, and stable-conflict policy.
`AuthenticatedRequestRetryPolicyTests` owns transport retry-account binding.
`InferenceNetworkArchitectureTests` guards the focused owners, private transport
bridges, `DetachedWork` boundary, non-concatenating overflow-safe byte
accumulator, 600-line ceiling, and exact aggregate rehome. `DetachedWorkTests`
locks parent-cancellation propagation through the shared value-returning bridge.

The critical-result gate keeps the three existing protected case names for
foreground `/identify` dispatch and queue-backed/direct retry policy, but their
suite/type owner is now `Inference Endpoint Transport` /
`InferenceEndpointTransportTests`. Adversarial fixtures reject those cases under
the retired aggregate owner; the protected-case count is unchanged.

Build fresh candidate products, then run:

```bash
inference_network_destination="$(bash scripts/select-ios-simulator-destination.sh)"
xcodebuild test-without-building \
  -scheme Merian \
  -project merian.xcodeproj \
  -derivedDataPath '<build-for-testing-derived-data>' \
  -destination "$inference_network_destination" \
  -parallel-testing-enabled NO \
  -only-testing:merianTests/InferenceEndpointTransportTests \
  -only-testing:merianTests/InferencePayloadBuilderTests \
  -only-testing:merianTests/InferenceMediaPolicyTests \
  -only-testing:merianTests/InferenceRequestPolicyTests \
  -only-testing:merianTests/InferenceNetworkArchitectureTests \
  -only-testing:merianTests/DetachedWorkTests \
  -only-testing:merianTests/MerianNetworkClientTests \
  -only-testing:merianTests/SupabaseManagerTests \
  -only-testing:merianTests/InferenceLiveRequestServiceTests \
  -only-testing:merianTests/OfflineQueueManagerTests \
  -only-testing:merianTests/BackgroundTransferOwnershipTests \
  -only-testing:merianTests/BackgroundTransferArchitectureTests
```

Then replace the individual selectors with `-only-testing:merianTests` against
the same fresh build products. Pure/source tests and DEBUG transport overrides
do not replace a real-session account-switch check, a device request-upload
callback check, or queue handoff under changing connectivity.

### Endpoint verification

This section owns the shared endpoint-test requirements. Feature guides link
here rather than maintain separate lists of the endpoint groups that must run
after a shared bridge or fixture change.

`MerianTests/Core/Network/NetworkTransportTestSupport.swift` owns the legacy
process-global interceptor and the lock-backed scoped URLProtocol transport used
across Network suites.
`MerianTests/Core/Network/Endpoints/NetworkEndpointTestSupport.swift` composes
that scoped transport into the per-case client and supplies type-preserving JSON
comparison plus fixed handler-marked response helpers for all extracted endpoint
suites. Its POST assertion reads a potentially one-shot body stream once and
returns a `NetworkEndpointRequestSnapshot` containing those same bytes, the
idempotency key, and the timeout. Field Chat, post-management, Dictionary, scan
lifecycle, enrichment/export/feedback, and media storage retry tests compare the
snapshot directly; Dictionary also retains the GET URL and the overview's
single-read body with its generated cache-buster. Rereading a request can
compare drained streams instead of the transmitted bodies.
`NetworkEndpointTestSupportTests` covers data- and stream-backed bodies,
byte-distinct but semantically equal JSON, key/timeout identity, and
scalar/null/omission distinctions. `CollectionSyncEndpointTests` uses the same
fixture to freeze its single body-ignoring request. The support suite tests the
assertion helper with synthetic requests; it does not execute the authenticated
client or replace endpoint transport tests.

Changes to any shared JSON bridge, the configuration guard,
`NetworkTransportTestSupport.swift`, or `NetworkEndpointTestSupport.swift`
require `NetworkEndpointTestSupportTests`,
`CoreNetworkIntegrationArchitectureTests`, the Field Trips and Identify matrices
linked above, the [inference matrix](#inference-verification), the Explore
browsing matrix below, the
[interaction matrix](#explore-interaction-verification), the
[notification/public-profile matrix](#notification-and-public-profile-verification),
the [post-management matrix](#explore-post-management-verification), the
[Field Chat matrix](#field-chat-verification), the
[Dictionary matrix](#species-dictionary-verification), the
[scan lifecycle matrix](#scan-lifecycle-verification), the
[scan-publication/recovery matrix](#scan-publication-and-owned-recovery-verification),
the
[enrichment/export/feedback matrix](#enrichment-export-and-feedback-verification),
the [media storage/upload matrix](#media-storage-and-upload-verification), and
the
[account-deletion/recovery matrix](#account-deletion-and-recovery-verification).
Every endpoint slice also requires the complete `merianTests` target, generic
Simulator build, generated-project/source membership checks, strict
affected-source lint, Markdown formatting, and diff checks. The focused browsing
command builds its own candidate test products:

```sh
xcodebuild test \
  -scheme Merian \
  -project merian.xcodeproj \
  -destination 'id=<booted-simulator-id>' \
  -derivedDataPath .build/ios-explore-browsing-tests \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:merianTests/ExploreBrowsingEndpointTests \
  -only-testing:merianTests/ExploreBrowsingEndpointTransportTests \
  -only-testing:merianTests/NetworkEndpointTestSupportTests \
  -only-testing:merianTests/ScanStatusEndpointTests \
  -only-testing:merianTests/ScanDeletionEndpointTests \
  -only-testing:merianTests/ScanLifecycleNetworkEndpointTests \
  -only-testing:merianTests/ScanLifecycleNetworkTransportTests \
  -only-testing:merianTests/ScanLifecycleAPIModelsTests \
  -only-testing:merianTests/ScanLifecycleResponseDecoderTests \
  -only-testing:merianTests/ScanLifecycleNetworkArchitectureTests \
  -only-testing:merianTests/CollectionSyncEndpointTests \
  -only-testing:merianTests/ScanEnrichmentEndpointTests \
  -only-testing:merianTests/ExportEndpointTests \
  -only-testing:merianTests/ProductFeedbackEndpointTests \
  -only-testing:merianTests/EnrichmentExportFeedbackTransportTests \
  -only-testing:merianTests/EnrichmentExportFeedbackBoundaryTests \
  -only-testing:merianTests/MediaStorageEndpointTests \
  -only-testing:merianTests/ScanImageCloudEndpointTests \
  -only-testing:merianTests/MediaStorageTransportTests \
  -only-testing:merianTests/MediaStorageBoundaryTests \
  -only-testing:merianTests/MediaStorageAPIModelsTests \
  -only-testing:merianTests/PresignedMediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadPlanTests \
  -only-testing:merianTests/MediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadTests \
  -only-testing:merianTests/ExploreLocationSharingAPIModelsTests \
  -only-testing:merianTests/ExploreLocationSharingPresentationTests \
  -only-testing:merianTests/ExploreNetworkModelArchitectureTests \
  -only-testing:merianTests/MerianNetworkArchitectureTests \
  -only-testing:merianTests/MerianNetworkClientTests \
  -only-testing:merianTests/ExploreFeedViewModelTests \
  -only-testing:merianTests/ExploreHashtagPostsViewModelTests \
  -only-testing:merianTests/ExplorePostDetailViewModelTests \
  -only-testing:merianTests/ExploreMapPresentationTests \
  -only-testing:merianTests/ExploreMapViewModelTests \
  -only-testing:merianTests/ExploreAuthorProfilePresentationTests \
  -only-testing:merianTests/ExploreAuthorProfileViewModelTests \
  -only-testing:merianTests/ProfilePublicationsViewModelTests \
  -only-testing:merianTests/SpeciesCommunitySightingsViewModelTests \
  -only-testing:merianTests/InsightExploreSharingViewModelTests \
  -only-testing:merianTests/InsightSharingCacheRefreshTests \
  -only-testing:merianTests/ExploreShellNavigationPolicyTests
```

Manually regress all Feed modes/filters, Feed/Map switching and facets,
post/detail/hashtag navigation, author and owner preview/pagination/refresh,
Species Community sightings, and media-only cards on a candidate build. Keep
verification evidence in the
[cleanup record](../../../../../docs/rfcs/codebase-cleanup.md#phase-2-behavior-preserving-file-splits):
source checks and cached-dependency typechecking do not execute the iOS client,
and a native macOS JSON/architecture run is not candidate iOS runtime
acceptance.

### Explore interaction verification

The interaction matrix includes all extracted endpoint groups because the
body-ignoring overload shares the private authenticated transport. Build fresh
candidate products and run the affected feature state and social-guard suites:

```sh
xcodebuild test \
  -scheme Merian \
  -project merian.xcodeproj \
  -destination 'id=<booted-simulator-id>' \
  -derivedDataPath .build/ios-explore-interaction-tests \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:merianTests/ExploreInteractionEndpointTests \
  -only-testing:merianTests/ExploreInteractionEndpointTransportTests \
  -only-testing:merianTests/NetworkEndpointTestSupportTests \
  -only-testing:merianTests/ScanStatusEndpointTests \
  -only-testing:merianTests/ScanDeletionEndpointTests \
  -only-testing:merianTests/ScanLifecycleNetworkEndpointTests \
  -only-testing:merianTests/ScanLifecycleNetworkTransportTests \
  -only-testing:merianTests/ScanLifecycleAPIModelsTests \
  -only-testing:merianTests/ScanLifecycleResponseDecoderTests \
  -only-testing:merianTests/ScanLifecycleNetworkArchitectureTests \
  -only-testing:merianTests/ScanEnrichmentEndpointTests \
  -only-testing:merianTests/ExportEndpointTests \
  -only-testing:merianTests/ProductFeedbackEndpointTests \
  -only-testing:merianTests/EnrichmentExportFeedbackTransportTests \
  -only-testing:merianTests/EnrichmentExportFeedbackBoundaryTests \
  -only-testing:merianTests/MediaStorageEndpointTests \
  -only-testing:merianTests/ScanImageCloudEndpointTests \
  -only-testing:merianTests/MediaStorageTransportTests \
  -only-testing:merianTests/MediaStorageBoundaryTests \
  -only-testing:merianTests/MediaStorageAPIModelsTests \
  -only-testing:merianTests/PresignedMediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadPlanTests \
  -only-testing:merianTests/MediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadTests \
  -only-testing:merianTests/MerianNetworkArchitectureTests \
  -only-testing:merianTests/MerianNetworkClientTests \
  -only-testing:merianTests/FieldTripEndpointTests \
  -only-testing:merianTests/CommunityIdentificationEndpointTests \
  -only-testing:merianTests/ExploreBrowsingEndpointTests \
  -only-testing:merianTests/ExploreBrowsingEndpointTransportTests \
  -only-testing:merianTests/NotificationEndpointTests \
  -only-testing:merianTests/PublicProfileEndpointTests \
  -only-testing:merianTests/NotificationAndPublicProfileEndpointTransportTests \
  -only-testing:merianTests/ExplorePostManagementEndpointTests \
  -only-testing:merianTests/ExploreShareStateEndpointTests \
  -only-testing:merianTests/ExploreMediaIncidentEndpointTests \
  -only-testing:merianTests/ExplorePostManagementEndpointTransportTests \
  -only-testing:merianTests/FieldChatNetworkEndpointTests \
  -only-testing:merianTests/FieldChatNetworkTransportTests \
  -only-testing:merianTests/FieldChatConversationEndpointTests \
  -only-testing:merianTests/FieldChatActionEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryChatEndpointTests \
  -only-testing:merianTests/FieldChatResponseDecoderTests \
  -only-testing:merianTests/SpeciesDictionaryNetworkEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryNetworkTransportTests \
  -only-testing:merianTests/SpeciesDictionaryDetailEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryCatalogEndpointTests \
  -only-testing:merianTests/SpeciesObservationStatsEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryResponseValidatorTests \
  -only-testing:merianTests/SpeciesDictionaryResponseCacheTests \
  -only-testing:merianTests/SpeciesDictionaryAPIModelsTests \
  -only-testing:merianTests/SpeciesDictionaryCatalogAPIModelsTests \
  -only-testing:merianTests/SpeciesObservationStatsAPIModelsTests \
  -only-testing:merianTests/ExploreFeedViewModelTests \
  -only-testing:merianTests/ExplorePostDetailViewModelTests \
  -only-testing:merianTests/ExploreCommentMentionTextTests \
  -only-testing:merianTests/ExploreReplyLoadingStateTests \
  -only-testing:merianTests/ExploreAuthorProfileViewModelTests \
  -only-testing:merianTests/ExploreReportUserViewModelTests \
  -only-testing:merianTests/ExploreReplyThreadViewModelTests \
  -only-testing:merianTests/ExploreNotificationNavigationCoordinatorTests \
  -only-testing:merianTests/ExploreCommentAuthorPresentationTests \
  -only-testing:merianTests/CommunityIDDetailViewModelTests \
  -only-testing:merianTests/SocialGuardManagerTests
```

Also run the complete unit target and the project/build/source checks above.
Manually cover Feed/detail likes, comment/reply pagination, mention composition,
create/delete/moderate/reaction actions, follow/unfollow rollback, report forms,
Community post reporting, blocking rollback, and notification reply
destinations. An unchanged transport contract does not substitute for candidate
iOS runtime or accessibility/navigation verification. Record current-candidate
evidence and unavailable checks explicitly in the
[cleanup record](../../../../../docs/rfcs/codebase-cleanup.md#phase-2-behavior-preserving-file-splits),
which also tracks the interaction slice's implementation and second-pass review.

### Notification and public-profile verification

Build fresh candidate products for both endpoint owners, the other extracted
groups, and the affected catalog, routing, push, and profile state owners:

```sh
xcodebuild test \
  -scheme Merian \
  -project merian.xcodeproj \
  -destination 'id=<booted-simulator-id>' \
  -derivedDataPath .build/ios-notification-public-profile-tests \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:merianTests/NotificationEndpointTests \
  -only-testing:merianTests/PublicProfileEndpointTests \
  -only-testing:merianTests/NotificationAndPublicProfileEndpointTransportTests \
  -only-testing:merianTests/ExplorePostManagementEndpointTests \
  -only-testing:merianTests/ExploreShareStateEndpointTests \
  -only-testing:merianTests/ExploreMediaIncidentEndpointTests \
  -only-testing:merianTests/ExplorePostManagementEndpointTransportTests \
  -only-testing:merianTests/FieldChatNetworkEndpointTests \
  -only-testing:merianTests/FieldChatNetworkTransportTests \
  -only-testing:merianTests/FieldChatConversationEndpointTests \
  -only-testing:merianTests/FieldChatActionEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryChatEndpointTests \
  -only-testing:merianTests/FieldChatResponseDecoderTests \
  -only-testing:merianTests/SpeciesDictionaryNetworkEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryNetworkTransportTests \
  -only-testing:merianTests/SpeciesDictionaryDetailEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryCatalogEndpointTests \
  -only-testing:merianTests/SpeciesObservationStatsEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryResponseValidatorTests \
  -only-testing:merianTests/SpeciesDictionaryResponseCacheTests \
  -only-testing:merianTests/SpeciesDictionaryAPIModelsTests \
  -only-testing:merianTests/SpeciesDictionaryCatalogAPIModelsTests \
  -only-testing:merianTests/SpeciesObservationStatsAPIModelsTests \
  -only-testing:merianTests/NetworkEndpointTestSupportTests \
  -only-testing:merianTests/ScanStatusEndpointTests \
  -only-testing:merianTests/ScanDeletionEndpointTests \
  -only-testing:merianTests/ScanLifecycleNetworkEndpointTests \
  -only-testing:merianTests/ScanLifecycleNetworkTransportTests \
  -only-testing:merianTests/ScanLifecycleAPIModelsTests \
  -only-testing:merianTests/ScanLifecycleResponseDecoderTests \
  -only-testing:merianTests/ScanLifecycleNetworkArchitectureTests \
  -only-testing:merianTests/ScanEnrichmentEndpointTests \
  -only-testing:merianTests/ExportEndpointTests \
  -only-testing:merianTests/ProductFeedbackEndpointTests \
  -only-testing:merianTests/EnrichmentExportFeedbackTransportTests \
  -only-testing:merianTests/EnrichmentExportFeedbackBoundaryTests \
  -only-testing:merianTests/MediaStorageEndpointTests \
  -only-testing:merianTests/ScanImageCloudEndpointTests \
  -only-testing:merianTests/MediaStorageTransportTests \
  -only-testing:merianTests/MediaStorageBoundaryTests \
  -only-testing:merianTests/MediaStorageAPIModelsTests \
  -only-testing:merianTests/PresignedMediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadPlanTests \
  -only-testing:merianTests/MediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadTests \
  -only-testing:merianTests/MerianNetworkArchitectureTests \
  -only-testing:merianTests/MerianNetworkClientTests \
  -only-testing:merianTests/FieldTripEndpointTests \
  -only-testing:merianTests/CommunityIdentificationEndpointTests \
  -only-testing:merianTests/ExploreBrowsingEndpointTests \
  -only-testing:merianTests/ExploreBrowsingEndpointTransportTests \
  -only-testing:merianTests/ExploreInteractionEndpointTests \
  -only-testing:merianTests/ExploreInteractionEndpointTransportTests \
  -only-testing:merianTests/ExploreNotificationsViewModelTests \
  -only-testing:merianTests/ExploreReplyThreadViewModelTests \
  -only-testing:merianTests/ExploreNotificationRowPresentationTests \
  -only-testing:merianTests/ExploreNotificationNavigationCoordinatorTests \
  -only-testing:merianTests/ExploreCommentAuthorPresentationTests \
  -only-testing:merianTests/PushNotificationPolicyTests \
  -only-testing:merianTests/PushRegistrationCoordinatorTests \
  -only-testing:merianTests/PushNotificationManagerTests \
  -only-testing:merianTests/AppIconBadgeControllerTests \
  -only-testing:merianTests/NotificationArchitectureTests \
  -only-testing:merianTests/NotificationSettingsViewModelTests \
  -only-testing:merianTests/ProfileViewModelTests \
  -only-testing:merianTests/ProfileTabViewModelTests \
  -only-testing:merianTests/UserProfileAvatarCoordinatorTests
```

Also run the complete `merianTests` target and the project/build/source checks
above. Manually cover notification loading/refresh/cursors, mark-read and badge
clearing, OS permission and push-preference synchronization, notification
destinations, username availability/conflict feedback, display-name clearing and
alias fallback, and avatar selection/upload/promotion/error timing. Check
VoiceOver and large Dynamic Type on the affected sheets. Source/typechecking
evidence is not iOS runtime or OS integration acceptance; record
current-candidate results and unrun checks in the
[cleanup record](../../../../../docs/rfcs/codebase-cleanup.md#phase-2-behavior-preserving-file-splits).

### Explore post-management verification

Build fresh candidate products for all extracted endpoint owners and the
affected Feed, Insight Sharing, and Scans incident state:

```sh
xcodebuild test \
  -scheme Merian \
  -project merian.xcodeproj \
  -destination 'id=<booted-simulator-id>' \
  -derivedDataPath .build/ios-explore-post-management-tests \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:merianTests/ExplorePostManagementEndpointTests \
  -only-testing:merianTests/ExploreShareStateEndpointTests \
  -only-testing:merianTests/ExploreMediaIncidentEndpointTests \
  -only-testing:merianTests/ExplorePostManagementEndpointTransportTests \
  -only-testing:merianTests/FieldChatNetworkEndpointTests \
  -only-testing:merianTests/FieldChatNetworkTransportTests \
  -only-testing:merianTests/FieldChatConversationEndpointTests \
  -only-testing:merianTests/FieldChatActionEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryChatEndpointTests \
  -only-testing:merianTests/FieldChatResponseDecoderTests \
  -only-testing:merianTests/SpeciesDictionaryNetworkEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryNetworkTransportTests \
  -only-testing:merianTests/SpeciesDictionaryDetailEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryCatalogEndpointTests \
  -only-testing:merianTests/SpeciesObservationStatsEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryResponseValidatorTests \
  -only-testing:merianTests/SpeciesDictionaryResponseCacheTests \
  -only-testing:merianTests/SpeciesDictionaryAPIModelsTests \
  -only-testing:merianTests/SpeciesDictionaryCatalogAPIModelsTests \
  -only-testing:merianTests/SpeciesObservationStatsAPIModelsTests \
  -only-testing:merianTests/NetworkEndpointTestSupportTests \
  -only-testing:merianTests/ScanStatusEndpointTests \
  -only-testing:merianTests/ScanDeletionEndpointTests \
  -only-testing:merianTests/ScanLifecycleNetworkEndpointTests \
  -only-testing:merianTests/ScanLifecycleNetworkTransportTests \
  -only-testing:merianTests/ScanLifecycleAPIModelsTests \
  -only-testing:merianTests/ScanLifecycleResponseDecoderTests \
  -only-testing:merianTests/ScanLifecycleNetworkArchitectureTests \
  -only-testing:merianTests/ScanEnrichmentEndpointTests \
  -only-testing:merianTests/ExportEndpointTests \
  -only-testing:merianTests/ProductFeedbackEndpointTests \
  -only-testing:merianTests/EnrichmentExportFeedbackTransportTests \
  -only-testing:merianTests/EnrichmentExportFeedbackBoundaryTests \
  -only-testing:merianTests/MediaStorageEndpointTests \
  -only-testing:merianTests/ScanImageCloudEndpointTests \
  -only-testing:merianTests/MediaStorageTransportTests \
  -only-testing:merianTests/MediaStorageBoundaryTests \
  -only-testing:merianTests/MediaStorageAPIModelsTests \
  -only-testing:merianTests/PresignedMediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadPlanTests \
  -only-testing:merianTests/MediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadTests \
  -only-testing:merianTests/MerianNetworkArchitectureTests \
  -only-testing:merianTests/MerianNetworkClientTests \
  -only-testing:merianTests/FieldTripEndpointTests \
  -only-testing:merianTests/CommunityIdentificationEndpointTests \
  -only-testing:merianTests/ExploreBrowsingEndpointTests \
  -only-testing:merianTests/ExploreBrowsingEndpointTransportTests \
  -only-testing:merianTests/ExploreInteractionEndpointTests \
  -only-testing:merianTests/ExploreInteractionEndpointTransportTests \
  -only-testing:merianTests/NotificationEndpointTests \
  -only-testing:merianTests/PublicProfileEndpointTests \
  -only-testing:merianTests/NotificationAndPublicProfileEndpointTransportTests \
  -only-testing:merianTests/ExploreFeedViewModelTests \
  -only-testing:merianTests/ExplorePostDetailViewModelTests \
  -only-testing:merianTests/ExploreLocationPrivacyTests \
  -only-testing:merianTests/InsightExploreSharingViewModelTests \
  -only-testing:merianTests/InsightSharingCacheRefreshTests \
  -only-testing:merianTests/InsightSharingOperationStateTests \
  -only-testing:merianTests/InsightSharingPresentationTests \
  -only-testing:merianTests/ScansShellViewModelTests
```

Also run the complete unit target, project/build/source gates above, and
`make test-ios-ci-tooling` when protected suite references change. The other
focused matrices remain required for a shared bridge/test-helper change.
Manually cover composer hydration/selection, public notes/content/location/media
edits, unshare and post disappearance, same-scan and changed-scan
reconciliation, hidden publications, and incident refresh/dismissal/account
changes. Confirm draft/error retention, VoiceOver, and large Dynamic Type. The
[cleanup record](../../../../../docs/rfcs/codebase-cleanup.md#phase-2-behavior-preserving-file-splits)
tracks implementation and second-pass review evidence. Record candidate iOS
runtime and manual results separately from parsing, cached-dependency
typechecking, and native source/JSON checks; a clean source review does not
complete the runtime or manual requirements above.

### Field Chat verification

Build fresh candidate products for all extracted endpoint owners plus the
unchanged Field Chat DTO, source-adapter, presentation, and state owners:

```sh
xcodebuild test \
  -scheme Merian \
  -project merian.xcodeproj \
  -destination 'id=<booted-simulator-id>' \
  -derivedDataPath .build/ios-field-chat-network-tests \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:merianTests/FieldChatNetworkEndpointTests \
  -only-testing:merianTests/FieldChatNetworkTransportTests \
  -only-testing:merianTests/FieldChatConversationEndpointTests \
  -only-testing:merianTests/FieldChatActionEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryChatEndpointTests \
  -only-testing:merianTests/FieldChatResponseDecoderTests \
  -only-testing:merianTests/SpeciesDictionaryNetworkEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryNetworkTransportTests \
  -only-testing:merianTests/SpeciesDictionaryDetailEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryCatalogEndpointTests \
  -only-testing:merianTests/SpeciesObservationStatsEndpointTests \
  -only-testing:merianTests/SpeciesDictionaryResponseValidatorTests \
  -only-testing:merianTests/SpeciesDictionaryResponseCacheTests \
  -only-testing:merianTests/SpeciesDictionaryAPIModelsTests \
  -only-testing:merianTests/SpeciesDictionaryCatalogAPIModelsTests \
  -only-testing:merianTests/SpeciesObservationStatsAPIModelsTests \
  -only-testing:merianTests/FieldChatAPIModelsTests \
  -only-testing:merianTests/NetworkEndpointTestSupportTests \
  -only-testing:merianTests/ScanStatusEndpointTests \
  -only-testing:merianTests/ScanDeletionEndpointTests \
  -only-testing:merianTests/ScanLifecycleNetworkEndpointTests \
  -only-testing:merianTests/ScanLifecycleNetworkTransportTests \
  -only-testing:merianTests/ScanLifecycleAPIModelsTests \
  -only-testing:merianTests/ScanLifecycleResponseDecoderTests \
  -only-testing:merianTests/ScanLifecycleNetworkArchitectureTests \
  -only-testing:merianTests/ScanEnrichmentEndpointTests \
  -only-testing:merianTests/ExportEndpointTests \
  -only-testing:merianTests/ProductFeedbackEndpointTests \
  -only-testing:merianTests/EnrichmentExportFeedbackTransportTests \
  -only-testing:merianTests/EnrichmentExportFeedbackBoundaryTests \
  -only-testing:merianTests/MediaStorageEndpointTests \
  -only-testing:merianTests/ScanImageCloudEndpointTests \
  -only-testing:merianTests/MediaStorageTransportTests \
  -only-testing:merianTests/MediaStorageBoundaryTests \
  -only-testing:merianTests/MediaStorageAPIModelsTests \
  -only-testing:merianTests/PresignedMediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadPlanTests \
  -only-testing:merianTests/MediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadTests \
  -only-testing:merianTests/MerianNetworkArchitectureTests \
  -only-testing:merianTests/MerianNetworkClientTests \
  -only-testing:merianTests/FieldTripEndpointTests \
  -only-testing:merianTests/CommunityIdentificationEndpointTests \
  -only-testing:merianTests/ExploreBrowsingEndpointTests \
  -only-testing:merianTests/ExploreBrowsingEndpointTransportTests \
  -only-testing:merianTests/ExploreInteractionEndpointTests \
  -only-testing:merianTests/ExploreInteractionEndpointTransportTests \
  -only-testing:merianTests/NotificationEndpointTests \
  -only-testing:merianTests/PublicProfileEndpointTests \
  -only-testing:merianTests/NotificationAndPublicProfileEndpointTransportTests \
  -only-testing:merianTests/ExplorePostManagementEndpointTests \
  -only-testing:merianTests/ExploreShareStateEndpointTests \
  -only-testing:merianTests/ExploreMediaIncidentEndpointTests \
  -only-testing:merianTests/ExplorePostManagementEndpointTransportTests \
  -only-testing:merianTests/FieldChatEndpointTests \
  -only-testing:merianTests/FieldChatViewModelStateTests \
  -only-testing:merianTests/FieldChatPresentationPreparationTests \
  -only-testing:merianTests/FieldChatPresentationTests \
  -only-testing:merianTests/FieldChatArchitectureTests
```

Also run the complete `merianTests` target and the shared-bridge project/build,
source, lint, documentation, and other focused matrices above. On a candidate
device/simulator, cover load/send/retry/edit/delete on all three subjects,
cancel/dismiss/subject replacement, quota and unavailable feedback, prompt
fallbacks, answer feedback, Insight feature feedback and note summaries, offline
state, VoiceOver, and large Dynamic Type. Source/architecture checks and native
decoder execution do not exercise URLSession, the iOS host, or live backend
admission. Record candidate runtime and manual results separately in the
[cleanup record](../../../../../docs/rfcs/codebase-cleanup.md#phase-2-behavior-preserving-file-splits).
This refactor does not clear existing backend release holds or authorize live
service calls or deployment.

### Species Dictionary verification

The canonical
[Species Dictionary iOS matrix](../../../../../docs/features-and-hardware/16-species-dictionary.md#testing)
joins the ten Core Network Dictionary suites with the unchanged Catalog, Detail,
Shared, Species Reference, and Explore routing suites. It includes the rehome of
18 prior wire/endpoint tests; Catalog's three route assertions now live in
`SpeciesDictionaryCatalogRouteTests`, alongside explicit identity/name
propagation checks. `SpeciesDictionaryNetworkEndpointTests` adds 17 request
variants and cache/reset/cancellation integration coverage;
`SpeciesDictionaryNetworkTransportTests` covers raw decoding errors, handler
denials, auth refresh, bounded ambiguous replay, and independent cancellation.
`SpeciesDictionaryResponseValidatorTests` and
`SpeciesDictionaryResponseCacheTests` run deterministic schema, identity, TTL,
alias-capacity, replacement, and reset checks without transport or wall-clock
sleep. `MerianNetworkArchitectureTests`,
`ScanLifecycleNetworkArchitectureTests`,
`EnrichmentExportFeedbackBoundaryTests`, and `MediaStorageBoundaryTests` lock
all extracted endpoint owners, the private GET/cache boundary,
configuration-before-input ordering, and fixed-result cache bridges.
Rejected-schema and returned-identity regression tests require a fresh dispatch
after rejection, catching premature cache insertion rather than only asserting
that the first call throws.

Run the complete `merianTests` target and the project, source, lint, and
documentation gates above. A shared bridge/guard change also requires all other
endpoint matrices. Manually cover Species filters/search/refresh/pagination,
UUID/name/deep-link fallback, Dictionary reopen/error/retry, observation chart
refresh and partial/local-only states, and VoiceOver/large Dynamic Type. Record
candidate build/runtime and manual results in the
[cleanup record](../../../../../docs/rfcs/codebase-cleanup.md#phase-2-behavior-preserving-file-splits);
native cache/validator/source checks are not iOS URLSession or host execution.
This code-only extraction changes no API, persistence, or backend release gate
and authorizes no hosted calls or deployment.

### Scan lifecycle verification

`ScanStatusEndpointTests` and `ScanDeletionEndpointTests` rehome all six legacy
status/deletion regressions without changing method selectors. The
[critical-result validator](../../../../../scripts/validate-ios-critical-test-results.sh)
now requires their new suite owners;
[adversarial fixtures](../../../../../scripts/test-validate-ios-critical-test-results.sh)
reject those three protected integrity results if reported under the old
aggregate suite. `ScanLifecycleNetworkEndpointTests` adds 18 independent request
cases, bulk ordering/raw-key projection, empty/invalid bulk short circuits, and
recovery encoding failures. `ScanLifecycleNetworkTransportTests` covers handler
denials, ordinary classified refresh, the bulk funding probe's durable-owner
`401` deferral, bounded status replay, deletion replay refusal, identical
single-read request snapshots, and pre-dispatch/in-flight/independent
cancellation. Every case uses a private client and scoped transport.

`ScanLifecycleAPIModelsTests` owns wire/legacy/optional decoding;
`ScanLifecycleResponseDecoderTests` owns strict single/bulk/deletion validation.
`ScanLifecycleNetworkArchitectureTests` guards the exact endpoint inventory,
encoding/configuration order, recovery owner-ID pass-through, private transport,
and test rehome. DEBUG transport fixtures bypass live Auth lease acquisition;
their retry tests do not prove real-session account fencing. Shared Auth and
cross-endpoint tests remain in `MerianNetworkClientTests`; missing-row policy
and publication recovery use the dedicated matrix below. Queue and feature
callers keep their existing suites.

Build and run fresh candidate products:

```sh
xcodebuild test \
  -scheme Merian \
  -project merian.xcodeproj \
  -destination 'id=<booted-simulator-id>' \
  -derivedDataPath .build/ios-scan-lifecycle-tests \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:merianTests/ScanStatusEndpointTests \
  -only-testing:merianTests/ScanDeletionEndpointTests \
  -only-testing:merianTests/ScanLifecycleNetworkEndpointTests \
  -only-testing:merianTests/ScanLifecycleNetworkTransportTests \
  -only-testing:merianTests/ScanLifecycleAPIModelsTests \
  -only-testing:merianTests/ScanLifecycleResponseDecoderTests \
  -only-testing:merianTests/ScanLifecycleNetworkArchitectureTests \
  -only-testing:merianTests/ScanEnrichmentEndpointTests \
  -only-testing:merianTests/ExportEndpointTests \
  -only-testing:merianTests/ProductFeedbackEndpointTests \
  -only-testing:merianTests/EnrichmentExportFeedbackTransportTests \
  -only-testing:merianTests/EnrichmentExportFeedbackBoundaryTests \
  -only-testing:merianTests/MediaStorageEndpointTests \
  -only-testing:merianTests/ScanImageCloudEndpointTests \
  -only-testing:merianTests/MediaStorageTransportTests \
  -only-testing:merianTests/MediaStorageBoundaryTests \
  -only-testing:merianTests/MediaStorageAPIModelsTests \
  -only-testing:merianTests/PresignedMediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadPlanTests \
  -only-testing:merianTests/MediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadTests \
  -only-testing:merianTests/MerianNetworkArchitectureTests \
  -only-testing:merianTests/NetworkEndpointTestSupportTests \
  -only-testing:merianTests/MerianNetworkClientTests \
  -only-testing:merianTests/OfflineQueueManagerTests \
  -only-testing:merianTests/BackgroundTransferOwnershipTests \
  -only-testing:merianTests/BackgroundTransferArchitectureTests \
  -only-testing:merianTests/OfflineSyncTests \
  -only-testing:merianTests/SyncStateManagerTests \
  -only-testing:merianTests/CloudDeletionSyncTests \
  -only-testing:merianTests/CollectionSyncTests \
  -only-testing:merianTests/MediaUploadSyncTests \
  -only-testing:merianTests/MediaUploadCompletionTests \
  -only-testing:merianTests/OfflineQueueRetryPolicyTests \
  -only-testing:merianTests/MediaStagingContractTests \
  -only-testing:merianTests/MediaStagingBudgetTests \
  -only-testing:merianTests/MediaStagingIdentityTests \
  -only-testing:merianTests/MediaStagingCompletionStateTests \
  -only-testing:merianTests/InferenceURLSessionTaskContractTests \
  -only-testing:merianTests/GenerationTaskRegistryTests \
  -only-testing:merianTests/QueuedScanExtractionTests \
  -only-testing:merianTests/OfflineSyncFoundationArchitectureTests \
  -only-testing:merianTests/OfflineQueueSyncArchitectureTests \
  -only-testing:merianTests/OfflineQueuedScanDeletionTests \
  -only-testing:merianTests/ScanDeletionServiceTests \
  -only-testing:merianTests/FieldChatEndpointTests \
  -only-testing:merianTests/FieldChatViewModelStateTests
```

Run the complete unit target and shared endpoint requirements above, including
`make test-ios-ci-tooling` for the selector rehome. Manually check queued
confirmation/retry, recovery before sharing or Field Chat, owner switching
during a request, and scan deletion with interrupted connectivity on an
authorized local/staging fixture. Record fresh-build, iOS runtime, and manual
evidence separately in the
[cleanup record](../../../../../docs/rfcs/codebase-cleanup.md#phase-2-behavior-preserving-file-splits).
Pure decoder/source tests and cached-dependency frontend checks are
supplemental, not iOS URLSession/queue integration evidence. No hosted call or
deployment is authorized by this refactor.

### Scan publication and owned recovery verification

`ScanPublicationEndpointTests` owns the five direct payload, idempotency, and
strict-success regressions. `ScanPublicationEndpointTransportTests` owns the
platform-route retry, handler-owned `404`, transport-retry cancellation, and
persistence-poll cancellation boundaries with isolated lock-backed request
probes. `OwnedScanRecoveryPolicyTests` owns the stable missing-row classifier,
ingestion-state admission, and Field Chat identity fence.
`ScanPublicationMediaRestorePolicyTests` owns mixed-media count/byte rejection
and the `scan_share_restore` signing projection.
`ScanPublicationRecoveryArchitectureTests` locks the Endpoint, Recovery, and
Media owner groups, their supporting payload/policy files, private helpers,
narrow Auth bridge, test rehomes, and 600-line ceiling.

The critical-result validator now requires the five direct endpoint cases, three
recovery-policy cases, and media-budget case under their new suite display
names. Its adversarial fixture rejects those results under
`MerianNetworkClientTests`. Shared Auth/session policy and unrelated DTO or
feature-state tests remain with their existing owners.

Build fresh candidate products, then run:

```sh
xcodebuild test \
  -scheme Merian \
  -project merian.xcodeproj \
  -destination 'id=<booted-simulator-id>' \
  -derivedDataPath .build/ios-scan-publication-tests \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:merianTests/ScanPublicationEndpointTests \
  -only-testing:merianTests/ScanPublicationEndpointTransportTests \
  -only-testing:merianTests/OwnedScanRecoveryPolicyTests \
  -only-testing:merianTests/ScanPublicationMediaRestorePolicyTests \
  -only-testing:merianTests/ScanPublicationRecoveryArchitectureTests \
  -only-testing:merianTests/ScanStatusEndpointTests \
  -only-testing:merianTests/ScanLifecycleNetworkEndpointTests \
  -only-testing:merianTests/ScanLifecycleNetworkTransportTests \
  -only-testing:merianTests/ScanLifecycleResponseDecoderTests \
  -only-testing:merianTests/MediaStorageEndpointTests \
  -only-testing:merianTests/MediaStorageTransportTests \
  -only-testing:merianTests/PresignedMediaUploadTests \
  -only-testing:merianTests/MediaUploadTests \
  -only-testing:merianTests/NetworkEndpointTestSupportTests \
  -only-testing:merianTests/MerianNetworkArchitectureTests \
  -only-testing:merianTests/MerianNetworkClientTests \
  -only-testing:merianTests/InsightExploreSharingViewModelTests \
  -only-testing:merianTests/InsightSharingCacheRefreshTests \
  -only-testing:merianTests/CommunityIdentificationRequestViewModelTests \
  -only-testing:merianTests/FieldChatEndpointTests \
  -only-testing:merianTests/FieldChatViewModelStateTests
```

Also run the complete unit target and `make test-ios-ci-tooling`. Manually
exercise Explore publication, Ask the Community, missing-owner recovery,
image/video/audio repair, no-surviving-media refusal, cancellation, account
switching, and Field Chat readiness on an authorized local or staging account.
Record synthetic, iOS runtime, real-session, and manual evidence separately;
source guards and policy tests do not prove signed upload bytes, authenticated
owner fencing, or server-side promotion. This refactor authorizes no hosted
mutation or deployment.

### Enrichment, export, and feedback verification

`ScanEnrichmentEndpointTests` rehomes the three context/enrichment endpoint
regressions and adds raw/optional inputs, both enrichment scopes and legacy
scope forwarding, no-context cancellation, serialization-before-UUID failure,
explicit-key projection, and plain decoding-error coverage.
`ExportEndpointTests` rehomes the export regression and checks default/raw
scopes, Boolean precision, the queue deadline, and release/rate denials.
`ProductFeedbackEndpointTests` rehomes the survey endpoint regression and checks
both submissions' wire keys, constructor normalization, metadata, and empty
fields. Settings' `FeedbackSurveyTests` retains only prompt/cooldown policy and
no longer changes the shared network client.

`EnrichmentExportFeedbackTransportTests` shares request fixtures across exactly
these five methods. It checks ignored 2xx bodies/statuses, handler denials,
classified refresh with identical single-read request snapshots, bounded keyed
enrichment replay, replay refusal for the other four mutations, cancellation,
and exact prepared-body forwarding. `EnrichmentExportFeedbackBoundaryTests`
protects the three owners, ordering, unchanged DTO locations, private transport,
and test rehome. No protected critical-CI selector changes owner in this slice.
Private DEBUG fixtures bypass live Auth leases; they are not evidence of real
account-switch fencing.

Build and run fresh candidate products:

```sh
xcodebuild test \
  -scheme Merian \
  -project merian.xcodeproj \
  -destination 'id=<booted-simulator-id>' \
  -derivedDataPath .build/ios-enrichment-export-feedback-tests \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:merianTests/ScanEnrichmentEndpointTests \
  -only-testing:merianTests/ExportEndpointTests \
  -only-testing:merianTests/ProductFeedbackEndpointTests \
  -only-testing:merianTests/EnrichmentExportFeedbackTransportTests \
  -only-testing:merianTests/EnrichmentExportFeedbackBoundaryTests \
  -only-testing:merianTests/MediaStorageEndpointTests \
  -only-testing:merianTests/ScanImageCloudEndpointTests \
  -only-testing:merianTests/MediaStorageTransportTests \
  -only-testing:merianTests/MediaStorageBoundaryTests \
  -only-testing:merianTests/MediaStorageAPIModelsTests \
  -only-testing:merianTests/PresignedMediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadPlanTests \
  -only-testing:merianTests/MediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadTests \
  -only-testing:merianTests/NetworkEndpointTestSupportTests \
  -only-testing:merianTests/MerianNetworkArchitectureTests \
  -only-testing:merianTests/MerianNetworkClientTests \
  -only-testing:merianTests/InferenceEngineTests \
  -only-testing:merianTests/CaptureSubmissionDeferredContextServiceTests \
  -only-testing:merianTests/ExportScansViewModelTests \
  -only-testing:merianTests/FeedbackSurveyViewModelTests \
  -only-testing:merianTests/FeedbackSurveyTests \
  -only-testing:merianTests/CommunityFeedbackViewModelTests
```

Also run the complete `merianTests` target and the shared endpoint requirements
above. On authorized local/staging fixtures, manually verify late context and
local fallback, independent enrichment/lookalike loading and stale-result
suppression, export's unchanged release gate and queue/error presentation, and
both feedback forms' validation, loading, failure, and repeat-submission
behavior. Record fresh-build/runtime and manual results separately from native
pure/source tests and cached-dependency typechecking in the
[cleanup record](../../../../../docs/rfcs/codebase-cleanup.md#phase-2-behavior-preserving-file-splits).
No hosted mutation or deployment is part of this refactor.

### Account deletion and recovery verification

Eight existing aggregate tests now live in `AccountDeletionEndpointTests`,
`AccountDeletionRecoveryEndpointTests`, and `AccountDeletionAPIModelsTests`.
Endpoint cases use a private client and scoped session, never the shared client.
New coverage locks legacy nil-body behavior, exact proof fields, strict receipt
decoding, validation-before-dispatch, stale transition-owner rejection,
classified Auth refresh, ambiguous-intake replay refusal, and cancellation.
`AccountDeletionRecoveryTransportTests` exercises all four public operations,
including no-current-account success, absent user Auth headers, exact optional
key omission, one identical retry, response-size ordering, raw non-200 errors,
and task-owned versus independent transport cancellation.

`AccountDeletionRecoveryValidationTests` and
`AccountDeletionResponseDecoderTests` use a fixed clock for syntax, expiry,
phase/status/version, operation-specific recovery status, acknowledgement-state,
and terminal replay checks. `AccountDeletionBoundaryTests` guards ownership,
validation/bridge ordering, private public-recovery policy, private request
DTOs, the eight endpoint rehomes, and exact-session fencing across immediate and
recovered deletion. The existing shared-auth tests and protected critical
selector remain in `MerianNetworkClientTests`; no CI selector or protected-case
count changes.

The injected transport does not admit a valid Auth transition owner. V2
prepare/commit success is therefore covered by exact payload tests and the pure
receipt decoder, with stale-owner no-dispatch tests at the endpoint. Accepted
transition sequencing lives in `AccountDeletionIntakeWorkflowTests` and
`AccountDeletionCleanupWorkflowTests`; classification and cached-session
eligibility live in `AccountDeletionTransitionPolicyTests`. The workflow suites
also prove that stale failed intake cannot clear its durable marker, stale
prepared-v2 failures cannot reach outer recovery classification, and deferred
restoration cannot publish a cached account after exact session revalidation
fails. `AccountDeletionCoordinatorTests` locks fresh v2 effect order and both
preflight gates; `AccountDeletionRecoveryCoordinatorTests` locks no-op, v1/v2,
accepted, noncommitted, stale-session, acknowledgement-failure, proof-only, and
retirement routes, plus proofless prepared-v2 cancellation and raw-v1 proof
continuity across an ambiguous pre-capability replay. It also pins legacy-domain
recovery before restoration for an already-installed mixed envelope.
`SupabaseManagerTests` retains SDK/Auth effect assembly, while the integration
architecture suite locks ordinary refresh, transition-owned telemetry, and
failed-sign-out restoration to the same exact session coordinator. Neither the
injected workflow tests nor source guards replace real-session integration.
Never add an Auth bypass to make these endpoint fixtures succeed.

The pass-three candidate ran this focused account-deletion/Auth matrix on an
iPhone 17 Pro iOS 26.4 Simulator: 341 parameter-expanded cases across 190 unique
test identifiers passed with no failures or skips. The complete `merianTests`
target then passed 4,860 parameter-expanded cases across 2,876 unique test
identifiers with no failures or skips. These local simulator results do not
replace the separately authorized real-session checklist below. The follow-up
review removed one obsolete test-only combined rejection helper, renamed its
coverage to the proof-only operation used by production, and hardened the exact
helper-inventory guard. A fresh generic Simulator `build-for-testing` compiles
that candidate; runtime execution could not be repeated because
CoreSimulatorService was unavailable, so the counts above remain the latest
runtime baseline rather than evidence for the renamed test identifier.

The final fail-closed review restored Simulator execution against a freshly
rebuilt candidate. Its combined account-deletion, Auth, Core Network
architecture, and Explore media regression matrix passed 50 XCTest cases and 29
Swift Testing cases with zero failures or skips. The matching Edge recovery
matrix passed 12 Deno tests. The complete `merianTests` target was not rerun
after this narrow correction, so the 4,860-case pass above remains the broader
runtime baseline.

#### Preparation receipt contract

Protocol-v2 preparation has its own non-destructive response contract. The
`prepare` branch of
[`safe-delete/handler.ts`](../../../../../services/supabase/functions/safe-delete/handler.ts)
returns exactly `success`, `status`, `protocol_version`, and
`recovery_capability_expires_at`. Native
[`AccountDeletionPreparationReceipt`](AccountDeletionAPIModels.swift) represents
that shape, and `AccountDeletionResponseDecoder.decodePreparation` admits only a
successful HTTP-200 `prepared` response with protocol version 2 and a valid
future expiry. Preparation intentionally has no provider disposition because no
destructive intake, cleanup, or revocation decision has occurred.

Accepted deletion and public recovery continue to decode
`AccountDeletionReceipt`, where `manual_provider_revocation_required` remains a
nonoptional wire field. The identity-free
[`account-deletion-preparation-v2-success.json`](../../../../../services/supabase/functions/_tests/fixtures/account-deletion-preparation-v2-success.json)
fixture is consumed by both the Deno handler test and native DTO/decoder tests;
the native suite also proves the four-field preparation cannot decode as an
accepted receipt. `AccountDeletionIntakeWorkflowTests` separately locks the
workflow order: prepare, verify the exact transition-session context, persist
the prepared marker, persist the intake marker, commit, then reverify that exact
context for the accepted receipt. It also proves stale preparation context or
either marker failure stops before commit with the persistence error, while
stale commit context retains `signOutSessionChanged`. Cancellation cases stop
before initial persistence, after the durable legacy marker, after v2
preparation, and after the v2 marker pair without dispatching the destructive
request. These source and simulator regressions prove the checked-in
producer/consumer shape, but do not replace the authorized real-session
integration checklist below.

#### Focused command

Build and run fresh candidate products:

```sh
xcodebuild test \
  -scheme Merian \
  -project merian.xcodeproj \
  -destination 'id=<booted-simulator-id>' \
  -derivedDataPath .build/ios-account-deletion-tests \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:merianTests/AccountDeletionEndpointTests \
  -only-testing:merianTests/AccountDeletionRecoveryEndpointTests \
  -only-testing:merianTests/AccountDeletionRecoveryTransportTests \
  -only-testing:merianTests/AccountDeletionAPIModelsTests \
  -only-testing:merianTests/AccountDeletionRecoveryValidationTests \
  -only-testing:merianTests/AccountDeletionResponseDecoderTests \
  -only-testing:merianTests/AccountDeletionBoundaryTests \
  -only-testing:merianTests/AccountDeletionTransitionPolicyTests \
  -only-testing:merianTests/AccountDeletionIntakeWorkflowTests \
  -only-testing:merianTests/AccountDeletionCleanupWorkflowTests \
  -only-testing:merianTests/AccountDeletionCoordinatorTests \
  -only-testing:merianTests/AccountDeletionRecoveryCoordinatorTests \
  -only-testing:merianTests/AuthTransitionFoundationTests \
  -only-testing:merianTests/AuthTransitionPolicyTests \
  -only-testing:merianTests/AuthSessionRecoveryCoordinatorTests \
  -only-testing:merianTests/SupabaseAuthSessionServiceTests \
  -only-testing:merianTests/AuthLocalSignOutCoordinatorTests \
  -only-testing:merianTests/AuthLocalSignOutFacadeTests \
  -only-testing:merianTests/AuthSessionLifecycleCoordinatorTests \
  -only-testing:merianTests/AuthSessionLifecycleLiveProviderTests \
  -only-testing:merianTests/HistoricalSessionSyncLiveServiceTests \
  -only-testing:merianTests/AuthLifecycleReplayCoordinatorTests \
  -only-testing:merianTests/OAuthIdentityTokenPolicyTests \
  -only-testing:merianTests/OAuthSignInModelsTests \
  -only-testing:merianTests/OAuthSignInWorkflowTests \
  -only-testing:merianTests/OAuthSignInCoordinatorTests \
  -only-testing:merianTests/OAuthSignInCancellationTests \
  -only-testing:merianTests/OAuthProviderSignInCoordinatorTests \
  -only-testing:merianTests/GoogleOAuthLiveProviderTests \
  -only-testing:merianTests/AppleOAuthAuthorizationLiveProviderTests \
  -only-testing:merianTests/AppleOAuthRegistrationServiceTests \
  -only-testing:merianTests/CoreNetworkIntegrationArchitectureTests \
  -only-testing:merianTests/NetworkEndpointTestSupportTests \
  -only-testing:merianTests/MerianNetworkArchitectureTests \
  -only-testing:merianTests/MerianNetworkClientTests \
  -only-testing:merianTests/SupabaseManagerTests \
  -only-testing:merianTests/AccountDeletionCapabilityStoreTests \
  -only-testing:merianTests/AccountDeletionLocalCleanupStoreTests \
  -only-testing:merianTests/ManualAppleRevocationNoticeStoreTests \
  -only-testing:merianTests/AccountDeletionSecurityArchitectureTests \
  -only-testing:merianTests/KeychainKeysTests \
  -only-testing:merianTests/UserDefaultsKeysTests \
  -only-testing:merianTests/ScanRepositoryPurgeTests \
  -only-testing:merianTests/AccountScopedPreferencesTests \
  -only-testing:merianTests/GamificationManagerTests \
  -only-testing:merianTests/AppIconBadgeControllerTests \
  -only-testing:merianTests/AppDIContainerTests
```

Also run the shared endpoint requirements and complete `merianTests` target. The
existing safe-delete protocol, hashing, recovery-handler, and account-deletion
source/migration-contract tests remain backend-owned; this extraction changes no
Function, database, or release control.

#### Account deletion integration checklist

The checked-in preparation producer/consumer contract is source-verified. Use
separately authorized disposable accounts and a named non-production target for
the remaining real-session checks; these checks can delete data and revoke
provider authorization. This contract fix authorizes no live deletion or
deployment.

- Verify a real-session v2 preparation is non-destructive, the prepared marker
  is durable before commit, and pending/202 or completed/200 acceptance reaches
  the existing cleanup owner. An arbitrary `2xx` or prepared/200 response is not
  deletion acceptance.
- Terminate and relaunch before prepare, after prepare, after a dropped commit
  response, and during each local cleanup/acknowledgement/retirement boundary.
  Recovery must reuse the existing proof, work without cached Auth, and retain
  the barrier on ambiguous transport or decoding failures.
- Distinguish v2 `not_committed` and v2-only genuinely unknown-proof
  cancellation (unused proof/intent retirement only) from legacy unknown-proof
  ambiguity and the installed mixed-domain state below (barrier retained). A
  preparation-expired `410` cannot authorize local erasure; only a matched
  committed-capability `account_deletion_recovery_expired` may take the
  conservative cleanup path.
- Check `409 purchase_continuity_pending` and exact-session cancellation without
  admitting another account's response. V2 rejection retirement also requires
  recovery to establish `not_committed`; rejection-retirement relaunch must not
  sign out or purge data.
- Verify the manual-provider notice is durable before sign-out, private-map
  reset precedes SwiftData purge, every `CurrentSchema` model is removed, and
  the classified account-derived defaults are read-back verified before local
  cleanup acknowledgement. Process-local settings, gamification, badge, and
  image-cache projections reset only after those durable steps; badge work is
  generation-fenced against stale completion. Device settings, consent, the
  deletion marker, and the manual notice must survive. V2 acknowledgement uses
  its independent proof; acknowledged or matched-expired recovery must remain
  safely replayable. Verified Keychain removal precedes marker clearing.
- Exercise legacy stored proofs and pre-capability cleanup markers without
  changing their fallback behavior. Confirm proofless legacy intake writes and
  reuses one raw v1 proof across an ambiguous request, while a proofless
  prepared-v2 marker restores the cached account without starting deletion. For
  an installed mixed v2-envelope/v1-intake state, confirm v2 unknown checks
  legacy recovery and does not restore on a second unknown result. Verify
  Settings confirmation, pending/error presentation, relaunch recovery, and
  manual-notice dismissal, including VoiceOver and large Dynamic Type.

Record fresh iOS build/runtime results and authorized manual results separately
from native pure/source execution and cached-dependency typechecking in the
[cleanup record](../../../../../docs/rfcs/codebase-cleanup.md#phase-2-behavior-preserving-file-splits).
This checklist supplements, but does not replace, the Apple/provider and
older-client release evidence in the
[canonical deletion contract](../../../../../docs/backend-and-data/20-sign-in-with-apple-account-deletion.md).

### Media storage and upload verification

`MediaStorageEndpointTests` rehomes the structured-signing regression and covers
lowercase explicit/resolved payload-owner mapping, unresolved-current-account
refusal, optional and raw manifest fields, encoding order, and plain decoding
failures. `ScanImageCloudEndpointTests` rehomes both inspect/repair regressions
and checks raw values, omitted versus empty keys, status projection, required
envelopes, and malformed counts. `MediaStorageTransportTests` covers all three
operations' handler denials, classified refresh with identical single-read body
snapshots, ambiguous-replay refusal, and cancellation. Private DEBUG transports
bypass live Auth leases; these tests do not prove real-session account-switch
fencing. The existing `AuthTransitionFoundationTests` exact-session lease tests,
`AuthTransitionPolicyTests` transition-admission tests, and
`AuthenticatedRequestRetryPolicyTests` retry-account tests remain the pure
state/policy owners; none substitutes for live-session integration.

`MediaStorageAPIModelsTests` owns strict wire fields, optional lifecycle IDs,
snake-case inspection projection, and default counts.
`PresignedMediaUploadTests` covers URL/header validation order and exact success
policy. `StagedVideoUploadPlanTests` covers resolution/fallback, partial-file
refusal, and count/byte boundaries without signing. `MediaUploadTests` covers
both raw PUT paths, absent Auth headers, changed/missing files, strict status
handling, and unmodified transport errors. Its private held-request transport
also checks that cancelling the owning task stops both Data/file URLSession
requests and retains raw `URLError.cancelled`. Start, completion, and stop waits
have independent bounds; completion timeout actively invalidates the test
session instead of awaiting a potentially stuck task. `StagedVideoUploadTests`
rehomes all three foreground video regressions and adds invalid-plan,
wrong-response-count, post-signing file-change, and failed-PUT coverage.
`MediaStorageBoundaryTests` guards the five owners, ordering, private bridges,
file-backed transfer, retained workflow owners, DTOs, and test rehomes.
`CloudScanImageRepairActorTests` verifies the injected inspect → sign → upload →
repair → library-invalidation workflow and canonical single-flight identity
while inspection is suspended. It also invalidates evidence at admission,
inspection, signing, and upload, verifies that the next side effect is
suppressed, and permits a successful later verified retry.
`ImageLoadingArchitectureTests` freezes the relocated repair owner, live-effect
containment, and Core Data Images 600-line production boundary.

The raw-upload mock asserts body bytes only for the Data overload. Its file
cases exercise request headers, validation, response/error handling, and
cancellation; source guards separately protect `upload(for:fromFile:)`. Neither
a mocked file PUT nor the supplemental native Foundation probe proves which
bytes reach storage. That requires a real iOS transfer and receiver-side
verification with approved fixtures.

The critical-result gate now requires
`StagedVideoUploadTests/testUploadStagedVideoFilesRejectsEmptyFileBeforeSigning`
under suite display name `Staged Video Uploads`, not `MerianNetworkClientTests`.
The validator's adversarial fixtures reject the old owner. Keep that exact
selector protected and run `make test-ios-ci-tooling` when changing its owner.

Build and run fresh candidate products:

```sh
xcodebuild test \
  -scheme Merian \
  -project merian.xcodeproj \
  -destination 'id=<booted-simulator-id>' \
  -derivedDataPath .build/ios-media-storage-tests \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:merianTests/MediaStorageEndpointTests \
  -only-testing:merianTests/ScanImageCloudEndpointTests \
  -only-testing:merianTests/MediaStorageTransportTests \
  -only-testing:merianTests/MediaStorageBoundaryTests \
  -only-testing:merianTests/MediaStorageAPIModelsTests \
  -only-testing:merianTests/PresignedMediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadPlanTests \
  -only-testing:merianTests/MediaUploadTests \
  -only-testing:merianTests/StagedVideoUploadTests \
  -only-testing:merianTests/NetworkEndpointTestSupportTests \
  -only-testing:merianTests/MerianNetworkArchitectureTests \
  -only-testing:merianTests/MerianNetworkClientTests \
  -only-testing:merianTests/AuthTransitionFoundationTests \
  -only-testing:merianTests/AuthTransitionPolicyTests \
  -only-testing:merianTests/SupabaseManagerTests \
  -only-testing:merianTests/OfflineQueueManagerTests \
  -only-testing:merianTests/BackgroundTransferOwnershipTests \
  -only-testing:merianTests/BackgroundTransferArchitectureTests \
  -only-testing:merianTests/InferenceLiveRequestServiceTests \
  -only-testing:merianTests/LocalImageLoaderTests \
  -only-testing:merianTests/CloudScanImageRepairActorTests \
  -only-testing:merianTests/ImageLoadingArchitectureTests \
  -only-testing:merianTests/ProfileViewModelTests
```

Also run the shared endpoint matrices and complete `merianTests` target.

#### Media storage integration checklist

Use only authorized local/staging targets and synthetic media:

- **Signed Data/file transfers:** Verify the received fixture bytes and stored
  length, exact signed headers, and rejection of wrong length or MIME. HEAD
  confirms stored length, not byte identity. Change a file's size after signing
  and confirm the stale signature is rejected before a PUT.
- **Foreground video:** Exercise absolute, file-URL, Documents, and temporary
  paths, including a moved-file fallback. Missing, empty, oversized, or failed
  uploads must not become an empty successful video-key list; the
  already-durable queue retains recovery. A valid upload returns the server's
  key.
- **Cancellation and identity:** Cancel a held foreground Data/file PUT and
  verify the underlying transfer stops with raw `URLError.cancelled`. Separately
  exercise real-session changes during signing and queue upload; the old
  operation must not adopt a replacement account. Verify background suspension
  and resume retain each server-issued key and its account binding. Raw PUTs do
  not themselves own Auth leases or durable queue cancellation.
- **Avatar and missing-image consumers:** Check avatar upload followed by
  promotion, healthy-image inspection without repair, and missing-image recovery
  through the surviving local file. Confirm repaired references refresh the
  existing cache/library consumers; an ambiguous repair outcome must preserve a
  potentially committed replacement.
- **Publication restore:** Exercise surviving image, audio, and playback-video
  restoration through the existing publication workflow, including failed
  signing/PUT/repair. Network primitives must not bypass the owning workflow or
  silently accept a partial media set.

Record the candidate revision, platform/OS, selected suites, synthetic fixture
cases, outcomes, and outstanding checks without signed URLs, Auth/session data,
or response bodies. Keep fresh-build, iOS runtime, and manual evidence separate
in the
[cleanup record](../../../../../docs/rfcs/codebase-cleanup.md#phase-2-behavior-preserving-file-splits).
Native model/policy/planning/source tests and cached-dependency typechecking are
supplemental, not iOS URLSession/background integration evidence. No hosted
mutation or deployment is authorized by this refactor.

### Shared client behavior

- Builds authenticated requests to Supabase Edge Functions and retains the
  existing response/request DTO contracts.
- Rejects an existing but zero-byte foreground playback-video file before
  requesting an upload signature, matching the durable queue and Edge
  positive-size contract.
- Sends positive exact `sizeBytes` for every foreground/avatar/repair/restore
  signing request, validates each returned two-header `requiredHeaders` map, and
  applies its `Content-Type` and `Content-Length` to every PUT. File-backed work
  re-stats before upload and rejects a changed size; callers retain retry and
  re-signing policy. No legacy no-size signing method remains.
- Uses one `PinnedNetworkTransport` session for both inference and connection
  prewarming. `MerianNetworkClient+Inference.prewarmInferenceEndpoint()` sends
  `OPTIONS` to `/identify-multimodal`; an auth SDK request is not considered a
  prewarm because it uses another connection pool.
- Calls `ConsentManager.ensureCloudConsentForInference()` before constructing
  any provider request. That preflight resolves the active account, awaits
  pending consent synchronization, and requires a freshly fetched adult row,
  Terms row, and granted all-version Gemini stream head for the same account.
  Local onboarding completion or persisted `syncedUserId` values cannot open
  this request boundary.
- Maps only handler-owned HTTP `403` with stable code `ai_consent_required` to
  `MerianError.aiConsentRequired`. That is a disclosure transition—not quota
  exhaustion or generic authorization—and foreground callers must preserve the
  queued scan while the account returns to Ready. `402 pro_required` and the
  `429` quota/rate codes remain separate.
- Treats shared-auth `401 auth_session_missing` and `401 invalid_session_token`
  as refresh-first transitions. The pinned Supabase SDK refreshes the current
  session through its single-flight session manager, then the client rebuilds
  and retries the request once with the new access token. Anonymous identity
  replacement is considered only after that refresh fails, so an ordinary
  expired JWT cannot detach a first scan, consent ledger, or entitlement
  reservation from its existing account UUID. Every unclassified `401` preserves
  both Ghost and OAuth identities because route policy failure is not
  Auth-deletion evidence.
- Adds `X-Merian-Constrained-Network` for aggregate diagnostics without exposing
  the active interface or user identity.
- Reads privacy-safe `Server-Timing` and `X-Merian-Edge-Region` response
  headers.
- Records URLSession request-upload, time-to-first-byte-after-upload, and
  response-transfer intervals.
- Treats current `/identify-multimodal` `200` as a server durability fence:
  moderation, required media promotion, primary species resolution, scan
  creation, and owner-scoped read-back have completed.
- Builds `OwnedScanRecoveryPayload` only from an owned local record. Single
  `/check-scan-status` can repair eligible non-media state; record-based Explore
  sharing and Ask the Community first resolve and byte-validate a complete
  surviving local-media restore plan, then repair status, and only then request
  signing URLs and upload. They refuse owner-row reconstruction when no
  observation media survives. Field Chat may repair non-media status because it
  does not publish media. Explore can then combine the repaired row with
  owner-staged local image/video/audio; guarded inline repair remains compatible
  with an older released client that stages before Share. Recovery admits only a
  completed-but-missing job or exact authenticated-owner `replay_exhausted`
  reason, or `media_reconciliation_abandoned` with the matching composite
  dead-letter/quota/media-lifecycle proof. Active, retryable, current/later
  policy, unproven abandonment, deletion, foreign, no-ledger, and unknown state
  fails closed. Restore signing uses the explicit `scan_share_restore` purpose
  and deterministic scan/category filenames, so a completed ingestion can stage
  surviving local media only after an unrestricted scan read confirms the active
  JWT-owned row or proves it absent for guarded reconstruction; tombstoned and
  foreign rows fail closed. Bulk status never accepts caller-provided row
  recovery or writes `public.scans`; it may reconcile existing job/quota/staging
  state under the canonical server policy.
- Enforces the inference/playback audio split before request creation. Ordinary
  inline and staged inference accepts only a local, structurally supported WAV;
  a URL-scheme path, compressed M4A, missing file, or extension-only spoof fails
  locally. The upload signer receives `.wav`/`audio/wav` for ordinary audio and
  may receive `.m4a`/`audio/mp4` only with `scan_share_restore`. Historical
  remote references are first materialized as bounded local WAV sidecars rather
  than passed through a file-path initializer. Edge repeats actual RIFF/WAVE and
  structural validation after resolving the bytes.
- Treats `failed_retryable` status as a two-step durable transition rather than
  permanent server ownership. The first observation schedules one
  generation-fenced retry. Its exact `server_retryable_failure` marker and
  attempt count are mirrored across the queued scan and durable job and survive
  required re-upload. Fresh reads consult both copies, counters use their
  monotonic maximum, and serialized transitions repair drift before mutation.
  After the persisted delay, only that marker lets the next preflight send
  Identify. A cloud-complete marker has higher authority and can never be
  replaced by retry state. After the retryable-status save, OfflineSync restores
  the central persisted wake before revalidating cancellation, network policy,
  poll-token ownership, and inference-generation ownership for optional
  process-local poll replacement.
- Translates known technical Explore failures at the UI boundary so database
  authorization and missing-row implementation detail are not customer-facing.
- Decodes Explore media-health incidents from the canonical `{data:[...]}`
  envelope and one exact direct-array compatibility shape retained defensively.
  An empty `[]` is therefore a valid no-incidents result instead of a Scan
  Library decode error; retained traces do not prove that this shape was
  deployed, and any other malformed success shape becomes
  `MerianError.invalidResponse`. Scan Library coalesces rapid queue-event
  refreshes of this independent read-only endpoint, preserves one trailing
  refresh requested during an in-flight call, and revalidates the authenticated
  owner before projecting the private incident queue.
- Requires `/delete-scan` to return a decodable `success: true` envelope before
  confirming cloud erasure. A missing, false, malformed, or contradictory 2xx
  response is `MerianError.invalidResponse`; the durable
  `PendingCloudDeletionTask` remains queued because auth or response failure is
  never evidence that remote data is absent. Its capped-backoff retries do not
  expire; the next drain repairs legacy paused job state while the backend
  independently resumes any owner-bound tombstone it already accepted.

## Species Dictionary identity and cache boundary

`SpeciesDictionaryAPIModels.swift` contains only Codable wire DTOs. UI
presentation, routing, taxonomy conversion, and reference-image labels belong to
`Features/SpeciesDictionary/Shared` or the owning Catalog/Detail module.
`SpeciesDictionaryIdentity.swift` is the Core Network normalization owner: it
accepts only canonical UUID species IDs, collapses scientific-name whitespace,
enforces the 160-character name bound, and derives the case-insensitive cache
key.

`Decoding/SpeciesDictionaryResponseValidator.swift` requires exact
`schema_version = 1` for catalog, overview, and detail. An exact requested UUID
may retain a stale display-name hint; a different returned UUID is accepted only
with a matching supplied normalized name and a canonical returned ID. A
name-only response must match that name and return either a canonical UUID or an
`external:` identity. Stats requires schema 2 or newer and both canonical ID and
normalized-name equality.

The cache type can be constructed in isolation for clock-injected tests, but
`MerianNetworkClient` keeps its live cache instance private. Endpoint extensions
reach that instance only through the fixed-result request bridges described
[above](#meriannetworkclient); feature Services keep calling the existing client
methods. Neither layer receives a cache reference or injects a response or
loader into that instance. Rejected schemas and identities must not add
requested or returned aliases. Without a previously validated entry, a later
lookup must load and validate a response independently.

`Caching/SpeciesDictionaryResponseCache.swift` owns separate locked per-client
stores: 10 minutes for Dictionary detail and 5 minutes for observation stats,
each capped at 64 alias keys, not 64 species. A valid requested UUID is always
the lookup key; a miss does not fall through to the name alias. Detail inserts
only the returned canonical UUID and normalized name, never a stale requested
UUID or an `external:` ID. Stats retains the union of requested and returned
ID/name aliases after strict validation. A warm stats UUID lookup still returns
its cached entry when a later caller supplies another valid name; the endpoint
does not revalidate a cached response against that hint.

TTL is measured from insertion, with expiry at the exact boundary. Reads do not
refresh age. On capacity overflow, expired keys are pruned before oldest-
insertion keys are evicted; equal-timestamp tie ordering remains unspecified.
The DEBUG reset and `overridingSession` replacement clear both stores but do not
add an in-flight generation fence: an already dispatched valid response can
repopulate them. Cache hits continue to bypass Auth/transport cancellation; cold
misses enter the existing cancellation-aware transport. Feature state owners
retain their own cancellation/generation fences.

Wire tests live in `MerianTests/Core/Network/Decoding/`, endpoint and transport
tests in `Core/Network/Endpoints/`, and clock-injected memo tests in
`Core/Network/Caching/`. Feature-only routes, presentation, and state tests stay
under `Features/SpeciesDictionary` or `Features/SpeciesReference`; the former
`SpeciesDictionaryTests` aggregate has been removed.

## Entitlement protocol

The authenticated request builders attach `X-Merian-Entitlement-Protocol: 3` and
preserve `client_scan_id` as the idempotency and original-analysis key. This
covers the four public identification routes: `/identify`, `/identify-describe`,
`/identify-multimodal`, and `/audio-spec`. After the coordinated server cutover,
an older public client receives HTTP `426` with `code = client_update_required`
before provider work; only authenticated internal replay bypasses the public
protocol check.

Identify success envelopes may omit `entitlement` for historical stored
responses. When present, the generated DTO contains `user_id`, `plan_used`,
`credit_consumed`, and `entitlement_after`. The client validates the user,
balance identity, and monotonic `entitlement_version`; it never infers a trial
or Flash fallback from local dates. `get_my_entitlement()` establishes the
current-launch baseline before buffered response metadata can unlock
complimentary access. Response decoding copies the generated DTO into a domain
settlement without mutating account state. Offline Sync applies it only after
successful local persistence and any required exact queue deletion, then keeps
the account-work lease in `InferenceFundingReconciliationOwner` until the
coalesced follow-up finishes or Auth cancellation drains it.

Local funding completion uses `plan_used` and `credit_consumed` together.
`pro_complimentary` with `credit_consumed = true` settles the local blocker as
consumed; the same plan with `false` releases the local complimentary assumption
because paid access may have won before final settlement. Bulk
`check-scan-status` exposes owner-scoped `complimentary_state` for deferred
ordering, but that state-only response cannot prove the installed entitlement
snapshot includes terminal settlement. The scheduler performs an authoritative
entitlement refresh before it reopens capacity or removes a terminal consumed
blocker. Because this bulk probe runs only inside the retained funding
reconciliation owner, it declines inline classified-`401` recovery. The failure
returns to durable scheduling; otherwise recovery would try to quiesce the task
and account lease that initiated it.

The server—not the request payload—classifies whether a single-evidence capture
can use the separate daily Flash policy after complimentary exhaustion. Video,
multiple or mixed evidence, and Pro-only actions remain upgrade-required. The
normative wire and rollout contract is
[Three Complimentary Pro Scans](../../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

## Field trip completion evidence

`Models/FieldTrips/` owns Codable DTOs, request values, and wire-compatibility
fallbacks in eight focused contract-family files. Catalog filtering, lifecycle
display, dates, artwork, profile policy, and other UI presentation belong to
`Features/Explore/FieldTrips/Models`; do not add SwiftUI-facing state or display
extensions to the network model directory.

Catalog and template-detail checklist items may decode an optional private
`completed_scan_id` into `FieldTripChecklistItem.completedScanId`. The ID is the
exact saved scan that completed that item; clients must not infer completed
slots from `completed_count` or array order. The API supplies no media URL.
Explore resolves the identifier against the current device's `LocalScanRecord`
library and reuses `ScanThumbnail`/Insight navigation when available.

The backing catalog/detail RPCs are service-role-only. iOS reaches them through
the authenticated `/field-trips` Edge Function, which supplies the verified
caller ID. Never add this field to public Field trip profiles, publication or
challenge DTOs, Explore feed/map DTOs, or the capture-context DTO.

Template detail additionally decodes optional `FieldTripProgress.publicationId`
/ `publishedAt`. These fields refer only to the requesting owner's active,
non-deleted outing publication. The title badge derives Published from a
non-null publication ID; completion and Community results are not substitutes.
Missing fields remain backward-compatible and render Private during a staged
backend/client rollout.

## Field trip scan progress

`applyFieldTripProgress(scanId:preferredGoal:)` posts
`{"action":"apply_scan_progress","scan_id":"..."}` and may add an optional
`preferred_goal` object containing `user_field_trip_id` and `item_id`. The hint
is best effort and server-validated; older callers omit it. Eligible Capture
submissions also include the same object in the identification-ingestion
payload, allowing the scan-insert trigger to apply progress atomically. The
later Field trips call repeats the hint and retrieves the authoritative receipt
rather than creating a second mutation.

An unreviewed identification earns automatic credit only at the applicable
Possible-match boundary (`Flash >= 0.75`, `Pro >= 0.65`). A weaker result keeps
the preference pending until explicit confirmation or a confirmed
correction/community resolution. A later confidence, inference-tier, or
confirmation downgrade can remove that scan's credit and reopen completed
progress.

The client decodes standard updates from `data` plus Seasonal Challenge updates
from `challenge_updates`. Both update models optionally decode
`creditedLevelNumber`, `creditedLevelTitle`, `creditedCompletedCount`, and
`creditedTargetCount`, plus removed-item metadata used when an identification or
evidence correction invalidates credit. These fields describe the level changed
by the scan; when a completion advances immediately, current counts describe the
next level while credited counts preserve the just-completed full ring. Toast
accessors fall back to current counts against the legacy response shape.

Only updates with nonempty `newlyCompletedItems` represent a new credit. The
first item is in server checklist order and supplies the toast label/focus
target, with its prompt as the common-name fallback. Reapplying an already
credited scan is idempotent and yields no progress toast. Weak pending receipts
and downgrade reconciliation also return no newly completed items and must not
produce a progress toast.

`getFieldTripScanContributions(scanId:)` posts
`{"action":"scan_contributions","scan_id":"..."}` and decodes one
`FieldTripScanContribution` per credited standard outing or Event. The DTO
contains only source IDs, labels, credited item/level counts, artwork inputs,
and typed-routing inputs. It must never grow media, coordinates, notes, or
public evidence. The Insight view model silently treats empty and failed reads
as no card.

## Field trip capture context

`getFieldTripCaptureContext()` posts `{"action":"capture_context"}` to the
authenticated `/field-trips` Edge Function and decodes the narrow
`FieldTripCaptureContextResponse`. The response contains standard field
trip/current level metadata, aggregate progress, and unfinished target prompts
only. New and migrated accounts normally receive Backyard Safari Level 1 from
the server's account-enrollment trigger/backfill. The response must not contain
scan evidence, media, location, or field notes.

`MerianNetworkClient` performs the request.
`Features/Explore/FieldTrips/Services/FieldTripCaptureGoalProvider.swift` maps
the source DTOs into a generic `CaptureGoalContextSnapshot`. After a successful
empty response it uses the existing authenticated `template_detail` slug lookup
to validate the optional post-Reset Backyard Safari introduction.
`ActiveCaptureGoalStore` owns the five-minute freshness policy, per-account
cache, selected-goal persistence, and silent stale-data retention. Concurrent
freshness checks share the provider request; an explicit invalidation received
while that request is active queues at most one forced follow-up. Capture never
imports these Field trip DTOs. Callers must never await this request before
starting the camera or accepting a capture. See
`docs/backend-and-data/05-api-contracts.md` and
`docs/features-and-hardware/25-field-trips.md`. The source-agnostic ownership
decision and future provider aggregation rules live in
`docs/rfcs/active-capture-goal-context.md`.

## Request-Body Completion

`performAuthenticatedRequest` accepts an optional, idempotent body-upload-
complete callback. The idempotency contract spans the whole logical request, not
only one URLSession attempt. The authenticated dispatcher gives each attempt its
own file-local `MerianRequestUploadDelegate`, which fires from
`urlSession(_:task:didSendBodyData:...)` when all expected bytes have been sent
and suppresses that attempt's duplicate response fallback. Receiving a response
is the fallback for protocols that do not deliver upload progress; a transport
failure fires the logical callback immediately. If that failure is replayed, a
later successful attempt can invoke the callback again, so callers must treat
every invocation after the first as a no-op.

For eligible live-camera still-image analysis this callback releases the durable
queue row for background upload after the inline body no longer competes for
uplink capacity. `InferenceLivePipelineCoordinator` sequences the callback and
two-second fail-safe, but both retain `InferenceLiveAttemptCoordinator`
independently so durable upload release does not depend on engine lifetime. Only
the callback's local-analysis update captures the engine weakly. These
foreground callback paths reach `OfflineQueueManager` through
`InferenceLiveQueueService+Live`; Offline Sync's connectivity monitor and
Capture lifecycle retain their direct bulk-release responsibilities.

## Queue-backed Identify Foreground and Retry Ownership

The durable queue, rather than the foreground HTTP helper, owns retry after the
first transport failure of a queue-backed live Identify request. The client uses
one explicit per-call ownership policy:

- queue-backed `identifyMultiModal` gets one foreground attempt, with a
  30-second URLRequest timeout for Pro-funded scans and 15 seconds otherwise,
  and returns its first transient `URLError` through
  `InferenceLiveRequestService` to `InferenceLivePipelineCoordinator`, after the
  idempotent body-sent callback releases the upload hold;
- `InferenceLiveFailureCoordinator` asks `InferenceLiveAttemptCoordinator` to
  retire durable foreground ownership idempotently and returns the exact queue-
  transition action for `InferenceEngine` to apply as **Queued for later**; and
- durable replay or exact-ID status recovery decides when another provider
  attempt is eligible.

This exception is scoped to queue-backed live Identify transport. It does not
remove reviewed replay from queue-less direct callers, audited read routes,
handler-owned authentication refresh, or Supabase route-propagation recovery. A
returned handler/provider `5xx` also remains a service failure rather than
evidence that the device is offline.

The 30-second Pro trial follows eight supplied successful Pro samples whose
legacy Gemini stage exceeded 15 seconds (15.2–24.6 seconds). It can reduce
avoidable queue handoffs but does not accelerate inference or guarantee a
30-second total wall-clock limit: URLRequest applies an inactivity timeout. It
also increases the wait on a stalled Pro connection. Other funding sources
retain the 15-second timeout, and direct callers retain 90 seconds.

The live pipeline snapshots Pro funding synchronously after claiming its exact
foreground generation. The queue reads the matching durable ingestion job and
funding reservation; paid and complimentary Pro qualify. Missing, stale, or
legacy metadata conservatively keeps 15 seconds. The snapshot crosses the
request service only as local transport policy, never as a JSON entitlement
claim. A slow valid result remains recoverable under the same idempotency key
and durable scan ID.

**Current source status (2026-08-10): remediated; release acceptance pending.**
`performAuthenticatedRequest` carries `allowsTransientTransportRetry` through
transport, auth-refresh, route-propagation, and handler retry recursion.
`identifyMultiModal` exposes `durableQueueOwnsRecovery`; the admitted pipeline
session derives that ownership decision and includes it in
`InferenceLiveRequestService`'s request value, which the service forwards
unchanged. Queue-backed calls therefore couple the selected 15/30-second timeout
with no inline retry, while queue-less calls keep the 90-second/replay default.
Protected request-policy regressions assert all three request timeouts, one
immediate queue-backed failure, and one stable-key queue-less replay. The engine
integration regression also proves that a deadline timeout can retire the active
owner without a prior path-monitor callback. Exact-SHA hosted and physical
connectivity evidence remain release blockers in the
[live scan connectivity handoff incident](../../../../../docs/incidents/2026-08-live-scan-connectivity-handoff-gap.md).

## Deferred Context

`updateScanContext` sends owner-authenticated late WeatherKit/geocoding data to
`/update-scan-context`, keyed by `scan_id`. It carries only supported optional
elevation, weather, and semantic-location fields and never resubmits media or
starts another identification. This method is the transport adapter only.
`CaptureSubmissionDeferredContextService` owns local-first persistence and the
single optional 500 ms retry. Endpoint, transport, or task cancellation is
terminal and never starts that retry.

## Failure Rules

Authentication failures propagate to callers; they are not converted to missing
headers. TLS pin failures, invalid HTTPS URLs, and response validation failures
remain fail-closed. Upload-completion callbacks ask the live-attempt coordinator
to release queue ownership on failure, but they do not delete the durable row;
the existing live-success sequence alone asks that coordinator to perform exact-
generation deletion through its injected queue service. Offline Sync retains the
resulting queue-task cancellation and durable-row cleanup.

Transport failures and returned `5xx` responses are ambiguous: the server may
have committed before the connection failed. Foreground replay is therefore
limited to the audited read-route inventory and exact endpoint contracts that
receive a server-supported idempotency key. New routes default to no ambiguous
replay. Insert-only comments/feedback/flags, toggle actions, and multi-action
Field trip requests never gain replay merely because they use `POST`. Signed
upload-session and upload-URL preparation remains excluded from the generic
foreground request replay inventory because avatar and legacy signing requests
do not have a stable scan registration identity. Structured scan signing with
`clientScanId` is database-idempotent on owner/scan/object key, but its durable
retry is owned explicitly by `OfflineQueueManager`; do not turn that guarantee
into blanket replay for every signer caller.

Queue-backed live Identify is the additional durable-owner exception described
above: once its first transport attempt fails, immediate UI handoff takes
priority over generic inline transport replay. The per-call policy is now
implemented and protected by transport-boundary request-count/timing tests;
release acceptance still depends on the incident's exact-SHA and device gates.

Every retry delay is cancellation-propagating. A task canceled while waiting for
transport, server, route-propagation, or guest-session retry exits with
`CancellationError` before constructing another request. Do not replace these
awaits with `try?`: URLSession cancellation is cooperative, and swallowing the
sleep error would let stale inference work replay after ownership moved to a
newer generation. Foundation may surface its async URLSession bridge as
`NSURLErrorCancelled`; the shared request boundary normalizes that error to
`CancellationError` only when the enclosing Swift task is canceled. Session
invalidation or another transport-owned cancellation retains its original
`URLError`.

The Explore replay-cancellation unit regression must observe its first
`MockURLProtocol` dispatch through a bounded monotonic wait before canceling the
task. A fixed executor-yield count is not a URLSession scheduling guarantee on
hosted simulators. Keep both exact request-count assertions: one request before
cancellation and still one afterward, proving the cancellation-propagating retry
delay did not construct a replay.

A Supabase platform `404 NOT_FOUND` is not an application-level missing record.
`EdgeFunctionRoutePolicy` classifies it only when the fixed
`X-Merian-Handler: 1` response marker is absent and the response contains the
stable `SB-Error-Code: NOT_FOUND` header, official missing-function envelope, or
equivalent gateway-without-execution headers. It then replays the same request
through `performAuthenticatedRequest` after one-, two-, and four-second delays.
The handler did not execute, so replay is safe; request bodies and idempotency
keys remain unchanged. A marked handler-owned `404`, including `Scan not found`,
is never route-retried and remains eligible for the normal owner-row recovery
flow. Exhausted platform route retries become
`MerianError.edgeFunctionUnavailable`, so downstream missing-record logic cannot
mark the scan unavailable. Customer surfaces use temporary-availability copy
rather than exposing Supabase router text.

Background `/identify-multimodal` downloads retain the same selected response
headers and run this classifier before general HTTP handling. A platform route
`404` preserves the queued scan and schedules its normal durable retry. A queued
handler `401`, `408`, `409`, `425`, or `429` is also retryable because a fresh
request can refresh authentication, recover an already-finalized result, or
honor transient capacity. Integer `Retry-After` values are bounded by the
queue's maximum delay. Other handler-owned `4xx` responses preserve the local
media as `queueNeedsAttention`; only the exact stable `observation_rejected`
policy response is terminal.

An HTTP `200` is only a candidate background success. Its body must be nonempty,
decode as the generated Identify envelope, not explicitly report
`success: false`, contain a nonempty bounded scan ID, and contain a finite
confidence score from zero through one before local finalization starts. Empty,
truncated, or structurally unusable bodies are ambiguous transport outcomes and
enter exact-ID status recovery plus the durable retry path. The queue row is
removed and its job is marked complete only after response persistence and the
main-context queue deletion both commit. Wrong-scan envelopes, local save
failures, and cleanup save failures retain the queue instead of converting a
no-op save into data loss. A valid confidence-zero envelope for the exact scan
remains terminal and intentionally creates no `LocalScanRecord`, but its source
media stays intact until the main-context queue deletion commits and authorizes
file cleanup. The guarded deletion marks the job complete, inserts the completed
event, and removes the row in the same save; only explicit deletion records
cancellation.

Foreground Identify handling does not translate every `409` into a network
timeout. Only handler responses whose stable code is exactly
`ai_request_in_progress`, `ai_request_already_completed`,
`scan_already_complete`, or `scan_already_finalized` enter the **Restoring
scan** state and remain eligible for exact-ID queue/status hydration. Generic
conflicts, malformed envelopes, and `409` responses from other routes keep their
normal error semantics. Current functions should normally absorb these four
cases and replay `200`; the client branch is a rolling-deployment and
unexpected-race safety net.

Owner-row repair is not a fallback table upsert. The server derives owner
identity, validates/gates recovery, inserts without overwrite, reloads by owner,
and restores media only through validated staging keys. A processing/retryable
or exact policy-rejected job remains unrepaired.

Scan-status success is also treated as untrusted input. Single responses must
decode to the reviewed enum, may echo only the exact requested scan ID, and
cannot report a negative job-attempt count. A bulk response must contain exactly
one unique row for every requested scan ID and no foreign row. Duplicate,
missing, malformed, foreign, or negative-attempt rows become
`MerianError.invalidResponse`; bulk decoding never uses
`Dictionary(uniqueKeysWithValues:)`, whose duplicate-key precondition would
otherwise let a contradictory server response terminate the app.

Before the first Field Chat request,
`ensureCloudScanAvailableForFieldChat(scan:expectedScanId:)` first requires the
local record to match the engine result that will be presented, then polls the
exact owner status and uses bounded non-media recovery only for eligible
historical drift. Explore sharing can combine the same bounded owner recovery
with newly signed local user media. Both retain the stable scan UUID, reject a
stale record/engine identity combination, and keep transient/unknown state
retryable. A handler-owned missing scan is classified by stable
`code: "not_found"`; case-insensitive `Scan not found` text remains only a
released-backend compatibility fallback when no stable code is present. The
joined contract is
[`docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md`](../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md).

An HTTP-successful Explore-share response is not accepted on decoding alone.
`shareScanToExplore` requires `success: true`, the exact requested scan UUID, a
valid post UUID, a parseable ISO-8601 share timestamp, an authoritative
location-sharing value that equals an explicitly requested privacy mode, and an
explicit `published` publication status. Unknown location values are rejected
instead of being coerced into success. Any integrity mismatch becomes
`MerianError.invalidResponse`; callers must not cache the post ID or dismiss the
composer as though publication succeeded.

Ask the Community applies the same candidate-success rule: decoder failures,
unknown request statuses, false success flags, identity mismatches, invalid
UUIDs/timestamps, or non-`needs_id` results become
`MerianError.invalidResponse`.

Field Chat responses are decoded through
`Decoding/FieldChatResponseDecoder.swift` for Insight scans, Explore posts, and
Species Dictionary entries. `Endpoints/MerianNetworkClient+FieldChat.swift`
constructs requests with exactly one source-specific key: `scan_id`, `post_id`,
or `species_id`. Every envelope must echo the requested subject through
`subject_id`, including when the thread is empty. Every message must have a
unique UUID, match that same subject through the compatibility `scan_id`, match
the envelope's valid conversation UUID, contain trimmed/nonempty text bounded to
4,000 characters, and fit the exact v1 server limits. Field Chat JSON is
rejected above the reviewed 1 MiB decode ceiling. A send response must also
contain exactly one user message and one assistant message carrying the
requested `client_message_id`, and the acknowledged user row must contain the
exact trimmed text that was sent. Invalid, contradictory, or incomplete
envelopes never reach the Field Chat feature's `InsightChatViewModel.apply`;
failed sends remain retryable under the same canonical lowercase idempotency
UUID rather than clearing the pending question or creating a duplicate on manual
retry. A backend `field_chat_idempotency_conflict` means that UUID was reused
for edited text and is never treated as confirmation of either send.

Core Network owns those wire contracts, endpoint construction, and validation
rules through the [Field Chat owners](#field-chat-endpoints-and-validation).
Cloud preflight lives in the owned-scan Recovery owner; public-media recovery is
coordinated there through the dedicated Media restorer. The source-specific
presentation adapter lives in
`Features/FieldChat/Services/FieldChatEndpoint.swift`; host views do not select
or call these routes directly.

Species Dictionary Field Chat calls `/species-dictionary-chat`; the app sends
only the canonical dictionary UUID as `species_id`. The route's stable
`species_not_available` response is permanent only for that dictionary subject,
while shared transport and admission failures remain retryable. Dictionary
product telemetry records the source/action outcome without the species UUID,
name, conversation ID, or message ID. Migration
`20260821030027_add_species_dictionary_field_chat.sql` extends atomic admission
and stale recovery to all three chat families;
`20260824210544_preserve_field_chat_daily_usage.sql` then makes its content-free
user/day counter the intended authority across conversation deletion. The
backend candidate remains release-held until its Ghost handler registry and real
three-family database paths execute without skips, cutover remains closed until
all three corrected bundles are explicitly activated, quota denial proves no
empty conversation, Swift/Deno prompt labels make identical normalization
decisions, and release clearance is bound to retained exact-SHA evidence. Client
replay correctness cannot substitute for those server gates.

The request sends the canonical `client_message_id` as `Idempotency-Key`, and
manual retry reuses it. `species-dictionary-chat` is also in
`AuthenticatedRequestRetryPolicy.idempotencyAwareFunctionNames`, so
`AuthenticatedRequestRetryPolicy.canReplayAfterAmbiguousFailure` automatically
retries a lost response or retryable `5xx` with the exact same body and
lowercase UUID. The regression returns failure once, then one saved pair, and
asserts both attempts carried the identical key. Missing or malformed
`species_id` maps to `400 invalid_request`; only a valid canonical UUID that is
unavailable/nonbiological maps to the permanent `404 species_not_available`
subject state.

Atomic admission and stale-request recovery remain backend authority.
`field_chat_send_in_progress`, `field_chat_admission_unavailable`, and
`field_chat_recovery_unavailable` are temporary failures; network/UI callers
must preserve the exact pending UUID and text. The client never infers database
capacity, daily eligibility, or the ten-minute stale-recovery condition from a
local count or timeout.

Feedback, feature-feedback, field-note-summary, and prompt-suggestion responses
also require the exact subject echo plus confirmed action-specific evidence.
False `ok` values, mismatched message/rating/sentiment fields, invalid IDs,
empty or UUID-leaking summaries, and duplicate, oversized, unknown-category, or
locally unsafe prompts become `MerianError.invalidResponse`; no success UI is
applied.

## Consent synchronization identity boundary

Session observation never treats assignment of `currentSessionUserId` as proof
that account consent is current. Synchronization first activates the target
ledger with analytics fail-closed, pushes every target-owned pending adult,
Terms, Gemini, and analytics row, fetches the account's authoritative state, and
only then merges. Returning to a previously used account therefore flushes an
offline revocation before remote state can be applied.

The remote read retains current-disclosure rows as evidence but separately
fetches each provider's all-version greatest `consentRevision`. The final merge
uses that provider-wide head—not the version-filtered row—as permission
authority and as the causal parent for the next local action. A delayed
revocation created under older disclosure copy therefore closes Gemini and
PostHog even when a current-version grant is also present locally.

Every network await rechecks task cancellation, the observed account, the
Supabase SDK's synchronous `auth.currentSession` user, and the synchronization
generation. The final merge repeats that complete check inside the mutation
boundary immediately before changing or persisting the ledger or applying
analytics. A stale request can finish at the transport layer, but it cannot
install evidence, change the active ledger, or reopen PostHog for a replacement
account.

Non-cancellation synchronization failure is not remote authority. While a
completed account still lacks current local required evidence, `ConsentManager`
keeps the launch-matched neutral root active, exposes explicit retry, and runs
5-, 10-, and 20-second outer retries. Only the final identity-fenced merge after
verified ledger persistence may resolve to the workspace or Ready consent
screen.

`ConsentRealtimeCoordinator` owns the requested channel user and confirmed
subscriber independently of session observation. Failed subscriptions retain an
account-owned bounded retry, while `ConsentCloudSessionCoordinator` owns session
adoption and the `ConsentManager` facade retains foreground repair triggers that
ensure the current channel without allowing a stale retry to attach to a new
account. Only the coordinator's live adapter touches analytics-consent Supabase
Realtime. Explicit stop, listener completion, and coordinator deinitialization
converge on one coalesced removal operation; deinitialization initiates removal
independently of listener cancellation.

## OAuth account replacement

Linking an OAuth identity to an anonymous user keeps the same Supabase UUID and
does not replace the account. The client reads the SDK session back after a
successful link and requires an anonymous-to-permanent transition for that same
UUID before adopting it and clearing provider-bound ghost-merge recovery. The
provider-conflict fallback and ordinary OAuth sign-in can install a different
UUID, so they use one replacement boundary:

1. synchronously suppress analytics; snapshot, cancel, and await every consent
   synchronization and restoration task; normalize any canceled same-account
   restoration wait back to `.reconciling`; and stop and await physical removal
   of the prior consent Realtime channel;
2. ask Supabase Auth to install the target session; and
3. reconcile the SDK's actual current session on both success and failure.

The consent transition is generation-fenced. A delayed completion from an older
overlapping sign-in cannot reopen PostHog, restart a stale Realtime owner, or
overwrite `currentUser` after a newer transition starts. A failed replacement
restores the actual surviving session rather than assuming the preflight session
still exists. Restoration retry admission independently rejects caller
cancellation, so a canceled timer cannot reenter if manual retry reuses the same
account, generation, and attempt number. Provider-bound ghost handoff
suppression remains independently active until its durable queue has been fully
reconciled.

## Sign in with Apple revocation credential

`AppleOAuthAuthorizationLiveProvider` requires both `identityToken` and
`authorizationCode`, retains the exact authorization controller, and maps the
raw Apple credential into a provider-neutral value containing one registration
UUID. `OAuthProviderSignInCoordinator` owns callback admission and the retained
completion task. Immediately after Supabase installs the permanent Apple
session, `SupabaseManager` invokes the injected
`AppleOAuthCredentialRegistrationService` between exact transition/session
fences. Its `+Live` adapter alone sends both values and that UUID, owns the
private wire DTOs, and performs the authenticated
`register-apple-revocation-token` invocation; the provider-neutral service
accepts only the exact registered receipt. The adapter performs exactly one
authenticated Function invocation per service call. It owns neither retry policy
nor asynchronous task state; `OAuthSignInWorkflow` remains the retry owner.
Within the provider-neutral completion values, the identity token exists only in
the OAuth credentials; the registration value keeps the UUID and one-use
authorization code, and the adapter forwards the credential token that installed
the session. The same UUID and payload receive one bounded response-loss retry.
Server-side Apple verification and Vault persistence are mandatory: if
registration cannot be confirmed, the shared recovery path clears the newly
installed local session and requires a fresh Apple authorization instead of
completing an account that cannot later be revoked.

`AppleCredentialRevocationLiveProvider` alone observes
`ASAuthorizationAppleIDProvider.credentialRevokedNotification` and maps
`getCredentialState` into provider-neutral outcomes. The retained
`AppleCredentialRevocationCoordinator` defers during Auth transitions, coalesces
overlap, captures the exact Apple session and provider subject plus an
Auth-context generation, and repeats those checks when the lookup returns. A
cancelled or stale predecessor cannot clear a replacement session, and the task
does not retain its coordinator or manager across suspended provider work.
Revoked, missing, transferred, unknown, or failed state resolution clears only
the still-matching local session: the live terminal-clear adapter rechecks the
captured identity and absence of a replacement transition immediately before
recovery admission, and recovery repeats the expected/current-session check
after account-work quiescence. A context change retains the signal for the next
stable context. A purchase-handoff deferral retains it without immediately
starting another lookup; publishing the aggregate handoff fence as false wakes
the retained work. If Auth context changed while clear was suspended, the stale
attempt immediately revalidates after the deferred result instead of losing the
earlier lifecycle wakeup. Clear diagnostics are emitted only after cleanup
reports a completed clear. An authoritative `.authorized` result preserves the
session. The separate live diagnostics adapter retains privacy-safe logging.
This client transition does not fabricate a server revocation receipt.

## Sign-out and anonymous account transition

User-facing logout is **Sign out**. `ProfileViewModel.signOut()` and the
Settings danger-zone action call `transitionToGhostSession()`; user-facing copy
does not expose internal Ghost or guest-session terminology. Apple, Google, Sign
out, anonymous recovery, Apple credential revocation, and account deletion all
enter one `AuthTransitionCoordinator`. `Core/Network/Auth/` owns that
value-state coordinator, deterministic transition policy, provider-neutral
Auth-session lifecycle coordinator, deletion classification, pure deletion
workflow helpers, separate dependency-injected fresh/recovery deletion
coordinators, and purchase-safe sign-out/proof-removal ordering, keyed stable/
compatibility handoff completion, plus ghost-merge queue/error policy and
finalization order. The public-author refresh coordinator owns direct refresh
fencing and the keyed restored-session Ghost-completion/refresh/event sequence.
The Apple credential-revocation coordinator owns notification coalescing,
transition deferral, generation fencing, exact-identity postflight, and retained
lookup task lifetime. Its task holds neither the coordinator nor manager across
provider suspension; the injected closure retains only the live provider. Core
Security owns the durable ghost-merge and purchase journals through injected
stores; `AuthRuntimeState` stores and advances the Auth transition coordinator,
generation, exact-session work leases/drain waiters, transition analytics
generations, and local sign-out state without live effects. `SupabaseManager`
retains the focused lifecycle provider, history service, and local-sign-out
coordinator; that coordinator owns the retained task and compare-before-clear
lifecycle. The manager supplies all live Supabase SDK, provider, consent,
purchase-identity, recovery, deletion, public-author event, and diagnostic
effects to the focused coordinators. The lifecycle coordinator owns session
projection and listener-driven purchase, entitlement, and historical-sync
admission. Replacing the SDK listener cancels its task and deferred replay
obligation; after lifecycle coordination, cancellation is checked again before
the operation may resume deferred credential revocation. The operation token
owns the source session, expected destination, phase, and Auth-event generation.
A second operation cannot start while one owns the SDK; late provider callbacks
and wrong-controller Apple callbacks are discarded. SDK events for an unadopted
intermediate or destination session cannot link RevenueCat, refresh entitlement,
write metadata, or change account routes ahead of the operation owner. The
Apple, Google, and destructive-account controls remain disabled for the whole
transition. Unowned account-scoped background work uses the same closed gate.
Every direct Supabase read/write, entitlement refresh, profile/preference
mutation, historical reconciliation, collection sync, and ordinary authenticated
HTTP attempt acquires an exact-session account-work lease in
`AuthenticatedTransportDispatcher`. The transition closes admission
synchronously, snapshots, cancels, and awaits every outstanding scheduled and
active consent synchronization handle—including superseded and previously
invalidated work—closes inference write admission through the
session-lifecycle/write coordinator boundary, cancels and awaits even
non-cooperative presentation/metadata tasks, waits for all admitted leases and
collection work, and only then mutates the Auth SDK session. Ordinary HTTP
retries release their per-attempt lease before 401 recovery so recovery cannot
deadlock on its initiating request. Collection sync and the bulk funding-status
probe are the narrow exceptions because their services retain separate outer
leases across the request; those endpoints return a classified `401` to their
durable retry owners instead of entering recovery. Payloads that embed an Auth
UUID also pass that UUID as an expected owner and fail before dispatch if the
live account differs. Every recursive transport, route, refresh, and service
retry remains pinned to the account that initiated the request; an unowned
request cannot silently recapture a replacement session. Foreground and
background inference keep the request body, JWT, and expected Auth UUID in one
typed request value; the background dispatcher persists that Auth UUID plus
generation in the job metadata and `inference_v3` task description before
resume, then retains the exact account lease until the URLSession terminal
callback. Offline media staging does the same through `upload_v2`, requires
every returned R2 key to equal the prepared owner key, and retains one exact
lease per task through its terminal callback. The transition drain first commits
each affected queue row back to pending and clears its source-owned staging
keys, then cancels every matching task and waits for both URLSession
disappearance and lease release; there is no timeout that allows Auth mutation
to outrun a presigned PUT, and a failed durable retreat, task cancellation, or
bounded drain expiry aborts the transition and leaves the source session intact
for retry. Callbacks and relaunched tasks may mutate local state only when their
explicit owner/generation matches both the live Auth session and durable job
metadata. Before a relaunched terminal callback crosses its first actor
boundary, it atomically reacquires and retains an exact-session account-work
lease, so the transition drain cannot overtake persistence merely because the
original process-local lease was lost. Legacy or unprovable tasks are cancelled
and restaged rather than adopted by a replacement account. Inference refuses any
staged key whose canonical owner differs from its typed request account.
Realtime channels are keyed to the final account and close while a transition is
active. If collection work was already in flight, the source session remains
stable until it finishes, and local tombstones are retained whenever the
transition began before the local commit. Each URLSession terminal delegate
callback registers its asynchronous durable work synchronously before crossing
actors. The background-session `urlSessionDidFinishEvents` callback waits for
that tracker to drain before invoking the system completion handler, preventing
suspension between network completion and final queue/result persistence.
`Core/Data/OfflineSync/Services/BackgroundTransfer` owns the tracker, retained
task leases, transition quiescence, private owner/generation validation and
adoption, terminal callback routing, and delegate adapter. The focused upload-
and inference-completion processors receive only accepted terminal work.
`Services/BackgroundInference` owns exact generation lifecycle, request
dispatch, accepted result/failure completion, and delayed status-probe/task
retirement, with focused Recovery and Retry siblings owning server-result
hydration, retryable-status persistence, general transport retry, and
server-poll lifetime. When dispatch cannot transfer its exact Auth lease after
the durable claim, it cancels the still-suspended task and finishes the process
generation only after durable retirement succeeds. Exhausted retirement retries
preserve the suspended task and active generation, keeping process state aligned
with the unresolved `.inferencing` row until a later quiescence or recovery
pass. A later successful Auth sweep or rejected terminal retirement immediately
closes that exact process generation; the Auth sweep does so before cancelling
its transport. Anonymous bootstrap is itself a coordinator-owned transition, so
restore/create cannot be overtaken by Apple, Google, Sign out, recovery, or
deletion.

Every usable session outside a pending protocol-3 stable sign-out first calls
the additive `/resolve-purchase-principal` route. Its explicit `mode` selects
the stable or legacy branch; only a definite missing route may use legacy
fallback, while auth, timeout, provider, and database failures remain
fail-closed. A fresh anonymous destination owned by a pending stable journal
uses the exact reservation claim below and never enters ordinary resolution.
Once an installation has activated a stable principal, server rollback keeps
returning that exact principal; it never instructs iOS to rotate back to the
current Auth UUID. A response requiring a newer stable protocol also fails
closed until the app is updated. A verified device-only activation fingerprint
makes that transition monotonic: it must be the exact 64-character lowercase
SHA-256 shape before the secure write begins, and later `404` or `mode: legacy`
responses are rejected rather than used as compatibility fallback.

In stable mode, the client read-verifies a device-only installation capability
and advances/read-verifies its device-monotonic binding intent before each
ordinary resolver request. The server rejects any older intent, so a cancelled
Auth request that finishes late cannot replace the current binding. Stable
**Sign out** uses a separate protocol-3 state machine:

The local `PurchaseIdentityHandoffStore` owns both this stable journal and the
legacy proof below: explicit persisted field names, fail-closed decoding,
state-specific validation, exact Keychain selection, device-only accessibility,
byte read-back, and verified removal. Its shared timestamp policy accepts 20–40
UTF-8-byte fractional PostgreSQL and whole-second RFC 3339 values for both
protocols. `PurchaseIdentityHandoffCoordinator` owns completion task lifetime
keyed by destination, Auth generation, and transition owner; stable claim and
compatibility completion routing; session/cancellation fences; and proof removal
through injected boundaries. The Auth workflow owns the reusable phase order,
while the manager injects all live server, provider, session, entitlement,
journal, and logging effects.

1. While the exact linked source session and binding generation are live, iOS
   generates a rotation UUID and 256-bit secret, persists/read-verifies a
   `preparing` Keychain journal, and invokes `prepare_signout_rotation`.
2. iOS validates the same principal, App User ID, binding generation, and
   server-issued expiry, then persists/read-verifies the `prepared` journal
   before closing the source session.
3. Only one different anonymous identity created no earlier than preparation may
   invoke `claim_signout_rotation`. A prepared reservation blocks generic
   resolver intent and binding writes. Its terminal intent fence also rejects
   any resolver completion begun before preparation after claim, cancellation,
   or expiry.
4. The client validates the atomic claim receipt and advanced generation,
   serially links the unchanged RevenueCat App User ID, requires
   `EntitlementManager.beginSession(...)` to return `true`, and then revalidates
   task cancellation, the exact anonymous manager-published user, nonexpired SDK
   session, captured Auth generation, and transition context before removing the
   journal last.

An unrelated permanent session, old anonymous session, malformed/unreadable
journal, expired claim, provider failure, or entitlement failure remains closed
and cannot invoke the generic resolver or RevenueCat link. If local sign-out
fails or the exact source is restored first, that source invokes
`cancel_signout_rotation` with the same proof and clears the journal only after
a terminal `cancelled` or `expired` receipt; a `preparing` cancellation safely
tombstones a request whose prepare response was lost. Foreground activation
retries the exact durable destination and proof without creating a replacement
capability or provider customer. There is no `syncPurchases()` or RevenueCat
customer-transfer call. Email, username, display name, avatar, account kind, and
Auth UUID are never written to the shared stable provider customer; adoption
deletes any legacy values and synchronizes that deletion before stable paid
readiness opens. The rotation UUID, raw secret, capability/fingerprint, and
every journal identity field are bearer or identity material and never enter
logs, analytics, crash metadata, or request URLs.

In legacy mode, `LegacyPurchaseHandoffRemoteService+Live.swift` first calls
`/transfer-signout-purchases` to snapshot authoritative StoreKit-backed access
and persists its one-use proof under `Merian_PendingSignOutPurchaseHandoff_v1`
with `whenUnlockedThisDeviceOnly`. A malformed or oversized server expiry fails
before that secure write. A preparation or verified-Keychain-write failure
leaves the linked session untouched. Only then does the client close the local
Supabase session and create one fresh anonymous identity. A linked SDK session
is always presented as linked; the retired `Merian_GhostModeUserID_v1`
presentation marker is deleted during startup and can no longer hide an
authenticated account. The anonymous Profile state offers **Continue with
Apple** and **Continue with Google**.

The fresh legacy anonymous identity binds through that same typed adapter before
RevenueCat is linked to its uppercase UUID. The client then calls
`Purchases.syncPurchases()` under the project's required **Transfer to new App
User ID** restore behavior, asks the server to verify authoritative destination
CustomerInfo, refreshes the Merian entitlement projection, and removes the proof
last. Every suspended phase and the removal boundary revalidate task
cancellation, the exact anonymous manager-published user, nonexpired SDK
session, captured Auth generation, and transition context. A retry without a
transition owner becomes stale as soon as another Auth transition opens.
Purchase/restore/redeem admission remains disabled while that proof exists.
Temporary failures retain it and auth-state restoration retries the same
destination. The anonymous Profile also exposes a visible **Finish sign out**
action, so recovery does not depend on a relaunch or another provider attempt. A
restored source account can cancel only a still-unbound proof; the server
refuses cancellation once receipt movement may have begun. An already-issued
compatibility proof always finishes against its exact uppercase destination UUID
even if `principal_mode` changes to `stable` while the transition is in flight.
Only after the proof is cleared may the resolver adopt/rebind that installation
to a stable principal; this prevents receipt sync and server verification from
targeting different customers. If a finite prepared purchase expires before
first completion, the server refreshes the source before accepting the
destination's current StoreKit state, so natural expiry can finish free without
overlooking a source renewal. Completed replay uses the immutable attested state
and snapshot.

While a proof is unresolved, generic auth-state bootstrap and refresh must not
link the anonymous RevenueCat identity early. A confirmed-missing-session `401`
also preserves the exact Auth session instead of rotating or locally clearing
it; an unreadable Keychain proof is treated as pending. Account deletion is
disabled in the UI while any local proof is unresolved. The server rejects
deletion of either side after binding; if deletion wins before binding, bind
fails before RevenueCat is mutated. The database also prevents anonymous cleanup
or profile merge from deleting a bound destination.

Only StoreKit-backed access moves. RevenueCat promotional/beta grants are
account-bound and remain on the linked source rather than being cloned onto a
second customer. The server requires an explicit RevenueCat v1
`store: app_store` purchase record; `store: promotional` and unknown/missing
stores fail closed. Active detached seven-day pass history is accepted only when
the durable database projection confirms the same expiry, preventing refunded
historical purchases from being resurrected.

`SupabaseManager` closes the authenticated-request gate and clears observable
account state before asking Supabase Auth to invalidate the local session. It
asks the Auth coordinators to cancel bootstrap, Ghost-merge, and public-author
refresh tasks first, ignores late authenticated SDK events while sign-out is
active, and serializes concurrent sign-out callers through one task.
`getValidAuthHeaders()` fails closed during that interval, checking both before
and after asynchronous token retrieval, and session-refresh retries cannot
reopen authenticated state. Explore, Field trip, and profile Edge requests
therefore cannot launch with a token that is being invalidated.

Low-level `signOut()` cannot later recover the same Supabase anonymous account.
Ordinary user logout therefore calls `transitionToGhostSession()` to request one
replacement anonymous identity after the mode-specific durable boundary is
prepared. Stable success means that replacement Auth session claims the exact
server reservation, links the unchanged purchase principal, establishes a
current entitlement session, and clears the journal last. Legacy success means
the anonymous Supabase identity, exact custom RevenueCat identity, receipt sync,
server verification/reconciliation, and current entitlement read all completed.
An anonymous-session result by itself is not success. The same identity rotation
remains available for stable missing/invalid-session recovery after SDK refresh
fails only when no purchase handoff is pending; a generic `401` never reaches
it. Account deletion intentionally calls `signOut()` alone so it does not
recreate an identity during deletion. `/safe-delete` returns
`409 purchase_continuity_pending` if either side of an active handoff is
targeted; the user must use **Finish sign out** first. The `/safe-delete` call
may return immediate `200` completion or `202` durable acceptance. The shared
request layer strictly decodes the matching status plus the required
`manual_provider_revocation_required` boolean; missing or contradictory receipts
are invalid responses. A legacy Apple disposition is persisted before sign-out
so the app-root manual-removal notice survives local account and SQLite cleanup.
Backend intent and relational cleanup are persisted before the client signs out.
The scheduled account-deletion reaper owns cursor-persisted R2 sweeps, delayed
empty verification, Apple provider revocation when a Vault credential exists,
and terminal Auth removal; a new request therefore normally receives `202`.

This strict receipt and durable notice exist only in supporting binaries. An
older client can ignore `manual_provider_revocation_required`, so publishing the
new build does not prove fallback delivery. Public promotion remains blocked
until an enforceable minimum-supported-build control or an independent
server-delivered manual fallback covers those installed clients.

Account deletion retains ownerless exact scientific facts under the
[`scientific-observation retention contract`](../../../../../docs/backend-and-data/17-scientific-observation-retention.md);
`signOut()` must not imply that every submitted observation is erased. The
provider-specific lifecycle is canonical in the
[`Sign in with Apple account-deletion contract`](../../../../../docs/backend-and-data/20-sign-in-with-apple-account-deletion.md).
Before `/safe-delete` can commit, iOS writes `capability_preparation_pending`,
then synchronously generates an atomic Keychain envelope with independent
256-bit recovery and acknowledgement capabilities and verifies the exact encoded
bytes before the first network suspension. Its intended next steps are the
server's non-destructive v2 preparation, `capability_prepared_pending`, and
`capability_intake_pending` before destructive commit. This ordering closes both
lost-request and lost-response windows: a relaunch from either preparation phase
re-enters the deletion transition; a crash before commit publicly cancels as
`not_committed` without erasing Auth or SwiftData, while a crash after commit
recovers the job receipt. If another device commits first, the database
atomically binds every still-live prepared proof to the same deletion job and
tombstones expired proof hashes as committed. No expired preparation is promoted
into a 180-day recovery capability. While commit is unresolved, the only
permitted authenticated call is an exact-transition replay. If the cached Auth
session is gone, the app submits only the recovery capability to
`/recover-account-deletion`; acknowledgement after verified cleanup uses only
its distinct proof. Neither request contains an account, job, provider, or
purchase identity.

The live intake path checks task cancellation before its first recovery marker.
The legacy branch checks again after the intake marker; the v2 branch checks
again before preparation, after its non-destructive response and before the
prepared/intake marker pair, and after that pair before destructive commit.
Cancellation never rolls back evidence that already crossed a durable boundary:
recovery owns the retained marker or capability, while the cancelled task
dispatches no later destructive effect.

The operation-specific preparation receipt described in the
[focused matrix](#preparation-receipt-contract) admits the checked-in handler
shape without weakening accepted-deletion or recovery receipts. Real-session
execution of this workflow remains part of the integration checklist rather than
source-test evidence.

A returned durable receipt promotes the marker to `capability_cleanup_pending`;
only then may iOS sign out locally, purge every active SwiftData model, and
read-back verify account-derived `UserDefaults` cleanup. It then resets
process-local settings, gamification, badge, and image-cache projections. After
cleanup, iOS acknowledges recovery, records `capability_retirement_pending`,
read-after-delete verifies Keychain removal, and clears the marker last.
Relaunch from retirement re-verifies local Auth absence and repeats the
idempotent SwiftData/preferences purge before proof removal, so a marker-writing
durability failure cannot skip either cleanup boundary. A definitive
`409 purchase_continuity_pending` first records
`capability_rejection_retirement_pending`, then read-after-delete verifies the
unused proof is gone, and clears the marker last. Relaunch in this phase retires
that proof, restores only the exact cached source session, and then clears the
barrier; it never signs out or purges local data because the server proved the
deletion intake did not win. Transport, Auth, gateway, `5xx`, cancellation, and
malformed responses retain the proof and barrier because commit may still be in
flight. An unknown legacy v1 proof also remains ambiguous. Installed
pre-capability intake with no proof creates and verifies one raw v1 proof before
legacy replay; a proofless prepared-v2 marker restores only its exact cached
source because destructive commit had not started. An installed intake/cleanup
marker with a v2 envelope may be the historical mixed-domain state whose
recovery value was sent to legacy intake. Its v2 unknown result must therefore
check v1 recovery: a positive legacy match continues cleanup, while another
unknown retains the proof and barrier. Outside that compatibility state, an
unknown v2 proof permits proof-only retirement because commit requires the
missing server preparation. A `not_committed` or an unknown v2 proof admitted
after compatibility routing first retires the unused proof, then adopts only the
exact cached unexpired Supabase session into the transition coordinator while
the barrier remains. It clears the barrier before publishing that same UUID and
anonymous/account kind or reopening account work. The distinct
`account_deletion_recovery_preparation_expired` response is a non-authorizing
tombstone match and retains the barrier. Only a matched committed capability's
`account_deletion_recovery_expired` `410` is positive evidence that deletion was
accepted; it permits conservative local erasure, after which the independent
acknowledgement proof remains valid and then permits verified retirement. It
does not reveal pre-cleanup job state. Legacy `intake_pending` and
`cleanup_pending` remain readable during the installed-client compatibility
window. No marker or proof stores an account, provider, job, or request
identifier. A refreshable `401` renews only the transition's exact expected
Supabase session; it cannot start nested recovery or relink RevenueCat,
analytics, profile metadata, or entitlements.

## Explore emoji-reaction endpoints

`Endpoints/MerianNetworkClient+ExploreReactions.swift` adds explicit-state
`setExploreReaction(target:id:emoji:selected:)` for the post/comment setter
routes and `getExploreReactions(target:id:afterOrder:)` for continuation pages.
These are separate from the unchanged legacy toggle method. The summary read
uses the existing bounded read-replay policy; setters remain conservatively
excluded from ambiguous transport retries even though the server mutation is
idempotent. Classified auth-refresh replay follows the common transport policy.

`Models/Explore/ExploreReactionAPIModels.swift` owns response/page values.
Post/detail/comment summaries and their cursor are optional for older-server
compatibility; native UI treats missing arrays as empty. Groups merge by
canonical emoji, and post ❤️ results use existing like semantics. Unicode
validation and canonicalization remain server-authoritative.

The Notifications adapter sends `supports_post_reactions: true` for list,
unread-count, mark-read, and device registration. This capability is separate
from push opt-in and from account-scoped registration coordination metadata.

Wire behavior is covered by `ExploreInteractionEndpointTests`,
`NotificationEndpointTests`,
`NotificationAndPublicProfileEndpointTransportTests`, and
`AuthenticatedRequestRetryPolicyTests`; Feed state owns optimism/rollback. See
the
[API contract](../../../../../docs/backend-and-data/05-api-contracts.md#explore-emoji-reactions-2026-09-18)
and
[verification matrix](../../../../../docs/development-guides/08-testing-strategy.md#explore-emoji-reaction-verification).

`getExplorePostReactors(postId:afterUserId:)` adds the replayable authenticated
read for detail reactor identities. `ExplorePostReactorsPage` contains unique
count, preview names, public reactor rows, and a nullable UUID cursor. The
[people contract](../../../../../docs/backend-and-data/05-api-contracts.md#post-reaction-people)
defines visibility, likes-as-heart, and pagination semantics.

### Conversational dictionary search

`Endpoints/MerianNetworkClient+SpeciesDiscoverySearch.swift` adds the dedicated
`searchSpecies` operation through the existing authenticated encoded-JSON
bridge. `SpeciesDiscoverySearchAPIModels.swift` owns hand-written bounded
request and response DTOs; `Decoding/SpeciesSearchResponseValidator.swift`
checks identity, version, result kind, context, row bounds and cursors before
feature state changes. No automatic replay is enabled for provider-backed
search. Search state and tests remain in
[Species Dictionary Search](../../Features/SpeciesDictionary/Search/README.md).
