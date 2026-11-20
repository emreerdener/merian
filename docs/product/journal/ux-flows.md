# Journal UX flows

Status: current interaction synthesis of J-01–J-30. Confirmed rules link to
[Decisions](decisions.md); visual direction and unresolved presentation are
identified separately. See the [prototype plan](prototype-plan.md) for what to
test next. These flows do not describe shipped implementation.

## Navigation

```text
Capture workspace
  Book sheet
    Library
      Scans
      Collections
    Journal
      Pages
        Open a page -> expanding canvas editor
      Pins
```

At Book's root, the top X dismisses the sheet to capture. Drag-to-dismiss
remains available. Preserve the originating section, filter, and scroll state
when returning from search or detail. Restoring the last Library/Journal
selection is a proposal, not yet a final persistence policy.

The updated visual reference shows a Pages grid with New page, Sort, Filters,
All, Recent, and Favorites. Pins uses Photos, Videos, Audio, and Text sections
with View all; expanded Photos shows a grid, per-item pin/menu controls, result
count, and bottom search field with close X. This supersedes the earlier
All/Text/Media/Stickers filter sketch as the working presentation. Exact filter,
sort, favorite, and category-browsing semantics still need review. Built-in
sticker browsing need not populate Pins automatically.

The editor hides root navigation, provides Back to the page gallery, and exposes
undo/redo, export, page options, and a compact expandable creation toolbar. The
mockup's generic Saved status needs the J-20 distinction between Saved on this
device and Synced. Authored headings and text notes in the canvas examples are
composition content, not automatically imported metadata or Field Notes.

## Add to journal and Pins

Confirmed source action under J-13/J-28, with ordering confirmed by
[J-29](decisions.md#confirmed-selection-and-destination-order--october-18-2026):

```text
Add to journal
  Select media
    Save to Pins
    Add to page
      New page...
      Recent pages...
      Search all pages...
```

When inserting from an open Journal page, confirm the media selection directly
into that page; skip destination selection. Exact recent-page ordering and
page-picker presentation remain open.

- Save to Pins collects material without requiring composition. Under
  [J-28](decisions.md#confirmed-shared-media-selection-view--october-18-2026), a
  shared media-selection view lets users choose available items from personal
  scans, Explore posts, Species Dictionary pages, and other supported sources.
  Save/place only the chosen items, not the entire source. This supersedes
  J-27's no-picker interaction. Media selection precedes destination selection.
- Choosing a page saves the material to Pins and places an independent copy on
  that page. Saving the same unchanged material reuses its existing Pin;
  different excerpts or selected images can have separate Pins.
- New page creates a page with the selected material already present.
- Confirm in place with Saved to Pins or Added to [page], plus a View action.
- A Pin remains available for reuse, including on the same page. Placement edits
  affect only that copy; Pin edits affect future placements only.
- Removing a page copy leaves the Pin, source, and other copies intact. **Delete
  from Pins** leaves existing page copies and the original source intact,
  explains "Copies on your pages will stay," and offers Undo. There is no
  ordinary delete-everywhere action. Copies retain provenance and attribution
  after Pin deletion.
- Material created or inserted within a page becomes a Pin only through an
  explicit **Save to Pins** action. Automatic saving applies to material brought
  in through **Add to journal**.

Confirmed scan-add direction under
[J-24](decisions.md#confirmed-media-first-scan-additions--october-18-2026):
present the image, video, audio, or stack of media as the main canvas UI. Each
media item can be moved individually as a separate element. Carry name, date,
and associated metadata automatically for on-demand access, without a metadata
selection form or automatically placing metadata as separate canvas text.
Exclude Field Notes, including optional Field Notes import.

Confirmed details interaction under
[J-25](decisions.md#confirmed-selected-media-details-menu--october-18-2026): tap
media to select it; a visible, accessible menu button appears while it is
selected. Choose **Show details** in that object's menu to open its saved
metadata. Selection alone does not open details or start playback; media keeps
its explicit play controls. Exact menu placement, details-sheet layout, and
authorized source-action presentation remain open. Stack expansion and stack/Pin
granularity remain open. J-28 establishes explicit media selection. No public
URL is fabricated for private observations. Source deletion, snapshots, and
export privacy still follow the confirmed policies below.

Confirmed selection treatment under
[J-26](decisions.md#confirmed-selected-media-species-tag--october-18-2026):
overlay the saved snapshot common name on selected media, styled like the
Explore feed's top-leading rounded translucent material pill with semibold text
in
[`ExplorePostCard.speciesOverlay`](../../../apps/ios/Merian/Features/Explore/Feed/Components/Cards/ExplorePostCard.swift).
Hide the tag when deselected; exclude it and menu controls from exports. Keep
the selected object's menu button visible and avoid covering playback or
manipulation controls. Show details opens fuller metadata. Missing-name
fallback, zoom/rotation handling, and exact spacing need design. The tag is
editor UI and does not add permanent metadata text to the composition.

Saving selected Field Chat text preserves the selected excerpt and AI
attribution. Explore references retain author/source attribution. The complete
originating conversation or post should not be silently copied into a pin.

## Media selection and playback

Confirmed under [J-18](decisions.md#confirmed-v1-media-scope--october-18-2026):

- Photos are individually selectable, including within a multi-photo scan. Each
  selected photo follows the existing Pin and independent page-copy model.
- Audio plays within Journal, with playback controls and duration alongside the
  existing spectrograph/waveform visual selected in
  [J-17](decisions.md#confirmed-audio-visual--october-18-2026). Locate the
  existing visual owner and validate reuse during engineering planning.
- Video shows a poster image and play action; tap to open playback, without
  autoplay. Exact player presentation remains open.

The shared picker includes media, with attached metadata and no Field Notes or
metadata checkboxes. Defaults under
[J-30](decisions.md#confirmed-media-picker-defaults--october-18-2026):

| Entry context                         | Initial selection                     |
| ------------------------------------- | ------------------------------------- |
| Current media item known              | That item, adjustable before saving   |
| Multiple items, none currently viewed | Nothing selected                      |
| One available item                    | Sole item selected in the same picker |

Show checkmarks and a count; disable saving at zero. Audio/video preview does
not change selection. Cancel saves nothing. Choose a destination afterward under
J-29, unless already inserting into an open page.

Exact layout, no eligible media, availability changes, and stack controls remain
open. Media limits, download mechanics, and playback/arrangement gestures need
qualification. Playback does not imply trimming or other media editing. Offline
availability follows J-20; static audio/video export follows J-22.

## Source snapshots and deliberate updates

Confirmed under
[J-16](decisions.md#confirmed-source-snapshots-and-deliberate-updates--october-18-2026):
save the selected material as a snapshot. Reidentifying a scan does not change
the saved image or attached species metadata; editing an Explore post does not
change saved excerpts/images. Field Notes import is excluded under J-24. Opening
the source shows its current state, while saved material retains provenance to
the source version used.

The user can preview newer source material and deliberately update a selected
Pin or page copy. A Pin update affects future placements only; a page-copy
update affects only that copy. Exact controls, handling of local edits,
layout/crop preservation, and Undo remain design questions. Source withdrawal
and deletion still follow J-14/J-15 below; snapshots do not prevent required
removal or fallback substitution.

## Deleted-source image fallback

Confirmed direction under
[J-14](decisions.md#confirmed-fallback-image-direction--october-18-2026): for a
deleted or withdrawn Explore source, try a fallback image from Naturebook,
Wikipedia, or GBIF before showing an unavailable-image placeholder. Provider
priority is not decided.

Preserve the object's position and dimensions and the user's surrounding
writing/drawings. Use an image matching the referenced species with its own
attribution tag. No special replacement or Representative image label is needed.
Keep the original source's unavailable status distinct from the replacement
image's source. If no suitable image with the needed permissions is available,
show the placeholder. Offline lookup, export eligibility, and matching when the
species is uncertain still require qualification.

## Source deletion

Confirmed under
[J-15](decisions.md#confirmed-source-deletion-policy--october-18-2026):

- Deleting the user's own scan keeps deliberately saved Journal material by
  default. When copies exist, explain "Material saved to Journal will remain."
  Show Original scan deleted in source status and remove the open-source action.
- Offer **Delete scan and remove saved Journal content** as a separate
  deliberate action. Show affected Pins/pages before confirmation; remove
  source-derived content while preserving independent annotations and drawings.
- Deleting a Field Chat conversation leaves deliberately saved excerpts and AI
  attribution intact, with the original conversation unavailable.
- A deleted or withdrawn Explore post loses its original image and saved source
  text in Pins/page copies once the app learns of withdrawal. Try the fallback
  above for its image. Preserve personal annotations and layout, and exclude
  withdrawn content from future exports.
- A disappeared external webpage leaves explicitly saved excerpts/images,
  attribution, and the original link intact. Mark the link unavailable when
  known. Temporary loading failures do not trigger deletion behavior.

These flows do not settle account deletion or explicit erasure procedures.
Offline propagation and distinguishing source-derived content from personal
annotations remain engineering-planning requirements.

## Expanding canvas and drawing

Each named page expands spatially. Confirmed under
[J-19](decisions.md#confirmed-canvas-interaction-and-editing-tools--october-18-2026):

- Arrange mode: drag empty space to pan, tap an object to select it, then move,
  resize, or rotate it. Pinch to zoom.
- Draw mode: one finger draws, two fingers navigate, and Done returns to
  arranging. Tools include pen, pencil, highlighter, eraser, color, and stroke
  width.
- Tap Text to insert a text box; double-tap existing text to edit it.
- Media uses an explicit play control distinct from object selection/movement.
- Fit all shows the whole composition. Reopening restores the previous viewport.
- Shared Undo/Redo covers drawing and object edits; autosave preserves accepted
  changes.
- Provide accessible controls for positioning, resizing, and other actions
  beyond gestures.

Proposed details: place new material visibly without unnecessarily covering
existing content, keep ink in canvas coordinates during navigation, and group
creation controls into Draw, Text/Notes, and Insert (Pins, photos, stickers,
references). Exact toolbar layout, ink selection, keyboard/sheet gestures,
resource limits, and Undo history lifetime require design/prototype validation.
Smart connectors, shape recognition, and grouping are separate enhancements.

Autosave and Undo/Redo are approved requirements. Their persistence mechanics,
interruption recovery, and large-canvas performance remain engineering-planning
and acceptance concerns; J-20 below establishes offline and sync behavior.

## Offline editing and account sync

Confirmed under
[J-20](decisions.md#confirmed-offline-editing-and-account-sync--october-18-2026):

- Allow page creation/editing, drawing, and reuse of downloaded Pins offline.
  Save accepted changes immediately on the device.
- Sync automatically to the signed-in account when connected. Distinguish Saved
  on this device from Synced, keep routine status quiet, and show clear errors
  when action is needed.
- Keep saved photos available offline; offer separate Download for offline use
  controls and download status for audio/video. Pending downloads and storage
  limits need further design.
- Safely merge edits to different objects where possible. Preserve both versions
  of conflicting same-content edits for review, without silently losing either
  edit.
- Before sign-out, identify unsynced work and warn the user. Preserve account
  isolation. Exact sign-out choices and recovery behavior remain open.

Conflict review UI, deletion-versus-edit conflicts, guest transitions, download
retention, and recovery mechanics require further planning. Source withdrawal
and explicit removal still follow J-14/J-15; keeping conflicting edits must not
restore withdrawn source material.

## Search

The working navigation offers Scans, Collections, and Journal scopes. Journal
shows separate Pages and Pins result sections with View all. Expanded Pages or
Pins uses a full grid with an editable bottom search field and result count; the
keyboard stays hidden on entry until the user focuses the field.

Confirmed under
[J-21](decisions.md#confirmed-search-scope-and-query-behavior--october-18-2026):
search page titles, typed text, saved excerpts, captions, and species/reference
names. Pins are independently searchable, including those already used on pages.
A page matches only material placed on it; do not automatically index entire
source conversations or posts. Rank title/name matches ahead of content matches,
with recent editing as a tie-breaker. Search locally available content offline,
including unsynced edits. Handwriting recognition, text recognition inside
images, and semantic image/audio search are deferred beyond v1.

Show a matching excerpt and open the page near its relevant object. Pages and
Pins share the query; preserve it while navigating within search. Close search
to clear the query. Empty search shows recently opened Pages/Pins; clearing the
query in an expanded grid shows all items of that type without closing search.

Proposed presentation details: show page titles and Pin sources, return from
detail to preserved results/viewport, and search while typing. Keyboard and
sheet interactions below still require prototype validation; expanded Back,
bottom X, inline clear, and query-lifetime behavior are confirmed by J-21.

| Action                                 | Result                                                                   | Authority                                                  |
| -------------------------------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------- |
| Change Scans/Collections/Journal scope | Keep query and keyboard state                                            | Proposed cross-scope presentation                          |
| Root search Back or bottom close X     | Exit search, clear query, restore originating Book view                  | Closing/clearing confirmed; root Back/restoration proposed |
| View all for Pages or Pins             | Narrow the same search session to that result type                       | Working presentation; shared query confirmed               |
| Expanded results Back                  | Return to combined Journal results with current query                    | Confirmed J-21                                             |
| Expanded results bottom close X        | Exit entire search session and clear query                               | Confirmed J-21                                             |
| Inline clear inside populated field    | Clear text without closing; expanded results show all items of that type | Confirmed J-21                                             |
| Dismiss keyboard                       | Keep search/results open                                                 | Proposed native interaction                                |
| Drag Book sheet down                   | Dismiss Book to capture; closing search clears query                     | Dismissal proposed; clear-on-close confirmed               |

Recent-item history controls, no-match presentation, exact matching rules, index
maintenance, and source-removal propagation remain open. Root and expanded
close-X implementation needs hands-on native validation to fulfill the confirmed
behavior. Indexes must honor account isolation and source withdrawal.

## Export

Confirmed under [J-22](decisions.md#confirmed-v1-page-export--october-18-2026):

1. Choose Image or PDF and All content or Selected area.
2. Preview the selected visible composition, showing the resulting scale for a
   large canvas. Preserve source credits, including fallback-image attribution.
3. Render audio/video as static waveform/spectrograph or poster visuals, without
   playback controls. Flag missing media so the user can download it or
   knowingly continue with a placeholder. Withdrawn content stays excluded under
   J-14/J-15.
4. Exclude hidden location metadata and private source links. Private imagery or
   locations visibly written on the page remain part of the selected composition
   and must appear in the preview.
5. Export, then present the system share sheet. No automatic public upload or
   public scan URL is created.

Automatic multi-page tiling is deferred unless later review establishes it as
essential. Image encoding, resolution/size limits, PDF sizing, preview/credit
layout and permissions require further qualification. This core Image/PDF export
is included on Free under J-23. Playable audio/video export is outside this
approved v1 export scope.

## Free/Pro and downgrade

Confirmed under
[J-23](decisions.md#confirmed-free-core-and-pro-enhancements--october-18-2026):
keep the complete Journal core on Free, with sync within a storage allowance;
Pro adds storage and optional creative enhancements. Preserve existing pages and
placed premium assets after downgrade, including editing and export.

When above the Free storage allowance, keep access/export and local editing
available and clearly distinguish unsynced changes. Additional cloud uploads
require freeing space or upgrading. Exact storage accounting, reconciliation and
deletion operations, and recovery UI remain open, as do allowances, pricing, and
the paid catalog. Use storage rather than a small page-count cap as the
monetization boundary.
