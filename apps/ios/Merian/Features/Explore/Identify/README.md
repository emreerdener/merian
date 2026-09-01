# Explore Identify

The `Identify` directory owns community-driven species identification inside
Explore. Identify is one of the three root bottom-navigation items and contains
the `Requests` / `Index` root mode picker. Product behavior remains defined by
the canonical
[Explore bottom-menu contract](../../../../../../docs/features-and-hardware/24-explore-bottom-menu.md).

## Purpose

This area lets explorers ask for help with an observation, review recent
identification activity, open complete request/activity feeds, suggest a taxon,
and follow community consensus to resolution. The existing Species Dictionary
overview is rendered as Identify's `Index` mode, although its implementation
continues to live under
[`Features/SpeciesDictionary/Catalog`](../../SpeciesDictionary/Catalog/README.md).
Identify owns the mode switch; Catalog owns Index loading, presentation, and
typed category routes.

## Root surfaces

`ExploreIdentifyMode` has exactly two cases:

- `.requests` renders `ExploreCommunityIdentificationView`.
- `.index` renders `SpeciesDictionaryOverviewView`.

The Requests root is a dashboard with one shared
`CommunityIdentificationRequestFilter`. `All` and `Yours` precede Plants, Birds,
Insects, Fungi, Mammals, and Herps. `Yours` maps to API scope `mine` and means
requests owned by the viewer, not suggestions made by the viewer. Organism
filters apply to Requests and Activity together.

The dashboard layout is:

1. **Identify requests** / **See all requests** heading row.
2. Dismissible **Ask the community** information banner.
3. Up to 12 open request cards.
4. A deliberately larger section gap.
5. **Recent activity** / **See all activity** heading row.
6. Up to 10 grouped Activity rows.
7. **Give feedback**.

Request and Activity previews start concurrently through `async let`. Each
section keeps independent loading, empty, stale-content error, initial error,
and Retry presentation. Pull-to-refresh and filter changes reload both. Activity
temporary-service failures use Recent activity-specific copy; they must not show
the generic “Explore is temporarily unavailable” message.

## Complete feeds

The dashboard pushes two typed routes while preserving the selected filter:

- `ExploreCommunityRequestsFeedRoute` opens `ExploreCommunityRequestsFeedView`,
  titled **Identify requests**.
- `ExploreCommunityActivityFeedRoute` opens `ExploreCommunityActivityFeedView`,
  titled **Identify activity**.

Both pages hide the root tab bar and Requests/Index picker. Back navigation
returns to the dashboard with its prior filter. Complete feeds request 30 rows
per page and de-duplicate IDs while appending:

- Requests paginate on `(requested_at, request_id)` and retain location-aware
  ordering when coordinates are available.
- Activity paginates on `(activity_at, activity_id)`.

Changing filters or pulling to refresh starts a new load generation and resets
the cursor. Near-end row/card appearance requests the next page.

## Activity rows

`CommunityIdentificationActivityRow` is a compact, tappable summary containing:

- request thumbnail or placeholder;
- Activity-type symbol;
- visible actor/count summary for suggestion bursts;
- latest consensus or resolved taxon when available;
- relative timestamp; and
- disclosure chevron.

Every row pushes the existing `ExploreCommunityRequestRoute`; Activity has no
separate detail page. Supported item types are `suggestion_burst`,
`consensus_changed`, and `resolved`.

## Navigation policy

`ExploreView` owns the shared `NavigationPath`:

- Species links select Explore's Identify tab and `.index` mode before pushing
  `SpeciesDictionaryRoute`.
- Community request links select Explore's Identify tab and `.requests` mode
  before pushing `ExploreCommunityRequestRoute`.
- The complete Requests and Activity routes are stack-only destinations and are
  never root tabs.

Keep these policies centralized in `ExploreInitialTabPolicy`,
`ExploreInitialIdentifyModePolicy`, and
`openCommunityIdentificationRequest(_:)`. A new caller must not infer mode from
the route after presentation.

## Network and privacy contract

Requests call `/get-community-identification-feed`; Activity calls
`/get-community-identification-activity`. Both receive the same `scope` and
`group` filters. The dashboard limits are exactly 12 Requests and 10 Activity
groups; backend defaults are not used for previews.

**Report post** on a Community detail calls `/report-explore-post` through the
Identify Services adapter with the detail's exact `postId`, the fixed
`Inappropriate content` reason, and `Reported from Community request` context.
The client does not send reporter identity: the Edge Function derives it from
the verified JWT, rejects self-reports and unavailable posts, and writes only
the public-content moderation queue. It never sets identification-review state
on the backing scan. `/flag-issue` has no current iOS call site; its Edge module
retains a narrow bridge for older Community clients.

The Activity Edge Function requires a user JWT through the repository's custom
`withEdgeHandler` authentication boundary, even though platform
`verify_jwt = false` is configured for that route. It invokes the database RPC
with a service-role client. Projection tables and the RPC deny direct `PUBLIC`,
`anon`, and `authenticated` access.

Activity reads apply request withdrawal/unshare/moderation, owner shadowban,
viewer blocking, scan tombstone, aggregate media quarantine, and active-media
rules. Actor IDs/counts are stored in the internal projection; actor names are
not stored. Public usernames are resolved and visibility-filtered at read time.
Activity does not affect the Explore bell feed or unread state.

Suggestions on the same request generation chain into one burst when every
adjacent suggestion is at most 60 minutes apart. The exact 60-minute boundary is
inclusive. Submission-caused consensus changes enrich that burst; unrelated
consensus changes are standalone rows, and resolution is always a separate
immutable milestone. Migration backfill includes only the request's current
generation.

## Directory ownership

- `Models/` owns typed routes, root modes, filters, preview/page-size policy,
  independent dashboard load state, and feature-local request values passed to
  dependency closures. Codable response DTOs and cursor wire models remain in
  `Core/Network/ExploreAPIModels.swift`.
- `Services/` adapts `MerianNetworkClient`, current account/device identity,
  haptics, error formatting, and typed app events into small live `Dependencies`
  values. It is the only Identify layer that calls the network client.
- `ViewModels/` owns concurrent dashboard loading, complete-feed pagination,
  de-duplication, request-detail mutations, taxonomy search, and feedback
  validation/submission. Every view model is `@MainActor @Observable` and
  accepts initializer-injected closure dependencies.
- `Views/` owns screen composition and navigation-compatible wrappers. Filter
  bindings, sheet selection/dismissal, menu presentation, and animation timing
  stay with their screen.
- `Components/` owns feature UI grouped by Catalog, Activity, Detail, Taxonomy,
  and Shared presentation. Views and components do not call the network client
  directly.
- `Core/Network/ExploreAPIModels.swift` owns request/activity response DTOs,
  item types, and cursor models.
- `Core/Network/MerianNetworkClient.swift` constructs authenticated request and
  Activity payloads.
- `Core/Utilities/ExploreErrorFormatter.swift` owns generic and Recent
  activity-specific error copy.
- `Explore/Shell/Models/ExploreShellNavigationModels.swift` owns initial
  tab/mode and deep-link policy; `Explore/Shell/Views/` owns root selection and
  destination registration.

Production Swift files in this directory must remain below 600 lines. Existing
screen and route initializer signatures are compatibility boundaries. This
organization does not change API actions, payloads, persistence, feature flags,
navigation, visible copy, accessibility, loading states, or interaction timing.

Backend ownership:

- `services/supabase/functions/report-explore-post/`
- `services/supabase/functions/flag-issue/` (old-client compatibility only)
- `services/supabase/functions/get-community-identification-activity/`
- `services/supabase/migrations/20260831120000_submit_owned_flag_issue_atomically.sql`
- `services/supabase/migrations/20260731050009_add_community_identification_activity.sql`
- `services/supabase/functions/_tests/flagIssueMigrationContract.test.ts`
- `services/supabase/functions/_tests/communityIdentificationActivityDb.test.ts`
- `services/supabase/functions/_tests/communityIdentificationActivityMigrationContract.test.ts`

## Dictionary scope

Identify/Index is the sole Species Dictionary browsing surface. Taxonomy remains
searchable reference data within catalog and detail responses; there is no
separate taxonomy visualization, control, or route.

## Verification

Focused tests cover dashboard limits and independent section failures,
filter/route propagation, request and Activity pagination, cursor forwarding,
de-duplication, detail mutations and typed refresh events, pinned-version
taxonomy search, feedback validation/submission, mode/deep-link policy, Activity
decoding and payloads, grouping boundaries, actor aggregation,
consensus/resolution behavior, reopened generations, visibility, backfill, and
stable pagination. See:

- `apps/ios/MerianTests/Features/Explore/Identify/`
- `apps/ios/MerianTests/Features/Explore/Shell/ExploreShellNavigationPolicyTests.swift`
- `apps/ios/MerianTests/Features/SpeciesDictionary/Catalog/`
- `apps/ios/MerianTests/Features/SpeciesDictionary/SpeciesDictionaryTests.swift`
- `apps/ios/MerianTests/Core/Network/MerianNetworkClientTests.swift`
- `apps/ios/MerianTests/Core/Utilities/MerianConfigTests.swift`
- `services/supabase/functions/get-community-identification-activity/db_test.ts`
- `services/supabase/functions/flag-issue/db_test.ts`
- `services/supabase/functions/_tests/flagIssueMigrationContract.test.ts`
- `services/supabase/functions/_tests/jsonEndpointSecurityCoverage.test.ts`
- `services/supabase/functions/_tests/communityIdentificationActivityDb.test.ts`
- `services/supabase/functions/_tests/communityIdentificationActivityMigrationContract.test.ts`
- `services/supabase/tests/flag_issue_submission_security.sql`

Run the focused iOS suites with:

```sh
xcodebuild -scheme Merian -project Merian.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:merianTests/CommunityIdentificationPresentationTests \
  -only-testing:merianTests/IdentifyDashboardViewModelTests \
  -only-testing:merianTests/IdentifyFeedViewModelTests \
  -only-testing:merianTests/CommunityIDDetailViewModelTests \
  -only-testing:merianTests/CommunityTaxonomySearchViewModelTests \
  -only-testing:merianTests/CommunityFeedbackViewModelTests \
  -only-testing:merianTests/CommunityIdentificationModelsTests \
  -only-testing:merianTests/ExploreShellNavigationPolicyTests \
  -only-testing:merianTests/SpeciesDictionaryCatalogContractTests \
  -only-testing:merianTests/SpeciesCatalogPresentationTests \
  -only-testing:merianTests/SpeciesDictionaryCatalogViewModelTests \
  -only-testing:merianTests/SpeciesDictionaryOverviewViewModelTests \
  -only-testing:merianTests/SpeciesDictionaryRegionMapViewModelTests \
  -only-testing:merianTests/SpeciesCatalogArchitectureTests \
  -only-testing:merianTests/SpeciesDictionaryTests \
  -only-testing:merianTests/MerianNetworkClientTests \
  -only-testing:merianTests/MerianConfigTests test
```

The focused matrix does not replace the complete `merianTests` target, generic
iOS Simulator build, generated-project validation, SwiftLint, Markdown format,
or manual parity checks in the canonical contract.
