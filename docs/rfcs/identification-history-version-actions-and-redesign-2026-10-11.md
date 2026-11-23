## November 14 — audio/video shared-workspace integration update

Single audio and video submissions now use the shared toolbar through their
existing durable source hosts. Protected original-media loading uses immutable
manifest membership; a video and its derived frames/sound remain one item.
Source identity supports completed V1–V5 results independently of new media
type.

The schema-5 native preparation layer now represents one held whole-composition
child, but is not connected to Capture or backend execution. Mixed submission,
coordinated backend runtime/cleanup and result-reader support remain open. The
pending isolated backend release does not enable this new lane. Current details
are in the
[shared Capture contract](../features-and-hardware/29-staged-capture-review.md#history-reanalysis-integration-status);
earlier checkpoints below retain their historical status.

> Current planning authority: the
> [November 13 UI/UX decisions](#november-13-2026--approved-uiux-scope) below
> supersede conflicting October requirements. They record intended work, not
> implemented, validated, or released behavior. The earlier decisions and
> qualification records remain historical evidence.

> October 31 qualification update:
> [current simulator qualification](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md#october-31--simulator-qualification-after-component-repair)
> records repaired simulator execution, populated-store migration and selected
> native/network results. It also retains pending fixture coverage and the
> measured native-audit performance gap. This does not close journey/RUX
> acceptance, activate features or change the approved milestone sequence.

> October 16 integration boundary: PR116 feature scope is frozen at the
> committed inactive foundation. The
> [merge-readiness proposal](identification-history-pr116-merge-readiness-2026-10-16.md)
> separates source integration from activation and this later roadmap. No
> version deletion/export or redesign is added to PR116; the sequence below
> remains required after current-scope acceptance. Capture-tools/Add details
> ownership remains separate. No push, merge or deployment is authorized.

<!-- Approved user plan transcribed from planning thread 01a12460-a2c6-7b21-abcf-d3be41331b45, October 11, 2026. -->

# Identification and History: version actions and UX redesign

## November 13, 2026 — approved UI/UX scope

Source: explicit action-by-action decisions in the
[History app UI/UX chat](codex://threads/01a0fe55-d9d3-77e0-90a5-b7eeeaaa74e1).
The user authorized recording these decisions in the existing roadmap. Supplied
screenshots establish the discussed layout; the
[Figma reference](https://www.figma.com/design/AVATuIm6rP8wxiYAJg1qGa/Merian?node-id=2555-12058)
is retained for the detailed design pass, not claimed as independently inspected
by this update.

Status: approved product direction; implementation and acceptance remain
outstanding for the changed behavior. This chat now scopes app UI/UX, beginning
with the Insights menu. PR consolidation has a separate owner. Automatic prompts
remain paused. This record authorizes no publication, deployment, installation,
data deletion, or change to existing stored media.

### Insights menu

Use this order:

1. Two prominent shortcuts: **Identification** and **Field notes**.
2. **Add to collection**.
3. **Download media**.
4. A conditional **Explore post** section.
5. **Delete scan**, separated at the bottom.

**Identification** is the redesigned Confidence sheet, not a second explanation
destination. Both the confidence badge and this shortcut open it. Preserve the
content already in the Confidence sheet and refactor it to incorporate the
identification and History elements. There is no direct History entry in the
main Insights menu.

Content order is the identification summary and slide-to-confirm review
controls, then the existing alternatives card, then the existing confidence
explanation, model information and tips. Retain all existing Confidence-sheet
content and its applicable conditional states.

**Field notes** always uses that label and opens the existing saved-scan notes
editor. **Add to collection** keeps its existing label and behavior, including
multiple memberships and creation of a collection.

**Download media** targets the identification currently displayed, excludes
reference images, and offers a chooser for multiple items. The source-original,
authorized-delivery, missing-original and cleanup requirements in the original
download milestone remain applicable. A label change alone does not implement
original-media export.

Show **View post** and **Edit post** in the Explore post section only when a
linked post exists; editing is available to the owner. Move **Boost audio** out
of this menu into the audio player.

**Delete scan** deletes the whole scan, all identification versions and
associated media, with a clear confirmation explaining that scope.
Single-identification deletion belongs in History and retains the
surviving-owner media protection below.

### Identification and History presentation

The Identification overflow menu contains **Identification history**, **Ask the
community**, and **Reanalyze species**, in that order. When a community request
already exists, replace Ask the community with **View community request** and
open that request.

Preserve the existing slide-to-confirm interaction for confirming or marking an
identification incorrect, including the existing way to correct a choice. Do not
introduce an additional Undo button or a new reversal flow merely because the
interim implementation has one. Detailed reversal presentation has not been
newly specified; existing correctness and receipt protections remain.

History opens within the same sheet. **Back** returns to Identification; closing
the sheet returns to Insights. Keep interaction within the History card stack:
no separate full identification preview is required for an older card. **Use
identification** explicitly makes that card current.

Pin the current identification at the top, with remaining versions newest first.
The current card is expanded with review controls; older cards stay compact with
actions in their menus. Move the expanded controls when the current
identification changes. Preserve all existing Confidence-sheet content in the
Identification destination; the simplified History interaction does not remove
that content.

Confirming or marking an older identification incorrect affects only that
version. It does not make it current; **Use identification** owns that change.

### Reanalysis through the shared media toolbar

Use the existing reanalysis staging and shared media toolbar on the **Capture
workspace**, not a new standalone editor. Open it with the displayed
identification's submitted photo, audio or video media and its originally
submitted notes. Allow editing those notes in the new draft; do not substitute
the scan's latest editable Field notes. Editing the draft does not change the
source version. Reanalysis from an older History card uses that card's submitted
media and notes.

Use **Reanalyze** for explicit reanalysis submission and **Identify** for a new
scan. Opening or editing never starts analysis. After submission, return to the
existing identification and show progress there while keeping its result
visible.

On successful reanalysis, make the new identification current automatically and
preserve existing versions. The user can subsequently choose another version in
History. This also applies if the user selects an older identification while the
reanalysis is running: the successful new result still becomes current. On
failure, retain the existing current identification and show the failure and
appropriate recovery action in the progress area. Recovery must retain
exact-operation identity and must not silently repeat uncertain AI work.

This is an intended behavior change where existing completion currently only
appends a version. It requires reconciliation with the authoritative completion
and selection contracts; this planning update does not change them. User
selection during an in-flight reanalysis is resolved above; account changes,
deletion, uncertain completion and competing operations still require the
existing authority checks and explicit integration treatment. Reuse the existing
capture/media owners rather than adding a second staging, submission or
persistence implementation.

While reanalysis is running, replace its Reanalyze action with **View reanalysis
progress** in that scan's Identification and History menus. Open the existing
progress area instead of starting another reanalysis.

### Individual-identification deletion

Allow deletion of the current identification when other versions exist. The
confirmation explains that the newest remaining identification becomes current.
Commit deletion and replacement of the current selection as one coordinated,
revision-checked operation; interrupted responses must not leave an observation
without a current identification. This supersedes the requirement to select a
different version manually before deletion.

If there is only one identification, use **Delete scan** instead of individual
deletion. Deleting an older version remains permitted, including a source of
later versions. Preserve surviving versions, scan notes, collections,
observation identity and media still needed by surviving owners. Permanent
version deletion has no Undo. Existing publication consequences, authorization,
connectivity, idempotency, unresolved-operation and anti-resurrection
requirements remain.

### Updated acceptance and remaining scope

- Replace the old current-version rejection check with deletion plus automatic
  newest-survivor selection, including uncertain responses, stale revisions and
  concurrent selection/reanalysis. Continue rejecting individual last-version
  deletion and verify whole-scan deletion remains distinct.
- Verify current-first ordering and movement of expanded controls; older-card
  actions target their exact version without requiring a separate preview.
- Verify both Identification entry points, retained Confidence-sheet content,
  same-sheet History navigation, menu grouping, conditional community/Explore
  actions, existing review correction behavior and accessible slider controls.
- Verify displayed-version media export and chooser behavior without reference
  images or substitution of missing originals; retain all-media export checks.
- Verify shared-toolbar reanalysis across photo/audio/video, original submitted
  notes, explicit submission, preserved versions, progress, automatic current
  selection on success and unchanged current selection on failure.
- Reconcile affected technical contracts and tests during implementation. Prior
  test evidence does not qualify these changed behaviors; unchanged valid
  evidence should be reused without unnecessary reruns.

The earlier requirement for a separate historical Identification detail view is
superseded by the card-stack scope. UI/UX planning now proceeds first as
requested; the older sequence is not a reason to block this planning. Detailed
delivery order, remaining visual states and shared-toolbar integration still
need to be resolved against the existing owners. Deletion/export and the
redesigned flows remain required engineering work; no acceptance requirement is
marked complete by this record. Notion summaries have not been updated by this
local change.

### Source mapping and Capture draft assessment — November 13

Read-only mapping against app checkout
`6b91a4cf654524da6e6a5a3e947bd35dd110c639`, including an independent read-only
trace of Capture routing. This is source evidence, not a simulator or phone
result. Only this roadmap is changed; existing app behavior, data and automatic
prompt settings are untouched. PR consolidation remains separately owned.

| Agreed surface                     | Existing implementation to reuse                                                                                                                                                                                                                                                                                                                                     | Required integration delta                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Insights menu                      | [TopToolbar.actionMenuContent](../../apps/ios/Merian/Features/Insights/Toolbars/TopToolbar/TopToolbar.swift), [Shell toolbar bindings](../../apps/ios/Merian/Features/Insights/Shell/Views/InsightSheetView+Toolbar.swift) and `AddCollectionTopMenu`                                                                                                                | Replace the flat scan/review action list with the agreed shortcuts and sections; preserve identity-bound action closures, Field notes and collection behavior. Existing community action selection and Explore visibility rules already provide useful seams.                                                                                                                                                                                                             |
| Identification destination         | [ConfidenceBadge](../../apps/ios/Merian/Features/Insights/IdentificationReview/Confidence/Views/ConfidenceBadge.swift), [ConfidenceExplanationSheet](../../apps/ios/Merian/Features/Insights/IdentificationReview/Confidence/Views/ConfidenceExplanationSheet.swift), its view model and `ConfidenceReviewControls`                                                  | Refactor the existing sheet, join the badge and menu entry points, retain conditional correction/rejection/candidate states, confidence spectrum, plan information and tips, and add the agreed summary/order/navigation. Reuse existing `SlideToConfirm`; the interim protected History review section currently uses buttons and is not evidence of the approved slider presentation.                                                                                   |
| History card stack                 | [IdentificationHistorySheet](../../apps/ios/Merian/Features/Insights/History/Views/IdentificationHistorySheet.swift), [IdentificationHistoryViewModel](../../apps/ios/Merian/Features/Insights/History/ViewModels/IdentificationHistoryViewModel.swift) and [Shell History host](../../apps/ios/Merian/Features/Insights/Shell/Views/InsightSheetView+History.swift) | Replace list-to-preview presentation with current-first cards and same-sheet navigation. Preserve paged reads, exact-version review/selection authority and acknowledgment handling. Current review/reanalysis actions are prepared by the model's preview command; removing the preview screen must retain that exact-version preparation internally for card actions. Ensure a current version outside the loaded page can be pinned without loading unbounded history. |
| Reanalysis entry and media staging | [Saved reanalysis entry](../../apps/ios/Merian/Features/Insights/Shell/Views/InsightSheetView+SavedReanalysis.swift), `SavedReanalysisHandoff`, historical handoff, [ActiveScanToolbar](../../apps/ios/Merian/Features/Capture/Staging/Components/Toolbar/ActiveScanToolbar.swift), `StagedCapture` and Capture Shell                                                | Preserve frozen source/account tickets, but adapt their presentation to the existing Capture workspace and media editors. Protected History currently uses a separate photo-only form; legacy refinement already uses the toolbar but is not a safe drop-in replacement. Keep protected submission/recovery ownership rather than falling back to legacy replacement/inference.                                                                                           |
| Submit labels and progress         | [CaptureStagingToolbarPresentation](../../apps/ios/Merian/Features/Capture/Staging/Models/CaptureStagingToolbarPresentation.swift), [Reanalysis status host](../../apps/ios/Merian/Features/Insights/Shell/Views/InsightSheetView+ReanalysisStatus.swift), `ReanalysisStatusViewModel`                                                                               | Current toolbar refinement copy is **Analyze**, requiring **Reanalyze**. Adapt the existing status/recovery model to the Identification progress area and running-state menu action. Automatic selection of successful results is a completion/selection behavior change, not a cosmetic menu change.                                                                                                                                                                     |
| Version-specific downloads         | [Insight media export](../../apps/ios/Merian/Features/Insights/Media/Utilities/InsightSheetViewModel+MediaExport.swift), [MediaExportService](../../apps/ios/Merian/Core/Media/MediaExportService.swift)                                                                                                                                                             | Current `saveUserMedia` builds photo/video requests from displayed media and can include a reference-image URL; `MediaSaveRequest` has no audio sources. This does not implement the agreed exact-version, reference-excluding original-media chooser. Reuse delivery/export services only where their ownership and source semantics match the planned all-media capability.                                                                                             |
| Audio boost                        | [AudioPlaybackCarouselPage](../../apps/ios/Merian/Core/UI/Components/MediaCarousel/AudioPlayback/AudioPlaybackCarouselPage.swift), audio playback presentation/policy, `InsightAudioBoostPreferenceStore` and existing Shell bindings                                                                                                                                | Reuse the existing player boost control and preference/effect ownership; remove the redundant menu control. Do not introduce a second audio player or mutate submitted audio.                                                                                                                                                                                                                                                                                             |
| Individual-version deletion        | Original deletion milestone below and existing History action/session boundaries                                                                                                                                                                                                                                                                                     | Remains a capability requiring backend/native implementation and validation. Add the approved current-version deletion plus newest-survivor selection; menu rendering cannot substitute for that operation. Keep whole-scan deletion distinct.                                                                                                                                                                                                                            |

#### What happens to an unfinished Capture draft today

The two route handlers have different behavior if invoked with staged content.
The original trace did not establish that a user can reach reanalysis from
another unfinished capture through normal navigation; it must not be read as
proof of that user journey.

- **Protected saved/History route:** `PreparedHistoryReanalysisComposition`
  dispatches `historicalReanalysis`; `CaptureWorkspaceViewModel.apply` in
  `+Routing.swift` opens a separate `CaptureReanalysisEditor` and
  `CaptureReanalysisSheet`. This branch does not clear `stagedCapture`; any
  preexisting workspace draft would remain underneath. The form has
  original-photo selection, photo import and notes, rather than the shared
  all-media workspace toolbar.
- **Legacy refinement route:** `refinement` reaches `startRefinementScan` in
  `CaptureWorkspaceViewModel+Refinement.swift`. Its admission checks include
  native-photo composition, mutation locks and library access, but an ordinary
  editable staged draft is not itself a mutation lock. After admission,
  `startRefinementScan(with:)` calls
  `clearStagedCaptureAndCropState(discardStagedMediaFiles: true)` before loading
  the historical media. This clears that draft's media and notes and schedules
  disposal of its draft-owned files. There is no nonempty-draft-specific
  confirmation at this boundary.
- **Route deferral:** an occupied feature presentation can defer a route; an
  unfinished staged draft alone is not such a presentation. Presentation
  deferral therefore does not establish draft protection.

Trace owners:
[routing](../../apps/ios/Merian/Features/Capture/Shell/ViewModels/CaptureWorkspaceViewModel+Routing.swift),
[refinement](../../apps/ios/Merian/Features/Capture/Shell/ViewModels/CaptureWorkspaceViewModel+Refinement.swift),
[draft locks](../../apps/ios/Merian/Features/Capture/Shell/ViewModels/CaptureWorkspaceViewModel+Draft.swift),
[separate protected editor](../../apps/ios/Merian/Features/Capture/Shell/ViewModels/CaptureReanalysisEditor.swift),
and
[separate protected sheet](../../apps/ios/Merian/Features/Capture/Shell/Views/Reanalysis/CaptureReanalysisSheet.swift).

**Required preservation boundary:** moving protected reanalysis into the Capture
workspace must not silently replace or delete another draft or its files/notes.
Do not route it through the legacy clearing path unchanged. No test asserting
this unfinished-draft handoff protection was located in the focused source/test
trace; no runtime reproduction or data-changing action was performed.

**User clarification — contained capture/review flow:** the supplied designs
keep users within the current analysis or reanalysis preparation flow until
submission or explicit discard; they should not open another saved Insight from
that state. The media toolbar replaces normal navigation. Current source also
switches between `MainTabBar` and `ActiveScanToolbar` in
[`CaptureWorkspaceView`](../../apps/ios/Merian/Features/Capture/Shell/Views/CaptureWorkspaceView.swift)
using `shouldPresentActiveScanToolbar`; staged content or refinement selects the
latter when its existing presentation guards allow it.

The earlier proposed draft-conflict prompt is withdrawn. No extra product
decision, draft parking/restoration or multi-draft manager is required for this
scope. Preserve the contained navigation and existing explicit discard behavior.
Verify route/lifecycle guards during the shared-toolbar integration so an
unexpected incoming route cannot silently replace staged content; do not infer
that such a route is normally reachable or add a user-facing flow without
evidence. Existing admitted-work protections remain applicable.

#### November 14 — preserve the existing media-toolbar composition

The user confirmed that reanalysis must preserve the existing Capture toolbar
experience: initialize it from the displayed identification's submitted media
and notes, allow removing any staged item and adding replacement photos, audio
or video using the existing controls, and submit only on **Reanalyze**. Do not
introduce a restriction that locks reanalysis to its source media type. Preserve
the existing composition rules rather than inventing a new media-selection UI.

The shared presentation must retain exact source-version identity and the
protected durable child/retry owners. The current separate photo/audio/video
submission implementations are integration dependencies, not a reason to reduce
the approved UX or fall back to legacy replacement. Preloading and editing must
not submit, select a version or overwrite the original result. Preserve the
earlier contained-flow and unexpected-route draft safeguards above.

The protected photo route now opens the shared Capture workspace and media
toolbar. It preloads verified source content, retains the exact source/account,
and returns to the existing identification after explicit submission or discard.
Staging bypasses ordinary new-scan quota checks; History owns submission
funding. Failed frozen requests retain their original content and identity for
retry, while editing remains locked. Audio/video and mixed-media submission
adapters remain incomplete; this photo integration does not qualify the full
approved all-media experience. Automatic prompts remain paused.

The integration trace distinguishes the final input from its source version: the
existing photo child backend can reference an immutable V4 audio or V5 video
result, but native source capture, preparation and recovery gates must agree
before that conversion is exposed. Audio currently accepts one prepared WAV with
notes; video accepts one locally retained clip graph with notes. Neither is an
adapter for the toolbar's general mixed-media timeline. Complete the required
protected submission/materialization/recovery support instead of silently
dropping staged items, splitting one submission into multiple children, or
reverting to legacy scan replacement. Preserve existing media-slot policies.

The new preload helper commits the whole verified source composition or none,
retains exact submitted notes, and stops on failed retained-media discovery. A
source without immutable original photos returns to the saved identification
with an explanation; missing legacy media recovery remains unresolved. The
photo-specific handoff rejects foreign source lineage before replacing its
staged value and retains the existing final-submit freeze. The photo workspace
route uses these helpers; they do not establish that audio/video/mixed
submission is connected. The existing toolbar now uses **Reanalyze** for
reanalysis and **Identify** for a new scan, with matching accessibility hints
and tooltip copy.

#### Implementation sequence and applicable verification

1. Deliver the agreed menu and refactor the existing Confidence sheet into
   Identification, retaining its content and action owners. Add the shared
   navigation boundary for History; preserve notes/collections/Explore actions.
2. Render the History card stack using the existing exact-version read/review/
   selection services. Keep review separate from current selection and adapt the
   existing slider components without adding a new Undo design requirement.
3. Integrate protected reanalysis with Capture's existing staging, media toolbar
   and editors while preserving the contained capture/review navigation. Retain
   original submitted media/notes, protected admission/recovery and
   account/source identity. Add progress presentation, running-state action
   substitution and the approved successful-result selection behavior.
4. Complete the existing all-media download and individual-deletion capabilities
   and connect their menu actions. They remain visible delivery dependencies,
   not features that can be claimed complete by presenting buttons.

This is a proposed implementation breakdown for the now-authorized mapping, not
new implementation/release approval or a claim that historical acceptance has
closed. Reuse applicable existing evidence; test changed boundaries as they are
implemented, then qualify the connected journey.

Existing test owners to adapt include `ConfidenceReviewPresentationTests`,
`ConfidencePresentationViewModelTests`, `IdentificationHistoryViewModelTests`,
`IdentificationHistoryReanalysisTests`, `SavedReanalysisHandoffTests`,
`ReanalysisStatusViewModelTests`, `CaptureWorkspaceRefinementTests`,
`CaptureWorkspaceRefinementDescriptionTests`, `CaptureDraftSessionTests`,
`CaptureReanalysisEditorTests`, `InsightMediaExportLifecycleTests` and
`MediaExportServiceTests`. These were identified, not rerun or claimed passing.
Add explicit unfinished-draft preservation coverage, card-action identity and
navigation coverage, exact-source all-media staging/export checks, and
completion selection after an intervening user selection. Keep the existing
deletion/shared-media and account/concurrency acceptance requirements.

## Original October plan and historical sequencing

The following records are preserved for provenance. Apply the November 13
decisions above wherever they conflict with the original plan.

## Summary and sequencing

October 18, 2026 (Chicago) scheduling addendum:
[unresolved-analysis recovery UX](unresolved-analysis-recovery-and-replacement-2026-10-18.md)
is part of current native integration acceptance and is reused by the redesign.
Its separately gated **Replace pending identification** milestone defaults to
following the deletion/export and redesign sequence below. It does not block or
reorder these milestones. Existing selection, review and permanent
version-deletion behavior is unchanged.

Use the supplied mockup as the target experience, delivered in this order:

1. Finish the current media-required identification-history and analysis-engine
   scope, including source-bound video reanalysis alongside photo/audio.
2. Add individual-version deletion and source-media download to the existing
   history experience.
3. Refactor the Confidence sheet into the Identification sheet and deliver the
   redesigned History page.

Document the new behavioral requirements now so ongoing work can account for
them. They do not automatically expand the current implementation milestone.

The history implementation chat remains the implementation owner. Approval and
handoff are recorded below. The user has authorized automatic continuation
through these milestones after current-scope acceptance, without routine proceed
confirmation. Each milestone still needs its own capability/evidence matrix,
implementation review and required qualification; external-operation permissions
remain unchanged. Completing the current IC-1 scope alone does not complete this
follow-up assignment.

## Milestone 1: deletion and media download

### Delete one identification

- Permanently delete one identification after an explicit confirmation. Preserve
  other versions, scan notes, collections, and observation identity.
- Require users to select another version before deleting the current one.
  Consequently, the last remaining version cannot be individually deleted;
  whole-scan deletion remains separate.
- Allow deletion of earlier versions, including the initial saved version, even
  when surviving versions were derived from them.
- Remove the deleted version’s private history content. Preserve minimal
  internal deletion/provenance records and media still required by surviving
  owners. Never cascade-delete later identifications.
- Use an authenticated, revision-checked, idempotent deletion operation.
  Synchronization, completion, recovery, and retries must not resurrect the
  version.
- Temporarily block deletion while conflicting operations remain unresolved,
  with an actionable explanation. Require connectivity to commit deletion;
  reconcile uncertain outcomes before retrying.
- If the version backs a community post, preserve the discussion and mark its
  identification unresolved under existing publication rules. Explain this
  consequence in the confirmation. Existing chat messages retain their
  established retention behavior; deletion must not silently rewrite
  conversations.

### Download source media

- Include photo, audio, and video support in this milestone. Text-only versions
  are historical records and have no download action unless they have associated
  retained source media. Fresh no-media identification is denied by the current
  media-required admission contract and is not an eligible version/download
  source.
- Export the retained source assets associated with the chosen version—not
  generated frames, thumbnails, or processing artifacts presented as originals.
- Support multiple source assets through a selection step. Use the system share
  sheet for export, including Save to Files and supported Photos destinations.
- Resolve media through owner-authorized delivery. Validate access and asset
  identity; never infer availability from a thumbnail.
- Preserve source assets required by live history under the existing observation
  retention contract. For older entries whose originals are missing, explain
  that they are unavailable; do not reconstruct substitutes.
- Provide progress, cancellation, retry, and temporary-file cleanup.

### Interfaces and storage

Add version-deletion operations and per-version action/export capabilities to
the existing history contracts, with corresponding native models. Capabilities
must express availability and refusal reasons.

Introduce the necessary deletion records and media-retention relationships
without weakening immutable result history. Update backend schemas, generated
DTOs, native persistence where required, and canonical documentation together.

## Milestone 2: Identification sheet and History redesign

### Insight-sheet menu

The user approved this additional menu presentation on October 11. Its durable
visual reference is
`.artifacts/identification-history-version-actions/insight-menu-reference.png`.
It belongs to Milestone 2 and does not reorder the milestones or expand the
active IC-1 checkpoint.

- Show two equal top shortcuts, icon above label: **Identification** on the left
  and **Field notes** on the right, followed by a divider.
- Show a full-width **Add to collection** row with its collection icon and a
  trailing submenu chevron, then **Download media** with a download icon.
- Place a divider immediately above the full-width destructive **Delete scan**
  row, whose label and trash icon are red.
- Use a rounded translucent menu over scan media, preserving label legibility
  over busy photos. A slightly more opaque backdrop is a design recommendation;
  no exact opacity value has been approved.
- **Identification** opens the redesigned Identification sheet. Field notes and
  Add to collection retain their existing flows; only their menu presentation
  changes.
- **Delete scan** remains whole-scan deletion, distinct from **Delete
  identification** in version history. Preserve its existing behavior and
  confirmation requirements.
- **Download media** uses the approved source-media export behavior, scoped to
  the scan/current identification context under established media ownership. It
  must not silently export another historical version.
- Preserve accessibility, Dynamic Type and native menu interaction behavior.
  Species-header, sharing, Field chat and other layout changes visible in the
  reference are context only, not additional implementation scope.

### Identification sheet

- Rename the Confidence sheet to **Identification**.
- Replace the large confidence heading with the sheet header, close control, and
  overflow menu shown in the design.
- Introduce a shared identification card containing confidence, current status,
  timestamp, thumbnail, and species names.
- Preserve the existing alternatives card layout and confidence-calculation
  policy.
- Show confirmation/incorrect states with revision-safe Undo.
- Use slide gestures for all four colored primary actions: **Confirm**, **Mark
  as incorrect**, **Reanalyze**, and **Ask the community**. Provide accessible
  activation alternatives.
- Sliding confirm/incorrect submits that review action. Sliding
  reanalyze/community opens the existing preparation flow; it does not bypass
  consent, editing, or publication steps.
- Show actions according to the viewed version’s supported capabilities. Video
  reanalysis is required by the October 12 current-scope decision and precedes
  this redesign. Video confirmation/review/community publication are not
  introduced by deletion/download or inferred from a V5 record.

### History page

- Open a separate History page from the Identification toolbar menu.
- Pin the current identification first; order remaining versions newest first.
- Reuse the identification card and provide per-version action menus.
- Tapping a card opens the same Identification layout scoped to that historical
  version, including its saved alternatives and explanations where available.
- Opening or confirming a historical version never makes it current. Provide a
  separate **Use this identification** action.
- Bind every action and asynchronous result to the exact observation, version,
  and account. Missing historical details must not be borrowed from the current
  result.
- Include loading, empty, unavailable-media, pending, conflict, and failure
  states.

## Validation and acceptance

- Delete an earlier version while preserving descendants, their media, and the
  current identification.
- Reject current/last-version deletion; verify deletion after an acknowledged
  selection change.
- Exercise duplicate requests, interrupted responses, stale revisions,
  concurrent selection/reanalysis, account switching, and late recovery after
  deletion.
- Verify community authority invalidation preserves discussion and cannot be
  reversed by stale jobs.
- Export retained photo, audio, and video sources; test multiple assets, missing
  originals, unauthorized access, cancellation, and cleanup.
- Verify historical details and review actions target the opened version;
  confirmation remains separate from selection.
- Verify the insight menu grouping, labels, destructive divider, readable
  backdrop and current-context media export; preserve existing field-notes and
  collection navigation and distinguish scan deletion from version deletion.
- Test sliders, accessible alternatives, Undo conflicts, Dynamic Type,
  VoiceOver, and navigation against the supplied mockup.
- Run required migration, backend contract, native, and affected public-consumer
  gates. Keep installation and release controls unchanged until separately
  authorized.

## Boundaries and defaults

The mockup guides the visual redesign. The approved insight-sheet menu changes
field-notes and collections presentation while preserving their existing flows.
Other main-scan layout changes and changes to whole-scan deletion behavior
remain outside this scope. Permanent version deletion has no Undo; review and
selection retain their existing conditional Undo behavior.

The first milestone is complete only when deletion and source export are
qualified across photo, audio, and video. The visual redesign follows those
capabilities.

## Recorded handoff and scope boundary

Status: approved future work, recorded October 11, 2026. History primary remains
the sole implementation writer. The current IC-1/S0 and alpha-readiness scope
takes precedence; external-only blockers remain explicitly open and do not
silently reorder these milestones. Broader initial-engine hardening remains
separately owned under IC-1. No push, deployment, activation, installation or
distribution is authorized.

The source is the human-approved plan in planning thread
`01a12460-a2c6-7b21-abcf-d3be41331b45`, handed to history thread
`01a0fe55-d9d3-77e0-90a5-b7eeeaaa74e1`. Requirements above are transcribed
without changing their scope. The visual reference is retained locally at
`.artifacts/identification-history-version-actions/reference.png`; it guides
presentation, not permissions or lifecycle semantics. A capability and evidence
matrix with concrete owners/pass conditions must precede implementation of each
milestone. Impact review belongs at the next safe checkpoint and must identify
required changes to descendant-safe provenance, shared-media retention,
publication authority, closed capabilities and exact historical native action
routing. No such implementation or qualification is claimed by recording this
plan.

## Current-scope reconciliation — October 12, 2026

The direct human decisions in
[Check current slice](codex://threads/01a12460-a2c6-7b21-abcf-d3be41331b45)
require media for new identification and reanalysis and include video reanalysis
now. They supersede only the older video-reanalysis exclusion here. The amended
[alpha roadmap](identification-history-alpha-readiness-2026-10-11.md) and
[IC-1](initial-completion-history-interface-2026-10-11.md) define current
admission, source, recovery and native acceptance. Supporting text remains
immutable private evidence; old text records/accepted recovery remain intact.
Local-only queued no-media work requires explicit media/remediation.

Deletion/download for photo/audio/video still follows current acceptance, then
the Identification/History/menu redesign. The separately staged capture UI
refactor is owned by
[Simplify capture tools](codex://threads/01a12c47-6f54-7500-bab9-679c2babf9a0)
and requires its own handoffs and fresh final approval. Functional media
admission/journey qualification in existing shells does not depend on that
visual refactor. No release controls change.

## November 13 — first presentation slice implemented locally

The authorized local implementation starts with the Insights menu and shared
Identification destination. Both the confidence badge and menu use the same
sheet, retain confidence content and existing review owners, and push the
existing History view inside that sheet. Prepared handoffs preserve exact scan,
engine generation, account and container ownership. No migration, backend
mutation, deployment or device update is part of this slice; automatic prompts
remain paused.

The existing export action is relabeled Download media; the approved source-only
all-media chooser is still pending. The new History card stack, individual
version deletion, shared Capture-toolbar reanalysis and successful-result
selection changes also remain pending. The existing History view is reused here
only to establish the agreed navigation. Debug compilation, independent
lifecycle review, 59 focused native checks and 14 UI scenarios have applicable
passing evidence across the initial run and targeted fixes. Two selector
failures and one real name-form handoff failure are retained with their fixes in
`.artifacts/insights-identification-redesign-20261113.md`. The final targeted
run passed all 18 selected checks without skips. This is local presentation
validation, not release or full redesign acceptance. Existing user simulators,
phone data and signed-in library were preserved; testing used an isolated
synthetic simulator.

## November 13 — History cards implemented and locally verified

The next authorized local slice replaces the interim list/full-preview route
with current-first cards, current review controls and compact older-card menus.
It reuses existing exact-version selection, review, reanalysis and community
owners. A bounded current-row fetch covers selections older than the first page.
Pending actions and account/revision invalidation retain existing protections.
Visible cards request version-specific thumbnails through the existing verified
private-photo resolver, serial reads and a bounded 160-pixel cache. Each row is
attempted once per page generation; missing media uses placeholders and no
current-cover substitution is permitted. Download, deletion, Capture staging and
successful-reanalysis selection policy remain separate. Independent review found
no remaining blocker in this slice. Scoped native checks and six UI scenarios
have passing evidence; the final targeted run passed 25 native tests and two UI
tests with no failures or skips. Retained failures, fixes, exact results and
unrun surfaces are recorded in `.artifacts/history-cards-redesign-20261113.md`.
No release or user-data mutation is claimed.
