# Explore Root Pager

The Explore sheet uses root-only bottom navigation as its primary section
navigation. The menu uses native tab-bar chrome for Observations, Identify,
Field Trips, and Dictionary.

## Sections

- **Observations** shows either the public Explore feed or the Explore map. A
  root-only header toggle keeps Feed first and Map second.
- **Identify** shows the Ask the Community queue for unresolved identification
  requests. It uses `ExploreCommunityIdentificationView`, a two-column image
  grid sorted by nearby public coordinates when available and then recency. The
  request filter row keeps `All` and `Yours` first, followed by server-backed
  organism filters for Plants, Birds, Insects, Fungi, Mammals, and Herps. Cards
  show the request image and submitted-ID count without exposing the AI-derived
  name in the grid.
- **Field Trips** shows curated regional checklist quests backed by the
  `/field-trips` Edge Function. Active Field Trip progress can appear on public
  profiles as checklist status only; published Field Trips open
  `FieldTripPublicationDetailView` and remain separate from Explore posts.
- **Map** lives inside Observations and shows open-location public discoveries.
  It includes a horizontal species-type filter row below the Explore heading;
  the filter button opens a sheet with the region's available categories, and
  active categories filter the map payload before clusters or individual
  waypoints render.
- **Dictionary** opens `SpeciesDictionaryOverviewView`, a browse overview with
  Recently Added, local region, organism-group, and region entry points.
  The featured Recently Added card opens that species' detail page, while a
  separate Recently Added row opens the full newest-species list. Pushed
  category and group pages use `SpeciesDictionaryCatalogView`, a searchable and
  paginated catalog powered by the public `species_dictionary` table through
  the existing `/species-dictionary` Edge Function.
- **Tree** is still in development and is only included in simulator builds.
  It shows `TaxonomyTreeCanvasView`, an interactive Tree of Life canvas powered
  by the `species-dictionary` Edge Function's `mode: "tree"` graph response for
  the signed-in user's scanned taxonomy. The default tree orientation runs
  top-down from higher taxonomy ranks into species leaves. Users can pan, zoom,
  search, focus branches, inspect lineage highlights, and open a species
  preview before navigating to the existing Species Dictionary detail page.

## Navigation

`ExploreView` owns the root section state through `ExploreTab`. Bottom-menu
taps set the active section in the production order Observations, Identify, then
Field Trips, then Dictionary. Observations owns a Feed/Map header toggle, and Dictionary keeps
Tree inside its Catalog/Tree header toggle rather than exposing either Map or
Tree as a separate root bottom-menu item.

## iOS File Ownership

Explore is organized by product area first so a contributor can open the folder
for the surface they are changing:

- `apps/ios/Merian/Features/Explore/Shell/` owns the root Explore sheet,
  toolbar, root mode picker, navigation routes, and cross-area presentation.
- `apps/ios/Merian/Features/Explore/Feed/` owns the Observations feed, post
  cards, post detail, comments, hashtags, feed formatting, and feed
  view-model extensions.
- `apps/ios/Merian/Features/Explore/Map/` owns the Observations map surface,
  map filters, waypoints, clusters, preview cards, and map view model.
- `apps/ios/Merian/Features/Explore/Identify/` owns Community ID requests,
  activity, request detail, taxonomy search, disagreement handling, and
  community feedback entry points.
- `apps/ios/Merian/Features/Explore/FieldTrips/` owns the Field Trips catalog,
  progress cards, publication detail pages, profile modules, and Field Trip
  comment presentation.
- `apps/ios/Merian/Features/Explore/Notifications/` owns notification models,
  rows, sheet UI, and notification fetch/read state.
- `apps/ios/Merian/Features/Explore/AuthorProfile/` owns public Explore author
  profile presentation.
- `apps/ios/Merian/Features/Explore/Shared/` is reserved for Explore helpers
  that are used by more than one product area.
- `apps/ios/Merian/Features/SpeciesDictionary/Catalog/` owns the Explore Index
  catalog and overview surfaces, while
  `apps/ios/Merian/Features/SpeciesDictionary/Tree/` owns the Tree canvas.

The bottom menu is intentionally root-scoped. It is hidden on pushed post
details, Identify request details, catalog detail pages, hashtag lists, author
profile sheets, comments, notification sheets, and the Insight sheet.
Dictionary rows and Tree species preview actions still push
`SpeciesDictionaryRoute` into the sheet's existing `NavigationPath`.

Community request details use `ExploreCommunityIdentificationDetailView`, which
loads `/get-community-identification-detail`, frames the starting name as
Merian's AI identification in a compact card backed by the scan's stored model
tier, optional confidence, and collapsed AI reasoning row, renders the
community identification timeline with its ID count, and pins a **Suggest ID**
action at the bottom. The
taxonomy search sheet calls `/search-community-taxa` with the request's pinned
taxonomy version. Exact or descendant species IDs submit immediately, genus IDs
can ask whether genus is as specific as it can get, ancestor IDs ask whether the
user is only less specific or explicitly disagreeing, and sibling/unrelated IDs
ask for confirmation plus optional reasoning.
Submitting, withdrawing, or restoring an ID from the detail screen notifies the
Identify request grid to refresh the visible page so each compact card badge
stays aligned with the current active ID count shown in detail.
When an Insight already has an active community request, the Insight share flow
opens the same request sheet in edit mode, prefills the current note and
location sharing from request detail, and saves through
`/update-community-identification-request`. Opening **Edit request** from the
community request detail menu uses that same `CommunityIdentificationRequestSheet`
component, so Insight-originated edits and request-detail edits share the same
toolbar Save action and form layout. Pending requests render horizontal **Edit**
and **View** actions first, followed by a separate **Publish to Explore** action
with a visible disclaimer that the community is still reviewing the ID. New
scans continue to use the sheet in create mode and call
`/request-community-identification`.

The detail sheet intentionally leaves the image toolbar title empty. The image
is the visual context, while the first body card names Merian's AI
identification and lets explorers expand the scan-derived reasoning when
needed. Community IDs then live below in the timeline so the AI starting point
and human identification evidence stay visually distinct.

## Data Boundaries

Feed, Map, author, hashtag, and detail Explore RPCs read
`explore_observation_projection` and exclude posts while their projection state
is `community_needs_id`. Once the community consensus resolves at species, or
at genus when users mark that as the best practical ID, the projection becomes
`community_resolved`, but normal Explore surfaces continue to exclude it until
the owner explicitly publishes the resolved request to Explore. After that
publish action, the resolved community taxon drives the public
common/scientific-name display, and species-level resolutions set
`scans.confirmed_species_id` after materializing any new GBIF-backed species
into Merian's Dictionary. The original AI `scans.species_id` is preserved.

Map species-type filters are backed by `/get-explore-map-points`, which derives
category counts from the privacy-safe posts in the current region and applies
selected species categories before clustering. The UI can therefore keep the
pill row dynamic without exposing private scan coordinates or separate raw
taxonomy queries.

Dictionary and Tree use species-level public data only. The Dictionary overview
returns featured, group, and region summaries, while pushed catalog pages return
compact species rows with taxonomy, content quality, tags, status fields, and a
single reference image URL. Promoted Merian community photos rank before
external reference images when available. The tree mode requires auth only to
choose the species represented by the current user's non-deleted biological scans; it then
returns public taxonomy nodes, edges, species counts, representative species,
reference thumbnails, and status fields for those species. It does not include
scan IDs, field notes, media, comments, locations, users, or Explore post
content.

If no scanned biological species can be matched to dictionary rows, the tree
returns an empty graph and `TaxonomyTreeCanvasView` shows the scanned-taxonomy
empty state.

Tree node IDs are stable lineage keys such as
`taxonomy:genus:animalia/arthropoda/insecta/lepidoptera/nymphalidae/danaus`,
while species leaves use `species:<species_dictionary.id>`. Missing taxonomy
ranks are grouped under `Unclassified`; no new taxonomy schema, migration, or
precomputed graph table is required for this version.
