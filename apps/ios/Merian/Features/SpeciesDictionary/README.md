# Species Dictionary

`SpeciesDictionary/` owns the iOS public species-reference experience. The
canonical behavior, API, privacy, and release contract is
[Species Dictionary Page](../../../../../docs/features-and-hardware/16-species-dictionary.md).

## Ownership

- [`Catalog/`](Catalog/README.md) owns Identify/Index overview, category search,
  pagination, and region browsing.
- [`Detail/`](Detail/README.md) owns the species page, gallery, share action,
  Field Chat presentation, and Community sightings.
- `Shared/Models/` owns only cross-surface route/entry-point values, taxonomy
  presentation adaptation, and reference-image labels/attribution used by
  Catalog, Detail, Explore, or Field Trips. It contains no networking or
  SwiftUI.
- `Core/Network/SpeciesDictionaryAPIModels.swift` owns Codable wire DTOs only.
  `SpeciesDictionaryIdentity.swift` and `MerianNetworkClient` own request and
  response identity normalization, exact schema-version validation, transport,
  and the bounded memory cache.
- Explore Shell owns Identify/Index selection, the shared navigation path, and
  destination registration. Views keep selection, navigation, presentation,
  scroll, focus, and lifecycle timing.

Services are the only feature layer that resolves live dependencies. Views and
components do not call endpoints or resolve concrete service singletons. Catalog
and Detail use generation-fenced `@MainActor @Observable` state owners, and
every production Swift file under this feature remains at or below 600 lines.

## Identity And Compatibility

Canonical UUIDs are lowercase. Invalid, synthetic, and `external:` route IDs are
dropped and the normalized scientific name becomes the name-only compatibility
lookup. A dual UUID/name request tries the UUID first and may recover only to an
existing local row with the exact normalized name; it never invokes external
enrichment. Name-only local misses may use the bounded public GBIF/Wikipedia
fallback. iOS accepts only `schema_version = 1` and a matching response identity
before caching. It caches only the returned canonical UUID and normalized
returned name, never a stale requested UUID alias or an `external:` ID.

Index is the only dictionary browser. Taxonomy remains metadata in Catalog and
Detail; the Tree implementation, route, feature flag, DTOs, and endpoint mode
are retired. Decode-only handling of the former `taxonomy` overview category
maps an old response to the complete All catalog.

## Verification

Mirrored tests live under
`MerianTests/Features/SpeciesDictionary/{Catalog,Detail,Shared}`. The Shared
suite owns both presentation behavior and architecture. `SpeciesDictionaryTests`
retains wire, strict client validation, lookup recovery, and cache coverage.
Backend request, eligibility, handler, and disposable-database coverage lives
beside `services/supabase/functions/species-dictionary/` and under
`services/supabase/tests/`.
