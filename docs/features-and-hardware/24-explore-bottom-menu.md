# Explore Root Pager

The Explore sheet uses a root-only bottom menu as its primary section
navigation. The menu uses native tab-bar chrome and controls a horizontally
paged root shell.

## Sections

- **Feed** shows the public Explore feed.
- **Community** shows the Ask the Community queue for unresolved identification
  requests. It uses `ExploreCommunityIdentificationView`, a two-column image
  grid sorted by nearby public coordinates when available and then recency.
  Cards show the request image, current anchor or consensus label, ID count, and
  privacy-safe location label.
- **Map** shows open-location public discoveries.
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
order Feed, Community, Map, then Dictionary. Simulator builds keep Tree inside
the Dictionary header toggle rather than exposing it as a separate root
bottom-menu item. The old top Feed/Map segmented control is not shown.

The bottom menu is intentionally root-scoped. It is hidden on pushed post
details, Community request details, catalog detail pages, hashtag lists, author
profile sheets, comments, notification sheets, and the Insight sheet.
Dictionary rows and Tree species preview actions still push
`SpeciesDictionaryRoute` into the sheet's existing `NavigationPath`.

Community request details use `ExploreCommunityIdentificationDetailView`, which
loads `/get-community-identification-detail`, renders a consensus panel and
identification timeline, and pins a **Suggest ID** action at the bottom. The
taxonomy search sheet calls `/search-community-taxa`; exact or descendant IDs
submit immediately, ancestor IDs ask whether the user is only less specific or
explicitly disagreeing, and sibling/unrelated IDs ask for confirmation plus
optional reasoning.

## Data Boundaries

Feed, Map, author, hashtag, and detail Explore RPCs exclude posts while their
community request status is `needs_id`. Once the community consensus resolves
at species, or at genus when users mark that as the best practical ID, the post
graduates back into normal Explore projections with the resolved community
taxon driving the public common/scientific-name projection. V1 does not mutate
`scans.species_id` or `confirmed_species_id`.

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
