# Journal feature brief

Status: planning synthesis. See [decision authority](decisions.md).

## Product idea

Collect what sparks your curiosity and make it your own. Journal is a private,
visual commonplace book where people gather nature knowledge, connect ideas, and
add their own writing and drawings.

The primary motivation chosen by the user is learning. Freeform collage is the
chosen interaction model. A page can develop over several visits rather than
being a dated, finished entry.

Example: a page titled **Oaks I keep confusing** contains two species
references, a passage saved from Field Chat, a leaf sketch, and a personal
question. A user can revisit the original observation or reference without
losing the composition.

## Audience and jobs

The initial audience is curious observers and hobby naturalists already using
capture, observations, Explore, and Field Chat.

- Keep an explanation or image without interrupting discovery.
- Bring material from different sources together around a topic.
- Write, sketch, compare, and arrange material freely on an iPhone.
- Find a remembered fact or page later and understand its source.
- Export a chosen composition deliberately while keeping the Journal private.

Repeat engagement between outings is a hypothesis to measure, not an established
retention benefit.

## Vocabulary and boundaries

| Term        | Working meaning                                                      |
| ----------- | -------------------------------------------------------------------- |
| Book        | Personal destination presented over the camera/audio workspace       |
| Library     | Scans and Collections                                                |
| Journal     | Creative workspace within Book                                       |
| Page        | Named composition on an expanding canvas; no fixed portrait boundary |
| Pin         | Saved material reusable as independent copies on pages               |
| Field Notes | Existing notes attached to an individual observation; name retained  |

Journal does not replace Collections or Field Notes. Collections organize scans;
Field Notes record one encounter. Journal combines material across encounters
and topics. Field Notes are excluded from the Journal source-add flow.

## Confirmed first-version scope

The [decision log](decisions.md) owns the full rules and their history. This is
the current scope summary, not a statement of implemented behavior.

| Area             | Confirmed direction                                                                                                                                                                         | Decision owner                                                                       |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Pages            | One book, many expanding collage canvases; text, images, stickers, and drawing                                                                                                              | J-01–J-08                                                                            |
| Pins             | Reusable saved material; independent page copies; direct Add to journal placement also saves to Pins; page-created material needs explicit Save to Pins                                     | [J-13](decisions.md#confirmed-pins-decision--october-18-2026)                        |
| Media selection  | Shared picker for personal scans, Explore, Species Dictionary, and other supported media sources; only selected items are added                                                             | [J-28](decisions.md#confirmed-shared-media-selection-view--october-18-2026)          |
| Add flow         | Choose media, then Save to Pins or Add to page; new/recent/searchable pages; known open-page destination skips selection of a destination; confirm in place with View                       | [J-29](decisions.md#confirmed-selection-and-destination-order--october-18-2026)      |
| Picker defaults  | Preselect current or sole item; multiple items without a current item start empty; checks/count, disabled save at zero, separate preview, cancel saves nothing                              | [J-30](decisions.md#confirmed-media-picker-defaults--october-18-2026)                |
| Canvas media     | Individually movable photos, playable audio using the existing spectrograph/waveform, and tap-to-play video without autoplay                                                                | [J-17/J-18](decisions.md#confirmed-v1-media-scope--october-18-2026)                  |
| Selected media   | Saved common-name tag in the Explore style and visible object-menu button; Show details reveals attached metadata; no permanent automatic metadata text or Field Notes import               | [J-24–J-26](decisions.md#confirmed-media-first-scan-additions--october-18-2026)      |
| Editing          | Move/resize/rotate, pan/zoom, separate Draw mode, pen/pencil/highlighter/eraser, color/width, text editing, Fit all, restored viewport, shared Undo/Redo, autosave, accessible alternatives | [J-19](decisions.md#confirmed-canvas-interaction-and-editing-tools--october-18-2026) |
| Offline and sync | Immediate local saving and automatic account sync; photos offline, separate audio/video downloads; preserve conflicting edits; warn before sign-out with unsynced work; isolate accounts    | [J-20](decisions.md#confirmed-offline-editing-and-account-sync--october-18-2026)     |
| Search           | Page titles, typed text, excerpts, captions, and species/reference names; independent Pin results; offline local content including unsynced edits; shared query cleared on closing search   | [J-21](decisions.md#confirmed-search-scope-and-query-behavior--october-18-2026)      |
| Export           | Image/PDF, All content or Selected area, preview, credits, static audio/video visuals, missing-media handling, system share sheet                                                           | [J-22](decisions.md#confirmed-v1-page-export--october-18-2026)                       |
| Free/Pro         | Complete Free core with a storage allowance; Pro adds storage and optional creative enhancements; existing work remains usable after downgrade                                              | [J-23](decisions.md#confirmed-free-core-and-pro-enhancements--october-18-2026)       |

## Saved material and source changes

- Editing a page copy affects only that copy. Pin edits affect future
  placements. Removing a page copy leaves its Pin/source; deleting a Pin leaves
  page copies and their provenance. Re-saving unchanged material reuses its Pin.
  See J-13.
- Save source material and metadata as snapshots. Source changes do not silently
  alter a composition. A user can preview and deliberately update a selected Pin
  or page copy; withdrawal/removal rules still apply. See
  [J-16](decisions.md#confirmed-source-snapshots-and-deliberate-updates--october-18-2026).
- Ordinary deletion of the user's own scan retains saved Journal material; a
  separate explicit action can remove its source-derived Journal content too,
  after previewing affected Pins/pages. Personal annotations are preserved.
  Saved Field Chat excerpts survive conversation deletion with AI attribution. A
  missing external webpage retains explicitly saved content and credit.
- Withdrawn Explore images and source text are removed once known. Try a
  species-matched, permitted Naturebook, Wikipedia, or GBIF image with its own
  attribution, preserving layout and annotations. No special replacement label
  is required; use a placeholder if no suitable image exists. Temporary network
  failures are not deletion. See
  [J-14/J-15](decisions.md#confirmed-source-deletion-policy--october-18-2026).

## Scope still to qualify

The media picker covers personal scans, Explore posts, and Species Dictionary
pages. Saved Field Chat excerpts have confirmed retention/attribution rules;
their entry interaction remains to be designed. Additional import sources such
as personal photos and external links need an explicit scope decision.

Page lifecycle, multi-item placement/stack controls, metadata fields, source
access, detailed player controls, and recovery presentation need design work.
Storage allowances, prices, the paid catalog, resource limits, persistence,
source-removal propagation, export permissions, and output limits need further
qualification. Above the Free allowance, local access/editing/export continue,
additional cloud uploads require space or an upgrade, and unsynced changes must
remain clear; exact accounting/reconciliation mechanics are open.

The working scope defers collaboration, public Journal publishing, multiple
notebooks, and automatic AI page generation. Handwriting/OCR/semantic media
search and automatic PDF tiling are deferred beyond v1. Media playback does not
imply trimming; drawing does not imply smart connectors, shape recognition, or
multi-object grouping.

Use the [roadmap](roadmap.md) for remaining decisions and the
[prototype plan](prototype-plan.md) for the next design pass.

## Privacy and provenance

Private scan references must open only inside the authorized app context. Adding
an observation to Journal must not publish it or create a public URL. Preserve
the distinction between personal annotations, saved AI text, and attributed
third-party references.

Page export is a separate deliberate disclosure of the selected visible
composition, including any private imagery or visibly written locations in it.
Preview this content before export. Exclude hidden location metadata and private
source links, preserve source credits, and honor the source-deletion policy,
including removal of withdrawn Explore content. Do not automatically publish the
page or create public source URLs.
