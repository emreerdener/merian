# Journal decisions

Consolidated October 18, 2026. Product direction is distinct from implementation
authorization and release status.

This log preserves the history of explicit choices. Use the [brief](brief.md)
and [UX flows](ux-flows.md) for the current synthesis. Later decisions override
earlier ones where noted: J-24 excludes Field Notes import; J-28 replaces J-27's
no-picker interaction; J-30 completes the picker defaults. The
[prototype plan](prototype-plan.md) contains proposals to test, not additional
confirmed decisions.

## Explicitly confirmed by the user

| ID   | Decision                                                                                      | Evidence from the discussion                                                                                                 |
| ---- | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| J-01 | Learning commonplace book is the main purpose.                                                | User selected this motivation over personal journal and creative keepsake.                                                   |
| J-02 | Freeform collage is the page experience.                                                      | User selected freeform over guided blocks and writing-first entries.                                                         |
| J-03 | One book contains many pages.                                                                 | User selected one book rather than multiple notebooks or one shared endless canvas.                                          |
| J-04 | Journal is private with deliberate page export.                                               | User selected private with export rather than public Explore publishing or no sharing.                                       |
| J-05 | Text, images, and stickers are core material.                                                 | Initial creation-tools selection.                                                                                            |
| J-06 | Each page has an expanding canvas.                                                            | Later explicit correction supersedes the assistant's finite portrait-page proposal.                                          |
| J-07 | Drawing belongs in v1.                                                                        | Later explicit instruction supersedes the original drawing deferral. No engineering estimate was validated.                  |
| J-08 | Apple Freeform is the main inspiration/reference.                                             | User statement in the linked brainstorming conversation.                                                                     |
| J-09 | Keep the name Field Notes for now.                                                            | Explicit response to the proposed Observation notes rename.                                                                  |
| J-10 | Retain the search close-X interaction.                                                        | User rejected replacing that control with a textual Cancel action. Exact platform behavior still needs prototype validation. |
| J-11 | Add initial supporting details to Field Notes without an extra submitted-with-analysis label. | User approved sending this requirement to Simplify capture tools. It belongs to that plan, not Journal implementation.       |
| J-12 | Create repository planning documents and a dedicated Journal chat within Merian.              | User selected both organizational options.                                                                                   |

## Confirmed Pins decision — October 18, 2026

**J-13:** A Pin is saved material; each placement on a page is an independent
copy. The user accepted this recommendation and explicitly requested its
recording in the dedicated Journal planning chat. This is a product decision,
not implementation authorization.

- **Save to Pins** saves material without requiring a page. **Add to journal**
  offers this destination, a new page, or an existing page. Adding directly to a
  page also saves the material to Pins. Confirm in place with Saved to Pins or
  Added to [page] and a View action, without automatically leaving the source.
- Reusing a Pin creates a fresh independent placement, including when reused on
  the same page. Editing a placement's text, crop, or appearance affects only
  that placement. Editing saved material in Pins affects future placements only;
  it does not update existing page copies.
- Removing a placement affects only that page object. **Delete from Pins**
  removes reusable material from Pins while preserving existing page copies and
  the original source. Explain: "Copies on your pages will stay." Offer Undo. Do
  not include an ordinary delete-everywhere action.
- Saving the same unchanged material again reuses its existing Pin. Different
  excerpts or selected images can be separate Pins. Exact identity matching
  remains an engineering-planning detail.
- Each placement retains source provenance and attribution after Pin deletion.
  Underlying source deletion and access revocation follow J-14/J-15 below; Pin
  deletion is separate from those operations.
- Writing, sketches, and objects created or inserted within a page do not
  automatically become Pins. The user can choose **Save to Pins** for them.
  Automatic saving applies to material brought in through **Add to journal**.

## Confirmed fallback-image direction — October 18, 2026

**J-14:** When another person's Explore source is deleted or withdrawn, try to
provide a fallback image from Naturebook, Wikipedia, or GBIF before defaulting
to an unavailable-image placeholder. The user explicitly requested this change
to the proposed placeholder behavior. Provider priority and selection rules
remain open; the list does not establish a strict lookup order.

The user subsequently approved the updated deletion proposal with one
correction: no special replacement or "Representative image" label is needed;
use an attribution tag for the replacement's own source and credits. Match the
referenced species, preserve the object's position and dimensions and personal
annotations, and use a placeholder when no suitable, permitted image is
available. Do not use a fallback to reintroduce the withdrawn original image or
attribute the new image to the original observer. Provider access, reuse/export
permissions, matching when the species is uncertain, and offline lookup require
qualification before implementation.

## Confirmed source-deletion policy — October 18, 2026

**J-15:** The user approved the updated deletion proposal, including J-14's
fallback images with attribution and no special replacement label. This is
planning approval, not implementation or a change to current deletion systems.

| Event                                                     | Confirmed Journal behavior                                                                                                                                                                                                                                                                             |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| User deletes their own scan                               | Keep deliberately saved material in Pins and pages by default. Mark its source Original scan deleted and remove the action to open it. When Journal copies exist, the deletion confirmation says "Material saved to Journal will remain."                                                              |
| User chooses Delete scan and remove saved Journal content | Show affected Pins/pages before confirmation, then remove the scan and its source-derived Journal content. Preserve independently written annotations and drawings. This is a separate source-removal action, not ordinary Delete from Pins.                                                           |
| User deletes a Field Chat conversation                    | Keep deliberately saved excerpts and their AI attribution; the original conversation is unavailable.                                                                                                                                                                                                   |
| Another person deletes or withdraws an Explore post       | Remove its original photo and saved source text from Pins/page copies once the app learns of the withdrawal. Try J-14's image fallback; otherwise show an unavailable placeholder. Preserve surrounding personal writing, drawings, and layout. Future exports must not include the withdrawn content. |
| External webpage disappears                               | Keep the excerpt or image explicitly saved to Journal, with attribution and its original link. Mark the source link unavailable when known.                                                                                                                                                            |
| Source temporarily fails to load                          | Show temporary unavailability. A network failure is not evidence of deletion and must not trigger destructive removal.                                                                                                                                                                                 |

Removal propagation, offline reconciliation, derived previews/search indexes,
and distinguishing personal annotations from source-derived content need an
engineering plan. Account deletion and explicit erasure requests are outside
this ordinary source-deletion decision; retained Journal copies must not be
assumed exempt from those policies.

## Confirmed source snapshots and deliberate updates — October 18, 2026

**J-16:** Save a snapshot of material when it enters Journal. The user approved
snapshot behavior with the option to deliberately update a Pin or page copy.

- A scan's saved image and species label stay as saved when the scan is
  reidentified. Opening its source shows the current scan; the saved material
  retains provenance to the source version used at insertion or deliberate
  update. Exact identifiers and storage are engineering-planning details.
- Deliberately saved Field Notes excerpts remain independent of later note
  edits. Saved Explore excerpts/images likewise do not change automatically when
  the original post is edited.
- Let the user preview newer source material and deliberately update the
  selected Pin or page copy. Updating a Pin affects future placements only;
  updating a page copy affects only that copy, consistent with J-13.
- Snapshot behavior does not bypass J-14/J-15 source deletion, withdrawal,
  removal, or fallback-image rules. It is not a promise to retain withdrawn
  content indefinitely.

The update interaction's exact copy, handling of locally edited material,
layout/crop preservation, and Undo need further design. This records product
direction and does not authorize implementation.

Later scope correction: J-24 excludes Field Notes from Journal's source-add
flow, superseding the contemplated Field Notes import above. Snapshot behavior
continues to govern supported saved material and attached metadata.

## Confirmed audio visual — October 18, 2026

**J-17:** Use the existing spectrograph/waveform visual for Journal audio. The
user specified this visual in response to the proposed compact audio card.
Identify and reuse the appropriate existing visual during engineering planning;
this decision does not claim that Journal integration is implemented.

The broader media scope was subsequently approved in J-18 below; J-22 defines
static audio/video visuals for image/PDF exports.

## Confirmed v1 media scope — October 18, 2026

**J-18:** Include individually selectable photos, playable audio, and
tap-to-play video in v1. The user explicitly approved this scope and requested
that it be recorded.

- Let users select individual photos from a multi-photo scan. Each selected
  photo follows the existing Pin and independent page-copy model.
- Audio plays within Journal and uses J-17's existing spectrograph/waveform
  visual with playback controls and duration.
- Video presents a poster image with a play action; tapping opens playback. Do
  not autoplay video.
- Saved media remains subject to J-13's reuse rules, J-16's snapshot behavior,
  and J-14/J-15's source-deletion and withdrawal policy.

Stack behavior, exact player presentation, media limits, and download mechanics
require further design or engineering qualification. J-28 establishes a shared
media-selection view across supported sources. J-22 defines export
representation. J-20 establishes offline availability direction. Trimming and
other media editing are not included by this playback decision. This is product
scope, not implementation approval.

## Confirmed canvas interaction and editing tools — October 18, 2026

**J-19:** The user approved the arranging/drawing model, including drawing
tools, shared Undo/Redo, autosave, and accessible controls.

- Arrange: drag empty space to pan, tap an object to select it, then move,
  resize, or rotate it. Pinch to zoom.
- Draw: enter Draw mode; one finger draws and two fingers navigate. Done returns
  to arranging. Include pen, pencil, highlighter, eraser, color, and stroke
  width.
- Write: tap Text to insert a text box; double-tap existing text to edit it.
- Play media using its explicit play control, distinct from selecting or moving
  the object.
- Fit all shows the whole composition. Reopening a page restores its previous
  viewport.
- Shared Undo/Redo covers drawing and object edits. Autosave preserves accepted
  changes.
- Provide accessible controls for positioning, resizing, and other actions
  beyond gestures; gesture-only interaction is insufficient.

Exact toolbar layout, ink selection, keyboard/sheet gesture handling, canvas
resource limits, Undo history lifetime, and implementation of J-20's
offline/sync policy remain design or engineering questions. This product
approval does not establish implemented persistence or authorize implementation.

## Confirmed offline editing and account sync — October 18, 2026

**J-20:** The user approved offline editing with automatic account sync,
separate audio/video downloads, preservation of conflicting edits, and warning
about unsynced work before sign-out.

- Create and edit pages, draw, and reuse downloaded Pins without internet.
  Persist accepted edits on the device immediately; upload is not a prerequisite
  for local saving.
- Sync automatically to the signed-in account when a connection is available.
  Use a quiet status indicator and clear errors when user action is needed.
  Distinguish Saved on this device from Synced.
- Keep saved photos available offline. Offer separate **Download for offline
  use** controls for audio/video and show download status. The mechanics of
  pending photo downloads and storage limits still need qualification.
- Merge changes to different objects where safe. When the same content has
  conflicting edits, preserve both versions for review rather than silently
  overwriting either edit. Exact conflict presentation remains open.
- Identify and warn about unsynced work before sign-out. Keep each account's
  private Journal isolated. The sign-out choices and recovery mechanics remain
  to be designed; the warning does not establish a discard policy.

Sync transport, merge rules, deletion-versus-edit conflicts, media retention,
guest transitions, and account recovery require engineering planning against
existing account-isolation and deletion contracts. J-14/J-15 still govern source
withdrawal/removal; conflict preservation must not restore withdrawn source
content. This is product approval, not an implemented sync guarantee or
authorization to change schemas or backend behavior.

## Confirmed search scope and query behavior — October 18, 2026

**J-21:** The user approved the proposed search scope and query behavior,
including offline search and clearing the query when search closes.

- Search page titles, typed text, saved excerpts, captions, and
  species/reference names. Pins remain independently searchable after placement.
  A page matches only content actually placed on it, not entire source
  conversations or posts.
- Show a matching excerpt and open the page near the relevant object.
- Rank title/name matches ahead of content matches; use recent editing as a
  tie-breaker. Exact matching/tokenization still requires design.
- Pages and Pins share a query. Preserve it during navigation within search.
  Expanded-results Back returns to combined results; the bottom X exits search.
- Clear the query when search closes. Clearing text in an expanded grid keeps
  search open and shows all items of that type.
- Search locally available Journal content offline, including unsynced edits.
- Empty search shows recently opened Pages/Pins.
- Defer handwriting recognition, text recognition inside images, and semantic
  image/audio search beyond v1.

Index maintenance, source-removal propagation, recent-item history controls,
no-match presentation, keyboard behavior, and native interaction validation
remain design/engineering work. Search must honor source withdrawal/removal and
account isolation under J-15/J-20. This is product approval, not implementation.

## Confirmed v1 page export — October 18, 2026

**J-22:** The user approved image and PDF export in v1 with the proposed framing
and privacy rules, including attribution and static audio/video visuals.

- Offer Image and PDF formats with **All content** or **Selected area** framing
  and a preview before exporting. Show the resulting scale clearly for large
  canvases. Defer automatic multi-page tiling unless later review establishes it
  as essential; it is not an approved v1 requirement.
- Render audio as its static waveform/spectrograph and video as a static poster
  image. Omit playback controls that would appear functional. Playable-media
  export is not part of this decision.
- Preserve source credits, including attribution for fallback images.
- Export only the selected visible composition. Exclude hidden location metadata
  and private source links. Visibly written locations remain visible in the
  preview; this is not automatic redaction of visible page content.
- Flag missing media before export so the user can download it or knowingly
  continue with a placeholder. Honor J-14/J-15: withdrawn source content stays
  excluded, with fallback imagery used where applicable.
- Present the system share sheet after export. Do not automatically upload
  publicly or create public scan URLs as a side effect.

Image encoding, resolution/size limits, PDF sizing, preview/credit layout, and
permission qualification remain open. J-23 includes this core export on Free.
This is product approval, not implementation or authorization for external
publication.

## Confirmed Free core and Pro enhancements — October 18, 2026

**J-23:** The user approved a complete Free Journal core with Pro for extra
storage and optional creative enhancements. Existing work stays usable after
downgrade; storage allowances and pricing remain open.

- Free includes Pages, Pins, drawing/basic assets, photos, audio/video playback,
  search, offline editing, automatic account sync within a storage allowance,
  and the approved Image/PDF export.
- Pro provides extra storage and optional creative enhancements, such as
  additional creative packs or premium stickers. The exact paid catalog and
  delivery scope remain open. Future advanced export or AI tools are
  possibilities, not approved v1 commitments or restrictions on core export.
- Preserve existing pages and placed premium assets after downgrade. Existing
  work remains accessible, editable, and exportable.
- If above the Free storage allowance after downgrade, keep local editing and
  access/export available. Additional cloud uploads require freeing space or
  upgrading; clearly identify unsynced changes. Exact accounting, allowed
  reconciliation/deletion operations, and recovery behavior need design.
- Use storage rather than a small page-count cap as the monetization boundary.
  Set allowances after measuring costs; this does not promise unlimited storage
  or remove technical canvas/media limits.

This product decision does not authorize changing billing products, prices, or
entitlements in external systems. It does not change Field Chat's separate
generation access policy.

## Confirmed media-first scan additions — October 18, 2026

**J-24:** The user rejected the proposed photo-plus-visible-species-label flow
with optional Field Notes/date/location fields. Use media as the main canvas UI:
image, video, audio, or a stack whose media can be moved individually as
separate canvas elements.

- Do not include Field Notes in Journal's source-add flow, including as an
  optional import. Field Notes remains the separate observation feature; this
  supersedes the earlier contemplated Field Notes excerpt import.
- Carry associated metadata, such as name and date, with the media without
  asking the user which metadata to include. Metadata is available on demand,
  rather than automatically laid out as separate text or a permanent label.
- Preserve individual media manipulation when presenting multiple items as a
  stack. This does not approve general-purpose grouping or flatten the stack
  into one image.
- Retain J-16 snapshot behavior for supported source material and metadata. J-22
  still excludes hidden metadata/private links from exports; attachment of
  metadata does not make it visible export content.

The user initially suggested tapping media to see metadata or a **Show details**
menu option; J-25 below confirms the object-menu approach. J-28 establishes
explicit media selection across sources. Stack/Pin granularity, stack expansion,
precise metadata fields (including any location policy), and source-access
presentation still need design. This is not authorization to copy entire source
records or implement the feature.

## Confirmed selected-media details menu — October 18, 2026

**J-25:** Put **Show details** in the object's menu, with the menu entry point
visible while media is selected. The user explicitly chose this interaction.

- Tapping media selects it and exposes a visible menu button. Opening the menu
  and choosing Show details opens the saved metadata/details presentation.
- Selection itself does not open details or start playback. Audio/video retain
  their explicit playback controls under J-18/J-19.
- Keep this menu entry point accessible under J-19; do not make discovering the
  menu depend solely on a long press or other hidden gesture.

Exact menu-button placement, details-sheet layout, metadata fields, and
source-action presentation still require design. This is planning approval, not
implementation authorization.

## Confirmed selected-media species tag — October 18, 2026

**J-26:** The user approved an Explore-style species common-name tag over
selected media, alongside the visible object-menu button.

- Use the saved snapshot common name in a top-leading rounded translucent
  material pill with semibold text, following the visual treatment of
  [`ExplorePostCard.speciesOverlay`](../../../apps/ios/Merian/Features/Explore/Feed/Components/Cards/ExplorePostCard.swift).
- Show the tag while the media item is selected; hide it when deselected. Keep
  the object-menu entry point visible during selection and leave playback and
  manipulation controls unobstructed.
- Show details remains the route to fuller metadata under J-25.
- Exclude the selection tag and menu controls from exports. The tag is editor
  UI, not permanent metadata text in the composition.

Missing-name fallback, zoom/rotation handling, and exact spacing still need
design. Explore's rank text and scientific-name fallback are reference behavior,
not automatically approved Journal requirements. This is planning approval, not
an implementation claim.

## Confirmed pinning of the currently viewed media — October 18, 2026

Historical decision, subsequently revised by J-28: the no-picker interaction is
superseded by a shared selection view. The principle of not automatically saving
all source media remains in force.

**J-27:** The primary pinning experience saves the specific media item the user
is looking at, not all media in its post or scan. The user explicitly rejected
the proposed whole-scan stack default.

- Add to journal from a media-viewing context targets the current image, video,
  or audio item and its associated snapshot metadata. Other items in the post
  are not implicitly saved or placed.
- Retain J-13's destinations: Save to Pins, New page, or an existing page.
  Direct page placement also retains that specific item in Pins.
- Do not require a media picker merely to save the item already being viewed.
  Saving additional items requires a separate deliberate action or explicit
  selection; bulk/stack interaction design remains open.

J-24's individually movable stack items remain a possible multi-item
presentation, not the default result of pinning from a post. Entry points with
no unambiguous current media item, optional bulk selection, and stack controls
still need design. This is product direction, not implementation authorization.

## Confirmed shared media-selection view — October 18, 2026

**J-28:** Use a selection view so users choose which available media to add to
Journal. The user first proposed this for private/personal scans, then extended
the direction to Explore posts, Species Dictionary pages, and other supported
media sources. This supersedes J-27's no-picker default across those surfaces.

- Present the source's available, eligible media for individual selection and
  save/place only the chosen items. Do not automatically import the entire scan,
  post, or species page.
- Preserve J-13's Save to Pins, New page, and existing-page destinations. Each
  selected media item retains its associated snapshot metadata and provenance;
  direct page placement also saves selected material to Pins.
- This is a media picker, not the rejected metadata/Field Notes form. Metadata
  accompanies selected media automatically; Field Notes remain excluded.
- Multiple chosen items remain individually movable on the canvas under J-24.
  The picker does not by itself settle stack layout or Pin grouping.

Subsequently confirmed by the user: preselect the currently viewed item when
identifiable, then let users adjust the selection. This is a starting selection,
not an automatic save or selection of the entire source.

J-30 below settles selection defaults and preview interaction. Exact picker
layout, the additional source list, and availability/permission handling remain
open. This is product direction, not implementation authorization.

## Confirmed selection and destination order — October 18, 2026

**J-29:** The user approved choosing media first, then its destination.

1. Add to journal opens the shared media-selection view under J-28.
2. The user adjusts the selected items.
3. Offer Save to Pins or Add to page.
4. Add to page offers New page, recent pages, and a searchable list of all
   pages.
5. Confirm the save in place with a View action, without automatically leaving
   the source screen.

When inserting from inside an open Journal page, its destination is already
known: confirmation adds the selected items to that page without asking the user
to choose it again. Existing J-13 save/reuse rules still apply. Exact
recent-page ordering and page-picker presentation remain design details. This is
planning approval, not implementation authorization.

## Confirmed media-picker defaults — October 18, 2026

**J-30:** The user approved these shared picker defaults:

- When the current item is known, preselect it, as established by J-28.
- With multiple available items and none currently viewed, start with nothing
  selected.
- With only one available item, show it selected in the same selection view.
- Show selection checkmarks and a selected count. Disable saving when nothing is
  selected.
- Audio/video use separate preview/play controls; previewing does not change
  selection.
- Cancel leaves the flow without saving anything.

These defaults apply to the shared flow across supported sources. Exact layout,
empty/unavailable-source states, and handling of availability changes during
selection remain design/engineering details. This is product approval, not
implementation authorization.

## Working direction shown in the user's mockups

These are the current design baseline. The accompanying behavioral proposals
still require review; screenshots do not settle data semantics or edge cases.

- Book contains Library and Journal in its bottom navigation.
- Library has Scans/Collections; Journal has Pages/Pins.
- The updated Pages gallery shows Sort, Filters, All, Recent, and Favorites.
  Their exact behavior is not yet confirmed.
- The updated Pins gallery shows Photos, Videos, Audio, and Text sections with
  View all. The expanded Photos grid has per-item pin/menu controls, a bottom
  search field, and close X. This replaces the earlier All/Text/Media/Stickers
  filter sketch as the working visual reference, not as a new filter contract.
- Opening a page enters a canvas editor with the Library/Journal navigation
  hidden and a compact expandable creation control.
- Search has Scans/Collections/Journal scopes. Journal results include Pages and
  Pins sections with View all actions and expanded result grids.
- Search uses a top back chevron plus the bottom close X. Expanded category
  mockups include an editable search field and result count.
- A scan menu offers Add to journal alongside Add to collection.

Generated follow-up mockups illustrate the media picker and selected photo,
video, and audio objects. Selection handles, exact menus, and player geometry in
those images remain illustrative. They are static studies, not validated
interactive prototypes. The selected species tag, visible object-menu entry
point, and explicit playback follow J-18/J-25/J-26.

## Recommendations still requiring confirmation

- Selection-to-source access details follow the proposals in
  [UX flows](ux-flows.md); J-19 confirms core canvas controls and J-22 confirms
  the export behavior.

## Superseded or unselected ideas

- Fixed portrait pages: superseded by expanding canvases.
- Automatically saving all media in a post/scan as a stack: rejected in favor of
  deliberate item choice, now through J-28's shared selection view.
- J-27's no-picker default: superseded by J-28 across supported media sources.
- Drawing deferred beyond v1: superseded by explicit v1 inclusion.
- Rename Field Notes to Observation notes: rejected for now.
- Replace the search close X with Cancel: rejected.
- Optional Field Notes import and a photo-plus-visible-species-label add form:
  superseded by J-24's media-first additions with attached metadata on demand.
- Pages/Scans/Collections as three peer Book sections: earlier recommendation,
  superseded as working direction by Library/Journal mockups.
- Clippings, Saved, Assets, and Boards: explored names; Pages/Pins is the
  current working vocabulary. Scrapbook describes the experience rather than a
  second destination inside Journal.
- Template-only MVP, earned-only stickers, smart connectors, AI-generated pages,
  and public Journal posts: brainstormed possibilities, not approved scope.

## Initial details to Field Notes handoff

The approved planning addition was sent to **Simplify capture tools**
(`01a12c47-6f54-7500-bab9-679c2babf9a0`) on October 18, 2026:

> When a new observation is submitted, include the user's supporting description
> as the initial editable Field Notes text, without a Submitted with analysis
> label. Preserve existing notes. Retries and recovery must not duplicate text
> or reinsert text the user later changes or clears. Editing Field Notes must
> not alter immutable submitted analysis evidence or automatically publish the
> text to Explore.

The handoff requested planning only and preserved that chat's implementation
approval boundary. Historical backfill and reanalysis-note changes were not
included. Do not assume the destination chat has completed or implemented the
addition merely because the message was delivered.
