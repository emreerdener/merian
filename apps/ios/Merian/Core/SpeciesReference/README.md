# Core Species Reference

This directory owns non-UI, cross-feature species-reference infrastructure.
Feature presentation, interaction, image loading, and observation charts remain
under `Features/SpeciesReference`.

## Shared hydration boundary

`Services/SpeciesReferenceHydrationService.swift` is the single client owner for
Wikipedia mobile-sections lookups by scientific name and GBIF occurrence-image
lookups by taxon key. Its live value owns the isolated public `URLSession`,
request construction, private wire DTOs, HTML normalization, and off-main
decoding.

`InferenceEngine` consumes the optional overview and requires it before applying
Wikipedia state to the active Insight presentation. `ScanThumbnailBackfillActor`
may still use an available article image when a Description section is absent.
Both callers retain their own generation, retry, URL-admission, persistence, and
presentation policy.

`Features/SpeciesReference/Services/SimilarSpeciesImageDependencies.swift`
intentionally remains separate: it uses Wikipedia's summary route and a GBIF
scientific-name query, then loads UI images under feature-owned cancellation and
ordering policy.

## Verification

`MerianTests/Core/SpeciesReference/SpeciesReferenceHydrationServiceTests.swift`
locks requests, parsing, missing-description compatibility, media selection, and
non-success behavior. `SpeciesHydrationArchitectureTests.swift` keeps the
service transport-only and prevents Inference or thumbnail recovery from
reintroducing the shared wire/session implementation.
