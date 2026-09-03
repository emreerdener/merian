# Species Dictionary Detail

`Detail` owns the in-app public species page, its UUID-first share action,
reference gallery, typed presentations, and the authenticated Community
sightings preview and paginated grid. The canonical behavior, privacy, API, and
release contract remains
[Species Dictionary](../../../../../../docs/features-and-hardware/16-species-dictionary.md).

## Ownership

- `Models/` owns platform-neutral request, state, share, presentation,
  telemetry, and hero-edge policies. Cross-surface routes, taxonomy adaptation,
  and reference-image labels/attribution live in sibling `Shared/Models`;
  Codable response and cursor DTOs remain in `Core/Network`.
- `Services/` is the only Detail owner that resolves `MerianNetworkClient`,
  `AppDIContainer`, haptics, entitlement state, telemetry, the fallback Explore
  state owner, or the Field Chat state owner. Its small closure-based dependency
  values are injected into the feature; Detail does not add a singleton or a
  broad protocol.
- `ViewModels/` owns `@MainActor @Observable` page and Community loading state.
  Views and components do not call endpoints.
- `Views/` owns the standalone navigation shell and the shared page-content
  host. It retains navigation, sheet/full-screen bindings, scroll-edge state,
  lifecycle tasks, and Field Chat presentation timing.
- `Components/Community`, `Content`, `Gallery`, `Loading`, and `Shared` own
  their corresponding rendering only. Cross-feature observation charts,
  taxonomy, habitat, lookalikes, media gallery, Explore post detail, and Field
  Chat remain with their existing feature owners.

Every production Swift file in this directory must remain at or below the
600-line review ceiling. `project.yml` includes this source tree recursively, so
new groups are registered by running `make xcodegen`, not by editing the Xcode
project directly.

The Community adapter calls `getExploreSpeciesPosts` in
`Core/Network/Endpoints/MerianNetworkClient+ExploreBrowsing.swift`. That
stateless request retains the quality-score cursor and typed Explore card page;
it does not own Dictionary page validation/caching or Community loading state.

The page adapter calls the two detail overloads in
`Core/Network/Endpoints/MerianNetworkClient+SpeciesDictionary.swift`. Core's
`SpeciesDictionaryResponseValidator` validates schema/identity and
`SpeciesDictionaryResponseCache` owns response reuse. The cache instance remains
private to `MerianNetworkClient`; its fixed-result request bridge owns lookup,
authenticated loading, validation, and insertion. Detail injects endpoint
closures, not a cache reference or a cache-population hook. The feature keeps
page loading, retry, error classification, and presentation timing. See the
[Core identity/cache contract](../../../Core/Network/README.md#species-dictionary-identity-and-cache-boundary)
for TTL, alias, cancellation, and reset compatibility.

## Loading And Concurrency

`SpeciesDictionaryPageViewModel` normalizes the route identity and classifies
endpoint failures through its injected service boundary. Canonical UUIDs remain
UUID-first; an invalid, synthetic, or `external:` route ID is discarded so a
usable scientific name becomes a name-only request. Each load receives a request
generation; only the latest generation may publish a species, not-found result,
readable error, or successful-load telemetry. The page-open event remains once
per state-owner lifetime.

Core Network requires `schema_version = 1` and validates the returned identity
before caching. An exact UUID hit may carry a stale display-name hint. A UUID
miss may recover to another local UUID only when the supplied normalized
scientific name matches. A name-only response must return that name and either a
canonical UUID or an `external:` identity. Only the returned canonical UUID and
returned normalized name become cache keys; a stale requested UUID and an
`external:` ID never become aliases.

`SpeciesCommunitySightingsViewModel` applies the same latest-request-wins rule
to species changes, refresh, and pagination. Refresh invalidates active
pagination before starting a replacement first page, so a late page cannot be
merged into reset state. Initial and page failures remain supplemental and do
not block the public dictionary content.

The
[concurrency contract](../../../../../../docs/system-architecture/02-zero-oom-and-concurrency.md#species-dictionary-detail-request-generations)
documents why structured-task cancellation is paired with generation and
identity checks.

## Field Chat

Every loaded detail whose returned `SpeciesDictionaryEntry.id` is a valid UUID
shows `FieldChatToolbarButton` at the bottom right. Loading, error, not-found,
and noncanonical-ID states hide the bottom bar; the native Share action remains
in the top bar. Because direct, deep-linked, and similar-species routes all use
`SpeciesDictionaryPageContentView`, they share this behavior.

A Free viewer opens the existing `PaywallView`. A Pro viewer preflights
`/species-dictionary-chat`, then presents the shared `InsightChatSheet` at its
large detent with owner-only scan actions disabled. The source-specific view
model preserves exact subject-generation fencing across load, send, retry/edit,
delete, feedback, and prompt suggestions. A transcript already loaded in memory
remains readable offline; sending and other mutations remain disabled until the
network returns.

The shared sheet, state owner, source model, and endpoint adapter live in
`Features/FieldChat`. Dictionary Detail owns the loaded-species identity,
eligibility, paywall routing, and typed presentation slot; it does not resolve a
Field Chat endpoint directly.

Gallery, author profile, Field Chat, and paywall share one typed
`SpeciesDictionaryPresentation` value. Sheet and full-screen bindings filter
that same slot, so they cannot mount together. A late Field Chat preflight must
still match the loaded canonical species, remain uncancelled, and find the slot
empty before it presents.

The server owns authorization, persistence, limits, and context. The client
requires `subject_id` and every compatibility `messages[].scan_id` to equal the
canonical species UUID before applying success. Dictionary telemetry includes
only entry point, content quality, entitlement state, and broad action fields;
it never includes species names or IDs.

This is a source candidate, not a released capability. Release remains blocked
until same-day sends survive conversation deletion, the Dictionary route is in
the iOS ambiguous-replay allowlist with a lost-response regression, executable
authenticated route tests run in the deploy gate, and refusals/local fallback
chips use fully source-specific, safely bounded labels. See the
[canonical Species Dictionary release status](../../../../../../docs/features-and-hardware/16-species-dictionary.md#candidate-release-status).

## Reference Gallery Safety

`SpeciesDictionaryReferenceGallery` filters every image through
`ExternalReferenceImagePolicy` before choosing the initial item, building the
carousel, or opening the fullscreen presentation. A denied first image promotes
the next permitted item without changing its source/attribution metadata. If no
permitted image remains, the normal leaf placeholder is shown. Catalog
thumbnails use the same policy when converting reference strings to `URL`, so
detail and catalog surfaces cannot diverge.

The current exact rule suppresses iNaturalist media `605615444` (GBIF occurrence
`5938154750`) only. It must not remove the European wildcat row or its
navigation route.

## Tests

Mirrored tests live under `MerianTests/Features/SpeciesDictionary/Detail/`:

- `SpeciesDictionaryPageViewModelTests` owns identity normalization, state,
  telemetry, retry, and stale success/failure fencing.
- `SpeciesCommunitySightingsViewModelTests` owns initial load, pagination,
  de-duplication, failures, species replacement, and refresh/pagination overlap.
- `SpeciesDictionaryDetailPresentationTests` owns share, gallery, attribution,
  alternate-name, Field Chat, hero-edge, and grid policies. Cross-surface route
  and reference-image behavior/ownership is guarded by
  `SpeciesDictionarySharedPresentationTests` and the sibling Shared architecture
  suite.
- `SpeciesDictionaryDetailServiceTests` owns both UUID-first and scientific-name
  endpoint-adapter paths plus failure classification.
- `SpeciesDictionaryDetailArchitectureTests` enforces directory ownership,
  Services-only live resolution, platform-neutral Models, Core-owned wire DTOs,
  separated root/content views, retired aggregate-file removal, and the 600-line
  ceiling.

Core Network's `SpeciesDictionaryAPIModelsTests` retains wire decoding;
`SpeciesDictionaryDetailEndpointTests` retains the existing request/recovery
regressions. `SpeciesDictionaryResponseValidatorTests`,
`SpeciesDictionaryResponseCacheTests`, and the Dictionary request/transport
suites add deterministic boundary coverage. Run the
[Core Dictionary matrix](../../../Core/Network/README.md#species-dictionary-verification)
and the complete unit target for endpoint/cache changes.

Species Community wire payload and quality-cursor regressions live in
`MerianTests/Core/Network/Endpoints/ExploreBrowsingEndpointTests.swift`, rehomed
from the aggregate network suite, with failure/replay coverage in
`ExploreBrowsingEndpointTransportTests.swift`. Wire changes require the
[Core Network browsing matrix](../../../Core/Network/README.md#endpoint-verification)
in addition to the feature's state/service tests.

Field Chat wire and replay coverage lives in the shared Core suites, including
the rehomed `SpeciesDictionaryChatEndpointTests`; strict response boundaries
live in `FieldChatResponseDecoderTests`. Run the
[Core Network Field Chat matrix](../../../Core/Network/README.md#field-chat-verification)
and the complete unit target for chat endpoint or validation changes. That
matrix joins the shared request/transport and single-read snapshot tests with
`Features/FieldChat`'s source-adapter and state suites. These tests do not move
chat state into Dictionary Detail or replace its loaded-species/presentation
fences.
