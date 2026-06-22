# Explore Root Pager

The Explore sheet uses root-only bottom navigation as its primary section
navigation. The menu uses native tab-bar chrome for Observations, Identify, and
Dictionary.

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
- **Map** lives inside Observations and shows open-location public discoveries.
  It includes a horizontal species-type filter row below the Explore heading;
  the filter button opens a sheet with the region's available categories, and
  active categories filter the map payload before clusters or individual
  waypoints render.
- **Dictionary** shows `SpeciesDictionaryCatalogView`, a searchable and
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
Dictionary. Observations owns a Feed/Map header toggle, and Dictionary keeps
Tree inside its Catalog/Tree header toggle rather than exposing either Map or
Tree as a separate root bottom-menu item.

The bottom menu is intentionally root-scoped. It is hidden on pushed post
details, Identify request details, catalog detail pages, hashtag lists, author
profile sheets, comments, notification sheets, and the Insight sheet.
Dictionary rows and Tree species preview actions still push
`SpeciesDictionaryRoute` into the sheet's existing `NavigationPath`.

Community request details use `ExploreCommunityIdentificationDetailView`, which
loads `/get-community-identification-detail`, frames the starting name as
Merian's AI identification in a rounded reasoning card backed by scan AI
confidence and reasoning, renders the community identification timeline, and
pins a **Suggest ID** action at the bottom. The
taxonomy search sheet calls `/search-community-taxa` with the request's pinned
taxonomy version. Exact or descendant species IDs submit immediately, genus IDs
can ask whether genus is as specific as it can get, ancestor IDs ask whether the
user is only less specific or explicitly disagreeing, and sibling/unrelated IDs
ask for confirmation plus optional reasoning.

The detail sheet intentionally leaves the image toolbar title empty. The image
is the visual context, while the first body card names Merian's AI
identification and shows the scan-derived reasoning when available. Community
IDs then live below in the timeline so the AI starting point and human
identification evidence stay visually distinct.

## Data Boundaries

Feed, Map, author, hashtag, and detail Explore RPCs read
`explore_observation_projection` and exclude posts while their projection state
is `community_needs_id`. Once the community consensus resolves at species, or
at genus when users mark that as the best practical ID, the projection becomes
`community_resolved`, but normal Explore surfaces continue to exclude it until
the owner explicitly publishes the resolved request to Explore. After that
publish action, the resolved community taxon drives the public
common/scientific-name display. V1 does not mutate `scans.species_id` or
`confirmed_species_id`.

Map species-type filters are backed by `/get-explore-map-points`, which derives
category counts from the privacy-safe posts in the current region and applies
selected species categories before clustering. The UI can therefore keep the
pill row dynamic without exposing private scan coordinates or separate raw
taxonomy queries.

Dictionary and Tree use species-level public data only. The catalog mode returns
compact species rows with taxonomy, content quality, tags, status fields, and a
single reference image URL. The tree mode requires auth only to choose the
species represented by the current user's non-deleted biological scans; it then
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
