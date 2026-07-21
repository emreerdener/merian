# Insight Media

The `Media` directory manages the rich visual assets associated with a scan.

## Purpose
This area drives the interactive image carousel at the top of an Insight sheet. It is responsible for seamlessly combining the user's live capture images, any additional staged media, and reference imagery (like GBIF or Wikipedia photos) into a unified viewing experience.

External reference URLs are normalized through
`ExternalReferenceImagePolicy.allowedURLStrings(from:)` before carousel pages
are built. The current policy silently removes iNaturalist media `605615444`
and preserves the order of all remaining URLs. Captured/staged user media is not
subject to this exact third-party denylist. If no permitted reference image
remains, the carousel keeps its existing non-reference media or empty-state
behavior; it never creates a censored placeholder page for the blocked URL.

Reference images also pass through the shared
`ReferenceImageDeduplicationPolicy` before the Insight page model is exposed.
`InsightSheetViewModel.displayMedia(_:)` excludes every visual identifier owned
by the current scan: image and video paths in `ActiveScanMedia`, persisted or
queued thumbnail paths, and the toolbar cover path. Naturebook URL variants for
the same storage object match even when their scheme, query, or fragment differs;
external URLs retain strict full-URL identity.

Filtering happens before `refUrls`, `totalImages`, inline carousel pages, and
fullscreen gallery items are derived. Consequently, inline and fullscreen
views share the same order and count, and an all-duplicate loaded reference set
becomes `.empty` instead of leaving an empty reference page or page indicator.
The rule is scoped to the exact scan, not the author: Naturebook imagery from
another scan remains eligible, as do unrelated Wikipedia and GBIF images.
