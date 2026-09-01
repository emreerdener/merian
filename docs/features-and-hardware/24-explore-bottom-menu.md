# Explore Root Navigation

The Explore sheet uses root-only bottom navigation as its primary section
navigation. The menu uses native tab-bar chrome for exactly three items, in
production order: Observations, Field trips, and Identify. Index is not a
bottom-navigation item; it is the second root mode inside Identify.

## Presentation entry points

Capture remains the application root. After onboarding, the default-off **Open
Explore on launch** setting may present this sheet with the generic Observations
feed selected once when a new process starts. The setting does not reopen
Explore on foreground returns and never selects a particular post.

Explicit intent supersedes this generic presentation. Photos/Files image
handoffs dismiss Explore and continue to capture staging/crop. Deep links and
tapped notifications replace the generic feed with their requested Explore post,
community request, scan Insight, or Scans library route. Any Explore appearance,
including automatic launch presentation, marks the one-time **New** chip as
seen.

## Sections

- **Observations** shows either the public Explore feed or the Explore map. A
  root-only header toggle keeps Feed first and Map second.
- **Field trips** shows curated regional checklist quests backed by the
  `/field-trips` Edge Function. The tab defaults to `Outings` for standard
  outings for every user. The `Events` segment is also public and lists live and
  upcoming Seasonal Challenges. Challenges require explicit Join, count only
  in-window scans after `joined_at`, award profile badges, and publish challenge
  entries through Field trips-specific pages. Active outing progress can appear
  on public profiles as checklist status only; published Field trips open
  `FieldTripPublicationDetailView`, challenge entries open
  `FieldTripChallengeEntryDetailView`, and all of these remain separate from
  Explore posts, feed filters, maps, APNs, widgets, prizes, and leaderboards.
  Challenge hashtags are optional composer suggestions only. Field trip
  comment/reply/followed-publication activity may appear in the Explore activity
  sheet and unread badge, but it is in-app only. Completed standard goals
  replace their artwork with the device-local completing scan thumbnail when
  available; tapping the thumbnail pushes the existing Insight view in this same
  Explore navigation stack.
- **Identify** owns a root-only `Requests` / `Index` segmented control.
  `Requests` renders `ExploreCommunityIdentificationView`, while `Index` renders
  the existing `SpeciesDictionaryOverviewView` directly.
- **Requests** is a dashboard rather than the complete request feed. A shared
  filter row keeps `All` and `Yours` first, followed by Plants, Birds, Insects,
  Fungi, Mammals, and Herps. `Yours` means requests owned by the viewer.
  Organism filters constrain both dashboard sections. The first section is
  headed **Identify requests** with **See all requests** opposite it, followed
  immediately by the dismissible **Ask the community** banner and up to 12
  unresolved request cards. Cards show the request image and submitted-ID count
  without exposing the AI-derived name. The second section is headed **Recent
  activity**, has additional visual separation from the request grid, and
  renders up to 10 grouped Activity rows.
- **Recent activity** rows show the request thumbnail, visible actor/count
  summary, latest consensus or resolved taxon when available, relative time, and
  a chevron. Tapping a row opens the existing request detail. Requests and
  Activity load concurrently and retain independent loading, empty, and error
  states; an Activity outage therefore does not remove the request preview.
  Pull-to-refresh and filter changes reload both sections.
- **Complete Identify feeds** are pushed stack pages reached through **See all
  requests** and **See all activity**. They inherit the current filter, hide the
  root tab bar and segmented control, and use **Identify requests** and
  **Identify activity** as their navigation titles. The Requests page retains
  the existing two-column paginated grid; Activity uses a paginated compact-row
  feed. Native Back returns to the filtered dashboard.
- **Observations Feed** keeps `Recent`, `Following`, `Trending`, and `Nearby` as
  dedicated server-backed modes. Its leading Filters pill opens a sheet for feed
  mode, species groups, image/audio/video media, shared-date range, and a
  Nearby-only 10/25/50/100-mile distance. Species and media are multi-select;
  selections are OR-ed within a section and AND-ed across sections before cursor
  pagination. Reset clears advanced filters without changing feed mode.
- **Map** lives inside Observations and shows open-location public discoveries.
  Its horizontal quick-filter row remains species-focused. The filter button
  opens a sheet with separate Species and Media type sections, where image,
  video, and audio selections can be combined with species groups. The generic
  Filters count and Reset/All actions cover both groups, while media types stay
  out of the horizontal pills. Active filters apply before clusters or
  individual waypoints render.
- **Index** opens `SpeciesDictionaryOverviewView`, a browse overview with
  Recently Added, local region, organism-group, and region entry points. The
  featured Recently Added card opens that species' detail page, while a separate
  Recently Added row opens the full newest-species list. Pushed category and
  group pages use `SpeciesDictionaryCatalogView`, a searchable and paginated
  catalog powered by the public `species_dictionary` table through the existing
  `/species-dictionary` Edge Function. Catalog Services adapt that endpoint;
  selection- and generation-fenced Catalog ViewModels own overview, search,
  refresh, pagination, and region-map loading. The View records a changed
  selection before its debounce so superseded refresh/page work cannot publish,
  while Views and Components remain free of direct endpoint or platform-service
  lookup.
- **Taxonomy** remains reference data shown and searched within Index catalog
  rows and species detail. There is no separate taxonomy visualization, feature
  flag, API mode, or Explore route.

## Navigation

`ExploreView` owns the root section state through `ExploreTab` and owns pushed
route state for post detail, hashtag collections, author profiles, and
dictionary destinations. `ExploreTab.allCases` contains only `.feed`,
`.fieldTrips`, and `.community`; `ExploreIdentifyMode.allCases` contains only
`.requests` and `.index`. Observations owns a Feed/Map header toggle. Identify
owns Requests/Index and resets no pushed route merely because the user changes
that root mode.

Species deep links and in-app species routes select Identify/Index before
pushing `SpeciesDictionaryRoute`. Community request deep links and notifications
select Identify/Requests before pushing `ExploreCommunityRequestRoute`. This
policy keeps canonical and legacy links compatible after removal of the
Dictionary bottom tab.

Author profiles opened from feed, detail, comments, notifications, Field trips,
or profile libraries push into this same Explore navigation stack rather than
presenting a second sheet over the active surface. Profile-library scans carry
an author-profile depth so the app allows `profile -> scan` but blocks another
author-profile hop from that nested detail. The visual Scan goal indicator
initializes this stack with a typed `CaptureGoalDestination`. Explore converts
the Field trip case through `ExploreFieldTripNavigationPolicy` into the
FieldTrips-owned `FieldTripTemplateRoute`, carrying an optional focused
checklist-item ID. The destination opens Tips and focuses the matching guide, or
falls back to the Goals tile when no guide exists. Ordinary route callers omit
the optional focus ID and keep their prior behavior.

Completed-goal navigation uses `ScanInsightRoute`. `ExploreShellNavigationView`
resolves the private completion scan ID to a local record before appending the
value route. The mounted `LocalScanInsightLoader` performs the one-time engine
hydration and then constructs `InsightSheetView` in `.embeddedInScansLibrary`
mode. A missing local record surfaces an unavailable message instead of
presenting another sheet or stale content.

## iOS File Ownership

Explore is organized by product area first so a contributor can open the folder
for the surface they are changing:

- `apps/ios/Merian/Features/Explore/Shell/` owns the root Explore sheet,
  toolbar, root mode picker, shared navigation path, initial-route and
  Capture-goal conversion policy, stack-based author-profile presentation, the
  profile-to-scan nesting cap, root sheet lifecycles, and cross-area
  presentation. Its live dependency adapter supplies only the app-event stream,
  root Scans-library request, and narrow haptic actions; Shell views contain no
  endpoint or singleton lookup. Product areas own their typed destination
  values, including `FieldTrips/Models/FieldTripRoutes.swift`.
- `apps/ios/Merian/Features/Explore/Feed/` owns the Observations feed, post
  detail, comments, hashtags, publishing/editing presentation, and Feed routes.
  `Models/` owns route and presentation values; `Services/` owns live endpoint,
  realtime, identity/entitlement, and loader adapters; `ViewModels/` owns
  catalog, post-store, comment, hashtag, and post-detail state; and `Views/`
  plus grouped
  `Components/{Cards,Catalog,Comments,Composer,Detail,DetailCards,Media,Shared}`
  render with no direct networking. Cross-area media rendering and playback live
  under `Explore/Shared/Media`; the domain-neutral Pro badge and reusable
  spectrogram loader live in Core. Shell prepares card identity/entitlement
  values and coordinates navigation, while Feed owns its tab, hashtag
  collection, detail host, and typed routes. See the feature-local
  [`README`](../../apps/ios/Merian/Features/Explore/Feed/README.md) for the
  exact consumer matrix and focused test ownership.
- `apps/ios/Merian/Features/Explore/Map/` owns the Observations map surface, map
  filters, waypoints, clusters, preview cards, and map view model. `Models/`
  owns focus/request values, presentation/camera/filtering/region policy, and
  the bounded in-memory cache; `Services/` alone supplies the live map-points
  network closure; `ViewModels/` owns spatial loading, request generations,
  filtering, and selection; `Views/` retains camera and gesture timing; and
  grouped `Components/` renders filters, markers, previews, and status chrome
  without direct networking. See the feature-local
  [`README`](../../apps/ios/Merian/Features/Explore/Map/README.md) for the
  compatibility, public/private map boundary, and focused test ownership.
- `apps/ios/Merian/Features/Explore/Identify/` owns Community ID requests,
  activity, request detail, taxonomy search, disagreement handling, and
  community feedback entry points. `Models/` owns presentation policy and typed
  routes, `Services/` is the only Identify layer that supplies live network
  closures, `@MainActor @Observable` models under `ViewModels/` own asynchronous
  state, and `Views/` plus feature-grouped `Components/` contain no direct
  networking. See the feature-local
  [`README`](../../apps/ios/Merian/Features/Explore/Identify/README.md) for the
  compatibility and test boundaries.
- `apps/ios/Merian/Features/Explore/FieldTrips/` owns public Field trip Outings
  and Events, Seasonal Challenges cards/detail, guided template detail, progress
  cards, publication and challenge entry detail pages, profile modules,
  challenge badges, pin controls, and Field Trip comment presentation.
  `Services/FieldTripCaptureGoalProvider.swift` adapts the feature DTOs into
  generic Capture goals. `Core/Models/CaptureGoalContext.swift` owns the
  app-injected, account-cached active-target store consumed by Capture.
- `apps/ios/Merian/Features/Explore/Notifications/` owns decoded notification,
  row-presentation, and reply-route models; live catalog/read/comment/reply
  adapters; generation-fenced catalog and reply-thread state; rows; and thin
  sheet hosts. Views and components perform no endpoint or singleton lookup.
  Failed refreshes retain the last usable catalog cursor, and later
  authoritative reply pages replace bounded notification fallback content. See
  the feature-local
  [`README`](../../apps/ios/Merian/Features/Explore/Notifications/README.md) for
  lifecycle, routing, and focused test ownership.
- `apps/ios/Merian/Features/Explore/AuthorProfile/` owns public Explore author
  profile content, route metadata, and published-scan library presentation.
- `apps/ios/Merian/Features/Explore/Shared/` is reserved for Explore helpers
  that are used by more than one product area.
- `apps/ios/Merian/Features/SpeciesDictionary/Catalog/` owns the Explore Index
  catalog, overview, and regions surfaces. Its Models own the category route and
  deterministic presentation policy; Services alone resolve endpoint, cached
  image, geocoding, and map-snapshot work; and ViewModels fence asynchronous
  browse state by normalized selection and request generation. Explore Shell
  continues to own Index selection and the shared `NavigationPath`. See the
  feature-local
  [`Catalog` README](../../apps/ios/Merian/Features/SpeciesDictionary/Catalog/README.md)
  for its source and test boundaries.

The bottom menu and root segmented control are intentionally root-scoped. They
are hidden on the complete Identify Requests and Activity feeds, pushed post
details, Identify request details, catalog detail pages, hashtag lists, author
profile routes, comments, notification sheets, and the Insight sheet. Index rows
push `SpeciesDictionaryRoute` into the sheet's existing `NavigationPath`.

Community request details use `ExploreCommunityIdentificationDetailView`, which
loads `/get-community-identification-detail`, frames the starting name as
Naturebook's AI identification in a compact card backed by the scan's stored
model tier, optional confidence, and collapsed AI reasoning row, renders the
community identification timeline with its ID count, and pins a **Suggest ID**
action at the bottom. The taxonomy search sheet calls `/search-community-taxa`
with the request's pinned taxonomy version. Exact or descendant species IDs
submit immediately, genus IDs can ask whether genus is as specific as it can
get, ancestor IDs ask whether the user is only less specific or explicitly
disagreeing, and sibling/unrelated IDs ask for confirmation plus optional
reasoning. Submitting, withdrawing, or restoring an ID from the detail screen
notifies the Identify request grid to refresh the visible page so each compact
card badge stays aligned with the current active ID count shown in detail. When
an Insight already has an active community request, the Insight share flow opens
the same request sheet in edit mode, prefills the current note and location
sharing from request detail, and saves through
`/update-community-identification-request`. Opening **Edit request** from the
community request detail menu uses that same
`Features/Insights/Sharing/Views/Community/CommunityIdentificationRequestSheet`
component, so Insight-originated edits and request-detail edits share the same
toolbar Save action and form layout. The sheet's observable Sharing view model
owns only draft/loading state and exact-request generation fencing; its injected
Sharing Service closure performs the existing-detail endpoint call, while the
Insight or Identify host retains the typed create/update completion action.
Pending requests render horizontal **Edit** and **View** actions first, followed
by a separate **Publish to Explore** action with a visible disclaimer that the
community is still reviewing the ID. New scans continue to use the sheet in
create mode and call `/request-community-identification`.

The detail sheet intentionally leaves the image toolbar title empty. The image
is the visual context, while the first body card names Naturebook's AI
identification and lets explorers expand the scan-derived reasoning when needed.
Community IDs then live below in the timeline so the AI starting point and human
identification evidence stay visually distinct.

## Data Boundaries

Feed, Map, author, hashtag, and detail Explore RPCs read
`explore_observation_projection` and exclude posts while their projection state
is `community_needs_id`. Once the community consensus resolves at species, or at
genus when users mark that as the best practical ID, the projection becomes
`community_resolved`, but normal Explore surfaces continue to exclude it until
the owner explicitly publishes the resolved request to Explore. After that
publish action, the resolved community taxon drives the public
common/scientific-name display, and species-level resolutions set
`scans.confirmed_species_id` after materializing any new GBIF-backed species
into Merian's Dictionary. The original AI `scans.species_id` is preserved.

Map species and media-type filters are backed by `/get-explore-map-points`. The
endpoint derives faceted counts from privacy-safe posts, applies selected
species and media groups before clustering, and treats attached media kinds as
an OR match. The horizontal pill row remains species-focused; image, video, and
audio choices live in the full Map filters sheet.

Index uses species-level public data only. The Dictionary overview returns
featured, group, and region summaries, while pushed catalog pages return compact
species rows with taxonomy, content quality, tags, status fields, and a single
reference image URL. Promoted Naturebook community photos rank before external
reference images when available.

Identify Activity is a separate service-only projection, not the Explore bell
feed. It is updated from identification inserts and consensus events, applies
the same request visibility/media rules at read time, and does not read or
mutate unread state. See
[`05-api-contracts.md`](../backend-and-data/05-api-contracts.md#get-community-identification-activity)
and
[`04-database-schema.md`](../backend-and-data/04-database-schema.md#internal-community-identify-activity-projection)
for its grouping, cursor, and authorization contracts.

The retired taxonomy-visualization boundary is documented in
[`16-species-dictionary.md`](16-species-dictionary.md#overview-and-catalog-modes)
and the
[`Species Dictionary long-term TODO`](../rfcs/species-dictionary-long-term-todo.md#scope-12--retired-taxonomy-visualization).
