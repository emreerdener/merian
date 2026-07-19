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
