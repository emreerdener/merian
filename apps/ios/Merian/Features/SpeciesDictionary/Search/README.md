# Species Dictionary Search

Results-first conversational discovery across canonical species and public
community sightings. Explore Shell owns one `SpeciesSearchViewModel` per Explore
presentation; returning from a detail preserves results, tab, draft, and scroll
position. Closing Explore releases that state, and account changes clear it. No
SwiftData model or retained conversation is created.

`Views` owns composition, keyboard focus and structured request tasks.
`Components` owns the overview entry and public-sighting presentation using
Explore's existing image/media primitives. `Models` owns the typed route.
`ViewModels` owns the search generation, replacement/page state, clarification
context, filters and retry. Only `Services` resolves live networking. Codable
payloads and strict decoding remain in Core Network.

The overview entry remains available during loading and failure. Search pushes
onto Explore's shared stack. Species and Sightings share species criteria; media
filters are explicitly Sightings-only. Dictionary excerpts are source text, not
model-authored claims. Sightings use public attribution/location labels and
publication dates labeled “Shared”. Result details use existing dictionary and
Explore routes. Sightings register only changed results in Explore's shared
store, honoring session removal revisions and newly blocked author IDs so
pagination and late responses cannot restore removed or blocked cards, including
posts not previously present in the store.

A request identity change cancels the old view task. Generation checks reject
late completions even if cancellation is ignored. Failed replacements preserve
the previous result and draft and disable pagination until retry or another
selection. Clearing search invalidates all work. Provider retries are explicit
new attempts; tab/pagination requests never invoke AI. Retries preserve the
failed request's result tab and cursor even if the visible tab changes.
Clarifications remain pending while users browse existing results, and
consecutive filter edits compose against the pending selection.

`SpeciesSearchViewModelTests` covers refinement, tab requests, reset, late
responses, cancellation, clarification across tabs, failed replacement recovery,
retry tab/cursor identity, pending filter composition, and removed/blocked
sighting suppression. `SpeciesSearchResponseTests` covers
version/identity/context/cursor validation. These suites and the authenticated
endpoint test are registered in the existing runtime-audit acceptance manifest.
Visual XCTest attachments cover the search introduction and results in
light/dark appearance and larger text. See the
[feature contract](../../../../../../docs/features-and-hardware/16-species-dictionary.md#conversational-discovery-search),
[verification matrix](../../../../../../docs/development-guides/08-testing-strategy.md#species-discovery-search-verification),
and
[endpoint contract](../../../../../../services/supabase/functions/species-discovery-search/README.md).
