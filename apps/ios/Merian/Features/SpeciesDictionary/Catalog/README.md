# Species Dictionary Catalog

The `Catalog` directory contains the browsing interfaces for the complete
Species Dictionary. In Explore, these surfaces appear directly as
Identify's **Index** mode; Index is not a bottom-navigation item.

## Structure

- **Views**: Main catalog grids and list views displaying known species.

## Purpose

This area provides a structured encyclopedia index independent of a user's
personal observations. `SpeciesDictionaryOverviewView` is the Identify/Index
root, while catalog, group, region, and species pages push onto Explore's shared
navigation stack and hide root tab/mode chrome.

Regional browsing is country-based. Overview payloads provide an English
display title plus an ISO country code backed by normalized GBIF occurrence
facets. iOS sends the code to catalog mode for exact matching. The personal map
card remains visible but non-interactive with `Coverage updating` when a valid
device country has not been hydrated yet; occurrence evidence is described as
"recorded in" and must not be presented as native range.

Species deep links must select Explore Identify/Index before pushing species
detail. The taxonomy Tree/galaxy map has no MVP entry point; its preserved code
and API contract remain owned by the sibling `Tree` area.
