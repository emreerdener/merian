# Insight Shell

The `Shell` directory acts as the root container and primary structural layout for the Insight sheet.

## Purpose
Following the Merian architecture guidelines, the `Shell` orchestrates the assembly of the various insight components (`Media`, `Content`, `IdentificationReview`, `Toolbars`) into a single cohesive scrollable view. It handles the lifecycle and presentation state of the sheet without embedding deep domain logic.

## Presentation Modes

`InsightPresentationStyle.sheet` is the ordinary modal presentation.
`embeddedInScansLibrary` hosts the same Insight content as a pushed destination
inside an existing navigation stack and owns its back arrow/back-swipe behavior.
`ScanInsightRoute` carries only the stable scan ID; the presenting shell must
resolve and load the caller's local scan before pushing it.

Explore uses the embedded mode when a user taps a completed Field-trip goal in
either the catalog card or outing detail. This keeps the Insight view inside the
current Explore sheet and returns to the outing on back. Missing local records
must be handled before navigation; the Insight shell does not fetch Field-trip
evidence or reconstruct media from a remote URL.
