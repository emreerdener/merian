# Explore Root Pager

The Explore sheet uses a root-only bottom menu as its primary section
navigation. The menu uses the shared floating capsule chrome from `MainTabBar`
and controls a horizontally paged root shell.

## Sections

- **Feed** shows the public Explore feed.
- **Map** shows open-location public discoveries.
- **Dictionary** shows `SpeciesDictionaryCatalogView`, a searchable and
  paginated catalog powered by the public `species_dictionary` table through
  the existing `/species-dictionary` Edge Function.
- **Tree** shows `TaxonomyTreeCanvasView`, an interactive Tree of Life canvas
  powered by the `species-dictionary` Edge Function's `mode: "tree"` graph
  response for the signed-in user's scanned taxonomy. Users can pan, zoom,
  search, focus branches, inspect lineage highlights, and open a species
  preview before navigating to the existing Species Dictionary detail page.

## Navigation

`ExploreView` owns the root section state through `ExploreTab`. Bottom-menu
taps set the active section, while horizontal swipes page in the order Feed,
Map, Dictionary, then Tree. The old top Feed/Map segmented control is not shown.

The bottom menu is intentionally root-scoped. It is hidden on pushed post
details, catalog detail pages, hashtag lists, author profile sheets, comments,
notification sheets, and the Insight sheet. Dictionary rows and Tree species
preview actions still push `SpeciesDictionaryRoute` into the sheet's existing
`NavigationPath`.

## Data Boundaries

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
