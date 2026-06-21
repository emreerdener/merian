# Explore Root Pager

The Explore sheet uses a root-only bottom menu as its primary section
navigation. The menu uses native tab-bar chrome and controls a horizontally
paged root shell.

## Sections

- **Feed** shows the public Explore feed.
- **Identify** shows the Ask the Community queue for unresolved identification
  requests. It uses `ExploreCommunityIdentificationView`, a two-column image
  grid sorted by nearby public coordinates when available and then recency.
  Cards show the request image, current anchor or consensus label, ID count, and
  privacy-safe location label.
- **Map** shows open-location public discoveries. It includes a horizontal
  species-type filter row below the Explore heading; the filter button opens a
  sheet with the region's available categories, and active categories filter the
  map payload before clusters or individual waypoints render.
- **Dictionary** shows `SpeciesDictionaryCatalogView`, a searchable and
  paginated catalog powered by the public `species_dictionary` table through
  the existing `/species-dictionary` Edge Function.
- **Tree** is still in development and is only included in simulator builds.
  It shows `TaxonomyTreeCanvasView`, an interactive Tree of Life canvas powered
  by the `species-dictionary` Edge Function's `mode: "tree"` graph response for
  the signed-in user's scanned taxonomy. Users can pan, zoom, search, focus
  branches, inspect lineage highlights, and open a species preview before
  navigating to the existing Species Dictionary detail page.

## Navigation

`ExploreView` owns the root section state through `ExploreTab`. Bottom-menu
taps set the active section, while horizontal swipes page in the production
order Feed, Identify, Map, then Dictionary. Simulator builds keep Tree inside
the Dictionary header toggle rather than exposing it as a separate root
bottom-menu item. The old top Feed/Map segmented control is not shown.

The bottom menu is intentionally root-scoped. It is hidden on pushed post
details, Identify request details, catalog detail pages, hashtag lists, author
profile sheets, comments, notification sheets, and the Insight sheet.
Dictionary rows and Tree species preview actions still push
`SpeciesDictionaryRoute` into the sheet's existing `NavigationPath`.

Community request details use `ExploreCommunityIdentificationDetailView`, which
loads `/get-community-identification-detail`, renders a consensus panel and
identification timeline, and pins a **Suggest ID** action at the bottom. The
taxonomy search sheet calls `/search-community-taxa` with the request's pinned
taxonomy version. Exact or descendant species IDs submit immediately, genus IDs
can ask whether genus is as specific as it can get, ancestor IDs ask whether the
user is only less specific or explicitly disagreeing, and sibling/unrelated IDs
ask for confirmation plus optional reasoning.

## Data Boundaries

Feed, Map, author, hashtag, and detail Explore RPCs read
`explore_observation_projection` and exclude posts while their projection state
is `community_needs_id`. Once the community consensus resolves at species, or
at genus when users mark that as the best practical ID, the projection becomes
`community_resolved` and the resolved community taxon drives the public
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
