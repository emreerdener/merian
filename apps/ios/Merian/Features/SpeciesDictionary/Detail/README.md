# Species Dictionary Detail

The `Detail` directory contains the deep-dive screens for individual species records within the dictionary.

## Structure

- **Views**: The main detail screen for a specific species.
- **Components**: Reusable UI blocks such as taxonomy breakdowns, ecological descriptions, and reference image galleries.
- **ViewModels**: Handles the fetching and formatting of the specific species data.

## Purpose
When a user selects a species from the catalog or taps a dictionary link elsewhere in the app, this area is responsible for presenting the rich educational content associated with that species, such as its taxonomy, conservation status, and visual characteristics.

## Reference Gallery Safety

`SpeciesDictionaryReferenceGallery` filters every image through
`ExternalReferenceImagePolicy` before choosing the initial item, building the
carousel, or opening the fullscreen presentation. A denied first image promotes
the next permitted item without changing its source/attribution metadata. If no
permitted image remains, the normal leaf placeholder is shown. Catalog and Tree
thumbnails use the same policy when converting reference strings to `URL`, so
detail, catalog, and taxonomy surfaces cannot diverge.

The current exact rule suppresses iNaturalist media `605615444` (GBIF occurrence
`5938154750`) only. It must not remove the European wildcat row or its navigation
route.
