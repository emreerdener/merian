# Journal roadmap and open questions

Status: paused by the user on October 27, 2026. The sequence below is retained
for a future resumption, not authorized implementation or a release schedule.
The [decision log](decisions.md) owns confirmed choices; the [brief](brief.md)
summarizes the current scope. Settled decisions are not reopened below.

## Proposed sequence

1. **Prototype the core journey.** Follow the
   [prototype plan](prototype-plan.md) using synthetic content and the updated
   visual references. Resolve page creation, multi-item placement,
   selected-object controls, and details through concrete interactions. Storage
   pricing and production architecture need not block this design pass.
2. **Review and record.** Walk through the scenarios, distinguish observed
   problems from preferences, and record accepted changes in the decision log.
   Keep untested recovery behavior and native gestures visibly outstanding.
3. **Qualify native interaction and engineering feasibility.** Inspect current
   source owners before selecting reusable components, persistence, sync, media
   ownership, or API contracts. Plan focused native checks for gestures,
   drawing, accessibility, and playback. Follow relevant Merian skills and
   coordinate with active capture/history/media work before overlapping changes.
4. **Plan an implementation slice.** Proposed slice: choose scan media, save a
   Pin, place an independent copy, edit text/ink, save locally across restart,
   reopen an authorized source, and retrieve it with search. Sequence cloud
   sync, other sources, withdrawal, and export only after their dependencies are
   understood. Request implementation separately from this planning work.
5. **Qualify the complete v1.** Carry the acceptance scenarios below into the
   engineering plan and applicable repository/device gates. A successful
   prototype is not evidence of sync durability, privacy, or release readiness.

## Product questions for prototype review

| Topic                     | Remaining question                                                                                                                                       | Review stage                                            |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| Page lifecycle            | How are blank/populated pages named, renamed, duplicated, deleted, and recovered? What happens when creation is cancelled?                               | Core journey first; destructive/recovery states second  |
| Multi-item composition    | Where do selected items land? How are overlapping items selected and separated? Is a stack only a visual arrangement or a distinct saved grouping?       | Core journey; independent movement is already confirmed |
| Selected object           | Handle/menu placement, missing common name, rotated/small objects, credit placement, and playback hit targets                                            | Photo, video, and audio states                          |
| Details and source access | Which saved metadata fields appear, how is location treated, and how does authorized source navigation appear?                                           | Details sheet and unavailable-source variants           |
| Source entry              | Exact picker presentation, no eligible media, availability changes during selection, recent-page ordering, Field Chat entry, and additional import scope | Shared picker plus source-specific variants             |
| Deliberate updates        | How are changes previewed while preserving local edits, crop/layout, and an understandable Undo action?                                                  | State walkthrough                                       |
| Canvas tools              | Toolbar, ink selection, overlapping layers, accessible manipulation, keyboard/sheet behavior, and Undo history lifetime                                  | Browser walkthrough, then native checks                 |
| Search                    | No-match presentation, recent-history controls, filters/category browsing, and keyboard/sheet transitions                                                | Search walkthrough                                      |
| Recovery                  | Conflict review, unsynced sign-out choices, downloads, storage-limit messaging, and unavailable media                                                    | Simulated states, followed by engineering qualification |
| Export                    | Selected-area interaction, preview scale, credit placement, and missing-media continuation                                                               | Export-preview walkthrough                              |

Picker defaults, multi-selection, media-before-destination order, no Field Notes
import, snapshot behavior, and the Free/Pro core boundary are already settled.
The latest gallery controls are a visual baseline, not approved filter
semantics. Do not silently resolve remaining questions through mock data or
schema choices.

## Engineering and commercial qualification

| Area                       | Evidence needed before implementation commitments                                                                                                                                               |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Local persistence and sync | Object/version ownership, immediate-save durability, migrations, account isolation, merge rules, conflict preservation, sign-out recovery, guest transitions, and deletion-versus-edit handling |
| Source retention           | Provenance/version identity, annotation/source separation, withdrawal propagation through offline devices/search/previews/exports, explicit removal, and separate account-erasure integration   |
| Fallback images            | Provider access and selection rules, uncertain-species matching, reuse/export permissions, attribution, and offline reconciliation; the provider list is not a priority order                   |
| Media and canvas           | Existing spectrogram/player/drawing owners, download retention, attachment and page limits, memory/rendering performance, and native gesture/accessibility behavior                             |
| Search                     | Matching/tokenization, ranking, index maintenance, local unsynced content, removal propagation, and account isolation                                                                           |
| Export                     | Image encoding/resolution, PDF sizing, metadata stripping, source permissions, output limits, and native sharing                                                                                |
| Free/Pro                   | Measured storage costs, allowances/accounting, optional paid catalog, prices, over-limit upload/reconciliation rules, and downgrade recovery                                                    |

J-23 preserves access, local editing, and export after downgrade, including
placed premium assets. Use storage rather than a small page-count cap as the
boundary. Do not invent allowances or prices in the prototype. Reusing received
Field Chat text must not bypass the separate policy for generating new answers.

## Acceptance scenarios to carry into implementation planning

- Exercise current-item, multiple-item/no-current-item, and sole-item picker
  defaults. Verify checkmarks/count, disabled saving for zero selection,
  playback preview without selection changes, and cancel without saved material.

- Save a reference to Pins without leaving the source; place it directly on an
  existing/new page; reuse it without unintended source duplication.
- Select media before choosing Save to Pins or Add to page. Verify New page,
  recent-page selection, and all-page search; insertion from an open page skips
  destination selection. Confirm in place with View without automatic
  navigation.
- Reuse an existing Pin for unchanged material. Edit a page copy without
  changing the Pin or other placements; edit a Pin without changing existing
  placements. Remove a placement without deleting its Pin or source. Delete from
  Pins with Undo while preserving page copies and attribution. Verify
  page-created material becomes a Pin only through an explicit save action.
- Add text, image, sticker, and ink; move/resize/rotate applicable objects;
  undo/redo; navigate a large canvas and return to all content.
- Verify Arrange/Draw transitions, one-finger drawing and two-finger navigation,
  text insertion/editing, explicit media play controls, all approved drawing
  tools, Fit all, and restored viewport. Exercise shared Undo/Redo across ink
  and object edits, autosave of accepted changes, and accessible positioning,
  resizing, and tool actions without relying only on gestures.
- Select individual photos from a multi-photo scan. Play audio within Journal
  using the existing spectrograph/waveform visual with controls and duration;
  tap a video poster to play, with no autoplay. Verify reuse, snapshot, and
  source-deletion behavior for supported media.
- Add scan media without a metadata-selection form or Field Notes import.
- Select media through the shared view for personal scans, Explore posts, and
  Species Dictionary pages. Verify Save to Pins and direct page placement
  include only chosen items, with metadata/provenance and no Field Notes.
  Preselect the currently viewed item when identifiable and allow changes to
  that selection before saving. Do not automatically import all source media.
  Arrange stack items individually, access attached metadata on demand without
  permanent metadata text on the canvas, and preserve snapshot behavior. Verify
  attached hidden metadata/private links remain excluded from exports.
- Select media and verify the object-menu entry point is visible and accessible.
  Show details opens saved metadata; selection alone neither opens details nor
  starts playback. Explicit audio/video controls remain usable.
- Show the saved common-name tag with the Explore-style treatment only while
  media is selected. Verify deselection hides it and exports omit both the tag
  and menu controls without removing required source attribution.
- Keep saved images, species labels, and excerpts stable across source edits or
  reidentification, while opening the source shows its current state. Preview
  and deliberately update a selected Pin or page copy with version provenance;
  verify Pin updates affect only future placements and page-copy updates affect
  only that copy. Apply deletion/withdrawal rules despite snapshot retention.
- Preserve accepted edits across keyboard changes, app backgrounding, restart,
  weak connectivity, and relevant account transitions.
- Create/edit/draw offline and reuse downloaded Pins; distinguish immediate
  local saving from completed automatic sync. Verify saved-photo offline access
  and separate audio/video download controls/status. Safely merge separate
  object edits, preserve conflicting same-content versions for review, and warn
  about unsynced work before sign-out while keeping accounts isolated. Conflict
  recovery must not reintroduce withdrawn source content.
- Search titles, typed text, placed excerpts, and reference labels; show why a
  result matched and navigate to it; preserve query on back navigation.
- Search captions and independently saved/placed Pins. Rank title/name matches
  ahead of content matches, then use recent editing for ties. Verify offline
  results include locally available unsynced edits, empty search shows recently
  opened Pages/Pins, inline clear in expanded grids shows all items, and closing
  search clears the query. Source withdrawal/removal and account isolation must
  also apply to search results.
- Keep private source navigation owner-only. Saving must not publish; exporting
  must reflect the user's explicit selected content and attribution policy.
- Export Image/PDF with All content and Selected area previews, clear scale,
  preserved credits, and static waveform/poster visuals without play controls.
  Flag missing media before export and support download or deliberate
  placeholder continuation. Verify hidden location metadata/private source links
  and withdrawn content are excluded, while visible written locations match the
  preview. Present the system share sheet without automatic public upload or
  creation of public scan URLs.
- Handle deleted/inaccessible sources according to the approved policy without
  losing unrelated user writing or restoring removed private content.
- Retain saved material after ordinary own-scan or Field Chat deletion; preview
  and remove scan-derived Journal material only for the separate explicit
  removal action. Withdraw Explore images/text and try a species-matched
  fallback with its own attribution tag and no replacement label. Preserve
  layout and personal annotations; exclude withdrawn material from future
  exports. Verify missing external pages retain saved content and temporary
  network failures never trigger destructive deletion.
- Provide VoiceOver and large-text support, accessible drawing/editing controls,
  and alternatives to gesture-only manipulation.
- Verify the complete core on Free and Pro's additional storage/creative
  entitlements once specified. After downgrade, preserve existing pages and
  placed premium assets with editing/export. Above the Free storage allowance,
  retain local editing/access/export, identify unsynced changes, and apply the
  upload restriction without blocking the ability to free space. Exact
  allowances and accounting still need approval and validation.

Success signals to define include pin-to-page use, repeat page editing, source
revisits, and successful retrieval. These are measurement ideas, not a request
to add analytics. Any telemetry must follow existing consent and privacy rules
and must not collect note text, queries, drawings, or source content.
