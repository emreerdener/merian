# Species Dictionary Detail

The `Detail` directory contains the deep-dive screens for individual species
records within the dictionary.

## Structure

- **Views**: The main detail screen for a specific species.
- **Components**: Reusable UI blocks such as taxonomy breakdowns, ecological
  descriptions, and reference image galleries.
- **ViewModels**: Handles the fetching and formatting of the specific species
  data.

## Purpose

When a user selects a species from the catalog or taps a dictionary link
elsewhere in the app, this area is responsible for presenting the rich
educational content associated with that species, such as its taxonomy,
conservation status, and visual characteristics.

## Field Chat

Every loaded detail whose returned `SpeciesDictionaryEntry.id` is a valid UUID
shows `FieldChatToolbarButton` at the bottom right. Loading, error, not-found,
and noncanonical-ID states hide the bottom bar; the native Share action remains
in the top bar. Because direct, deep-linked, and similar-species routes all use
`SpeciesDictionaryPageContentView`, they share this behavior.

A Free viewer opens the existing `PaywallView`. A Pro viewer preflights
`/species-dictionary-chat`, then presents the shared `InsightChatSheet` at its
large detent with owner-only scan actions disabled. The source-specific view
model preserves exact subject-generation fencing across load, send, retry/edit,
delete, feedback, and prompt suggestions. A transcript already loaded in memory
remains readable offline; sending and other mutations remain disabled until the
network returns.

Gallery, author profile, Field Chat, and paywall share one typed
`SpeciesDictionaryPresentation` value. Sheet and full-screen bindings filter
that same slot, so they cannot mount together. A late Field Chat preflight must
still match the loaded canonical species, remain uncancelled, and find the slot
empty before it presents.

The server owns authorization, persistence, limits, and context. The client
requires `subject_id` and every compatibility `messages[].scan_id` to equal the
canonical species UUID before applying success. Dictionary telemetry includes
only entry point, content quality, entitlement state, and broad action fields;
it never includes species names or IDs.

This is a source candidate, not a released capability. Release remains blocked
until same-day sends survive conversation deletion, the Dictionary route is in
the iOS ambiguous-replay allowlist with a lost-response regression, executable
authenticated route tests run in the deploy gate, and refusals/local fallback
chips use fully source-specific, safely bounded labels. See the
[canonical Species Dictionary release status](../../../../../../docs/features-and-hardware/16-species-dictionary.md#candidate-release-status).

## Reference Gallery Safety

`SpeciesDictionaryReferenceGallery` filters every image through
`ExternalReferenceImagePolicy` before choosing the initial item, building the
carousel, or opening the fullscreen presentation. A denied first image promotes
the next permitted item without changing its source/attribution metadata. If no
permitted image remains, the normal leaf placeholder is shown. Catalog and Tree
thumbnails use the same policy when converting reference strings to `URL`, so
detail, catalog, and taxonomy surfaces cannot diverge.

The current exact rule suppresses iNaturalist media `605615444` (GBIF occurrence
`5938154750`) only. It must not remove the European wildcat row or its
navigation route.
