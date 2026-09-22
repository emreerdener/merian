# Species Dictionary Search

Results-first conversational discovery across canonical species and public
community sightings. Explore Shell owns one `SpeciesSearchViewModel` per Explore
presentation; returning from a detail preserves results, draft, and scroll
position. Closing Explore releases that state, and account changes clear it. No
SwiftData model or retained conversation is created.

`Views` owns composition, keyboard focus and structured request tasks.
`Components` owns the overview entry and public-sighting presentation using
Explore's existing image/media primitives. `Models` owns the typed route.
`ViewModels` owns the search generation, replacement/page state, clarification
context, filters and retry. Only `Services` resolves live networking. Codable
payloads and strict decoding remain in Core Network.

`Components/SpeciesSearchIntroduction.swift` owns the keyboard-closed welcome: a
rotating selection of existing 3D nature artwork, centered heading, three
rotating prompts, the existing Insight `DidYouKnowCard`, and a two-column grid
of recent real species (one column at accessibility text sizes). Cards align at
the top and share the tallest natural height in each row; equal-width images
retain a uniform 1.25:1 aspect ratio. `SpeciesSearchViewModel` keeps the prompt
set stable until New search and owns a six-item
`SpeciesDictionaryCatalogViewModel` with Services-injected dependencies. That
existing public catalog read and its cancellation/retry rules are separate from
AI search. Successful starter rows remain in the current Explore session; tiles
route straight to dictionary detail. Grid loading, empty, and failure states
never prevent question entry. New search also leaves the keyboard closed. The
illustration changes without an immediate repeat whenever the welcome screen
reappears or New search is tapped, and stays fixed during typing and loading.

The fun facts card sits below the prompts and above the species grid. It reuses
Insight Content's persisted shuffled fact deck, 8.5-second rotation, and
tap/swipe navigation. `SpeciesSearchFactDependencies` resolves the existing fact
manager and selection feedback in Services; the card retains its own view-scoped
task.

The overview entry remains available during loading and failure. Its label and
search icon use the primary foreground color in both light and dark appearance.
Search pushes onto Explore's shared stack. Results share one vertical scroll
view: Species first, then Community sightings, with no result tabs. Species use
a horizontal row of 200-point image cards with material name overlays. A single
sighting has the same width; two or more use a two-column square-thumbnail grid
with 2-point gaps. Accessibility text sizes use full-width cards and a single
sighting column. Each section has its own Load more action and cursor. Both
share species criteria; media filters are explicitly Sightings-only. Dictionary
excerpts stay source-attributed in species card accessibility values. Public
sighting attribution, location labels, and dates labeled “Shared” remain in
accessibility summaries and the existing Explore detail route. Species cards
open dictionary detail. Sightings register only changed results in Explore's
shared store, honoring session removal revisions and newly blocked author IDs so
pagination and late responses cannot restore removed or blocked cards, including
posts not previously present in the store.

A search generation change cancels the view's task. One task retrieves species
first, then sightings with the accepted context and no second question or AI
interpretation. Generation and cancellation checks reject late completions from
either stage. Successful species retrieval commits the new criteria, clears old
sightings, and resets the shared scroll anchor; a failed sightings read retains
those new species and retries only sightings. A failed interpretation/species
replacement retains the previous results and draft. Loading/error locks prevent
pagination from replacing an unfinished or failed request. Clearing search
invalidates all work. Retries preserve the failed section and cursor.
Clarifications remain pending while users browse or paginate existing results,
and consecutive filter edits compose against the pending selection.

`SpeciesSearchViewModelTests` covers automatic dual-section reads with one
question, separate pagination cursors and deduplication, partial-result retry,
refinement, reset during either stage, late responses, cancellation,
clarification across pagination, failed replacement recovery, pending filter
composition, and removed/blocked sighting suppression.
`SpeciesSearchResponseTests` covers version/identity/context/cursor validation.
These suites and the authenticated endpoint test are registered in the existing
runtime-audit acceptance manifest. Visual XCTest attachments cover the search
introduction and results in light/dark appearance and larger text, including
single and paired sightings. See the
[feature contract](../../../../../../docs/features-and-hardware/16-species-dictionary.md#conversational-discovery-search),
[verification matrix](../../../../../../docs/development-guides/08-testing-strategy.md#species-discovery-search-verification),
and
[endpoint contract](../../../../../../services/supabase/functions/species-discovery-search/README.md).
