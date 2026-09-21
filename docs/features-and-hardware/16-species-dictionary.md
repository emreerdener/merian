# Species Dictionary Page

> **Beta policy update — September 18, 2026:** The owner authorized the existing
> beta backend rollout under the
> [Field Chat beta release decision](../release-evidence/field-chat-beta-release-decision-2026-09-18.md).
> `species_dictionary_chat_production_hold` is inactive by explicit exception,
> not because every full-release criterion passed. Statements below requiring
> all external/device/hosted-token evidence before backend rollout describe the
> full-release policy; that evidence remains open. Exact-SHA backend validation,
> live repository controls, runtime security/consent, and audited cutover
> activation remain required. This exception does not authorize iOS
> distribution.

The Species Dictionary Page is the standalone in-app and public-web reference
page for a discovered species. Its primary content remains canonical public
species-level dictionary data and licensed reference imagery. A separate
authenticated **Community sightings** request adds visibility-safe Explore cards
without placing viewer-sensitive data in the cacheable dictionary response. The
on-device local-observation overlay inside `SpeciesObservationChartsCard`
remains local; those counts are never sent to Supabase.

This creates three separate species surfaces in the iOS app:

| Surface                 | Scope                         | Primary data source                                                                                                                                                                                                |
| ----------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Insight scan            | A user's specific scan result | `InferenceEngine.shared.speciesData`, local scan media, and per-scan AI reasoning                                                                                                                                  |
| Explore post            | A public shared scan          | Explore post/detail endpoints plus the backing public scan projection                                                                                                                                              |
| Species dictionary page | General species reference     | `species_dictionary`, `species_lookalikes`, public reference imagery, local on-device observation aggregates, cached global public iNaturalist stats, and a separate authenticated Explore species-post projection |
| Public species page     | Anonymous species reference   | Versioned public `/species-dictionary` Edge response only                                                                                                                                                          |

## Product Scope

In-app entry includes similar-species cards in Insight and Explore,
Identify/Species browsing, and canonical or legacy external species links. An
external link selects Explore's Identify tab and Species mode before pushing the
page in the existing Explore navigation stack. The standalone dictionary
presenter still uses a large-detent sheet when opened directly.

Included in V1:

- canonical scientific and common names
- alternate common names, rendered as a compact line under the primary common
  name
- reference image gallery from normalized public reference imagery
- Wikipedia overview
- habitat description and GBIF heatmap when `gbif_taxon_key` is available
- observation pattern charts from local on-device logs plus cached global public
  iNaturalist stats
- a six-post **Community sightings** preview with a paginated Explore grid
- taxonomy
- IUCN Red List status
- hazard status
- similar species that route to another dictionary page in the same stack
- a top-right native share action after the canonical UUID and names have loaded
- a bottom-right private Pro Field Chat action for every loaded canonical UUID
  in the source candidate (release-held; see
  [Candidate Release Status](#candidate-release-status))
- a server-rendered browser fallback at
  `https://naturebook.earth/species/{speciesId}/{slug}`

Excluded in V1:

- local scan lists, scan media, or per-scan detail pages
- user-uploaded gallery media
- field notes
- comments
- locations
- preferred-name editing
- user-specific review state

The public web page additionally excludes local observation charts,
authenticated Community sightings, all user media, and similar-species
thumbnails. Those thumbnails are withheld until their payload includes public
license and attribution fields. It does not expose or link to authenticated
Field Chat.

## Architecture

Primary files:

- `services/supabase/functions/_shared/publicSpeciesProjection.ts`
- `services/supabase/functions/species-dictionary/index.ts`
- `services/supabase/functions/species-dictionary/db.ts`
- `services/supabase/migrations/20260901180000_add_public_biological_species_eligibility.sql`
- `services/supabase/functions/species-dictionary-chat/index.ts`
- `services/supabase/functions/species-dictionary-chat/db.ts`
- `apps/ios/Merian/Core/Network/SpeciesDictionaryAPIModels.swift`
- `apps/ios/Merian/Core/Network/SpeciesDictionaryIdentity.swift`
- `apps/ios/Merian/Core/Network/SpeciesObservationStatsAPIModels.swift`
- `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`
- `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+SpeciesDictionary.swift`
- `apps/ios/Merian/Core/Network/Decoding/SpeciesDictionaryResponseValidator.swift`
- `apps/ios/Merian/Core/Network/Caching/SpeciesDictionaryResponseCache.swift`
- `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+ExploreBrowsing.swift`
- `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+FieldChat.swift`
- `apps/ios/Merian/Core/Network/Decoding/FieldChatResponseDecoder.swift`
- `apps/ios/Merian/Core/Network/InsightChatAPIModels.swift`
- `apps/ios/Merian/Core/Routing/Models/AppRouteModels.swift`
- `apps/ios/Merian/Core/Routing/Coordination/AppRouteCoordinator.swift`
- `apps/ios/Merian/App/MerianApp.swift`
- `apps/ios/Merian/Features/Capture/Shell/ViewModels/CaptureWorkspaceViewModel+Routing.swift`
- `apps/ios/Merian/Features/Explore/Shell/Views/ExploreView.swift`
- `apps/ios/Merian/Features/SpeciesReference/Views/SpeciesObservationChartsCard.swift`
- `apps/ios/Merian/Features/SpeciesReference/Services/SpeciesObservationStatsDependencies.swift`
- `apps/ios/Merian/Features/SpeciesReference/ViewModels/SpeciesObservationStatsViewModel.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Detail/ViewModels/SpeciesDictionaryPageViewModel.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Shared/Models/SpeciesDictionaryNavigation.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Shared/Models/SpeciesDictionaryTaxonomyPresentation.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Shared/Models/SpeciesDictionaryReferenceImagePresentation.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Detail/ViewModels/SpeciesCommunitySightingsViewModel.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Detail/Models/SpeciesDictionaryDetailPresentation.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Detail/Services/SpeciesDictionaryDetailDependencies.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Detail/Views/SpeciesDictionaryPageView.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Detail/Views/SpeciesDictionaryPageContentView.swift`
- `apps/ios/Merian/Features/FieldChat/Services/FieldChatEndpoint.swift`
- `apps/ios/Merian/Features/FieldChat/ViewModels/InsightChatViewModel.swift`
- `apps/ios/Merian/Features/FieldChat/Views/InsightChatSheet.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Detail/Components/Gallery/SpeciesDictionaryReferenceGallery.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Detail/Components/Content/SpeciesDictionaryCards.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Detail/Components/Community/SpeciesCommunitySightingsSection.swift`
- `apps/ios/Merian/Features/SpeciesReference/Components/Lookalikes/SimilarSpeciesGallery.swift`
- `apps/ios/Merian/Features/SpeciesReference/Services/SimilarSpeciesImageDependencies.swift`
- `apps/ios/Merian/Features/Insights/Content/Views/BiologicalView.swift`
- `apps/ios/Merian/Features/Explore/Feed/Views/ExplorePostDetailView.swift`
- `apps/ios/messages/ScanSharing/Shared/MessageScanShareCache.swift`
- `apps/web/lib/species.ts`
- `apps/web/app/species/[speciesId]/page.tsx`
- `apps/web/app/species/[speciesId]/[slug]/page.tsx`

`SpeciesDictionaryPageView` is the standalone sheet shell. It owns a
`NavigationStack`, presents at `.large`, hides the sheet grabber, and renders
the root `SpeciesDictionaryPageContentView` with an `xmark` close button. Pushed
dictionary pages render the same content view with native back navigation
instead of a close button. When dictionary content is pushed from Insight or
Explore, those sheet roots own the navigation stack and register
`SpeciesDictionaryRoute`; the dictionary content does not create a nested sheet.
It does not mount `InferenceEngine`, does not read SwiftData scan records, and
does not reuse `InsightSheetViewModel`.

Detail follows a feature-owned `Models`, `Services`, `ViewModels`, `Views`, and
grouped `Components/{Community,Content,Gallery,Loading,Shared}` boundary.
Platform-neutral Models own request, page state, share, presentation, and
telemetry policy. Services alone resolve the live dictionary and Community
endpoints, telemetry, haptics, entitlement state, fallback Explore state, and
Field Chat state. Views and components contain no direct networking and retain
navigation, presentation bindings, scrolling, lifecycle tasks, and rendering.
Codable response and cursor contracts remain in `Core/Network`.
`SpeciesDictionary/Shared/Models` owns route/entry-point values, taxonomy
adaptation, and reference-image labels/attribution used across Detail, Catalog,
Explore, and Field Trips. The feature-local
[`Species Dictionary` README](../../apps/ios/Merian/Features/SpeciesDictionary/README.md)
is the concise ownership and contributor map.

`SpeciesDictionaryPageViewModel` is an `@Observable @MainActor` model with four
user-visible states:

- `loading`
- `loaded(SpeciesDictionaryEntry)`
- `notFound`
- `error(String)`

The model canonicalizes the incoming UUID/name before fetching and consumes a
small injected dependency value. Invalid, synthetic, and `external:` route IDs
are removed so a usable name becomes a name-only request. Canonical UUIDs remain
UUID-first. Each load increments a request generation, so a late success or
failure cannot overwrite a newer route load or retry. A marked handler-owned
`404` maps to `notFound`; a platform route `404` becomes the typed
temporary-service error and cannot cache the species as missing. Other failures
map to `error`.

`SpeciesObservationChartsCard` is embedded in the loaded dictionary content
after Habitat & Distribution. It owns its own generation-fenced
`SpeciesObservationStatsViewModel`. Injected
`SpeciesObservationStatsDependencies` fetch local scan projections through the
Services-owned `SpeciesObservationStatsDatabaseActor` and adapt the public
`/species-observation-stats` client call. The platform-neutral
`SpeciesObservationStatsReducer` aggregates local values on-device. The
dictionary page passes `species.id` and `species.scientificName`; the backend
requires that canonical pair before it may resolve/store `inaturalist_taxon_id`
or call the provider.

`SpeciesCommunitySightingsSection` follows the observation charts and precedes
similar species. It loads six square tiles, hides itself after an empty or
failed request, and shows **View all** only when the backend returns another
cursor. The destination reuses those six results, loads 30-item pages in the
same three-column grid, deduplicates posts, and supports pull-to-refresh.
Explore and Profile hosts supply their existing `ExploreFeedViewModel`;
standalone Dictionary, Scans, and Insight routes use a local fallback so tile
taps still push the existing Explore post detail in the current navigation
stack. Species changes and refreshes advance the Community request generation;
refresh therefore invalidates active pagination before its replacement first
page begins, and stale pages or failures cannot publish into the new state.

## Entry Point

`SimilarSpeciesGallery` can either emit `NavigationLink(value:)` routes through
`routeForSpecies` or call an optional legacy `onSpeciesSelected` callback. The
Insight sheet biological result passes a route builder from `BiologicalView`:

```swift
SimilarSpeciesGallery(
    similarData: similarData,
    currentScientificName: inferenceEngine.speciesData?.scientificName,
    currentCommonName: inferenceEngine.speciesData?.commonName,
    routeForSpecies: insightSimilarSpeciesRoute
)
```

The sheet root owns the route destination, so the user sees a single navigation
stack: Insight or Explore detail -> Species Dictionary -> another dictionary
page if they tap a similar species again. A canonical `speciesId` is UUID-first;
`scientificName` is the normalized recovery/display identity. A UUID miss may
recover only to an exact local name match, while an invalid or synthetic route
ID becomes a name-only compatibility request.

Explore post detail uses the same route from its public
`/get-explore-post-detail` similar-species payload. The Explore entry point is
detail-only for internal post navigation; feed cards, map previews, author
profile previews, and scan library do not open the species dictionary.

External links accept canonical and legacy HTTPS/custom-scheme forms:

```text
https://naturebook.earth/species/{speciesId}
https://naturebook.earth/species/{speciesId}/{slug}
https://merian.earth/species/{speciesId}
https://merian.earth/species/{speciesId}/{slug}
naturebook://species/{speciesId}
merian://species/{speciesId}
```

New shares emit the canonical UUID-first HTTPS form with a lowercase ASCII slug
derived from the common name, or the scientific name and then `species` when a
readable common-name slug is unavailable. The slug is presentation-only. The
parser accepts the canonical form, UUID-only compatibility form, and legacy
host/scheme forms, ignores the optional slug for identity, and requests
`AppRoute.speciesDictionary` with only the normalized UUID.
`CaptureWorkspaceViewModel` clears conflicting launch routes, protects the
destination from the immediate foreground timeout reset, opens Explore, selects
Identify/Species, and pushes a `SpeciesDictionaryRoute(entryPoint: .deepLink)`.

The share button appears only after the loaded response supplies a valid UUID
and uses the loaded names to build its readable slug. Its primary item is the
canonical HTTPS URL, its subject is the common name, and its message is brief
Naturebook copy. A browser recipient gets the public page; an installed current
app claims the same URL through Universal Links.

## In-App Field Chat

Name-only Similar Species links, including older saved Insights, may initially
load an `external:` reference entry. iOS then calls the authenticated
`/resolve-species-dictionary` route to reuse or create a verified canonical
species record. Reference content stays visible during resolution; failure shows
an explanation and Retry. A successful identity receipt binds the original name
to the accepted species UUID, which is fetched and checked for exact identity
before Share and Field Chat become available. Retry tasks are view-owned and
cancel on dismissal; replaying an old resolution retry cannot invalidate a newer
page load. Already-visible public reference fields can fill missing canonical
content in the current presentation while background enrichment runs; this does
not alter the network cache. Opening the page never starts chat.

The resolver checks exact accepted GBIF identities, handles verified synonyms,
preserves existing curated rows, and limits requests per user and globally. It
creates no lookalike relationships or recursive lookalike work. The public
dictionary read remains read-only. See the
[resolver contract](../../services/supabase/functions/resolve-species-dictionary/README.md).
This is source behavior; migration, endpoint deployment, and iOS distribution
remain separate release steps.

`SpeciesDictionaryPageContentView` shows the shared `FieldChatToolbarButton` at
the bottom right only when its loaded response contains a valid canonical
species UUID. Loading, not-found, error, and invalid ID states keep the bottom
bar hidden. Share remains in the top bar. Because the same content view owns
direct, deep-linked, and pushed dictionary pages, the behavior also follows
similar-species navigation without adding a nested sheet or stack.

The client captures the loaded UUID before asynchronous presentation work. A
Free tap routes to the existing paywall. A Pro tap activates
`FieldChatSource.speciesDictionary`, loads the viewer's saved thread from
`/species-dictionary-chat`, revalidates the active loaded UUID, and presents the
shared `InsightChatSheet` at `.large`. Owner-only Insight actions—field-note
summary, sheet-level feature feedback, candidate review, and reanalysis—remain
disabled. Answer feedback, delete, retry/edit, and deterministic prompt chips
remain available. A thread already loaded in memory stays readable offline;
network mutations remain unavailable.

Dictionary Field Chat can answer general questions from well-established species
knowledge even when the bounded dictionary text lacks the requested detail.
Shared backend rules distinguish typical traits from observations of an
individual, acknowledge uncertainty and relevant variation, and retain the
existing safety and privacy limits. This does not add live search, media access,
or evidence for current/local conditions.

The answer rules follow the complete dictionary context. `Unavailable` limits
the stored reference field rather than the assistant's stable species knowledge,
and casual pronouns in typical-trait questions refer to the dictionary species.
The shared synthetic provider check exercises this behavior across Dictionary,
Insight, and Explore without using user content.

The shared implementation is owned by `Features/FieldChat`, not Insights.
`FieldChatEndpoint` selects the Dictionary adapter, and `InsightChatViewModel`
consumes its injected dependencies. Dictionary Detail retains only eligibility,
entitlement, loaded-species identity, and typed presentation ownership. Codable
DTOs remain in `Core/Network/InsightChatAPIModels.swift`. Shared chat request
construction lives in `Endpoints/MerianNetworkClient+FieldChat.swift`, and
strict response validation lives in `Decoding/FieldChatResponseDecoder.swift`.
`Core/Network/Transport/` owns replay policy, the request-scoped executor that
applies it, the sole pinned session/TLS owner, and the per-attempt authenticated
dispatcher. The main client injects those owners. The anonymous Dictionary read
and its identity/cache rules are separate.

The detail host serializes gallery, author profile, Field Chat, and paywall as
cases of one `SpeciesDictionaryPresentation` value. Its sheet and full-screen
bindings filter that same slot and therefore cannot mount together. A late chat
preflight must still match the canonical loaded UUID, remain uncancelled, and
find the slot empty; choosing another destination clears the pending chat ID and
cancels the view-owned preparation task.

Each network success is untrusted until the shared strict decoder verifies that
top-level `subject_id` and every compatibility `messages[].scan_id` equal the
captured species UUID, message/conversation identities agree, and a send
contains its exact user/assistant `client_message_id` pair. Subject generations
fence late load, send, delete, feedback, and prompt completions so navigation to
another species cannot flash or overwrite the previous thread.

Dictionary product events report entry point, content quality, entitlement
state, action category, refusal state, and lookalike availability only. They do
not contain species UUIDs or names. The public web route and anonymous
`/species-dictionary` contract are unchanged.

### Candidate Release Status

Species Dictionary Field Chat is implemented in the source candidate but is
eligible for the owner-authorized beta rollout described above. This is not
evidence that production has deployed. The candidate adds a deletion-resistant
admission aggregate, automatic exact-UUID iOS replay after ambiguous
transport/`5xx`, Dictionary-specific refusal copy, a post-authenticated
handler-core suite, atomic no-orphan conversation admission, a database-clock
pending/ready cutover, explicit one-way post-bundle activation, and one
executable Swift/Deno prompt-label policy. The handler suite also executes the
actual Edge wrapper with deterministic accepted/refused authenticators. Source
improvements do not substitute for hosted real-token, database, device, and
external release evidence.

The machine-readable `species_dictionary_chat_production_hold` is inactive in
`services/supabase/release-holds.json` under the beta decision above. The
production workflow still requires exact-SHA Candidate Validation and live
repository-control verification. Missing or malformed hold controls still fail.
The full-release evidence checklist remains open and is not a machine-enforced
backend hold. Only a completed deployment and activation establish availability;
this policy decision does not authorize paywall/App Store launch copy. The
reviewed 2026-08-24 source now:

1. registers `field_chat_daily_admissions` in the effective Ghost handler
   allowlist and executes the complete policy-coverage assertion;
2. derives the merge/admission race day from PostgreSQL, calls the public
   reservation RPC and full merge orchestrator, and gives each Field Chat family
   a real reserve-delete-fresh-reserve case;
3. short-locks all three conversation/message families, removes historical
   message-less threads, records the next database-observed UTC boundary, blocks
   all novel sends while `pending` and `ready`, and permanently reserves
   conversation insertion for the atomic RPC while allowing exact persisted
   replays; after all three corrected bundles deploy and every live route
   exposes the `atomic-admission-v1` compatibility marker plus its
   candidate-derived `X-Merian-Field-Chat-Bundle-SHA256`, a one-way service-only
   activation records candidate, migration, and all three route digests; a
   database `ready` state force-selects the full fleet after the migration
   becomes the deployment baseline;
4. creates or resolves a conversation only inside the admitted transaction, so
   quota denial creates no empty conversation, message, or provider dispatch;
   cap, cutover, and ownership denials have the same no-write behavior;
5. executes `docs/contracts/species-dictionary-prompt-label-policy.json` in
   Swift and Deno, including U+2013 EN DASH acceptance, U+0085 normalization,
   U+FEFF rejection, combining marks, non-BMP scalars, and 64-scalar boundary
   cases; and
6. requires the named hold ID fail closed, independently pins and clean-checks
   the mutation SHA, and checks current protected main, merged-PR provenance,
   required checks, branch rules without bypass, and automatic environment
   policy before mutation. Optional artifact audits preserve retained evidence;
   ordinary deployments require no review click or per-commit clearance secret.

For full-public-launch readiness, the database-backed cases must execute without
a connection skip on the immutable candidate; the authenticated HTTP wrapper
boundary passes; a ready-state rerun always selects all three chat bundles;
every live route's content digest matches the candidate; a genuine released V49
binary accepts the exact V50 candidate without safe mode/store replacement or
data loss; and both hosted gates pass on that same SHA. The live verifier must
accept merged-main PR provenance, protected branch rules without bypass, and
automatic `Release Evidence` and `Production` environments restricted to
protected branches with no reviewers or waiting gates. The canonical
production-consent, App Store privacy/age-rating, paid Gemini billing, DPA, and
legal evidence must also be approved. Artifact digests establish the retained
bytes, not the authenticity of an off-platform issuer or independent secret
administration; those remain external operational approvals.

The exact machine-readable exit criteria and rollout order are canonical in the
[Supabase deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md#species-dictionary-field-chat-hold-exit-criteria).
Evidence authors must follow the
[release-evidence operations guide](../release-evidence/README.md).

These are release-evidence requirements, not accepted product limitations.
Public web remains unchanged regardless of the backend beta exception.

## Title And Alternate Names

The header renders the scientific name, then the primary common name, then
`AlternativeCommonNamesLine` when alternate names are available. The line uses
the compact copy `Also known as: Name, Name` and wraps naturally for long lists.
It trims names, splits comma-delimited source values, deduplicates
case-insensitively, treats whitespace/underscore/dash variants as the same name,
and excludes the primary common name. For example, `Desert Rose` and
`Desert-rose` share the same display key, so the alternate line is suppressed
instead of repeating the title with punctuation changed.

Alternate names are intentionally not repeated in a lower card. The old
dictionary-only "Also known as" grid was removed so the information lives in the
same place on both Species Dictionary and Explore detail pages. The toolbar
badge uses only the primary common name.

## Backend Contract

The Detail live service adapter delegates to the Core Network client:

```swift
MerianNetworkClient.shared.getSpeciesDictionary(scientificName:)
MerianNetworkClient.shared.getSpeciesDictionary(speciesId:scientificName:)
```

That method POSTs to the `species-dictionary` Edge Function:

```json
{
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "scientific_name": "Danaus plexippus"
}
```

Field Chat is a separate authenticated request surface:

```json
{
  "action": "send",
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "message_text": "How can I distinguish this species from lookalikes?",
  "client_message_id": "11111111-1111-4111-8111-111111111111"
}
```

`/species-dictionary-chat` supports `load`, `send`, `delete`, `feedback`, and
`suggest_prompts`. It requires authenticated functional Pro access and keeps one
private conversation per `(viewer, species)`. Every send reloads the latest
bounded canonical names, taxonomy, overview, habitat, hazard, conservation,
group tags, and nonrejected lookalikes. All dictionary values are fenced as
untrusted data. Community sightings, observation charts, scans, notes, users,
locations, media, reference URLs, and attribution identities are excluded.
Missing or malformed `species_id` input returns `400 invalid_request`; a valid
UUID that is absent or does not resolve to an available biological dictionary
row returns `404 species_not_available`.

Successful responses are wrapped in a `data` envelope:

```json
{
  "schema_version": 1,
  "data": {
    "id": "uuid",
    "scientific_name": "Danaus plexippus",
    "common_name": "Monarch Butterfly",
    "content_quality": "complete",
    "alternative_common_names": [],
    "taxonomy": {
      "kingdom": "Animalia",
      "phylum": "Arthropoda",
      "class": "Insecta",
      "order": "Lepidoptera",
      "family": "Nymphalidae",
      "genus": "Danaus"
    },
    "hazard_type": "none",
    "iucn_red_list_status": "least concern",
    "wikipedia_url": "https://en.wikipedia.org/wiki/Monarch_butterfly",
    "wikipedia_overview": "The monarch butterfly is a milkweed butterfly...",
    "habitat_description": "Often found in open meadows and milkweed patches.",
    "gbif_taxon_key": 5139790,
    "group_tags": ["animal", "insect"],
    "reference_images": [
      {
        "url": "https://upload.wikimedia.org/...",
        "source": "wikipedia",
        "license": "CC BY-SA 4.0",
        "attribution": "Example Photographer",
        "width": 1200,
        "height": 800
      },
      { "url": "https://static.inaturalist.org/...", "source": "gbif" }
    ],
    "similar_species": [
      {
        "species_id": "uuid",
        "scientific_name": "Limenitis archippus",
        "common_name": "Viceroy",
        "reference_image_url": "https://...",
        "iucn_red_list_status": "least concern"
      }
    ]
  }
}
```

The default detail lookup is public by design and has `verify_jwt = false`. It
may receive normal app auth headers from `MerianNetworkClient`, but the detail
and catalog paths do not require or read identity. Those responses must remain
species-level public dictionary data only.

`schema_version = 1` is the shared public species contract used by the
dictionary page and Explore detail similar-species projection. Current iOS and
web consumers both require exact version 1 before using or caching a payload.
Missing/unsupported versions and mismatched identities are invalid responses,
not compatibility successes.

The Community live service adapter delegates to a separate authenticated
request:

```swift
MerianNetworkClient.shared.getExploreSpeciesPosts(
    speciesId: species.id,
    limit: 30,
    cursor: cursor
)
```

The client method lives in
`Core/Network/Endpoints/MerianNetworkClient+ExploreBrowsing.swift`. Its
stateless payload and typed-page mapping are separate from Dictionary identity
validation/caching and feature Community loading state. The rehomed quality-
cursor request tests and transport checks live under
`MerianTests/Core/Network/Endpoints/ExploreBrowsingEndpointTests.swift` and
`ExploreBrowsingEndpointTransportTests.swift`; use the
[Core Network browsing matrix](../../apps/ios/Merian/Core/Network/README.md#endpoint-verification)
for wire changes.

`/get-explore-species-posts` accepts `species_id`, `limit`, and optional flat
`before_image_quality_score`, `before_shared_at`, and `before_post_id` cursor
fields. It returns standard Explore cards plus `next_cursor`. Results are exact
canonical species matches, including confirmed identifications and
community-resolved taxonomy, ordered by image quality descending, then newest
`shared_at`, then post UUID; unscored posts form the final tier. The internal
quality score is present only in the service-role RPC row used to construct the
cursor and is removed from card payloads.

### Overview and Catalog Modes

The same `/species-dictionary` function also supports the Explore Dictionary
landing view through overview mode:

```json
{
  "mode": "overview",
  "user_region": "US",
  "cache_buster": "550e8400-e29b-41d4-a716-446655440000"
}
```

The response returns image-backed category summaries for `All`, `Your Region`,
and `Recently Added`, a Recently Added featured species card with overview copy,
graphic-led high-level group summaries such as Birds and Plants, plus country
summaries derived from canonical GBIF occurrence facets in
`species_country_occurrences`. `Recently Added` is capped to the newest 40
biological entries for its overview count and representative image so it does
not duplicate the `All` total. iOS uses that featured card as the visible
Recently Added entry point, renders `Your Region` as a full-width MapKit
snapshot card whenever iOS can supply an ISO country. The card links to the
exact country catalog when coverage exists and remains visible, non-interactive,
with `Coverage updating` while the scheduled backfill is still filling that
country. `All` moves into a bottom row link. Explore keeps all Dictionary
surfaces under the Identify tab's `Species` mode (internally `.index`); Species
renders the Catalog overview/search content directly. Taxonomy remains
searchable reference data in catalog and detail responses; it is not a separate
overview category or route. The region snapshot uses the backend's country
display title and falls back to a default United States map only when MapKit
geocoding cannot resolve that title. If the overview has no non-empty country
summaries with species counts, iOS hides the Region section and the "Browse all
regions" row while the personal country card still communicates the pending
refresh state. Catalog detail pages opened from overview cards or rows,
including Birds, Mammals, All, Your Region, and Recently Added, keep the same
paginated species row list but add toolbar search, matching the Scans library
search presentation, that filters within the active category. Overview and
catalog results are gated to public biological taxa: a row must have a
scientific name plus either a positive GBIF taxon key or usable biological
taxonomy with a kingdom and at least one downstream rank. Rows that only resolve
to generic encyclopedia concepts are filtered out before they can appear as
dictionary records. Migration
`20260901180000_add_public_biological_species_eligibility.sql` stores that
decision in `species_dictionary.is_public_biological`; catalog keysets, overview
ranges, and country-summary aggregation apply it in PostgreSQL before limits.
The Deno projection treats the selected database value as authoritative, so
cursor pages and overview counts use the same eligible set. `user_region` may be
an ISO country code from an already-authorized physical location or, when
location is unavailable/not granted, from `Locale.current.region?.identifier`.
The function normalizes the code and queries exact ISO-country occurrence rows;
it never substring-matches a broad range such as `North America` as the
long-term regional source. During the backfill only, a country with no
occurrence rows may fall back to the legacy `native_region` display-name
compatibility filter. iOS includes `cache_buster` so overview requests bypass
old cached response bodies while category thumbnails are randomized.

The scheduled `refresh-species-content` worker obtains GBIF country facets for
records with `occurrenceStatus=PRESENT`, coordinates, and no geospatial issue.
It atomically replaces each species' country rows and refreshes them every 180
days through `species_content_provenance`. These rows mean "recorded in this
country," not "native to this country." Identification paths omit the legacy
range column and nullish provider fields so an upsert cannot erase curated text
with `Unknown` or remove a known GBIF identity during a transient lookup
failure.

```json
{
  "schema_version": 1,
  "data": {
    "featured_species": {
      "id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      "scientific_name": "Danaus plexippus",
      "common_name": "Monarch Butterfly",
      "overview": "The monarch butterfly is a milkweed butterfly known for long-distance migration.",
      "reference_image_url": "https://..."
    },
    "categories": [
      {
        "id": "your_region",
        "title": "Your Region",
        "subtitle": "Species recorded in United States",
        "count": 8,
        "reference_image_url": "https://...",
        "region": "United States",
        "region_code": "US"
      }
    ],
    "groups": [
      {
        "id": "birds",
        "title": "Birds",
        "count": 12,
        "reference_image_url": "https://..."
      }
    ],
    "regions": [
      {
        "id": "country:US",
        "title": "United States",
        "count": 8,
        "reference_image_url": "https://...",
        "code": "US"
      }
    ]
  }
}
```

Catalog mode powers search results and category detail pages:

```json
{
  "mode": "catalog",
  "category": "region",
  "region": "US",
  "query": "Danaus",
  "limit": 40,
  "cursor": {
    "scientific_name": "Danaus plexippus",
    "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    "created_at": "2026-06-01T12:00:00Z"
  }
}
```

`category` defaults to `all` for backward compatibility. `region` is required
when `category` is `region`; new clients send the response's ISO `region_code`
or region-summary `code`. English country titles remain accepted for deployed
client compatibility. `group` is required when `category` is `group`; supported
high-level groups are `plants`, `birds`, `insects`, `fungi`, `mammals`, and
`reptiles_amphibians`. `recently_added` sorts by
`species_dictionary.created_at DESC, id DESC`; other catalog views sort by
`scientific_name ASC, id ASC`. The response keeps the shared schema version and
returns a cursor-paginated list. Partial indexes cover the alphabetical and
Recently Added keysets only for eligible rows, preventing ineligible rows from
shortening a page before application filtering:

```json
{
  "schema_version": 1,
  "data": [
    {
      "id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      "scientific_name": "Danaus plexippus",
      "common_name": "Monarch Butterfly",
      "content_quality": "complete",
      "taxonomy": {
        "kingdom": "Animalia",
        "phylum": "Arthropoda",
        "class": "Insecta",
        "order": "Lepidoptera",
        "family": "Nymphalidae",
        "genus": "Danaus"
      },
      "iucn_red_list_status": "least concern",
      "hazard_type": "none",
      "group_tags": ["animal", "insect"],
      "reference_image_url": "https://..."
    }
  ],
  "next_cursor": null
}
```

Catalog rows are intentionally compact. They include enough species-level public
data for list cards, then route into `SpeciesDictionaryPageContentView` for full
reference imagery, overview, habitat, observation charts, and similar-species
content.

#### iOS Catalog ownership and request lifecycle

`apps/ios/Merian/Features/SpeciesDictionary/Catalog/` owns the Explore
Identify/Species browse experience. Its existing root interfaces remain
`SpeciesDictionaryOverviewView(userRegion:viewModel:)`,
`SpeciesDictionaryCatalogView(...)`, and
`SpeciesDictionaryRegionsView(userRegion:)`; Explore Shell registers the typed
destinations and owns the shared navigation stack. The feature-local
[`Catalog` README](../../apps/ios/Merian/Features/SpeciesDictionary/Catalog/README.md)
is the concise source map for contributors.

`ExploreView` retains the overview model for one Explore presentation and
injects it through the navigation host. Switching between Species, Community,
and other pages therefore preserves the loaded overview. Navigation reuses a
successful result for five minutes after completion, keyed to the normalized
country. After expiry, the existing content remains visible while the view task
refreshes it; failed or cancelled requests do not renew freshness. Explicit
pull-to-refresh and retry always fetch. Changing country clears incompatible
content before loading, while request generations reject late completions.
Skeletons appear only when the current country has no retained content. Closing
Explore or restarting the app releases this in-memory state. This feature-level
retention does not change the endpoint's `no-store` response or the network
client's detail/stats memos. The model retains only one overview, not a cache of
multiple countries or paginated catalog results. Country keys are trimmed and
uppercased; blank and absent country values share the no-country selection.
Reading retained content does not extend its freshness. Expiry is checked when
the view task runs; there is no periodic timer, scheduled off-screen refresh, or
background app execution. Cancellation on departure cannot publish a late
result, and returning can start another load without waiting for the cancelled
one to end.

Catalog implementation ownership is:

- `Models/` owns the normalized browse selection and page request, category
  route, country-flag rendering policy, overview filtering/order, and
  category-to-route mapping. Codable overview/catalog records and cursor
  contracts remain in `Core/Network/SpeciesDictionaryAPIModels.swift`; shared
  detail routes and taxonomy adaptation live in `SpeciesDictionary/Shared`.
- `Services/` adapts the live `MerianNetworkClient` calls and owns the live
  cached-image, geocoder, and MapKit snapshot implementations. Views and
  components invoke only the injected boundaries, not those concrete
  implementations.
- `ViewModels/` owns `@MainActor @Observable` catalog, overview, and
  map-snapshot state. A normalized selection prevents the two root SwiftUI tasks
  from issuing duplicate first-page calls. The view records selection changes
  before its debounce; request generations then make that selection or a refresh
  supersede older initial and pagination work. A reverted selection cannot be
  overwritten by the superseded request, and retained rows cannot paginate
  beneath a failed replacement selection. Failed refreshes of the current
  selection retain the last usable catalog or overview content. Cancelled map
  work releases its loading state.
- `Views/` retains search bindings, the 300-millisecond debounce, refresh tasks,
  navigation, and presentation timing. Grouped Catalog, Overview, Regions, and
  Shared components retain rendering and leaf placeholders.

The mirrored Catalog test suites cover detail routing, presentation policy,
request normalization, initial-load de-duplication, pagination,
refresh/search/reverted-selection overlap, failed-replacement page suppression,
five-minute overview reuse, explicit refresh, stale-content retention, country
replacement, cancellation/re-entry, stale overview/map completion, map
cancellation, ownership boundaries, and the 600-line production-file ceiling.
Mirrored Detail suites own page/Community state, presentation, endpoint
adaptation, and architecture. Core Network's `Decoding`, `Endpoints`, and
`Caching` suites own wire/schema/identity validation, request/transport
compatibility, and deterministic memo tests. The former mixed aggregate is
removed; Catalog route assertions remain feature-owned in
`SpeciesDictionaryCatalogRouteTests`. The retired taxonomy visualization has no
iOS source, feature flag, route, Swift transport/DTO, overview card, or Edge
mode. The endpoint rejects `mode: "tree"` with `400`; this explicit rejection is
covered by the import-safe HTTP handler tests before service-client
construction. Decode-only handling of the legacy overview category ID `taxonomy`
maps old responses to the complete `All` catalog during rolling client/server
deployment.

Observation pattern charts use a separate public endpoint:

```swift
SpeciesObservationStatsDependencies.live
```

The six client lookup/catalog/overview/stats method variants live in
`Core/Network/Endpoints/MerianNetworkClient+SpeciesDictionary.swift`. Dictionary
POSTs retain 30-second deadlines; stats remains an authenticated GET at 20
seconds through the same private client transport. Core's stateless
`SpeciesDictionaryResponseValidator` checks typed schemas/identities before
`SpeciesDictionaryResponseCache` inserts validated detail/stats values. The
client's cache instance is private; two fixed-result request bridges own its
lookup/load/validate/insert sequence and expose neither raw cache mutation nor
caller-provided response/loader hooks. Codable DTOs, feature Services,
observable state, navigation, and backend contracts are unchanged. See the
[Core Network boundary](../../apps/ios/Merian/Core/Network/README.md#species-dictionary-endpoints-validation-and-caches).

The Services adapter invokes
`MerianNetworkClient.getSpeciesObservationStats(speciesId:scientificName:)`,
which sends an authenticated GET to the public `species-observation-stats` route
with the dictionary `species_id` and `scientific_name`. Authentication supplies
a per-user rate bucket; it does not personalize the global iNaturalist response.
An IP budget is consumed before optional token verification. Local Merian logs
are aggregated on-device and are not sent to Supabase. The client rejects
malformed UUIDs and invalid name bounds before networking, then requires
response schema version 2 or newer plus the same canonical UUID/name pair before
memoizing a result. See
[`Species Observation Charts`](./18-species-observation-charts.md) for the full
contract, cache behavior, annotation mappings, and privacy rules.

## Caching

Successful detail and catalog `/species-dictionary` responses are public and
slow-changing, so the Edge Function sends:

```http
Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800
Vary: Accept-Encoding
```

Overview responses send `Cache-Control: no-store` and `Vary: Accept-Encoding`.
`400`, `404`, and `500` responses do not opt into public caching, so missing
rows and transient errors can recover immediately after data is added or fixed.

Separately, the iOS overview model retains its last successful result for the
current Explore presentation. Its five-minute navigation freshness policy is
defined in
[iOS Catalog ownership and request lifecycle](#ios-catalog-ownership-and-request-lifecycle).
This is feature state, not HTTP caching: an actual overview fetch still sends
the existing `cache_buster`, and closing Explore discards the retained result.

The iOS client memoizes recently opened dictionary pages in its per-client
`Core/Network/Caching/SpeciesDictionaryResponseCache` owner. The detail store is
in memory only, capped at 64 alias keys, and expires entries 10 minutes after
insertion; the stats memo is an independent 5-minute, 64-key store. Reads do not
refresh age. Capacity overflow prunes expired keys before oldest-insertion
eviction, with no promised ordering for timestamp ties. Exact
`schema_version = 1` and response identity are validated first. Accepted entries
are stored under the returned canonical `species_id` and normalized returned
scientific name, so an Insight or Explore tap that carries a dictionary ID can
warm a later scientific-name route for the same species. A stale requested UUID,
malformed identity, unsupported/missing schema version, and `external:` ID never
become cache aliases. The cache is cleared in DEBUG whenever tests swap the
injected `URLSession`; that reset does not cancel or generation-fence an already
dispatched response. Validated cache hits still precede Auth/transport and
cancellation checks; feature state owners retain their own generation fences.

Community sightings are not part of either cache. Their endpoint requires the
current viewer so blocked authors and other visibility state are evaluated on
every request; a failure remains supplemental and never blocks dictionary
content. The Detail Services adapter owns that authenticated endpoint call;
Community views and state owners consume only its injected page-loader closure.

Invalidation is currently TTL-based: rows refreshed by the scheduled species
workers (`refresh-species-content`, `refresh-species-model-content`, and
`refresh-merian-reference-images`) become visible after the iOS memo TTL and the
HTTP freshness window expire. Future curation tooling that needs immediate
public web visibility should add a CDN/cache purge step alongside the dictionary
write.

## Content Quality States

Every current `/species-dictionary` response includes additive
`content_quality`:

- `complete`: reference imagery, overview, habitat/distribution, and meaningful
  taxonomy are present.
- `sparse`: at least two of those public content sections are present.
- `needs_enrichment`: fewer than two public content sections are present.

iOS treats the field as optional for backward compatibility and estimates the
same state when older payloads omit it. All three states render available
content without a content-quality notice card. Sparse and early entries omit the
“Limited details” and “Early dictionary entry” notices across every in-app
Dictionary entry point. Content quality remains available for telemetry; the
page continues to fall back gracefully when images or text are missing.

A GBIF taxon key can supply a distribution map before habitat prose is
available. The Dictionary habitat card keeps that map visible and shows
**Habitat information is not available for this species yet.** for missing,
empty, or whitespace-only descriptions. It never leaves the habitat heading
without content or requests private scan enrichment from a public dictionary
page.

Sparse and needs-enrichment records also feed durable background enrichment.
`20260707153931_species_dictionary_enrichment_queue_backfill.sql` enqueues
missing content groups for existing sparse rows and adds an insert trigger so
future dictionary rows created by scans, Community ID materialization, taxonomy
imports, or service-role repair share the same queue contract.

PostHog tracks `SpeciesDictionaryOpened`, `SpeciesDictionaryPageLoaded`,
`SpeciesDictionaryNotFound`, `SpeciesDictionaryRetry`, and
`SpeciesDictionaryReferenceImageFallback`. Events include only `entryPoint`,
`contentQuality`, and image `source` where relevant. They never attach species
names, species IDs, user locations, scans, Explore post identifiers, field
notes, comments, image URLs, or review state.

Current iOS entry points are:

- `insight_similar_species`
- `explore_detail_similar_species`

The external-link entry point is `deep_link`. Reserved future entry points are
`search`, `web`, and `unknown`.

## Data Mapping Rules

All backend mapping rules below live in the shared public species projection
module. `/species-dictionary` uses the Deno helper directly; Explore detail
similar species use matching SQL helpers (`public.public_species_common_name`,
`public.public_species_first_reference_image_url`, and
`public.public_species_similar_species`) so SQL output stays aligned with the
Edge DTO.

Common name fallback order:

1. `species_dictionary.common_names.en`
2. first non-empty value in `common_names`
3. `scientific_name`

Dictionary rows are biological species rows, not material provenance records.
The identify boundary demotes processed/manufactured objects such as wool rugs,
leather goods, wooden furniture, paper/cardboard, cotton or linen fabric,
prepared food, toys, artwork, ornaments, and species depictions before they can
create or update dictionary entries. If a malformed scan tries to label
`Ovis aries` as "Wool Kilim Rug", the existing
`species_dictionary.common_names.en` value, such as "Domestic Sheep", remains
canonical. A scan-level common name only fills an empty English name for a
normalized biological subject.

Reference image mapping:

- The Edge Function prefers ordered rows from `species_reference_images`.
- Each normalized row becomes
  `{ "url": "...", "source": "merian" | "wikipedia" | "gbif" }` with optional
  `license`, `attribution`, `width`, and `height`. Promoted Naturebook rows also
  carry optional `author_user_id` and the current `author_username` resolved
  from the promoted private source row's stable species/image URL key; external
  rows never carry contributor fields.
- Normalized rows are ordered Merian first, then Wikipedia, then GBIF.
- If no normalized rows exist, the function falls back to the legacy
  comma-separated `species_dictionary.reference_image_url`, then splits, trims,
  and dedupes URLs.
- Merian rows come from currently published Explore media whose scan-level
  `image_quality_score` meets the scheduled worker threshold. V1 uses all
  non-empty image URLs from the qualifying scan and caps promotion at 8 images
  per species.
- Wikimedia/Wikipedia hosts are marked `wikipedia`.
- When a Wikipedia URL exists and the first image has no clear host signal, the
  first image is treated as `wikipedia`; all other unresolved URLs default to
  `gbif`.

Exact external-media suppression:

- `_shared/externalImagePolicy.ts` filters live enrichment and the shared Deno
  projection; the matching SQL helpers filter normalized and legacy values for
  Explore/detail reads.
- The current rule suppresses all variants beneath
  `inaturalist-open-data.s3.amazonaws.com/photos/605615444/` (GBIF occurrence
  `5938154750`) and no other `Felis silvestris` or GBIF media.
- If the denied URL was first, the next permitted image is promoted without
  changing source order. If none remain, the existing leaf placeholder is shown.
- `ExternalReferenceImagePolicy` applies the same check to iOS DTO
  normalization, persisted cache writes, historical
  `SimilarSpeciesEntry.referenceImageUrl` decoding, catalog URL creation, the
  reference gallery, and the final loader download boundary.
- The species card and navigation route remain. Suppression changes only the
  selected image and never adds a censor overlay or a new API field.

Reference image attribution:

- The durable `refresh-species-content` worker collects verified media-level
  rights from GBIF and exact-file Wikimedia Commons Imageinfo metadata. It
  writes canonical reusable-license URLs and plain-text creator credits through
  the existing reference-image replacement RPC. Interactive identification and
  page loading perform no additional rights lookup. Provider lookup failures
  retry the durable job; absent or unsupported rights do not bypass web
  filtering.
- Existing URL-only species may need an explicitly authorized queue backfill; a
  deployment alone does not populate their credits. See the bounded procedure in
  `services/supabase/functions/refresh-species-content/README.md`.

- `license` and `attribution` come from normalized `species_reference_images`
  rows.
- Rows with the stable technical `source = "merian"` retain
  `license = "Used with permission via Naturebook"` and the source author's
  public Explore label as canonical rights metadata.
- The username capsule truncates to one line and opens
  `ExploreAuthorProfileSheet`. iOS renders no attribution/license footer below
  the species gallery. The fullscreen image viewer shows fuller credit in its
  bottom overlay: `@username · Naturebook` without display-name or permission
  fallback for Naturebook, or attribution/license/source for external images.
- Legacy fallback images may not have attribution metadata. iOS can still render
  those images with source labeling, but the public web frontend runs
  `publicWebReferenceImageAttributionIssues(...)` and omits every image missing
  either required rights field from page content and metadata.

Lookalikes:

- Source table: `species_lookalikes`.
- Hydration uses the explicit PostgREST FK hint
  `species_dictionary!lookalike_id` because the join table has two foreign keys
  to `species_dictionary`.
- Returned fields include `species_id`, `scientific_name`, `common_names`,
  `reference_image_url`, `iucn_red_list_status`, and optional relation metadata
  (`reason`, `visual_traits`, `confidence`, `source`, `review_status`,
  `is_bidirectional`, `sort_order`); thumbnail URLs prefer
  `species_reference_images` and fall back to the legacy dictionary cache.
- Cards show only the common/scientific names over the image. Relation rationale
  and visual-trait explanation copy are intentionally hidden in the UI even
  though the payload remains additive for future curation views.
- Identity filtering excludes the current species by canonical UUID and then by
  normalized scientific name. It does not treat a shared common name as a
  duplicate: distinct `Pyracantha` species may all be labeled “Firethorn.” When
  that repeated label would be ambiguous, Field Chat uses the scientific name in
  its comparison suggestion.
- The page renders the section as same-stack navigation in V1.

Provenance:

- The iOS page does not display provenance or freshness metadata in V1.
- Backend writers record source/freshness rows in `species_content_provenance`
  for dictionary fields and durable lookalikes.
- `refresh-species-content` claims `gbif_wikipedia_reference` jobs from
  `species_enrichment_jobs` first, then falls back to
  `public.get_species_content_refresh_queue(...)` for older provenance-driven
  refreshes. It refreshes GBIF/Wikipedia-backed fields: alternate common names,
  taxonomy, Wikipedia URL/overview, GBIF taxon key, and reference images.
- `refresh-species-model-content` claims `habitat`, `lookalikes`, and
  `group_tags` jobs from the same queue and reuses the species-level biology
  primitives behind `enrich-scan` without pretending a user rescanned the
  organism. It verifies up to three lookalike identities against exact accepted
  GBIF taxa, retains provider and partial failures for retry, remembers valid
  empty outcomes, and gives legacy empty/exhausted lookalike jobs with no
  nonrejected relation one versioned recovery attempt. Candidate materialization
  is directional and cannot recursively grow another model lookalike job.
- Common-name overrides, IUCN status, and hazard type remain curation-owned and
  are not overwritten by either scheduled worker.
- Reference image refreshes update both the legacy comma-separated cache and
  normalized `species_reference_images` rows through
  `public.replace_species_reference_images(...)`, preserving existing
  license/attribution metadata for matching URLs and preserving Merian rows.
- `refresh-merian-reference-images` runs hourly as a separate service-role cron
  worker. It promotes published Explore media with `image_quality_score >= 80`
  and either `ai_confidence_score >= 0.95` or a resolved `confirmed_species_id`,
  stores private source/confidence provenance in
  `species_reference_image_merian_sources`, and removes public Merian rows when
  the source Explore post/media stops being visible.

Manual acceptance for Merian reference images:

1. Publish an Explore post backed by a scan with `image_quality_score >= 80` and
   either `ai_confidence_score >= 0.95` or a confirmed species.
2. Run or wait for `refresh-merian-reference-images`.
3. Open the species dictionary page and verify Merian images appear first with
   author attribution.
4. Unshare the Explore post and run or wait for the worker again.
5. Reopen the species dictionary page and verify the Merian images are removed
   while external Wikipedia/GBIF imagery remains.

## Privacy Rules

The public `/species-dictionary` response must never expose:

- scan IDs
- user IDs
- Explore post IDs
- exact or approximate user locations
- field notes
- comments
- local scan media
- per-scan AI reasoning
- user review state
- preferred common-name overrides
- scan-level pet-identification labels

The public web frontend consumes this endpoint without an authenticated user and
maps only the documented versioned fields.

The separate authenticated sightings endpoint may return standard public Explore
card identifiers and media, but only through
`public.explore_projected_post_cards(viewer_id)`. Unshared, tombstoned, blocked,
shadowbanned, identification-pending, and media-less posts remain excluded, and
the SQL RPC is executable only by `service_role`.

## Testing

Backend:

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/_shared/http.ts services/supabase/functions/_shared/externalImagePolicy.ts services/supabase/functions/_shared/publicSpeciesProjection.ts services/supabase/functions/_shared/speciesContentProvenance.ts services/supabase/functions/refresh-species-content/index.ts services/supabase/functions/refresh-species-content/db.ts services/supabase/functions/refresh-species-model-content/index.ts services/supabase/functions/refresh-species-model-content/db.ts services/supabase/functions/species-dictionary/index.ts services/supabase/functions/species-dictionary/db.ts services/supabase/functions/species-dictionary/db.test.ts services/supabase/functions/species-dictionary/handler_test.ts services/supabase/functions/_tests/speciesDictionaryPublicEligibilityMigrationContract.test.ts services/supabase/functions/species-dictionary-chat/index.ts
deno test --allow-env --allow-net --allow-read=. --config services/supabase/functions/deno.json services/supabase/functions/_shared/http_test.ts services/supabase/functions/_shared/externalImagePolicy_test.ts services/supabase/functions/_shared/external_test.ts services/supabase/functions/_shared/publicSpeciesProjection_test.ts services/supabase/functions/_shared/speciesContentProvenance_test.ts services/supabase/functions/_shared/fieldChatDailyUsage_test.ts services/supabase/functions/refresh-species-content/db.test.ts services/supabase/functions/refresh-species-model-content/db.test.ts services/supabase/functions/species-dictionary/db.test.ts services/supabase/functions/species-dictionary/handler_test.ts services/supabase/functions/_tests/speciesDictionaryPublicEligibilityMigrationContract.test.ts services/supabase/functions/species-dictionary-chat/handler_test.ts services/supabase/functions/species-dictionary-chat/eligibility_test.ts services/supabase/functions/species-dictionary-chat/prompt_test.ts services/supabase/functions/species-dictionary-chat/promptSuggestions_test.ts services/supabase/functions/species-dictionary-chat/refusal_test.ts services/supabase/functions/_tests/speciesDictionaryChatRouteContract.test.ts services/supabase/functions/_tests/speciesDictionaryChatMigrationContract.test.ts services/supabase/functions/_tests/fieldChatDurableDailyUsageMigrationContract.test.ts
supabase --workdir services db push --local
supabase --workdir services test db --local services/supabase/tests/species_dictionary_public_eligibility.sql
deno check --frozen --config services/supabase/functions/refresh-species-model-content/deno.json services/supabase/functions/refresh-species-model-content/index.ts
deno test --frozen --config services/supabase/functions/deno.json --allow-env --allow-read=. services/supabase/functions/refresh-species-model-content/db.test.ts services/supabase/functions/refresh-species-model-content/lookalikeCandidates.test.ts services/supabase/functions/_tests/speciesLookalikeRecoveryMigrationContract.test.ts
bash services/supabase/scripts/test_database_catalogs.sh
```

The route-contract file inspects source structure and wrapper registration.
`handler_test.ts` invokes the post-authenticated handler core with a synthetic
user and the actual Edge wrapper with deterministic accepted/refused
authenticators. It is not a hosted real-JWT authentication test. A
database-backed test is passing evidence only when it connects to a disposable
fully migrated catalog and executes rather than reporting a connection-refused
skip. Candidate Validation discovers the no-empty-conversation, three real
admission-branch, and full merge-orchestrator cases; before release, require
their non-skipped execution plus the hosted authenticated wrapper boundary on
the same SHA. The database catalog runner discovers
`species_lookalike_recovery.sql`; its transactional assertions cover claim
ordering, retry/backoff, one-time repair, trigger suppression, curation
preservation, identity conflicts, and settled-empty behavior.

iOS:

```sh
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'id=<booted simulator id>' CODE_SIGNING_ALLOWED=NO test \
  -only-testing:merianTests/SpeciesObservationStatsReducerTests \
  -only-testing:merianTests/SpeciesObservationStatsViewModelTests \
  -only-testing:merianTests/GBIFHeatmapViewModelTests \
  -only-testing:merianTests/SimilarSpeciesImageFetcherTests \
  -only-testing:merianTests/SpeciesReferenceArchitectureTests \
  -only-testing:merianTests/LocalImageLoaderTests \
  -only-testing:merianTests/SpeciesDataTests \
  -only-testing:merianTests/SimilarSpeciesTests \
  -only-testing:merianTests/SpeciesObservationModelsTests \
  -only-testing:merianTests/SpeciesDataEdgeResponseTests \
  -only-testing:merianTests/SpeciesModelsArchitectureTests \
  -only-testing:merianTests/FieldChatPresentationTests \
  -only-testing:merianTests/SpeciesDictionaryCatalogRouteTests \
  -only-testing:merianTests/SpeciesCatalogPresentationTests \
  -only-testing:merianTests/SpeciesDictionaryCatalogViewModelTests \
  -only-testing:merianTests/SpeciesDictionaryOverviewViewModelTests \
  -only-testing:merianTests/SpeciesDictionaryRegionMapViewModelTests \
  -only-testing:merianTests/SpeciesCatalogArchitectureTests \
  -only-testing:merianTests/SpeciesDictionaryPageViewModelTests \
  -only-testing:merianTests/SpeciesCommunitySightingsViewModelTests \
  -only-testing:merianTests/SpeciesDictionaryDetailPresentationTests \
  -only-testing:merianTests/SpeciesDictionaryDetailServiceTests \
  -only-testing:merianTests/SpeciesDictionaryDetailArchitectureTests \
  -only-testing:merianTests/SpeciesDictionarySharedPresentationTests \
  -only-testing:merianTests/SpeciesDictionarySharedArchitectureTests \
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
  -only-testing:merianTests/MerianNetworkArchitectureTests \
  -only-testing:merianTests/MerianNetworkClientTests \
  -only-testing:merianTests/ExploreShellNavigationPolicyTests
```

The iOS matrix includes the Core endpoint/cache rehome and new deterministic
boundary suites. Dictionary, chart, routing, and state owners remain separate.
For shared JSON bridge/configuration-guard changes, additionally run every
[Core Network endpoint matrix](../../apps/ios/Merian/Core/Network/README.md#endpoint-verification)
and the complete `merianTests` target. Native cache/validator/architecture
execution and cached-dependency typechecking do not replace a fresh iOS build,
Simulator tests, or the manual checks below.

For name-only resolution changes, also run:

```sh
deno check --frozen --config services/supabase/functions/resolve-species-dictionary/deno.json \
  services/supabase/functions/resolve-species-dictionary/index.ts
deno test --frozen --allow-env --allow-read=. --config services/supabase/functions/deno.json \
  services/supabase/functions/resolve-species-dictionary/ \
  services/supabase/functions/refresh-species-model-content/lookalikeCandidates.test.ts \
  services/supabase/functions/_tests/speciesDictionaryResolutionMigrationContract.test.ts
```

The complete disposable-database gate must execute
`services/supabase/tests/species_dictionary_resolution.sql` and both cases in
`functions/_tests/speciesDictionaryResolutionDb.test.ts`. The latter requires
`SUPABASE_DB_TEST_URL` for a disposable loopback database; a skipped test is not
concurrency evidence. Coverage includes denied callers, independent admission,
identity conflicts, ambiguous keys, legacy missing-key persistence, curated
content preservation, suppressed recursive lookalikes, and concurrent new or
legacy records reusing one UUID across accepted-name variants. Never print the
database URL or use a hosted database for these tests.

On iOS, `SpeciesDictionaryResponseValidatorTests` checks the versioned receipt;
`SpeciesDictionaryDetailServiceTests` checks receipt-to-detail ordering and
exact UUID binding; `SpeciesDictionaryPageViewModelTests` checks readable
reference state, failure/retry, cancellation, and retry replay during a fresh
load; `SpeciesDictionaryDetailPresentationTests` checks merge precedence. Run
these through `make ios-local-build`, then the complete `merianTests` target.

Local working-tree validation on 2026-09-21 passed 1,327 XCTest tests and 2,883
Swift Testing tests, 2,024 Edge tests, all 383 catalog assertions after clean
migration replay, and both explicitly enabled resolution concurrency cases. The
ordinary Edge run reported six conditional tests ignored; the two resolution
concurrency cases were executed separately against the disposable database.
Recursive Deno checks, tooling, migration/DTO contracts, project validation,
formatting, and whitespace checks also passed. Hosted deployment, exact-SHA CI
release evidence, and the on-device navigation checks below remain separate
outstanding verification.

For overview-retention changes, start with
`SpeciesDictionaryOverviewViewModelTests` and the Explore Shell navigation
suites through `make ios-local-build`; then run the applicable matrix above and
the complete unit target. The overview suite uses an injected clock and
suspended loaders to cover the 299/300-second freshness boundary, normalized and
absent country reuse, explicit refresh, retained content during refresh and
failure, country replacement, and cancelled-load re-entry. These model tests do
not exercise SwiftUI view identity; the navigation checks below remain required.

Local verification for the 2026-09-18 overview-retention change passed Swift
syntax parsing, XcodeGen/project validation, the iOS privacy, transport,
versioning and migration source gates, CI-tooling tests, Markdown formatting,
and whitespace checks. Both focused Simulator test attempts stopped before
compilation because another Xcode build was active. The new overview tests,
fresh iOS compilation, and manual navigation acceptance remain unverified by
those attempts; no release or runtime-validation claim follows from the source
checks.

For Field Chat changes, also run the
[Core Network Field Chat matrix](../../apps/ios/Merian/Core/Network/README.md#field-chat-verification)
and the complete `merianTests` target on fresh candidate products.
`SpeciesDictionaryChatEndpointTests` owns the rehomed strict-species request,
subject-binding, and ambiguous-replay regression. The shared request/transport,
decoder, and single-read snapshot suites cover all three chat sources; feature
suites retain source adaptation and generation-fenced state. The Dictionary
read/cache suite and host presentation tests above do not replace those chat
suites or the manual and release acceptance below.

Web:

```sh
cd apps/web
npm test
npm run typecheck
npm run build
```

Manual acceptance:

- Switch Identify repeatedly between Species and Community. Confirm Species
  preserves the existing overview layout, Recently Added and organism-group
  order, local region treatment, loading skeletons, empty/error copy, and
  pushed-navigation chrome.
- After loading Species, switch to Community or another root tab and return
  within five minutes: content should appear without overview skeletons or a new
  overview request. Return after five minutes and confirm existing content
  remains visible during refresh, including a failed offline refresh. Pull to
  refresh within the freshness window and confirm a new request. Change the
  device country and confirm the previous country's overview is replaced.
- Leave Species during its first load, return before the cancelled request
  finishes, and confirm it can load normally without a late result replacing
  current content. Close Explore entirely and reopen Species to confirm a new
  load; also confirm remaining on the page for five minutes does not start a
  timed refresh.
- Search a catalog, clear and re-enter the same query while results are loading,
  pull to refresh while the next page is loading, and retry a failed replacement
  query. Confirm only the current normalized selection publishes, no stale page
  appends, and the last usable rows remain visible when their own refresh fails.
- Open the full regions list and navigate away while the personal map snapshot
  is loading. On return, confirm the map can load again and does not remain
  stuck in a loading state.
- Recheck the overview, catalog rows, regions list, skeletons, search, and error
  actions with VoiceOver and the largest accessibility Dynamic Type sizes.
- Open a biological Insight scan with similar species.
- Tap a similar-species card.
- Confirm the large species page sheet opens and loads the tapped scientific
  name.
- Open an Explore post detail page with public similar species.
- Confirm the similar-species section appears after habitat/distribution, then
  tap a card and verify the same species page sheet opens.
- Confirm gallery images render, and missing images fall back gracefully.
- On Great Egret, confirm Free opens the paywall and Pro opens Field Chat; send,
  close/reopen, delete, feedback, similar-species navigation, and an
  already-loaded offline transcript must remain species-scoped.
- At the 20-send boundary, delete the Great Egret thread and confirm neither the
  returned remaining count nor a new send regains allowance that UTC day.
- While already at the 20-send boundary with no Great Egret thread, attempt a
  send and confirm the denial creates no empty conversation, message, or
  provider dispatch.
- Lose one successful send response and force one retryable `5xx`; confirm the
  automatic client retry reuses the exact lowercase UUID and restores one saved
  pair without requiring a second tap.
- Exercise missing/malformed `species_id` as `400 invalid_request` and a valid
  absent/nonbiological UUID as `404 species_not_available`.
- Trigger every local refusal class and server-suggestion fallback; confirm no
  scan/observation wording remains and an empty or overlong/untrusted display
  name produces a safe, bounded generic label. Include ASCII hyphen, U+2013 EN
  DASH, combining-mark, non-BMP, U+FEFF, and U+0085 labels and require Swift and
  Deno to make the same accept/fallback decision.
- Confirm the public Great Egret web page has no Field Chat change.
- Reopen the pictured Brown Tabby scan and confirm the European wildcat card
  remains visible and navigable but media `605615444` does not appear in
  Insight, Explore, the Dictionary catalog, or the Dictionary detail gallery.
  Confirm the next live image is used when available and the leaf placeholder
  appears when every candidate is blocked or fails.
- Follow the reported path: own Explore post → own Insight → Similar Species → a
  name-only dictionary reference. Use an explicitly authorized local/staging
  target and a biological species absent from that test catalog. Confirm the
  reference remains readable during preparation, then Share and Field Chat
  appear after verified resolution. Opening the page must not create or load a
  conversation. Repeat using an older saved Insight.
- Simulate verification failure or offline state, retry, navigate away while
  waiting, and return after Retry was used. Confirm no stuck loading state,
  stale species replacement, duplicate record, or automatic chat presentation.
  Exercise a verified synonym and an existing legacy record with no taxon ID;
  confirm the correct existing UUID is reused when it can be verified.
- Confirm an unrecoverable UUID lookup shows not-found/retry; a name-only public
  reference follows the resolution flow above.
- Share a loaded dictionary page and confirm the payload uses the canonical UUID
  HTTPS URL and common-name subject.
- Open canonical and legacy HTTPS/custom-scheme species links and confirm
  Explore selects Identify/Species, pushes the species, and survives an
  immediate session-timeout event.
- In a browser, confirm canonical metadata, licensed image attribution, textual
  similar-species navigation, native-app CTA, and clean omission of absent
  optional sections.

## Conversational discovery search

### Entry and interaction

The overview places “Search or ask Naturebook” below the sheet toolbar and
before the featured card, including loading and error states. The capsule entry
has a 50-point minimum height and matching card margins, with native interactive
Liquid Glass on iOS 26+ and an ultra-thin material fallback on earlier systems.
A single leading `sparkle.magnifyingglass` symbol combines search and AI; there
is no trailing icon. Core UI's `rainbowCapsuleAccent` adds the same soft rainbow
glow and occasional 1.8-second border sweep as the Field Chat sheet button,
sized to the entry. Reduce Motion keeps the glow static without the shimmer; the
decoration does not intercept taps or add VoiceOver elements. The existing
18-point stack spacing to the featured card remains. It pushes Search in
Explore's shared navigation stack with the keyboard closed. Root controls give
way to Back, Search, and an icon-only New search button with its VoiceOver label
retained; the bottom menu is hidden. Composer text is vertically centered beside
the send control, and example prompts use right-pointing arrows.

Before submission, a bundled 3D nature illustration sits above the centered
**What would you like to discover?** heading. The selection includes the
bird/magnifier, monarch butterfly, fern, frog, mushroom, and blue bird. Each
welcome-screen appearance and New search chooses a different illustration from
the current one; it stays fixed during typing and request loading. There is no
blue symbol or explanatory subheading. Three prompts are sampled from a curated
pool of twelve supported descriptive searches. They stay fixed while reading,
typing, opening details, or receiving results; New search selects three prompts
outside the current set and keeps the keyboard closed. A fresh Explore session
samples again. The keyboard opens when the user taps the composer or answers a
clarification.

Below the prompts, **Explore a species** shows up to six recently added, real
dictionary records in a two-column thumbnail grid, changing to one column at
accessibility text sizes. Tiles show common/scientific names and open the
existing species detail route directly. The retained Catalog view model loads
one six-item `recently_added` page through the existing `/species-dictionary`
endpoint, independently of AI search and its allowance. Successful rows survive
New search and detail navigation during the session. Loading and retry are local
to the grid; missing images use the existing leaf placeholder and an empty page
omits the grid without blocking questions.

The single bottom input changes from **Ask Naturebook…** to **Refine your
search…** after successful results. Submissions are explicit; the current source
does not issue model calls or show name suggestions while typing.

Species opens first. Results show the latest interpretation, editable scope
chips, Species/Sightings selector, scrollable cards, a group-refinement
shortcut, and the persistent input. Follow-ups replace the active search instead
of accumulating chat bubbles. For example, “Orange and black insects” followed
by “Only butterflies” updates the criteria used by both tabs. Results resolve to
existing dictionary or Explore detail routes.

Explicit group and Sightings-only media chips show the active scope. Descriptive
results are “Possible matches”; excerpts are verbatim dictionary text. Sightings
show public attribution and location labels, with publication dates labeled
“Shared”. Nearby, date filtering, and private observations are outside v1.

An empty Sightings result says **No matching public sightings** and offers the
Species tab; it does not imply there are no matching dictionary entries. An
empty Species result says **No matching species**. Loading retains the last
successful cards. Failures retain the draft and offer explicit Retry. A
clarification keeps the unresolved context and refocuses the input; an
unsupported request explains its limits without replacing successful results.

### Session, retrieval, and scope

Explore owns the in-memory search session. Detail navigation preserves both tabs
and their scroll anchors. New search, an account change, or closing Explore
clears the session. Failed follow-ups retain the previous results and draft;
generation fences reject obsolete completions and disable pagination after a
failed replacement. Clarifications preserve the unresolved query for the next
answer, including while browsing the other result tab. A retry retains the
failed request's tab and pagination cursor. Local block events also suppress
unseen posts from that author in late search responses; Edge enrichment keeps
the database projection's filtered media array intact.

The separate `species-discovery-search` operation interprets bounded questions
into English text-search criteria and retrieves real public biological entries.
An initial question without context and within the 240 UTF-16-unit name-query
bound bypasses AI when scientific/common/alternative name substrings match.
Exact scientific and canonical English common names rank first; alternative-name
matches do not receive the exact-match bonus. Follow-up questions use
interpretation; context-only filter/tab/page requests do not. Descriptions use a
generated search document and partial GIN index. Sightings join all matching
species through the viewer-aware Explore projection before pagination and
exclude coordinate fields. No record identities or post content come from the
model. Search does not reuse single-species Field Chat conversations.

The new source requires the forward search migration and function deployment
before hosted use; this implementation does not constitute deployment. See the
[endpoint contract](../../services/supabase/functions/species-discovery-search/README.md)
for bounds, privacy, pagination, consent, and dedicated 20/free or 120/Pro daily
AI allowances. The
[iOS owner](../../apps/ios/Merian/Features/SpeciesDictionary/Search/README.md)
contains source ownership; the
[verification matrix](../development-guides/08-testing-strategy.md#species-discovery-search-verification)
owns automated selectors and remaining manual acceptance. The existing Field
Chat beta exception does not authorize discovery-search deployment.
