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
  built from catalog entries. Users can pan, zoom, tap nodes to highlight nearby
  connections, and tap species nodes to open the existing Species Dictionary
  detail page.

## Navigation

`ExploreView` owns the root section state through `ExploreTab`. Bottom-menu
taps set the active section, while horizontal swipes page in the order Feed,
Map, Dictionary, then Tree. The old top Feed/Map segmented control is not shown.

The bottom menu is intentionally root-scoped. It is hidden on pushed post
details, catalog detail pages, hashtag lists, author profile sheets, comments,
notification sheets, and the Insight sheet. Dictionary rows and Tree species
nodes still push `SpeciesDictionaryRoute` into the sheet's existing
`NavigationPath`.

## Data Boundaries

Dictionary and Tree use species-level public data only. The catalog mode returns
compact species rows with taxonomy, content quality, tags, status fields, and a
single reference image URL. It does not include user scans, field notes,
comments, locations, or Explore post content.

The Tree MVP derives its graph client-side from catalog taxonomy fields. Missing
taxonomy ranks are grouped under `Unclassified`; no new taxonomy schema,
migration, or precomputed graph table is required.
