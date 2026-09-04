# Species Dictionary Catalog

The `Catalog` directory contains the browsing interfaces for the complete
Species Dictionary. In Explore, these surfaces appear directly as Identify's
**Index** mode; Index is not a bottom-navigation item.

The canonical behavior and backend contract remain the
[Species Dictionary product contract](../../../../../../docs/features-and-hardware/16-species-dictionary.md#overview-and-catalog-modes).

## Structure

- `Models/` owns the typed category route, normalized browse selection and page
  request, country-flag policy, overview filtering, stable category routing, and
  group-row layout values. These are presentation models, not wire DTOs. Shared
  species-detail routes and taxonomy adaptation live in sibling `Shared/Models`.
- `Services/` is the only Catalog layer that resolves live endpoint, image
  loader, geocoder, and MapKit snapshot implementations. Dependencies stay
  narrow closure values rather than a feature-wide protocol or singleton.
- `ViewModels/` owns `@MainActor @Observable` catalog, overview, and region-map
  loading state. Request generations fence stale search, refresh, pagination,
  and map completions.
- `Views/` owns the three root compositions: catalog results, overview, and the
  complete regions list. Search bindings, debounce tasks, pull-to-refresh,
  navigation, and other UI-only timing remain here.
- `Components/Catalog`, `Components/Overview`, and `Components/Regions` own
  their respective rows and cards. `Components/Shared` owns Catalog-only image,
  skeleton, style, and view-modifier rendering.

## Purpose

This area provides a structured encyclopedia index independent of a user's
personal observations. `SpeciesDictionaryOverviewView` is the Identify/Index
root, while catalog, group, region, and species pages push onto Explore's shared
navigation stack and hide root tab/mode chrome.

Regional browsing is country-based. Overview payloads provide an English display
title plus an ISO country code backed by normalized GBIF occurrence facets. iOS
sends the code to catalog mode for exact matching. The personal map card remains
visible but non-interactive with `Coverage updating` when a valid device country
has not been hydrated yet; occurrence evidence is described as "recorded in" and
must not be presented as native range.

Species deep links must select Explore Identify/Index before pushing species
detail. Index is the only dictionary browsing surface. Taxonomy remains
reference metadata displayed in catalog rows and species detail, not a separate
navigation mode.

## Boundaries

- `Core/Network/SpeciesDictionaryAPIModels.swift` remains the owner of Codable
  DTOs and JSON compatibility. The Species Dictionary endpoint extension owns
  catalog/overview payloads, `SpeciesDictionaryResponseValidator` requires exact
  `schema_version = 1`, and `MerianNetworkClient` injects Core Network's private
  pinned and authenticated transport owners. Catalog and overview do not use the
  separate detail/stats memos; Catalog Services adapt their calls for observable
  state.
- Explore Shell owns the shared `NavigationPath`, Identify/Index selection, and
  route destination registration. Catalog owns the category route value and
  emits species-detail routes without creating another navigation stack.
- Catalog Views and Components do not resolve endpoints, `LocalImageLoader`,
  geocoding, or map snapshots directly. The remote-image component preserves the
  existing leaf placeholders while the Service adapter uses the shared cached
  image loader.
- A search/category selection change is recorded before the view's debounce, so
  it immediately invalidates in-flight refresh or pagination work. Older
  completions cannot publish, and retained rows cannot paginate under a
  different selection after a replacement request fails. A failed refresh of the
  current selection still leaves its last usable rows visible. Overview and
  region-map requests use the same latest-request-wins rule, and map
  cancellation always releases its loading state. The corresponding
  [concurrency contract](../../../../../../docs/system-architecture/02-zero-oom-and-concurrency.md#species-dictionary-catalog-selection-and-request-generations)
  explains why task cancellation is paired with identity and generation checks.
- Every production Swift file in this directory must remain at or below the
  600-line review ceiling.

## Tests

Mirrored tests live under `MerianTests/Features/SpeciesDictionary/Catalog/`:

- `SpeciesDictionaryCatalogRouteTests` owns catalog-item and featured-species
  detail routing, including entry point and identity/name propagation.
- `SpeciesCatalogPresentationTests` owns country flags, region visibility,
  category routes/order, and group-row policy.
- `SpeciesDictionaryCatalogViewModelTests` owns normalization, initial-load
  de-duplication, pagination, refresh/search/reverted-selection overlap fencing,
  retained-content errors, and stale-page suppression.
- `SpeciesDictionaryOverviewViewModelTests` owns normalized region loading,
  retained-content errors, and stale overview completion.
- `SpeciesDictionaryRegionMapViewModelTests` owns stale snapshot completion and
  cancellation cleanup.
- `SpeciesCatalogArchitectureTests` enforces directory ownership, Services-only
  live resolution, platform-neutral Models, root-view separation, pre-debounce
  selection fencing, Shared-owned cross-surface models, Core-owned wire DTOs,
  and the 600-line ceiling.

The mirrored sibling `SpeciesDictionary/Detail/` suites own detail-page state,
presentation, endpoint adaptation, Community sightings, and architecture. Core
Network's `SpeciesDictionaryCatalogAPIModelsTests` and
`SpeciesDictionaryCatalogEndpointTests` now own the relocated overview/catalog
wire and payload tests. Schema, identity, deterministic memo, and shared
transport coverage stays with Core Network; see the
[Dictionary verification matrix](../../../Core/Network/README.md#species-dictionary-verification).
